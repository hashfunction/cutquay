# Copyright 2026 Trieflow LLC. MIT. Capture the unchanged, already-qualified Store package.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Inputs,[Parameter(Mandatory)][string]$QualifiedSource,[Parameter(Mandatory)][Alias('Output')][string]$CaptureOutput)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_helpers.ps1')
. (Join-Path $PSScriptRoot 'display_modes.ps1')
if(-not $IsWindows -or $env:CI -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'hashfunction/cutquay'){throw 'Requires isolated CutQuay Windows CI.'}
$inputRoot=(Resolve-Path $Inputs).Path;$qualified=(Resolve-Path $QualifiedSource).Path
$python=@(Get-Command python -CommandType Application)[0].Source
Invoke-CheckedNative $python @((Join-Path $PSScriptRoot 'capture_checks.py'),'--inputs',$inputRoot,'--qualified-source',$qualified)
$outputRoot=[IO.Path]::GetFullPath($CaptureOutput)
if(Test-Path $outputRoot){throw 'Screenshot output already exists and will not be overwritten.'}
New-Item -ItemType Directory $outputRoot | Out-Null;Assert-WorkflowDirectory $outputRoot
foreach($name in @('capture-inputs.json','media-attribution.json')){[IO.File]::Copy((Join-Path $inputRoot $name),(Join-Path $outputRoot $name),$false)}
$state=[ordered]@{package=(Join-Path $inputRoot 'store/Cliptern_1.0.1.0_x64.msix');record=$null;output=$outputRoot;temporary=$null;config=$null;
    work=$null;workOwned=$false;certificate=$null;trustAttempted=$false;installed=$null;installedByUs=$false;ownedPackageFullName=$null;
    installAttempted=$false;activationStarted=$null;process=$null;aumid=$null;workflowDriver=$null;mediaProcess=$null;
    ownedProcesses=[Collections.Generic.List[Diagnostics.Process]]::new();preflightPackageFullNames=@();residualPackageFullNames=@();
    cleanupErrors=[Collections.Generic.List[string]]::new();normalClose=$false;uninstallVerified=$false;export=$null;reopen=$null;
    displayOriginalMode=$null;displayDevice=$null;displayRestoreRequired=$false;displayEvidence=$null}
