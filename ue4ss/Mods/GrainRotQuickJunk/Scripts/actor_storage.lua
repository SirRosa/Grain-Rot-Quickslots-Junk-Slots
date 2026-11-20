-- Live-actor Junk Slots; no actor is destroyed or cloned.
-- Experimental: current world only. NOT safe to assume persistent across map travel.
local Store = {}
Store.__index=Store

local function valid(o)
    if o==nil then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v==true
end
local function read(o,key)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[key] end)
    if ok then return v end
    return nil
end
local function path(o)
    if not valid(o) then return nil end
    local ok,v=pcall(function() return o:GetFullName() end)
    return ok and tostring(v) or nil
end
local function isA(o,name)
    if not valid(o) then return false end
    local ok,result=pcall(function() return o:IsA("/Script/Helden."..name) end)
    if ok and result==true then return true end
    -- The observed UE4SS v3 player BP problem also affects physics actors:
    -- some builds expect UObject:IsA(UClass) rather than IsA(string).
    local cls
    pcall(function() cls=o:GetClass() end)
    for _=1,16 do
        if not valid(cls) then break end
        local s=path(cls) or ""
        if s:find(name,1,true) then return true end
        local parent
        pcall(function() parent=cls:GetSuperStruct() end)
        cls=parent
    end
    if name=="HeldenPhysicsActor" then
        -- The live physics grab target must expose the native Helden actor
        -- mesh and health/physics metadata. Actor ownership is verified later.
        local mesh=read(o,"RootMesh")
        return valid(mesh) and read(o,"bCanBeGrabbed")~=nil
    end
    return false
end
local function invoke(o,method,...)
    if not valid(o) then return false,"invalid_object" end
    local args={...}
    local ok,result=pcall(function() return o[method](o,table.unpack(args)) end)
    if not ok then return false,tostring(result) end
    return true,result
end
local function setHidden(o,hidden)
    local ok=invoke(o,"SetActorHiddenInGame",hidden)
    if not ok then return false end
    -- AActor.bHidden exists in Unreal; IsHidden() is an alternative.
    local actual=read(o,"bHidden")
    if type(actual)=="boolean" then return actual==hidden end
    local fine,value=invoke(o,"IsHidden")
    return fine and value==hidden
end
local function setCollision(o,enabled)
    local ok=invoke(o,"SetActorEnableCollision",enabled)
    return ok
end
local function setPhysics(mesh,enabled)
    local ok=invoke(mesh,"SetSimulatePhysics",enabled)
    return ok
end
local function parentOf(o)
    local ok,value=invoke(o,"GetAttachParentActor")
    return ok and value or nil
end
local function location(o)
    local ok,value=invoke(o,"K2_GetActorLocation")
    if not ok then ok,value=invoke(o,"GetActorLocation") end
    if ok then return value end
end
local function rotation(o)
    local ok,value=invoke(o,"K2_GetActorRotation")
    if not ok then ok,value=invoke(o,"GetActorRotation") end
    if ok then return value end
end
local function forward(o)
    local ok,value=invoke(o,"GetActorForwardVector")
    if ok then return value end
end
local function posInFront(pawn)
    local a=location(pawn)
    local f=forward(pawn)
    if not a or not f then return nil end
    local x,y,z=tonumber(read(a,"X")),tonumber(read(a,"Y")),tonumber(read(a,"Z"))
    local fx,fy=tonumber(read(f,"X")),tonumber(read(f,"Y"))
    if not x or not y or not z or not fx or not fy then return nil end
    -- UE4SS v3 accepts a plain Lua table for FVector UFunction parameters.
    return {X=x+fx*135,Y=y+fy*135,Z=z+60}
end
function Store.new(bank,logger)
    return setmetatable({bank=bank,log=logger or function() end,owner=nil,world=nil},Store)
end
function Store:warn(message)
    self.log("[JUNK] "..message)
