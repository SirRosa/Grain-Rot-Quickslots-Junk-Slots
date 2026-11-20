-- Save-scoped virtual quickslot state for HeldenPhysicsActor instances.
-- Native HeldenSaveGame.ItemSaveData only serializes HeldenEquipableItem;
-- physics objects cannot be put into that native map as "inventory items".
-- A separate manifest records their class/identity and original RMB grab
-- payload. On load, native actors are matched first. Reconstruction (one
-- attempt, outside a dungeon only) is deliberately conservative.
local M={}
M.__index=M
local function valid(o)
    if not o then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v==true
end
local function read(o,k)
    if not o then return nil end
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
end
local function str(v)
    if v==nil then return "" end
    local ok,s=pcall(function() return v:ToString() end)
    return ok and tostring(s) or tostring(v)
end
local function escape(s)
    return (tostring(s or ""):gsub("([^%w%._:/%-])",function(c)
        return string.format("%%%02X",string.byte(c))
    end))
end
local function unescape(s)
    return (s:gsub("%%(%x%x)",function(h)
        return string.char(tonumber(h,16))
    end))
end
local function number(v)
    local n=tonumber(v)
    if n and n==n and n>-1e9 and n<1e9 then return n end
end
local function classOf(o)
    local ok,c=pcall(function() return o:GetClass() end)
    if not ok or not valid(c) then return nil end
    local okn,n=pcall(function() return c:GetFullName() end)
    if okn and n then return tostring(n):match("%s(.+)$") end
end
local function fileFields(row)
    local p,r,g=row.pos,row.rot,row.grab
    if not p or not r or not g then return nil end
    local a={row.slot,escape(row.id),escape(row.class),
        escape(row.asset),escape(row.originName),
        p.X,p.Y,p.Z,r.Pitch,r.Yaw,r.Roll,
        g.up.X,g.up.Y,g.up.Z,
        g.normal.X,g.normal.Y,g.normal.Z,
        g.grabOffset.X,g.grabOffset.Y,g.grabOffset.Z,
        g.handleOffset.X,g.handleOffset.Y,g.handleOffset.Z,
        g.timestamp}
    for i=1,#a do
        if a[i]==nil then return nil end
    end
    return table.concat(a,"\t")
