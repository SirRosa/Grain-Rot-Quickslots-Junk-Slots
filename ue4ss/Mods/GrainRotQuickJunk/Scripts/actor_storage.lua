-- Grain Rot "Junk": reversible world-actor vault; crash-hardened.
-- IMPORTANT: No direct writes to PhysGrabData, no PhysicsHandle ReleaseComponent,
-- no K2_AttachToActor or K2_DetachFromActor. The previous build caused
-- a native Fatal Error during storage of held actors.
-- Storing is a TWO-PHASE operation: press Mouse4/G while grabbing with RMB,
-- then release RMB. Only after the game's OWN release clears the grab target
-- do we touch visibility/collision/physics on the released actor.
local Store={}
Store.__index=Store

local function valid(o)
    if o==nil then return false end
    local ok,result=pcall(function() return o:IsValid() end)
    return ok and result==true
end
local function read(o,key)
    if o==nil then return nil end
    local ok,r=pcall(function() return o[key] end)
    if ok then return r end
    return nil
end
local function fullname(o)
    if not valid(o) then return nil end
    local ok,r=pcall(function() return o:GetFullName() end)
    if ok then return tostring(r) end
    return nil
end
local function call(o,method,...)
    if not valid(o) then return false,"invalid_object" end
    local args={...}
    local ok,result=pcall(function() return o[method](o,table.unpack(args)) end)
    if not ok then return false,tostring(result) end
    return true,result
end
local function getWorld(o)
    local ok,w=call(o,"GetWorld")
    if ok and valid(w) then return fullname(w) end
    return nil
end
local function isPhysicsLoot(o)
    if not valid(o) then return false end
    local cls
    pcall(function() cls=o:GetClass() end)
    for _=1,16 do
        if not valid(cls) then break end
        local name=fullname(cls) or ""
        if name:find("HeldenPhysicsActor",1,true) then return true end
        local next
        pcall(function() next=cls:GetSuperStruct() end)
        cls=next
    end
    return valid(read(o,"RootMesh")) and read(o,"bCanBeGrabbed")~=nil
end
local function actorLoc(o)
    local ok,v=call(o,"K2_GetActorLocation")
    if not ok then ok,v=call(o,"GetActorLocation") end
    return ok and v or nil
end
local function actorRot(o)
    local ok,v=call(o,"K2_GetActorRotation")
    if not ok then ok,v=call(o,"GetActorRotation") end
    return ok and v or nil
end
local function visible(o,show)
    local ok=call(o,"SetActorHiddenInGame",not show)
    if not ok then return false end
    local b=read(o,"bHidden")
    if type(b)=="boolean" then return b==not show end
    local fine,r=call(o,"IsHidden")
    return fine and r==not show
end
local function collision(o,on)
    local ok=call(o,"SetActorEnableCollision",on)
    return ok
end
local function physics(mesh,on)
    local ok=call(mesh,"SetSimulatePhysics",on)
    return ok
end
local function dropPosition(pawn)
    local v=actorLoc(pawn)
    local ok,f=call(pawn,"GetActorForwardVector")
    if not v or not ok or not f then return nil end
    local x,y,z=tonumber(read(v,"X")),tonumber(read(v,"Y")),tonumber(read(v,"Z"))
    local a,b=tonumber(read(f,"X")),tonumber(read(f,"Y"))
    if not x or not y or not z or not a or not b then return nil end
    return {X=x+150*a,Y=y+150*b,Z=z+65}
end
function Store.new(bank,logger)
    return setmetatable({
        bank=bank, log=logger or function() end,
        owner=nil,world=nil,pending=nil,lastError=nil
    },Store)
end
function Store:warn(s) self.log("[JUNK] "..tostring(s)) end
function Store:store(pawn,grabbed)
    if self.pending then return false,"pending_release_rmb" end
    if not valid(pawn) or not valid(grabbed) then return false,"no_held_physics_item" end
    if not isPhysicsLoot(grabbed) then return false,"not_physics_loot" end
    local owner=fullname(pawn)
    if self.owner and self.owner~=owner then return false,"different_owner" end
    local pw,iw=getWorld(pawn),getWorld(grabbed)
    if not pw or pw~=iw then return false,"world_mismatch" end
    local data=read(pawn,"PhysGrabData")
    if fullname(read(data,"Target"))~=fullname(grabbed) then
        return false,"item_not_currently_grabbed"
    end
    local mesh=read(grabbed,"RootMesh")
    if not valid(mesh) or not actorLoc(grabbed) or not actorRot(grabbed) then
        return false,"item_mesh_or_transform_unavailable"
    end
    local tx,reason=self.bank:beginStore(fullname(grabbed),grabbed)
    if not tx then return false,reason end
    self.pending={tx=tx,owner=owner,world=pw,actor=grabbed,
        waits=0,releaseTicks=0}
    self:warn("ARMED slot "..tx.slot.."/10; release RMB to safely stow item")
    return true,"release_rmb_to_store"