end
function Store:store(pawn,grabbed)
    if not valid(pawn) or not valid(grabbed) then return false,"no_grabbed_actor" end
    if not isA(grabbed,"HeldenPhysicsActor") then return false,"not_supported_physics_loot" end
    local w1,w2=invoke(pawn,"GetWorld")
    local w3,w4=invoke(grabbed,"GetWorld")
    if not (w1 and w3 and valid(w2) and valid(w4) and path(w2)==path(w4)) then
        return false,"different_world"
    end
    if self.owner and self.owner~=path(pawn) then return false,"different_owner" end
    local identity=path(grabbed)
    local tx,why=self.bank:beginStore(identity,grabbed)
    if not tx then return false,why end
    local mesh=read(grabbed,"RootMesh")
    local handle=read(pawn,"GrabPhysHandle")
    local data=read(pawn,"PhysGrabData")
    if not valid(mesh) or not valid(handle) or data==nil or path(read(data,"Target"))~=path(grabbed) then
        self.bank:cancel(tx)
        return false,"grab_or_mesh_unavailable"
    end
    if not location(grabbed) or not rotation(grabbed) then
        self.bank:cancel(tx)
        return false,"transform_unavailable"
    end
    local originalLoc,originalRot=location(grabbed),rotation(grabbed)
    -- Game native handle is released before moving the actor.
    local released=invoke(handle,"ReleaseComponent")
    if not released then self.bank:cancel(tx);return false,"release_failed" end
    -- Clearing PhysGrabData.Target is a reflected struct write on the host.
    local cleared=pcall(function() data.Target=nil end)
    if not cleared then
        self.bank:cancel(tx)
        return false,"grab_target_clear_failed"
    end
    local physical=setPhysics(mesh,false)
    local attached,attachResult=invoke(grabbed,"K2_AttachToActor",pawn,"None",1,1,1,false)
    local parent=parentOf(grabbed)
    if not (physical and attached and attachResult~=false and valid(parent) and path(parent)==path(pawn)) then
        if physical then setPhysics(mesh,true) end
        self.bank:cancel(tx)
        return false,"attachment_not_confirmed"
    end
    setCollision(grabbed,false)
    local hidden=setHidden(grabbed,true)
    if not hidden then
        invoke(grabbed,"K2_DetachFromActor",1,1,1)
        setCollision(grabbed,true)
        setPhysics(mesh,true)
        self.bank:cancel(tx)
        return false,"hide_not_confirmed"
    end
    local committed=self.bank:confirm(tx,true)
    if not committed then
        setHidden(grabbed,false)
        setCollision(grabbed,true)
        invoke(grabbed,"K2_DetachFromActor",1,1,1)
        setPhysics(mesh,true)
        return false,"bank_commit_failed"
    end
    self.owner=path(pawn)
    self.world=path(w2)
    self:warn("STORED "..identity.." "..self.bank:count().."/10")
    return true,tx.slot
end
function Store:retrieve(pawn)
    if not valid(pawn) then return false,"invalid_pawn" end
    if self.owner~=path(pawn) then return false,"different_owner" end
    local tx,reason=self.bank:beginWithdraw()
    if not tx then return false,reason end
    local item=tx.actor
    if not valid(item) then self.bank:cancel(tx);return false,"stowed_actor_invalid" end
    local pos=posInFront(pawn)
    local rot=rotation(pawn)
    local mesh=read(item,"RootMesh")
    if not pos or not rot or not valid(mesh) then
        self.bank:cancel(tx)
        return false,"spawn_position_unavailable"
    end
    local detached=invoke(item,"K2_DetachFromActor",1,1,1)
    if not detached then self.bank:cancel(tx);return false,"detach_failed" end
    local moved,moveResult=invoke(item,"K2_TeleportTo",pos,rot)
    if not moved or moveResult==false then
        invoke(item,"K2_AttachToActor",pawn,"None",1,1,1,false)
        self.bank:cancel(tx)
        return false,"teleport_failed"
    end
    local unhidden=setHidden(item,false)
    local collision=setCollision(item,true)
    local physics=setPhysics(mesh,true)
    invoke(mesh,"SetEnableGravity",true)
    if not unhidden or not collision or not physics or valid(parentOf(item)) then
        -- Never report a successful retrieval if the item is still hidden.
        self.bank:cancel(tx)
        self:warn("RECOVER MANUALLY: actor could not be fully unhidden "..tostring(tx.identity))
        return false,"actor_recovery_incomplete"
    end
    local confirmed=self.bank:confirm(tx,true)
    if not confirmed then return false,"bank_commit_failed" end
    self:warn("RETRIEVED "..tx.identity.." "..self.bank:count().."/10")
    return true,tx.slot
end
function Store:recoverAll(pawn,reason)
    if not valid(pawn) or self.owner~=path(pawn) then return false,"wrong_owner" end
    local old=self.bank.selected
    local rescued,failed=0,0
    for slot=1,self.bank.capacity do
        if self.bank.slots[slot] then
            self.bank:select(slot)
            local ok=self:retrieve(pawn)
            if ok then rescued=rescued+1 else failed=failed+1 end
        end
    end
    self.bank:select(old)
    self:warn("emergency recover reason="..tostring(reason).." rescued="..rescued.." failed="..failed)
    return failed==0,rescued
end
function Store:status()
    return self.bank.selected,self.bank:count(),self.owner,self.world
end
return Store
