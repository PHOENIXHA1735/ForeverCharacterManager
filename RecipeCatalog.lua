local _, FCM = ...
-- Documentary catalogue; this is not a complete/live vendor stock listing.
-- Recipe names, faction reputation thresholds and costs below come from
-- published 2026-11-09 references; IDs are deliberately not guessed.
FCM.recipeCatalogEdition="2026-11-09"
FCM.recipeCatalog={
 {name="Venomous Smoothie",profession="Cooking",skill=25,favor=30,standing=4,source="Merchant's Favor vendor",status="Reference, vendor unverified"},
 {name="Slimy Smoothie",profession="Cooking",skill=100,favor=30,standing=4,source="Merchant's Favor vendor",status="Reference, vendor unverified"},
 {name="Mrrggl Smrrthle",profession="Cooking",skill=125,favor=30,standing=4,source="Merchant's Favor vendor",status="Reference, vendor unverified"},
 {name="Calcified Smoothie",profession="Cooking",skill=180,favor=60,standing=5,source="Merchant's Favor vendor",status="Reference, vendor unverified"},
 {name="Spicy Smoothie",profession="Cooking",skill=200,favor=60,standing=5,source="Merchant's Favor vendor",status="Reference, vendor unverified"},
 {name="Wicked Smoothie",profession="Cooking",skill=250,favor=90,standing=6,source="Merchant's Favor vendor",status="Reference, vendor unverified"},
}
FCM.recipeCatalogSources={
 "https://www.method.gg/wow-forever/azerorth-commerce-authority-and-durotar-supply-and-logistics-reputation-guide",
 "https://forevertome.com/professions/tailoring",
 "https://forever-hub.com/en/crafting",
}
function FCM:CatalogRecords()
    local result={}
    for _,entry in ipairs(self.recipeCatalog or {}) do result[#result+1]=entry end
    if self.UnlearnedRecipes then
        for _,entry in ipairs(self:UnlearnedRecipes()) do
            result[#result+1]={name=entry.name,profession=entry.profession,
                outputID=entry.outputID,recipeID=entry.id,source=entry.source or "Profession window",
                seenOn=entry.seenOn,status="Scanned: not learned (source unverified)"}
        end
    end
    if self.db and type(self.db.catalog)=="table" then
        for _,entry in pairs(self.db.catalog) do result[#result+1]=entry end
    end
    table.sort(result,function(a,b)return (a.name or "")<(b.name or "") end)
    return result
end
function FCM:CatalogAdd(name,profession,standing,source)
    if not self.db or not name or #name<2 then return false end
    self.db.catalog=self.db.catalog or {}
    self.db.catalog[string.lower(name)]={name=name,profession=profession or "Unknown",standing=tonumber(standing),source=source or "Manually entered",status="User-entered; verify in game"}
    return true
end

function FCM:ReputationForCatalog(ch,entry)
    if not ch or not entry or not entry.standing then return nil end
    local name=(ch.faction=="Horde") and "Durotar Supply and Logistics" or "Azeroth Commerce Authority"
    local record
    for _,rep in pairs(ch.reputations or {}) do
        if string.lower(rep.name or "")==string.lower(name) then record=rep;break end
    end
    local current=record and record.reaction or nil
    local toNext
    if record and record.value and record.high and current and current<entry.standing then
        toNext=math.max(0,record.high-record.value)
    end
    return {faction=name,required=entry.standing,current=current,
        unlocked=current and current>=entry.standing or false,
        nextStandingMissing=toNext,stamp=record and record.updated}
end
