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
FName=function(s) return tostring(s) end
local xform={Rotation={X=0,Y=0,Z=0,W=1},
    Translation={X=0,Y=0,Z=0},Scale3D={X=1,Y=1,Z=1}}
local settings={}
local slots={}
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
io.write("PASS: native slot settings and components 4->10, readback, guarded server indexing\n")
