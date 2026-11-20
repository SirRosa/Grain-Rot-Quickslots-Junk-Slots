-- Unified 1-0 quickslots for RMB-held HeldenPhysicsActor objects.
--
-- Native ItemSlots[] are HeldenInventroySlot structs, not item containers.
-- Physics actors are NOT HeldenEquipableItem. We therefore reserve only
-- genuinely free native hotbar indices in a separate virtual layer. Never
-- change ItemSlots, EquipedItems, physics handle or PhysGrabData in Lua.
--
-- Critical safety: do NOT hide/teleport a grabbed actor. First call the
-- game's verified no-arg ReleaseObject_Server, then wait for two polls
-- observing the engine's actual PhysGrabData.Target has cleared.
-- Selection uses native GrabObject_Server(InGrabData:HeldenPhysGrabData).
local M={}
M.__index=M
local function valid(o)
    if o==nil then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v==true
end
local function get(o,k)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
end
local function name(o)
    if not valid(o) then return nil end
    local ok,v=pcall(function() return o:GetFullName() end)
    if ok and v then return tostring(v) end
end
local function shortPath(o)
    local n=name(o)
    return n and n:match("%s(.+)$") or nil
end
local function world(o)
    if not valid(o) then return nil end
    local ok,w=pcall(function() return o:GetWorld() end)
    if ok and valid(w) then return name(w) end
end
local function call(o,k,...)
    if not valid(o) then return false,"invalid_target" end
    local fn=get(o,k)
    if fn==nil then return false,"method_missing_"..k end
    local args={...}
    local ok,res=pcall(function() return fn(o,table.unpack(args)) end)
    if not ok then return false,tostring(res) end
    return true,res
end
local function vec(obj)
    local x,y,z=tonumber(get(obj,"X")),tonumber(get(obj,"Y")),tonumber(get(obj,"Z"))
    if not x or not y or not z then return nil end
    return {X=x,Y=y,Z=z}
end
local function plus(a,b)
    return {X=a.X+b.X,Y=a.Y+b.Y,Z=a.Z+b.Z}
end
local function minus(a,b)
    return {X=a.X-b.X,Y=a.Y-b.Y,Z=a.Z-b.Z}
end
local function rotation(o)
    local ok,r=call(o,"K2_GetActorRotation")
    if not ok then ok,r=call(o,"GetActorRotation") end
    if ok and r then
        return {Pitch=tonumber(get(r,"Pitch")) or 0,
            Yaw=tonumber(get(r,"Yaw")) or 0,
            Roll=tonumber(get(r,"Roll")) or 0}
    end
end
local function location(o)
    local ok,v=call(o,"K2_GetActorLocation")
    if not ok then ok,v=call(o,"GetActorLocation") end
    return ok and vec(v) or nil
end
local function forward(pawn)
    local ok,v=call(pawn,"GetActorForwardVector")
    return ok and vec(v) or nil
end
local function inFront(pawn)
    local pos,fw=location(pawn),forward(pawn)
    if not pos or not fw then return nil end
    return {X=pos.X+fw.X*145,Y=pos.Y+fw.Y*145,
        Z=pos.Z+fw.Z*145+60}
end
local function grabTarget(pawn)
    return get(get(pawn,"PhysGrabData"),"Target")
end
local function grabSnapshot(pawn,actor)
    local d=get(pawn,"PhysGrabData")
    if name(get(d,"Target"))~=name(actor) then
        return nil,"not_native_rmb_target"
    end
    local orig=location(actor)
    local up=vec(get(d,"GrabUp"))
    local normal=vec(get(d,"GrabNormal"))
    local at=vec(get(d,"GrabLocation"))
    local target=vec(get(d,"PhysHandleTargetLocation"))
    local ts=tonumber(get(get(d,"StartFireTimer"),"Timestamp")) or 0
    if not orig or not up or not normal or not at or not target then
        return nil,"grab_data_incomplete"
    end
    return {up=up,normal=normal,grabOffset=minus(at,orig),
        handleOffset=minus(target,orig),timestamp=ts},nil
