-- Regression: the user's real UE4SS log showed every keybind loaded, yet
-- "authoritative host pawn unavailable", with zero inventory probes.
-- BP-derived character IsA(string) may return false; LastPlayerChar must work.
package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local Context=require("player_context")
local world={}
function world:IsValid() return true end
function world:GetFullName() return "World /Game/Maps/Helden_Expedition" end
local function obj(name)
    local o={}
    function o:IsValid() return true end
    function o:GetFullName() return name end
    function o:GetWorld() return world end
    function o:IsA(s) return false end -- real source of the old total rejection
    return o
end
local pc=obj("BP_HeldenPlayerController_C /Game/Maps/Helden_Expedition.PC_1")
local pawn=obj("BP_HeldenCharacter_C /Game/Maps/Helden_Expedition.Character_1")
local stats=obj("HeldenCharacterStats /Game/Maps/Helden_Expedition.Stats_1")
pawn.CharacterStats=stats
pawn.InventorySettings={SlotSettings={{},{},{},{}}}
pawn.ItemSlots={{},{},{},{}}
function pc:GetPawn() return pawn end
function pc:IsLocalController() return true end
local gm=obj("BP_HeldenGameMode_C /Game/Maps/Helden_Expedition.Mode_1")
local groups={
    HeldenPlayerController={pc},
    HeldenGameMode={gm},
    GameModeBase={gm},
}
FindAllOf=function(class) return groups[class] end
FindFirstOf=function(class) return groups[class] and groups[class][1] end
local all=Context.resolveAll()
assert(#all==1 and all[1].pawn==pawn)
assert(all[1].auth and all[1].world==world:GetFullName())
assert(Context.pickLocal().pawn==pawn)
assert(Context.diagnostic():find("host=true",1,true),"must log authority")
-- Native GetPawn sometimes returns a temporary soul/unpossessed pawn.
local soul=obj("HeldenCharacterSoul /Game/Maps/Helden_Expedition.Soul_1")
function pc:GetPawn() return soul end
pc.LastPlayerChar=pawn
pc.SoulCharacter=soul
all=Context.resolveAll()
assert(all[1].pawn==pawn and all[1].source=="LastPlayerChar")
assert(all[1].auth,"host must still resolve during soul transition")
groups.HeldenGameMode={}
groups.GameModeBase={}
all=Context.resolveAll()
assert(#all==1 and not all[1].auth,"client cannot mutate world inventory")
io.write("PASS: BP pawn without IsA(string), controller enumeration, LastPlayerChar and host-only world check\n")
