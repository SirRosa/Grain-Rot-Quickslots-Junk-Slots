-- Grain Rot native-gear continuity (host, save-slot scoped).
-- Native persistence's first line of defense is the 10-slot Blueprint CDO.
-- This companion manifest only records stable identities and allows a
-- bounded, identity-checked native re-pickup if actors were left on the floor.
-- It never writes to HeldenSaveGame.ItemSaveData, drops, destroys or clones
-- items already present in a player's inventory.
local M={}
M.__index=M
local function valid(o)
    if o==nil then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v==true
end
local function get(o,key)
    if o==nil then return nil end
    local ok,v=pcall(function() return o[key] end)
    if ok then return v end
end
local function name(o)
    if not valid(o) then return nil end
    local ok,v=pcall(function() return o:GetFullName() end)
    if ok and v then return tostring(v) end
end
local function path(o)
    local n=name(o)
    return n and n:match("%s(.+)$") or nil
end
local function sval(v)
    if v==nil then return nil end
    local ok,s=pcall(function() return v:ToString() end)
    return (ok and s) and tostring(s) or tostring(v)
end
local function enum(v)
    local n=tonumber(v)
    if n then return n end
    local t=sval(v)
    if t and t:find("Dead",1,true) then return 1 end
    if t and t:find("Default",1,true) then return 0 end
    return nil
