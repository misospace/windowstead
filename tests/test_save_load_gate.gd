extends "res://tests/test_case.gd"
## Issue #466: a save the compatibility gate rejects must leave the player's
## configuration alone.
##
## load_saved_game() used to apply the save's dock anchor BEFORE the gate ran.
## Applying the anchor persists a new dock_anchor to disk, reconfigures the
## window (anchor geometry, tile size, world grid columns), and rebuilds the
## world grid — so a corrupt or cross-layout save silently reconfigured the
## player's dock as a side effect of a load that never happened.
##
## The suite drives the real main.tscn scene so the assertions read the
## production side effects: the live settings dictionary, the live grid dims,
## the anchor family, the world grid's tile panels and columns, and the
## persisted user://windowstead.settings file.
##
## game_state.gd is loaded at runtime (not preloaded): a preload() compiles
## before the GameState autoload is registered in --script mode.

const SAVE_PATH := "user://windowstead.save"
const SETTINGS_PATH := "user://windowstead.settings"
## LayoutMath's two anchor-family grid sizes: 32x5 bottom, 10x24 vertical.
const BOTTOM_TILES := 32 * 5
const VERTICAL_TILES := 10 * 24
const PREVIOUS_TICK := 7
const SAVE_TICK := 42

var game_state: Node
var main: Node


func run_tests() -> void:
	var previous_settings := _read_text(SETTINGS_PATH)
	var previous_settings_existed := FileAccess.file_exists(SETTINGS_PATH)

	game_state = load("res://scripts/game_state.gd").new()
	root.add_child(game_state)
	await process_frame

	# Deterministic starting point: a bottom-docked session with a colony
	# already running, so a rejected load has something left to damage.
	game_state.save_settings({"dock_anchor": "bottom", "tick_speed": 0})
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# The colony tick timer would persist the running game over the fixture
	# save the load attempts below.
	main.tick_timer.stop()
	_start_previous_colony()

	await _rejected_save_leaves_configuration_alone()
	await _compatible_save_still_switches_anchor()

	_restore_user_data(previous_settings, previous_settings_existed)
	main.queue_free()
	game_state.queue_free()


## The running colony the load attempts below must not disturb.
func _start_previous_colony() -> void:
	main.state = {
		"tick": PREVIOUS_TICK,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [{"tick": 0, "text": "Colony already running."}],
		"dock_anchor": "bottom",
	}
	main.game_active = true
	main.build_world()


## A save the gate rejects must not touch settings, window geometry, or the
## world grid — and must leave the running colony alone.
func _rejected_save_leaves_configuration_alone() -> void:
	print("")
	print("--- rejected save leaves the configuration alone (issue #466) ---")
	var before := _snapshot()

	# Case 1: a vertical-layout save whose worker sits outside that layout.
	# The save is well-formed for the layout it names, but its worker
	# position is out of bounds, so the gate must reject it.
	game_state.save_game(_save_with({"dock_anchor": "left", "worker_pos": {"x": 40, "y": 20}}))
	main.load_saved_game()
	await process_frame
	_assert_configuration_untouched(before, "out-of-bounds worker")

	# Case 2: a vertical-layout save carrying a bottom-sized tile grid.
	# The gate must measure the save against the layout its own anchor names,
	# not against the grid the current session happens to run.
	game_state.save_game(_save_with({"dock_anchor": "left", "tile_count": BOTTOM_TILES}))
	main.load_saved_game()
	await process_frame
	_assert_configuration_untouched(before, "tile count does not match the save's anchor")

	# Case 3: a save whose build position is not a complete vector. Nothing
	# downstream repairs a build position, so the gate rejects the save
	# instead of loading a build the sim cannot place.
	game_state.save_game(_save_with({
		"dock_anchor": "left",
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 3}, "complete": false}],
	}))
	main.load_saved_game()
	await process_frame
	_assert_configuration_untouched(before, "malformed build position")

	assert_true(_latest_event_mentions("incompatible"),
		"rejected save: the failure is surfaced to the player")


