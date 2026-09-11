# Failure-path tests for the real CutQuay qualification orchestration.
# Copyright 2026 Trieflow LLC. MIT licensed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-FakeOperations([string]$PrimaryFailure, [string[]]$CleanupFailures, [switch]$Noisy) {
    $global:CutQuayQualificationTestCalls = [Collections.Generic.List[string]]::new()
    $operations = [ordered]@{}
    foreach ($name in @('Preflight','PrepareSignedCopy','Install','VerifyInstalledMedia','CaptureInstalledStderr','ActivateAndVerify','CloseCleanly','QualifyExportWorkflow','UninstallAndVerify')) {
        $operationName = $name
        $operations[$name] = {
            $global:CutQuayQualificationTestCalls.Add($operationName)
            if ($Noisy) { Write-Output "native stdout:$operationName"; Write-Output ([pscustomobject]@{ unrelated_native_output=$true }) }
            if ($PrimaryFailure -eq $operationName) { throw "primary:$operationName" }
        }.GetNewClosure()
    }
    foreach ($name in @('StopOwnedProcess','RemoveOwnedPackage','RemoveTrustedCertificate','RemovePersonalCertificate','RemoveTemporaryFiles')) {
        $operationName = $name
        $operations[$name] = {
            $global:CutQuayQualificationTestCalls.Add($operationName)
            if ($Noisy) { Write-Output "cleanup stdout:$operationName"; Write-Output 7 }
            if ($CleanupFailures -contains $operationName) { throw "cleanup:$operationName" }
        }.GetNewClosure()
    }
    return $operations
}

$result = Invoke-CutQuayQualificationCore -Operations (New-FakeOperations '' @())
Assert-True $result.installation_qualification_passed 'success path must pass'
Assert-True (-not $result.primary_error) 'success path must have no primary error'
Assert-True ($result.cleanup_errors.Count -eq 0) 'success path must have no cleanup errors'
Assert-True (($global:CutQuayQualificationTestCalls -join ',') -eq 'Preflight,PrepareSignedCopy,Install,VerifyInstalledMedia,CaptureInstalledStderr,ActivateAndVerify,CloseCleanly,QualifyExportWorkflow,UninstallAndVerify,StopOwnedProcess,RemoveOwnedPackage,RemoveTrustedCertificate,RemovePersonalCertificate,RemoveTemporaryFiles') 'all qualification and cleanup steps must run in order'

$result = Invoke-CutQuayQualificationCore -Operations (New-FakeOperations 'ActivateAndVerify' @('RemoveOwnedPackage','RemovePersonalCertificate'))
Assert-True (-not $result.installation_qualification_passed) 'primary and cleanup failure must fail'
Assert-True ($result.primary_error -eq 'primary:ActivateAndVerify') 'primary failure must be retained exactly'
Assert-True ($result.cleanup_errors.Count -eq 2) 'all cleanup failures must be retained'
Assert-True (($result.cleanup_errors -join '|') -match 'RemoveOwnedPackage.*RemovePersonalCertificate') 'cleanup failures must identify their operations'
Assert-True (-not ($global:CutQuayQualificationTestCalls -contains 'CloseCleanly')) 'later primary operations must not run after failure'
foreach ($cleanup in @('StopOwnedProcess','RemoveOwnedPackage','RemoveTrustedCertificate','RemovePersonalCertificate','RemoveTemporaryFiles')) {
    Assert-True ($global:CutQuayQualificationTestCalls -contains $cleanup) "cleanup operation $cleanup must still run"
}

$result = Invoke-CutQuayQualificationCore -Operations (New-FakeOperations '' @('RemoveTrustedCertificate'))
Assert-True (-not $result.installation_qualification_passed) 'cleanup failure alone must fail qualification'
Assert-True (-not $result.primary_error) 'cleanup-only failure must not manufacture a primary failure'
Assert-True ($result.cleanup_errors.Count -eq 1) 'cleanup-only failure must be recorded'

$result = Invoke-CutQuayQualificationCore -Operations (New-FakeOperations 'Preflight' @())
Assert-True (-not $result.installation_qualification_passed) 'preexisting-install/preflight failure must fail qualification'
Assert-True (($global:CutQuayQualificationTestCalls -join ',') -eq 'Preflight,StopOwnedProcess,RemoveOwnedPackage,RemoveTrustedCertificate,RemovePersonalCertificate,RemoveTemporaryFiles') 'preflight failure must skip mutation and still execute safe cleanup adapters'

