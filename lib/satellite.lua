-- whip satellite helper: include it, don't copy it. In your resource's fxmanifest.lua:
--
--     dependency 'whip_core'
--     shared_script '@whip_core/lib/satellite.lua'
--
-- Then, on either side (server or client), declare what your resource adds in a function:
--
--     Whip.register(function()
--         Whip.core:RegisterItem('lemonade', { name = 'Lemonade', weight = 0.3 })
--         Whip.core:RegisterUseHandler('lemonade', drinkLemonade)
--     end)
--
-- It runs once whip_core is ready, and again every time whip_core restarts (when it has forgotten what you
-- registered). A declaring call that whip_core refuses is printed in your console. It is a file you include, not an
-- export, because the registration list has to live in your resource's Lua state.

Whip = Whip or {}

local CORE = 'whip_core'
local SELF = GetCurrentResourceName()

--- Errors and red prints since this resource started, or since Whip.sayStarted last spoke.
local _startProblems = 0

-- ============================================
-- Your errors, kept by whip_core for tools
-- ============================================
--
-- As whip_core keeps its own (shared/error_tap.lua): an error in your threads, timeouts, event handlers, NUI
-- callbacks, commands and statebag handlers, and a print in red (^1), is printed (or reported by FiveM) as before
-- and also handed to whip_core, which keeps the last few hundred for tools to read (GetErrorLog). A SecureEvent or
-- SecureCallback handler of yours that throws is kept by whip_core under your name. Your export's errors still go
-- to whoever called it, and are not kept.
--
-- To do it, this block replaces Citizen.CreateThread, CreateThreadNow and SetTimeout (CreateThread and SetTimeout
-- too), RegisterCommand, AddStateBagChangeHandler, RegisterNUICallback and print in YOUR resource with versions
-- that do the same and report a failure. FiveM runs every event handler through CreateThreadNow, so each handler
-- call costs one xpcall more (about half a microsecond). A resource that wraps these itself, or wants none of it,
-- turns it off with one line in its fxmanifest:   whip_error_tap 'no'
-- Everything else here (Whip.register, Whip.call...) works the same either way; its errors just are not kept.

