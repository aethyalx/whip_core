-- ============================================
-- Settings — the server half: the record, the file, and who may change what
-- ============================================
--
-- shared/settings.lua holds the values and applies them. This file:
--   * keeps the RECORD in the database: whip_settings (one row per changed setting: the value,
--     who changed it, when) and whip_settings_log (every change, old and new);
--   * mirrors the rows into settings.json, which both sides read at load (shared/settings.lua);
--   * at boot, makes what is in force match the database (Settings.loadAll), because the file may
--     be older than the database (the whip_core folder replaced in an update) or missing;
--   * changes settings for a PERMANENT admin (Settings.change): checked against the schema,
--     written in one transaction, mirrored, put in force, sent to every player;
--   * answers the panel (whip_core:settings:panel) and a player who has just loaded
--     (whip_core:server:settingsHello), so a player joining after a change gets it.
--
-- WHEN A CHANGE TAKES EFFECT is the schema's `apply`: 'live' settings are put in force at once on
-- the server and on every player; 'restart' ones are saved and wait for whip_core's next start.

local CORE = Settings.CORE
local DEVTOOLS = 'whip.devtools'

local function say(fmt, ...) print(('[whip_core:settings] ' .. fmt):format(...)) end

local function q(sql, params)
    local ok, res = pcall(MySQL.query.await, sql, params or {})
    if not ok then return nil, tostring(res) end
    return res
end

-- [owner][path] = { value, changedBy, changedAt }: the database, as last read or written
local rows = {}

-- ============================================
-- The record
-- ============================================

