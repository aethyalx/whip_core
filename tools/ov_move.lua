-- ============================================
-- Dev Tools — the Object Viewer's Move
-- ============================================
--
-- Move (tools/ov_panel.lua) puts the furnisher's arrows and rings on the one thing, and nothing else of the
-- furnisher: no free camera, no catalog. You stay where you are, with the game's own camera:
--
--   mouse    the cursor drags the arrows (along X, Y, Z), the rings (R swaps to them: tilt and turn) and the centre
--            dot (it follows the pointer over the ground). Right mouse held looks round; WASD still walks.
--   pad      LS moves it across the ground the way the camera faces, LT / RT down and up, D-pad left / right turns it,
--            RS looks round, B is done.
--   Esc / B  done: back to its options.
--
-- The markers are the furnisher's own (html/js/furnisher-gizmo.js, borrowed through FurnishGizmo.route by
-- js/ov-panel.js) and so is the maths that aims a click into the world (client/furnish_view.lua).
--
-- WHO MOVES IT. A car, an NPC or a prop: this game, holding control of it (and holding it still while it is moved,
-- so it stays where it is put). A player: their own game owns their ped, so the server moves it
-- (whip_core:server:ovMovePlayer), about ten times a second while dragged and once more when let go.

OvMove = {}

---@class OvMoveState
---@field target table
---@field entity integer
---@field kind string
---@field tilt boolean
---@field onExit function|nil
---@field looking boolean
---@field pad boolean|nil
---@field hidden boolean|nil
---@field kScale number[]|nil
---@field lastCam number[]|nil
---@field calAt integer
---@field sent number[]|nil
---@field want number[]|nil
---@field sentAt integer

---@type OvMoveState|nil
local mv = nil   -- the move on: { target, entity, kind, tilt, onExit, looking, pad, k, kScale, sent, want, sentAt }
-- What reads it below runs only while a move is on (the ways in check it)
---@cast mv -nil

local SEND_MS = 100        -- a player's ped, to the server, at most this often
local PAD_SPEED = 3.0      -- metres a second at a full push
local PAD_TURN = 90.0      -- degrees a second
local DRAG_REACH = 300.0
local CALIBRATE_MS = 500

