# Copyright 2026 Trieflow LLC. MIT.
# Exercise real Install and RemoveOwnedPackage closures and outer failure evidence;
# only Appx cmdlets and unrelated Windows/UI operations are replaced.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$script:ActualCore = ${function:Invoke-CutQuayQualificationCore}
$global:RegistrationFixture = $null
function global:Get-AppxPackage {
    [CmdletBinding()] param([string]$Name)
    if ($Name -cne 'Trieflow.CutQuay.Qualification') { throw 'Unscoped package query' }
    $fixture = $global:RegistrationFixture
    if ($fixture.observationFailure) { $fixture.observationFailure=$false; throw 'registration observation failed' }
    return @($fixture.registrations)
}
function global:Add-AppxPackage {
    [CmdletBinding()] param([string]$Path)
    $fixture = $global:RegistrationFixture
    if ($Path -cne 'owned-test-signed-copy.msix') { throw 'Wrong signed package path' }
    switch ($fixture.scenario) {
        'failed-add-race' { $fixture.registrations=@($fixture.raced); throw 'Add failed after another registration appeared' }
        'ambiguous-add' { $fixture.registrations=@($fixture.owned,$fixture.foreign) }
        'wrong-architecture' { $fixture.registrations=@($fixture.foreign) }
        'observation-failed' { $fixture.registrations=@($fixture.owned); $fixture.observationFailure=$true }
        default { $fixture.registrations=@($fixture.owned) }
    }
    'native Add-AppxPackage output'
}
function global:Remove-AppxPackage {
    [CmdletBinding()] param([string]$Package)
    $fixture = $global:RegistrationFixture
    $fixture.removed.Add($Package)
    if ($fixture.scenario -eq 'remove-failed') { throw 'owned removal failed' }
    $fixture.registrations=@($fixture.registrations | Where-Object PackageFullName -CNE $Package)
    'native Remove-AppxPackage output'
}
function Invoke-CutQuayQualificationCore([Collections.IDictionary]$Operations) {
    $fixture = $global:RegistrationFixture
    $state = $Operations.Preflight.Module.SessionState.PSVariable.GetValue('state')
    $state.output=$fixture.directory
    $state.package=Join-Path $fixture.directory 'source.msix'
    [IO.File]::WriteAllText($state.package,'original unsigned bytes')
    $state.unsignedPackageSha256=(Get-FileHash $state.package -Algorithm SHA256).Hash.ToLowerInvariant()
    $state.signedCopy='owned-test-signed-copy.msix'
    $state.record=[pscustomobject]@{sourceCommit=('a'*40);payload=[pscustomobject]@{};runtime=[pscustomobject]@{electron=[pscustomobject]@{version='42.11.3'}}}
    # Native preflight is unavailable locally. Capture the empty preflight view;
    # actual Add/Get/Remove production closures run through the controlled adapter.
    $Operations.Preflight={ if (@(Get-AppxPackage -Name 'Trieflow.CutQuay.Qualification').Count) { throw 'Fixture must start empty' } }
    foreach ($name in @('PrepareSignedCopy','VerifyInstalledMedia','CaptureInstalledStderr','ActivateAndVerify','UninstallAndVerify','StopOwnedProcess','RemoveTrustedCertificate','RemovePersonalCertificate','RemoveTemporaryFiles')) {
        if ($name -eq 'UninstallAndVerify' -and $fixture.scenario -in @('normal-owned','normal-with-foreign')) { continue }
        $Operations[$name]={}
    }
    $Operations.CloseCleanly={
        if ($global:RegistrationFixture.scenario -in @('owned-with-foreign','normal-with-foreign')) { $global:RegistrationFixture.registrations += $global:RegistrationFixture.foreign }
    }
    return & $script:ActualCore $Operations
}
foreach ($scenario in @('failed-add-race','ambiguous-add','wrong-architecture','observation-failed','owned','owned-with-foreign','remove-failed','normal-owned','normal-with-foreign')) {
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('cutquay-registration-test-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $temporary | Out-Null
    try {
        $owned=[pscustomobject]@{Name='Trieflow.CutQuay.Qualification';Publisher='CN=CutQuay-CI-Qualification';Version='1.0.0.0';Architecture='X64';PackageFullName='Trieflow.CutQuay.Qualification_1.0.0.0_x64__fixture';PackageFamilyName='Trieflow.CutQuay.Qualification_fixture';InstallLocation=$temporary}
        $foreign=[pscustomobject]@{Name=$owned.Name;Publisher=$owned.Publisher;Version=$owned.Version;Architecture='Arm64';PackageFullName='Trieflow.CutQuay.Qualification_1.0.0.0_arm64__fixture';PackageFamilyName=$owned.PackageFamilyName;InstallLocation=$temporary}
        # The racing registration has the exact expected x64 full name; a name/
        # architecture match still cannot establish ownership after our Add failed.
        $raced=$owned.PSObject.Copy()
        $global:RegistrationFixture=[ordered]@{scenario=$scenario;directory=$temporary;owned=$owned;foreign=$foreign;raced=$raced;registrations=@();removed=[Collections.Generic.List[string]]::new();observationFailure=$false}
        $failure=$null
        try { Invoke-CutQuayInstallQualification unused unused unused $temporary | Out-Null } catch { $failure=$_.Exception.Message }
        $fixture=$global:RegistrationFixture
        $evidence=Get-Content (Join-Path $temporary 'installation-qualification.json') -Raw | ConvertFrom-Json
        if ($scenario -in @('failed-add-race','ambiguous-add','wrong-architecture','observation-failed')) {
            if ($fixture.removed.Count -or -not $fixture.registrations.Count) { throw "${scenario}: unowned or ambiguous registration was removed" }
            if (-not $failure -or $evidence.installation_qualification_passed -or -not $evidence.primary_error) { throw "${scenario}: original failure was lost" }
            if ($evidence.cleanup_errors.Count -ne 1 -or $evidence.cleanup_errors[0] -notmatch 'preserved') { throw "${scenario}: residual registration not reported" }
            if ($evidence.registration_ownership_established -or $evidence.owned_package_full_name) { throw "${scenario}: registration ownership was falsely claimed" }
        } else {
            if ($fixture.removed.Count -ne 1 -or $fixture.removed[0] -cne $owned.PackageFullName) { throw "${scenario}: removal was not limited to exact owned PackageFullName" }
            if (-not $evidence.registration_ownership_established -or $evidence.owned_package_full_name -cne $owned.PackageFullName) { throw "${scenario}: exact established ownership is missing" }
            if ($scenario -in @('owned','normal-owned')) {
                if ($failure -or -not $evidence.installation_qualification_passed -or $fixture.registrations.Count) { throw 'Owned registration success control failed' }
                if ($scenario -eq 'normal-owned' -and -not $evidence.uninstall_verified) { throw 'Normal uninstall did not execute' }
            } else {
                if (-not $failure -or $evidence.installation_qualification_passed -or -not $fixture.registrations.Count -or $evidence.cleanup_errors.Count -ne 1) { throw "${scenario}: residual/removal failure must fail and retain evidence" }
            }
        }
        Write-Output "PASS actual registration ownership flow: $scenario"
    } finally { Remove-Item $temporary -Recurse -Force }
}
Remove-Item Function:\Get-AppxPackage,Function:\Add-AppxPackage,Function:\Remove-AppxPackage
Remove-Variable RegistrationFixture -Scope Global
