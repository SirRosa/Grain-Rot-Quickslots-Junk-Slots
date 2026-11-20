-- Save slot isolation, cold load native actor re-pickup and death
-- carryover. No duplicate actors or direct inventory mutations.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local P=require("extra_slot_persistence")
local function obj(n)
    local o={n=n}
    function o:IsValid() return true end
    function o:GetFullName() return n end
    return o
end
local world=obj("World /Game/Test.PersistentLevel")
local klass=obj("BP_Pistol_C /Game/Items/BP_Pistol.BP_Pistol_C")
local asset=obj("HeldenItemData /Game/Items/DAPistol.DAPistol")
local save={MetaData={GameSlot=73,SaveSlotName="QA-Test-Slot"},TimePlayed=120}
function save:IsValid() return true end
local pc=obj("Controller /Game/Test.PC")
local pawn1=obj("Pawn /Game/Test.PlayerA")
local pawn2=obj("Pawn /Game/Test.PlayerB")
local mesh={}
local function setupPawn(pawn)
    pawn.CharacterState=0
    pawn.CharacterStats={CurrentHealth=80}
    pawn.EquipedItems={}
    pawn.ItemSlots={}
    for i=1,10 do
        pawn.ItemSlots[i]={SlotName="GrainRotQuick"..i,
            SlotComponent=obj("HeldenInventorySlotComponent /Game/Pawn.Slot"..i)}
    end
    function pawn:GetWorld() return world end
    function pawn:K2_GetActorLocation() return {X=0,Y=0,Z=100} end
end
setupPawn(pawn1)
setupPawn(pawn2)
local gun=obj("BP_Pistol_C /Game/Items.Gun")
gun.DynamicSaveName={ToString=function() return "StoredGun124" end}
gun.CurrentSlot=pawn1.ItemSlots[5].SlotComponent
gun.CurrentInventorySlot=4
gun.PreviousOwner=pawn1
gun.ItemDataAsset=asset
gun.ItemDurability=23
gun.ItemEnchantment={ToString=function() return "None" end}
function gun:GetClass() return klass end
function gun:Interact(pawn)
    self.PreviousOwner=pawn
    self.CurrentInventorySlot=0 -- native game first available vanilla slot
    self.CurrentSlot=pawn.ItemSlots[1].SlotComponent
    pawn.EquipedItems[#pawn.EquipedItems+1]=self
end
pawn1.EquipedItems={gun}
local found={gun}
FindAllOf=function(class)
    if class=="HeldenEquipableItem" then return found end
    return {}
end
local spawns=0
function world:SpawnActor(klassValue,pos,rot)
    assert(klassValue==klass)
    spawns=spawns+1
    local item=obj("BP_Pistol_C /Game/Items.Spawned"..spawns)
    item.DynamicSaveName={ToString=function() return "Regenerated"..spawns end}
    function item:Interact(pawn)
        self.PreviousOwner=pawn
        self.CurrentInventorySlot=0
        self.CurrentSlot=pawn.ItemSlots[1].SlotComponent
        pawn.EquipedItems[#pawn.EquipedItems+1]=self
    end
    found[#found+1]=item
    return item
end
StaticFindObject=function(path)
    if path=="/Game/Items/BP_Pistol.BP_Pistol_C" then return klass end
    if path=="/Game/Items/DAPistol.DAPistol" then return asset end
end
FName=setmetatable({},{__call=function(_,v)
    return {ToString=function() return v end}
end})
local log={}
local function logger(s) log[#log+1]=s end
local m=P.new(logger,{root="/tmp"})
local rows=P.snapshot(pawn1)
assert(#rows==1 and rows[1].slot==4 and rows[1].dyn=="StoredGun124")
local encoded=P.serialize(73,"QA-Test-Slot",120,rows)
local decoded,why=P.parse(encoded,73,"QA-Test-Slot",120)
assert(decoded and #decoded==1 and decoded[1].dyn=="StoredGun124")
assert(P.parse(encoded,74,"QA-Test-Slot",120)==nil,"wrong save slot rejected")
assert(P.parse(encoded,73,"QA-Test-Slot",0)==nil,"rewound/new save rejected")
for i=1,10 do assert(m:tick(pc,pawn1,save,world)) end
local f=m:fileFor(73)
local file=assert(io.open(f,"rb"));local serialized=file:read("*a");file:close()
assert(serialized:find("StoredGun124",1,true),"save manifest must be durable")
-- Death: same player controller receives a different live pawn. The existing
-- item actor must be re-interacted, never re-spawned.
pawn1.CharacterState=1
pawn1.CharacterStats.CurrentHealth=0
assert(m:tick(pc,pawn1,save,world))
for i=1,12 do assert(m:tick(pc,pawn2,save,world)) end
assert(spawns==0,"respawn original still exists, must not duplicate")
assert(gun.PreviousOwner==pawn2 and gun.CurrentInventorySlot==4,
    "original actor re-owned and re-bound to native slot 5")
assert(#pawn2.EquipedItems==1)
-- Cold load should reconcile from sidecar after process restart with a
-- native actor having the original DynamicSaveName.
local loaded=P.new(logger,{root="/tmp"})
local pawn3=obj("Pawn /Game/Test.PlayerC")
setupPawn(pawn3)
for i=1,12 do assert(loaded:tick(pc,pawn3,save,world)) end
assert(spawns==0,"load with original actor found must not clone")
assert(#pawn3.EquipedItems==1)
-- If the engine destroyed the old actor at load, fallback must only spawn
-- one replacement after bounded native actor discovery.
local pawn4=obj("Pawn /Game/Test.PlayerD")
setupPawn(pawn4)
found={}
local m2=P.new(logger,{root="/tmp"})
for i=1,35 do m2:tick(pc,pawn4,save,world) end
assert(spawns==1,"missing saved actor should be recreated only once")
assert(#pawn4.EquipedItems==1 and pawn4.EquipedItems[1].CurrentInventorySlot==4)
assert(pawn4.EquipedItems[1].ItemDurability==23)
os.remove(f);os.remove(f..".bak");os.remove(f..".tmp")
io.write("PASS: save-scoped durable native slot5 manifest, death re-pickup and reload recovery, no duplicate spawns\n")
