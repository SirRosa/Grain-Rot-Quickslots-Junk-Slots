-- Native persistence regression: default Blueprint inventory must be 10 slots
-- before SaveGame.ItemSaveData.OwningSlot is resolved on load/respawn.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local Slots=require("native_slots")
local function fname(s)
    return {ToString=function() return s end}
end
FName=setmetatable({},{__call=function(_,s) return fname(s) end})
local cdo={
    InventorySettings={SlotSettings={}},
    IsValid=function() return true end,
    GetFullName=function() return
        "BP_HeldenPlayerCharacter_01_C /Game/Gameplay/Character/BP_HeldenPlayerCharacter_01.Default__BP_HeldenPlayerCharacter_01_C"
    end,
}
local tx={
    Rotation={X=0,Y=0,Z=0,W=1},
    Translation={X=5,Y=0,Z=0},
    Scale3D={X=1,Y=1,Z=1}
}
for i=1,4 do
    cdo.InventorySettings.SlotSettings[i]={
        SlotName=fname("VanillaSlot"..i),Socket=fname("Back"),
        RelativeTransform=tx,
    }
end
local lookup=0
StaticFindObject=function(path)
    lookup=lookup+1
    if path=="/Game/Gameplay/Character/BP_HeldenPlayerCharacter_01.Default__BP_HeldenPlayerCharacter_01_C" then
        return cdo
    end
end
local nloads=0
LoadAsset=function(_) nloads=nloads+1 end
local logs={}
Slots.setLogger(function(msg) logs[#logs+1]=msg end)
local ok,reason=Slots.extendDefaults()
assert(ok and reason=="CDO_extended_to_10",reason)
assert(#cdo.InventorySettings.SlotSettings==10)
for i=1,4 do
    assert(cdo.InventorySettings.SlotSettings[i].SlotName:ToString()=="VanillaSlot"..i)
end
for i=5,10 do
    local sl=cdo.InventorySettings.SlotSettings[i]
    assert(sl.SlotName:ToString()=="GrainRotQuick"..i)
    assert(sl.Socket:ToString()=="Back")
    assert(sl.RelativeTransform.Translation.X==5)
end
assert(nloads==0,"already-loaded CDO should not trigger LoadAsset")
ok,reason=Slots.extendDefaults()
assert(ok and reason=="CDO_10_ready",reason)
assert(#cdo.InventorySettings.SlotSettings==10,"must not duplicate CDO settings")
-- Another inventory mod's custom 10-slot layout cannot be overwritten.
cdo.InventorySettings.SlotSettings[5].SlotName=fname("AnotherMod5")
local n=#cdo.InventorySettings.SlotSettings
ok,reason=Slots.extendDefaults()
assert(not ok and reason=="CDO_other_10_slot_layout",reason)
assert(#cdo.InventorySettings.SlotSettings==n)
io.write("PASS: exact playable CDO expanded pre-spawn, stable 5-10 OwningSlot names and idempotent/reject conflicting layouts\n")
