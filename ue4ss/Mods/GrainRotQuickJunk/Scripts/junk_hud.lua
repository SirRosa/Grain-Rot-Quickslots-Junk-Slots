-- One reused game-native UMG inventory slot frame in the lower-right HUD.
-- Does not manipulate the game's stock quickbar. Item art requires verified
-- metadata bindings (physical-loot meshes are not equipable item data assets).
local M={widget=nil,attempts=0}
local function valid(o)
    if o==nil then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v==true
end
local function get(o,key)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[key] end)
    return ok and v or nil
end
local function getInventory(pc)
    local h
    pcall(function() h=pc:GetHUD() end)
    local ui=get(get(h,"PlayerHudWidget"),"InventoryWidget")
    if valid(ui) then return ui end
    return nil
end
local function queryObject(path)
    if type(StaticFindObject)~="function" then return nil end
    local ok,obj=pcall(StaticFindObject,path)
    return ok and valid(obj) and obj or nil
end
function M.ensure(pc,log)
    if valid(M.widget) then return true,"exists" end
    if M.attempts>=12 then return false,"max_attempts" end
    if not valid(pc) then return false,"no_controller" end
    local inventory=getInventory(pc)
    if not inventory then return false,"inventory_widget_not_yet_visible" end
    local slotClass=get(inventory,"SlotWidgetClass")
    local lib=queryObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    if not valid(slotClass) or not lib then return false,"widget_blueprint_class_not_found" end
    M.attempts=M.attempts+1
    local ok,widget=pcall(function() return lib:Create(pc,slotClass,pc) end)
    if not ok or not valid(widget) then
        return false,"widget_creation_failed"
    end
    local added,err=pcall(function() widget:AddToViewport(98) end)
    if not added then return false,"viewport_add_failed:"..tostring(err) end
    local size={X=72,Y=72}
    pcall(function() widget:SetDesiredSizeInViewport(size) end)
    pcall(function() widget:SetAlignmentInViewport({X=1,Y=1}) end)
    -- Anchor at bottom-right if UUserWidget exposes anchors for this version.
    local anchored=pcall(function()
        widget:SetAnchorsInViewport({Minimum={X=1,Y=1},Maximum={X=1,Y=1}})
        widget:SetPositionInViewport({X=-24,Y=-30},false)
    end)
    if not anchored then
        local layout=queryObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local sizeX,sizeY
        if layout then
            local fine,v=pcall(function() return layout:GetViewportSize(pc) end)
            if fine and v then
                sizeX=tonumber(get(v,"X"))
                sizeY=tonumber(get(v,"Y"))
            end
        end
        if sizeX and sizeY then
            pcall(function() widget:SetPositionInViewport({X=sizeX-24,Y=sizeY-30},false) end)
        else
            pcall(function() widget:RemoveFromParent() end)
            return false,"viewport_size_unknown"
        end
    end
    pcall(function() widget:SetVisibility(4) end) -- SelfHitTestInvisible.
    M.widget=widget
    if type(log)=="function" then
        log("[JUNK HUD] game-native slot widget added at bottom-right")
    end
    return true,"created"
end
function M.reset()
    if valid(M.widget) then pcall(function() M.widget:RemoveFromParent() end) end
    M.widget=nil
    M.attempts=0
end
return M
