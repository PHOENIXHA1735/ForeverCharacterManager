# No scheduler or collection side effects. Activate one verified Public30 generation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Binding,
    [switch]$DisplayOnly
)
$ErrorActionPreference='Stop'
if(![IO.Path]::IsPathRooted($Python) -or !(Test-Path -LiteralPath $Python -PathType Leaf)){
    throw 'An explicit Python runtime is required.'
}
. (Join-Path $PSScriptRoot 'WriterLease.ps1')
$writerLease=Enter-FCMWriterLease (Split-Path -Parent $PSScriptRoot)
try {
. (Join-Path $PSScriptRoot 'ReferencePublication.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('fcm-public-'+[guid]::NewGuid().ToString('N')+'.lua')
try {
    $arguments=@('-B',(Join-Path $PSScriptRoot 'public_history_stage.py'),'--root',$Root,'--binding',$Binding,'--output',$temp)
    if($DisplayOnly){$arguments+='--display-only'}
    $receipt=& $Python @arguments
    if($LASTEXITCODE){throw 'Could not validate and stage Public30 history.'}
    $receipt=$receipt | ConvertFrom-Json
    if($receipt.sha256 -notmatch '\A[0-9a-f]{64}\z' -or (Get-FileHash -LiteralPath $temp).Hash -ne $receipt.sha256){
        throw 'Public30 stage verification failed.'
    }
    $bytes=[IO.File]::ReadAllBytes($temp)
    $hash=[Security.Cryptography.SHA256]::Create()
    try {$digest=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','')}
    finally {$hash.Dispose()}
    if($digest -ne $receipt.sha256 -or [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -ge [long]$receipt.validUntil){
        throw 'Staged Public30 data changed or expired.'
    }
    Publish-FCMReferenceData -Addon (Split-Path -Parent $PSScriptRoot) -Name 'PublicHistory.generated.lua' -Bytes $bytes
} finally {[IO.File]::Delete($temp)}
} finally { $writerLease.Dispose() }
