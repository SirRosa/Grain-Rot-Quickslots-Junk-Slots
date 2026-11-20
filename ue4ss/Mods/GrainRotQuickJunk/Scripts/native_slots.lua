-- Experimental extension of Helden's *native* slot configuration.
-- Does not allocate raw TArray memory: uses reflected UE4SS array assignments
-- and verifies each readback. Unsupported builds fail closed.
local M={}
local function valid(o)
    if o==nil then return false end
    local ok,result=pcall(function() return o:IsValid() end)
    return ok and result==true
end
local function get(o,key)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[key] end)
    if ok then return v end
    return nil
end
local function fullname(o)
    if not valid(o) then return nil end
    local ok,r=pcall(function() return o:GetFullName() end)
    return ok and tostring(r) or nil
end
local function enumString(value)
    if value==nil then return nil end
    local ok,s=pcall(function() return value:ToString() end)
    return ok and tostring(s) or tostring(value)
end
local function arrayLen(a)
    if a==nil then return nil end
    local ok,n=pcall(function() return #a end)
    return ok and n or nil
end
local state={seen={},signature=nil,log=function() end,blocked={}}
function M.setLogger(log)
    state.log=log
end
local function warn(s)
    state.log("[QUICK] "..s)
end
local function makeName(i)
    if type(FName)=="function" then
        local ok,v=pcall(FName,"GrainRotQuick"..i)
        if ok then return v end
    end
    return "GrainRotQuick"..i
end
function M.extend(pawn)
    if not valid(pawn) then return false,"pawn_invalid" end
    local key=fullname(pawn)
    if not key or key:find("Default__",1,true) then return false,"cdo" end
    if state.blocked[key] then return false,"blocked_after_failure" end
    local settings=get(get(pawn,"InventorySettings"),"SlotSettings")
    local slots=get(pawn,"ItemSlots")
    local cfgN=arrayLen(settings)
    local nativeN=arrayLen(slots)
    if not cfgN or not nativeN then return false,"native_inventory_missing" end
    if cfgN>=10 then
        if state.seen[key]~="complete" then
            warn("native settings="..cfgN..", active native slots="..nativeN..
                " player="..key)
            state.seen[key]="complete"
        end
        return nativeN>=10,nativeN>=10 and "ready" or "native_slots_not_created"
    end
    -- We only mutate an untouched 4-slot setup. Any other layout belongs
    -- to the game or another mod, and must not be overwritten.
    if cfgN~=4 or nativeN~=4 then
        if not state.seen[key] then warn("skip non-vanilla layout cfg="..cfgN.." native="..nativeN) end
        state.seen[key]="skipped"
        return false,"non_vanilla_layout"
    end
    local existing=get(settings,4)
    if not existing then return false,"no_template" end
    local originalName=enumString(get(existing,"SlotName"))
    local first=5
    local ok,err=pcall(function() settings[first]=existing end)
    local n=arrayLen(settings)
    if not ok or not n or n<first then
        state.blocked[key]=true
        warn("TArray append unsupported, no further writes: "..tostring(err))
        return false,"append_unsupported"
    end
    -- An append succeeded, so materialize the remaining five slots.
    for i=5,10 do
        if i>5 then
            local good,errorString=pcall(function() settings[i]=existing end)
            if not good then
                state.blocked[key]=true
                warn("append stopped at "..i..": "..tostring(errorString))
                return false,"partial_native_config"
            end
        end
        local entry=get(settings,i)
        if not entry then
            state.blocked[key]=true
            return false,"missing_appended_entry"
        end
        local renamed=pcall(function() entry.SlotName=makeName(i) end)
        if not renamed then
            state.blocked[key]=true
            warn("renaming native settings failed at "..i)
            return false,"slot_name_write_failed"
        end
    end
    if arrayLen(settings)~=10 or originalName~=enumString(get(get(settings,4),"SlotName")) then
        state.blocked[key]=true
        warn("layout verification FAILED; restore the backed-up save if it causes problems")
        return false,"layout_verification_failed"
    end
    state.seen[key]="complete"
    warn("APPENDED six SlotSettings to native player config; waiting for engine-created ItemSlots/HUD. Current ItemSlots="..nativeN)
    return false,"native_engine_rebuild_pending"
end
function M.describeAction()
    if state.signature~=nil then return state.signature end
    local r={parameters={},safe=false}
    local ok,fn=pcall(function()
        return StaticFindObject("/Script/Helden.HeldenPlayerController:InventoryAction_Server")
    end)
    if not ok or not valid(fn) then
        state.signature=r
        warn("InventoryAction_Server function metadata unavailable")
        return r
    end
    pcall(function()
        fn:ForEachProperty(function(p)
            local flags
            pcall(function() flags=p:GetPropertyFlags() end)
            local name
            pcall(function() name=p:GetName() end)
            local ptype
            pcall(function() ptype=p:GetFullName() end)
            if type(flags)=="number" and (flags & 0x80)~=0 and (flags & 0x400)==0 then
                r.parameters[#r.parameters+1]={name=tostring(name),type=tostring(ptype)}
            end
        end)
    end)
    if #r.parameters==1 then
        local p=r.parameters[1]
        local name=p.name:lower()
        local ptype=p.type:lower()
        r.safe=(name:find("slot",1,true)~=nil or name:find("index",1,true)~=nil)
            and (ptype:find("intproperty",1,true)~=nil or ptype:find("byteproperty",1,true)~=nil)
    end
    state.signature=r
    local args={}
    for i,p in ipairs(r.parameters) do args[i]=p.name..":"..p.type end
    warn("InventoryAction_Server parameters=["..table.concat(args,",").."] directIndexSafe="..tostring(r.safe))
    return r
end
function M.select(pc,pawn,slot)
    if not valid(pc) or not valid(pawn) then return false,"no_player" end
    if type(slot)~="number" or slot<1 or slot>10 then return false,"out_of_range" end
    local nativeN=arrayLen(get(pawn,"ItemSlots")) or 0
    if nativeN<slot then return false,"native_slots_missing_"..nativeN end
    local info=M.describeAction()
    if not info.safe then return false,"native_action_signature_unverified" end
    local ok,err=pcall(function() pc:InventoryAction_Server(slot-1) end)
    if not ok then return false,"native_action_error_"..tostring(err) end
    return true,"server_action_dispatched_unverified"
end
return M
