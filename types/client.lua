---@meta
-- ============================================
-- whip_core — Client Export Annotations
-- LuaLS type definitions for all client-side
-- exports. This file contains NO runtime code.
--
-- Usage in your resource:
--   local dead = exports.whip_core:IsPlayerDead()
--   -- LuaLS now knows `dead` is boolean
--
-- ---@async marks an export that can wait (on the server, on the player, on a model loading): call it from
-- a thread or a handler, never at file scope. whip_core/dev/waits.js finds them and checks these marks.
--
-- SIDES. Both this file and types/server.lua describe exports.whip_core, and the editor cannot tell a client file
-- from a server one, so it offers both sides' calls everywhere. Hover a call: WhipCoreClientExports is the client's,
-- WhipCoreServerExports the server's. whip_core/dev/stubcheck.lua checks every export has its stub on its side.
-- ============================================

---@class WhipCoreClientExports
local whip_core = {}

-- ============================================
-- Callback
-- ============================================

--- Call a registered server callback and wait for the result (blocking).
--- Returns the handler's return values — or, when there is none to give, `false, reason`:
--- refused by whip's checks ('Rate limited', 'Player is dead', 'Too far away', a param's reason),
--- 'Server error', 'Unknown callback', 'That is no longer available' (its resource has stopped),
--- or 'No answer from the server' after 10 seconds.
---@param name string Callback name
---@param ... any Arguments passed to the server handler
---@return any ... Return value(s) from the server handler, or false, reason
---@async
function whip_core:Callback(name, ...) end

--- Who registered what with whip on this client (item flags, stat displays, appearance holds...).
---@param resource? string Just this resource's share
---@return { registry: string, key: string|number, owner: string }[]
function whip_core:GetRegistrations(resource) end

--- Has whip_core this export on this client? (Whip.has asks it.)
---@param name string
---@return boolean
function whip_core:HasExport(name) end

--- Is developer mode on for this player? For what a client tool shows; the server's HasDevTools(source) is the one
--- that counts for anything it does.
---@return boolean
function whip_core:HasDevTools() end

--- Say where your UI sits in the HUD's corner, so whip's HUD (the vehicle dial) moves out of its way; nil (or false)
--- takes it back. Fractions of the screen. Held under your resource and `key`, and let go when your resource stops.
--- It hides nothing and takes no keys (SetScreenOpen does that).
---     exports.whip_core:SetScreenArea({ left = 0.78, top = 0.46, right = 0.98, bottom = 1.0 }, 'phone')
---@param area { left: number, top: number, right: number, bottom: number }|false|nil
---@param key string|nil  default 'default'
---@return boolean ok
---@return string|nil why
function whip_core:SetScreenArea(area, key) end

--- Remove everything YOU registered on this client under one run tag, and close the tag. Same rule
--- as the server's ReleaseTag.
---@param tag string e.g. 'run:42'
---@return boolean ok true, or false
---@return number|string countOrReason how many went, or why it was refused
function whip_core:ReleaseTag(tag) end

--- What you hold on this client under one run tag.
---@param tag string
---@return { registry: string, key: string|number }[]
function whip_core:GetTagged(tag) end

-- ============================================
-- Client Hooks & Readiness
-- ============================================

--- Subscribe to a whip_core client moment — 'beforeGiveMode', 'beforePlaceMode' or 'freeHands' (something is about
--- to use the player's hands: put away what you hold; FreeHands) — the framework announces, satellites subscribe. A
--- handler may return a number of milliseconds for whip_core to wait afterwards (clamped to 1000). Handlers are pcall'd.
--- Registering again from the same resource with the same id REPLACES the handler, so it is
--- safe to call from Whip.register. Dropped when your resource stops.
---@param hookName 'beforeGiveMode'|'beforePlaceMode'|'freeHands' The moment; any other name is refused
---@param handler fun(...): number|nil Optionally returns a delay in ms
---@param id string|nil Defaults to hookName; pass one to hold two handlers on one hook
---@return boolean registered
---@return string? reason
function whip_core:RegisterClientHook(hookName, handler, id) end

--- How a player moves while giving an item (give mode): `walk`, a /walk name ('trash') or a clipset, and `speed`,
--- 'jog' (no sprint) or 'walk' (no running). Keyed by your resource, the latest set wins, cleared when it stops; nil
--- clears yours. Takes effect from the next give; the player's own walk comes back when the mode ends. With none set,
--- Config.GiveModeStyle.
---@param style {walk?: string, speed?: 'jog'|'walk'}|nil
---@return boolean ok
---@return string? reason
function whip_core:SetGiveModeStyle(style) end

--- Something is about to go in the player's hands (a phone, a tool): whatever holds them puts it away first — the
--- 'freeHands' moment, which whip_gunny answers by holstering — and this waits for it. Call from a thread (Whip.core).
--- While the hands are blocked (BlockHands) it returns false and the block's words.
---@return boolean free  true when no weapon is in the hands after it
---@return string? why  the block's words, while blocked
---@async
function whip_core:FreeHands() end

--- Block the player's hands until UnblockHands(id) or your resource stops: everything (the hands emptied at once,
--- FreeHands returning false), or weapons only (`only = 'weapons'`). Every block stops a draw and puts a gun away.
--- whip_core:hands:blocked / :unblocked tell everyone.
---@param id string
---@param opts {label?: string, only?: 'weapons'}|nil
---@return boolean ok
---@return string? reason
function whip_core:BlockHands(id, opts) end

---@param id string
---@return boolean ok
---@return string? reason
function whip_core:UnblockHands(id) end

--- Are the hands blocked for `what` ('weapon': any block; nil: a block of everything)? This game's and the server's.
---@param what 'weapon'|nil
---@return boolean blocked
---@return string? label
function whip_core:AreHandsBlocked(what) end

--- What the player's body is doing that work in the hands cannot be done in: under water (swimming under, or in a sunk
--- car), swimming, or falling (a fall, a skydive), the first that applies, and the words for it. False when none.
--- A progress bar takes the same states as `notWhile`.
---@return 'underwater'|'swimming'|'falling'|false state
---@return string? words 'You cannot do that while swimming'
function whip_core:GetBodyState() end

--- whip draws its aim dot for any weapon in the hand by itself (Config.AimDot). For something you aim that is not a
--- weapon in the hand: true while it is aimed, false after, and the dot shows in the middle meanwhile. Taken down if
--- your resource stops while aiming.
---@param on boolean
function whip_core:AimDot(on) end

--- Your own held prop (server HoldProps, under your `tag`) in this player's hand on this game, or nil.
---@param model string|number
---@param tag string|nil defaults to 'held'
---@return number|nil entity
function whip_core:GetOwnHeldProp(model, tag) end

--- Your own held prop let go of AT ONCE on this game (still tell your server, whose DropHeldProps forgets the set).
---@param model string|number
---@param tag string|nil
function whip_core:DropOwnHeldProp(model, tag) end

--- Your own held prop sat another way in this player's hand, seen by everyone: a different grip for a while.
--- `pose` = { bone?, offset = { x, y, z }, rot = { x, y, z } } (lists of three;
--- rot in GTA's order 2, as AttachEntityToEntity takes it; bone: the server's when left out), or nil to put it back
--- where the server put it. Only while this game is in control of the prop (nearly always: it is made under the
--- holder's feet).
---@param model string|number
---@param tag string|nil
---@param pose table|nil
---@return boolean moved
function whip_core:SetOwnHeldPropPose(model, tag, pose) end

--- Has whip_core finished loading on this client?
--- For code that needs to ASK rather than be told — registration should use Whip.register
--- (include '@whip_core/lib/satellite.lua'), which runs again for late starters and restarts.
---@return boolean
function whip_core:IsReady() end

-- ============================================
-- Player & Status
-- ============================================

--- The local player's sheet: the login data, kept current — cash and metadata as they
--- change, and isDead, health and armour read live when you call. A copy; {} before a
--- character is loaded.
---@return table playerData { charId, fullName, cash, metadata, isDead, health, armour, ... }
function whip_core:GetPlayer() end

--- Check if the player is fully loaded (character selected, spawned).
---@return boolean
function whip_core:IsPlayerLoaded() end

--- Into a character with nobody at the game, for tools and tests: past the welcome screen as a press would, the card
--- chosen, Play as the button does but without the map (they arrive where they left). Yields until loaded (≤ 90 s).
---
---     local ok, why = exports.whip_core:EnterCharacter({ slot = 1 })
---@param opts? { charId?: number, slot?: number }  the first card when neither is given
---@return boolean ok
---@return string|nil why
---@async
function whip_core:EnterCharacter(opts) end

--- The character editor on this character's own look, as a store: only the tabs `only` names, Save priced from
--- `prices` ("Pay $120"), and Save handed to onSave(look), which charges and keeps it (server GetAppearanceChanges,
--- SetPlayerAppearance) and returns true, or false, 'why' (said on Save; the editor stays open). With `methods`, Save
--- first opens a checkout (the total, a Cash and a Bank tile with what `wallet` says the player has) and onSave gets
--- the method chosen. Cancel puts the old look back. onClose(saved) is told when it shuts. Yields for the fade.
---
---     exports.whip_core:EditAppearance({ only = { 'hair', 'beard' }, prices = { hair = 40, beard = 15 },
---         title = 'Herr Kutz', onSave = function(look) return exports.whip_core:Callback('mybarber:buy', look) end })
---@param opts { only?: string[], prices?: table<string, number>, methods?: ('cash'|'bank')[], wallet?: { cash?: number, bank?: number }, title?: string, sub?: string, onSave: fun(look: table, method: 'cash'|'bank'|nil): boolean, string?, onClose?: fun(saved: boolean) }
---@return boolean ok
---@return string|nil why
---@async
function whip_core:EditAppearance(opts) end

--- Get the current character ID.
---@return number|nil charId Nil if not loaded
function whip_core:GetCharId() end

--- Another player's character name, by server id — asked of the server, which replies under
--- Config.ShowPlayerNames ('nearby' by default). Names are not on the shared player statebags.
--- From a cache: the first ask for someone returns nil and fetches; `wait = true` waits for it.
---@param serverId number
---@param wait boolean|nil
---@return string|nil name  nil while fetching, too far away, names 'never', or nobody there
---@async
function whip_core:GetPlayerFullName(serverId, wait) end

--- Check if the player is dead.
---@return boolean
function whip_core:IsPlayerDead() end

-- ============================================
-- Stats & Effects
-- ============================================

--- Get a stat value from the client cache (synced from the server).
---@param name string Stat name (e.g. 'hunger')
---@return number|nil value Nil if not yet synced or unknown
function whip_core:GetStat(name) end

--- Get all synced stats, as a copy.
---@return table<string, number>
function whip_core:GetStats() end

--- Register a listener for stat changes. Pass '*' as the name to hear every
--- stat; wildcard listeners receive (name, value, old) instead of (value, old).
--- Registering again from the same resource with the same id REPLACES the listener, so it is
--- safe to call from Whip.register. Dropped when your resource stops.
--- Options, the same as the server's: `table = true` gives one { key, value, old };
--- `now = true` also calls it once straight away with the current value (old = nil).
--- PREFER `table = true`: the listeners' positional orders differ, and '*' shifts them.
---@param name string Stat name, or '*' for all stats
---@param callback fun(value: number, old: number|nil)|fun(name: string, value: number, old: number|nil)|fun(change: { key: string, value: number, old: number|nil }) The second shape is for '*'
---@param id string|nil Defaults to the stat name; pass one to hold two listeners on one stat (the options may go here instead)
---@param opts { table?: boolean, now?: boolean }|nil
---@return boolean registered
---@return string|nil err
function whip_core:OnStatChanged(name, callback, id, opts) end

--- Check if an effect is active on the local player.
---@param name string Effect name
---@return boolean
function whip_core:HasEffect(name) end

--- Get all active effects, as a copy — the same plain data as the server's GetEffects.
---@return table<string, { duration: number|nil, remaining: number|nil, magnitude: number, tickRate: number, damageModifier: number|nil, meleeModifier: number|nil, resource: string }> effects Keyed by effect name
function whip_core:GetEffects() end

--- The HUD's voice-range bar as a percentage (20 whisper, 50 normal, 100 shout), cycled by Z. A voice
--- resource (whip_voice) turns it into metres; without one it is display only. See the local event
--- whip_core:voice:rangeChanged.
---@return number level
function whip_core:GetVoiceLevel() end

--- The voice level's name ('Whisper', 'Normal', 'Shout').
---@return string name
function whip_core:GetVoiceName() end

--- Light the HUD's voice gauge blue while the player transmits (a voice resource's push-to-talk) —
--- or orange with a radio in place of the mic while they transmit on the radio.
--- Held by the calling resource and switched off if it stops.
---@param talking boolean
---@param mode? 'radio' Talking on the radio; leave it out for normal talk
function whip_core:SetVoiceTalking(talking, mode) end

--- The voice system running now (whip_voice, or another voice resource), or false when there is none. The
--- local event whip_core:voice:systemChanged says when it changes.
---@return WhipVoiceSystem|false
function whip_core:GetVoiceSystem() end

-- ============================================
-- Inventory & Item Flags
-- ============================================

