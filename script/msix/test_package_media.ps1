# Copyright 2026 Trieflow LLC. MIT. Real worker/pipe-free handshake tests. Only the
# Windows package launcher and GetPackageFullName API are substituted on macOS.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$script:helper = Join-Path $PSScriptRoot 'qualify-msix-install.ps1'
$script:runner = (Get-Process -Id $PID).Path
$script:child = $null
$script:scenario = 'success'
function Get-CutQuayProcessPackageName([Diagnostics.Process]$Process) {
    if ($script:scenario -eq 'wrong-parent-identity') { return 'Foreign.Package' }
    return 'Fixture.Package'
}
function Invoke-CommandInDesktopPackage {
    [CmdletBinding()] param([string]$PackageFamilyName, [string]$AppId, [string]$Command, [string]$Args, [switch]$PreventBreakaway)
    if ($PackageFamilyName -cne 'Fixture.Family' -or $AppId -cne 'CutQuay' -or $Command -cne $script:runner -or -not $PreventBreakaway) { throw 'Package launch identity/context changed.' }
    if ($script:scenario -eq 'wrong-parent-executable') {
        $info=[Diagnostics.ProcessStartInfo]::new((Get-Command python -CommandType Application).Source)
        $info.UseShellExecute=$false
        foreach ($argument in @('-c','import time; time.sleep(30)')) { $info.ArgumentList.Add($argument) }
        $script:child=[Diagnostics.Process]::Start($info); $null=$script:child.Handle
        $inputPath=Join-Path $state.temporary 'media-worker-input.json'
        $request=Get-Content $inputPath -Raw | ConvertFrom-Json
        Write-WorkerJson (Join-Path $state.output 'media-worker-ready.json') ([ordered]@{
            nonce=$request.nonce;process_id=$script:child.Id;start_ticks=$script:child.StartTime.ToUniversalTime().Ticks
            package_full_name='Fixture.Package';input_sha256=(Get-FileHash $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
        })
        return
    }
    $body = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($Args -split ' ')[-1]))
    # Preserve the actual library import and worker invocation. Substitute only
    # the Windows identity API and test's media operation inside the real child.
    $injection = @'
