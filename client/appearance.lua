-- Model swap, appearance application, creator camera and NUI creator, /charedit.

local isCreatorOpen = false
local creatorIsNew = false   -- opened for a character that was just created

--- True from when the creator starts closing until it has: NUI draws above a screen fade, so it stays clickable.
local creatorClosing = false

--- Is the creator accepting input right now? Every NUI callback gates on this.
local function CreatorLive()
    return isCreatorOpen and not creatorClosing
end

--- Same as isCreatorOpen, but global, for IsAnyUIOpen (client/inventory.lua).
CreatorIsOpen = false

local creatorCam = nil
local savedAppearance = nil  -- backup for cancel

--- While the creator is open on a look that is not this character's (EditLook): { done = function(look, headshot) }.
local lookFor = nil
-- The editor as a store (EditAppearance): { onSave, onClose, busy }; Save goes to it. nil otherwise.
local storeFor = nil

-- Preview-loop bookkeeping (see the previewAppearance callback); declared here so later functions can see it.
local previewGen = 0             -- generation stamp; stale waiters drop out
local previewLastBlendSig = nil  -- head-blend signature of the last preview
local previewLastApplied = nil   -- snapshot of the last preview, for delta application
local previewFieldGen = {}       -- per-field last-writer generation (see previewParts)
local previewFullGen = 0         -- generation of the last FULL preview that painted;
                                 -- it wrote every field, so it is a staleness floor
local previewLastTattooSig = nil -- tattooSig of the tattoos the last preview put on (nil = unknown)

-- Default appearance template

local function GetDefaultAppearance(gender)
    local model = (gender == 'female') and 'mp_f_freemode_01' or 'mp_m_freemode_01'
    return {
        model = model,
        headBlend = {
            mom = 0, dad = 0, grandparent = 0,
            faceWeight = 0.5, skinWeight = 0.5, thirdWeight = 0.0
        },
        faceFeatures = {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0},
        eyeColor = 0,
        hair = {style = 0, texture = 0, color = 0, highlight = 0},
        overlays = {
            blemishes    = {type = 0, opacity = 0.0},
            beard        = {type = 0, opacity = 0.0, color = 0, color2 = 0},
            eyebrows     = {type = 0, opacity = 0.0, color = 0, color2 = 0},
            ageing       = {type = 0, opacity = 0.0},
            makeup       = {type = 0, opacity = 0.0, color = 0, color2 = 0},
            blush        = {type = 0, opacity = 0.0, color = 0, color2 = 0},
            complexion   = {type = 0, opacity = 0.0},
            sunDamage    = {type = 0, opacity = 0.0},
            lipstick     = {type = 0, opacity = 0.0, color = 0, color2 = 0},
            moles        = {type = 0, opacity = 0.0},
            chestHair    = {type = 0, opacity = 0.0, color = 0, color2 = 0},
        },
        components = {},
        props = {},
    }
end

-- Overlay index mapping (GTA overlay IDs)
local OVERLAY_IDS = {
    blemishes  = 0,
    beard      = 1,
    eyebrows   = 2,
    ageing     = 3,
    makeup     = 4,
    blush      = 5,
    complexion = 6,
    sunDamage  = 7,
    lipstick   = 8,
    moles      = 9,
    chestHair  = 10,
}

--- The prop slots a freemode ped wears: hat, glasses, ear, watch, bracelet. Not contiguous (3, 4, 5 are unused).
local PROP_SLOTS = { 0, 1, 2, 6, 7 }

-- Overlays that support color (type 1 = hair colors, type 2 = makeup colors)
local OVERLAY_COLOR_TYPE = {
    beard     = 1,
    eyebrows  = 1,
    chestHair = 1,
    makeup    = 2,
    blush     = 2,
    lipstick  = 2,
}

-- Model loading is client/streaming.lua's LoadModel.

-- Apply appearance to a ped

--- Resolve a stored clothing choice to one this ped can wear (a missing variation leaves the default).
--- Out of range lands on the last drawable, not the first (zero is the bare default for most slots).
---@param ped number
---@param compId number
---@param drawable number|nil
---@param texture number|nil
---@return number compId, number drawable, number texture, number palette
local function safeComponent(ped, compId, drawable, texture)
    local d = math.floor(tonumber(drawable) or 0)
    local t = math.floor(tonumber(texture) or 0)

    -- Counts, not maxima: both natives return how many exist, so the last valid index is n - 1.
    local nd = GetNumberOfPedDrawableVariations(ped, compId)
    if nd and nd > 0 then
        if d < 0 or d >= nd then d = nd - 1 end
    else
        d = 0   -- nothing available for this slot at all
    end

    local nt = GetNumberOfPedTextureVariations(ped, compId, d)
    if nt and nt > 0 then
        if t < 0 or t >= nt then t = 0 end
    else
        t = 0
    end

    return compId, d, t, 0
end

--- The same check for props. -1 means nothing and passes through; out of range becomes -1.
---@return number propId, number drawable, number texture
local function safeProp(ped, propId, drawable, texture)
    local d = math.floor(tonumber(drawable) or -1)
    local t = math.floor(tonumber(texture) or 0)
    if d < 0 then return propId, -1, 0 end

    local nd = GetNumberOfPedPropDrawableVariations(ped, propId)
    if not nd or nd <= 0 or d >= nd then return propId, -1, 0 end

    local nt = GetNumberOfPedPropTextureVariations(ped, propId, d)
    if not nt or nt <= 0 or t < 0 or t >= nt then t = 0 end

    return propId, d, t
end

-- Tattoos
-- Stored as a list of { collection, overlay } names, drawn in order (list: shared/tattoo_list.lua).
-- No native removes one decoration, so changing the list clears all and re-applies the new list.
-- The hair fade (`hairFade`, shared/hair_fades.lua) is a decoration too and goes on first.

--- Put exactly this fade and these tattoos on a ped (nil or empty: none).
---@param ped number
---@param tattoos table|nil  { { collection = 'mpBiker_overlays', overlay = 'MP_MP_Biker_Tat_000_M' }, ... }
---@param fade table|nil     { collection = 'multiplayer_overlays', overlay = 'NG_M_Hair_001' }
local function applyTattoos(ped, tattoos, fade)
    ClearPedDecorationsLeaveScars(ped)
    if type(fade) == 'table' and type(fade.collection) == 'string' and type(fade.overlay) == 'string' then
        AddPedDecorationFromHashes(ped, GetHashKey(fade.collection), GetHashKey(fade.overlay))
    end
    if type(tattoos) ~= 'table' then return end
    for _, t in ipairs(tattoos) do
        if type(t) == 'table' and type(t.collection) == 'string' and type(t.overlay) == 'string' then
            AddPedDecorationFromHashes(ped, GetHashKey(t.collection), GetHashKey(t.overlay))
        end
    end
end

--- One string naming a fade and a tattoo list, so two can be compared.
local function tattooSig(tattoos, fade)
    local parts = {}
    if type(tattoos) == 'table' then
        for i, t in ipairs(tattoos) do
            parts[i] = type(t) == 'table' and ((t.collection or '') .. '/' .. (t.overlay or '')) or ''
        end
    end
    local f = type(fade) == 'table' and ((fade.collection or '') .. '/' .. (fade.overlay or '')) or ''
    return f .. '|' .. table.concat(parts, ',')
end

--- Apply an appearance to a ped.
---@param ped number
---@param appearance table
---@param skipBlendBake boolean|nil  true = the head blend is already on this ped, so skip SetPedHeadBlendData and its wait (creator preview loop only)
---@param skipTattoos boolean|nil  true = these tattoos and fade are already on this ped (creator preview loop only)
function ApplyAppearance(ped, appearance, skipBlendBake, skipTattoos)
    if not ped or ped == 0 or not appearance then return end


    -- `+ 0.0` on float natives: JSON turns 1.0 into an integer, which a float slot reads as ~1.4e-45.

    if not skipBlendBake then
        -- Head blend (genetics)
        local hb = appearance.headBlend or {}
        SetPedHeadBlendData(ped,
            hb.mom or 0,           -- shape first
            hb.dad or 0,           -- shape second
            hb.grandparent or 0,   -- shape third
            hb.mom or 0,           -- skin first
            hb.dad or 0,           -- skin second
            hb.grandparent or 0,   -- skin third
            (hb.faceWeight or 0.5) + 0.0,  -- shape mix
            (hb.skinWeight or 0.5) + 0.0,  -- skin mix
            (hb.thirdWeight or 0.0) + 0.0, -- third mix
            false
        )

        -- SetPedHeadBlendData is asynchronous: face features set during the bake are wiped. Wait it out (bounded).
        local deadline = GetGameTimer() + 500
        while not HasPedHeadBlendFinished(ped) and GetGameTimer() < deadline do
            Wait(0)
        end
    end

    -- Face features (0-19)
    local features = appearance.faceFeatures or {}
    for i = 0, 19 do
        SetPedFaceFeature(ped, i, (tonumber(features[i + 1]) or 0.0) + 0.0)
    end

    -- Eye color
    SetPedEyeColor(ped, appearance.eyeColor or 0)

    -- Hair (component 2)
    local hair = appearance.hair or {}
    SetPedComponentVariation(ped, safeComponent(ped, 2, hair.style, hair.texture))
    SetPedHairColor(ped, hair.color or 0, hair.highlight or 0)

    -- Overlays
    local overlays = appearance.overlays or {}
    for name, overlayId in pairs(OVERLAY_IDS) do
        local ov = overlays[name] or {}
        local ovType = ov.type or 0
        local ovOpacity = ov.opacity or 0.0

        -- type 0 with opacity 0 = disabled, use 255 to clear
        if ovType == 0 and ovOpacity == 0.0 then
            SetPedHeadOverlay(ped, overlayId, 255, 0.0)
        else
            SetPedHeadOverlay(ped, overlayId, ovType, ovOpacity + 0.0)
        end

        -- Apply color if this overlay supports it
        local colorType = OVERLAY_COLOR_TYPE[name]
        if colorType and ovType ~= 255 then
            SetPedHeadOverlayColor(ped, overlayId, colorType, ov.color or 0, ov.color2 or 0)
        end
    end

    -- Components (clothing), clamped against this ped (safeComponent)
    local components = appearance.components or {}
    for compId, comp in pairs(components) do
        local id = tonumber(compId)
        if id then
            -- safeComponent returns the native's last four arguments.
            SetPedComponentVariation(ped, safeComponent(ped, id, comp.drawable, comp.texture))
        end
    end

    -- Props: safeProp answers -1 for anything missing, which clears the prop.
    local props = appearance.props or {}
    for propId, prop in pairs(props) do
        local id = tonumber(propId)
        if id then
            local _, pd, pt = safeProp(ped, id, prop.drawable, prop.texture)
            if pd == -1 then
                ClearPedProp(ped, id)
            else
                SetPedPropIndex(ped, id, pd, pt, true)
            end
        end
    end

    -- Tattoos and the hair fade: always set, so an empty list also removes earlier ones.
    if not skipTattoos then applyTattoos(ped, appearance.tattoos, appearance.hairFade) end
