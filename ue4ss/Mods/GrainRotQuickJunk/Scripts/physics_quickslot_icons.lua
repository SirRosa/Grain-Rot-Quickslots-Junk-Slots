-- Physical-object thumbnails on the EXISTING native WBP_InventorySlot.
-- Verified ObjectDump:
--   WBP_InventorySlot_C.Icon : UMG.Image
--   UMG.Image:SetBrushFromTexture(Texture2D,...)
--   HeldenConstructAsset.Icon : UObject (usually Texture2D)
-- We never paint onto game equipable icons on occupied native item slots.
-- A readable [$] placeholder is used only if the actual game texture is
-- absent or UMG texture marshalling fails. No SceneCapture per frame.
local M={}
local DIGITS={"1","2","3","4","5","6","7","8","9","0"}
local cache={}
local fallback=nil
local fallbackChecked=false
local fallbackKind=nil
local function valid(o)
    if not o then return false end
    local ok,b=pcall(function() return o:IsValid() end)
    return ok and b==true
end
local function get(o,k)
    if not o then return nil end
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
end
local function objName(o)
    if not valid(o) then return nil end
    local ok,n=pcall(function() return o:GetFullName() end)
    return ok and tostring(n) or nil
end
local function imageOf(widget)
    return get(widget,"Icon")
