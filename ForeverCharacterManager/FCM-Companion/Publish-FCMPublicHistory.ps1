# No scheduler or collection side effects. Activate one verified Public30 generation.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Binding,
    [string[]]$Archive = @(),
    [string]$LocalHistoryConfig,
    [switch]$DisplayOnly
)
$ErrorActionPreference='Stop'
if(![IO.Path]::IsPathRooted($Python) -or !(Test-Path -LiteralPath $Python -PathType Leaf)){
    throw 'An explicit Python runtime is required.'
}
. (Join-Path $PSScriptRoot 'WriterLease.ps1')
$addon=Split-Path -Parent $PSScriptRoot
$publicFailed=$false
try {
    $writerLease=Enter-FCMWriterLease $addon
    try {
        $arguments=@('-B',(Join-Path $PSScriptRoot 'public_history_publication.py'),
            '--root',$Root,'--binding',$Binding,'--addon',$addon)
        if($DisplayOnly){$arguments+='--display-only'}
        foreach($path in $Archive){$arguments+=@('--archive',$path)}
        & $Python @arguments
        if($LASTEXITCODE){throw 'Could not publish confirmed Public30 history.'}
    } finally { $writerLease.Dispose() }
} catch {
    $publicFailed=$true
    Write-Warning 'Public30 publication did not complete.'
}

$privateFailed=$false
if($LocalHistoryConfig){
    & $Python -B (Join-Path $PSScriptRoot 'local_history_import.py') --config $LocalHistoryConfig --public-root $Root --addon $addon
    $privateFailed=$LASTEXITCODE -ne 0
}
if($publicFailed -or $privateFailed){throw 'One or more configured history workflows did not complete.'}