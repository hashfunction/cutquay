# Copyright 2026 Trieflow LLC. MIT. Real Process.Start failure regression.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('cutquay-start-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory (Join-Path $temporary 'resources') | Out-Null
try {
    $executable = Join-Path $temporary 'resources/ffmpeg.exe'
    [IO.File]::WriteAllText($executable, 'not an executable')
    $state = [ordered]@{
        installed=[pscustomobject]@{InstallLocation=$temporary}; output=$temporary; mediaProcess=$null
        record=[pscustomobject]@{payload=[pscustomobject]@{'resources/ffmpeg.exe'=[pscustomobject]@{
            bytes=(Get-Item $executable).Length; sha256=(Get-FileHash $executable -Algorithm SHA256).Hash
        }}}
    }
    $failure=$null
    try { Test-InstalledMedia $state | Out-Null } catch { $failure=$_.Exception.Message }
    if (-not $failure) { throw 'Invalid native image unexpectedly started.' }
    if ($state.mediaProcess) { throw 'Failed Process.Start retained an unstarted process for cleanup.' }
    Write-Output 'PASS actual failed native start preserves its error and leaves no owned process.'
} finally {
    if ($state.mediaProcess) { $state.mediaProcess.Dispose() }
    Remove-Item $temporary -Recurse -Force
}
