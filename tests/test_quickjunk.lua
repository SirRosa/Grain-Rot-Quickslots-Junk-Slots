-- Host-only mock tests. These deliberately do NOT claim live-game behaviour.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local messages, binds, hooks = {}, {}, {}
local poller
print=function(s) messages[#messages+1]=tostring(s) end
Key={XBUTTON_ONE=5,XBUTTON_TWO=6,G=71,H=72,E=69,
    OEM_COMMA=188,OEM_PERIOD=190,
    ONE=49,TWO=50,THREE=51,FOUR=52,FIVE=53,SIX=54,SEVEN=55,
    EIGHT=56,NINE=57,ZERO=48}
ModifierKey={SHIFT=16}
RegisterKeyBind=function(k,mods,cb)
    if cb~=nil then assert(mods[1]==16,"< and > must require Shift")
    else cb=mods end
    assert(not binds[k],"duplicate bind"); binds[k]=cb
end
RegisterHook=function(k,pre,post) hooks[k]={pre=pre,post=post};return 1,2 end
ExecuteInGameThread=function(cb) cb() end
LoopInGameThreadWithDelay=function(ms,cb) assert(ms==500);poller=cb end

local groups={}
local findCounts={}
FindAllOf=function(name)
    findCounts[name]=(findCounts[name] or 0)+1
    return groups[name] or {}
end
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
pawn.CharacterStats=object("HeldenCharacterStats","HeldenCharacterStats /Game/Test.PlayerStats",world)
pawn.EquipedItems={gun}
pawn.InventorySettings={SlotSettings={{},{},{},{}}}
pawn.ItemSlots={{},{},{},{}}
pawn.PhysGrabData={Target=gun2}
local pc=object("HeldenPlayerController","PC /Game/Test.Controller",world)
function pc:GetPawn() return nil end
pc.LastPlayerChar=pawn
function pc:InventoryAction_Server(idx) self.lastSelected=idx;self.rpcCalls=(self.rpcCalls or 0)+1 end
function pc:IsLocalController() return true end
-- The real game already has a 10-widget native quickbar. v0.3.1 MUST NOT
-- hide grabbed physics objects before confirming visible icon capacity.
local textCtor=function(value)
    return {value=value,ToString=function(self) return self.value end}
end
FText=setmetatable({},{__call=function(_,value) return textCtor(value) end})
local hud=object("HeldenHUD","HUD /Game/Test.HUD",world)
local bar=object("HeldenInventoryWidget","Widget /Game/Test.Quickbar",world)
bar.SlotWidgets={}
for i=1,10 do
    local w=object("WBP_InventorySlot_C","Widget /Game/Test.Quickslot"..i,world)
    local icon=object("Image","Image /Game/Test.QuickslotIcon"..i,world)
    function icon:SetBrushFromTexture(tex) self.texture=tex end
    function icon:SetVisibility(v) self.visibility=v end
    function icon:GetVisibility() return self.visibility end
    function icon:SetRenderOpacity(v) self.opacity=v end
    local input=object("HeldenInputIconWidget","InputIcon /Game/Test.Input"..i,world)
    local txt=object("TextBlock","Text /Game/Test.Digit"..i,world)
    txt.value=tostring(i%10)
    function txt:GetText() return textCtor(self.value) end
    function txt:SetText(t) self.value=t:ToString() end
    function txt:SetVisibility(v) self.visibility=v end
    input.InputKeyText=txt
    w.InputIcon=input
    w.Icon=icon
    bar.SlotWidgets[i]=w
end
local hudView=object("PlayerHudWidget","Widget /Game/Test.HudView",world)
hudView.InventoryWidget=bar
hud.PlayerHudWidget=hudView
function pc:GetHUD() return hud end
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
local function pollN(n) for _=1,n do poller() end end
for _,k in ipairs({69,49,50,51,52,53,54,55,56,57,48}) do
    assert(type(binds[k])=="function","missing keybind "..k)
end
for _,k in ipairs({5,6,71,72,188,190}) do
    assert(binds[k]==nil,
        "old Junk controls must not be rebound: "..k)
end
assert(hooks["/Script/Helden.HeldenPlayerController:InventoryAction_Server"]
    and type(hooks["/Script/Helden.HeldenPlayerController:InventoryAction_Server"].post)=="function",
    "native selection post-hook must track game-owned keys 1-4")
poller()
assert(gun.ItemDurability==3,"must not repair outside lift")
assert(gun2.ItemDurability==1,"world gun must not be repaired")
inside=true
pollN(4)
assert(gun.ItemDurability==12,"must repair on entry")
assert(gun2.ItemDurability==1,"must not repair unrelated world gun")
gun.ItemDurability=4
poller()
assert(gun.ItemDurability==4,"must not spam repairs while inside")
inside=false;pollN(4)
inside=true;pollN(4)
assert(gun.ItemDurability==12,"must repair on re-entry")
groups.HeldenGameMode={}
gun.ItemDurability=2
inside=false;pollN(4);inside=true;pollN(4)
assert(gun.ItemDurability==2,"client must not mutate firearm durability")
groups.HeldenGameMode={gm}
-- Discovery should run on the first poll, then only once per ~2 seconds;
-- previously FindAllOf on controller, GameMode and elevators ran every
-- 500 ms, creating game-thread stalls and FPS drops.
local oldCount=findCounts.HeldenPlayerController or 0
local oldElev=findCounts.HeldenDungeonElevator or 0
pollN(20)
local newCount=(findCounts.HeldenPlayerController or 0)-oldCount
local newElev=(findCounts.HeldenDungeonElevator or 0)-oldElev
assert(newCount<=7 and newElev<=7,
    "repeated full scans in poll loop would cause stutter")
local before=gun2.ItemDurability
-- Pressing E while RMB holds a non-physics object must fail closed.
binds[69]()
assert(gun2.ItemDurability==before and gun2.alive,
    "E on nonphysics actor must not destroy or mutate it")
assert(pawn.PhysGrabData.Target==gun2,"invalid E must leave RMB grab intact")
-- LIVE regression from UE4SS(6).log: GetPawn() is nil, but
-- LastPlayerChar is the valid character whose slots reach 10.
-- The game accepts a reflected InventoryAction_Server(InIdx:int).
for i=5,10 do pawn.ItemSlots[i]={SlotName="GrainRotQuick"..i} end
local bindings={{53,4},{54,5},{55,6},{56,7},{57,8},{48,9}}
for _,entry in ipairs(bindings) do
    binds[entry[1]]()
    assert(pc.lastSelected==entry[2],
        "pressing number key must dispatch the correct zero-based inventory slot")
end
assert(pc.rpcCalls==6,"all six new hotkeys must trigger server inventory RPC")
assert(hooks["/Script/Helden.HeldenPlayerController:InventoryAction_Server"]~=nil,
    "1-4 selection must be detected without double-binding the native keys")
-- End-to-end integration: RMB on a physics world item + E must store
-- in the ordinary 1-0 bar, and native 1/2/3/4 selection must grab it.
local junk=object("HeldenPhysicsActor","HeldenPhysicsActor /Game/Test.Junk",world)
junk.bCanBeGrabbed=true
junk.bHidden=false
junk.collision=true
junk.pos={X=10,Y=0,Z=20}
junk.rot={Pitch=0,Yaw=0,Roll=0}
junk.RootMesh=object("StaticMeshComponent","Mesh /Game/Test.JunkMesh",world)
function junk.RootMesh:SetSimulatePhysics(v) self.physics=v end
function junk:IsHidden() return self.bHidden end
function junk:SetActorHiddenInGame(v) self.bHidden=v end
function junk:SetActorEnableCollision(v) self.collision=v end
function junk:GetClass() return object("Class","Class /Script/Helden.HeldenPhysicsActor",world) end
function junk:K2_GetActorLocation() return self.pos end
function junk:K2_GetActorRotation() return self.rot end
function junk:K2_TeleportTo(pos,rot) self.pos=pos;self.rot=rot;return true end
function pawn:GetActorForwardVector() return {X=1,Y=0,Z=0} end
function pawn:K2_GetActorLocation() return {X=0,Y=0,Z=0} end
function pawn:K2_GetActorRotation() return {Pitch=0,Yaw=0,Roll=0} end
function pawn:ReleaseObject_Server()
    self.releases=(self.releases or 0)+1
    self.PhysGrabData.Target=nil
end
function pawn:GrabObject_Server(data)
    self.grabs=(self.grabs or 0)+1
    self.lastGrab=data
    self.PhysGrabData.Target=data.Target
end
pawn.PhysGrabData={
    Target=junk,GrabUp={X=0,Y=0,Z=1},GrabNormal={X=1,Y=0,Z=0},
    GrabLocation={X=11,Y=1,Z=20},
    PhysHandleTargetLocation={X=100,Y=0,Z=50},
    StartFireTimer={Timestamp=9.7}}
binds[69]()
assert(pawn.releases==1,"E should call native release once")
assert(junk.bHidden==false,"held actor cannot be hidden before native release")
pollN(2)
assert(junk.bHidden==true and junk.collision==false)
-- Direct keyboard event must work even if InventoryAction_Server never
-- triggers the optional native hook (the user's observed v0.3.0 failure).
binds[49]()
assert(pawn.grabs==1 and pawn.lastGrab.Target==junk,
    "native quickslot 1 selection must send native GrabObject_Server")
assert(pawn.PhysGrabData.Target==junk)
assert(bar.SlotWidgets[1].Icon.texture==nil or
    bar.SlotWidgets[1].InputIcon.InputKeyText.value~=nil)
poller()
binds[69]()
pollN(2)
assert(junk.bHidden and pawn.releases==2,
    "E should safely restow the already-selected quickslot into same slot")
local sawRefill,sawBlocked=false,false
for _,msg in ipairs(messages) do
    if msg:find("REFILL",1,true) then sawRefill=true end
    if msg:find("[PHYS] E store=false",1,true) then sawBlocked=true end
end
assert(sawRefill and sawBlocked,
    "E should report rejected nonphysics item and not touch native gun")
print=io.write
print("PASS: direct key 1-0 physics retrieval even without native hook, visible quickbar required and native 5-0 gear preserved\n")
