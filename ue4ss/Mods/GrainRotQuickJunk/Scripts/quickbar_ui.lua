-- Adds native game InventorySlotWidget instances for verified native
-- inventory slots 5-10. Never creates cosmetic-only extra slots: requires
-- player ItemSlots >= 10 first. Uses the game's own SlotWidgetClass.
local M={tries={},warned={}}
local function valid(o)
    if o==nil then return false end
    local ok,y=pcall(function() return o:IsValid() end)
    return ok and y==true
end
local function get(o,k)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
    return nil
end
local function id(o)
    if not valid(o) then return nil end
    local ok,n=pcall(function() return o:GetFullName() end)
    return ok and tostring(n) or nil
end
local function len(a)
    local ok,n=pcall(function() return #a end)
    return ok and n or nil
end
local DIGITS={"5","6","7","8","9","0"}
local KEY_NAMES={"Five","Six","Seven","Eight","Nine","Zero"}
local function textValue(value)
    if value==nil then return nil end
    local ok,t=pcall(function() return value:ToString() end)
    return ok and tostring(t) or tostring(value)
end
local function makeText(s)
    -- FText is a callable table (not Lua function) on UE4SS 3.0.1.
    if FText==nil then return nil end
    local ok,v=pcall(FText,s)
    if ok then return v end
end
local function makeName(s)
    if FName==nil then return nil end
    local ok,v=pcall(FName,s)
    if ok then return v end
end
local function configureLabel(widget,slot,log)
    if slot<5 or slot>10 or not valid(widget) then return false,"bad_widget" end
    local icon=get(widget,"InputIcon")
    if not valid(icon) then return false,"native_input_icon_missing" end
    local digit=DIGITS[slot-4]
    local keyName=KEY_NAMES[slot-4]
    -- The default cloned widget still points to its asset's keyboard action
    -- and displays a modifier such as Ctrl. Force "Key" mode instead.
    local key=makeName(keyName)
    if key then
        local assigned=pcall(function() icon.InputKey={KeyName=key} end)
        if type(log)=="function" then
            log("[QUICK UI] native key "..digit.." FKey assigned="..tostring(assigned))
        end
    end
    pcall(function() icon.IconType=1 end) -- EHeldenInputIconType.Key
    pcall(function() icon.bUseGamepadAction=false end)
    -- Explicit visual label is necessary: key-binding layout is computed
    -- separately by the game and needs not correspond to synthetic slots.
    local inputText=get(icon,"InputKeyText")
    if not valid(inputText) then return false,"InputKeyText_missing" end
    local literal=makeText(digit)
    if not literal then return false,"FText_constructor_missing" end
    local ok,err=pcall(function() inputText:SetText(literal) end)
    if not ok then return false,"set_text_failed_"..tostring(err) end
    pcall(function() inputText:SetVisibility(0) end)
    local picture=get(icon,"InputIconWidget")
    if valid(picture) then pcall(function() picture:SetVisibility(2) end) end
    local actual
    pcall(function() actual=textValue(inputText:GetText()) end)
    if actual and actual~=digit then return false,"readback_"..actual end
    return true,digit
end
function M.refreshLabels(pc,log)
    if not valid(pc) then return false,"no_controller" end
    local hud
    pcall(function() hud=pc:GetHUD() end)
    local ui=get(get(hud,"PlayerHudWidget"),"InventoryWidget")
    if not valid(ui) then return false,"missing_inventory_ui" end
    local widgets=get(ui,"SlotWidgets")
    if not widgets or (len(widgets) or 0)<10 then return false,"widgets_missing" end
    for i=5,10 do
        local ok,reason=configureLabel(get(widgets,i),i,log)
        if not ok then return false,"label_"..i.."_"..reason end
    end
    return true,"labels_5_to_0"
end

function M.ensure(pc,pawn,log)
    if not valid(pc) or not valid(pawn) then return false,"no_player" end
    local playerSlots=get(pawn,"ItemSlots")
    local native=len(playerSlots)
    if not native or native<10 then return false,"player_native_slots_not_10" end
    local hud
    pcall(function() hud=pc:GetHUD() end)
    local ui=get(get(hud,"PlayerHudWidget"),"InventoryWidget")
    if not valid(ui) then return false,"native_inventory_widget_unavailable" end
    local key=id(ui) or "unknown"
    local widgets=get(ui,"SlotWidgets")
    local count=len(widgets)
    if not count then return false,"native_widget_array_unavailable" end
    if count>=10 then
        local ok,why=M.refreshLabels(pc,log)
        return ok,ok and "native_widgets_10_labeled" or "native_widgets_10_unlabeled_"..tostring(why)
    end
    if count<4 then return false,"initial_widgets_missing" end
    if (M.tries[key] or 0)>=3 then return false,"ui_attempt_limit" end
    M.tries[key]=(M.tries[key] or 0)+1
    -- Native game may regenerate its own slot widgets once inventory expands.
    if M.tries[key]==1 then
        pcall(function() ui:OnSetInventoryWidget() end)
        local refreshed=len(widgets)
        if refreshed and refreshed>=10 then return true,"game_rebuilt_widget_bar" end
    end
    local cls=get(ui,"SlotWidgetClass")
    local container=get(ui,"InventorySlotBox")
    if not valid(cls) or not valid(container) then
        return false,"native_slot_widget_class_or_panel_missing"
    end
    local ok,lib=pcall(StaticFindObject,"/Script/UMG.Default__WidgetBlueprintLibrary")
    if not ok or not valid(lib) then return false,"widget_blueprint_library_unavailable" end
    local made=0
    for i=count+1,10 do
        local created,child=pcall(function() return lib:Create(pc,cls,pc) end)
        if not created or not valid(child) then
            return false,"slot_widget_create_failed_"..i
        end
        local attached,slot=pcall(function() return container:AddChild(child) end)
        if not attached or not valid(slot) then
            pcall(function() child:RemoveFromParent() end)
            return false,"slot_widget_attach_failed_"..i
        end
        local added,err=pcall(function() widgets[i]=child end)
        if not added or len(widgets)~=i then
            pcall(function() child:RemoveFromParent() end)
            return false,"slot_widget_array_append_failed_"..i..":"..tostring(err)
        end
        made=made+1
        local index
        pcall(function() index=child:GetSlotIndex() end)
        local okLabel,reason=configureLabel(child,i,log)
        if type(log)=="function" then
            log("[QUICK UI] new native widget "..i.."/10, game index="..tostring(index)..
                ", label="..tostring(reason).." ("..tostring(okLabel)..")")
        end
    end
    if type(log)=="function" then
        log("[QUICK UI] appended "..made.." native game slot widgets, count="..tostring(len(widgets)))
    end
    local ready,why=M.refreshLabels(pc,log)
    return ready,ready and "added_native_widgets_labeled" or "created_widgets_but_labels_failed_"..tostring(why)
end
function M.reset()
    M.tries={}
    M.warned={}
end
return M
