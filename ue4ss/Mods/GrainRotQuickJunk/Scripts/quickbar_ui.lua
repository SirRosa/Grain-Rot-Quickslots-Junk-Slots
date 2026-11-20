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
    if count>=10 then return true,"native_widgets_10" end
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
        if type(log)=="function" then
            log("[QUICK UI] new native widget "..i.."/10, game index="..tostring(index))
        end
    end
    if type(log)=="function" then
        log("[QUICK UI] appended "..made.." native game slot widgets, count="..tostring(len(widgets)))
    end
    return len(widgets)>=10,"added_native_widgets"
end
function M.reset()
    M.tries={}
    M.warned={}
end
return M
