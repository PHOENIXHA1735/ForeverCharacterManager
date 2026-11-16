# FCM v0.9.1 R6.1 cleanup, auto-detecting installer. PowerShell 5.1.
# Merge only; preserves character SavedVariables, user data, and companion files.
[CmdletBinding()]
param([string]$AddOnsPath)
$ErrorActionPreference = 'Stop'

# Only accept a directory that already contains this addon's manifest. A
# similarly named folder for another WoW installation cannot pass the check.
function Resolve-FCMAddOnsPath([string]$Candidate) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
    $clean = $Candidate.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $clean -PathType Container)) { return $null }
    $full = (Resolve-Path -LiteralPath $clean).ProviderPath
    if ((Split-Path -Path $full -Leaf) -ine 'AddOns') { return $null }
    if ((Split-Path -Path (Split-Path -Path $full -Parent) -Leaf) -ine 'Interface') { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $full 'ForeverCharacterManager\ForeverCharacterManager.toc') -PathType Leaf)) {
        return $null
    }
    return $full
}

try {
    $package = Join-Path $PSScriptRoot 'ForeverCharacterManager'
    if (-not (Test-Path -LiteralPath (Join-Path $package 'ForeverCharacterManager.toc') -PathType Leaf)) {
        throw 'Extract the entire ZIP before running the installer.'
    }
    Write-Host ''
    Write-Host 'FCM R6.1 - Inventory/Vendor/Binding Cleanup Test Candidate' -ForegroundColor Cyan
    Write-Host 'Close World of Warcraft before continuing.'

    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'Cannot locate the backup folder. No changes made.'
    }
    $rememberDirectory = Join-Path $localData 'FCM-Installer'
    $rememberFile = Join-Path $rememberDirectory 'AddOnsPath.txt'

    if ([string]::IsNullOrWhiteSpace($AddOnsPath)) {
        $candidates = @()
        $rememberedValid = $null
        if (Test-Path -LiteralPath $rememberFile -PathType Leaf) {
            try {
                $remembered = (Get-Content -LiteralPath $rememberFile -Raw -Encoding UTF8).Trim()
                $candidates += $remembered
                $rememberedValid = Resolve-FCMAddOnsPath $remembered
            }
            catch { Write-Host 'Saved AddOns path could not be read; checking known locations.' }
        }
        # B's confirmed WoW Forever path is first on a fresh install.
        $candidates += 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
        # Also handle the same game on another drive or a common Games folder.
        foreach ($drive in @(Get-PSDrive -PSProvider FileSystem)) {
            foreach ($suffix in @(
                'Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns',
                'Program Files\World of Warcraft\_forever_\Interface\AddOns',
                'World of Warcraft\_forever_\Interface\AddOns',
                'Games\World of Warcraft\_forever_\Interface\AddOns'
            )) {
                $candidates += (Join-Path $drive.Root $suffix)
            }
        }
        $validPaths = @()
        foreach ($candidate in $candidates) {
            $valid = Resolve-FCMAddOnsPath $candidate
            if ($valid -and ($validPaths -notcontains $valid)) { $validPaths += $valid }
        }
        if ($rememberedValid) {
            $AddOnsPath = $rememberedValid
            Write-Host 'Using your last successful FCM installation location.' -ForegroundColor Green
        } elseif ($validPaths.Count -eq 1) {
            $AddOnsPath = $validPaths[0]
            Write-Host 'Found your existing FCM installation automatically.' -ForegroundColor Green
        } elseif ($validPaths.Count -gt 1) {
            Write-Host 'Several valid WoW Forever addon folders were found:' -ForegroundColor Yellow
            for ($i=0; $i -lt $validPaths.Count; $i++) {
                Write-Host ('  ' + ($i+1) + '. ' + $validPaths[$i])
            }
            $selection = Read-Host 'Enter the number of the correct installation (or paste its full AddOns path)'
            $choiceNumber = 0
            if ([int]::TryParse($selection, [ref]$choiceNumber) -and
                $choiceNumber -ge 1 -and $choiceNumber -le $validPaths.Count) {
                $AddOnsPath = $validPaths[$choiceNumber-1]
            } else {
                $AddOnsPath = $selection
            }
        } else {
            $AddOnsPath = Read-Host 'Could not find FCM automatically. Paste the FULL Interface\AddOns path (one time)'
        }
    }
    $resolved = Resolve-FCMAddOnsPath $AddOnsPath
    if (-not $resolved) { throw 'That path is not a valid Interface\AddOns folder with FCM installed; no changes were made.' }
    $target = Join-Path $resolved 'ForeverCharacterManager'
    $updates = @()
    $skipped = @()
    $files = @(Get-ChildItem -LiteralPath $package -File -Recurse | Sort-Object FullName)
    foreach ($file in $files) {
        if (@('.lua', '.toc', '.png', '.tga') -notcontains $file.Extension.ToLowerInvariant()) {
            throw ('Unexpected file in package: ' + $file.Name)
        }
        $relative = $file.FullName.Substring($package.Length + 1)
        if ($relative -match '(^|[\\/])FCM-Companion[\\/]') {
            throw 'Companion scripts must not be overwritten by this addon update.'
        }
        $destination = Join-Path $target $relative
        if ($file.Name -like '*.generated.lua' -and
            (Test-Path -LiteralPath $destination -PathType Leaf)) {
            # Companion/gathering exports are user-owned runtime snapshots.
            # Never replace a newer local export with the test ZIP's copy.
            $skipped += $relative
            continue
        }
        $updates += [PSCustomObject]@{
            Source = $file.FullName
            Destination = $destination
            Relative = $relative
            AlreadyExists = (Test-Path -LiteralPath $destination -PathType Leaf)
        }
    }
    if ($updates.Count -lt 20) { throw 'Package incomplete; no changes made.' }
    Write-Host ('Destination: ' + $target)
    Write-Host ('Files to merge: ' + $updates.Count)
    Write-Host ('Existing generated data files preserved: ' + $skipped.Count)
    Write-Host 'Preserved: SavedVariables, user-generated data, companion scripts, other addons.'
    $answer = Read-Host 'Type INSTALL to back up and merge the R6.1 files (anything else cancels)'
    if ($answer -cne 'INSTALL') {
        Write-Host 'Cancelled. No files changed.'
        exit 0
    }
    $backup = Join-Path (Join-Path $localData 'FCM-Backups') ('R61-Cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    # Finish all existing-target backups before copying any package files.
    foreach ($item in $updates) {
        if ($item.AlreadyExists) {
            $backupFile = Join-Path $backup $item.Relative
            New-Item -ItemType Directory -Path (Split-Path -Path $backupFile -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $item.Destination -Destination $backupFile -ErrorAction Stop
        }
    }
    Write-Host ('Backup: ' + $backup)
    foreach ($item in $updates) {
        $destinationParent = Split-Path -Path $item.Destination -Parent
        if (-not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force -ErrorAction Stop
        $expected = (Get-FileHash -LiteralPath $item.Source -Algorithm SHA256).Hash
        $actual = (Get-FileHash -LiteralPath $item.Destination -Algorithm SHA256).Hash
        if ($expected -ne $actual) { throw ('Hash verification failed: ' + $item.Relative) }
    }
    Write-Host ''
    Write-Host ('SUCCESS: merged and verified ' + $updates.Count + ' addon files.') -ForegroundColor Green
    Write-Host ('Recovery backup: ' + $backup)
    try {
        if (-not (Test-Path -LiteralPath $rememberDirectory -PathType Container)) {
            New-Item -Path $rememberDirectory -ItemType Directory -Force | Out-Null
        }
        Set-Content -LiteralPath $rememberFile -Value $resolved -Encoding UTF8 -ErrorAction Stop
        Write-Host 'Remembered this AddOns location for future FCM installers.'
    } catch {
        Write-Host 'Could not remember the path, but this installation succeeded.' -ForegroundColor Yellow
    }
    Write-Host 'Reopen WoW. Search Inventory for Clam Meat and check the empty-result help.'
    Write-Host 'Inspect Fine Thread in Shopping and the Requests material plan for vendor guidance.'
    Write-Host 'Check the existing 2x Barbaric Linen Vest request is still present and unassigned.'
    Write-Host 'Keep live soulbound-material transfer QA OPEN until observed in game.'
} catch {
    Write-Host ('FCM R6.1 INSTALL FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'No deletion was performed. If a copy failed partway through, restore from the reported backup.'
    exit 1
}
