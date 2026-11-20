-- Strict simulated UE4SS quickslots + native physics grab RPC integration.
-- This is not a live Unreal runtime test.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local M=require("physics_quickslots")
local function make(class,path,w)
    local obj={klass=class,full=class.." "..path,world=w,valid=true}
    function obj:IsValid() return self.valid end
    function obj:GetFullName() return self.full end
    function obj:GetWorld() return self.world end
    return obj
end
local w=make("World","/Game/Test.Level")
local pawn=make("HeldenCharacter","/Game/Test.Pawn",w)
local native=make("HeldenEquipableItem","/Game/Test.Native",w)
native.CurrentInventorySlot=0
native.CurrentSlot=make("HeldenInventorySlotComponent","/Game/Test.NativeComp",w)
native.PreviousOwner=pawn
pawn.EquipedItems={native}
pawn.ItemSlots={}
for i=1,10 do
    pawn.ItemSlots[i]={SlotName="Quick"..i,
        SlotComponent=make("HeldenInventorySlotComponent","/Game/Test.Comp"..i,w)}
end
local phys=make("HeldenPhysicsActor","/Game/Test.Phys001",w)
phys.bCanBeGrabbed=true
phys.bHidden=false
phys.collision=true
phys.pos={X=10,Y=20,Z=30}
phys.rot={Pitch=0,Yaw=15,Roll=0}
local mesh=make("StaticMeshComponent","/Game/Test.PhysMesh",w)
mesh.simulates=true
function mesh:SetSimulatePhysics(v) self.simulates=v end
phys.RootMesh=mesh
phys.InitConAsset=make("HeldenConstructAsset","/Game/Test.FurnitureAsset",w)
phys.InitConAsset.Icon=make("Texture2D","/Game/UI/Test.FurnitureThumbnail",w)
function phys:GetClass()
    return make("Class","/Script/Helden.HeldenPhysicsActor",w)
end
function phys:IsHidden() return self.bHidden end
function phys:SetActorHiddenInGame(v) self.bHidden=v end
function phys:SetActorEnableCollision(v) self.collision=v end
function phys:K2_GetActorLocation() return self.pos end
function phys:K2_GetActorRotation() return self.rot end
function phys:K2_TeleportTo(loc,rot)
    self.pos=loc;self.rot=rot;self.teleports=(self.teleports or 0)+1
    return true
end
function pawn:K2_GetActorLocation() return {X=0,Y=0,Z=0} end
function pawn:GetActorForwardVector() return {X=1,Y=0,Z=0} end
function pawn:K2_GetActorRotation() return {Pitch=0,Yaw=0,Roll=0} end
pawn.PhysGrabData={
    Target=phys,GrabUp={X=0,Y=0,Z=1},
    GrabNormal={X=1,Y=0,Z=0},
    GrabLocation={X=12,Y=20,Z=34},
    PhysHandleTargetLocation={X=110,Y=20,Z=60},
    StartFireTimer={Timestamp=13.55},
}
function pawn:ReleaseObject_Server()
    self.nativeReleases=(self.nativeReleases or 0)+1
    self.PhysGrabData.Target=nil
end
function pawn:GrabObject_Server(payload)
    self.lastNativeGrabPayload=payload
    self.nativeGrabs=(self.nativeGrabs or 0)+1
    self.PhysGrabData.Target=payload.Target
end
local items={phys}
FindAllOf=function(cls)
    if cls=="HeldenEquipableItem" then return {native} end
    if cls=="HeldenPhysicsActor" then return items end
    return {}
