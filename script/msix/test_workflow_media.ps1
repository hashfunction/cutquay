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
    function Get-CutQuayProcessPackageName($Process){ return 'fixture-package' } # only unavailable OS identity adapter
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
    $request.outputSha256='0'*64;$failed=$false;try{Test-WorkflowMedia $state $request | Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'Changed output hash accepted'}
    $request.outputSha256=(Get-FileHash $request.output).Hash.ToLowerInvariant();$request.output=$request.fixture;$failed=$false;try{Test-WorkflowMedia $state $request | Out-Null}catch{$failed=$true}
    if(-not $failed){throw 'Source accepted as exported destination'}
    'PASS: real generated H.264/AAC, preserved existing input, real output probe/decode, changed output and source alias rejected.'
} finally { if(Get-Variable state -ErrorAction SilentlyContinue){if($state.mediaProcess -and -not $state.mediaProcess.HasExited){$state.mediaProcess.Kill();$null=$state.mediaProcess.WaitForExit(10000)}};Remove-Item $root -Recurse -Force }