function Get-CutQuayProcessPackageName { return 'Fixture.Package' }
function Test-InstalledMedia { return @(1..4 | ForEach-Object { [ordered]@{exit_code=0;configuration_verified=$true} }) }
'@
    if ($script:scenario -eq 'native-media') { $injection = "function Get-CutQuayProcessPackageName { return 'Fixture.Package' }" }
    if ($script:scenario -eq 'worker-cleanup-error') { $injection += @'
function Test-InstalledMedia([Collections.IDictionary]$State) {
    $State.mediaProcess=[pscustomobject]@{HasExited=$false}
    $State.mediaProcess | Add-Member ScriptMethod Kill { throw 'fixture media cleanup failed' }
    throw 'fixture media operation failed'
}
'@ }
    if ($script:scenario -eq 'worker-error') { $injection += "`nfunction Test-InstalledMedia { throw 'fixture media operation failed' }`n" }
    if ($script:scenario -eq 'worker-timeout') { $injection += "`nfunction Test-InstalledMedia { Start-Sleep -Seconds 30 }`n" }
    $body = $body.Replace('Invoke-CutQuayMediaWorker -InputPath', $injection + "`nInvoke-CutQuayMediaWorker -InputPath")
    $info = [Diagnostics.ProcessStartInfo]::new($Command)
    $info.UseShellExecute=$false
    foreach ($argument in @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body)))) { $info.ArgumentList.Add($argument) }
    $script:child=[Diagnostics.Process]::Start($info)
    $null=$script:child.Handle
}
foreach ($script:scenario in @('success','native-media','worker-error','worker-cleanup-error','wrong-parent-identity','wrong-parent-executable','worker-timeout')) {
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('cutquay-worker-test-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $temporary | Out-Null
    $state=[ordered]@{
        installed=[pscustomobject]@{PackageFullName='Fixture.Package';PackageFamilyName='Fixture.Family';InstallLocation=$temporary}
        temporary=$temporary;output=$temporary;record=[pscustomobject]@{};mediaWorkerProcess=$null;mediaWorkerEvidence=$null
    }
    if ($script:scenario -eq 'native-media') {
        New-Item -ItemType Directory (Join-Path $temporary 'resources') | Out-Null
        if ($IsWindows) {
            foreach ($file in Get-ChildItem (Join-Path $PSScriptRoot '../../ffmpeg/win32-x64/lib') -File) { [IO.File]::Copy($file.FullName, (Join-Path $temporary "resources/$($file.Name)"), $false) }
        } else {
            foreach ($name in @('ffmpeg','ffprobe')) {
                $target=Join-Path $temporary "resources/$name.exe"
                [IO.File]::Copy((Get-Command $name -CommandType Application).Source, $target, $false)
                & chmod +x $target
                if ($LASTEXITCODE) { throw 'Could not prepare native media fixture.' }
            }
        }
        $nativeText=(& (Join-Path $temporary 'resources/ffmpeg.exe') -version 2>&1) -join "`n"
        if ($LASTEXITCODE -or $nativeText -notmatch 'ffmpeg version ([^ ]+)') { throw 'Native FFmpeg version unavailable.' }
        $version=$Matches[1]
        if ($nativeText -notmatch '(?m)^configuration: (.+)$') { throw 'Native FFmpeg configuration unavailable.' }
        $configuration=$Matches[1].TrimEnd("`r")
        $payload=[ordered]@{}
        foreach ($name in @('ffmpeg','ffprobe')) {
            $relative="resources/$name.exe"; $path=Join-Path $temporary $relative
            $payload[$relative]=[pscustomobject]@{bytes=(Get-Item $path).Length;sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
        $state.record=[pscustomobject]@{payload=[pscustomobject]$payload;runtime=[pscustomobject]@{media=[pscustomobject]@{version=$version;configuration=$configuration}}}
    }
    try {
        $failure=$null; $results=@()
        try { $timeout=if ($script:scenario -eq 'worker-timeout') { 2 } else { 30 }; $results=@(Invoke-InstalledMediaInPackage $state -TimeoutSeconds $timeout) } catch { $failure=$_.Exception.Message }
        if ($script:scenario -in @('success','native-media')) {
            if ($failure -or $results.Count -ne 4 -or -not $state.mediaWorkerEvidence.clean_exit_verified -or $state.mediaWorkerEvidence.exit_code -ne 0) { throw "Worker success failed: $failure" }
        } elseif ($script:scenario -in @('worker-error','worker-cleanup-error')) {
            if ($failure -notmatch 'fixture media operation failed' -or -not $state.mediaWorkerProcess.HasExited) { throw "Worker failure was lost: $failure" }
            if ($script:scenario -eq 'worker-cleanup-error' -and $failure -notmatch 'fixture media cleanup failed') { throw 'Worker cleanup error was lost' }
        } elseif ($script:scenario -in @('wrong-parent-identity','wrong-parent-executable')) {
            if ($failure -notmatch 'package identity|exact diagnostic runner' -or $state.mediaWorkerProcess -or $script:child.HasExited -or (Test-Path (Join-Path $temporary 'media-worker-authorized.json'))) { throw "Unverified worker was authorized/claimed: $failure" }
        } else {
            if ($failure -notmatch 'timed out' -or -not $state.mediaWorkerProcess -or $state.mediaWorkerProcess.HasExited) { throw "Owned timeout process not retained: $failure" }
        }
        if ($script:scenario -in @('wrong-parent-identity','wrong-parent-executable','worker-timeout')) {
            $script:workerForCleanup=$state.mediaWorkerProcess
            function Invoke-CutQuayQualificationCore([Collections.IDictionary]$Operations) {
                $captured=$Operations.Preflight.Module.SessionState.PSVariable.GetValue('state')
                $captured.mediaWorkerProcess=$script:workerForCleanup
                & $Operations.StopOwnedProcess
                throw 'fixture cleanup completed'
            }
            $cleanupFailure=$null
            try { Invoke-CutQuayInstallQualification unused unused unused unused } catch { $cleanupFailure=$_.Exception.Message }
            if ($cleanupFailure -cne 'fixture cleanup completed') { throw "Actual outer cleanup failed: $cleanupFailure" }
            if (($script:scenario -eq 'worker-timeout') -ne $script:child.HasExited) { throw 'Actual cleanup removed an unverified process or retained an owned process.' }
        }
        Write-Output "PASS real package-worker process/handshake: $script:scenario"
    } finally {
        # The test owns its directly created child regardless of production's
        # package verification result. Never use name-based process cleanup.
        if ($script:child) { if (-not $script:child.HasExited) { $script:child.Kill(); $null=$script:child.WaitForExit(10000) }; $script:child.Dispose(); $script:child=$null }
        if ($state.mediaWorkerProcess) { $state.mediaWorkerProcess.Dispose() }
        Remove-Item $temporary -Recurse -Force
    }
}
