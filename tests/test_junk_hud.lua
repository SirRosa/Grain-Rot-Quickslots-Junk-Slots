package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local hud=require("junk_hud")
local function validObj()
    local o={}
    function o:IsValid() return true end
    return o
end
local widget=validObj()
function widget:AddToViewport(layer) self.layer=layer end
function widget:SetDesiredSizeInViewport(size) self.size=size end
function widget:SetAlignmentInViewport(v) self.alignment=v end
function widget:SetAnchorsInViewport(v) self.anchors=v end
function widget:SetPositionInViewport(v,s) self.position=v end
function widget:SetVisibility(n) self.visibility=n end
function widget:RemoveFromParent() self.removed=true end
local bpl=validObj()
local created=0
function bpl:Create(pc,klass,controller)
    assert(pc==controller and klass.isSlot)
    created=created+1
    return widget
end
StaticFindObject=function(p)
    if p=="/Script/UMG.Default__WidgetBlueprintLibrary" then return bpl end
end
local slotClass=validObj()
slotClass.isSlot=true
local inv=validObj()
inv.SlotWidgetClass=slotClass
local pc=validObj()
function pc:GetHUD() return {PlayerHudWidget={InventoryWidget=inv}} end
assert(hud.ensure(pc))
assert(widget.layer==98 and widget.anchors.Maximum.X==1)
assert(widget.position.X==-24 and widget.visibility==4 and widget.size.X==72)
assert(hud.ensure(pc) and created==1,"only one junk HUD slot per local client")
hud.reset()
assert(widget.removed)
io.write("PASS: native UMG slot widget creation, anchored bottom-right, no duplicate overlays\n")
