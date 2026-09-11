# Copyright 2026 Trieflow LLC. MIT. Temporary identity, metadata-only evidence.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows -or $env:CI -ne 'true' -or $PSVersionTable.PSVersion.Major -lt 7) { throw 'Requires Windows CI and PowerShell 7.' }
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..'))
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with $LASTEXITCODE" }
}
$powerShell = (Get-Process -Id $PID).Path
Invoke-Checked python @('script/msix/test_msix_qualification.py')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_qualify_msix_install.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_msix_evidence.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_registration_ownership.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_installed_media.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_media_failed_start.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_package_media.ps1')
Invoke-Checked node @('--test','script/msix/testWorkflowUi.mjs')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_workflow_media.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_media_identity.ps1')
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/test_workflow_ownership.ps1')
$sourceCommit = (git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -cne $env:GITHUB_SHA) { throw 'Source commit differs from this qualification run.' }
$baseline = Get-Content build-evidence/windows-startup.json -Raw | ConvertFrom-Json
if (-not $baseline.windows_native_startup -or $baseline.source_commit -cne $sourceCommit -or $baseline.window_title -cne 'CutQuay 1.0.0') { throw 'Exact source/native startup qualification is required before MSIX.' }
$exeHash = (Get-FileHash dist/win-unpacked/CutQuay.exe -Algorithm SHA256).Hash
if ($exeHash -cne $baseline.executable_sha256) { throw 'Native executable changed since baseline qualification.' }
$electronInput = Join-Path $env:RUNNER_TEMP ('cutquay-electron-input-' + [guid]::NewGuid().ToString('N'))
Invoke-Checked node @('script/msix/prepare-electron-input.cjs',$electronInput)
$electronVersion = (Get-Content package.json -Raw | ConvertFrom-Json).devDependencies.electron
$sdkVersion = '10.0.26100.0'
$sdkDirectory = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin\$sdkVersion\x64"
$packageOutput = Join-Path $env:RUNNER_TEMP ('cutquay-msix-package-' + [guid]::NewGuid().ToString('N'))
Invoke-Checked python @('script/msix/msix_qualification.py','--release','dist/win-unpacked','--artwork','icon-build/app-512.png','--source-root','.','--source-commit',$sourceCommit,'--makeappx',(Join-Path $sdkDirectory 'makeappx.exe'),'--sdk-version',$sdkVersion,'--output',$packageOutput,'--electron-archive',(Join-Path $electronInput "electron-v$electronVersion-win32-x64.zip"),'--electron-checksums',(Join-Path $electronInput 'SHASUMS256.txt'))
[IO.File]::Copy((Join-Path $packageOutput 'package-record.json'), (Join-Path (Get-Location) 'build-evidence/msix-package-record.json'), $false)
Invoke-Checked $powerShell @('-NoLogo','-NoProfile','-File','script/msix/qualify-msix-install.ps1','-Package',(Join-Path $packageOutput 'CutQuay.Qualification_1.0.0.0_x64.msix'),'-PackageRecord',(Join-Path $packageOutput 'package-record.json'),'-SignTool',(Join-Path $sdkDirectory 'signtool.exe'),'-Output','build-evidence/msix-install')