$result = @(Invoke-CutQuayQualificationCore -Operations (New-FakeOperations '' @() -Noisy))
Assert-True ($result.Count -eq 1) 'native stdout must not contaminate the one structured result'
Assert-True $result[0].installation_qualification_passed 'noisy success must retain its success result'
$result = @(Invoke-CutQuayQualificationCore -Operations (New-FakeOperations 'ActivateAndVerify' @('RemovePersonalCertificate') -Noisy))
Assert-True ($result.Count -eq 1) 'noisy failure must retain only one structured result'
Assert-True (-not $result[0].installation_qualification_passed) 'noisy failure cannot pass'
Assert-True ($result[0].primary_error -eq 'primary:ActivateAndVerify') 'native stdout must not erase primary failure'
Assert-True ($result[0].cleanup_errors.Count -eq 1) 'native stdout must not erase cleanup failure'

# Real pipeline output must never turn the result into an object array.
foreach ($failure in @('', 'ActivateAndVerify')) {
    $operations = New-FakeOperations $failure @('RemoveTrustedCertificate')
    $operations.PrepareSignedCopy = { 'SignTool native stdout'; 'certificate diagnostic stdout' }
    $operations.RemoveTemporaryFiles = { 'cleanup native stdout' }
    $noisy = Invoke-CutQuayQualificationCore $operations
    Assert-True ($noisy -isnot [array]) 'noisy operations must return exactly one structured result'
    Assert-True (-not $noisy.installation_qualification_passed) 'noisy cleanup failure must remain failed'
    Assert-True ($noisy.cleanup_errors.Count -eq 1) 'noisy output must not erase cleanup errors'
}
$operations = New-FakeOperations '' @()
$operations.PrepareSignedCopy = { 'SignTool successful verification stdout' }
$noisy = Invoke-CutQuayQualificationCore $operations
Assert-True ($noisy -isnot [array] -and $noisy.installation_qualification_passed) 'noisy success must return one passing result'

$packageRoot = Join-Path ([IO.Path]::GetTempPath()) 'package'
$insidePackage = Test-PathInside -Candidate (Join-Path $packageRoot 'CutQuay.exe') -Root $packageRoot
$siblingPackage = Test-PathInside -Candidate (Join-Path ([IO.Path]::GetTempPath()) 'package-other/foreign.dll') -Root $packageRoot
Assert-True $insidePackage 'exact package descendant must be accepted'
Assert-True (-not $siblingPackage) 'textual sibling prefix must not count as package path'
$recordFixture = [pscustomobject]@{ payload = [pscustomobject]@{ 'CutQuay.exe' = [pscustomobject]@{ bytes=1; sha256=('a' * 64) } } }
Assert-True ((Get-RecordPayloadEntry $recordFixture 'CutQuay.exe').bytes -eq 1) 'slash-qualified payload property must resolve exactly'
$exclusiveDirectory = Join-Path ([IO.Path]::GetTempPath()) ('cutquay-ps-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $exclusiveDirectory | Out-Null
try {
    $exclusiveFile = Join-Path $exclusiveDirectory 'evidence.json'
    Write-NewUtf8Json $exclusiveFile ([ordered]@{ passed=$false })
    try { Write-NewUtf8Json $exclusiveFile ([ordered]@{ passed=$true }); throw 'expected exclusive write failure' }
    catch { Assert-True ($_.Exception.Message -notmatch 'expected exclusive') 'evidence writer must refuse replacement' }
    Assert-True ((Get-Content -LiteralPath $exclusiveFile -Raw | ConvertFrom-Json).passed -eq $false) 'failed replacement must preserve evidence bytes'
} finally {
    Remove-Item -LiteralPath $exclusiveDirectory -Recurse -Force
}
Add-CutQuayActivationTypes
Assert-True ($null -ne ('CutQuayQualification.NativePackageProbe' -as [type])) 'GetPackageFullName helper types must compile'

Remove-Variable CutQuayQualificationTestCalls -Scope Global
Write-Output 'PASS: 6 installation orchestration scenarios plus path/evidence/native-helper checks.'

$result=Invoke-CutQuayQualificationCore -Operations (New-FakeOperations 'QualifyExportWorkflow' @('RemoveOwnedPackage'))
Assert-True (-not $result.installation_qualification_passed) 'workflow failure must fail installation qualification'
Assert-True ($result.primary_error -ceq 'primary:QualifyExportWorkflow') 'workflow error must survive cleanup'
Assert-True ($result.cleanup_errors.Count -eq 1) 'workflow failure must retain cleanup error'
Assert-True (-not ($global:CutQuayQualificationTestCalls -contains 'UninstallAndVerify')) 'failed workflow cannot reach normal acceptance'
Remove-Variable CutQuayQualificationTestCalls -Scope Global
