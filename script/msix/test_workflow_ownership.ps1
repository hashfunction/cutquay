# Copyright 2026 Trieflow LLC. MIT. Real helper/owned-process cleanup; Windows adapter mocked.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$script:listeners=@([pscustomobject]@{LocalAddress='127.0.0.1';OwningProcess=731})
function Get-NetTCPConnection {param($State,$LocalPort) if($State -cne 'Listen' -or $LocalPort -ne 8123){throw 'Listener query changed'};return $script:listeners}
Assert-WorkflowListener 8123 731
foreach($rows in @(@([pscustomobject]@{LocalAddress='0.0.0.0';OwningProcess=731}),@([pscustomobject]@{LocalAddress='::';OwningProcess=731}),@([pscustomobject]@{LocalAddress='127.0.0.1';OwningProcess=999}),@([pscustomobject]@{LocalAddress='127.0.0.1';OwningProcess=731},[pscustomobject]@{LocalAddress='0.0.0.0';OwningProcess=731}))) {
 $script:listeners=$rows;$failed=$false;try{Assert-WorkflowListener 8123 731}catch{$failed=$true};if(-not $failed){throw 'Foreign/broad DevTools listener accepted'}
}
$script:listeners=@();$failed=$false;try{Assert-WorkflowListener 8123 731}catch{$failed=$true};if(-not $failed){throw 'Absent listener accepted'}
if((ConvertTo-WorkflowArgument '--config-dir=C:\owned space\config') -cne '"--config-dir=C:\owned space\config"'){throw 'Argument quoting changed'}
foreach($value in @('bad"quote',"bad`nnewline",'trailing\')){$failed=$false;try{ConvertTo-WorkflowArgument $value | Out-Null}catch{$failed=$true};if(-not $failed){throw 'Ambiguous argument accepted'}}
$script:owned=$null;$foreign=$null
function Invoke-CutQuayQualificationCore([Collections.IDictionary]$Operations){
 $captured=$Operations.Preflight.Module.SessionState.PSVariable.GetValue('state');$captured.workflowDriver=$script:owned
 & $Operations.StopOwnedProcess
 throw 'fixture cleanup completed'
}
try {
 $python=@(& python -c 'import sys;print(sys.executable)')[0];if($LASTEXITCODE){throw 'Python fixture unavailable'}
 foreach($label in @('owned','foreign')){$info=[Diagnostics.ProcessStartInfo]::new($python);$info.UseShellExecute=$false;$info.ArgumentList.Add('-c');$info.ArgumentList.Add('import time;time.sleep(30)');$child=[Diagnostics.Process]::Start($info);$null=$child.Handle;if($label -eq 'owned'){$script:owned=$child}else{$foreign=$child}}
 $errorText=$null;try{Invoke-CutQuayInstallQualification unused unused unused unused}catch{$errorText=$_.Exception.Message}
 if($errorText -cne 'fixture cleanup completed' -or -not $script:owned.HasExited -or $foreign.HasExited){throw "Owned driver cleanup boundary failed: $errorText"}
 'PASS: exact loopback/PID listener and argument boundaries; actual owned driver stopped, foreign process preserved.'
}finally{foreach($child in @($script:owned,$foreign)){if($child){if(-not $child.HasExited){$child.Kill();$null=$child.WaitForExit(10000)};$child.Dispose()}}}
