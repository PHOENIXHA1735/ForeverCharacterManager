-- FCM v0.9.0 crafting profession classification regressions (texlua / Lua 5.1).
local base='ForeverCharacterManager/'
local function eq(got,want,label)
    if got~=want then error((label or 'Mismatch')..': expected '..tostring(want)..', got '..tostring(got),2) end
end
local function mkFCM()
    local ch={key='frosty',professions={},recipes={},unlearnedRecipes={}}
    local offline={key='spotty',professions={},recipes={},unlearnedRecipes={}}
    local fcm={db={characters={}},externalData={recipes={}},_roster={ch,offline}}
    function fcm:Current() return ch end
    function fcm:Characters() return self._roster end
    function fcm:Now() return 123456 end
    function fcm:Try(fn,...)
        if not fn then return nil end
        local ok,a,b,c,d,e,f,g=pcall(fn,...)
        if ok then return a,b,c,d,e,f,g end
        return nil
    end
    assert(loadfile(base..'Crafting.lua'))('ForeverCharacterManager',fcm)
    return fcm,ch,offline
end

local passed=0
local function test(label,fn)
    fn(); passed=passed+1; print('PASS: '..label)
end

test('mixed recipes use their own profession, not the active Tailoring pane',function()
    local fcm,ch=mkFCM()
    C_TradeSkillUI={
        GetBaseProfessionInfo=function() return {professionName='Tailoring',skillLevel=55,maxSkillLevel=75,professionID=197} end,
        GetChildProfessionInfo=function() return {} end,
        GetAllRecipeIDs=function() return {101,102,103,104} end,
        GetRecipeInfo=function(id) return {learned=id~=104,name=({[101]='Brilliant Smallfish',[102]='Bolt of Linen Cloth',[103]='Beer Basted Boar Ribs',[104]='Unlearned Food'})[id]} end,
        GetProfessionInfoByRecipeID=function(id)
            return {professionName=({[101]='Cooking',[102]='Tailoring',[103]='Cooking',[104]='Cooking'})[id]}
        end,
        GetRecipeSchematic=function() return {reagentSlotSchematics={}} end,
        GetRecipeOutputItemData=function() return nil end,
        GetRecipeSourceText=function() return nil end,
    }
    fcm:ScanRecipes()
    eq(ch.recipes[101].profession,'Cooking','fish recipe')
    eq(ch.recipes[102].profession,'Tailoring','linen recipe')
    eq(ch.recipes[103].profession,'Cooking','ribs recipe')
    eq(ch.unlearnedRecipes[104].profession,'Cooking','unlearned food')
    eq(ch.professions['Tailoring'].skill,55)
    eq(ch.professions['Cooking'],nil,'no invented profession skill scan')
end)

test('trusted public reference repairs old offline records without deleting recipes',function()
    local fcm,ch,offline=mkFCM()
    C_TradeSkillUI={}
    ch.recipes[101]={id=101,name='Brilliant Smallfish',learned=true,profession='Tailoring',reagents={{itemID=100,count=1}}}
    offline.recipes[102]={id=102,name='Beer Basted Boar Ribs',learned=true,profession='Tailoring'}
    offline.recipes[103]={id=103,name='Unknown recipe',learned=true,profession='Tailoring'}
    offline.unlearnedRecipes[104]={id=104,name='Unknown Cooking recipe',profession='Tailoring'}
    fcm.externalData.recipes[101]={profession='Cooking'}
    fcm.externalData.recipes['102']={profession='Cooking'} -- string-keyed import also works
    fcm.externalData.recipes[104]={profession='Cooking'}
    fcm.allRecipesCache={stale=true}
    eq(fcm:RepairRecipeProfessions(),3)
    eq(ch.recipes[101].profession,'Cooking')
    eq(offline.recipes[102].profession,'Cooking')
    eq(offline.recipes[103].profession,'Tailoring','unknown is preserved')
    eq(offline.unlearnedRecipes[104].profession,'Cooking')
    eq(ch.recipes[101].reagents[1].itemID,100,'ingredients retained')
    eq(fcm.allRecipesCache,nil,'cache invalidated')
    eq(fcm:RepairRecipeProfessions(),0,'idempotent')
end)

test('authoritative client profession takes precedence over historical reference',function()
    local fcm,ch=mkFCM()
    C_TradeSkillUI={GetProfessionInfoByRecipeID=function() return {professionName='Cooking'} end}
    fcm.externalData.recipes[201]={profession='Tailoring'}
    local profession,verified=fcm:RecipeProfession(201,'Tailoring')
    eq(profession,'Cooking'); eq(verified,true)
    ch.recipes[201]={id=201,profession='Tailoring',learned=true}
    eq(fcm:RepairRecipeProfessions(),1)
    eq(ch.recipes[201].profession,'Cooking')
end)

test('unavailable or throwing API never destroys a saved profession',function()
    local fcm,ch=mkFCM()
    C_TradeSkillUI={GetProfessionInfoByRecipeID=function() error('not ready') end}
    ch.recipes[202]={id=202,profession='Tailoring',learned=true}
    eq(fcm:RepairRecipeProfessions(),0)
    eq(ch.recipes[202].profession,'Tailoring')
    local profession,verified=fcm:RecipeProfession(202,'Tailoring')
    eq(profession,'Tailoring'); eq(verified,false)
end)

test('blank and zero-skill profession slots are ignored',function()
    local fcm,ch=mkFCM()
    assert(loadfile(base..'Scan.lua'))('ForeverCharacterManager',fcm)
    C_TradeSkillUI=nil
    GetProfessions=function() return 1,2,3 end
    GetProfessionInfo=function(index)
        if index==1 then return '',nil,0,0 end
        if index==2 then return '   ',nil,0,0 end
        return 'Cooking',nil,60,75
    end
    fcm:ScanProfessions()
    eq(ch.professions[''],nil)
    eq(ch.professions['   '],nil)
    eq(ch.professions['Cooking'].skill,60)
end)

print('All '..passed..' crafting profession regression tests passed.')
