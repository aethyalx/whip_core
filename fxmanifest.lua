fx_version 'cerulean'
game 'gta5'

name 'whip_core'
author 'Whippy'
description 'Custom FiveM framework — Beta 1.0.1'
version '1.0.1'   -- the start-up banner reads it
-- Where its releases are: the update check (server/updates.lua) compares the latest one with `version`.
whip_updates 'WHIPFX/whip_core'

-- First on both sides: while whip_core loads, GetInvokingResource() names no caller.
shared_script 'shared/invoker.lua'
shared_script 'shared/error_tap.lua'

shared_script 'config.lua'
-- Names a mistake in config.lua by its line and stops the start until it is fixed.
shared_script 'shared/config_guard.lua'

-- /whip settings over config.lua's defaults: before every file that reads a setting at load.
shared_script 'shared/config_schema.lua'
shared_script 'shared/settings.lua'
shared_script 'shared/inventory_shape.lua'

shared_script 'shared/statebags.lua'
shared_script 'shared/vehicle_logos.lua'
shared_script 'shared/emote_list.lua'

-- Before every server and client file: registries on both sides are built on it at file scope.
shared_script 'shared/registry.lua'

-- Before anything that does a platform's thing.
shared_script 'shared/platform.lua'

shared_script 'shared/assets_index.lua'
shared_script 'shared/assets.lua'
shared_script 'shared/events.lua'
shared_script 'shared/hands.lua'
shared_script 'shared/body_state.lua'
shared_script 'shared/skillcheck.lua'