end
local function parseLine(line)
    local fields={}
    for part in (line.."\t"):gmatch("(.-)\t") do
        fields[#fields+1]=part
    end
    if #fields~=24 then return nil,"invalid_fields_"..#fields end
    local n={}
    for i=1,24 do
        if i>5 then
            n[i]=number(fields[i])
            if not n[i] then return nil,"invalid_numeric_field_"..i end
        end
    end
    local slot=number(fields[1])
    if not slot or slot%1~=0 or slot<1 or slot>10 then
        return nil,"invalid_slot"
    end
    local id,klass,asset,origin=unescape(fields[2]),
        unescape(fields[3]),unescape(fields[4]),unescape(fields[5])
    if id=="" or #id>500 or klass=="" or #klass>500 then
        return nil,"invalid_identity"
    end
    return {
        slot=slot,id=id,class=klass,asset=asset,originName=origin,
        pos={X=n[6],Y=n[7],Z=n[8]},
        rot={Pitch=n[9],Yaw=n[10],Roll=n[11]},
        grab={
            up={X=n[12],Y=n[13],Z=n[14]},
            normal={X=n[15],Y=n[16],Z=n[17]},
            grabOffset={X=n[18],Y=n[19],Z=n[20]},
            handleOffset={X=n[21],Y=n[22],Z=n[23]},
            timestamp=n[24],
        }
    }
end
local function serialize(slot,saveName,played,rows)
    local out={"PQ1\t"..slot.."\t"..escape(saveName).."\t"..
        string.format("%.3f",played).."\t"..#rows}
    for _,r in ipairs(rows) do
        local encoded=fileFields(r)
        if not encoded then return nil,"incomplete_physics_record" end
        out[#out+1]=encoded
    end
    return table.concat(out,"\n").."\n"
end
local function parse(data,slot,saveName,played)
    local lines={}
    for line in (data.."\n"):gmatch("(.-)\n") do
        if line~="" then lines[#lines+1]=line end
    end
    local version,sl,nm,t,n=(lines[1] or ""):match(
        "^(%w+)\t(%d+)\t([^\t]*)\t([%d%.]+)\t(%d+)$")
    if version~="PQ1" or tonumber(sl)~=slot or
        unescape(nm or "")~=saveName then
        return nil,"different_slot_or_version"
    end
    local previous=tonumber(t)
    local count=tonumber(n)
    if not previous or not count or count>10 or
        previous>played+5 or played>previous+3600 then
        return nil,"stale_or_invalid_time"
    end
    if #lines~=count+1 then return nil,"wrong_line_count" end
    local rows,used={},{}
    for i=2,#lines do
        local row,why=parseLine(lines[i])
        if not row or used[row.slot] then
            return nil,why or "duplicate_slot"
        end
        used[row.slot]=true
        rows[#rows+1]=row
    end
    return rows,"ok"
end
local function rowFor(entry,physics)
    local actor=entry.actor
    local class=entry.class or (valid(actor) and classOf(actor)) or ""
    local asset=entry.asset
    if not asset and valid(actor) then
        asset=physics.name(read(actor,"InitConAsset"))
            or physics.name(read(actor,"SettingsAsset")) or ""
    end
    local origin=entry.originName or (valid(actor) and physics.name(actor)) or ""
    return {slot=entry.slot,id=entry.identity or
        (valid(actor) and physics.keyOf(actor)) or "",
        class=class,asset=asset or "",originName=origin,
        pos=entry.originalPosition or (valid(actor) and physics.location(actor)),
        rot=entry.originalRotation or (valid(actor) and physics.rotation(actor)),
        grab=entry.grab}
end
local function scopeOf(save)
    local meta=read(save,"MetaData")
    local slot=number(read(meta,"GameSlot"))
    local saveName=str(read(meta,"SaveSlotName"))
    local played=number(read(save,"TimePlayed")) or 0
    if not slot or slot<0 or slot>100 then return nil end
    return {slot=slot,name=saveName,played=played,
        key=tostring(slot).."|"..saveName}
end
local function activeDungeon(save)
    local x=read(save,"GameState")
    return number(x)==1 or str(x):find("Dungeon",1,true)~=nil
end
function M.new(log,physics,options)
    options=options or {}
    return setmetatable({log=log or function() end,physics=physics,
        root=options.root,scope=nil,lastPayload=nil,unresolved={},
        scanCount=0,spawned={},lastError=nil,dirty=false},M)
end
function M:fileFor(slot)
    local base=self.root or (os.getenv and os.getenv("LOCALAPPDATA"))
    if not base or base=="" then return nil end
    local sep=base:find("\\",1,true) and "\\" or "/"
    if not self.root then base=base..sep.."Helden"..sep.."Saved" end
    return base..sep.."GrainRotQuickJunk_physics_slot"..slot.."_host.txt"
end
function M:readManifest(scope)
    local filename=self:fileFor(scope.slot)
    if not filename then return nil,"localappdata_unavailable" end
    local f=io.open(filename,"rb")
    if not f then return nil,"manifest_missing" end
    local data=f:read(16384);f:close()
    if not data then return nil,"manifest_read_failed" end
    return parse(data,scope.slot,scope.name,scope.played)
end
function M:resetWorld()
    self.scope=nil;self.lastPayload=nil;self.unresolved={}
    self.scanCount=0;self.spawned={};self.lastError=nil
end
function M:rows()
    local rows,used={},{}
    for _,entry in ipairs(self.unresolved) do
        if not used[entry.slot] then
            rows[#rows+1]=entry
            used[entry.slot]=true
        end
    end
    for i=1,10 do
        local entry=self.physics:get(i)
        if entry then
            local row=rowFor(entry,self.physics)
            if row.id~="" then
                if used[i] then
                    for j=1,#rows do
                        if rows[j].slot==i then
                            rows[j]=row;break
                        end
                    end
                else
                    rows[#rows+1]=row
                end
                used[i]=true
            end
        end
    end
    table.sort(rows,function(a,b) return a.slot<b.slot end)
    return rows
end
function M:checkpoint(save)
    local scope=scopeOf(save)
    if not scope then return false,"save_scope_missing" end
    if not self.scope or self.scope.key~=scope.key then
        return false,"not_loaded_for_this_save"
    end
    local rows=self:rows()
    local payload,err=serialize(scope.slot,scope.name,scope.played,rows)
    if not payload then return false,err end
    if payload==self.lastPayload then return true,"unchanged" end
    local filename=self:fileFor(scope.slot)
    if not filename then return false,"localappdata_unavailable" end
    local tmp=filename..".tmp"
    local f=io.open(tmp,"wb")
    if not f then return false,"file_open_failed" end
    local ok,writeError=pcall(function() f:write(payload);f:flush() end)
    f:close()
    if not ok then return false,"write_failed_"..tostring(writeError) end
    local backup=filename..".bak"
    os.remove(backup)
    os.rename(filename,backup)
    local renamed,err=os.rename(tmp,filename)
    if not renamed then
        os.rename(backup,filename)
        return false,"rename_failed_"..tostring(err)
    end
    self.lastPayload=payload
    return true,"written"
end
local function findExisting(rows,physics)
    local wanted={}
    for _,r in ipairs(rows) do wanted[r.id]=true end
    local found={}
    if type(FindAllOf)~="function" then return found end
    local ok,items=pcall(FindAllOf,"HeldenPhysicsActor")
    if not ok or type(items)~="table" then return found end
    for _,actor in ipairs(items) do
        if valid(actor) and wanted[physics.keyOf(actor)] then
            found[physics.keyOf(actor)]=actor
        end
    end
    return found
end
function M:poll(pawn,save)
    if not valid(pawn) or not valid(save) then
        return false,"no_player_or_save"
    end
    local scope=scopeOf(save)
    if not scope then return false,"save_scope_unavailable" end
    if not self.scope or self.scope.key~=scope.key then
        self.scope=scope;self.unresolved={};self.scanCount=0
        self.spawned={};self.lastPayload=nil
        local rows,why=self:readManifest(scope)
        if rows then
            self.unresolved=rows
            if #rows>0 then
                self.log("[PHYS SAVE] found "..#rows..
                    " shared 1-0 quickslot records; restoring original actors")
            end
        elseif why~="manifest_missing" then
            self.log("[PHYS SAVE] manifest ignored: "..tostring(why))
        end
    else
        self.scope=scope
    end
    if #self.unresolved==0 then return true,"ready" end
    if self.physics.pending then return false,"transaction_pending" end
    self.scanCount=self.scanCount+1
    -- Heavy FindAllOf is limited to once per 2s caller (not 500ms tick).
    local found=findExisting(self.unresolved,self.physics)
    local native,size=self.physics.nativeOccupied(pawn,true)
    if size<10 then return false,"waiting_native_10_slot_inventory" end
    local pending={}
    for _,row in ipairs(self.unresolved) do
        local actor=found[row.id]
        local slot=row.slot
        if self.physics:hasSlot(slot) or native[slot] then
            -- Native item has priority over virtual physics reservation.
            local nextFree
            for i=1,10 do
                if not native[i] and not self.physics:hasSlot(i) then
                    local reserved=false
                    for _,r in ipairs(pending) do
                        if r.slot==i then reserved=true end
                    end
                    if not reserved then nextFree=i;break end
                end
            end
            if nextFree then slot=nextFree
            else
                pending[#pending+1]=row
                goto continue
            end
        end
        if valid(actor) and self.physics.isPhysicsActor(actor) and
            self.physics.worldOf(actor)==self.physics.worldOf(pawn) then
            local held=read(read(pawn,"PhysGrabData"),"Target")
            if valid(held) and self.physics.name(held)==self.physics.name(actor) then
                pending[#pending+1]=row
            else
                local ok=self.physics.stow(actor)
                if ok then
                    local entry={
                        slot=slot,actor=actor,identity=row.id,class=row.class,
                        asset=row.asset,originName=row.originName,
                        originalPosition=row.pos,originalRotation=row.rot,
                        grab=row.grab,world=self.physics.worldOf(pawn),
                        state="stored"}
                    self.physics.slots[slot]=entry
                    self.physics:signal()
                    self.log("[PHYS SAVE] reattached world actor to hotbar "..slot)
                else pending[#pending+1]=row end
            end
        else
            -- Do not silently delete missing items. Retain their record for
            -- future streaming/map load. No unsafe blind class spawning:
            -- reconstruction requires more native Blueprint init evidence.
            pending[#pending+1]=row
        end
        ::continue::
    end
    self.unresolved=pending
    return true,#pending==0 and "all_resolved" or ("missing_"..#pending)
end
M.serialize=serialize
M.parse=parse
M.rowFor=rowFor
return M