--- Register an item flag that auto-updates when inventory changes.
--- Three patterns:
---   RegisterItemFlag('crowbar')                                           -- has any crowbar
---   RegisterItemFlag('crowbar', function(meta) return meta.tier end)     -- with metadata filter
---   RegisterItemFlag('my_flag', 'vehicle_key', function(meta) ... end)   -- named flag, different item
--- The flag belongs to your resource and goes when it stops; a flag name another resource holds
--- (whip_core's own 'lockpick' included) is refused. A filter that errors counts
--- as "no" and is reported once; it can no longer break the inventory update.
---@param flagOrItem string Flag name (pattern 1-2) or flag name (pattern 3)
---@param filterOrItem? string|fun(metadata: table): boolean Item key (pattern 3) or filter function (pattern 2)
---@param filter? fun(metadata: table): boolean Filter function (pattern 3 only)
---@return boolean ok
---@return string|nil err
function whip_core:RegisterItemFlag(flagOrItem, filterOrItem, filter) end

--- Check if a registered item flag is currently satisfied.
---@param flagName string Flag name
---@return boolean
function whip_core:HasItemFlag(flagName) end

--- Check if the player has an item (one-shot, no registration needed).
---@param itemKey string Item key
---@param filter? fun(metadata: table): boolean|number Optional metadata filter, or a minimum AMOUNT (as on the server)
---@return boolean
function whip_core:HasItem(itemKey, filter) end

--- Count an item across all cached containers (one-shot, no registration needed). Items inside a
--- carried bag are not counted. A number in the filter's place is ignored (HasItem takes a minimum).
---@param itemKey string Item key
---@param filter? fun(metadata: table): boolean Optional metadata filter
---@return number count
function whip_core:GetItemCount(itemKey, filter) end

--- What this player holds, as the server last told this game (its SetHeldItem): a copy, or nil when the hand is empty.
--- For the item's metadata, ask the server's GetHeldItem(source). An action can require it: `require = { held = ... }`.
---@return { item: string, pocket: string, slot: number }|nil
function whip_core:GetHeldItem() end

--- Get a deep copy of the client's cached inventory, every container at once.
--- Read-only in every sense: editing what comes back changes nothing. To move
--- an item, fire `whip_core:server:storeMove` exactly as whip's own UI does.
---@return table|nil inventory { [container] = { [slot] = { item, amount, metadata } } }, or nil before first sync
function whip_core:GetInventory() end

--- Check if the inventory UI is currently open.
---@return boolean
function whip_core:IsInventoryOpen() end

--- Is a screen or a dialog up (not a bare progress bar)? The question for hiding an overlay (whip's
--- status HUD, the radar and whip_chat follow it). To ask whether the player may start something, ask
--- IsGameInputFree.
---
--- ASK IT ONCE, THEN LISTEN. Calling it from another resource is marshalled across the runtime
--- boundary, and the boundary is the cost: whip_chat once called it four times a second, and it showed
--- in a profile as a periodic spike.
---
--- Seed a local from this once, then keep it current from `whip_core:ui:stateChanged`:
---
---     local hidden = false
---     CreateThread(function()
---         local ok, open = pcall(function() return exports.whip_core:IsAnyScreenOpen() end)
---         if ok then hidden = open and true or false end
---     end)
---     AddEventHandler('whip_core:ui:stateChanged', function(e) hidden = e.open end)
---
--- Both halves are needed: the event says when it CHANGED, this says what it IS, and a resource
--- that starts while the inventory is already open has missed every event ever fired.
---@return boolean
function whip_core:IsAnyScreenOpen() end

--- May a hotkey act on the world right now? False while any screen, bar or dialog is up,
--- while another screen holds the focus (the F1 wheel,
--- chat, the /whip panel, character select, or ANY resource's screen — IsNuiFocused), and while a
--- mode owns the keys (placing, give mode,
--- throwing, an emote's ghost). Ask it first in every RegisterKeyMapping command that acts on the world:
---
---     RegisterCommand('+my_horn', function()
---         if not exports.whip_core:IsGameInputFree() then return end
---         ...
---     end, false)
---
--- A key mapping fires under a screen — disabling a control does not stop one, and a KeepInput
--- screen (the furnisher, whip_autos) passes every key through. One call per press.
---@return boolean
function whip_core:IsGameInputFree() end

--- Say the local player may hold a GTA weapon your resource gives (on = true), or no longer
--- (false). whip takes away every native weapon nothing permits (Config.WeaponGuard): a dead NPC's
--- gun, a police car's shotgun. Call it BEFORE GiveWeaponToPed and after RemoveWeaponFromPed. Your
--- permits go when your resource stops.
---@param weapon number|string A hash or a name ('WEAPON_PETROLCAN')
---@param on boolean
---@return boolean ok False for a weapon that is not a hash or a name
function whip_core:PermitNativeWeapon(weapon, on) end

--- Fired on this client whenever the answer to IsAnyScreenOpen changes. Local event, so a plain
--- AddEventHandler in any resource receives it; there is nothing to register.
---
---     AddEventHandler('whip_core:ui:stateChanged', function(e) ... e.open ... end)
---
--- e.open: true when a screen or dialog (whip's, or a satellite's via SetScreenOpen) is now up (WhipEvtUiState)

--- Declare that this resource's own NUI is open or closed. whip then treats your
--- screen exactly like one of its own: the HUD hides, prompts stop, nothing opens
--- on top — including ANOTHER resource's Input/Confirm/Alert/SkillCheck/Progress, which return
--- `false, 'busy'` (your own still open over your own screen). Cleared automatically when your
--- resource stops.
---
--- A resource with more than one screen names each with `key`, so closing one leaves the other
--- held: `SetScreenOpen(true, 'shop')` / `SetScreenOpen(false, 'shop')`.
--- `{ keepHud = true }` (the phone) leaves the status HUD, minimap and vehicle dial up for this screen; chat,
--- prompts and hotkeys still make way.
---@param open boolean True when you show your NUI, false when you hide it
---@param key? string Which of your screens; leave it out if you only have one
---@param opts? { keepHud?: boolean }
---@return boolean accepted False if there was no calling resource to attribute this to
function whip_core:SetScreenOpen(open, key, opts) end

--- Nothing on screen but the game's picture, for filming: GTA's HUD and map, whip's page, and the
--- prompts, /me bubbles and bay marks in the world all go (chat stays: F6). Held per resource under
--- your `id`, and released when your resource stops.
---@param id? string Your name for this hold
---@return boolean ok False if there was no calling resource
function whip_core:HoldCleanScreen(id) end

--- Let go of a HoldCleanScreen. The screen comes back once nothing else holds it.
---@param id? string The name you held it under
---@return boolean ok False if there was no calling resource
function whip_core:ReleaseCleanScreen(id) end

--- Hold controls off until you let go — the one call for "no walking / shooting / driving / radio
--- while my screen is up". whip runs ONE loop for every resource's blocks; whip_core
--- keeps the pause keys and action mode on it, so it is always running, and your block adds its
--- controls to it instead of a loop of your own. Swept when your resource stops, so a crash
--- cannot leave the player stuck. The same id again replaces that block.
---
--- Groups: move, combat, driving, vehicleCombat, look, radio, weaponWheel — and the switch driveBy
--- (shooting from a vehicle, turned off once rather than every frame). `controls` adds raw GTA ids;
--- name 200 when Esc is your way out, and the pause menu leaves Esc to you while you hold it.
--- A blocked control can still be READ with the disabled readers (IsDisabledControlPressed,
--- GetDisabledControlNormal). GetRegistrations() lists who holds a block (registry 'controlBlocks').
---
--- `all = true` holds off every control bar the `except` ids; an exception never gives back a control
--- another block holds. `walk = true` keeps the player to a walk at most (no jog, no sprint): sprint held
--- off and the move speed capped every frame in the same loop. `jog = true` caps it at a jog (walk and jog, never
--- sprint), with the sprint key left on: holding it is how a player jogs; the cap stops the sprint. The slower of
--- two blocks wins. `mode = true`: a mode of your own (placing,
--- aiming, a minigame) — whip's E prompts, hotbar and wheels stand down while it is held (IsGameInputFree
--- returns false), the HUD stays. A block holds from the frame it is made.
---
---     exports.whip_core:BlockControls('shop', { groups = { 'move', 'combat', 'radio' }, controls = { 75 } })
---     exports.whip_core:BlockControls('cursor', { all = true, except = { 30, 31 } })   -- only move the stick
---     exports.whip_core:BlockControls('carrying', { walk = true })                   -- walk, never run
---     exports.whip_core:BlockControls('holdRope', { jog = true })                    -- jog, never sprint
---     exports.whip_core:BlockControls('placing', { controls = { 26, 45, 140 }, mode = true })   -- your own mode
---@param id string|number Which of your blocks
---@param spec { groups?: string[], controls?: integer[], all?: boolean, except?: integer[], walk?: boolean, jog?: boolean, mode?: boolean }
---@return boolean ok
---@return string? why An unknown group, a bad control id, except without all, or nothing named
function whip_core:BlockControls(id, spec) end

--- Let go of one of your blocks (BlockControls). Returns true when it was not held, too.
---@param id string|number
---@return boolean ok
---@return string? why
function whip_core:UnblockControls(id) end

--- Hold the player's own ped invincible, frozen, hidden or without collision until you let go — the one
--- owner of those four (client/ped_hold.lua). The ped gets every hold together, so your letting go never
--- shows an admin who is invisible or thaws a player who is down. Swept when your resource stops; kept
--- on the new ped a death or a model change hands back. The same id again changes what it holds.
---
---     exports.whip_core:HoldPlayerPed('hang', { hidden = true, noCollision = true, invincible = true })
---     exports.whip_core:ReleasePlayerPed('hang')
---@param id string|number Which of your holds
---@param flags { invincible?: boolean, frozen?: boolean, hidden?: boolean, noCollision?: boolean }
---@return boolean ok
---@return string? why
function whip_core:HoldPlayerPed(id, flags) end

--- Let go of one of your holds (HoldPlayerPed). Returns true when it was not held, too.
---@param id string|number
---@return boolean ok
---@return string? why
function whip_core:ReleasePlayerPed(id) end

--- Close the inventory UI (handles NUI, server cleanup, and focus release).
function whip_core:CloseInventory() end

--- Get an item definition by key.
---@param key string Item key
---@return WhipItemDef|nil
function whip_core:GetItemDef(key) end

--- Get all registered item definitions.
---@return table<string, WhipItemDef>
function whip_core:GetItemDefs() end

-- ============================================
-- UI Library
-- ============================================

--- Show a notification toast.
---
--- Appears in the PLAYER CAPSULE at the bottom left when it is free and on screen, and in the
--- top-right stack otherwise (a UI is open, or the player is dead — both hide the capsule).
--- Bursts queue through the capsule one at a time. Callers do not choose: the surface is decided
--- at the moment the notification arrives.
---@param text string Message text
---@param type? string 'success', 'error', 'info', or 'warning' (default: 'info')
---@param duration? number Duration in ms (default: 3000)
function whip_core:Notify(text, type, duration) end

-- ============================================
-- Composer — one line of text, typed into the player capsule
--
-- The capsule at the bottom left normally shows stats. OpenComposer turns it into a text field:
-- the gauges step aside, the microphone bubble becomes an icon, and the capsule takes the
-- KEYBOARD ONLY — never the mouse cursor, because you are typing rather than clicking and taking
-- the cursor rips the camera away mid-sentence.
--
-- whip_chat is the first caller, but nothing in the composer knows about chat. Any resource that
-- wants one typed line gets the same capsule.
-- ============================================

---@class WhipComposerOpts
---@field onSubmit fun(text: string, mode: string|nil) REQUIRED. Called with the finished line.
---@field placeholder? string Ghost text shown while the field is empty
---@field prefill? string Text the field starts with, caret at the end
---@field maxLength? number Default 256
---@field modes? { name: string, displayName?: string, color?: string }[] Cycled with Tab when no suggestion list is showing; the active one comes back in onSubmit
---@field suggestions? { name: string, help?: string, params?: { name: string, help?: string }[] }[] Filtered live as the player types
---@field onCancel? fun() Escape, an empty line, or CloseComposer
---@field onScroll? fun(delta: number) PageUp (-1) / PageDown (1), for a log living in another NUI frame
---@field deferFocus? boolean Open WITHOUT taking the keyboard — call FocusComposer to take it. Use this from a `+command` binding so the key that opened the box is not typed into it.

--- Turn the player capsule into a text field.
---
--- One at a time: returns false if a composer is already open, rather than cancelling somebody
--- else's half-typed line.
---@param opts WhipComposerOpts
---@return boolean opened
function whip_core:OpenComposer(opts) end

--- Take the keyboard, for a caller that opened with `deferFocus`.
---
--- Meant for the release half of a `+`/`-` key binding pair: open the capsule on the press so it
--- transforms immediately, and take the keyboard on the release so the key that opened it does
--- not end up typed into the field.
---@return boolean focused
function whip_core:FocusComposer() end

--- Close the composer without submitting. The caller's onCancel runs.
---
--- Only closes a composer YOUR resource opened. Not needed in onResourceStop: when the resource that
--- opened a composer stops, whip closes it (silently — its onCancel went with it) and hands the
--- keyboard back.
---@return boolean closed False when none is open, or it is another resource's
function whip_core:CloseComposer() end

--- Is a composer open right now? Any composer, not necessarily yours.
---@return boolean
function whip_core:IsComposerOpen() end

-- ---- The blocking components: the rules they share ----
--
-- One at a time; a call while another is up returns `false, 'busy'` without showing anything.
-- Every one returns a second value when there is no answer: 'busy' | 'cancelled' | 'timeout', and
-- 'failed' for a SkillCheck the player missed. They close the inventory first, will not open over
-- another resource's SetScreenOpen screen ('busy'), and are cancelled when the resource that opened
-- them stops. Each takes its arguments positionally or as one table.

--- Show a progress bar (blocking). Can play an animation, hold a prop, and hold off the controls
--- you choose; dying ends it as 'cancelled' unless `cancelOnDeath = false`, and with `cancelOnExit = true`
--- so does getting out of the vehicle it began in.
---
--- Two forms: `Progress(label, duration, opts)` or `Progress({ label, duration, ... })`.
---
--- The player's word, not proof: if finishing hands something out, use the SERVER Progress(source,
--- opts), or for an item a declared RegisterUseHandler table.
---@param label string|WhipProgressOptions Text above the bar, or every option in one table
---@param duration? number Duration in ms (default 3000)
---@param opts? WhipProgressOptions
---@return boolean completed
---@return 'busy'|'cancelled'|'timeout'|'refused'|nil why 'refused': it never started (notWhile)
---@return string? words What stopped or refused it, as the capsule said
---@async
function whip_core:Progress(label, duration, opts) end

--- Load a model and wait for it — at most `timeoutMs` (default 5000). Returns the hash once loaded,
--- or nil (not a model the game has, or too slow). Release it with SetModelAsNoLongerNeeded. Waits:
--- call it from a thread.
---@param model string|number A name or a hash
---@param timeoutMs? number
---@return number|nil hash
---@async
function whip_core:LoadModel(model, timeoutMs) end

--- Load an animation dictionary and wait for it — at most `timeoutMs` (default 5000).
---@param dict string
---@param timeoutMs? number
---@return boolean loaded
---@async
function whip_core:LoadAnimDict(dict, timeoutMs) end

--- Load a streamed texture dictionary (for DrawSprite) and wait for it — at most `timeoutMs`
--- (default 5000).
---@param dict string
---@param timeoutMs? number
---@return boolean loaded
---@async
function whip_core:LoadTextureDict(dict, timeoutMs) end

--- Load a movement clip set (a walk style, for SetPedMovementClipset) and wait for it — at most
--- `timeoutMs` (default 5000).
---@param set string
---@param timeoutMs? number
---@return boolean loaded
---@async
function whip_core:LoadAnimSet(set, timeoutMs) end

--- Load a named particle asset (for UseParticleFxAssetNextCall) and wait for it — at most `timeoutMs`
--- (default 5000).
---@param asset string
---@param timeoutMs? number
---@return boolean loaded
---@async
function whip_core:LoadPtfxAsset(asset, timeoutMs) end

--- Is a progress bar running right now (anyone's)?
---@return boolean
function whip_core:IsProgressActive() end

--- Cancel the progress bar YOUR resource started; its caller gets `false, 'cancelled'`.
---@return boolean cancelled False when no bar is up, or it is another resource's
function whip_core:CancelProgress() end

--- End the progress bar YOUR resource started because something the player did not choose stopped it: it
--- turns red where it stands, a red ✗ in its disc, and says `why` for a moment. Its caller gets
--- `false, 'cancelled', why`. (whip's own bars do this for going down, being knocked down or falling, getting out
--- with cancelOnExit, a notWhile state beginning, and running in a walk-only bar.)
---@param why string Plain words: 'The engine caught fire'
---@return boolean interrupted False when no bar is up, or it is another resource's
function whip_core:InterruptProgress(why) end

--- Show on the hint capsule that one of your modes (an aim, a placing) was stopped by something the player
--- did not choose, as an interrupted bar is shown: a red outline and ✗, `why` as the title and `what` under
--- it, for a moment. Call it before taking your mode's own text down. Not shown while a bar is up.
---@param why string Plain words: 'You went down'
---@param what? string What it stopped: 'Placing the sign'
---@return boolean shown
function whip_core:ShowInterrupted(why, what) end

--- Show an input dialog with custom fields (blocking).
---
--- Two forms: `Input(title, fields)` or `Input({ title, fields })`. For one line of free text use
--- OpenComposer; for digits at a 3D prompt, InteractBeginInput.
---@param title string|{ title: string, fields: WhipInputField[] } Dialog title, or both in one table
---@param fields? WhipInputField[] Array of field definitions
---@return table|false values Field values indexed by position, or false when there is no answer
---@return 'busy'|'cancelled'|'timeout'|nil why
---@async
function whip_core:Input(title, fields) end

--- Let the player put a prop of yours down exactly (blocking): the item placer's see-through ghost follows where they
--- look; the wheel turns it, the arrows raise and lower it, Ctrl makes both fine, E puts it there, C cancels. Nothing
--- is made: your resource puts its prop where the answer says.
---@param model string|integer The prop's model
---@param opts? { label?: string, vehicles?: boolean, reach?: number } label: what the hint calls it; vehicles: it may go on a car; reach: metres from the camera (1-10)
---@return { coords: vector3, rot: vector3, netId?: integer, offset?: vector3, offsetRot?: vector3 }|false spot Where it was put (rot: tilt forward, tilt sideways, heading); on a car, the car and where on it
---@return 'cancelled'|'busy'|'model'|'dead'|nil why
---@async
function whip_core:PlaceObject(model, opts) end

--- A point placed in the world with the object viewer's markers: a ghost where the camera looks (opts.at's heading), the
--- centre dot dragged over the world, the arrows along X / Y / Z, the ring to turn it; Place takes it, Esc leaves it.
---
---     local spot = exports.whip_core:PlacePoint({ model = 's_f_y_shop_mid', ped = true, label = 'Shopkeeper' })
---@param opts? { at?: { x: number, y: number, z: number, w?: number }, model?: string, ped?: boolean, label?: string }
---@return { x: number, y: number, z: number, w: number }|false point
---@return 'cancelled'|'busy'|'model'|nil why
---@async
function whip_core:PlacePoint(opts) end

--- Run a skill check (blocking): the ring. The player pushes the dot onto the lit part of a ring and
--- holds it there until it fills, once a round (the difficulty's `rounds`, each part smaller); touching the ring
--- outside the lit part fails. Mouse (just moved, no cursor) or a pad's right stick; not the keyboard. The player's
--- word: when passing hands something out, use the server SkillCheck(source, difficulty).
---
--- Three forms: `SkillCheck(difficulty)`, `SkillCheck({ difficulty })`, and `SkillCheck({ difficulty, game })`, which
--- plays another resource's game instead (the phone's: 'phone.reroute'; `difficulty` one of its levels). A game whose
--- own canStart says they cannot play it (the phone's: no phone) shows nothing, tells them why, and returns
--- false, 'not started': never a fail. `SkillCheck({ level = { ... } })` plays the ring with your own numbers instead
--- of a named difficulty (WhipSkillLevel).
---@param difficulty? WhipSkillDifficulty|{ difficulty?: WhipSkillDifficulty|string, game?: string, level?: WhipSkillLevel } Default 'medium'
---@return boolean passed True if every round was filled
---@return 'failed'|'busy'|'cancelled'|'timeout'|'not started'|'unavailable'|string|nil why  'unavailable': no running resource here has that game; or a sentence naming a bad difficulty
---@async
function whip_core:SkillCheck(difficulty) end

--- The ring's settings as they are now (config.lua's, or what an admin changed in /whip Config), for a tool that
--- shows them. A copy. The server has the same export.
---@return { holdMs: number, mouseSpeed: number, difficulties: table<string, WhipSkillLevel> }
function whip_core:GetSkillCheckSettings() end

--- Show an alert dialog with a single OK button (blocking).
---
--- Two forms: `Alert(title, message, btnText)` or `Alert({ title, message, button })`.
---@param title string|{ title: string, message: string, button?: string }
---@param message? string Alert message
---@param btnText? string Button text (default: 'OK')
---@return boolean seen True once the player pressed the button
---@return 'busy'|'cancelled'|'timeout'|nil why
---@async
function whip_core:Alert(title, message, btnText) end

--- Show a confirm dialog (blocking).
---
--- Two forms: `Confirm(title, message, confirmText, cancelText)` or
--- `Confirm({ title, message, yes, no })`.
---@param title string|{ title: string, message: string, yes?: string, no?: string }
---@param message? string Confirm message
---@param confirmText? string Confirm button text (default: 'Confirm')
---@param cancelText? string Cancel button text (default: 'Cancel')
---@return boolean confirmed True if confirmed
---@return 'busy'|'cancelled'|'timeout'|nil why 'cancelled' when they said no
---@async
function whip_core:Confirm(title, message, confirmText, cancelText) end

--- Show persistent instruction text on screen: the hint capsule at the bottom centre.
---
--- Write the controls as parts: '[E] Place Burger  |  [Scroll] Rotate  |  [C] Cancel'. The first
--- part is the title, the rest a row under it; a short [Key] is a keycap, {pad:a} a pad button.
--- The same capsule the progress bar draws into. Pass `progress` to show a fill you drive yourself,
--- frame by frame; use Progress instead when you want it timed and blocking.
---
--- Two forms: `ShowText(text, position, progress)` or `ShowText(text, { position, progress, icon, tone })`.
---@param text string Text to display (e.g. '[E] Open Door')
---@param position? string|{ position: 'bottom'|'top'|nil, progress: number|nil, icon: string|nil, tone: 'warn'|nil } 'bottom' (default) or 'top'; or the options table. `icon`: a glyph's name (html/js/glyphs.js: 'place', 'give', 'talk', 'pickup'...) for the disc — without one the disc shows the first part's key. `tone = 'warn'`: an amber ring, it cannot be done here
---@param progress? number 0-100 fill percentage; omit for no bar
function whip_core:ShowText(text, position, progress) end

--- Hide the persistent instruction text — only if your resource put it up. (whip also takes it
--- down when your resource stops.)
---@return boolean hidden False when the text on screen is another resource's
function whip_core:HideText() end

--- Put an objective card up at the top right, on this player's screen only, or change the one `id`
--- names: the Director's card, with your text and mark. For something the client runs (a filming
--- tool's dummy objective); what the server runs is the server's to say. Yours by id; gone when your
--- resource stops.
---@param id string Your name for the card (64 letters at most)
---@param text string What to do ("Get to the docks"); 200 characters at most
---@param opts? { icon: WhipGlyph|nil, name: string|nil, countdown: number|nil, countdownTotal: number|nil, film: boolean|nil } `icon`: the disc's mark (the flag when none, or one whip does not have); `name`: the line under it; `countdown`: seconds on its clock (`countdownTotal` for the disc); `film = true`: stays up on a clean screen, as part of the picture
---@return boolean ok
---@return string|nil why
function whip_core:ShowObjective(id, text, opts) end

--- Take your objective card down. True also when there was none.
---@param id string
---@return boolean ok
function whip_core:HideObjective(id) end

-- ============================================
-- Radial Menu (the F1 wheel)
-- ============================================
--
-- An entry on the wheel is an action: AddAction({ at = { radial = true }, label = ..., onSelect = ... }).

--- Is the radial menu currently open?
---@return boolean
function whip_core:IsRadialOpen() end

-- ============================================
-- Interactions — AddAction
-- ============================================
--
-- One declaration for everything a player can do in the world: a prompt at a spot or riding on an
-- entity, a choice on a car part, an entry on the F1 wheel. `at`
-- says where; every other field reads the same. Yours by id (another resource's 'bench' is a
-- different action), adding again replaces, gone when your resource stops.

---@alias WhipGlyph
---| 'lock' | 'unlock' | 'lockpick' | 'door' | 'hood_closed' | 'hood_open' | 'trunk_closed'
---| 'trunk_open' | 'trunk_lid' | 'garage' | 'car' | 'store' | 'turbo' | 'furnish' | 'house'
---| 'pickup' | 'bank' | 'deposit' | 'withdraw' | 'back' | 'fuel' | 'nozzle' | 'cash' | 'talk'
---| 'phone' | 'bag' | 'emote' | 'id' | 'power' | 'headlights' | 'seat' | 'devtools' | 'place' | 'give'
---| 'eat' | 'respawn' | 'objective' | 'timer' | 'house_door' | 'target' | 'pin' | 'star' | 'fail' | 'success'
---| 'info' | 'warning' | 'object' | 'ped' | 'camera'
---| string  # `mfr_<brand>` for a maker's badge; anything else is drawn as its own text ('E', '$'). On the F1 wheel, text longer than 3 letters draws the label's first letter instead

---@class WhipActionAt
---@field coords vector3|nil A prompt at a point
---@field heading number|nil With coords: stands like a sign facing this way; none turns to face you. With model: a sign at this turn from the prop's own facing
---@field follow nil|fun(): number, number, number, number? With coords: where it is now, for something that moves
---@field entity number|nil A prompt riding on this entity (a prop, a local NPC); removed when it is gone (onGone says when)
---@field netId number|nil A prompt riding on this networked entity: off while it is not streamed in here, back on it when it is
---@field offset vector3|nil With entity or netId: from the entity's origin. With model: in the prop's own space (x across, y out of its face, z up)
---@field bone string|nil With entity or netId: ride this bone
---@field vehiclePart 'hood'|'trunk'|'door_dside_f'|'door_pside_f'|'door_dside_r'|'door_pside_r'|'bike'|'bicycle'|'boat'|nil A choice on a car part's prompt; `hood` only while the bonnet is open; `bike`, `bicycle`, `boat` their one prompt each
---@field model string|string[]|nil A prompt on every prop of this model NAME (or any of a list of names) near the player — a hash is refused
---@field faces 1|2|nil With model: 2 for a prop used from both sides
---@field perModel table<string, { offset: vector3|nil, heading: number|nil }>|nil With model: one model placed its own way; what an entry leaves out is the action's offset / heading. /actionplace <id> aims it and copies the line
---@field radial boolean|nil The F1 wheel (a label is required; its slab shows `icon`, the pill under it `description`)
---@field aimBox 'vehicle'|'object'|'ped'|'world'|string[]|nil A prompt where the player looks on the box of the car / prop / person they aim at: flat on that side (wrapped round its corners) or over its top. Offered only while the look meets one in reach; ctx.entity is the thing, ctx.coords the point. 'world': the map itself (ground, walls) where the look meets it: ctx.entity nil, ctx.world true, ctx.normal the way the surface faces

---@class WhipActionRequire
---@field alive boolean|nil false: also offered while downed (default: alive only)
---@field vehicle 'in'|'out'|nil In a vehicle, or on foot
---@field job string|number|(string|number)[]|nil Has a role at one of these jobs (key or jobId)
---@field onDuty boolean|nil ...and is on duty there (with no job: on duty anywhere)
---@field jobPermission string|nil ...and that role has this permission
---@field item string|{ item: string, count: number? }|(string|{ item: string, count: number? })[]|nil Carries all of these
---@field zone string|string[]|nil Standing inside one of these zones
---@field charId number|number[]|nil Is one of these characters
---@field ace string|nil Holds this ACE (asked of the server once, then remembered)

---@class WhipActionCtx
---@field id string Your action's id
---@field owner string Your resource
---@field option string Which option
---@field entity number|nil The entity aimed at, the car of a part, or the entity a prompt rides on
---@field coords vector3|nil Where the prompt was / where the aim hit
---@field player { serverId: number, playerIdx: number, activeJob: string|false|nil, isDead: boolean|nil }|nil Aiming at a player; their name is GetPlayerFullName(serverId). Their statebags: Player(ctx.player.serverId).state — a statebag reader cannot cross resources, so ctx carries none you can use
---@field flash fun(r: number, g: number, b: number)|nil onSelect only. Tint the prompt for a moment (world prompts)
---@field status fun(text: string, ms: number|nil)|nil onSelect only. Say something on the prompt (a notification elsewhere)
---@field refuse fun(why: string|nil)|nil onSelect only. Amber flash and the reason (an error notification elsewhere)
---@field beginInput fun(opts: { max: number|nil, numeric: boolean|nil, title: string|nil, prefix: string|nil, commas: boolean|nil, placeholder: string|nil, value: string|nil, onSubmit: fun(text: string), onCancel: fun()|nil, onChange: fun(text: string)|nil }): boolean|nil onSelect only. Type a value: the prompt steps aside for a capsule (a keyboard: Enter gives it) or the 3D on-screen keyboard (a pad). A number by default (`numeric = false`: any text)
---@field cancelInput fun()|nil onSelect only
---@field inputText fun(): string|nil onSelect only. What is typed so far, or nil when not typing
---@field typed string|false What is typed and a blinking caret while typing, else false. A value, not a function (the prompt itself is hidden while it is typed into)
---@field under string|nil onSelect, an option in a menu: the id of the menu option it was chosen in
---@field model string|nil at.model: the prop's model name
---@field face 1|2|nil at.model: which face of the prop (2 on a two-sided prop's other side)
---@field prop string|nil at.model: the prop's id (the same prop's every time)

--- What onFound / onLost get (at.model): one prop of the model, within 50 m (every one, seated too).
---@class WhipActionPropCtx
---@field id string Your action's id
---@field owner string Your resource
---@field entity number The prop (may be gone by onLost: read coords)
---@field model string Its model name
---@field prop string Its id
---@field coords vector3 Where it was found

--- A colour: '#ffc850', { 255, 200, 80 } or { r = 255, g = 200, b = 80 }.
---@alias WhipColour string|number[]|{ r: number, g: number, b: number }

--- How a world prompt looks and moves (client/interact_style.lua). Every field optional: what it
--- leaves out comes from `base`, and in the end from 'default' (Config.Interact3D).
---@class WhipPromptStyle
---@field base string|nil Start from this named style (Config.Interact3D.styles, or 'default')
---@field badgeScale number|nil The circle's size, 0.25-4
---@field labelScale number|nil The label's size, 0.25-4
---@field opacity { seen: number|nil, inReach: number|nil, focused: number|nil }|nil 0-1 in sight / in reach / the one E acts on (default 0.35 / 0.85 / 1)
---@field tint WhipColour|nil The circle's colour (the art is white)
---@field labelTint WhipColour|nil The label's colour
---@field fadeMs number|nil Fading in, out and between states, ms
---@field crossfadeMs number|nil The ring turning into the key, ms
---@field slideMs number|nil A stack of options sliding, ms
---@field flash 'blink'|'fade'|nil An answer flash: twice (default) or once
---@field flashMs number|nil How long that flash lasts, ms
---@field gap number|nil Circle to label, a share of the circle
---@field stackGap number|nil Between stacked option circles
---@field stackAlpha number|nil How visible an unselected option is
---@field previewScale number|nil The picture above the label, times the label's height
---@field cullBehind boolean|nil false: a sign is drawn from behind as well
---@field easing WhipEasing|nil How every movement eases ('smooth' default)
---@field fadeEasing WhipEasing|nil Fading only
---@field crossfadeEasing WhipEasing|nil The ring turning into the key only
---@field slideEasing WhipEasing|nil The option stack only
---@field appear 'fade'|'pop'|'slide'|'none'|nil How it arrives ('fade' default)
---@field appearMs number|nil How long arriving takes (220)
---@field focus 'none'|'pop'|'pulse'|nil When it becomes the one E acts on
---@field idle 'none'|'pulse'|'bob'|nil While it is not
---@field press 'none'|'pop'|nil When it is used
---@field labelWeight number|nil The label's weight, 400-800 (700)
---@field labelOutline number|nil The dark edge round its letters, 0-8 (3)
---@field labelOutlineColour WhipColour|nil That edge's colour (black)
---@field labelCase 'none'|'upper'|nil Capitals, a little spaced
---@field labelShadow boolean|nil false: no soft shadow under it
---@field theme 'classic'|'glass'|'rim'|'keycap'|'dot'|nil The circle's look ('classic', the white disc)

---@alias WhipEasing 'smooth'|'linear'|'out'|'inOut'|'back'

---@class WhipActionOption
---@field id string|nil Yours; defaults to 'opt<n>'
---@field label? string|fun(ctx: WhipActionCtx): string Falls back to the action's
---@field icon? WhipGlyph|fun(ctx: WhipActionCtx): string
---@field image? string|fun(ctx: WhipActionCtx): string World prompts: a picture above the label (a path under whip_core's html/)
---@field description? string|fun(ctx: WhipActionCtx): string The F1 wheel: the pill's second line while it is aimed at. Falls back to the action's
---@field require WhipActionRequire|nil On top of the action's
---@field canInteract nil|fun(ctx: WhipActionCtx): boolean On top of the action's
---@field onSelect nil|fun(ctx: WhipActionCtx) Falls back to the option above it (a menu's), then the action's
---@field holdMs number|nil Held to use, falling back to the action's; 0 is a press
---@field press boolean|vector3|{ coords?: vector3, offset?: vector3, normal?: vector3 }|nil Used with the hand, falling back to the menu's, then the action's (WhipAction.press)
---@field options? WhipActionOption[]|fun(ctx: WhipActionCtx): WhipActionOption[] World prompts: a MENU — choosing it shows these on the prompt, with a Back (any number of levels; looking away folds it). Its options pass this one's require / canInteract too and take what they leave out from it. A function fills the menu each time it opens, in a thread of its own (it may wait: "One moment…" shows meanwhile, "Nothing here" for an empty list)
---@field stay boolean|nil Down a menu: after its onSelect the prompt stays on this menu (a filled one is filled again) instead of going back to the top

---@class WhipAction
---@field id string|nil Yours; the same id again replaces it. Left out, one is made from the rest (stable)
---@field at WhipActionAt Where it lives (required)
---@field label? string|fun(ctx: WhipActionCtx): string What it says; a function is asked each draw and must not wait
---@field icon? WhipGlyph|fun(ctx: WhipActionCtx): string
---@field image? string|fun(ctx: WhipActionCtx): string
---@field description? string|fun(ctx: WhipActionCtx): string The F1 wheel: what it does, in the pill under the wheel while it is aimed at ('Start or stop the engine')
---@field require WhipActionRequire|nil Who may use it (every key given must pass)
---@field canInteract nil|fun(ctx: WhipActionCtx): boolean Your own rule; must not wait
---@field onSelect nil|fun(ctx: WhipActionCtx) Required here or on the options (an option takes the one above it, then this). Runs in its own thread: it may wait
---@field options WhipActionOption[]|nil Several choices on one action
---@field reach number|nil Metres to use it. Default Config.InteractActiveRange (2) for a prompt — set it to what your server check allows
---@field seeFrom number|nil World prompts: metres it appears from. Default Config.InteractVisibleRange
---@field scale number|nil World prompts: bigger or smaller than every other prompt (1.5 = half as big again), 0.25 to 4
---@field sizeRange number|nil World prompts: the distance its size is designed at (default its reach) — give the first reach here so a reach changed later does not resize it
---@field focusMode 'aim'|'near'|nil World prompts: which one E acts on among several in reach — 'aim' (default) what you look at; 'near' the closest, in a wider cone (doors, counters)
---@field onBlur nil|fun() World prompts: called when it stops being the one E acts on (fold a menu back up)
---@field style string|WhipPromptStyle|nil World prompts: how it looks and moves — a style's name ('subtle', Config.Interact3D.styles) or a table
---@field holdMs number|nil World prompts: hold E (A on a pad) this many ms to use it, a ring filling; letting go cancels. nil: a press
---@field press boolean|vector3|{ coords?: vector3, offset?: vector3, normal?: vector3 }|nil World prompts and car parts: used with the HAND — onSelect runs at once, and from where the player stands their hand goes out towards the point and straight back, only how it looks (never moves the player or takes control). true: towards the prompt's own point; a point; or { coords | offset (the entity's frame), normal (the way the surface faces) }. With no press clips installed it is a press of E (PlayPress)
---@field onGone nil|fun(ctx: { id: string, owner: string }) With at.entity: called when the entity has gone and the action with it
---@field onFound nil|fun(ctx: WhipActionPropCtx) With at.model: each prop of the model as it comes within 50 m (every one, seated too). Its own thread
---@field onLost nil|fun(ctx: WhipActionPropCtx) With at.model: as it goes (past 60 m, or gone from this game). Read ctx.coords
---@field group string|nil For RemoveActionGroup
---@field enabled boolean|nil false hides it without removing it

---@class WhipActionInfo
---@field id string
---@field owner string
---@field key string '<owner>:<id>'
---@field group string|nil
---@field reach number|nil
---@field seeFrom number|nil
---@field enabled boolean
---@field at table The plain values of `at`
---@field label string|nil When a string
---@field icon string|nil When a string
---@field mounted 'prompt'|'aimbox'|'props'|'radial'|'part'|false Where it lives ('aimbox': at = { aimBox }; 'props': at = { model }, on each prop of it found); false if it could not be put there (F8 says why)
---@field engineIds string[] The engine entries it is mounted as
---@field options { id: string, label: string|nil, offered: boolean, why: string|nil }[] Would each be offered to this player now, and why not

--- Put an action in the world — a prompt, an aim-menu option, a wheel entry or a car-part choice.
---
---     exports.whip_core:AddAction({
---         id = 'bench', at = { coords = vector3(12.1, -1105.3, 29.8), heading = 90.0 },
---         label = 'Weapon Bench', icon = 'store', require = { job = 'gunsmith' },
---         onSelect = function(ctx) TriggerServerEvent('mygunsmith:openBench') end,
---     })
---
--- A field it does not have, a value of the wrong kind or a number out of range is WARNED about
--- (F8, and the third return value), not refused; `require` is still refused on an unknown word.
---@param def WhipAction
---@return string|false id The id, or false when refused
---@return string|false why Why it was refused; false when added (so the warnings get through the export)
---@return string[]|nil warnings What was wrong but not refused ("lable is not a field — use 'label'. It was ignored"), or nil
function whip_core:AddAction(def) end

--- Change some of one of your actions' fields. `patch` is laid over what it has; an `at` in it
--- replaces the old one whole.
---@param id string
---@param patch table Any WhipAction fields
---@return boolean ok
---@return string|false reason Why it was refused; false when it went in (not nil: that would cut off the warnings across the export)
---@return string[]|nil warnings As AddAction's
function whip_core:UpdateAction(id, patch) end

--- Change how one of your actions' world prompts looks, now: in place, no fade out and in. A style's
--- name, a table, or nil for the default. UpdateAction(id, { style = ... }) alone does the same.
---@param id string
---@param style string|WhipPromptStyle|nil
---@return boolean ok
---@return string|false reason Why it was refused; false when it went in (so the warnings get through the export)
---@return string[]|nil warnings
function whip_core:SetActionStyle(id, style) end

--- Take one of your actions out. Another resource's id is refused. Not needed when you stop.
---@param id string
---@return boolean ok
---@return string|nil reason
function whip_core:RemoveAction(id) end

--- Take out every one of your actions in this group. Another resource's group of the same name is
--- untouched.
---@param group string
---@return boolean ok
---@return number|string countOrReason
function whip_core:RemoveActionGroup(group) end

--- One of your actions as plain data, with whether each option would be offered right now — and
--- why not. The first thing to ask when "my action never shows".
---@param id string
---@return WhipActionInfo|nil
function whip_core:GetAction(id) end

--- The hand goes out towards a point (3D Clanker's press clips), from where the player stands, and straight back as
--- it gets there: only how it looks. Returns AT ONCE (it plays in its own thread), so do the thing itself before or
--- right after, never waiting on it; safe inside any callback. It never moves or turns the player or takes control
--- (every press is a standing one). For a prompt, AddAction's `press = true` does this alongside onSelect.
---
---     ringTheBell()
---     exports.whip_core:PlayPress(vector3(x, y, z), { normal = vector3(0, -1, 0) })
---
--- `target`: a point, or { entity, offset?, bone? } (offset in the entity's frame). `opts.normal`: the way the
--- surface faces (either way round): a press pushing into it is preferred, and the hand comes back where it meets
--- it. `opts.onContact`: run exactly once for a press that went out, as the hand gets there (or as it ends, if it
--- is cut short on the way); never for false. Returns true (a press is going out), or false, why: 'off' (none:
--- off, not installed, too far, seated, already against the surface), 'busy' (one is going out), 'dead'.
---@param target vector3|table
---@param opts? { normal?: vector3, onContact?: function }
---@return boolean started
---@return string|nil why
function whip_core:PlayPress(target, opts) end

---@class GarageHelperStatus
---@field enabled boolean Config.GaragePositionHelper.enabled
---@field duiActive boolean Whether the one browser this feature uses is currently up
---@field drawing number How many bay outlines are visible right now
---@field driving boolean Whether the player is in a driver's seat
---@field qualifies boolean Whether the driven vehicle passes the storable test

--- What the garage position helper is doing right now.
---
--- Observable state for a feature whose only other evidence is a picture on a road.
--- INTERNAL (DEAD-1): used by the /garagehelper tuner and by whip_test — a test hook, not a satellite API.
---@return GarageHelperStatus
function whip_core:GetGarageHelperStatus() end

-- ============================================
-- Vehicles
-- ============================================

--- Get the framework vehicleId for an entity (cache-only, instant).
--- Safe for use in an action's canInteract and label.
--- Takes the entity bare or as `{ entity = veh }`; a bare number here is the ENTITY, not an id.
---@param entity number|{ entity: number } Vehicle entity handle
---@return number|nil vehicleId
function whip_core:GetVehicleId(entity) end

--- The other direction: the entity for a framework vehicleId, or nil when that
--- car is not streamed in around this client. For natives: every whip vehicle
--- export takes the vehicleId itself (a bare number is a vehicleId).
---@param vehicleId number|WhipVehicleRef Framework vehicle ID, or a vehicle reference
---@return number|nil entity
function whip_core:GetVehicleEntity(vehicleId) end

--- Does the local player have a key for this car? From the key cache: the server's HasVehicleKey, for this player.
--- `{ plate = }` reads the cache by plate, so a car that is not streamed in here is found too.
---
---     exports.whip_core:HasVehicleKey({ plate = 'ABC123' })
---@param ref number|WhipVehicleRef Vehicle ID, or a vehicle reference
---@return boolean
function whip_core:HasVehicleKey(ref) end

--- Everything this CLIENT knows about a vehicle, in one call.
---
--- Client view: live damage, colours, lock and engine state, and EVERY occupant including ambient
--- peds — which the server cannot see. It cannot see ownership or the garage. Returns nil when the
--- vehicle is not streamed in here, which is a real result rather than an error.
---
--- Named to match the server's GetVehicle, so one word means one thing on both sides. Takes a
--- vehicleId or a vehicle reference (`{ entity = }`, `{ plate = }`, `{ netId = }`, `{ id = }`). Only
--- cars streamed in near this client are found.
---
---     local v = exports.whip_core:GetVehicle({ entity = veh })
---@param ref number|WhipVehicleRef A vehicleId, or a vehicle reference
---@return table|nil
function whip_core:GetVehicle(ref) end

--- Resolve a vehicle entity to a vehicleId, registering it as a session vehicle if it is not one
--- already.
---
--- Instant for any vehicle whip already knows — which is every owned car and every street car
--- anyone has driven — because the id is read straight off the entity. Only an entirely unknown
--- vehicle costs a server round-trip, so do not call it from a prompt's canInteract; use
--- GetVehicleId there, which never blocks.
---@param entity number|{ entity: number } Vehicle entity handle, bare or as `{ entity = veh }`
---@return number|false vehicleId
---@return string|nil why  Why not: not near you, an owned car's plate, too many street cars held, ...
---@async
function whip_core:ResolveVehicle(entity) end

--- Get all vehicles within a radius, sorted by distance (closest first).
---@param radius? number Search radius in meters (default: 25, max: 100)
---@return WhipNearbyVehicle[]
function whip_core:GetNearbyVehicles(radius) end

--- Read everything about how a vehicle looks, as a plain table.
--- Mods, colours, wheels, tint, neon, livery, extras — the same shape
--- SetVehicleProperties takes, so capture-then-restore round-trips.
--- Use it to REMEMBER, not to store: persistence is the server's
--- SetVehicleAppearance, because a client saying what a car looks like is a
--- client that can say anything.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@return table props
function whip_core:GetVehicleProperties(vehicle) end

--- Apply an appearance to a vehicle entity, here and now. Local and unsaved,
--- but not unseen: mods are networked state, so this changes the car for every
--- player who can see it — provided this client holds network control of the
--- entity. The car reverts the next time the server pushes its stored
--- appearance, which is what makes this safe for previews.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param props table Appearance table (same shape GetVehicleProperties returns)
---@return boolean ok
---@return string|nil why  a bare entity handle is refused with a hint (a bare number is a vehicleId)
function whip_core:SetVehicleProperties(vehicle, props) end

--- Switch a vehicle's extras (light bars, roof racks, covers) KEEPING ITS DAMAGE. GTA's SetVehicleExtra repairs
--- the car (health, doors, tyres, fuel, dirt); this reads them first and puts them back, and switches only the
--- extras not already as asked. Local and unsaved like SetVehicleProperties (take control first); stored with
--- the car through SetVehicleAppearance's `extras`, which merges one extra at a time.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param extras table<integer, boolean> { [n] = true (on) | false (off) }, n 1-14
---@return integer switched How many changed (one the model lacks, or already as asked, is left alone)
function whip_core:SetVehicleExtras(vehicle, extras) end

--- Take network control of a vehicle: ask, wait, check, retry. Mod, paint and repair natives only
--- work for the client that controls the car. True at once if you already have it. Refuses a car
--- another player is driving (taking it makes their car rubber-band). Waits: call it from a thread,
--- through Whip.core.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param opts? { attempts?: number, wait?: number } Tries (default 3) and ms per try (default 500)
---@return boolean ok
---@return string? why 'no such vehicle' | 'another player is driving it' | 'control was not granted'
---@async
function whip_core:TakeVehicleControl(vehicle, opts) end

-- ============================================
-- Jobs
-- ============================================

--- Get all jobs the local player has a role at, by jobId.
---@return table<number, WhipPlayerJobInfo>
function whip_core:GetPlayerJobs() end

--- Is the local player on duty at this job (jobId or key) — or, with none, at any?
---@param job number|string|nil
---@return boolean
function whip_core:IsPlayerClockedOn(job) end

--- What the server's job list says the player may do at a job — a hint for what to offer; the server
--- checks again.
---@param job number|string jobId or key
---@param permission string
---@return boolean
function whip_core:HasJobPermission(job, permission) end

--- The job the player is on duty at — the most recent clock-on — or nil. The server's GetPlayerJob, for this player.
---@return WhipPlayerJobInfo|nil
function whip_core:GetPlayerJob() end

--- Go on duty at a job (jobId or key). Waits for the server: call from a thread. Refused
--- ('This job puts people on duty itself') for a job whose resource set selfClockOn = false.
---@param job number|string
---@return boolean ok
---@return string|nil err
---@async
function whip_core:ClockOn(job) end

--- Go off duty at a job — or, with none, everywhere. Waits for the server.
---@param job number|string|nil
---@return boolean ok
---@return string|nil err
---@async
function whip_core:ClockOff(job) end

-- ============================================
-- Camera
-- ============================================

--- Play a single camera at a position/rotation.
---
--- WAITS until the camera ends (with exitKey on — the default — or canLook/canMove) unless
--- `async = true`: the camera's controls run in the caller's thread.
---
--- BUSY while another resource's camera is up: `false, 'busy'` (your own camera is replaced).
---@param opts WhipCameraOptions Camera options
---@return boolean played
---@return string|nil why  'busy', or what is wrong with opts
function whip_core:PlayCamera(opts) end

--- Play a camera path through multiple waypoints.
---
--- ONE OPTIONS TABLE, not positional arguments (a call without `points` silently does nothing):
---
---     exports.whip_core:PlayCameraPath({ points = { ... }, duration = 8000, easing = 'smooth' })
---
--- WAITS for the whole path — forever, for a `loop` — unless `async = true`.
---
--- Checked before any camera goes up: at least two points, each with a pos and a rot, and a
--- duration above 0. BUSY while another resource's camera is up: `false, 'busy'`.
---@param opts { points: WhipCameraWaypoint[], mode?: 'interpolate'|'cycle', duration?: number, easing?: string, loop?: boolean, cycleDuration?: number, transitionIn?: number, transitionOut?: number, async?: boolean }
---@return boolean played
---@return string|nil why  'busy', or what is wrong with opts
---@async
function whip_core:PlayCameraPath(opts) end

--- Play a timeline of shots: a name saved in the Camera Creator (fetched from the server the first time:
--- call from a thread), or the sequence table (docs.html#client-camera has every field). WAITS for it
--- to end unless `async = true`. Checked before any camera goes up.
---@param sequence string|table  { keys = { { t, shot = { kind, ... }, move?, ease?, ... } }, length?, anchor?, loop?, letterbox?, ease? }
---@param opts table|nil { subjects?: table<string, number|table>, async?: boolean, loop?: boolean, letterbox?: boolean, speed?: number, startAt?: number, hold?: boolean, control?: boolean, exitKey?: boolean, transitionIn?: number, transitionOut?: number }
---@return boolean played
---@return string|nil why  'busy', or what is wrong (the key and the field), or a subject not there
---@async
function whip_core:PlayCameraSequence(sequence, opts) end

--- An orbit round an entity or a place { x, y, z, h }, left up until StopCamera; the player turns and
--- zooms it unless control = false. Returns at once.
---@param target number|table
---@param opts table|nil { yaw?, pitch?, fit?, dist?, aim?, look?, fov?, turn?, clear?, control?, exitKey?, letterbox?, transitionIn?, transitionOut? }
---@return boolean ok
---@return string|nil why
---@async
function whip_core:OrbitCamera(target, opts) end

--- Stop the camera YOUR resource started and return to gameplay, easing over its transitionOut.
--- Not needed on your resource stopping — whip releases it.
---@return boolean stopped False when none is playing, or it is another resource's
function whip_core:StopCamera() end

--- Check if a scripted camera is currently active.
---@return boolean
function whip_core:IsCameraActive() end

-- ============================================
-- Shops
-- ============================================

--- Check if the shop UI is currently open.
---@return boolean
function whip_core:IsShopOpen() end

--- Get the ID of the currently open shop.
---@return number|nil shopId
function whip_core:GetActiveShopId() end

-- ============================================
-- Time & Weather
-- ============================================

--- Get the current client-side time.
---@return number hour
---@return number minute
function whip_core:GetTime() end

--- Get the current client-side weather.
---@return string weather
function whip_core:GetWeather() end

--- Check if time is frozen.
---@return boolean
function whip_core:IsTimeFrozen() end

--- Check if the player has a time/weather override applied.
---@return boolean
function whip_core:IsTimeOverridden() end

--- Add or replace a client-side weather/time layer. Fields left out are not
--- overridden — a layer with only `weather` leaves time alone. The highest
--- priority layer that says anything about a field owns it. Affects THIS
--- client only, so it is safe to call from anywhere. The layer is yours: another
--- resource cannot replace or clear it, and it goes when your resource stops.
---@param name string Unique layer name (e.g. 'zone:swamp')
---@param opts { priority?: number, hour?: number, minute?: number, weather?: string, frozen?: boolean, blackout?: boolean }  weather: one of Config.WeatherTypes
---@return boolean ok
---@return string|nil why  only with false: 'Invalid weather type', 'layer "x" belongs to ...', ...
function whip_core:SetWeatherLayer(name, opts) end

--- Remove one of your weather/time layers by name.
---@param name string Layer name
---@return boolean ok  false if no such layer existed, or it is another resource's
---@return string|nil why
function whip_core:ClearWeatherLayer(name) end

--- Every active layer, plus which one currently owns each field ('server' when
--- no layer says anything about it). For debugging a stack that is not
--- resolving the way you expected.
---@return { layers: table[], owners: table<string, string> }
function whip_core:GetWeatherLayers() end

-- ============================================
-- Zones
-- ============================================

--- Register a client zone: a box, a sphere or a polygon, by its `type`. Returns its id (yours, or one made for it).
---
---     local id = exports.whip_core:RegisterZone({ type = 'sphere', pos = vector3(0, 0, 70), radius = 5.0,
---         onEnter = function() print('in') end })
---@param data WhipZoneBoxData|WhipZoneSphereData|WhipZonePolyData Zone configuration, with its `type`
---@return string|false id Registered zone ID
---@return string|nil why
function whip_core:RegisterZone(data) end

--- Remove one of your zones by ID.
---@param id string Zone ID
---@return boolean ok
---@return string|nil why
function whip_core:RemoveZone(id) end

--- Remove all your zones in a group.
---@param group string Group name
---@return boolean ok
---@return number|string countOrWhy
function whip_core:RemoveZoneGroup(group) end

---@class WhipZonePatch
---@field pos vector3|nil New center position (re-indexes the spatial grid; a poly's points move with it)
---@field size vector3|number|nil A box's new size, or a sphere's new radius (a poly is resized by its points)
---@field condition (fun(): boolean)|false|nil The zone only fires while it returns true; false takes it off
---@field debug boolean|nil Render the zone's outline
---@field trackVehicles boolean|nil Vehicle enter/exit detection
---@field label string|nil Display name
---@field priority number|nil Where zones overlap, every zone's rules hold together; priority decides the speed limit (the highest that sets one; a tie, the lower limit), the weather, and the enter/exit callback order
---@field notify boolean|nil Enter/exit notifications
---@field rules WhipZoneRules|false|nil Replaces the rules; false: none

--- Change one of your zones: only the keys you give. A key it doesn't know changes nothing.
---
---     exports.whip_core:UpdateZone(id, { pos = GetEntityCoords(PlayerPedId()), label = 'Here' })
---@param idOrKey string Zone id, or a saved zone's key (EnsureZone)
---@param patch WhipZonePatch
---@return boolean ok
---@return string|nil why
function whip_core:UpdateZone(idOrKey, patch) end

--- Is a point inside a zone (instant, no polling)?
---@param id string Zone id, or a saved zone's key (EnsureZone)
---@param point vector3 Point to test
---@return boolean
function whip_core:IsPointInZone(id, point) end

--- Is the local player inside a zone right now?
---@param id string Zone id, or a saved zone's key (EnsureZone)
---@return boolean
function whip_core:IsInZone(id) end

--- Every zone ID the local player is inside right now.
---@return string[]
function whip_core:GetZonesInside() end

--- Get a zone's full definition (client-side).
---
--- Includes `inside` (is the player in it right now), `debug`, and `hasCondition` —
--- whether a gate function is attached. The condition function itself is deliberately
--- not returned: it belongs to whoever set it, and the poll loop owns when it runs.
---@param id string Zone ID
---@return table|nil
function whip_core:GetZone(id) end

--- Every zone near a point, sorted by distance.
---@param pos vector3 Center position
---@param radius? number Search radius (default: 50)
---@return table[] Array of { id, type, label, pos, dist }
function whip_core:GetZonesNearby(pos, radius) end

-- ============================================
-- Doors
-- ============================================

--- Check if a door is locked. For a far door, the state as of the last time the player was near it.
---@param doorId number Door ID
---@return boolean|nil locked  nil for a door that does not exist
function whip_core:IsDoorLocked(doorId) end

--- Get all doors within a radius of the player — `(range)` — or of a point, with the server
--- export's shapes: `(coords, range)` or `(x, y, z, range)`. Measured flat, like the server.
---@param a? number|vector3 The range (player's position), the center as a vector3, or center X
---@param b? number The range after a vector3, or center Y
---@param c? number Center Z (accepted for symmetry; not used in the distance test)
---@param d? number The range after x, y, z
---@return WhipDoorDef[]
---@return string? why
function whip_core:GetDoorsNearby(a, b, c, d) end

--- Get all doors currently synced to the client.
---@return table[] Array of door data
function whip_core:GetLoadedDoors() end

--- A door from this client's cache: by its ID, or `{ entity = }` for the saved door a world entity is (by
--- model and position, among the doors nearby).
---
---     local door = exports.whip_core:GetDoor({ entity = entity })
---@param ref number|{ entity: number }|{ id: number } A doorId, or a reference
---@return table|nil doorData
function whip_core:GetDoor(ref) end

-- ============================================
-- Properties
-- ============================================

--- The property the player is standing in, or nil. `mine` is true when they own it.
--- whip_core:property:entered / :exited fire as this changes.
---@return { id: number, name: string, label: string|nil, building: string|nil, ownerCharId: number|nil, mine: boolean }|nil
function whip_core:GetCurrentProperty() end

--- How far along whip's furniture is for the property this interior copy belongs to (matched by its
--- placement): 'pending' (will be made, or made again, not up yet), 'done' (up, or the furnisher has
--- the room), 'none' (no saved furniture, or not a property's interior), 'idle' (has furniture, not
--- being made now: too far, or not among the nearest). whip_core:property:furnishStateChanged says
--- each change. For an interior resource that covers its windows until the room is finished.
---@param interiorId number
---@return 'pending'|'done'|'none'|'idle'
function whip_core:GetInteriorFurnishState(interiorId) end

-- ============================================
-- Escort
-- ============================================

--- Check if the local player is currently escorting someone.
---@return boolean
function whip_core:IsEscorting() end

--- Check if the local player is being escorted.
---@return boolean
function whip_core:IsBeingEscorted() end

--- Get the server ID of the player being escorted (or nil).
---@return number|nil targetServerId
function whip_core:GetEscortTarget() end

-- ============================================
-- Export binding
-- ============================================

---@type WhipCoreClientExports
exports.whip_core = whip_core

-- ============================================
-- Vehicle Stats (client)
-- ============================================
--
-- These had no stubs at all, which meant the client half of the vehicle stat API was invisible to
-- the language server — a satellite author had no way to discover it short of reading the source.
-- The Stage B plan called that out as the mistake Stats made and told us not to repeat it; it was
-- repeated on this side, and this is the correction.

--- Read one stat off a vehicle.
---
--- Takes the vehicleId, as on the server — a bare number is a vehicleId on every whip vehicle
--- export. Holding an entity? Pass `{ entity = veh }`.
--- Never a guess: the two ranges overlap, so a despawned car's handle could answer for another car.
---
--- Falls back to the stat's REGISTERED DEFAULT when the vehicle carries no value of
--- its own, so this returns the same number the server's GetVehicleStat returns.
---
--- "Is one fitted?" is NOT `> 0`: an absent stat reads as its default, so with a default
--- above zero every car says yes. Ask HasVehicleStat, just below.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param name string Stat name, e.g. 'fuel'
---@return number|nil value nil if the vehicle is not streamed in, or the stat is unknown
function whip_core:GetVehicleStat(vehicle, name) end

--- Does this vehicle actually CARRY this stat, as opposed to reading as its default?
---
--- The question GetVehicleStat cannot answer: readers resolve an absent key to
--- the registered default, so `GetVehicleStat(veh, name) > 0` reports true for
--- every car on the server whenever the default is above zero. This reads
--- presence — recorded when the stat is fitted, removed when it is cleared.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param name string Stat name
---@return boolean
function whip_core:HasVehicleStat(vehicle, name) end

--- Report that this client used some of a consumable stat.
---
--- SAFE TO CALL EVERY FRAME. Hand it the amount used since the last call and the
--- framework does the rest: it accumulates locally, reports on the cadence the stat
--- was registered with, and the server caps whatever arrives against the wall clock.
---
--- You never declare an event, keep an accumulator, pick a rate limit, or decide what
--- to do when a report does not land. What is sent is a RUNNING TOTAL, so a dropped
--- report costs one report's latency rather than the burn it carried.
---
--- Only works for a stat registered with a `consume` block, and only for the driver
--- unless that block set driverOnly = false.
---
--- ```lua
--- exports.whip_core:ConsumeVehicleStat({ entity = veh }, 'nitro', 5.0 * GetFrameTime())
--- ```
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param name string Stat name
---@param delta number Amount used since the last call. Positive.
---@return boolean accepted false if the arguments were unusable or the car is unknown
function whip_core:ConsumeVehicleStat(vehicle, name, delta) end

--- Report several consumable stats used on one vehicle, in a single call.
---
--- USE THIS WHENEVER YOU HAVE MORE THAN ONE. Everything about the protocol is identical to
--- ConsumeVehicleStat — same accumulator, same per-stat cadence, same server-side cap. The only
--- difference is that you cross into whip_core once instead of once per stat, and that crossing
--- costs far more than the accumulating does: a resource draining ten stats this way spends about
--- a fifth of what ten separate calls cost.
---
--- ```lua
--- local used = {}
--- for i = 1, 10 do used['part' .. i] = FULL * moved / distance[i] end
--- exports.whip_core:ConsumeVehicleStats({ entity = veh }, used)
--- ```
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param deltas table<string, number> Stat name to amount used since the last call. Positive.
---@return boolean ok false if the car is unknown or `deltas` was not a table
---@return number accepted How many of the deltas were valid and applied
function whip_core:ConsumeVehicleStats(vehicle, deltas) end

--- Report what a live stat is worth right now.
---
--- The rising counterpart to ConsumeVehicleStat. Use it for a value the client
--- drives in BOTH directions — turbo boost, engine heat, charge — where the
--- question is "what is it now" rather than "how much was used". Safe to call
--- every frame: the latest value supersedes any earlier one, and the framework
--- reports on the stat's registered cadence. The server caps how fast it may
--- rise, and refuses the report unless the vehicle already carries the stat.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param name string Stat name
---@param value number What the stat is worth now
---@return boolean accepted false if the arguments were unusable or the car is unknown
function whip_core:ReportVehicleStat(vehicle, name, value) end

--- Every stat on a vehicle, as a plain table.
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@return table<string, number> stats A copy — mutating it changes nothing
function whip_core:GetVehicleStats(vehicle) end

--- Be told when a vehicle stat changes, on ANY vehicle streamed to this client.
---
--- The vehicle counterpart of OnStatChanged. Push, not poll: the server writes the stat block once
--- and every client with that vehicle in scope is notified, so a satellite never needs its own
--- loop. Listeners are dropped automatically when the resource that registered them stops.
---
--- ```lua
--- exports.whip_core:OnVehicleStatChanged('nos', function(vehicleId, value, old, entity)
---     if value < 10 then exports.whip_core:Notify('Nos running low', 'error') end
--- end)
--- ```
--- The server exports the SAME NAME, with one difference in the callback: it is told whether the
--- stat was CLEARED where this side is told which ENTITY it happened on. Neither side can answer
--- the other's question, so neither pretends to.
---
--- `{ table = true }` hands the callback one WhipVehicleChange table with the names the server uses
--- too, and `{ now = true }` also calls it once straight away for every car in range carrying the
--- stat. The options may go third, in place of `id`.
---@param name string Stat name to watch
---@param callback fun(vehicleId: number, value: number, old: number|nil, entity: number)|fun(change: WhipVehicleChange)
---@param id? string|WhipVehicleListenOpts Registration key within your resource; registering the same id again replaces it
---@param opts? WhipVehicleListenOpts
---@return boolean registered false if the arguments were not a string and a function
function whip_core:OnVehicleStatChanged(name, callback, id, opts) end

--- Run code while a vehicle in scope carries a stat, without writing a presence cache.
---
--- Two pairs of callbacks, and picking the right one is the only thing to get right:
---   onGained / onLost — facts about the WORLD. Fire for EVERY vehicle in scope, always,
---                       and ignore driverOnly. React to what a car IS.
---   onStart / onStop  — facts about THIS WATCHER. Bracket whileHeld running for an
---                       entity, and follow driverOnly. If you modify a vehicle and must
---                       put it back, these are yours: onStop covers getting out, losing
---                       the stat, the car despawning and the stat being pulled.
---
--- whileHeld defaults to every holder in scope; `driverOnly = true` narrows it to the
--- car this player is driving. Vehicles already in scope with the stat are announced to
--- onGained at registration, so it is the only setup point you need.
---
--- A LIST OF NAMES watches them all with one set of callbacks, each handed the stat's name second —
--- onGained(entity, name, value), onStart(entity, name, value), onStop(entity, name) — under
--- one id that UnwatchVehicleStat and SetVehicleStatWatchInterval act on as a whole.
---
--- A list's whileHeld runs once PER STAT, each a crossing into your resource. For one job per car,
--- use onStart/onStop to know what is fitted and run the job in a loop of your own.
---@param name string|string[] Stat name to watch, or a list of them
---@param data { onGained?: function, onLost?: function, onStart?: function, onStop?: function, whileHeld?: function, interval?: number, driverOnly?: boolean, id?: string }
---@return string|false watcherId Handle for UnwatchVehicleStat, or false if the arguments were unusable
---@return string|nil why
function whip_core:WatchVehicleStat(name, data) end

--- Change a live watcher's whileHeld cadence.
---
--- FOR A SATELLITE WHOSE WORKLOAD COMES IN BURSTS. An interval is fixed at
--- registration, so anything busy occasionally and idle the rest of the time
--- otherwise has to register for its busiest moment and pay that rate forever.
--- Register idle, raise it when the work starts, lower it when it stops.
---
--- IT IS NOT ONLY YOUR OWN BILL. The sweep sleeps until the soonest watcher is
--- due, so the fastest watcher that can act sets the floor for every other
--- watcher and for the sweep's own wake rate. One satellite asking for 20Hz
--- makes the whole system 20Hz. whip_autos/client/power/nitrous.lua raises its
--- interval only while a bottle burns.
---
--- whileHeld receives a real elapsed `dt`, so anything integrated against it
--- stays correct across a change of cadence. Anything that bills or accumulates
--- a fixed amount per call does not — fix that before reaching for this.
---
--- Cheap and safe to call on every state transition, and a no-op when the value
--- has not moved. `lastRun` is left alone, so a watcher that has just run waits
--- out the remainder of its new interval rather than getting a free tick.
---@param watcherId string The id returned by WatchVehicleStat (a list's id sets every stat in it)
---@param ms number New whileHeld interval in milliseconds; 0 means every pass
---@return boolean changed False if the id is unknown or the interval already matched
function whip_core:SetVehicleStatWatchInterval(watcherId, ms) end

--- Stop a watcher. Fires onStop for anything it was still running for, and does
--- NOT fire onLost — nothing about the world changed, but the watcher's work is
--- stopping, so a satellite that unwatches mid-drive still gets to put the car back.
---@param watcherId string The id returned by WatchVehicleStat (a list's id stops every stat in it)
---@return boolean removed
function whip_core:UnwatchVehicleStat(watcherId) end

--- Run code while a vehicle in scope carries a piece of vehicle data — the data twin of
--- WatchVehicleStat. onGained/onChanged/onLost fire for every car in scope (cars already there are
--- announced at once); onStart/onStop bracket this watcher, and with `driverOnly` only for the car
--- this player drives (handling). Without onChanged, a new value fires onLost(old) then onGained(new).
--- Registering again with the same key and `id` (default: the key) replaces it.
---@param key string A vehicle data key
---@param data { onGained?: function, onChanged?: function, onLost?: function, onStart?: function, onStop?: function, driverOnly?: boolean, id?: string }
---@return string|false watcherId Handle for UnwatchVehicleData, or false
---@return string|nil why Why not
function whip_core:WatchVehicleData(key, data) end

--- Stop one of your data watchers. Fires onStop for anything it had started, not onLost.
---@param watcherId string The id returned by WatchVehicleData
---@return boolean removed
function whip_core:UnwatchVehicleData(watcherId) end

--- Declare (or replace) your handling layer on the car this player drives. whip_core is the one
--- owner of handling writes: each field's stock value is captured before the first write, every
--- layer's `set` applies in `order` (higher wins), then every `add` is summed on, then every `scale`
--- multiplies in, and the car goes back on every way out. Never write handling yourself.
---@param vehicle WhipVehicleRef|number { entity = veh } or a vehicleId
---@param name string Your layer's name, one per feature ('engine', 'turbo')
---@param spec { set?: table<string, number>, add?: table<string, number>, scale?: table<string, number>, order?: number } handling.meta units; add amounts -1000 to 1000; scale factors 0.01-100
---@return boolean ok
---@return string|nil why Why not
function whip_core:SetVehicleHandlingLayer(vehicle, name, spec) end

--- Take your layer off, whatever car it is on. The car goes back to stock once no layer is left.
---@param name string
---@return boolean removed False when you had no layer by that name
function whip_core:ClearVehicleHandlingLayer(name) end

--- Ask for engine torque on the car this player drives: a multiplier, 1.0 being the engine as it is.
--- A turbo, a shot of nitrous. The car gets the PRODUCT of every resource's ask, written every frame
--- through GTA's torque multiplier: no gearing change, so top speed comes from the physics. Ask again
--- as often as the amount changes; clear it when the feature stops (a driverOnly watcher's onStop).
---@param vehicle WhipVehicleRef|number { entity = veh } or a vehicleId
---@param name string Your ask's name, one per feature ('turbo', 'nitrous')
---@param multiplier number 0 to 10 (1.25 = a quarter more torque)
---@return boolean ok
---@return string|nil why Why not
function whip_core:SetVehiclePower(vehicle, name, multiplier) end

--- Take your torque ask off, whatever car it is on.
---@param name string
---@return boolean removed False when you had no ask by that name
function whip_core:ClearVehiclePower(name) end

--- Say which engine a vehicle's rev dial follows, on THIS player's game. The dial goes by the engine:
--- its model in Config.VehicleHud.rpmByModel, else rpmElectric for an electric motor, else its kind in
--- rpmByClass. A vehicle's engine is its own until a resource says otherwise: an engine swap passes the
--- donor's model (whip_autos does, for every car in view). Set it on every client; clear it in onLost.
--- A resource's settings are dropped when it stops; another running resource's are refused.
---@param vehicle WhipVehicleRef|number { entity = veh } or a vehicleId
---@param engine string|{ max: number, idle?: number }|nil A model's spawn name, a range in thousands of rpm (max 2-20, idle 0 to under max), or nil for its own engine
---@return boolean ok
---@return string|nil why Why not
function whip_core:SetVehicleRevRange(vehicle, engine) end

--- Is this vehicle's engine electric? GTA's own flag on its engine's model (its own, or the one
--- SetVehicleRevRange says it carries). False for a vehicle that is not here, or a build without the flag.
---@param vehicle WhipVehicleRef|number { entity = veh } or a vehicleId
---@return boolean
function whip_core:IsVehicleElectric(vehicle) end

--- Say which forward gear the rev dial shows for a vehicle, when your resource drives the gears itself
--- (whip_autos' gearbox computer gives GTA one gear and changes its ratio, so GTA's own gear stays 1).
--- Reverse and N stay the game's. Dropped when your resource stops; another running resource's is refused.
--- 'speed': your resource moves the car itself (a recorded drive), not its gearbox, so the dial works the gear out
--- from its speed, R going backwards. Cleared, GTA's gearbox is put in that gear for whoever drives on.
---@param vehicle WhipVehicleRef|number { entity = veh } or a vehicleId
---@param gear integer|'speed'|nil 1 to 20, 'speed', or nil for the game's gear again
---@return boolean ok
---@return string|nil why Why not
function whip_core:SetVehicleDialGear(vehicle, gear) end

--- A field's value after every layer's `set` and `add` but before any `scale` — what a multiplier multiplies.
--- For a car no layer is on, simply its current value.
---@param vehicle WhipVehicleRef|number
---@param field string A CHandlingData field (f... float, n... whole number)
---@return number|nil value Nil when the car or the field is not there
function whip_core:GetVehicleHandlingBase(vehicle, field) end

--- Let this client draw its own reading for a stat, instead of the replicated one.
---
--- For a value the client is already calculating in real time. The provider is
--- called with (entity, replicatedValue) whenever the capsule repaints; return
--- nil to defer to the replicated value. It does NOT write the stat, reach the
--- server, or decide whether the gauge is drawn at all — presence stays the
--- replicated answer, so a provider can never put a gauge on a car without the part.
---
--- The stat's reading belongs to the resource that set it: another resource is refused.
---@param name string Stat name
---@param fn fun(entity: number|nil, replicated: number|nil): number|nil
---@return boolean registered
---@return string? reason
function whip_core:SetVehicleStatDisplay(name, fn) end

--- Stop drawing YOUR local reading for a stat. The gauge goes back to the replicated value.
---@param name string Stat name
---@return boolean removed false if no provider was registered, or it is another resource's
---@return string? reason
function whip_core:ClearVehicleStatDisplay(name) end

--- Whether a stat's gauge is drawn on a car at all: `fn(entity)` returns false to hide it there (whip_fuel: no
--- fuel gauge on an electric car). Asked as the capsule repaints, for the car this player sits in; the stat itself
--- is untouched. One rule a stat, its setter's; dropped when that resource stops.
---@param name string Stat name
---@param fn fun(entity: number): boolean
---@return boolean registered
---@return string? reason
function whip_core:SetVehicleStatShown(name, fn) end

--- A stat's gauge icon by the car: `fn(entity)` returns the icon to draw on that car, or nil for the stat's own
--- (whip_fuel: the pump with an arrow to the side the filler is on). An icon is a dial glyph ('fuel', 'fuel_left',
--- 'fuel_right', 'turbo', 'nitro', 'coolant', 'hack', 'weapon') or an SVG path in a 24x24 viewBox. Asked for the car
--- this player sits in, at most once a second. One rule a stat, its setter's; dropped when that resource stops.
---@param name string Stat name
---@param fn fun(entity: number): string|nil
---@return boolean registered
---@return string? reason
function whip_core:SetVehicleStatIcon(name, fn) end

--- Every car draws the stat's own icon again. Only the resource that set the rule can clear it.
---@param name string Stat name
---@return boolean removed
---@return string? reason
function whip_core:ClearVehicleStatIcon(name) end

--- Where a named point is on this vehicle now, on the side nearest the player: whip's own ('fuel', 'engine',
--- 'storage', 'mount', 'board') or yours (SetVehiclePointRules). nil when the model has nowhere for it. `fixed`: the
--- point is on that side wherever the player stands (a car's filler); false, it is on the side they are on.
---@param ref number|table A vehicle reference: a vehicleId, or the entity as { entity = veh }
---@param action string
---@return { x: number, y: number, z: number, heading: number, side: 'left'|'right'|'front'|'rear'|nil, fixed: boolean }|nil
function whip_core:GetVehiclePoint(ref, action) end

--- Name a point of your own: rules = { default = { place, ... }, bike = { ... }, boat = ... }, the places to try in
--- order per kind of vehicle. A place: a bone name, a list of bone names, 'entry', 'box', 'box:rear', 'box:front',
--- 'filler' (a car's filler, as whip's 'fuel' finds it).
--- whip's own and another resource's cannot be taken; yours go when your resource stops.
---@param action string
---@param rules table<string, (string|string[])[]>
---@return boolean ok
---@return string|nil why
function whip_core:SetVehiclePointRules(action, rules) end

--- Every car shows the stat's gauge again. Only the resource that set the rule can clear it.
---@param name string Stat name
---@return boolean removed
---@return string? reason
function whip_core:ClearVehicleStatShown(name) end

--- Stop whip storing this vehicle's appearance while something is previewing it.
---
--- A customisation shop applies parts to the entity so the player can see them. Those are not
--- bought yet, and the client reports what a car looks like when the player gets out — so without
--- this, leaving mid-preview stores the preview and the parts are kept for nothing.
---
--- Releasing reports the car immediately, so whatever was skipped is caught up with what is
--- actually true, including the preview coming back off.
---
--- ALWAYS RELEASE IT. A hold left set means that car's appearance is never stored again for this
--- client, which is a quiet way to lose somebody's paintwork. Release on close and on death. If
--- your resource stops or crashes holding one, whip releases it and puts the car's STORED look back,
--- so unpaid preview parts come off rather than being saved.
---
--- The full shop pattern: hold → let the player preview → SetVehicleAppearance for what they paid
--- for → RestoreVehicleAppearance to strip what they did not → release.
---
--- A hold belongs to the resource that took it: another resource cannot take it over or release
--- it (false, reason). Releasing a car nobody holds is true.
---@param vehicleId number|WhipVehicleRef
---@param held boolean  true to hold, false to release
---@return boolean ok
---@return string? reason
function whip_core:HoldVehicleAppearance(vehicleId, held) end

-- ============================================
-- Vehicle Data (client)
-- ============================================
--
-- The read side of the server's vehicle data API: anything json-encodable, attached to a
-- vehicle by key, replicated on the entity. READ ONLY, and that is the point — a client can
-- see what a car carries; only the server can change it.

--- Read one value off a vehicle, exactly as stored — a stored `false` reads as false. No default
--- to fall back to, unlike a stat: nothing declares what data a vehicle OUGHT to carry, so nil
--- means the car does not have it and the caller decides what that means. With no key, everything
--- it carries, as a plain copy ({} when the vehicle is not streamed in or carries nothing).
---@param vehicle number|WhipVehicleRef A vehicleId, or a vehicle reference — an entity is { entity = veh }
---@param key? string Data key
---@return any value
function whip_core:GetVehicleData(vehicle, key) end

--- Be told when a piece of vehicle data changes, on any vehicle streamed to this client.
--- The server exports the SAME NAME, with one difference in the callback: it is told
--- whether the value was CLEARED where this side is told which ENTITY it happened on.
--- Listeners are dropped automatically when the resource that registered them stops, and
--- registering again with the same id replaces rather than stacks.
---
--- `{ table = true }` hands the callback one WhipVehicleChange table with the names the server uses
--- too, and `{ now = true }` also calls it once straight away for every car in range carrying the
--- key. The options may go third, in place of `id`.
---@param key string Data key to watch
---@param callback fun(change: WhipVehicleChange)|fun(vehicleId: number, value: any, old: any, entity: number) The first with `{ table = true }` (the one to prefer), else the second
---@param id string|WhipVehicleListenOpts|nil Defaults to the key
---@param opts WhipVehicleListenOpts|nil
---@return boolean registered
function whip_core:OnVehicleDataChanged(key, callback, id, opts) end

-- ============================================
-- CONTROLLER
-- ============================================
--
-- Whip reads the gamepad in client/controller.lua, because a NUI page cannot: resources are
-- served as full-screen iframes and the Gamepad API is gated behind a permission only the
-- parent document can grant. Panels receive navigation as intent instead — that half is
-- internal plumbing. This is the one piece a satellite has a real use for.

--- Is the player using a gamepad right now?
---
--- Tracks the LAST INPUT the player made, so it flips the moment they put a pad down and touch
--- the keyboard. Use it to decide whether to draw a key letter or a button glyph — not to decide
--- whether a controller is plugged in, which is a different and less useful question.
---@return boolean usingPad
function whip_core:IsControllerActive() end

--- Whip's on-screen keyboard, for a pad player who has to type (a search box, a price, a name): it
--- comes up over any page, theirs or yours, and this WAITS (call it from a thread) for what was typed.
--- A types the lit key, X deletes, Y is a space, LB Caps, LT symbols, RB Done, B leaves it; the right
--- stick moves it round the screen. Over the keys it suggests words to finish the one being typed (RT takes
--- the first); `predict = false` for text that is not words (a plate, a code). While it is up the pad is the
--- keyboard's: a Whip.padScreen leaves it alone by itself, and a resource reading the pad its own way waits for
--- whip_core:keyboard:closed. From a satellite: `Whip.core:OpenKeyboard(opts)`.
---@param opts? { title?: string, value?: string, placeholder?: string, numeric?: boolean, maxLength?: integer, predict?: boolean }
---@return string|nil text  what was typed, or nil when the player left it
---@async
function whip_core:OpenKeyboard(opts) end

--- Put one of your actions on whip's controller buttons. It shows on the pause menu's Controller screen
--- beside whip's own, players move it there, and whip reads the button for you (no loop of yours). Give
--- it a key command (its '-' half runs on the release) or an onPress, with an optional onRelease. `slot`
--- is the button it goes on while that button has nothing on it. It does nothing while a screen or mode
--- has the keys (IsGameInputFree), unless `menus = true`. One owner per id; it goes when your resource
--- stops, so call it from Whip.register.
---@param id string  a word: letters, digits, _ (up to 32)
---@param def { label: string, command?: string, onPress?: function, onRelease?: function, where?: 'car'|'foot', menus?: boolean, slot?: 'dpad_up'|'dpad_down'|'dpad_left'|'dpad_right'|'l3'|'veh_a'|'foot_b'|'lb_a'|'lb_b'|'lb_x'|'lb_y'|'lb_dpad_up'|'lb_dpad_down'|'lb_dpad_left'|'lb_dpad_right', ready?: boolean }
---@return boolean ok
---@return string|nil why
function whip_core:RegisterPadAction(id, def) end

--- Take one of your pad actions off whip's buttons.
---@param id string
---@return boolean ok
---@return string|nil why
function whip_core:RemovePadAction(id) end

--- Can your pad action do anything right now? Not ready, its button is GTA's again (the press reaches the
--- game, and GTA's action there is not held off); it keeps its button.
---@param id string
---@param ready boolean
---@return boolean ok
---@return string|nil why
function whip_core:SetPadActionReady(id, ready) end

--- Which button an action is on now, in this player's layout, for a hint of your own. Any action: yours, another
--- resource's, or whip's own ('radial', 'inventory', 'engine', 'sprint'). Ask when you show the hint: players move
--- actions on the Controller screen. An action whose `slot` was taken starts on no button (F8 says so).
---@param id string
---@return string|nil slot  'lb_y', or nil: on no button
---@return string|nil hint  the button's pictures for UI.ShowText: '{pad:lb}{pad:y}'
---@return string|nil name  'LB+Y'
function whip_core:GetPadActionButton(id) end

--- A mode of your own (placing, aiming a tool, a minigame) confirms the way whip's do: on a keyboard the Interact
--- key (E unless the player moved it in GTA's Key Bindings, as the prompts follow it), A on a pad, never LB + A.
--- Read it every frame of the mode (a press made before the mode started asking does not count), and hold
--- BlockControls(id, { controls = { 26, 45, 140 }, mode = true }) while it runs: mode stands whip's E prompts down,
--- or a prompt in focus takes the same E.
---@return boolean
function whip_core:IsAcceptPressed() end

--- The same, held down (a hold to confirm).
---@return boolean
function whip_core:IsAcceptHeld() end

--- '[E]' on a keyboard (the Interact key's name: '[F]' when the player moved it there), '{pad:a}' (the A button's
--- picture) on a pad: for UI.ShowText.
---@return string
function whip_core:AcceptHint() end

--- A mode's cancel: C on a keyboard, B on a pad, never LB + B. Read it every frame of the mode. It reads through
--- a block, so hold 26 (C's look behind) and 45 / 140 (B's reload and melee) off with BlockControls meanwhile.
---@return boolean
function whip_core:IsCancelPressed() end

--- '[C]' on a keyboard, '{pad:b}' on a pad: for UI.ShowText.
---@return string
function whip_core:CancelHint() end

--- Any other key of your mode, the way Accept and Cancel work: `key` went down this frame on a keyboard, or `button`
--- on a pad, whichever device is in the player's hands (never both: a pad's buttons are keys on a keyboard too), and
--- on a pad never with LB held (LB + a button is whip's combo). Either may be nil: that device has no such key.
--- Controls are GTA's numbers; a pad's are the frontend ones (201 A, 202 B, 203 X, 204 Y, 206 RB, 199 Start, the
--- D-pad 187-190). Read through a block: hold your keys off with BlockControls. Never LB (205).
---@param key number|nil
---@param button number|nil
---@return boolean
function whip_core:IsKeyPressed(key, button) end

--- The same, held down.
---@param key number|nil
---@param button number|nil
---@return boolean
function whip_core:IsKeyHeld(key, button) end

--- That key for UI.ShowText: '[Space]' on a keyboard, the button's picture on a pad ('{pad:x}'). `button` is a
--- picture's name (a, b, x, y, lb, rb, lt, rt, ls, rs, l3, r3, dpad, dpad_up ... dpad_right, view, menu) or a list
--- drawn side by side ({ 'lt', 'rt' }). Either may be nil: '' on that device.
---@param keyText string|nil  'Space'
---@param button string|string[]|nil  'x'
---@return string
function whip_core:KeyHint(keyText, button) end

-- ============================================
-- EMOTES
-- ============================================
--
-- The list of emotes, walk styles and moods is whip_core/shared/emote_list.lua. Players use /e,
-- /walk, /mood and the emote menu on the F1 wheel; these are for a resource that wants to do the same from code.

--- Play an emote on the player by its /e name (e.g. 'drink'). Returns true, or false and why
--- (no such emote, dead, in a vehicle, a progress bar running, a weapon out...). Returns at once;
--- the emote starts a moment later, once its animation has loaded.
---@param cmd string
---@return boolean ok
---@return string? why
function whip_core:PlayEmote(cmd) end

--- Stop the emote the player is doing, and put away its props. Returns whether there was one.
---@return boolean stopped
function whip_core:CancelEmote() end

--- The /e name of the emote the player is doing, or false.
---@return string|false
function whip_core:IsEmoting() end

--- Take over the player's walk for a while (a drunk stagger, an injury limp), or give it back with
--- nil. While any override is set the newest wins; when the last is cleared the walk the player
--- chose with /walk comes back — not the game's default. Keyed by your resource, and cleared when
--- it stops.
---@param clipset string|nil A GTA movement clipset, e.g. 'MOVE_M@DRUNK@VERYDRUNK'
---@return boolean ok
function whip_core:SetWalkOverride(clipset) end

--- The Director runs this player is in now, newest first (never a builder's Test): for a phone's job
--- screen or a HUD. `countdown` is the seconds left on its band's clock, or nil. The local events
--- whip_core:run:joined / :updated / :left / :ended say when it changes (types/events.lua).
---@return { runId: number, scenario: string, name: string, objective: string|nil, countdown: number|nil }[]
function whip_core:GetPlayerScenarioRuns() end

--- What the game's browser can do (FiveM's Chromium 103 or 144), as whip_core's page reported it: a
--- copy. Before the page has reported: false, 'not_detected_yet' — whip_core:nui:capsDetected says when.
---@return WhipEvtNuiCaps|false caps
---@return string|nil err
function whip_core:GetNuiCaps() end

--- What whip_core's screens show right now, for tests and tools (developer mode only, else false, why). The
--- text in reading order, a line per block, and every control that can be pressed: buttons, fields, lists,
--- tabs, switches, and rows with a pointer cursor. Each control has an `id` for PressScreen, its words, its
--- kind ('button', 'row', 'field', 'list', 'tab', 'checkbox', ...), `near` (the heading above it), `row`
--- (for a control of few words, the words of the row it sits in), `state` ({ disabled, on, selected,
--- value }) and `rect` ({ x, y, w, h }, a list, in screen pixels). A keyboard-only menu that marks its rows
--- data-probe-press (/w) can be read and pressed too. Other resources' pages that load whip_core's
--- js/page-tools.js (the phone, Whiplash, the dealership) come as `pages`, by resource, with whatever they show
--- (`pages = false` leaves them out). Waits for the page (up to 4 s).
---
---     local screen = exports.whip_core:ReadScreen({ under = 'Interactions' })
---@param opts? { text?: boolean, controls?: boolean, under?: string, pages?: boolean }  text / controls: false leaves them out; under: only controls under that heading
---@return { view: table, focus: string|nil, text: string[]|nil, controls: table[]|nil, pages: table<string, table>|nil }|false screen
---@return string|nil why
---@async
function whip_core:ReadScreen(opts) end

--- Press one control on whip_core's screens the way a mouse would, at its middle, so the screen's own
--- handlers run (developer mode only). `target`: an id from the last ReadScreen, or its words (exact, then
--- starts with, then contains), narrowed by `near` (the heading above it or its row's words), `kind`, or
--- `index` (the nth match). Several matches and no index: returns `{ ambiguous = { {id, label, near, row} } }`
--- instead of guessing. `opts.text` types into a field instead (`enter` presses Enter after); `opts.choose`
--- picks a list's choice by its words. A screen that changed since the read: its ids are gone, read again.
--- `target.page`: another resource's page (a key of ReadScreen's `pages`), its ids from that page's read.
---
---     exports.whip_core:PressScreen({ label = 'Change', near = 'Who may use it' })
---     exports.whip_core:PressScreen('Search points', { text = 'coffee' })
---     exports.whip_core:PressScreen({ label = 'Messages', page = 'whip_phone' })
---@param target number|string|{ id?: number, label?: string, near?: string, kind?: string, index?: number, page?: string }
---@param opts? { button?: 'left'|'right'|'double', text?: string, enter?: boolean, choose?: string }
---@return { pressed: string, kind?: string, chose?: string, typed?: number, covered?: string }|{ ambiguous: table[] }|false result
---@return string|nil why
---@async
function whip_core:PressScreen(target, opts) end

--- The game's picture, read once now (whip_core's page; nothing is drawn between shots, unlike screenshot-basic).
--- The game alone (whip's interface sits over it, not in it), unless `ui`: then whip_core's page is drawn over it
--- as it looks at that moment (not other resources' pages, such as the phone). Yields until the shot is made (up to
--- 15 s). `frames` (2-24) + `every` (ms, 33-1000): a burst, that many frames one after another in one picture (a
--- grid, each frame numbered with when it was read; 640 wide a frame unless asked; no ui). `upload`: posted to that
--- address (a helper on this PC) as a file in a form instead, and its reply's text comes back in place of the data.
---
---     local png = exports.whip_core:TakeScreenshot({ format = 'png', ui = true })
---@param opts? { format?: 'jpg'|'png'|'webp', quality?: number, width?: number, height?: number, ui?: boolean, frames?: number, every?: number, upload?: { url: string, field?: string } }
---@return string|false data  a data URL (or the upload's reply)
---@return string|nil why
---@async
function whip_core:TakeScreenshot(opts) end

--- How smoothly this game runs over the next `seconds` (1-30, 5), for tools and tests: frames a second on average
--- and over the worst 1% of frames, the median and longest frame, and frames over 33 ms and over 50 ms. Yields.
---@param opts? { seconds?: number }
---@return { seconds: number, frames: number, fps: number, fpsWorst1: number, medianMs: number, worstMs: number, over33: number, over50: number }
function whip_core:MeasureFrames(opts) end

--- What went wrong lately in this game (the server has the same export for its side): errors in the threads, event
--- handlers, NUI callbacks, commands and statebag handlers of whip_core and its satellites, whip_core's own caught
--- errors ('[whip_core...] ERROR / threw / errored' lines), red (^1) warnings, and the errors of whip_core's page and
--- of satellite pages that load js/page-tools.js, which otherwise reach only F8. Not an export's error (its caller
--- gets it). The last 200; one repeated is counted. `since`: only those after an earlier call's `last`.
---@param opts? { since?: number, max?: number }
---@return { entries: { seq: number, at: number, side: string, resource: string, kind: 'error'|'warning'|'page', text: string, count: number }[], last: number, side: string }
function whip_core:GetErrorLog(opts) end

--- Which GTA V this server runs on, as the server says (server.cfg's whip_platform): 'legacy' or 'enhanced'.
---@return 'legacy'|'enhanced'
function whip_core:GetPlatform() end

-- ============================================
-- Dev pages (your page in /w)
-- ============================================

---@class WhipDevPageRow
---@field id string|number|nil     what onSelect is handed; every row but a note needs one
---@field label string|nil         the row's words (a `sep` row has none)
---@field kind 'run'|'toggle'|'open'|'note'|nil  run (default): does something once; toggle: a switch, lit by `active`; open: a chevron, into a level of your own; note: a line to read, never picked
---@field active boolean|nil       a toggle row's switch
---@field desc string|nil          the line under the list while the row is picked
---@field close boolean|nil        picking it shuts the menu after onSelect, as Escape does (/w opens on the page again)
---@field icon WhipGlyph|nil       a glyph drawn before the label (an icon list, an objective's mark)
---@field sep string|nil           a group header instead of a row

---@class WhipDevPageView
---@field title string|nil         the page title (default: the page's label)
---@field back string|nil          a level of your own: the name of the level above; the way back then calls onBack
---@field select string|number|nil the row picked when this level first shows
---@field rows WhipDevPageRow[]

--- Add a page of your own to /w: a row at the end of Panels that, picked, swaps the list for your rows,
--- with the way back at the top (Backspace too). Only with developer mode on, like every /w tool.
--- In Whip.register: whip_core forgets pages when it restarts. Again with the same id replaces it.
--- `rows` is asked after every pick and on RefreshDevPage; `onSelect(rowId)` runs on Enter. Neither may
--- wait: start a thread for anything that does, then RefreshDevPage when it is done.
---@param id string Letters, digits, _ and -; yours only
---@param def { label: string, desc?: string, rows: fun(): (WhipDevPageView|WhipDevPageRow[]), onSelect: fun(rowId: string|number), onBack?: fun(), onOpen?: fun(), onClose?: fun() }
---@return boolean ok
---@return string|nil why
function whip_core:RegisterDevPage(id, def) end

--- Your page's rows changed (a scene loaded, a list arrived): asked for again if it is on screen.
---@param id string
---@return boolean ok
---@return string|nil why
function whip_core:RefreshDevPage(id) end

--- Take your page out of /w. It goes by itself when your resource stops.
---@param id string
---@return boolean ok
---@return string|nil why
function whip_core:RemoveDevPage(id) end

--- A switch of your own among /w's debug tools (shown while its Debug row is on), or the one you added under this id
--- replaced. onToggle(on) runs when it is switched, and with false when Debug or developer mode goes off; answer false
--- to stay off. Call inside Whip.register (whip_core forgets them when it restarts); gone when your resource stops.
---@param id string  letters, digits, _ and -
---@param def { label: string, desc?: string, onToggle: fun(on: boolean): boolean|nil }
---@return boolean ok
---@return string|nil why
function whip_core:RegisterDebugTool(id, def) end

--- Take your debug tool out of /w (it goes by itself when your resource stops). One that is on is not switched off.
---@param id string
---@return boolean ok
---@return string|nil why
function whip_core:RemoveDebugTool(id) end

-- ============================================
-- Item settings (an item's own, changed on /whip → Items)
-- ============================================

--- One of an item's own settings (its definition's `settings`) in force on this game. Nil until
--- whip_core has sent them as the player joins: OnItemSettingChanged runs when they arrive.
---@param item string  the item's key
---@param key string
---@return any value
function whip_core:GetItemSetting(item, key) end

--- fn(value, old, item, key) after one of an item's own settings changes on this game, including
--- the first time it arrives. One per resource for each setting: calling again replaces it.
---@param item string  the item's key
---@param key string
---@param fn fun(value: any, old: any, item: string, key: string)
---@return boolean ok
---@return string|nil why
function whip_core:OnItemSettingChanged(item, key, fn) end

-- ============================================
-- Player settings (each player's own: the pause menu's Server Settings page)
-- ============================================

---@class WhipPlayerSettingDef
---@field key string Yours and unique: letters, digits, dots, dashes, underscores (1-64). Start it with your resource's name
---@field label string The row's name
---@field type 'toggle'|'choice'|'slider'
---@field get fun(): any The value now
---@field set fun(value: any) Keep the player's new value: the page keeps nothing of yours
---@field default any What "Reset to the server's defaults" puts back: a plain value its type takes (required)
---@field group? string 'Controller', 'Vehicles', 'Map & HUD', 'Chat & voice', or a tab of yours. Default 'Other'
---@field help? string One line under the row
---@field options? { value: any, label: string }[] A choice's options (two at least)
---@field min? number A slider's range
---@field max? number
---@field step? number Default 1
---@field unit? string What a slider shows after the number

--- A row's value in force on this PC: the player's choice, else the default. whip_core's own rows too
--- ('dial.speedUnit' is 'mph' or 'kmh'). Nil for a key that is not on the page.
---@param key string
---@return any
function whip_core:GetPlayerSetting(key) end

--- Change one as the page does, for a resource that shows the same setting in its own screen (whip_phone's call
--- volume, from its Settings). The player's own choice on their own PC: any resource may.
---@param key string
---@param value any
---@return boolean ok
---@return string|nil why
function whip_core:SetPlayerSetting(key, value) end
