extends "res://tests/test_case.gd"

## Tests for recruit worker decision logic (issue #149, links to #133, #135).
## Verifies: successful recruit, blocked recruit at cap, name cycling, food impact messaging.

# A completed hut raises the cap to 4 (base 2 + hut bonus 2).
const HUT_BUILD := {"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}

# Real-sim regression helpers (issue #436): the recruit must spawn with a valid
# pos/prev_pos and an empty task so process_tick() can route it into work.
const ColonySim := preload("res://scripts/colony_sim.gd")
const Constants := preload("res://scripts/constants.gd")

const SIM_GRID := 5


func run_tests() -> void:
	# main.gd references the GameState autoload, so it must be load()ed at
	# runtime — preload() compiles before autoloads are registered in --script mode.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()

	test_can_recruit_with_capacity(main)
	test_cannot_recruit_at_cap(main)
	test_recruit_adds_worker_to_state(main)
	test_recruit_cycles_through_names(main)
	test_recruit_unique_names(main)
	test_recruit_with_no_workers_returns_true(main)
	test_food_impact_messaging_for_extra_workers(main)
	test_food_impact_no_upkeep_when_under_threshold(main)
	test_overlay_sprites_keyed_by_identity(main)
	test_overlay_sprites_stable_across_mutation(main)
	test_recruit_runs_clean_ticks_in_real_sim()
	test_recruited_worker_survives_save_roundtrip()
	test_ensure_defaults_heals_malformed_legacy_recruit()
	test_healed_legacy_recruit_survives_ticks()
	test_malformed_legacy_recruit_loads_heals_and_roundtrips()

	main.free()


# ── Test 1: can_recruit returns true when under cap ──
func test_can_recruit_with_capacity(main) -> void:
	print("")
	print("--- recruit with capacity ---")
	var builds = [HUT_BUILD.duplicate(true)]
	_setup_state(main, builds, [{"name": "Jun", "task": {"kind": "", "data": {}}}])
	# Cap is 4 (base 2 + hut bonus 2), 1 worker → can recruit
	assert_true(main.can_recruit_worker(), "can_recruit: returns true when under cap (1/4)")


# ── Test 2: can_recruit returns false at cap ──
func test_cannot_recruit_at_cap(main) -> void:
	print("")
	print("--- blocked at cap ---")
	var builds = []
	_setup_state(main, builds, [
		{"name": "Jun", "task": {"kind": "", "data": {}}},
		{"name": "Mara", "task": {"kind": "", "data": {}}},
	])
	# Cap is 2 (base), 2 workers → cannot recruit
	assert_true(not main.can_recruit_worker(), "can_recruit: returns false at cap (2/2)")


# ── Test 3: recruit adds worker to state ──
func test_recruit_adds_worker_to_state(main) -> void:
	print("")
	print("--- recruit adds worker ---")
	var builds = []
	_setup_state(main, builds, [
		{"name": "Jun", "task": {"kind": "", "data": {}}},
	])
	assert_true(main.can_recruit_worker(), "precondition: can recruit")
	var initial_count: int = main.state.workers.size()
	main.recruit_worker()
	assert_eq(main.state.workers.size(), initial_count + 1, "recruit: state workers count increases by 1")


# ── Test 4: name cycling through WORKER_NAMES ──
func test_recruit_cycles_through_names(main) -> void:
	print("")
	print("--- name cycling ---")
	# Base cap is only 2, so a completed hut is needed for the third recruit to succeed.
	var builds = [HUT_BUILD.duplicate(true)]
	_setup_state(main, builds, [])
	# First recruit should pick index 0 ("Jun")
	main.recruit_worker()
	assert_eq(main.state.workers[0].name, "Jun", "first recruit gets first name 'Jun'")

	# Second recruit should pick index 1 ("Mara")
	main.recruit_worker()
	assert_eq(main.state.workers[1].name, "Mara", "second recruit gets second name 'Mara'")

	# Third recruit should pick index 2 ("Kai")
	main.recruit_worker()
	assert_eq(main.state.workers[2].name, "Kai", "third recruit gets third name 'Kai'")


# ── Test 5: unique names across all workers ──
func test_recruit_unique_names(main) -> void:
	print("")
	print("--- unique worker names ---")
	var builds = [HUT_BUILD.duplicate(true)]
	_setup_state(main, builds, [])
	# Cap is 4 (base 2 + hut bonus 2), recruit all 4 workers
	for i in range(4):
		main.recruit_worker()
	var names: Array[String] = []
	for w in main.state.workers:
		names.append(w.name)
	var seen := {}
	for n in names:
		seen[n] = true
	assert_eq(seen.size(), names.size(), "all recruited workers have unique names")


# ── Test 6: can_recruit returns true when no workers exist yet ──
func test_recruit_with_no_workers_returns_true(main) -> void:
	print("")
	print("--- recruit with no workers ---")
	var builds = []
	_setup_state(main, builds, [])
	assert_true(main.can_recruit_worker(), "can_recruit: returns true when no workers (empty state)")


# ── Test 7: food impact messaging for extra workers ──
func test_food_impact_messaging_for_extra_workers(main) -> void:
	print("")
	print("--- food impact messaging ---")
	# A hut raises the cap to 4 so the third recruit (the first extra worker) succeeds.
	var builds = [HUT_BUILD.duplicate(true)]
	_setup_state(main, builds, [
		{"name": "Jun", "task": {"kind": "", "data": {}}},
		{"name": "Mara", "task": {"kind": "", "data": {}}},
	])
	# At base threshold (2 workers), extra = 0, so recruiting the 3rd triggers food cost
	main.recruit_worker()
	var events: Array = main.state.get("events", [])
	var found_food_msg := false
	for evt in events:
		if "Food impact" in str(evt.get("text", "")):
			found_food_msg = true
	assert_true(found_food_msg, "recruit extra worker: food impact message logged")


# ── Test 8: no food cost when under base threshold ──
func test_food_impact_no_upkeep_when_under_threshold(main) -> void:
	print("")
	print("--- no food cost under threshold ---")
	var builds = []
	_setup_state(main, builds, [])
	main.recruit_worker()
	var events: Array = main.state.get("events", [])
	var found_food_msg := false
	for evt in events:
		if "Food impact" in str(evt.get("text", "")):
			found_food_msg = true
	assert_true(not found_food_msg, "recruit under threshold: no food impact message")


# ── Helper ──
func _setup_state(main, builds: Array, workers: Array) -> void:
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": workers,
		"tiles": [],
		"builds": builds,
		"next_build_id": int(builds.size()) + 1,
		"reserved_resources": {},
		"events": [],
	}

