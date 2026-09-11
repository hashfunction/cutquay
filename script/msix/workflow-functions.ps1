# Copyright 2026 Trieflow LLC. MIT. External installed-consumer qualification only.
function Get-WorkflowFileRecord([string]$Path) {
    $item=Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer -or $item.LinkType -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Workflow requires a regular non-link file.'}
    return [ordered]@{bytes=$item.Length;sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
function Assert-WorkflowDirectory([string]$Path) {
    $current=Get-Item -LiteralPath $Path -Force
    while($current){if(-not $current.PSIsContainer -or $current.LinkType -or ($current.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Linked/invalid workflow directory: $($current.FullName)"};$parent=$current.Parent;$current=if($parent){Get-Item -LiteralPath $parent.FullName -Force}else{$null}}
}
function Invoke-WorkflowNative([Collections.IDictionary]$State,[string]$Name,[string[]]$Arguments,[string]$Label) {
    $relative="resources/$Name.exe";$executable=Join-Path $State.installed.InstallLocation $relative
    $expected=Get-RecordPayloadEntry $State.record $relative
    $hash=Assert-FileMatchesRecord $executable $expected $Name
    # All media DLLs were part of the installed payload inventory; revalidate
    # their actual bytes immediately around this separate process operation.
    $mediaRows=@($State.record.payload.PSObject.Properties | Where-Object {$_.Name -match '^resources/(ffmpeg|ffprobe)\.exe$|^resources/(avcodec|avdevice|avfilter|avformat|avutil|swresample|swscale)-[0-9]+\.dll$'})
    foreach($row in $mediaRows){$null=Assert-FileMatchesRecord (Join-Path $State.installed.InstallLocation $row.Name) $row.Value $row.Name}
    $start=[Diagnostics.ProcessStartInfo]::new($executable);$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($arg in $Arguments){$start.ArgumentList.Add($arg)}
    $candidate=[Diagnostics.Process]::new();$candidate.StartInfo=$start
    try{if(-not $candidate.Start()){throw 'Media process did not start.'}}catch{$candidate.Dispose();throw}
    $State.mediaProcess=$candidate;$null=$candidate.Handle
    $stdout=$candidate.StandardOutput.ReadToEndAsync();$stderr=$candidate.StandardError.ReadToEndAsync()
    $actualPackage=Get-CutQuayProcessPackageName $candidate
    if($actualPackage -cne [string]$State.installed.PackageFullName){throw 'Workflow media lacks exact installed package identity.'}
    if((Get-CanonicalPath $candidate.MainModule.FileName) -ine (Get-CanonicalPath $executable)){throw 'Workflow media executable differs from installed path.'}
    if(-not $candidate.WaitForExit(60000)){throw "Workflow $Label timed out."}
    $out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
    $receipt=[ordered]@{program=$relative;executable_sha256=$hash;arguments=$Arguments;package_full_name=$actualPackage;exit_code=$candidate.ExitCode;stdout=$out;stderr=$err}
    try{Write-NewUtf8Json (Join-Path $State.output ($Label+'-native.json')) $receipt}catch{throw "Native workflow reporting failed: $($_.Exception.Message); command exit: $($candidate.ExitCode); stderr: $err"}
    if($candidate.ExitCode -ne 0){throw "Workflow $Label failed with $($candidate.ExitCode): $err"}
    foreach($row in $mediaRows){$null=Assert-FileMatchesRecord (Join-Path $State.installed.InstallLocation $row.Name) $row.Value $row.Name}
    $candidate.Dispose();$State.mediaProcess=$null
    return $receipt
}
function Test-WorkflowMedia([Collections.IDictionary]$State,[object]$Request) {
    if($Request.mode -cnotin @('generate','verify')){throw 'Unknown fixed workflow media mode.'}
    Assert-WorkflowDirectory $Request.work
    if((Get-CanonicalPath $Request.fixture) -cne (Get-CanonicalPath (Join-Path $Request.work 'source.mp4'))){throw 'Unexpected generated fixture path.'}
    if($Request.mode -ceq 'generate') {
        if(Test-Path -LiteralPath $Request.fixture){throw 'Generated fixture already exists; preserved.'}
        $args=@('-hide_banner','-loglevel','error','-nostdin','-n','-f','lavfi','-i','testsrc2=size=160x90:rate=25','-f','lavfi','-i','sine=frequency=440:sample_rate=48000','-t','8','-map','0:v:0','-map','1:a:0','-c:v','libx264','-preset','ultrafast','-pix_fmt','yuv420p','-g','25','-keyint_min','25','-sc_threshold','0','-c:a','aac','-b:a','96k',$Request.fixture)
        $null=Invoke-WorkflowNative $State 'ffmpeg' $args 'generate'
        return [ordered]@{generated=$true;input=(Get-WorkflowFileRecord $Request.fixture)}
    }
    if((Get-CanonicalPath ([IO.Path]::GetDirectoryName($Request.output))) -ine (Get-CanonicalPath $Request.work) -or (Get-CanonicalPath $Request.output) -ieq (Get-CanonicalPath $Request.fixture) -or [IO.Path]::GetExtension($Request.output) -ine '.mp4'){throw 'Output is not a separate owned media destination.'}
    $input=Get-WorkflowFileRecord $Request.fixture;$output=Get-WorkflowFileRecord $Request.output
    if($input.sha256 -cne $Request.inputSha256 -or $output.sha256 -cne $Request.outputSha256){throw 'Workflow input/output hash changed.'}
    $probe=Invoke-WorkflowNative $State 'ffprobe' @('-v','error','-show_streams','-show_format','-of','json',$Request.output) 'probe-output'
    $parsed=$probe.stdout | ConvertFrom-Json
    $video=@($parsed.streams|Where-Object codec_type -CEQ 'video');$audio=@($parsed.streams|Where-Object codec_type -CEQ 'audio')
    $duration=[double]::Parse([string]$parsed.format.duration,[Globalization.CultureInfo]::InvariantCulture)
    if(@($parsed.streams).Count -ne 2 -or $video.Count -ne 1 -or $audio.Count -ne 1 -or $video[0].codec_name -cne 'h264' -or $audio[0].codec_name -cne 'aac' -or $video[0].width -ne 160 -or $video[0].height -ne 90 -or -not [double]::IsFinite($duration) -or $duration -lt 2.85 -or $duration -gt 3.15){throw 'Output codecs/geometry/duration differ from requested three-second trim.'}
    $null=Invoke-WorkflowNative $State 'ffmpeg' @('-hide_banner','-loglevel','error','-nostdin','-xerror','-i',$Request.output,'-map','0:v:0','-map','0:a:0','-f','null','-') 'decode-output'
    if((Get-WorkflowFileRecord $Request.fixture).sha256 -cne $input.sha256 -or (Get-WorkflowFileRecord $Request.output).sha256 -cne $output.sha256){throw 'Media changed during independent probe/decode.'}
    return [ordered]@{decoded=$true;input=$input;output=$output;probe=$parsed}
}
function Get-WorkflowModules([Collections.IDictionary]$State) {
    Update-OwnedPackageProcesses $State
    $rows=[Collections.Generic.List[object]]::new();$root=Get-CanonicalPath $State.installed.InstallLocation
    foreach($process in @($State.ownedProcesses)) {
        if($process.HasExited){continue}
        foreach($module in @($process.Modules)) {
            $file=Get-CanonicalPath $module.FileName
            if(Test-PathInside $file $root){$relative=$file.Substring($root.Length).TrimStart('\','/').Replace('\','/');$hash=Assert-FileMatchesRecord $file (Get-RecordPayloadEntry $State.record $relative) $relative;$origin='package'}
            elseif(Test-PathInside $file $env:SystemRoot){$relative=$null;$hash=$null;$origin='windows'}
            else{throw "Workflow process loaded foreign module: $file"}
            $rows.Add([ordered]@{process_id=$process.Id;path=$file;relative_path=$relative;origin=$origin;sha256=$hash})
        }
    }
    if(-not @($rows|Where-Object relative_path -CEQ 'CutQuay.exe').Count){throw 'Workflow module snapshot lacks installed consumer executable.'}
    return @($rows)
}
function ConvertTo-WorkflowArgument([string]$Value) {
    # Owned generated paths contain no quote/control characters; reject instead
    # of inventing a lossy command-line representation.
    if($Value -match '["\r\n\x00]' -or $Value.EndsWith('\')){throw 'Unsupported qualification command-line argument.'}
    return '"'+$Value+'"'
}
function Assert-WorkflowListener([int]$Port,[int]$ProcessId) {
    $listeners=@(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop)
    if(-not $listeners.Count){throw 'No observed DevTools listener.'}
    foreach($listener in $listeners){if($listener.OwningProcess -ne $ProcessId -or $listener.LocalAddress -cnotin @('127.0.0.1','::1')){throw 'DevTools listener is not loopback-only and owned by the observed broker process.'}}
}
function Invoke-WorkflowUiSession([Collections.IDictionary]$State,[object]$Request) {
    $profile=Join-Path $State.temporary ('workflow-profile-'+$Request.phase)
    if(Test-Path -LiteralPath $profile){throw 'Workflow browser profile already exists.'}
    New-Item -ItemType Directory $profile | Out-Null
    $arguments=@('--remote-debugging-port=0','--remote-debugging-address=127.0.0.1',('--user-data-dir='+$profile),('--config-dir='+$Request.config),'--disable-networking')
    $argumentString=($arguments|ForEach-Object {ConvertTo-WorkflowArgument $_}) -join ' '
    $started=[DateTime]::UtcNow
    $processId=[CutQuayQualification.ActivationBroker]::Activate($State.aumid,$argumentString)
    $process=[Diagnostics.Process]::GetProcessById([int]$processId)
    try {
        $null=$process.Handle
        if($process.HasExited -or $process.StartTime.ToUniversalTime() -lt $started){throw 'Workflow broker did not create a fresh process.'}
        if((Get-CanonicalPath $process.MainModule.FileName) -ine (Get-CanonicalPath (Join-Path $State.installed.InstallLocation 'CutQuay.exe'))){throw 'Workflow broker executable is outside exact installed path.'}
        if((Get-CutQuayProcessPackageName $process) -cne [string]$State.installed.PackageFullName){throw 'Workflow broker package identity mismatch.'}
        $null=Assert-FileMatchesRecord $process.MainModule.FileName (Get-RecordPayloadEntry $State.record 'CutQuay.exe') 'Workflow consumer executable'
        $State.ownedProcesses.Add($process);$State.process=$process
    } catch {$process.Dispose();throw}
    $deadline=[DateTime]::UtcNow.AddSeconds(45)
    $activePort=Join-Path $profile 'DevToolsActivePort'
    $lines=@()
    do{
        Start-Sleep -Milliseconds 200;$process.Refresh()
        if($process.HasExited){throw 'Workflow consumer exited at startup.'}
        if(Test-Path -LiteralPath $activePort){$null=Get-WorkflowFileRecord $activePort;$lines=@(Get-Content -LiteralPath $activePort)}
    }until(($process.MainWindowHandle -ne 0 -and $lines.Count -eq 2) -or [DateTime]::UtcNow -ge $deadline)
    if($process.MainWindowHandle -eq 0 -or $process.MainWindowTitle -cne 'CutQuay'){throw 'Workflow consumer main window is missing or incorrect.'}
    if($lines.Count -ne 2 -or $lines[0] -notmatch '^\d{1,5}$' -or [int]$lines[0] -notin 1024..65535 -or $lines[1] -notmatch '^/devtools/browser/[A-Za-z0-9-]+$'){throw 'Malformed owned DevToolsActivePort file.'}
    $port=[int]$lines[0];Assert-WorkflowListener $port $process.Id
    $uiDirectory=Join-Path $State.output ('workflow-'+$Request.phase)
    if(Test-Path -LiteralPath $uiDirectory){throw 'Workflow UI evidence directory already exists.'}
    New-Item -ItemType Directory $uiDirectory | Out-Null
    $nativeWindow=Get-WindowQualification $process $uiDirectory
    if(-not $nativeWindow.screenshot_captured){throw 'Workflow native window screenshot failed.'}
    Write-NewUtf8Json (Join-Path $uiDirectory 'native-window.json') $nativeWindow
    $input=[ordered]@{phase=$Request.phase;fixture=$Request.fixture;output=$Request.output;config=$Request.config;recipeName=$Request.recipeName;inspection=$Request.inspection;evidence=$uiDirectory;processId=$process.Id;port=$port;endpoint=('ws://127.0.0.1:'+$port+$lines[1]);rendererPath=(Join-Path $State.installed.InstallLocation 'resources/app.asar/out/renderer/index.html');sourceCommit=$State.record.sourceCommit;packageFullName=$State.installed.PackageFullName}
    $inputPath=Join-Path $State.temporary ($Request.phase+'-ui-input.json');Write-NewUtf8Json $inputPath $input
    $driver=Join-Path $PSScriptRoot 'workflowUi.mjs'
    $node=@(Get-Command node -CommandType Application -ErrorAction Stop)[0].Source
    $start=[Diagnostics.ProcessStartInfo]::new($node);$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;$start.CreateNoWindow=$true
    $start.ArgumentList.Add($driver);$start.ArgumentList.Add($inputPath)
    $candidate=[Diagnostics.Process]::new();$candidate.StartInfo=$start
    try{if(-not $candidate.Start()){throw 'UI automation driver did not start.'}}catch{$candidate.Dispose();throw}
    $State.workflowDriver=$candidate;$null=$candidate.Handle
    $stdout=$candidate.StandardOutput.ReadToEndAsync();$stderr=$candidate.StandardError.ReadToEndAsync()
    if(-not $candidate.WaitForExit(240000)){throw 'UI automation driver timed out.'}
    $driverResult=[ordered]@{driver_sha256=(Get-FileHash $driver).Hash.ToLowerInvariant();node_sha256=(Get-FileHash $node).Hash.ToLowerInvariant();input_sha256=(Get-FileHash $inputPath).Hash.ToLowerInvariant();arguments=$arguments;exit_code=$candidate.ExitCode;stdout=$stdout.GetAwaiter().GetResult();stderr=$stderr.GetAwaiter().GetResult();broker_process_id=$process.Id;broker_start_ticks=$process.StartTime.ToUniversalTime().Ticks;package_full_name=$State.installed.PackageFullName;loopback_listener_verified=$true}
    try{Write-NewUtf8Json (Join-Path $uiDirectory 'driver.json') $driverResult}catch{throw "UI driver reporting failed: $($_.Exception.Message); driver exit: $($candidate.ExitCode); stderr: $($driverResult.stderr)"}
    if($candidate.ExitCode -ne 0){throw ('Consumer UI workflow failed: '+$driverResult.stderr)}
    $candidate.Dispose();$State.workflowDriver=$null
    $result=Get-Content -LiteralPath (Join-Path $uiDirectory ($Request.phase+'-ui-result.json')) -Raw | ConvertFrom-Json
    if(-not $result.passed -or $result.phase -cne $Request.phase -or $result.sourceCommit -cne $State.record.sourceCommit -or $result.brokerProcessId -ne $process.Id -or $result.packageFullName -cne $State.installed.PackageFullName){throw 'Consumer UI result does not bind this installed session.'}
    Assert-WorkflowListener $port $process.Id
    Write-NewUtf8Json (Join-Path $uiDirectory 'loaded-modules.json') @(Get-WorkflowModules $State)
    if(-not $process.CloseMainWindow() -or -not $process.WaitForExit(15000) -or $process.ExitCode -ne 0){throw 'Workflow consumer did not close normally.'}
    Wait-OwnedPackageExit $State
    return $result
}
function Invoke-InstalledExportWorkflow([Collections.IDictionary]$State) {
    $work=Join-Path $State.temporary 'workflow-media';$config=Join-Path $State.temporary 'workflow-config'
    foreach($directory in @($work,$config)){if(Test-Path -LiteralPath $directory){throw 'Workflow work/config directory already exists.'};New-Item -ItemType Directory $directory | Out-Null;Assert-WorkflowDirectory $directory}
    $fixture=Join-Path $work 'source.mp4';$name='Original CI three-second trim'
    $generate=[pscustomobject]@{mode='generate';work=$work;fixture=$fixture;output=$null;inputSha256=$null;outputSha256=$null}
    $generated=@(Invoke-InstalledMediaInPackage -State $State -Workflow $generate)
    if($generated.Count -ne 1 -or -not $generated[0].generated){throw 'Installed media fixture generation did not pass.'}
    $State.workflowEvidence=[ordered]@{source_commit=$State.record.sourceCommit;input=$generated[0].input;generation_worker=$State.mediaWorkerEvidence;export_ui=$null;verification_worker=$null;media=$null;reopen_ui=$null;passed=$false}
    $request=[pscustomobject]@{phase='export';fixture=$fixture;output=$null;config=$config;recipeName=$name;inspection=$null}
    $export=Invoke-WorkflowUiSession $State $request;$State.workflowEvidence.export_ui=$export
    $verify=[pscustomobject]@{mode='verify';work=$work;fixture=$fixture;output=$export.output;inputSha256=$generated[0].input.sha256;outputSha256=$export.outputHash.sha256}
    $verified=@(Invoke-InstalledMediaInPackage -State $State -Workflow $verify)
    if($verified.Count -ne 1 -or -not $verified[0].decoded){throw 'Actual installed FFprobe/decode verification did not pass.'}
    $State.workflowEvidence.verification_worker=$State.mediaWorkerEvidence;$State.workflowEvidence.media=$verified[0]
    $request.phase='reopen';$request.output=$export.output;$request.inspection=$verified[0].probe
    $reopen=Invoke-WorkflowUiSession $State $request;$State.workflowEvidence.reopen_ui=$reopen
    if((Get-WorkflowFileRecord $fixture).sha256 -cne $generated[0].input.sha256 -or (Get-WorkflowFileRecord $export.output).sha256 -cne $export.outputHash.sha256){throw 'Final workflow input/output integrity failed.'}
    $State.workflowEvidence.passed=$true
    Write-NewUtf8Json (Join-Path $State.output 'consumer-workflow.json') $State.workflowEvidence
}