function Settings.ensureTable()
    local ok = CreateTable('whip_settings', [[
        CREATE TABLE IF NOT EXISTS `whip_settings` (
            `owner`     VARCHAR(64)  NOT NULL,
            `path`      VARCHAR(128) NOT NULL,
            `value`     MEDIUMTEXT   NOT NULL,
            `changedBy` VARCHAR(100) NULL,
            `changedAt` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`owner`, `path`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    local logOk = CreateTable('whip_settings_log', [[
        CREATE TABLE IF NOT EXISTS `whip_settings_log` (
            `id`        INT UNSIGNED NOT NULL AUTO_INCREMENT,
            `owner`     VARCHAR(64)  NOT NULL,
            `path`      VARCHAR(128) NOT NULL,
            `oldValue`  MEDIUMTEXT   NULL,
            `newValue`  MEDIUMTEXT   NULL,
            `changedBy` VARCHAR(100) NULL,
            `at`        TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `ix_whip_settings_log_path` (`owner`, `path`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    return ok and logOk
end

---@param v any
---@return string
local function toJson(v)
    return json.encode(Settings.encode(v))
end

---@param s string
---@return boolean ok, any value
local function fromJson(s)
    local ok, data = pcall(json.decode, s)
    if not ok or data == nil then return false end
    return true, Settings.decode(data)
end

--- The saved row for a setting, if it is one that counts: a row the boot check refused (out of
--- range, no longer a setting) is ignored, and config.lua's value stays.
---@param owner string
---@param path string
---@return table|nil
local function savedRow(owner, path)
    local row = rows[owner] and rows[owner][path]
    if row and not row.refused then return row end
    return nil
end

--- Is this value for the server only? Its entry says sides = 'server'. A satellite whose page is not
--- declared yet is kept server-only until it is: the safe way round for something that may be a
--- secret.
---@param owner string
---@param path string
---@return boolean
local function serverOnly(owner, path)
    local entry = Settings.entry(owner, path)
    if not entry then return owner ~= CORE end
    return (entry.sides or 'both') == 'server'
end

--- The rows as the two files: settings.json (every player downloads it: files{} in the manifest)
--- and server_settings.json (the server's only; the manifest's glob does not match it). Both are
--- { version, values = { [owner] = { [path] = encoded } } }.
---@return boolean
local function writeFile()
    local shared, private = {}, {}
    for owner, list in pairs(rows) do
        for path, row in pairs(list) do
            if not row.refused then
                local into = serverOnly(owner, path) and private or shared
                into[owner] = into[owner] or {}
                into[owner][path] = Settings.encode(row.value)
            end
        end
    end
    local okShared = SaveResourceFile(CORE, Settings.FILE, json.encode({ version = 1, values = shared }), -1)
    local okPrivate = SaveResourceFile(CORE, Settings.SERVER_FILE, json.encode({ version = 1, values = private }), -1)
    if not (okShared and okPrivate) then
        say('^1could not write the settings files: the database holds the change, and they are rebuilt at the next start^0')
    end
    return okShared == true and okPrivate == true
end

-- One write for a burst of item pages (Settings.pageRegistered's quiet path): gunny declares two
-- hundred as it starts.
local writeQueued = false
local function queueWrite()
    if writeQueued then return end
    writeQueued = true
    SetTimeout(0, function()
        writeQueued = false
        writeFile()
    end)
end

--- Is a value saved for this setting (one the checks took)?
---@param owner string
---@param path string
---@return boolean
function Settings.isSaved(owner, path)
    return savedRow(owner, path) ~= nil
end

--- What is saved for this setting: true and a copy of it, or false when nothing is.
---@param owner string
---@param path string
---@return boolean, any
function Settings.savedValue(owner, path)
    local row = savedRow(owner, path)
    if not row then return false end
    return true, Settings.copy(row.value)
end

---@param entry table|nil
---@return string
local function applyOf(entry)
    return entry and entry.apply or 'live'
end

-- ============================================
-- Boot: what is in force matches the database
-- ============================================

--- A boot loader (player_lifecycle.lua). Reads the rows, then puts in force whatever the file
--- did not already give this side at load: a live setting now, a restart one at the next start
--- (said in the console). Rewrites the file when it differs. Answers false on a failed read.
---@return boolean
function Settings.loadAll()
    local res, err = q('SELECT `owner`, `path`, `value`, `changedBy`, `changedAt` FROM `whip_settings`')
    if not res then
        say('^1the saved settings could not be read: %s^0', tostring(err))
        return false
    end
    rows = {}
    for _, r in ipairs(res) do
        local ok, v = fromJson(r.value)
        if not ok then
            say('^3%s.%s could not be read and is ignored^0', tostring(r.owner), tostring(r.path))
        else
            local row = { value = v, changedBy = r.changedBy, changedAt = r.changedAt }
            -- CHECKED LIKE THE FILE IS (shared/settings.lua): a row out of range, of the wrong type,
            -- or for a setting that no longer exists is ignored, not put in force. A satellite's
            -- is checked when it declares its page.
            if r.owner == CORE then
                local entry = Settings.entry(CORE, r.path)
                local good, checked = false, nil
                if entry then good, checked = Settings.check(entry, v) end
                if good then
                    row.value = checked
                else
                    row.refused = true
                    say('^3saved %s is %s: it is ignored, and config.lua\'s value stays^0', r.path,
                        entry and ('refused (' .. tostring(checked) .. ')') or 'not a setting any more')
                end
            end
            rows[r.owner] = rows[r.owner] or {}
            rows[r.owner][r.path] = row
        end
    end

    local applied, waiting, stale = 0, {}, false
    local function settle(owner, path, value)
        stale = true
        if owner ~= CORE then
            Settings.apply(owner, path, value)
            return
        end
        local entry = Settings.entry(CORE, path)
        if not entry then return end
        if applyOf(entry) == 'live' then
            if Settings.apply(CORE, path, value) then applied = applied + 1 end
        else
            waiting[#waiting + 1] = path
        end
    end

    -- Saved, but not what the files gave at load (or not in them at all).
    for owner, list in pairs(rows) do
        local file = Settings.fileValues(owner)
        for path in pairs(list) do
            local row = savedRow(owner, path)
            if row then
                local rec = file[path]
                if rec == nil or not Settings.same(rec.v, row.value) then
                    settle(owner, path, row.value)
                end
            end
        end
    end
    -- In the files, but no longer saved: back to the default. A satellite's is forgotten instead (its
    -- page, and so its default, is not declared yet; reading it then gives the default).
    for owner, list in pairs(Settings.allFileValues()) do
        for path in pairs(list) do
            if not savedRow(owner, path) then
                if owner == CORE then
                    settle(owner, path, Settings.default(owner, path))
                else
                    stale = true
                    Settings.forget(owner, path)
                end
            end
        end
    end

    if stale then
        writeFile()
        say('the settings files were out of date and have been rebuilt from the database')
    end
    if applied > 0 then say('%d saved setting(s) put in force', applied) end
    if #waiting > 0 then
        say('^3%d saved setting(s) take effect at the next start: %s^0', #waiting, table.concat(waiting, ', '))
    end
    local n = 0
    for _, list in pairs(rows) do for _ in pairs(list) do n = n + 1 end end
    return n
end

--- A satellite declared its page (shared/settings.lua, Settings.register): its saved rows are checked
--- now, as config.lua's are at start (a refused one is ignored, its value already forgotten there);
--- the files are written again, since only now is it known which values players may have; and the
--- players online are sent its values (they loaded before it declared them).
---
--- THIS IS THE SATELLITE STARTING, so a setting of its that waits for a restart (apply = 'restart')
--- takes effect now: what is in force becomes what is saved, and one reset while it ran goes back
--- to its default.
---
--- AN ITEM'S PAGE IS QUIET (opts.quiet, server/item_settings.lua): its values are checked and put in
--- force the same way, but they are all for the server only, so no player is sent them here (that
--- file sends its own), no panel is told, and one file write covers the burst.
---@param owner string
---@param opts table|nil  { quiet = true }
---@diagnostic disable-next-line: duplicate-set-field -- replaces shared/settings.lua's empty default
function Settings.pageRegistered(owner, opts)
    for path, row in pairs(rows[owner] or {}) do
        local entry = Settings.entry(owner, path)
        local good, checked = false, nil
        if entry then good, checked = Settings.check(entry, row.value) end
        if good then
            row.value, row.refused = checked, nil
            Settings.apply(owner, path, checked)
        else
            row.refused = true
        end
    end
    for path in pairs(Settings.values[owner] or {}) do
        if not savedRow(owner, path) then Settings.apply(owner, path, Settings.default(owner, path)) end
    end
    if type(opts) == 'table' and opts.quiet then
        queueWrite()
        return
    end
    writeFile()
    -- EVERY SAVED VALUE GOES TO PLAYERS, not only what changed since start: while the page was not
    -- declared its values were written to server_settings.json (the safe side for a secret), so the
    -- settings.json players loaded may not hold them. The ones for the server only stay here.
    for path in pairs(Settings.values[owner] or {}) do Settings.touch(owner, path) end
    local wire = {}
    for path in pairs(Settings.touched(owner)) do
        local entry = Settings.entry(owner, path)
        if entry and (entry.sides or 'both') ~= 'server' then
            wire[#wire + 1] = { owner = owner, path = path, value = Settings.encode(Settings.read(owner, path)) }
        end
    end
    if #wire > 0 then TriggerClientEvent('whip_core:client:settingsChanged', -1, wire) end
    -- An admin looking at the page sees it as it is now (rows added or gone, restart ones in force).
    TriggerClientEvent('whip_core:client:settingsSaved', -1)
end

--- A satellite stopped and its page went (shared/settings.lua): an admin looking at it is told.
---@diagnostic disable-next-line: duplicate-set-field -- replaces shared/settings.lua's empty default
function Settings.pageDropped()
    TriggerClientEvent('whip_core:client:settingsSaved', -1)
end

--- The satellites' pages, for the panel's Settings group: { { owner, label }, ... }, by name. (Not
--- the items' pages: the Items page shows those.)
---@return table
function Settings.satellitePages()
    local out = {}
    for owner, page in pairs(Settings.pages()) do
        if owner ~= CORE and not Settings.isItemPage(owner) then out[#out + 1] = { owner = owner, label = page.label } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

-- ============================================
-- Changing settings
-- ============================================

--- A permanent admin: whip.devtools from server.cfg, not the Player Manager's temporary tools. A
--- saved setting outlives the restart that takes temporary tools away (as grants do).
---@param src number
---@return boolean
function Settings.mayEdit(src)
    if not DevTools.hasAce(src, DEVTOOLS) then return false end   -- developer mode on, too
    return not (DevTools and DevTools.isTemporary and DevTools.isTemporary(src))
end

--- A value from the panel, in the setting's own form. The panel speaks JSON: a vector arrives as
--- { x, y, z }. Plain values pass through for Settings.check to judge.
local fromWire

--- A record's position fields from the wire's { x, y, z } into vectors (records and map rows).
local function recordFromWire(fields, rec)
    if type(rec) ~= 'table' then return rec end
    for _, f in ipairs(fields) do
        if f.type == 'vec3' or f.type == 'vec4' then
            Settings.setField(rec, f.key, fromWire(f, Settings.getField(rec, f.key)))
        end
    end
    return rec
end

---@param entry table
---@param value any
---@return any
function fromWire(entry, value)
    if type(value) == 'table' and (entry.type == 'vec3' or entry.type == 'vec4') then
        local x, y, z, w = tonumber(value.x), tonumber(value.y), tonumber(value.z), tonumber(value.w)
        if entry.type == 'vec4' and x and y and z and w then return vector4(x + 0.0, y + 0.0, z + 0.0, w + 0.0) end
        if entry.type == 'vec3' and x and y and z then return vector3(x + 0.0, y + 0.0, z + 0.0) end
    end
    if type(value) == 'table' and entry.type == 'records' then
        for i = 1, #value do value[i] = recordFromWire(entry.fields, value[i]) end
    end
    -- The character screen's shots: each one's camera and mark into vectors. (A `false` is a place with no shot.)
    if type(value) == 'table' and entry.type == 'heroShots' then
        local V3, V4 = { type = 'vec3' }, { type = 'vec4' }
        for _, s in ipairs(value) do
            if type(s) == 'table' then
                if type(s.camera) == 'table' then
                    s.camera.pos = fromWire(V3, s.camera.pos)
                    s.camera.rot = fromWire(V3, s.camera.rot)
                end
                s.pos = fromWire(V4, s.pos)
            end
        end
    end
    -- A map comes as { pairs = { { key, value }, ... } }: a plain table from JSON could not tell a
    -- model's number key from a list's 1, 2, 3. The first of a key twice is kept (the panel says so).
    if type(value) == 'table' and entry.type == 'map' then
        local out = {}
        for _, kv in ipairs(type(value.pairs) == 'table' and value.pairs or {}) do
            if type(kv) == 'table' and kv[1] ~= nil and out[kv[1]] == nil then
                out[kv[1]] = entry.fields and recordFromWire(entry.fields, kv[2]) or kv[2]
            end
        end
        return out
    end
    return value
end

--- Change settings for an admin. `list` is { { owner?, path, value?, isNil?, reset? }, ... }: a
--- new value, nil (isNil, for a setting where "none" is allowed), or reset to the default. All or
--- nothing: every item is checked before anything is written, and the writes are one transaction.
--- Answers { changed, live, waiting = { path, ... } }, or false and why.
---@param src number
---@param list table
---@return table|false, string|nil
function Settings.change(src, list)
    if not Settings.mayEdit(src) then
        return false, 'Only a permanent admin can change settings'
    end
    -- Not before the boot has read what is saved: the files would be written from nothing.
    if CoreReady ~= true then return false, 'whip_core is still starting' end
    if type(list) ~= 'table' or #list == 0 then return false, 'Nothing to change' end
    if #list > 200 then return false, 'Too many changes at once' end

    local plan = {}
    for _, c in ipairs(list) do
        local owner = type(c.owner) == 'string' and c.owner ~= '' and c.owner or CORE
        local path = c.path
        local entry = type(path) == 'string' and Settings.entry(owner, path) or nil
        if not entry then return false, ('%s is not a setting'):format(tostring(path)) end
        if applyOf(entry) == 'readonly' then return false, ('%s cannot be changed here'):format(entry.label) end
        local value
        if c.reset then
            value = Settings.default(owner, path)
        else
            -- Written out: `c.isNil and nil or x` is always x.
            local given = nil
            if not c.isNil then given = fromWire(entry, c.value) end
            local ok, v = Settings.check(entry, given)
            if not ok then return false, ('%s %s'):format(entry.label, v) end
            value = v
        end
        local saved = savedRow(owner, path)
        local old
        if saved then old = saved.value else old = Settings.default(owner, path) end
        plan[#plan + 1] = {
            owner = owner, path = path, entry = entry, value = value,
            isDefault = Settings.same(value, Settings.default(owner, path)),
            old = old,
            -- Any row, a refused one too: going back to the default deletes it.
            hadRow = (rows[owner] and rows[owner][path]) ~= nil,
        }
    end

    -- SETTINGS THAT MUST AGREE WITH EACH OTHER (a skill check's widest part no wider than its
    -- pieces): each changed entry with a `cross` check is asked about the values as they will be
    -- once this change is saved — this change's, else what is saved, else the default.
    local planned = {}
    for _, p in ipairs(plan) do planned[p.owner .. '\0' .. p.path] = { v = p.value } end
    local function willBe(owner, path)
        local hit = planned[owner .. '\0' .. path]
        if hit then return hit.v end
        local saved = savedRow(owner, path)
        if saved then return saved.value end
        return Settings.default(owner, path)
    end
    for _, p in ipairs(plan) do
        if p.entry.cross then
            local called, ok, why = pcall(p.entry.cross, function(path) return willBe(p.owner, path) end)
            if not called then
                say('^1the cross check of %s errored: %s^0', p.path, tostring(ok))
                return false, ('%s could not be checked'):format(p.entry.label)
            end
            if not ok then return false, why or ('%s does not fit the settings beside it'):format(p.entry.label) end
        end
    end

    -- Never half a character (Sanitize.string cuts whole ones): a split name is invalid UTF-8,
    -- which a strict database refuses, and the whole save with it.
    local by = Sanitize.string(GetPlayerName(src), 100, 'player ' .. src)
    local queries = {}
    for _, p in ipairs(plan) do
        if p.isDefault then
            queries[#queries + 1] = {
                query = 'DELETE FROM `whip_settings` WHERE `owner` = ? AND `path` = ?',
                values = { p.owner, p.path },
            }
        else
            queries[#queries + 1] = {
                query = 'INSERT INTO `whip_settings` (`owner`, `path`, `value`, `changedBy`) VALUES (?, ?, ?, ?) '
                    .. 'ON DUPLICATE KEY UPDATE `value` = VALUES(`value`), `changedBy` = VALUES(`changedBy`), `changedAt` = CURRENT_TIMESTAMP',
                values = { p.owner, p.path, toJson(p.value), by },
            }
        end
        if p.hadRow or not p.isDefault then
            queries[#queries + 1] = {
                query = 'INSERT INTO `whip_settings_log` (`owner`, `path`, `oldValue`, `newValue`, `changedBy`) VALUES (?, ?, ?, ?, ?)',
                values = { p.owner, p.path, toJson(p.old), toJson(p.value), by },
            }
        end
    end
    -- Through whip's one transaction door (stores.lua): the stall watchdog, the in-flight count
    -- whip_test reads, and a fault mode of its own.
    local committed, why = Stores.runTransaction(queries, 'settings')
    if not committed then
        say('^1a settings change by %s was not saved: %s^0', by, tostring(why))
        return false, DB_ERROR
    end

    -- Saved. The record in memory, then the file, then in force.
    local now = os.time()
    for _, p in ipairs(plan) do
        rows[p.owner] = rows[p.owner] or {}
        if p.isDefault then
            rows[p.owner][p.path] = nil
        else
            rows[p.owner][p.path] = { value = Settings.copy(p.value), changedBy = by, changedAt = now }
        end
    end
    writeFile()

    local live, waiting, wire = 0, {}, {}
    for _, p in ipairs(plan) do
        if applyOf(p.entry) == 'live' then
            if Settings.apply(p.owner, p.path, p.value) then
                live = live + 1
                if (p.entry.sides or 'both') ~= 'server' then
                    wire[#wire + 1] = { owner = p.owner, path = p.path, value = Settings.encode(p.value) }
                end
            end
        else
            waiting[#waiting + 1] = p.path
        end
        say('%s set %s.%s to %s%s', by, p.owner, p.path, toJson(p.value),
            applyOf(p.entry) == 'live' and '' or ' (takes effect at the next start)')
    end
    if #wire > 0 then TriggerClientEvent('whip_core:client:settingsChanged', -1, wire) end
    -- Any admin with the Config panel open redraws it (a server-only setting sends no values).
    TriggerClientEvent('whip_core:client:settingsSaved', -1)
    return { changed = #plan, live = live, waiting = waiting }
end

-- ============================================
-- The panel
-- ============================================

---@param t any  a changedAt: os.time() or the database's timestamp (ms)
---@return string|nil
local function when(t)
    t = tonumber(t)
    if not t then return nil end
    if t > 1e11 then t = math.floor(t / 1000) end
    return os.date('%d %b %Y %H:%M', t) --[[@as string]]
end

-- What the panel needs of an entry to draw and check it, at every level (a list's item, a
-- record's fields, a map's value). The name rules go too, so the panel refuses what this side
-- would: one refused value fails the whole Apply. Functions (`cross`) stay here.
local PANEL_FIELDS = {
    'type', 'label', 'help', 'key', 'min', 'max', 'step', 'unit', 'maxLen', 'options', 'nullable',
    'forbidden', 'pattern', 'patternWhy', 'offWhenEmpty', 'emptyLabel', 'minItems', 'maxItems',
    'limits', 'axisLabels', 'here', 'camera', 'unique', 'keyKind', 'keyPattern', 'keyWhy', 'keyLabel',
    'link', 'form', 'formLabel', 'formHelp', 'formFirst', 'choicesFrom', 'widget', 'shownWhen', 'warnOn',
    'marker', 'place',
}

-- [owner][path] = fn: a setting whose panel row offers what exists right now (the stats with a gauge), asked at
-- each send. Kept here, not on the schema entry, because only the file that knows the answer (server/stats.lua)
-- can give it, and the schema is shared with the client.
local choices = {}

--- Offer the panel a list for this setting, made at each send: fn() returns a plain list of tables. The row's
--- `widget` says how it is drawn (html/js/wp/config.js).
---@param path string
---@param fn function
---@param owner string|nil  whip_core when left out
function Settings.setChoices(path, fn, owner)
    owner = owner or CORE
    choices[owner] = choices[owner] or {}
    choices[owner][path] = fn
end

local function forPanel(e)
    local out = {}
    for _, k in ipairs(PANEL_FIELDS) do out[k] = e[k] end
    out.nullable = e.nullable == true
    if e.item then out.item = forPanel(e.item) end
    if e.each then out.each = forPanel(e.each) end
    if e.fields then
        out.fields = {}
        for i, f in ipairs(e.fields) do out.fields[i] = forPanel(f) end
    end
    return out
end

--- Settings as the panel draws them (html/js/wp/config.js): each with what is in force, what is saved
--- (when it waits for a restart, the two differ), its default, and who changed it last. The Items
--- page draws an item's the same way (server/item_settings.lua).
---@param owner string
---@param entries table  the page's entries
---@return table
function Settings.panelSettings(owner, entries)
    local list = {}
    for _, e in ipairs(entries or {}) do
        local row = savedRow(owner, e.path)
        local inForce = Settings.read(owner, e.path)
        local default = Settings.default(owner, e.path)
        -- WHAT IS SAVED IS ALWAYS SENT: the row's value, or the default when there is none.
        -- Written out, never `row and x or y`: a saved `false` (an on/off setting turned off)
        -- is a value, and the and/or form lost it.
        local saved = default
        local changedBy, changedAt = nil, nil
        if row then
            saved = row.value
            changedBy, changedAt = row.changedBy, when(row.changedAt)
        end
        local item = forPanel(e)
        item.path = e.path
        item.apply, item.why = applyOf(e), e.why
        item.value = Settings.encode(inForce)
        item.default = Settings.encode(default)
        item.saved = Settings.encode(saved)
        -- Saved but not in force: a restart setting waiting for whip_core's next start.
        item.waiting = not Settings.same(saved, inForce)
        item.changedBy, item.changedAt = changedBy, changedAt
        local offer = choices[owner] and choices[owner][e.path]
        if offer then
            local ok, offered = pcall(offer)
            if ok and type(offered) == 'table' then item.choices = offered
            elseif not ok then print(('[whip_core:settings] %s: its choices failed: %s'):format(e.path, tostring(offered))) end
        end
        list[#list + 1] = item
    end
    return list
end

--- Every page, as the panel draws it (Settings.panelSettings). Not the items' pages, nor a group
--- edited on a page of its own (`editedIn`: config.lua's items, on the Items page).
---@return table
function Settings.panelData()
    local out = {}
    for owner, page in pairs(Settings.pages()) do
        if not Settings.isItemPage(owner) then
            local groups = {}
            for _, g in ipairs(page.groups) do
                if not g.editedIn then
                    groups[#groups + 1] = { id = g.id, label = g.label, settings = Settings.panelSettings(owner, g.settings) }
                end
            end
            out[#out + 1] = { owner = owner, label = page.label, groups = groups }
        end
    end
    table.sort(out, function(a, b)
        -- Never true for a page against itself: Lua's sort can compare its pivot with itself.
        if a.owner == b.owner then return false end
        if a.owner == CORE then return true end
        if b.owner == CORE then return false end
        return a.owner < b.owner
    end)
    return out
end

SecureCallback('whip_core:settings:panel', { ace = DEVTOOLS, rateLimit = 500, burst = 5, whileDead = true }, function(source)
    if not Settings.mayEdit(source) then return false, 'Only a permanent admin can change settings' end
    return { pages = Settings.panelData() }
end)

SecureCallback('whip_core:settings:apply', {
    ace = DEVTOOLS, rateLimit = 500, burst = 3, whileDead = true,
    params = {
        { 'changes', 'list', {
            { 'owner', 'string', 64, '' },
            { 'path', 'string', 128 },
            { 'value', 'any' },
            { 'isNil', 'bool', false },
            { 'reset', 'bool', false },
        }, 200 },
    },
}, function(source, _, changes)
    return Settings.change(source, changes)
end)

-- ============================================
-- A player who has just loaded
-- ============================================
--
-- Their game read settings.json at load, but the file a player downloads is the one whip_core
-- started with: anything changed since (or put in force at boot from the database) has to be sent.
--
-- THE PLAYER ASKS, AND ASKS AGAIN WHEN WHIP_CORE IS READY (client/settings.lua: once as its game
-- starts, and again on whip_core:client:coreReady). Before whip_core is ready the answer could be
-- out of date (the boot has not put the database's values in force yet), so a hello then is simply
-- not answered: the second one is. No waiting thread, no time limit to run out.

---@param src number
local function sendInForce(src)
    local owners = {}
    for owner in pairs(Settings.pages()) do owners[owner] = true end
    for owner in pairs(rows) do owners[owner] = true end
    local list = {}
    for owner in pairs(owners) do
        for path in pairs(Settings.touched(owner)) do
            -- Only what a player may have: a declared setting that is not for the server only.
            local entry = Settings.entry(owner, path)
            if entry and (entry.sides or 'both') ~= 'server' then
                list[#list + 1] = { owner = owner, path = path, value = Settings.encode(Settings.read(owner, path)) }
            end
        end
    end
    if #list > 0 then TriggerClientEvent('whip_core:client:settingsChanged', src, list) end
end

SecureEvent('whip_core:server:settingsHello', { rateLimit = 5000, burst = 2, whileDead = true, requirePlayer = false }, function(source)
    if CoreReady ~= true then return end
    sendInForce(source)
end)