# ── Overlay rendering keyed by stable identity, not name or index ──
func test_overlay_sprites_keyed_by_identity(main: Node) -> void:
	print("")
	print("--- overlay sprites keyed by stable identity ---")
	# Set up 12 workers with duplicate names (as happens at cap with 5 huts).
	var worker_names := ["Jun", "Mara", "Kai", "Sora", "Ren", "Aya", "Leo", "Nia", "Taro", "Yuki"]
	# Workers 10 and 11 duplicate names from index 0 and 1.
	var workers := []
	for i in range(12):
		workers.append(_make_worker(worker_names[i % worker_names.size()], i, i))
	_setup_state(main, [], workers)
	_setup_overlay_ui(main)

	# Call render_worker_overlay.
	main.render_worker_overlay()

	# Verify: each worker has its own sprite node, keyed by name + spawn_tick.
	var overlay_nodes: Dictionary = main.worker_overlay_nodes
	assert_eq(overlay_nodes.size(), 12, "overlay_sprites_keyed_by_identity: 12 sprite nodes")

	# Verify keys are the stable identity (name:spawn_tick), not bare names or indices.
	for i in range(12):
		var key := _make_worker(worker_names[i % worker_names.size()], i, i)
		var expected_key: String = main.worker_identity(key)
		assert_true(overlay_nodes.has(expected_key), "overlay_sprites_keyed_by_identity: has key \"" + expected_key + "\"")

	# Verify that duplicate-name workers have distinct sprites.
	# Worker 0 (Jun, spawn 0) and worker 10 (Jun, spawn 10) should each have their own node.
	var sprite_0: TextureRect = overlay_nodes.get(main.worker_identity(workers[0]), null)
	var sprite_10: TextureRect = overlay_nodes.get(main.worker_identity(workers[10]), null)
	assert_true(sprite_0 != null, "overlay_sprites_keyed_by_identity: sprite for Jun@0 exists")
	assert_true(sprite_10 != null, "overlay_sprites_keyed_by_identity: sprite for Jun@10 exists")
	assert_true(sprite_0 != sprite_10, "overlay_sprites_keyed_by_identity: Jun@0 and Jun@10 have distinct sprites")

	# Verify cache entries are also keyed by identity.
	for i in range(12):
		var key: String = main.worker_identity(workers[i])
		assert_true(main._overlay_sprite_cache_frame.has(key), "cache has frame for key \"" + key + "\"")
		assert_true(main._overlay_sprite_cache_carrying.has(key), "cache has carrying for key \"" + key + "\"")


