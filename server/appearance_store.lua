-- ============================================
-- A look kept by a store: GetAppearanceChanges and SetPlayerAppearance
-- ============================================
--
-- For a clothes shop, a barber or a tattoo parlour (a resource's): the player edits their own look in the character
-- editor on only the store's tabs (client/appearance.lua EditAppearance), and the store's server asks what changed,
-- charges for it, and keeps it. `only` names the tabs, as the editor's category ids ('tops', 'hair', 'makeup') or its
-- groups ('face', 'apparel', 'props', 'tattoos', 'outfits'); only those parts are taken from the new look, the rest
-- stays the character's. The counts are html/js/creator-store.js's, which prices Save in the editor: keep the two
-- the same, and the categories html/js/creator-data.js's.

-- The editor's tabs (creator-data.js CATEGORIES), as far as the save is concerned.
local CATEGORIES = {
    { id = 'heritage',    cluster = 'face',    kind = 'heritage' },
    { id = 'features',    cluster = 'face',    kind = 'features' },
    { id = 'eyes',        cluster = 'face',    kind = 'eyes' },
    { id = 'hair',        cluster = 'face',    kind = 'hair' },
    { id = 'eyebrows',    cluster = 'face',    kind = 'overlays', overlays = { 'eyebrows' } },
    { id = 'beard',       cluster = 'face',    kind = 'overlays', overlays = { 'beard' } },
    { id = 'makeup',      cluster = 'face',    kind = 'overlays', overlays = { 'makeup', 'blush', 'lipstick' } },
    { id = 'skin',        cluster = 'face',    kind = 'overlays', overlays = { 'blemishes', 'ageing', 'complexion', 'sunDamage', 'moles' } },
    { id = 'chestHair',   cluster = 'face',    kind = 'overlays', overlays = { 'chestHair' } },
    { id = 'mask',        cluster = 'apparel', kind = 'component', comp = 1 },
    { id = 'tops',        cluster = 'apparel', kind = 'component', comp = 11 },
    { id = 'undershirt',  cluster = 'apparel', kind = 'component', comp = 8 },
    { id = 'arms',        cluster = 'apparel', kind = 'component', comp = 3 },
    { id = 'legs',        cluster = 'apparel', kind = 'component', comp = 4 },
    { id = 'shoes',       cluster = 'apparel', kind = 'component', comp = 6 },
    { id = 'accessory',   cluster = 'apparel', kind = 'component', comp = 7 },
    { id = 'armor',       cluster = 'apparel', kind = 'component', comp = 9 },
    { id = 'decal',       cluster = 'apparel', kind = 'component', comp = 10 },
    { id = 'bag',         cluster = 'apparel', kind = 'component', comp = 5 },
    { id = 'hat',         cluster = 'props',   kind = 'prop', prop = 0 },
    { id = 'glasses',     cluster = 'props',   kind = 'prop', prop = 1 },
    { id = 'ear',         cluster = 'props',   kind = 'prop', prop = 2 },
    { id = 'watch',       cluster = 'props',   kind = 'prop', prop = 6 },
    { id = 'bracelet',    cluster = 'props',   kind = 'prop', prop = 7 },
    { id = 'tatHead',     cluster = 'tattoos', kind = 'tattoos' },
    { id = 'tatTorso',    cluster = 'tattoos', kind = 'tattoos' },
    { id = 'tatLeftArm',  cluster = 'tattoos', kind = 'tattoos' },
    { id = 'tatRightArm', cluster = 'tattoos', kind = 'tattoos' },
    { id = 'tatLeftLeg',  cluster = 'tattoos', kind = 'tattoos' },
    { id = 'tatRightLeg', cluster = 'tattoos', kind = 'tattoos' },
    { id = 'outfits',     cluster = 'outfits', kind = 'outfits' },
}

local EPS = 0.001

local function same(a, b)
    if type(a) == 'number' and type(b) == 'number' then return math.abs(a - b) < EPS end
    return a == b
end

local function slotSame(a, b)
    a, b = a or {}, b or {}
    return same(a.drawable, b.drawable) and same(a.texture, b.texture)
end

local function overlaySame(a, b)
    a, b = a or {}, b or {}
    for _, k in ipairs({ 'type', 'opacity', 'color', 'color2' }) do
        if not same(a[k] or 0, b[k] or 0) then return false end
    end
    return true
end

local function tattooKey(t)
    return (tostring(t.collection) .. '|' .. tostring(t.overlay)):lower()
end

--- `only` as a set, or nil for every tab; false, why for something that is not a list of names.
local function readOnly(only)
    if only == nil then return nil end
    if type(only) ~= 'table' then return false, 'only is a list of the editor\'s tabs or groups' end
    local set = {}
    for _, v in ipairs(only) do
        if type(v) == 'string' then set[v] = true end
    end
    return next(set) and set or nil
end

local function allows(set, cat)
    return not set or set[cat.id] or set[cat.cluster] or false
end

local function deep(v) return json.decode(json.encode(v)) end

--- { [category id] = count, tattoos = count } between two sanitized looks, in the tabs `set` offers.
local function changes(from, to, set)
    local out = {}
    local function add(k, n) if n > 0 then out[k] = (out[k] or 0) + n end end
    local tattoosDone = false
    for _, cat in ipairs(CATEGORIES) do
        if allows(set, cat) then
            if cat.kind == 'heritage' then
                local a, b = from.headBlend or {}, to.headBlend or {}
                for _, k in ipairs({ 'mom', 'dad', 'grandparent', 'faceWeight', 'skinWeight', 'thirdWeight' }) do
                    if not same(a[k], b[k]) then add(cat.id, 1) break end
                end
            elseif cat.kind == 'features' then
                local a, b = from.faceFeatures or {}, to.faceFeatures or {}
                for i = 1, 20 do
                    if not same(a[i] or 0, b[i] or 0) then add(cat.id, 1) break end
                end
            elseif cat.kind == 'eyes' then
                add(cat.id, same(from.eyeColor, to.eyeColor) and 0 or 1)
            elseif cat.kind == 'hair' then
                local a, b = from.hair or {}, to.hair or {}
                local diff = (from.hairFade and tattooKey(from.hairFade) or '') ~= (to.hairFade and tattooKey(to.hairFade) or '')
                for _, k in ipairs({ 'style', 'texture', 'color', 'highlight' }) do
                    if not same(a[k], b[k]) then diff = true end
                end
                add(cat.id, diff and 1 or 0)
            elseif cat.kind == 'overlays' then
                for _, key in ipairs(cat.overlays) do
                    add(cat.id, overlaySame((from.overlays or {})[key], (to.overlays or {})[key]) and 0 or 1)
                end
            elseif cat.kind == 'component' then
                local k = tostring(cat.comp)
                add(cat.id, slotSame((from.components or {})[k], (to.components or {})[k]) and 0 or 1)
            elseif cat.kind == 'prop' then
                local k = tostring(cat.prop)
                local b = (to.props or {})[k] or {}
                add(cat.id, ((b.drawable or -1) >= 0 and not slotSame((from.props or {})[k], b)) and 1 or 0)
            elseif cat.kind == 'tattoos' and not tattoosDone then
                tattoosDone = true
                local had = {}
                for _, t in ipairs(from.tattoos or {}) do had[tattooKey(t)] = true end
                local n = 0
                for _, t in ipairs(to.tattoos or {}) do
                    if not had[tattooKey(t)] then n = n + 1 end
                end
                add('tattoos', n)
            end
        end
    end
    return out
end

--- The parts of `to` in the tabs `set` offers, put on a copy of `from`: the character's look with the store's work.
local function merge(from, to, set)
    if not set then return deep(to) end
    local out = deep(from)
    out.overlays = out.overlays or {}
    out.components = out.components or {}
    out.props = out.props or {}
    for _, cat in ipairs(CATEGORIES) do
        if allows(set, cat) then
            if cat.kind == 'heritage' then out.headBlend = deep(to.headBlend)
            elseif cat.kind == 'features' then out.faceFeatures = deep(to.faceFeatures)
            elseif cat.kind == 'eyes' then out.eyeColor = to.eyeColor
            elseif cat.kind == 'hair' then
                out.hair = deep(to.hair)
                out.hairFade = to.hairFade and deep(to.hairFade) or nil
                out.components['2'] = to.components and deep(to.components['2']) or out.components['2']
            elseif cat.kind == 'overlays' then
                for _, key in ipairs(cat.overlays) do
                    out.overlays[key] = to.overlays and deep(to.overlays[key]) or out.overlays[key]
                end
            elseif cat.kind == 'component' then
                local k = tostring(cat.comp)
                out.components[k] = to.components and deep(to.components[k]) or out.components[k]
            elseif cat.kind == 'prop' then
                local k = tostring(cat.prop)
                out.props[k] = to.props and deep(to.props[k]) or out.props[k]
            elseif cat.kind == 'tattoos' then
                out.tattoos = to.tattoos and deep(to.tattoos) or nil
            end
        end
    end
    return out
end

--- The online player's saved look and the sanitized new one, or nil, why.
local function both(who, look)
    local charId, src = WhoIs(who)
    if not charId then return nil, nil, nil, src end
    local player = src and Players[src]
    if not player then return nil, nil, nil, 'That character is not playing' end
    local from = player:getMetadata('appearance')
    if type(from) ~= 'table' or not from.model then return nil, nil, nil, 'That character has no look saved yet' end
    local encoded = json.encode(look)
    if not encoded or #encoded > 10000 then return nil, nil, nil, 'That look is too big' end
    local to, err = SanitizeAppearanceData(look)
    if not to then return nil, nil, nil, 'That look is not valid: ' .. tostring(err) end
    if to.model ~= from.model then return nil, nil, nil, 'That look is another body' end
    return player, from, to
end

exports('GetAppearanceChanges', function(who, look, only)
    local set, why = readOnly(only)
    if set == false then return false, why end
    local player, from, to, err = both(who, look)
    if not player then return false, err end
    return changes(from, to, set)
end)

exports('SetPlayerAppearance', function(who, look, opts)
    opts = type(opts) == 'table' and opts or {}
    local set, why = readOnly(opts.only)
    if set == false then return false, why end
    local player, from, to, err = both(who, look)
    if not player then return false, err end
    local kept = SanitizeAppearanceData(merge(from, to, set))
    if not kept then return false, 'That look is not valid' end
    player:setMetadata('appearance', kept)
    player:save()
    return true, kept
end)
