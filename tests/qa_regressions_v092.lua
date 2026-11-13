-- FCM v0.9.1 QA regression harness, runs under texlua (no game access needed).
local base='ForeverCharacterManager/'
local tests, passed={},0
local function test(name, fn) tests[#tests+1]={name,fn} end
local function eq(actual,expected,message)
    if actual~=expected then error((message or 'Mismatch')..': expected '..tostring(expected)..', got '..tostring(actual),2) end
end
local function loadModule(name,fcm) assert(loadfile(base..name))('ForeverCharacterManager',fcm) end
local function mkScanFcm()
    local errors={}
    local ch={key='owner',name='Frosty',faction='Alliance'}
    local fcm={_errors=errors,_ch=ch,_boeBagBaselineReady=false}
    function fcm:Try(fn,...)
        if not fn then return nil end
        local good,a,b,c=pcall(fn,...)
        if good then return a,b,c end
        self:RecordError('API',a)
    end
    function fcm:RecordError(area,msg) errors[#errors+1]={area=area,msg=msg} end
    function fcm:Current() return ch end
    function fcm:Now() return 1234 end
    loadModule('Scan.lua',fcm)
    C_Container={}
    C_Container.GetContainerNumSlots=function(bag) if bag==0 then return 1 else return 0 end end
    C_Container.GetContainerItemInfo=function(bag,slot)
        if bag==0 and slot==1 then return {itemID=1234,stackCount=1,itemName='Cape'} end
    end
    return fcm,ch,errors
end

test('Bag binding uses ItemLocation colon method / actual self',function()
    local fcm,ch,errors=mkScanFcm()
    local locCalls,isBoundCalls=0,0
    ItemLocation={}
    function ItemLocation:CreateFromBagAndSlot(bag,slot)
        eq(self,ItemLocation,'self on ItemLocation')
        eq(bag,0)
        eq(slot,1)
        locCalls=locCalls+1
        return {bagID=bag,slotIndex=slot,IsValid=function() return true end, HasAnyLocation=function() return true end}
    end
    C_Item={}
    C_Item.DoesItemExist=function(loc) return loc.bagID==0 end
    C_Item.IsBound=function(loc) isBoundCalls=isBoundCalls+1; eq(loc.slotIndex,1); return false end
    fcm:ScanBags()
    eq(ch.bags['0:1'].bound,false)
    eq(locCalls,1)
    eq(isBoundCalls,1)
    eq(#errors,0)
end)

test('Invalid ItemLocation stays unknown; no strict API invocation',function()
    local fcm,ch,errors=mkScanFcm()
    ItemLocation={CreateFromBagAndSlot=function(self,bag,slot)
        return {IsValid=function() return false end,HasAnyLocation=function() return true end}
    end}
    C_Item={IsBound=function() error('must not be called') end}
    fcm:ScanBags()
    eq(ch.bags['0:1'].bound,nil)
    eq(#errors,0)
end)

test('Missing item-location API keeps binding unknown',function()
    local fcm,ch,errors=mkScanFcm()
    ItemLocation=nil;C_Item={IsBound=function() error('should never be called') end}
    fcm:ScanBags()
    eq(ch.bags['0:1'].bound,nil)
    eq(#errors,0)
end)

test('Known container isBound bypasses strict lookup',function()
    local fcm,ch,errors=mkScanFcm()
    C_Container.GetContainerItemInfo=function() return {itemID=1234,isBound=true} end
    ItemLocation={CreateFromBagAndSlot=function() error('should never be called') end}
    C_Item={IsBound=function() error('should never be called') end}
    fcm:ScanBags()
    eq(ch.bags['0:1'].bound,true)
    eq(#errors,0)
end)

test('False reported by container is retained without a second API lookup',function()
    local fcm,ch,errors=mkScanFcm()
    C_Container.GetContainerItemInfo=function() return {itemID=1234,isBound=false} end
    ItemLocation={CreateFromBagAndSlot=function() error('must not query existing false') end}
    C_Item={IsBound=function() error('must not query existing false') end}
    fcm:ScanBags()
    eq(ch.bags['0:1'].bound,false)
    eq(#errors,0)
end)

test('Missing item instance keeps binding unknown, not unbound',function()
    local fcm,ch,errors=mkScanFcm()
    ItemLocation={CreateFromBagAndSlot=function(self,bag,slot) return {bagID=bag,slotIndex=slot} end}
    C_Item={DoesItemExist=function() return false end,IsBound=function() error('must not query absent instance') end}
    fcm:ScanBags()
    eq(ch.bags['0:1'].bound,nil)
    eq(#errors,0)
end)

test('Strict API failure is logged once per pass, binding stays unknown',function()
    local fcm,ch,errors=mkScanFcm()
    C_Container.GetContainerNumSlots=function(bag) return bag==0 and 3 or 0 end
    C_Container.GetContainerItemInfo=function(bag,slot) if bag==0 then return {itemID=1234} end end
    ItemLocation={CreateFromBagAndSlot=function(self,bag,slot) return {bagID=bag,slotIndex=slot} end}
    C_Item={DoesItemExist=function() return true end,IsBound=function() error('mock strict API failure') end}
    fcm:ScanBags()
    eq(#errors,1)
    eq(errors[1].area,'Binding')
    for i=1,3 do eq(ch.bags['0:'..i].bound,nil) end
end)

local function mkBoe()
    -- Unlike live client, this harness provides deterministic game data.
    local owner={key='f',name='Frosty',faction='Alliance',ruleset='Normal',region='US',level=16,gearStamp=1000,
        bags={['0:1']={itemID=1234,count=1,bound=false}}}
    local spotty={key='s',name='Spotty',faction='Alliance',ruleset='Normal',region='US',level=1,gearStamp=1000}
    local itty={key='i',name='Itty',faction='Horde',ruleset='Normal',region='US',level=1,gearStamp=1000}
    local roster={owner,spotty,itty}
    local fcm={db={settings={minimumUpgrade=1,boeFutureLevels=10}},_roster=roster}
    function fcm:Now() return 2000 end
    function fcm:Characters() return self._roster end
    function fcm:Current() return owner end
    function fcm:ScanFreshness() return {status='fresh',label='Current'} end
    function fcm:NormalizeFaction(s)
        if type(s)~='string' then return nil end
        s=s:lower()
        return s=='alliance' and 'Alliance' or s=='horde' and 'Horde' or nil
    end
    function fcm:NormalizeRuleset(s) return s end
    function fcm:CanCollaborate(a,b)
        if a.key==b.key then return true end
        if not self:NormalizeFaction(a.faction) or not self:NormalizeFaction(b.faction) then return false,'Faction not recorded' end
        if a.faction~=b.faction then return false,'Opposing factions cannot transfer' end
        if a.ruleset~=b.ruleset then return false,'Different ruleset' end
        if a.region~=b.region then return false,'Different region' end
        return true
    end
    fcm.Gear={}
    function fcm.Gear:Info(item) return {name='Reinforced Linen Cape',bindType=2,level=7,link='item:1234'} end
    local deltas={f=0,s=3.5,i=9}
    function fcm.Gear:CompareItem(item,ch,_,opts) return {status='ok',delta=deltas[ch.key]} end
    loadModule('BoEProtection.lua',fcm)
    return fcm,owner,spotty,itty,deltas
end

test('Alliance BoE KEEP includes Spotty, excludes higher-scored Horde Itty',function()
    local fcm,owner,spotty,itty=mkBoe()
    local r=fcm:BoEProtectionCheck(1234,owner)
    eq(r.status,'keep')
    eq(r.best.name,'Spotty')
    eq(#r.excluded,1)
    eq(r.excluded[1].name,'Itty')
    eq(#r.candidates,1)
    assert(r.excluded[1].reason:find('Opposing faction',1,true))
end)

test('Horde-only hypothetical upgrade cannot cause Alliance KEEP/REVIEW',function()
    local fcm,owner,spotty,itty,deltas=mkBoe()
    deltas.s=0
    local r=fcm:BoEProtectionCheck(1234,owner)
    eq(r.status,'no-known-upgrade')
    eq(#r.candidates,0)
    eq(#r.excluded,1)
end)

test('Cross-ruleset recipients excluded regardless of upgrade amount',function()
    local fcm,owner,spotty,itty=mkBoe()
    spotty.ruleset='PvP'
    local r=fcm:BoEProtectionCheck(1234,owner)
    eq(r.status,'no-known-upgrade')
    eq(#r.excluded,2)
end)

test('Unknown ruleset is not confirmed transferable',function()
    local fcm,owner,spotty,itty=mkBoe()
    spotty.ruleset=nil
    local r=fcm:BoEProtectionCheck(1234,owner)
    eq(r.status,'review')
    eq(#r.candidates,1)
    eq(r.candidates[1].transferable,false)
end)

test('Reverse direction: Horde owner excludes Alliance recipient',function()
    local fcm,owner,spotty,itty,deltas=mkBoe()
    fcm._roster={itty,owner,spotty}
    itty.bags={['0:2']={itemID=1234,count=1,bound=false}}
    deltas.i=0;deltas.f=11;deltas.s=12
    local r=fcm:BoEProtectionCheck(1234,itty)
    eq(r.status,'no-known-upgrade')
    eq(#r.excluded,2)
end)

test('Known bound copy cannot be mailed even to same faction',function()
    local fcm,owner,spotty,itty=mkBoe()
    owner.bags['0:1'].bound=true
    local r=fcm:BoEProtectionCheck(1234,owner)
    eq(r.status,'bound')
    eq(r.candidates[1].transferable,false)
end)

test('Unknown binding does not become confirmed transfer',function()
    local fcm,owner,spotty,itty=mkBoe()
    owner.bags['0:1'].bound=nil
    local r=fcm:BoEProtectionCheck(1234,owner)
    eq(r.status,'review')
    eq(r.candidates[1].transferable,false)
end)

test('Tooltip exclusion text exists in loaded source',function()
    local data=assert(io.open(base..'Tooltips.lua')):read('*a')
    assert(data:find('Excluded '..'"',1,true))
    assert(data:find('Forever Character Manager v',1,true))
end)

test('School-aware gear: Frost damage cape outranks generic +1 for Frost, not Arcane',function()
    local fcm={currentKey='not-this-character'}
    function fcm:Try(fn,...) if fn then return fn(...) end end
    function fcm:GearActivity() return 'leveling' end
    function fcm:Mode() return 'dps' end
    local refs={
        [111]={name="Buccaneer's Cape of Frozen Wrath",armor=16,effect='Equip: Increases damage done by Frost spells and effects by up to 4.'},
        [222]={name='Reinforced Linen Cape',armor=11,effect='Equip: Increases damage and healing done by magical spells and effects by up to 1.'},
    }
    local function getid(x) if type(x)=='number' then return x end return tonumber(tostring(x):match('item:(%d+)')) end
    C_Item={}
    C_Item.GetItemInfo=function(x)
        local r=refs[getid(x)]; if not r then return nil end
        return r.name,'item:'..getid(x),2,10,7,'Armor','Cloth',1,'INVTYPE_CLOAK',nil,67,4,1,2
    end
    C_Item.GetItemStats=function(x)
        local r=refs[getid(x)]; if not r then return nil end
        return {ITEM_MOD_ARMOR_SHORT=r.armor,ITEM_MOD_SPELL_POWER_SHORT=getid(x)==111 and 4 or 1}
    end
    C_TooltipInfo={GetHyperlink=function(x)
        local r=refs[getid(x)];if not r then return nil end
        return {lines={{leftText=r.name},{leftText=r.effect}}}
    end}
    loadModule('Gear.lua',fcm)
    local function character(spec)
        return {key='f',class='MAGE',talentSpec=spec,level=16,gearStamp=123,gear={[15]={link='item:111'}}}
    end
    local frost=fcm.Gear:CompareItem('item:222',character('Frost'))
    local arcane=fcm.Gear:CompareItem('item:222',character('Arcane'))
    eq(frost.status,'ok');eq(arcane.status,'ok')
    assert(frost.delta<0,'Frost spec must not consider +1 general better than +4 Frost')
    assert(arcane.delta>0,'Arcane spec gets no benefit from Frost-only bonus')
end)

for _,testCase in ipairs(tests) do
    local ok,err=pcall(testCase[2]); if not ok then
        io.stderr:write('FAIL: '..testCase[1]..'\n  '..tostring(err)..'\n')
        os.exit(1)
    end
    passed=passed+1
    io.write('PASS: '..testCase[1]..'\n')
end
io.write('PASS: '..passed..' regression scenarios\n')
