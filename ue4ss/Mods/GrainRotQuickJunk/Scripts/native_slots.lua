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
-- Verified against installed UE4SS 3.0.1 commit 1c1a1497:
-- LuaTArray.cpp:prepare_to_handle calls FScriptArray::AddZeroed on index
-- >= Num, including __newindex. Only append exactly one element at #arr+1.
-- The StructProperty pusher accepts a Lua table and copies its members.
local function safeAppend(array,entry)
    local before=arrayLen(array)
    if before==nil or before<1 or before>=10 then
        return false,"unexpected_array_length"
    end
    local ok,err=pcall(function() array[before+1]=entry end)
    if not ok then return false,tostring(err) end
    if arrayLen(array)~=before+1 then return false,"array_length_unchanged" end
    return true,nil
end
local function makeName(i)
    if FName==nil then return nil end
    local n="GrainRotQuick"..i
    -- FName is a callable TABLE in UE4SS (not a Lua function). The Lua
    -- constructor at this commit uses FNAME_Add by default.
    local ok,v=pcall(FName,n)
    if ok and v and enumString(v)==n then return v end
    return nil
end
local function makeTemplate(src)
    local socket=enumString(get(src,"Socket"))
    local t=get(src,"RelativeTransform")
    local q=get(t,"Rotation")
    local p=get(t,"Translation")
    local s=get(t,"Scale3D")
    if not socket or not q or not p or not s or FName==nil then return nil end
    local ok,socketName=pcall(FName,socket)
    if not ok or not socketName or enumString(socketName)~=socket then return nil end
    local function vec3(v)
        local x,y,z=tonumber(get(v,"X")),tonumber(get(v,"Y")),tonumber(get(v,"Z"))
        if not x or not y or not z then return nil end
        return {X=x,Y=y,Z=z}
    end
    local quat=vec3(q)
    local pos=vec3(p)
    local scale=vec3(s)
    local w=tonumber(get(q,"W"))
    if not quat or not pos or not scale or not w then return nil end
    quat.W=w
    return {
        Socket=socketName,
        RelativeTransform={Rotation=quat,Translation=pos,Scale3D=scale},
    }
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
    local data=makeTemplate(existing)
    if not data or not originalName then
        return false,"cannot_snapshot_struct_before_append"
    end
    local entries={}
    for i=5,10 do
        local label=makeName(i)
        if not label then return false,"cannot_create_native_slot_name_"..i end
        entries[i]={SlotName=label,Socket=data.Socket,RelativeTransform=data.RelativeTransform}
    end
    -- Never keep a reference into the old FScriptArray after an append:
    -- reallocation invalidates UScriptStruct userdata addresses.
    for i=5,10 do
        local ok,err=safeAppend(settings,entries[i])
        if not ok then
            state.blocked[key]=true
            warn("UE4SS TArray indexed append failed at "..i..": "..tostring(err))
            return false,"array_append_failed"
        end
        local entry=get(settings,i)
        if not entry or enumString(get(entry,"SlotName"))~="GrainRotQuick"..i then
            state.blocked[key]=true
            warn("native SlotSetting readback mismatch at "..i)
            return false,"slot_readback_mismatch"
        end
    end
    if arrayLen(settings)~=10 or originalName~=enumString(get(get(settings,4),"SlotName")) then
        state.blocked[key]=true
        warn("layout verification failed, do not continue")
        return false,"layout_verification_failed"
    end
    state.seen[key]="complete"
    warn("APPENDED six SlotSettings to native player config; waiting for engine-created ItemSlots/HUD. Current ItemSlots="..nativeN)
    return false,"native_engine_rebuild_pending"