end
function Store:tick(pawn)
    local p=self.pending
    if not p then return false,"idle" end
    p.waits=p.waits+1
    if not valid(pawn) or fullname(pawn)~=p.owner
       or getWorld(pawn)~=p.world or not valid(p.actor)
       or getWorld(p.actor)~=p.world then
        self.bank:cancel(p.tx)
        self.pending=nil
        self:warn("CANCELLED pending store (owner/world/item changed)")
        return false,"pending_cancelled"
    end
    local target=read(read(pawn,"PhysGrabData"),"Target")
    if valid(target) and fullname(target)==fullname(p.actor) then
        p.releaseTicks=0
        if p.waits>=120 then
            self.bank:cancel(p.tx)
            self.pending=nil
            self:warn("CANCELLED pending store after 60s (still held)")
            return false,"release_timeout"
        end
        return false,"awaiting_rmb_release"
    end
    -- Release must be observed on two consecutive game-thread polls.
    -- No memory writes are made while physics grab still references the item.
    p.releaseTicks=p.releaseTicks+1
    if p.releaseTicks<2 then return false,"confirming_release" end
    local mesh=read(p.actor,"RootMesh")
    if not valid(mesh) then
        self.bank:cancel(p.tx);self.pending=nil
        return false,"mesh_lost_after_release"
    end
    -- No native physics-handle or UStruct writes. These 3 UFunctions are
    -- standard actor/component operations, executed only after the game
    -- has released its own held component.
    local offPhysics=physics(mesh,false)
    if not offPhysics then
        self.bank:cancel(p.tx);self.pending=nil
        return false,"disable_physics_failed"
    end
    local offCollision=collision(p.actor,false)
    if not offCollision then
        physics(mesh,true)
        self.bank:cancel(p.tx);self.pending=nil
        return false,"disable_collision_failed"
    end
    local hidden=visible(p.actor,false)
    if not hidden then
        collision(p.actor,true);physics(mesh,true)
        self.bank:cancel(p.tx);self.pending=nil
        return false,"hide_failed"
    end
    local saved=self.bank:confirm(p.tx,true)
    self.pending=nil
    if not saved then
        visible(p.actor,true);collision(p.actor,true);physics(mesh,true)
        return false,"transaction_commit_failed"
    end
    self.owner=p.owner
    self.world=p.world
    self:warn("STORED slot "..p.tx.slot.."/10; item hidden only after native RMB release")
    return true,p.tx.slot
end
function Store:retrieve(pawn)
    if self.pending then return false,"release_rmb_first" end
    if self.bank:count()==0 then return false,"empty" end
    if not valid(pawn) or fullname(pawn)~=self.owner then
        return false,"different_owner"
    end
    if not getWorld(pawn) or getWorld(pawn)~=self.world then
        return false,"different_world"
    end
    -- Do not teleport or re-enable physical actors while the player is
    -- holding another item with the game's native physics handle.
    if valid(read(read(pawn,"PhysGrabData"),"Target")) then
        return false,"release_current_rmb_grab_before_retrieve"
    end
    local tx,reason=self.bank:beginWithdraw()
    if not tx then return false,reason end
    local item=tx.actor
    if not valid(item) or getWorld(item)~=self.world then
        self.bank:cancel(tx);return false,"stored_actor_invalid"
    end
    local pos=dropPosition(pawn)
    local rot=actorRot(pawn)
    local mesh=read(item,"RootMesh")
    if not pos or not rot or not valid(mesh) then
        self.bank:cancel(tx);return false,"restore_prerequisites_missing"
    end
    local moved,result=call(item,"K2_TeleportTo",pos,rot)
    if not moved or result==false then
        self.bank:cancel(tx);return false,"teleport_failed"
    end
    local revealed=visible(item,true)
    local coll=collision(item,true)
    local phys=physics(mesh,true)
    if not (revealed and coll and phys) then
        -- Item remains tracked for recovery if partial restore occurs.
        self.bank:cancel(tx)
        self:warn("RESTORE partial failure slot "..tx.slot)
        return false,"restore_incomplete"
    end
    local committed=self.bank:confirm(tx,true)
    if not committed then return false,"transaction_commit_failed" end
    self:warn("RETRIEVED slot "..tx.slot.."/10 in front of player")
    return true,tx.slot
end
function Store:recoverAll(pawn,why)
    if self.pending then
        self.bank:cancel(self.pending.tx)
        self.pending=nil
    end
    if self.bank:count()==0 then return true,0 end
    if not valid(pawn) or fullname(pawn)~=self.owner then
        return false,"different_owner"
    end
    local old=self.bank.selected
    local rescued,failed=0,0
    for i=1,self.bank.capacity do
        if self.bank.slots[i] then
            self.bank:select(i)
            local ok=self:retrieve(pawn)
            if ok then rescued=rescued+1 else failed=failed+1 end
        end
    end
    self.bank:select(old)
    self:warn("recovery "..tostring(why).." rescued="..rescued.." failed="..failed)
    return failed==0,rescued
end
function Store:status()
    return self.bank.selected,self.bank:count(),self.owner,self.world
end
return Store
