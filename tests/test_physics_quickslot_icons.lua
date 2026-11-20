-- Native Grain Rot WBP_InventorySlot Icon behaviour (pure mock).
-- The real reflected Icon field is UMG.Image, not InputIcon.InputIconWidget.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local Icons=require("physics_quickslot_icons")
local function UObject(n)
    local o={name=n}
    function o:IsValid() return true end
    function o:GetFullName() return n end
    return o
end
local w={SlotWidgets={}}
function w:IsValid() return true end
for i=1,10 do
    local slot=UObject("WBP_InventorySlot_C /Game/Test.Slot"..i)
    local image=UObject("Image /Game/Test.Icon"..i)
    image.visibility=2
    image.Brush={original=i}
    function image:GetVisibility() return self.visibility end
    function image:SetVisibility(v) self.visibility=v end
    function image:SetRenderOpacity(v) self.opacity=v end
    function image:SetBrushFromTexture(tex,matchSize)
        self.texture=tex
    end
    function image:SetBrush(b) self.Brush=b end
    slot.Icon=image
    local txt=UObject("TextBlock /Game/Test.Key"..i)
    txt.value=tostring(i%10)
    function txt:GetText() return {ToString=function() return self.value end} end
    function txt:SetText(t) self.value=t:ToString() end
    function txt:SetVisibility(_) end
    slot.InputIcon={InputKeyText=txt}
    w.SlotWidgets[i]=slot
end
local hud=UObject("HUD /Game/Test.GameHUD")
local screen=UObject("UserWidget /Game/Test.Screen")
screen.InventoryWidget=w
hud.PlayerHudWidget=screen
local pc=UObject("HeldenPlayerController /Game/Test.PC")
function pc:GetHUD() return hud end
FText=setmetatable({},{__call=function(_,val)
    return {ToString=function() return val end}
end})
local tex=UObject("Texture2D /Game/Icons.Furniture")
local furniture=UObject("HeldenPhysicsActor /Game/Test.Furniture")
local asset=UObject("HeldenConstructAsset /Game/Test.FurnitureConstruct")
asset.Icon=tex
furniture.InitConAsset=asset
-- Regression: when InitConAsset is first non-nil candidate, actual icon
-- must be found even if all other optional asset fields are absent.
local icon,kind=Icons.iconForActor(furniture)
assert(icon==tex and kind=="construct_icon")
local physics={slots={},unresolvedSlots={}}
physics.slots[4]={identity="furniture1",actor=furniture,state="stored"}
assert(Icons.canRender(pc,4))
local ok,why=Icons.refresh(pc,physics)
assert(ok,why)
assert(w.SlotWidgets[4].Icon.texture==tex,
    "must fill the true WBP InventorySlot Icon with construct texture")
assert(w.SlotWidgets[4].Icon.visibility==0)
assert(w.SlotWidgets[4].InputIcon.InputKeyText.value=="4+")
-- Cached textures must not be reset by frequent 500 ms polls.
local image=w.SlotWidgets[4].Icon
function image:SetBrushFromTexture(t)
    self.textureCalls=(self.textureCalls or 0)+1
    self.texture=t
end
assert(Icons.refresh(pc,physics))
assert(image.textureCalls==nil,
    "do not issue redundant native UMG brush updates per poll")
-- Remove item: return the original empty brush, key hint and visibility.
physics.slots[4]=nil
assert(Icons.refresh(pc,physics))
assert(w.SlotWidgets[4].InputIcon.InputKeyText.value=="4")
assert(w.SlotWidgets[4].Icon.Brush.original==4)
assert(w.SlotWidgets[4].Icon.visibility==2)
-- A junk actor may lack any build/icon asset. A readable money shorthand
-- must still mark the slot, not leave it visually empty.
local junk=UObject("HeldenPhysicsActor /Game/Test.Junk")
physics.slots[5]={identity="junk1",actor=junk,state="stored"}
Icons.reset()
assert(Icons.refresh(pc,physics))
assert(w.SlotWidgets[5].InputIcon.InputKeyText.value=="5[$]",
    "missing icon must have visible currency/junk placeholder")
assert(w.SlotWidgets[5].Icon.visibility==0)
-- A missing saved actor remains visibly reserved ("?") until streamed.
physics.slots[5]=nil;physics.unresolvedSlots[5]=true
assert(Icons.refresh(pc,physics))
assert(w.SlotWidgets[5].InputIcon.InputKeyText.value=="5?")
-- Reused same-world HUD cleanup on LoadGame.
Icons.reset()
assert(w.SlotWidgets[5].InputIcon.InputKeyText.value=="5")
assert(w.SlotWidgets[5].Icon.visibility==2)
io.write("PASS: native construct thumbnail, currency placeholder, missing slot label, brush restoration and no repeated image setters\n")
