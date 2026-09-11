# Copyright 2026 Trieflow LLC. MIT. Run the real media verifier against owned copies
# of available native FFmpeg/FFprobe. This is a process/API test, not MSIX installation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('cutquay-media-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory (Join-Path $temporary 'resources') | Out-Null
try {
    if ($IsWindows) {
        $inputDirectory = Join-Path $PSScriptRoot '../../ffmpeg/win32-x64/lib'
        foreach ($file in Get-ChildItem $inputDirectory -File) { [IO.File]::Copy($file.FullName, (Join-Path $temporary "resources/$($file.Name)"), $false) }
    } else {
        foreach ($name in @('ffmpeg','ffprobe')) {
            $inputFile = (Get-Command $name -CommandType Application -ErrorAction Stop).Source
            $target = Join-Path $temporary "resources/$name.exe"
            [IO.File]::Copy($inputFile, $target, $false)
            & chmod +x $target
            if ($LASTEXITCODE) { throw 'Cannot prepare owned native media executable.' }
        }
    }
    $versionText = (& (Join-Path $temporary 'resources/ffmpeg.exe') -version 2>&1) -join "`n"
    if ($LASTEXITCODE) { throw 'Available native FFmpeg failed.' }
    if ($versionText -notmatch 'ffmpeg version ([^ ]+)') { throw 'Cannot determine native FFmpeg version.' }
    $version = $Matches[1]
    if ($versionText -notmatch '(?m)^configuration: (.+)$') { throw 'Cannot determine native FFmpeg build configuration.' }
    $configuration = $Matches[1].TrimEnd("`r")
    $payload = [ordered]@{}
    foreach ($name in @('ffmpeg','ffprobe')) {
        $relative = "resources/$name.exe"
        $file = Join-Path $temporary $relative
        $payload[$relative] = [pscustomobject]@{bytes=(Get-Item $file).Length;sha256=(Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $state = [ordered]@{
        installed=[pscustomobject]@{InstallLocation=$temporary}; output=$temporary; mediaProcess=$null
        record=[pscustomobject]@{payload=[pscustomobject]$payload; runtime=[pscustomobject]@{media=[pscustomobject]@{version=$version;configuration=$configuration}}}
    }
    $results = @(Test-InstalledMedia $state)
    if ($results.Count -ne 4 -or @($results | Where-Object { $_.exit_code -ne 0 -or -not $_.configuration_verified }).Count) { throw 'Expected four successful actual native invocations.' }
    foreach ($file in @('installed-ffmpeg-version.log','installed-ffmpeg-buildconf.log','installed-ffprobe-version.log','installed-ffprobe-buildconf.log')) {
        if (-not (Test-Path (Join-Path $temporary $file))) { throw "Missing actual media output: $file" }
    }
    $state.record.runtime.media.configuration='--configuration-that-is-not-built'
    $failure=$null
    try { Test-InstalledMedia $state | Out-Null } catch { $failure=$_.Exception.Message }
    if ($failure -notmatch 'configuration mismatch') { throw 'A different native build configuration was accepted.' }
    $state.record.runtime.media.configuration=$configuration
    $state.record.payload.'resources/ffmpeg.exe'.sha256='0' * 64
    $failure=$null
    try { Test-InstalledMedia $state | Out-Null } catch { $failure=$_.Exception.Message }
    if ($failure -notmatch 'hash differs') { throw 'Changed native media bytes were accepted.' }
    Write-Output "PASS: four actual native media calls ($version), incompatible configuration rejected, changed executable hash rejected. No MSIX installation claim."
} finally {
    if (Get-Variable state -ErrorAction SilentlyContinue) {
        if ($state.mediaProcess -and -not $state.mediaProcess.HasExited) { $state.mediaProcess.Kill(); $null=$state.mediaProcess.WaitForExit(10000) }
    }
    Remove-Item $temporary -Recurse -Force
}
