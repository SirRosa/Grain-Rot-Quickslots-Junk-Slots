-- Host-only mock tests. These deliberately do NOT claim live-game behaviour.
local messages, binds, hooks = {}, {}, {}
local poller
print=function(s) messages[#messages+1]=tostring(s) end
Key={XBUTTON_ONE=5,XBUTTON_TWO=6,G=71,H=72,OEM_COMMA=188,OEM_PERIOD=190,
    ONE=49,TWO=50,THREE=51,FOUR=52,FIVE=53,SIX=54,SEVEN=55,
    EIGHT=56,NINE=57,ZERO=48}
ModifierKey={SHIFT=16}
RegisterKeyBind=function(k,mods,cb)
    if cb~=nil then assert(mods[1]==16,"< and > must require Shift")
    else cb=mods end
    assert(not binds[k],"duplicate bind"); binds[k]=cb
end
RegisterHook=function(k,cb) hooks[k]=cb;return 1,2 end
ExecuteInGameThread=function(cb) cb() end
LoopInGameThreadWithDelay=function(ms,cb) assert(ms==500);poller=cb end

local groups={}
FindAllOf=function(name) return groups[name] or {} end
local function object(class,name,world)
    local o={klass=class, fullName=name, world=world, alive=true}
    function o:IsValid() return self.alive end
    function o:GetFullName() return self.fullName end
    function o:GetWorld() return self.world end
    function o:IsA(path) return path=="/Script/Helden."..self.klass end
    return o
end
local world=object("World","World /Game/Maps/Dungeon.PersistentLevel")
local pawn=object("HeldenCharacter","HeldenCharacter /Game/Test.Player",world)
local old=object("HeldenCharacter","HeldenCharacter /Game/Test.Other",world)
local gun=object("HeldenRangedWeapon","HeldenRangedWeapon /Game/Test.Gun",world)
gun.PreviousOwner=pawn;gun.CurrentSlot=object("SceneComponent","Slot",world)
gun.ItemDurabilityMax=12
gun.ItemDurability=3
local gun2=object("HeldenRangedWeapon","HeldenRangedWeapon /Game/Test.WorldGun",world)
gun2.PreviousOwner=old;gun2.CurrentSlot=nil;gun2.ItemDurabilityMax=10;gun2.ItemDurability=1
pawn.EquipedItems={gun}
pawn.InventorySettings={SlotSettings={{},{},{},{}}}
pawn.ItemSlots={{},{},{},{}}
pawn.PhysGrabData={Target=gun2}
local pc=object("HeldenPlayerController","PC /Game/Test.Controller",world)
function pc:GetPawn() return pawn end
function pc:IsLocalController() return true end
local inside=false
local box=object("BoxComponent","Box /Game/Test.Lift",world)
function box:IsOverlappingActor(actor) assert(actor==pawn);return inside end
local lift=object("HeldenDungeonElevator","Lift /Game/Test.Lift",world)
lift.InteriorCollisionBox=box
local gm=object("HeldenGameMode","GM /Game/Test.GM",world)
groups.HeldenPlayerController={pc}
groups.HeldenDungeonElevator={lift}
groups.HeldenGameMode={gm}
groups.HeldenRangedWeapon={gun,gun2}
groups.HeldenInventoryWidget={}
assert(loadfile("ue4ss/Mods/GrainRotQuickJunk/Scripts/main.lua"))()
assert(type(poller)=="function","poller not registered")
for _,k in ipairs({5,6,71,72,188,190,53,54,55,56,57,48}) do
    assert(type(binds[k])=="function","missing keybind "..k)
end
for _,k in ipairs({49,50,51,52}) do
    assert(binds[k]==nil,"native key 1-4 must remain untouched")
end
poller()
assert(gun.ItemDurability==3,"must not repair outside lift")
assert(gun2.ItemDurability==1,"world gun must not be repaired")
inside=true
poller()
assert(gun.ItemDurability==12,"must repair on entry")
assert(gun2.ItemDurability==1,"must not repair unrelated world gun")
gun.ItemDurability=4
poller()
assert(gun.ItemDurability==4,"must not spam repairs while inside")
inside=false;poller()
inside=true;poller()
assert(gun.ItemDurability==12,"must repair on re-entry")
groups.HeldenGameMode={}
gun.ItemDurability=2
inside=false;poller();inside=true;poller()
assert(gun.ItemDurability==2,"client must not mutate firearm durability")
groups.HeldenGameMode={gm}
local before=gun2.ItemDurability
binds[5]()
binds[71]()
binds[6]()
binds[72]()
binds[188]()
binds[190]()
binds[48]()
assert(gun2.ItemDurability==before and gun2.alive,"preview must not mutate grabbed world item")
assert(pawn.PhysGrabData.Target==gun2,"grabbed object must remain unchanged")
assert(type(hooks["/Script/Helden.HeldenPlayerController:InventoryAction_Server"])=="function",
    "read-only inventory RPC probe must register")
local sawRefill,sawBlock=false,false
for _,s in ipairs(messages) do
    if s:find("REFILL",1,true) then sawRefill=true end
    if s:find("BLOCKED",1,true) then sawBlock=true end
end
assert(sawRefill and sawBlock,"diagnostic must clearly separate supported and unsupported operations")
print=io.write
print("PASS: bindings, source actor safety, one refill per entry, host authority, fail-closed junk preview\n")
