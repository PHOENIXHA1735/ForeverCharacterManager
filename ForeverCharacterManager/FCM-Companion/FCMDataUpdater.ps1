# Forever Character Manager - Windows Data Companion v0.9.0
# Open-source PowerShell 5.1 Windows Forms tool; no installation, modules, or
# administrator privileges required. Internet requests are GET only.
# Reads FCM's SavedVariables locally for item IDs. Never uploads them.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http
[System.Windows.Forms.Application]::EnableVisualStyles()
$ErrorActionPreference = 'Stop'
$script:Base = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ConfigPath = Join-Path $script:Base 'settings.json'
$script:CachePath = Join-Path $script:Base 'reference-cache.json'
$script:ReportPath = Join-Path $script:Base 'last-sync-report.json'
$script:OperationRunning = $false
$script:ScanRunning = $false
$script:FcmLastHttpDailyRemaining = $null
$script:FcmLastHttpRetryAfter = $null
$script:CancelRequested = $false
$script:ActiveRequestCancellation = $null
# HttpClient requests execute asynchronously while the WinForms event loop stays
# responsive. Each network request has its own 25-second cancellation token.
# No background worker is allowed to modify the cache or SavedVariables.
$script:HttpHandler = [System.Net.Http.HttpClientHandler]::new()
$script:HttpHandler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$script:HttpClient = [System.Net.Http.HttpClient]::new($script:HttpHandler)
$script:HttpClient.Timeout = [TimeSpan]::FromSeconds(28)
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

# Detect both supported layouts:
#  1) FCM-Companion and ForeverCharacterManager as siblings
#  2) FCM-Companion nested inside the already installed ForeverCharacterManager
$script:PackageRoot = Split-Path -Parent $script:Base
$script:SourceAddon = Join-Path $script:PackageRoot 'ForeverCharacterManager'
if (Test-Path -LiteralPath (Join-Path $script:PackageRoot 'ForeverCharacterManager.toc')) {
    $script:SourceAddon = $script:PackageRoot
}
$script:ItemCache = @{}
$script:RecipeCache = @{}
$script:PriceCache = @{}
$script:Config = @{ gameRoot=''; terms='Raw Brilliant Smallfish'; market='forever.normal.alliance.us'; autoSync=$true; autoUpdateCheck=$true; lastSync=''; fdbItemOffset=0; fdbDungeonOffset=0 }

# Optional ForeverDB provider: loaded as a source file, not executed as web content.
. (Join-Path $script:Base 'ForeverDB.Provider.ps1')
. (Join-Path $script:Base 'ReferenceAudit.ps1')
. (Join-Path $script:Base 'GitHubUpdates.ps1')

function Get-Config {
    if (Test-Path -LiteralPath $script:ConfigPath) {
        try {
            $o = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json
            foreach ($prop in $o.PSObject.Properties) {
                if ($prop.Name -in @('gameRoot','terms','market','autoSync','autoUpdateCheck','lastSync') -or $prop.Name -match '^fdb[A-Za-z0-9_]+$') {
                    if ($null -ne $prop.Value) { $script:Config[$prop.Name] = $prop.Value }
                }
            }
        } catch { }
    }
    if (Test-Path -LiteralPath $script:CachePath) {
        try {
            $obj = Get-Content -LiteralPath $script:CachePath -Raw | ConvertFrom-Json
            if ($obj.items) { foreach ($p in $obj.items.PSObject.Properties) { $script:ItemCache[$p.Name] = $p.Value } }
            if ($obj.recipes) { foreach ($p in $obj.recipes.PSObject.Properties) { $script:RecipeCache[$p.Name] = $p.Value } }
            if ($obj.prices) {
                foreach ($p in $obj.prices.PSObject.Properties) {
                    # Migrate v0.7.3 flat price cache without losing its market.
                    $cacheKey = [string]$p.Name
                    if ($cacheKey -match '^\d+$' -and $p.Value.market) {
                        $cacheKey = ([string]$p.Value.market) + '|' + $cacheKey
                    }
                    $script:PriceCache[$cacheKey] = $p.Value
                }
            }
            if ($obj.dungeons) { foreach ($p in $obj.dungeons.PSObject.Properties) { $script:DungeonCache[$p.Name] = $p.Value } }
        } catch { }
    }
}
function Save-Config {
    $script:Config.gameRoot = $script:gameBox.Text.Trim()
    $script:Config.terms = $script:termsBox.Text.Trim()
    $script:Config.market = [string]$script:marketBox.SelectedItem
    $script:Config.autoSync = [bool]$script:autoBox.Checked
    if ($script:checkUpdatesBox) {$script:Config.autoUpdateCheck=[bool]$script:checkUpdatesBox.Checked}
    $script:Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}
