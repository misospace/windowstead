extends "res://tests/test_case.gd"

# =============================================================================
# Tests for the web (localStorage) load path in GameState (issue #313).
#
# load_game() previously returned the raw parsed dictionary on the web branch
# without running validate_save_schema() or migrate_save(). This test forces
# the web branch by setting use_local_storage=true and stubs the
# JavaScriptBridge-backed _local_storage_reader with a closure so the web
# path can be exercised in a headless test (no browser).
#
# Expected behaviour, matching the desktop path:
#   - schema-invalid localStorage save returns {} (fresh start)
#   - v1 localStorage save is migrated to v2 with spawn_tick backfilled
#   - valid v2 localStorage save is returned as-is
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node
var _stub: Dictionary = {}
var _prior_use_local_storage: bool = false
var _prior_reader: Callable

func run_tests() -> void:
	setup()
	flow_schema_invalid_returns_empty_dict()
	flow_v1_is_migrated_to_v2_with_spawn_tick()
	flow_valid_v2_is_returned_as_is()
	flow_empty_local_storage_falls_back_to_fresh_start()
	flow_missing_resources_backfilled_web()
	flow_missing_harvested_backfilled_web()
	flow_missing_resources_backfilled_desktop()
	flow_missing_harvested_backfilled_desktop()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	# SceneTree-based tests must parent new nodes under the SceneTree's
	# root viewport, not add_child directly (which would only work for Node-
	# based test harnesses).
	root.add_child(_gs)
	# Headless runners have use_local_storage=false, so force the web branch.
	_prior_use_local_storage = _gs.use_local_storage
	_prior_reader = _gs._local_storage_reader
	_gs.use_local_storage = true
	# _local_storage_reader is a Callable hook. The closure captures _stub
	# by reference, so individual tests can swap fixtures without rebuilding
	# the Callable. Deep-copy on read so the load path cannot mutate fixtures.
	_gs._local_storage_reader = func(_key: String) -> Dictionary:
		return _stub.duplicate(true)

func teardown() -> void:
	# Restore production state so any caller-side cleanup sees the desktop
	# path again.
	if _gs and is_instance_valid(_gs):
		_gs.use_local_storage = _prior_use_local_storage
		_gs._local_storage_reader = _prior_reader
		_gs.queue_free()
	_gs = null
	_stub = {}

# 1) Schema-invalid localStorage save returns {} (fresh start).
#    validate_save_schema rejects "workers" when it is not an Array, so
#    this fixture exercises the schema-rejection branch on the web path.
func flow_schema_invalid_returns_empty_dict() -> void:
	_stub = {
		"save_version": 2,
		"tick": 0,
		"colonies": {},
		"workers": "not an array",
	}
	var result: Dictionary = _gs.load_game()
	assert_eq(result, {}, "schema-invalid localStorage save returns {}")

# 2) A v1 localStorage save is migrated to v2 with spawn_tick backfilled.
#    This is the acceptance criterion from issue #313: web saves must run
#    migrate_save() so when SAVE_VERSION bumps, existing web saves load
#    with the new shape instead of crashing on missing keys.
func flow_v1_is_migrated_to_v2_with_spawn_tick() -> void:
	_stub = {
		"save_version": 1,
		"tick": 42,
		"colonies": {},
		"workers": [
			{
				"id": "w1",
				"name": "Alice",
				"colony_id": "c1",
				"pos": {"x": 0, "y": 0},
				"prev_pos": {"x": 0, "y": 0},
				"carrying": {},
				"task": {"kind": "idle"},
				"break_ticks": 0,
			},
		],
	}
	var migrated: Dictionary = _gs.load_game()
	assert_eq(int(migrated.get("save_version", -1)), 2, "v1 localStorage save migrated to v2")
	var workers: Array = migrated.get("workers", [])
	assert_eq(workers.size(), 1, "v1 worker survived web migration")
	var worker: Dictionary = workers[0]
	assert_true(worker.has("spawn_tick"), "v1 worker received spawn_tick during web migration")
	assert_eq(int(worker.get("spawn_tick", -1)), 42, "web-migrated spawn_tick backfilled from tick")

# 3) A valid v2 localStorage save is returned as-is.
func flow_valid_v2_is_returned_as_is() -> void:
	_stub = {
		"save_version": 2,
		"tick": 7,
		"colonies": {},
		"workers": [
			{
				"id": "w2",
				"name": "Bob",
				"colony_id": "c1",
				"pos": {"x": 1, "y": 1},
				"prev_pos": {"x": 1, "y": 1},
				"carrying": {},
				"task": {"kind": "idle"},
				"break_ticks": 0,
				"spawn_tick": 7,
			},
		],
	}
	var ok: Dictionary = _gs.load_game()
	assert_eq(int(ok.get("save_version", -1)), 2, "v2 localStorage save kept at v2")
	assert_eq(int(ok.get("tick", -1)), 7, "v2 tick preserved on web load")

