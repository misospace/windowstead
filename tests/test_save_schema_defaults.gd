extends "res://tests/test_case.gd"

# =============================================================================
# Regression tests for issue #483: a schema-valid save that omits workers,
# builds, or next_build_id must be healed before the sim runs.
#
# validate_save_schema() only validates the fields that are present, so a
# hand-edited or partially-corrupt save could pass validation and still omit
# the three keys the runtime dot-accesses unconditionally. The colony then
# crashed on the first tick (state.workers / state.builds) or on the first
# build placement (state.next_build_id).
#
# The healing lives in ColonySim.backfill_colony_state(), which both
# migrate_save() (the load path) and ensure_defaults() (bootstrap and direct
# state assignment) call.
#
# Covered:
# 1. migrate_save() back-fills each missing key
# 2. next_build_id is derived from the highest persisted build id
# 3. a counter that is not ahead of every build id is bumped
# 4. existing values are preserved
# 5. ensure_defaults() heals the same keys
# 6. the issue's repro save loads through main.gd and ticks
# 7. queue_structure_at() hands out monotonically increasing build ids
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")
const ColonySim := preload("res://scripts/colony_sim.gd")
const LayoutMath := preload("res://scripts/layout_math.gd")

const SETTINGS_PATH := "user://windowstead.settings"

var _gs: Node
# Untyped on purpose: main.gd is loaded at runtime (the GameState autoload is
# unavailable at parse time in --script mode), so the flows call into it
# dynamically.
var _main_scene
var _previous_save := ""
var _previous_save_existed := false
var _previous_settings := ""
var _previous_settings_existed := false


func run_tests() -> void:
	await setup()
	flow_missing_workers_healed_on_load()
	flow_missing_builds_healed_on_load()
	flow_missing_next_build_id_healed_on_load()
	flow_next_build_id_derived_from_builds()
	flow_next_build_id_equal_to_highest_build_id()
	flow_stale_next_build_id_bumped()
	flow_existing_colony_values_preserved()
	flow_ensure_defaults_heals_missing_keys()
	flow_repro_save_loads_and_ticks()
	flow_queue_structure_assigns_increasing_ids()
	teardown()


func setup() -> void:
	# Leave the player's data directory as the suite found it: the load path
	# below writes the shared save file, and loading a save re-persists the
	# dock settings.
	_previous_save = _read_text(GameState.SAVE_PATH)
	_previous_save_existed = FileAccess.file_exists(GameState.SAVE_PATH)
	_previous_settings = _read_text(SETTINGS_PATH)
	_previous_settings_existed = FileAccess.file_exists(SETTINGS_PATH)

	_gs = GameState.new()
	# SceneTree-based: parent under the root viewport (issue #281 harness note).
	root.add_child(_gs)
	# The real main scene: the load path and the build placement both render
	# into dock UI nodes, so the flows need the scene, not a bare script.
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main_scene = scene.instantiate()
	root.add_child(_main_scene)
	await process_frame
	# The colony tick timer would persist the running game over the fixture
	# save the load attempts below install.
	_main_scene.tick_timer.stop()


func teardown() -> void:
	_restore_user_data(GameState.SAVE_PATH, _previous_save, _previous_save_existed)
	_restore_user_data(SETTINGS_PATH, _previous_settings, _previous_settings_existed)
	if _main_scene and is_instance_valid(_main_scene):
		_main_scene.free()
	_main_scene = null
	if _gs and is_instance_valid(_gs):
		_gs.queue_free()
	_gs = null


# A minimal save that passes every other schema check, so only the keys under
# test can be the missing ones.
func _base_save() -> Dictionary:
	return {
		"save_version": 2,
		"tick": 3,
		"resources": {"wood": 1, "stone": 0, "food": 0},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
	}


# A well-formed build entry (the schema checks id/kind/pos/complete).
func _build(id: int) -> Dictionary:
	return {"id": id, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": false}


# ── 1) migrate_save() back-fills each missing key ─────────────────────────────

func flow_missing_workers_healed_on_load() -> void:
	print("\n--- missing workers: healed on load (issue #483) ---")
	var data := _base_save()
	data.erase("workers")
	var schema: Dictionary = _gs.validate_save_schema(data)
	assert_true(schema.valid, "missing workers: schema accepts the save", str(schema.get("reason", "")))
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "missing workers: migrate_save accepts the save")
	assert_true(migrated.has("workers"), "missing workers: migrate_save back-fills workers")
	assert_eq(migrated.get("workers", null), [], "missing workers: healed value is an empty array")