## The happy path is unchanged: a compatible save still switches the dock
## anchor and rebuilds the world.
func _compatible_save_still_switches_anchor() -> void:
	print("")
	print("--- compatible save still switches the anchor (issue #466) ---")
	game_state.save_game(_save_with({"dock_anchor": "left", "worker_pos": {"x": 2, "y": 9}}))
	main.load_saved_game()
	await process_frame

	assert_eq(String(main.settings.get("dock_anchor", "")), "left",
		"compatible save: dock_anchor switched to the save's anchor")
	assert_eq(main.grid_w, 10, "compatible save: grid width follows the new anchor")
	assert_eq(main.grid_h, 24, "compatible save: grid height follows the new anchor")
	assert_eq(String(main.anchor_family), "vertical",
		"compatible save: anchor family switched to vertical")
	assert_eq(main.world_grid.get_child_count(), VERTICAL_TILES,
		"compatible save: world grid rebuilt for the new layout")
	assert_eq(main.world_grid.columns, 10,
		"compatible save: world grid columns follow the new layout")
	assert_true(_settings_file_contains("left"),
		"compatible save: the new anchor is persisted")
	assert_eq(int(main.state.get("tick", -1)), SAVE_TICK,
		"compatible save: the saved colony replaces the running one")


func _assert_configuration_untouched(before: Dictionary, label: String) -> void:
	assert_eq(String(main.settings.get("dock_anchor", "")), before["anchor"],
		"%s: dock_anchor setting unchanged" % label)
	assert_eq(int(main.grid_w), int(before["grid_w"]),
		"%s: grid width unchanged" % label)
	assert_eq(int(main.grid_h), int(before["grid_h"]),
		"%s: grid height unchanged" % label)
	assert_eq(String(main.anchor_family), String(before["family"]),
		"%s: anchor family unchanged" % label)
	assert_eq(main.world_grid.get_child_count(), int(before["panels"]),
		"%s: world grid not rebuilt" % label)
	assert_eq(main.world_grid.columns, int(before["columns"]),
		"%s: world grid layout not reconfigured" % label)
	assert_eq(_read_text(SETTINGS_PATH), String(before["settings_file"]),
		"%s: persisted settings unchanged" % label)
	assert_eq(int(main.state.get("tick", -1)), int(before["tick"]),
		"%s: the running colony is left alone" % label)
	assert_true(main.game_active, "%s: the running colony stays active" % label)


func _snapshot() -> Dictionary:
	return {
		"anchor": String(main.settings.get("dock_anchor", "")),
		"grid_w": main.grid_w,
		"grid_h": main.grid_h,
		"family": String(main.anchor_family),
		"panels": main.world_grid.get_child_count(),
		"columns": main.world_grid.columns,
		"settings_file": _read_text(SETTINGS_PATH),
		"tick": int(main.state.get("tick", -1)),
	}


## A save shaped like a real one: schema-valid for the layout its own anchor
## names, so GameState.load_game() hands it to the compatibility gate.
func _save_with(options: Dictionary) -> Dictionary:
	var anchor := String(options.get("dock_anchor", "bottom"))
	var tile_count := int(options.get("tile_count", VERTICAL_TILES))
	return {
		"tick": SAVE_TICK,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{
			"name": "Jun",
			"pos": options.get("worker_pos", {"x": 2, "y": 9}),
			"prev_pos": options.get("worker_pos", {"x": 2, "y": 9}),
			"carrying": {},
			"task": {},
			"break_ticks": 0,
			"spawn_tick": 0,
		}],
		"tiles": _tiles(tile_count),
		"builds": options.get("builds", []),
		"next_build_id": 1,
		"events": [],
		"dock_anchor": anchor,
		"save_version": 2,
	}


func _tiles(count: int) -> Array:
	var tiles: Array = []
	for i in count:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	return tiles


func _latest_event_mentions(needle: String) -> bool:
	var events: Array = main.state.get("events", [])
	if events.is_empty():
		return false
	var latest: Dictionary = events[0]
	return String(latest.get("text", "")).find(needle) != -1


func _settings_file_contains(needle: String) -> bool:
	return _read_text(SETTINGS_PATH).find(needle) != -1


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## Leave the player's data directory as the suite found it.
func _restore_user_data(previous_settings: String, previous_settings_existed: bool) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if previous_settings_existed:
		_write_text(SETTINGS_PATH, previous_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
