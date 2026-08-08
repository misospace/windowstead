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
