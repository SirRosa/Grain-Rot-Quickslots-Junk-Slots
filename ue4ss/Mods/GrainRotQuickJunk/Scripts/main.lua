-- Grain Rot Quickslots & Junk Slots, v0.2.4-visibility-perf.
-- UE4SS 3.x, Helden UE 5.7. Source-driven research build.
-- EXPERIMENTAL: host-only actor storage mutates physics/visibility and native
-- slot creation may be incompatible with current game saves. Back up saves.
-- No actor is destroyed or cloned by this mod. Save/travel unverified.
local CFG = {
    ElevatorRefill = true,
    PollMillis = 500,
    LogInventoryProbes = false, -- opt-in: FindAllOf UI dumps can stall game thread
    LogInputHookOnce = false, -- no per-action tracing in release
    MaxProbeEvents = 0,
}
local TAG = "[GrainRotQuickJunk] "
local function log(msg) print(TAG .. tostring(msg) .. "\n") end
local function valid(o)
    if o == nil then return false end
    local ok,yes=pcall(function() return o:IsValid() end)
    return ok and yes == true
end
local function get(o,k)
    if o == nil then return nil end
    local ok,v=pcall(function() return o[k] end)
    if ok then return v end
    return nil
end
local function number(x)
    local n=tonumber(x)
    if n and n==n and n>-1e9 and n<1e9 then return n end
    return nil
end
local function full(o)
    if not valid(o) then return "?" end
    local ok,v=pcall(function() return o:GetFullName() end)
    if ok and v then return tostring(v) end
    return "?"
end
local function all(class)
    if type(FindAllOf)~="function" then return {} end
    local ok,v=pcall(FindAllOf,class)
    if ok and type(v)=="table" then return v end
    return {}
end
local function isA(o,class)
    if not valid(o) then return false end
    local ok,yes=pcall(function() return o:IsA("/Script/Helden."..class) end)
    if ok and yes==true then return true end
    local c
    pcall(function() c=o:GetClass() end)
    for _=1,10 do
        if not valid(c) then break end
        if full(c):find(class,1,true) then return true end
        local parent
        pcall(function() parent=c:GetSuperStruct() end)
        c=parent
    end
    return false
end
local function worldOf(o)
    if not valid(o) then return nil end
    local w
    pcall(function() w=o:GetWorld() end)
    if valid(w) then return full(w) end
    return nil
end
local function unique(items, obj)
    if not valid(obj) then return end
    items[full(obj)] = obj