end
local function payload(entry,targetPos)
    local saved=entry.grab
    if not saved then return nil end
    return {
        Target=entry.actor,
        GrabUp=saved.up,
        GrabNormal=saved.normal,
        GrabLocation=plus(targetPos,saved.grabOffset),
        PhysHandleTargetLocation=plus(targetPos,saved.handleOffset),
        StartFireTimer={Timestamp=saved.timestamp},
    }
end
local function isPhysicsActor(o)
    if not valid(o) then return false end
    if get(o,"bCanBeGrabbed")==false then return false end
    local cls
    pcall(function() cls=o:GetClass() end)
    for _=1,12 do
        if not valid(cls) then break end
        if (name(cls) or ""):find("HeldenPhysicsActor",1,true) then
            return valid(get(o,"RootMesh"))
        end
        local parent
        pcall(function() parent=cls:GetSuperStruct() end)
        cls=parent
    end
    return valid(get(o,"RootMesh")) and get(o,"bCanBeGrabbed")~=nil
end
local function isHidden(actor)
    local b=get(actor,"bHidden")
    if type(b)=="boolean" then return b end
    local ok,h=call(actor,"IsHidden")
    if ok and type(h)=="boolean" then return h end
    return nil
end
local function setHidden(actor,flag)
    local ok,why=call(actor,"SetActorHiddenInGame",flag)
    if not ok then return false,why end
    local actual=isHidden(actor)
    if actual~=nil and actual~=flag then return false,"hidden_readback_failed" end
    return true
end
local function setCollision(actor,enabled)
    local ok,why=call(actor,"SetActorEnableCollision",enabled)
    return ok,why
end
local function setPhysics(actor,enabled)
    local mesh=get(actor,"RootMesh")
    if not valid(mesh) then return false,"RootMesh_missing" end
    local ok,why=call(mesh,"SetSimulatePhysics",enabled)
    return ok,why
end
local function stow(actor)
    local off=select(1,setPhysics(actor,false))
    if not off then return false,"physics_off_failed" end
    local col=select(1,setCollision(actor,false))
    if not col then
        setPhysics(actor,true)
        return false,"collision_off_failed"
    end
    local hide=select(1,setHidden(actor,true))
    if not hide then
        setCollision(actor,true);setPhysics(actor,true)
        return false,"hide_failed"
    end
    return true,"hidden_after_native_release"
end
local function reveal(actor)
    local v=select(1,setHidden(actor,false))
    local c=select(1,setCollision(actor,true))
    local p=select(1,setPhysics(actor,true))
    return v and c and p