end
local function getWidget(pc,slot)
    if not valid(pc) or type(slot)~="number" or slot<1 or slot>10 then
        return nil,"invalid_player_or_slot"
    end
    local ok,hud=pcall(function() return pc:GetHUD() end)
    if not ok or not valid(hud) then return nil,"native_hud_not_ready" end
    local ui=get(get(hud,"PlayerHudWidget"),"InventoryWidget")
    if not valid(ui) then return nil,"native_inventory_ui_not_ready" end
    local widgets=get(ui,"SlotWidgets")
    local n=0
    pcall(function() n=#widgets end)
    if n<10 then return nil,"native_widgets_not_10" end
    local w=get(widgets,slot)
    if not valid(w) then return nil,"slot_widget_missing_"..slot end
    return w
end
function M.canRender(pc,slot)
    local w,reason=getWidget(pc,slot)
    if not w then return false,reason end
    local img=imageOf(w)
    local label=get(get(w,"InputIcon"),"InputKeyText")
    if not valid(img) or not valid(label) then
        return false,"icon_or_label_widget_missing_"..slot
    end
    if not FText then
        return false,"FText_unavailable_cannot_mark_slot"
    end
    local exists=pcall(function() return FText("JUNK") end)
    if not exists then
        return false,"FText_failed_cannot_mark_slot"
    end
    return true,"native_WBP_InventorySlot_ready"
end
local function itemTexture(actor)
    if not valid(actor) then return nil end
    -- Furniture/construct objects expose ready-to-use game-generated icons.
    -- SetupConstructAsset and InitConAsset are reflected on physics actors.
    local candidates={
        "InitConAsset","SetupConstructAsset","SettingsAsset","SourceObject"
    }
    local function tryAsset(asset)
        if not valid(asset) then return nil end
        local tex=get(asset,"Icon")
        if valid(tex) then return tex,"construct_icon" end
        local embedded=get(asset,"ItemDataAsset") or get(asset,"InitConAsset")
        if valid(embedded) and valid(get(embedded,"Icon")) then
            return get(embedded,"Icon"),"item_icon"
        end
        return nil
    end
    for _,field in ipairs(candidates) do
        local asset=get(actor,field)
        local tex,kind=tryAsset(asset)
        if tex then return tex,kind end
    end
    local asset=actor
    do
        local tex,kind=tryAsset(asset)
        if tex then return tex,kind end
    end
    return nil
end
local function fallbackTexture()
    if fallbackChecked then return fallback,fallbackKind end
    fallbackChecked=true
    -- This is an ACTUAL loaded Grain Rot Texture2D from the user's UE5.7.4
    -- ObjectDump, not an invented path: /Game/UI/Textures/Icons/T_Gold.
    local goldPath="/Game/UI/Textures/Icons/T_Gold.T_Gold"
    if type(StaticFindObject)=="function" then
        local ok,tex=pcall(StaticFindObject,goldPath)
        if ok and valid(tex) then
            fallback=tex;fallbackKind="game_gold_texture"
            return fallback,fallbackKind
        end
    end
    -- Native UI item textures with "coin", "gold" or "money" identifiers
    -- make a sensible generic junk icon, avoiding expensive 3D capture.
    local singleton
    if type(FindFirstOf)=="function" then
        local ok,o=pcall(FindFirstOf,"HeldenDataSingleton")
        if ok and valid(o) then singleton=o end
    end
    local container=get(singleton,"ItemAssetContainer")
    local items=get(container,"ItemAssets")
    local len=0
    pcall(function() len=math.min(#items,256) end)
    for i=1,len do
        local a=get(items,i)
        local n=(objName(a) or ""):lower()
        if n:find("coin",1,true) or n:find("gold",1,true) or
            n:find("money",1,true) or n:find("scrap",1,true) then
            local tex=get(a,"Icon")
            if valid(tex) then
                fallback=tex
                fallbackKind="money_item_icon"
                return fallback,fallbackKind
            end
        end
    end
    -- A visible generic textured placeholder is preferable to a blank slot
    -- if the game's asset container exposes no coin image.
    if type(StaticFindObject)=="function" then
        local ok,tex=pcall(StaticFindObject,
            "/Engine/EngineResources/DefaultTexture.DefaultTexture")
        if ok and valid(tex) then
            fallback=tex
            fallbackKind="engine_default_texture"
        end
    end
    return fallback,fallbackKind
end
local function text(s)
    if not FText then return nil end
    local ok,t=pcall(FText,s)
    if ok then return t end
end
local function labelValue(label)
    local ok,v=pcall(function() return label:GetText():ToString() end)
    return ok and tostring(v) or nil
end
local function changeLabel(label,target)
    if not valid(label) then return false end
    if labelValue(label)==target then return true end
    local t=text(target)
    if not t then return false end
    local ok=pcall(function() label:SetText(t) end)
    return ok and (labelValue(label)==nil or labelValue(label)==target)
end
local function setVisible(w,flag)
    if not valid(w) then return false end
    return pcall(function() w:SetVisibility(flag and 0 or 2) end)
end
local function paint(slot,entry,pc)
    local widget,why=getWidget(pc,slot)
    if not widget then return false,why end
    local img=imageOf(widget)
    local label=get(get(widget,"InputIcon"),"InputKeyText")
    if not valid(img) or not valid(label) then
        return false,"native_slot_image_missing"
    end
    local key=objName(widget) or tostring(widget)
    local actor=entry and entry.actor
    local tex,source=itemTexture(actor)
    if not tex then
        tex,source=fallbackTexture()
        if not tex then source="text_currency" end
    end
    local mark=entry and (entry.state=="held" and "*" or "+") or "?"
    local targetLabel=DIGITS[slot]..mark
    local before=cache[slot]
    if not before or before.widget~=key then
        local oldBrush=get(img,"Brush")
        local oldVis,oldWidgetOpacity,oldRetainerOpacity
        local retainer=get(widget,"RetainerBox")
        pcall(function() oldVis=img:GetVisibility() end)
        pcall(function() oldWidgetOpacity=widget:GetRenderOpacity() end)
        if valid(retainer) then
            pcall(function() oldRetainerOpacity=retainer:GetRenderOpacity() end)
        end
        before={widget=key,icon=img,label=label,widgetObj=widget,
            retainer=retainer,originalWidgetOpacity=oldWidgetOpacity,
            originalRetainerOpacity=oldRetainerOpacity,
            originalLabel=labelValue(label),
            originalBrush=oldBrush,originalVisibility=oldVis,
            identity=nil,texture=nil}
        cache[slot]=before
    end
    local id=entry and entry.identity or "missing"
    if before.identity~=id or before.texture~=tex then
        if valid(tex) then
            local ok=pcall(function() img:SetBrushFromTexture(tex,false) end)
            if not ok then
                -- Supports UTextureRenderTarget2D and other valid objects
                -- that are not subclassed from UTexture2D.
                ok=pcall(function() img:SetBrushResourceObject(tex) end)
            end
            if not ok then tex=nil;source="text_currency" end
        else
            -- Clear any old thumbnail; never show an unrelated weapon when
            -- the new junk object has no actual image.
            pcall(function() img:SetBrushFromTexture(nil,false) end)
        end
        before.identity=id
        before.texture=tex
    end
    -- WBP_InventorySlot.SetupForInvalidAsset can fade an EMPTY slot via
    -- its RetainerBox; setting the brush alone would not show the icon.
    pcall(function() widget:SetRenderOpacity(1) end)
    if valid(before.retainer) then
        pcall(function() before.retainer:SetRenderOpacity(1) end)
    end
    pcall(function() img:SetVisibility(0) end)
    pcall(function() img:SetRenderOpacity(1) end)
    -- [$] is deliberately a recognisable money/junk fallback, not a
    -- fabricated blueprint item thumbnail.
    if entry and (not valid(tex) or
        source=="engine_default_texture") then
        targetLabel=DIGITS[slot].."[$]"
    end
    local ok=changeLabel(label,targetLabel)
    pcall(function() label:SetVisibility(0) end)
    if not ok then return false,"FText_update_failed" end
    return true,source
end
local function clear(slot,pc)
    local previous=cache[slot]
    if not previous then return true end
    local w=getWidget(pc,slot)
    if not w or (objName(w) or tostring(w))~=previous.widget then
        cache[slot]=nil
        return true
    end
    local image=imageOf(w)
    if valid(image) then
        if previous.originalBrush~=nil then
            pcall(function() image:SetBrush(previous.originalBrush) end)
        else
            -- The game can restore an empty brush for an empty slot.
            -- Do not call OnSetupFromAsset(nil) on an owned weapon slot.
            pcall(function() image:SetBrushFromTexture(nil,false) end)
        end
        if previous.originalVisibility~=nil then
            pcall(function() image:SetVisibility(previous.originalVisibility) end)
        else pcall(function() image:SetVisibility(2) end) end
    end
    if previous.originalWidgetOpacity~=nil then
        pcall(function() w:SetRenderOpacity(previous.originalWidgetOpacity) end)
    end
    if valid(previous.retainer) and previous.originalRetainerOpacity~=nil then
        pcall(function()
            previous.retainer:SetRenderOpacity(previous.originalRetainerOpacity)
        end)
    end
    local label=get(get(w,"InputIcon"),"InputKeyText")
    changeLabel(label,DIGITS[slot])
    cache[slot]=nil
    return true
end
function M.refresh(pc,physics)
    if not valid(pc) then return false,"no_local_controller" end
    for slot=1,10 do
        local entry=physics.slots[slot]
        if entry or physics.unresolvedSlots[slot] then
            local ok,why=paint(slot,entry,pc)
            if not ok then return false,"slot_"..slot.."_"..tostring(why) end
        elseif cache[slot] then
            clear(slot,pc)
        end
    end
    return true,"icons_synced"
end
function M.reset()
    -- Same-world reload can reuse the inventory widget; do not leave old
    -- furniture thumbnails visible after the physics storage was cleared.
    for slot,previous in pairs(cache) do
        local img=previous.icon
        if valid(img) then
            if previous.originalBrush~=nil then
                pcall(function() img:SetBrush(previous.originalBrush) end)
            else
                pcall(function() img:SetBrushFromTexture(nil,false) end)
            end
            if previous.originalVisibility~=nil then
                pcall(function() img:SetVisibility(previous.originalVisibility) end)
            else
                pcall(function() img:SetVisibility(2) end)
            end
        end
        if valid(previous.widgetObj) and previous.originalWidgetOpacity~=nil then
            pcall(function()
                previous.widgetObj:SetRenderOpacity(previous.originalWidgetOpacity)
            end)
        end
        if valid(previous.retainer) and previous.originalRetainerOpacity~=nil then
            pcall(function()
                previous.retainer:SetRenderOpacity(previous.originalRetainerOpacity)
            end)
        end
        if valid(previous.label) and previous.originalLabel then
            changeLabel(previous.label,previous.originalLabel)
        end
    end
    cache={}
    fallback=nil
    fallbackChecked=false
    fallbackKind=nil
end
M.iconForActor=itemTexture
M.getWidget=getWidget
return M