# ── Regression: sprite mapping is stable across worker-list mutations (#364) ──
func test_overlay_sprites_stable_across_mutation(main: Node) -> void:
	print("")
	print("--- overlay sprites stable across worker-list mutation ---")
	# Three workers with distinct identities.
	var workers := [
		_make_worker("Jun", 0, 0),
		_make_worker("Mara", 1, 1),
		_make_worker("Kai", 2, 2),
	]
	_setup_state(main, [], workers)
	_setup_overlay_ui(main)

	main.render_worker_overlay()

	# Record the sprite node each worker currently owns.
	var jun_sprite: TextureRect = main.worker_overlay_nodes[main.worker_identity(workers[0])]
	var mara_sprite: TextureRect = main.worker_overlay_nodes[main.worker_identity(workers[1])]
	var kai_sprite: TextureRect = main.worker_overlay_nodes[main.worker_identity(workers[2])]
	assert_true(jun_sprite != null and mara_sprite != null and kai_sprite != null,
		"stable_mutation: all three sprites exist before mutation")

	# Insert a new worker at the FRONT of the roster. Under the old index-keyed
	# scheme this would shift every surviving index and reassign Jun's sprite to
	# the newcomer, Mara's to Jun, and Kai's to Mara.
	var newcomer := _make_worker("Sora", 0, 99)
	var mutated: Array = [newcomer]
	for w in workers:
		mutated.append(w)
	_setup_state(main, [], mutated)

	main.render_worker_overlay()

	# Each surviving worker must still own the exact same sprite node it had
	# before the insertion — no sprite was replaced or reassigned.
	assert_true(main.worker_overlay_nodes[main.worker_identity(workers[0])] == jun_sprite,
		"stable_mutation: Jun keeps its sprite after a front insertion")
	assert_true(main.worker_overlay_nodes[main.worker_identity(workers[1])] == mara_sprite,
		"stable_mutation: Mara keeps her sprite after a front insertion")
	assert_true(main.worker_overlay_nodes[main.worker_identity(workers[2])] == kai_sprite,
		"stable_mutation: Kai keeps his sprite after a front insertion")

	# The newcomer got its own new sprite, distinct from all survivors.
	var sora_sprite: TextureRect = main.worker_overlay_nodes[main.worker_identity(newcomer)]
	assert_true(sora_sprite != null, "stable_mutation: newcomer Sora got a sprite")
	assert_true(sora_sprite != jun_sprite and sora_sprite != mara_sprite and sora_sprite != kai_sprite,
		"stable_mutation: newcomer sprite is distinct from survivors")
	assert_eq(main.worker_overlay_nodes.size(), 4, "stable_mutation: 4 sprite nodes after insertion")

	# Now remove the newcomer (front) again; survivors must still be intact and
	# the newcomer's sprite must be freed (no longer tracked).
	_setup_state(main, [], workers)
	main.render_worker_overlay()
	assert_true(main.worker_overlay_nodes[main.worker_identity(workers[0])] == jun_sprite,
		"stable_mutation: Jun keeps its sprite after the newcomer is removed")
	assert_true(main.worker_overlay_nodes[main.worker_identity(workers[1])] == mara_sprite,
		"stable_mutation: Mara keeps her sprite after the newcomer is removed")
	assert_true(main.worker_overlay_nodes[main.worker_identity(workers[2])] == kai_sprite,
		"stable_mutation: Kai keeps his sprite after the newcomer is removed")
	assert_true(not main.worker_overlay_nodes.has(main.worker_identity(newcomer)),
		"stable_mutation: newcomer sprite freed after removal")
	assert_eq(main.worker_overlay_nodes.size(), 3, "stable_mutation: back to 3 sprite nodes")