end
-- HeldenCharacter.ItemSlots does NOT expose CurrentItemInSlot.
-- Occupancy is determined from native HeldenEquipableItem ownership and
-- CurrentInventorySlot, including holstered actors missing from EquipedItems.
local function nativeOccupied(pawn,scanAll)
    local slots=get(pawn,"ItemSlots")
    local count=0
    pcall(function() count=math.min(#slots,10) end)
    local found={}
    local owner=name(pawn)
    local function add(item,fromEquipment)
        if not valid(item) then return end
        local idx=tonumber(get(item,"CurrentInventorySlot"))
        local current=get(item,"CurrentSlot")
        local prev=get(item,"PreviousOwner")
        if not idx or idx<0 or idx>=count or not valid(current) then
            return
        end
        if fromEquipment or (valid(prev) and name(prev)==owner) then
            found[idx+1]=true
        end
    end
    local eq=get(pawn,"EquipedItems")
    local n=0
    pcall(function() n=math.min(#eq,64) end)
    for i=1,n do
        local item
        pcall(function() item=eq[i] end)
        add(item,true)
    end
    if scanAll and type(FindAllOf)=="function" then
        local ok,all=pcall(FindAllOf,"HeldenEquipableItem")
        if ok and type(all)=="table" then
            for _,item in ipairs(all) do add(item,false) end
        end
    end
    return found,count
end
local function keyOf(item)
    local dyn=get(item,"DynamicSaveName")
    local n
    pcall(function() n=dyn:ToString() end)
    if n and tostring(n)~="" and tostring(n)~="None" then
        return "dyn:"..tostring(n)
    end
    return "actor:"..tostring(name(item))
end
function M.new(logger)
    return setmetatable({log=logger or function() end,slots={},pending=nil,
        active=nil,owner=nil,world=nil,queuedSelect=nil,
        changed=true,dropTicks=0,saveDirty=false},M)
end
function M:count()
    local count=0
    for i=1,10 do if self.slots[i] then count=count+1 end end
    return count
end
function M:hasSlot(index)
    return self.slots[index]~=nil
end
function M:get(index)
    return self.slots[index]
end
function M:occupied(pawn,expensive)
    local native,n=nativeOccupied(pawn,expensive)
    local slots={}
    for i=1,math.min(10,n) do
        slots[i]=native[i] or self.slots[i]~=nil
    end
    return slots,n
end
function M:firstFree(pawn)
    local busy,n=self:occupied(pawn,true)
    if n<10 then return nil,"native_quickslots_not_ready_"..n end
    for i=1,10 do if not busy[i] then return i end end
    return nil,"all_10_slots_occupied"
end
function M:signal()
    self.changed=true
    self.saveDirty=true
end
function M:requestStore(pawn)
    if self.pending then return false,"transaction_pending" end
    if not valid(pawn) then return false,"no_character" end
    local target=grabTarget(pawn)
    if not valid(target) or not isPhysicsActor(target) then
        return false,"must_hold_physics_item_with_rmb"
    end
    local pw,aw=world(pawn),world(target)
    if not pw or pw~=aw then return false,"different_world" end
    if self.world and self.world~=pw then return false,"world_changed" end
    local oldSlot
    if self.active and name(self.active.actor)==name(target) then
        oldSlot=self.active.slot
    end
    local slot,why
    if oldSlot then
        slot=oldSlot
    else
        slot,why=self:firstFree(pawn)
        if not slot then return false,why end
    end
    local sampled,reason=grabSnapshot(pawn,target)
    if not sampled then return false,reason end
    local pos,rot=location(target),rotation(target)
    if not pos or not rot then return false,"actor_transform_unavailable" end
    local entry=self.slots[slot]
    if not entry then
        entry={slot=slot,actor=target,identity=keyOf(target),
            class=shortPath(get(target,"Class")) or
                (function()
                    local ok,c=pcall(function() return target:GetClass() end)
                    return ok and shortPath(c) or nil
                end)(),
            originalPosition=pos,originalRotation=rot,grab=sampled,
            world=pw,state="storing"}
    end
    -- Native RPC takes ZERO parameters (verified from the live ObjectDump).
    -- Do not mutate the current PhysGrabData or the physics handle.
    local released,err=call(pawn,"ReleaseObject_Server")
    if not released then return false,"native_release_failed_"..tostring(err) end
    self.owner=name(pawn);self.world=pw
    self.pending={op="store",actor=target,entry=entry,slot=slot,
        world=pw,owner=self.owner,waits=0,releaseTicks=0}
    self.log("[PHYS] E accepted -> native release requested for slot "..slot)
    return true,"release_requested"
end
function M:requestSelect(pawn,slot)
    if type(slot)~="number" or slot<1 or slot>10 then
        return false,"invalid_slot"
    end
    if not valid(pawn) then return false,"no_character" end
    if self.pending then
        if self.pending.op=="store" then
            self.queuedSelect=slot
            return true,"queued_until_release"
        end
        return false,"transaction_pending"
    end
    if self.active and self.active.slot~=slot then
        if name(grabTarget(pawn))==name(self.active.actor) then
            local accepted,why=self:requestStore(pawn)
            if accepted then
                self.queuedSelect=slot
                return true,"stowing_previous_held"
            end
            return false,why
        end
        -- User released RMB: the object is in the world, not in inventory.
        self.slots[self.active.slot]=nil
        self.active=nil
        self:signal()
    end
    local entry=self.slots[slot]
    if not entry then return false,"no_stored_physics_in_slot" end
    if entry.state=="held" and name(grabTarget(pawn))==name(entry.actor) then
        return true,"already_in_hands"
    end
    if not valid(entry.actor) or world(entry.actor)~=world(pawn) then
        return false,"item_not_in_current_world"
    end
    local held=grabTarget(pawn)
    if valid(held) and name(held)~=name(entry.actor) then
        return false,"release_other_RMB_object_first"
    end
    local occupied=nativeOccupied(pawn,true)
    if occupied[slot] then return false,"native_item_now_occupies_slot" end
    local target=inFront(pawn)
    if not target then return false,"player_forward_location_unavailable" end
    local original=location(entry.actor)
    local rot=rotation(pawn)
    if not original or not rot then return false,"actor_transform_unavailable" end
    -- Safe: the object is HIDDEN, has NO physics and is NOT held.
    local moved,err=call(entry.actor,"K2_TeleportTo",target,rot)
    if not moved or err==false then return false,"teleport_failed" end
    if not reveal(entry.actor) then
        stow(entry.actor)
        return false,"reveal_failed"
    end
    local data=payload(entry,target)
    if not data then
        stow(entry.actor)
        return false,"grab_payload_missing"
    end
    -- Verified native UFunction: GrabObject_Server(InGrabData:HeldenPhysGrabData).
    local ok,result=call(pawn,"GrabObject_Server",data)
    if not ok then
        stow(entry.actor)
        return false,"native_grab_RPC_error_"..tostring(result)
    end
    self.pending={op="equip",actor=entry.actor,entry=entry,
        slot=slot,waits=0,origin=original,world=world(pawn),
        owner=name(pawn)}
    self.log("[PHYS] slot "..slot.." -> native GrabObject_Server requested")
    return true,"native_grab_requested"
end
function M:tick(pawn)
    local p=self.pending
    if p then
        p.waits=p.waits+1
        if not valid(pawn) or name(pawn)~=p.owner or
            world(pawn)~=p.world or not valid(p.actor) or
            world(p.actor)~=p.world then
            self.pending=nil
            return false,"pending_player_or_world_changed"
        end
        local target=grabTarget(pawn)
        if p.op=="store" then
            if valid(target) and name(target)==name(p.actor) then
                p.releaseTicks=0
                if p.waits>=20 then
                    self.pending=nil
                    return false,"native_release_timeout_release_RMB"
                end
                return false,"native_release_pending"
            end
            if valid(target) then
                self.pending=nil
                return false,"player_grabbed_different_actor"
            end
            p.releaseTicks=p.releaseTicks+1
            if p.releaseTicks<2 then return false,"confirming_native_release" end
            local stowed,why=stow(p.actor)
            if not stowed then
                self.pending=nil
                return false,why
            end
            local entry=p.entry
            entry.state="stored"
            entry.slot=p.slot
            entry.actor=p.actor
            self.slots[p.slot]=entry
            if self.active and name(self.active.actor)==name(p.actor) then
                self.active=nil
            end
            self.pending=nil
            self:signal()
            self.log("[PHYS] STORED 1-0 quickslot "..p.slot)
            local nextSlot=self.queuedSelect
            self.queuedSelect=nil
            if nextSlot then self:requestSelect(pawn,nextSlot) end
            return true,p.slot
        elseif p.op=="equip" then
            if name(target)==name(p.actor) then
                p.entry.state="held"
                self.active=p.entry
                self.pending=nil
                self.dropTicks=0
                self:signal()
                self.log("[PHYS] native RMB grab confirmed slot "..p.slot)
                return true,p.slot
            end
            if p.waits>=4 then
                -- Do not hide an item held by a different player/handle.
                if valid(target) then
                    self.pending=nil
                    self.slots[p.slot]=nil
                    self:signal()
                    return false,"grab_claimed_other_object_visible_on_ground"
                end
                stow(p.actor)
                self.pending=nil
                return false,"native_grab_not_confirmed"
            end
            return false,"confirming_native_grab"
        end
        self.pending=nil
        return false,"unknown_pending_op"
    end
    if self.active and valid(pawn) then
        local target=grabTarget(pawn)
        if name(target)==name(self.active.actor) then
            self.dropTicks=0
        else
            self.dropTicks=self.dropTicks+1
            if self.dropTicks>=2 then
                -- Player intentionally released RMB / threw the item.
                -- No teleport, physics or hide operations on the dropped actor.
                local slot=self.active.slot
                self.slots[slot]=nil
                self.active=nil
                self.dropTicks=0
                self:signal()
                self.log("[PHYS] RMB released -> world object removed from slot "..slot)
            end
        end
    end
    return false,"idle"
end
function M:resolveNativeConflicts(pawn)
    if not valid(pawn) or self.pending then return false end
    local native,count=nativeOccupied(pawn,true)
    if count<10 then return false end
    for slot=1,10 do
        local entry=self.slots[slot]
        if entry and native[slot] then
            -- Native inventory wins. Move this reservation to another truly
            -- free quickslot rather than overwriting regular equipment.
            local replacement
            for j=1,10 do
                if not native[j] and not self.slots[j] then
                    replacement=j;break
                end
            end
            if replacement then
                self.slots[slot]=nil
                self.slots[replacement]=entry
                entry.slot=replacement
                self:signal()
                self.log("[PHYS] native conflict moved physics slot "..slot..
                    " to empty slot "..replacement)
            else
                -- All 10 occupied: make sure physics actor never disappears.
                if entry.state=="stored" and valid(entry.actor) then
                    local pos=inFront(pawn)
                    local rot=rotation(pawn)
                    if pos and rot then
                        call(entry.actor,"K2_TeleportTo",pos,rot)
                    end
                    reveal(entry.actor)
                    self.slots[slot]=nil
                    self:signal()
                    self.log("[PHYS] native inventory full; physics object safely returned to world")
                end
            end
        end
    end
    return true
end
function M:resetWorld()
    self.pending=nil;self.active=nil;self.slots={}
    self.owner=nil;self.world=nil;self.queuedSelect=nil
    self:signal()
end
local DIGITS={"1","2","3","4","5","6","7","8","9","0"}
local function ftext(value)
    if not FText then return nil end
    local ok,v=pcall(FText,value)
    if ok then return v end
end
function M:refreshUI(pc)
    if not valid(pc) then return false,"no_controller" end
    local hud
    pcall(function() hud=pc:GetHUD() end)
    local ui=get(get(hud,"PlayerHudWidget"),"InventoryWidget")
    if not valid(ui) then return false,"no_native_quickbar" end
    local widgets=get(ui,"SlotWidgets")
    local n=0
    pcall(function() n=#widgets end)
    if n<10 then return false,"native_widgets_not_ready" end
    for i=1,10 do
        local w=get(widgets,i)
        local icon=get(w,"InputIcon")
        local txt=get(icon,"InputKeyText")
        if valid(txt) then
            local expected=self.slots[i] and DIGITS[i].."+" or DIGITS[i]
            if self.slots[i] or i>=5 then
                local existing
                pcall(function()
                    local v=txt:GetText()
                    existing=v:ToString()
                end)
                if tostring(existing)~=expected then
                    local v=ftext(expected)
                    if v then pcall(function() txt:SetText(v) end) end
                end
                if self.slots[i] then
                    pcall(function() txt:SetVisibility(0) end)
                    local image=get(icon,"InputIconWidget")
                    if valid(image) then
                        pcall(function() image:SetVisibility(2) end)
                    end
                end
            end
        end
    end
    self.changed=false
    return true,"native_quickbar_1_to_0_occupancy_labels"
end
M.nativeOccupied=nativeOccupied
M.grabSnapshot=grabSnapshot
M.payload=payload
M.keyOf=keyOf
M.isPhysicsActor=isPhysicsActor
M.location=location
M.rotation=rotation
M.world=world
M.name=name
M.stow=stow
M.reveal=reveal
return M
