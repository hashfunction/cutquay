# Copyright 2026 Trieflow LLC. MIT. Real unsigned ZIP/manifest/record identity checks.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('cutquay-identity-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null

function New-IdentityFixture([string]$Mode) {
    $identity=[ordered]@{
        packageName='Trieflow.CutQuay.Qualification';publisher='CN=CutQuay-CI-Qualification';publisherDisplayName='Trieflow LLC'
        version='1.0.1.0';architecture='x64';applicationId='CutQuay';executable='Cliptern.exe'
        deviceFamily='Windows.Desktop';minVersion='10.0.19041.0';maxVersionTested='10.0.26100.0';capability='runFullTrust'
    }
    if ($Mode -ceq 'store') {
        $identity.packageName='1659hashfunction.CutQuay'
        $identity.publisher='CN=B6A2631A-FD32-45CC-AE12-82466975F528'
        $identity.publisherDisplayName='hashfunction'
    }
    $manifest=@"
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"><Identity Name="$($identity.packageName)" Publisher="$($identity.publisher)" Version="1.0.1.0" ProcessorArchitecture="x64"/><Properties><PublisherDisplayName>$($identity.publisherDisplayName)</PublisherDisplayName></Properties><Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.19041.0" MaxVersionTested="10.0.26100.0"/></Dependencies><Applications><Application Id="CutQuay" Executable="Cliptern.exe" EntryPoint="Windows.FullTrustApplication"/></Applications><Capabilities><rescap:Capability Name="runFullTrust"/></Capabilities></Package>
"@
    return @{manifest=$manifest;record=[pscustomobject]@{
        schemaVersion=1;sourceCommit=('a'*40);identityMode=$Mode;identity=[pscustomobject]$identity
        qualificationIdentityOnly=($Mode -ceq 'qualification');storeIdentityUsed=($Mode -ceq 'store')
        signed=$false;publicRelease=$false;licenseClearanceClaimed=$false;installationQualificationPassed=$false
    }}
}
function Write-ManifestPackage([string]$Manifest) {
    $path=Join-Path $temporary ([guid]::NewGuid().ToString('N')+'.msix')
    $archive=[IO.Compression.ZipFile]::Open($path,[IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry=$archive.CreateEntry('AppxManifest.xml')
        $writer=[IO.StreamWriter]::new($entry.Open(),[Text.UTF8Encoding]::new($false))
        try {$writer.Write($Manifest)} finally {$writer.Dispose()}
    } finally {$archive.Dispose()}
    return $path
}
function Assert-Rejected([scriptblock]$Action,[string]$Label) {
    $failure=$null
    try {& $Action} catch {$failure=$_}
    if (-not $failure) {throw "Identity boundary accepted $Label"}
}
try {
    foreach ($mode in @('qualification','store')) {
        $fixture=New-IdentityFixture $mode
        $package=Write-ManifestPackage $fixture.manifest
        Assert-CutQuayPackageIdentity $fixture.record $package $mode
        $other=if ($mode -ceq 'store') {'qualification'} else {'store'}
        Assert-Rejected {Assert-CutQuayPackageIdentity $fixture.record $package $other} "$mode record under $other mode"
        foreach ($field in @('packageName','publisher','publisherDisplayName','version','architecture','applicationId','executable','deviceFamily','minVersion','maxVersionTested','capability')) {
            $changed=New-IdentityFixture $mode
            $changed.record.identity.$field='wrong'
            Assert-Rejected {Assert-CutQuayPackageIdentity $changed.record $package $mode} "mutated $field"
        }
        foreach ($field in @('qualificationIdentityOnly','storeIdentityUsed','signed','publicRelease','licenseClearanceClaimed','installationQualificationPassed')) {
            foreach ($wrong in @('false',1,$null)) {
                $changed=New-IdentityFixture $mode
                $changed.record.$field=$wrong
                Assert-Rejected {Assert-CutQuayPackageIdentity $changed.record $package $mode} "untyped $field"
            }
            $changed=New-IdentityFixture $mode
            $changed.record.$field=-not $changed.record.$field
            Assert-Rejected {Assert-CutQuayPackageIdentity $changed.record $package $mode} "inverted $field"
        }
        $changed=New-IdentityFixture $mode
        $changed.record.identityMode=$other
        Assert-Rejected {Assert-CutQuayPackageIdentity $changed.record $package $mode} 'record mode confusion'
        foreach ($field in @('identityMode','sourceCommit')) {
            foreach ($wrong in @($true,1,$null,'')) {
                $changed=New-IdentityFixture $mode
                $changed.record.$field=$wrong
                Assert-Rejected {Assert-CutQuayPackageIdentity $changed.record $package $mode} "untyped or empty $field"
            }
        }
        $otherFixture=New-IdentityFixture $other
        $otherPackage=Write-ManifestPackage $otherFixture.manifest
        Assert-Rejected {Assert-CutQuayPackageIdentity $fixture.record $otherPackage $mode} 'manifest mode confusion with unchanged record'
        foreach ($before in @($fixture.record.identity.packageName,$fixture.record.identity.publisher,$fixture.record.identity.publisherDisplayName,'1.0.1.0','x64','Id="CutQuay"','Cliptern.exe','Windows.FullTrustApplication','Windows.Desktop','10.0.19041.0','10.0.26100.0','runFullTrust')) {
            $replacement=if ($before -ceq 'Id="CutQuay"') {'Id="Other"'} else {'wrong'}
            $changedPackage=Write-ManifestPackage $fixture.manifest.Replace($before,$replacement)
            Assert-Rejected {Assert-CutQuayPackageIdentity $fixture.record $changedPackage $mode} "mutated manifest $before"
        }
        Write-Output "PASS exact manifest/record identity, mode confusion, field and typed-flag rejection: $mode"
    }
    foreach ($mode in @('','Store','custom')) {
        Assert-Rejected {Assert-CutQuayPackageIdentity $fixture.record $package $mode} "unsupported mode $mode"
    }
    # Real preflight registration boundary; only the Windows registry query is adapted.
    $script:QueryName=$null
    $script:Registrations=@()
    function Get-AppxPackage {
        [CmdletBinding()] param([string]$Name)
        if ($Name -cne $script:QueryName) {throw 'Preflight queried a different identity'}
        return $script:Registrations
    }
    foreach ($mode in @('qualification','store')) {
        $script:QueryName=if ($mode -ceq 'store') {'1659hashfunction.CutQuay'} else {'Trieflow.CutQuay.Qualification'}
        $state=@{preflightPackageFullNames=@()}
        $script:Registrations=@()
        Assert-CutQuayPackageAbsent $state $mode
        foreach ($fullName in @($script:QueryName+'_1.0.0.0_x64__fixture',$script:QueryName+'_9.0.0.0_arm64__foreign')) {
            $script:Registrations=@([pscustomobject]@{PackageFullName=$fullName})
            Assert-Rejected {Assert-CutQuayPackageAbsent $state $mode} 'preexisting same-name registration'
            if ($state.preflightPackageFullNames.Count -ne 1 -or $state.preflightPackageFullNames[0] -cne $fullName) {throw 'Existing registration observation was not retained'}
        }
        Write-Output "PASS actual preflight rejects existing same-name package at any version/architecture: $mode"
    }
} finally {Remove-Item -LiteralPath $temporary -Recurse -Force}