# ── Helpers for the overlay tests ──
func _make_worker(name: String, x: int, spawn_tick: int) -> Dictionary:
	return {
		"name": name,
		"pos": Vector2i(x, 0),
		"prev_pos": Vector2i(x, 0),
		"state": "idle",
		"task": {},
		"carry_limit": 1,
		"spawn_tick": spawn_tick,
		"assigned_to": "",
		"assigned_resource": "",
		"assigned_target": "",
		"assigned_action": "",
		"assigned_pos": Vector2i(0, 0),
		"assigned_carry": 0,
	}


func _setup_overlay_ui(main: Node) -> void:
	# Set up minimal UI so render_worker_overlay doesn't early-return.
	var world_grid := GridContainer.new()
	world_grid.name = "WorldGrid"
	main.add_child(world_grid)
	main.world_grid = world_grid
	var world_overlay := Control.new()
	world_overlay.name = "WorldOverlay"
	main.add_child(world_overlay)
	main.world_overlay = world_overlay
	main.tile_views.append({
		"panel": Control.new(),
		"tile_map": TileMap.new(),
		"tile_size": Vector2i(32, 32),
	})
	main.tile_size = Vector2i(32, 32)


# ── Real-sim regression tests (issue #436) ───────────────────────────────────

# Minimal real ColonySim following tests/test_tick_integration.gd's _new_sim()
# pattern: real 5x5 ground grid, a stockpile at (0,0), a completed hut so the
# cap allows recruiting, one seeded worker with a valid pos/prev_pos, and food
# in the treasury. Two wood-bearing trees give both workers real gather work.
func _new_populated_sim() -> ColonySim:
	var sim := ColonySim.new()
	sim.grid_w = SIM_GRID
	sim.grid_h = SIM_GRID
	sim.stockpile_pos = Vector2i(0, 0)
	sim.priority_order = ["build", "haul", "gather"] as Array[String]
	sim.rng.seed = 1234
	var tiles: Array = []
	for i in SIM_GRID * SIM_GRID:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	sim.state = {
		"tick": 0,
		"resources": {"wood": 0, "stone": 0, "food": 10},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{
			"name": Constants.WORKER_NAMES[0],
			"pos": {"x": 2, "y": 2},
			"prev_pos": {"x": 2, "y": 2},
			"carrying": {},
			"task": {},
			"break_ticks": 0,
		}],
		"tiles": tiles,
		"builds": [{
			"id": 1, "kind": "hut", "pos": {"x": 4, "y": 4},
			"complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0,
		}],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}
	sim.set_tile(Vector2i(3, 0), {"kind": "tree", "amount": 2, "resource": "wood", "build_kind": ""})
	sim.set_tile(Vector2i(1, 3), {"kind": "tree", "amount": 2, "resource": "wood", "build_kind": ""})
	sim.ensure_defaults()
	return sim


