# Copyright 2026 Trieflow LLC. MIT. Actual process lifetime, adapted identity API results.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'qualify-msix-install.ps1') -LibraryOnly
$script:imageMode='good';$script:packageMode='good'
function Get-CutQuayProcessImageName($Process){
    if($script:imageMode -eq 'failure'){throw [ComponentModel.Win32Exception]::new(31,'fixture image observation failure')}
    if($script:imageMode -eq 'wrong'){return '/foreign/tool.exe'}
    return $Process.StartInfo.FileName
}
function Get-CutQuayProcessPackageName($Process){
    if($script:packageMode -eq 'failure'){throw [ComponentModel.Win32Exception]::new(6,'fixture package observation failure')}
    if($script:packageMode -eq 'wrong'){return 'Foreign.Package'}
    return 'Fixture.Package'
}
$runner=(Get-Process -Id $PID).Path
foreach($case in @('observed-exited','image-unavailable','package-unavailable','both-unavailable','wrong-image-exited','wrong-package-exited','image-failure-live','package-failure-live')){
    $script:imageMode='good';$script:packageMode='good'
    $live=$case.EndsWith('-live')
    $start=[Diagnostics.ProcessStartInfo]::new($runner);$start.UseShellExecute=$false;$start.RedirectStandardOutput=$true
    $body=if($live){'[Console]::WriteLine("ready");Start-Sleep -Seconds 30'}else{'[Console]::WriteLine("ready");exit 0'}
    foreach($arg in @('-NoLogo','-NoProfile','-Command',$body)){$start.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($start);$handle=$process.SafeHandle
    try{
        if($process.StandardOutput.ReadLine() -cne 'ready'){throw 'Real lifetime fixture did not start'}
        if(-not $live -and -not $process.WaitForExit(10000)){throw 'Fixture did not exit'}
        if($case -in @('image-unavailable','both-unavailable','image-failure-live')){$script:imageMode='failure'}
        if($case -in @('package-unavailable','both-unavailable','package-failure-live')){$script:packageMode='failure'}
        if($case -eq 'wrong-image-exited'){$script:imageMode='wrong'}
        if($case -eq 'wrong-package-exited'){$script:packageMode='wrong'}
        $result=$null;$failure=$null
        try{$result=Get-WorkflowProcessIdentity $process $runner 'Fixture.Package'}catch{$failure=$_.Exception.Message}
        $mustFail=$live -or $case.StartsWith('wrong-')
        if([bool]$failure -ne $mustFail){throw "Identity contract result differs: $case / $failure"}
        if($live -and $failure -notmatch 'while the retained process remained running'){throw 'A live API failure was not preserved'}
        if($live -and $failure -notmatch $(if($case.StartsWith('image-')){'native error 31.*fixture image observation failure'}else{'native error 6.*fixture package observation failure'})){throw 'A live API failure lost its actual error code/message'}
        if($case -eq 'wrong-image-exited' -and $failure -notmatch 'differs from installed path'){throw 'A returned image mismatch was not preserved'}
        if($case -eq 'wrong-package-exited' -and $failure -notmatch 'exact installed package identity'){throw 'A returned package mismatch was not preserved'}
        if(-not $mustFail){
            if($result.process_id -ne $process.Id){throw 'Receipt identifies a different process'}
            foreach($kind in @('image','package')){
                $mode=if($kind -eq 'image'){$script:imageMode}else{$script:packageMode}
                $observation=$result[$kind]
                if($mode -eq 'failure'){
                    $code=if($kind -eq 'image'){31}else{6}
                    if($observation.status -cne 'unavailable_after_observed_exit' -or $null -ne $observation.value -or
                        $observation.error.native_error_code -ne $code -or $observation.error.type -cne 'System.ComponentModel.Win32Exception' -or
                        $observation.error.message -cne "fixture $kind observation failure" -or -not $observation.process_exit_observed){throw "Unavailable $kind observation fabricated/lost: $case"}
                }elseif($observation.status -cne 'observed' -or -not $observation.value -or $null -ne $observation.error){throw 'Observed identity was not distinguished'}
            }
        }
        if(-not [object]::ReferenceEquals($handle,$process.SafeHandle) -or $handle.IsClosed){throw 'Original process handle was replaced/closed'}
        "PASS real retained-process observation contract: $case"
    }finally{if(-not $process.HasExited){$process.Kill();$null=$process.WaitForExit(10000)};$process.Dispose()}
}
