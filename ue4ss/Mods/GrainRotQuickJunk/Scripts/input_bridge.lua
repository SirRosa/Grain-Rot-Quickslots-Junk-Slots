-- Learns numeric native inventory actions by observing the game's own
-- slots 1, 2 and 3; never invents InventoryAction_Server parameter types.
-- Nothing is dispatched before three consistent baseline samples.
local M={}
local capture={sample={},expected=nil,controller=nil,index=nil,offset=nil,n=nil,
    args=nil,ready=false,logger=function() end}
local function log(s) capture.logger("[INPUT] "..s) end
function M.setLogger(l) capture.logger=l end
function M.mark(slot)
    if slot>=1 and slot<=4 then capture.expected=slot end
end
local function unwrap(a)
    if a==nil then return nil end
    local ok,v=pcall(function() return a:get() end)
    if ok then return v end
    return a
end
local function path(o)
    if o==nil then return nil end
    local ok,p=pcall(function() return o:GetFullName() end)
    return ok and tostring(p) or nil
end
local function validArgs(args,n)
    if n<1 or n>5 then return false end
    for i=1,n do
        if type(args[i])~="number" and type(args[i])~="boolean" then return false end
    end
    return true
end
local function tryCalibrate()
    local a,b,c=capture.sample[1],capture.sample[2],capture.sample[3]
    if not a or not b or not c or a.n~=b.n or b.n~=c.n then return end
    local candidates={}
    for i=1,a.n do
        local x,y,z=a.args[i],b.args[i],c.args[i]
        if type(x)=="number" and type(y)=="number" and type(z)=="number"
            and y-x==1 and z-y==1 and (x==0 or x==1) then
            local othersEqual=true
            for j=1,a.n do
                if j~=i and (a.args[j]~=b.args[j] or b.args[j]~=c.args[j]) then
                    othersEqual=false
                    break
                end
            end
            if othersEqual then candidates[#candidates+1]=i end
        end
    end
    if #candidates~=1 then
        log("baseline samples ambiguous, no native 5-0 dispatch")
        return
    end
    capture.index=candidates[1]
    capture.offset=a.args[capture.index]
    capture.args=a.args
    capture.n=a.n
    capture.ready=true
    capture.controller=a.controller
    log("CALIBRATED InventoryAction_Server slot parameter #"..
        capture.index.." baseline="..capture.offset..
        ", args="..capture.n.." (requires actual native 10-slot capacity)")
end
function M.observe(context,...)
    local expected=capture.expected
    if not expected or capture.ready then return end
    capture.expected=nil
    local controller=unwrap(context)
    local controllerKey=path(controller)
    if not controllerKey then return end
    local n=select("#",...)
    local args={}
    for i=1,n do args[i]=unwrap(select(i,...)) end
    if not validArgs(args,n) then
        log("native InventoryAction_Server has non-scalar arguments; auto-dispatch disabled")
        return
    end
    local old=capture.sample[expected]
    if old and old.controller~=controllerKey then
        capture.sample={} -- do not mix different players' actions.
    end
    capture.sample[expected]={args=args,n=n,controller=controllerKey}
    log("observed native slot "..expected.." with "..n.." scalar RPC args")
    tryCalibrate()
end
function M.activate(pc,slot)
    if not capture.ready then return false,"calibration_needed_press_1_2_3" end
    if not pc or path(pc)~=capture.controller then return false,"different_controller" end
    if slot<5 or slot>10 then return false,"out_of_range" end
    local args={}
    for i=1,capture.n do args[i]=capture.args[i] end
    args[capture.index]=capture.offset+slot-1
    local ok,err=pcall(function()
        pc:InventoryAction_Server(table.unpack(args,1,capture.n))
    end)
    if not ok then return false,"native_rpc_failed_"..tostring(err) end
    return true,"calibrated_server_action_dispatched"
end
function M.ready() return capture.ready end
function M.reset()
    capture.sample={}
    capture.expected=nil
    capture.controller=nil
    capture.index=nil
    capture.offset=nil
    capture.n=nil
    capture.args=nil
    capture.ready=false
end
return M