end
local function equippedGuns(pawn)
    local found = {}
    local arr=get(pawn,"EquipedItems")
    local n=0
    pcall(function() n=math.min(#arr,64) end)
    for i=1,n do
        local obj
        pcall(function() obj=arr[i] end)
        if isA(obj,"HeldenRangedWeapon") then unique(found,obj) end
    end
    -- A ranged weapon may have a native slot but not appear in EquipedItems.
    -- PreviousOwner alone is insufficient: it also remains on dropped items.
    local ownerPath=full(pawn)
    for _,item in ipairs(all("HeldenRangedWeapon")) do
        if valid(item) and full(get(item,"PreviousOwner"))==ownerPath
            and valid(get(item,"CurrentSlot")) then
            unique(found,item)
        end
    end
    return found
end
local function refillGun(gun)
    local max=number(get(gun,"ItemDurabilityMax"))
    local cur=number(get(gun,"ItemDurability"))
    if not max or max<=0 or not cur or cur<0 then return false end
    if cur>=max then return false end
    local ok,err=pcall(function() gun.ItemDurability=max end)
    if not ok then log("REFILL failed "..full(gun)..": "..tostring(err));return false end
    local readback=number(get(gun,"ItemDurability"))
    if readback and math.abs(readback-max)<0.01 then
        log(string.format("REFILL %.1f -> %.1f %s",cur,max,full(gun)))
        return true
    end
    log("REFILL unconfirmed (readback mismatch): "..full(gun))
    return false
end
local session={inside={},world=nil,probedWorld=nil,junkIndex=1,probEvents=0,
    overlapError=false, cachedContexts=nil, cachedElevators={},
    quickUiReady={}, hudReady=false}
local hasStore,storeModule=pcall(require,"junk_store")
if hasStore and type(storeModule)=="table" and type(storeModule.new)=="function" then
    session.bank=storeModule.new(10)
else
    log("ERROR: Junk transaction module failed to load: "..tostring(storeModule))
end
local hasActors,actorsModule=pcall(require,"actor_storage")
if hasActors and session.bank and type(actorsModule)=="table" then
    session.storage=actorsModule.new(session.bank,log)
else
    log("ERROR: actor storage unavailable: "..tostring(actorsModule))
end
local hasNative,nativeModule=pcall(require,"native_slots")
if hasNative and type(nativeModule)=="table" then
    session.native=nativeModule
    session.native.setLogger(log)
    session.nativeAttempts={}
else
    log("ERROR: native inventory extension unavailable: "..tostring(nativeModule))
end
local hasHud,hudModule=pcall(require,"junk_hud")
if hasHud and type(hudModule)=="table" then
    session.hud=hudModule
else
    log("ERROR: game-native Junk HUD unavailable: "..tostring(hudModule))
end
local hasInput,inputModule=pcall(require,"input_bridge")
if hasInput and type(inputModule)=="table" then
    session.input=inputModule
    session.input.setLogger(log)
else
    log("ERROR: native inventory input calibration unavailable: "..tostring(inputModule))
end
local hasQuickUI,quickUIModule=pcall(require,"quickbar_ui")
if hasQuickUI and type(quickUIModule)=="table" then
    session.quickUI=quickUIModule
else
    log("ERROR: native quickbar UI module unavailable: "..tostring(quickUIModule))
end
local hasContext,contextModule=pcall(require,"player_context")
if hasContext and type(contextModule)=="table" then
    session.context=contextModule
else
    log("ERROR: player context resolver unavailable: "..tostring(contextModule))
end
local hasVisibility,visibilityModule=pcall(require,"extra_item_visibility")
if hasVisibility and type(visibilityModule)=="table" then
    session.visibility=visibilityModule
    session.visibility.setLogger(log)
else
    log("ERROR: extra-slot visibility module unavailable: "..tostring(visibilityModule))
end
-- Game's native load/respawn resolves ItemSaveData.OwningSlot by name.
-- Configure the player Blueprint CDO *before* the game creates the pawn.
-- Do not wait until the normal inventory poll, which runs after deserialization.
session.defaultsReady=false
local function ensureDefaultSlots(reason)
    if session.defaultsReady or not session.native or
        type(session.native.extendDefaults)~="function" then return end
    local ok,why=session.native.extendDefaults()
    if ok then
        session.defaultsReady=true
        log("PRESPAWN CDO ready: "..tostring(why).." source="..tostring(reason))
    elseif session.defaultStatus~=why then
        session.defaultStatus=why
        log("PRESPAWN CDO pending: "..tostring(why).." source="..tostring(reason))
    end
end
ensureDefaultSlots("mod_initialization")
if type(RegisterHook)=="function" then
    -- Executed before native save loading / character respawn. Does not
    -- override parameters or return values of either function.
    for _,spec in ipairs({
       {path="/Script/Helden.HeldenGameInstance:LoadGame",tag="LoadGame"},
       {path="/Script/Helden.HeldenGameInstance:LoadLastSaveGame",tag="LoadLastSaveGame"},
       {path="/Script/Helden.HeldenPlayerController:RespawnCharacter_Server",tag="Respawn"}
    }) do
        local ok,err=pcall(function()
            RegisterHook(spec.path,function()
                ensureDefaultSlots(spec.tag)
            end)
        end)
        if not ok then log("PRESPAWN hook unavailable: "..spec.tag.." "..tostring(err)) end
    end
end

session.pollCount=0
local function hostFor(world)
    if session.context then
        local ctx=session.context.pickLocal()
        if ctx and ctx.world==world and ctx.auth then return ctx.pc end
        return nil
    end
    -- Only for older mock environments without the new context module.
    for _,class in ipairs({"HeldenGameMode","GameModeBase"}) do
        for _,gm in ipairs(all(class)) do
            if valid(gm) and not full(gm):find("Default__",1,true)
                and worldOf(gm)==world then return gm end
        end
    end
    return nil
end
local function inElevator(pawn,elevators,world)
    for _,lift in ipairs(elevators) do
        if valid(lift) and worldOf(lift)==world then
            local box=get(lift,"InteriorCollisionBox")
            if valid(box) then
                local ok,inside=pcall(function() return box:IsOverlappingActor(pawn) end)
                if ok and inside==true then return true end
                if not ok and not session.overlapError then
                    session.overlapError=true
                    log("InteriorCollisionBox overlap API unavailable; refill is fail-closed")
                end
            end
        end
    end
    return false
end
local function probeInventory(pawn)
    local slots=get(pawn,"ItemSlots")
    local settings=get(get(pawn,"InventorySettings"),"SlotSettings")
    local n,m=-1,-1
    pcall(function() n=#slots end)
    pcall(function() m=#settings end)
    local grab=get(get(pawn,"PhysGrabData"),"Target")
    log(string.format("PROBE native inventory slots=%d settings=%d grabbed=%s",
        n,m,full(grab)))
    local widget
    for _,ui in ipairs(all("HeldenInventoryWidget")) do
        if valid(ui) then widget=ui;break end
    end
    if widget then
        local w=-1
        pcall(function() w=#get(widget,"SlotWidgets") end)
        log("PROBE InventoryWidget.SlotWidgets="..w..
            " / SlotWidgetClass="..full(get(widget,"SlotWidgetClass")))
    end
end
local function poll()
    session.pollCount=session.pollCount+1
    -- Tick every 500 ms for pending RMB release and visual changes.
    -- Heavy object discovery and elevator scans occur only every 2 s.
    local deepPoll=(session.pollCount==1 or session.pollCount%4==0)
    local needDiscovery=deepPoll or session.cachedContexts==nil
    if not needDiscovery and session.cachedContexts then
        for _,ctx in ipairs(session.cachedContexts) do
            if not valid(ctx.pawn) or
                (ctx.world and worldOf(ctx.pawn)~=ctx.world) then
                needDiscovery=true
                break
            end
        end
    end
    if needDiscovery then
        session.cachedContexts=session.context and session.context.resolveAll()
            or all("HeldenPlayerController")
    end
    if deepPoll then
        session.cachedElevators=all("HeldenDungeonElevator")
    end
    if CFG.LogInventoryProbes and session.context and deepPoll then
        log("DIAG "..session.context.diagnostic())
    end
    if not session.defaultsReady and deepPoll then
        ensureDefaultSlots("poll_retry")
    end
    local pcs=session.cachedContexts or {}
    local elevators=session.cachedElevators or {}
    for _,record in ipairs(pcs) do
        local pc=record.pc or record
        if valid(pc) and not full(pc):find("Default__",1,true) then
            local pawn=record.pawn
            if not pawn then pcall(function() pawn=pc:GetPawn() end) end
            if valid(pawn) and (session.context or isA(pawn,"HeldenCharacter")) then
                local world=record.world or worldOf(pawn)
                if world then
                    if session.world~=world then
                        if session.bank and session.bank:count()>0 then
                            log("WARNING: world changed with "..session.bank:count()..
                                " junk actors; check save/old actors before continuing")
                        end
                        session.world=world
                        session.inside={}
                        session.probedWorld=nil
                        session.overlapError=false
                        session.nativeAttempts={}
                        session.quickUiReady={}
                        session.hudReady=false
                        if session.visibility then session.visibility.reset() end
                        if session.hud then session.hud.reset() end
                        if session.quickUI then session.quickUI.reset() end
                        session.quickUiStatus={}
                        if session.input then session.input.reset() end
                    end
                    local isLocal=(record.pc and record.isLocal) or false
                    if not record.pc then
                        pcall(function() isLocal=pc:IsLocalController()==true end)
                    end
                    if session.hud and isLocal and not session.hudReady and deepPoll then
                        local shown,why=session.hud.ensure(pc,log)
                        session.hudReady=shown==true
                        if shown and session.bank then
                            session.hud.update(session.bank.selected)
                        end
                        if not shown and why=="max_attempts" and not session.hudWarned then
                            session.hudWarned=true
                            log("JUNK HUD failed to construct; native widget path unavailable")
                        end
                    end
                    if CFG.LogInventoryProbes and session.probedWorld~=world then
                        session.probedWorld=world
                        probeInventory(pawn)
                    end
                    -- Purely visual hiding for items 5-10; run locally even
                    -- on clients, without touching native inventory data.
                    if session.visibility and isLocal and session.pollCount%2==0 then
                        session.visibility.sync(pawn)
                    end
                    -- Do not mutate client inventory. GameMode exists only on server.
                    -- Context carries host authority from the current scan.
                    -- Do NOT resolve all controllers/GameModes again on a client.
                    local host=(record.pc and record.auth and record.pc)
                        or (not session.context and hostFor(world) or nil)
                    if host then
                        local key=full(pawn)
                        -- Store only AFTER Grain Rot itself releases RMB.
                        -- Never call ReleaseComponent, clear PhysGrabData.Target,
                        -- or attach a grabbed actor (native Fatal Error on v0.2.1).
                        if session.storage and session.storage.pending then
                            local done,result=session.storage:tick(pawn)
                            if done or (result~="awaiting_rmb_release" and
                                    result~="confirming_release" and result~="idle") then
                                log("JUNK pending completion="..tostring(done)..
                                    " result="..tostring(result))
                            end
                        end
                        -- One bounded attempt per real player to create six native
                        -- slots; don't keep appending to actor arrays every frame.
                        if session.native then
                            local tries=session.nativeAttempts[key] or 0
                            if tries<4 then
                                local extended,reason=session.native.extend(pawn)
                                if tries==0 or tries==3 then
                                    log("NATIVE slot attempt="..(tries+1)..
                                        " success="..tostring(extended)..
                                        " result="..tostring(reason).." player="..key)
                                end
                                if tries==3 and reason=="native_slots_not_created" then
                                    local done,msg=session.native.rebuildMissing(pawn)
                                    log("NATIVE slot component rebuild="..tostring(done)..": "..tostring(msg))
                                end
                                session.nativeAttempts[key]=tries+1
                            end
                        end
                        -- Only render the 6 additional native UI widgets after
                        -- the real reflected ItemSlots array contains 10 entries.
                        if session.quickUI and isLocal and deepPoll and
                            (not session.quickUiReady[key] or session.pollCount%20==0) then
                            -- Initial creation retries at most every 2 seconds.
                            -- Healthy HUD is validated/relabeled every 10 s,
                            -- not 6 widget reads every game-thread tick.
                            local slotArray=get(pawn,"ItemSlots")
                            local n=0
                            pcall(function() n=#slotArray end)
                            if n>=10 then
                                local ready,result=session.quickUI.ensure(pc,pawn,log)
                                session.quickUiReady[key]=ready==true
                                if session.quickUiStatus==nil then session.quickUiStatus={} end
                                if session.quickUiStatus[key]~=result then
                                    log("QUICK UI ready="..tostring(ready)..
                                        " result="..tostring(result))
                                    session.quickUiStatus[key]=result
                                end
                            end
                        end
                        if session.storage and session.bank and session.bank:count()>0 then
                            local state=get(pawn,"CharacterState")
                            if tonumber(state)==1 or tostring(state):find("Dead",1,true) then
                                session.storage:recoverAll(pawn,"player_death")
                            end
                        end
                        if deepPoll then
                            local inside=inElevator(pawn,elevators,world)
                            if inside and session.inside[key]~=true then
                                session.inside[key]=true
                                if CFG.ElevatorRefill then
                                    local count=0
                                    for _,gun in pairs(equippedGuns(pawn)) do
                                        if refillGun(gun) then count=count+1 end
                                    end
                                    log("elevator ENTRY: refilled weapons="..count.." player="..key)
                                end
                            elseif not inside then
                                session.inside[key]=false
                            end
                        end
                    end
                end
            end
        end
    end
end
local function localPawn()
    if session.context then
        local e=session.context.pickLocal()
        return e and e.pawn or nil
    end
    for _,pc in ipairs(all("HeldenPlayerController")) do
        local pawn
        pcall(function() pawn=pc:GetPawn() end)
        if valid(pawn) and isA(pawn,"HeldenCharacter") then return pawn end
    end
    return nil
end
-- Gameplay GetPawn() is NIL for the live BP_HeldenPlayerCharacter_01_C
-- in UE4SS(6).log. The player controller owns LastPlayerChar instead.
-- Always resolve the *local* controller and its selected player together.
local function localQuickController()
    if session.context then
        local ctx=session.context.pickLocal()
        if ctx and valid(ctx.pc) and valid(ctx.pawn) and ctx.isLocal then
            return ctx.pc,ctx.pawn,ctx.source
        end
    end
    -- Fallback for older versions without the player_context helper.
    for _,pc in ipairs(all("HeldenPlayerController")) do
        if valid(pc) and not full(pc):find("Default__",1,true) then
            local localOk=false
            pcall(function() localOk=pc:IsLocalController()==true end)
            if localOk then
                local candidate
                pcall(function() candidate=pc:GetPawn() end)
                if not valid(candidate) then candidate=get(pc,"LastPlayerChar") end
                if valid(candidate) and get(candidate,"ItemSlots")~=nil then
                    return pc,candidate,"native_pc_fallback"
                end
            end
        end
    end
    return nil,nil,"local_controller_not_found"
end

local function onInput(action,source)
    if action=="junk_prev" then
        if session.bank then
            session.bank:cycle(-1)
            session.junkIndex=session.bank.selected
        else
            session.junkIndex=(session.junkIndex+8)%10+1
        end
        if session.hud then session.hud.update(session.junkIndex) end
        log("JUNK selected "..session.junkIndex.."/10")
    elseif action=="junk_next" then
        if session.bank then
            session.bank:cycle(1)
            session.junkIndex=session.bank.selected
        else
            session.junkIndex=session.junkIndex%10+1
        end
        if session.hud then session.hud.update(session.junkIndex) end
        log("JUNK selected "..session.junkIndex.."/10")
    elseif action=="junk_put" then
        local pawn=localPawn()
        local grabbed=pawn and get(get(pawn,"PhysGrabData"),"Target")
        local world=pawn and worldOf(pawn)
        if not pawn or not world or not hostFor(world) then
            log("JUNK "..source.." ERROR: authoritative pawn unavailable; "..
                (session.context and session.context.diagnostic() or "legacy resolver"))
        elseif not session.storage then
            log("JUNK "..source.." ERROR: storage module missing")
        else
            local success,result=session.storage:store(pawn,grabbed)
            log("JUNK "..source.." store="..tostring(success)..
                " result="..tostring(result))
        end
    elseif action=="junk_take" then
        local pawn=localPawn()
        local world=pawn and worldOf(pawn)
        if not pawn or not world or not hostFor(world) then
            log("JUNK "..source.." ERROR: authoritative pawn unavailable; "..
                (session.context and session.context.diagnostic() or "legacy resolver"))
        elseif not session.storage then
            log("JUNK "..source.." ERROR: storage module missing")
        else
            local success,result=session.storage:retrieve(pawn)
            log("JUNK "..source.." retrieve="..tostring(success)..
                " result="..tostring(result))
        end
    elseif action:find("learn_",1,true)==1 then
        if session.input then session.input.mark(tonumber(action:sub(7))) end
    elseif action:find("quick_",1,true)==1 then
        local slot=tonumber(action:sub(7))
        local pc,pawn,sourceName=localQuickController()
        if not pc or not pawn then
            log("QUICK "..tostring(slot).." ERROR: "..tostring(sourceName)..
                "; key="..tostring(source))
        elseif not session.native then
            log("QUICK "..tostring(slot).." ERROR: native inventory bridge missing")
        else
            local success,why=session.native.select(pc,pawn,slot)
            -- The game method accepts exactly one IntProperty InIdx.
            -- Never swallow an unresolved controller or claim a slot switched
            -- merely because RegisterKeyBind returned true.
            log("QUICK "..tostring(slot).." controller="..full(pc)..
                " pawn="..full(pawn).." source="..tostring(sourceName)..
                " dispatched="..tostring(success).." reason="..tostring(why))
        end
    end
end
local function queueInput(action,source)
    if type(ExecuteInGameThread)=="function" then
        ExecuteInGameThread(function()
            local ok,err=pcall(onInput,action,source)
            if not ok then log("input failed: "..tostring(err)) end
        end)
    else
        log("input ignored: ExecuteInGameThread unavailable")
    end
end
local function bind(keyName,action,requiresShift)
    local k=type(Key)=="table" and Key[keyName] or nil
    if k==nil or type(RegisterKeyBind)~="function" then
        log("BIND unavailable: "..keyName)
        return
    end
    local ok,err=pcall(function()
        if requiresShift then
            if not ModifierKey or not ModifierKey.SHIFT then
                error("UE4SS modifier SHIFT unavailable")
            end
            RegisterKeyBind(k,{ModifierKey.SHIFT},function() queueInput(action,keyName) end)
        else
            RegisterKeyBind(k,function() queueInput(action,keyName) end)
        end
    end)
    if ok then log("BIND "..keyName.." => "..action)
    else log("BIND error "..keyName..": "..tostring(err)) end
end
bind("XBUTTON_ONE","junk_put")
bind("XBUTTON_TWO","junk_take")
bind("G","junk_put")
bind("H","junk_take")
bind("OEM_COMMA","junk_prev",true)
bind("OEM_PERIOD","junk_next",true)
for n,keyName in ipairs({"ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT","NINE","ZERO"}) do
    -- The exact game ObjectDump verifies InventoryAction_Server(InIdx:int).
    -- Keys 1-4 are owned solely by the game; never intercept or double-bind.
    if n>=5 then bind(keyName,"quick_"..n) end
end
-- Read-only prehook: collect actual signature of key native inventory action.
local function probeHook(path,label)
    if type(RegisterHook)~="function" then return end
    local ok,err=pcall(function()
        RegisterHook(path,function(context,...)
            if label=="InventoryAction_Server" and session.input then
                session.input.observe(context,...)
            end
            if session.probEvents>=CFG.MaxProbeEvents then return end
            session.probEvents=session.probEvents+1
            local args={...}
            local info={}
            for i=1,math.min(#args,8) do
                local a=args[i]
                local okv,value=pcall(function() return a:get() end)
                info[i]=tostring(okv and value or a)
            end
            log("HOOK "..label.." args="..#args.." ["..table.concat(info," | ").."]")
        end)
    end)
    if ok then log("HOOK registered: "..label)
    else log("HOOK unavailable "..label..": "..tostring(err)) end
end
if CFG.LogInputHookOnce then
    probeHook("/Script/Helden.HeldenPlayerController:InventoryAction_Server","InventoryAction_Server")
    probeHook("/Script/Helden.HeldenCharacter:GrabObject_Server","GrabObject_Server")
end
local function safePoll()
    local ok,err=pcall(poll)
    if not ok then log("poll failed: "..tostring(err)) end
end
if type(LoopInGameThreadWithDelay)=="function" then
    local ok,err=pcall(function() LoopInGameThreadWithDelay(CFG.PollMillis,safePoll) end)
    if ok then log("poller active: "..CFG.PollMillis.."ms on game thread")
    else log("poller unavailable: "..tostring(err)) end
else
    -- Fallback callback rate is game-dependent: do not claim 500ms here.
    local sample=0
    local ok,err=pcall(function()
        RegisterHook("/Game/Animation/ABP_HeldenPlayer.ABP_HeldenPlayer_C:BlueprintUpdateAnimation",
        function()
            sample=sample+1
            if sample>=120 then sample=0;safePoll() end
        end)
    end)
    if ok then log("fallback sampled animation heartbeat active")
    else log("NO POLLER: "..tostring(err)) end
end
log("v0.2.5-compat-prespawn: configure Blueprint CDO before LoadGame/Respawn, restoring stable native quickslot names.")
