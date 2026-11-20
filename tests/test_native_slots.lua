package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local mod=require("native_slots")
local logs={}
mod.setLogger(function(m) logs[#logs+1]=m end)
local function obj(name)
    local x={__name=name}
    function x:IsValid() return true end
    function x:GetFullName() return self.__name end
    return x
end
local lib=obj("KismetStringLibrary")
function lib:Conv_StringToName(s) return s end
local klass=obj("HeldenInventorySlotComponent")
local property={GetPropertyFlags=function() return 0x80 end,
    GetName=function() return "SlotIndex" end,
    GetFullName=function() return "IntProperty SlotIndex" end}
local fn=obj("InventoryAction_Server")
function fn:ForEachProperty(cb) cb(property) end
StaticFindObject=function(s)
    if s=="/Script/Engine.Default__KismetStringLibrary" then return lib end
    if s=="/Script/Helden.HeldenInventorySlotComponent" then return klass end
    if s=="/Script/Helden.HeldenPlayerController:InventoryAction_Server" then return fn end
end
FName=setmetatable({}, {__call=function(_,s) return tostring(s) end})
local xform={Rotation={X=0,Y=0,Z=0,W=1},
    Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local function nativeArray()
    local arr={}
    function arr:Add(value) table.insert(self,value) end
    return arr
end
local settings=nativeArray()
local slots=nativeArray()
for i=1,4 do
    settings[i]={Socket="None",SlotName="Quick"..i,RelativeTransform=xform}
    slots[i]={SlotName="Quick"..i,SlotComponent=obj("OriginalSlotComponent"..i)}
end
local pawn=obj("HeldenCharacter /Game/Player")
pawn.InventorySettings={SlotSettings=settings}
pawn.ItemSlots=slots
function pawn:AddComponentByClass(_,manual,tf,deferred)
    assert(not manual and not deferred and tf.Rotation.W==1)
    return obj("HeldenInventorySlotComponent "..tostring(#self.ItemSlots+1))
end
local ok,why=mod.extend(pawn)
assert(not ok and why=="native_engine_rebuild_pending")
assert(#settings==10 and #slots==4)
for i=1,10 do
    assert(settings[i].SlotName=="Quick"..i or settings[i].SlotName=="GrainRotQuick"..i)
end
assert(mod.rebuildMissing(pawn))
assert(#slots==10 and #settings==10)
for i=5,10 do
    assert(slots[i].SlotName=="GrainRotQuick"..i and slots[i].SlotComponent)
end
local pc=obj("HeldenPlayerController /Game/PC")
function pc:InventoryAction_Server(n) self.pressed=n end
assert(mod.select(pc,pawn,10))
assert(pc.pressed==9,"native hotkey must send 0-based index")
assert(mod.select(pc,pawn,5))
assert(pc.pressed==4)
assert(not mod.select(pc,pawn,11))
-- Actual UE4SS v3 TArray has no Add() method. Ensure this path cannot
-- write outside the pre-existing native FScriptArray's bounds.
local noBridgePawn=obj("HeldenCharacter /Game/NoNativeBridge")
noBridgePawn.InventorySettings={SlotSettings={}}
noBridgePawn.ItemSlots={{},{},{},{}}
for i=1,4 do
    noBridgePawn.InventorySettings.SlotSettings[i]={
        Socket="None",SlotName="Quick"..i,RelativeTransform=xform
    }
end
local orig=noBridgePawn.InventorySettings.SlotSettings
setmetatable(orig,{__newindex=function(_,key,_)
    error("simulated reflected TArray append failure at "..tostring(key))
end})
local before=#orig
local no,reason=mod.extend(noBridgePawn)
assert(not no and reason=="array_append_failed")
assert(#noBridgePawn.InventorySettings.SlotSettings==before,
    "no out-of-bounds write should happen without native array bridge")
io.write("PASS: safe append bridge, 4->10 mock slots, readback, no unsafe native TArray indexing\\n")
