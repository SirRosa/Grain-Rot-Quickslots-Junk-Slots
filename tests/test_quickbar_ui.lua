-- Native quickbar widget extension must never fake inventory capacity.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local bar=require("quickbar_ui")
local function object(id)
  local x={_id=id}
  function x:IsValid() return true end
  function x:GetFullName() return self._id end
  return x
end
FText=setmetatable({},{__call=function(_,s)
  return {ToString=function() return s end}
end})
FName=setmetatable({},{__call=function(_,s) return s end})
local pc=object("PC /Game/Test.PC")
local pawn=object("BP_HeldenCharacter_C /Game/Test.Player")
local widgets={}
for i=1,4 do widgets[i]=object("Widget /Game/Test.Slot"..i) end
local class=object("Class /Game/UI.GameSlotWidget")
local container=object("HorizontalBox /Game/UI.InventorySlotBox")
function container:AddChild(w)
  w.parent=self
  return object("HorizontalBoxSlot /Game/UI.Slot")
end
local inv=object("InventoryWidget /Game/UI.Inventory")
inv.SlotWidgetClass=class
inv.InventorySlotBox=container
inv.SlotWidgets=widgets
function inv:OnSetInventoryWidget() self.refreshCount=(self.refreshCount or 0)+1 end
function pc:GetHUD()
  return {PlayerHudWidget={InventoryWidget=inv}}
end
local lib=object("WidgetBlueprintLibrary")
local nextid=0
function lib:Create(controller,klass,own)
  assert(controller==pc and klass==class and own==pc)
  nextid=nextid+1
  local w=object("WBP_Slot_"..nextid)
  local icon=object("WBP_InputIcon_"..nextid)
  local label=object("TextBlock_"..nextid)
  function label:SetText(t) self.text=t end
  function label:GetText() return self.text end
  function label:SetVisibility(n) self.visibility=n end
  local image=object("InputImage_"..nextid)
  function image:SetVisibility(n) self.visibility=n end
  icon.InputKeyText=label
  icon.InputIconWidget=image
  w.InputIcon=icon
  function w:GetSlotIndex() return #widgets end
  function w:RemoveFromParent() self.parent=nil end
  return w
end
StaticFindObject=function(name)
  if name=="/Script/UMG.Default__WidgetBlueprintLibrary" then return lib end
  return nil
end
local logs={}
local function logger(msg) logs[#logs+1]=msg end
pawn.ItemSlots={{},{},{},{}}
local yes,why=bar.ensure(pc,pawn,logger)
assert(not yes and why=="player_native_slots_not_10")
assert(#widgets==4 and nextid==0,"never create cosmetic-only extra slots")
for i=5,10 do pawn.ItemSlots[i]={} end
yes,why=bar.ensure(pc,pawn,logger)
assert(yes and why=="added_native_widgets_labeled" and #widgets==10)
assert(nextid==6 and inv.refreshCount==1)
assert(#pawn.ItemSlots==10)
yes,why=bar.ensure(pc,pawn,logger)
assert(yes and why=="native_widgets_10_labeled" and nextid==6)
for i=5,10 do
  assert(widgets[i].parent==container)
  local digit=({"5","6","7","8","9","0"})[i-4]
  assert(widgets[i].InputIcon.InputKeyText:GetText():ToString()==digit)
  assert(widgets[i].InputIcon.IconType==1)
  assert(widgets[i].InputIcon.InputIconWidget.visibility==2)
end
io.write("PASS: 10 native UMG slots with explicit visible 5-0 keys, no default Ctrl text, real capacity required\n")