end
local log={}
local qs=M.new(function(s) log[#log+1]=s end)
-- No reliable native UI -> E is forbidden to hide the object. This
-- protects against a repeat of the user's invisible/unselectable item.
local badPc=make("HeldenPlayerController","/Game/Test.NoHUD",w)
function badPc:GetHUD() return nil end
local blocked,reason=qs:requestStore(pawn,badPc)
assert(not blocked and reason:find("cannot_show_quickslot_icon",1,true))
assert(pawn.PhysGrabData.Target==phys and not phys.bHidden,
    "no HUD must preserve player's RMB-held world actor")
assert(pawn.nativeReleases==nil)
local busy,count=qs:occupied(pawn,true)
assert(count==10 and busy[1] and not busy[2])
local ok,why=qs:requestStore(pawn)
assert(ok and why=="release_requested",why)
assert(pawn.nativeReleases==1 and pawn.PhysGrabData.Target==nil)
assert(phys.bHidden==false and phys.collision==true and mesh.simulates,
    "must not hide or disable actor until confirmed native release")
assert(qs:count()==0 and qs.pending.slot==2)
qs:tick(pawn)
assert(phys.bHidden==false,"one poll insufficient to prove native release")
local done,slot=qs:tick(pawn)
assert(done and slot==2 and qs:count()==1)
assert(phys.bHidden==true and phys.collision==false and mesh.simulates==false)
local st=qs:get(2)
assert(st and st.state=="stored" and st.grab.timestamp==13.55)
local sel,reason=qs:requestSelect(pawn,2)
assert(sel,reason)
assert(phys.bHidden==false and phys.collision and mesh.simulates)
assert(pawn.nativeGrabs==1)
assert(pawn.lastNativeGrabPayload.Target==phys)
assert(pawn.lastNativeGrabPayload.GrabLocation.X==147,
    "grab offset must move with actor in front of pawn")
assert(pawn.lastNativeGrabPayload.StartFireTimer.Timestamp==13.55)
done,slot=qs:tick(pawn)
assert(done and slot==2 and qs:get(2).state=="held")
-- E must return *same* item to its same slot, never duplicate it.
ok,why=qs:requestStore(pawn)
assert(ok and qs.pending.slot==2 and pawn.nativeReleases==2,why)
qs:tick(pawn);qs:tick(pawn)
assert(qs:count()==1 and qs:get(2).state=="stored")
-- Selecting a different native slot can only change reserved physics state;
-- the standard 1-0 inventory must stay intact.
qs:requestSelect(pawn,2);qs:tick(pawn)
local switched,sw=qs:requestSelect(pawn,1)
assert(switched and sw=="stowing_previous_held")
qs:tick(pawn);qs:tick(pawn)
assert(qs:get(2) and qs:get(2).state=="stored")
assert(qs:count()==1)
-- A real RMB release places the actor on the ground and frees the slot.
qs:requestSelect(pawn,2);qs:tick(pawn)
pawn.PhysGrabData.Target=nil
qs:tick(pawn);qs:tick(pawn)
assert(qs:count()==0,"physics world item dropped -> virtual slot free")
assert(not phys.bHidden and phys.collision and mesh.simulates)
-- Fill every slot with ordinary native gear: E must not steal a slot.
pawn.EquipedItems={}
for i=1,10 do
    local item=make("HeldenEquipableItem","/Game/Test.Item"..i,w)
    item.CurrentInventorySlot=i-1
    item.CurrentSlot=pawn.ItemSlots[i].SlotComponent
    item.PreviousOwner=pawn
    pawn.EquipedItems[#pawn.EquipedItems+1]=item
end
pawn.PhysGrabData.Target=phys
local releases=pawn.nativeReleases
ok,why=qs:requestStore(pawn)
assert(not ok and why=="all_10_slots_occupied")
assert(pawn.PhysGrabData.Target==phys and pawn.nativeReleases==releases,
    "full inventory must leave held physics actor unchanged")
-- Invalid/non-RMB target never starts a transaction.
pawn.PhysGrabData.Target=nil
ok,why=qs:requestStore(pawn)
assert(not ok and why=="must_hold_physics_item_with_rmb")
-- Visual marker overlays only native 1-0; no secondary Junk HUD.
local iconText={text="1"}
function iconText:IsValid() return true end
function iconText:GetText() return {ToString=function() return self.text end} end
function iconText:SetText(value) self.text=value.value end
function iconText:SetVisibility(_) end
local icon={InputKeyText=iconText}
function icon:IsValid() return true end
local hudWidget={InputIcon=icon}
function hudWidget:IsValid() return true end
local ui={SlotWidgets={}}
function ui:IsValid() return true end
for i=1,10 do
    local t={text=tostring(i%10)}
    function t:IsValid() return true end
    function t:GetText() return {ToString=function() return self.text end} end
    function t:SetText(v) self.text=v.value end
    function t:SetVisibility(_) end
    local icon={InputKeyText=t}
    function icon:IsValid() return true end
    local image={visibility=2}
    function image:IsValid() return true end
    function image:SetBrushFromTexture(tex) self.texture=tex end
    function image:SetVisibility(v) self.visibility=v end
    function image:GetVisibility() return self.visibility end
    function image:SetRenderOpacity(v) self.opacity=v end
    function image:SetBrush(v) self.brush=v end
    ui.SlotWidgets[i]={InputIcon=icon,Icon=image}
    ui.SlotWidgets[i].IsValid=function() return true end
    ui.SlotWidgets[i].GetFullName=function() return "WBP /Game/Test.Slot"..i end
end
FText=setmetatable({},{__call=function(_,value)
    return {value=value,ToString=function(self) return self.value end}
end})
local pc=make("HeldenPlayerController","/Game/Test.PC",w)
local hud={PlayerHudWidget={InventoryWidget=ui}}
function hud:IsValid() return true end
function hud.PlayerHudWidget:IsValid() return true end
function pc:GetHUD() return hud end
-- First slot has a native item, so temporarily restore free physics slot2.
pawn.EquipedItems={}
qs.slots[2]={slot=2,actor=phys,grab=st.grab,identity="test",state="stored"}
qs.changed=true
assert(qs:refreshUI(pc))
assert(ui.SlotWidgets[2].InputIcon.InputKeyText.text=="2+")
assert(ui.SlotWidgets[2].Icon.texture==phys.InitConAsset.Icon,
    "must render actual furniture asset texture in WBP_InventorySlot.Icon")
qs.slots[2]=nil;qs.changed=true
assert(qs:refreshUI(pc))
assert(ui.SlotWidgets[2].InputIcon.InputKeyText.text=="2",
    "native quickslot label must be restored after physical item is removed")
-- Native UE4SS struct marshalling can fail. The old v0.3.0 code
-- re-hid the actor in this case, making it appear lost permanently.
qs.slots={}
pawn.EquipedItems={native}
pawn.PhysGrabData.Target=phys
function pawn:GrabObject_Server() error("UE4SS rejected HeldenPhysGrabData") end
assert(qs:requestStore(pawn))
qs:tick(pawn);qs:tick(pawn)
assert(phys.bHidden)
local grabbed,why=qs:requestSelect(pawn,2)
assert(not grabbed and why:find("item_visible_on_ground",1,true),why)
assert(phys.bHidden==false and phys.collision==true and mesh.simulates==true,
    "rejected native grab may NOT leave object hidden")
assert(qs:count()==0)
-- Some RPCs dispatch but never set PhysGrabData.Target. After 2 s the
-- actor must still remain in front, not silently disappear again.
pawn.PhysGrabData.Target=phys
function pawn:GrabObject_Server(payload)
    self.lastNativeGrabPayload=payload -- no target update
end
assert(qs:requestStore(pawn))
qs:tick(pawn);qs:tick(pawn)
assert(qs:requestSelect(pawn,2))
for i=1,4 do qs:tick(pawn) end
assert(qs:count()==0 and phys.bHidden==false,
    "unconfirmed native grab must also return object to visible world")
print("PASS: 1-0 native RMB store, real icon gate, inventory full, RPC rejection and delayed failure return visible actor")