-- shapes.lua first: property_math.lua prepares shapes with it.
shared_script 'shared/shapes.lua'
shared_script 'shared/property_math.lua'
shared_script 'shared/garage_bay.lua'
shared_script 'shared/spot_shape.lua'
shared_script 'shared/bubbles.lua'
shared_script 'shared/gta_weapons.lua'
shared_script 'shared/gta_weapon_models.lua'
shared_script 'shared/weapon_catalog.lua'
shared_script 'shared/tattoo_list.lua'
shared_script 'shared/hair_fades.lua'
shared_script 'shared/interact_spec.lua'
shared_script 'shared/cam_math.lua'
shared_script 'shared/cam_sequence.lua'
shared_script 'shared/take_track.lua'
-- Before any Director file on either side.
shared_script 'shared/director/kit.lua'
shared_script 'shared/director/steps.lua'
shared_script 'shared/director/things.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    -- Right after oxmysql's lib: no MySQL await call may wait forever.
    'server/db_guard.lua',
    -- First: every file after it may add a CoreStop step at file scope.
    'server/lifecycle.lua',
    'server/db_health.lua',
    'server/migrations.lua',
    'server/testseams.lua',

    -- Security layer first: SecureEvent is a global made by secure.lua, so no file before it can use it at file scope.
    'server/callback.lua',
    'server/sanitize.lua',
    'server/secure.lua',
    -- After secure.lua, before any module that writes a player statebag at file scope.
    'server/sentinel.lua',

    'server/player.lua',
    'server/skillcheck.lua',
    'server/timed_action.lua',
    'server/ask.lua',
    'server/character.lua',
    'server/portraits.lua',
    'server/permissions.lua',
    'server/settings.lua',
    'server/camera_sequences.lua',
    'server/item_holds.lua',
    'server/held_props.lua',
    'server/clock.lua',
    'server/audience.lua',
    'server/task_seq.lua',
    'server/npcs.lua',
    'server/actors.lua',
    'server/vision.lua',
    'server/bank.lua',
    'server/money.lua',
    -- Before inventory.lua: it checks config.lua's items with these as it loads.
    'server/item_options.lua',
    'server/item_settings.lua',
    'server/retired_items.lua',
    'server/inventory.lua',
    'server/activity_log.lua',  -- before every file whose handlers call Log
    'server/stores.lua',
    'server/ground.lua',
    'server/containers.lua',
    -- Before server/items/*.lua: wallet and duffle_bag call RegisterPanelItem.
    'server/panels.lua',
    -- The built-in list first: prop_catalog.lua seeds its table from it.
    'server/prop_catalog_seed.lua',
    'server/prop_catalog_seed_world.lua',
    'server/prop_catalog.lua',
    -- No JavaScript on the server: any makes FXServer enter whip_core every server frame.
    'server/clothing_pictures.lua',
    'server/garages.lua',
    'server/garage_spots.lua',
    'server/properties.lua',
    'server/property_objects.lua',
    'server/property_stashes.lua',
    'server/spawn_choices.lua',
    'server/screenshot.lua',
    'server/property_themes.lua',
    -- Validate first: the packs call it.
    'server/property_validate.lua',
    'server/property_packs.lua',
    'server/property_export.lua',
    'server/property_admin.lua',
    'server/vehicles.lua',
    'server/vehicle_stats.lua',
    'server/vehicle_damage.lua',
    'server/vehicle_data.lua',
    'server/vehicle_claim.lua',
    'server/money_holds.lua',
    'server/pending_gives.lua',
    -- The catalog first: the list fills it at file scope.
    'server/vehicle_catalog.lua',
    'server/vehicle_catalog_list.lua',
    'server/jobs.lua',
    'server/atm.lua',
    'server/shops.lua',
    'server/prices.lua',
    'server/zones.lua',
    'server/time.lua',
    'server/stats.lua',
    'server/voice_system.lua',
    'server/emotes.lua',
    'server/bubbles.lua',
    'server/doors.lua',
    'server/commands.lua',
    'server/helpers.lua',
    'server/hands.lua',
    'server/devtools_base.lua',
    'server/inventory_sync.lua',
    -- Before player_lifecycle.lua, whose login sync rides it.
    'server/themes.lua',
    'server/requirements.lua',
    'server/runtime_points.lua',
    'server/conversations.lua',
    'server/player_text.lua',
    'server/blips.lua',
    'server/player_flags.lua',
    'server/prop_sets.lua',
    -- The Director: each file uses the ones before it as it loads, and core.lua makes the table they add to.
    'server/director/core.lua',
    'server/director/fields.lua',
    'server/director/effects.lua',
    'server/director/nodes.lua',
    'server/director/doc.lua',
    'server/director/tasks.lua',
    'server/director/refs.lua',
    'server/director/routes.lua',
    'server/director/graph.lua',
    'server/director/runtime.lua',
    'server/director/band.lua',
    'server/director/spots.lua',
    'server/director/talk.lua',
    'server/director/nodes_core.lua',
    'server/director/nodes_world.lua',
    'server/director/nodes_heist.lua',
    'server/director/nodes_talk.lua',
    'server/director/nodes_props.lua',
    'server/director/nodes_tasks.lua',
    'server/director/guards.lua',
    'server/director/nodes_cars.lua',
    'server/director/nodes_basics.lua',
    'server/director/nodes_goals.lua',
    'server/director/nodes_conditions.lua',
    'server/director/nodes_npcs.lua',
    'server/director/nodes_script.lua',
    'server/director/nodes_weapons.lua',
    'server/director/lore.lua',
    'server/director/lore_voice.lua',
    'server/director/speakers.lua',
    'server/director/store.lua',
    'server/director/takes.lua',
    'server/director/packs.lua',
    'server/director/main.lua',
    'server/director/commands.lua',
    'server/director/npctests.lua',
    'server/director/hub.lua',
    -- After main.lua: it adds to the Director table at load.
    'server/director/api.lua',
    -- After api.lua (Director.checkVar) and main.lua (Director.onLife).
    'server/director/cards_api.lua',
    -- After cards_api.lua and tasks.lua.
    'server/director/satellite_api.lua',
    -- After api.lua (Director.sendEvent) and main.lua.
    'server/director/testing.lua',
    'server/director/live.lua',
    -- The Systems Creator: after every module its cards and hooks call (Money, Inventory, Vehicles, Zones, Character, Permissions, Stores, Registry).
    'shared/systems/formula.lua',
    'shared/systems/cards.lua',
    'shared/systems/compile.lua',
    'shared/systems/walk.lua',
    'shared/systems/cards_core.lua',
    'server/systems/store.lua',
    'server/systems/test_items.lua',
    'server/systems/cards_server.lua',
    'server/systems/cards_people.lua',
    'server/systems/cards_world.lua',
    'server/systems/cards_screen.lua',
    'server/systems/cards_others.lua',
    'server/systems/cards_npcs.lua',
    'server/systems/cards_places.lua',
    'server/systems/cards_make.lua',
    'server/systems/main.lua',
    'server/systems/hub.lua',
    'server/player_lifecycle.lua',
    'server/satellites_back.lua',
    'server/events_inventory.lua',
    'server/events_containers.lua',
    'server/events_vehicles.lua',
    'server/seats.lua',
    'server/events_misc.lua',
    'server/appearance_store.lua',   -- a look kept by a store (GetAppearanceChanges, SetPlayerAppearance)
    'server/shop_counters.lua',
    'server/shop_talk.lua',
    -- After RegisterItem, RegisterUseHandler (inventory.lua) and RegisterPanelItem (panels.lua), which items call at file scope.
    'server/items/*.lua',
    'server/devtools.lua',
    'server/bank_admin.lua',
    'server/dev_players.lua',
    'server/dev_ground.lua',
    'server/property_probe.lua',
    -- After devtools_base.lua: it shares DevTools.viewers.
    'server/vehicle_manager.lua',
    'server/object_viewer.lua',
    -- After devtools_base.lua (DevTools.onModeChange), before setup_report.lua (its lines).
    'server/updates.lua',
    'server/setup_report.lua',
    'lib/cost.lua',
    'server/whipcost.lua',
}

client_scripts {
    -- First: profiling.lua wraps the handler registrations, so it only sees registrations made after it.
    'client/profiling.lua',
    -- Early, so every file below can time its loops.
    'lib/cost.lua',
    'client/callback.lua',
    -- Early, so every file below can use DevCommand.
    'client/dev_commands.lua',
    'client/clock.lua',
    -- Early, so its hello goes out as this game starts.
    'client/settings.lua',
    'client/item_settings.lua',
    -- Early: the files below declare their rows at file scope.
    'client/player_prefs.lua',
    -- Leaf used by player.lua, spawn.lua and charselect.lua.
    'client/curtain.lua',
    -- Leaves that every screen below uses.
    'client/focus.lua',
    'client/ped_hold.lua',
    'client/body_state.lua',
    'client/streaming.lua',
    'client/player.lua',
    'client/spawn.lua',
    'client/arrival_list.lua',
    'client/arrival.lua',
    'client/stats.lua',
    'client/voice_system.lua',
    'client/hud.lua',
    'client/clean_screen.lua',
    'client/hud_skin.lua',
    'client/minimap.lua',
    'client/radar_debug.lua',   -- after hud.lua, whose seams it reads
    'client/aim_dot.lua',
    'client/controller.lua',
    -- After controller.lua, whose ControllerDebugState it reads.
    'client/controller_debug.lua',
    'client/keyboard.lua',
    'client/appearance.lua',
    'client/portrait.lua',
    'client/inventory.lua',
    -- After inventory.lua: it sets Inventory.freeHands at file scope.
    'client/hands.lua',
    -- Before every file that calls DuiPage.new at file scope.
    'client/dui_page.lua',
    -- Before interact_world.lua and garage_helper.lua, which bind WorldQuad.draw at file scope.
    'client/world_quad.lua',
    'client/interact_style.lua',
    -- First of the three: the two renderers sign into its InteractRenderers at file scope.
    'client/interact.lua',
    'client/interact_nui.lua',
    'client/interact_world.lua',
    -- Typing a value into a prompt (Interactions.beginInput): after dui_page.lua (DuiPage.new at file scope).
    'client/prompt_typing.lua',
    'client/bubbles.lua',
    'client/vision.lua',
    'client/ped_outfit.lua',
    'client/npcs.lua',
    'client/actors.lua',
    'client/director_tasks.lua',
    'client/escort.lua',
    'client/zones.lua',
    'client/doors.lua',
    'client/ground.lua',
    'client/placing.lua',
    'client/interior_rooms.lua',
    'client/viewport_room.lua',
    'client/freecam.lua',
    -- Before containers.lua and shops.lua, which register streams at file scope.
    'client/streamprops.lua',
    'client/containers.lua',
    'client/vehicle_properties.lua',
    -- Before vehicles.lua, whose tick calls Seats.tick.
    'client/seats.lua',
    'client/vehicles.lua',
    -- The next files call the Vehicles table that vehicles.lua defines.
    'client/vehicle_points.lua',
    'client/vehicle_prompts.lua',
    'client/vehicle_stats.lua',
    'client/vehicle_data.lua',
    'client/vehicle_damage.lua',
    'client/vehicle_handling.lua',
    'client/vehicle_hud.lua',
    'client/garage_spots.lua',
    -- After world_quad.lua.
    'client/garage_helper.lua',
    -- After garage_helper.lua and world_quad.lua.
    'client/director_spots.lua',
    -- After world_quad.lua.
    'client/director_talk.lua',
    -- Before atm.lua: it calls PropPrompts.define at file scope.
    'client/prop_prompts.lua',
    'client/atm.lua',
    'client/property_listing.lua',
    -- After streamprops.lua (addStream at file scope).
    'client/properties.lua',
    'client/property_objects.lua',
    'client/furnish_view.lua',
    'client/highlight.lua',
    -- After world_quad.lua: it binds WorldQuad.draw at file scope.
    'client/world_marks.lua',
    -- Before property_furnish.lua, which plugs it in as it loads (FurnishBuilder.attach).
    'client/furnish_builder.lua',
    'client/property_furnish.lua',
    'client/property_themes.lua',
    'client/jobs.lua',
    'client/shops.lua',
    'client/time.lua',
    -- Before ui.lua, whose progress bar holds its controls through it.
    'client/controls.lua',
    'client/ui.lua',
    'client/nui_caps.lua',
    'client/screen_probe.lua',
    'client/screenshot.lua',
    'client/composer.lua',
    'client/radial.lua',
    'client/aim_box.lua',
    'client/interact_press.lua',
    -- After every engine it mounts into (interact, vehicle_prompts, radial) and the helpers it reads.
    'client/actions.lua',
    'client/runtime_points.lua',
    'client/conversations.lua',
    'client/director.lua',
    'client/director_npcdebug.lua',
    'client/director_weapons.lua',
    'client/director_live.lua',
    'client/live_world.lua',
    'client/director_takes.lua',
    'client/take_copies.lua',
    'client/director_preview.lua',
    'client/director_buttons.lua',
    'client/director_runs.lua',
    'client/director_standon.lua',
    'client/lore_reactions.lua',
    'client/systems_editor.lua',
    'client/blips.lua',
    'client/prop_sets.lua',
    'client/emotes.lua',
    'client/emote_place.lua',   -- after emotes.lua: it adds to the Emotes table
    'client/death.lua',
    'client/ov_effects.lua',
    'client/weapon_guard.lua',
    'client/action_mode.lua',   -- after controls.lua (ControlBlocks at file scope)
    'client/pad.lua',
    'client/idle_cam.lua',
    'client/pause.lua',         -- after controls.lua (ControlBlocks at file scope)
    'client/game_settings.lua', -- the pause menu's Settings page: GTA's settings menu under it
    'client/cam_shots.lua',
    'client/camera.lua',
    'client/drive_cam.lua',     -- after camera.lua
    'client/charselect.lua',
    'client/landing.lua',
    'client/main.lua',
    'client/items/*.lua',
    'tools/core.lua',
    -- After core.lua; before tools/panel_sections/*.lua, which register into the PanelSections table this file makes.
    'tools/whip_panel.lua',
    'tools/panel_sections/*.lua',
    'tools/noclip.lua',
    'tools/player.lua',
    'tools/show_players.lua',
    'tools/ground_debug.lua',
    'tools/debug_cards.lua',
    'tools/mousedebug.lua',
    'tools/propcheck.lua',
    'tools/nativecost.lua',
    'tools/whipcost.lua',
    'tools/vehpoints.lua',
    'tools/coords.lua',
    'tools/camera.lua',
    'tools/door_leaf.lua',
    'tools/zones.lua',
    'tools/prop.lua',
    -- After client/interact.lua.
    'tools/objectviewer.lua',
    'tools/ov_panel.lua',
    'tools/ov_move.lua',
    'tools/hand_edit.lua',
    -- Before every tool that shows it.
    'tools/editor_hud.lua',
    -- Before the wizard, which calls it at runtime.
    'tools/interior.lua',
    -- After editor_hud.lua, which every mode shows.
    'tools/property_editor.lua',
    -- After property_editor.lua and interior.lua.
    'tools/property_wizard.lua',
    'tools/property_scale.lua',
    'tools/property_probe.lua',

    -- Last: it announces whip_core:onReady, which has to mean every file above has run.
    'client/ready.lua',
}

ui_page 'html/index.html'

-- Registers the for-sale sign post props so CreateObject can spawn them.
data_file 'DLC_ITYP_REQUEST' 'stream/forsale_signs/whip_forsale_signs.ytyp'

-- NUI callbacks answer only whip_core's own page: otherwise another resource's web view on an admin's client could call them.
nui_callback_strict_mode 'true'

files {
    'html/index.html',
    -- A glob: the file does not exist until the first change, and a plain missing name warns at every start.
    'settings*.json',
    -- Globs, so a new file cannot 404 in game. html/js/package.json is deliberately not matched.
    'html/css/*.css',
    'html/js/*.js',
    -- DUI pages: served, not mounted, so they can @font-face the fonts below.
    'html/interact3d/*.html',
    'html/bubble3d/*.html',
    'html/vision3d/*.html',
    'html/debug3d/*.html',
    'html/js/core/*.js',
    'html/js/wp/*.js',
    'html/js/director/*.js',
    'html/js/systems/*.js',
    'html/keyboard/*.json',
    'html/keyboard/*.txt',
    'html/js/vehicle_hud/*.js',
    'html/js/vehicle_hud/fonts/*.woff2',
    'html/js/vehicle_hud/vendor/three.module.min.js',
    'html/js/map3d/*.js',
    -- Read as data by client/vehicle_hud.lua (LoadResourceFile), never run as a script.
    'data/rpm_by_model.lua',
    'data/dash_skins.lua',
    -- Read by client/interact_press.lua and client/ground.lua (LoadResourceFile).
    'data/interact_press.json',
    'data/interact_press_arm.json',
    'data/interact_grab_lowcover.json',
    'html/fonts/*.woff2',
    'html/img/manufacturers/*.png',
    'html/img/items/*.webp',   -- used over the PNG of the same item
    'html/img/items/*.png',
    'html/img/jobs/*.png',
    'html/img/pad/*.svg',
    -- Only the "no picture" stand-in: the other vehicle pictures live in the media packs.
    'html/img/vehicles/*.png',
    -- Not loaded by whip_core: satellites include it. Listed so clients can fetch it from this resource.
    'lib/satellite.lua',
}

lua54 'yes'

dependency 'oxmysql'