function Log([string]$message) {
    $stamp = Get-Date -Format 'HH:mm:ss'
    $script:logBox.AppendText("[$stamp] $message`r`n")
    $script:logBox.SelectionStart = $script:logBox.Text.Length
    $script:logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
function Check-FcmCancel {
    if ($script:ScanRunning -and $script:CancelRequested) {
        throw 'FCM scan cancelled by user.'
    }
}
function Wait-FcmResponsive([int]$milliseconds) {
    # Unlike Start-Sleep, this pumps the WinForms event queue during throttling.
    $until = [DateTime]::UtcNow.AddMilliseconds([Math]::Max(0,$milliseconds))
    while ([DateTime]::UtcNow -lt $until) {
        [System.Windows.Forms.Application]::DoEvents()
        Check-FcmCancel
        [System.Threading.Thread]::Sleep(35)
    }
}
function Get-FcmHttpStatus($failure) {
    $err = if ($failure -is [System.Management.Automation.ErrorRecord]) { $failure.Exception } else { $failure }
    if ($null -eq $err) { return 0 }
    try { if ($err.Data.Contains('HttpStatus')) { return [int]$err.Data['HttpStatus'] } } catch { }
    try { return [int]$err.Response.StatusCode } catch { }
    return 0
}
function Invoke-FcmHttpJson([string]$uri,[hashtable]$headers) {
    Check-FcmCancel
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get,[Uri]$uri)
    foreach ($name in $headers.Keys) {
        [void]$request.Headers.TryAddWithoutValidation([string]$name,[string]$headers[$name])
    }
    $cts = [System.Threading.CancellationTokenSource]::new()
    $script:ActiveRequestCancellation = $cts
    $cts.CancelAfter(25000)
    $response = $null
    $script:FcmLastHttpDailyRemaining = $null
    $script:FcmLastHttpRetryAfter = $null
    try {
        $task = $script:HttpClient.SendAsync($request,[System.Net.Http.HttpCompletionOption]::ResponseContentRead,$cts.Token)
        while (-not $task.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            if ($script:CancelRequested -and $script:ScanRunning) {
                $cts.Cancel()
                Check-FcmCancel
            }
            [System.Threading.Thread]::Sleep(35)
        }
        Check-FcmCancel
        $response = $task.GetAwaiter().GetResult()
        if ($response.Headers.Contains('X-Daily-Remaining')) {
            $script:FcmLastHttpDailyRemaining=(@($response.Headers.GetValues('X-Daily-Remaining')) | Select-Object -First 1)
        }
        if ($response.Headers.RetryAfter) {
            try { $script:FcmLastHttpRetryAfter=[int][Math]::Ceiling($response.Headers.RetryAfter.Delta.TotalSeconds) } catch {}
        }
        if (-not $response.IsSuccessStatusCode) {
            $status = [int]$response.StatusCode
            $failure = [System.Exception]::new("HTTP $status from reference provider")
            $failure.Data['HttpStatus'] = $status
            if ($script:FcmLastHttpRetryAfter) { $failure.Data['RetryAfterSeconds']=$script:FcmLastHttpRetryAfter }
            throw $failure
        }
        $payload = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Check-FcmCancel
        return ConvertFrom-Json -InputObject $payload
    } finally {
        $script:ActiveRequestCancellation = $null
        if ($null -ne $response) { $response.Dispose() }
        $cts.Dispose()
        $request.Dispose()
    }
}
function Find-Game {
    if ($script:Config.gameRoot -and (Test-Path -LiteralPath (Join-Path $script:Config.gameRoot 'Interface\AddOns'))) {
        return $script:Config.gameRoot
    }
    $candidates = @(
        'C:\Program Files (x86)\World of Warcraft\_forever_',
        'C:\Program Files\World of Warcraft\_forever_',
        'D:\World of Warcraft\_forever_',
        'D:\Games\World of Warcraft\_forever_',
        'E:\World of Warcraft\_forever_'
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath (Join-Path $c 'Interface\AddOns')) { return $c } }
    return ''
}
function Game-Is-Running {
    # A conservative check: external Lua changes do not take effect until restart.
    return [bool](Get-Process -Name Wow,WowB,WowClassic,WowT -ErrorAction SilentlyContinue | Select-Object -First 1)
}
function Target-Addon {
    $root = $script:gameBox.Text.Trim()
    if (-not (Test-Path -LiteralPath (Join-Path $root 'Interface\AddOns'))) {
        throw 'Select the WoW Forever game folder (the _forever_ directory) first.'
    }
    return (Join-Path $root 'Interface\AddOns\ForeverCharacterManager')
}
function Backup-Addon($path) {
    if (Test-Path -LiteralPath $path) {
        $backup = "$path.backup.$(Get-Date -Format yyyyMMdd-HHmmss)"
        Copy-Item -LiteralPath $path -Destination $backup -Recurse -Force
        Log "Backed up previous addon to: $backup"
    }
}
function Ensure-GeneratedReferenceFile([string]$dest) {
    # Never reset previously downloaded ForeverDB/AHledger reference data.
    $generated = Join-Path $dest 'ExternalData.generated.lua'
    if (Test-Path -LiteralPath $generated) { return }
    $template = Join-Path $script:Base 'ExternalData.generated.template.lua'
    if (Test-Path -LiteralPath $template) {
        Copy-Item -LiteralPath $template -Destination $generated -Force
        Log 'Initialized missing generated reference file; existing data is preserved.'
    }
}
function Install-Addon {
    if (Game-Is-Running) { throw 'Exit World of Warcraft fully before installing or updating the addon.' }
    if (-not (Test-Path -LiteralPath (Join-Path $script:SourceAddon 'ForeverCharacterManager.toc'))) {
        throw 'The addon source folder could not be found. Keep the FCM-Companion folder beside or inside ForeverCharacterManager.'
    }
    $dest = Target-Addon
    $sourcePath = [IO.Path]::GetFullPath($script:SourceAddon).TrimEnd([char[]]@([char]92,[char]47))
    $destPath = [IO.Path]::GetFullPath($dest).TrimEnd([char[]]@([char]92,[char]47))
    if ([string]::Equals($sourcePath,$destPath,[StringComparison]::OrdinalIgnoreCase)) {
        # Installed directly under Interface\AddOns: do not copy files over themselves.
        Ensure-GeneratedReferenceFile $dest
        Save-Config
        Log 'FCM addon already installed in this game directory. Skipped self-copy; character saves and cached data were not modified.'
        return
    }
    Backup-Addon $dest
    if (-not (Test-Path -LiteralPath $dest)) { New-Item -Path $dest -ItemType Directory | Out-Null }
    foreach ($src in @(Get-ChildItem -LiteralPath $script:SourceAddon -File)) {
        # Never overwrite reference data created by an earlier successful update.
        if ($src.Name -in @('ExternalData.generated.lua','AHPrices.generated.lua') -and
                (Test-Path -LiteralPath (Join-Path $dest $src.Name))) { continue }
        Copy-Item -LiteralPath $src.FullName -Destination (Join-Path $dest $src.Name) -Force
    }
    # Include the artwork. Earlier updates only copied top-level Lua and TOC files,
    # leaving custom minimap emblems missing on new installations.
    $mediaSource = Join-Path $script:SourceAddon 'Media'
    if (Test-Path -LiteralPath $mediaSource) {
        $mediaDest = Join-Path $dest 'Media'
        if (-not (Test-Path -LiteralPath $mediaDest)) { New-Item -Path $mediaDest -ItemType Directory | Out-Null }
        foreach ($asset in @(Get-ChildItem -LiteralPath $mediaSource -File)) {
            Copy-Item -LiteralPath $asset.FullName -Destination (Join-Path $mediaDest $asset.Name) -Force
        }
        Log 'Installed FCM emblem artwork.'
    }
    $destCompanion = Join-Path $dest 'FCM-Companion'
    if (-not (Test-Path -LiteralPath $destCompanion)) { New-Item -Path $destCompanion -ItemType Directory | Out-Null }
    # Only copy static scripts and documentation; NEVER copy credentials, settings or caches.
    foreach ($filename in @('FCMDataUpdater.ps1','ForeverDB.Provider.ps1','ReferenceAudit.ps1','OPEN-FCM-DATA-UPDATER.cmd','ABOUT_DATA_SOURCES.txt','ExternalData.generated.template.lua','GitHubUpdates.ps1','FCM-DailyAHSync.ps1','Enable-FCM-DailyAH.ps1','Disable-FCM-DailyAH.ps1','DAILY_AH_SETUP.txt','FCM-ForeverDBBuildCheck.ps1','Enable-FCM-ScheduledRefresh.ps1','Disable-FCM-ScheduledRefresh.ps1','AUTO_REFRESH_SETUP.txt')) {
        $companionSource = Join-Path $script:Base $filename
        if (Test-Path -LiteralPath $companionSource) {
            Copy-Item -LiteralPath $companionSource -Destination (Join-Path $destCompanion $filename) -Force
        }
    }
    Ensure-GeneratedReferenceFile $dest
    Save-Config
    Log 'FCM addon, emblem, and companion installed. Existing WTF character records and downloaded references were preserved.'
}
function Get-Remote([string]$uri) {
    # Preserve the v0.7.4 public-host allowlist. No private data is uploaded.
    $u = [uri]$uri
    if ($u.Scheme -ne 'https' -or $u.Host -notin @('thewowdb.com','api.ahledger.com')) {
        throw 'Unapproved data source.'
    }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        Check-FcmCancel
        try {
            return Invoke-FcmHttpJson $uri @{'User-Agent'='FCM/0.9.0 (+https://github.com/PHOENIXHA1735/ForeverCharacterManager)';'Accept'='application/json'}
        } catch {
            Check-FcmCancel
            $httpStatus = Get-FcmHttpStatus $_
            if ($httpStatus -in @(400,401,403,404,429) -or $attempt -eq 2) { throw }
            Wait-FcmResponsive 1000
        }
    }
}

