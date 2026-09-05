extends "res://tests/test_case.gd"

## Tests for recruit worker decision logic (issue #149, links to #133, #135).
## Verifies: successful recruit, blocked recruit at cap, name cycling, food impact messaging.

# A completed hut raises the cap to 4 (base 2 + hut bonus 2).
const HUT_BUILD := {"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}


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