local HOLD = { groups = { 'combat', 'weaponWheel' }, controls = { 199, 200, 37, 44, 45, 140, 141, 142 } }
local HOLD_PAD = { groups = { 'move' } }   -- (a pad's LS moves the thing, not the player)
local HOLD_LOOK = { groups = { 'look' } }  -- (the mouse looks only while the right button is down)

local function near(a, b) return math.abs(a - b) < 1e-4 end

--- Is it this game's to move now? One only this game has (a prop set's copy, the map's own) always is.
local function mine(ent) return not NetworkGetEntityIsNetworked(ent) or NetworkHasControlOfEntity(ent) end

local control = Vehicles.takeEntityControl

--- The view's two numbers: the camera's FOV, put right by the engine's own answer while it holds still.
local function viewK()
    local kx, ky = FurnishView.kFromFov(GetFinalRenderedCamFov(), GetAspectRatio(false))
    if mv and mv.kScale then return kx * mv.kScale[1], ky * mv.kScale[2] end
    return kx, ky
end

--- Put it there: this game for a car, an NPC or a prop; the server for a player (sent at most every SEND_MS).
local function place(x, y, z, rx, ry, rz, final)
    local ent = mv.entity
    if mv.kind == 'player' then
        mv.want = { x, y, z, rz }
        local now = GetGameTimer()
        if final or now - mv.sentAt >= SEND_MS then
            mv.sentAt = now
            TriggerServerEvent('whip_core:server:ovMovePlayer', mv.target.sid, x, y, z, rz)
            mv.want = nil
        end
        return
    end
    if not mine(ent) then NetworkRequestControlOfEntity(ent) return end
    SetEntityCoordsNoOffset(ent, x, y, z, false, false, false)
    if mv.tilt then SetEntityRotation(ent, rx, ry, rz, 2, true) else SetEntityHeading(ent, rz % 360.0) end
end

local function pushView()
    local c, rot = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local now = GetGameTimer()
    -- Asked of the engine only while the camera holds still (furnisher's rule): kept as a share of the FOV's
    -- answer, so a zoom (aiming, a car's camera) still comes out right.
    local still = mv.lastCam and near(mv.lastCam[1], c.x) and near(mv.lastCam[2], c.y) and near(mv.lastCam[3], c.z)
        and near(mv.lastCam[4], rot.x) and near(mv.lastCam[5], rot.z)
    mv.lastCam = { c.x, c.y, c.z, rot.x, rot.z }
    if still and now - mv.calAt >= CALIBRATE_MS then
        mv.calAt = now
        local kx, ky = FurnishView.calibrate(c.x, c.y, c.z, rot.x, rot.z, GetScreenCoordFromWorldCoord)
        local fx, fy = FurnishView.kFromFov(GetFinalRenderedCamFov(), GetAspectRatio(false))
        if kx and ky and fx > 0 and fy > 0 then mv.kScale = { kx / fx, ky / fy } end
    end
    local kx, ky = viewK()
    local p, r = GetEntityCoords(mv.entity), GetEntityRotation(mv.entity, 2)
    local v = { c.x, c.y, c.z, rot.x, rot.z, kx, ky, p.x, p.y, p.z, r.x, r.y, r.z }
    if mv.sent then
        local moved = false
        for i = 1, #v do
            if not near(v[i], mv.sent[i]) then moved = true break end
        end
        if not moved then return end
    end
    mv.sent = v
    SendNUIMessage({ action = 'ovMoveView', c = { c.x, c.y, c.z }, r = { rot.x, rot.z }, k = { kx, ky },
                     o = { p.x, p.y, p.z, r.x, r.y, r.z }, i = 1, t = mv.tilt })
end

--- The right button: the cursor goes and the camera looks while it is down.
local function setLooking(on)
    mv.looking = on
    Focus.mouseLook('ovMove', on)
    if on then ControlBlocks.release('ovMoveLook') else ControlBlocks.hold('ovMoveLook', HOLD_LOOK) end
    SendNUIMessage({ action = 'ovMoveLook', on = on })
end

local function setPad(pad)
    mv.pad = pad
    if pad then
        ControlBlocks.hold('ovMovePad', HOLD_PAD)
        ControlBlocks.release('ovMoveLook')   -- RS looks
        if mv.looking then setLooking(false) ControlBlocks.release('ovMoveLook') end
    else
        ControlBlocks.release('ovMovePad')
        if not mv.looking then ControlBlocks.hold('ovMoveLook', HOLD_LOOK) end
    end
    SendNUIMessage({ action = 'ovMovePad', pad = pad })
end

--- The pad's own way: LS across the ground the way the camera faces, LT / RT down and up, D-pad left / right turns.
local function padFrame()
    local lx, ly = GetDisabledControlNormal(0, 30), GetDisabledControlNormal(0, 31)
    local up = WhipPadTrigger('rt', 0.0) - WhipPadTrigger('lt', 0.0)   -- the 0.1 below is its rest
    local turn = (IsDisabledControlPressed(0, 190) and 1 or 0) - (IsDisabledControlPressed(0, 189) and 1 or 0)
    if math.abs(lx) < 0.15 then lx = 0.0 end
    if math.abs(ly) < 0.15 then ly = 0.0 end
    if math.abs(up) < 0.1 then up = 0.0 end
    if lx == 0.0 and ly == 0.0 and up == 0.0 and turn == 0 then
        if mv.want then place(mv.want[1], mv.want[2], mv.want[3], 0.0, 0.0, mv.want[4], true) end
        return
    end
    local dt = GetFrameTime()
    local yaw = math.rad(GetFinalRenderedCamRot(2).z)
    local fx, fy, rx, ry = -math.sin(yaw), math.cos(yaw), math.cos(yaw), math.sin(yaw)
    local step = PAD_SPEED * dt
    local base = mv.want or nil
    local p, r = GetEntityCoords(mv.entity), GetEntityRotation(mv.entity, 2)
    local x, y, z, h = p.x, p.y, p.z, r.z
    if base then x, y, z, h = base[1], base[2], base[3], base[4] end
    x = x + (rx * lx - fx * ly) * step
    y = y + (ry * lx - fy * ly) * step
    z = z + up * step
    h = h - turn * PAD_TURN * dt
    place(x, y, z, r.x, r.y, h)
end

local function stop()
    if not mv then return end
    local m = mv
    if m.kind == 'player' and m.want then place(m.want[1], m.want[2], m.want[3], 0.0, 0.0, m.want[4], true) end
    mv = nil
    ControlBlocks.release('ovMove')
    ControlBlocks.release('ovMoveLook')
    ControlBlocks.release('ovMovePad')
    Focus.release('ovMove')
    SendNUIMessage({ action = 'ovMoveStop' })
    -- Let go of it where it was put, unless an admin holds it frozen (client/ov_effects.lua keeps that). One only this
    -- game has stays frozen: it stood still before (a prop set's copy, a ground item), and the server is told where it
    -- went (`onPlaced`: its set is shown there again for everyone).
    if m.kind ~= 'player' and DoesEntityExist(m.entity) then
        if NetworkGetEntityIsNetworked(m.entity) and NetworkHasControlOfEntity(m.entity) then
            local mask = Entity(m.entity).state[ENTITY_OV_HOLD_KEY]
            if not (type(mask) == 'number' and mask & 4 ~= 0) then FreezeEntityPosition(m.entity, false) end
        end
        if m.target.onPlaced then
            local p, r = GetEntityCoords(m.entity), GetEntityRotation(m.entity, 2)
            local ok, err = pcall(m.target.onPlaced, p.x, p.y, p.z, r.x, r.y, r.z)
            if not ok then print('[whip_core:objectviewer] telling where it went failed: ' .. tostring(err)) end
        end
    end
    if m.onExit then
        local ok, err = pcall(m.onExit)
        if not ok then print('[whip_core:objectviewer] back from Move failed: ' .. tostring(err)) end
    end
end

--- Start moving `target` (the panel's: entity, kind, sid, name; `onPlaced(x, y, z, rx, ry, rz)`: where it was left, for
--- one only this game has). `onExit` runs when it is done. A caller whose Done means more than Esc (the hand editor's
--- save) gives `target.onDone`: the Done button runs that instead of ending Move, and the caller ends it
--- (OvMove.stop). The bar is the caller's to word too: `target.doneText` (the button), `target.caption` (the line
--- over the name, 'Moving' when not given) and `target.keys`, { { key, text }, ... }, in place of Move's own keys.
---@return boolean ok
---@return string|nil why
function OvMove.start(target, onExit)
    if mv then return false, 'Something is being moved already' end
    if FurnishModeActive then return false, 'The furnisher has the markers: close it first' end
    local ent = target and target.entity
    if not ent or not DoesEntityExist(ent) then return false, 'It is not there any more' end
    if target.kind == 'player' then
        if not target.sid then return false, 'Could not tell which player that is' end
    else
        local ok, why = control(ent)
        if not ok then return false, 'Could not take hold of it: ' .. tostring(why) end
        FreezeEntityPosition(ent, true)
    end
    mv = { target = target, entity = ent, kind = target.kind, onExit = onExit, sentAt = 0, calAt = 0,
           -- A ped stands up: it turns, it does not tilt. A car or a prop takes all three rings, unless the caller says
           -- (target.tilt = false: a point placed with a heading, tools/place_point.lua).
           tilt = target.tilt ~= false and (target.kind == 'vehicle' or target.kind == 'object'), looking = false }
    Focus.take('ovMove', { screen = true, keepInput = true })
    ControlBlocks.hold('ovMove', HOLD)
    ControlBlocks.hold('ovMoveLook', HOLD_LOOK)
    SendNUIMessage({ action = 'ovMoveStart', name = target.kind == 'player' and target.label or target.name,
                     kind = target.kind, tilt = mv.tilt, caption = target.caption, doneText = target.doneText,
                     keys = target.keys })
    setPad(WhipLastInputIsPad())
    local me = mv
    CreateThread(function()
        while mv == me do
            if not DoesEntityExist(me.entity) then
                UI.Notify('It is not there any more', 'info')
                me.onExit = nil
                stop()
                break
            end
            local pad = WhipLastInputIsPad()
            if pad ~= me.pad then setPad(pad) end
            -- Put away (OvMove.update): nothing moved or drawn, and the look still works
            if pad then
                if not me.hidden then padFrame() end
                if WhipKeyPressed(nil, 202) then stop() break end   -- B, never LB + B
            else
                local look = IsDisabledControlPressed(0, 25)
                if look ~= me.looking then setLooking(look) end
            end
            if not me.hidden then pushView() end
            Wait(0)
        end
    end)
    return true
end

function OvMove.active() return mv ~= nil end

--- Change what Move is on while it runs (the hand editor's next item): `entity` (this game's own, held still like
--- the first), the bar's `name` and `caption`, and `markers`: false puts the arrows and rings away and nothing is
--- moved (the hand editor's walk, where the item is tied to a moving hand), true brings them back.
---@param fields table { entity?, name?, caption?, markers? }
function OvMove.update(fields)
    if not mv or type(fields) ~= 'table' then return end
    local ent = fields.entity
    if ent and ent ~= mv.entity and DoesEntityExist(ent) and mv.kind ~= 'player' then
        FreezeEntityPosition(ent, true)
        mv.entity, mv.target.entity, mv.sent = ent, ent, nil
    end
    if fields.name ~= nil then mv.target.name = fields.name end
    if fields.caption ~= nil then mv.target.caption = fields.caption end
    if fields.markers ~= nil then mv.hidden, mv.sent = fields.markers == false or nil, nil end
    SendNUIMessage({ action = 'ovMoveBar', name = mv.target.name, caption = mv.target.caption, markers = not mv.hidden })
end

--- Done with it (the object viewer switching off): its onExit still runs.
function OvMove.stop() stop() end

-- ============================================
-- The markers' drags (js/ov-panel.js routes the gizmo here)
-- ============================================

RegisterNUICallback('ovMoveTo', function(d, cb)
    cb('ok')
    if not mv or mv.hidden or type(d) ~= 'table' then return end
    local p, r = GetEntityCoords(mv.entity), GetEntityRotation(mv.entity, 2)
    local w = mv.want
    local x = tonumber(d.x) or (w and w[1]) or p.x
    local y = tonumber(d.y) or (w and w[2]) or p.y
    local z = tonumber(d.z) or (w and w[3]) or p.z
    place(x, y, z, tonumber(d.rx) or r.x, tonumber(d.ry) or r.y, tonumber(d.rz) or (w and w[4]) or r.z)
end)

--- The centre dot: stood on whatever the ray through the pointer meets, its base on it (a car on its wheels, a
--- ped on its feet). Sky, or nothing in reach, leaves it where it is.
RegisterNUICallback('ovMoveDragTo', function(d, cb)
    cb('ok')
    if not mv or mv.hidden or type(d) ~= 'table' then return end
    local nx, ny = tonumber(d.x), tonumber(d.y)
    if not nx or not ny or nx < 0 or nx > 1 or ny < 0 or ny > 1 then return end
    local c, rot = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local kx, ky = viewK()
    local dx, dy, dz = FurnishView.rayAt(nx, ny, rot.x, rot.z, kx, ky)
    local ray = StartShapeTestRay(c.x, c.y, c.z, c.x + dx * DRAG_REACH, c.y + dy * DRAG_REACH, c.z + dz * DRAG_REACH,
        1 + 16, mv.entity, 0)
    local _, hit, at = GetShapeTestResult(ray)
    if not (hit == 1 or hit == true) then return end
    local mn = GetModelDimensions(GetEntityModel(mv.entity))
    local x, y = at.x, at.y
    if d.snap == true then x, y = math.floor(x / 0.25 + 0.5) * 0.25, math.floor(y / 0.25 + 0.5) * 0.25 end
    local r = GetEntityRotation(mv.entity, 2)
    place(x, y, at.z - (mn and mn.z or 0.0), r.x, r.y, (mv.want and mv.want[4]) or r.z)
end)

RegisterNUICallback('ovMoveEnd', function(_, cb)
    cb('ok')
    if mv and mv.want then place(mv.want[1], mv.want[2], mv.want[3], 0.0, 0.0, mv.want[4], true) end
end)

RegisterNUICallback('ovMoveClick', function(_, cb) cb('ok') end)   -- (a click off the markers: nothing to pick)

RegisterNUICallback('ovMoveExit', function(d, cb)
    cb('ok')
    local onDone = mv and type(d) == 'table' and d.done == true and mv.target.onDone
    if onDone then
        local ok, err = pcall(onDone)
        if not ok then print('[whip_core:objectviewer] Done failed: ' .. tostring(err)) end
        return
    end
    stop()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and mv then
        mv.onExit = nil
        stop()
    end
end)