-- /whipcost: what this resource is asked to run, by name ('event x', 'call into file[lines]': its event handlers, and
-- the calls other resources make into it, whip_core's included). Set by the /whipcost block at the bottom of this file
-- while it runs, nil the rest of the time (all it costs then is one look at a nil). [label] = { n, kb }.
local costAsked = nil
local costLabel = {}   -- [the runtime's name] = label

local function countAsked(list, fn, name)
    -- /whipcost's own start and stop are its work, not this resource's
    if type(name) == 'string' and name:find('event whip_core:cost:', 1, true) == 1 then return fn end
    local label = costLabel[name or '']
    if not label then
        local s = type(name) == 'string' and name or '(a thread started at once)'
        label = s:match('^event (%S+)') and ('event ' .. s:match('^event (%S+)'))
            or (s:match('^ref call %[(.+)%]$') and ('call into ' .. s:match('^ref call %[(.+)%]$')))
            or s
        costLabel[name or ''] = label
    end
    local e = list[label]
    if not e then
        e = { n = 0, kb = 0.0 }
        list[label] = e
    end
    -- The answers passed straight through (no table to hold them: it would be counted as the handler's)
    local function finish(kb0, ...)
        local made = collectgarbage('count') - kb0
        e.n = e.n + 1
        if made > 0 then e.kb = e.kb + made end
        return ...
    end
    return function(...)
        return finish(collectgarbage('count'), fn(...))
    end
end

if GetResourceMetadata(SELF, 'whip_error_tap', 0) ~= 'no' then
    local nativePrint, traceback = print, debug.traceback
    local function report(kind, text)
        TriggerEvent('whip_core:errorTap:report', SELF, kind, tostring(text))
    end
    local function runCaught(fn, ...)
        local r = table.pack(xpcall(fn, traceback, ...))
        if r[1] then return table.unpack(r, 2, r.n) end
        _startProblems = _startProblems + 1
        report('error', r[2])
        nativePrint(('^1SCRIPT ERROR: %s^7'):format(tostring(r[2])))
    end
    local function guard(fn)
        if type(fn) ~= 'function' then return fn end
        return function(...) return runCaught(fn, ...) end
    end
    -- A thread's catch, named as the function it wraps: FiveM names a thread after the function it was started with
    -- (the profiler, resmon), so one catch round every thread made all of your loops one row named after this file.
    -- Compiled once for each function a thread starts with, as a function of that file over those lines (whip_core's
    -- shared/error_tap.lua does the same).
    local catchFor = {}   -- [source] = { [first line] = function(fn) -> fn caught }
    local function threadGuard(fn)
        if type(fn) ~= 'function' then return fn end
        local info = debug.getinfo(fn, 'S')
        local first, last = info.linedefined, info.lastlinedefined
        if info.what ~= 'Lua' or first < 1 or last < first then return guard(fn) end
        local bySource = catchFor[info.source]
        if not bySource then
            bySource = {}
            catchFor[info.source] = bySource
        end
        local make = bySource[first]
        if make == nil then
            local code = 'local run = ... return function(fn) return ' .. string.rep('\n', first - 1)
                .. 'function(...) return run(fn, ...)' .. string.rep('\n', last - first) .. ' end end'
            local chunk = load(code, info.source, 't')
            make = chunk and chunk(runCaught) or false
            bySource[first] = make
        end
        if not make then return guard(fn) end
        return make(fn)
    end
    local nativeThread, nativeNow, nativeTimeout = Citizen.CreateThread, Citizen.CreateThreadNow, Citizen.SetTimeout
    ---@diagnostic disable-next-line: duplicate-set-field -- wrapped on purpose (this section's top says why)
    Citizen.CreateThread = function(fn) return nativeThread(threadGuard(fn)) end
    ---@diagnostic disable-next-line: duplicate-set-field -- wrapped on purpose (this section's top says why)
    Citizen.CreateThreadNow = function(fn, name)
        local list = costAsked
        if list ~= nil and type(fn) == 'function' then fn = countAsked(list, fn, name) end
        -- Named by the runtime (an event handler, a call into this resource): that name is what shows
        return nativeNow(name ~= nil and guard(fn) or threadGuard(fn), name)
    end
    ---@diagnostic disable-next-line: duplicate-set-field -- wrapped on purpose (this section's top says why)
    Citizen.SetTimeout = function(ms, fn) return nativeTimeout(ms, threadGuard(fn)) end
    CreateThread, SetTimeout = Citizen.CreateThread, Citizen.SetTimeout
    -- The runtime catches these itself: kept, then raised again, so FiveM reports them as before.
    local function rethrow(fn)
        if type(fn) ~= 'function' then return fn end
        return function(...)
            local r = table.pack(xpcall(fn, traceback, ...))
            if r[1] then return table.unpack(r, 2, r.n) end
            report('error', r[2])
            error(r[2], 0)
        end
    end
    local nativeCommand, nativeBagHandler = RegisterCommand, AddStateBagChangeHandler
    RegisterCommand = function(name, fn, restricted) return nativeCommand(name, rethrow(fn), restricted) end
    AddStateBagChangeHandler = function(key, bag, fn) return nativeBagHandler(key, bag, rethrow(fn)) end
    if not IsDuplicityVersion() then
        local nativeNUI, nativeNui = RegisterNUICallback, RegisterNuiCallback
        RegisterNUICallback = function(name, fn) return nativeNUI(name, rethrow(fn)) end
        if nativeNui then RegisterNuiCallback = function(name, fn) return nativeNui(name, rethrow(fn)) end end
    end
    function print(...)
        nativePrint(...)
        local first = ...
        if type(first) == 'string' and first:sub(1, 2) == '^1' then
            _startProblems = _startProblems + 1
            local parts = table.pack(...)
            for i = 1, parts.n do parts[i] = tostring(parts[i]) end
            report('warning', (table.concat(parts, ' ', 1, parts.n):gsub('%^%d', '')))
        end
    end
end

-- ============================================
-- Your page, for tools
-- ============================================
--
-- A resource with a ui_page whose page loads whip_core's js/page-tools.js
--     <script src="https://cfx-nui-whip_core/html/js/page-tools.js"></script>
-- can be read and pressed by its words like whip_core's own (ReadScreen / PressScreen, for tests and the AI link), and
-- its page's errors are kept with the rest (GetErrorLog). Only your own page can be messaged, so the asks and the
-- answers pass through here.
if not IsDuplicityVersion() and GetResourceMetadata(SELF, 'ui_page', 0) then
    AddEventHandler('whip_core:probe:ask', function(token, kind, opts, page)
        -- Only whip_core's own ask (client/screen_probe.lua), which is developer mode only: any client resource could
        -- fire this event and press this page's buttons (audit 20, CLI-3)
        if GetInvokingResource() ~= 'whip_core' then return end
        if page and page ~= SELF then return end
        SendNUIMessage({ action = 'whipProbe', token = token, kind = kind, opts = opts })
    end)
    RegisterNUICallback('whipProbe', function(d, cb)
        cb({})
        if type(d) == 'table' then TriggerEvent('whip_core:probe:answer', SELF, d.token, d.ok == true, d.result, d.err) end
    end)
    RegisterNUICallback('whipErrorTap', function(d, cb)
        cb({})
        if type(d) == 'table' and type(d.text) == 'string' then
            TriggerEvent('whip_core:errorTap:report', SELF .. ' page', 'page', d.text)
        end
    end)
end

local _registerFns = {}
local _lostFns     = {}
local _heard       = false   -- an announcement for us has arrived since whip_core last stopped

--- Is whip_core running and finished starting?
---
--- Answered from what this file heard: whip_core says it is ready (whip_core:onReady, to every resource that starts)
--- and that holds until it stops (onResourceStop, below). Asked of whip_core only before that, as callers ask often
--- (a loop's every pass) and each export call costs both resources a coroutine and a few tables.
---@return boolean
function Whip.isReady()
    if _heard then return true end
    if GetResourceState(CORE) ~= 'started' then return false end
    local ok, ready = pcall(function() return exports[CORE]:IsReady() end)
    return ok and ready == true
end

--- Wait until whip_core is ready. Only from inside a thread (it yields).
---@param timeoutMs number|nil  give up after this long; nil waits for ever
---@return boolean ready  false when it timed out
function Whip.ready(timeoutMs)
    local deadline = timeoutMs and (GetGameTimer() + timeoutMs) or nil
    while not Whip.isReady() do
        if deadline and GetGameTimer() > deadline then return false end
        Wait(100)
    end
    return true
end

--- Calls still waiting on whip_core, answered if it stops first. [promise] = the export's name.
local _waiting = {}

-- The exports that can wait, on each side: dev/waits.js finds them, its --write writes this list and the docs' WAITS
-- list, and its --check keeps both the same as the stubs' ---@async marks. Only these get Whip.call's thread and
-- promise; every other call goes straight through (cheap enough for a loop).
local WAITS = json.decode([[{"server":["AddCatalogItem","AddItem","AdoptVehicle","BankDeposit","BankSystemDeposit","BankSystemTransfer","BankSystemWithdraw","BankTransfer","BankWithdraw","CanGrantBankAccess","CanHirePlayer","CanUseBankAccount","ChangeVehicleLocks","ChargePlayer","ClaimVehicle","ClearAllVehicleData","ClearVehicleData","CloseBankAccount","ClosePanel","ClosePlayerInventory","CloseStore","CommitWithAction","CountVehicleKeys","CreateBankAccount","CreateContainer","CreateDoor","CreateGarage","CreateGroundItem","CreateJobRole","CreateOwnedVehicle","CreateShop","DeleteContainer","DeleteDoor","DeleteGarage","DeleteGroundItem","DeleteJob","DeleteJobRole","DeleteShop","DeleteZone","DespawnVehicle","EnsureContainer","EnsureDoor","EnsureDoors","EnsureJob","EnsureShop","EnsureTable","EnsureZone","FlushActivityLog","GetBalance","GetBankAccessList","GetBankAccount","GetBankTransactions","GetCharacterBankAccounts","GetCharacterNames","GetDefaultBankAccount","GetItemAt","GetJobBankAccounts","GetPermissionHolders","GetPlayerMetadata","GetPlayerVehicleKeys","GetScenarioStats","GetShopPrices","GetShopStock","GiveOnLogin","GivePropertyKey","GiveVehicleKey","GrantBankAccess","GrantPermission","HasVehicleKey","HirePlayer","HoldDoor","HoldMoney","IsCharacterDeleted","LinkDoors","LogActivity","LoreSay","OpenPlayerInventory","OpenStore","PayAsLore","PayPlayer","Progress","RefundPlayer","RegisterPropertyPack","RegisterProps","RegisterVehicles","RemoveCatalogItem","RemoveItem","RemovePropertyKey","RemoveVehicleKey","RequestScreenshot","RevokeBankAccess","RevokePermission","SavePlayer","SetBankAccountFrozen","SetHeldItem","SetItemMetadata","SetPlayerMetadata","SetPropertyOwner","SetPropertyTheme","SetShopItemPrice","SetShopLayout","SetVehicleAppearance","SetVehicleData","SetVehicleGarage","SetVehicleLocked","SetVehiclePlate","SettleMoneyHold","SkillCheck","SpawnTempVehicle","SpawnVehicle","StoreCount","StoreGive","StoreMove","StoreRead","StoreTake","SwitchScenario","TestDirectorCard","TestDirectorScenario","TransferVehicle","UnlinkDoors","UpdateContainer","UpdateDoor","UpdateGarage","UpdateJob","UpdateJobRole","UpdateShop","__AdoptOrCreateDoor","__RegisterDirectorScenario","__ReleaseManagedDoor"],"client":["Alert","Callback","ClockOff","ClockOn","Confirm","EditAppearance","EnterCharacter","FreeHands","GetPlayerFullName","Input","LoadAnimDict","LoadAnimSet","LoadModel","LoadPtfxAsset","LoadTextureDict","OpenKeyboard","OrbitCamera","PlaceObject","PlacePoint","PlayCameraPath","PlayCameraSequence","PressScreen","Progress","ReadScreen","ResolveVehicle","SkillCheck","TakeScreenshot","TakeVehicleControl"]}]])
local WAITS_HERE = {}
for _, n in ipairs(WAITS[IsDuplicityVersion() and 'server' or 'client'] or {}) do WAITS_HERE[n] = true end

--- The coroutines running registrations right now (see Whip.register): [co] = how many passes it is inside. A set,
--- not one saved-and-restored value: two passes can overlap (one waits on a slow export while another starts), and
--- the first to end must not hide the other's refusals.
local _passes = {}

--- Is this coroutine inside a registration pass?
local function inPass()
    local co = coroutine.running()
    return co ~= nil and _passes[co] ~= nil
end

--- One call into whip_core: Whip.call without its refusal line.
---@param name string  the export's name
---@return any ...
local function callCore(name, ...)
    if GetResourceState(CORE) ~= 'started' then
        return false, 'whip_core is not running'
    end

    -- Called where nothing can wait (file scope, a sort callback): run in line as a plain export call.
    -- An export that waits then shows up as an "attempt to yield" error (FiveM's export __call awaits
    -- whenever coroutine.running() is truthy, which in Lua 5.4 it always is). The export is already
    -- running in whip_core's own thread and finishes there, so the caller is told it STARTED.
    if not coroutine.isyieldable() then
        local packed = table.pack(pcall(function(...)
            return exports[CORE][name](exports[CORE], ...)
        end, ...))
        if not packed[1] then
            if tostring(packed[2]):find('attempt to yield', 1, true) then
                return false, ('whip_core:%s waits, so its answer cannot reach you here — it STARTED and will finish; call it from a thread or a handler to get the answer'):format(tostring(name))
            end
            return false, ('whip_core:%s failed: %s'):format(tostring(name), tostring(packed[2]))
        end
        return table.unpack(packed, 2, packed.n)
    end

    -- An export that cannot wait (most of them): straight through, no thread and no promise.
    if not WAITS_HERE[name] then
        -- The lookup inside the pcall too: FiveM raises "No such export" for a name whip_core does not have (one
        -- renamed, or a typo), and that must answer false like any failure rather than throw out of a Whip.register.
        local packed = table.pack(pcall(function(...) return exports[CORE][name](exports[CORE], ...) end, ...))
        if not packed[1] then
            return false, ('whip_core:%s failed: %s'):format(tostring(name), tostring(packed[2]))
        end
        return table.unpack(packed, 2, packed.n)
    end

    local args = table.pack(...)
    local p = promise.new()
    -- Run in a thread of its own so this one can stop waiting for it. An export that does not wait
    -- finishes before CreateThreadNow returns, so nothing here waits either.
    Citizen.CreateThreadNow(function()
        p:resolve(table.pack(pcall(function()
            return exports[CORE][name](exports[CORE], table.unpack(args, 1, args.n))
        end)))
    end)
    local packed
    if p.state == 0 then
        _waiting[p] = name
        packed = Citizen.Await(p)
        _waiting[p] = nil
    else
        packed = p.value
    end
    if not packed[1] then
        return false, ('whip_core:%s failed: %s'):format(tostring(name), tostring(packed[2]))
    end
    return table.unpack(packed, 2, packed.n)
end

--- Does `name` declare something (what a Whip.register function is for)? Its refusal there is printed.
---@param name string
---@return boolean
local function declares(name)
    return name:find('^Register') ~= nil or name:find('^Ensure') ~= nil or name:find('^Add') ~= nil
        or name:find('^On%u') ~= nil or name:find('^Watch') ~= nil
        or name == 'SecureEvent' or name == 'SecureCallback'
end

--- Print a refusal (`false, why`) in this console, naming the export, and pass every answer on. A start problem
--- (Whip.startProblem): red, and Whip.sayStarted does not then say all is well.
local function sayRefusal(name, ...)
    local ok, why = ...
    if ok == false and type(why) == 'string' then
        -- Whip.call's own reasons already name the export ('whip_core:X failed: ...')
        local text = why:find('whip_core:' .. name, 1, true) == 1 and why
            or ('whip_core:%s refused: %s'):format(name, why)
        Whip.startProblem('%s', text)
    end
    return ...
end

--- Call a whip_core export safely, by a name built at run time (for a name you know, Whip.core:Name(...), below, is
--- the same call with the export's types). Returns what the export returns, or (false, reason) when whip_core is not
--- running or the call threw — never an error in your code.
---
---     local ok, err = Whip.call(exportName, source, 'lemonade', 1, nil, { reason = 'bought at the stand' })
---
--- INSIDE A Whip.register FUNCTION, A DECLARING CALL'S REFUSAL IS PRINTED in your console, naming the export:
--- Register..., Ensure..., Add..., On..., Watch..., SecureEvent and SecureCallback. Nobody else reads it there. A
--- call straight through exports.whip_core is not.
---
--- AN EXPORT THAT WAITS IS ANSWERED IF whip_core STOPS. Progress and SkillCheck
--- wait for the player; anything that reads the database waits for it. That wait lives in
--- whip_core, and when whip_core stops it is gone with it — the call never returns, and your
--- handler stays stuck holding whatever it held (a "busy" latch, a half-done flow) until your
--- resource restarts. Called through here, it returns `false, 'whip_core stopped'` instead.
--- `exports.whip_core:Progress(...)` straight gets no such answer. (With `dependency 'whip_core'`
--- your resource stops with whip_core and starts fresh, so nothing stays stuck either way.)
---
--- 'whip_core stopped' MEANS "NO ANSWER", NOT "DID NOT HAPPEN": a charge whose write had already gone
--- to the database lands anyway. Treat it like a lost connection — check, do not repeat blindly.
---@param name string  the export's name
---@return any ...
function Whip.call(name, ...)
    if type(name) == 'string' and inPass() and declares(name) then
        return sayRefusal(name, callCore(name, ...))
    end
    return callCore(name, ...)
end

--- whip_core's exports, each called through Whip.call: `Whip.core:AddItem(source, 'cookie', 1)` is
--- `Whip.call('AddItem', source, 'cookie', 1)`. Typed like exports.whip_core (types/satellite.lua), so the editor
--- shows each export's params and returns, where Whip.call('Name') shows none and a misspelt name only returns false.
--- Written with a colon like an export; a dot works too. Typed here too, so an editor that has this file open (a
--- workspace holding whip_core) still underlines a misspelt name.
---@type WhipCoreServerExports|WhipCoreClientExports
Whip.core = setmetatable({}, {
    __index = function(proxy, name)
        local fn = function(first, ...)
            if rawequal(first, proxy) then return Whip.call(name, ...) end
            return Whip.call(name, first, ...)
        end
        rawset(proxy, name, fn)
        return fn
    end,
})

local function runAll(list, what)
    -- A copy of the list: a registration added while these run (from another thread, during a wait)
    -- has already run when it was added, and must not run again here.
    local snapshot = table.move(list, 1, #list, 1, {})
    local co = coroutine.running()
    _passes[co] = (_passes[co] or 0) + 1
    for _, fn in ipairs(snapshot) do
        local ok, err = pcall(fn)
        if not ok then
            _startProblems = _startProblems + 1
            print(('^1[%s] %s failed: %s^0'):format(SELF, what, tostring(err)))
        end
    end
    _passes[co] = _passes[co] > 1 and _passes[co] - 1 or nil
end

--- Run `fn` whenever your registrations are needed: when whip_core becomes ready, and every time
--- it restarts. Put everything you register with whip in here, called through Whip.core:
---
---     Whip.register(function()
---         Whip.core:RegisterItem('lemonade', { name = 'Lemonade', weight = 0.3 })
---         Whip.core:SecureEvent('lemonade:buy', { rateLimit = 1000 }, buyLemonade)
---     end)
---
--- Safe to run more than once: the same registration again changes nothing. While `fn` runs, a declaring
--- call through Whip.core or Whip.call that whip_core refuses (`false, why`) is printed in your console:
--- Register..., Ensure..., Add..., On..., Watch..., SecureEvent and SecureCallback. A call straight through
--- exports.whip_core is not: check its answer yourself.
---
--- Called late — from a thread, after the announcement already went by — `fn` runs straight
--- away as well, instead of waiting for a whip_core restart that may never come.
---
--- Called from inside a registered function (a helper that registers, used inside your own
--- Whip.register), it runs once and is not remembered: the outer function registers it again every
--- time it runs.
---@param fn function
function Whip.register(fn)
    if inPass() then
        runAll({ fn }, 'Whip.register')
        return
    end
    _registerFns[#_registerFns + 1] = fn
    if _heard then runAll({ fn }, 'Whip.register') end
end

--- Run `fn` when whip_core stops. ONLY FOR A RESOURCE WITHOUT `dependency 'whip_core'`: with it (every
--- whip resource), FiveM stops your resource first when whip_core stops, so this never runs, and your
--- resource starts fresh when whip_core brings it back. Without it, this is for letting go of anything
--- that only made sense while whip_core ran: a UI you opened through it, a car you were previewing.
--- Whatever you REGISTERED needs no cleanup — whip_core forgets it by itself, and Whip.register puts it back.
---
--- A handler waiting in `exports.whip_core:Progress` (or SkillCheck, or any export that waits)
--- when whip_core stops is never answered, so anything it holds stays held; clear that here. Or
--- make the call through Whip.core, which returns `false, 'whip_core stopped'` for it.
---
--- EVERY PLAYER HAS BEEN LOGGED OUT when this runs, and no whip_core:player:logout
--- fires for them — whip_core is going away, and it cannot announce on the way down. So drop any
--- per-player or per-character state here too (who is on a job, whose shift, a timer per player):
--- when whip_core comes back every player loads again, and whip_core:player:loaded fires for each.
---@param fn function
function Whip.onCoreLost(fn)
    _lostFns[#_lostFns + 1] = fn
end

-- ============================================
-- One line when you have started: Whip.sayStarted, Whip.startProblem
-- ============================================
--
--     Whip.sayStarted()                                          -- once, in a server file
--     Whip.startProblem('engines.json is unreadable: %s', why)   -- what went wrong, in red
--
-- Once your Whip.register functions have run, the server console says "<your resource> started successfully!",
-- unless something went wrong since your resource started: one of them threw, an error was caught in your code, or
-- something was printed in red (Whip.startProblem does both). Then those lines are all it says.

local _sayStarted = false

--- SERVER. Say "<your resource> started successfully!" once your registrations have run, each time whip_core is ready.
function Whip.sayStarted()
    _sayStarted = IsDuplicityVersion()
end

--- Something wrong found while starting: printed in red with your resource's name, and Whip.sayStarted stays quiet.
---@param fmt string  as string.format's, with the values after it
function Whip.startProblem(fmt, ...)
    _startProblems = _startProblems + 1
    local text = select('#', ...) > 0 and fmt:format(...) or tostring(fmt)
    print(('^1[%s] %s^0'):format(SELF, text))
end

-- ============================================
-- A registry of your own: Whip.registry, Whip.registerWith
-- ============================================
--
-- For a resource others extend (phone apps, MDT plugins, tuning parts): whip's own registry rule, in your resource.
-- An entry belongs to the resource that registered it first; the same again changes nothing; a changed one replaces
-- it; another resource's is refused, said once in your console; a resource's entries go when it stops.
--
--     local Apps = Whip.registry('phoneApp', { label = 'app' })
--     exports('RegisterApp', function(id, def)
--         return Apps:add(Whip.caller(), id, def)         -- Whip.caller(): the resource calling your export
--     end)
--     -- Apps:get(id), Apps.entries (id -> def), Apps:remove(owner, id), Apps:keysOf(owner), Apps:ownerOf(id)
--
-- The resources registering with yours put it in Whip.registerWith('yourresource', fn): fn runs now if you are
-- running, and again each time you start.
--
-- It is whip_core's shared/registry.lua, loaded once into a table of your resource's own (it adds no globals or
-- exports to yours). opts as Registry.new: label, scoped, sweep, same, validate, onAdd, onRemove, prefixed.
local _registryLib
local function registryLib()
    if _registryLib then return _registryLib end
    local src = LoadResourceFile('whip_core', 'shared/registry.lua')
    if not src then error('Whip.registry: whip_core/shared/registry.lua is not there', 3) end
    -- Its own globals, so nothing lands in yours; `exports` a no-op, as whip_core's own exports are whip_core's.
    local env = setmetatable({ exports = function() end }, { __index = _G })
    local chunk, err = load(src, '@@whip_core/shared/registry.lua', 't', env)
    if not chunk then error('Whip.registry: ' .. tostring(err), 3) end
    chunk()
    _registryLib = env.Registry
    return _registryLib
end

--- A registry of your own, with whip's rule (above). One per name.
---@param name string
---@param opts table|nil
---@return table registry  :add(owner, id, value), :remove(owner, id), :get(key), :ownerOf(key), :keysOf(owner), .entries
function Whip.registry(name, opts)
    return registryLib().new(name, opts)
end

-- ============================================
-- Which whip: Whip.requires, Whip.has
-- ============================================
--
-- The version a resource needs goes in its fxmanifest.lua, where the setup report reads it and prints a FIX line
-- when this server's whip_core is older:
--
--     whip_requires '1.0'
--
-- Whip.requires says the same from your code (once, in this console); Whip.has asks about one call, for a feature
-- newer than the oldest whip you support.

--- A version's numbers: '1.2.10' -> { 1, 2, 10 }.
local function versionNumbers(v)
    local out = {}
    for n in tostring(v or ''):gmatch('%d+') do out[#out + 1] = tonumber(n) end
    return out
end

--- Is version `have` at least `want`? ('1.0' is 1.0.0.)
---@param have string
---@param want string
---@return boolean
function Whip.versionAtLeast(have, want)
    local a, b = versionNumbers(have), versionNumbers(want)
    for i = 1, math.max(#a, #b) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    return true
end

local _saidRequires = false
--- Is this server's whip_core at least `min`? Says so once in this console when it is not, naming your resource.
---@param min string  '1.0' or '1.0.0'
---@return boolean
function Whip.requires(min)
    local have = GetResourceMetadata('whip_core', 'version', 0) or '0'
    if Whip.versionAtLeast(have, min) then return true end
    if not _saidRequires then
        _saidRequires = true
        print(('^1[%s] needs whip_core %s or newer; this server has %s. Update whip_core.^7'):format(SELF, tostring(min), have))
    end
    return false
end

--- Has this server's whip_core the export `name` on this side? false when whip_core is not running or older.
---@param name string
---@return boolean
function Whip.has(name)
    if GetResourceState('whip_core') ~= 'started' then return false end
    local ok, yes = pcall(function() return exports.whip_core:HasExport(name) end)
    return ok and yes == true
end

--- The resource calling your export (read it first, before anything waits), or your own name when nothing did.
---@return string
function Whip.caller()
    return GetInvokingResource() or GetCurrentResourceName()
end

--- Run `fn` now if `resource` is running, and again each time it starts: for registering with another resource's
--- registry (its apps, its plugins) so a restart of it brings yours back. Each run in its own thread.
---@param resource string
---@param fn function
function Whip.registerWith(resource, fn)
    local function run()
        CreateThread(function()
            local ok, err = pcall(fn)
            if not ok then print(('^1[%s] Whip.registerWith(%s) failed: %s^7'):format(GetCurrentResourceName(), resource, tostring(err))) end
        end)
    end
    if GetResourceState(resource) == 'started' then run() end
    AddEventHandler('onResourceStart', function(res) if res == resource then run() end end)
end

-- ============================================
-- A command behind whip's gate: Whip.command (server)
-- ============================================
--
-- A command a player types is a way in from their game, like an event: the same gate, in one place.
--
--     Whip.command('ropes', { dev = true }, function(source, args, raw) ... end)
--
-- opts:
--   dev = true          the server console, and whip.devtools with developer mode on (whip_core decides)
--   ace = 'my.perm'     the player needs this ACE (IsPlayerAceAllowed)
--   whileDead = true    allowed while they are down (refused by default, as a SecureEvent is)
--   rateLimit = false   no limit; default 3 at once, then one a second
--   console = false     not from the server console (allowed by default)
-- A refusal is said to the player as a toast (or printed for the console). fn runs in its own thread, so it may
-- wait (Whip.core with an export that waits).
if IsDuplicityVersion() then
    local _commandUse = {}   -- [name] = { [source] = { tokens, at } }

    local function commandRefuse(source, why)
        if source == 0 then print(('[%s] %s'):format(SELF, why)) return end
        Whip.call('NotifyPlayer', source, why, 'error')
    end

    --- Register a command with whip's gate (above).
    ---@param name string
    ---@param opts table|nil
    ---@param fn fun(source: number, args: string[], raw: string)
    function Whip.command(name, opts, fn)
        opts = type(opts) == 'table' and opts or {}
        local burst, everyMs = 3, 1000
        if type(opts.rateLimit) == 'table' then
            burst, everyMs = tonumber(opts.rateLimit.burst) or burst, tonumber(opts.rateLimit.everyMs) or everyMs
        end
        _commandUse[name] = {}
        RegisterCommand(name, function(source, args, raw)
            CreateThread(function()
                if source == 0 then
                    if opts.console == false then return commandRefuse(0, '/' .. name .. ' is for players only') end
                else
                    if opts.dev and Whip.call('HasDevTools', source) ~= true then
                        return commandRefuse(source, '/' .. name .. ' needs developer mode on (/w)')
                    end
                    if opts.ace and not IsPlayerAceAllowed(source, opts.ace) then
                        return commandRefuse(source, '/' .. name .. ' is not for you')
                    end
                    if opts.whileDead ~= true and Whip.call('IsPlayerDead', source) == true then
                        return commandRefuse(source, 'Not while downed')
                    end
                    if opts.rateLimit ~= false then
                        local now, use = GetGameTimer(), _commandUse[name][source]
                        if not use then use = { tokens = burst, at = now }; _commandUse[name][source] = use end
                        use.tokens = math.min(burst, use.tokens + (now - use.at) / everyMs)
                        use.at = now
                        if use.tokens < 1 then return commandRefuse(source, 'Slow down') end
                        use.tokens = use.tokens - 1
                    end
                end
                local ok, err = pcall(fn, source, args or {}, raw or '')
                if not ok then print(('^1[%s] /%s failed: %s^7'):format(SELF, name, tostring(err))) end
            end)
        end, false)
    end

    AddEventHandler('playerDropped', function()
        local src = source
        for _, users in pairs(_commandUse) do users[src] = nil end
    end)
end

-- ============================================
-- The voice system: Whip.voice
-- ============================================
--
-- whip runs ONE voice system: whip_voice (its own voice server, 3D, rooms, sound recipes), or a voice
-- resource of the owner's own that registers with RegisterVoiceSystem. A resource that uses voice — a
-- phone's calls, an intercom — never names one: it asks whip_core which it is and calls it through here.
--
--     local v = Whip.voiceSystem()      -- { resource, label, features } or false: none running
--     local lineId, why = Whip.voice('OpenLine', { members = { a, b }, track = 'voice', recipe = mySound })
--
-- Whip.voice answers what the export answers, or false and why (no voice system, or the call threw).
-- A line is YOURS (the voice system reads its caller) and goes when your resource stops. `features`
-- says what this one can do: whip_voice/docs/LINES.md has the exports, and what the simple one leaves out.

--- The voice system running now, or false.
---@return table|false
function Whip.voiceSystem()
    local v = Whip.call('GetVoiceSystem')
    if type(v) ~= 'table' or type(v.resource) ~= 'string' or GetResourceState(v.resource) ~= 'started' then
        return false
    end
    return v
end

--- Call one of the voice system's exports. Answers its answer, or false and why.
---@param name string  'OpenLine', 'CloseLine', 'SetLineSpeaker', 'IsVoiceReady', ...
function Whip.voice(name, ...)
    local v = Whip.voiceSystem()
    if not v then return false, 'no voice system is running' end
    local res, args = v.resource, table.pack(...)
    local ok, a, b = pcall(function() return exports[res][name](exports[res], table.unpack(args, 1, args.n)) end)
    if not ok then return false, ('%s: %s'):format(res, tostring(a)) end
    return a, b
end

--- Does this announcement concern us?
---
--- 'coreStarted': whip_core has just (re)started and remembers nothing — always. 'resourceStarted':
--- only when WE are among the resources that just started, which is how a resource starting after
--- whip_core hears it is ready. Anything else (an older whip_core that sends no reason) — yes, to
--- be safe: running a registration twice costs nothing.
local function concernsUs(info)
    if type(info) ~= 'table' or info.reason == 'coreStarted' then return true end
    if info.reason == 'resourceStarted' and type(info.resources) == 'table' then
        for _, res in ipairs(info.resources) do
            if res == SELF then return true end
        end
        return false
    end
    return true
end

-- ============================================
-- Your config.lua as a settings page: Whip.configPage
-- ============================================
--
-- Your Config on a page in /whip → Settings, so an admin changes it in game. In a shared script
-- after config.lua, at file scope:
--
--     Whip.configPage({ label = 'Autos', groups = {
--         { label = 'Prices', settings = {
--             { key = 'Tuning.EngineSwapPrice', type = 'int', min = 0, max = 1000000, unit = '$', label = 'Engine swap' },
--         } },
--     } })
--     Whip.onConfigChanged('Shop', function(value, old, key) ... end)   -- for what you worked out at load
--
-- Each key is a path in your Config, and its default is what config.lua says. What an admin saved
-- is written into Config on this side when the page is declared and whenever a change arrives
-- (a table in place, so a file holding Config.Shop sees the new values), so your code keeps reading
-- Config.X. The entries are whip_core's settings entries (docs.html#registersettings) with no `default`.
-- A 'record' entry is one card for several values of one table: key = 'Turbo', fields = { { key =
-- 'TorqueGain', ... }, ... }, each field kept as its own setting ('Turbo.TorqueGain').
-- The page is declared again whenever whip_core starts; a refusal is printed here, with why.

local _configHooks = {}   -- { { path, fn }, ... } from Whip.onConfigChanged

--- A path step: digits are a list place unless the table has a key of the same name (Items['420']).
local function configStep(t, p)
    if p:match('^%d+$') and t[p] == nil then return math.tointeger(tonumber(p)) end
    return p
end

--- Why a value cannot go on a page, or nil. Only data makes the trip through whip_core: a function
--- comes back a plain table, and a row field the page does not declare comes back as plain data (a
--- position as { x, y, z }), so both are said when the page is made rather than found broken later.
local function notData(v, depth)
    if type(v) == 'function' then return 'holds a function' end
    if type(v) ~= 'table' or depth > 8 then return nil end
    for _, x in pairs(v) do
        local why = notData(x, depth + 1)
        if why then return why end
    end
    return nil
end

local function undeclaredRowField(entry, default)
    if (entry.type ~= 'records' and entry.type ~= 'map') or type(entry.fields) ~= 'table' or type(default) ~= 'table' then return nil end
    local declared = {}
    for _, f in ipairs(entry.fields) do
        if type(f) == 'table' and type(f.key) == 'string' then declared[f.key:match('^[^%.]+')] = true end
    end
    for _, row in pairs(default) do
        for k, x in pairs(type(row) == 'table' and row or {}) do
            local t = type(x)
            if not declared[k] and t ~= 'string' and t ~= 'number' and t ~= 'boolean' then
                return ('has a row field "%s" its fields do not declare'):format(tostring(k))
            end
        end
    end
    return nil
end

--- The table holding `path` in `root`, and its key there; nil when the path is not in it.
local function configParent(root, path)
    local parts = {}
    for part in path:gmatch('[^%.]+') do parts[#parts + 1] = part end
    local t = root
    for i = 1, #parts - 1 do
        if type(t) ~= 'table' then return nil end
        t = t[configStep(t, parts[i])]
    end
    if type(t) ~= 'table' or #parts == 0 then return nil end
    return t, configStep(t, parts[#parts])
end

local function configCopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = configCopy(x) end
    return out
end

local function configSame(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, x in pairs(a) do if not configSame(x, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

--- Put `value` at `path` in `root` and run the onConfigChanged hooks that cover it.
local function configApply(root, path, value)
    local parent, key = configParent(root, path)
    if not parent or key == nil then
        print(('[%s] settings: %s is not a place in Config'):format(SELF, path))
        return
    end
    local old = configCopy(parent[key])
    if configSame(old, value) then return end
    if type(old) == 'table' and type(value) == 'table' then
        local t = parent[key]
        for k in pairs(t) do t[k] = nil end
        for k, x in pairs(value) do t[k] = configCopy(x) end
    else
        parent[key] = configCopy(value)
    end
    -- A hook hears its own path, anything under it, and a change to a table it is inside.
    for _, h in ipairs(_configHooks) do
        if h.path == path or path:sub(1, #h.path + 1) == h.path .. '.' or h.path:sub(1, #path + 1) == path .. '.' then
            local ok, err = pcall(h.fn, value, old, path)
            if not ok then print(('[%s] settings: the hook for %s failed: %s'):format(SELF, h.path, tostring(err))) end
        end
    end
end

--- Your Config as a settings page in /whip. See the top of this section.
---@param def table { label, settings | groups, config? }  config: the table the keys are in (Config)
---@return boolean ok  false when def is not a page (printed)
function Whip.configPage(def)
    local root = type(def) == 'table' and (def.config or Config) or nil
    if type(def) ~= 'table' or type(root) ~= 'table' then
        print(('[%s] Whip.configPage({ label, settings }) needs your Config loaded first'):format(SELF))
        return false
    end
    -- THE DEFAULTS ARE TAKEN NOW, before anything saved is written into Config: config.lua's values.
    local groups = def.groups or { { label = def.label, settings = def.settings } }
    local page = { label = def.label, groups = {} }
    local keys = {}
    for gi, g in ipairs(type(groups) == 'table' and groups or {}) do
        local list = {}
        for _, e in ipairs(type(g) == 'table' and type(g.settings) == 'table' and g.settings or {}) do
            local entry = {}
            for k, v in pairs(type(e) == 'table' and e or {}) do entry[k] = v end
            local why = nil
            if type(entry.key) == 'string' then
                local parent, key = configParent(root, entry.key)
                entry.default = parent and configCopy(parent[key])
                why = notData(entry.default, 1) or undeclaredRowField(entry, entry.default)
                if not why and entry.type == 'record' and type(entry.fields) == 'table' then
                    -- A card of fields: each is a setting of its own, '<key>.<field key>'.
                    for _, f in ipairs(entry.fields) do
                        if type(f) == 'table' and type(f.key) == 'string' then keys[#keys + 1] = entry.key .. '.' .. f.key end
                    end
                elseif not why then
                    keys[#keys + 1] = entry.key
                end
            end
            if why then
                print(('[%s] settings: %s is left off the page: it %s'):format(SELF, entry.key, why))
            else
                list[#list + 1] = entry
            end
        end
        page.groups[gi] = { id = type(g) == 'table' and g.id or nil, label = type(g) == 'table' and g.label or nil, settings = list }
    end
    Whip.register(function()
        local ok, why = exports[CORE]:__RegisterSettings(page)
        if ok ~= true then
            print(('[%s] settings page refused: %s'):format(SELF, tostring(why)))
            return
        end
        -- Each key's callback before its value: nothing that changes in between is missed. A key
        -- whip_core left off the page (its default failed its check: printed there) reads nil, and
        -- keeps config.lua's value.
        for _, key in ipairs(keys) do
            exports[CORE]:__OnSettingChanged(key, function(value, _, changed)
                configApply(root, changed or key, value)
            end)
            local value = exports[CORE]:__GetSetting(key)
            if value ~= nil then configApply(root, key, value) end
        end
    end)
    return true
end

--- fn(value, old, key) after a Config value on your page changes on this side: an admin's change, or
--- a saved value written over config.lua's as the page is declared. It hears its own path, anything
--- under it ('Shop' hears 'Shop.radius') and a change to a table it is inside. For anything you
--- worked out from Config at load (a price list, a thread that only starts when an option is on).
--- Call it at file scope: it lives in your resource, and outlasts whip_core restarts.
---@param path string
---@param fn function
function Whip.onConfigChanged(path, fn)
    if type(path) ~= 'string' or type(fn) ~= 'function' then
        print(('[%s] Whip.onConfigChanged(path, function(value, old, key) end)'):format(SELF))
        return
    end
    _configHooks[#_configHooks + 1] = { path = path, fn = fn }
end

-- ============================================
-- Player settings (client side): Whip.playerSetting
-- ============================================
--
-- A row of your own on the pause menu's Server Settings page: a choice each PLAYER makes
-- for themselves, not your server config (that is Whip.configPage). Your resource keeps the value as it already
-- does (its own KVP); the page shows it and changes it through `get` and `set`. On the client:
--
--     Whip.playerSetting({
--         key = 'chat.visibility', group = 'Chat & voice', label = 'Chat messages',
--         help = 'New messages fade away, stay on screen, or chat is hidden.',
--         type = 'choice', options = { { value = 0, label = 'Fade away' }, { value = 1, label = 'Stay' } },
--         default = 0,                                   -- what "Reset to the server's defaults" puts back
--         get = function() return hideState end,
--         set = function(value) hideState = value; SetResourceKvp(...) end,
--     })
--
-- type: 'toggle' (true / false), 'choice' (options, each { value, label }), 'slider' (min, max, step, unit).
-- group: one of the page's tabs ('Controller', 'Vehicles', 'Map & HUD', 'Chat & voice') or a new one of yours.
-- Declared again by itself when whip_core restarts; the row goes when your resource stops. Call it at file scope.
---@param def table
---@return boolean ok  false when def is not a row (printed)
function Whip.playerSetting(def)
    if IsDuplicityVersion() then
        print(('[%s] Whip.playerSetting is client side: each player\'s own choice lives on their PC'):format(SELF))
        return false
    end
    if type(def) ~= 'table' or type(def.key) ~= 'string' or type(def.get) ~= 'function' or type(def.set) ~= 'function' then
        print(('[%s] Whip.playerSetting({ key, label, type, get = function, set = function, ... }) needs a key, get and set')
            :format(SELF))
        return false
    end
    Whip.register(function()
        local ok, why = exports[CORE]:__RegisterPlayerSetting(def)
        if ok ~= true then
            print(('[%s] player setting %s refused: %s'):format(SELF, def.key, tostring(why)))
        end
    end)
    return true
end

-- ============================================
-- A controller on your NUI screen (client side): Whip.padScreen
-- ============================================
--
-- The browser cannot read a gamepad inside FiveM. While your screen is open this reads the pad in Lua and
-- sends each press to your page, owns your NUI focus (no mouse cursor while a pad drives; the mouse moving
-- brings it back), and holds the pad's world actions off. On the client, once:
--
--     local screen = Whip.padScreen({
--         buttons  = { 'up', 'down', 'left', 'right', 'a', 'b', 'x', 'y' },   -- the default; also 'lb', 'rb', 'menu'
--     })
--     -- opening:  local pad = screen:open()   then tell your page `pad` so it draws button hints
--     -- closing:  screen:close()
--
-- Your page gets { action = 'pad', cmd = 'up', down = true, rep = 2 } per press (rep: the D-pad held down,
-- repeating), and { action = 'padDevice', pad = true } when the player swaps between pad and mouse.
--
-- Also:
--   stick     = false        the left stick does not step like the D-pad (default: it does)
--   releases  = { a = true } these buttons send down = false when let go (a hold on the page)
--   keepInput = 'always'     the game keeps its input with the mouse too (default: only on a pad)
--   block     = { groups = {...}, controls = {...} } | false   what is held off while a pad drives
--               (default: walking, looking, fighting, the radio and weapon wheels, jump, get in, cover,
--               reload and Start / Esc)
--   onButton  = function(cmd, down, rep) end   instead of the 'pad' message
--   onDevice  = function(pad) end              instead of the 'padDevice' message
--   onFrame   = function() end                 every frame a pad drives (a stick of your own)
--   screen:typing(on)  a text field on your page has the keyboard: the pad is left alone, no game input
--   screen:pause(on)   another screen of yours has the pad: left alone, your focus untouched. Not for whip's
--                      OpenKeyboard: while it is up the screen leaves the pad to it by itself
--   screen:isPad()
--
-- LB IS WHIP'S COMBO KEY: a press while LB is held that whip_core says is its combo (LB + A talks) never
-- reaches your page, and 'lb' itself goes on its release, only when no combo was used.
if not IsDuplicityVersion() then
    local CONTROL = { up = 188, down = 187, left = 189, right = 190, a = 201, b = 202, x = 203, y = 204,
                      lb = 205, rb = 206, menu = 199 }
    local DIR = { up = true, down = true, left = true, right = true }
    local LB = 205
    local FIRST, REPEAT = 380, 110   -- whip's menus' repeat (whip_core client/controller.lua)
    local SETTLE = 150               -- the device stays put this long before the cursor goes or comes back
    local STICK = 0.6                -- the left stick past this is a direction, as in whip's menus
    local BLOCK = { groups = { 'move', 'look', 'combat', 'radio', 'weaponWheel' }, controls = { 22, 23, 36, 44, 45, 199, 200 } }

    local _screens = {}

    --- whip's OpenKeyboard is up (whip_core:keyboard:opened / closed): the pad is its, so no screen reads it.
    local keyboardUp = false

    local function setKeyboard(up)
        if up == keyboardUp then return end
        keyboardUp = up
        for _, x in ipairs(_screens) do
            x.kb = up
            -- Back to the screen: its focus again, as screen:pause(false) does (the keyboard took whip_core's).
            if not up and x.open and not x.paused then x.refocus() end
        end
    end

    --- Is the left stick held that way? Read disabled: the block holds walking off.
    local function stickHeld(cmd)
        if cmd == 'left' then return GetDisabledControlNormal(0, 30) < -STICK end
        if cmd == 'right' then return GetDisabledControlNormal(0, 30) > STICK end
        if cmd == 'up' then return GetDisabledControlNormal(0, 31) < -STICK end
        return GetDisabledControlNormal(0, 31) > STICK
    end

    ---@param def table|nil  see above
    ---@return table screen  :open() :close() :typing(on) :pause(on) :isPad()
    function Whip.padScreen(def)
        def = type(def) == 'table' and def or {}
        local buttons = {}
        for _, name in ipairs(def.buttons or { 'up', 'down', 'left', 'right', 'a', 'b', 'x', 'y' }) do
            if CONTROL[name] then
                buttons[#buttons + 1] = name
            else
                print(('[%s] Whip.padScreen: there is no button "%s" (up down left right a b x y lb rb menu)'):format(SELF, tostring(name)))
            end
        end
        local releases = type(def.releases) == 'table' and def.releases or {}
        local stick = def.stick ~= false
        local keepAlways = def.keepInput == 'always'
        local block = def.block
        if block == nil then block = BLOCK end
        local blockId = 'padScreen' .. (#_screens + 1)
        local onButton = def.onButton or function(cmd, down, rep)
            SendNUIMessage({ action = 'pad', cmd = cmd, down = down, rep = rep })
        end
        local onDevice = def.onDevice or function(pad) SendNUIMessage({ action = 'padDevice', pad = pad }) end
        local onFrame = def.onFrame

        -- kb: whip's OpenKeyboard is up (setKeyboard); refocus: applyFocus, for setKeyboard
        local s = { open = false, pad = false, typing = false, paused = false, kb = keyboardUp, blocked = false, warned = false, gen = 0 }
        _screens[#_screens + 1] = s

        local function call(what, fn, ...)
            local ok, err = pcall(fn, ...)
            if not ok then print(('[%s] Whip.padScreen %s failed: %s'):format(SELF, what, tostring(err))) end
        end

        local function applyFocus()
            SetNuiFocus(s.open, s.open and not s.pad)
            SetNuiFocusKeepInput(s.open and not s.typing and (keepAlways or s.pad))
        end
        s.refocus = applyFocus

        local function setBlock(want)
            if not block or want == s.blocked then return end
            s.blocked = want
            if not want then return Whip.call('UnblockControls', blockId) end
            local ok, why = Whip.call('BlockControls', blockId, block)
            if ok ~= true and not s.warned and GetResourceState(CORE) == 'started' then
                s.warned = true
                print(('[%s] Whip.padScreen: the pad\'s block was refused: %s'):format(SELF, tostring(why)))
            end
        end

        local function read(gen)
            local was, held, nextAt, reps = {}, {}, {}, {}
            local lbHere = false   -- LB went down while this read (one carried in does not count)
            local fresh = true     -- the first frame read: what is already down (A that opened it) is not a press
            local last, since = s.pad, GetGameTimer()
            local function letGo()
                for cmd in pairs(held) do
                    if releases[cmd] then call('onButton', onButton, cmd, false) end
                end
                was, held, lbHere, fresh = {}, {}, false, true
            end
            while s.open and gen == s.gen do
                Wait(0)
                -- Closed during the wait: stop here, or the block would be taken again after close released it.
                if not s.open or gen ~= s.gen then break end
                if not s.paused and not s.kb then
                    local now = GetGameTimer()
                    local pad = not IsUsingKeyboard(0)
                    if pad ~= last then last, since = pad, now end
                    if pad ~= s.pad and now - since >= SETTLE then
                        s.pad = pad
                        applyFocus()
                        call('onDevice', onDevice, pad)
                    end
                    setBlock(s.pad and not s.typing)
                end
                if s.pad and not s.typing and not s.paused and not s.kb and gen == s.gen then
                    local now = GetGameTimer()
                    local lbDown = IsDisabledControlPressed(0, LB) and true or false
                    for i = 1, #buttons do
                        local cmd = buttons[i]
                        local id = CONTROL[cmd]
                        local down = (IsDisabledControlPressed(0, id) or (stick and DIR[cmd] and stickHeld(cmd))) and true or false
                        if fresh then
                            -- seen, not pressed
                        elseif cmd == 'lb' then
                            if down and not was.lb then
                                lbHere = true
                            elseif not down and was.lb and lbHere then
                                lbHere = false
                                if Whip.call('__PadComboUsed') ~= true then call('onButton', onButton, 'lb', true) end
                            end
                        elseif down and not was[cmd] then
                            if not (lbDown and Whip.call('__PadComboTakes', id) == true) then
                                held[cmd], nextAt[cmd], reps[cmd] = true, now + FIRST, 0
                                call('onButton', onButton, cmd, true)
                            end
                        elseif down and held[cmd] and DIR[cmd] and now >= nextAt[cmd] then
                            nextAt[cmd], reps[cmd] = now + REPEAT, reps[cmd] + 1
                            call('onButton', onButton, cmd, true, reps[cmd])
                        elseif not down and held[cmd] then
                            held[cmd] = nil
                            if releases[cmd] then call('onButton', onButton, cmd, false) end
                        end
                        was[cmd] = down
                    end
                    fresh = false
                    if onFrame then call('onFrame', onFrame) end
                elseif not fresh then
                    letGo()
                end
            end
        end

        local screen = {}

        --- Take the focus and start reading. Answers whether a pad is in the player's hands, for your page.
        ---@return boolean pad
        function screen:open()
            if s.open then return s.pad end
            s.open, s.typing, s.paused = true, false, false
            s.pad = not IsUsingKeyboard(0)
            s.gen = s.gen + 1
            applyFocus()
            setBlock(s.pad)
            local gen = s.gen
            CreateThread(function() read(gen) end)
            return s.pad
        end

        --- Give the focus back and stop reading.
        function screen:close()
            if not s.open then return end
            s.open, s.typing, s.paused = false, false, false
            s.gen = s.gen + 1
            applyFocus()
            setBlock(false)
        end

        --- A text field on your page has the keyboard (or not).
        function screen:typing(on)
            on = on == true
            if on == s.typing then return end
            s.typing = on
            if s.open then
                applyFocus()
                setBlock(s.pad and not on)
            end
        end

        --- Another screen has the pad (whip's OpenKeyboard), or gave it back: your focus again.
        function screen:pause(on)
            s.paused = on == true
            if s.open and not s.paused then applyFocus() end
        end

        function screen:isPad() return s.open and s.pad end

        if #_screens == 1 then
            -- whip_core forgot the blocks when it stopped: they are held again once it is back.
            Whip.register(function()
                for _, x in ipairs(_screens) do x.blocked = false end
            end)
            -- whip's keyboard has the pad between these. whip_core going away takes the keyboard with it, and
            -- the closed would never come.
            AddEventHandler('whip_core:keyboard:opened', function() setKeyboard(true) end)
            AddEventHandler('whip_core:keyboard:closed', function() setKeyboard(false) end)
            Whip.onCoreLost(function() setKeyboard(false) end)
            AddEventHandler('onResourceStop', function(res)
                if res ~= SELF then return end
                for _, x in ipairs(_screens) do
                    if x.open then
                        SetNuiFocus(false, false)
                        SetNuiFocusKeepInput(false)
                    end
                end
            end)
        end
        return screen
    end
end

-- ============================================
-- Director cards (server side): Whip.card
-- ============================================
--
-- A card of your own in the Director's palette. On the server:
--
--     Whip.card('police.notify', {
--         title = 'Notify Police', desc = 'Sends a dispatch call to on-duty officers.',
--         outputs = { 'sent', 'nobody' }, labels = { sent = 'Sent', nobody = 'Nobody on duty' }, bad = { 'nobody' },
--         props = { { key = 'message', kind = 'text', label = 'Message', default = '10-90 alarm', maxLength = 120 } },
--         testSays = 'Would send "{message}" to the police on duty',
--         run = function(card)
--             ...                              -- it may wait: Whip.core, the database
--             return 'sent'                    -- an outcome; or nothing, and Whip.answerCard(card.callId, 'sent') later
--         end,
--     })
--
-- The type is '<your namespace>.<name>': the first running resource to use a namespace has it, for its
-- cards and its events (SendDirectorEvent). Call it at file scope or inside Whip.register: it is sent
-- again whenever whip_core restarts. A refusal is printed here, with why.
--
-- Also: category / categoryTitle / color (blue, teal, green, amber, red, violet, slate) / icon / help;
-- timeout = seconds before Took Too Long (30); instant = true (answers at once, never waits);
-- event = { name = 'police.panicButton', match = 'player' | 'run' | 'any', once?, filter? } (no run:
-- it goes on when you send that event); check = function(props, doc) -> message, 'warning'? (doc: its vars,
-- its world { id, kind, label, model, models }, and data[worldId]: what your buttons saved on each thing);
-- a field's showIf = '<a bool field's key>' (shown only while that switch is on); a field of kind 'entries'
-- (button = one of your Director buttons for kind 'card', add = its words, max = 1-12): a list on the card
-- that button fills, each entry plain data with a `text` its row shows (client: Whip.directorButton);
-- onEnd = function(callId, why) (it ended without your answer); test = 'run' (it runs in a builder's
-- Test too, with card.test: sandbox yourself); v = 2 (bumped when its fields change);
-- renamed = { ['police.alert'] = { pins = { sent = 'dispatched' } } } (what it was called before);
-- once = false (the run waits at it for a player: no "Only once" switch) / onceOut = 'sent' (the outcome
-- a skipped "Only once" card goes on through; its first when left out).
--
-- A FAIL CONDITION of your own (no outputs, no run): a card wired to nothing that watches the whole run and fails it
-- when your event comes about one of its players:
--
--     Whip.card('police.failArrested', {
--         title = 'Fail If a Player Is Arrested', desc = 'Whenever one of the run\'s players is arrested...',
--         fail = {
--             event = 'police.arrested',   -- yours: SendDirectorEvent('police.arrested', { source = src })
--             match = 'player',            -- 'player' (about one of its players: the default), 'run' (opts.runId), 'any'
--             ends = 'them',               -- its "When it is broken" default: 'everyone' (the run fails) or 'them' (only
--                                          -- that player is out); a 'player' match only
--             reason = 'You were arrested',   -- its "Why" default, said to them
--             filter = function(card, event) return event.data.felony and 'Arrested for a felony' end,   -- optional:
--                                          -- true or words breaks it; false or nil, not this time (it may not wait)
--         },
--     })
--
-- It shows with whip_core's Fail Conditions (category 'fail' unless you name one), and gets their two fields itself.
-- In a builder's Test it hears only /director send, and its filter runs only with test = 'run'.
--
-- YOUR FUNCTIONS STAY HERE. whip_core gets your card as data and one function that runs your run,
-- event filter, check and onEnd inside a pcall on this side, so a mistake in them comes back to
-- whip_core in its own words (from another resource, a thrown error arrives with no message).
--
-- THE CARD your run is handed is a copy (callId, runId, cardId, scenario, name, rev, test, tag, player,
-- starter, players, trigger, props) with methods, each a call back into whip_core, refused once the card
-- has finished: card:var(name) / card:setVar(name, v), card:state() / card:setState(t), card:place(id),
-- card:made(id), card:record(kind, { source?, detail? }), card:objective(text, { who? }),
-- card:clearObjective(), card:clock(seconds, label) (both taken down by themselves when the card ends
-- without your answer: Took too long, Didn't work, its run ended), card:give(src, item, n, metadata?),
-- card:pay(src, amount, { method?, reason? }), card:charge(src, amount, { method?, reason? }),
-- card:finish('succeeded' | 'failed' | 'calledOff', reason?), card:log(fmt, ...).
if IsDuplicityVersion() then
    local _cards = {}   -- [type] = your definition (this resource's own)
    local _cardSenders = {}   -- [type] = the one function that sends it (Whip.register's)

    local METHOD_NAMES = { 'var', 'setVar', 'state', 'setState', 'place', 'made', 'record', 'objective', 'clearObjective',
                           'clock', 'give', 'pay', 'charge', 'finish', 'log' }
    -- These answer what they read (nil and why when they cannot); the rest true (false and why).
    local GETTERS = { var = true, state = true, place = true, made = true }

    local cardMethods = {}
    for _, m in ipairs(METHOD_NAMES) do
        cardMethods[m] = function(self, ...)
            local args = table.pack(...)
            if m == 'log' then
                local ok, s = pcall(string.format, tostring(args[1]), table.unpack(args, 2, args.n))
                args = table.pack(ok and s or tostring(args[1]))
            end
            local r = table.pack(Whip.call('__DirectorCardDo', rawget(self, 'callId'), m, table.unpack(args, 1, args.n)))
            if GETTERS[m] then
                if r[1] == true then return r[2] end
                return nil, r[2]
            end
            if r[1] == true then return true, r[2] end
            return false, r[2]
        end
    end
    local cardMeta = { __index = cardMethods }

    --- Plain data only (what may cross to whip_core): 8 deep, no functions.
    local function plainOf(v, depth)
        local t = type(v)
        if t == 'string' or t == 'number' or t == 'boolean' then return v end
        if t ~= 'table' then return nil end
        depth = (depth or 0) + 1
        if depth > 8 then return nil end
        local out = {}
        for k, x in pairs(v) do
            if type(k) == 'string' or type(k) == 'number' then out[k] = plainOf(x, depth) end
        end
        return out
    end

    local function cardOf(data) return setmetatable(type(data) == 'table' and data or {}, cardMeta) end

    --- The one function whip_core holds: it runs your code here and answers data, never an error.
    local function entryFor(t)
        return function(op, payload)
            local def = _cards[t]
            if not def then return { err = t .. ' is not one of this resource\'s cards any more' } end
            payload = type(payload) == 'table' and payload or {}
            if op == 'run' then
                local ok, pin, data = pcall(def.run, cardOf(payload.card))
                if not ok then return { err = tostring(pin) } end
                return { pin = pin, data = plainOf(data) }
            elseif op == 'filter' and type(def.fail) == 'table' then
                -- A fail condition's: true (or the words they are told) breaks the rule; false or nil, not this time.
                local ok, res = pcall(def.fail.filter, cardOf(payload.card), payload.event)
                if not ok then return { err = tostring(res) } end
                if not res then return {} end
                return { pin = 'broken', data = type(res) == 'string' and { reason = res } or nil }
            elseif op == 'filter' then
                local ok, pin, data = pcall(def.event.filter, cardOf(payload.card), payload.event)
                if not ok then return { err = tostring(pin) } end
                return { pin = pin, data = plainOf(data) }
            elseif op == 'check' then
                local ok, msg, severity = pcall(def.check, payload.props or {}, payload.doc or {})
                if not ok then return { err = tostring(msg) } end
                return { msg = msg ~= nil and tostring(msg) or nil, severity = severity == 'warning' and 'warning' or nil }
            elseif op == 'onEnd' then
                local ok, err = pcall(def.onEnd, payload.callId, payload.why)
                if not ok then return { err = tostring(err) } end
                return {}
            end
            return { err = 'whip_core asked for "' .. tostring(op) .. '", which this helper does not know (update it)' }
        end
    end

    --- The card as data (what whip_core checks and draws).
    local function specOf(def)
        local spec = plainOf({
            category = def.category, categoryTitle = def.categoryTitle, color = def.color, icon = def.icon,
            title = def.title, desc = def.desc, help = def.help, outputs = def.outputs, labels = def.labels, bad = def.bad,
            testSays = def.testSays, test = def.test, instant = def.instant == true or nil, timeout = def.timeout, v = def.v or 1,
            permission = def.permission, renamed = def.renamed, once = def.once, onceOut = def.onceOut,
        }) or {}
        local props = {}
        for i, f in ipairs(type(def.props) == 'table' and def.props or {}) do
            props[i] = plainOf({ key = f.key, kind = f.kind, label = f.label, default = f.default, required = f.required,
                                 options = f.options, worldKind = f.worldKind, min = f.min, max = f.max, maxLength = f.maxLength,
                                 hint = f.hint, unit = f.unit, lines = f.lines, group = f.group, showIf = f.showIf,
                                 button = f.button, add = f.add })
        end
        spec.props = props
        if type(def.event) == 'table' then
            spec.event = { name = def.event.name, match = def.event.match, once = def.event.once,
                           hasFilter = type(def.event.filter) == 'function' }
        end
        if type(def.fail) == 'table' then
            spec.fail = { event = def.fail.event, match = def.fail.match, ends = def.fail.ends, reason = def.fail.reason,
                          hasFilter = type(def.fail.filter) == 'function' }
        end
        spec.hasCheck = type(def.check) == 'function'
        spec.hasOnEnd = type(def.onEnd) == 'function'
        spec.__whipCard = 1
        return spec
    end

    --- Add (or change) a Director card of this resource's. See the top of this section.
    ---@param t string    '<your namespace>.<name>'
    ---@param def table
    ---@return boolean ok  false when it is not a card (printed); whip_core's own answer is printed too
    function Whip.card(t, def)
        if type(t) ~= 'string' or type(def) ~= 'table' then
            print(('[%s] Whip.card(type, def): a type ("police.notify") and a table'):format(SELF))
            return false
        end
        if def.event == nil and def.fail == nil and type(def.run) ~= 'function' then
            print(('[%s] Director card %s: it needs run = function(card) ... end (or an event, or fail)'):format(SELF, t))
            return false
        end
        if def.fail ~= nil and (type(def.fail) ~= 'table' or (def.fail.filter ~= nil and type(def.fail.filter) ~= 'function')) then
            print(('[%s] Director card %s: fail is { event, match?, ends?, reason?, filter? }'):format(SELF, t))
            return false
        end
        if def.event ~= nil and (type(def.event) ~= 'table' or (def.event.filter ~= nil and type(def.event.filter) ~= 'function')) then
            print(('[%s] Director card %s: event is { name, match?, once?, filter? }'):format(SELF, t))
            return false
        end
        _cards[t] = def
        -- ONE sender a type, whatever number of times it is called (a test that adds its card each run):
        -- it sends the card as it is now, at every whip_core start, and now when whip_core is up.
        if _cardSenders[t] then
            if _heard then runAll({ _cardSenders[t] }, 'Whip.card') end
        else
            local entry = entryFor(t)
            _cardSenders[t] = function()
                local now = _cards[t]
                if not now then return end   -- (removed since)
                local ok, why = Whip.call('__RegisterDirectorCard', t, specOf(now), entry)
                if ok ~= true then print(('[%s] Director card %s refused: %s'):format(SELF, t, tostring(why))) end
            end
            Whip.register(_cardSenders[t])
        end
        return true
    end

    --- Take one of this resource's cards away (it goes by itself when this resource stops).
    function Whip.removeCard(t)
        _cards[t] = nil
        return Whip.call('__RemoveDirectorCard', t)
    end

    --- A Director scenario built in code: offered to the server's Director
    --- admins as a shipped one is (pending until one accepts it, unless they trust this resource), then
    --- read-only there. Sent again whenever whip_core restarts; the same scenario again changes nothing.
    ---@param key string   its key on every server
    ---@param doc table    a scenario document, as the editor saves it (format 1)
    function Whip.scenario(key, doc)
        Whip.register(function()
            local status, why = Whip.call('__RegisterDirectorScenario', key, doc)
            if status == false then print(('[%s] Director scenario %s refused: %s'):format(SELF, tostring(key), tostring(why))) end
        end)
    end

    --- A starting point in the Director editor's New list ("Bank alarm (police)"): a builder's copy is theirs.
    ---@param name string
    ---@param doc table
    function Whip.template(name, doc)
        Whip.register(function()
            local ok, why = Whip.call('__RegisterDirectorTemplate', name, doc)
            if ok ~= true then print(('[%s] Director template %s refused: %s'):format(SELF, tostring(name), tostring(why))) end
        end)
    end

    --- A thread card's answer, later (from anywhere): __AnswerDirectorCard.
    ---@param callId string  card.callId (never send it to a player's game)
    ---@param outcome string
    ---@param data table|nil  data.source: which of the run's players what follows acts for
    function Whip.answerCard(callId, outcome, data)
        return Whip.call('__AnswerDirectorCard', callId, outcome, data)
    end
end

-- ============================================
-- Skill check games (both sides): Whip.skillCheckGame
-- ============================================
--
-- A skill check game of your own, played wherever whip runs a skill check: SkillCheck(source, 'hard',
-- { game = 'phone.reroute' }) and the Director's Skill Check card (its Game field). ONE call, in a file both
-- sides load (each side reads its own fields), or one on each side with the same id:
--
--     Whip.skillCheckGame('phone.reroute', {
--         label = 'Reroute (phone)', desc = 'Turn the tiles until power reaches the exit.',
--         levels = {                                    -- server: the levels, and how each is timed
--             easy   = { minMs = 2500, timeoutMs = 47000 },   -- minMs: faster than this cannot be honest
--             medium = { minMs = 2500, timeoutMs = 57000 },   -- timeoutMs: the server gives up after this
--             hard   = { minMs = 2500, timeoutMs = 67000 },
--         },
--         canStart = function(source)                  -- server, optional: what they need to play it at all
--             if not hasPhone(source) then return false, 'You need a phone!' end
--             return true
--         end,
--         -- client, optional: the same rule, for a client script's SkillCheck({ difficulty, game }) (no source; it
--         -- must not wait: read what this game already knows, e.g. Whip.core:GetItemCount('phone') > 0)
--         run = function(difficulty, token)            -- client: play it (in a thread: it may wait)
--             return passed, why                       -- why: 'failed' | 'cancelled' | 'timeout' | 'busy'
--         end,
--         cancel = function(token) end,                -- client, optional: called off (make run return)
--     })
--
-- Someone canStart refuses is told the words, nothing starts, and the check answers false, 'not started'.
-- The id is '<yours>.<name>'. It is sent again whenever whip_core restarts; your resource stopping removes it.
do
    local _gameDefs, _gameSenders = {}, {}
    local IS_SERVER = IsDuplicityVersion()

    --- Plain data only (what may cross to whip_core).
    local function levelsOf(levels)
        local out = {}
        for name, lv in pairs(type(levels) == 'table' and levels or {}) do
            if type(name) == 'string' and type(lv) == 'table' then
                out[name] = { minMs = tonumber(lv.minMs), timeoutMs = tonumber(lv.timeoutMs) }
            end
        end
        return out
    end

    local _running = {}   -- (client) [token] = true while this game's run plays it

    --- The one function whip_core holds: it runs your code here and answers data, never an error.
    local function entryFor(id)
        return function(op, payload)
            local def = _gameDefs[id]
            if not def then return { err = id .. ' is not one of this resource\'s skill check games any more' } end
            payload = type(payload) == 'table' and payload or {}
            if op == 'canStart' then
                -- (The client's is asked by a client-side SkillCheck({ game }): no source, and it must not wait.
                -- None on this side: it may start.)
                if def.canStart == nil then return { ok = true } end
                local ok, may, words = pcall(def.canStart, IS_SERVER and payload.source or nil)
                if not ok then return { err = tostring(may) } end
                return { ok = may == true, words = type(words) == 'string' and words or nil }
            elseif not IS_SERVER and op == 'start' then
                local token = payload.token
                _running[token] = true
                CreateThread(function()
                    -- Called off before this thread began (a cancel in the same frame as the start): never shown
                    if not _running[token] then return end
                    local ok, passed, why = pcall(def.run, payload.difficulty, token)
                    if not _running[token] then return end   -- called off meanwhile: whip_core has its answer
                    _running[token] = nil
                    if not ok then
                        print(('[%s] skill check game %s failed: %s'):format(SELF, id, tostring(passed)))
                        passed, why = false, 'failed'
                    end
                    Whip.call('__SkillCheckGameDone', token, passed == true, type(why) == 'string' and why or nil)
                end)
                return { ok = true }
            elseif not IS_SERVER and op == 'cancel' then
                if _running[payload.token] then
                    _running[payload.token] = nil
                    if type(def.cancel) == 'function' then
                        local ok, err = pcall(def.cancel, payload.token)
                        if not ok then print(('[%s] skill check game %s cancel failed: %s'):format(SELF, id, tostring(err))) end
                    end
                end
                return {}
            end
            return { err = 'whip_core asked for "' .. tostring(op) .. '", which this helper does not know (update it)' }
        end
    end

    --- Add (or change) a skill check game of this resource's. See above.
    ---@param id string   '<your namespace>.<name>'
    ---@param def table
    ---@return boolean ok  false when it is not a game (printed); whip_core's own answer is printed too
    function Whip.skillCheckGame(id, def)
        if type(id) ~= 'string' or type(def) ~= 'table' then
            print(('[%s] Whip.skillCheckGame(id, def): an id ("phone.reroute") and a table'):format(SELF))
            return false
        end
        if IS_SERVER and type(def.levels) ~= 'table' then
            print(('[%s] skill check game %s: levels = { easy = { minMs, timeoutMs }, ... }'):format(SELF, id))
            return false
        end
        if not IS_SERVER and type(def.run) ~= 'function' then
            print(('[%s] skill check game %s: it needs run = function(difficulty, token) ... end'):format(SELF, id))
            return false
        end
        _gameDefs[id] = def
        if _gameSenders[id] then
            if _heard then runAll({ _gameSenders[id] }, 'Whip.skillCheckGame') end
            return true
        end
        local entry = entryFor(id)
        _gameSenders[id] = function()
            local now = _gameDefs[id]
            if not now then return end   -- (removed since)
            local ok, why
            if IS_SERVER then
                ok, why = Whip.call('__RegisterSkillCheckGame', id, {
                    label = now.label, desc = now.desc, levels = levelsOf(now.levels),
                    canStart = type(now.canStart) == 'function' or nil,
                }, entry)
            else
                ok, why = Whip.call('__RegisterSkillCheckGame', id, entry)
            end
            if ok ~= true then print(('[%s] skill check game %s refused: %s'):format(SELF, id, tostring(why))) end
        end
        Whip.register(_gameSenders[id])
        return true
    end

    --- Take one of this resource's games away (they go by themselves when this resource stops).
    function Whip.removeSkillCheckGame(id)
        _gameDefs[id] = nil
        return Whip.call('__RemoveSkillCheckGame', id)
    end
end

-- ============================================
-- Director tasks (both sides): Whip.task
-- ============================================
--
-- A task of your own in the Tasks list of the Director's NPCs and cars. ONE call, in a file both sides load
-- (shared_scripts, or the same file in server_scripts and client_scripts):
--
--     Whip.task('autos.flash', {
--         label = 'Flash the Lights', group = 'car', kinds = { 'vehicle' }, timing = 'timed', sec = 4,
--         fields = { { key = 'times', kind = 'number', label = 'Times', min = 1, max = 20, default = 5 } },
--         run = function(car, args, info)       -- on the game that owns the car, in a thread (it may wait)
--             for _ = 1, args.times do SetVehicleLights(car, 2) Wait(200) SetVehicleLights(car, 1) Wait(200) end
--             SetVehicleLights(car, 0)
--         end,
--     })
--
-- The server sends the type as data; each game keeps the code. The type is '<your namespace>.<name>', the namespace
-- yours as your cards' are. Called again, it changes the task. A refusal is printed here, with why.
--
-- label (40); desc (160, under it in the picker); group: one of the Director's (move, look, fight, act, car, body,
-- wait) or your own, groupTitle its name in the picker; kinds: npc, vehicle (a prop's tasks are whip_core's only);
-- timing: 'instant' (done once run has started), 'timed' (sec seconds: 3 unless given), 'until' (until it is done,
-- giving up after giveUp seconds: 30), 'either' (the builder picks: next = 'done' | 'time'); lasting = true (it keeps
-- going after its slot: a Wait after it keeps the thing at it), once = true (never played again by a new owner: it
-- would happen twice), standing = false (a standing NPC passes it over: it needs a run).
-- fields (8 at most), each { key, kind, label, hint?, default?, required? }, kind one of:
--   number (min, max; slider = true with step, unit: drawn as a slider) · bool · select (1-200 options; look = 'seg':
--   2-4 of them as a row of buttons) · text (max)
--   world (worldKind?: one of the scenario's placed things) · point (key 'at': a place the world builder puts down)
--   target (key 'target'; options of nearest, trigger, thing, point: who or what it points at)
--
-- run(entity, args, info) plays the step on the game that owns the thing (and on the world builder's copy, for its
-- Play here: info.preview). args: each field's value; a world field is that thing's entity on this game (nil when it
-- is not here), a target { kind, entity, coords }, a point { x, y, z, heading }. info: { type, kind, timing, ms (how
-- long the step has), preview }. An 'until' step is done when run returns (false, or an error: failed), unless you
-- give done(entity, args): asked each quarter second, true is done, 'failed' failed, anything else not yet.
-- A new owner of the thing runs a timed or lasting step again from its start, so keep run to what the entity does.
do
    local _tasks, _taskSenders = {}, {}
    local _calls = {}           -- [call] = { at, finished, failed }: steps this game's code was handed (client)
    local KEEP_MS = 600000

    --- Plain data only (what may cross to whip_core): 8 deep, no functions.
    local function plainCopy(v, depth)
        local t = type(v)
        if t == 'string' or t == 'number' or t == 'boolean' then return v end
        if t ~= 'table' then return nil end
        depth = (depth or 0) + 1
        if depth > 8 then return nil end
        local out = {}
        for k, x in pairs(v) do
            if type(k) == 'string' or type(k) == 'number' then out[k] = plainCopy(x, depth) end
        end
        return out
    end

    --- The task as data (what the server checks and the editor draws).
    local function taskSpec(def)
        local fields = {}
        for i, f in ipairs(type(def.fields) == 'table' and def.fields or {}) do
            fields[i] = plainCopy({ key = f.key, kind = f.kind, label = f.label, hint = f.hint, unit = f.unit, default = f.default,
                                    required = f.required, min = f.min, max = f.max, step = f.step, options = f.options,
                                    worldKind = f.worldKind })
        end
        return { __whipTask = 1, label = def.label, desc = def.desc, group = def.group, groupTitle = def.groupTitle,
                 kinds = plainCopy(def.kinds), timing = def.timing, sec = def.sec, giveUp = def.giveUp, next = def.next,
                 lasting = def.lasting, once = def.once, standing = def.standing, fields = fields }
    end

    --- The one function whip_core holds on a game: it plays your step here and answers data, never an error.
    local function stepEntry(t)
        return function(op, payload)
            local def = _tasks[t]
            if not def then return { err = t .. ' is not one of this resource\'s tasks any more' } end
            payload = type(payload) == 'table' and payload or {}
            if op == 'run' then
                local now = GetGameTimer()
                for k, c in pairs(_calls) do if now - c.at > KEEP_MS then _calls[k] = nil end end
                local c = { at = now }
                if payload.call ~= nil then _calls[payload.call] = c end
                CreateThread(function()
                    local ok, res = pcall(def.run, payload.entity, payload.args or {}, payload.info or {})
                    if not ok then
                        c.failed = true
                        print(('[%s] Director task %s failed: %s'):format(SELF, t, tostring(res)))
                    elseif res == false then
                        c.failed = true
                    else
                        c.finished = true
                    end
                end)
                return {}
            elseif op == 'done' then
                local c = _calls[payload.call]
                if c and c.failed then return { how = 'failed' } end
                if type(def.done) == 'function' then
                    local ok, res = pcall(def.done, payload.entity, payload.args or {})
                    if not ok then
                        print(('[%s] Director task %s: its done failed: %s'):format(SELF, t, tostring(res)))
                        return { how = 'failed' }
                    end
                    if res == true then return { how = 'done' } end
                    if res == 'failed' then return { how = 'failed' } end
                    return {}
                end
                if not c then return { how = 'failed' } end
                return c.finished and { how = 'done' } or {}
            end
            return { err = 'whip_core asked for "' .. tostring(op) .. '", which this helper does not know (update it)' }
        end
    end

    --- Add (or change) a Director task of this resource's, on this side. See the top of this section.
    ---@param t string    '<your namespace>.<name>'
    ---@param def table
    ---@return boolean ok  false when it is not a task (printed); whip_core's own answer is printed too
    function Whip.task(t, def)
        if type(t) ~= 'string' or type(def) ~= 'table' then
            print(('[%s] Whip.task(type, def): a type ("autos.paint") and a table'):format(SELF))
            return false
        end
        if type(def.run) ~= 'function' then
            print(('[%s] Director task %s: it needs run = function(entity, args, info) ... end'):format(SELF, t))
            return false
        end
        if def.done ~= nil and type(def.done) ~= 'function' then
            print(('[%s] Director task %s: done is a function, or left out'):format(SELF, t))
            return false
        end
        _tasks[t] = def
        -- ONE sender a type, however many times it is called: it sends the task as it is now, at every whip_core
        -- start, and now when whip_core is up.
        if _taskSenders[t] then
            if _heard then runAll({ _taskSenders[t] }, 'Whip.task') end
            return true
        end
        local send
        if IsDuplicityVersion() then
            send = function()
                local now = _tasks[t]
                if not now then return end   -- (removed since)
                local ok, why = Whip.call('__RegisterDirectorTask', t, taskSpec(now))
                if ok ~= true then print(('[%s] Director task %s refused: %s'):format(SELF, t, tostring(why))) end
            end
        else
            local entry = stepEntry(t)
            send = function()
                if not _tasks[t] then return end
                local ok, why = Whip.call('__RegisterDirectorTaskStep', t, entry)
                if ok ~= true then print(('[%s] Director task %s (its step) refused: %s'):format(SELF, t, tostring(why))) end
            end
        end
        _taskSenders[t] = send
        Whip.register(send)
        return true
    end

    --- Take one of this resource's tasks away, on this side (it goes by itself when this resource stops).
    function Whip.removeTask(t)
        _tasks[t] = nil
        return Whip.call(IsDuplicityVersion() and '__RemoveDirectorTask' or '__RemoveDirectorTaskStep', t)
    end
end

-- ============================================
-- Weapons of your own (both sides): Whip.weapons
-- ============================================
--
-- Add-on weapons your resource streams (its own WEAPON_* in its weapons.meta), offered beside GTA's wherever whip lists
-- weapons: the Director's NPC weapons and its Hold a Weapon step, its Fixed Weapons (a firearm with a world model),
-- Dungeon Mode, the Object Viewer's Give a weapon. ONE call, in a file both sides load:
--
--     Whip.weapons({
--         { name = 'WEAPON_MY_PUMP', label = 'Pump Shotgun', group = 'shotgun', model = 'w_sg_my_pump' },
--         { name = 'WEAPON_MY_KNIFE', label = 'Knife', group = 'melee' },
--     }, { tag = 'mine' })
--
-- name: WEAPON_ and capitals, digits or _ (64), never one of GTA's. label (40). group: pistol, smg, rifle, machine gun,
-- shotgun, sniper, heavy, thrown, stun gun or melee. model: its world model, a firearm's only; with one it can be a
-- Fixed Weapon. tag (16): shown beside each label, "Pump Shotgun (mine)"; your resource's name unless given.
-- Called again, the new list replaces the old. They go when your resource stops. A refusal is printed here, with why.
-- An NPC given one carries the gun itself, never your item: your own ammo and reload code is not on it.
do
    local _weapons, _weaponSender

    ---@param list table
    ---@param opts table|nil  { tag }
    ---@return boolean ok  false when it is not a list (printed); whip_core's own answer is printed too
    function Whip.weapons(list, opts)
        if type(list) ~= 'table' then
            print(('[%s] Whip.weapons(list, opts): a list of { name, label, group, model }'):format(SELF))
            return false
        end
        _weapons = { list = list, opts = opts }
        if _weaponSender then
            if _heard then runAll({ _weaponSender }, 'Whip.weapons') end
            return true
        end
        _weaponSender = function()
            if not _weapons then return end
            local ok, why = Whip.call('__AddWeapons', _weapons.list, _weapons.opts)
            if ok ~= true then print(('[%s] Whip.weapons refused: %s'):format(SELF, tostring(why))) end
        end
        Whip.register(_weaponSender)
        return true
    end

    --- Take all of this resource's weapons away, on this side (they go by themselves when it stops).
    function Whip.removeWeapons()
        _weapons = nil
        return Whip.call('__RemoveWeapons')
    end
end

-- ============================================
-- Director buttons (client side): Whip.directorButton
-- ============================================
--
-- A button of your own for a kind of placed thing, on its page in the Director (and the world builder's Configure
-- panel), in the world builder's bubble beside the selected thing, or both. Never a button on the screen by itself.
--
--     Whip.directorButton('autos.customise', {
--         label = 'Customise', icon = 'turbo', kinds = { 'vehicle' },
--         where = 'both',               -- 'page' (its page), 'bubble' (beside it in the world builder), or 'both'
--         takesOver = true,             -- the Director steps aside until thing:back()
--         press = function(thing)       -- here, in a thread of its own (it may wait)
--             ...                       -- your own screen, on a car of your own at thing.coords
--             thing:back({ paint = 27 })   -- the Director again, this kept on the car first
--         end,
--     })
--
-- thing: { id, kind, label, model, coords = { x, y, z, heading }, scenario, data, entity, builder }. data is what you
-- keep on it; entity the world builder's copy while it is open (never for a button that takes over: the builder
-- has handed it back by then); builder whether it was pressed in the world builder.
-- kinds = { 'card' }: a button for your card's list (an entries field, button = its id), pressed on the card's page
-- to add an entry or change one. Its thing is the card: card = { type, field, entry (nil: a new one), value (that
-- entry), props, world (the card's placed things by field: { id, kind, label, model, models, coords }) };
-- thing:save(t) keeps t as that entry (nil takes it out).
-- thing:save(t) keeps t on the thing (plain data, 4 KB of JSON at most; nil takes it away): an edit of the open
-- scenario, saved and undone like any other. A run hands it to your server side for the thing:
-- whip_core:run:thingMade's data[<your resource>], card:made(id).data, GetDirectorThingData(runId or key, id).
-- hint (120) is its tooltip. The id is '<your namespace>.<name>'. Called again, it changes the button.
if not IsDuplicityVersion() then
    local _buttons, _buttonSenders = {}, {}

    local thingMethods = {}
    function thingMethods.save(self, data) return Whip.call('__DirectorButtonDo', rawget(self, 'token'), 'save', data) end
    function thingMethods.back(self, data) return Whip.call('__DirectorButtonDo', rawget(self, 'token'), 'back', data) end
    local thingMeta = { __index = thingMethods }

    --- The one function whip_core holds: it runs your press here, in a thread, and answers at once.
    local function buttonEntry(id)
        return function(op, payload)
            local def = _buttons[id]
            if not def then return { err = id .. ' is not one of this resource\'s buttons any more' } end
            if op ~= 'press' then return { err = 'whip_core asked for "' .. tostring(op) .. '", which this helper does not know (update it)' } end
            payload = type(payload) == 'table' and payload or {}
            local thing = setmetatable(type(payload.thing) == 'table' and payload.thing or {}, thingMeta)
            rawset(thing, 'token', payload.token)
            CreateThread(function()
                local ok, err = pcall(def.press, thing)
                if not ok then
                    print(('[%s] Director button %s failed: %s'):format(SELF, id, tostring(err)))
                    -- (The Director must not stay out of the way for a press that is over.)
                    if def.takesOver then thing:back() end
                end
            end)
            return {}
        end
    end

    --- Add (or change) a Director button of this resource's. See the top of this section.
    ---@param id string   '<your namespace>.<name>'
    ---@param def table
    ---@return boolean ok
    function Whip.directorButton(id, def)
        if type(id) ~= 'string' or type(def) ~= 'table' then
            print(('[%s] Whip.directorButton(id, def): an id ("autos.customise") and a table'):format(SELF))
            return false
        end
        if type(def.press) ~= 'function' then
            print(('[%s] Director button %s: it needs press = function(thing) ... end'):format(SELF, id))
            return false
        end
        _buttons[id] = def
        if _buttonSenders[id] then
            if _heard then runAll({ _buttonSenders[id] }, 'Whip.directorButton') end
            return true
        end
        local entry = buttonEntry(id)
        _buttonSenders[id] = function()
            local now = _buttons[id]
            if not now then return end
            local kinds = {}
            for i, k in ipairs(type(now.kinds) == 'table' and now.kinds or {}) do kinds[i] = k end
            local spec = { __whipButton = 1, label = now.label, icon = now.icon, hint = now.hint, kinds = kinds,
                           where = now.where, takesOver = now.takesOver == true }
            local ok, why = Whip.call('__RegisterDirectorButton', id, spec, entry)
            if ok ~= true then print(('[%s] Director button %s refused: %s'):format(SELF, id, tostring(why))) end
        end
        Whip.register(_buttonSenders[id])
        return true
    end

    --- Take one of this resource's buttons away (it goes by itself when this resource stops).
    function Whip.removeDirectorButton(id)
        _buttons[id] = nil
        return Whip.call('__RemoveDirectorButton', id)
    end
end

-- ============================================
-- Object viewer options (client side): Whip.objectViewerOption
-- ============================================
--
-- An option of your own in the object viewer's list (the /w dev tool: G on what it has picked out opens its options
-- down the right of the screen). Shown for the kinds you name, and only for whip's own (whip = true: a saved car, a
-- player) or only for the game's (whip = false: a street car, an NPC walking by), or both (left out).
--
--     Whip.objectViewerOption('autos.whiplash', {
--         label = 'Open Whiplash', group = 'Whiplash', tint = 'violet',   -- the list's heading, and its colour
--         hint = 'Takes the driver\'s seat and opens the shop on this car.',  -- the line under the list (160)
--         kinds = { 'vehicle' },        -- any of: vehicle, player, npc, object
--         whip = true,
--         select = function(target)     -- here, in a thread of its own (it may wait); the list has closed
--             ...
--         end,
--     })
--
-- target: { kind, entity, netId, whip, vehicleId, serverId, model, name, coords = { x, y, z, heading } }. The id is
-- '<your namespace>.<name>'; tint is blue, teal, green, amber, red, violet or slate. Called again, it changes the
-- option; it goes by itself when your resource stops. Shown to someone with dev tools on, and to a Dungeon Master in
-- Dungeon Mode (director.live: Josh, 1 Nov), so anything your select does on the server checks for itself (HasDevTools,
-- or the permission it needs).
if not IsDuplicityVersion() then
    local _options, _optionSenders = {}, {}

    local function optionEntry(id)
        return function(op, payload)
            local def = _options[id]
            if not def then return { err = id .. ' is not one of this resource\'s options any more' } end
            if op ~= 'select' then return { err = 'whip_core asked for "' .. tostring(op) .. '", which this helper does not know (update it)' } end
            local target = type(payload) == 'table' and type(payload.target) == 'table' and payload.target or {}
            CreateThread(function()
                local ok, err = pcall(def.select, target)
                if not ok then print(('[%s] object viewer option %s failed: %s'):format(SELF, id, tostring(err))) end
            end)
            return {}
        end
    end

    --- Add (or change) an object viewer option of this resource's. See the top of this section.
    ---@param id string   '<your namespace>.<name>'
    ---@param def table
    ---@return boolean ok
    function Whip.objectViewerOption(id, def)
        if type(id) ~= 'string' or type(def) ~= 'table' then
            print(('[%s] Whip.objectViewerOption(id, def): an id ("autos.whiplash") and a table'):format(SELF))
            return false
        end
        if type(def.select) ~= 'function' then
            print(('[%s] object viewer option %s: it needs select = function(target) ... end'):format(SELF, id))
            return false
        end
        _options[id] = def
        if _optionSenders[id] then
            if _heard then runAll({ _optionSenders[id] }, 'Whip.objectViewerOption') end
            return true
        end
        local entry = optionEntry(id)
        _optionSenders[id] = function()
            local now = _options[id]
            if not now then return end
            local kinds = {}
            for i, k in ipairs(type(now.kinds) == 'table' and now.kinds or {}) do kinds[i] = k end
            local spec = { __whipOvOption = 1, label = now.label, hint = now.hint, group = now.group, tint = now.tint,
                           kinds = kinds, whip = now.whip }
            local ok, why = Whip.call('__RegisterObjectViewerOption', id, spec, entry)
            if ok ~= true then print(('[%s] object viewer option %s refused: %s'):format(SELF, id, tostring(why))) end
        end
        Whip.register(_optionSenders[id])
        return true
    end

    --- Take one of this resource's options away (it goes by itself when this resource stops).
    function Whip.removeObjectViewerOption(id)
        _options[id] = nil
        return Whip.call('__RemoveObjectViewerOption', id)
    end
end

-- ============================================
-- /whipcost: how much memory this resource makes
-- ============================================
--
-- whip_core's /whipcost (tools/whipcost.lua) prints how much memory every whip resource makes a second while it runs:
-- what Lua's collector has to clear after it. A satellite that times loops of its own loads lib/cost.lua, which
-- answers for it, sections and all; any other gets its whole-resource figure from here, measured the same way: the
-- collector paused for the run, so the count only goes up (should it come down anyway, the figure is at least that).
if not IsDuplicityVersion() then
    local CAP_KB = 32 * 1024    -- this much more and the collector runs again, and the counting stops (as lib/cost.lua)
    local measuring = nil       -- { from, at, last, giveUpAt, gc, capped, made, seconds } while it runs

    -- EVERY LOOP: what one pass makes, filed under the function its thread started with. lib/cost.lua's twin (its
    -- "EVERY LOOP" block says how): kept the same in both.
    ---@type table|nil, function|nil, function|nil
    local loops, nativeWait, nativeThread = nil, nil, nil
    local SELF_ROW = '(/whipcost itself: naming the loops)'
    local wokeAt = setmetatable({}, { __mode = 'k' })
    local loopOf = setmetatable({}, { __mode = 'k' })
    local WRAPPERS = { 'error_tap.lua', 'lib/satellite.lua', 'lib/cost.lua', 'scheduler.lua' }
    local function loopName()
        local name, wrapped
        local level = 3
        while true do
            local info = debug.getinfo(level, 'S')
            if not info then break end
            if info.what ~= 'C' then
                local src, isWrapper = info.short_src, false
                for _, w in ipairs(WRAPPERS) do
                    if src:find(w, 1, true) then isWrapper = true break end
                end
                if isWrapper then wrapped = wrapped or (src .. ':' .. info.linedefined)
                else name = src .. ':' .. info.linedefined end
            end
            level = level + 1
        end
        return name or wrapped or '?'
    end
    local function file(list, name, made, kb)
        local e = list[name]
        if not e then
            e = { n = 0, kb = 0.0 }
            list[name] = e
        end
        e.n = e.n + 1
        if made > 0 then e.kb = e.kb + made end
        local own = list[SELF_ROW]
        own.kb = own.kb + math.max(0, collectgarbage('count') - kb)
    end
    local function countedWait(ms)
        local co = coroutine.running()
        local list = loops
        if co and list then
            local kb = collectgarbage('count')
            local from = wokeAt[co]
            if from then
                local name = loopOf[co]
                if not name then
                    name = loopName()
                    loopOf[co] = name
                end
                file(list, name, kb - from, kb)
            end
        end
        -- nativeWait is nil once counting stops; a countedWait kept from before (`local wait = Wait`) then waits with
        -- the real Wait, which is back by then.
        local wait = nativeWait or Wait
        wait(ms)
        if co and loops then wokeAt[co] = collectgarbage('count') end
    end
    local function threadEnded(co, fn, ...)
        local list, from = loops, wokeAt[co]
        if list and from then
            local kb = collectgarbage('count')
            local name = loopOf[co]
            if not name then
                local info = debug.getinfo(fn, 'S')
                name = info.short_src .. ':' .. info.linedefined
            end
            file(list, name, kb - from, kb)
        end
        return ...
    end
    local function countedThread(fn)
        ---@type function   (a counted thread passes its function's answers on)
        local spawn = nativeThread or CreateThread   -- (as in countedWait: the real one is back once counting stops)
        if type(fn) ~= 'function' or not loops then return spawn(fn) end
        return spawn(function(...)
            local co = coroutine.running()
            if loops then wokeAt[co] = collectgarbage('count') end
            return threadEnded(co, fn, fn(...))
        end)
    end
    local function countLoops(on)
        if on and not nativeWait then
            nativeWait, nativeThread, loops = Wait, CreateThread, { [SELF_ROW] = { n = 0, kb = 0.0 } }
            Wait, CreateThread = countedWait, countedThread
        elseif not on and nativeWait then
            Wait, CreateThread = nativeWait, nativeThread
            nativeWait, nativeThread = nil, nil
        end
    end

    AddEventHandler('whip_core:cost:started', function(info)
        costAsked = {}                -- what it is asked to run (above), whichever file counts the rest
        if WhipCost then return end   -- lib/cost.lua answers for this resource
        collectgarbage('stop')
        local m = { from = collectgarbage('count'), at = GetGameTimer() }
        m.last = m.from
        -- No stop by then (whip_core went in the middle of it): the collector runs again
        m.giveUpAt = m.at + ((tonumber(type(info) == 'table' and info.seconds) or 120) + 10) * 1000
        measuring = m
        countLoops(true)
        CreateThread(function()
            while measuring == m and not m.capped do
                Wait(250)
                if measuring ~= m then break end
                if GetGameTimer() > m.giveUpAt then
                    measuring = nil
                    countLoops(false)
                    collectgarbage('restart')
                    break
                end
                local now = collectgarbage('count')
                if now < m.last then m.gc = true end
                m.last = now
                if now - m.from > CAP_KB then
                    m.capped, m.made, m.seconds = true, now - m.from, (GetGameTimer() - m.at) / 1000
                    collectgarbage('restart')
                end
            end
        end)
    end)

    AddEventHandler('whip_core:cost:stopped', function()
        local asked = costAsked
        costAsked = nil
        local m = measuring
        if not m then
            -- lib/cost.lua reported the rest of this resource: what it was asked goes on its own
            if asked then TriggerEvent('whip_core:cost:askedReported', { resource = SELF, asked = asked }) end
            return
        end
        measuring = nil
        if not m.capped then
            m.made, m.seconds = collectgarbage('count') - m.from, (GetGameTimer() - m.at) / 1000
            collectgarbage('restart')
        end
        local counted = loops
        countLoops(false)
        loops = nil
        TriggerEvent('whip_core:cost:reported', {
            resource = SELF, ms = {}, runs = {}, loops = counted, asked = asked,
            memory = { kb = m.made, seconds = m.seconds, gc = m.gc == true, capped = m.capped == true },
        })
    end)
end

AddEventHandler('whip_core:onReady', function(info)
    if not concernsUs(info) then return end
    _heard = true
    if #_registerFns > 0 then runAll(_registerFns, 'Whip.register') end
    if _sayStarted then
        if _startProblems == 0 then print(('%s started successfully!'):format(SELF)) end
        _startProblems = 0
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= CORE then return end
    _heard = false
    -- Every Whip.call still waiting answers now (see Whip.call); whip_core never will.
    local waiting = _waiting
    _waiting = {}
    for p in pairs(waiting) do
        p:resolve(table.pack(true, false, 'whip_core stopped'))
    end
    if #_lostFns == 0 then return end
    runAll(_lostFns, 'Whip.onCoreLost')
end)