$primary=$null;$unsignedUnchanged=$false
$expectedHash='db4cfd8eb24999260ce23557026c398701a536c2110db6f69950cc53dab34dfa'
$fullName='1659hashfunction.CutQuay_1.0.1.0_x64__r3hxytd7jt6c4'
try{
    Start-MarketingDisplay $state
    $state.record=Get-Content (Join-Path $inputRoot 'metadata/msix-store-package-record.json') -Raw|ConvertFrom-Json
    if($state.record.sourceCommit -cne '1f2d10d8237e684d5c04113c6c9fe3f199f2f5e6'){throw 'Capture package source differs from the fixed qualification.'}
    Assert-CutQuayPackageIdentity $state.record $state.package 'store'
    if((Get-WorkflowFileRecord $state.package).sha256 -cne $expectedHash -or (Get-Item $state.package).Length -ne 260378239){throw 'Exact original Store package differs.'}
    Assert-CutQuayPackageAbsent $state 'store'
    $state.temporary=Join-Path $env:RUNNER_TEMP ('cutquay-marketing-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $state.temporary | Out-Null
    $state.config=Join-Path $state.temporary 'settings';New-Item -ItemType Directory $state.config | Out-Null
    $videos=Join-Path $env:USERPROFILE 'Videos'
    if(-not (Test-Path $videos)){New-Item -ItemType Directory $videos | Out-Null}
    Assert-WorkflowDirectory $videos;$state.work=Join-Path $videos 'Cliptern Demo'
    if(Test-Path $state.work){throw 'Existing customer-style demo directory will not be replaced.'}
    New-Item -ItemType Directory $state.work | Out-Null;$state.workOwned=$true
    $media=Join-Path $state.work 'Spring - Blender Foundation.webm'
    [IO.File]::Copy((Join-Path $inputRoot 'Spring - Blender Foundation.webm'),$media,$false)
    if((Get-WorkflowFileRecord $media).sha256 -cne 'd691a199035cc7d295210b286f8f6734893c7d4358d228081af6f0da98a56343'){throw 'Copied licensed media changed.'}
    $signTool=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin/10.0.26100.0/x64/signtool.exe'
    $signToolRecord=Get-WorkflowFileRecord $signTool
    $signed=Join-Path $state.temporary 'Cliptern.marketing.signed.msix';[IO.File]::Copy($state.package,$signed,$false)
    $state.certificate=New-SelfSignedCertificate -Type Custom -KeyUsage DigitalSignature -KeyExportPolicy NonExportable -KeySpec Signature `
        -CertStoreLocation 'Cert:\CurrentUser\My' -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3','2.5.29.19={text}') `
        -Subject 'CN=B6A2631A-FD32-45CC-AE12-82466975F528' -FriendlyName 'Cliptern ephemeral marketing capture' -NotAfter (Get-Date).AddHours(2)
    $public=Join-Path $state.temporary 'capture-public.cer';Export-Certificate -Cert $state.certificate -FilePath $public | Out-Null
    $state.trustAttempted=$true;Import-Certificate -FilePath $public -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    Invoke-CheckedNative $signTool @('sign','/fd','SHA256','/sha1',$state.certificate.Thumbprint,'/s','My',$signed)
    Invoke-CheckedNative $signTool @('verify','/pa','/all','/v',$signed)
    $signature=Get-AuthenticodeSignature -LiteralPath $signed
    if($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $signature.SignerCertificate.Thumbprint -cne $state.certificate.Thumbprint -or
        (Get-WorkflowFileRecord $signTool).sha256 -cne $signToolRecord.sha256 -or (Get-WorkflowFileRecord $state.package).sha256 -cne $expectedHash){throw 'Ephemeral signing identity/tool/original integrity differs.'}
    Add-CutQuayActivationTypes
    $state.activationStarted=[DateTime]::UtcNow;$state.installAttempted=$true
    Add-AppxPackage -Path $signed -ErrorAction Stop
    $matches=@(Get-AppxPackage -Name '1659hashfunction.CutQuay' -ErrorAction Stop)
    if($matches.Count -ne 1 -or $matches[0].PackageFullName -cne $fullName -or $matches[0].Publisher -cne 'CN=B6A2631A-FD32-45CC-AE12-82466975F528' -or
        $matches[0].PackageFamilyName -cne '1659hashfunction.CutQuay_r3hxytd7jt6c4'){throw 'Installed capture identity differs; ownership not established.'}
    $state.installed=$matches[0];$state.installedByUs=$true;$state.ownedPackageFullName=$fullName;$state.aumid=$state.installed.PackageFamilyName+'!CutQuay'
    foreach($row in $state.record.payload.PSObject.Properties){$null=Assert-FileMatchesRecord (Join-Path $state.installed.InstallLocation $row.Name) $row.Value $row.Name}
    $duration=Invoke-MarketingMedia $state $media 'input'
    if([Math]::Abs($duration-464.141) -gt .15){throw 'Actual source media duration differs.'}
    $state.export=Invoke-MarketingUi $state 'export' $media $duration
    $exported=[string]$state.export.output
    if((Get-CanonicalPath ([IO.Path]::GetDirectoryName($exported))) -ine (Get-CanonicalPath $state.work) -or $exported -ieq $media){throw 'Actual export escaped the owned demo directory.'}
    if((Get-WorkflowFileRecord $exported).sha256 -cne $state.export.output_hash.sha256){throw 'Actual export differs from consumer report.'}
    $duration=Invoke-MarketingMedia $state $exported 'output'
    if($duration -lt 23.5 -or $duration -gt 35){throw 'Actual export duration is outside bounded keyframe alignment.'}
    $state.reopen=Invoke-MarketingUi $state 'reopen' $exported $duration
    $state.normalClose=$true
    if((Get-WorkflowFileRecord $media).sha256 -cne 'd691a199035cc7d295210b286f8f6734893c7d4358d228081af6f0da98a56343' -or
        (Get-WorkflowFileRecord $exported).sha256 -cne $state.export.output_hash.sha256){throw 'Final actual media integrity changed.'}
    Remove-AppxPackage -Package $state.ownedPackageFullName -ErrorAction Stop
    if(@(Get-AppxPackage -Name '1659hashfunction.CutQuay' -ErrorAction Stop).Count){throw 'Registration remains after normal screenshot uninstall.'}
    $state.uninstallVerified=$true
}catch{$primary=$_.Exception.Message}
finally{
    Complete-MarketingCleanup $state
    try{Restore-MarketingDisplay $state}catch{$state.cleanupErrors.Add($_.Exception.Message)}
    if($state.displayEvidence){try{Write-NewUtf8Json (Join-Path $outputRoot 'native-display-mode.json') $state.displayEvidence}catch{$state.cleanupErrors.Add('Display evidence: '+$_.Exception.Message)}}
    try{$unsignedUnchanged=(Get-WorkflowFileRecord $state.package).sha256 -ceq $expectedHash}catch{$state.cleanupErrors.Add('Could not recheck original unsigned package.')}
    $captured=($null -eq $primary -and $state.cleanupErrors.Count -eq 0 -and $state.normalClose -and $state.uninstallVerified -and $unsignedUnchanged)
    Write-NewUtf8Json (Join-Path $outputRoot 'capture-result.json') ([ordered]@{schema_version=1;purpose='marketing screenshots only';captured=$captured;
        consumer_acceptance=$false;installation_qualification_claimed=$false;submission_changed=$false;product_binary_changed=$false;
        capture_source_commit=$env:GITHUB_SHA;capture_workflow_run_id=$env:GITHUB_RUN_ID;capture_workflow_run_attempt=$env:GITHUB_RUN_ATTEMPT;
        qualified_source_commit='1f2d10d8237e684d5c04113c6c9fe3f199f2f5e6';qualified_run_id='34681628290';package_full_name=$state.ownedPackageFullName;
        original_unsigned_sha256=$expectedHash;original_unsigned_unchanged=$unsignedUnchanged;certificate_private_key_exported=$false;
        normal_close_verified=$state.normalClose;uninstall_verified=$state.uninstallVerified;residual_package_full_names=$state.residualPackageFullNames;display_mode=$state.displayEvidence;
        export=$state.export;reopen=$state.reopen;primary_error=$primary;cleanup_errors=@($state.cleanupErrors);captured_at_utc=[DateTime]::UtcNow.ToString('o')})
    foreach($process in @($state.ownedProcesses)+@($state.workflowDriver,$state.mediaProcess)){if($process){$process.Dispose()}}
}
if(-not $captured){throw "Marketing capture incomplete. Primary: $primary; cleanup: $($state.cleanupErrors -join '; ')"}
Write-Output 'Captured real installed app scenes and completed normal close/uninstall. Screenshot evidence only; no new qualification or submission.'
