# Copyright 2026 Trieflow LLC. MIT. Screenshot-only lifecycle helpers.
. (Join-Path $PSScriptRoot '../msix/qualify-msix-install.ps1') -LibraryOnly

function Get-MarketingWindowPlan($WorkArea){
    if($WorkArea.Width -lt 1472 -or $WorkArea.Height -lt 1000){throw 'Actual display is too small for readable marketing screenshots.'}
    return @{x=[int]($WorkArea.X+($WorkArea.Width-1472)/2);y=[int]($WorkArea.Y+($WorkArea.Height-1000)/2);width=1472;height=1000}
}

function Add-MarketingWindowTypes {
    if('CutQuayMarketing.Desktop' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CutQuayMarketing {
 public static class Desktop {
  [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int state);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT rect);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 }
}
'@
}

function Assert-MarketingProcess($State){
    $process=$State.process
    if(-not $process -or $process.SafeHandle.IsClosed -or $process.SafeHandle.IsInvalid -or $process.HasExited){throw 'Retained screenshot consumer is unavailable.'}
    if((Get-CutQuayProcessPackageName $process) -cne $State.ownedPackageFullName -or
        (Get-CanonicalPath (Get-CutQuayProcessImageName $process)) -ine (Get-CanonicalPath (Join-Path $State.installed.InstallLocation 'CutQuay.exe'))){throw 'Retained screenshot consumer identity differs.'}
    $null=Assert-FileMatchesRecord (Join-Path $State.installed.InstallLocation 'CutQuay.exe') (Get-RecordPayloadEntry $State.record 'CutQuay.exe') 'Screenshot consumer'
}

function Set-MarketingWindow($State){
    Add-MarketingWindowTypes
    $null=[CutQuayMarketing.Desktop]::SetThreadDpiAwarenessContext([IntPtr](-4))
    Add-Type -AssemblyName System.Windows.Forms
    Assert-MarketingProcess $State
    $screen=[Windows.Forms.Screen]::PrimaryScreen;$area=$screen.WorkingArea
    $plan=Get-MarketingWindowPlan $area
    $handle=$State.process.MainWindowHandle
    $null=[CutQuayMarketing.Desktop]::ShowWindow($handle,9)
    if(-not [CutQuayMarketing.Desktop]::SetWindowPos($handle,[IntPtr]::Zero,$plan.x,$plan.y,$plan.width,$plan.height,0x0040)){throw 'Could not resize the actual app window.'}
    $null=[CutQuayMarketing.Desktop]::SetForegroundWindow($handle)
    Start-Sleep -Milliseconds 500
    return Assert-MarketingWindow $State
}

function Assert-MarketingWindow($State){
    Assert-MarketingProcess $State;$handle=$State.process.MainWindowHandle
    if([CutQuayMarketing.Desktop]::GetForegroundWindow() -ne $handle){throw 'Exact consumer is not the foreground native window.'}
    $rect=[CutQuayMarketing.Desktop+RECT]::new()
    if(-not [CutQuayMarketing.Desktop]::GetWindowRect($handle,[ref]$rect)){throw 'Actual native window bounds are unavailable.'}
    $screen=[Windows.Forms.Screen]::FromHandle($handle);$area=$screen.WorkingArea;$dpi=[CutQuayMarketing.Desktop]::GetDpiForWindow($handle)
    if($dpi -ne 96 -or $rect.Left -lt $area.Left -or $rect.Top -lt $area.Top -or $rect.Right -gt $area.Right -or $rect.Bottom -gt $area.Bottom -or
        $rect.Right-$rect.Left -lt 1472 -or $rect.Bottom-$rect.Top -lt 1000){throw 'Actual display scale/window bounds cannot support an unclipped capture.'}
    return [ordered]@{device=$screen.DeviceName;dpi=$dpi;display=@{x=$screen.Bounds.X;y=$screen.Bounds.Y;width=$screen.Bounds.Width;height=$screen.Bounds.Height};
        work_area=@{x=$area.X;y=$area.Y;width=$area.Width;height=$area.Height};window=@{x=$rect.Left;y=$rect.Top;width=($rect.Right-$rect.Left);height=($rect.Bottom-$rect.Top)};
        process_id=$State.process.Id;foreground_verified=$true;device_emulation_used=$false}
}