end

-- Swap model + apply appearance

local function SwapModelAndApply(appearance)
    local modelName = appearance.model or 'mp_m_freemode_01'

    if not LoadModel(modelName) then
        print('[whip_core] Failed to load model: ' .. modelName)
        return false
    end

    local hash = GetHashKey(modelName)
    -- SetPlayerModel builds a new ped: end the emote first so its props are not left behind.
    if Emotes ~= nil then Emotes.stop() end
    SetPlayerModel(PlayerId(), hash)
    SetModelAsNoLongerNeeded(hash)
    PedHold.reapply()   -- the new ped starts with none of the holds (character select's hide, say)

    -- SetPlayerModel resets health regen, health and armour: re-disable regen.
    SetPlayerHealthRechargeMultiplier(PlayerId(), 0.0)
    SetPlayerHealthRechargeLimit(PlayerId(), 0.0)

    Wait(100)

    local ped = PlayerPedId()

    -- Re-apply health and armour: the Stats cache first, then PlayerData (set at login, before statsSync).
    local cachedHealth = ClientStatValue('health')
    local cachedArmour = ClientStatValue('armour')

    if not cachedHealth or cachedHealth == 0 then
        cachedHealth = PlayerData and PlayerData.health
    end
    if not cachedArmour then
        cachedArmour = PlayerData and PlayerData.armour
    end

    if cachedHealth and cachedHealth > 100 then
        SetEntityHealth(ped, math.floor(cachedHealth))
    end
    if cachedArmour and cachedArmour > 0 then
        SetPedArmour(ped, math.floor(cachedArmour))
    end

    if appearance.default then
        SetPedDefaultComponentVariation(ped)   -- a model an admin put them in (WearModel): the game's own look for it
    else
        ApplyAppearance(ped, appearance)
    end
    -- A new ped has the default walk and face: the emote system restores the chosen ones.
    WhipEmit('whip_core:appearance:modelChanged', {})
    return true
end

-- Creator camera: an orbit rig around the ped. Targets are chased by a frame-rate independent damp;
-- the ped does not turn, so every framing change is one continuous move.

local abs, deg, rad = math.abs, math.deg, math.rad
local sin, cos, asin, exp, sqrt = math.sin, math.cos, math.asin, math.exp, math.sqrt
local atan2 = math.atan   -- Lua 5.3+ math.atan(y, x) is atan2

local CAM = {
    blendRate    = 3.0,     -- how fast framing changes are chased
    poseRate     = 14.0,    -- the spring rate once settled; see the camera loop

    -- Handover: enterRate is the spring rate the arrival starts at, ramped up to poseRate across enterTime.
    enterTime    = 0.90,    -- seconds
    enterRate    = 3.20,
    exitMs       = 600,     -- engine ease back to gameplay

    pitchMin     = -30.0,
    pitchMax     = 45.0,
    yawSpeed     = 0.42,    -- degrees per pixel of right-drag
    pitchSpeed   = 0.30,
    panSpeed     = 0.004,   -- metres per pixel of left-drag

    -- Zoom has the same range on every tab: all the way in is a face close-up, all the way out the whole body.
    zoomStep     = 0.12,    -- metres per wheel notch
    distMin      = 0.62,
    distMax      = 3.10,    -- = CAM_FRAMINGS.body.dist
}

--- Every shot the creator uses. `bone` is the look-at point, `up` nudges it (metres), `dist` is how far
--- back, `pitch` how far above, `yaw` the bearing from the ped's facing (180 is face-on).
local CAM_FRAMINGS = {
    torso = { bone = 24818, up = 0.06, dist = 2.05, pitch = 5.0,  yaw = 217.0, fov = 36.0 },  -- SKEL_Spine3
    legs  = { bone = 63931, up = 0.15, dist = 2.10, pitch = 6.0,  yaw = 217.0, fov = 38.0 },  -- SKEL_L_Calf
    body  = { bone = 23553, up = 0.05, dist = 3.10, pitch = 4.0,  yaw = 217.0, fov = 45.0 },  -- SKEL_Spine0
}

-- ---- maths ----

local function clampN(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--- Whichever of b, b+360 or b-360 is closest to a, so yaw never spins the long way round.
local function nearestAngle(a, b)
    local d0, bUp, bDn = abs(a - b), b + 360.0, b - 360.0
    local d1, d2 = abs(a - bUp), abs(a - bDn)
    if d0 <= d1 and d0 <= d2 then return b end
    if d1 <= d2 then return bUp end
    return bDn
end

--- Frame-rate independent exponential approach: the same feel at 30fps and 144.
local function damp(current, target, rate, dt)
    return target + (current - target) * exp(-rate * dt)
end

local function dampAngle(current, target, rate, dt)
    local t = nearestAngle(current, target)
    local v = t + (current - t) * exp(-rate * dt)
    return (v + 180.0) % 360.0 - 180.0
end

local function wrap180(a)
    return (a + 180.0) % 360.0 - 180.0
end

local function lerp(a, b, t) return a + (b - a) * t end

--- Ease in and out, for the transitions.
local function smoothstep(t) return t * t * (3.0 - 2.0 * t) end

local function normalize(x, y, z)
    local l = sqrt(x * x + y * y + z * z)
    if l < 1e-6 then return 0.0, 0.0, 0.0 end
    return x / l, y / l, z / l
end

--- Camera pitch and yaw that look down a direction vector.
local function rotFromDir(dx, dy, dz)
    local nx, ny, nz = normalize(dx, dy, dz)
    return deg(asin(clampN(nz, -1.0, 1.0))), deg(atan2(-nx, ny))
end

--- Offset a world position by a local-space (right, forward, up) triple.
local function localToWorld(px, py, pz, heading, right, fwd, up)
    local h = rad(heading)
    local fx, fy = -sin(h), cos(h)
    local rx, ry =  cos(h), sin(h)
    return px + rx * right + fx * fwd, py + ry * right + fy * fwd, pz + up
end

-- ---- rig state ----

local camActive = false
local startCamLoop   -- the camera's frame loop, started when it is; defined with the loop below
local camYaw,  camPitch,  camDist,  camFov  = 180.0, 2.0, 1.0, 24.0
local tYaw,    tPitch,    tDist,    tFov    = 180.0, 2.0, 1.0, 24.0
local camAimU, tAimU = 0.65, 0.65    -- aim height above the ped's root, metres
-- Where across the screen the ped stands, -1 (left edge) to 1 (right edge). The page reports where the open
-- world is (NUI creatorStage) and the camera slides sideways to stand the ped there (ComputeCamPose).
local camShiftX, tShiftX = 0.0, 0.0
local camFraming = 'torso'   -- the framing the shot was last pointed at

-- The live pose, kept between frames so the loop smooths rather than snaps.
local cpx, cpy, cpz, cpPitch, cpYaw, cpFov = 0.0, 0.0, 0.0, 0.0, 0.0, 45.0

-- Roll is carried from the gameplay camera and damps out, so nothing snaps.
local cpRoll = 0.0

-- Rig state:
--   'enter'  the spring carries the camera onto the ped
--   'live'   orbit, pan and framing changes own the camera
--   'exit'   handed back to the engine, easing out, camera held still
--   'idle'   no camera
-- The camera is destroyed only once the exit ease has finished: destroying it mid-ease cuts.
local camPhase = 'idle'
local enterT   = 1.0     -- 0 at the start of the entry spring, 1 when settled
local leaveAt  = 0       -- game time the exit ease is due to finish

--- Point the rig at a named framing. Only the targets move; the loop eases the live values across.
local function ApplyCamFraming(name)
    camFraming = CAM_FRAMINGS[name] and name or 'torso'
    local f = CAM_FRAMINGS[camFraming]
    tPitch = clampN(f.pitch, CAM.pitchMin, CAM.pitchMax)
    tDist  = f.dist
    tFov   = f.fov

    -- The aim point is a height above the ped's root, not a bone, so it can be damped.
    local ped = PlayerPedId()
    local root = GetEntityCoords(ped)
    local bone = GetPedBoneCoords(ped, f.bone, 0.0, 0.0, 0.0)
    tAimU = (bone.z - root.z) + (f.up or 0.0)
end

--- How far the shot may slide up and down, read off the ped's skeleton so it fits any model.
local function AimRange(ped)
    local root = GetEntityCoords(ped)
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)   -- SKEL_Head
    local foot = GetPedBoneCoords(ped, 14201, 0.0, 0.0, 0.0)   -- SKEL_L_Foot
    local lo = (foot.z - root.z) - 0.15
    local hi = (head.z - root.z) + 0.25
    if hi <= lo then return -1.0, 2.0 end   -- bones unavailable; stay permissive
    return lo, hi
end

--- One frame of camera input from the NUI: left-drag slides up and down, right-drag orbits, wheel dollies.
local function CamInput(pan, orbitX, orbitY, zoom)
    -- Only while the shot is the player's to move, not mid-transition.
    if camPhase ~= 'live' then return end

    if orbitX ~= 0.0 or orbitY ~= 0.0 then
        tYaw   = wrap180(tYaw - orbitX * CAM.yawSpeed)
        tPitch = clampN(tPitch + orbitY * CAM.pitchSpeed, CAM.pitchMin, CAM.pitchMax)
    end

    if pan ~= 0.0 then
        -- Dragging down pulls the body down the screen, so the shot looks higher.
        local lo, hi = AimRange(PlayerPedId())
        tAimU = clampN(tAimU + pan * CAM.panSpeed, lo, hi)
    end

    if zoom ~= 0.0 then
        tDist = clampN(tDist + zoom * CAM.zoomStep, CAM.distMin, CAM.distMax)
    end
end

--- Where the camera belongs right now, from the current (damped) framing. Used by the loop and the entry.
---@return number cx, number cy, number cz, number cpitch, number cyaw
local function ComputeCamPose()
    local ped  = PlayerPedId()
    local root = GetEntityCoords(ped)
    local ph   = GetEntityHeading(ped)

    -- The shot is built around a point straight up from the ped's root.
    local lx, ly, lz = root.x, root.y, root.z + camAimU

    -- The camera orbits that point at a bearing off the ped's facing.
    local h     = ph + camYaw
    local ang   = rad(camPitch)
    local horiz = camDist * cos(ang)
    local vert  = camDist * sin(ang)
    local cx, cy, cz = localToWorld(lx, ly, lz, h, 0.0, -horiz, vert)

    local cpitch, cyaw = rotFromDir(lx - cx, ly - cy, lz - cz)

    -- camShiftX: slide the camera sideways without turning it. The screen's half-width at the ped's distance
    -- is dist x tan(fov/2) x aspect (GTA's fov is vertical); sliding left by that times camShiftX puts the ped right.
    if camShiftX ~= 0.0 then
        local dx, dy = lx - cx, ly - cy
        local flat = sqrt(dx * dx + dy * dy)
        if flat > 1e-4 then
            local rx, ry = dy / flat, -dx / flat                   -- the camera's right, on the ground
            local half = camDist * math.tan(rad(camFov * 0.5)) * GetAspectRatio(false)
            cx, cy = cx - rx * half * camShiftX, cy - ry * half * camShiftX
        end
    end
    return cx, cy, cz, cpitch, cyaw
end

--- Create the scripted camera for this rig.
local function StartCreatorCamera(preset)
    ApplyCamFraming(preset)
    tYaw = wrap180(CAM_FRAMINGS[camFraming].yaw)

    -- Snap the framing so the shot flown to is the finished one.
    camYaw, camPitch, camDist, camFov = tYaw, tPitch, tDist, tFov
    camAimU = tAimU

    if creatorCam and camPhase == 'exit' then
        -- Back in before the handover finished: restart the spring from where the camera is.
        RenderScriptCams(true, true, 250, true, true)
    else
        -- Seeded at the gameplay camera's pose so the swap needs no ease.
        local gp, gr, gf = GetGameplayCamCoord(), GetGameplayCamRot(2), GetGameplayCamFov()
        cpx, cpy, cpz = gp.x, gp.y, gp.z
        cpPitch, cpRoll, cpYaw, cpFov = gr.x, gr.y, gr.z, gf

        if not creatorCam then
            creatorCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA',
                gp.x, gp.y, gp.z, gr.x, gr.y, gr.z, gf, true, 2)
        else
            SetCamCoord(creatorCam, gp.x, gp.y, gp.z)
            SetCamRot(creatorCam, gr.x, gr.y, gr.z, 2)
            SetCamFov(creatorCam, gf)
        end

        SetCamActive(creatorCam, true)
        RenderScriptCams(true, false, 0, true, true)
    end

    -- The spring takes it from here.
    camPhase, enterT = 'enter', 0.0
    camActive = true
    startCamLoop()
end

--- Ask the engine to ease the view back, hold the camera, and destroy it once the ease has finished.
local function DestroyCreatorCamera()
    if not creatorCam then
        camActive, camPhase = false, 'idle'
        return
    end
    if camPhase == 'exit' then return end   -- already on its way

    RenderScriptCams(false, true, CAM.exitMs, true, true)
    camPhase = 'exit'
    leaveAt  = GetGameTimer() + CAM.exitMs + 50

    -- The loop notices when the ease has finished.
    camActive = true
    startCamLoop()
end

--- Is the creator's camera still on screen (holding the shot or easing home)? DestroyCreatorCamera starts a
--- 600ms blend and returns at once, so callers ask this before raising the picture.
---@return boolean
function CreatorCameraIsActive()
    return creatorCam ~= nil
end

--- Tear down now, no flight (resource stop).
local function KillCreatorCamera()
    camActive, camPhase = false, 'idle'
    if creatorCam then
        RenderScriptCams(false, false, 0, true, true)
        SetCamActive(creatorCam, false)
        DestroyCam(creatorCam, false)
        creatorCam = nil
    end
end

--- The camera's frame loop (startCamLoop), running only while there is a camera.
local camLoopRunning = false

local function camLoop()
    while camActive and creatorCam do
        -- Every path must reach the Wait below, or no frame advances and the game hangs.
        if camPhase == 'exit' then
            -- Leaving: hold the camera for the engine's blend, then let go when it is over.
            if GetGameTimer() >= leaveAt then
                KillCreatorCamera()
            end
        else
            local dt = GetFrameTime()
            if dt <= 0.0 then dt = 1.0 / 60.0 end

            local r = CAM.blendRate
            camYaw   = dampAngle(camYaw, tYaw, r, dt)
            camPitch = damp(camPitch, tPitch, r, dt)
            camDist  = damp(camDist,  tDist,  r, dt)
            camFov   = damp(camFov,   tFov,   r, dt)
            camAimU  = damp(camAimU,  tAimU,  r, dt)
            camShiftX = damp(camShiftX, tShiftX, r, dt)

            local cx, cy, cz, cpitch, cyaw = ComputeCamPose()

            -- The spring: one path for arriving and steering; only the rate changes.
            local posRate, rotRate = CAM.poseRate, CAM.poseRate

            -- Entry ramp: a low rate first, smoothstepped up, so it settles without a snap.
            if enterT < 1.0 then
                enterT = math.min(enterT + dt / CAM.enterTime, 1.0)
                local b = smoothstep(enterT)
                posRate = lerp(CAM.enterRate, posRate, b)
                rotRate = lerp(CAM.enterRate, rotRate, b)
                if enterT >= 1.0 then camPhase = 'live' end
            end

            cpx     = damp(cpx, cx, posRate, dt)
            cpy     = damp(cpy, cy, posRate, dt)
            cpz     = damp(cpz, cz, posRate, dt)
            cpPitch = damp(cpPitch, cpitch, rotRate, dt)
            cpYaw   = dampAngle(cpYaw, cyaw, rotRate, dt)

            -- Roll damps away with the rest of the move.
            cpRoll  = damp(cpRoll, 0.0, rotRate, dt)
            cpFov   = damp(cpFov, camFov, rotRate, dt)

            SetCamCoord(creatorCam, cpx, cpy, cpz)
            SetCamRot(creatorCam, cpPitch, cpRoll, cpYaw, 2)
            SetCamFov(creatorCam, cpFov)
        end

        Wait(0)
    end
    camLoopRunning = false
end

startCamLoop = function()
    if camLoopRunning then return end
    camLoopRunning = true
    CreateThread(camLoop)
end

-- Clothing pictures (img/clothing in whip_media_clothing_male and _female)
-- Pictures are named by collection and the item's number inside it, because a card's global number moves
-- when a pack adds items:  img/clothing/male/11_tops/male_11_mp_m_vinewood_004_00.webp
-- Each card's name is asked of the game once per creator open and the page builds the path from it.
-- The ped's first collection is called 'base' in the pictures.

--- '<collection>_<item>' for each of a slot's drawables, in card order ('' when unnamed).
local function iconNames(count, nameOf, indexOf, base)
    local out = {}
    for d = 0, count - 1 do
        local name, idx = nameOf(d), indexOf(d)
        if type(name) ~= 'string' or type(idx) ~= 'number' or idx < 0 then
            out[d + 1] = ''
        else
            if name == '' or name == base then name = 'base' end
            out[d + 1] = ('%s_%03d'):format(name, idx)
        end
    end
    return out
end

--- Every card's picture name for the creator, or nil (only the freemode bodies have pictures).
---@return table|nil  { gender = 'male'|'female', components = { ['11'] = { 'base_000', ... } }, props = { ['0'] = {...} } }
local function clothingIcons(ped)
    local model = GetEntityModel(ped)
    local gender = (model == GetHashKey('mp_m_freemode_01') and 'male')
        or (model == GetHashKey('mp_f_freemode_01') and 'female') or nil
    if not gender or GetPedCollectionNameFromDrawable == nil or GetPedCollectionNameFromProp == nil then return nil end
    local base = GetPedCollectionName(ped, 0)
    local out = { gender = gender, components = {}, props = {} }
    for comp = 0, 11 do
        out.components[tostring(comp)] = iconNames(GetNumberOfPedDrawableVariations(ped, comp),
            function(d) return GetPedCollectionNameFromDrawable(ped, comp, d) end,
            function(d) return GetPedCollectionLocalIndexFromDrawable(ped, comp, d) end, base)
    end
    for _, slot in ipairs(PROP_SLOTS) do
        out.props[tostring(slot)] = iconNames(GetNumberOfPedPropDrawableVariations(ped, slot),
            function(d) return GetPedCollectionNameFromProp(ped, slot, d) end,
            function(d) return GetPedCollectionLocalIndexFromProp(ped, slot, d) end, base)
    end
    return out
end

-- Which items have a picture, per body (server/clothing_pictures.lua): the editor hides items without one.
-- Asked the first time a body's editor opens, kept until a media pack restarts.
-- No answer: nothing is hidden, and the next open asks again.
local picturesFor = {}   -- ['male'|'female'] = { components = { ['11'] = { base = '0-15,...' } }, props = {...} }
local picturesAsked = {}

-- Forgotten on a media pack restart, so the next open asks again.
AddEventHandler('onClientResourceStart', function(res)
    if WhipAssets.isAsset(res) then picturesFor = {} end
end)

local function askPictures(gender)
    if picturesFor[gender] or picturesAsked[gender] then return end
    picturesAsked[gender] = true
    CreateThread(function()
        local ok, got = pcall(Callback, 'whip_core:appearance:clothingPictures', gender)
        picturesAsked[gender] = nil   -- cleared whatever happened, so a failed ask is asked again
        if not ok or type(got) ~= 'table' then return end
        picturesFor[gender] = got
        if isCreatorOpen then
            SendNUIMessage({ action = 'creatorPictures', gender = gender, pictures = got })
        end
    end)
end

-- The tattoos the editor offers

-- GET_PED_DECORATION_ZONE_FROM_HASHES answer to the editor's body part. Anything else (6, 7) is not offered.
local TATTOO_ZONES = { [0] = 'torso', [1] = 'head', [2] = 'larm', [3] = 'rarm', [4] = 'lleg', [5] = 'rleg' }
local tattoosByBody = {}   -- 'm' | 'f' → the answer below, asked once: the game build does not change

--- The tattoos this ped's body can wear, or nil for a non-freemode ped. Each is checked against this game
--- (the zone native answers only for tattoos it has).
---@return table|nil  { collections = { { name, label }, ... }, zones = { torso = { { collection index, overlay, facing, name }, ... }, head = ..., larm, rarm, lleg, rleg } }
local function tattoosFor(ped)
    local model = GetEntityModel(ped)
    local body = (model == GetHashKey('mp_m_freemode_01') and 'm')
        or (model == GetHashKey('mp_f_freemode_01') and 'f') or nil
    if not body then return nil end
    if tattoosByBody[body] then return tattoosByBody[body] end

    local out = { collections = {}, zones = { head = {}, torso = {}, larm = {}, rarm = {}, lleg = {}, rleg = {} } }
    local hashes = {}
    for i, c in ipairs(TattooList.collections) do
        out.collections[i] = { name = c.name, label = c.label }
        hashes[i] = GetHashKey(c.name)
    end
    for _, t in ipairs(TattooList.list) do
        if t[4]:find(body, 1, true) then
            local zone = TATTOO_ZONES[GetPedDecorationZoneFromHashes(hashes[t[1]], GetHashKey(t[2]))]
            if zone then
                local list = out.zones[zone]
                list[#list + 1] = { t[1], t[2], t[5], t[6] }
            end
        end
    end
    tattoosByBody[body] = out
    return out
end

local fadesByBody = {}     -- as tattoosByBody, for the hair fades

--- The hair fades this ped's body can wear, or nil for a non-freemode ped (a decoration on zone 1).
---@return table|nil  { collections = { { name, label }, ... }, list = { { collection index, overlay }, ... } }
local function fadesFor(ped)
    local model = GetEntityModel(ped)
    local body = (model == GetHashKey('mp_m_freemode_01') and 'm')
        or (model == GetHashKey('mp_f_freemode_01') and 'f') or nil
    if not body then return nil end
    if fadesByBody[body] then return fadesByBody[body] end

    local out = { collections = {}, list = {} }
    local hashes = {}
    for i, c in ipairs(HairFades.collections) do
        out.collections[i] = { name = c.name, label = c.label }
        hashes[i] = GetHashKey(c.name)
    end
    for _, f in ipairs(HairFades.list) do
        if f[3]:find(body, 1, true) and GetPedDecorationZoneFromHashes(hashes[f[1]], GetHashKey(f[2])) == 1 then
            out.list[#out.list + 1] = { f[1], f[2] }
        end
    end
    fadesByBody[body] = out
    return out
end

-- Undressed (the creator's Undress buttons)
-- What each freemode body wears with nothing on: underwear, bare feet, and the "nothing" item elsewhere
-- (male briefs are base legs 14, female base legs 15 plus a bra, base top 15; no nudity).
-- Named by collection and item number as the pictures are; a slot whose item this game lacks stays dressed.
local UNDRESSED = {
    male = {
        ['1']  = { 'base', 0 },          -- no mask
        ['3']  = { 'base', 15 },         -- bare arms and chest
        ['4']  = { 'base', 14 },         -- briefs
        ['5']  = { 'base', 0 },          -- no bag
        ['6']  = { 'male_apt01', 1 },    -- bare feet
        ['7']  = { 'base', 0 },          -- no chain
        ['8']  = { 'base', 15 },         -- no undershirt
        ['9']  = { 'base', 0 },          -- no vest
        ['10'] = { 'base', 0 },          -- no decal
        ['11'] = { 'base', 15 },         -- no top
    },
    female = {
        ['1']  = { 'base', 0 },          -- no mask
        ['3']  = { 'base', 15 },         -- bare arms and chest (the bra is the top, below)
        ['4']  = { 'base', 15 },         -- briefs
        ['5']  = { 'base', 0 },          -- no bag
        ['6']  = { 'female_apt01', 1 },  -- bare feet
        ['7']  = { 'base', 0 },          -- no chain
        ['8']  = { 'base', 14 },         -- no undershirt
        ['9']  = { 'base', 0 },          -- no vest
        ['10'] = { 'base', 0 },          -- no decal
        ['11'] = { 'base', 15 },         -- the bra
    },
}

--- This ped's undressed items as this game numbers them: { components = { ['3'] = 15, ... } }. nil for a non-freemode ped.
local function undressedFor(ped)
    local model = GetEntityModel(ped)
    local body = (model == GetHashKey('mp_m_freemode_01') and 'male')
        or (model == GetHashKey('mp_f_freemode_01') and 'female') or nil
    if not body then return nil end
    local out = { components = {} }
    for comp, item in pairs(UNDRESSED[body]) do
        local id = tonumber(comp) --[[@as integer]]   -- (UNDRESSED's keys are all digit strings)
        local d = -1
        if item[1] == 'base' then
            d = item[2]
        elseif GetPedDrawableGlobalIndexFromCollection ~= nil then
            d = GetPedDrawableGlobalIndexFromCollection(ped, id, item[1], item[2]) or -1
        end
        if d >= 0 and d < GetNumberOfPedDrawableVariations(ped, id) then out.components[comp] = d end
    end
    return out
end

-- Max variations for the NUI

local function GetMaxVariations()
    local ped = PlayerPedId()
    local maxes = {
        components = {},
        props = {},
        hair = {},
        overlays = {},
    }

    -- Components
    for i = 0, 11 do
        maxes.components[tostring(i)] = {
            maxDrawable = GetNumberOfPedDrawableVariations(ped, i),
            maxTexture = GetNumberOfPedTextureVariations(ped, i, GetPedDrawableVariation(ped, i)),
        }
    end

    -- Props (see PROP_SLOTS)
    for _, i in ipairs(PROP_SLOTS) do
        local drawable = GetPedPropIndex(ped, i)
        maxes.props[tostring(i)] = {
            maxDrawable = GetNumberOfPedPropDrawableVariations(ped, i),
            maxTexture = (drawable >= 0) and GetNumberOfPedPropTextureVariations(ped, i, drawable) or 0,
        }
    end

    -- Hair
    maxes.hair.maxStyle = GetNumberOfPedDrawableVariations(ped, 2)
    maxes.hair.maxTexture = GetNumberOfPedTextureVariations(ped, 2, GetPedDrawableVariation(ped, 2))
    maxes.hair.maxColor = GetNumHairColors()
    maxes.hair.maxHighlight = GetNumHairColors()

    -- Overlays
    for name, overlayId in pairs(OVERLAY_IDS) do
        maxes.overlays[name] = {
            maxType = GetPedHeadOverlayNum(overlayId),
        }
    end

    -- The game's real RGB behind each palette index, read once per creator open.
    maxes.hairColors = {}
    for i = 0, (maxes.hair.maxColor or 64) - 1 do
        local r, g, b = GetPedHairRgbColor(i)
        maxes.hairColors[i + 1] = { r = r, g = g, b = b }
    end

    maxes.makeupColors = {}
    local numMakeup = GetNumMakeupColors()
    for i = 0, numMakeup - 1 do
        local r, g, b = GetPedMakeupRgbColor(i)
        maxes.makeupColors[i + 1] = { r = r, g = g, b = b }
    end

    maxes.icons = clothingIcons(ped)
    if maxes.icons then maxes.icons.pictures = picturesFor[maxes.icons.gender] end

    maxes.tattoos = tattoosFor(ped)
    maxes.fades = fadesFor(ped)
    maxes.undressed = undressedFor(ped)

    return maxes
end

-- Open / close creator

-- The pose a new character holds on the creator's mark (Config.Creator.pose, an /e name). Not the emote
-- system's: no props, nothing the player presses ends it. Re-applied after a model swap, removed in CloseCreator.
local creatorPose = nil   -- { dict, anim } while it is ours on the ped
local creatorPoseGen = 0  -- bumped by every start and stop: a start still loading its dict gives up
local POSE_CHECK_MS = 500 -- how soon a pose taken off is put back

local function stopCreatorPose()
    creatorPoseGen = creatorPoseGen + 1
    local p = creatorPose
    if not p then return end
    creatorPose = nil
    local ped = PlayerPedId()
    if p.scenario then
        if IsPedUsingScenario(ped, p.scenario) then ClearPedTasks(ped) end
    else
        if IsEntityPlayingAnim(ped, p.dict, p.anim, 3) then StopAnimTask(ped, p.dict, p.anim, 1.0) end
        RemoveAnimDict(p.dict)
    end
end

local function startCreatorPose()
    stopCreatorPose()
    if not (isCreatorOpen and creatorIsNew) then return end
    local name = (Config.Creator or {}).pose
    if not name then return end
    local def = Emotes and Emotes.get(name)
    if not (def and (def.dict or def.scenario)) then
        print(('^3[whip_core] Config.Creator.pose: no emote "%s" with an animation^7'):format(tostring(name)))
        return
    end
    local gen = creatorPoseGen
    CreateThread(function()
        if gen ~= creatorPoseGen then return end      -- stopped (or started again) before this ran
        if Emotes.current() then Emotes.stop() end   -- one thing plays on the ped
        if def.scenario then
            TaskStartScenarioInPlace(PlayerPedId(), def.scenario, 0, true)
            creatorPose = { scenario = def.scenario }
            return
        end
        if not LoadAnimDict(def.dict, 2000) then
            print(('^3[whip_core] Config.Creator.pose: "%s" would not load^7'):format(def.dict))
            return
        end
        if gen ~= creatorPoseGen then RemoveAnimDict(def.dict) return end   -- the creator closed while it loaded
        -- Looped or held on its last frame: stays until the creator closes.
        local flag = def.loop and 1 or 2
        TaskPlayAnim(PlayerPedId(), def.dict, def.anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
        creatorPose = { dict = def.dict, anim = def.anim }
        -- Held: anything that takes the ped off it is put back within POSE_CHECK_MS. Logged once in F8.
        local said = false
        while gen == creatorPoseGen do
            Wait(POSE_CHECK_MS)
            if gen ~= creatorPoseGen then break end
            local ped = PlayerPedId()
            if not IsEntityPlayingAnim(ped, def.dict, def.anim, 3) and not IsPedFalling(ped) and not IsPedRagdoll(ped)
                and not IsPedInAnyVehicle(ped, false) then
                TaskPlayAnim(ped, def.dict, def.anim, 8.0, -8.0, -1, flag, 0.0, false, false, false)
                if not said then
                    said = true
                    print('[whip_core] Config.Creator.pose: something took the character out of the pose; it is back')
                end
            end
        end
    end)
end

AddEventHandler('whip_core:appearance:modelChanged', function()
    if isCreatorOpen and creatorIsNew then startCreatorPose() end
end)

---@param heading table|nil  { title, sub, store }: the editor's heading (EditLook's: whose look it is), and
---                           EditAppearance's store ({ only, prices }: its tabs and the price on Save)
local function OpenCreator(appearance, isNew, heading)
    if isCreatorOpen then return end
    isCreatorOpen = true
    CreatorIsOpen = true
    creatorIsNew = isNew and true or false
    creatorClosing = false

    -- The ped must not be frozen: FreezeEntityPosition locks rotation too, and a ped caught mid-turn shuffles.

    -- Back up the appearance for cancel, as a deep copy (/charedit passes PlayerData.metadata.appearance itself).
    savedAppearance = json.decode(json.encode(appearance))

    -- Fresh preview session: the first preview takes the full apply path.
    previewLastBlendSig = nil
    previewLastApplied = nil
    previewLastTattooSig = nil
    previewFieldGen = {}
    previewFullGen = 0
    previewGen = previewGen + 1

    -- Send appearance, max variations and the character's outfits (server/events_misc.lua) to the NUI
    local maxes = GetMaxVariations()
    SendNUIMessage({
        action = 'openCreator',
        appearance = appearance,
        maxVariations = maxes,
        isNew = isNew or false,
        title = heading and heading.title or nil,
        sub = heading and heading.sub or nil,
        store = heading and heading.store or nil,   -- EditAppearance: { only, prices }
        outfits = PlayerData and PlayerData.metadata and PlayerData.metadata.outfits or {},
        outfitMax = math.max(1, math.min(100, math.floor(tonumber((Config.Creator or {}).maxOutfits) or 20))),   -- the server's bounds
    })
    if maxes.icons then askPictures(maxes.icons.gender) end
    Focus.take('creator', { screen = true })
    StartCreatorCamera('torso')
    startCreatorPose()   -- a new character only (Config.Creator.pose)
end

--- Close the creator, and for a brand new character hand them over to the world. The move happens
--- black; the server releases the private bucket, so the client waits for whip_core:client:creatorFinished.
local CloseCreator

local function FinishCreator()
    if creatorClosing then return end

    if not creatorIsNew then
        CloseCreator()
        return
    end

    -- The UI comes down before the fade: NUI draws above a fade and would stay clickable.
    creatorClosing = true
    SendNUIMessage({ action = 'closeCreator' })
    Focus.release('creator')

    CreateThread(function()
        local cfg = Config.Creator or {}

        -- Through the curtain (client/curtain.lua): GiveToGame hands the blackout to the game's fade.
        Curtain.GiveToGame(cfg.fadeOut or 800)

        CloseCreator()
        if WeatherLayer then WeatherLayer.set('creator', nil) end
        TriggerServerEvent('whip_core:server:creatorDone')
    end)
end

--- The server has put us back in the shared world: travel to the spawn point and bring the picture back.
RegisterNetEvent('whip_core:client:creatorFinished', function()
    local ccfg = Config.Creator or {}

    -- Wait for the camera blend to land (CreatorCameraIsActive): teleporting mid-blend flies across the map. Bounded.
    local waited = 0
    while CreatorCameraIsActive() and waited < 2000 do
        Wait(16); waited = waited + 16
    end

    SpawnCharacterAt(PlayerData)

    -- A beat for the world to settle (SpawnCharacterAt waits for the ped itself, client/spawn.lua).
    Wait(ccfg.arriveHoldMs or 500)

    -- Through the curtain at arrival weight (CharSelect.TIMES in client/charselect.lua).
    Curtain.TakeFromGame()
    Curtain.Uncover(ccfg.fadeIn or 800)
end)

-- Assignment: the local is declared above.
function CloseCreator()
    if not isCreatorOpen then return end
    isCreatorOpen = false
    CreatorIsOpen = false
    creatorIsNew = false
    creatorClosing = false
    stopCreatorPose()

    -- Nothing to unfreeze or restore (see OpenCreator).
    DestroyCreatorCamera()
    SendNUIMessage({ action = 'closeCreator' })
    Focus.release('creator')

    savedAppearance = nil
end

--- The creator on someone else's look (EditLook) is done: the saved look, or nil for Cancel. A headshot is taken
--- first, then the player's own look goes back on, then the caller is told.
local function FinishLook(look)
    if creatorClosing then return end
    local job = lookFor
    lookFor = nil
    creatorClosing = true
    SendNUIMessage({ action = 'closeCreator' })
    Focus.release('creator')
    CreateThread(function()
        DoScreenFadeOut(300)
        Wait(300)
        local headshot = look and TakeHeadshot and TakeHeadshot(PlayerPedId()) or nil
        KillCreatorCamera()   -- the screen is black: no flight home
        CloseCreator()
        local own = PlayerData and PlayerData.metadata and PlayerData.metadata.appearance
        if not (own and own.model) then own = GetDefaultAppearance(PlayerData and PlayerData.gender or 'male') end
        SwapModelAndApply(own)
        Wait(300)
        DoScreenFadeIn(500)
        if job and job.done then job.done(look, headshot) end
    end)
end

-- Player loaded: apply appearance / open creator

--- Put the character's face and body on. Returns the appearance to hand the creator for a new character.
--- A step of the load sequence behind a black screen (client/player.lua); blocks until the model is on.
---@param data table  the serialized player from playerLoaded
---@return table|nil creatorAppearance  non-nil when a new character needs the creator opened
function ApplyLoadedAppearance(data)
    if not data then return nil end

    local gender = data.gender or 'male'
    local metadata = data.metadata or {}
    local existingAppearance = metadata.appearance

    -- openCreator: a character just made, or one whose creator was never finished.
    if data.openCreator or data.isNewCharacter then
        local appearance = GetDefaultAppearance(gender)
        SwapModelAndApply(appearance)
        return appearance
    elseif existingAppearance and existingAppearance.model then
        SwapModelAndApply(existingAppearance)
    else
        -- No creator data: at least use the right freemode model.
        SwapModelAndApply(GetDefaultAppearance(gender))
    end

    return nil
end

--- Open the creator for a character that has just been made (OpenCreator is local to this file).
---@param appearance table
function OpenCreatorForNewCharacter(appearance)
    if not appearance then return end
    OpenCreator(appearance, true)
end

-- NUI callbacks

--- One string describing this head blend's inputs, compared between previews.
local function blendSig(hb)
    hb = hb or {}
    return ('%s|%s|%s|%s|%s|%s'):format(
        hb.mom or 0, hb.dad or 0, hb.grandparent or 0,
        hb.faceWeight or 0.5, hb.skinWeight or 0.5, hb.thirdWeight or 0.0)
end

--- Apply only what changed between two previews (a full ApplyAppearance is ~50 natives a frame).
--- The rules mirror ApplyAppearance (255 overlay clear, color-type table, ClearPedProp on -1, `+ 0.0`):
--- change both together.
local function applyPreviewDelta(ped, appearance, last)
    local ff, lf = appearance.faceFeatures or {}, last.faceFeatures or {}
    for i = 0, 19 do
        local v = tonumber(ff[i + 1]) or 0.0
        if v ~= (tonumber(lf[i + 1]) or 0.0) then
            SetPedFaceFeature(ped, i, v + 0.0)
        end
    end

    if (appearance.eyeColor or 0) ~= (last.eyeColor or 0) then
        SetPedEyeColor(ped, appearance.eyeColor or 0)
    end

    local h, lh = appearance.hair or {}, last.hair or {}
    if (h.style or 0) ~= (lh.style or 0) or (h.texture or 0) ~= (lh.texture or 0) then
        SetPedComponentVariation(ped, 2, h.style or 0, h.texture or 0, 0)
    end
    if (h.color or 0) ~= (lh.color or 0) or (h.highlight or 0) ~= (lh.highlight or 0) then
        SetPedHairColor(ped, h.color or 0, h.highlight or 0)
    end

    local ovs, lovs = appearance.overlays or {}, last.overlays or {}
    for name, overlayId in pairs(OVERLAY_IDS) do
        local o, lo = ovs[name] or {}, lovs[name] or {}
        if (o.type or 0) ~= (lo.type or 0) or (o.opacity or 0.0) ~= (lo.opacity or 0.0)
            or (o.color or 0) ~= (lo.color or 0) or (o.color2 or 0) ~= (lo.color2 or 0) then
            local ovType, ovOpacity = o.type or 0, o.opacity or 0.0
            if ovType == 0 and ovOpacity == 0.0 then
                SetPedHeadOverlay(ped, overlayId, 255, 0.0)
            else
                SetPedHeadOverlay(ped, overlayId, ovType, ovOpacity + 0.0)
            end
            local colorType = OVERLAY_COLOR_TYPE[name]
            if colorType and ovType ~= 255 then
                SetPedHeadOverlayColor(ped, overlayId, colorType, o.color or 0, o.color2 or 0)
            end
        end
    end

    -- No safeComponent clamp: the values come from this ped's own card grid, and a clamp would differ from what is saved.
    local comps, lcomps = appearance.components or {}, last.components or {}
    for compId, comp in pairs(comps) do
        local id = tonumber(compId)
        if id then
            local lc = lcomps[compId] or {}
            if (comp.drawable or 0) ~= (lc.drawable or 0) or (comp.texture or 0) ~= (lc.texture or 0) then
                SetPedComponentVariation(ped, id, comp.drawable or 0, comp.texture or 0, 0)
            end
        end
    end

    local props, lprops = appearance.props or {}, last.props or {}
    for propId, prop in pairs(props) do
        local id = tonumber(propId)
        if id then
            local lp = lprops[propId] or {}
            if (prop.drawable or -1) ~= (lp.drawable or -1) or (prop.texture or 0) ~= (lp.texture or 0) then
                if (prop.drawable or -1) == -1 then
                    ClearPedProp(ped, id)
                else
                    SetPedPropIndex(ped, id, prop.drawable, prop.texture or 0, true)
                end
            end
        end
    end

    -- Tattoos and the fade: the whole list again, or nothing (see applyTattoos).
    local sig = tattooSig(appearance.tattoos, appearance.hairFade)
    if sig ~= previewLastTattooSig then
        applyTattoos(ped, appearance.tattoos, appearance.hairFade)
        previewLastTattooSig = sig
    end
end

-- Preview changes in real time. The NUI streams a preview per frame during a drag, and re-setting the head
-- blend restarts its asynchronous bake. Rules:
--   1. Blend unchanged: no re-bake, no wait, only changed fields applied (applyPreviewDelta).
--   2. Blend changed or no snapshot yet: the full ApplyAppearance path, which re-bakes and waits.
--   3. After any wait a generation stamp decides whether this preview may still paint or store its
--      snapshot (nil forces a full resync next frame).
RegisterNUICallback('previewAppearance', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end

    local appearance = data.appearance
    if not appearance then cb({ ok = false }) return end

    previewGen = previewGen + 1
    local myGen = previewGen
    local ped = PlayerPedId()

    local sig = blendSig(appearance.headBlend)
    local blendChanged = (sig ~= previewLastBlendSig)
    previewLastBlendSig = sig

    if blendChanged or not previewLastApplied then
        -- Full path: sets blend, waits out the bake. Tattoos only when changed (see skipTattoos).
        local tSig = tattooSig(appearance.tattoos, appearance.hairFade)
        local tattoosOn = (tSig == previewLastTattooSig)
        previewLastTattooSig = tSig
        ApplyAppearance(ped, appearance, nil, tattoosOn)
        previewFullGen = myGen
        if myGen == previewGen then
            previewLastApplied = appearance
        else
            -- Superseded while waiting: drop the baseline so the next preview re-applies everything.
            previewLastApplied = nil
            previewLastTattooSig = nil
        end
        cb({ ok = true })
        return
    end

    if not HasPedHeadBlendFinished(ped) then
        -- Same blend, but an earlier bake is still landing: wait so our writes are not wiped; stand down if superseded.
        local deadline = GetGameTimer() + 500
        while not HasPedHeadBlendFinished(ped) and GetGameTimer() < deadline do
            Wait(0)
        end
        if myGen ~= previewGen then cb({ ok = true }) return end
    end

    applyPreviewDelta(ped, appearance, previewLastApplied)
    -- The ped now matches in full: same staleness floor as the full path.
    previewFullGen = myGen
    previewLastApplied = appearance
    cb({ ok = true })
end)

--- Preview one field from the small-payload lane. `gen` is the message's generation; `previewFieldGen`
--- remembers which generation last wrote each field, so a message that waited out a bake writes a
--- field only if nothing newer has. Rules mirror ApplyAppearance: change both together.
local function applyPreviewPart(ped, part, gen)
    -- A full preview wrote every field: one floor check instead of stamping each.
    if gen < previewFullGen then return end

    local kind = part.kind

    if kind == 'feature' then
        local idx = tonumber(part.idx)
        if not idx or idx < 0 or idx > 19 then return end
        local field = 'f' .. idx
        if (previewFieldGen[field] or 0) > gen then return end
        previewFieldGen[field] = gen

        local value = (tonumber(part.value) or 0.0) + 0.0
        SetPedFaceFeature(ped, idx, value)
        -- Keep the delta baseline current. The part's idx is the native (0-based) index; Lua arrays are 1-based.
        if previewLastApplied and previewLastApplied.faceFeatures then
            previewLastApplied.faceFeatures[idx + 1] = value
        end

    elseif kind == 'overlay' then
        local name = part.key
        local overlayId = name and OVERLAY_IDS[name]
        if not overlayId then return end
        local field = 'o' .. name
        if (previewFieldGen[field] or 0) > gen then return end
        previewFieldGen[field] = gen

        local ovType = tonumber(part.type) or 0
        local ovOpacity = tonumber(part.opacity) or 0.0
        local color = tonumber(part.color) or 0
        local color2 = tonumber(part.color2) or 0

        if ovType == 0 and ovOpacity == 0.0 then
            SetPedHeadOverlay(ped, overlayId, 255, 0.0)
        else
            SetPedHeadOverlay(ped, overlayId, ovType, ovOpacity + 0.0)
        end
        local colorType = OVERLAY_COLOR_TYPE[name]
        if colorType and ovType ~= 255 then
            SetPedHeadOverlayColor(ped, overlayId, colorType, color, color2)
        end

        if previewLastApplied and previewLastApplied.overlays then
            local snap = previewLastApplied.overlays[name]
            if snap then
                snap.type, snap.opacity = ovType, ovOpacity
                if colorType then snap.color, snap.color2 = color, color2 end
            end
        end
    end
end

-- Small-payload preview lane for controls that stream a value every frame (feature pads, fine sliders,
-- overlay opacity): one field (~60 bytes) instead of the whole appearance (~2-3KB). Discrete edits use
-- the full lane, which also re-establishes the delta baseline.
RegisterNUICallback('previewParts', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end

    local parts = data.parts
    if type(parts) ~= 'table' or #parts == 0 then cb({ ok = false }) return end

    -- Supersedes any full preview still waiting on a bake.
    previewGen = previewGen + 1
    local myGen = previewGen
    local ped = PlayerPedId()

    -- A head blend bake in flight wipes face features when it lands: wait it out (only right after a heritage edit).
    if not HasPedHeadBlendFinished(ped) then
        local deadline = GetGameTimer() + 500
        while not HasPedHeadBlendFinished(ped) and GetGameTimer() < deadline do
            Wait(0)
        end
    end

    for i = 1, #parts do
        applyPreviewPart(ped, parts[i], myGen)
    end
    cb({ ok = true })
end)

-- Save appearance
RegisterNUICallback('saveAppearance', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end

    local appearance = data.appearance
    if not appearance then cb({ ok = false }) return end

    -- Someone else's look (EditLook): it goes to whoever asked, never onto this character.
    if lookFor then
        cb({ ok = true })
        FinishLook(appearance)
        return
    end

    -- A store (EditAppearance): Save goes to it, which charges and keeps the look (SetPlayerAppearance), or
    -- says why not and the editor stays open.
    if storeFor then
        cb({ ok = true })
        local job = storeFor
        if job.busy then return end
        job.busy = true
        CreateThread(function()
            -- The way the player chose at the checkout, when the store offers ways to pay; else nil.
            local method = job.methods[data.method] and data.method or nil
            local called, ok, why = pcall(job.onSave, appearance, method)
            job.busy = false
            if storeFor ~= job or not CreatorLive() then return end   -- closed meanwhile (a death, a logout)
            if called and ok == true then
                storeFor = nil
                -- What the server kept (its metadataChanged comes before the store's answer), else what was saved.
                local kept = PlayerData.metadata and PlayerData.metadata.appearance
                ApplyAppearance(PlayerPedId(), (kept and kept.model) and kept or appearance)
                FinishCreator()
                if job.onClose then pcall(job.onClose, true) end
            else
                if not called then print(('^1[whip_core] EditAppearance onSave failed: %s^0'):format(tostring(ok))) end
                SendNUIMessage({ action = 'creatorSaveRefused',
                    why = called and type(why) == 'string' and why ~= '' and why:sub(1, 60) or 'Not saved' })
            end
        end)
        return
    end

    local ped = PlayerPedId()
    ApplyAppearance(ped, appearance)

    -- Save to server
    TriggerServerEvent('whip_core:server:saveAppearance', appearance)

    -- Update local PlayerData
    if PlayerData.metadata then
        PlayerData.metadata.appearance = appearance
    end

    -- Answer the browser before the transition: FinishCreator blocks on a fade, and an unanswered callback holds the page up.
    cb({ ok = true })
    FinishCreator()
end)

-- Cancel creator
RegisterNUICallback('cancelCreator', function(_, cb)
    if not CreatorLive() then cb({ ok = false }) return end

    -- Someone else's look: nothing handed back; the player's own look goes back on (FinishLook).
    if lookFor then
        cb({ ok = true })
        FinishLook(nil)
        return
    end

    -- A store: not while it is charging for Save (the look may be kept a moment later).
    local job = storeFor
    if job and job.busy then cb({ ok = false }) return end
    storeFor = nil

    -- Restore saved appearance
    if savedAppearance and savedAppearance.model then
        local ped = PlayerPedId()
        ApplyAppearance(ped, savedAppearance)
    end

    -- A new character skipping the creator still enters the world, keeping the default look.
    cb({ ok = true })
    FinishCreator()
    if job and job.onClose then pcall(job.onClose, false) end
end)

-- Outfits tab buttons: save, save over, rename, delete. The server keeps the list (server/events_misc.lua);
-- the page gets { ok, outfits } or { ok = false, why }. Nothing here changes the ped.
local function answerOutfits(cb, list, why)
    if type(list) ~= 'table' then
        cb({ ok = false, why = type(why) == 'string' and why or 'No answer from the server' })
        return
    end
    cb({ ok = true, outfits = list })
end

RegisterNUICallback('saveOutfit', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    CreateThread(function()
        answerOutfits(cb, Callback('whip_core:appearance:saveOutfit', tostring(data.name or ''), data.outfit))
    end)
end)

RegisterNUICallback('updateOutfit', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    CreateThread(function()
        answerOutfits(cb, Callback('whip_core:appearance:updateOutfit', data.id, data.outfit))
    end)
end)

RegisterNUICallback('renameOutfit', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    CreateThread(function()
        answerOutfits(cb, Callback('whip_core:appearance:renameOutfit', data.id, tostring(data.name or '')))
    end)
end)

RegisterNUICallback('deleteOutfit', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    CreateThread(function()
        answerOutfits(cb, Callback('whip_core:appearance:deleteOutfit', data.id))
    end)
end)

-- Switch framing: only the rig's targets move. Unknown names fall back to 'torso'.
-- `yaw` also turns the camera round the ped (180 face-on, 0 from behind); sent alone it leaves framing,
-- zoom and height as they are.
RegisterNUICallback('switchCamera', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    local yaw = tonumber(data.yaw)
    if yaw ~= nil and not (yaw > -3600.0 and yaw < 3600.0) then yaw = nil end   -- NaN and the infinities too
    if data.preset or not yaw then ApplyCamFraming(data.preset) end
    if yaw then tYaw = wrap180(yaw) end
    cb({ ok = true })
end)

-- Where the open world is across the screen (creator.js reportStage); the ped is stood there. Kept short
-- of the edges. Snapped instead of eased while the camera is still flying in.
RegisterNUICallback('creatorStage', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    tShiftX = clampN(tonumber(data and data.x) or 0.0, -0.8, 0.8)
    if camPhase == 'enter' then camShiftX = tShiftX end
    cb({ ok = true })
end)

-- Camera input from the stage: pan (left-drag), orbit (right-drag), zoom (wheel), batched every ~32ms.
-- The clamps only guard against absurd payloads.
RegisterNUICallback('camInput', function(data, cb)
    if not CreatorLive() then cb({ ok = false }) return end
    local function lim(v, n)
        return math.max(-n, math.min(n, tonumber(v) or 0.0))
    end
    CamInput(lim(data.pan, 400.0), lim(data.orbitX, 400.0), lim(data.orbitY, 400.0), lim(data.zoom, 20.0))
    cb({ ok = true })
end)

-- Get max texture for a specific component/drawable combo
RegisterNUICallback('getMaxTexture', function(data, cb)
    local ped = PlayerPedId()
    local compType = data.type -- 'component' or 'prop' or 'hair'
    local id = tonumber(data.id) or 0
    local drawable = tonumber(data.drawable) or 0

    local maxTex = 0
    if compType == 'component' then
        maxTex = GetNumberOfPedTextureVariations(ped, id, drawable)
    elseif compType == 'prop' then
        maxTex = (drawable >= 0) and GetNumberOfPedPropTextureVariations(ped, id, drawable) or 0
    elseif compType == 'hair' then
        maxTex = GetNumberOfPedTextureVariations(ped, 2, drawable)
    end

    cb({ maxTexture = maxTex })
end)

-- (The page gets the max variations with the open message, GetMaxVariations.)

-- /charedit

--- Open the character editor on this character (/charedit, and the server's OpenCharacterEditor export below).
--- Waits; call it from a thread.
---@return boolean ok
---@return string|nil why
---@param heading table|nil  { title, sub, store }: EditAppearance's heading and store
function OpenCharacterEditor(heading)
    if not PlayerLoaded then return false, 'No character loaded.' end
    if isCreatorOpen then return false, 'Creator is already open.' end
    if PlayerIsDead then return false, 'Not while dead.' end

    -- Appearance from metadata, or built from the ped
    local appearance
    if PlayerData.metadata and PlayerData.metadata.appearance and PlayerData.metadata.appearance.model then
        appearance = PlayerData.metadata.appearance
    else
        -- No saved appearance: default by gender
        local gender = PlayerData.gender or 'male'
        appearance = GetDefaultAppearance(gender)
    end

    -- No fade unless there is a model swap to hide.
    local ped = PlayerPedId()
    local expectedModel = GetHashKey(appearance.model or 'mp_m_freemode_01')
    local needsSwap = (GetEntityModel(ped) ~= expectedModel)

    if needsSwap then
        DoScreenFadeOut(300)
        Wait(300)
        SwapModelAndApply(appearance)
        Wait(300)
    end

    OpenCreator(appearance, false, heading)

    -- Raised only if it was dropped, after the creator is up.
    if needsSwap then
        DoScreenFadeIn(500)
    end
    return true
end

-- Developer mode only: nothing else checks the place, a price or a permission.
DevCommand('charedit', function()
    local ok, why = OpenCharacterEditor()
    if not ok then
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            args = {'[whip_core]', why}
        })
    end
end)

-- The server opens it: the OpenCharacterEditor export and the object viewer's Force open character editor
-- (OpenCharacterEditorFor, server/events_misc.lua).
RegisterNetEvent('whip_core:client:openCharacterEditor', function()
    if not PlayerLoaded then return end
    CreateThread(function()
        if Emotes then Emotes.stop() end
        local ok, why = OpenCharacterEditor()
        if not ok then print('[whip_core] the character editor the server opened did not open: ' .. tostring(why)) end
    end)
end)

--- Change Model (object viewer, client/ov_effects.lua): the ped becomes `model` with its default look until
--- WearModel(nil) restores the character. Never saved. Waits; call it from a thread.
---@param model string|nil
---@return boolean ok
function WearModel(model)
    if not PlayerLoaded then return false end
    if model == nil then
        local own = PlayerData.metadata and PlayerData.metadata.appearance
        if not (own and own.model) then own = GetDefaultAppearance(PlayerData.gender or 'male') end
        return SwapModelAndApply(own) ~= false
    end
    if not IsModelInCdimage(GetHashKey(model)) or not IsModelAPed(GetHashKey(model)) then
        print(('[whip_core] Change Model: %s is not a ped this game has'):format(tostring(model)))
        return false
    end
    -- SwapModelAndApply's swap, with the model's default look.
    return SwapModelAndApply({ model = model, default = true }) ~= false
end

-- EditLook: the creator on a look that is not this character's (a lore character's, tools/panel_sections/director.lua).
-- The player's ped wears it while the creator is open; nothing is saved to the character. Save hands the look
-- back with a headshot, Cancel hands back nothing; the player's own look is restored first.

--- Why the player cannot edit a look now, or nil.
---@return string|nil why
function LookEditProblem()
    if not PlayerLoaded then return 'No character loaded' end
    if isCreatorOpen then return 'The character editor is already open' end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return 'Not while dead' end
    if IsPedInAnyVehicle(ped, true) then return 'Get out of the vehicle first' end
    -- A new ped keeps nothing in hand.
    if GetSelectedPedWeapon(ped) ~= GetHashKey('WEAPON_UNARMED') then return 'Put your weapon away first' end
    return nil
end

--- The player's look now: the saved face with the clothes, props and hair worn this moment. A copy.
--- nil and why when the ped is not the character's own. For Copy my look (tools/panel_sections/director.lua).
---@return table|nil look
---@return string|nil why
function CurrentAppearance()
    if not PlayerLoaded then return nil, 'No character loaded' end
    if lookFor then return nil, 'The character editor is open on another look' end
    local saved = PlayerData.metadata and PlayerData.metadata.appearance
    if not (saved and saved.model) then return nil, 'Your character has no look saved yet (/charedit)' end
    local ped = PlayerPedId()
    if GetEntityModel(ped) ~= GetHashKey(saved.model) then return nil, 'You are not wearing your own character right now' end
    local look = json.decode(json.encode(saved))
    -- Hair is component 2, kept as `hair`.
    look.components = {}
    for i = 0, 11 do
        if i ~= 2 then
            look.components[tostring(i)] = { drawable = GetPedDrawableVariation(ped, i), texture = GetPedTextureVariation(ped, i) }
        end
    end
    look.props = {}
    for _, i in ipairs(PROP_SLOTS) do
        look.props[tostring(i)] = { drawable = GetPedPropIndex(ped, i), texture = math.max(0, GetPedPropTextureIndex(ped, i)) }
    end
    look.hair = type(look.hair) == 'table' and look.hair or {}
    look.hair.style, look.hair.texture = GetPedDrawableVariation(ped, 2), GetPedTextureVariation(ped, 2)
    look.hair.color, look.hair.highlight = GetPedHairColor(ped), GetPedHairHighlightColor(ped)
    return look
end

--- Open the creator on a look that is not this character's. Waits; call it from a thread.
---@param opts table  { appearance = the look to start from | nil, gender = 'male' | 'female' (a new look's),
---                     title, sub = the editor's heading, done = function(look | nil, headshot | nil) }
---@return boolean ok
---@return string|nil why
function EditLook(opts)
    opts = type(opts) == 'table' and opts or {}
    local why = LookEditProblem()
    if why then return false, why end
    local look = type(opts.appearance) == 'table' and opts.appearance.model and json.decode(json.encode(opts.appearance))
        or GetDefaultAppearance(opts.gender == 'female' and 'female' or 'male')
    DoScreenFadeOut(300)
    Wait(300)
    if not SwapModelAndApply(look) then
        DoScreenFadeIn(300)
        return false, 'That look\'s ped could not be loaded'
    end
    lookFor = { done = opts.done }
    OpenCreator(look, false, { title = opts.title, sub = opts.sub })
    Wait(300)
    DoScreenFadeIn(500)
    return true
end

local function callable(v)
    if type(v) == 'function' then return true end
    if type(v) ~= 'table' then return false end
    if rawget(v, '__cfx_functionReference') ~= nil then return true end
    local mt = getmetatable(v)
    return type(mt) == 'table' and rawget(mt, '__call') ~= nil
end

--- The editor on this character's own look, as a store: only the tabs `only` names, the price of what changed on
--- Save, and Save handed to onSave(look), which charges and keeps it (server: SetPlayerAppearance) and returns
--- true, or false, 'why' (said on Save; the editor stays open). With `methods` ('cash', 'bank'), Save first opens a
--- checkout (the total, a tile for each way to pay, what `wallet` says the player has there) and onSave gets the one
--- chosen. Waits for the fade only; call it from a thread.
---@param opts table  { only = { category ids or groups }, prices = { [id or group or 'default'] = $ each },
---                     methods = { 'cash', 'bank' } | nil, wallet = { cash = n, bank = n } | nil,
---                     title, sub, onSave = function(look, method) -> ok, why, onClose = function(saved) | nil }
---@return boolean ok
---@return string|nil why
function EditAppearance(opts)
    if type(opts) ~= 'table' or not callable(opts.onSave) then return false, 'onSave is required' end
    local why = LookEditProblem()
    if why then return false, why end
    local only, prices = {}, {}
    for _, v in ipairs(type(opts.only) == 'table' and opts.only or {}) do
        if type(v) == 'string' then only[#only + 1] = v end
    end
    for k, v in pairs(type(opts.prices) == 'table' and opts.prices or {}) do
        if type(k) == 'string' and type(v) == 'number' and v >= 0 then prices[k] = v end
    end
    -- The checkout: the ways to pay offered, and what the player has in each (the store's server knows; optional).
    local methods, methodSet, wallet = {}, {}, {}
    for _, m in ipairs(type(opts.methods) == 'table' and opts.methods or {}) do
        if (m == 'cash' or m == 'bank') and not methodSet[m] then methods[#methods + 1] = m; methodSet[m] = true end
    end
    local w = type(opts.wallet) == 'table' and opts.wallet or {}
    for _, m in ipairs({ 'cash', 'bank' }) do
        if type(w[m]) == 'number' then wallet[m] = w[m] end
    end
    storeFor = { onSave = opts.onSave, onClose = callable(opts.onClose) and opts.onClose or nil, busy = false,
                 methods = methodSet }
    local ok, err = OpenCharacterEditor({
        title = type(opts.title) == 'string' and opts.title or nil,
        sub = type(opts.sub) == 'string' and opts.sub or nil,
        store = { only = only, prices = prices, methods = methods, wallet = wallet },
    })
    if not ok then storeFor = nil end
    return ok, err
end

exports('EditAppearance', EditAppearance)

--- A store's editor closed without a Save (a death, a logout): tell it, once.
local function dropStore()
    local job = storeFor
    storeFor = nil
    if job and job.onClose then CreateThread(function() pcall(job.onClose, false) end) end
end

-- Resource stop: release the camera, NUI focus and this file's open/closing flags.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if not isCreatorOpen then return end

    if WeatherLayer then WeatherLayer.set('creator', nil) end

    -- Kill the camera outright before the normal close: there is no next frame to fly it home.
    KillCreatorCamera()
    CloseCreator()
end)

-- A death closes it as Cancel does (it would hold NUI focus over the death screen). The blackout is already
-- up: no flight home. A new character's creator opens again once they are alive.
local reopenOnRevive = nil   -- that new character's look to open on

AddEventHandler('whip_core:player:died', function()
    if not CreatorLive() then return end
    if lookFor then FinishLook(nil) return end
    dropStore()
    local back = savedAppearance
    if creatorIsNew then reopenOnRevive = back or GetDefaultAppearance(PlayerData and PlayerData.gender or 'male') end
    KillCreatorCamera()
    CloseCreator()
    if back and back.model then
        CreateThread(function() ApplyAppearance(PlayerPedId(), back) end)
    end
end)

AddEventHandler('whip_core:player:revived', function()
    local look = reopenOnRevive
    reopenOnRevive = nil
    if look and PlayerLoaded then OpenCreator(look, true) end
end)

-- A logout closes it too, before the character screen is built (its Save would write onto the next character). Nothing is saved.
AddEventHandler('whip_core:player:logout', function()
    lookFor = nil   -- someone else's look is dropped with it: the character screen makes a new ped anyway
    dropStore()
    local waiting = reopenOnRevive ~= nil
    reopenOnRevive = nil
    if not isCreatorOpen and not waiting then return end
    if WeatherLayer then WeatherLayer.set('creator', nil) end
    KillCreatorCamera()   -- the screen is going black: no flight home
    CloseCreator()
end)
