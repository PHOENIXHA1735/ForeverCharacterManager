# Creates the FCM-owned scan archive folders. Does not copy, parse, schedule,
# delete, or alter AHledger data. Compatible with Windows PowerShell 5.1.
[CmdletBinding()]
param(
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
)
$ErrorActionPreference = 'Stop'

$folders = @(
    'Incoming',
    'RawScans',
    'Parsed',
    'Index',
    'Reports\Daily',
    'Reports\Weekly',
    'Reports\Monthly',
    'Logs',
    'Quarantine'
)

try {
    if (-not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
        throw ('AddOns folder does not exist: ' + $AddOnsPath)
    }
    $resolved = (Resolve-Path -LiteralPath $AddOnsPath).ProviderPath
    if ((Split-Path -Path $resolved -Leaf) -ine 'AddOns' -or
        (Split-Path -Path (Split-Path -Path $resolved -Parent) -Leaf) -ine 'Interface') {
        throw 'The selected path must end with Interface\AddOns.'
    }
    $addonRoot = Join-Path $resolved 'ForeverCharacterManager'
    if (-not (Test-Path -LiteralPath (Join-Path $addonRoot 'ForeverCharacterManager.toc') -PathType Leaf)) {
        throw 'The FCM addon manifest was not found. Install FCM first.'
    }
    $historyRoot = Join-Path $addonRoot 'AHHistory'

    # Refuse junctions/symlinks so a mistaken link cannot lead outside FCM.
    $pathsToCheck = @($addonRoot, $historyRoot, (Join-Path $historyRoot 'Reports'))
    foreach ($subfolder in $folders) { $pathsToCheck += (Join-Path $historyRoot $subfolder) }
    foreach ($pathToCheck in $pathsToCheck) {
        if (Test-Path -LiteralPath $pathToCheck) {
            $entry = Get-Item -LiteralPath $pathToCheck -Force
            if (-not $entry.PSIsContainer) { throw ('Expected a folder, found a file: ' + $pathToCheck) }
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw ('Linked folders are not supported for the FCM archive: ' + $pathToCheck)
            }
        }
    }

    if (-not (Test-Path -LiteralPath $historyRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $historyRoot -ErrorAction Stop | Out-Null
    }
    foreach ($subfolder in $folders) {
        $newFolder = Join-Path $historyRoot $subfolder
        if (-not (Test-Path -LiteralPath $newFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $newFolder -Force -ErrorAction Stop | Out-Null
        }
    }
    Write-Host ''
    Write-Host 'FCM AH scan archive folders are ready.' -ForegroundColor Green
    Write-Host ('Location: ' + $historyRoot) -ForegroundColor Cyan
    Get-ChildItem -LiteralPath $historyRoot -Directory -Recurse |
        Sort-Object FullName | Select-Object -ExpandProperty FullName |
        ForEach-Object { Write-Host ('  ' + $_) }
    Write-Host ''
    Write-Host 'No scan data copied. No scheduled task installed. No cleanup or backup enabled.'
    Write-Host 'Personal scan archives stay private.'
    Write-Host 'Provider tables require explicit personal retention permission; never redistribute them.'
} catch {
    Write-Host ('Folder setup failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'If access was denied under Program Files, run the .cmd file as Administrator.'
    exit 1
}