# 4) Empty localStorage falls back to a fresh start.
#    The shared _validate_and_apply_save pipeline treats {} as valid
#    (no fields => no checks fail) and migrate_save stamps save_version.
#    Either {} or {"save_version": ...} is a correct fresh-start save.
func flow_empty_local_storage_falls_back_to_fresh_start() -> void:
	_stub = {}
	var empty: Dictionary = _gs.load_game()
	assert_true(empty is Dictionary, "empty localStorage returns a Dictionary")
	assert_true(
		empty.is_empty() or (empty.has("save_version") and empty.get("save_version") is int),
		"empty localStorage yields a fresh-start save shape"
	)

# 5) A web save missing state.resources is back-filled by migrate_save
#    (issue #378) so the sim doesn't crash on the first tick after load.
#    Previously validate_save_schema only checked resources "if present", so
#    this fixture passed validation and ColonySim.apply_food_upkeep raised on
#    state.resources.get(...) against a missing key.
func flow_missing_resources_backfilled_web() -> void:
	_stub = {
		"save_version": 2,
		"tick": 3,
		"harvested": {"wood": 1, "stone": 0, "food": 0},
		"workers": [],
	}
	var loaded: Dictionary = _gs.load_game()
	assert_true(loaded.has("resources"), "web save missing resources is back-filled")
	assert_true(loaded["resources"] is Dictionary, "back-filled resources is a Dictionary")
	assert_eq(int(loaded["resources"].get("wood", -1)), 0, "back-filled resources.wood defaults to 0")
	assert_eq(int(loaded["resources"].get("stone", -1)), 0, "back-filled resources.stone defaults to 0")
	assert_eq(int(loaded["resources"].get("food", -1)), 0, "back-filled resources.food defaults to 0")
	assert_eq(int(loaded.get("harvested", {}).get("wood", -1)), 1, "existing harvested values preserved")

# 6) A web save missing state.harvested is back-filled the same way.
func flow_missing_harvested_backfilled_web() -> void:
	_stub = {
		"save_version": 2,
		"tick": 3,
		"resources": {"wood": 5, "stone": 2, "food": 1},
		"workers": [],
	}
	var loaded: Dictionary = _gs.load_game()
	assert_true(loaded.has("harvested"), "web save missing harvested is back-filled")
	assert_true(loaded["harvested"] is Dictionary, "back-filled harvested is a Dictionary")
	assert_eq(int(loaded["harvested"].get("wood", -1)), 0, "back-filled harvested.wood defaults to 0")
	assert_eq(int(loaded["harvested"].get("stone", -1)), 0, "back-filled harvested.stone defaults to 0")
	assert_eq(int(loaded["harvested"].get("food", -1)), 0, "back-filled harvested.food defaults to 0")
	assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 5, "existing resources values preserved")

# 7) Desktop (file) branch: a save file missing state.resources is back-filled
#    on load (issue #378). The desktop path shares _validate_and_apply_save
#    with the web path, but the file round-trip is exercised here so a
#    regression in either branch is caught.
func flow_missing_resources_backfilled_desktop() -> void:
	_gs.use_local_storage = false
	var path := "user://test_missing_resources.save"
	_gs.save_game({
		"save_version": 2,
		"tick": 3,
		"harvested": {"wood": 2, "stone": 0, "food": 0},
		"workers": [],
	}, path)
	var loaded: Dictionary = _gs.load_game(path)
	assert_true(loaded.has("resources"), "desktop save missing resources is back-filled")
	assert_true(loaded["resources"] is Dictionary, "desktop back-filled resources is a Dictionary")
	assert_eq(int(loaded["resources"].get("wood", -1)), 0, "desktop back-filled resources.wood defaults to 0")
	assert_eq(int(loaded["resources"].get("food", -1)), 0, "desktop back-filled resources.food defaults to 0")
	assert_eq(int(loaded.get("harvested", {}).get("wood", -1)), 2, "desktop existing harvested values preserved")
	_remove_save_file(path)

# 8) Desktop (file) branch: a save file missing state.harvested is back-filled.
func flow_missing_harvested_backfilled_desktop() -> void:
	_gs.use_local_storage = false
	var path := "user://test_missing_harvested.save"
	_gs.save_game({
		"save_version": 2,
		"tick": 3,
		"resources": {"wood": 4, "stone": 1, "food": 2},
		"workers": [],
	}, path)
	var loaded: Dictionary = _gs.load_game(path)
	assert_true(loaded.has("harvested"), "desktop save missing harvested is back-filled")
	assert_true(loaded["harvested"] is Dictionary, "desktop back-filled harvested is a Dictionary")
	assert_eq(int(loaded["harvested"].get("wood", -1)), 0, "desktop back-filled harvested.wood defaults to 0")
	assert_eq(int(loaded["harvested"].get("food", -1)), 0, "desktop back-filled harvested.food defaults to 0")
	assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 4, "desktop existing resources values preserved")
	_remove_save_file(path)

# Helper: remove a temporary save file written by the desktop-branch tests.
func _remove_save_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
