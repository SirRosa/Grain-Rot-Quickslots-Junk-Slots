package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local Bank=require("junk_store")
local Actors=require("actor_storage")
local function unreal(class,id)
    local o={__class=class,__id=id,__valid=true}
    function o:IsValid() return self.__valid end
    function o:GetFullName() return self.__id end
    function o:IsA(s) return s=="/Script/Helden."..self.__class end
    return o
end
local world=unreal("World","World /Game/Dungeon")
local pawn=unreal("HeldenCharacter","Actor /Game/Player")
local item=unreal("HeldenPhysicsActor","Actor /Game/Item")
local mesh=unreal("StaticMeshComponent","Component /Game/Item.Mesh")
local handle=unreal("PhysicsHandleComponent","Component /Game/Player.Handle")
local grabbed={Target=item}
local messages={}
local bank=Bank.new(10)
local pocket=Actors.new(bank,function(msg) messages[#messages+1]=msg end)
function pawn:GetWorld() return world end
function item:GetWorld() return world end
function pawn:GetActorForwardVector() return {X=1,Y=0,Z=0} end
function pawn:K2_GetActorLocation() return {X=0,Y=0,Z=200} end
function pawn:K2_GetActorRotation() return {Pitch=0,Yaw=0,Roll=0} end
function item:K2_GetActorLocation() return {X=11,Y=9,Z=205} end
function item:K2_GetActorRotation() return {Pitch=0,Yaw=0,Roll=0} end
function handle:ReleaseComponent() self.released=true end
function mesh:SetSimulatePhysics(v) self.physics=v end
function mesh:SetEnableGravity(v) self.gravity=v end
function item:SetActorEnableCollision(v) self.collision=v end
function item:SetActorHiddenInGame(v) self.bHidden=v end
function item:K2_AttachToActor(p, socket, a,b,c,d)
    assert(socket=="None" and a==1 and b==1 and c==1)
    if self.failAttach then return false end
    self.parent=p
    return true
end
function item:GetAttachParentActor() return self.parent end
function item:K2_DetachFromActor() self.parent=nil end
function item:K2_TeleportTo(v,r)
    self.lastTeleport=v
    if self.failTeleport then return false end
    return true
end
pawn.GrabPhysHandle=handle
pawn.PhysGrabData=grabbed
item.RootMesh=mesh
assert(not pocket:store(pawn,nil),"cannot store when nothing grabbed")
assert(bank:count()==0)
local ok,result=pocket:store(pawn,item)
assert(ok and result==1,"should store real item")
assert(bank:count()==1 and item.bHidden==true and item.collision==false)
assert(mesh.physics==false and handle.released and grabbed.Target==nil)
assert(item.parent==pawn)
local duplicate,reason=pocket:store(pawn,item)
assert(not duplicate and bank:count()==1)
assert(bank:cycle(1) and bank.selected==2)
ok,reason=pocket:retrieve(pawn)
assert(not ok and reason=="empty")
assert(bank:select(1))
ok,result=pocket:retrieve(pawn)
assert(ok and result==1 and bank:count()==0)
assert(not item.bHidden and item.collision and mesh.physics and item.parent==nil)
assert(item.lastTeleport.X==135 and item.lastTeleport.Z==260)
assert(mesh.gravity)
grabbed.Target=item
item.failAttach=true
ok,reason=pocket:store(pawn,item)
assert(not ok and reason=="attachment_not_confirmed" and bank:count()==0)
assert(mesh.physics==true)
item.failAttach=false
grabbed.Target=item
assert(pocket:store(pawn,item))
item.failTeleport=true
ok,reason=pocket:retrieve(pawn)
assert(not ok and reason=="teleport_failed" and bank:count()==1)
assert(item.parent==pawn and item.bHidden==true)
item.failTeleport=false
assert(pocket:retrieve(pawn) and bank:count()==0)
io.write("PASS: real-actor mock store, native handle release, restore, full rejection and no item duplication\n")