func flow_missing_builds_healed_on_load() -> void:
	print("\n--- missing builds: healed on load (issue #483) ---")
	var data := _base_save()
	data.erase("builds")
	var schema: Dictionary = _gs.validate_save_schema(data)
	assert_true(schema.valid, "missing builds: schema accepts the save", str(schema.get("reason", "")))
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "missing builds: migrate_save accepts the save")
	assert_true(migrated.has("builds"), "missing builds: migrate_save back-fills builds")
	assert_eq(migrated.get("builds", null), [], "missing builds: healed value is an empty array")


func flow_missing_next_build_id_healed_on_load() -> void:
	print("\n--- missing next_build_id: healed on load (issue #483) ---")
	var data := _base_save()
	data.erase("next_build_id")
	var schema: Dictionary = _gs.validate_save_schema(data)
	assert_true(schema.valid, "missing next_build_id: schema accepts the save", str(schema.get("reason", "")))
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "missing next_build_id: migrate_save accepts the save")
	assert_true(migrated.has("next_build_id"), "missing next_build_id: migrate_save back-fills the counter")
	assert_eq(int(migrated.get("next_build_id", -1)), 1, "missing next_build_id: healed counter starts at 1")


# ── 2) The counter is derived from the highest persisted build id ──────────────

func flow_next_build_id_derived_from_builds() -> void:
	print("\n--- next_build_id derived from existing builds (issue #483) ---")
	var data := _base_save()
	data.erase("next_build_id")
	data["builds"] = [_build(7)]
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "derived counter: migrate_save accepts the save")
	assert_eq(int(migrated.get("next_build_id", -1)), 8, "derived counter: highest build id + 1")


# ── 3) A counter that is not ahead of every build id is bumped ────────────────

func flow_next_build_id_equal_to_highest_build_id() -> void:
	print("\n--- next_build_id equal to the highest build id (issue #483) ---")
	# The boundary case: the counter sits exactly on an existing id, so the
	# next placement would re-use it unless the counter is bumped.
	var data := _base_save()
	data["builds"] = [_build(7)]
	data["next_build_id"] = 7
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "equal counter: migrate_save accepts the save")
	assert_eq(int(migrated.get("next_build_id", -1)), 8, "equal counter: bumped past the highest build id")


func flow_stale_next_build_id_bumped() -> void:
	print("\n--- stale next_build_id bumped (issue #483) ---")
	var data := _base_save()
	data["builds"] = [_build(7)]
	data["next_build_id"] = 2
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "stale counter: migrate_save accepts the save")
	assert_eq(int(migrated.get("next_build_id", -1)), 8, "stale counter: bumped past the highest build id")


# ── 4) Existing values are preserved ──────────────────────────────────────────

func flow_existing_colony_values_preserved() -> void:
	print("\n--- existing colony values preserved (issue #483) ---")
	var worker := {"name": "Jun", "pos": {"x": 1, "y": 1}, "prev_pos": {"x": 1, "y": 1}, "carrying": {}, "task": {}, "break_ticks": 0}
	var data := _base_save()
	data["workers"] = [worker]
	data["builds"] = [_build(3)]
	data["next_build_id"] = 5
	var migrated: Dictionary = _gs.migrate_save(data)
	assert_false(migrated.is_empty(), "preserved values: migrate_save accepts the save")
	assert_eq((migrated.get("workers", []) as Array).size(), 1, "preserved values: worker list kept")
	assert_eq((migrated.get("builds", []) as Array).size(), 1, "preserved values: build list kept")
	assert_eq(int(migrated.get("next_build_id", -1)), 5, "preserved values: counter kept")


# ── 5) ensure_defaults() heals the same keys (bootstrap / direct assignment) ───

