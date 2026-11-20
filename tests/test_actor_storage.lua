-- Fatal Error regression: held item must never have PhysGrabData,
-- PhysicsHandle or actor attachment mutated by the Junk store.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local Bank=require("junk_store")
local Actors=require("actor_storage")
local function obj(id)
    local x={id=id,alive=true}
    function x:IsValid() return self.alive end
    function x:GetFullName() return self.id end
    return x
end
local world=obj("World /Game/Dungeon")
local pawn=obj("BP_HeldenPlayerCharacter_01_C /Game/Player")
local item=obj("BP_Treasure_C /Game/Item")
local mesh=obj("StaticMeshComponent /Game/Item.Mesh")
local handle=obj("PhysicsHandleComponent /Game/Player.Handle")
function pawn:GetWorld() return world end
function item:GetWorld() return world end
function pawn:GetActorForwardVector() return {X=1,Y=0,Z=0} end
function pawn:K2_GetActorLocation() return {X=0,Y=0,Z=200} end
function pawn:K2_GetActorRotation() return {Pitch=0,Yaw=0,Roll=0} end
function item:K2_GetActorLocation() return {X=11,Y=9,Z=205} end
function item:K2_GetActorRotation() return {Pitch=0,Yaw=0,Roll=0} end
function mesh:SetSimulatePhysics(v) self.physics=v end
function item:SetActorEnableCollision(v) self.collision=v end
function item:SetActorHiddenInGame(v) self.bHidden=v end
function item:K2_TeleportTo(pos,rot)
    if self.failTeleport then return false end
    self.pos=pos
    return true
end
-- This native sequence caused a fatal crash in the actual game. The mock
-- raises if a regression calls it, and the test checks PhysGrabData.Target.
function handle:ReleaseComponent() error("UNSAFE native handle release") end
function item:K2_AttachToActor() error("UNSAFE native actor attachment") end
function item:K2_DetachFromActor() error("UNSAFE native actor detachment") end
pawn.GrabPhysHandle=handle
local physGrab={Target=item}
pawn.PhysGrabData=physGrab
item.RootMesh=mesh
item.bCanBeGrabbed=true
local log={}
local bank=Bank.new(10)
local pocket=Actors.new(bank,function(s) log[#log+1]=s end)
assert(not pocket:store(pawn,nil))
local ok,reason=pocket:store(pawn,item)
assert(ok and reason=="release_rmb_to_store")
assert(bank:count()==0 and physGrab.Target==item and mesh.physics==nil)
assert(item.bHidden==nil and item.collision==nil)
for i=1,3 do
    ok,reason=pocket:tick(pawn)
    assert(not ok and reason=="awaiting_rmb_release")
end
assert(physGrab.Target==item,"must never mutate native grabbed struct")
-- Game itself releases RMB/PhysHandle on its own.
physGrab.Target=nil
ok,reason=pocket:tick(pawn)
assert(not ok and reason=="confirming_release")
ok,reason=pocket:tick(pawn)
assert(ok and reason==1 and bank:count()==1)
assert(item.bHidden==true and item.collision==false and mesh.physics==false)
assert(not pocket:store(pawn,item),"cannot duplicate actor")
-- Empty second Junk slot cannot retrieve the item from another slot.
assert(bank:select(2))
ok,reason=pocket:retrieve(pawn)
assert(not ok and reason=="empty")
assert(bank:select(1))
ok,reason=pocket:retrieve(pawn)
assert(ok and reason==1 and bank:count()==0)
assert(item.pos.X==150 and item.pos.Z==265)
assert(item.bHidden==false and item.collision and mesh.physics)
assert(physGrab.Target==nil)
-- A broken teleport must keep hidden item in the bank.
physGrab.Target=item
assert(pocket:store(pawn,item))
physGrab.Target=nil
pocket:tick(pawn)
pocket:tick(pawn)
assert(bank:count()==1)
item.failTeleport=true
ok,reason=pocket:retrieve(pawn)
assert(not ok and reason=="teleport_failed" and bank:count()==1)
item.failTeleport=false
assert(pocket:retrieve(pawn) and bank:count()==0)
-- Reuse of M5/H on an empty bank is a safe no-op; no native access.
local n,msg=pocket:retrieve(pawn)
assert(not n and msg=="empty")
io.write("PASS: fatal-grab-regression, deferred RMB release, reversible world actor store, no native handle or struct mutations\\n")
