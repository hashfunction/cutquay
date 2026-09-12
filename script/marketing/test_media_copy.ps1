# Copyright 2026 Trieflow LLC. MIT. Real exact-byte standalone media-tool copy.
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'capture_helpers.ps1')
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('cut-media-copy-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $temporary|Out-Null
try{
 $source=Join-Path $temporary 'source.exe';$dest=Join-Path $temporary 'tool.exe';[IO.File]::WriteAllBytes($source,[byte[]](0..255));$expected=Get-WorkflowFileRecord $source
 $copy=Copy-MarketingMediaTool $source $dest $expected
 if($copy -cne $dest -or (Get-WorkflowFileRecord $dest).sha256 -cne $expected.sha256){throw 'Copied media tool bytes/path differ'}
 $failed=$false;try{$null=Copy-MarketingMediaTool $source $dest $expected}catch{$failed=$true};if(-not $failed -or (Get-WorkflowFileRecord $dest).sha256 -cne $expected.sha256){throw 'Existing tool copy was replaced'}
 [IO.File]::WriteAllText($source,'changed');$other=Join-Path $temporary 'other.exe';$failed=$false;try{$null=Copy-MarketingMediaTool $source $other $expected}catch{$failed=$true};if(-not $failed -or (Test-Path $other)){throw 'Changed installed source was accepted'}
}finally{Remove-Item -LiteralPath $temporary -Recurse -Force}
'PASS: exact standalone copy, exclusive destination, changed installed source refusal.'