end
local function length(array)
    local ok,n=pcall(function() return #array end)
    return ok and n or 0
end
local function escape(t)
    return (tostring(t or ""):gsub("([^%w_.:/%-])",function(c)
        return string.format("%%%02X",string.byte(c))
    end))
end
local function unescape(t)
    return (t:gsub("%%(%x%x)",function(hex)
        return string.char(tonumber(hex,16))
    end))
end
local function snapshot(pawn)
    local arr=get(pawn,"EquipedItems")
    local rows,seen={},{}
    for i=1,math.min(length(arr),64) do
        local item
        pcall(function() item=arr[i] end)
        if valid(item) then
            local idx=tonumber(get(item,"CurrentInventorySlot"))
            local dyn=sval(get(item,"DynamicSaveName"))
            local owner=get(item,"PreviousOwner")
            if idx and idx>=4 and idx<=9 and dyn and dyn~="None" and
                dyn~="" and not seen[dyn] and valid(get(item,"CurrentSlot")) and
                (not valid(owner) or name(owner)==name(pawn)) then
                local cls
                pcall(function() cls=item:GetClass() end)
                local asset=get(item,"ItemDataAsset")
                local classPath=path(cls)
                if classPath then
                    seen[dyn]=true
                    rows[#rows+1]={slot=idx,dyn=dyn,klass=classPath,
                        asset=path(asset) or "",
                        durability=tonumber(get(item,"ItemDurability")),
                        enchant=sval(get(item,"ItemEnchantment")) or "",
                        ref=item,owner=name(pawn)}
                end
            end
        end
    end
    table.sort(rows,function(a,b) return a.slot<b.slot end)
    return rows
end
local function serialize(slot,savename,played,rows)
    local out={"QJS2\t"..slot.."\t"..escape(savename).."\t"..
        string.format("%.3f",played).."\t"..#rows}
    for _,r in ipairs(rows) do
        out[#out+1]=table.concat({r.slot,escape(r.dyn),escape(r.klass),
            escape(r.asset),r.durability or "",escape(r.enchant)},"\t")
    end
    return table.concat(out,"\n").."\n"
end
local function parse(data,slot,savename,played)
    local lines={}
    for line in (data.."\n"):gmatch("(.-)\n") do
        if line~="" then lines[#lines+1]=line end
    end
    local header=lines[1]
    if not header then return nil,"empty" end
    local ver,sv,scoped,time,count=header:match(
        "^(%w+)\t(%d+)\t([^\t]*)\t([%d%.]+)\t(%d+)$")
    if ver~="QJS2" or tonumber(sv)~=slot or unescape(scoped or "")~=savename then
        return nil,"different_save"
    end
    local t,c=tonumber(time),tonumber(count)
    if not t or not c or c>6 or t>played+5 or played>t+600 then
        return nil,"stale_or_invalid_manifest"
    end
    local rows,used={},{}
    if #lines~=c+1 then return nil,"invalid_count" end
    for i=2,#lines do
        local n,d,k,a,h,e=lines[i]:match(
            "^(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        local idx=tonumber(n)
        d,k,a,e=unescape(d or ""),unescape(k or ""),
            unescape(a or ""),unescape(e or "")
        if not idx or idx<4 or idx>9 or d=="" or k=="" or used[idx] or
            #k>512 or #d>256 then return nil,"invalid_row" end
        used[idx]=true
        rows[#rows+1]={slot=idx,dyn=d,klass=k,asset=a,
            durability=tonumber(h),enchant=e}
    end
    return rows,"ok"
end
local function toRecordTable(rows)
    local t={}
    for _,r in ipairs(rows) do t[r.dyn]=r end
    return t
end
local function isAlive(pawn)
    if not valid(pawn) then return false end
    local st=enum(get(pawn,"CharacterState"))
    if st==1 then return false end
    local hp=tonumber(get(get(pawn,"CharacterStats"),"CurrentHealth"))
    return hp==nil or hp>0
end
local function acquireWorld(pawn)
    local ok,w=pcall(function() return pawn:GetWorld() end)
    if ok and valid(w) then return w end
end
local function owns(pawn,item)
    if not valid(item) then return false end
    local owner=get(item,"PreviousOwner")
    if valid(owner) and name(owner)==name(pawn)
        and valid(get(item,"CurrentSlot")) then return true end
    local arr=get(pawn,"EquipedItems")
    for i=1,math.min(length(arr),64) do
        local o
        pcall(function() o=arr[i] end)
        if name(o)==name(item) then return true end
    end
    return false
end
local function occupied(pawn,index,except)
    local arr=get(pawn,"EquipedItems")
    for i=1,math.min(length(arr),64) do
        local a
        pcall(function() a=arr[i] end)
        if valid(a) and name(a)~=name(except) and
            tonumber(get(a,"CurrentInventorySlot"))==index then
            return true
        end
    end
    return false
end
local function moveToSavedSlot(pawn,item,slot)
    if not valid(item) or not owns(pawn,item) then return false,"not_owned" end
    if tonumber(get(item,"CurrentInventorySlot"))==slot then return true,"already_slot" end
    if occupied(pawn,slot,item) then return false,"slot_occupied" end
    local arr=get(pawn,"ItemSlots")
    if length(arr)<slot+1 then return false,"target_slot_missing" end
    local ref
    pcall(function() ref=arr[slot+1] end)
    local component=get(ref,"SlotComponent")
    if not valid(component) then return false,"target_slot_component_missing" end
    local ok,err=pcall(function()
        item.CurrentSlot=component
        item.CurrentInventorySlot=slot
    end)
    if not ok then return false,"assignment_failed_"..tostring(err) end
    if name(get(item,"CurrentSlot"))~=name(component) or
        tonumber(get(item,"CurrentInventorySlot"))~=slot then
        return false,"readback_failed"
    end
    -- Refresh game's native equip/holster render state; do not modify
    -- EquipedItems directly or invent inventory ownership.
    pcall(function() item:OnRep_CurrentSlot() end)
    pcall(function() item:OnRep_CurrentInventorySlot() end)
    return true,"rebound"
end
local function findExisting(records)
    if type(FindAllOf)~="function" then return {} end
    local ok,items=pcall(FindAllOf,"HeldenEquipableItem")
    if not ok or type(items)~="table" then return {} end
    local byIdentity={}
    for _,item in ipairs(items) do
        if valid(item) then
            local dyn=sval(get(item,"DynamicSaveName"))
            if dyn and records[dyn] then byIdentity[dyn]=item end
        end
    end
    return byIdentity
end
local function tryPickup(pawn,item,rec)
    if not valid(pawn) or not valid(item) then return false,"actor_missing" end
    local prev=get(item,"PreviousOwner")
    if valid(prev) and name(prev)~=rec.owner and name(prev)~=name(pawn) then
        return false,"another_player_owned"
    end
    if owns(pawn,item) then
        return moveToSavedSlot(pawn,item,rec.slot)
    end
    -- Only the game's own Interact can claim item ownership. Do not call
    -- DetachFromAll, change native physics grab data or fake EquipedItems.
    local ok,why=pcall(function() item:Interact(pawn) end)
    if not ok then return false,"native_pickup_error_"..tostring(why) end
    if not owns(pawn,item) then return false,"native_pickup_pending" end
    return moveToSavedSlot(pawn,item,rec.slot)
end
local function spawnMissing(pawn,rec)
    -- Cold-start fallback only: no spawning for respawn where ExpeditionSaver
    -- may already be retrieving the same item.
    if not rec.klass or rec.klass=="" or type(StaticFindObject)~="function"
        then return nil,"class_missing" end
    local ok,klass=pcall(StaticFindObject,rec.klass)
    if not ok or not valid(klass) then return nil,"class_not_loaded" end
    local world=acquireWorld(pawn)
    if not world then return nil,"world_unavailable" end
    local loc
    pcall(function() loc=pawn:K2_GetActorLocation() end)
    if not loc then return nil,"position_unavailable" end
    local pos={X=(tonumber(get(loc,"X")) or 0)+100,
        Y=tonumber(get(loc,"Y")) or 0,
        Z=(tonumber(get(loc,"Z")) or 0)+55}
    local spawned,actor=pcall(function()
        return world:SpawnActor(klass,pos,{Pitch=0,Yaw=0,Roll=0})
    end)
    if not spawned or not valid(actor) then return nil,"spawn_failed" end
    if rec.asset~="" then
        local found,asset=pcall(StaticFindObject,rec.asset)
        if found and valid(asset) then
            pcall(function() actor.ItemDataAsset=asset end)
        end
    end
    if rec.durability~=nil then
        pcall(function() actor.ItemDurability=rec.durability end)
        pcall(function() actor:OnRep_ItemDurability() end)
    end
    if rec.enchant and rec.enchant~="" and FName then
        local named,enchant=pcall(FName,rec.enchant)
        if named and enchant then
            pcall(function() actor.ItemEnchantment=enchant end)
            pcall(function() actor:OnRep_ItemEnchantment() end)
        end
    end
    return actor,"spawned_once"
end
function M.new(logger,opts)
    opts=opts or {}
    return setmetatable({log=logger or function()end,root=opts.root,
        scope=nil,lastPawn=nil,lastRows={},pending=nil,
        pendingKind=nil,pendingTicks=0,restoreAttempts={},
        spawned={},lastSaved=nil,ticks=0,emptyStreak=0},M)
end
function M:resetWorld()
    -- Do not carry potentially invalid UObject actor refs across map travel.
    -- Keep the sidecar untouched and reload it on the new map.
    self.scope=nil;self.lastPawn=nil;self.lastRows={}
    self.pending=nil;self.pendingKind=nil;self.pendingTicks=0
    self.restoreAttempts={};self.spawned={};self.lastSaved=nil
    self.emptyStreak=0
    self.lastPawnRef=nil;self.lastSave=nil
end

function M:fileFor(slot)
    local base=self.root or (os.getenv and os.getenv("LOCALAPPDATA"))
    if not base or base=="" then return nil end
    local sep=base:find("\\",1,true) and "\\" or "/"
    if not self.root then base=base..sep.."Helden"..sep.."Saved" end
    return base..sep.."GrainRotQuickJunk_slot"..slot.."_host.txt"
end
function M:readManifest(slot,saveName,played)
    local filename=self:fileFor(slot)
    if not filename then return nil,"no_local_app_data" end
    local f=io.open(filename,"rb")
    if not f then return nil,"no_backup" end
    local data=f:read(8192);f:close()
    if not data then return nil,"read_failed" end
    return parse(data,slot,saveName,played)
end
function M:writeManifest(slot,saveName,played,rows)
    local filename=self:fileFor(slot)
    if not filename then return false,"no_local_app_data" end
    local payload=serialize(slot,saveName,played,rows)
    if self.lastSaved==payload then return true,"unchanged" end
    local tmp=filename..".tmp"
    local f=io.open(tmp,"wb")
    if not f then return false,"write_failed" end
    f:write(payload);f:flush();f:close()
    -- Preserve the last good manifest if any rename fails.
    local bak=filename..".bak"
    os.remove(bak)
    os.rename(filename,bak)
    local ok,err=os.rename(tmp,filename)
    if not ok then
        os.rename(bak,filename)
        return false,"rename_failed_"..tostring(err)
    end
    self.lastSaved=payload
    return true,"written"
end
-- Match the manifest to the real game's successful SaveGame lifecycle.
-- When the user removes the last item and saves immediately, this overrides
-- any older periodic snapshot so a consumed item is not resurrected.
function M:checkpoint()
    local pawn,save=self.lastPawnRef,self.lastSave
    if self.pending or not isAlive(pawn) or not valid(save) then
        return false,"recovery_or_dead"
    end
    local md=get(save,"MetaData")
    local slot=tonumber(get(md,"GameSlot"))
    local saveName=sval(get(md,"SaveSlotName")) or ""
    local played=tonumber(get(save,"TimePlayed")) or 0
    if not slot or self.scope~=tostring(slot)..":"..saveName then
        return false,"wrong_save_scope"
    end
    local rows=snapshot(pawn)
    local ok,why=self:writeManifest(slot,saveName,played,rows)
    if ok then self.lastRows=rows;self.emptyStreak=0 end
    return ok,why
end

function M:tick(pc,pawn,save,world)
    if not valid(pc) or not valid(pawn) or not valid(save) or not valid(world) then
        return false,"no_host_save_context"
    end
    local metadata=get(save,"MetaData")
    local slot=tonumber(get(metadata,"GameSlot"))
    local saveName=sval(get(metadata,"SaveSlotName")) or ""
    local played=tonumber(get(save,"TimePlayed")) or 0
    if not slot or slot<0 or slot>100 then return false,"save_slot_unavailable" end
    local scope=tostring(slot)..":"..saveName
    if scope~=self.scope then
        self.scope=scope;self.lastPawn=nil;self.lastRows={}
        self.ticks=0;self.lastSaved=nil;self.spawned={};self.emptyStreak=0
        self.restoreAttempts={};self.pendingTicks=0;self.pendingKind=nil
        local rows,reason=self:readManifest(slot,saveName,played)
        self.pending=rows and toRecordTable(rows) or nil
        if rows and #rows>0 then
            self.pendingKind="reload"
            self.log("[PERSIST] loaded "..#rows.." slot 5-10 records; native restore first")
        else
            self.log("[PERSIST] no matching manifest ("..tostring(reason)..")")
        end
    end
    self.ticks=self.ticks+1
    self.lastSave=save
    self.lastPawnRef=pawn
    if not isAlive(pawn) then return true,"dead_paused" end
    local pawnId=name(pawn)
    if self.lastPawn and self.lastPawn~=pawnId and #self.lastRows>0 then
        local candidates=toRecordTable(self.lastRows)
        self.pending=candidates
        self.pendingKind="respawn"
        self.pendingTicks=0;self.restoreAttempts={};self.spawned={}
        self.log("[PERSIST] new pawn detected, recovering "..#self.lastRows..
            " old native items; no spawns allowed during respawn")
    end
    self.lastPawn=pawnId
    local records=snapshot(pawn)
    if not self.pending and #records>0 then
        self.lastRows=records
    end
    if self.pending and length(get(pawn,"ItemSlots"))>=10 then
        self.pendingTicks=self.pendingTicks+1
        local current=toRecordTable(records)
        local matched={}
        for id,rec in pairs(self.pending) do
            local own=current[id]
            if own and own.slot==rec.slot then matched[id]=true end
        end
        local missing={}
        for id,rec in pairs(self.pending) do
            if not matched[id] then missing[id]=rec end
        end
        local seenActors={}
        if next(missing)~=nil and self.pendingTicks>=3 and self.pendingTicks%3==0 then
            seenActors=findExisting(missing)
        end
        for id,rec in pairs(missing) do
            if self.pendingTicks>=3 and self.pendingTicks%3==0 and
                (self.restoreAttempts[id] or 0)<6 then
                local actor=(valid(rec.ref) and rec.ref) or self.spawned[id] or seenActors[id]
                if not actor and self.pendingKind=="reload" and
                    self.pendingTicks>=6 and not self.spawned[id] then
                    actor=spawnMissing(pawn,rec)
                    if valid(actor) then
                        self.spawned[id]=actor
                        self.log("[PERSIST] one-shot cold-load actor restored for slot "..(rec.slot+1))
                    end
                end
                if valid(actor) then
                    local done,reason=tryPickup(pawn,actor,rec)
                    self.restoreAttempts[id]=(self.restoreAttempts[id] or 0)+1
                    if done then
                        matched[id]=true
                        self.log("[PERSIST] native item restored to slot "..(rec.slot+1)..
                            " identity="..id)
                    elseif self.restoreAttempts[id]==6 then
                        self.log("[PERSIST] item still not restored "..id.." reason="..tostring(reason))
                    end
                end
            end
        end
        for id in pairs(matched) do self.pending[id]=nil end
        if next(self.pending)==nil then
            self.log("[PERSIST] original slots 5-10 reconciled without item duplication")
            self.pending=nil;self.pendingKind=nil;self.pendingTicks=0
            records=snapshot(pawn)
            self.lastRows=records
        end
    end
    -- Never overwrite a pre-death or pre-reload backup with an empty pawn.
    -- A failed restoration stays visible in logs and the manifest persists.
    if not self.pending then
        if #records==0 then
            self.emptyStreak=self.emptyStreak+1
        else
            self.emptyStreak=0
        end
        if self.ticks>=4 and self.ticks%5==0 then
            local latest=snapshot(pawn)
            -- Explicitly clearing the last extra slot must also persist.
            -- Otherwise a stale manifest could resurrect an intentionally
            -- dropped/sold/consumed item after a later restart.
            if #latest>0 or #self.lastRows==0 or self.emptyStreak>=5 then
                local ok,reason=self:writeManifest(slot,saveName,played,latest)
                if not ok and self.ticks==5 then
                    self.log("[PERSIST] backup unavailable: "..tostring(reason))
                end
                self.lastRows=latest
            end
        end
    end
    return true,self.pending and ("recovering_"..tostring(self.pendingKind)) or "ready"
end
M.snapshot=snapshot
M.parse=parse
M.serialize=serialize
M.moveToSavedSlot=moveToSavedSlot
return M
