---@meta
-- ============================================
-- whip_core — Server Export Annotations
-- LuaLS type definitions for all server-side
-- exports. This file contains NO runtime code.
--
-- Usage in your resource:
--   local player = exports.whip_core:GetPlayer(source)
--   -- LuaLS now knows `player` is WhipPlayer|nil
--
-- ---@async marks an export that can wait (on the database, on the player): call it from a thread or a
-- handler, never at file scope. whip_core/dev/waits.js finds them and checks these marks (and the docs').
--
-- SIDES. Both this file and types/client.lua describe exports.whip_core, and the editor cannot tell a server file
-- from a client one, so it offers both sides' calls everywhere. Hover a call: WhipCoreServerExports is the server's,
-- WhipCoreClientExports the client's. whip_core/dev/stubcheck.lua checks every export has its stub on its side.
-- ============================================

---@class WhipCoreServerExports
local whip_core = {}

-- ============================================
-- Player
-- ============================================

-- THESE RETURN DATA, NOT AN OBJECT WITH METHODS. FiveM copies values across a resource boundary
-- and a metatable does not survive the copy, so these return WhipPlayer:serialize(); the methods
-- are exports of their own further down this section.
--
-- IDENTIFIERS ARE NOT ON THE SHEET. serialize() omits license, steam, discord and fivem because
-- it is also the payload sent to the CLIENT on playerLoaded. Use GetPlayerIdentifiers.

--- A player as plain, copyable data. A copy of the whole sheet (appearance and inventory too): for one number
--- use GetCharId, for "are they in" IsPlayerLoaded. Online players only; nil when nobody online matches.
---
---     exports.whip_core:GetPlayer(source)
---     exports.whip_core:GetPlayer({ charId = 42 })
---     exports.whip_core:GetPlayer({ userId = 7 })
---     exports.whip_core:GetPlayer({ identifier = 'license:abc...' })   -- license, steam, discord or fivem
---@param who number|{ charId: number }|{ userId: number }|{ identifier: string } A server id, or a reference
---@return WhipPlayerData|nil
function whip_core:GetPlayer(who) end

--- Their charId, or nil while no character is loaded. Copies nothing.
---@param source number
---@return integer|nil charId
function whip_core:GetCharId(source) end

--- Is a character loaded for this server id? Copies nothing.
---@param source number
---@return boolean
function whip_core:IsPlayerLoaded(source) end

--- Are they down? The server's own reading (what a SecureEvent's whileDead asks). false for nobody loaded.
---@param source number
---@return boolean
function whip_core:IsPlayerDead(source) end

--- Every currently loaded player, as plain data. `{ light = true }` gives each one's light sheet
--- (who, and whether dead — no position, cash, health or appearance), which is much cheaper.
---@param opts { light?: boolean }|nil
---@return table<number, WhipPlayerData> Keyed by source ID
function whip_core:GetPlayers(opts) end

--- Is this still the same character session — loaded, not logging out, not replaced by the next
--- character on the same source? Ask it in a handler that WAITED (a DB await, a Wait, a bar) before
--- it gives or takes something; `session` is on the sheet your handler was given.
---
---     local receipt = exports.whip_core:ChargePlayer(source, 500)   -- yields
---     Wait(4000)
---     if not exports.whip_core:IsSessionCurrent(source, player.session) then
---         exports.whip_core:RefundPlayer(receipt)
---         return false, 'You left before the sale went through'
---     end
---
--- Logout also waits up to two seconds for running handlers, so a short wait is covered anyway.
---@param source number
---@param session number
---@return boolean
function whip_core:IsSessionCurrent(source, session) end

--- The players within network range of a point (Config.NetworkRange, 424 m), for a message about a
--- place that only the players there should get. `coords` is a vector3 or `{ x, y }`; `range` in
--- metres overrides the default. Server ids; empty for bad input.
---@param coords vector3|table
---@param range number|nil
---@return number[]
function whip_core:GetPlayersInRange(coords, range) end

--- Is this character gone — deleted, or never there? Ask it before acting on
--- whip_core:character:deleted, which any server resource can fire. `true, 'deleted'` or
--- `true, 'no such character'`; `false` for a live one, and `false, why` when it cannot tell (so a
--- doubt never removes anything).
---@param charId number
---@return boolean gone
---@return string|nil why
---@async
function whip_core:IsCharacterDeleted(charId) end

--- The four identifiers GetPlayer deliberately leaves off the player sheet.
---
--- Separate because that sheet is also what goes to the client on playerLoaded, and a licence id
--- has no business being sent to the machine it identifies. Asking for one is a deliberate act.
---@param source number
---@return { discord: string|nil, fivem: string|nil, license: string|nil, steam: string|nil }|nil
function whip_core:GetPlayerIdentifiers(source) end

-- ============================================
-- Player — the methods, as exports
--
-- WhipPlayer's methods cannot cross a resource boundary, so each one a satellite could reasonably
-- want has a call of its own. Each resolves the player itself rather than taking a sheet back in:
-- handing a serialized player to a mutating call would ask the caller to carry state that can go
-- stale between the two calls.
-- ============================================

---@param source number
---@return number cash  0 when the player is not loaded
---@return string|nil why  'Player not loaded'
function whip_core:GetPlayerCash(source) end

--- Show a player one of whip's toasts, of any kind, from the server.
---@param source number  a player, or -1 for everyone
---@param text string
---@param kind? 'info'|'success'|'warning'|'error'  default 'info'
---@param duration? number  milliseconds; leave it out for the usual short toast
---@return boolean sent  false for a player who is not on the server, or no text
---@return string|nil why
function whip_core:NotifyPlayer(source, text, kind, duration) end

