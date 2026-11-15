-- ============================================
-- A point placed in the world: PlacePoint
-- ============================================
--
-- For a position too far to find on a map: a see-through ghost (a small marker, or a ped for where someone stands)
-- appears where the camera looks, or where the point already is, and the object viewer's Move takes over
-- (tools/ov_move.lua): drag the centre dot over the world, the arrows along X / Y / Z, the ring to turn it (R).
-- Place (the bar's button) takes it; Esc leaves it. The ghost is this game's alone and goes when it is done.
--
-- The settings page offers it as Place (tools/place_point.lua). OvMove is a tool's (tools/ov_move.lua, loaded after
-- this file): asked only when a point is placed.

local GHOSTS = { 'prop_mp_placement_sm', 'prop_mp_cone_02', 'prop_roadcone02a' }   -- the first this game has
local REACH = 30.0
local placing = false

local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    return HasModelLoaded(hash)
end

--- Where the camera looks: the first surface within REACH, else two metres in front of the player.
local function lookedAt()
    local c, r = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
    local px, rz = math.rad(r.x), math.rad(r.z)
    local dx, dy, dz = -math.sin(rz) * math.cos(px), math.cos(rz) * math.cos(px), math.sin(px)
    local ray = StartShapeTestRay(c.x, c.y, c.z, c.x + dx * REACH, c.y + dy * REACH, c.z + dz * REACH, 1 + 16, PlayerPedId(), 0)
    local _, hit, at = GetShapeTestResult(ray)
    if hit == 1 or hit == true then return at, true end
    return GetOffsetFromEntityInWorldCoords(PlayerPedId(), 0.0, 2.0, 0.0), false
end

--- Place a point in the world. Waits until Place or Esc.
---@param opts table|nil { at = { x, y, z, w? } (the point as it is: its heading is kept), model = a prop or ped name, ped = true (the model is a
---                       ped: it stands, and turns), label = the bar's name }
---@return table|false point  { x, y, z, w } (w: its heading), or false
---@return string|nil why  'cancelled', 'busy', 'model'
function PlacePoint(opts)
    opts = type(opts) == 'table' and opts or {}
    if placing or OvMove.active() then return false, 'busy' end
    placing = true
    local hash
    for _, name in ipairs(type(opts.model) == 'string' and { opts.model } or GHOSTS) do
        local h = GetHashKey(name)
        if loadModel(h) then hash = h break end
    end
    if not hash then placing = false return false, 'model' end
    local ped = opts.ped == true and IsModelAPed(hash)

    -- Where it starts: always where the camera looks, standing on that surface (the point as it is may be across
    -- the map). Its heading is the point's, else facing the player, as one standing at a counter would.
    local p, onSurface = lookedAt()
    local mn = GetModelDimensions(hash)
    local x, y, z = p.x, p.y, p.z - (onSurface and mn and mn.z or 0.0)
    local at = opts.at
    local h = type(at) == 'table' and tonumber(at.w) or (GetEntityHeading(PlayerPedId()) + 180.0) % 360.0

    local ghost
    if ped then
        ghost = CreatePed(4, hash, x, y, z, h, false, false)
        SetBlockingOfNonTemporaryEvents(ghost, true)
        SetEntityInvincible(ghost, true)
    else
        ghost = CreateObjectNoOffset(hash, x, y, z, false, false, false)
        SetEntityHeading(ghost, h)
    end
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityAlpha(ghost, 170, false)

    local result, finished = nil, false
    local ok, why = OvMove.start({
        entity = ghost, kind = ped and 'npc' or 'object', tilt = false,
        name = type(opts.label) == 'string' and opts.label or 'Point',
        caption = 'Placing', doneText = 'Place',
        onDone = function()
            local p = GetEntityCoords(ghost)
            result = { x = p.x, y = p.y, z = p.z, w = GetEntityHeading(ghost) }
            OvMove.stop()
        end,
    }, function() finished = true end)
    if not ok then
        DeleteEntity(ghost)
        placing = false
        return false, why
    end
    while not finished do Wait(0) end
    if DoesEntityExist(ghost) then DeleteEntity(ghost) end
    placing = false
    if not result then return false, 'cancelled' end
    return result
end

exports('PlacePoint', PlacePoint)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then placing = false end
end)
