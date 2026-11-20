-- Keep extra quickslot items hidden when holstered.
-- Reflected USMAP: HeldenEquipableItem.CurrentInventorySlot (int; 0-based),
-- HolsterState (EHeldenItemHolsterState: None=0, Equipped=1, Holsterd=2).
-- Never touch the item transform, ownership, collision or serialization.
-- Hidden holstered item is restored when equipped or moved out of slot 5-10.
local M={}
local tracked={}
local log=function() end
local function valid(o)
    if o==nil then return false end
    local ok,v=pcall(function() return o:IsValid() end)
    return ok and v==true
end
local function read(o,key)
    if o==nil then return nil end
    local ok,r=pcall(function() return o[key] end)
    if ok then return r end
    return nil
end
local function name(o)
    if not valid(o) then return nil end
    local ok,v=pcall(function() return o:GetFullName() end)
    if ok then return tostring(v) end
    return nil
end
local function hidden(o)
    local b=read(o,"bHidden")
    if type(b)=="boolean" then return b end
    local ok,v=pcall(function() return o:IsHidden() end)
    if ok and type(v)=="boolean" then return v end
    return nil
end
local function setHidden(o,on)
    local ok,err=pcall(function() o:SetActorHiddenInGame(on) end)
    if not ok then return false,tostring(err) end
    local b=hidden(o)
    if b~=nil and b~=on then return false,"readback_mismatch" end
    return true
end
local function num(e)
    if type(e)=="number" then return e end
    local n=tonumber(e)
    if n~=nil then return n end
    local ok,s=pcall(function() return e:ToString() end)
    if not ok then s=tostring(e) end
    if s:find("Holsterd",1,true) then return 2 end
    if s:find("Equipped",1,true) then return 1 end
    if s:find("None",1,true) then return 0 end
    return nil
end
local function release(entry)
    if not entry then return end
    if entry.changed and valid(entry.actor) then
        -- Do not show something hidden by the game prior to our intervention.
        setHidden(entry.actor,entry.original == true)
    end
end
function M.setLogger(fn)
    log=fn or log
end
function M.reset()
    for k,entry in pairs(tracked) do
        release(entry)
        tracked[k]=nil
    end
end
function M.sync(pawn)
    if not valid(pawn) then return false,"pawn_invalid" end
    local arr=read(pawn,"EquipedItems")
    local ok,n=pcall(function() return #arr end)
    if not ok or type(n)~="number" then return false,"equipment_unavailable" end
    local seen={}
    local changed=0
    for i=1,math.min(n,24) do
        local item
        pcall(function() item=arr[i] end)
        if valid(item) then
            local idx=num(read(item,"CurrentInventorySlot"))
            local state=num(read(item,"HolsterState"))
            local key=name(item)
            if key and idx and idx>=4 and idx<=9 then
                seen[key]=true
                local entry=tracked[key]
                -- Do not hide an actively equipped item in player's hands.
                -- Unknown states are left untouched to avoid invisibility bugs.
                if state==2 then
                    if not entry then
                        local before=hidden(item)
                        entry={actor=item,original=before,changed=false}
                        tracked[key]=entry
                    end
                    entry.actor=item
                    -- If game resets visibility when re-holstering, reapply.
                    if hidden(item)~=true then
                        local applied,reason=setHidden(item,true)
                        if applied then
                            entry.changed=true
                            changed=changed+1
                            log("[VISUAL] hidden holstered extra slot "..(idx+1).." item="..key)
                        else
                            log("[VISUAL] failed to hide slot "..(idx+1)..": "..tostring(reason))
                        end
                    end
                elseif entry then
                    release(entry)
                    tracked[key]=nil
                    if state==1 then
                        changed=changed+1
                        log("[VISUAL] revealed equipped extra slot "..(idx+1).." item="..key)
                    end
                end
            elseif key and tracked[key] then
                release(tracked[key])
                tracked[key]=nil
            end
        end
    end
    -- Dropped/moved/unloaded items must not remain hidden by the mod.
    for key,entry in pairs(tracked) do
        if not seen[key] then release(entry);tracked[key]=nil end
    end
    return true,changed
end
return M
