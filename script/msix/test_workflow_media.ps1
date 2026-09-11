# Real fixed-command media checks, using owned native binaries. No Windows UI claim.
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$root=Join-Path $(if($IsWindows){[IO.Path]::GetTempPath()}else{'/private/tmp'}) ('cut-workflow-media-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory (Join-Path $root 'resources') | Out-Null
New-Item -ItemType Directory (Join-Path $root 'media') | Out-Null
New-Item -ItemType Directory (Join-Path $root 'evidence') | Out-Null
try {
    if($IsWindows){ Get-ChildItem (Join-Path $PSScriptRoot '../../ffmpeg/win32-x64/lib') -File | ForEach-Object {[IO.File]::Copy($_.FullName,(Join-Path $root ('resources/'+$_.Name)),$false)} }
    else { foreach($name in @('ffmpeg','ffprobe')){ $source=@(Get-Command $name -CommandType Application)[0].Source; $target=Join-Path $root "resources/$name.exe";[IO.File]::Copy($source,$target,$false);& chmod +x $target;if($LASTEXITCODE){throw 'chmod failed'} } }
    $payload=[ordered]@{};foreach($file in Get-ChildItem (Join-Path $root 'resources') -File){$payload['resources/'+$file.Name]=[pscustomobject]@{bytes=$file.Length;sha256=(Get-FileHash $file.FullName).Hash.ToLowerInvariant()}}
    $state=[ordered]@{installed=[pscustomobject]@{InstallLocation=$root;PackageFullName='fixture-package'};record=[pscustomobject]@{payload=[pscustomobject]$payload};output=(Join-Path $root 'evidence');mediaProcess=$null}
    $script:endedBeforeImageQuery=0
    $script:fixturePackage='fixture-package'
    function Get-CutQuayProcessPackageName($Process){
        # Deterministically reproduce the observed short-process race: the
        # original process is terminated before production inspects its image.
        if(-not $Process.WaitForExit(30000)){throw 'Native lifetime fixture did not finish.'}
        $script:endedBeforeImageQuery++
        return $script:fixturePackage
    }
    if(-not $IsWindows){
        # Windows' retained-handle image query is unavailable on macOS. This
        # adapter does not claim OS identity verification; Windows runs the real API.
        function Get-CutQuayProcessImageName($Process){return $Process.StartInfo.FileName}
    }
    $request=[pscustomobject]@{mode='generate';work=(Join-Path $root 'media');fixture=(Join-Path $root 'media/source.mp4');output=$null;inputSha256=$null;outputSha256=$null}
    $generated=Test-WorkflowMedia $state $request
    if(-not $generated.generated -or $generated.input.bytes -le 0){throw 'Actual fixture was not generated'}
    $sentinel=(Get-FileHash $request.fixture).Hash
    $failed=$false;try{Test-WorkflowMedia $state $request | Out-Null}catch{$failed=$true}
    if(-not $failed -or (Get-FileHash $request.fixture).Hash -cne $sentinel){throw 'Existing generated source was overwritten'}
    $request.mode='verify';$request.output=Join-Path $root 'media/trim.mp4';$request.inputSha256=$generated.input.sha256
    & (Join-Path $root 'resources/ffmpeg.exe') -hide_banner -loglevel error -n -ss 2 -i $request.fixture -t 3 -map 0 -c copy $request.output
    if($LASTEXITCODE){throw 'Local output fixture creation failed'}
    $request.outputSha256=(Get-FileHash $request.output).Hash.ToLowerInvariant()
    $verified=Test-WorkflowMedia $state $request
    if(-not $verified.decoded -or $verified.probe.streams.Count -ne 2){throw 'Real output probe/decode not observed'}
    if($script:endedBeforeImageQuery -ne 3){throw 'All three native commands must exit before their image query.'}
    $native=Get-Content (Join-Path $state.output 'probe-output-native.json') -Raw | ConvertFrom-Json
    if((Get-CanonicalPath $native.process_image_path) -ine (Get-CanonicalPath (Join-Path $root 'resources/ffprobe.exe'))){throw 'Observed native image path was not retained in evidence.'}
    $request.outputSha256='0'*64;$failed=$false;try{Test-WorkflowMedia $state $request | Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'Changed output hash accepted'}
    $request.outputSha256=(Get-FileHash $request.output).Hash.ToLowerInvariant();$request.output=$request.fixture;$failed=$false;try{Test-WorkflowMedia $state $request | Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'Source accepted as exported destination'}
    $imageQuery=${function:Get-CutQuayProcessImageName}
    foreach($case in @('wrong-package','wrong-image','query-error')){
        try{
            $script:fixturePackage=if($case -eq 'wrong-package'){'other-package'}else{'fixture-package'}
            if($case -eq 'wrong-image'){function Get-CutQuayProcessImageName($Process){return (Join-Path $root 'foreign.exe')}}
            if($case -eq 'query-error'){function Get-CutQuayProcessImageName($Process){throw 'native image query failed'}}
            $failure=$null
            try{Invoke-WorkflowNative $state 'ffprobe' @('-version') $case | Out-Null}catch{$failure=$_.Exception.Message}
            $expected=@{'wrong-package'='exact installed package identity';'wrong-image'='differs from installed path';'query-error'='native image query failed'}[$case]
            if(-not $failure -or $failure -notmatch $expected -or (Test-Path (Join-Path $state.output ($case+'-native.json')))){throw "Identity failure was accepted or lost: $case / $failure"}
        } finally {
            Set-Item Function:Get-CutQuayProcessImageName $imageQuery
            if($state.mediaProcess){if(-not $state.mediaProcess.HasExited){$state.mediaProcess.Kill();$null=$state.mediaProcess.WaitForExit(10000)};$state.mediaProcess.Dispose();$state.mediaProcess=$null}
        }
    }
    Add-CutQuayActivationTypes
    $invalid=[Microsoft.Win32.SafeHandles.SafeProcessHandle]::new([IntPtr]::Zero,$false)
    try{
        $failure=$null
        try{[CutQuayQualification.NativePackageProbe]::GetImageName($invalid)|Out-Null}catch{$failure=$_.Exception.Message}
        if($failure -notmatch 'retained process handle'){throw "Invalid handle was not rejected: $failure"}
    }finally{$invalid.Dispose()}
    'PASS: real native generate/probe/decode with forced exit before image query, identity failures, invalid handle, preserved inputs and output hash/alias checks.'
    if($IsWindows){'PASS: actual Windows QueryFullProcessImageNameW observed each terminated native process through its original retained handle.'}
    else{'LIMIT: Windows package/image APIs are adapters on macOS; no Windows identity or installed UI claim.'}
} finally { if(Get-Variable state -ErrorAction SilentlyContinue){if($state.mediaProcess -and -not $state.mediaProcess.HasExited){$state.mediaProcess.Kill();$null=$state.mediaProcess.WaitForExit(10000)}};Remove-Item $root -Recurse -Force }
