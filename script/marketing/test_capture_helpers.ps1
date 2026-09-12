$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_helpers.ps1')
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message}}
$plan=Get-MarketingWindowPlan @{X=0;Y=0;Width=1920;Height=1040}
Check ($plan.width -eq 1472 -and $plan.height -eq 1000 -and $plan.x -ge 0 -and $plan.y -ge 0) 'Native window plan does not fit the actual display.'
foreach($bounds in @(@{X=0;Y=0;Width=1024;Height=768},@{X=0;Y=0;Width=1920;Height=900})){
    $rejected=$false;try{$null=Get-MarketingWindowPlan $bounds}catch{$rejected=$true};Check $rejected 'Insufficient native display was accepted.'
}
function Get-AppxPackage {param($Name) @([pscustomobject]@{PackageFullName='1659hashfunction.CutQuay_1.0.0.0_x64__r3hxytd7jt6c4'})}
function Remove-AppxPackage {param($Package) throw 'Unowned package removal attempted.'}
$state=@{ownedProcesses=[Collections.Generic.List[Diagnostics.Process]]::new();workflowDriver=$null;mediaProcess=$null;installed=$null;
    installAttempted=$true;installedByUs=$false;ownedPackageFullName=$null;certificate=$null;trustAttempted=$false;
    temporary=$null;workOwned=$false;work=$null;residualPackageFullNames=@();cleanupErrors=[Collections.Generic.List[string]]::new()}
Complete-MarketingCleanup $state
Check ($state.cleanupErrors.Count -eq 1 -and $state.cleanupErrors[0] -match 'preserved' -and $state.residualPackageFullNames.Count -eq 1) 'Failed Add residue was removed or hidden.'
$info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$info.UseShellExecute=$false
foreach($arg in @('-NoLogo','-NoProfile','-Command','Start-Sleep -Seconds 30')){$info.ArgumentList.Add($arg)}
$child=[Diagnostics.Process]::Start($info);$null=$child.Handle
try{
    $state.installAttempted=$false;$state.ownedProcesses.Add($child);$state.cleanupErrors.Clear()
    function Update-OwnedPackageProcesses {param($State) throw 'Injected secondary process enumeration failure.'}
    $state.installed=@{PackageFullName='owned'}
    Complete-MarketingCleanup $state
    Check ($child.WaitForExit(5000) -and $state.cleanupErrors.Count -eq 1 -and $state.cleanupErrors[0] -match 'enumeration failure') 'Secondary enumeration failure prevented retained owned process cleanup.'
}finally{if(-not $child.HasExited){$child.Kill()};$child.Dispose()}
Write-Output 'PASS: actual display constraints, failed-Add ownership preservation, retained process cleanup.'
