# FCM GitHub releases updater v0.8.8. Public repo only; no user credentials
# and no client data are sent to GitHub. Updates require explicit confirmation.
$script:FCMRepo='PHOENIXHA1735/ForeverCharacterManager'
$script:FCMRepoUrl='https://github.com/PHOENIXHA1735/ForeverCharacterManager'
$script:FCMGitHubApi='https://api.github.com/repos/PHOENIXHA1735/ForeverCharacterManager/releases/latest'
$script:FCMInstalledVersion=[version]'0.8.8'
$script:LatestFCMRelease=$null
$script:LatestFCMAsset=$null

function Get-FCMInstalledVersion {
    # Read the actual installed TOC instead of trusting the companion's own version.
    # This matters if the companion is launched from Downloads or after rollback.
    try {
        if (-not $script:gameBox -or [string]::IsNullOrWhiteSpace($script:gameBox.Text)) { return [version]'0.0.0' }
        $path=Join-Path ($script:gameBox.Text.Trim()) 'Interface\AddOns\ForeverCharacterManager\ForeverCharacterManager.toc'
        if (-not (Test-Path -LiteralPath $path)) { return [version]'0.0.0' }
        $toc=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ($toc -match '(?m)^## Version:\s*(\d+\.\d+\.\d+)\s*$') { return [version]$Matches[1] }
    } catch { }
    return [version]'0.0.0'
}
function Write-FCMUpdateReadiness {
    $script:FCMInstalledVersion=Get-FCMInstalledVersion
    $root=if ($script:gameBox) { [string]$script:gameBox.Text.Trim() } else { '' }
    if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root 'Interface\AddOns'))) {
        Log 'UPDATE READINESS: Select a valid WoW Forever folder before checking GitHub releases.'
        return
    }
    $backupRoot=Join-Path $root 'FCM-Backups'
    $backupCount=0
    if (Test-Path -LiteralPath $backupRoot) {
        $backupCount=@(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue).Count
    }
    $reference=Join-Path $root 'Interface\AddOns\ForeverCharacterManager\ExternalData.generated.lua'
    Log ("UPDATE READINESS: installed addon v$($script:FCMInstalledVersion); backups $backupCount; local reference file " + $(if (Test-Path -LiteralPath $reference) {'present'} else {'not yet generated'}))
    if ($script:FCMInstalledVersion -eq [version]'0.0.0') { Log 'No installed FCM TOC was detected in the selected WoW Forever folder.' }
}
function Get-FCMLatestGitHubRelease {
    Write-FCMUpdateReadiness
    if ($script:statusLabel) {$script:statusLabel.Text='Checking GitHub...'}
    $script:LatestFCMRelease=$null
    $script:LatestFCMAsset=$null
    if ($script:githubUpdateButton) {$script:githubUpdateButton.Enabled=$false}
    $headers=@{'Accept'='application/vnd.github+json';'User-Agent'='ForeverCharacterManagerCompanion/0.8.8'}
    try { $release=Invoke-FcmHttpJson $script:FCMGitHubApi $headers }
    catch {
        $status=Get-FcmHttpStatus $_
        if ($status -eq 404) {
            Log 'No public GitHub Release is published yet. A repository alone does not enable distribution.'
            return
        }
        Log ('GitHub release check could not complete: HTTP '+$status+' or network error. Confirm internet access and the GitHub releases page.')
        return
    }
    if ($release.draft -eq $true -or $release.prerelease -eq $true) {
        Log 'Latest GitHub release is not a stable published release.'
        return
    }
    $tag=[string]$release.tag_name
    if ($tag -notmatch '^v?(\d+\.\d+\.\d+)$') {Log 'Unrecognized GitHub release version. No update offered.';return}
    $remote=[version]$Matches[1]
    if ($remote -le $script:FCMInstalledVersion) {
        Log ("FCM is up to date: local $($script:FCMInstalledVersion), published $remote.")
        return
    }
    $selected=$null
    foreach ($a in @($release.assets)) {
        $name=[string]$a.name
        if ($a.state -eq 'uploaded' -and
                $name -match '^ForeverCharacterManager_v\d+\.\d+\.\d+_FULL[A-Za-z0-9_.-]*\.zip$' -and
                $name -match ('^ForeverCharacterManager_v'+[regex]::Escape($remote.ToString())+'_')) {
            $selected=$a;break
        }
    }
    if (-not $selected) {
        # Exact short-name fallback, still subject to SHA-256 and archive verification.
        foreach ($a in @($release.assets)) {
            if ($a.state -eq 'uploaded' -and [string]$a.name -eq ('FCM-v'+$remote.ToString()+'.zip')) {
                $selected=$a;break
            }
        }
    }
    if (-not $selected) {
        Log "Release $remote found, but no matching full-package ZIP asset was attached."
        return
    }
    $url=[string]$selected.browser_download_url
    $prefix=$script:FCMRepoUrl+'/releases/download/'
    if (-not $url.StartsWith($prefix,[StringComparison]::Ordinal) -or $url.Contains('?')) {
        Log 'Release download URL did not match the trusted repository. Update blocked.';return
    }
    $script:LatestFCMRelease=$release
    $script:LatestFCMAsset=$selected
    $script:FCMAvailableVersion=$remote
    Log ("FCM v$remote is available (installed v$($script:FCMInstalledVersion)). Press Install GitHub Update to apply after backup.")
    if ($script:githubUpdateButton) { $script:githubUpdateButton.Enabled=$true }
}
function Get-FCMTrustedAssetBytes([string]$url,[int]$maximumBytes) {
    if (-not $url.StartsWith(($script:FCMRepoUrl+'/releases/download/'),[StringComparison]::Ordinal)) {
        throw 'Release asset URL is not from the approved FCM repository.'
    }
    $req=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get,[Uri]$url)
    [void]$req.Headers.TryAddWithoutValidation('User-Agent','ForeverCharacterManagerCompanion/0.8.8')
    $cts=[System.Threading.CancellationTokenSource]::new()
    $cts.CancelAfter(28000)
    $res=$null
    try {
        $pending=$script:HttpClient.SendAsync($req,[System.Net.Http.HttpCompletionOption]::ResponseContentRead,$cts.Token)
        while (-not $pending.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            [System.Threading.Thread]::Sleep(35)
        }
        $res=$pending.GetAwaiter().GetResult()
        if (-not $res.IsSuccessStatusCode) {throw ('Release asset download HTTP '+[int]$res.StatusCode)}
        if ($res.Content.Headers.ContentLength -and $res.Content.Headers.ContentLength.Value -gt $maximumBytes) {
            throw 'Release asset exceeds the 15 MB download limit.'
        }
        $bytes=$res.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        if (-not $bytes -or $bytes.Length -gt $maximumBytes) {throw 'Release asset is empty or exceeds the size limit.'}
        return ,$bytes
    } finally {
        if ($res) {$res.Dispose()}
        $cts.Dispose();$req.Dispose()
    }
}
function Test-FCMReleaseHash([byte[]]$bytes,$release,$asset) {
    # Prefer GitHub's SHA-256 digest. A companion .sha256 file is also supported
    # for releases published by clients that don't expose asset.digest.
    $expected=''
    $digest=[string]$asset.digest
    if ($digest -match '^sha256:([a-fA-F0-9]{64})$') { $expected=$Matches[1].ToLowerInvariant() }
    if (-not $expected) {
        $sidecarName=([string]$asset.name)+'.sha256'
        foreach ($candidate in @($release.assets)) {
            if ([string]$candidate.name -eq $sidecarName) {
                $content=Get-FCMTrustedAssetBytes ([string]$candidate.browser_download_url) 4096
                $sidecar=[Text.Encoding]::UTF8.GetString($content)
                if ($sidecar -match '^\s*([a-fA-F0-9]{64})\b') { $expected=$Matches[1].ToLowerInvariant() }
                break
            }
        }
    }
    if (-not $expected) {throw 'Release has no SHA-256 digest or valid .sha256 sidecar; update blocked.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $actual=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally {$sha.Dispose()}
    if ($actual -ne $expected) {throw 'Release ZIP hash mismatch; update blocked.'}
    Log 'Verified downloaded ZIP against SHA-256 digest.'
}
function Expand-FCMTrustedRelease([string]$zipFile,[string]$root,[version]$expectedVersion) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($zipFile)
    $total=[long]0
    $count=0
    try {
        foreach ($entry in $archive.Entries) {
            $name=$entry.FullName.Replace('\','/')
            if ($name.EndsWith('/')) {continue}
            # Validate every non-directory entry before choosing whether to
            # extract it. Tests and root-level docs ship with the release,
            # but are not needed inside the installed WoW AddOns folder.
            if ($name.Contains('..') -or $name.Contains(':') -or
                    $name.StartsWith('/') -or $name.StartsWith('./')) {
                throw ("Unsafe release archive entry path: " + $name)
            }
            if ($name -match '^[A-Za-z0-9_.-]+$') {continue}
            if ($name -match '^tests/[A-Za-z0-9_.-]+\.lua$') {continue}
            if ($name -notmatch '^ForeverCharacterManager/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+$') {
                throw ("Unexpected archive entry path: " + $name)
            }
            $total += $entry.Length
            $count++
            if ($total -gt 30000000 -or $count -gt 160) {throw 'Release archive exceeded safety limits.'}
            $target=Join-Path $root ($name.Replace('/',[IO.Path]::DirectorySeparatorChar))
            $parent=Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
        }
    } finally {$archive.Dispose()}
    $source=Join-Path $root 'ForeverCharacterManager'
    foreach ($required in @('ForeverCharacterManager.toc','Core.lua','UI.lua','FCM-Companion\FCMDataUpdater.ps1','FCM-Companion\GitHubUpdates.ps1','Media\FCM_Emblem.tga')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $required))) {throw "Full release missing required file: $required"}
    }
    $toc=Get-Content -LiteralPath (Join-Path $source 'ForeverCharacterManager.toc') -Raw
    if ($toc -notmatch '(?m)^## Version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$') {throw 'Release TOC does not declare a parseable version.'}
    if ([version]$Matches[1] -ne $expectedVersion) {throw 'Release TOC version does not match the GitHub release tag.'}
    return $source
}
function Copy-FCMReleaseCode([string]$source,[string]$destination) {
    if (-not (Test-Path -LiteralPath $destination)) {New-Item -ItemType Directory -Path $destination -Force | Out-Null}
    foreach ($file in @(Get-ChildItem -LiteralPath $source -File)) {
        if ($file.Name -eq 'ExternalData.generated.lua') {continue}
        if ($file.Extension -notin @('.lua','.toc')) {continue}
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $destination $file.Name) -Force
    }
    $fromMedia=Join-Path $source 'Media'; $toMedia=Join-Path $destination 'Media'
    if (Test-Path -LiteralPath $fromMedia) {
        if (-not (Test-Path -LiteralPath $toMedia)) {New-Item -ItemType Directory -Path $toMedia -Force | Out-Null}
        foreach ($file in @(Get-ChildItem -LiteralPath $fromMedia -File)) {
            if ($file.Extension -in @('.tga','.png')) {Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $toMedia $file.Name) -Force}
        }
    }
    $fromComp=Join-Path $source 'FCM-Companion';$toComp=Join-Path $destination 'FCM-Companion'
    if (-not (Test-Path -LiteralPath $toComp)) {New-Item -ItemType Directory -Path $toComp -Force | Out-Null}
    foreach ($name in @('FCMDataUpdater.ps1','ForeverDB.Provider.ps1','GitHubUpdates.ps1','OPEN-FCM-DATA-UPDATER.cmd','ABOUT_DATA_SOURCES.txt','ExternalData.generated.template.lua')) {
        $file=Join-Path $fromComp $name
        if (Test-Path -LiteralPath $file) {Copy-Item -LiteralPath $file -Destination (Join-Path $toComp $name) -Force}
    }
    # settings.json, reference-cache.json, ForeverDB DPAPI key, reports and
    # ExternalData.generated.lua are never copied or overwritten here.
}
function New-FCMBackup([string]$installed) {
    $backupRoot=Join-Path ($script:gameBox.Text.Trim()) 'FCM-Backups'
    $path=Join-Path $backupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    $dir=Join-Path $path 'ForeverCharacterManager'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    # Back up ONLY static application code and artwork. Do not duplicate
    # settings.json, DPAPI credentials, reference-cache.json or player data.
    Copy-FCMReleaseCode $installed $dir
    return $dir
}
function Install-FCMLatestGitHubRelease {
    if (Game-Is-Running) {throw 'Exit WoW completely before updating FCM.'}
    if (-not $script:LatestFCMRelease -or -not $script:LatestFCMAsset) {throw 'Check GitHub for an available release first.'}
    $dest=Target-Addon
    if ($script:statusLabel) {$script:statusLabel.Text='Updating...'}
    $version=$script:FCMAvailableVersion
    $confirmation=[System.Windows.Forms.MessageBox]::Show(
        "Install FCM v$version from the official GitHub repository?`n`nThe companion will verify the download, back up the current addon, and preserve locally stored character and reference data.",
        'Confirm FCM update',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {Log 'GitHub update was declined.';return}
    $tmp=Join-Path ([IO.Path]::GetTempPath()) ('FCMRelease-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $backup=''
    try {
        $archiveBytes=Get-FCMTrustedAssetBytes ([string]$script:LatestFCMAsset.browser_download_url) 15000000
        Test-FCMReleaseHash $archiveBytes $script:LatestFCMRelease $script:LatestFCMAsset
        $zip=Join-Path $tmp 'release.zip'
        [IO.File]::WriteAllBytes($zip,$archiveBytes)
        $src=Expand-FCMTrustedRelease $zip $tmp $version
        if (-not (Test-Path -LiteralPath $dest)) {throw 'Current addon folder not found; install a full FCM package manually first.'}
        $backup=New-FCMBackup $dest
        Log ('Local addon backup created outside AddOns: '+$backup)
        try {Copy-FCMReleaseCode $src $dest}
        catch {
            Log 'Update copy failed. Attempting to restore previous code from backup.'
            if ($backup) {Copy-FCMReleaseCode $backup $dest}
            throw
        }
        $script:FCMInstalledVersion=Get-FCMInstalledVersion
        if ($script:FCMInstalledVersion -ne $version) { throw 'Installed TOC version mismatch after update; use Restore FCM Backup.' }
        $script:LatestFCMAsset=$null
        Log "FCM v$version installed. Close and reopen the companion, then restart WoW."
        [System.Windows.Forms.MessageBox]::Show(
            "FCM v$version is installed. Restart this companion and WoW to load the new version.",
            'FCM update complete',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function Restore-FCMLatestBackup {
    if (Game-Is-Running) {throw 'Exit WoW completely before restoring a backup.'}
    $root=Join-Path ($script:gameBox.Text.Trim()) 'FCM-Backups'
    if (-not (Test-Path -LiteralPath $root)) {throw 'No local FCM update backup exists.'}
    $candidates=@(Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name -Descending)
    $source=$null
    foreach ($candidate in $candidates) {
        $path=Join-Path $candidate.FullName 'ForeverCharacterManager'
        if (Test-Path -LiteralPath (Join-Path $path 'ForeverCharacterManager.toc')) {$source=$path;break}
    }
    if (-not $source) {throw 'No valid FCM backup found.'}
    $response=[System.Windows.Forms.MessageBox]::Show(
        "Restore the latest FCM code backup?`n`nCharacter records, API key, current reference cache, and generated data will be kept.",
        'Confirm rollback',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($response -ne [System.Windows.Forms.DialogResult]::Yes) {return}
    Copy-FCMReleaseCode $source (Target-Addon)
    $script:FCMInstalledVersion=Get-FCMInstalledVersion
    $script:LatestFCMRelease=$null
    $script:LatestFCMAsset=$null
    if ($script:githubUpdateButton) {$script:githubUpdateButton.Enabled=$false}
    Log ('Restored addon v'+$script:FCMInstalledVersion+' files from '+$source+'. Restart WoW and the companion.')
}
