$ErrorActionPreference='Stop'
$companion=Join-Path (Split-Path -Parent $PSScriptRoot) 'ForeverCharacterManager/FCM-Companion'
$messages=[Collections.Generic.List[string]]::new()
function Log([string]$Message) { $messages.Add($Message) }
function Target-Addon { throw 'Disabled handler must not resolve a target.' }
foreach ($name in @('FCMDataUpdater.ps1','GitHubUpdates.ps1')) {
    $errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $companion $name),[ref]$null,[ref]$errors)
    if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
    $source=[IO.File]::ReadAllText((Join-Path $companion $name))
    if ($source -match '(?im)github(?:Update|Restore)Button\.Enabled\s*=\s*(?!\$false\b)\S') {
        throw 'Legacy companion install or restore action can be enabled.'
    }
}
. (Join-Path $companion 'GitHubUpdates.ps1')
Install-FCMLatestGitHubRelease
Restore-FCMLatestBackup
if ($messages.Count -ne 2 -or ($messages -notmatch 'disabled').Count) {
    throw 'Expected actionable disabled messages from both handlers.'
}
'PASS: legacy install and restore handlers are disabled'
