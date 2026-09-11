# Actual outer reporting path with only Windows orchestration replaced.
# Copyright 2026 Trieflow LLC. MIT licensed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
foreach ($scenario in @('missing','changed','changed-after-success','success','write-failure')) {
    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('cutquay-evidence-test-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $probeRoot | Out-Null
    try {
        function Invoke-CutQuayQualificationCore([Collections.IDictionary]$Operations) {
            $captured = $Operations.Preflight.Module.SessionState.PSVariable.GetValue('state')
            $captured.output = $probeRoot
            $captured.package = Join-Path $probeRoot 'source.msix'
            [IO.File]::WriteAllText($captured.package, 'original bytes')
            $captured.unsignedPackageSha256 = (Get-FileHash -LiteralPath $captured.package -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($scenario -eq 'missing') { Remove-Item -LiteralPath $captured.package }
            if ($scenario -in @('changed','changed-after-success')) { [IO.File]::WriteAllText($captured.package, 'changed bytes') }
            if ($scenario -eq 'write-failure') { [IO.File]::WriteAllText((Join-Path $probeRoot 'installation-qualification.json'), 'preserve existing evidence') }
            if ($scenario -in @('success','changed-after-success')) {
                return [pscustomobject]@{ installation_qualification_passed=$true; primary_error=$null; cleanup_errors=@() }
            }
            return [pscustomobject]@{ installation_qualification_passed=$false; primary_error='original activation failure'; cleanup_errors=@('original uninstall failure') }
        }
        $failure = $null
        try { Invoke-CutQuayInstallQualification -PackagePath 'unused' -RecordPath 'unused' -SignToolPath 'unused' -OutputPath $probeRoot | Out-Null }
        catch { $failure = $_.Exception.Message }
        $evidencePath = Join-Path $probeRoot 'installation-qualification.json'
        if (-not (Test-Path -LiteralPath $evidencePath)) { throw "Missing final evidence in $scenario" }
        if ($scenario -eq 'write-failure') {
            if ((Get-Content -LiteralPath $evidencePath -Raw) -ne 'preserve existing evidence' -or $failure -notmatch 'Could not preserve.*original activation failure.*original uninstall failure') { throw 'Evidence write failure lost original errors or replaced previous bytes.' }
            continue
        }
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if ($scenario -eq 'success') {
            if ($failure -or -not $evidence.installation_qualification_passed -or -not $evidence.unsigned_package_unchanged -or $evidence.evidence_errors.Count) { throw 'Unchanged success control did not pass.' }
        } else {
            if (-not $failure -or $evidence.installation_qualification_passed -or $evidence.unsigned_package_unchanged -or $evidence.evidence_errors.Count -ne 1) { throw "Changed/missing source must fail in $scenario" }
            if ($scenario -ne 'changed-after-success' -and ($evidence.primary_error -ne 'original activation failure' -or $evidence.cleanup_errors[0] -ne 'original uninstall failure')) { throw 'Original primary/cleanup failures were lost.' }
        }
    } finally { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
}
Write-Output 'PASS: five real final-hash and exclusive-evidence reporting scenarios.'
