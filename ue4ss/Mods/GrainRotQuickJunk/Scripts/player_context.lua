-- Resolve real Grain Rot player controllers, pawns and host authority.
-- The earlier code rejected every player if UObject:IsA(string) failed.
-- HeldenCharacter is a parent class of BP player pawns; inventory fields
-- are stronger evidence than the boolean string IsA() result on UE4SS v3.
local M={}
local function good(o)
    if o==nil then return false end
    local ok,res=pcall(function() return o:IsValid() end)
    return ok and res==true
end
local function get(o,k)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
    return nil
end
local function name(o)
    if not good(o) then return "none" end
    local ok,v=pcall(function() return o:GetFullName() end)
    return ok and tostring(v) or "unknown"
end
local function live(o)
    local n=name(o)
    return good(o) and not n:find("Default__",1,true)
        and not n:find("SKEL_",1,true)
end
local function findAll(cls)
    if type(FindAllOf)~="function" then return {}, "missing" end
    local ok,x=pcall(FindAllOf,cls)
    if not ok then return {},tostring(x) end
    if type(x)~="table" then return {},type(x) end
    return x,nil
end
local function findFirst(cls)
    if type(FindFirstOf)~="function" then return nil end
    local ok,o=pcall(FindFirstOf,cls)
    if ok and live(o) then return o end
    return nil
end
local function getWorld(o)
    if not good(o) then return nil end
    local ok,w=pcall(function() return o:GetWorld() end)
    if ok and good(w) then return w end
    return nil
end
local function worldId(o)
    local w=getWorld(o)
    return w and name(w) or nil
end
local function char(pawn)
    if not live(pawn) then return false end
    -- A controlled Helden player pawn exposes these reflected properties.
    -- Unlike IsA("/Script/Helden.HeldenCharacter"), this handles BP-derived
    -- players on builds whose IsA accepts UClass userdata only.
    local stats=get(pawn,"CharacterStats")
    local settings=get(pawn,"InventorySettings")
    local slots=get(pawn,"ItemSlots")
    return good(stats) and settings~=nil and slots~=nil
end
local function controllers()
    local list=findAll("HeldenPlayerController")
    local result={}
    local paths={}
    for _,pc in ipairs(list) do
        if live(pc) and not paths[name(pc)] then
            paths[name(pc)]=true;result[#result+1]=pc
        end
    end
    if #result==0 then
        local first=findFirst("HeldenPlayerController")
        if live(first) then result[1]=first end
    end
    return result
end
local function pawns(pc)
    local direct
    pcall(function() direct=pc:GetPawn() end)
    local last=get(pc,"LastPlayerChar")
    local soul=get(pc,"SoulCharacter")
    -- GetPawn may currently refer to a soul or a transient Unreal actor.
    if char(direct) and name(direct)~=name(soul) then
        return direct,"GetPawn",direct,last
    end
    if char(last) then
        return last,"LastPlayerChar",direct,last
    end
    return nil,"unresolved",direct,last
end
local function authority(pawn,world)
    if not char(pawn) then return false,"not_player_character" end
    local ok,has=pcall(function() return pawn:HasAuthority() end)
    if ok and type(has)=="boolean" then
        if not has then return false,"client_no_authority" end
        -- On some UE4SS builds HasAuthority may not be callable.
        -- Also require a real GameMode actor in the same world.
    end
    local candidates={}
    for _,class in ipairs({"HeldenGameMode","GameModeBase"}) do
        local a=findAll(class)
        for _,g in ipairs(a) do candidates[#candidates+1]=g end
        if #candidates==0 then
            local f=findFirst(class)
            if f then candidates[#candidates+1]=f end
        end
    end
    for _,gm in ipairs(candidates) do
        if live(gm) then
            local w=worldId(gm)
            if w and world and w==world then return true,"world_game_mode" end
        end
    end
    return false,"no_matching_game_mode"
end
function M.resolveAll()
    local found={}
    local pcs=controllers()
    for _,pc in ipairs(pcs) do
        local pawn,source,raw,last=pawns(pc)
        local world=pawn and worldId(pawn) or nil
        local auth,why=authority(pawn,world)
        local localController=false
        pcall(function() localController=pc:IsLocalController()==true end)
        found[#found+1]={
            pc=pc,pawn=pawn,raw=raw,last=last,
            source=source,world=world,auth=auth,authWhy=why,
            isLocal=localController,
        }
    end
    return found
end
function M.pickLocal()
    local entries=M.resolveAll()
    for _,item in ipairs(entries) do
        if item.isLocal and good(item.pawn) then return item end
    end
    if #entries==1 and good(entries[1].pawn) then
        return entries[1]
    end
    return nil
end
function M.diagnostic()
    local entries=M.resolveAll()
    local s={"controllers="..#entries}
    for i,e in ipairs(entries) do
        local rawName=name(e.raw)
        local lastName=name(e.last)
        s[#s+1]=string.format("[%d] source=%s char=%s raw=%s last=%s world=%s host=%s(%s) local=%s",
            i,e.source,name(e.pawn),rawName,lastName,
            tostring(e.world),tostring(e.auth),e.authWhy,
            tostring(e.isLocal))
    end
    return table.concat(s," | ")
end
M.valid=good
M.full=name
M.worldOf=worldId
M.all=findAll
return M
