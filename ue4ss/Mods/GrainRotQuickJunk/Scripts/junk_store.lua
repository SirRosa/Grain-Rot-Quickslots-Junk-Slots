-- Pure Lua transactional backing store for the future native inventory bridge.
-- This module NEVER moves Unreal actors. A caller must perform a native
-- ownership/persistence operation and independently verify its outcome.
local M={}
M.__index=M
function M.new(capacity)
    assert(type(capacity)=="number" and capacity>=1 and capacity<=10)
    return setmetatable({capacity=capacity,selected=1,slots={},pending=nil},M)
end
function M:count()
    local n=0
    for i=1,self.capacity do if self.slots[i]~=nil then n=n+1 end end
    return n
end
function M:select(index)
    if type(index)~="number" or index%1~=0 or index<1 or index>self.capacity
    then return false,"out_of_range" end
    self.selected=index
    return true,index
end
function M:cycle(delta)
    if delta~=1 and delta~=-1 then return false,"invalid_delta" end
    return self:select((self.selected-1+delta+self.capacity)%self.capacity+1)
end
function M:find(identity)
    for i=1,self.capacity do
        local entry=self.slots[i]
        if entry and entry.identity==identity then return i,entry end
    end
    return nil
end
function M:beginStore(identity,actor)
    if self.pending then return nil,"busy" end
    if type(identity)~="string" or identity=="" or actor==nil then
        return nil,"invalid_item"
    end
    if self:find(identity) then return nil,"duplicate" end
    local slot
    for i=1,self.capacity do
        if not self.slots[i] then slot=i;break end
    end
    if not slot then return nil,"full" end
    local tx={op="store",slot=slot,identity=identity,actor=actor}
    self.pending=tx
    return tx,nil
end
function M:beginWithdraw(slot)
    if self.pending then return nil,"busy" end
    slot=slot or self.selected
    if type(slot)~="number" or slot%1~=0 or slot<1 or slot>self.capacity
    then return nil,"out_of_range" end
    local item=self.slots[slot]
    if not item then return nil,"empty" end
    local tx={op="withdraw",slot=slot,identity=item.identity,actor=item.actor}
    self.pending=tx
    return tx,nil
end
function M:cancel(tx)
    if tx~=self.pending then return false,"stale" end
    self.pending=nil
    return true,nil
end
function M:confirm(tx,verified)
    if tx~=self.pending or tx==nil then return false,"stale" end
    -- No mutation may be committed based solely on a successful pcall.
    if verified~=true then self.pending=nil;return false,"unverified" end
    if tx.op=="store" then
        if self.slots[tx.slot] or self:find(tx.identity) then
            self.pending=nil;return false,"conflict"
        end
        self.slots[tx.slot]={identity=tx.identity,actor=tx.actor}
    elseif tx.op=="withdraw" then
        local item=self.slots[tx.slot]
        if not item or item.identity~=tx.identity or item.actor~=tx.actor then
            self.pending=nil;return false,"conflict"
        end
        self.slots[tx.slot]=nil
    else
        self.pending=nil
        return false,"invalid_op"
    end
    self.pending=nil
    return true,nil
end
return M
