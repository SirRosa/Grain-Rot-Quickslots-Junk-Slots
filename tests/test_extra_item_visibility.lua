-- Regression: 5-0 quickbar items were rendered over the player's camera.
-- Preserve real equippables and their visibility ONLY when selected, hide
-- holstered ones while leaving the original slots (1-4) unchanged.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local visibility=require("extra_item_visibility")
local function actor(n,idx,holster,hidden)
    local o={name=n,CurrentInventorySlot=idx,HolsterState=holster,bHidden=hidden,changes=0}
    function o:IsValid() return true end
    function o:GetFullName() return self.name end
    function o:IsHidden() return self.bHidden end
    function o:SetActorHiddenInGame(b)
        self.changes=self.changes+1
        self.bHidden=b
    end
    return o
end
local slot1=actor("item-sl1",0,2,false)
local slot4=actor("item-sl4",3,2,false)
local slot5=actor("item-sl5",4,2,false)
local slot6=actor("item-sl6",5,1,false)
local slot9=actor("item-sl9",8,2,true) -- game originally hides this
local slot10=actor("item-sl10",9,2,false)
local pawn={EquipedItems={slot1,slot4,slot5,slot6,slot9,slot10}}
function pawn:IsValid() return true end
local log={}
visibility.setLogger(function(s) log[#log+1]=s end)
local ok,n=visibility.sync(pawn)
assert(ok and n==2)
assert(slot1.changes==0 and slot4.changes==0,"stock quickslots must be untouched")
assert(slot5.bHidden==true and slot10.bHidden==true,"holstered extra models hidden")
assert(slot6.bHidden==false,"actively equipped extra-slot item remains visible")
assert(slot9.bHidden==true and slot9.changes==0,"preserve game-initial hidden state")
local before=slot5.changes+slot10.changes
visibility.sync(pawn)
assert(slot5.changes+slot10.changes==before,"no redundant native visibility setters")
slot5.HolsterState=1
slot6.HolsterState=2
visibility.sync(pawn)
assert(slot5.bHidden==false,"show slot5 when equipped")
assert(slot6.bHidden==true,"hide slot6 when holstered")
-- A dropped item stops being inventoried; restore the actor's old visibility.
slot10.CurrentInventorySlot=-1
visibility.sync(pawn)
assert(slot10.bHidden==false,"restore dropped item visibility")
-- The equipped item is swapped without its actor being destroyed.
slot6.CurrentInventorySlot=2
visibility.sync(pawn)
assert(slot6.bHidden==false,"restore item moved into slot3")
local stateText={ToString=function() return "EHeldenItemHolsterState::Holsterd" end}
slot5.HolsterState=stateText
visibility.sync(pawn)
assert(slot5.bHidden==true,"enum userdata accepted")
visibility.reset()
assert(slot5.bHidden==false,"reset restores all mod-hidden actors")
assert(slot9.bHidden==true,"game-hidden original remains hidden")
assert(#pawn.EquipedItems==6,"inventory untouched")
io.write("PASS: 5-0 invisible only when holstered; selected items visible; original 1-4, drops, reset and game-hidden states preserved\n")