# Regression for issue #436: recruit_worker() used to append a worker with no
# pos/prev_pos and a non-empty placeholder task, so its first tick raised
# "Invalid access to property or key 'target'" in step_worker. The recruit must
# now spawn at the stockpile with an empty task and survive real ticks.
func test_recruit_runs_clean_ticks_in_real_sim() -> void:
	print("")
	print("--- recruit worker runs clean in a real populated sim (issue #436) ---")
	var sim := _new_populated_sim()
	assert_true(sim.can_recruit_worker(), "real sim precondition: can recruit (1 worker, hut cap 4)")
	sim.recruit_worker()
	assert_eq(sim.state.workers.size(), 2, "real sim: recruit added a second worker")
	var recruit: Dictionary = sim.state.workers[1]
	assert_true(recruit.get("pos") is Dictionary, "real sim: recruit pos is a dictionary")
	assert_true(recruit.get("prev_pos") is Dictionary, "real sim: recruit prev_pos is a dictionary")
	assert_eq(recruit.get("pos", {}), {"x": 0, "y": 0}, "real sim: recruit spawns at the stockpile")
	assert_eq(recruit.get("prev_pos", {}), {"x": 0, "y": 0}, "real sim: recruit prev_pos starts at the stockpile")
	assert_true(recruit.get("task", {}).is_empty(), "real sim: recruit starts with an empty task")

	# Drive 10 real ticks; the recruit must pick a task, move in-bounds, and
	# never raise (SCRIPT ERROR output is the CI grep — a raise here aborts
	# the whole suite, which the summary line exposes).
	var busy_ticks := 0
	var busy_task_had_target := true
	var always_in_bounds := true
	var ever_moved := false
	for i in 10:
		sim.process_tick()
		if not recruit.task.is_empty():
			busy_ticks += 1
			if not recruit.task.has("target"):
				busy_task_had_target = false
		var p := ColonySim.data_to_vec(recruit.pos)
		if p.x < 0 or p.y < 0 or p.x >= SIM_GRID or p.y >= SIM_GRID:
			always_in_bounds = false
		if p != sim.stockpile_pos:
			ever_moved = true
	assert_true(busy_ticks > 0, "real sim: recruit picked a real task within 10 ticks")
	assert_true(busy_task_had_target, "real sim: recruit task carried a target when busy")
	assert_true(always_in_bounds, "real sim: recruit pos stayed in-bounds across 10 ticks")
	assert_true(ever_moved, "real sim: recruit left the stockpile to work")


# The post-recruit state must be a loadable save: schema-valid, migratable,
# and the recruit must still be present (by name) after the round-trip.
func test_recruited_worker_survives_save_roundtrip() -> void:
	print("")
	print("--- recruited worker survives a save round-trip (issue #436) ---")
	var sim := _new_populated_sim()
	sim.recruit_worker()
	var recruit_name := String(sim.state.workers[1].get("name", ""))
	assert_false(recruit_name.is_empty(), "roundtrip precondition: recruit has a name")
	# Autoloads are unavailable in --script mode; load GameState like
	# test_save_schema_events.gd does.
	var gs = load("res://scripts/game_state.gd").new()
	var data: Dictionary = sim.state.duplicate(true)
	var result: Dictionary = gs.validate_save_schema(data)
	assert_true(result.valid, "roundtrip: post-recruit state passes validate_save_schema")
	var migrated: Dictionary = gs.migrate_save(data)
	assert_false(migrated.is_empty(), "roundtrip: migrate_save preserves the state")
	var migrated_result: Dictionary = gs.validate_save_schema(migrated)
	assert_true(migrated_result.valid, "roundtrip: migrated state still passes validation")
	var survivor: Dictionary = {}
	for w in migrated.get("workers", []):
		if String(w.get("name", "")) == recruit_name:
			survivor = w
	assert_false(survivor.is_empty(), "roundtrip: recruit worker present after migration by name")
	assert_true(survivor.get("pos", {}) is Dictionary, "roundtrip: surviving recruit keeps a dictionary pos")
	assert_true(survivor.get("task", {}) is Dictionary, "roundtrip: surviving recruit keeps a dictionary task")
	gs.free()


