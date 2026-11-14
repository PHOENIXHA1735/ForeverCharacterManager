-- QA6e regression: Enter must preserve typed quantity before StaticPopup hides.
-- No WoW client required: mock the alternate edit-box fields/API variants.
local function eq(got,want,label)
    if got~=want then error((label or 'mismatch')..': expected '..tostring(want)..', got '..tostring(got),2) end
end
local function fixture(variant,hideFirst)
    local fcm={db={characters={spotty={key='spotty'}}},messages={}}
    function fcm:Say(message) self.messages[#self.messages+1]=message end
    function fcm:ValidCraftQuantity(raw)
        local n=tonumber(raw)
        return n and n>=1 and n<=999 and n%1==0 and n or nil
    end
    function fcm:CraftRequestQuantity(req) return req.quantity or 1 end
    function fcm:UpdateQueuedCraftQuantity(req,n) req.quantity=n;return true,'Updated' end
    assert(loadfile('ForeverCharacterManager/UI.lua'))('ForeverCharacterManager',fcm)
    function fcm.UI:Refresh() fcm.refreshed=true end
    function fcm.UI:ShowCrafterMenu(recipe,key,existing,crafters,qty)
        fcm.accepted={recipe=recipe.id,key=key,qty=qty}
    end
    StaticPopupDialogs={}
    local popup={}
    StaticPopup_Show=function(which,_,__,data)
        local def=StaticPopupDialogs[which]
        popup.definition=def
        popup.data=data
        local edit={value=''}
        function edit:SetText(t)
            self.value=t
            if def.EditBoxOnTextChanged then def.EditBoxOnTextChanged(self) end
        end
        function edit:GetText() return self.value end
        function edit:HighlightText() end
        function edit:SetFocus() end
        local dialog={data=data}
        function edit:GetParent() return dialog end
        if variant=='lower' then dialog.editBox=edit
        elseif variant=='upper' then dialog.EditBox=edit
        elseif variant=='method' then function dialog:GetEditBox() return edit end
        elseif variant=='named' then
            function dialog:GetName() return 'StaticPopup1' end
            _G.StaticPopup1EditBox=edit
        else error('Unknown variant') end
        dialog.button1={Click=function()
            if hideFirst then
                -- Simulate a client clearing the input before OnAccept fires.
                edit.value=''
            end
            def.OnAccept(dialog)
        end}
        popup.dialog=dialog
        popup.edit=edit
        def.OnShow(dialog)
        return dialog
    end
    local recipe={id=99,name='Red Linen Bag'}
    fcm.UI:PromptCraftQuantity(recipe,'spotty')
    return fcm,popup,recipe
end

local count=0
local function test(label,fn)
    fn();count=count+1;print('PASS: '..label)
end

test('Enter saves typed 3 even when client clears input before accepting',function()
    local fcm,popup=fixture('lower',true)
    eq(popup.edit:GetText(),'1','default quantity')
    popup.edit:SetText('3')
    popup.definition.EditBoxOnEnterPressed(popup.edit)
    eq(fcm.accepted.qty,3)
    eq(#fcm.messages,0)
end)

test('Continue button accepts 6 using capitalized EditBox field',function()
    local fcm,popup=fixture('upper',false)
    eq(popup.edit:GetText(),'1')
    popup.edit:SetText('6')
    popup.dialog.button1:Click()
    eq(fcm.accepted.qty,6)
end)

test('Continue uses captured value if input was cleared before callback',function()
    local fcm,popup=fixture('upper',true)
    popup.edit:SetText('3')
    popup.dialog.button1:Click()
    eq(fcm.accepted.qty,3)
end)

test('GetEditBox accessor works for WoW client variants',function()
    local fcm,popup=fixture('method',false)
    popup.edit:SetText('20')
    popup.dialog.button1:Click()
    eq(fcm.accepted.qty,20)
end)

test('global StaticPopup1EditBox name works when no field is exposed',function()
    local fcm,popup=fixture('named',false)
    popup.edit:SetText('4')
    popup.dialog.button1:Click()
    eq(fcm.accepted.qty,4)
    _G.StaticPopup1EditBox=nil
end)

test('editing an existing request updates its requested output count',function()
    local fcm,popup,recipe=fixture('upper',false)
    local req={quantity=8}
    fcm.UI:PromptCraftQuantity(recipe,'spotty',req)
    eq(popup.edit:GetText(),'8')
    popup.edit:SetText('3')
    popup.definition.EditBoxOnEnterPressed(popup.edit)
    eq(req.quantity,3)
    eq(fcm.refreshed,true)
end)

test('invalid text does not create a request',function()
    local fcm,popup=fixture('lower',false)
    popup.edit:SetText('0')
    popup.definition.EditBoxOnEnterPressed(popup.edit)
    eq(fcm.accepted,nil)
    eq(#fcm.messages,1)
end)

print('All '..count..' craft popup regressions passed.')
