# Copyright 2026 Trieflow LLC. MIT. Real entry-point parameter and dot-source scope regression.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$entry=Join-Path $PSScriptRoot 'capture.ps1'
$raw=Get-Content -LiteralPath $entry -Raw
$prefix=$raw.Substring(0,$raw.IndexOf("if(-not `$IsWindows"))
# Execute the actual parameter block/imports and actual output resolution, before
# platform checks and all external mutations. Preserve production PSScriptRoot.
$resolve=($raw -split "`n" | Where-Object {$_ -clike '$outputRoot=*'})
if(@($resolve).Count -ne 1){throw 'Missing unique real output resolution'}
$probe=Join-Path $PSScriptRoot ('.capture-parameters-'+[guid]::NewGuid().ToString('N')+'.ps1')
$expected=Join-Path ([IO.Path]::GetTempPath()) 'cut-capture-test-output'
try{
 [IO.File]::WriteAllText($probe,$prefix+"`n"+$resolve+"`nreturn `$outputRoot")
 $actual=& $probe -Inputs ignored -QualifiedSource ignored -Output $expected
 if($actual -cne [IO.Path]::GetFullPath($expected)){throw 'Entry point helper imports changed the requested output directory'}
}finally{Remove-Item -LiteralPath $probe -ErrorAction SilentlyContinue}
'PASS: actual capture parameters survive production helper imports; no Windows mutation executed.'