# ── Legacy heal regression tests (issue #437) ────────────────────────────────

# Pre-#436 releases persisted recruits with no pos/prev_pos and the
# placeholder task {"kind": "", "data": {}}. validate_save_schema lets that
# shape through (missing pos falls back to the {} default in
# scripts/game_state.gd) and migrate_save never repairs it, so the load path
# (main.load_saved_game → state assignment → sim.ensure_defaults) must heal
# it before the next process_tick() hits the missing task target.
func _malformed_legacy_recruit(worker_name: String) -> Dictionary:
	return {
		"name": worker_name,
		"carrying": {},
		"task": {"kind": "", "data": {}},
		"break_ticks": 0,
	}


func test_ensure_defaults_heals_malformed_legacy_recruit() -> void:
	print("")
	print("--- ensure_defaults heals malformed legacy recruits (issue #437) ---")
	var sim := _new_populated_sim()
	var healthy_before: Dictionary = sim.state.workers[0].duplicate(true)
	sim.state.workers.append(_malformed_legacy_recruit("Legacy"))
	# A worker with a valid pos but missing prev_pos keeps its pos and only
	# gains prev_pos at the stockpile.
	sim.state.workers.append({
		"name": "HalfHealed",
		"pos": {"x": 1, "y": 4},
		"carrying": {},
		"task": {},
		"break_ticks": 0,
	})
	# Schema-valid shapes the {} validator defaults let through: an empty pos
	# dict (data_to_vec raises on missing x/y) and an absent task key
	# (process_tick dot-accesses worker.task).
	sim.state.workers.append({
		"name": "EmptyPos",
		"pos": {},
		"prev_pos": {},
		"carrying": {},
		"task": {},
		"break_ticks": 0,
	})
	sim.state.workers.append({
		"name": "NoTask",
		"pos": {"x": 3, "y": 3},
		"prev_pos": {"x": 3, "y": 3},
		"carrying": {},
		"break_ticks": 0,
	})
	sim.dirty = false
	sim.ensure_defaults()
	var healed: Dictionary = sim.state.workers[1]
	assert_eq(healed.get("pos", {}), {"x": 0, "y": 0}, "heal: malformed recruit gains stockpile pos")
	assert_eq(healed.get("prev_pos", {}), {"x": 0, "y": 0}, "heal: malformed recruit gains stockpile prev_pos")
	assert_eq(healed.get("task"), {}, "heal: placeholder task normalizes to the empty idle task")
	assert_true(sim.dirty, "heal: healing marks the save dirty so the repair persists")
	assert_eq(sim.state.workers[0], healthy_before, "heal: already-valid worker stays untouched")
	var partial: Dictionary = sim.state.workers[2]
	assert_eq(partial.get("pos", {}), {"x": 1, "y": 4}, "heal: existing pos is preserved")
	assert_eq(partial.get("prev_pos", {}), {"x": 0, "y": 0}, "heal: missing prev_pos fills at the stockpile")
	var empty_pos: Dictionary = sim.state.workers[3]
	assert_eq(empty_pos.get("pos", {}), {"x": 0, "y": 0}, "heal: empty pos dict heals to the stockpile")
	assert_eq(empty_pos.get("prev_pos", {}), {"x": 0, "y": 0}, "heal: empty prev_pos dict heals to the stockpile")
	var no_task: Dictionary = sim.state.workers[4]
	assert_true(no_task.has("task"), "heal: absent task key is backfilled")
	assert_eq(no_task.get("task"), {}, "heal: absent task key backfills to the empty idle task")
	assert_eq(no_task.get("pos", {}), {"x": 3, "y": 3}, "heal: absent-task worker keeps its pos")


