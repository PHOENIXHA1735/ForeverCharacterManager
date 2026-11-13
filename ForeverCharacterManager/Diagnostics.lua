local _, FCM = ...

-- Diagnostics stay in SavedVariables. Never include account IDs, chat messages or locations.
function FCM:RecordError(area, message)
    if not self.db then return end
    self.db.diagnostics = self.db.diagnostics or { errors = {}, scans = {} }
    local rows = self.db.diagnostics.errors
    rows[#rows + 1] = { area = tostring(area or "Unknown"), message = tostring(message or "Unknown error"):sub(1, 300), at = self:Now() }
    while #rows > 35 do table.remove(rows, 1) end
end

function FCM:ScanAll()
    if not self.db then return false end
    local stages = {
        {"Basic", "ScanBasic"}, {"Bags", "ScanBags"}, {"Gear", "ScanGear"},
        {"Professions", "ScanProfessions"}, {"Reputation", "ScanReputations"},
        {"Talents", "ScanTalents"}, {"Recipes", "ScanRecipes"},
    }
    local succeeded = 0
    for _, row in ipairs(stages) do
        local fn = self[row[2]]
        if type(fn) == "function" then
            local ok, message = pcall(fn, self)
            if ok then succeeded = succeeded + 1 else self:RecordError(row[1], message) end
        end
    end
    if self.bankOpen and self.ScanBank then
        local ok, message = pcall(self.ScanBank, self)
        if not ok then self:RecordError("Bank", message) end
    end
    self.db.diagnostics = self.db.diagnostics or {errors={}, scans={}}
    self.db.diagnostics.scans[self.currentKey or "unknown"] = self:Now()
    if self.Refresh then self:Refresh() end
    return succeeded == #stages, succeeded, #stages
end

function FCM:DataQuality(ch)
    if not ch then return {} end
    local fields = {
        {"Equipment", "gear"}, {"Bags", "bags"}, {"Bank", "bank"},
        {"Professions", "professions"}, {"Recipes", "recipes"},
        {"Reputation", "reputation"}, {"Talents", "talents"}
    }
    local result = {}
    for _, f in ipairs(fields) do
        local status=self:ScanFreshness(ch,f[2])
        result[#result + 1] = {name=f[1], category=f[2],timestamp=status.timestamp,
            age=status.age,state=status.status,label=status.label}
    end
    return result
end

function FCM:DiagnosticsReport()
    local interface="Unknown"
    if type(GetBuildInfo)=="function" then
        local ok, a,b,c,d=pcall(GetBuildInfo)
        if ok and d then interface=tostring(d) end
    end
    local rows = {"FCM v" .. tostring(self.version), "Build: " .. tostring(self.build or "unlabeled"), "Interface: " .. interface, ""}
    local count = 0
    for _ in pairs((self.db and self.db.characters) or {}) do count = count + 1 end
    rows[#rows+1] = "Saved characters: " .. count
    rows[#rows+1] = "Craft requests: " .. #(self.db.craftingQueue or {})
    rows[#rows+1] = "Completed requests: " .. #(self.db.requestHistory or {})
    rows[#rows+1] = "Active registered events: " .. tostring(self.events and (function() local n=0 for _ in pairs(self.events) do n=n+1 end return n end)() or 0)
    local own = self:Current()
    rows[#rows+1] = ""
    rows[#rows+1] = "Current character data:"
    for _, item in ipairs(self:DataQuality(own)) do
        rows[#rows+1] = "  " .. item.name .. ": " .. item.label
    end
    local errors = self.db.diagnostics and self.db.diagnostics.errors or {}
    rows[#rows+1] = ""
    rows[#rows+1] = "Recent API errors: " .. #errors
    for i=math.max(1,#errors-9),#errors do
        local e=errors[i]
        rows[#rows+1] = "  " .. self:Age(e.at) .. " [" .. e.area .. "] " .. e.message
    end
    rows[#rows+1] = ""
    rows[#rows+1] = "This report contains no character credentials or private chat."
    return table.concat(rows, "\n")
end
