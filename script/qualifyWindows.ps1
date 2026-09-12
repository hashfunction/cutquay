$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true') { throw 'Requires isolated Windows CI.' }
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
$yarn = '.yarn/releases/yarn-4.11.0.cjs'
function Run-Yarn([string[]]$Arguments) {
  & node $yarn @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Yarn failed: $Arguments" }
}
$sourceCommit = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -cne $env:GITHUB_SHA) { throw 'Native source commit differs from this run.' }
$dirty = git status --porcelain --untracked-files=all
if ($LASTEXITCODE -ne 0 -or $dirty) { throw 'Qualification must start from a clean source checkout.' }
New-Item -ItemType Directory -Force build-evidence | Out-Null
Run-Yarn @('install', '--immutable')
Run-Yarn @('download-ffmpeg-win32-x64')
$env:CUTQUAY_TEST_FFMPEG_DIR = (Resolve-Path 'ffmpeg/win32-x64/lib').Path
$ffmpeg = Join-Path $env:CUTQUAY_TEST_FFMPEG_DIR 'ffmpeg.exe'
$version = & $ffmpeg -version 2>&1
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg version execution failed.' }
$configuration = & $ffmpeg -buildconf 2>&1
if ($LASTEXITCODE -ne 0) { throw 'FFmpeg build configuration execution failed.' }
$version | Set-Content build-evidence/ffmpeg-version.txt -Encoding utf8NoBOM
$configuration | Set-Content build-evidence/ffmpeg-buildconf.txt -Encoding utf8NoBOM
$pin = Get-Content Release/ffmpeg-build.json -Raw | ConvertFrom-Json
if (-not (($version -join "`n").Contains($pin.version))) { throw 'FFmpeg version differs from pin.' }
if (-not (($version -join "`n").Contains($pin.configureStringsExtractedFromBinaries[0]))) { throw 'FFmpeg configuration differs from pin.' }
Run-Yarn @('tsc')
Run-Yarn @('lint')
Run-Yarn @('test', 'run', '--reporter=default', '--reporter=junit', '--outputFile=build-evidence/tests.xml')
Run-Yarn @('check-licenses')
Run-Yarn @('generate-licenses')
$noticeHash = (Get-FileHash licenses.txt -Algorithm SHA256).Hash.ToLowerInvariant()
$env:CSC_IDENTITY_AUTO_DISCOVERY = 'false'
Run-Yarn @('pack-win-dir')
$executable = (Resolve-Path 'dist/win-unpacked/Cliptern.exe').Path
$process = Start-Process $executable -PassThru
try {
  $deadline = (Get-Date).AddSeconds(45)
  do {
    Start-Sleep -Milliseconds 500
    $process.Refresh()
    if ($process.HasExited) { throw "Cliptern exited during startup: $($process.ExitCode)" }
  } until (($process.MainWindowHandle -ne 0 -and $process.MainWindowTitle -ceq 'Cliptern 1.0.1') -or (Get-Date) -gt $deadline)
  if ($process.MainWindowHandle -eq 0) { throw 'No Cliptern native main window appeared.' }
  if ($process.MainWindowTitle -cne 'Cliptern 1.0.1') { throw "Unexpected native startup title: $($process.MainWindowTitle)" }
  @{ generated_notices_sha256=$noticeHash; source_commit=$env:GITHUB_SHA; workflow_run_id=$env:GITHUB_RUN_ID; workflow_run_attempt=$env:GITHUB_RUN_ATTEMPT; generated_at_utc=[DateTime]::UtcNow.ToString('o'); windows_native_startup=$true; executable_sha256=(Get-FileHash $executable -Algorithm SHA256).Hash; window_title=$process.MainWindowTitle; ffmpeg_version=$pin.version; native_source_clearance=$false; interactive_acceptance=$false; msix_built=$false; submitted=$false } | ConvertTo-Json | Set-Content build-evidence/windows-startup.json -Encoding utf8NoBOM
} finally {
  if (-not $process.HasExited) {
    $process.CloseMainWindow() | Out-Null
    if (-not $process.WaitForExit(5000)) { $process.Kill() }
  }
}