function Complete-MarketingCleanup($State){
    $operations=[ordered]@{
        processes={
            $errors=[Collections.Generic.List[string]]::new()
            if($State.installed){try{Update-OwnedPackageProcesses $State}catch{$errors.Add($_.Exception.Message)}}
            foreach($process in @($State.workflowDriver,$State.mediaProcess)+@($State.ownedProcesses)){
                if(-not $process){continue}
                try{if(-not $process.HasExited){$process.Kill();if(-not $process.WaitForExit(10000)){throw 'Retained owned process remains.'}}}catch{$errors.Add($_.Exception.Message)}
            }
            if($errors.Count){throw ($errors -join '; ')}
        }
        package={
            if($State.installAttempted){
                $remaining=@(Get-AppxPackage -Name '1659hashfunction.CutQuay' -ErrorAction Stop)
                if($State.installedByUs -and $State.ownedPackageFullName){
                    $owned=@($remaining|Where-Object PackageFullName -CEQ $State.ownedPackageFullName)
                    if($owned.Count -gt 1){throw 'Ambiguous registration preserved.'}
                    if($owned.Count -eq 1){Remove-AppxPackage -Package $State.ownedPackageFullName -ErrorAction Stop}
                }
                $State.residualPackageFullNames=@(Get-AppxPackage -Name '1659hashfunction.CutQuay' -ErrorAction Stop|ForEach-Object PackageFullName)
                if($State.residualPackageFullNames.Count){throw 'Unowned or unresolved registration preserved.'}
            }
        }
        trusted_certificate={if($State.trustAttempted -and $State.certificate){$path='Cert:\LocalMachine\TrustedPeople\'+$State.certificate.Thumbprint;if(Test-Path $path){Remove-Item -LiteralPath $path -Force};if(Test-Path $path){throw 'Owned trusted certificate remains.'}}}
        personal_certificate={if($State.certificate){$path='Cert:\CurrentUser\My\'+$State.certificate.Thumbprint;if(Test-Path $path){Remove-Item -LiteralPath $path -Force};if(Test-Path $path){throw 'Owned personal certificate remains.'}}}
        temporary={if($State.temporary -and (Test-Path $State.temporary)){Assert-WorkflowDirectory $State.temporary;Remove-Item -LiteralPath $State.temporary -Recurse -Force;if(Test-Path $State.temporary){throw 'Owned temporary files remain.'}}}
        demo_files={if($State.workOwned -and (Test-Path $State.work)){Assert-WorkflowDirectory $State.work;Remove-Item -LiteralPath $State.work -Recurse -Force;if(Test-Path $State.work){throw 'Owned demo files remain.'}}}
    }
    foreach($name in $operations.Keys){try{& $operations[$name]}catch{$State.cleanupErrors.Add(($name+': '+$_.Exception.Message).Substring(0,[Math]::Min(2048,($name+': '+$_.Exception.Message).Length)))}}
}

function Copy-MarketingMediaTool([string]$Source,[string]$Destination,$Expected){
    $null=Assert-FileMatchesRecord $Source $Expected 'Installed standalone media tool source'
    [IO.File]::Copy($Source,$Destination,$false)
    $null=Assert-FileMatchesRecord $Destination $Expected 'Standalone media tool copy'
    $null=Assert-FileMatchesRecord $Source $Expected 'Installed media tool source after copy'
    return $Destination
}

function Invoke-MarketingMedia($State,[string]$Media,[string]$Phase){
    $results=[ordered]@{}
    $toolDirectory=Join-Path $State.temporary "$Phase-media-tools"
    New-Item -ItemType Directory $toolDirectory | Out-Null
    # The fixed qualified package uses shared FFmpeg, not standalone static EXEs.
    # Preserve its exact adjacent DLL closure in the owned diagnostic copy.
    foreach($library in @('avcodec-62.dll','avdevice-62.dll','avfilter-11.dll','avformat-62.dll','avutil-60.dll','swresample-6.dll','swscale-9.dll')){
        $null=Copy-MarketingMediaTool (Join-Path $State.installed.InstallLocation "resources/$library") (Join-Path $toolDirectory $library) (Get-RecordPayloadEntry $State.record "resources/$library")
    }
    foreach($kind in @('probe','decode')){
        $name=if($kind -ceq 'probe'){'ffprobe'}else{'ffmpeg'}
        $installedProgram=Join-Path $State.installed.InstallLocation "resources/$name.exe"
        $expected=Get-RecordPayloadEntry $State.record "resources/$name.exe"
        # WindowsApps disallows external direct process launch. This already
        # standalone media check runs an exact owned copy, never changing ACLs.
        $program=Copy-MarketingMediaTool $installedProgram (Join-Path $toolDirectory "$name.exe") $expected
        $programHash=Assert-FileMatchesRecord $program $expected 'Screenshot media tool'
        $arguments=if($kind -ceq 'probe'){@('-v','error','-show_streams','-show_format','-of','json',$Media)}else{@('-hide_banner','-loglevel','error','-nostdin','-xerror','-i',$Media,'-map','0:v:0','-map','0:a:0','-f','null','-')}
        $info=[Diagnostics.ProcessStartInfo]::new($program);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        foreach($arg in $arguments){$info.ArgumentList.Add($arg)}
        $process=[Diagnostics.Process]::Start($info);$null=$process.Handle;$State.mediaProcess=$process
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(60000)){throw 'Screenshot media observation exceeded its deadline.'}
        $out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
        if($out.Length -gt 1048576 -or $err.Length -gt 65536){throw 'Screenshot media output exceeds bound.'}
        $result=[ordered]@{purpose='standalone media observation only; no package-context or qualification claim';executable=$program;executable_sha256=$programHash;
            arguments=$arguments;process_id=$process.Id;exit_code=$process.ExitCode;stdout=$out;stderr=$err;input=(Get-WorkflowFileRecord $Media);installed_source=$installedProgram;standalone_copy_verified=$true}
        Write-NewUtf8Json (Join-Path $State.output "$Phase-$kind.json") $result
        if($process.ExitCode -ne 0){throw "Actual screenshot media $kind failed: $err"}
        $null=Assert-FileMatchesRecord $program (Get-RecordPayloadEntry $State.record "resources/$name.exe") 'Screenshot media tool'
        $results[$kind]=$result;$process.Dispose();$State.mediaProcess=$null
    }
    $probe=$results.probe.stdout|ConvertFrom-Json
    $video=@($probe.streams|Where-Object codec_type -CEQ 'video');$audio=@($probe.streams|Where-Object codec_type -CEQ 'audio')
    if($video.Count -ne 1 -or $audio.Count -ne 1 -or $video[0].codec_name -cne 'vp9' -or $audio[0].codec_name -cne 'opus' -or $video[0].width -ne 2048 -or $video[0].height -ne 858){throw 'Actual demo media differs from selected licensed footage.'}
    return [double]$probe.format.duration
}

function Invoke-MarketingUi($State,[string]$Phase,[string]$Media,[double]$Duration){
    $profile=Join-Path $State.temporary ('profile-'+$Phase);New-Item -ItemType Directory $profile | Out-Null
    $directory=Join-Path $State.output $Phase;New-Item -ItemType Directory $directory | Out-Null
    $arguments=@('--remote-debugging-port=0','--remote-debugging-address=127.0.0.1',('--user-data-dir='+$profile),('--config-dir='+$State.config),'--disable-networking')
    $started=[DateTime]::UtcNow
    $processId=[CutQuayQualification.ActivationBroker]::Activate($State.aumid,(($arguments|ForEach-Object {ConvertTo-WorkflowArgument $_}) -join ' '))
    $process=[Diagnostics.Process]::GetProcessById([int]$processId);$null=$process.Handle
    try{
        if($process.HasExited -or $process.StartTime.ToUniversalTime() -lt $started){throw 'Screenshot broker did not create a fresh process.'}
        $State.process=$process;Assert-MarketingProcess $State;$State.ownedProcesses.Add($process)
    }catch{$process.Dispose();$State.process=$null;throw}
    $deadline=[DateTime]::UtcNow.AddSeconds(45);$lines=@()
    do{
        Start-Sleep -Milliseconds 200;$process.Refresh();if($process.HasExited){throw 'Screenshot consumer exited at startup.'}
        $portPath=Join-Path $profile 'DevToolsActivePort'
        if(Test-Path $portPath){$null=Get-WorkflowFileRecord $portPath;$lines=@(Get-Content $portPath)}
    }until(($process.MainWindowHandle -ne 0 -and $lines.Count -eq 2) -or [DateTime]::UtcNow -ge $deadline)
    if($process.MainWindowHandle -eq 0 -or $process.MainWindowTitle -cne 'CutQuay' -or $lines.Count -ne 2 -or $lines[0] -notmatch '^\d{1,5}$' -or [int]$lines[0] -notin 1024..65535 -or $lines[1] -notmatch '^/devtools/browser/[A-Za-z0-9-]+$'){throw 'Actual screenshot window/listener did not become ready.'}
    $port=[int]$lines[0];Assert-WorkflowListener $port $process.Id
    Write-NewUtf8Json (Join-Path $directory 'display.json') (Set-MarketingWindow $State)
    $nonce=[guid]::NewGuid().ToString('N')
    $input=[ordered]@{phase=$Phase;media=$Media;mediaHash=(Get-WorkflowFileRecord $Media).sha256;duration=$Duration;config=$State.config;evidence=$directory;nonce=$nonce;
        processId=$process.Id;port=$port;endpoint=('ws://127.0.0.1:'+$port+$lines[1]);rendererPath=(Join-Path $State.installed.InstallLocation 'resources/app.asar/out/renderer/index.html');
        captureSource=$env:GITHUB_SHA;packageSource=$State.record.sourceCommit;packageFullName=$State.ownedPackageFullName}
    $inputPath=Join-Path $State.temporary ($Phase+'-ui.json');Write-NewUtf8Json $inputPath $input
    $node=@(Get-Command node -CommandType Application)[0].Source;$driver=Join-Path $PSScriptRoot 'captureUi.mjs'
    $info=[Diagnostics.ProcessStartInfo]::new($node);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @($driver,$inputPath,(Get-FileHash $inputPath).Hash.ToLowerInvariant())){$info.ArgumentList.Add($arg)}
    $candidate=[Diagnostics.Process]::Start($info);$null=$candidate.Handle;$State.workflowDriver=$candidate
    $stdout=$candidate.StandardOutput.ReadToEndAsync();$stderr=$candidate.StandardError.ReadToEndAsync();$done=@{}
    $deadline=[DateTime]::UtcNow.AddSeconds(240)
    do{
        foreach($scene in @('01-trim-timeline','02-export-recipe','03-export-reopened')){
            $requestPath=Join-Path $directory ($scene+'-native-request.json')
            if(-not $done.ContainsKey($scene) -and (Test-Path (Join-Path $directory ($scene+'-native-request.ready')))){
                $request=Get-Content $requestPath -Raw|ConvertFrom-Json
                if($request.nonce -cne $nonce -or $request.process_id -ne $process.Id -or $request.name -cne $scene){throw 'Native capture request does not bind this session.'}
                $bounds=Assert-MarketingWindow $State
                $native=Join-Path $directory $scene;New-Item -ItemType Directory $native | Out-Null
                $window=Get-WindowQualification $process $native
                if(-not $window.screenshot_captured){throw 'Actual native screenshot failed.'}
                Write-NewUtf8Json (Join-Path $native 'native-window.json') @{bounds=$bounds;window=$window;png=(Get-WorkflowFileRecord (Join-Path $native 'qualification-window.png'))}
                Write-NewUtf8Json (Join-Path $directory ($scene+'-native-complete.json')) @{nonce=$nonce;process_id=$process.Id;name=$scene}
                $marker=[IO.File]::Open((Join-Path $directory ($scene+'-native-complete.ready')),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$marker.Dispose()
                $done[$scene]=$true
            }
        }
        if(-not $candidate.HasExited){Start-Sleep -Milliseconds 100}
    }until($candidate.HasExited -or [DateTime]::UtcNow -ge $deadline)
    if(-not $candidate.HasExited){throw 'Screenshot UI input driver exceeded its deadline.'}
    $out=$stdout.GetAwaiter().GetResult();$err=$stderr.GetAwaiter().GetResult()
    Write-NewUtf8Json (Join-Path $directory 'driver.json') @{driver_sha256=(Get-FileHash $driver).Hash.ToLowerInvariant();node_sha256=(Get-FileHash $node).Hash.ToLowerInvariant();input_sha256=(Get-FileHash $inputPath).Hash.ToLowerInvariant();arguments=$arguments;process_id=$process.Id;start_ticks=$process.StartTime.ToUniversalTime().Ticks;exit_code=$candidate.ExitCode;stdout=$out;stderr=$err}
    if($candidate.ExitCode -ne 0){throw ('Actual screenshot workflow failed: '+$err)}
    $candidate.Dispose();$State.workflowDriver=$null
    $result=Get-Content (Join-Path $directory 'ui-result.json') -Raw|ConvertFrom-Json
    if($result.captured -ne $true -or $result.consumer_acceptance -ne $false -or $result.nonce -cne $nonce -or $result.process_id -ne $process.Id -or $result.package_full_name -cne $State.ownedPackageFullName -or $result.qualified_source_commit -cne $State.record.sourceCommit -or $result.capture_source_commit -cne $env:GITHUB_SHA){throw 'Screenshot result identity differs.'}
    Assert-WorkflowListener $port $process.Id;Assert-MarketingProcess $State
    Write-NewUtf8Json (Join-Path $directory 'loaded-modules.json') @(Get-WorkflowModules $State)
    if(-not $process.CloseMainWindow() -or -not $process.WaitForExit(15000) -or $process.ExitCode -ne 0){throw 'Screenshot consumer did not close normally.'}
    Wait-OwnedPackageExit $State
    return $result
}
