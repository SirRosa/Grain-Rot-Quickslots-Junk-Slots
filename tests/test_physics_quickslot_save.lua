-- Tests for the shared physics quickslot save manifest and identity reattach.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local QS=require("physics_quickslots")
local Save=require("physics_quickslot_save")
local function obj(n,w)
    local o={fullname=n,w=w,bHidden=false}
    function o:IsValid() return true end
    function o:GetFullName() return self.fullname end
    function o:GetWorld() return self.w end
    return o
end
local world=obj("World /Game/MapLevel.PersistentLevel")
local pawn=obj("Pawn /Game/MapLevel.PlayerA",world)
pawn.ItemSlots={}
pawn.EquipedItems={}
for i=1,10 do
    pawn.ItemSlots[i]={SlotComponent=obj("SceneComponent /Game/MapLevel.Slot"..i,world)}
end
local physics=obj("BP_DefaultPhysTreasure_C /Game/MapLevel.Phys1",world)
physics.bCanBeGrabbed=true
physics.RootMesh=obj("StaticMeshComponent /Game/MapLevel.Mesh1",world)
function physics.RootMesh:SetSimulatePhysics(v) self.sim=v end
function physics:GetClass() return obj("Class /Game/Junk/BP_PhysicsThing.BP_PhysicsThing_C",world) end
function physics:SetActorHiddenInGame(v) self.bHidden=v end
function physics:IsHidden() return self.bHidden end
function physics:SetActorEnableCollision(v) self.collision=v end
local entry={
    slot=7,actor=physics,identity="actor:"..physics.fullname,
    class="/Game/Junk/BP_PhysicsThing.BP_PhysicsThing_C",
    asset="/Game/Junk/DAPhysThing.DAPhysThing",
    originalPosition={X=11,Y=22,Z=33},
    originalRotation={Pitch=0,Yaw=45,Roll=0},
    grab={
        up={X=0,Y=0,Z=1},normal={X=1,Y=0,Z=0},
        grabOffset={X=1,Y=2,Z=3},handleOffset={X=80,Y=0,Z=12},
        timestamp=17.9
    },
    state="stored"
}
local textLog={}
local function log(s) textLog[#textLog+1]=s end
local quick=QS.new(log)
quick.slots[7]=entry
local save={MetaData={GameSlot=96,SaveSlotName="Save with tabs\t unicode"},TimePlayed=75,GameState=0}
function save:IsValid() return true end
local saver=Save.new(log,quick,{root="/tmp"})
assert(saver:poll(pawn,save))
local ok,reason=saver:checkpoint(save)
assert(ok and reason=="written",reason)
local f=saver:fileFor(96)
local handle=assert(io.open(f,"rb"))
local payload=handle:read("*a");handle:close()
local rows,why=Save.parse(payload,96,"Save with tabs\t unicode",75)
assert(rows and #rows==1,why)
local row=rows[1]
assert(row.slot==7 and row.id==entry.identity)
assert(row.asset==entry.asset and row.class==entry.class)
assert(row.pos.Z==33 and row.grab.grabOffset.Y==2)
assert(Save.parse(payload,97,"Save with tabs\t unicode",75)==nil)
assert(Save.parse(payload,96,"different slot name",75)==nil)
assert(Save.parse(payload,96,"Save with tabs\t unicode",0)==nil)
-- Repeated checkpoint without changes may update elapsed played time but may
-- never remove a slot by accidentally losing its actor reference.
assert(saver:checkpoint(save))
-- New game process: native actor already exists in the level and should be
-- re-hidden (never cloned or teleported from user data).
local all={physics}
FindAllOf=function(cls)
    if cls=="HeldenPhysicsActor" then return all end
    return {}
end
local quick2=QS.new(log)
local saver2=Save.new(log,quick2,{root="/tmp"})
assert(saver2:poll(pawn,save))
assert(quick2:count()==1 and quick2:get(7).actor==physics)
assert(physics.bHidden and physics.collision==false and physics.RootMesh.sim==false)
assert(#saver2.unresolved==0)
-- An item on the ground occupying its native slot forces virtual item to
-- move to another empty quickslot instead of overwriting normal equipment.
local native=obj("HeldenEquipableItem /Game/MapLevel.Native",world)
native.PreviousOwner=pawn;native.CurrentSlot=pawn.ItemSlots[7].SlotComponent
native.CurrentInventorySlot=6
pawn.EquipedItems={native}
local quick3=QS.new(log)
local saver3=Save.new(log,quick3,{root="/tmp"})
assert(saver3:poll(pawn,save))
assert(quick3:get(1) and quick3:get(1).actor==physics)
assert(quick3:get(7)==nil,"occupied native slot must not be replaced")
assert(saver3:checkpoint(save))
-- Missing actors must retain manifest; no blind spawn of unverified class.
local quick4=QS.new(log)
local saver4=Save.new(log,quick4,{root="/tmp"})
all={}
pawn.EquipedItems={}
for _=1,5 do saver4:poll(pawn,save) end
assert(quick4:count()==0 and #saver4.unresolved==1)
local completed,res=saver4:checkpoint(save)
assert(completed)
local handle2=assert(io.open(f,"rb"))
local pendingPayload=handle2:read("*a");handle2:close()
local pending=Save.parse(pendingPayload,96,"Save with tabs\t unicode",75)
assert(pending and #pending==1 and pending[1].id==entry.identity)
os.remove(f);os.remove(f..".bak");os.remove(f..".tmp")
io.write("PASS: save-scoped 1-0 physics identity and native reattach, native equipment conflict, missing actors retained without duplication\n")