func flow_ensure_defaults_heals_missing_keys() -> void:
	print("\n--- ensure_defaults heals missing keys (issue #483) ---")
	var sim := ColonySim.new()
	sim.state = {
		"tick": 0,
		"resources": {"wood": 1, "stone": 0, "food": 0},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
	}
	sim.ensure_defaults()
	assert_true(sim.state.has("workers"), "ensure_defaults: workers back-filled")
	assert_eq(sim.state.get("workers", null), [], "ensure_defaults: healed workers is an empty array")
	assert_true(sim.state.has("builds"), "ensure_defaults: builds back-filled")
	assert_eq(sim.state.get("builds", null), [], "ensure_defaults: healed builds is an empty array")
	assert_true(sim.state.has("next_build_id"), "ensure_defaults: next_build_id back-filled")
	assert_eq(int(sim.state.get("next_build_id", -1)), 1, "ensure_defaults: healed counter starts at 1")
	# The sim dot-accesses workers/builds on every tick — a healed state ticks.
	sim.process_tick()
	assert_eq(int(sim.state.get("tick", -1)), 1, "ensure_defaults: healed colony ticks")


# ── 6) The issue's repro save loads through main.gd and ticks ─────────────────

# The repro from issue #483: a v2 save with valid tiles, resources, and
# harvested, but no workers, builds, or next_build_id. It carries one active
# reward so the tick's reward pass is observable: the reward only counts down
# when the tick runs to the end, past the worker loop that used to crash.
func _repro_save() -> Dictionary:
	var tiles := []
	for i in LayoutMath.BOTTOM_GRID_W * LayoutMath.BOTTOM_GRID_H:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	return {
		"save_version": 2,
		"tick": 3,
		"dock_anchor": "bottom",
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"active_rewards": [{
			"type": "haul_speed",
			"remaining": 5,
			"duration": 30,
			"trickle_ticks": 0,
			"label": "haul speed +50%",
		}],
		"tiles": tiles,
	}


func flow_repro_save_loads_and_ticks() -> void:
	print("\n--- repro save loads and ticks (issue #483) ---")
	var main = _main_scene
	_write_save_file(_repro_save())
	main.load_saved_game()
	assert_true(main.state.has("workers"), "repro save: workers back-filled on load")
	assert_eq(main.state.get("workers", null), [], "repro save: healed workers is an empty array")
	assert_true(main.state.has("builds"), "repro save: builds back-filled on load")
	assert_eq(main.state.get("builds", null), [], "repro save: healed builds is an empty array")
	assert_true(main.state.has("next_build_id"), "repro save: next_build_id back-filled on load")
	assert_eq(int(main.state.get("next_build_id", -1)), 1, "repro save: healed counter starts at 1")
	# The colony keeps running: the sim dot-accesses workers/builds every tick.
	main.sim.process_tick()
	assert_eq(int(main.state.get("tick", -1)), 4, "repro save: colony ticks after load")
	# The reward counts down in the tick's last phase, so it only shortens
	# when the whole tick ran — a tick that died on the missing worker list
	# would leave it untouched.
	var rewards: Array = main.state.get("active_rewards", [])
	assert_eq(rewards.size(), 1, "repro save: the active reward survives the tick")
	assert_eq(int((rewards[0] as Dictionary).get("remaining", -1)), 4, "repro save: the tick ran to the end")


# ── 7) queue_structure_at() hands out monotonically increasing ids ────────────

func flow_queue_structure_assigns_increasing_ids() -> void:
	print("\n--- queue_structure_at assigns increasing ids (issue #483) ---")
	var main = _main_scene
	# Load the repro save again so the flow stands on its own: a healed
	# counter (1) with no builds, so the first placement takes id 1.
	_write_save_file(_repro_save())
	main.load_saved_game()
	main.queue_structure_at(Vector2i(2, 2), "hut")
	main.queue_structure_at(Vector2i(3, 3), "hut")
	var builds: Array = main.state.get("builds", [])
	assert_eq(builds.size(), 2, "queue_structure_at: both builds queued")
	assert_eq(int(builds[0].get("id", -1)), 1, "queue_structure_at: first build id is 1")
	assert_eq(int(builds[1].get("id", -1)), 2, "queue_structure_at: second build id is 2")
	assert_eq(int(main.state.get("next_build_id", -1)), 3, "queue_structure_at: counter advanced past both ids")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _write_save_file(data: Dictionary) -> void:
	_write_text(GameState.SAVE_PATH, JSON.stringify(data))


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
func _restore_user_data(path: String, previous: String, existed: bool) -> void:
	if existed:
		_write_text(path, previous)
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
