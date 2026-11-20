package.path="ue4ss/Mods/GrainRotQuickJunk/Scripts/?.lua;"..package.path
local bridge=require("input_bridge")
local log={}
bridge.setLogger(function(msg) log[#log+1]=msg end)
local pc={}
function pc:GetFullName() return "HeldenPlayerController /Game/PC" end
function pc:InventoryAction_Server(mode,idx)
    self.called=(self.called or 0)+1
    self.mode,self.index=mode,idx
end
assert(not bridge.activate(pc,5),"must not dispatch before calibration")
local remote={get=function() return pc end}
local function value(v)
    return {get=function() return v end}
end
for slot=1,3 do
    bridge.mark(slot)
    bridge.observe(remote,value(true),value(slot-1))
end
assert(bridge.ready(),"baseline 1,2,3 should calibrate 0-based slot param")
assert(bridge.activate(pc,10))
assert(pc.called==1 and pc.mode==true and pc.index==9)
bridge.reset()
assert(not bridge.activate(pc,5),"travel must invalidate replay args")
bridge.mark(1)
bridge.observe(remote,value({nested="struct"}))
assert(not bridge.ready(),"non scalar UFunction inputs are unsupported")
io.write("PASS: native action replay learned from three samples, preserves flags, reset and fail-closed\n")