--- Put up the instruction band (the client's ShowText) for a player, from the server: an objective,
--- a job step. One band per player: a new one takes it over. Yours: gone when your resource stops,
--- your run's tag is released, or they log out. Colour codes removed, at most 200 characters.
---@param source number
---@param text string
---@param opts? { position?: 'bottom'|'top', progress?: number, countdown?: number, countdownTotal?: number, tag?: string }  progress 0-100 fills the band; countdown (seconds) puts a clock after the text that the player's game counts down (countdownTotal: its full length, for the fill)
---@return boolean ok
---@return string|nil reason
function whip_core:ShowPlayerText(source, text, opts) end

--- Take your band down (another resource's text is left alone).
---@param source number
---@return boolean ok
---@return string|nil reason
function whip_core:HidePlayerText(source) end

--- A blip on some players' maps, from the server. The same id again moves or changes it; ids are
--- yours alone. Gone when your resource stops or your run's tag is released. No frame loop.
---@param audience 'everyone'|{ people: (number|{ charId: number })[] }  who sees it (a charId follows them across relogs)
---@param id string|number  yours
---@param spec { coords: vector3|table, label?: string, sprite?: integer, color?: integer, route?: boolean, radius?: number, shortRange?: boolean, scale?: number, flash?: boolean, tag?: string }
---@return boolean ok
---@return string|nil reason
function whip_core:ShowBlip(audience, id, spec) end

--- Take one of your blips down, the pair of ShowBlip.
---@param id string|number
---@return boolean ok
---@return string|nil reason
function whip_core:HideBlip(id) end

--- GTA's own waypoint (the one a player can set on the map), set on one player's map.
---@param source number
---@param coords vector3|table
---@return boolean ok
---@return string|nil reason
function whip_core:SetPlayerWaypoint(source, coords) end

---@class WhipPropSetProp
---@field model string A prop's name (letters, digits and _)
---@field coords vector3|table Exactly where (no snap to the ground)
---@field rot vector3|table|nil { tilt forward, tilt sideways, heading } in degrees, rotation order 2
---@field heading number|nil Its turn, when there is no rot
---@field interior boolean|nil Inside an MLO: each game waits for the interior, then files it in its room
---@field light boolean|nil A lamp: filed in the interior's limbo so it lights the room
---@field collision boolean|nil false: players walk through it
---@field drawDistance number|nil Metres (1-500): made out to this and drawn this far, past its model's own draw distance

--- Props made by each player's own game near them (never networked): ShowPropSet(id, spec). The same
--- id again replaces the set; yours go when you stop or your run's tag is released. At most
--- Config.PropSetMaxProps props (256; /whip → Settings, Props per scene set).
---@param id string|number  yours
---@param spec { props: WhipPropSetProp[], audience?: 'everyone'|{ people: (number|{ charId: number })[] }, tag?: string }
---@return boolean ok
---@return string|nil reason
function whip_core:ShowPropSet(id, spec) end

--- Take one of your prop sets down.
---@param id string|number
---@return boolean ok
---@return string|nil reason
function whip_core:HidePropSet(id) end

--- Declare an in-game permission (a right an admin gives an ACCOUNT in /whip). The resource that
--- declares a name owns it. Full admins (whip.devtools) hold every permission unless `devtools = false`.
--- Gate a SecureEvent/SecureCallback on one with `permission = 'name'` (it does not excuse the
--- dead-player rule: add whileDead if needed).
---@param name string  3-64 letters, digits, '.', '_' and '-' (e.g. 'myres.manage')
---@param def? { label?: string, description?: string, implies?: string[], devtools?: boolean, grantedBy?: string }
---@return boolean ok
---@return string|nil reason
function whip_core:RegisterPermission(name, def) end

--- Does this player have the permission (a grant on their account, one that includes it, or full admin)?
---@param source number
---@param name string
---@return boolean
function whip_core:HasPermission(source, name) end

-- ============================================
-- Player flags — what a character has done, kept for good (server/player_flags.lua)
-- ============================================

--- A flag of a character who is on: true, a number, text, or nil (not set). Saved in the character's
--- metadata, so only an online character's can be read or set.
---@param who number|{ charId: number }
---@param name string  letters, digits and _ . - : (at most 64), starting with a letter
---@return boolean|number|string|nil
function whip_core:GetPlayerFlag(who, name) end

--- All of a character's flags ({ [name] = value }), or nil when they are not on.
---@param who number|{ charId: number }
---@return table<string, boolean|number|string>|nil
function whip_core:GetPlayerFlags(who) end

--- Set a flag, or clear it with nil or false. Saved with the character; `whip_core:flag:changed` is told.
--- At most 256 per character; text at most 100 characters.
---@param who number|{ charId: number }
---@param name string
---@param value boolean|number|string|nil
---@return boolean ok
---@return string|nil reason
function whip_core:SetPlayerFlag(who, name, value) end

--- Start a run of a switched-on Director scenario for a player (a phone app, a job menu). Only a
--- scenario whose Settings say "A run starts: From a script"; one already in a run of it is refused.
---@param key string   the scenario's key
---@param who number|{ charId: number }   a server id, or an online character
---@param opts? DirectorStartOpts   more players, its variables, this run's own places
---@return number|false runId
---@return string|nil reason
function whip_core:StartScenarioRun(key, who, opts) end

-- ---- The Director API: steering runs (refused for a builder's Test, but EndScenarioRun) ----

--- End a run as a Succeed, Fail or Call Off card would ('calledOff': no result, nobody told). Written
--- into the run's history with your resource's name.
---@param runId number
---@param outcome 'succeeded'|'failed'|'calledOff'
---@param reason? string
---@return boolean ok
---@return string|nil reason
function whip_core:EndScenarioRun(runId, outcome, reason) end

--- Put a player into a run going now as CREW (its rights: doors, containers, payouts). Told, announced
--- (whip_core:run:playerJoined), written down. Refused: a Test, down, no character, already in a run of
--- that scenario, a full run (16).
---@param runId number
---@param who number|{ charId: number }
---@return boolean ok
---@return string|nil reason
function whip_core:AddPlayerToScenarioRun(runId, who) end

--- Take a player out of a run: what it handed them goes back, they are told, its history says left.
--- WAITS (the take-back): call it from a thread.
---@param runId number
---@param who number|{ charId: number }
---@param why? string
---@return boolean ok
---@return string|nil reason
function whip_core:RemovePlayerFromScenarioRun(runId, who, why) end

--- A run's variable. TRUE FIRST: a variable can hold false or nothing.
---@param runId number
---@param name string
---@param opts? { tests?: boolean }
---@return boolean ok
---@return any valueOrReason
function whip_core:GetScenarioRunVar(runId, name, opts) end

--- Set a run's variable, of the type the scenario declares (number, text, true/false).
---@param runId number
---@param name string
---@param value string|number|boolean
---@return boolean ok
---@return string|nil reason
function whip_core:SetScenarioRunVar(runId, name, value) end

--- Tell runs something: Wait for Script Event cards waiting for `name` carry on. `name` is in YOUR
--- namespace ('police.backupArrived': the first running resource to send in one has it; whip_core's are
--- nobody's). payload.source (a server id) is who it is about. At most 20 of one event a second.
---@param name string
---@param payload? table
---@param opts? { runId?: number }   only that run hears it
---@return boolean ok
---@return number|string heardByOrReason   how many runs heard it
function whip_core:SendDirectorEvent(name, payload, opts) end

--- Switch a scenario on or off by script (heists only at night). Only one whose Settings say "Scripts
--- may switch it on and off"; on again only at the revision a person last switched on; never while a
--- builder tests it; in memory only (a reboot puts back what a person chose). WAITS (switching on reads
--- the revision).
---@param key string
---@param on boolean
---@param why? string
---@return boolean ok
---@return string|nil reason
---@async
function whip_core:SwitchScenario(key, on, why) end

-- ---- Lore characters (server/director/lore.lua): the story's named NPCs ----

---@class LoreCharacter
---@field key string
---@field name string            'Irwin Dundee'
---@field model string|nil       its ped's spawn name
---@field bankName string|nil    what its payments are from (nil: its name)
---@field payName string         bankName, else name
---@field notes string|nil       its personality, for whoever writes it
---@field picture string|nil     its profile picture's link (one of Config.LorePictureLinks), nil for none
---@field pictureFrame { x: number, y: number, z: number }|nil  what of the picture shows in a round frame: x, y the point kept in view (0-100, % across and down), z the zoom (1-3); nil: the middle, unzoomed
---@field retired boolean        out of the pickers, its records kept
---@field accountId number|nil   its bank account (owned by no character), once it has paid someone

--- A lore character by key (a retired one too), or nil.
---@param key string
---@return LoreCharacter|nil
function whip_core:GetLoreCharacter(key) end

--- A lore character says one of its voice lines from its NPC in the world (the Lore Says card). WAITS (the
--- recording is fetched; with opts.wait, until it has been said). opts.near: its NPC nearest that player.
---@param key string
---@param line string  'hello', 'goodbye', 'positive', ... (its voice lines)
---@param opts { near: number|nil, npcId: number|nil, wait: boolean|nil, busy: 'skip'|'queue'|'cut'|nil }|nil
---@return boolean ok
---@return string|nil why  ('queued' with true)
---@async
function whip_core:LoreSay(key, line, opts) end

--- A profile picture as whip takes one (a link on Config.LorePictureLinks' sites, its framing cleaned): true, frame
--- (nil for the plain framing, or an empty link), or false, why.
---@param url string
---@param frame { x: number, y: number, z: number }|nil
---@return boolean ok
---@return table|string|nil frameOrWhy
function whip_core:CheckPicture(url, frame) end

--- Every lore character in use, by name.
---@param withRetired? boolean   the retired ones as well
---@return LoreCharacter[]
function whip_core:GetLoreCharacters(withRetired) end

--- A lore character pays a player into their bank: a transfer from its own account, so their statement reads
--- like any other; the money is made on the spot (its account's statement says by which resource).
---
---     exports.whip_core:PayAsLore('irwin', source, 500, { message = 'For the drop' })
---@param key string
---@param who number|{ charId: number }
---@param amount number   whole, 1 or more
---@param opts? { message?: string }
---@return boolean ok
---@return string|nil reason
---@async
function whip_core:PayAsLore(key, who, amount, opts) end

-- ---- The Director API: asking about runs and scenarios (classes in types/director.lua) ----
-- Test runs (a builder's Test) are left out of every result unless opts.tests is true.

--- A run going now, as other resources see it (a copy).
---@param runId number
---@param opts? { tests?: boolean }
---@return DirectorRunView|false run
---@return string|nil reason
function whip_core:GetScenarioRun(runId, opts) end

--- The runs going now.
---@param filter? { scenario?: string, player?: number|{ charId: number }, kind?: string, tests?: boolean }
---@return DirectorRunView[]
function whip_core:GetScenarioRuns(filter) end

--- The runs a player is in now.
---@param who number|{ charId: number }
---@param opts? { tests?: boolean }
---@return DirectorRunView[]
function whip_core:GetPlayerScenarioRuns(who, opts) end

--- Is a player in a run now: of that scenario (key), or of any?
---@param who number|{ charId: number }
---@param key? string
---@param opts? { tests?: boolean }
---@return boolean
function whip_core:IsPlayerInScenarioRun(who, key, opts) end

--- Which run a car, an NPC or a tag belongs to (a police tracker on a getaway car).
---@param ref { netId?: number, vehicleId?: number, npcId?: number, tag?: string }
---@param opts? { tests?: boolean }
---@return DirectorRunView|false run
---@return string|nil reason
function whip_core:GetScenarioRunOf(ref, opts) end

--- Would StartScenarioRun start one for this player now? The same checks, nothing started.
---@param key string
---@param who number|{ charId: number }
---@return boolean ok
---@return string|nil reason
function whip_core:CanStartScenarioRun(key, who) end

--- A scenario, with its cards, placed things and variables: the switched-on revision, else its draft.
---@param key string
---@return DirectorScenarioView|false scenario
---@return string|nil reason
function whip_core:GetScenario(key) end

--- Every scenario, short (no cards, world or vars).
---@param filter? { on?: boolean, kind?: string, startMode?: string }
---@return DirectorScenarioView[]
function whip_core:GetScenarios(filter) end

--- How a stored scenario's runs have gone (tests left out). WAITS on the database: call it from a thread.
---@param key string
---@return { runs: number, succeeded: number, stopped: number, lastAt: number|nil }|false stats
---@return string|nil reason
---@async
function whip_core:GetScenarioStats(key) end

--- The Director's card types, each with its owner: whip_core's own, and other resources' (Whip.card).
---@param filter? { category?: string, owner?: string }
---@return table[]
function whip_core:GetDirectorCards(filter) end

--- Take one of your code scenarios off the Shipped list (what was accepted stays in the store).
---@param key string
---@return boolean ok
---@return string|nil reason
function whip_core:RemoveDirectorScenario(key) end

--- Take one of your templates away.
---@param name string
---@return boolean ok
---@return string|nil reason
function whip_core:RemoveDirectorTemplate(name) end

--- What the editor's Check says of a scenario document: ok, and its problems
--- ({ { severity = 'error' | 'warning', node?, pin?, message } }).
---@param doc table
---@return boolean ok
---@return table problems
function whip_core:CheckDirectorScenario(doc) end

--- One of YOUR cards run once, without a builder: in a scenario of its own (Scenario Enabled -> the card
--- -> each outcome ends it), as a Test played by `opts.player`. Its real code runs, but only ever in a
--- Test: Give hands out what the run's end takes back, Pay only says, Charge charges nothing, and no
--- script hears of the run. A place field (kind 'world') takes { x, y, z, heading? }. WAITS until it
--- has an outcome (or opts.seconds, 1-120; default its Give up after and 5 more; a longer Give up after is
--- shortened to fit). Refused: Check's first problem, Didn't work's reason, no answer in time.
--- Your code sees card.test = true: keep what it does to card.player then (never page the real police).
---@param cardType string   'police.notify'
---@param props? table  its fields, as the editor sets them
---@param opts { player: number, seconds?: number, event?: table }   event: an event card's payload
---@return { outcome: string, data: table|nil }|false result   outcome: the one it took ('timeout' too)
---@return string|nil reason
---@async
function whip_core:TestDirectorCard(cardType, props, opts) end

--- A whole scenario document run once as a Test for `opts.player`, as the editor's Test runs it, and steered as
--- the test map is: Give hands out what the run's end takes back, Pay and Charge only say, no script hears of it.
--- Check must pass (a run that can never succeed is tested all the same). One per player at a time, three of
--- yours at a time. WAITS until it ends, unless opts.wait is false (then it returns at once: steer it with
--- SteerDirectorTest, read it with GetDirectorTestResult).
--- steer: done in order; take and say once their card waits, the rest once their `when` card waits (or at once):
---   { op = 'take', node, pin } | { op = 'say', node, option, amount? } | { op = 'event' | 'emit', name, payload?, when? }
---   | { op = 'var', name, value, when? } | { op = 'end', outcome?, reason? } | { op = 'wait', ms }
---@param doc table  a scenario document, as the editor saves it
---@param opts { player: number, seconds?: number, vars?: table, steer?: table[], wait?: boolean }  seconds: 1-600 (60)
---@return table|false result  { runId, status, reason, faultNode, late, vars, steps, fired, entered, waiting, things, made, players, steered, left, done }
---@return string|nil reason
---@async
function whip_core:TestDirectorScenario(doc, opts) end

--- One of YOUR scripted tests still going: 'take', nodeId, pin | 'say', nodeId, option, amount? | 'event', name,
--- payload? (a script's event) | 'emit', name, payload? (the Director's own, to this run alone) | 'var', name, value |
--- 'end', outcome?, reason? ('succeeded' or 'failed'; else aborted).
---@param runId number
---@param op string
---@return boolean ok
---@return any extraOrReason
function whip_core:SteerDirectorTest(runId, op, ...) end

--- What one of YOUR scripted tests did (TestDirectorScenario's result), going or ended: kept 10 minutes after its end.
---@param runId number
---@return table|nil result
function whip_core:GetDirectorTestResult(runId) end

--- What YOU keep on a placed thing (your Director buttons' saves, client Whip.directorButton): a copy, or nil when
--- nothing is saved; false and why when there is no such run, scenario or thing.
--- `where` is a run's id (that run's revision of the scenario) or a scenario's key (the revision that is on now).
---@param where number|string
---@param worldId string
---@return table|false|nil data
---@return string|nil why   with false: no such run, scenario or thing
function whip_core:GetDirectorThingData(where, worldId) end

--- Give a person's account a permission. Every character on it has it. Written, then believed. `who` is a person:
--- an online player's server id, { charId = n } (online or not), or { userId = n } for the account itself.
---@param who number|{ charId: number }|{ userId: number }
---@param name string
---@return boolean ok
---@return string|nil reason
---@async
function whip_core:GrantPermission(who, name) end

--- Take a permission away from a person's account (true also when it never had it). `who` as GrantPermission.
---@param who number|{ charId: number }|{ userId: number }
---@param name string
---@return boolean ok
---@return string|nil reason
---@async
function whip_core:RevokePermission(who, name) end

--- Who has been given a permission directly (full admins hold everything without a row).
---@param name string
---@return { userId: number, name: string, account: string|nil, grantedBy: string|nil, grantedAt: number|nil, online: boolean }[]|false holders
---@return string|nil reason
---@async
function whip_core:GetPermissionHolders(name) end

--- One key of a person's metadata, or all of it with no key. A character who is not playing is read from the
--- database. nil for nobody.
---@param who number|{ charId: number } A server id, or a character (online or not)
---@param key? string
---@return any
---@async
function whip_core:GetPlayerMetadata(who, key) end

--- Refused (false, reason) for a value the character row cannot store as JSON — a vector3, a
--- function, NaN. Plain tables, strings, numbers and booleans are fine. Also refused: whip's own keys
--- (appearance, outfits, creatorPending, walk, mood, whipFlags, moneyHeldOwed, pourRefundOwed, lastSeat).
--- The player's own game receives every value: keep secrets server-side. A character who is not playing has
--- their row written (refused, try again, while they are logging in).
---@param who number|{ charId: number } A server id, or a character (online or not)
---@param key string
---@param value any
---@return boolean ok
---@return string|nil err
---@async
function whip_core:SetPlayerMetadata(who, key, value) end

---@param source number
---@return vector4|nil
function whip_core:GetPlayerCoords(source) end

--- The character's full name, or nil for a player not in a character — the name alone, where
--- GetPlayer copies the whole sheet. (FiveM's own GetPlayerName is the account's name.)
---@param source number
---@return string|nil
function whip_core:GetPlayerFullName(source) end

--- A player's game picture, from their own game (TakeScreenshot there; never uploaded anywhere). Yields until it
--- arrives (up to 30 s). Only answers to asks made here are taken; a player's game can still send one it made up,
--- so this is for tools, not for catching cheats.
---
---     local jpg, why = exports.whip_core:RequestScreenshot(source, { quality = 0.8 })
---@param source number
---@param opts? { format?: 'jpg'|'png'|'webp', quality?: number, width?: number, height?: number, ui?: boolean, frames?: number, every?: number }
---@return string|false data  a data URL
---@return string|nil why
---@async
function whip_core:RequestScreenshot(source, opts) end

--- Bring a downed player back where they lie, as /w Restore does: the server's record first, then their game stands
--- the ped up and ends the death screen. Full health, no armour.
---@param source number
---@param reason? string  for the Stats change log, after 'revive:' (default the resource that asked)
---@return boolean ok
---@return string|nil why  'Player not loaded', 'not down'
function whip_core:RevivePlayer(source, reason) end

--- Hold a dead player's respawn (an EMS job: a medic on the way): they stay where they lie, and their death screen
--- says `label` (80 letters) instead of "Hold to respawn", until you release it, they are revived, they log out, or
--- your resource stops. `key` names your hold; the same key again changes its words. Only on a dead player.
---@param source number
---@param key string
---@param label? string  default 'Help is on the way'
---@return boolean ok
---@return string|nil why  'no such player' | 'they are not dead'
function whip_core:HoldRespawn(source, key, label) end

--- Let go of your hold `key` on this player (no key: every hold of yours on them). true when one went.
---@param source number
---@param key? string
---@return boolean released
function whip_core:ReleaseRespawn(source, key) end

--- Is this player's respawn held? The words their death screen shows, or nil.
---@param source number
---@return string|nil label
function whip_core:GetRespawnHold(source) end

--- What went wrong lately on the server (the client has the same export for its side): errors in the threads, event
--- handlers, commands and statebag handlers of whip_core and its satellites, in their SecureEvent / SecureCallback
--- handlers, whip_core's own caught errors ('[whip_core...] ERROR / threw / errored' lines), and red (^1) warnings.
--- Not an export's error (its caller gets it). The last 200; one repeated is counted. `since`: only those after an
--- earlier call's `last`.
---@param opts? { since?: number, max?: number }
---@return { entries: { seq: number, at: number, side: string, resource: string, kind: 'error'|'warning', text: string, count: number }[], last: number, side: string }
function whip_core:GetErrorLog(opts) end

--- Characters' names by charId, online or not (up to 200): { [charId] = 'First Last' }. A charId that
--- names no character is left out.
---@param charIds number[]
---@return table<number, string>
---@async
function whip_core:GetCharacterNames(charIds) end

--- May `viewer` be shown `target`'s character name? whip's name rule, Config.ShowPlayerNames: 'nearby'
--- (within PlayerNameRange, same world, not in the creator; an offline character is never nearby),
--- 'always', or 'never' (only yourself).
---@param viewer WhipPersonRef
---@param target WhipPersonRef
---@return boolean ok
---@return string|nil why 'Too far away' | 'Names are hidden on this server' | 'Player not loaded'
function whip_core:CanSeePlayerName(viewer, target) end

--- Write this player's inventory, then their character row, now. For a write of your own that must
--- follow an inventory change you made (a ledger row after RemoveItem).
---@param source number
---@return boolean ok, string|nil err
---@async
function whip_core:SavePlayer(source) end

---@param source number
---@param reason string|nil
---@return boolean ok, string|nil err
function whip_core:KickPlayer(source, reason) end

--- Return the player to character selection without dropping them from the server. Refused
--- (`false, 'Already leaving'`) while they are already logging out or disconnecting.
---@param source number
---@return boolean ok, string|nil err
function whip_core:LogoutPlayer(source) end

-- ============================================
-- Readiness
-- ============================================

--- Has whip_core finished starting?
--- For code that needs to ASK rather than be told — a command that must refuse
--- while core is down, say. Registration should use Whip.register (include
--- '@whip_core/lib/satellite.lua'), which runs again on core restart and for late starters.
---@return boolean
function whip_core:IsReady() end

--- Which GTA V this server runs on: server.cfg's `set whip_platform enhanced` on an Enhanced server, else
--- 'legacy'. One whip runs on both: ask here where the two differ (the same result on the client).
---@return 'legacy'|'enhanced'
function whip_core:GetPlatform() end

--- Who registered what with whip on this side: every registry built on the one registration
--- rule (items, stats, secure events, callbacks, panel items, store kinds, handlers, flags...).
--- Pass a resource name for just that resource's share.
---@param resource? string
---@return { registry: string, key: string|number, owner: string }[]
function whip_core:GetRegistrations(resource) end

--- Has whip_core this export on the server? (Whip.has asks it.)
---@param name string
---@return boolean
function whip_core:HasExport(name) end

--- Remove everything YOU registered under one run tag (`{ tag = 'run:42' }` on a registration), in
--- every whip module, and close the tag: later registrations under it are refused ("... has ended").
--- Use a new tag for each run. A stopped resource's closed tags are forgotten.
---@param tag string e.g. 'run:42'
---@return boolean ok true, or false
---@return number|string countOrReason how many went, or why it was refused
function whip_core:ReleaseTag(tag) end

--- What you hold under one run tag, across whip's modules.
---@param tag string
---@return { registry: string, key: string|number }[]
function whip_core:GetTagged(tag) end

-- ============================================
-- SecureEvent / SecureCallback
-- ============================================

--- Register a network event with automatic input validation, rate limiting, ACE gating, and player checks.
--- Handler receives pre-validated, sanitized parameters.
---
--- `player` IS A SHEET, NOT THE LIVE OBJECT, when your resource is not whip_core: GetPlayer's sheet
--- (source, userId, charId, firstName, lastName, fullName, dateOfBirth, gender, cash, position,
--- health, armour, isDead) without `metadata`, with no methods and no inventory. Use the exports
--- (GetPlayerCash, AddItem, SetPlayerMetadata...) to act on the player; GetPlayer(source).metadata
--- has the metadata.
---
--- Register inside Whip.register. Your registrations are dropped when your resource stops.
---
--- THE NAME IS YOURS once registered: the same resource registering again swaps its handler in;
--- another resource is refused (false, 'event "x" belongs to y'); names starting 'whip_core:'
--- belong to whip_core.
---
--- SAYING NO: a handler that returns `false, 'why'` has refused — the player sees `why` as an error
--- toast and the Event Monitor records a rejection with that text. A bare `return false` records
--- the rejection and shows nothing. Anything else logs as ok.
---
---     if not exports.whip_core:HasItem(source, 'wrench', 1) then return false, 'You need a wrench' end
---@param eventName string Event name to register
---@param schema WhipSecureSchema Validation schema
---@param handler fun(source: number, player: table, ...: any): (boolean?, string?) Event handler with sanitized params; `false, 'why'` refuses (anything else is ok)
---@return boolean ok
---@return string? reason
function whip_core:SecureEvent(eventName, schema, handler) end

--- Register a callback with automatic validation (same as SecureEvent but returns a value to the client).
--- The same ownership rule as SecureEvent. When there is no answer to give, the client's Callback
--- gets `false, reason`: a refusal ('Rate limited', 'Player is dead', 'Too far away', a param's
--- reason), 'Server error', 'Unknown callback', 'That is no longer available' (the resource that
--- registered it has stopped), or 'No answer from the server'.
---@param name string Callback name
---@param schema WhipSecureSchema Validation schema
---@param handler fun(source: number, player: table, ...: any): ... Every value it returns is the client's answer, as it gave them (`false, 'why'` for a refusal; an error returns `false, 'Server error'`)
---@return boolean ok
---@return string? reason
function whip_core:SecureCallback(name, schema, handler) end

--- Register a release function for a lock taken during the current
--- SecureEvent/SecureCallback handler invocation. Anything still held when the
--- handler ERRORS is released automatically; a handler that returns normally
--- keeps its locks.
---
--- From YOUR resource, pass the event (or callback) name and the source your handler was given;
--- without them it lands on the one handler your resource has running, and is refused if there
--- are several. Outside a handler it attaches nothing and returns false.
---@param releaseFn function Called to release the lock
---@param eventName? string The name your handler was registered under
---@param src? number The source your handler was given
---@return boolean ok
---@return string? reason
function whip_core:TrackInvocationLock(releaseFn, eventName, src) end

--- Record that a handler REFUSED what a valid event or callback asked for, so
--- the refusal lands in the Event Monitor alongside the framework's own (rate
--- limit, ACE, validation). Also stops the wrapper stamping a cheerful 'ok'
--- over this invocation when the handler returns a moment later.
---@param eventName string Event or callback name
---@param src number Player server ID
---@param reason? string Why it was refused
function whip_core:RecordEventRejection(eventName, src, reason) end

--- The ACE one of whip_core's commands needs beyond FiveM's own, or nil. Its in-game admin
--- commands (/whip_giveitem, /whip_revive, ...) answer 'whip.devtools'. For a chat resource's
--- command suggestions (whip_chat asks it).
---@param name string Command name, without the slash
---@return string|nil ace
function whip_core:GetCommandAce(name) end

--- May this player use dev tools now: whip.devtools AND developer mode on (/w). Ask this rather than
--- IsPlayerAceAllowed(src, 'whip.devtools'), which returns true with developer mode off. A
--- SecureEvent/SecureCallback declaring `ace = 'whip.devtools'` already gets this check.
---@param source number
---@return boolean
function whip_core:HasDevTools(source) end

--- For tools: turn a player's developer mode on or off, as their /w switch does (a tool acting for a player who is
--- not at the game). On only for a player with whip.devtools; logged with the resource that asked.
---@param source number
---@param on boolean
---@return boolean ok
---@return string|nil why
function whip_core:SetDeveloperMode(source, on) end

-- ============================================
-- Sentinel (statebag integrity guard)
-- ============================================

--- Put one of YOUR statebag keys under the Sentinel's watch: forged client writes
--- are corrected and logged as tampers. Player family needs no truth function (the
--- ledger — what you last wrote via SetSentinelPlayerKey — is the truth). Entity
--- family REQUIRES def.truth: function(entity) -> value|nil, where nil means "this
--- entity should not carry the key" (it gets stripped). Register inside
--- Whip.register; registering your own key again is fine, another resource's is
--- refused. Your watches unwind when your resource stops.
---@param def { key: string, family: 'player'|'entity', truth?: fun(entity: number): any }
---@return boolean ok
---@return string? err
function whip_core:RegisterSentinelKey(def) end

--- The sanctioned WRITE for YOUR player-bag keys: records the value in the Sentinel's
--- ledger first, then writes the bag. A bare Player(src).state write to a watched
--- key is treated as a tamper — correctly. Follow the absence rule: write nil, not
--- false/defaults, when the fact is off. A watched key can only be written by the
--- resource that registered it, so whip's own keys (whipDead, whipJob...) are refused:
--- false, 'key "whipDead" is owned by whip_core'. A key nobody watches is anyone's.
---@param src number Player server ID (must be connected)
---@param key string Bag key
---@param value any
---@return boolean ok
---@return string? err 'no such player', 'key "x" is owned by <resource>'...
function whip_core:SetSentinelPlayerKey(src, key, value) end

--- The sanctioned WRITE for YOUR entity-bag keys. Change your truth (the table your
--- truth function reads) FIRST, then write through this: it carries the flag whip's own
--- vehicle writes carry, so a truth/write mismatch is reported in the console and nobody
--- is struck. A bare Entity(e).state:set written before the truth changes strikes the
--- car's network owner — the driver. Your own keys only; a key nobody watches is anyone's.
---@param entity number
---@param key string
---@param value any
---@return boolean ok
---@return string? err 'no such entity', 'key "x" is owned by <resource>'...
function whip_core:SetSentinelEntityKey(entity, key, value) end

--- The sanctioned server-side READ: what the server last wrote, as opposed to the
--- bag, which the described player can forge. Server gates use this; clients keep
--- reading the bag. Note false is a real ledger value, distinct from nil.
---@param src number Player server ID
---@param key string Bag key
---@return any
function whip_core:GetSentinelTruth(src, key) end

-- ============================================
-- Bank
-- ============================================

-- Every bank export has "Bank" in its name. Amounts are whole numbers of 1 or more — anything else
-- returns (false, 'Amount must be a whole number of 1 or more').

---@alias WhipBankRole 'view'|'deposit'|'withdraw'|'manager'|'owner'  -- each includes those before it

--- One bank account: by its ID, or by its display number, `{ number = 'WB-123456' }`.
---@param ref number|{ number: string }|{ accountId: number }|{ id: number } An accountId, or a reference
---@return WhipBankAccount|nil
---@async
function whip_core:GetBankAccount(ref) end

--- Every account a character can use — owned, shared or job — each row with their `role` on it.
---@param charId number
---@return (WhipBankAccount|{ role: WhipBankRole })[]
---@async
function whip_core:GetCharacterBankAccounts(charId) end

--- Get the default bank account for a person.
---@param who WhipPersonRef source, or { charId = n }
---@return WhipBankAccount|nil
---@async
function whip_core:GetDefaultBankAccount(who) end

--- A balance without the database, after the first read: a person's main account (a server id or
--- { charId = n }), or { accountId = n } for one account. Kept true by every bank write. The first read of
--- each waits; after that it returns at once.
---@param who WhipPersonRef|{ accountId: integer }
---@return integer|false balance
---@return string|nil why
---@async
function whip_core:GetBalance(who) end

--- Get all bank accounts associated with a job.
---@param job WhipJobRef jobId or key
---@return WhipBankAccount[] accounts  {} (with a why) for a job that does not exist
---@return string|nil why
---@async
function whip_core:GetJobBankAccounts(job) end

--- Get transaction history for an account.
---@param accountId number Account ID
---@param limit? number Max results (default: 50)
---@param offset? number Pagination offset (default: 0)
---@return WhipBankTransaction[]
---@async
function whip_core:GetBankTransactions(accountId, limit, offset) end

--- Get the access list for a bank account.
---@param accountId number Account ID
---@return WhipBankAccess[]
---@async
function whip_core:GetBankAccessList(accountId) end

--- May this person use this account for `role`? Decide BEFORE you act — a shop listing only
--- accounts that can pay, a menu hiding what a rank cannot touch. The account first, then the person.
---@param accountId number
---@param who WhipPersonRef source, or { charId = n }
---@param role WhipBankRole
---@return boolean ok
---@return string|nil err 'Account not found', 'Needs withdraw access to this account'...
---@async
function whip_core:CanUseBankAccount(accountId, who, role) end

--- Create a new bank account. A character may own at most Config.MaxExtraAccounts savings and shared
--- accounts; their personal account and job accounts don't count.
---@param owner WhipPersonRef Who owns it: source, or { charId = n }
---@param label? string Account label (default: Config.DefaultAccountLabel)
---@param opts? { type?: 'personal'|'savings'|'business'|'shared', job?: number|string } type default 'personal'; job: the job it belongs to (for job accounts), by jobId or key, one that does not exist refused
---@return WhipBankAccount|false account The created account, or false on failure
---@return string|nil error Error message if creation failed
---@async
function whip_core:CreateBankAccount(owner, label, opts) end

--- Close a bank account. It must be empty and not the character's default.
---@param accountId number Account ID
---@param who? WhipPersonRef The player closing it, checked: they own it, and it is a savings or shared account, not a job's. Leave it out when your code decides
---@return boolean ok
---@return string|nil err
---@async
function whip_core:CloseBankAccount(accountId, who) end

--- Freeze (true) or unfreeze (false) an account: while frozen, no money goes in or out of it.
---@param accountId number
---@param frozen boolean
---@return boolean ok
---@return string|nil err
---@async
function whip_core:SetBankAccountFrozen(accountId, frozen) end

--- What your resource charges for vehicles: what the /whip Banks page values an owned car at, averaged across
--- every resource selling that model. Declared again, it replaces your list; it goes when your resource stops.
---@param prices table<string, number>  { [model] = price }
---@return boolean ok
---@return string|nil err
function whip_core:SetVehiclePrices(prices) end

--- Grant a person access to a bank account. You can only grant roles below your own, and only
--- to someone below you.
---@param accountId number Account ID
---@param who WhipPersonRef Who gets it: source, or { charId = n }
---@param role WhipBankRole
---@param grantedBy WhipPersonRef Who is granting it (their role is what is checked)
---@return boolean ok
---@return string|nil err
---@async
function whip_core:GrantBankAccess(accountId, who, role, grantedBy) end

--- Would GrantBankAccess with these arguments be allowed? Every rule asked, nothing written: ask before a step that
--- waits on someone (an invite they accept), then grant.
---@param accountId number Account ID
---@param who WhipPersonRef Who would get it
---@param role WhipBankRole
---@param grantedBy WhipPersonRef Who would grant it
---@return boolean ok
---@return string|nil why
---@async
function whip_core:CanGrantBankAccess(accountId, who, role, grantedBy) end

--- Revoke a person's access to a bank account. The owner cannot be revoked.
---@param accountId number Account ID
---@param who WhipPersonRef Who loses it: source, or { charId = n }
---@param revokedBy WhipPersonRef Who is revoking it (must outrank them)
---@return boolean ok
---@return string|nil err
---@async
function whip_core:RevokeBankAccess(accountId, who, revokedBy) end

--- A PLAYER deposits: their deposit permission on the account is checked. BANK MONEY ONLY: no cash is taken.
--- For a cash deposit, take the notes first (ChargePlayer(source, n, { method = 'cash' })), deposit only on a receipt,
--- and RefundPlayer it if the deposit is refused; otherwise a deposit makes money from nothing.
---@param accountId number Target account ID
---@param amount number Whole number, 1 or more
---@param actor WhipPersonRef Who is depositing (required — the permission is theirs): source, or { charId = n }
---@param opts? { reason?: string } reason: shown on the statement
---@return boolean ok
---@return string|nil err
---@async
function whip_core:BankDeposit(accountId, amount, actor, opts) end

--- A PLAYER withdraws: their withdraw permission is checked. BANK MONEY ONLY: no cash is given; for a cash
--- withdrawal, pay the notes with PayPlayer (method 'cash') once this returns true. To charge a player for something,
--- use ChargePlayer instead — it handles cash too, and hands back a receipt RefundPlayer can undo.
---@param accountId number Target account ID
---@param amount number Whole number, 1 or more
---@param actor WhipPersonRef Who is withdrawing (required)
---@param opts? { reason?: string } reason: shown on the statement
---@return boolean ok
---@return string|nil err
---@async
function whip_core:BankWithdraw(accountId, amount, actor, opts) end

--- A PLAYER transfers: their withdraw permission on the source account is checked.
---@param fromId number Source account ID
---@param toId number Destination account ID
---@param amount number Whole number, 1 or more
---@param actor WhipPersonRef Who is transferring (required)
---@param opts? { reason?: string } reason: shown on the statement
---@return boolean ok
---@return string|nil err
---@async
function whip_core:BankTransfer(fromId, toId, amount, actor, opts) end

--- The SYSTEM pays in — a wage, a sale's takings, a reward. No permission check: you decide.
--- Written to the activity log with your resource's name.
---@param accountId number Target account ID
---@param amount number Whole number, 1 or more
---@param opts? { reason?: string, actorCharId?: number }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:BankSystemDeposit(accountId, amount, opts) end

--- The SYSTEM takes out — a fine, a fee, a bill. No permission check; refused for a frozen account
--- or one without enough in it. Written to the activity log with your resource's name.
---@param accountId number
---@param amount number Whole number, 1 or more
---@param opts? { reason?: string, actorCharId?: number }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:BankSystemWithdraw(accountId, amount, opts) end

--- The SYSTEM moves money between two accounts — payroll out of a business account.
---@param fromId number
---@param toId number
---@param amount number Whole number, 1 or more
---@param opts? { reason?: string, actorCharId?: number }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:BankSystemTransfer(fromId, toId, amount, opts) end

-- ============================================
-- Payments (ChargePlayer / RefundPlayer)
-- ============================================

---@class WhipReceipt
---@field id number What RefundPlayer needs (the record itself stays on the server)
---@field amount number
---@field method 'cash'|'bank'
---@field accountId number|nil bank: the account it came from
---@field currency string|nil cash: the item it was paid in ('cash' for banknotes)
---@field refunded number How much has been given back so far

--- Take a payment from a player — the one way whip charges anyone.
---
---     local receipt, err = exports.whip_core:ChargePlayer(source, 500, { method = 'auto', reason = 'Car wash' })
---     if not receipt then return end   -- err is readable: 'Not enough cash (have $20, need $500)'
---     if not doTheThing() then exports.whip_core:RefundPlayer(receipt) end
---
--- `auto` (the default) takes cash if they carry enough, otherwise the bank. A bank payment uses the
--- player's own withdraw permission (default account unless `accountId`). `currency` makes a cash
--- payment in another item (gold bars), refunded in that item. An amount of 0 moves nothing and still
--- returns a receipt.
---@param source number
---@param amount number Whole number, 0 or more
---@param opts? { method?: 'cash'|'bank'|'auto', accountId?: number, currency?: string, reason?: string }
---@return WhipReceipt|false receipt
---@return string|nil err
---@async
function whip_core:ChargePlayer(source, amount, opts) end

--- Give back a payment ChargePlayer took — all of it, or `amount` of it. Only the resource that
--- charged may, only up to what is left, and only for 30 minutes. It goes back where it came from
--- with no permission check; a bank refund that is refused comes back as cash, and cash for a player
--- who has left goes to their bank.
---@param receipt WhipReceipt|number The receipt, or its id
---@param amount? number Default: everything not yet refunded
---@return boolean ok
---@return string|nil err
---@async
function whip_core:RefundPlayer(receipt, amount) end

--- MONEY HELD, for a metered service (a pump's fuel, a taxi's fare): take the most it could cost now, say what is
--- used as it runs, settle when it ends and the rest comes back. The refund for all of it is noted with the charge,
--- so a crash is paid back at the next login; the payer leaving, your resource or whip_core stopping settles it for
--- what was used. Yours alone.
---@param source number
---@param amount number
---@param opts { method: 'cash'|'bank', reason: string|nil, vehicle: number|nil }|nil vehicle: that car's row held unwritten till the settle
---@return integer|false holdId
---@return string|nil why
---@async
function whip_core:HoldMoney(source, amount, opts) end

--- How much of your hold is used so far (money, 0 to what was held). false and why: it is gone (settled by
--- whip_core), or not yours.
---@param id integer
---@param spent number
---@return boolean ok
---@return string|nil why
function whip_core:SpendMoneyHold(id, spent) end

--- End your hold: `spent` (else what SpendMoneyHold last said) kept, the rest back. false and why: settled already,
--- or not yours.
---@param id integer
---@param spent number|nil
---@return { spent: number, refunded: number, paidNow: boolean }|false
---@return string|nil why
---@async
function whip_core:SettleMoneyHold(id, spent) end

--- One of your holds as it is now, or nil (not yours, or settled): ask it before giving more of the service.
---@param id integer
---@return { source: number, amount: number, spent: number, method: string }|nil
function whip_core:GetMoneyHold(id) end

---@class WhipPayResult
---@field method 'cash'|'bank'
---@field amount number
---@field currency string|nil The item paid (cash payments)
---@field placement 'inventory'|'ground'|nil Where cash went: their pockets, or at their feet when full
---@field accountId number|nil The account paid into (bank payments)

--- Pay a player — a wage, a reward, a sale: the other way from ChargePlayer.
---
---     exports.whip_core:PayPlayer(source, 250, { reason = 'Courier job' })
---     exports.whip_core:PayPlayer({ charId = 12 }, 250, { method = 'bank', reason = 'Wages' })
---
--- `auto` (the default) pays cash while they are online, else into their bank. Cash that does not fit
--- lands at their feet, never lost. Someone not online can only be paid into the bank. 0 pays nothing.
---@param who number|{ charId: number } A server id (online), or a character (online or not)
---@param amount number Whole number, 0 or more
---@param opts? { method?: 'cash'|'bank'|'auto', accountId?: number, currency?: string, reason?: string }
---@return WhipPayResult|false result
---@return string|nil why
---@async
function whip_core:PayPlayer(who, amount, opts) end

-- ============================================
-- Jobs
-- ============================================

-- Every job export names things one way:
--   WhipJobRef     a jobId (number) or a key ('police')
--   WhipPersonRef  a source (a player online), or { charId = n } — any character, online or not
--   WhipRoleRef    a roleId (number) or a role name ('Manager', any case)
-- and returns a value, or false and a reason in words ('No such job', 'They do not work there', ...).

---@alias WhipJobRef number|string
---@alias WhipPersonRef number|{ charId: number }
---@alias WhipRoleRef number|string

--- Get a job by jobId or key.
---@param job WhipJobRef
---@return WhipJobDef|nil
function whip_core:GetJob(job) end

--- Every job, in jobId order.
---@return WhipJobDef[]
function whip_core:GetJobs() end

--- A job's roles, highest level first.
---@param job WhipJobRef
---@return WhipJobRole[]|false roles
---@return string|nil err
function whip_core:GetJobRoles(job) end

--- Find-or-create a job by key. On a job that exists, the name, icon, `permissions` and `selfClockOn`
--- follow the call and missing `roles` are added; the owner and existing roles never change. A key
--- another running resource declared is refused. Waits (up to 60 s) while whip_core is starting.
---@param key string Job key: letters, digits and _ (e.g. 'police')
---@param data { name: string?, icon: string?, owner: WhipPersonRef?, roles: { name: string, level: integer, permissions: table? }[]?, permissions: table<string, string>?, selfClockOn: boolean?, settings: table? }?
---@return WhipJobDef|false job
---@return string|nil err
---@async
function whip_core:EnsureJob(key, data) end

--- Change a job's name, icon or owner (`owner = false` removes it; refused while it has a business
--- account). The business account follows a new owner. Refused for a job another running resource declares.
---@param job WhipJobRef
---@param patch { name: string?, icon: string?, owner: WhipPersonRef|false|nil }
---@return boolean ok  true once the job changed (a business account that could not follow is reported in the console)
---@return string|nil err  only with false
---@async
function whip_core:UpdateJob(job, patch) end

--- Delete a job, its roles and staff list; its business accounts close with it. Refused while one
--- holds money ('Empty the job's business account first'), and for a job another running resource declares.
---@param job WhipJobRef
---@return boolean ok
---@return string|nil err
---@async
function whip_core:DeleteJob(job) end

--- The job they are on duty at — the most recent clock-on — or nil.
---@param who WhipPersonRef
---@return WhipPlayerJobInfo|nil
function whip_core:GetPlayerJob(who) end

--- Every job they have a role at, by jobId.
---@param who WhipPersonRef
---@return table<number, WhipPlayerJobInfo>
function whip_core:GetPlayerJobs(who) end

--- On duty at this job — or, with no job, at any.
---@param who WhipPersonRef
---@param job WhipJobRef?
---@return boolean clockedOn
---@return string|nil why  with false when the question is wrong (no such player or job)
function whip_core:IsPlayerClockedOn(who, job) end

--- Their role at this job (the top role if they own it), or nil.
---@param who WhipPersonRef
---@param job WhipJobRef
---@return WhipJobRole|nil
function whip_core:GetPlayerRole(who, job) end

--- May they do this at this job? A built-in ('canHire', 'canFire', 'canPromote', 'canDemote',
--- 'canManage') or one the job declared. `{ onDuty = true }` also requires being on duty there.
---@param who WhipPersonRef
---@param job WhipJobRef
---@param permission string
---@param opts { onDuty: boolean? }?
---@return boolean ok
---@return string|nil why  'Not on duty at ...', 'Not allowed at ...', no such player or job
function whip_core:HasJobPermission(who, job, permission, opts) end

--- Everyone on the payroll, by charId.
---@param job WhipJobRef
---@return table<number, WhipJobEmployee>|false employees
---@return string|nil err
function whip_core:GetJobEmployees(job) end

--- Everyone on duty at this job, the owner included.
---@param job WhipJobRef
---@return { charId: number, source: number }[]|false
---@return string|nil err
function whip_core:GetClockedOnEmployees(job) end

--- Hire someone. Without a role they start at the lowest one. `opts.by` is the player doing it:
--- recorded, and checked — they must outrank the role, hold canHire, and hold everything the role can do
--- (its permissions, its business-account access). Leave it out when your own code or an admin decides
--- (then nothing is checked).
---@param who WhipPersonRef
---@param job WhipJobRef
---@param role WhipRoleRef?
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil err 'They already work there' | 'No such role at that job' | 'No such character' | 'Your role is not allowed to do that' | 'They (or that role) outrank you' | ...
---@async
function whip_core:HirePlayer(who, job, role, opts) end

--- Would HirePlayer with these arguments be allowed? Every one of its rules, nothing written: ask before a step that
--- waits on someone (a job offer they accept), then hire.
---@param who WhipPersonRef
---@param job WhipJobRef
---@param role WhipRoleRef?
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil why
---@async
function whip_core:CanHirePlayer(who, job, role, opts) end

--- Fire someone. `opts.by` is the player doing it, checked: they must outrank the person and hold canFire.
---@param who WhipPersonRef
---@param job WhipJobRef
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil err
function whip_core:FirePlayer(who, job, opts) end

--- Change someone's role. `opts.by` is the player doing it, checked: they must outrank the person's
--- role now and the new one, and hold canPromote (up) or canDemote (down); the new role gives the person
--- nothing the player's own role can't do.
---@param who WhipPersonRef
---@param job WhipJobRef
---@param role WhipRoleRef
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil err
function whip_core:SetPlayerRole(who, job, role, opts) end

--- Add a role to a job. `opts.by` is the player doing it, checked: they hold canManage, and below level
--- 100 the new role is below their own level and can do no more than theirs. A permission the job does not
--- have is refused.
---@param job WhipJobRef
---@param data { name: string, level: integer, permissions: table<string, boolean|string>? } level 1-100; permissions { canHire = true, bankAccess = 'view' }
---@param opts { by: WhipPersonRef? }?
---@return WhipJobRole|false role
---@return string|nil err 'There is already a role called ...' | 'They (or that role) outrank you' | ...
---@async
function whip_core:CreateJobRole(job, data, opts) end

--- Change a role's name, level or permissions; permissions not named keep their value, `false` takes one
--- away. `opts.by` is the player doing it, checked: canManage, the role and its new level below their own
--- (below 100), nothing added their own role can't do, and the job keeps a level 100 role.
---@param job WhipJobRef
---@param role WhipRoleRef
---@param patch { name: string?, level: integer?, permissions: table<string, boolean|string>? }
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil err
---@async
function whip_core:UpdateJobRole(job, role, patch, opts) end

--- Delete a role nobody holds. `opts.by` is checked as for UpdateJobRole.
---@param job WhipJobRef
---@param role WhipRoleRef
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil err 'Move the people in that role to another role first' | ...
---@async
function whip_core:DeleteJobRole(job, role, opts) end

--- Put an online player on duty (Config.JobDutyOneAtATime clocks off every other job first). `opts.by` is
--- the player doing it, checked like the client's ClockOn: only themselves, and only where the job's
--- selfClockOn allows it.
---@param who WhipPersonRef
---@param job WhipJobRef
---@param opts { by: WhipPersonRef? }?
---@return boolean ok
---@return string|nil err 'They do not work there' | 'They are not online' | 'No such job' | 'This job puts people on duty itself' | ...
function whip_core:ClockOn(who, job, opts) end

--- Take someone off duty at a job — or, with no job, everywhere.
---@param who WhipPersonRef
---@param job WhipJobRef?
---@return boolean ok
---@return string|nil err 'They are not on duty' | ...
function whip_core:ClockOff(who, job) end

-- ============================================
-- Inventory
-- ============================================
--
-- The player shortcuts: each spans every pocket the character carries — "this player, wherever it
-- fits on them". One specific slot, or any other store, is named by ADDRESS (the Stores section):
-- GetItemAt, SetItemMetadata, StoreGive, StoreTake. A use handler and FindItem hand you the address.

--- Get a deep copy of a player's full inventory cache.
---@param source number Player server ID
---@return WhipInventoryCache inventory  {} when the player is not loaded
---@return string|nil why  'Player not loaded'
function whip_core:GetInventory(source) end

--- Give a player an item, wherever it fits in their pockets.
---
--- If it fits nowhere, the item is DROPPED AT THE PLAYER'S FEET and that still counts as given — the
--- result is 'ground'. Pass `{ noDrop = true }` to refuse instead. (Config.DropOnFullInventory = false
--- does the same server-wide.) A mistyped item or a bad amount is REFUSED — (false, 'Unknown item
--- "x"') — never dropped.
---
---     local where, err = exports.whip_core:AddItem(source, 'drink', 2, nil, 'quest reward')
---     if not where then print(err) elseif where == 'ground' then --[[ dropped ]] end
---@param source number Player server ID
---@param item string Item key (must be registered)
---@param amount? number A whole number, 1 or more (default: 1)
---@param metadata? table Item metadata
---@param opts? string|WhipAddItemOpts A reason for the activity log ('quest reward'), or options
---@return 'inventory'|'ground'|false where  where it went; false when nothing was given
---@return string|nil err
---@async
function whip_core:AddItem(source, item, amount, metadata, opts) end

--- Remove an item from any container (scans every PlayerContainers entry), as AddItem's shape: `metadata` takes
--- only the stacks whose metadata carries every one of its values.
---
---     exports.whip_core:RemoveItem(source, 'repair_kit', 1, nil, { reason = 'repair' })
---@param source number Player server ID
---@param item string Item key
---@param amount? number Amount to remove (default: 1)
---@param metadata? table Only stacks carrying these values ({ serial = 'AB12' })
---@param opts? string|{ reason: string } For the activity log (see AddItem) — either shape
---@return boolean success
---@return string|nil error
---@async
function whip_core:RemoveItem(source, item, amount, metadata, opts) end

--- Check if player has an item across all containers.
---@param source number Player server ID
---@param item string Item key
---@param amount? number Required amount (default: 1)
---@return boolean
function whip_core:HasItem(source, item, amount) end

--- Count an item across all containers.
---@param source number Player server ID
---@param item string Item key
---@return number count
function whip_core:GetItemCount(source, item) end

--- Will this item fit on the player — weight and slots, across every pocket?
---
--- Pass `metadata` when checking room for a SPECIFIC instance that carries contents — a loaded
--- magazine, a wallet with cash in it. Contents live in metadata, so without it the item is
--- weighed empty and the result comes back optimistic.
---@param source number Player server ID
---@param item string Item key
---@param amount? number Amount (default: 1)
---@param metadata? table The instance's metadata, if checking a specific one
---@return boolean fits
---@return string|nil err  a sentence: 'Only 3 fit', 'No room', 'Unknown item "x"', a bad amount
function whip_core:CanFitItem(source, item, amount, metadata) end

--- The player's pockets, in order: { 'player', 'accessory' }. Use it for enum validation instead of
--- hardcoding the list — a hardcoded list silently breaks the day a server adds a pocket or a whip
--- release removes one. Read it at registration time; it does not change at runtime.
---     { 'pocket', 'enum', exports.whip_core:GetPockets(), 'player' }
---@return string[]
function whip_core:GetPockets() end

--- Slot count for one of the player's pockets (see GetPockets). Returns the whole table when called
--- with no argument. Bounds a slot loop by the real capacity instead of a guess.
---@param pocket? string 'player' | 'accessory'
---@return number|table<string, number>|nil
function whip_core:GetPocketSlots(pocket) end

--- Max weight for one of the player's pockets, same contract as GetPocketSlots.
---@param pocket? string
---@return number|table<string, number>|nil
function whip_core:GetPocketMaxWeight(pocket) end

--- The first stack of an item the player carries (the lowest slot first), with its address — or nil.
---@param source number Player server ID
---@param item string Item key
---@param pocket? string Only this pocket; one that does not exist finds nothing
---@return WhipFoundItem|nil
function whip_core:FindItem(source, item, pocket) end

--- Every stack of an item the player carries, each with its address. An empty list when none.
---@param source number Player server ID
---@param item string Item key
---@param pocket? string Only this pocket
---@return WhipFoundItem[]
function whip_core:FindAllItems(source, item, pocket) end

-- ============================================
-- Inventory — Registration
-- ============================================

--- Register a new item definition at runtime (adds to Config.Items).
--- Re-registering your own item replaces it. An item another running resource (or whip_core)
--- registered is refused — you cannot redefine `cash` or `vehicle_key`.
---@param key string Item key: letters, digits, _ and - only (no colon), 50 characters at most
---@param definition WhipItemDef Item definition
---@return boolean ok
---@return string|nil err
function whip_core:RegisterItem(key, definition) end

--- Take an item out of the game for good. Only your own key: refused for one a running resource holds or another
--- resource registered last (remembered across restarts). Its definition goes, nothing can
--- make a new one, and RegisterItem refuses the name. Every one already out there is taken away, logged as 'lost'
--- with your reason, not refunded: at once from online players, open stashes and boots and the ground; the rest as
--- each loads (a character at login, a stash or a car when opened). Inside duffle bags and wallets too.
--- Yours while your resource runs, as every registration; asking again changes nothing.
---
---     exports.whip_core:RetireItem('mycafe_bagel', 'Bagels are off the menu')
---@param key string Item key
---@param reason? string For the log (120 characters at most)
---@return boolean ok
---@return string|nil err
function whip_core:RetireItem(key, reason) end

--- Give up your own RetireItem. The name is free again (RegisterItem it to bring the item back); what was taken
--- stays taken.
---@param key string Item key
---@return boolean ok
---@return string|nil err
function whip_core:UnretireItem(key) end

--- Register a metadata generator for an item. Called when the item is first created to produce default metadata.
---@param itemKey string Item key
---@param generator fun(itemKey: string, ctx: { source: number|nil, charId: number|nil, reason: 'given'|'pickup'|'shelf'|'bought' }|nil): table Returns default metadata table. ctx says who it is for (nil into a stash; ctx itself nil from the Director's rewards)
---@param opts { forBuyer: boolean|nil }|nil forBuyer: bought off an infinite shelf, it is made again for the buyer
---@return boolean ok
---@return string|nil err
function whip_core:RegisterItemDefaultMetadata(itemKey, generator, opts) end

--- Register a context menu action handler. Called when the player selects a custom context action.
--- Same handler shape as RegisterUseHandler: `(source, player, slotData, addr)`, and a fifth, `how`: nil from the
--- inventory, `{ from = 'ground' }` when it runs straight after a pick up from a pile's prompt (an item's
--- groundOptions: Equip on a gun lying there), so it can skip what the pick up already showed.
--- A name whip_core uses for its own panel items (a wallet's, a bag's) is refused.
--- START IT WITH YOUR RESOURCE'S NAME ('my_bows:equip'): action names are one list for the whole
--- server, first come first served. At most 32 characters.
---@param actionKey string Action key (must match item's defaultAction or contextOptions)
---@param handler fun(source: number, player: table, slotData: WhipInventorySlot, addr: WhipStoreAddr, how: { from: 'ground' }|nil) `player` is the data sheet
---@return boolean ok
---@return string|nil err
function whip_core:RegisterContextAction(actionKey, handler) end

--- Add a right-click option to an item, yours or another resource's (a police resource's "Check for
--- prints" on whip_gunny's guns). The option is a contextOptions entry; its action is yours, registered
--- with RegisterContextAction. It goes when your resource stops. Refused: an option that is not one, an
--- action the item already has of its own, the same item and action another resource added.
---@param itemKey string
---@param option { action: string, label: string, order?: number, when?: table, require?: table }
---@return boolean ok
---@return string|nil err
function whip_core:AddItemOption(itemKey, option) end

--- Take back an option AddItemOption added (only your own).
---@param itemKey string
---@param action string
---@return boolean ok
---@return string|nil err
function whip_core:RemoveItemOption(itemKey, action) end

--- One of an item's settings in force: one of its own (its definition's `settings`), or its 'name',
--- 'desc' or 'weight'. What an admin saved on /whip → Items, else the item's own. Nil for a key it
--- does not have.
---@param item string  the item's key
---@param key string
---@return any value
function whip_core:GetItemSetting(item, key) end

--- fn(value, old, item, key) after one of an item's own settings changes on the server (Reset too).
--- One per resource for each setting: calling again replaces it. Goes when your resource stops.
---@param item string  the item's key
---@param key string
---@param fn fun(value: any, old: any, item: string, key: string)
---@return boolean ok
---@return string|nil why
function whip_core:OnItemSettingChanged(item, key, fn) end

--- Say what happens when a player USES an item (clicks Use, or presses its hotbar key).
---
--- The handler gets `(source, player, slotData, addr)`:
---   player    the player SHEET (serialize()) for any resource but whip_core — read it, do not keep it
---   slotData  the item used: { item, amount, metadata }
---   addr      where it is — the handle for GetItemAt / StoreTake / SetItemMetadata
--- Return `false` to KEEP the item (a jerry can, a tool); anything else, including nothing, uses one
--- up. The item needs `usable = true`; whip says so in the console if it is registered without it.
---
--- OR A TABLE, for a use with a progress bar — whip runs the bar (timed by the
--- server), checks the item is still there, takes it, then calls onComplete; `false, 'why'` from
--- onComplete gives it back. See WhipTimedUse.
---
---     exports.whip_core:RegisterUseHandler('bandage', {
---         label = 'Bandaging...', duration = 4000,
---         onComplete = function(source) exports.whip_core:AddStat(source, 'health', 25) end,
---     })
---@param itemKey string Item key
---@param handler (fun(source: number, player: table, slotData: WhipInventorySlot, addr: WhipStoreAddr): boolean|nil)|WhipTimedUse
---@return boolean ok
---@return string|nil err  also for a table without a positive `duration`
function whip_core:RegisterUseHandler(itemKey, handler) end

--- Write a row into the activity log's player timeline (and, when slotData names a slot,
--- into that item instance's own timeline — minting its uid on first touch). Use for
--- anything a satellite considers admin-timeline-worthy: a Whiplash bay entered, a
--- radial option used, a minigame won.
---
---     exports.whip_core:LogActivity(source, 'whiplash_enter', { detail = 'bay 3' })
---@param source number Player server id
---@param event string Short event key, e.g. 'whiplash_enter'
---@param opts? { detail?: string, slotData?: WhipStoreAddr|WhipInventorySlot } detail: free text shown on the row (truncated to 191). slotData: the item's ADDRESS ({ kind = 'player', id = source, sub = 'player', slot = 4 }, or any store's); a slot table from GetItemAt is also accepted, but it is a copy, so it can only use a uid the item already has
---@return boolean ok, string|nil err
---@async
function whip_core:LogActivity(source, event, opts) end

--- Write every activity-log row still owed, now (tests, ops). Rows normally land with the change they
--- describe; this waits for a write already in flight, and is false if the database refused the rows.
---@return boolean ok
---@async
function whip_core:FlushActivityLog() end

--- Validate a character-appearance table against the same rules the
--- saveAppearance event enforces: structural wrongness rejects, out-of-range
--- values clamp. Returns a NEW table; the input is never mutated.
---
--- BOOLEAN FIRST: FiveM truncates a cross-resource return that leads with nil, so
--- `ok` is false on refusal and the second value is the reason.
--- Tattoos are optional: `tattoos = { { collection = 'mpBiker_overlays', overlay = 'MP_MP_Biker_Tat_000_M' }, ... }`,
--- in the order put on. Kept only if shared/tattoo_list.lua names it for that body (in the list's spelling,
--- once each, at most 40); anything else is dropped, never refused. None: no `tattoos` key.
--- The hair fade is optional too: `hairFade = { collection = 'multiplayer_overlays', overlay = 'NG_M_Hair_001' }`, one at
--- most, kept only if shared/hair_fades.lua names it for that body (in the list's spelling). None: no `hairFade` key.
---@param appearance table The full appearance shape (model, headBlend, faceFeatures[20], eyeColor, hair, overlays, components, props, tattoos?, hairFade?)
---@return boolean ok
---@return table|string result The sanitized appearance when ok, otherwise the reason it was refused
function whip_core:SanitizeAppearance(appearance) end

--- Open a player's character editor on their own character, as /charedit does: Save keeps the new look, Cancel
--- puts the old one back. Refused for someone not online, still making their character, or down; their game also
--- refuses it while the editor is already open.
---@param who number|{ charId: number } A server id, or { charId = n } for a character who is online
---@return boolean ok
---@return string|nil why
function whip_core:OpenCharacterEditor(who) end

--- What a store's customer changed (client EditAppearance): their saved look against `look`, by the editor's tabs.
--- A count per category id ('tops' = 1, 'makeup' = 2 for two of its overlays) and `tattoos` for tattoos put on.
--- Taking off an accessory or a tattoo counts nothing. `only` (the editor's category ids or groups) counts only those.
---
---     local changes = exports.whip_core:GetAppearanceChanges(source, look, { 'apparel', 'props' })
---@param who number|{ charId: number } A server id, or { charId = n } for a character who is playing
---@param look table The look from the editor
---@param only? string[] Category ids ('hair', 'tops') or groups ('face', 'apparel', 'props', 'tattoos', 'outfits')
---@return table|false changes { [id] = count, tattoos? = count }
---@return string|nil why
function whip_core:GetAppearanceChanges(who, look, only) end

--- Keep a look for a playing character, checked as the editor's Save is. opts.only takes only those tabs' parts
--- from `look` and keeps the rest of their saved look, so a barber can't change a face. Their game gets it at once.
---
---     local ok, why = exports.whip_core:SetPlayerAppearance(source, look, { only = { 'hair', 'beard' } })
---@param who number|{ charId: number } A server id, or { charId = n } for a character who is playing
---@param look table The look
---@param opts? { only?: string[] }
---@return boolean ok
---@return table|string result The look kept, or why not
function whip_core:SetPlayerAppearance(who, look, opts) end

--- Register (or replace) one accessory-strip slot. Re-registration is
--- idempotent, and a stopping resource's slots are unregistered automatically.
--- `accepts` names the item key the slot takes, or a list of them; `keys = true` takes any ignition key
--- too (RegisterIgnitionKey); with neither it takes anything. The registry is the rule, the
--- NUI's copy only makes refusals instant. `tag` is a run tag: ReleaseTag(tag) puts whip's own slot back.
---@param def { slot: number, accepts?: string|string[], keys?: boolean, label?: string, icon?: string, iconSvg?: string, tag?: string } slot is 1..Config.ContainerSlots.accessory
---@return boolean ok
---@return string|nil err
function whip_core:RegisterAccessorySlot(def) end

--- What the accessory strip looks like right now, keyed by slot number.
---
--- The read side of RegisterAccessorySlot, which did not exist: a satellite could add a slot but
--- never ask what was already there, so the only way to learn whether a slot was free was to try a
--- move and see whether the store refused it. A copy, not the registry — assigning into the
--- returned table changes nothing.
---@return table<number, { slot: number, accepts: string[]|nil, keys: boolean|nil, label: string, icon: string|nil }>
function whip_core:GetAccessorySlots() end

--- Register an item the vehicle ignition slot accepts — and that the
--- "does this player hold a key" sweeps count. Unregistered automatically when
--- the calling resource stops.
---@param itemName string Item key
---@return boolean ok
---@return string|nil err
function whip_core:RegisterIgnitionKey(itemName) end

-- ============================================
-- Items
-- ============================================

--- Get an item definition by key.
---@param key string Item key
---@return WhipItemDef|nil
function whip_core:GetItemDef(key) end

--- Get all registered item definitions.
---@return table<string, WhipItemDef>
function whip_core:GetItemDefs() end

-- ============================================
-- Vehicles
-- ============================================

--- Everything whip knows about a vehicle, in one call. THE read.
---
--- Always a copy — editing what comes back changes nothing.
---
---     local v = exports.whip_core:GetVehicle(id)
---     local v = exports.whip_core:GetVehicle({ plate = 'ABC123' })   -- or { netId = }, { entity = }
---     v.plate  v.model  v.owner.charId  v.state  v.garage  v.coords  v.locked  v.session
---     v.spawned  v.entity  v.netId  v.stats.fuel  v.data.mine  v.properties  v.storage
---
--- Occupants cost a scan of every player on the server, so they are opt-in.
---
--- Every vehicle, stat and data export takes a vehicleId OR a vehicle reference (WhipVehicleRef):
--- `{ id = }`, `{ entity = }`, `{ plate = }`, `{ netId = }`. GetVehicle returns nil for a car whip
--- does not know; the exports that return `false, why` say 'Vehicle not found', or 'Invalid vehicle
--- reference' for a table that names nothing.
---@param vehicleId number|WhipVehicleRef
---@param opts table|nil `{ occupants = true }`
---@return WhipVehicleContext|nil
function whip_core:GetVehicle(vehicleId, opts) end

--- Every vehicle a person owns, as full snapshots. A person: a server id, or `{ charId = n }`.
---@param who number|{ charId: number } A server id, or a character
---@return WhipVehicleContext[]
---@return string|nil why  with {} when `who` names nobody
function whip_core:GetVehiclesOf(who) end

--- Where is this vehicle? Three floats, and nothing else — the shape the
--- `near` schema wants, without four lines of nil checks through GetVehicle.
--- Only a car that is in the world has one; garaged, despawned or lost is nil
--- (a `near` check against it fails). Last seen: GetVehicle(id).coords.
---@param vehicleId number|WhipVehicleRef
---@return number|nil x  nil when the car is not in the world
---@return number|nil y
---@return number|nil z
function whip_core:GetVehiclePosition(vehicleId) end

-- A vehicle's trunk, glovebox or ignition is a store: StoreRead({ kind = 'vehicle', id = vehicle,
-- sub = 'trunk' }), where `id` is a vehicleId or a vehicle reference.

--- Set a vehicle's lock state. Every car is unlocked when the server starts, so a lock lasts until the
--- next restart.
---
--- Fires `whip_core:vehicle:lockChanged` `{ vehicleId, plate, locked, source }` when the state
--- actually changes — as every lock change does, whoever made it.
---@param vehicleId number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@param locked boolean True to lock, false to unlock
---@return boolean ok
---@return string|nil error
---@async
function whip_core:SetVehicleLocked(vehicleId, locked) end

--- Give a vehicle key item to a player: their server id, or { charId = n } while they play (a key goes into
--- pockets, so they must be online). Refused when they hold a key of it already, unless `opts.spare = true` (a
--- second key, to hand to someone).
---@param who number|{ charId: number }
---@param vehicleId number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@param opts { spare?: boolean }|nil
---@return boolean success
---@return string|nil err  only with false: 'Already has a key for this vehicle', no room, not online, ...
---@async
function whip_core:GiveVehicleKey(who, vehicleId, opts) end

--- Change an owned car's locks: every key of it cut so far stops fitting, wherever it is (pockets, a stash, a boot,
--- its own ignition, the ground, a character who is not playing), and keys cut after fit. It lasts through a
--- restart. A car running on an old key stops. A street or temporary car is refused.
---@param vehicleId number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@return boolean ok
---@return string|nil err  only with false
---@async
function whip_core:ChangeVehicleLocks(vehicleId) end

--- How many keys fit a car now, wherever they are: every character's pockets (online or not), every stash, every
--- car's boot, glovebox and ignition, and the ground. A key inside another item (a bag), a resource's own stores and
--- an open panel's slots are not counted.
---@param vehicleId number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@return number|false count
---@return string|nil err  only with false: no such vehicle, the database could not be read
---@async
function whip_core:CountVehicleKeys(vehicleId) end

--- Has this person a key for a vehicle (scans their pockets)? A character who is not playing is read from the
--- database.
---@param who number|{ charId: number } A server id, or a character (online or not)
---@param vehicleId number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@return boolean
---@return string? why  with false when the question could not be asked: no such person, a bad reference
---@async
function whip_core:HasVehicleKey(who, vehicleId) end

--- Every vehicle key a person holds. A character who is not playing is read from the database.
---@param who number|{ charId: number } A server id, or a character (online or not)
---@return table<number, string> keys Map of vehicleId to plate
---@return string|nil why with {} when it could not be read
---@async
function whip_core:GetPlayerVehicleKeys(who) end

--- Take on a car already in the world, adopting it as a session vehicle if whip has never seen it.
--- It never creates a car.
---
--- Pass THE CAR when you have it — `{ entity = veh }` or `{ netId = id }` adopts exactly that one. A
--- plate is for a caller holding a plate and nothing else (a database row, an ANPR camera), and takes
--- whichever car on the map wears that text first. A CLIENT holding an entity wants ResolveVehicle.
--- `player = source` with the car: brought in for that player, a car never seen counts against their street-car
--- limit (refused past it).
---@param ref string|{ entity?: number, netId?: number, player?: number } License plate text, or the car
---@return number|false vehicleId, string|nil err
---@async
function whip_core:AdoptVehicle(ref) end

--- Keep a car's engine from running, `reason` shown to its driver (80 letters): it will not start, a running one
--- stops, the car still rolls. `key` names your hold (the same again replaces its reason). It goes when you release
--- it, your resource stops, or the car's id goes.
---@param vehicleId number
---@param key string
---@param reason string|nil
---@return boolean ok
---@return string|nil why
function whip_core:HoldVehicleEngine(vehicleId, key, reason) end

--- Let go of your hold `key` on the car (no key: every hold of yours on it). true when one went, or false and why.
---@param vehicleId number
---@param key string|nil
---@return boolean released
---@return string|nil why
function whip_core:ReleaseVehicleEngine(vehicleId, key) end

--- Is anything holding the car's engine off (anyone's hold)? Its reason, or nil.
---@param vehicleId number
---@return string|nil reason
function whip_core:GetVehicleEngineHold(vehicleId) end

--- Put props in a player's hand, for everyone: { { model, bone?, offset? = {x,y,z}, rot? = {x,y,z} } }, at most two
--- (bone defaults to SKEL_L_Hand 18905). The server makes them and the player's own game ties them on. It replaces
--- whatever the hand held (an emote's cup, a bar's tool); `tag` names your set, kept as '<resource>:<tag>', and your
--- props go when your resource stops. whip_core:heldProps:lost says when yours left without you asking.
---@param source number
---@param props table[]  { { model, bone?, offset?, rot? } }, 1 or 2
---@param tag string|nil  your name for the set (default 'held')
---@return boolean ok
---@return string|nil why
function whip_core:HoldProps(source, props, tag) end

--- Take your props of `tag` out of a player's hand; with no tag, whatever of yours they hold. Never anybody else's.
---@param source number
---@param tag string|nil
---@return boolean dropped  whether anything went
---@return string|nil why  when nothing did
function whip_core:DropHeldProps(source, tag) end

--- What a player's hands hold, or are about to: the tag ('<resource>:<tag>', or whip's own 'emote', 'bar', 'give',
--- 'take'), or nil. whip_core:heldProps:lost says when yours left without you asking.
---@param source number
---@return string|nil tag
function whip_core:GetHeldPropsTag(source) end

-- A car's session flag and owner are fields of the one read:
--
--   exports.whip_core:GetVehicle(id).session
--   exports.whip_core:GetVehicle(id).owner    -- { charId, name, online }

-- Fuel (whip_fuel's) is an ordinary vehicle stat and uses the same two calls as every other one:
--
--   exports.whip_core:GetVehicleStat(vehicleId, 'fuel')
--   exports.whip_core:SetVehicleStat(vehicleId, 'fuel', 42.0, 'refuel:pump')

--- Remove every key to this vehicle from a player's inventory (every one that fits, not the first). `who` as
--- GiveVehicleKey: a server id, or { charId = n } while they play.
---@param who number|{ charId: number }
---@param vehicleId number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@return boolean success  true if at least one was removed
---@return string? why  only with false: 'They have no key for that vehicle', not online, ...
---@async
function whip_core:RemoveVehicleKey(who, vehicleId) end

-- By network id: exports.whip_core:GetVehicle({ netId = netId })

--- Create a vehicle owned by a player's character.
---
--- ownerCharId is taken from the caller's player record and NOT from `data`: a satellite passing a
--- charId would be asserting who owns the vehicle, and nothing downstream would question it.
---
--- THE SECOND RETURN IS THE ERROR, ALWAYS. The plate is a field of the vehicle:
---
---     local vehicleId, err = exports.whip_core:CreateOwnedVehicle(source, { model = 'adder' })
---     if not vehicleId then return end
---     local plate = exports.whip_core:GetVehicle(vehicleId).plate
---
--- A WHOLE SALE IN ONE CALL: `opts = { giveKey = true, spawnAt = vector4(...) }` also brings the car
--- out there and hands over the key. If either fails the car is deleted again and the result is
--- `(false, reason)`. `vehType` comes from the vehicle catalog when not given. `garage` must name a
--- garage that exists; left out, the car goes in the default garage. Only spawnAt puts it in the
--- world: `state = 'out'` without spawnAt is refused, and data.x/y/z are not read. spawnAt is also
--- refused while a vehicle or another player stands on the spot, and for a builder in the Director's
--- Isolate world ('Leave Isolate world first'); ask CanBringOutVehicleFor before charging.
---@param source number  the buying/receiving player
---@param data table  { model, plate?, garage?, stats?, properties?, vehType?, trunkSlots?, trunkMaxWeight?, gloveboxSlots?, gloveboxMaxWeight? } — stats: what it starts with by stat name ({ fuel = 100 })
---@param opts table|nil  { giveKey?: boolean, spawnAt?: vector4|vector3|{x,y,z,heading} }
---@return number|false vehicleId, string|nil err
---@async
function whip_core:CreateOwnedVehicle(source, data, opts) end

--- Can a car be brought out for this player now? Ask it BEFORE charging for a car that comes out into
--- the world (CreateOwnedVehicle{spawnAt}): a builder in the Director's Isolate world is refused, since
--- whip's cars come out in the shared world where they would not see it. CreateOwnedVehicle still asks
--- the same question itself; this only lets a seller refuse before taking the money.
---@param source number
---@return boolean ok, string|nil why
function whip_core:CanBringOutVehicleFor(source) end

--- Does this game have a vehicle called `model`? Each player's game tells the server its list of
--- vehicles (add-on cars included) as they join (the character screen), and the server keeps them all,
--- saved per platform and game build across restarts; a name no game has reported for 14 days is dropped.
--- `nil` means no player's game has said yet (a new server, or a new game build), or the list is full
--- (20,000 names) and the model is not on it; nothing is refused then.
--- CreateOwnedVehicle, SpawnTempVehicle and the garages refuse a model the game does not have
--- (`'There is no vehicle called "x" in this game'`); a seller asks this to leave such cars out of its
--- stock. GetVehicleCatalog's rows carry the same result as `inGame`.
---@param model string
---@return boolean|nil
function whip_core:VehicleModelExists(model) end

--- Put a TEMPORARY car in the world — a rental, a job van, a test drive. No owner and no row, but a
--- vehicleId, stats, data, storage and keys like any other car.
---
--- It belongs to the calling resource and is removed when that resource stops, when `despawnAfter`
--- runs out (even with somebody driving it), after ten minutes with nobody near it (unless
--- `idleDespawn = false`), or by DespawnVehicle. Each fires `whip_core:vehicle:released` with a
--- `reason`. The key it gave is taken back when it goes. If the key cannot be given the car is
--- removed again and the result is `(false, reason)`.
---
--- It spawns locked (`locked = false` for one that stands open). `keyInIgnition = true` puts a key
--- in its ignition, so anyone in the driver's seat can start it. GetVehicle shows `temp = true`.
---
--- `tag` files it under one of your tags (ReleaseTag removes it; a released tag spawns no more).
--- `secure = true`: no lockpicking, no ignition hacking — only its key works.
---@param model string
---@param coords vector4|vector3|table  `{ x, y, z, heading }` works too
---@param opts WhipTempVehicleOpts|nil
---@return number|false vehicleId, string|nil err
---@async
function whip_core:SpawnTempVehicle(model, coords, opts) end

--- Make a car nobody owns (a temporary or street car) someone's own: a new owned car with a new id
--- (and plate unless opts.plate), its contents moved across, put where the old one stood.
---@param vehicle number|table  a vehicleId or a vehicle reference
---@param who number|{ charId: number }
---@param opts { plate?: string, here?: boolean, garage?: string, key?: boolean, reason?: string, leave?: fun(metadata: table|nil, item: string): boolean }|nil
---@return number|false vehicleId  the new one
---@return string|nil noteOrWhy  a note (it waits in its garage) or why not
---@async
function whip_core:ClaimVehicle(vehicle, who, opts) end

--- Change a car's plate (saved for an owned car).
---@param vehicle number|table
---@param plate string  up to 8 characters, not another car's
---@return boolean ok
---@return string|nil reason
---@async
function whip_core:SetVehiclePlate(vehicle, plate) end

--- Put a vehicle into the world.
---
--- Idempotent: calling it on a vehicle that is already out moves it rather than cloning it.
--- Omit `coords` to use the vehicle's own saved position; a vector4 carries the heading in w.
---
---     exports.whip_core:SpawnVehicle(vehicleId, vector4(215.0, -810.0, 30.7, 90.0))
---@param vehicleId number|WhipVehicleRef
---@param coords vector3|vector4|nil
---@return number|false netId, string|nil err
---@async
function whip_core:SpawnVehicle(vehicleId, coords) end

--- Take a vehicle out of the world and put it away in its garage (state 'garaged', no position), its record and
--- its storage contents intact — even with somebody inside. Storage is flushed before the entity is removed. It
--- does not come back at the next restart; SpawnVehicle brings it out again.
---
--- A car that was already out of the world is in the state you asked for, so that reports success.
--- It fails for an unknown vehicleId, a car busy being spawned, stored or deleted ('Vehicle is busy';
--- try again), or a garage save that did not go through. A temporary car (SpawnTempVehicle) is
--- removed for good; a street car is handed back to GTA (left where it is) and forgotten, its
--- storage logged as lost.
---
--- `opts.garage` puts the car away in that garage instead of its own. Then only an owned car that is `out` is taken:
--- a street or temporary car is refused (neither has a garage row), as is one already put away, or a key that
--- names no garage. `opts.refuseOccupied` refuses a car with somebody inside: on by default with a garage, off
--- without one.
---
---     exports.whip_core:DespawnVehicle(vehicleId, { garage = 'impound', refuseOccupied = true })
---@param vehicleId number|WhipVehicleRef
---@param opts? { garage?: string, refuseOccupied?: boolean }
---@return boolean ok, string|nil err
---@async
function whip_core:DespawnVehicle(vehicleId, opts) end

--- Take a vehicle out of a garage. Marks it `out` and locked; it still has to be spawned.
---
--- Two calls on purpose: retrieving decides the car MAY come out, spawning decides WHERE. A garage
--- uses its own spawn point; a satellite may want it somewhere else entirely.
---@param vehicleId number|WhipVehicleRef
---@param garageKey string|nil  defaults to the garage it is assigned to
---@return boolean ok, string|nil err
function whip_core:RetrieveVehicle(vehicleId, garageKey) end

--- Hand a vehicle to another player.
---
--- Takes the receiving player: their server id, or { charId = n } while they play. The new owner
--- must be online, the same rule CreateOwnedVehicle follows: read off a live player record, the
--- owner can only be a character that exists.
---
--- Fires `whip_core:vehicle:ownerChanged` and re-syncs both players' vehicle lists.
---
--- KEYS ARE NOT FULLY TRANSFERRED. A vehicle key is an inventory item carrying a vehicleId,
--- tied to no owner, so `revokeOldKeys` can only take one out of the previous owner's own
--- pockets while they are online. A key that is offline, stashed, in a boot or on the ground
--- survives and still works. Closing that needs a key generation on the vehicle.
---@param vehicleId number|WhipVehicleRef
---@param newOwner number|{ charId: number }  the receiving player, who must be online
---@param opts table|nil  { giveKey = true, revokeOldKeys = true }
---@return boolean ok, string|nil err
---@async
function whip_core:TransferVehicle(vehicleId, newOwner, opts) end

--- Destroy a vehicle and everything in it, permanently.
---
--- The row, the trunk, the glovebox, the ignition contents, the entity, any queued writes and
--- anybody's open view of its storage — all of it, in one transaction. A session vehicle is
--- deleted by being forgotten, since a street car has no row of its own.
---
--- Fires `whip_core:vehicle:deleted`, which is the hook for anything keeping its own
--- per-vehicle state. Ungated like every other satellite export.
---@param vehicleId number|WhipVehicleRef
---@return boolean ok, string|nil err
function whip_core:DeleteVehicle(vehicleId) end

--- Be told when one piece of vehicle data changes, on any vehicle.
---
--- The targeted alternative to the `whip_core:vehicle:dataChanged` broadcast, and the server half
--- of the client export of the same name. THE POSITIONS DIFFER BY SIDE: here (vehicleId, value,
--- cleared, old); on the client (vehicleId, value, old, entity). A listener moved across reads the
--- wrong thing with no error — prefer `{ table = true }`, the same field names on both sides.
--- Registering again from the same resource with the same id replaces rather than stacks.
---
--- `{ table = true }` hands the callback one WhipVehicleChange table — the same names on both sides —
--- and `{ now = true }` also calls it once straight away for every car carrying the key. The options
--- may go third, in place of `id`.
---@param key string
---@param callback fun(change: WhipVehicleChange)|fun(vehicleId: number, value: any, cleared: boolean, old: any) The first with `{ table = true }` (the one to prefer), else the second
---@param id string|WhipVehicleListenOpts|nil Defaults to the key
---@param opts WhipVehicleListenOpts|nil
---@return boolean registered
function whip_core:OnVehicleDataChanged(key, callback, id, opts) end

-- ============================================
-- Vehicle Data
-- ============================================
--
-- Anything json-encodable, attached to a vehicle by key, replicated on the entity and
-- persisted with the row. For a NUMBER WITH A RANGE the player should see, register a
-- vehicle stat instead — that is what gauges, drains and clearAtMin are for.
--
-- A KEY BELONGS TO THE RESOURCE THAT FIRST WROTE IT. Any resource can read it; writing or clearing
-- another resource's key is refused with a reason naming the owner. The 32-key budget is per
-- resource, and ClearAllVehicleData takes away only the caller's keys. Saved with the data.

--- Attach a value to a vehicle. Anything json-encodable (false included); nil removes it.
--- Refused with a reason when the key is malformed or another resource's, the vehicle is unknown,
--- or the block would bust your key budget or the size ceiling.
---
--- A table in place of the key sets several in one replication and one database write, and returns how many
--- were applied: keys past your key budget are skipped; a batch that busts the size ceiling, or touches a key
--- another resource owns, is refused whole (false, reason). A nil value cannot be expressed in a Lua table: use
--- ClearVehicleData to remove one.
---
---     exports.whip_core:SetVehicleData(vehicleId, { kit = 'street', kitAt = os.time() })
---@param vehicleId number|WhipVehicleRef
---@param key string|table<string, any> Letters, digits and underscore only; or { [key] = value }
---@param value any Json-encodable, or nil to clear (not with a table)
---@return boolean|number ok true, or with a table how many keys were applied; false when none were
---@return string|nil err
---@async
function whip_core:SetVehicleData(vehicleId, key, value) end

--- One value, or nil when this vehicle does not carry it. There is no
--- registered default here, unlike a stat — absent means absent, and the
--- caller decides what that means. With no key, everything it carries, as a plain copy ({} for none).
---@param vehicleId number|WhipVehicleRef
---@param key? string
---@return any value
function whip_core:GetVehicleData(vehicleId, key) end

--- Remove one value — only a key your resource wrote. True when the key is absent afterwards,
--- including when it was never there.
---@param vehicleId number|WhipVehicleRef
---@param key string
---@return boolean ok
---@return string|nil err
---@async
function whip_core:ClearVehicleData(vehicleId, key) end

--- Remove every key YOUR resource put on this vehicle. For an uninstall that removes a whole kit in
--- one go; other resources' keys on the same car are left alone. One dataChanged per key removed.
---@param vehicleId number|WhipVehicleRef
---@return boolean ok
---@return string|nil err
---@async
function whip_core:ClearAllVehicleData(vehicleId) end

-- ============================================
-- Vehicle appearance
-- ============================================
--
-- TWO WORDS, TWO MEANINGS, AND THE DIFFERENCE IS REAL.
--
--   PROPERTIES — the raw GTA block, applied to an ENTITY. Client-side only, because paint and mods
--                are client natives. GetVehicleProperties / SetVehicleProperties.
--   APPEARANCE — what whip has STORED for a vehicle, keyed by vehicleId. Server-side authority.
--
-- A shop changes the appearance. The entity's properties are how that becomes visible.

--- Change how a vehicle looks, and store it. THE CALL A CUSTOMISATION SHOP MAKES.
---
--- MERGED over what the vehicle already carries, one level deep into `mods` as well — so changing
--- the colour does not restate every mod, and setting mod 11 does not drop mod 23.
---
--- An INSTRUCTION, not a report. A client saying what a car looks like is believed about paint and
--- bodywork only; this is server-side, from code you wrote, so it is trusted for performance mods
--- too. `plate` and `model` can never be written this way whatever is passed.
---
--- FALSE MEANS NOT SAVED, AND NOT SHOWN: the car goes back to its old look. A shop should refund
--- rather than treat it as sold.
---
--- A SESSION car (GetVehicle(id).session: a street car whip adopted, a rental) has no row: the look
--- lasts as long as the car does. A seller can tell the buyer.
---
--- `opts.data` / `opts.clearData`: VehicleData keys (your resource's) set and removed IN THE SAME WRITE
--- as the look, checked as SetVehicleData checks a table of them — parts and the data that goes with them land
--- together, with the payment, or not at all. False: none of it changed.
---@param vehicleId number|WhipVehicleRef
---@param props table  appearance fields to apply over the current ones ({} for none)
---@param opts { data?: table<string, any>, clearData?: string[] }|nil
---@return boolean ok, string|nil err  why it failed
---@async
function whip_core:SetVehicleAppearance(vehicleId, props, opts) end

--- Push the stored appearance back onto the car, for every player who can see it.
---
--- THE UNDO FOR ANYTHING A CLIENT DID LOCALLY. Vehicle mods replicate: a client with network
--- control that calls SetVehicleMod changes the car for everyone, and none of that touches the
--- server. That is what makes a live preview look right to bystanders — and why an abandoned
--- preview leaves a car wearing parts nobody paid for until this is called.
---@param vehicleId number|WhipVehicleRef
---@return boolean ok, string|nil err
function whip_core:RestoreVehicleAppearance(vehicleId) end

-- ============================================
-- Garages
-- ============================================

--- One garage, by key.
---@param key string
---@return table|nil  a COPY — editing it changes nothing
function whip_core:GetGarage(key) end

--- Every garage whip knows about, keyed by garage key. All copies.
---@return table
function whip_core:GetGarages() end

--- The garage closest to a point.
---
--- The call a satellite actually wants: "which garage is this player standing at" is the question
--- an impound, a rental or a job garage asks, and answering it from GetGarages() means every one of
--- them writes the same distance loop slightly differently.
---
--- A garage's distance is to the nearest of its marker or its parking bays. With `maxRange`,
--- nothing further away counts — so "is this player AT a garage" is one call. (coords, maxRange) works too.
---@param x number|vector3  or a vector3, then y is maxRange
---@param y number|nil
---@param z number|nil
---@param maxRange number|nil
---@return string|nil key, number|nil distance
function whip_core:GetNearestGarage(x, y, z, maxRange) end

--- The vehicles currently stored in one garage, as full GetVehicle snapshots.
---@param key string
---@return WhipVehicleContext[]
function whip_core:GetGarageVehicles(key) end

--- Create a garage.
---@param data table  { key, name?, x?, y?, z?, heading?, spawnX?, spawnY?, spawnZ?, spawnHeading?, blipSprite?, blipColor? }
---@return table|false garage, string|nil err
---@async
function whip_core:CreateGarage(data) end

--- Change a garage. Absent fields are left alone. Refused for one another running resource made.
---@param key string
---@param data table
---@return boolean ok, string|nil err
---@async
function whip_core:UpdateGarage(key, data) end

--- Delete a garage. Vehicles stored in it move to the nearest other garage and their owners are
--- told; they are not deleted. Refused for one another running resource made.
---@param key string
---@return boolean ok, string|nil err
---@async
function whip_core:DeleteGarage(key) end

--- May this person use this garage? Always true for a public one. A PRIVATE garage — a
--- property's, keyed 'property:<id>' — is for its owner and keyholders only: its bays are hidden
--- from everyone else, it has no blip, and GetNearestGarage never returns it.
---
---     if exports.whip_core:CanUseGarage(key, source) then ... end
---@param key string
---@param who WhipPersonRef source, or { charId = n }
---@return boolean ok
---@return string|nil why  'No such garage', 'That garage belongs to ...', ...
function whip_core:CanUseGarage(key, who) end

--- Move a vehicle to a different garage without taking it out of storage.
---
--- NOT DespawnVehicle with a garage, which refuses anything that is not currently `out`. This is the one that moves
--- a car that is already put away — an impound releasing to a home garage, a dealership delivering
--- to the buyer's garage of choice.
---@param vehicleId number|WhipVehicleRef
---@param garageKey string
---@return boolean ok, string|nil err
---@async
function whip_core:SetVehicleGarage(vehicleId, garageKey) end

-- A car's net id and full context are GetVehicle — see the top of this section.
--
--   exports.whip_core:GetVehicle(id).netId
--   exports.whip_core:GetVehicle(id)
--   exports.whip_core:GetVehicle({ entity = entity })
--
-- Two things worth knowing about what comes back. `occupants` is opt-in, and PLAYERS ONLY when you
-- ask for it: ambient peds are created by clients and never reach the server, so an empty list does
-- not mean an empty car — `occupantsPlayersOnly` says so. And storage is reported only when the
-- vehicle's inventory is ALREADY loaded, because asking otherwise would pull it into memory that
-- nothing would release; `storageLoaded` says which you got.

-- ============================================
-- Vehicle Stats
-- ============================================

--- Register a stat that every vehicle carries.
---
--- Give it a `hud` block and a gauge appears in the vehicle panel AND a meter on the
--- vehicle's garage card, with no further wiring. The stat is saved with the vehicle and
--- replicated to every client that has it streamed in, so a passenger — or somebody
--- standing next to it — sees it change live.
---
--- Give it a `consume` block and the framework also owns the whole burn-down protocol:
--- it declares the report event, checks the reporter is the driver, caps every report
--- against the wall clock, and takes the stat off the vehicle when it bottoms out. The
--- client then only ever calls ConsumeVehicleStat. There is no event to write and no
--- anti-cheat to get wrong.
---
--- ```lua
--- exports.whip_core:RegisterVehicleStat('nitro', {
---     default = 0, min = 0, max = 100, persist = true,
---     consume = { maxRate = 5.0, driverOnly = true, clearAtMin = true, interval = 0.5 },
---     hud    = { label = 'Nitrous', color = '#60a5fa', showAboveZero = true },
--- })
--- ```
---
--- The registration belongs to the calling resource and is dropped when that resource stops.
--- VALUES ARE NOT DROPPED WITH IT — restarting your resource does not delete what players
--- have fitted to their cars. Use PurgeVehicleStat when you genuinely mean to retire one.
---
--- Names whip_core owns — `engine` and the damage stats — cannot be taken. (`fuel` is whip_fuel's.)
---
--- REGISTER BEFORE YOU WRITE: SetVehicleStat, SetVehicleStats and AddVehicleStat refuse a name nobody
--- registered, so a typo cannot become a stat saved on the car forever.
---@param name string
---@param config WhipVehicleStatConfig
---@return boolean ok
---@return string|nil err
function whip_core:RegisterVehicleStat(name, config) end

--- Read one stat. Returns the stat's default if it has never been set, or nil if the vehicle or
--- the stat is unknown.
---@param vehicleId number|WhipVehicleRef
---@param name string
---@return number|nil
function whip_core:GetVehicleStat(vehicleId, name) end

--- Every registered stat on a vehicle, defaults filled in. With `{ stored = true }`, every stat it actually
--- CARRIES, with no defaults filled in.
---
--- The difference is the whole of how "fitted" works: an absent key means no value stored, and a filled-in
--- default would read as "fitted and empty". A car with no nitrous and a car with a spent bottle both report 0
--- from GetVehicleStat; only one of them appears in the stored stats.
---@param vehicleId number|WhipVehicleRef
---@param opts? { stored?: boolean }
---@return table|nil stats { [name] = value }; with stored, {} for an unknown vehicle
function whip_core:GetVehicleStats(vehicleId, opts) end

--- Set a stat. Clamped to the range it was registered with, saved, and replicated.
--- Refused, with a reason, for an unknown car, a value that is not a number, or a stat nobody
--- registered.
---@param vehicleId number|WhipVehicleRef
---@param name string
---@param value number
---@param changeSource string|nil  a label for the change event, e.g. 'refuel:pump'
---@return boolean ok
---@return string|nil err
function whip_core:SetVehicleStat(vehicleId, name, value, changeSource) end

--- Write several stats to one vehicle in a single replication. Worth reaching
--- for whenever more than two stats are set together — fitting a kit, applying
--- a tune, resetting a car. Takes the VALUES, not a callback, so one table
--- crosses the resource boundary once.
---@param vehicleId number|WhipVehicleRef
---@param values table<string, number>  [statName] = value; unregistered names and non-numbers are skipped
---@param changeSource string|nil
---@return number|false written  how many actually took; false when none did
---@return string|nil err  why, only with false
function whip_core:SetVehicleStats(vehicleId, values, changeSource) end

--- Take a stat off ONE vehicle, leaving it registered for every other.
---
--- Not the same as setting it to zero, and not the same as unregistering it. A stat is DEFINED for
--- every vehicle and PRESENT on the ones that have a value — so this is what "uninstall" means for
--- anything fitted to a car: a nitrous bottle, a tuning chip, a tow hook.
---
--- Afterwards GetVehicleStat falls back to the stat's registered default, and the row stops
--- carrying a key for a thing this vehicle no longer has.
---
--- ```lua
--- if remaining <= 0 then
---     exports.whip_core:ClearVehicleStat(vehicleId, 'nitro')
--- end
--- ```
---@param vehicleId number|WhipVehicleRef
---@param name string
---@return boolean ok  true includes "already absent"
---@return string|nil err
function whip_core:ClearVehicleStat(vehicleId, name) end

--- Forget the damage whip keeps on a car (engine and body health, doors torn off, burst tyres), so
--- its next spawn comes out like new. Call it with a repair: it does not fix the car in the world,
--- which only the game running it can do (SetVehicleFixed and friends).
---
--- The damage itself is five stats, read with GetVehicleStat: `engineHealth` and `bodyHealth`
--- (0-1000, GTA's scale), and the masks `doorsOff`, `tyresFlat` and `tyresRim`.
---
--- ```lua
--- exports.whip_core:ClearVehicleDamage(vehicleId)
--- ```
---@param vehicle number|WhipVehicleRef
---@return boolean ok
---@return string|nil err
function whip_core:ClearVehicleDamage(vehicle) end

--- Is this car wrecked: blown up, or sunk? The game running the car says it sank (no server native shows
--- it). false for a car that is not out in the world.
---
--- ```lua
--- if exports.whip_core:IsVehicleWrecked(vehicleId) then return 'lost' end
--- ```
---@param vehicle number|WhipVehicleRef
---@return boolean
function whip_core:IsVehicleWrecked(vehicle) end

--- Does this vehicle actually CARRY this stat?
---
--- The question GetVehicleStat cannot answer, and the mirror of the client
--- export of the same name: reads resolve an absent stat to its registered
--- default, so `GetVehicleStat(id, name) > 0` is true for EVERY vehicle
--- whenever the default is above zero. This reads presence, not value.
---@param vehicleId number|WhipVehicleRef
---@param name string
---@return boolean
function whip_core:HasVehicleStat(vehicleId, name) end

--- Be told when ONE stat changes, on any vehicle, without being woken for the rest.
---
--- The server half of the client export of the same name, and how every server script hears a
--- vehicle stat move: any stat, whoever registered it. The callback's fourth argument differs by
--- side, deliberately: the server knows whether the stat was CLEARED, the client knows which ENTITY
--- it happened on. Listeners are dropped when the resource that registered them stops.
---
--- `'*'` (server only) hears every stat, once per stat that moved, with the name second:
--- `function(vehicleId, name, value, previous, cleared, source)`. Name the stats when you know them.
---
--- `{ table = true }` hands the callback one WhipVehicleChange table — the same names on both sides —
--- and `{ now = true }` also calls it once straight away for every car carrying the stat
--- (`source = 'now'`); `{ now = 'all' }` (a named stat) for every car whip has, its default included (a car with
--- only the default does not carry the stat). The options may go third, in place of `id`.
---@param name string Stat name to watch
---@param callback fun(vehicleId: number, value: number, previous: number|nil, cleared: boolean, source: string|nil)|fun(change: WhipVehicleChange)
---@param id? string|WhipVehicleListenOpts Registration key within your resource; registering the same id again replaces it
---@param opts? WhipVehicleListenOpts
---@return boolean registered
function whip_core:OnVehicleStatChanged(name, callback, id, opts) end

--- Delete a stat's values from EVERY vehicle, permanently.
---
--- For retiring a stat for good. This is NOT what stopping your resource does —
--- a restart leaves values alone, precisely so that developing a resource does
--- not destroy what players have fitted to their cars.
---
--- A stat another RUNNING resource has registered can only be purged by that resource; one with
--- no running owner (a retired stat) by anyone.
---@param name string
---@return number|false touched  how many vehicles carried a value, or false when refused
---@return string? reason
function whip_core:PurgeVehicleStat(name) end

--- Is this player in the DRIVER'S seat of this vehicle?
---
--- Three natives, no allocation, no player scan — the cheap way to ask the question
--- a hot path actually asks. GetVehicleContext returns it too, but it builds a whole
--- snapshot of the vehicle and walks every player on the server to do it, which is
--- the right shape for a panel and the wrong shape for something called twice a second.
---@param source number
---@param vehicleId number|WhipVehicleRef
---@return boolean
function whip_core:IsPlayerDrivingVehicle(source, vehicleId) end

--- Is this player anywhere inside this vehicle? Passengers included.
---
--- Say which you mean. This is the right check for "may they open the glovebox";
--- IsPlayerDrivingVehicle is the right one for "may they report fuel burn".
---@param source number
---@param vehicleId number|WhipVehicleRef
---@return boolean
function whip_core:IsPlayerInVehicle(source, vehicleId) end

--- Whose game drives this car now: the player in its driver's seat ('seat'), or the player's game a
--- recorded drive (a Director take) plays it on ('take'). nil for a car nobody drives (parked, an NPC
--- at the wheel), or no car. Ask it before taking a car to another game to pull or carry it (a rope, a
--- tow): a take's game takes its car back every two seconds, and the two would fight.
---@param vehicle number|WhipVehicleRef  a vehicleId, or { netId } | { entity } (any networked car) | { plate }
---@return number|nil source
---@return 'seat'|'take'|nil how
function whip_core:GetVehicleDriver(vehicle) end

--- Which whip car is this player sitting in? The server's view of them, never the client's word.
--- `{ driver = true }` wants the driver's seat; without it any seat will do.
---@param source number
---@param opts { driver?: boolean }|nil
---@return number|false vehicleId
---@return string|nil why  a sentence you can show the player (with false)
function whip_core:GetPlayerVehicle(source, opts) end

--- Which seat is this player in? The server's view, any vehicle (street cars too). `vehicleId` is
--- only there for a car whip looks after; `netId` always is. Seat changes are announced as
--- whip_core:vehicle:entered again, with the new seat.
---@param source number
---@return { seat: number, driver: boolean, vehicleId: number|nil, netId: number }|false at
---@return string|nil why  'Not in a vehicle', 'Not in a seat yet', ...
function whip_core:GetPlayerSeat(source) end

--- Add to a stat. Same clamping, persistence and refusals as SetVehicleStat.
---@param vehicleId number|WhipVehicleRef
---@param name string
---@param delta number
---@param changeSource string|nil
---@return boolean ok
---@return string|nil err
function whip_core:AddVehicleStat(vehicleId, name, delta, changeSource) end

-- ============================================
-- Vehicle Catalog & Images
-- ============================================

--- The whole vehicle catalog, as a copy: model -> { model, displayName, class, hasImage (boolean),
--- image (its URL for a NUI, or false), inGame (what VehicleModelExists returns) }. Filled from
--- server/vehicle_catalog_list.lua; a model has a picture when its img/vehicles/<model>.webp is in a media pack.
---@return table catalog
function whip_core:GetVehicleCatalog() end

--- Your car pack's cars in the catalog while your resource runs: named, classed and pictured wherever the catalog
--- is read (the dealership, the vehicle wizard, garages). The whole list each call: one left out goes. A model whip
--- already lists keeps its name and class and takes your picture. Waits for whip_core to finish starting.
---@param list { model: string, name?: string, class: string|integer, image?: string }[]  class: 'sports', 'suvs', ... or GetVehicleClass's number; image: 'img/x.webp' in your resource (in its files {}), or '@res/img/x.webp'
---@return boolean ok
---@return string|nil why
---@async
function whip_core:RegisterVehicles(list) end

--- URL for a vehicle's image, usable from any resource's NUI, or nil when the model has none (a lookup).
---@param model string Model name (case-insensitive)
---@return string|nil url
function whip_core:GetVehicleImage(model) end

--- Does this model have a picture?
---@param model string Model name (case-insensitive)
---@return boolean
function whip_core:HasVehicleImage(model) end

-- ============================================
-- Ground Items
-- ============================================

--- Create a ground item (3D world drop): CreateGroundItem({ item, amount, coords, metadata, heading, reason }).
--- The item must be registered and the amount a whole number (nil = 1). `reason` goes in the activity log.
---
--- Failure is `false, reason` and NOT `nil, reason`: a FiveM export truncates its return list at a
--- leading nil, so a nil first value would deliver the reason to nobody. `false` is still falsy,
--- so `if not created then` reads the same either way.
---@param def { item: string, amount?: number, coords: vector3|vector4, metadata?: table, heading?: number, reason?: string, createdBy?: number }  createdBy: the charId it is logged against
---@return WhipGroundItem|false created The created ground item, or false on failure
---@return string|nil error Error message if failed
---@async
function whip_core:CreateGroundItem(def) end

--- Delete a ground item by ID.
---@param id number Ground item ID
---@return boolean ok
---@return string|nil err  'Item not found', 'Database error'
---@async
function whip_core:DeleteGroundItem(id) end

--- Get all ground items within a radius of a point: (x, y, z, range) or (coords, range).
---@param x number|vector3 Center X, or the centre as a vector
---@param y? number Center Y (or the range, in the vector form)
---@param z? number Center Z
---@param range? number Search radius in meters (default 10)
---@return WhipGroundItem[]
function whip_core:GetGroundItemsNearby(x, y, z, range) end

--- One ground item by its id, or nil once it is gone.
---@param id number
---@return WhipGroundItem|nil
function whip_core:GetGroundItem(id) end

-- ============================================
-- Containers
-- ============================================

--- A container declared in code, by key — the EnsureShop / EnsureZone rule. New key: made. The same
--- declaration as last time: nothing changes (an admin's edits stand). A changed one: every declared
--- field applied, an `allowedItems` or `requirements` no longer declared cleared, fewer slots only
--- over empty ones. A key another running resource declared is refused. Owner/access are not
--- declared. `requirements` is who may open it, in a door's shape — any one of jobs (on duty, with
--- onDuty), charIds, items, ace; held on every move. Leave it out and anyone can open it:
---     requirements = { jobs = 'police', onDuty = true }
--- An action's `require` is taken instead when it names one rule, refused when it names more (any one vs all).
--- A field a container does not read is said in the console.
---@param key string Letters, digits, _ - . and :, at most 100 — e.g. 'pd:weapon_locker'
---@param data { x: number, y: number, z: number, heading?: number, name?: string, type?: string, slots?: integer, maxWeight?: number, prop?: string, locked?: boolean, allowedItems?: table, requirements?: WhipContainerRequirements, require?: table }
---@return WhipContainerDef|false container
---@return string|nil why
---@async
function whip_core:EnsureContainer(key, data) end

--- Create a persistent world container — a NEW one on every call. For a stash your resource always
--- has, EnsureContainer.
---
--- `persist = false` makes one that is never saved and is yours: gone when your resource stops or its
--- `tag` is released (ReleaseTag), its screens shut and its contents logged as lost. It takes `items`
--- (what it holds from the start: `{ { item, amount, metadata } }`, all or nothing), `prop = false`
--- (no prop, only its prompt) and `placed = true` with `rx` / `ry` (exactly there, no ground snap).
--- It has no `key`. A required item (`requirements.items`) never goes into the container it opens.
---@param data table Container data (name, slots, maxWeight, x, y, z, heading, prop, type, ownerCharId, accessCharId, locked, allowedItems, requirements — see EnsureContainer; persist, tag, items, placed, rx, ry)
---@return WhipContainerDef|false created  false on failure, never nil
---@return string|nil error
---@async
function whip_core:CreateContainer(data) end

--- Delete a container and everything in it. Refused while a shop sells from it. One made with
--- persist = false only by the resource that made it.
---@param containerId number Container ID
---@return boolean ok
---@return string|nil err
---@async
function whip_core:DeleteContainer(containerId) end

--- What a container IS — name, size, position, owner — by its id, or by its key (EnsureContainer's):
--- `GetContainer({ key = 'pd:weapon_locker' })`. nil when there is none. What it HOLDS is
--- StoreRead({ kind = 'container', id = containerId }).
---@param ref number|{ id: number }|{ key: string } A container id, or a reference
---@return WhipContainerDef|nil
function whip_core:GetContainer(ref) end

--- Change a container's definition after it has been created. Fields absent
--- from `data` are left alone — including `accessCharId`, which is what makes
--- a tradeable key, a transferred stash or a job handover expressible. Fewer
--- `slots` are refused while an item sits above the new count. `key` gives it a
--- key EnsureContainer finds it by (`false` takes it away); `requirements = false`
--- clears its job rule. Players who have it open are held to the change on their
--- next move.
---@param containerId number Container ID
---@param data { name?: string, type?: string, slots?: number, maxWeight?: number, ownerCharId?: number, accessCharId?: number, locked?: boolean, x?: number, y?: number, z?: number, heading?: number, prop?: string, allowedItems?: table, requirements?: WhipContainerRequirements|false, key?: string|false }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:UpdateContainer(containerId, data) end

-- To put a stash on a player's screen: OpenStore(source, { kind = 'container', id = containerId }),
-- and CloseStore to take it away (the Stores section).

-- ============================================
-- Stores
-- ============================================
--
-- The store model: every inventory surface — player pockets, containers, vehicle storage,
-- panels, shops — is a KIND, and every move goes through one mover with one set of rules.
-- Any store, and any one slot in it, is named by an ADDRESS: { kind, id, sub, slot } (WhipStoreAddr).

--- Define a new kind of store from outside whip_core, with whip's own
--- persistence and move validation behind it.
---
--- Required functions in kindDef: resolve, instanceId, slots, maxWeight, get,
--- set, clear. Optional: unitKey (defaults to instanceId), allows, allowsAt
--- (a per-slot filter), persist, durability, label, beforeMove, afterMove — and
--- `authorize(src, addr)`. Players can move items in and out of your kind while you have it open on
--- their screen (OpenStore); `authorize` is the other way in, for a kind that decides "has it open"
--- itself. Without either, only your resource moves things. `instanceId` must start with
--- "<kindId>:". Hooks get `ctx.other` as an address, not the store. Names are claimed
--- first-come and core's are reserved; a kind is cleaned up when its resource stops.
---@param kindId string Kind name
---@param kindDef table The kind definition
---@return boolean ok
---@return string|nil err
function whip_core:RegisterStoreKind(kindId, kindDef) end

--- Move a stack between any two stores, as ONE committed operation. Handles merge, partial merge
--- and swap.
---
--- It routes through Stores.commitMove, the same path a player's own drag takes: hooks, saving and
--- client sync included.
---
--- IT TAKES ADDRESSES, whip's own `{ kind, id, sub, slot }`, the same shape the client speaks:
---
---     exports.whip_core:StoreMove(
---         { kind = 'container', id = 12,     slot = 3 },
---         { kind = 'player',    id = source, sub = 'player', slot = 1 }
---     )
---
--- `shop` and `basket` are refused: they exist only relative to a player who has one open, so
--- there is no server-side address for them.
---@param fromAddr WhipStoreAddr Source address
---@param toAddr WhipStoreAddr Destination address — the slot may be left out: wherever it fits
---@param opts? { amount?: number, mode?: 'move'|'one'|'split', reason?: string } amount 0 or nil moves the whole slot; reason goes in the activity log
---@return boolean ok
---@return string|nil err
---@async
function whip_core:StoreMove(fromAddr, toAddr, opts) end

--- What is in any store. A copy; keyed by slot number. A slot in the address is ignored.
---@param addr WhipStoreAddr
---@return WhipStoreContents|false contents
---@return string|nil err
---@async
function whip_core:StoreRead(addr) end

--- How many of one item a store holds.
---@param addr WhipStoreAddr
---@param item string
---@return number|false count
---@return string|nil err
---@async
function whip_core:StoreCount(addr, item) end

--- Create an item in any store. With a slot in the address: exactly there (onto the same item if
--- it stacks) or refused. Without one: wherever it fits, across several slots if needed — all of it
--- or none. For a REWARD to a player, AddItem is still the call (it drops instead of refusing).
---@param addr WhipStoreAddr
---@param item string A registered item
---@param amount? number A whole number, 1 or more (default 1)
---@param metadata? table Leave out for a fresh generated metadata per slot
---@param opts? string|{ reason: string } A reason for the activity log, or a table carrying one
---@return number|false slot  the (first) slot it landed in
---@return string|nil err
---@async
function whip_core:StoreGive(addr, item, amount, metadata, opts) end

--- Take items out of any store, DESTROYING them. With a slot: from it (amount nil = the stack).
--- Without one: `opts.item` from wherever it is in the store, all or nothing. Taking is not moving —
--- to put it somewhere, StoreMove.
---@param addr WhipStoreAddr
---@param amount? number
---@param opts? { item?: string, reason?: string }|string  a plain string is the reason
---@return { item: string, amount: number, metadata: table|nil }|false taken
---@return string|nil err
---@async
function whip_core:StoreTake(addr, amount, opts) end

--- What is in ONE slot of any store: a copy, nil when the slot is empty, or false and a reason when
--- the address is wrong. Both nil and false are falsy, so `if not item then` reads the same.
---@param addr WhipStoreAddr  with a slot
---@return WhipInventorySlot|false|nil item
---@return string|nil err  only with false
---@async
function whip_core:GetItemAt(addr) end

--- Say which of a player's items is in their hand (the slot your resource drew it from), or nil when it is put
--- away. Yours alone; cleared when your resource stops, at logout and when they leave. whip_fuel's pump and car
--- doors act on the fuel can in hand (GetHeldItem).
---@param source number
---@param addr WhipStoreAddr|nil  one of that player's pocket slots
---@return boolean ok
---@return string|nil why
---@async
function whip_core:SetHeldItem(source, addr) end

--- What the player holds: what GetItemAt returns, plus `addr`, or nil (nothing held, or it left its slot).
---@param source number
---@return { addr: WhipStoreAddr, item: string, amount: number, metadata: table|nil }|nil
function whip_core:GetHeldItem(source) end

--- Change the metadata of the item at an address — pockets, a stash, a boot, a panel. MERGES: only
--- the keys passed change. The item's
--- `uid` is kept either way (pass `uid = false` to clear it). Anything json.encode cannot write is
--- refused before anything changes. True once the slot has changed, even if the save has to be retried.
---@param addr WhipStoreAddr  with a slot
---@param metadata table|nil The keys to change; nil only with replace (clears it all) or remove
---@param opts { replace?: boolean, remove?: string[], quiet?: boolean }|nil replace = the table becomes the whole metadata; remove = keys to take away; quiet (a player's pockets) saves without pushing the inventory to the client, for a value changed many times a second that the client learns about another way (gunny's round count)
---@return boolean ok
---@return string|nil err
---@async
function whip_core:SetItemMetadata(addr, metadata, opts) end

--- Where one specific item is, by its uid — searching what is LOADED (online players, stashes /
--- boots / panels in memory, the ground). `{ kind = 'ground', id }` for a ground item.
---@param uid string
---@return WhipStoreAddr|{ kind: 'ground', id: number }|nil
function whip_core:FindItemByUid(uid) end

--- Where an item whose metadata `key` holds `value` is (the first found: a gun's serial), in the same loaded places
--- as FindItemByUid.
---@param key string
---@param value any
---@return WhipStoreAddr|{ kind: 'ground', id: number }|nil
function whip_core:FindItemByMetadata(key, value) end

--- Block a player's hands from the server (jail, an arrest): sent to their game, kept here for AreHandsBlocked.
--- Gone at logout, a drop, or when your resource stops. opts as the client's: { label?, only? = 'weapons' }.
---@param source number|{ charId: number }
---@param id string
---@param opts {label?: string, only?: 'weapons'}|nil
---@return boolean ok
---@return string? reason
function whip_core:BlockHands(source, id, opts) end

---@param source number
---@param id string
---@return boolean ok
---@return string? reason
function whip_core:UnblockHands(source, id) end

--- The server's blocks on this player's hands, for `what` ('weapon', or nil for anything).
---@param source number
---@param what 'weapon'|nil
---@return boolean blocked
---@return string? label
function whip_core:AreHandsBlocked(source, what) end

--- Have the player's game empty their hands now (the client FreeHands moment).
---@param source number|{ charId: number }
---@return boolean ok
---@return string? reason
function whip_core:FreeHands(source) end

--- Every store this player has open, as addresses, in a stable order. Their own pockets are never
--- listed; a shop they are browsing is { kind = 'shop' }; a panel carries its `label` too (the way to
--- learn the id of a panel an item opened).
---@param source number
---@return WhipStoreAddr[]
function whip_core:GetOpenStores(source) end

--- Put a store on a player's screen, beside their pockets — a stash, a vehicle's boot, or one of
--- your own store kinds (shown in the same right-hand grid, and the player's moves in it count while
--- it is open). A player's pockets open with OpenPlayerInventory, a panel with OpenPanel; a glovebox
--- and ignition open from the seat. If the player already has a screen open, whip declines the open.
---@param source number
---@param addr WhipStoreAddr  { kind, id, sub } — a vehicle's `sub` must be 'trunk'
---@param opts? { skipDistance?: boolean, skipAccess?: boolean, coords?: vector3, range?: number, readOnly?: boolean } skipDistance: a stash; skipAccess: a stash's lock/owner, a boot's lock; coords/range/readOnly: your own kind
---@return boolean ok
---@return string|nil err
---@async
function whip_core:OpenStore(source, addr, opts) end

--- Take a store off a player's screen and away from them: they can move nothing in it after this.
--- Other players with it open are untouched. A panel closes with ClosePanel.
---@param source number
---@param addr WhipStoreAddr
---@return boolean ok
---@return string|nil err  'That is not open' ...
---@async
function whip_core:CloseStore(source, addr) end

-- ============================================
-- Shops
-- ============================================

--- One shop, by its id or by a reference that says what you hold, as GetVehicle takes one:
---
---     exports.whip_core:GetShop(4)
---     exports.whip_core:GetShop({ key = 'burgershot' })
---     exports.whip_core:GetShop({ containerId = 12 })   -- the shop whose stock that container is
---
--- A job's shops (a job can own several) are GetShops({ job = }).
---@param ref number|{ id: number }|{ key: string }|{ containerId: number } A shop id, or a reference
---@return WhipShopDef|nil
function whip_core:GetShop(ref) end

--- Every shop, sorted by shopId, or those of one job: `{ job = }` takes the job by jobId or key.
---@param filter? { job: number|string }
---@return WhipShopDef[] shops
---@return string|nil why 'No such job' (with an empty list)
function whip_core:GetShops(filter) end

--- A shop declared in code, by key — the EnsureZone rule. New key: made. The same declaration as
--- last time: nothing changes (an admin's panel edits stand). A changed declaration: every declared
--- field is applied, and a link the code stops declaring (jobId, containerId, npcModel, prop,
--- blipSprite) is cleared. A key another running resource declared is refused.
---@param key string Shop key
---@param data table { name, mode, x, y, z, heading, npcModel?, prop?, catalog?, jobId? (id or key), containerId?, blipSprite?, blipColor?, settings? }
---@return WhipShopDef|false shop
---@return string|nil error
---@async
function whip_core:EnsureShop(key, data) end

--- Create a new shop.
---@param data table Shop data (key, name, mode, x, y, z, heading, npcModel, prop, blipSprite, blipColor, jobId, catalog)
---@return WhipShopDef|false created
---@return string|nil error
---@async
function whip_core:CreateShop(data) end

--- Delete a shop. Refused for one another running resource made or declares.
---@param shopId number Shop ID
---@return boolean success
---@return string|nil err 'Shop not found' ...
---@async
function whip_core:DeleteShop(shopId) end

--- Update shop properties. Leave a field out to keep it; pass `false` for jobId, containerId,
--- npcModel, prop, blipSprite or key to clear it (no job, no stock container, no blip...). Refused for a shop
--- another running resource made or declares.
---@param shopId number Shop ID
---@param data table Fields to update
---@return boolean success
---@return string|nil err
---@async
function whip_core:UpdateShop(shopId, data) end

--- A shop's tabs and where its goods sit (the shop screen's Edit Shelf). Each layout entry replaces
--- that item's place; an item not mentioned keeps its own; leave `categories` out to keep the tabs.
---@param shopId number
---@param data { categories: string[]|nil, layout: table<string, { category: string|nil, order: integer|nil }>|nil }
---@return boolean success, string|nil err
---@async
function whip_core:SetShopLayout(shopId, data) end

--- Price an item on a stocked shop's shelf, or take it off sale (forSale false keeps the price). One
--- price per item: every shelf slot holding it sells at it.
---@param target number|{ shopId: number } The shop's stock container id, or the shop itself
---@param itemKey string A registered item
---@param price number Price (a negative price is set to 0)
---@param forSale boolean Whether the item is on the shopfront
---@return boolean success, string|nil err 'Unknown container' | 'Unknown item' | 'Invalid price' | 'Could not save that (database error)'
---@async
function whip_core:SetShopItemPrice(target, itemKey, price, forSale) end

--- Get the list of players currently viewing a shop.
---@param shopId number Shop ID
---@return number[] Array of source IDs
function whip_core:GetShopViewers(shopId) end

--- Get a shop's catalog (item definitions and prices).
---@param shopId number Shop ID
---@return table|nil catalog
function whip_core:GetShopCatalog(shopId) end

--- Add an item to a shop's catalog.
---@param shopId number Shop ID
---@param itemKey string Item key to add
---@param price number Item price
---@return boolean success
---@return string|nil error
---@async
function whip_core:AddCatalogItem(shopId, itemKey, price) end

--- Remove an item from a shop's catalog.
---@param shopId number Shop ID
---@param itemKey string Item key to remove
---@return boolean success
---@return string|nil error
---@async
function whip_core:RemoveCatalogItem(shopId, itemKey) end

--- Get a shop's current stock levels.
---@param shopId number Shop ID
---@return table|false stock  false on refusal, never nil
---@return string|nil error
---@async
function whip_core:GetShopStock(shopId) end

--- Get a stocked shop's price list, per item: `{ [itemKey] = { price, forSale } }`.
---@param shopId number Shop ID
---@return table<string, { price: number, forSale: boolean }>|false prices  false on refusal, never nil
---@return string|nil error
---@async
function whip_core:GetShopPrices(shopId) end

-- ============================================
-- Time & Weather
-- ============================================

--- Get the current server time.
---@return number hour Current hour (0-23)
---@return number minute Current minute (0-59)
function whip_core:GetTime() end

--- Get the current weather type.
---@return string weather Weather type string (e.g. 'CLEAR', 'RAIN')
function whip_core:GetWeather() end

--- Check if server time is frozen.
---@return boolean
function whip_core:IsTimeFrozen() end

--- Get the current time scale multiplier.
---@return number timeScale
function whip_core:GetTimeScale() end

--- Is the city blacked out (no lights)?
---@return boolean
function whip_core:IsBlackout() end

--- Set the server time. Out-of-range values wrap (25:61 is 02:01); a hour or minute that is not a
--- number is refused rather than thrown on.
---@param h number Hour (0-23)
---@param m number|nil Minute (0-59), default 0
---@return boolean ok
---@return string|nil reason
function whip_core:SetTime(h, m) end

--- Set the server weather.
---@param w string Weather type (e.g. 'CLEAR', 'RAIN', 'THUNDER'), any case
---@return boolean ok
---@return string|nil reason 'Invalid weather type', or not a string
function whip_core:SetWeather(w) end

--- Freeze or unfreeze server time.
---@param f boolean True to freeze
---@return boolean ok
function whip_core:SetTimeFrozen(f) end

--- Enable or disable blackout (no lights).
---@param b boolean True to enable blackout
---@return boolean ok
function whip_core:SetBlackout(b) end

--- Set the time speed multiplier (held to 0-10). Not a number: refused, not read as 1.0.
---@param s number Time scale (1.0 = normal)
---@return boolean ok
---@return string|nil reason
function whip_core:SetTimeScale(s) end

--- Push a named time/weather layer onto one player. Several can be active at
--- once and each clears independently, so a mission storm ending restores the
--- zone fog underneath it. Resolution is per field: a layer that sets only
--- `weather` leaves the time to whatever is below it. For anything the CLIENT
--- already knows about, use the client export of the same name and skip the
--- round trip.
---
--- The layer is YOURS: it comes off every player when your resource stops, and another running
--- resource cannot replace or clear it. What it carries is checked (a weather that does not exist,
--- an hour that is not a number: refused) and only those six fields reach the player.
---@param src number Player server ID
---@param name string Unique per source, e.g. 'mission:heist' (at most 64 characters)
---@param opts table|nil { priority?: number, hour?: number, minute?: number, weather?: string, frozen?: boolean, blackout?: boolean }; nil clears
---@return boolean ok
---@return string|nil reason
function whip_core:SetPlayerWeatherLayer(src, name, opts) end

--- Clear one named layer off a player (one of yours).
---@param src number Player server ID
---@param name string Layer name
---@return boolean ok
---@return string|nil reason
function whip_core:ClearPlayerWeatherLayer(src, name) end

--- The layers the SERVER believes this player is carrying. The client is the
--- authority on what is actually applied — it also holds layers it set for itself.
---@param src number Player server ID
---@return table<string, table> layers Keyed by layer name
function whip_core:GetPlayerWeatherLayers(src) end

-- ============================================
-- Zones (Server)
-- ============================================

-- Every lookup takes a saved zone's KEY as well as its id: a saved zone's id is 'dbzone_<n>', which
-- no resource can know, so ask for it by the key it was made with.
--
-- SERVER ENTER/EXIT EVENTS. A zone registered or ensured with `trackPlayers = true` is swept
-- every Config.ZoneTrackInterval ms (1000) and fires local server events:
--     AddEventHandler('whip_core:zone:entered', function(e) end)  -- { zoneId, key?, source }
--     AddEventHandler('whip_core:zone:exited',  function(e) end)  -- { zoneId, key?, source, dropped?, removed? }

--- Register a zone on the server (for server-side point checks). The id is yours once registered:
--- another resource's is refused, and your zones go when your resource stops. The shape is checked
--- (a sphere needs pos and radius, a box pos and size, a poly 3+ points) and refused with what was
--- wrong. `tag` files it under your run tag: ReleaseTag removes it, after the rest of the run.
---@param id string Zone ID
---@param data table Zone data (type, pos, size, heading, radius, points, minZ, maxZ, group, label, trackPlayers, tag)
---@return boolean ok
---@return string? reason
function whip_core:RegisterZone(id, data) end

--- Remove one of YOUR server-side zones.
---@param id string Zone ID
---@return boolean ok
---@return string? reason not registered, or registered by another resource
function whip_core:RemoveZone(id) end

--- Check if a point is inside a zone (server zone or saved zone, by id or key). A client-made zone
--- counts as its players report it; `trusted = true` reads only the server's own zones
--- (saved, or RegisterZone) — the one to use for anti-cheat.
---@param id string Zone id, or a saved zone's key
---@param point vector3 Point to test
---@param trusted boolean|nil
---@return boolean
function whip_core:IsPointInZone(id, point, trusted) end

--- Get all player source IDs currently inside a zone.
---@param id string Zone id, or a saved zone's key
---@return number[] Array of player source IDs
function whip_core:GetPlayersInZone(id) end

--- The vehicles inside a zone. `vehicleId` is nil for a car whip does not track (an ambient one).
---@param id string Zone id, or a saved zone's key
---@return { vehicleId: number|nil, entity: number }[]
function whip_core:GetVehiclesInZone(id) end

--- Get all registered server-side zones.
---@return table[]
function whip_core:GetZones() end

--- Get a specific zone definition.
---@param id string Zone id, or a saved zone's key
---@return table|nil
function whip_core:GetZone(id) end

--- A saved zone, declared by a key you choose: made the first time, and brought up to date when
--- your declaration CHANGES. The same declaration again writes nothing, so an admin's edits in the
--- zone editor stand until you change yours. A key another running resource declared is refused.
---@param key string Letters, digits, _ - . and :, at most 60
---@param data table { type = 'box'|'sphere'|'poly', pos, size (box), heading, radius (sphere), points (poly), minZ, maxZ, label, group, priority, rules, notify, trackVehicles, trackPlayers }
---@return table|false zone
---@return string|nil reason
---@async
function whip_core:EnsureZone(key, data) end

--- A table of your resource's own, built the way whip_core builds its own: `createSql` (one CREATE TABLE IF NOT
--- EXISTS, the table complete) on a database without it, then `migrations` (the changes since, append only), each
--- run once per database and recorded as '<resource>:<id>'. Each statement says what it is about and is skipped
--- when that is there: { sql = 'ALTER TABLE ...', unless = { column = { 'mycafe_orders', 'note' } } } (or onlyIf, or
--- a `run` function). Waits for whip_core to finish starting, as every Ensure* does.
---@param name string
---@param createSql string
---@param migrations { id: string, statements?: (string|{ sql: string, unless?: table, onlyIf?: table })[], run?: fun(): boolean? }[]|nil
---@return boolean ok
---@return string|nil why
---@async
function whip_core:EnsureTable(name, createSql, migrations) end

--- Your own queries in ONE transaction with what the player's current action has changed and whip has not yet
--- written: the item you took and the row you wrote for it land together or not at all. Outside an action, the
--- queries alone. opts.source / opts.vehicleId: whose action, when your code runs outside the handler.
---@param queries { query: string, values?: any[] }[]
---@param opts { source?: number, vehicleId?: number }|nil
---@return boolean ok
---@return string|nil why
---@async
function whip_core:CommitWithAction(queries, opts) end

--- An item for a person: now if they are playing, else kept in the database and handed over at their next login
--- (at their feet when their pockets are full). `who`: a server id or { charId = n }.
---@param who number|{ charId: integer }
---@param item string
---@param amount integer|nil  default 1
---@param metadata table|nil
---@param opts? string|{ reason?: string }  the reason, for the item log
---@return 'now'|'login'|false given
---@return string|nil why
---@async
function whip_core:GiveOnLogin(who, item, amount, metadata, opts) end

--- Delete a saved zone by key or id. Not one another running resource declares (it would be made
--- again), and not a server zone (RemoveZone removes your own).
---@param keyOrId string
---@return boolean ok
---@return string|nil reason
---@async
function whip_core:DeleteZone(keyOrId) end

-- ============================================
-- Doors
-- ============================================

--- Who may open a door. ANY-OF: one match opens it. Empty or nil: anyone.
---@class WhipDoorRequirements
---@field jobs string[]|nil      job keys — has a role there (employed or owner), on duty or not...
---@field onDuty boolean|nil     ...unless this is true: then on duty at that job too
---@field charIds number[]|nil   these characters
---@field items { key: string }[]|nil  carrying one of these
---@field ace string|nil         holding this ACE
---@field lockpick boolean|nil   a locked door offers a lockpick attempt

---@class WhipDoorDef
---@field doorId number
---@field label string
---@field folder string|nil
---@field model number         signed, as GetEntityModel returns it
---@field x number
---@field y number
---@field z number
---@field heading number
---@field locked boolean       every door starts locked on every server start
---@field autolock boolean
---@field autolockDelay number seconds
---@field linkedDoorId number|nil
---@field requirements WhipDoorRequirements|nil
---@field metadata table|nil   `managedBy` = { system, id, key, label, created|adopted } for a managed door

--- One door of a resource's declared set (EnsureDoors).
---@class WhipDeclaredDoor
---@field key string        yours, the same between runs: letters, digits, _ - . and :, at most 60
---@field model string|number
---@field coords vector3|vector4|table  a vector4's w is the heading (or give x, y, z instead)
---@field heading number|nil
---@field label string|nil  default the key
---@field folder string|nil
---@field requirements WhipDoorRequirements|nil
---@field autolock boolean|nil
---@field autolockDelay number|nil
---@field link string|nil   the key of the door it is paired with
---@field require table|nil  an action's `require`, taken as requirements when it names one rule (refused with more)

--- Declare your doors: the list is your WHOLE set, each door named by a key. A new key makes
--- its door (or adopts the one already on that spot); a known key's label, folder, requirements,
--- autolock and link follow the list; a key that left the list is released (deleted if the list
--- made it, put back if it was adopted). Checked whole first: one bad entry and nothing is written.
--- Declared doors are managed — the Door Manager cannot change their access — and stay when your
--- resource stops. Waits (up to a minute) for whip's doors to load.
---@param list WhipDeclaredDoor[]
---@param opts { id?: string, label?: string, prune?: boolean }|nil  id: several sets per resource (default 'doors'); label: the Door Manager's name for them; prune = false keeps doors a key left
---@return { doors: table<string, number>, failed: table<string, string>, released: number }|false result
---@return string|nil reason
---@async
function whip_core:EnsureDoors(list, opts) end

--- One declared door, by key: EnsureDoors for a single door, never releasing any. Its own set
--- ('door:<key>') unless opts.id names one, so EnsureDoors neither prunes it nor is undone by it.
--- A linked pair is declared with EnsureDoors.
---@param key string
---@param data WhipDeclaredDoor  (its key is `key`)
---@param opts { id?: string, label?: string }|nil  id defaults to 'door:<key>'
---@return WhipDoorDef|false door
---@return string|nil reason
---@async
function whip_core:EnsureDoor(key, data, opts) end

--- Get a door definition by ID.
---@param doorId number Door ID
---@return WhipDoorDef|nil
function whip_core:GetDoor(doorId) end

--- Find a door near a world position. (coords, range) works too.
---@param x number|vector3 World X, or a vector3 (then y is the range)
---@param y? number World Y
---@param z? number World Z
---@param range? number Search radius (default: uses internal default)
---@return WhipDoorDef|nil
function whip_core:GetDoorByPosition(x, y, z, range) end

--- Get all registered doors.
---@return WhipDoorDef[]
function whip_core:GetDoors() end

--- Create a new door. Always created LOCKED — `data.locked` is not consulted.
---
--- `model` is stored SIGNED, the way GetEntityModel returns it: an unsigned number (as map packs
--- write them) or a model name is converted.
---@param data table Door data (model, x, y, z, heading, label, folder, requirements, metadata)
---@return WhipDoorDef|false created  false on failure, never nil
---@return string|nil error
---@return number|nil existingDoorId  the door already within half a metre, when that is why
---@async
function whip_core:CreateDoor(data) end

--- Which of your door sets a door belongs to, for UpdateDoor, DeleteDoor, LinkDoors and UnlinkDoors. A door you
--- declared is in the set you declared it in: `{ id = 'doors' }` for EnsureDoors with no `opts.id`, `{ id = opts.id }`
--- with one, and `{ id = 'door:<key>' }` for one from EnsureDoor.
---@class WhipDoorManager
---@field id any          the set: 'doors', your EnsureDoors opts.id, or 'door:<key>' (EnsureDoor)
---@field key? string     the door's name within it ('entrance', 'garage')
---@field label? string   what the Door Manager shows ("Business #4 · Bean Machine")

--- Hold a door while you need it (a heist's vault): the door at the spot, saved or not (a temporary
--- one, never saved, where there is none). In memory only. Nobody may press it until you say who; it
--- never relocks by itself; it goes back to the lock it had when released, its tag released, or you
--- stop. Lockpicking stays as its row says. A property's or another manager's door is refused.
---@param data { model: number|string, x: number, y: number, z: number, heading?: number, label?: string }
---@param opts? { tag?: string, requirements?: table }
---@return number|false doorId
---@return string howOrWhy 'held' | 'made' | 'already', or why not
---@async
function whip_core:HoldDoor(data, opts) end

--- Who may press a door you hold, in a door's requirements shape. nil = nobody, {} = anyone.
---@param doorId number
---@param requirements? table
---@return boolean ok
---@return string|nil why
function whip_core:SetHeldDoorAccess(doorId, requirements) end

--- Give a door you hold back now, the pair of HoldDoor (its old lock; a temporary one is gone).
---@param doorId number
---@return boolean ok
---@return string|nil why
function whip_core:ReleaseDoor(doorId) end

--- Who holds a door, or nil.
---@param doorId number
---@return { owner: string, tag: string|nil, doorId: number, made: boolean }|nil
function whip_core:GetDoorHold(doorId) end

--- The doors the calling resource manages: all of them, or one thing's.
---@param id? any  a manager id, or nil for all
---@return WhipDoorDef[]
function whip_core:GetManagedDoors(id) end

--- Update a door's properties. The row is written first; the change is only adopted in memory
--- once the write commits, so a false return means nothing moved on either side.
---
--- `{ requirements = nil }` does NOT clear requirements — in Lua that is an empty table and the
--- key is never seen. Pass `{}`, which the authorization check reads as "no requirements".
---
--- Updatable fields: label, folder, locked, autolock, autolockDelay, linkedDoorId, requirements,
--- metadata. `locked` takes the lock path, as SetDoorLocked does: the linked twin moves too and the
--- players at the door are told. (`defaultLocked` is refused: every door starts locked on every
--- server start.) Anything else is refused with an error rather
--- than written to memory and silently lost — a door's position, model and heading are fixed at
--- creation. To remove a link, UnlinkDoors.
---
--- A managed door's requirements, linkedDoorId, autolock, autolockDelay and metadata are refused
--- unless `manager` is the one holding it (a door you declared with EnsureDoors). Label and folder are open.
---@param doorId number Door ID
---@param updates table Fields to update
---@param manager? WhipDoorManager  yours, when you manage this door
---@return boolean success
---@return string|nil error
---@async
function whip_core:UpdateDoor(doorId, updates, manager) end

--- Delete a door. Unlinking any door paired with it happens in the same transaction, so this
--- either removes the door and clears its pairings or changes nothing. A managed door is deleted
--- only by its manager.
---@param doorId number Door ID
---@param manager? WhipDoorManager  yours, when you manage this door
---@return boolean success
---@return string|nil error
---@async
function whip_core:DeleteDoor(doorId, manager) end

--- Set a door's lock state (also syncs linked doors).
---@param doorId number Door ID
---@param locked boolean True to lock, false to unlock
---@return boolean success
---@return string|nil error
function whip_core:SetDoorLocked(doorId, locked) end

--- Check if a door is locked.
---@param doorId number Door ID
---@return boolean|nil locked  nil for a door that does not exist
function whip_core:IsDoorLocked(doorId) end

--- May this player open this door? The reason is the one the player is shown.
---@param source number Player server ID
---@param doorId number Door ID
---@return boolean authorized
---@return string|nil reason  'Door not found', 'Requires job: police (on duty)', ...
function whip_core:CanUseDoor(source, doorId) end

--- Link two doors together (locking one locks the other). Both halves are written in one
--- transaction, so a failure leaves neither linked rather than a one-way pairing.
--- Refuses to link a door to itself, or to change the link of a door another manager holds.
---@param doorId1 number First door ID
---@param doorId2 number Second door ID
---@param manager? WhipDoorManager  yours, when you manage these doors
---@return boolean success
---@return string|nil error
---@async
function whip_core:LinkDoors(doorId1, doorId2, manager) end

--- Undo a door's link — both halves, in one write. True for a door that was not linked. A managed
--- door's link is its manager's.
---@param doorId number Door ID
---@param manager? WhipDoorManager  yours, when you manage this door
---@return boolean success
---@return string|nil error
---@async
function whip_core:UnlinkDoors(doorId, manager) end

--- Get all doors within a radius of a point: `(x, y, z, range)` or `(coords, range)` — the
--- same shapes the client export takes.
---
--- Measured FLAT — `z` is accepted but not used, so every floor of a stairwell comes back
--- together. Use GetDoorByPosition when height matters. Without a point, `{}, why`.
---@param x number|vector3 Center X, or the center as a vector3 (then the next argument is the range)
---@param y? number Center Y
---@param z? number Center Z (accepted for symmetry; not used in the distance test)
---@param range? number Search radius in meters (default: 25)
---@return WhipDoorDef[]
---@return string? why
function whip_core:GetDoorsNearby(x, y, z, range) end

-- ============================================
-- Universal Panels
-- ============================================

---@class PanelConfig
---@field id string|number Unique panel identifier — its address is { kind = 'panel', id = id }
---@field label? string Header text (default: 'Panel')
---@field slots? number Number of slots (default: 10)
---@field items? table<number, PanelSlotData> Initial items
---@field maxWeight? number Weight limit (nil = unlimited)
---@field allowedItems? string[]|table<string, any> Only these items: a list of names, or keyed by name
---@field readOnly? boolean Block moves to/from panel
---@field onValidate? fun(ctx: WhipPanelHookCtx): boolean|nil, string|nil Before a player's move; return false, 'why' to refuse
---@field onChange? fun(ctx: WhipPanelHookCtx) After a player's move landed; ctx.items is what it holds now
---@field onClose? fun(ctx: { panel: string|number, source: number, items: table<number, PanelSlotData> }) When the last viewer has left

---@class PanelSlotData
---@field item string Item key
---@field amount number Quantity
---@field metadata? table Item metadata

--- Open a panel — an extra grid beside the player's inventory that your resource owns: a workbench,
--- a trade window, a mailbox. Its hooks (onValidate / onChange / onClose) are the PANEL's, set by the
--- first OpenPanel for that id that brings any, and asked for every viewer's moves. Your own
--- StoreGive / StoreTake into it (address { kind = 'panel', id = id }) are not asked. The same id
--- opened twice by one player is a no-op.
---@param source number Player server ID
---@param config PanelConfig Panel configuration
---@return boolean ok
---@return string|nil err
function whip_core:OpenPanel(source, config) end

--- Close a panel for a player. Omitting `panelId` closes EVERY panel they hold.
---@param source number Player server ID
---@param panelId string|number|nil Which panel; nil closes all of this player's panels
---@return boolean ok
---@return string|nil err  'No such panel open'
---@async
function whip_core:ClosePanel(source, panelId) end

--- Register an item whose context action opens a panel of its contents — a wallet, a bag, a gun's
--- magazine. The contents live in the item's metadata (meta[storageKey], or your read / write), so
--- they travel with it.
---
--- config:
---   slots, label (string or function(host)), storageKey (default 'slots'), action (default the
---   item's defaultAction), allowedItems (a list of names, or keyed by name)
---   canOpen(host) -> ok, why       may it open at all?
---   read(host) -> items            what the panel shows
---   write(host, items) -> meta     how a change folds back into the item
---   onValidate(ctx) -> ok, why     before a player's move — the same one-table hook OpenPanel has;
---                                  the item is ctx.host
---   onChange(ctx)                  after it landed; ctx.host (read after the fold), ctx.items
--- `host` is { source, container, slot, addr, item, amount, metadata } — `container` is the pocket,
--- `addr` the item's whip address (for GetItemAt, SetItemMetadata, StoreTake).
---@param itemKey string Item key
---@param config table
---@return boolean ok
---@return string|nil err
function whip_core:RegisterPanelItem(itemKey, config) end

-- ============================================
-- Player Inventory Inspection
-- ============================================

--- Open another player's inventory for inspection/editing (an admin tool, a robbery).
---
--- Returns `false, 'why'` and shows nothing itself: tell the admin if you want to.
--- Held to the target by default: the viewer must stay within `opts.range` metres (5) of an online
--- target, and the session closes itself when they leave it, the target goes, or after five
--- minutes. `{ range = false }` is no limit, for an admin tool.
---@param source number Viewer's player server ID
---@param target WhipPersonRef Whose pockets: source, or { charId = n } (offline too)
---@param opts { range: number|false|nil }|nil
---@return boolean success
---@return string|nil why  'You already have a player inventory open', 'Character not found', 'They are too far away', ...
---@async
function whip_core:OpenPlayerInventory(source, target, opts) end

--- Close a player inventory inspection session.
---@param source number Viewer's player server ID
---@return boolean success
---@return string|nil why
---@async
function whip_core:ClosePlayerInventory(source) end

--- Check if a character's inventory is currently being inspected by anyone (an admin, a robbery).
---@param charId number Character ID to check
---@return boolean
function whip_core:IsCharacterBeingInspected(charId) end

-- ============================================
-- Skill Check
-- ============================================

--- Run a skill check on a player's screen, server-side, and get a result the
--- server can act on. Blocks until the client answers or the check times out.
--- An answer that arrives faster than a human could play resolves as failure;
--- a cheater who waits the honest time can still lie, so do not gate anything
--- that must be uncheatable on a minigame.
---
--- `opts.game`: another resource's game instead of the ring (GetSkillCheckGames names them; `difficulty` is then one
--- of that game's levels). One the player cannot start (whip_phone's: no phone) shows nothing, tells them why
--- (`opts.quiet`: not told), and returns false, 'not started': never a fail.
---@param source number Player server ID
---@param difficulty? WhipSkillDifficulty|string|{ difficulty?: WhipSkillDifficulty|string, game?: string, level?: WhipSkillLevel } Default 'medium'; `{ level }`: the ring with your own numbers, timed from them
---@param opts? { timeoutMs?: number, minMs?: number, tag?: string, game?: string, quiet?: boolean }  timeout default: the check's clock + 2 s (run medium/hard from an event, not a callback); minMs must be shorter than the timeout, or the call is refused; `tag` (your run tag): ReleaseTag(tag) ends the check at once ('cancelled') and takes it off their screen, and a released tag is refused ('run ended')
---@return boolean passed
---@return string|nil why  only with false: 'failed' | 'busy' | 'cancelled' | 'timeout' | 'too fast' | 'dead' (down: not shown one, or passed from the floor) | 'run ended' | 'Player not loaded' | 'not started' (a game they could not start: told why) | 'unavailable' (their game does not have that game), or a sentence naming a bad argument
---@async
function whip_core:SkillCheck(source, difficulty, opts) end

--- The skill check games other resources add (Whip.skillCheckGame): what SkillCheck's `opts.game` and the Director's
--- Skill Check card can name. `levels` is the game's level NAMES (its timings stay its own); `needs`: it has a
--- canStart (something to have before it starts).
---@return { id: string, label: string, desc: string|nil, levels: string[], needs: boolean|nil, owner: string }[]
function whip_core:GetSkillCheckGames() end

--- The ring's settings as they are now (config.lua's, or what an admin changed in /whip Config), for a tool that
--- shows them. A copy. The client has the same export.
---@return { holdMs: number, mouseSpeed: number, difficulties: table<string, WhipSkillLevel> }
function whip_core:GetSkillCheckSettings() end

-- ============================================
-- Timed Actions (server-timed progress bars)
-- ============================================

--- Show a progress bar on a player's screen and WAIT for it — true only if the bar really ran its
--- length (the server keeps its own clock; an answer sooner than 90% of `duration` is 'too fast').
--- Blocks the calling handler for the bar: fine in a SecureEvent or a use handler, not in a
--- SecureCallback (the client gives up on those after 10 seconds). For an item, prefer a
--- RegisterUseHandler table, which also takes the item.
---
--- ```lua
--- local done = exports.whip_core:Progress(source, { label = 'Picking the lock...', duration = 8000,
---     near = { coords = doorCoords, range = 3.0 } })
--- if not done then return end
--- ```
---
--- `near` (server only): `{ coords = vector3, range }` or `{ vehicle = vehicleId, range }` — the
--- player must be that close when the bar starts AND when it finishes, or the answer is 'too far'.
---
--- `tag` (server only, your run tag): ReleaseTag(tag) ends the bar at once ('cancelled') and takes it
--- off their screen; a released tag is refused ('run ended'). A player who is down is not shown a bar
--- ('dead') unless `cancelOnDeath = false`.
---
--- `cancelOnExit = true`: work done from a seat. They must be in a vehicle to start ('not in a vehicle'),
--- getting out of it ends the bar, and a finish from outside it is 'left the vehicle'.
---
--- If whip_core restarts mid-bar this export never returns. `Whip.core:Progress(source, opts)`
--- returns `false, 'whip_core stopped'` instead (SkillCheck too).
---@param source number Player server ID
---@param opts WhipProgressOptions|{ near: { coords: vector3|nil, vehicle: number|WhipVehicleRef|nil, range: number }|nil, tag: string|nil } `duration` is required
---@return boolean completed
---@return 'cancelled'|'busy'|'timeout'|'too fast'|'too far'|'dead'|'player left'|'run ended'|string|nil why
---@async
function whip_core:Progress(source, opts) end

--- Somewhere else to ask whip_core's server Yes / No questions (whip_phone registers 'phone'): a question asked for
--- this channel (the Director's job invite) is offered to `deliver` first, which returns true when it showed it;
--- otherwise whip_core asks on screen. Answer with AnswerAsk; take the screen down on the local client event
--- whip_core:ask:cancelled ({ token }). Yours until your resource stops (questions you were still showing are then
--- asked on screen, the same question); another running resource's name is refused.
---@param name string letters, digits, _ or -
---@param deliver fun(source: number, token: number, kind: 'confirm', payload: { title: string, message: string, yes: string, no: string }): boolean
---@return boolean ok
---@return string|nil why
function whip_core:RegisterAskChannel(name, deliver) end

--- The answer to a question your channel showed: only the resource that took it may answer, for that player and the
--- character still playing.
---@param source number
---@param token number as deliver was given it
---@param yes boolean true Accept, false Decline
---@return boolean ok
---@return string|nil why 'That question is gone' | 'That question was not asked through you' | 'That question was for another character'
function whip_core:AnswerAsk(source, token, yes) end


-- ============================================
-- Player Stats & Effects
-- ============================================

--- Register a player stat (hunger, thirst, stress, ...). The caller's config
--- table is copied, never kept. Reserved names and another resource's stats
--- are refused with a reason; re-registering your OWN stat is allowed (that is
--- what a hot restart looks like). A `hud` block puts a gauge on the HUD with
--- no further wiring. The registration is dropped when the calling resource
--- stops; values are not.
---@param name string Stat name
---@param config { type?: string, default?: number, min?: number, max?: number, persist?: boolean, decay?: number, decayInterval?: number, thresholds?: table[], hud?: table }
---@return boolean ok
---@return string|nil err
function whip_core:RegisterStat(name, config) end

--- Get a stat value from the server cache.
---@param source number Player server ID
---@param name string Stat name
---@return number|nil value Nil if the player is not loaded or the stat is unset
function whip_core:GetStat(source, name) end

--- Set a stat value. Validated, clamped to the registered range, cached,
--- persisted (for persistent stats) and synced to the client. The stat must be
--- registered — an unknown name is refused, not quietly kept for one session.
---@param source number Player server ID
---@param name string Stat name
---@param value number New value
---@param reason string|nil What caused it, e.g. 'quest reward' (the change log and OnStatChanged show it; default 'by <your resource>')
---@return boolean ok
---@return string|nil err 'Player not loaded', 'no stat named "x" (RegisterStat it first)', 'value must be a number'
function whip_core:SetStat(source, name, value, reason) end

--- Add to a stat value. Same clamping, persistence and sync as SetStat.
---@param source number Player server ID
---@param name string Stat name
---@param delta number Amount to add (negative to subtract)
---@param reason string|nil What caused it, e.g. 'item:food' (shown where stat changes are logged)
---@return boolean ok
---@return string|nil err As SetStat, or 'amount must be a number'
function whip_core:AddStat(source, name, delta, reason) end

--- Get all stats for a player, as a copy.
---@param source number Player server ID
---@return table<string, number> stats {} if the player is not loaded
---@return string|nil why  'Player not loaded'
function whip_core:GetStats(source) end

---@class WhipStatChange
---@field source number The player
---@field key string The stat's name
---@field value number What it is now
---@field old number|nil What it was (nil on the `now` call)
---@field reason string|nil What caused it: 'decay', 'item:food', 'combat (reported): Pistol', 'by my_resource', 'now'

--- Be told when a player's stat changes on the server — every path: decay,
--- items, effects, combat damage, other resources' SetStat. Keyed by
--- `<your resource>:<id>` (id defaults to the name), so calling it again from
--- Whip.register replaces rather than doubles. Cleared when your resource stops.
---
---     exports.whip_core:OnStatChanged('hunger', function(source, value, old, reason) end)
---     exports.whip_core:OnStatChanged('*', function(source, name, value, old, reason) end)
---     exports.whip_core:OnStatChanged('hunger', function(change) end, { table = true, now = true })
---
--- `table = true`: one WhipStatChange instead. `now = true`: also called once
--- straight away for every loaded player who has the stat (old = nil, reason = 'now').
--- A listener that sets the stat it listens to is not re-announced (the set still lands).
---@param name string A stat name, or '*' for every stat
--- PREFER `table = true`: the positional orders of OnStatChanged, OnVehicleStatChanged
--- and OnVehicleDataChanged differ, and `'*'` shifts every argument by one.
---@param callback fun(source: number, value: number, old: number|nil, reason: string|nil)|fun(source: number, name: string, value: number, old: number|nil, reason: string|nil)|fun(change: WhipStatChange) The second shape is for '*'
---@param id any|nil Only to hold two listeners on one stat; the options may go here instead
---@param opts { table?: boolean, now?: boolean }|nil
---@return boolean ok
---@return string|nil err
function whip_core:OnStatChanged(name, callback, id, opts) end

--- Apply a temporary effect to a player. Nothing stacks: a second apply under
--- the same name REPLACES the effect. `replaceSilently = true` skips the replaced
--- instance's onRemove (by default it fires first). (`stackable` was its old
--- name and is refused.) The effect is always YOUR resource's: it is swept when
--- your resource stops.
---@param source number Player server ID
---@param name string Effect name
--- A timed effect keeps counting down while the player is dead; its onTick does not fire then.
--- Callbacks receive the player SHEET (serialize()), not the live object.
---@param config { duration?: number, magnitude?: number, tickRate?: number, onTick?: function, onApply?: function, onRemove?: function, damageModifier?: number, meleeModifier?: number, replaceSilently?: boolean, sheet?: 'light' } Nil duration = permanent until removed; sheet = 'light' hands your callbacks the light player sheet
---@return boolean ok
---@return string|nil err  why the config was refused (a non-numeric duration, say)
function whip_core:ApplyEffect(source, name, config) end

--- Remove an active effect from a player. Fires the effect's onRemove.
---@param source number Player server ID
---@param name string Effect name
---@return boolean ok
---@return string|nil err 'Player not loaded', 'no effect named "x" on this player'
function whip_core:RemoveEffect(source, name) end

--- Check if a player has an active effect.
---@param source number Player server ID
---@param name string Effect name
---@return boolean
function whip_core:HasEffect(source, name) end

---@class WhipEffectView
---@field duration number|nil Seconds it was applied for (nil = until removed)
---@field remaining number|nil Seconds left
---@field magnitude number
---@field tickRate number Seconds between onTicks
---@field damageModifier number|nil
---@field meleeModifier number|nil
---@field resource string Whose effect it is

--- Get all active effects for a player, as plain data (never the callbacks).
---@param source number Player server ID
---@return table<string, WhipEffectView> effects Keyed by effect name; {} when none
function whip_core:GetEffects(source) end

-- ============================================
-- Damage Modifiers
-- ============================================

--- Get the combined weapon damage modifier from all active effects on a player.
--- Returns 1.0 if no effects have damageModifier set.
---@param source number Player server ID
---@return number modifier Combined multiplicative modifier
function whip_core:GetDamageModifier(source) end

--- Get the combined melee damage modifier from all active effects on a player.
--- Returns 1.0 if no effects have meleeModifier set.
---@param source number Player server ID
---@return number modifier Combined multiplicative modifier
function whip_core:GetMeleeModifier(source) end

-- ============================================
-- Themes
-- ============================================

--- Set (or clear) the server-wide NUI theme override. `resource` names a
--- resource whose theme.css the NUI should inject — usually the caller's own.
--- Pass nil to clear back to Config.Theme. Fail-soft on the client, and unwound
--- automatically when the registering resource stops. Call it inside
--- Whip.register, not file scope.
---
--- The override belongs to the resource that set it: only it can change or clear it,
--- and another skin is refused ('the active theme belongs to X — stop it first').
---@param resource string|nil Resource name, or nil to clear
---@return boolean ok
---@return string|nil err
function whip_core:SetActiveTheme(resource) end

--- The theme in force: the override and who set it, or Config.Theme with no owner.
---@return string|nil theme  the resource whose theme.css is applied; nil for the stock look
---@return string|nil owner  the resource that set the override; nil for Config.Theme
function whip_core:GetActiveTheme() end

-- ============================================
-- Properties
-- ============================================

---@class WhipProperty
---@field id number
---@field name string
---@field label string|nil       the unit's own label, e.g. "3-1"
---@field building string|nil
---@field ownerCharId number|nil nil when unowned
---@field active boolean         false while the map pack that provides it is not running
---@field place table            { hash, x, y, z, yaw } — where its interior stands
---@field anchor table           { x, y, z, r } — a sphere holding the whole property
---@field sign table|nil         { x, y, z, heading } — outside, shown while it is for sale
---@field manager table|nil      { x, y, z, heading } — inside, shown to its owner and keyholders
---@field price number           shown on the outside sign (nothing is sold yet)
---@field visit table|nil        { x, y, z } — a spot to stand inside it
---@field shapes table[]         its space, as world boxes and polygons
---@field garageKey string|nil   its private garage ('property:<id>'), when its unit has bays
---@field keys number[]          charIds holding a key (GetProperty only)
---@field doorIds table          [doorKey] = doorId (GetProperty only)
---@field settings table         { price, maxObjects, autolock, autolockDelay } (GetProperty only)
---@field status string          'ok' (checked in the world by Verify) | 'unverified' | 'attention' (GetProperty only)
---@field statusReason string|nil why it needs attention (GetProperty only)
---@field templateId number      the template it is built on (GetProperty only)
---@field unitKey string         which unit of that template (GetProperty only)
---@field source string          'admin', or 'pack:<packId>' (GetProperty only)
---@field propertyKey string|nil '<packId>:<key>' for a pack's property (GetProperty only)
---@field packIssue string|nil   'orphaned: ...' / 'conflict: ...' for a pack's property (GetProperty only)

--- One property, with its keyholders, doors and settings.
---@param propertyId number
---@return WhipProperty|nil
function whip_core:GetProperty(propertyId) end

--- Every property, as clients see them (no keyholders, doors or settings).
---@return WhipProperty[]
function whip_core:GetProperties() end

--- The property whose space holds this point, or nil. Accepts (x, y, z) or a vector3.
---@param x number|vector3
---@param y number|nil
---@param z number|nil
---@return WhipProperty|nil
function whip_core:GetPropertyAt(x, y, z) end

--- What a character owns and holds keys to.
---@param charId number
---@return { owned: number[], keys: number[] }
function whip_core:GetCharacterProperties(charId) end

--- Is this person the property's owner or a keyholder?
---@param propertyId number
---@param who WhipPersonRef source, or { charId = n }
---@return boolean ok
---@return string|nil why  'No such property', 'No key to that property', ...
function whip_core:HasPropertyAccess(propertyId, who) end

--- Give a property to a person, or pass nil (or false) to make it unowned. A change of owner takes
--- back every key and locks the doors.
---@param propertyId number
---@param who WhipPersonRef|false|nil source, or { charId = n }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:SetPropertyOwner(propertyId, who) end

--- Give a person a key. No distance check: that is the in-game key menu's rule, not the API's.
---@param propertyId number
---@param who WhipPersonRef source, or { charId = n }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:GivePropertyKey(propertyId, who) end

--- Take a person's key back.
---@param propertyId number
---@param who WhipPersonRef source, or { charId = n }
---@return boolean ok
---@return string|nil err
---@async
function whip_core:RemovePropertyKey(propertyId, who) end

--- A property's stashes: the furniture in it that holds things (Config.PropertyStashProps), which
--- only its owner and keyholders open. Plain data, by containerId; open one with the container calls.
---@param propertyId number
---@return { containerId: number, name: string, slots: number, maxWeight: number, x: number, y: number, z: number }[]
function whip_core:GetPropertyStashes(propertyId) end

--- A property's looks, from the resource that built its interior (one declaring `whip_interior_themes`):
--- the one in force and every one it offers. nil when its interior has none.
---@param propertyId number
---@return { label: string, current: integer, themes: { id: integer, name: string, walls: string|nil, trim: string|nil, floor: string|nil }[] }|nil
function whip_core:GetPropertyThemes(propertyId) end

--- Give a property one of its looks, as its owner would from its sign, but with no check on who asks.
--- Saved, then the interior's resource redraws the home.
---@param propertyId number
---@param themeId integer
---@return boolean ok
---@return string|nil err
---@async
function whip_core:SetPropertyTheme(propertyId, themeId) end

--- Register an MLO's property pack from a script — the same table a `whip_property_pack` file
--- returns (docs/properties.md has the format). The pack belongs to the calling resource. Checked
--- whole first: the first mistake refuses it, with where it is.
---@param data table The pack
---@return boolean ok
---@return string howOrError 'applied' | 'unchanged' | 'queued', or 'path: why'
---@async
function whip_core:RegisterPropertyPack(data) end

--- The packs whip knows, and the pack files it refused, for an admin screen.
---@return { packs: { id: string, resource: string, version: string, label: string|nil, running: boolean }[], problems: { file: string, error: string }[] }
function whip_core:GetPropertyPacks() end

-- ============================================
-- The prop catalogue
-- ============================================

--- Your prop pack's props in the furnisher while your resource runs, under one of its categories, with your
--- pictures. The whole list each call: one left out goes. A model whip already lists keeps its row and takes your
--- picture. Waits for whip_core to finish starting.
---@param list { model: string, name?: string, category: string, image?: string }[]  category: a Config.PropCategories key
---@return boolean ok
---@return string|nil why
---@async
function whip_core:RegisterProps(list) end

--- May this prop model be placed? False for an unknown model or one marked unavailable.
---@param model string
---@return boolean
function whip_core:IsPlaceableProp(model) end

-- ============================================
-- Runtime points — interaction points made in code, from the server (server/runtime_points.lua)
-- ============================================

---@class WhipPointAt One place: coords, netId, vehicle, ground or container
---@field coords vector3|vector4|{ x: number, y: number, z: number }|nil A spot
---@field heading number|nil Stands like a sign facing this way; none: turns to face the player
---@field netId number|nil Rides this networked entity (an NPC): shown while a player's game has it
---@field vehicle number|table|nil Rides this whip car (a vehicleId, { plate }, ...) wherever it is out; nothing while it is in a garage
---@field ground number|nil Over this ground pile (gone once it is picked up)
---@field container number|nil Over this container
---@field offset vector3|nil From what it is on, within 10 m (on a car, a pile or a container: a little above it when left out)
---@field bone string|nil An entity bone, like 'SKEL_Head' (netId or vehicle only)

---@class WhipPointOption
---@field id string Letters, digits, _ and - (at most 40); what `use.option` says. Unique on its level
---@field label string|nil Its text (the point's label when left out)
---@field icon string|nil A glyph name
---@field require WhipActionRequire|nil Its own requirements, on top of the point's (and of the menus above it)
---@field options WhipPointOption[]|nil A menu: choosing it opens these, with a Back (at most 3 deep, 6 to a level, 40 in all). It is never pressed itself

---@class WhipPointUse
---@field pointId number
---@field option string The option chosen ('default' for a point with no options)
---@field path string The option's ids from the top, with / between ('tools/hack/firewall'; its id alone at the top)
---@field useId number This press, for whip functions that must only follow a real one
---@field coords { x: number, y: number, z: number } Where the point was, on the server
---@field netId number|nil The entity it rides (a car's, as it is now)

---@class WhipPointDef
---@field at WhipPointAt
---@field label string|nil
---@field icon string|nil A glyph name
---@field options WhipPointOption[]|nil At most 6 (to a level). None: the point itself is the one choice
---@field require WhipActionRequire|nil AddAction's words; an unknown word is refused. A zone must be a saved one
---@field audience WhipAudience|'everyone'|nil Who sees it and may use it ('everyone' when left out)
---@field reach number|nil How close to use it, 0.5-25 m
---@field seeFrom number|nil How far it is seen from
---@field focusMode 'aim'|'near'|nil 'aim' (default): point at it. 'near': the closest wins
---@field enabled boolean|nil false: there, but not offered
---@field style string|table|nil How it looks on every player's game: a style's name or table, as AddAction's (WhipPromptStyle). false clears it
---@field holdMs number|nil Hold E this long to use it (only the options that are pressed; Back stays a press). onUse is still the check. false clears it
---@field tag string|nil Your run tag: ReleaseTag removes it
---@field onUse fun(source: number, use: WhipPointUse): (boolean|nil), string? Runs on the server after distance, audience and requirements pass. false, 'why' refuses and tells the player

---@class WhipPointInfo
---@field pointId number
---@field owner string
---@field tag string|nil
---@field label string
---@field icon string|nil
---@field coords { x: number, y: number, z: number }|nil
---@field heading number|nil
---@field netId number|nil
---@field vehicleId number|nil
---@field groundId number|nil
---@field containerId number|nil
---@field enabled boolean
---@field options { id: string, label: string|nil, icon: string|nil, options: table[]|nil }[]

--- Add an interaction point from the server: a Talk prompt on an NPC, a hand-in spot. Yours: gone
--- when your resource stops, removed by ReleaseTag(def.tag). Not saved: add it again when your resource
--- starts. A field a point does not have (AddAction's onSelect, a misspelt lable) is
--- warned about in the server console and in the third return value; a wrong value is refused.
---@param def WhipPointDef
---@return number|false pointId
---@return string|false reason Why it was refused; false when it went in (not nil: that would cut off the warnings across the export)
---@return string[]|nil warnings What was wrong but not refused, or nil
function whip_core:AddPoint(def) end

--- Change one of your points: the fields in `patch` replace its own (false clears an optional one).
--- The tag cannot change.
---@param pointId number
---@param patch table
---@return boolean ok
---@return string|false reason Why it was refused; false when it went in (so the warnings get through the export)
---@return string[]|nil warnings As AddPoint's
function whip_core:UpdatePoint(pointId, patch) end

--- Remove one of your points.
---@param pointId number
---@return boolean ok
---@return string|nil reason
function whip_core:RemovePoint(pointId) end

--- Your points, or those under one of your tags.
---@param filter? { tag?: string }
---@return WhipPointInfo[]
function whip_core:GetPoints(filter) end

-- ============================================
-- Conversations — an NPC talks, a player answers (server/conversations.lua, the dialog capsule)
-- ============================================

---@class WhipConversationAnswer
---@field id string Letters, digits, _ and - (at most 40): what onChoose is told
---@field label string What the player reads (at most 60 characters)
---@field ends boolean|nil Choosing it ends the conversation (after onChoose)
---@field input { min?: integer, max?: integer, prefix?: string }|nil A typed amount: choosing it opens a field (digits, E gives it, Backspace steps back); onChoose's 4th argument is the whole number, checked against min (default 0) and max (default 999999999). prefix ('$') at most 8 characters
---@field cost { amount: integer, currency?: string, method?: 'auto'|'cash'|'bank', reason?: string }|nil What choosing it costs, charged before onChoose hears of it (ChargePlayer's rules). currency: an item key for that many of an item (paid from the pockets). One they cannot pay is refused with the reason and the answers stay. Not with input

---@class WhipConversationLine
---@field line string What the speaker says (at most 220 characters; colour codes removed)
---@field options WhipConversationAnswer[] 1 to 4 answers
---@field next table<string, { line: string, options: WhipConversationAnswer[] }>|nil The reply to each answer, sent ahead so the player sees it at once

---@class WhipConversationSpec: WhipConversationLine
---@field fromUse number The useId your point's onUse was handed: a conversation opens only from a press
---@field npcId number|nil The NPC Creator NPC who speaks (or netId)
---@field netId number|nil Any networked entity who speaks
---@field speaker string|nil The name shown above the line
---@field layout 'grid'|'stack'|nil The answers in a 2x2 grid (default) or a column
---@field tag string|nil Your run tag: ReleaseTag ends it
---@field onChoose fun(source: number, optionId: string, convId: number, amount: integer|nil)|nil An answer, checked (and paid, for a costed one): change what is said (UpdateConversation) or end it. amount: what was typed, for an answer with input
---@field onEnd fun(source: number, why: string)|nil Why it ended: 'ended', 'chose', 'left', 'blocked', 'downed', 'logout', 'killed', 'gone', 'hostile', 'no answer', 'replaced', 'released', 'stopped'
---@field canChoose fun(source: number, optionId: string, convId: number): (boolean|nil, string|nil)|nil Asked before an answer is taken or paid: answer false, why to refuse it (what it needs changed since it was offered). UpdateConversation takes it too (false takes it off)

---@class WhipConversationInfo
---@field convId number
---@field owner string
---@field tag string|nil
---@field source number
---@field npcId number|nil
---@field netId number
---@field speaker string
---@field line string
---@field options { id: string, label: string, ends: boolean }[]
---@field waiting boolean An answer is waiting for the owner

--- Open a conversation from your point's onUse: the dialog capsule beside the speaker, for this
--- player. One at a time per player (a new one replaces theirs). Yours: ends when your resource stops.
---@param source number
---@param spec WhipConversationSpec
---@return number|false convId
---@return string|nil reason
function whip_core:StartConversation(source, spec) end

--- Say something else: a new line and answers (and their replies, sent ahead).
---@param convId number
---@param patch WhipConversationLine|{ speaker: string }
---@return boolean ok
---@return string|nil reason
function whip_core:UpdateConversation(convId, patch) end

--- End one of your conversations (onEnd hears 'ended').
---@param convId number
---@return boolean ok
---@return string|nil reason
function whip_core:EndConversation(convId) end

--- A conversation, as a copy.
---@param convId number
---@return WhipConversationInfo|nil
function whip_core:GetConversation(convId) end

-- ============================================
-- NPCs (the NPC Creator)
-- ============================================

---@class WhipNpcConditions
---@field invincible boolean|nil Cannot be hurt (default false)
---@field canMove boolean|nil false freezes it in place (default true)
---@field reacts boolean|nil Reacts to the world on its own (gunfire, shoves); default false
---@field flees boolean|nil Runs away instead of fighting; default false. Needs reacts = true (a ped that reacts to nothing never flees)

---@class WhipNpcDef
---@field model string A ped model name, e.g. 's_m_y_dealer_01'
---@field coords vector3|vector4|{x: number, y: number, z: number, heading?: number}
---@field behaviour 'stand'|'guard'|nil Idle: 'stand' stays put (default), 'guard' wanders near its spot. Either walks back to its spot after a fight
---@field conditions WhipNpcConditions|nil
---@field weapon string|{ name: string, ammo?: number }|nil A GTA weapon name, e.g. 'WEAPON_PISTOL'
---@field armour number|nil 0-100
---@field interior boolean|nil It stands inside an MLO: each owning game keeps it frozen until it has that interior

---@class WhipAudience
---@field people (number|{ charId: number })[]|nil Server ids or characters (at most 64)
---@field except (number|{ charId: number })[]|nil Everyone BUT these (an NPC's hostileTo only, and only with a range)

---@class WhipNpcOpts
---@field tag string|nil Your run tag ('run:42'): ReleaseTag removes it with the rest of the run
---@field hostileTo WhipAudience|nil Who it fights (the nearest of them; never one who is down)
---@field fightBack boolean|nil Fights whoever attacks it, until they go down or a minute after their last hit (default true)
---@field corpseMs number|nil How long a body stays, in ms (default 60000; 0 = until removed)
---@field range number|nil A guard, 1-500 m: fights hostileTo only this near its spot, chases an attacker up to 3x as far
---@field group string|nil Hurt one, and every NPC of yours in the same group fights the attacker too
---@field bucket number|nil The routing bucket it is made in, from its birth (default 0, the shared world)

---@class WhipNpcInfo
---@field npcId number
---@field owner string The resource that made it
---@field tag string|nil
---@field model string
---@field netId number
---@field alive boolean
---@field health number|nil
---@field armour number|nil
---@field behaviour 'stand'|'guard'
---@field conditions WhipNpcConditions
---@field targets number[] Server ids it is fighting
---@field focus number|nil The attacker it is fighting first
---@field range number|nil Its guard range, if it has one
---@field group string|nil Its group, if it has one
---@field killer number|nil Who killed it (server id; a car's driver for a run-over), the server's own reading
---@field killedAt number|nil GetGameTimer() when it died
---@field weapon number|nil The weapon hash that killed it
---@field coords { x: number, y: number, z: number } Where it is now
---@field post { x: number, y: number, z: number, heading: number } Where it belongs (SetNpcState post moves it)
---@field pace 'walk'|'run'
---@field follow number|nil The player it follows
---@field flee number|nil The player it runs from
---@field interior boolean Its post is inside an MLO (it waits for that interior while it is there)

--- Make an NPC the server keeps and looks after (a networked ped). Yours: swept when your resource
--- stops, removed by ReleaseTag(opts.tag).
---@param def WhipNpcDef
---@param opts? WhipNpcOpts
---@return number|false npcId
---@return number|string netIdOrReason
function whip_core:SpawnNpc(def, opts) end

--- Remove one of your NPCs.
---@param npcId number
---@return boolean ok
---@return string|nil reason
function whip_core:DespawnNpc(npcId) end

--- Change what one of your NPCs does. post: a new spot it walks (pace 'run': runs) to and stays at
--- (interior: inside an MLO); follow / flee: a player's server id it walks after / runs from (false:
--- off); anim: what it plays where it stands (false: nothing); attack: a car (its netId) or a point (a prop) it
--- shoots at while it has nobody to fight (false: none).
---@param npcId number
---@param patch { behaviour?: 'stand'|'guard', hostileTo?: WhipAudience|false, fightBack?: boolean, conditions?: WhipNpcConditions, range?: number|false, post?: vector3|vector4|{ x: number, y: number, z: number, heading?: number }, interior?: boolean, pace?: 'walk'|'run', follow?: number|false, flee?: number|false, anim?: { dict: string, clip: string }|{ scenario: string }|false, attack?: { net: number }|{ at: vector3|{ x: number, y: number, z: number } }|false }
---@return boolean ok
---@return string|nil reason
function whip_core:SetNpcState(npcId, patch) end

--- An NPC, as a copy (any resource's). By its npcId, or by what you hold: `{ entity = }` or `{ netId = }`,
--- found only while that is still the NPC's ped.
---
---     local npc = exports.whip_core:GetNpc({ netId = netId })
---@param ref number|{ id: number }|{ entity: number }|{ netId: number } An npcId, or a reference
---@return WhipNpcInfo|nil
function whip_core:GetNpc(ref) end

--- Your NPCs, or those under one of your tags.
---@param filter? { tag?: string }
---@return WhipNpcInfo[]
function whip_core:GetNpcs(filter) end

-- ============================================
-- The voice system (server/voice_system.lua)
-- ============================================
--
-- One voice resource runs: whip_voice (its own voice server), or another that registers with RegisterVoiceSystem.
-- A resource that uses voice calls whichever it is through Whip.voice (lib/satellite.lua), never by name.
-- WhipVoiceSystem, what GetVoiceSystem returns, is declared in types/satellite.lua.

--- For a VOICE RESOURCE: make yourself the voice system. One at a time: refused while another one runs.
--- Call it in Whip.register; you are let go when your resource stops.
---@param info { label: string, features: { lines?: boolean, speaker?: boolean, pickup?: boolean, quality?: boolean, sounds?: 'full'|'basic' } }
---@return boolean ok
---@return string|nil why Naming the one already running
function whip_core:RegisterVoiceSystem(info) end

--- The voice system running now, or false when there is none.
---@return WhipVoiceSystem|false
function whip_core:GetVoiceSystem() end

-- ============================================
-- Update checks (server/updates.lua)
-- ============================================
-- A resource takes part by naming its GitHub repository in its fxmanifest.lua: whip_updates 'owner/repo'.

---@class WhipUpdateStatus
---@field resource string
---@field repository string 'owner/repo'
---@field current string|nil The resource's own `version`
---@field latest string|nil The latest release's tag, once GitHub has answered
---@field url string|nil That release's page
---@field newer boolean Whether `latest` is newer than `current`
---@field checkedAt integer|nil When GitHub last answered (os.time())
---@field problem string|nil Why there is no answer: a private repository, no release, GitHub's limit...

--- A resource's update status: its own when `resource` is left out. From whip_core's last check (every 12 hours),
--- so it costs nothing to call. nil when the resource names no repository.
---@param resource string|nil
---@return WhipUpdateStatus|nil
function whip_core:GetUpdate(resource) end

--- Every running resource that names a repository, with its update status.
---@return WhipUpdateStatus[]
function whip_core:GetUpdates() end

-- ============================================
-- Export binding
-- ============================================

---@type WhipCoreServerExports
exports.whip_core = whip_core