# Without the heal the first process_tick() raises "Invalid access to
# property or key 'target'" in step_worker (suite-aborting SCRIPT ERROR);
# with it the healed recruit works like a post-#436 recruit.
func test_healed_legacy_recruit_survives_ticks() -> void:
	print("")
	print("--- healed legacy recruit runs clean ticks (issue #437) ---")
	var sim := _new_populated_sim()
	sim.state.workers.append(_malformed_legacy_recruit("Legacy"))
	sim.ensure_defaults()
	var legacy: Dictionary = sim.state.workers[1]
	var busy_ticks := 0
	var ever_moved := false
	var always_in_bounds := true
	for i in 10:
		sim.process_tick()
		if not legacy.task.is_empty():
			busy_ticks += 1
		var p := ColonySim.data_to_vec(legacy.pos)
		if p.x < 0 or p.y < 0 or p.x >= SIM_GRID or p.y >= SIM_GRID:
			always_in_bounds = false
		if p != sim.stockpile_pos:
			ever_moved = true
	assert_true(busy_ticks > 0, "heal+ticks: healed recruit picks real work within 10 ticks")
	assert_true(always_in_bounds, "heal+ticks: healed recruit stays in-bounds across 10 ticks")
	assert_true(ever_moved, "heal+ticks: healed recruit leaves the stockpile to work")


# Mirrors the full load pipeline: validate + migrate leave the malformed
# shape intact (documented by the assertions below), ensure_defaults heals
# it, and the healed shape round-trips through a second save generation.
func test_malformed_legacy_recruit_loads_heals_and_roundtrips() -> void:
	print("")
	print("--- malformed legacy recruit load + heal + round-trip (issue #437) ---")
	var sim := _new_populated_sim()
	sim.state.workers.append(_malformed_legacy_recruit("Legacy"))
	var gs = load("res://scripts/game_state.gd").new()
	var loaded: Dictionary = sim.state.duplicate(true)
	var schema: Dictionary = gs.validate_save_schema(loaded)
	assert_true(schema.valid, "load: malformed legacy recruit passes validate_save_schema")
	var migrated: Dictionary = gs.migrate_save(loaded)
	assert_false(migrated.is_empty(), "load: migrate_save accepts the legacy save")
	var pre_heal_legacy: Dictionary = {}
	for w in migrated.get("workers", []):
		if String(w.get("name", "")) == "Legacy":
			pre_heal_legacy = w
	assert_false(pre_heal_legacy.is_empty(), "load: malformed recruit survives migrate_save")
	assert_false(pre_heal_legacy.has("pos"), "load: migrate_save intentionally leaves the heal to ensure_defaults")
	# main.load_saved_game assignment point, then the ensure_defaults call.
	sim.state = migrated
	sim.ensure_defaults()
	var survivor: Dictionary = {}
	for w in sim.state.get("workers", []):
		if String(w.get("name", "")) == "Legacy":
			survivor = w
	assert_false(survivor.is_empty(), "heal: legacy recruit survives load + ensure_defaults")
	assert_eq(survivor.get("pos", {}), {"x": 0, "y": 0}, "heal: survivor gains stockpile pos on load")
	assert_eq(survivor.get("prev_pos", {}), {"x": 0, "y": 0}, "heal: survivor gains stockpile prev_pos on load")
	assert_eq(survivor.get("task"), {}, "heal: survivor placeholder becomes the empty idle task")
	var roundtrip: Dictionary = (sim.state as Dictionary).duplicate(true)
	var rt_schema: Dictionary = gs.validate_save_schema(roundtrip)
	assert_true(rt_schema.valid, "round-trip: healed state passes validate_save_schema")
	var rt_migrated: Dictionary = gs.migrate_save(roundtrip)
	var rt_legacy: Dictionary = {}
	for w in rt_migrated.get("workers", []):
		if String(w.get("name", "")) == "Legacy":
			rt_legacy = w
	assert_eq(rt_legacy.get("pos", {}), {"x": 0, "y": 0}, "round-trip: healed pos persists through migrate_save")
	assert_eq(rt_legacy.get("task"), {}, "round-trip: healed idle task persists through migrate_save")
	gs.free()