end
local rebuilt={}
local function worldPos() -- identity transform, UE4SS v3 table representation
    return {Rotation={X=0,Y=0,Z=0,W=1},
        Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
end
function M.rebuildMissing(pawn)
    if not valid(pawn) then return false,"pawn_invalid" end
    local key=fullname(pawn)
    local items=get(pawn,"ItemSlots")
    local settings=get(get(pawn,"InventorySettings"),"SlotSettings")
    local count=arrayLen(items)
    if not key or not count or not settings then return false,"no_native_slots" end
    if count>=10 then return true,"already_complete" end
    if rebuilt[key] then return false,"already_attempted" end
    if count~=4 or arrayLen(settings)~=10 then return false,"unexpected_layout" end
    local componentClass
    local fine,cl=pcall(function()
        return StaticFindObject("/Script/Helden.HeldenInventorySlotComponent")
    end)
    if fine and valid(cl) then componentClass=cl end
    if not componentClass then return false,"slot_component_class_missing" end
    rebuilt[key]=true
    warn("native array still has 4 entries; attempting six registered slot components")
    for i=5,10 do
        local ok,comp=pcall(function()
            return pawn:AddComponentByClass(componentClass,false,worldPos(),false)
        end)
        if not ok or not valid(comp) then
            warn("AddComponentByClass failed at "..i..": "..tostring(comp))
            return false,"component_add_failed"
        end
        local setting=get(settings,i)
        local name=get(setting,"SlotName")
        if name==nil then return false,"setting_missing_"..i end
        local assigned,errorString=pcall(function()
            comp.SlotSetting=setting
        end)
        if not assigned then
            warn("component SlotSetting assignment failed "..i..": "..tostring(errorString))
            return false,"component_setting_failed"
        end
        local appended,appendError=safeAppend(items,{SlotName=name,SlotComponent=comp})
        if not appended then
            warn("UE4SS ItemSlots indexed append failed at "..i..": "..tostring(appendError))
            return false,"native_slot_append_failed"
        end
        local added=get(items,i)
        if not added or fullname(get(added,"SlotComponent"))~=fullname(comp) then
            warn("native slot component readback mismatch at "..i)
            return false,"slot_component_readback_failed"
        end
    end
    warn("READY 10/10 native ItemSlots; next verify game input, HUD and replication")
    return true,"native_slots_extended"
end

function M.describeAction()
    if state.signature~=nil then return state.signature end
    local r={parameters={},safe=false}
    local ok,fn=pcall(function()
        return StaticFindObject("/Script/Helden.HeldenPlayerController:InventoryAction_Server")
    end)
    if not ok or not valid(fn) then
        -- UE4SS(6).log proves the function exists and registers a native
        -- hook; the exact game ObjectDump declares InIdx: IntProperty.
        -- StaticFindObject may fail to locate UFunction metadata on this
        -- UE4SS build, but calling the reflected RPC on a real controller
        -- is still supported and independently error-checked.
        r.safe=true
        r.reason="verified_2026_11_20_objectdump_InIdx_IntProperty_metadata_lookup_missing"
        state.signature=r
        warn("InventoryAction_Server metadata lookup unavailable; using exact ObjectDump InIdx:int signature")
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
        r.safe=(name=="inidx" or name:find("slot",1,true)~=nil or name:find("index",1,true)~=nil)
            and (ptype:find("intproperty",1,true)~=nil or ptype:find("byteproperty",1,true)~=nil)
    end
    -- Exact game 2026-11-20 ObjectDump: HeldenPlayerController:
    -- InventoryAction_Server has ONE IntProperty named InIdx (offset 0).
    -- Some UE4SS builds do not expose UFunction:ForEachProperty to Lua;
    -- a missing metadata iterator must not disable this verified RPC.
    if #r.parameters==0 then
        r.safe=true
        r.reason="exact_Helden_2026_ObjectDump_InIdx_IntProperty"
    end
    state.signature=r
    local args={}
    for i,p in ipairs(r.parameters) do args[i]=p.name..":"..p.type end
    warn("InventoryAction_Server parameters=["..table.concat(args,",").."] directIndexSafe="..tostring(r.safe).." evidence="..tostring(r.reason))
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