function Get-ObservedIds {
    Check-FcmCancel
    $root = $script:gameBox.Text.Trim()
    $wtf = Join-Path $root 'WTF\Account'
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    if (-not (Test-Path -LiteralPath $wtf)) { return @() }
    $files = @(Get-ChildItem -LiteralPath $wtf -Filter 'ForeverCharacterManager.lua' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 15)
    foreach ($file in $files) {
        Check-FcmCancel
        try {
            # Bounded read, no script execution. Only item IDs and hyperlink IDs.
            if ($file.Length -gt 30000000) { continue }
            $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
            foreach ($m in [regex]::Matches($content,'(?:itemID|outputID)\s*=\s*(\d{1,7})|item:(\d{1,7})')) {
                $s = if ($m.Groups[1].Success) {$m.Groups[1].Value} else {$m.Groups[2].Value}
                $n = [int]$s
                if ($n -gt 0) { [void]$ids.Add($n) }
            }
        } catch { Log "Unable to read a saved record: $($file.Name)" }
    }
    $found = @($ids | Sort-Object)
    Log "Found $($found.Count) distinct item IDs in local FCM saves; querying up to 60 per sync."
    return @($found | Select-Object -First 60)
}
function Normalize-Item($item) {
    if ($null -eq $item) { return $null }
    if ($item.data -and $item.data.id) { $item = $item.data }
    if ($item.item -and $item.item.id) { $item = $item.item }
    $id = 0
    try { $id = [int]$item.id } catch { return $null }
    if ($id -le 0 -or -not $item.name) { return $null }
    $info = [ordered]@{
        name = [string]$item.name
        category = 'Imported Forever item'
        sourceStatus = 'Public API record; acquisition locations may not be included'
        metadataSource = 'Data from TheWoWDB (thewowdb.com)'
        link = "https://thewowdb.com/wow-forever/item/$id/"
        sourceProvider = 'TheWoWDB'
        referenceCheckedAt = (Get-Date).ToUniversalTime().ToString('o')
        sourceEvidence = 'Public reference item; not independently verified in the game client'
    }
    if ($item.links -and $item.links.html) { $info.link = [string]$item.links.html }
    if ($item.class_name) { $info.category = [string]$item.class_name }
    elseif ($item.item_class) { $info.category = [string]$item.item_class }
    return @{ id=$id; info=$info }
}
function Save-Item($item) {
    $normalized = Normalize-Item $item
    if ($null -eq $normalized) { return }
    $key = [string]$normalized.id
    if ($script:ItemCache.ContainsKey($key)) {
        $current = $script:ItemCache[$key]
        # Preserve richer ForeverDB or manually curated data; add only missing fields.
        if ([string]$current.metadataSource -match 'ForeverDB') { return }
        if ($current -is [System.Collections.IDictionary]) {
            foreach ($field in $normalized.info.Keys) {
                if (-not $current[$field]) { $current[$field] = $normalized.info[$field] }
                if ($field -eq 'referenceCheckedAt' -and [string]$current.sourceProvider -eq 'TheWoWDB') {
                    $current[$field] = $normalized.info[$field]
                }
            }
            $script:ItemCache[$key] = $current
            return
        }
    }
    $script:ItemCache[$key] = $normalized.info
}
function Get-ItemIdsFromSearch($response) {
    if ($null -eq $response) { return @() }
    $records = @()
    if ($response.results) { $records = @($response.results) }
    elseif ($response.items) { $records = @($response.items) }
    elseif ($response.data) {
        if ($response.data.items) { $records = @($response.data.items) }
        elseif ($response.data -is [array]) { $records = @($response.data) }
        else { $records = @($response.data) }
    }
    elseif ($response -is [array]) { $records = @($response) }
    elseif ($response.id) { $records = @($response) }
    $ids = @()
    foreach ($r in $records) {
        $normalized = Normalize-Item $r
        if ($null -ne $normalized) {
            # Use the same merge rules as single-item lookups so this fallback
            # search cannot overwrite richer ForeverDB records.
            Save-Item $r
            $ids += $normalized.id
        }
    }
    return @($ids | Select-Object -Unique)
}
function Sync-Items {
    Check-FcmCancel
    # TheWoWDB is supplemental. A 404 from the search endpoint should not
    # trigger dozens of identical failed lookups, or block the ForeverDB sync.
    $ids = @(Get-ObservedIds)
    $ids += 6291
    $publicUnavailable = $false
    foreach ($q in ($script:termsBox.Text -split '[,;\r\n]')) {
        Check-FcmCancel
        $term = $q.Trim()
        if (-not $term) { continue }
        if ($term -match '^\d{1,7}$') { $ids += [int]$term; continue }
        try {
            $url = 'https://thewowdb.com/api/v1/forever/item/?q=' + [uri]::EscapeDataString($term)
            $hit = Get-Remote $url
            $found = @(Get-ItemIdsFromSearch $hit)
            $ids += $found
            Log "TheWoWDB search '$term': $($found.Count) records."
        } catch {
            $status = 0
            $status = Get-FcmHttpStatus $_
            if ($status -in @(403,404,429)) {
                Log "TheWoWDB search returned HTTP $status; skipping that source this sync. ForeverDB and previously cached data remain available."
                $publicUnavailable = $true
                break
            }
            Log "TheWoWDB search '$term' unavailable: $($_.Exception.Message)"
        }
    }
    if ($publicUnavailable) { return }
    $ids = @($ids | Sort-Object -Unique | Select-Object -First 100)
    $fetched = 0
    $skipped = 0
    $missing = 0
    foreach ($id in $ids) {
        Check-FcmCancel
        if (-not $id) { continue }
        $key = [string]$id
        # Prefer ForeverDB data already retrieved in this sync.
        if ($script:ItemCache.ContainsKey($key) -and
            [string]$script:ItemCache[$key].metadataSource -match 'ForeverDB') {
            $skipped++
            continue
        }
        try {
            $data = Get-Remote "https://thewowdb.com/api/v1/forever/item/$id"
            Save-Item $data
            $fetched++
            $missing = 0
        } catch {
            $status = 0
            $status = Get-FcmHttpStatus $_
            if ($status -eq 404) {
                $missing++
                if ($missing -ge 3) {
                    Log 'TheWoWDB returned HTTP 404 for three consecutive items; stopping redundant requests. Cached/ForeverDB items are unaffected.'
                    break
                }
            } elseif ($status -in @(401,403,429)) {
                Log "TheWoWDB returned HTTP $status; stopping public item lookups for this sync."
                break
            } else {
                $missing++
                if ($missing -ge 3) {
                    Log 'TheWoWDB item lookup failed repeatedly; stopping this source for now.'
                    break
                }
            }
            Log "TheWoWDB item ${id}: not available (HTTP $status); cached data retained."
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    Log "TheWoWDB refreshed $fetched items; used $skipped existing ForeverDB entries; cache contains $($script:ItemCache.Count) items."
}
function Sync-Recipes {
    Check-FcmCancel
    $market = [string]$script:marketBox.SelectedItem
    # The AHledger API is a read-only public source of recipe ingredients. A
    # recipe listed here is not necessarily obtainable on the live server.
    $professions = @('Tailoring','Enchanting','Engineering','Cooking','Alchemy','Blacksmithing','Leatherworking','First Aid')
    $success=0
    foreach ($profession in $professions) {
        Check-FcmCancel
        $url = 'https://api.ahledger.com/v1/crafting/' + $market + '?profession=' + [uri]::EscapeDataString($profession) + '&all=1'
        try {
            $res = Get-Remote $url
            $rows = @($res.recipes)
            if ($null -eq $res.recipes) { Log "$profession`: API returned no recipe list."; continue }
            $found=0
            foreach ($r in $rows) {
                if ($null -eq $r -or -not $r.recipe -or -not $r.recipe.spellId) { continue }
                $rid = [string]$r.recipe.spellId
                $mats = @()
                foreach ($mat in @($r.reagents)) {
                    if ($mat -and $mat.id -and $mat.qty) {
                        $mats += @{ id=[int]$mat.id; count=[double]$mat.qty; name=[string]$mat.name }
                    }
                }
                $recipe = [ordered]@{
                    name = [string]$r.recipe.name
                    profession = [string]$profession
                    skill = [int]$r.recipe.skillRequired
                    acquisition = [string]$r.recipe.acquisition
                    resultID = $(if ($r.result -and $r.result.id) {[int]$r.result.id} else {0})
                    reagents = $mats
                    source = 'Recipe data from AHledger (ahledger.com); verify live availability'
                    sourceProvider = 'AHledger'
                    referenceCheckedAt = (Get-Date).ToUniversalTime().ToString('o')
                    sourceEvidence = 'Public recipe reference; reagent and acquisition claims not independently verified'
                }
                # Do not replace richer ForeverDB acquisition records with a
                # thinner AHledger recipe summary on subsequent refreshes.
                $prior=$script:RecipeCache[$rid]
                if ($null -eq $prior -or [string]$prior.source -notmatch 'ForeverDB') {
                    $script:RecipeCache[$rid] = $recipe
                    $found++
                }
            }
            Log "$profession`: imported $found recipe references."
            $success++
        } catch { Log "$profession`: API unavailable, retaining cached recipes. $($_.Exception.Message)" }
        [System.Windows.Forms.Application]::DoEvents()
    }
    Log "Recipe categories reached: $success/$($professions.Count). Cached recipes: $($script:RecipeCache.Count)."
}
function LuaQ($value) {
    $s = [string]$value
    # Lua 5.1 cannot embed raw control characters in quoted strings.
    $s=[regex]::Replace($s,'[\x00-\x08\x0B\x0C\x0E-\x1F]',' ')
    $s = $s.Replace('\','\\').Replace('"','\"').Replace("`r",'').Replace("`n",'\n').Replace("`t",'\t')
    # WoW Lua can display UTF-8; trim exceptionally long untrusted fields.
    if ($s.Length -gt 600) { $s = $s.Substring(0,600) }
    return '"' + $s + '"'
}
function Sync-AuctionPrices {
    Check-FcmCancel
    $market=[string]$script:marketBox.SelectedItem
    if ($market -notmatch '^forever\.(normal|pvp|rp|rppvp)\.(alliance|horde)\.(us|eu|cn)$') {throw 'Invalid market selected.'}
    # A conservative number of item prices, downloaded without an API key.
    $ids=@(Get-ObservedIds)
    $ids+=6291
    foreach ($term in ($script:termsBox.Text -split '[,;\r\n]')) {
        $t=$term.Trim()
        if ($t -match '^\d{1,7}$') { $ids+=[int]$t }
    }
    $ids+=@($script:ItemCache.Keys | Where-Object {$_ -match '^\d{1,7}$'} | Sort-Object {[int]$_})
    $ids=@($ids | Select-Object -Unique | Select-Object -First 60)
    $fetched=0
    foreach ($id in $ids) {
        Check-FcmCancel
        try {
            $r=Get-Remote ('https://api.ahledger.com/v1/prices/'+$market+'/'+$id+'?range=7d')
            if ($r.latest -and $null -ne $r.latest.median) {
                $script:PriceCache[($market + '|' + [string]$id)]=@{
                    median=[long]$r.latest.median;
                    minBuyout=[long]$r.latest.minBuyout;
                    observedAt=[string]$r.latest.observedAt;
                    market=$market
                }
                $fetched++
            }
        } catch {Log "AHledger price unavailable for item #$id; cached price retained."}
    }
    Log "AHledger: refreshed $fetched snapshots for $market. Cached markets remain separate."
}
function Write-LuaFile {
    Check-FcmCancel
    $target=Target-Addon
    if (-not (Test-Path -LiteralPath (Join-Path $target 'ExternalData.lua'))) { throw 'Install FCM v0.6.0 from the companion first.' }
    $file=Join-Path $target 'ExternalData.generated.lua'
    $sb=New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local _, FCM = ...')
    [void]$sb.AppendLine('-- Generated by FCM Data Companion. Edits will be overwritten. Do not store character data here.')
    [void]$sb.AppendLine('FCM.externalData = FCM.externalData or {items={},recipes={}}')
    [void]$sb.AppendLine('FCM.externalData.items = FCM.externalData.items or {}')
    [void]$sb.AppendLine('FCM.externalData.recipes = FCM.externalData.recipes or {}')
    [void]$sb.AppendLine('FCM.externalData.prices = FCM.externalData.prices or {}')
    [void]$sb.AppendLine('FCM.externalData.pricesByMarket = FCM.externalData.pricesByMarket or {}')
    [void]$sb.AppendLine('FCM.externalData.dungeons = FCM.externalData.dungeons or {}')
    [void]$sb.AppendLine('FCM.externalData.edition = ' + (LuaQ (Get-Date -Format 'yyyy-MM-dd HH:mm')))
    $itemWritten=0
    $processed=0
    foreach ($key in @($script:ItemCache.Keys | Where-Object {$_ -match '^\d{1,7}$'} | Sort-Object {[int]$_} | Select-Object -First 100000)) {
        if ($key -notmatch '^\d{1,7}$') { continue }
        $processed++
        if (($processed % 100) -eq 0) { [System.Windows.Forms.Application]::DoEvents(); Check-FcmCancel }
        $id=[int]$key
        $item=$script:ItemCache[$key]
        [void]$sb.AppendLine("do local r = FCM.externalData.items[$id] or {}")
        foreach ($name in @('name','category','link','where','uses','recipes','source','sourceStatus','metadataSource','sourceProvider','sourceEvidence','referenceCheckedAt','gatheringEvidence','vendorEvidence','dungeon','dungeonSources','confidence','stats','effects','quality','itemLevel','requiredLevel','classID','subclass','equipLoc','slotID','binding','sellPrice','soldBy','vendorSource','availabilityNote','liveClientNote')) {
            $value=$item.$name
            if ($null -ne $value -and [string]$value -ne '') {
                [void]$sb.AppendLine('r.' + $name + ' = ' + (LuaQ $value))
            }
        }
        foreach ($name in @('betaEvent','speculation')) {
            if ($item.$name -eq $true) { [void]$sb.AppendLine('r.'+$name+'=true') }
        }
        # Structured, attributed farm sources; values validated before being
        # emitted as Lua. No guessed rates, no API key, no personal character data.
        $farmRows=@($item.farmSources | Where-Object {$_})
        if ($farmRows.Count -gt 0) {
            [void]$sb.AppendLine('r.farmSources = {')
            foreach ($farm in @($farmRows | Select-Object -First 30)) {
                $name=([string]$farm.name);$zone=([string]$farm.zone)
                if (-not $name -and -not $zone) {continue}
                [void]$sb.Append('{kind='+(LuaQ $farm.kind)+',name='+(LuaQ $name)+',zone='+(LuaQ $zone)+
                    ',source='+(LuaQ $farm.source)+',evidence='+(LuaQ $farm.evidence))
                foreach ($prop in @('dropRatePct','sampleSize','killsPerHour','levelMin','levelMax')) {
                    $v=0.0
                    try {if ($null -ne $farm.$prop) {$v=[double]$farm.$prop}} catch {}
                    if ($v -gt 0 -and $v -lt 1000000000 -and
                        ($prop -ne 'dropRatePct' -or $v -le 100)) {
                        [void]$sb.Append(','+$prop+'='+$v.ToString('0.#####',[Globalization.CultureInfo]::InvariantCulture))
                    }
                }
                [void]$sb.AppendLine('},')
            }
            [void]$sb.AppendLine('}')
        }
        [void]$sb.AppendLine("FCM.externalData.items[$id]=r end")
        $itemWritten++
    }
    $recipeWritten=0
    Check-FcmCancel
    foreach ($key in @($script:RecipeCache.Keys | Where-Object {$_ -match '^\d{1,8}$'} | Sort-Object {[int]$_} | Select-Object -First 20000)) {
        if ($key -notmatch '^\d{1,8}$') { continue }
        $r=$script:RecipeCache[$key]
        [void]$sb.Append("FCM.externalData.recipes[$key]={")
        foreach ($name in @('name','profession','acquisition','source','sourceProvider','sourceEvidence','referenceCheckedAt')) {
            [void]$sb.Append($name + '=' + (LuaQ $r.$name) + ',')
        }
        [void]$sb.Append('resultID=' + [int]$r.resultID + ',skill=' + [int]$r.skill + ',reagents={')
        foreach ($mat in @($r.reagents)) {
            if ($mat -and $mat.id -gt 0 -and $mat.count -gt 0) {
                [void]$sb.Append('{id=' + [int]$mat.id + ',count=' + ([string]([double]$mat.count).ToString([Globalization.CultureInfo]::InvariantCulture)) + '},')
            }
        }
        [void]$sb.AppendLine('}}')
        $recipeWritten++
    }
    # Preserve both Horde and Alliance AHledger snapshots in separate markets.
    # The flat prices[] table remains the CURRENT selected market for older code.
    $selectedMarket=[string]$script:marketBox.SelectedItem
    Check-FcmCancel
    foreach ($key in @($script:PriceCache.Keys | Sort-Object | Select-Object -First 10000)) {
        if ($key -match '^(forever\.(?:normal|pvp|rp|rppvp)\.(?:alliance|horde)\.(?:us|eu|cn))\|(\d{1,7})$') {
            $market=$Matches[1]
        } else { continue }
        $id=$Matches[2]
        $price=$script:PriceCache[$key]
        [void]$sb.AppendLine('FCM.externalData.pricesByMarket[' + (LuaQ $market) + '] = FCM.externalData.pricesByMarket[' + (LuaQ $market) + '] or {}')
        $record='{ median=' + [long]$price.median + ',minBuyout=' + [long]$price.minBuyout + ',market=' + (LuaQ $market) + ',observedAt=' + (LuaQ $price.observedAt) + ' }'
        [void]$sb.AppendLine('FCM.externalData.pricesByMarket[' + (LuaQ $market) + '][' + $id + '] = ' + $record)
        if ($market -eq $selectedMarket) {
            [void]$sb.AppendLine('FCM.externalData.prices[' + $id + '] = ' + $record)
        }
    }
    Check-FcmCancel
    foreach ($key in @($script:DungeonCache.Keys | Where-Object {$_ -match '^\d{1,8}$'} | Sort-Object {[int]$_} | Select-Object -First 1000)) {
        $d=$script:DungeonCache[$key]
        [void]$sb.Append('FCM.externalData.dungeons[' + $key + '] = {name=' + (LuaQ $d.name) + ',levels='+(LuaQ $d.levels)+',kind='+(LuaQ $d.kind)+',sourceProvider='+(LuaQ $d.sourceProvider)+',referenceCheckedAt='+(LuaQ $d.referenceCheckedAt)+',sourceEvidence='+(LuaQ $d.sourceEvidence)+',bossCount=' + [int]$d.bossCount + ',lootIDs={')
        foreach ($itemID in @($d.lootIDs | Select-Object -First 100)) { if ([int]$itemID -gt 0) { [void]$sb.Append(([int]$itemID).ToString() + ',') } }
        [void]$sb.Append('},bosses={')
        foreach ($boss in @($d.bosses | Select-Object -First 90)) {
            if (-not $boss) {continue}
            [void]$sb.Append('{id=' + [int]$boss.id + ',name='+(LuaQ $boss.name)+',loot={')
            foreach ($drop in @($boss.loot | Select-Object -First 65)) {
                if (-not $drop -or [int]$drop.id -le 0) {continue}
                [void]$sb.Append('{id=' + [int]$drop.id + ',name='+(LuaQ $drop.name)+',sourceType='+(LuaQ $drop.sourceType)+'},')
            }
            [void]$sb.Append('}},')
        }
        [void]$sb.Append('},dungeonLoot={')
        foreach ($drop in @($d.dungeonLoot | Select-Object -First 100)) {
            if (-not $drop -or [int]$drop.id -le 0) {continue}
            [void]$sb.Append('{id=' + [int]$drop.id + ',name='+(LuaQ $drop.name)+',sourceType='+(LuaQ $drop.sourceType)+'},')
        }
        [void]$sb.Append('},lines={')
        foreach ($line in @($d.lines | Select-Object -First 100)) { [void]$sb.Append((LuaQ $line) + ',') }
        [void]$sb.AppendLine('}}')
    }
    $text=$sb.ToString()
    if ($text.Length -gt 24000000) { throw 'Catalog exceeded the 24MB Lua safety limit; the previous version was preserved. Reduce imported fields or split the catalog.' }
    Check-FcmCancel
    $backup = [ordered]@{ savedAt=(Get-Date -Format o);items=$script:ItemCache;recipes=$script:RecipeCache;prices=$script:PriceCache;dungeons=$script:DungeonCache }
    $json = $backup | ConvertTo-Json -Depth 9 -Compress
    $null = ConvertFrom-Json -InputObject $json
    $tmp="$file.tmp"
    # Lua files in WoW are read as UTF-8 with no BOM.
    [IO.File]::WriteAllText($tmp,$text,(New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $file) {
        Copy-Item -LiteralPath $file -Destination "$file.bak" -Force
    }
    Move-Item -LiteralPath $tmp -Destination $file -Force
    $cacheTemp = "$($script:CachePath).tmp"
    [IO.File]::WriteAllText($cacheTemp,$json,(New-Object System.Text.UTF8Encoding($false)))
    # Check generated JSON parses before replacing the last known-good cache.
    $null = $json | ConvertFrom-Json
    if (Test-Path -LiteralPath $script:CachePath) {
        Copy-Item -LiteralPath $script:CachePath -Destination "$($script:CachePath).bak" -Force
    }
    Move-Item -LiteralPath $cacheTemp -Destination $script:CachePath -Force
    Log "Wrote $itemWritten items, $recipeWritten recipes, $($script:PriceCache.Count) market-specific prices, and $($script:DungeonCache.Count) dungeon records. Character saves were not touched."
}
function Sync-All {
    Check-FcmCancel
    if (Game-Is-Running) { throw 'Close WoW completely before synchronizing. A running client cannot reload external files safely.' }
    $null=Target-Addon
    Save-Config
    Log 'Starting public-reference update (read-only web requests). Market prices are snapshots; IV is not scraped.'
    # Query approved ForeverDB first so a broken public endpoint does not delay useful data.
    Sync-ForeverDB
    Check-FcmCancel
    Sync-Items
    Check-FcmCancel
    Sync-Recipes
    Check-FcmCancel
    Sync-AuctionPrices
    Check-FcmCancel
    Write-LuaFile
    $audit=Write-FCMReferenceAudit
    $script:Config.lastSync = (Get-Date).ToString('o')
    Save-Config
    # Local-only progress report; NEVER include the ForeverDB key or player data.
    $summary = [ordered]@{
        version = '0.9.0'
        lastSync = $script:Config.lastSync
        items = $script:ItemCache.Count
        nextForeverDBItemOffset = $script:Config.fdbItemOffset
        catalogCoverage = "Incremental; records may be speculative or not present in live Forever"
        referenceRecipes = $script:RecipeCache.Count
        prices = $script:PriceCache.Count
        dungeons = $script:DungeonCache.Count
        foreverDBRequests = $script:ForeverDBRequests
        # Do not write local path or account names into a report intended for sharing.
        market = [string]$script:marketBox.SelectedItem
        referenceAudit = 'reference-audit.json'
        incompleteRecipes = $audit.recipes.withoutOutput + $audit.recipes.withoutReagents
        dungeonOnlyLootLinks = $audit.dungeons.dungeonOnlyLinks
        note = 'Reference data from external sources; source confidence varies. Character saves are not uploaded.'
    }
    $reportTemp = "$($script:ReportPath).tmp"
    [IO.File]::WriteAllText($reportTemp,($summary | ConvertTo-Json -Depth 4),(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $reportTemp -Destination $script:ReportPath -Force
    Log "CATALOG COVERAGE: $($summary.items) item records cached; additional manual syncs advance through ForeverDB catalog pages."
    Log "SYNC SUMMARY: $($summary.items) items; $($summary.referenceRecipes) recipes; $($summary.prices) prices; $($summary.dungeons) dungeons."
    Log 'Finished. Open WoW Forever and type /fcm, then choose Item Explorer.'
}
function Action($operation,[bool]$isScan=$false) {
    if ($script:OperationRunning) { return }
    $script:OperationRunning = $true
    $script:ScanRunning = $isScan
    $script:CancelRequested = $false
    $originalOffsets=@{}
    if ($isScan) {
        foreach ($key in @($script:Config.Keys)) {
            if ($key -match '^fdb.*(Offset|Importer)$') { $originalOffsets[$key] = $script:Config[$key] }
        }
    }
    $script:syncButton.Enabled = $false
    $script:installButton.Enabled = $false
    $script:stopButton.Enabled = $isScan
    foreach ($ctrl in @($script:githubCheckButton,$script:githubUpdateButton,$script:githubRestoreButton,$script:checkUpdatesBox,$script:auditButton)) {
        if ($null -ne $ctrl) {$ctrl.Enabled=$false}
    }
    $script:stopButton.Text = 'Stop Scan'
    $script:statusLabel.Text = $(if ($isScan) {'Scanning...'} else {'Installing...'})
    foreach ($control in @($script:gameBox,$script:termsBox,$script:marketBox,$script:autoBox,$script:fdbKeyBox,$script:fdbRememberBox,$script:browseButton)) {
        $control.Enabled = $false
    }
    try {
        & $operation
        if ($isScan) { Check-FcmCancel }
    } catch {
        if ($script:CancelRequested -and $isScan) {
            Log 'STOPPED by user. Incomplete scan was not installed; previous generated Lua file and saved cache were retained.'
        } else {
            Log "ERROR: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'FCM Companion',[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    } finally {
        if ($isScan -and $script:CancelRequested) {
            # No reference cache was committed; roll back catalog-page cursors
            # so the next scan doesn't skip pages from an aborted run.
            foreach ($key in @($script:Config.Keys)) {
                if ($key -match '^fdb.*(Offset|Importer)$' -and -not $originalOffsets.ContainsKey($key)) { $script:Config.Remove($key) }
            }
            foreach ($key in $originalOffsets.Keys) { $script:Config[$key] = $originalOffsets[$key] }
            try { Save-Config } catch { }
        }
        $script:ScanRunning = $false
        $script:OperationRunning = $false
        $script:ActiveRequestCancellation = $null
        $script:syncButton.Enabled = $true
        $script:installButton.Enabled = $true
        $script:stopButton.Enabled = $false
        $script:stopButton.Text = 'Stop Scan'
        if ($script:githubCheckButton) {$script:githubCheckButton.Enabled=$true}
        if ($script:githubUpdateButton) {$script:githubUpdateButton.Enabled=($null -ne $script:LatestFCMAsset)}
        if ($script:githubRestoreButton) {$script:githubRestoreButton.Enabled=$true}
        if ($script:checkUpdatesBox) {$script:checkUpdatesBox.Enabled=$true}
        if ($script:auditButton) {$script:auditButton.Enabled=$true}
        $script:statusLabel.Text = $(if ($script:CancelRequested) {'Stopped'} else {'Idle'})
        $script:CancelRequested = $false
        foreach ($control in @($script:gameBox,$script:termsBox,$script:marketBox,$script:autoBox,$script:fdbKeyBox,$script:fdbRememberBox,$script:browseButton)) {
            $control.Enabled = $true
        }
    }
}

Get-Config
$form=New-Object System.Windows.Forms.Form
$form.Text='Forever Character Manager - Data Companion v0.9.0'
$form.Size=New-Object System.Drawing.Size(800,850)
$form.StartPosition='CenterScreen'
$form.MinimumSize=New-Object System.Drawing.Size(800,850)
$form.BackColor=[System.Drawing.Color]::FromArgb(27,33,42)
$form.ForeColor=[System.Drawing.Color]::White
$form.Font=New-Object System.Drawing.Font('Segoe UI',10)
function New-Label([string]$text,[int]$x,[int]$y,[int]$width,[int]$height) {
    $v=New-Object System.Windows.Forms.Label; $v.Text=$text; $v.Location=New-Object System.Drawing.Point($x,$y)
    $v.Size=New-Object System.Drawing.Size($width,$height); $v.ForeColor=[System.Drawing.Color]::White
    $form.Controls.Add($v); return $v
}
$null=New-Label 'WoW Forever installation folder (_forever_)' 20 18 600 26
$script:gameBox=New-Object System.Windows.Forms.TextBox
$script:gameBox.Location=New-Object System.Drawing.Point(20,46)
$script:gameBox.Size=New-Object System.Drawing.Size(610,28)
$script:gameBox.Text=Find-Game
$form.Controls.Add($script:gameBox)
$script:browseButton=New-Object System.Windows.Forms.Button
$browse=$script:browseButton
$browse.Text='Browse';$browse.Location=New-Object System.Drawing.Point(636,43)
$browse.Size=New-Object System.Drawing.Size(92,30)
$browse.Add_Click({
    $folder=New-Object System.Windows.Forms.FolderBrowserDialog
    $folder.Description='Choose the WoW Forever _forever_ installation folder'
    if ($folder.ShowDialog() -eq 'OK') {
        $script:gameBox.Text=$folder.SelectedPath
        Save-Config
        Write-FCMUpdateReadiness
    }
});$form.Controls.Add($browse)
$null=New-Label 'Item names or IDs to look up (comma-separated; local saved items scanned automatically)' 20 96 706 28
$script:termsBox=New-Object System.Windows.Forms.TextBox
$script:termsBox.Location=New-Object System.Drawing.Point(20,127)
$script:termsBox.Size=New-Object System.Drawing.Size(708,28)
$script:termsBox.Text=[string]$script:Config.terms
$form.Controls.Add($script:termsBox)
$null=New-Label 'Reference market (recipes and AHledger historical auction prices)' 20 174 708 25
$script:marketBox=New-Object System.Windows.Forms.ComboBox
$script:marketBox.DropDownStyle='DropDownList'
$script:marketBox.Location=New-Object System.Drawing.Point(20,203)
$script:marketBox.Size=New-Object System.Drawing.Size(300,29)
foreach ($m in @('forever.normal.alliance.us','forever.normal.horde.us','forever.pvp.alliance.us','forever.pvp.horde.us','forever.rp.alliance.us','forever.rp.horde.us','forever.rppvp.alliance.us','forever.rppvp.horde.us')) { [void]$script:marketBox.Items.Add($m) }
$index=$script:marketBox.Items.IndexOf([string]$script:Config.market)
$script:marketBox.SelectedIndex=$(if ($index -ge 0) {$index} else {0})
$form.Controls.Add($script:marketBox)
$script:autoBox=New-Object System.Windows.Forms.CheckBox
$script:autoBox.Text='Update automatically when the companion opens (if WoW is closed)'
$script:autoBox.AutoSize=$true
$script:autoBox.Location=New-Object System.Drawing.Point(344,205)
$script:autoBox.Checked=[bool]$script:Config.autoSync
$form.Controls.Add($script:autoBox)
$null=New-Label 'ForeverDB API key (optional; approved key required from ForeverDB.net)' 20 245 745 25
$script:fdbKeyBox=New-Object System.Windows.Forms.TextBox
$script:fdbKeyBox.Location=New-Object System.Drawing.Point(20,274)
$script:fdbKeyBox.Size=New-Object System.Drawing.Size(490,28)
$script:fdbKeyBox.UseSystemPasswordChar=$true
$form.Controls.Add($script:fdbKeyBox)
$script:fdbRememberBox=New-Object System.Windows.Forms.CheckBox
$script:fdbRememberBox.Text='Remember encrypted for this Windows user'
$script:fdbRememberBox.Location=New-Object System.Drawing.Point(520,275)
$script:fdbRememberBox.Size=New-Object System.Drawing.Size(255,27)
$form.Controls.Add($script:fdbRememberBox)
$secret = Read-ForeverDBKey
if ($secret) { $script:fdbKeyBox.Text=$secret; $script:fdbRememberBox.Checked=$true }
$script:installButton=New-Object System.Windows.Forms.Button
$script:installButton.Text='1. Install / Update FCM'
$script:installButton.Location=New-Object System.Drawing.Point(20,328)
$script:installButton.Size=New-Object System.Drawing.Size(360,39)
$script:installButton.Add_Click({ Action { Install-Addon } })
$form.Controls.Add($script:installButton)
$script:syncButton=New-Object System.Windows.Forms.Button
$script:syncButton.Text='2. Scan + Update Data'
$script:syncButton.Location=New-Object System.Drawing.Point(392,328)
$script:syncButton.Size=New-Object System.Drawing.Size(232,39)
$script:syncButton.Add_Click({ Action { Sync-All } $true })
$form.Controls.Add($script:syncButton)
$script:stopButton=New-Object System.Windows.Forms.Button
$script:stopButton.Text='Stop Scan'
$script:stopButton.Location=New-Object System.Drawing.Point(636,328)
$script:stopButton.Size=New-Object System.Drawing.Size(132,39)
$script:stopButton.BackColor=[System.Drawing.Color]::FromArgb(142,52,43)
$script:stopButton.ForeColor=[System.Drawing.Color]::White
$script:stopButton.Enabled=$false
$script:stopButton.Add_Click({
    if ($script:ScanRunning -and -not $script:CancelRequested) {
        $script:CancelRequested=$true
        $script:statusLabel.Text='Stopping...'
        $script:stopButton.Enabled=$false
        $script:stopButton.Text='Stopping...'
        # Cancel the active HTTP request immediately rather than waiting for
        # its normal 25-second timeout.
        if ($null -ne $script:ActiveRequestCancellation) {
            try { $script:ActiveRequestCancellation.Cancel() } catch { }
        }
    }
})
$form.Controls.Add($script:stopButton)
# Public GitHub Releases are checked independently of the reference-data sync.
$script:githubCheckButton=New-Object System.Windows.Forms.Button
$script:githubCheckButton.Text='Check GitHub Releases'
$script:githubCheckButton.Location=New-Object System.Drawing.Point(20,376)
$script:githubCheckButton.Size=New-Object System.Drawing.Size(232,36)
$script:githubCheckButton.Add_Click({Action {Get-FCMLatestGitHubRelease}})
$form.Controls.Add($script:githubCheckButton)
$script:githubUpdateButton=New-Object System.Windows.Forms.Button
$script:githubUpdateButton.Text='Install GitHub Update'
$script:githubUpdateButton.Location=New-Object System.Drawing.Point(265,376)
$script:githubUpdateButton.Size=New-Object System.Drawing.Size(240,36)
$script:githubUpdateButton.Enabled=$false
$script:githubUpdateButton.Add_Click({Action {Install-FCMLatestGitHubRelease}})
$form.Controls.Add($script:githubUpdateButton)
$script:githubRestoreButton=New-Object System.Windows.Forms.Button
$script:githubRestoreButton.Text='Restore FCM Backup'
$script:githubRestoreButton.Location=New-Object System.Drawing.Point(518,376)
$script:githubRestoreButton.Size=New-Object System.Drawing.Size(250,36)
$script:githubRestoreButton.Add_Click({Action {Restore-FCMLatestBackup}})
$form.Controls.Add($script:githubRestoreButton)
$script:checkUpdatesBox=New-Object System.Windows.Forms.CheckBox
$script:checkUpdatesBox.Text='Check for new FCM releases when the companion opens (no automatic installation)'
$script:checkUpdatesBox.Location=New-Object System.Drawing.Point(20,415)
$script:checkUpdatesBox.Size=New-Object System.Drawing.Size(520,26)
$script:checkUpdatesBox.Checked=($script:Config.autoUpdateCheck -ne $false)
$form.Controls.Add($script:checkUpdatesBox)
$script:auditButton=New-Object System.Windows.Forms.Button
$script:auditButton.Text='Audit Reference Data'
$script:auditButton.Location=New-Object System.Drawing.Point(548,414)
$script:auditButton.Size=New-Object System.Drawing.Size(220,29)
$script:auditButton.Add_Click({Action {$null=Write-FCMReferenceAudit}})
$form.Controls.Add($script:auditButton)
$null=New-Label 'Sync activity and data sources' 20 444 470 25
$script:statusLabel=New-Label 'Idle' 650 444 118 25
$script:logBox=New-Object System.Windows.Forms.TextBox
$script:logBox.Multiline=$true; $script:logBox.ReadOnly=$true;$script:logBox.ScrollBars='Vertical'
$script:logBox.Location=New-Object System.Drawing.Point(20,471)
$script:logBox.Size=New-Object System.Drawing.Size(748,231)
$script:logBox.BackColor=[System.Drawing.Color]::FromArgb(12,18,25)
$script:logBox.ForeColor=[System.Drawing.Color]::FromArgb(185,225,210)
$script:logBox.Font=New-Object System.Drawing.Font('Consolas',9)
$form.Controls.Add($script:logBox)
# ForeverDB requires a visible, clickable link in the Windows companion.
$script:fdbCreditLink=New-Object System.Windows.Forms.LinkLabel
$script:fdbCreditLink.Text='Data from ForeverDB.net - https://foreverdb.net'
$script:fdbCreditLink.Location=New-Object System.Drawing.Point(20,713)
$script:fdbCreditLink.Size=New-Object System.Drawing.Size(460,20)
$script:fdbCreditLink.LinkColor=[System.Drawing.Color]::FromArgb(93,170,245)
[void]$script:fdbCreditLink.Links.Add(0,$script:fdbCreditLink.Text.Length,'https://foreverdb.net')
$script:fdbCreditLink.Add_LinkClicked({Start-Process 'https://foreverdb.net'})
$form.Controls.Add($script:fdbCreditLink)
$null=New-Label 'Also: AHledger and TheWoWDB.' 490 713 278 20
$null=New-Label 'Only item IDs/search terms go to data providers. No character records uploaded.' 20 733 748 20
$null=New-Label 'ForeverDB data may be Classic or speculative. Legacy point automation remains deferred.' 20 753 748 20
$form.Add_Shown({
    Log "Ready. Found cached records: $($script:ItemCache.Count) items, $($script:RecipeCache.Count) recipes."
    Write-FCMUpdateReadiness
    if ($script:checkUpdatesBox.Checked) {
        $form.BeginInvoke([action]{ if (-not $script:OperationRunning) {Action {Get-FCMLatestGitHubRelease}} }) | Out-Null
    }
    if ($script:autoBox.Checked -and $script:gameBox.Text -and (Test-Path -LiteralPath (Join-Path $script:gameBox.Text 'Interface\AddOns\ForeverCharacterManager\ExternalData.lua'))) {
        if (Game-Is-Running) { Log 'WoW is running; auto-update skipped.' }
        else {
            $eligible = $true
            try {
                if ($script:Config.lastSync) {
                    $last=[DateTime]::Parse([string]$script:Config.lastSync)
                    $eligible = ((Get-Date) - $last).TotalHours -ge 24
                }
            } catch { $eligible = $true }
            if ($eligible) { $form.BeginInvoke([action]{ Action { Sync-All } }) | Out-Null }
            else { Log 'Reference data updated within 24 hours. Use Scan and Update to refresh manually.' }
        }
    }
})
$form.Add_FormClosing({
    param($sender,$e)
    if ($script:OperationRunning) {
        # Closing during an active scan requests cancellation. Keep the form
        # alive until the operation has returned and restored its state.
        $e.Cancel=$true
        if ($script:ScanRunning -and -not $script:CancelRequested) {
            $script:CancelRequested=$true
            $script:statusLabel.Text='Stopping...'
            if ($null -ne $script:ActiveRequestCancellation) {
                try { $script:ActiveRequestCancellation.Cancel() } catch { }
            }
        }
        return
    }
    try { Save-Config; Save-ForeverDBCredential } catch { }
    if ($null -ne $script:HttpClient) { $script:HttpClient.Dispose() }
    if ($null -ne $script:HttpHandler) { $script:HttpHandler.Dispose() }
})
[void]$form.ShowDialog()
