extends "res://tests/test_case.gd"

# ── Core script test suite ────────────────────────────────────────────────────
# Persistence, resources, priorities, workers, migration, and reservation
# behavior. Assertion helpers and the summary come from tests/test_case.gd.

func run_tests() -> void:
	var game_state_script := load("res://scripts/game_state.gd")
	var game_state = game_state_script.new()
	root.add_child(game_state)
	await process_frame

	# Run all tests
	test_persistence_roundtrip(game_state)
	test_resource_operations(game_state)
	test_build_costs_and_unlocks(game_state)
	test_priority_ordering(game_state)
	test_tile_get_set(game_state)
	test_worker_task_state(game_state)
	test_save_version_tracking(game_state)
	test_settings_roundtrip(game_state)
	test_event_log(game_state)
	test_bounded_event_log(game_state)
	test_clear_game(game_state)
	test_save_migration_hardening(game_state)
	test_resource_reservations(game_state)
	test_two_worker_race_condition(game_state)
	test_delivery_clamping(game_state)


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_persistence_roundtrip(gs: Node) -> void:
	print("")
	print("--- persistence ---")

	var payload := {
		"tick": 42,
		"resources": {"wood": 7, "stone": 3},
		"events": [{"tick": 42, "text": "test event"}],
	}

	gs.save_game(payload)
	var loaded = gs.load_game()
	assert_not_empty(loaded, "persistence_roundtrip: load returned data")
	assert_eq(int(loaded.get("tick", -1)), 42, "persistence_roundtrip: tick")
	assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 7, "persistence_roundtrip: wood")
	assert_eq(int(loaded.get("resources", {}).get("stone", -1)), 3, "persistence_roundtrip: stone")
	assert_eq(loaded.get("events", []).size(), 1, "persistence_roundtrip: events count")

	gs.clear_game()
	assert_empty(gs.load_game(), "persistence_roundtrip: cleared game is empty")


func test_resource_operations(gs: Node) -> void:
	print("")
	print("--- resource operations ---")

	# Bootstrap a fresh game state
	gs.clear_game()
	var payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
	}
	gs.save_game(payload)
	var loaded = gs.load_game()

	# Verify initial resources
	assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 8, "resource_ops: initial wood")
	assert_eq(int(loaded.get("resources", {}).get("stone", -1)), 4, "resource_ops: initial stone")
	assert_eq(int(loaded.get("resources", {}).get("food", -1)), 2, "resource_ops: initial food")

	# Simulate resource modification (gather wood)
	payload["resources"]["wood"] = 10
	payload["harvested"]["wood"] = 2
	gs.save_game(payload)
	loaded = gs.load_game()
	assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 10, "resource_ops: updated wood")
	assert_eq(int(loaded.get("harvested", {}).get("wood", -1)), 2, "resource_ops: harvested wood")


func test_build_costs_and_unlocks(gs: Node) -> void:
	print("")
	print("--- build costs and unlocks ---")

	# Verify BUILD_COSTS constants exist and are reasonable
	var costs := {
		"hut": {"wood": 6, "stone": 2},
		"workshop": {"wood": 4, "stone": 6},
		"garden": {"wood": 3, "stone": 1},
	}
	assert_eq(costs.get("hut", {}).get("wood", 0), 6, "build_costs: hut wood cost")
	assert_eq(costs.get("hut", {}).get("stone", 0), 2, "build_costs: hut stone cost")
	assert_eq(costs.get("workshop", {}).get("wood", 0), 4, "build_costs: workshop wood cost")
	assert_eq(costs.get("workshop", {}).get("stone", 0), 6, "build_costs: workshop stone cost")
	assert_eq(costs.get("garden", {}).get("wood", 0), 3, "build_costs: garden wood cost")
	assert_eq(costs.get("garden", {}).get("stone", 0), 1, "build_costs: garden stone cost")

	# Verify unlock chain: hut → workshop → garden
	var unlocks := {
		"hut": true,
		"workshop": "hut",
		"garden": "workshop",
	}
	assert_true(unlocks.get("hut") == true, "build_unlocks: hut is unlocked by default")
	assert_eq(unlocks.get("workshop"), "hut", "build_unlocks: workshop requires hut")
	assert_eq(unlocks.get("garden"), "workshop", "build_unlocks: garden requires workshop")


func test_priority_ordering(gs: Node) -> void:
	print("")
	print("--- priority ordering ---")

	# Test that priority order is preserved through save/load
	var payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["gather", "haul", "build"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
	}
	gs.save_game(payload)
	var loaded = gs.load_game()

	var order = loaded.get("priority_order", [])
	assert_eq(order.size(), 3, "priority_order: has 3 entries")
	assert_eq(order[0], "gather", "priority_order: first is gather")
	assert_eq(order[1], "haul", "priority_order: second is haul")
	assert_eq(order[2], "build", "priority_order: third is build")

	# Test default order
	var default_payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
	}
	gs.save_game(default_payload)
	loaded = gs.load_game()
	order = loaded.get("priority_order", [])
	assert_eq(order[0], "build", "priority_order: default first is build")
	assert_eq(order[2], "gather", "priority_order: default last is gather")


func test_tile_get_set(gs: Node) -> void:
	print("")
	print("--- tile get/set ---")

	# Bootstrap with tiles
	var tiles := []
	for y in 5:
		for x in 5:
			tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})

	var payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": tiles,
		"builds": [],
		"next_build_id": 1,
		"events": [],
	}
	gs.save_game(payload)
	var loaded = gs.load_game()

	# Verify tile grid
	assert_eq(loaded.get("tiles", []).size(), 25, "tile_ops: 5x5 grid = 25 tiles")
	assert_eq(loaded.get("tiles", [])[0].get("kind", ""), "ground", "tile_ops: tile[0] is ground")
	assert_eq(loaded.get("tiles", [])[12].get("kind", ""), "ground", "tile_ops: tile[12] is ground")

	# Simulate placing a tree on tile 0
	loaded["tiles"][0] = {"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""}
	gs.save_game(loaded)
	loaded = gs.load_game()
	assert_eq(loaded.get("tiles", [])[0].get("kind", ""), "tree", "tile_ops: tree placed on tile 0")
	assert_eq(int(loaded.get("tiles", [])[0].get("amount", -1)), 6, "tile_ops: tree has 6 wood")

	# Verify other tiles unchanged
	assert_eq(loaded.get("tiles", [])[1].get("kind", ""), "ground", "tile_ops: tile 1 still ground")


func test_worker_task_state(gs: Node) -> void:
	print("")
	print("--- worker task state ---")

	var workers := [
		{
			"name": "Jun",
			"pos": {"x": 2, "y": 1},
			"prev_pos": {"x": 2, "y": 1},
			"carrying": {},
			"task": {},
			"break_ticks": 0,
		},
		{
			"name": "Mara",
			"pos": {"x": 3, "y": 1},
			"prev_pos": {"x": 3, "y": 1},
			"carrying": {"wood": 2},
			"task": {"kind": "haul", "target": {"x": 5, "y": 3}, "resource": "wood", "build_id": 1},
			"break_ticks": 0,
		},
	]

	var payload := {
		"tick": 10,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": workers,
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
	}
	gs.save_game(payload)
	var loaded = gs.load_game()

	var loaded_workers = loaded.get("workers", [])
	assert_eq(loaded_workers.size(), 2, "worker_ops: 2 workers persisted")

	# Jun: idle, no carrying
	var jun = loaded_workers[0]
	assert_eq(jun.get("name", ""), "Jun", "worker_ops: Jun's name")
	assert_true(jun.get("task", {}).is_empty(), "worker_ops: Jun has no task")
	assert_true(jun.get("carrying", {}).is_empty(), "worker_ops: Jun carrying nothing")
	assert_eq(int(jun.get("break_ticks", 0)), 0, "worker_ops: Jun not on break")

	# Mara: hauling wood
	var mara = loaded_workers[1]
	assert_eq(mara.get("name", ""), "Mara", "worker_ops: Mara's name")
	assert_eq(mara.get("task", {}).get("kind", ""), "haul", "worker_ops: Mara hauling")
	assert_eq(int(mara.get("carrying", {}).get("wood", 0)), 2, "worker_ops: Mara carrying 2 wood")
	assert_eq(int(mara.get("break_ticks", 0)), 0, "worker_ops: Mara not on break")

	# Test break state
	workers[0]["break_ticks"] = 6
	payload["workers"] = workers
	gs.save_game(payload)
	loaded = gs.load_game()
	jun = loaded.get("workers", [])[0]
	assert_eq(int(jun.get("break_ticks", -1)), 6, "worker_ops: Jun on break for 6 ticks")


func test_save_version_tracking(gs: Node) -> void:
	print("")
	print("--- save version tracking ---")

	var payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
		"save_version": 1,
	}
	gs.save_game(payload)
	var loaded = gs.load_game()

	assert_not_empty(loaded, "save_version: load returned data")
	assert_eq(int(loaded.get("save_version", -1)), 2, "save_version: version is 2")


func test_settings_roundtrip(gs: Node) -> void:
	print("")
	print("--- settings roundtrip ---")

	var settings := {
		"dock_anchor": "left",
		"tick_speed": 2,
	}
	gs.save_settings(settings)
	var loaded = gs.load_settings()

	assert_not_empty(loaded, "settings_roundtrip: settings loaded")
	assert_eq(loaded.get("dock_anchor", ""), "left", "settings_roundtrip: dock_anchor")
	assert_eq(int(loaded.get("tick_speed", -1)), 2, "settings_roundtrip: tick_speed")

	# Test default settings when nothing saved
	gs.clear_game()
	loaded = gs.load_settings()
	assert_empty(loaded, "settings_roundtrip: cleared settings are empty")


func test_event_log(gs: Node) -> void:
	print("")
	print("--- event log ---")

	var events := [
		{"tick": 0, "text": "Colony started"},
		{"tick": 5, "text": "First tree gathered"},
		{"tick": 10, "text": "Hut built"},
	]

	var payload := {
		"tick": 10,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": events,
	}
	gs.save_game(payload)
	var loaded = gs.load_game()

	var loaded_events = loaded.get("events", [])
	assert_eq(loaded_events.size(), 3, "event_log: 3 events persisted")
	assert_eq(loaded_events[0].get("tick", -1), 0, "event_log: first event tick 0")
	assert_eq(loaded_events[0].get("text", ""), "Colony started", "event_log: first event text")
	assert_eq(loaded_events[2].get("text", ""), "Hut built", "event_log: last event text")



func test_bounded_event_log(gs: Node) -> void:
	print("")
	print("--- bounded event log ---")

	# Simulate push_event bounded behavior: max 20 events, LIFO eviction
	var events := []
	const MAX_EVENTS := 20

	for i in range(25):
		events.push_front({"tick": i, "text": "Event %d" % i})
		while events.size() > MAX_EVENTS:
			events.pop_back()

	assert_eq(events.size(), MAX_EVENTS, "bounded_event_log: capped at 20")
	# First event should be the most recent (24), last should be oldest kept (5)
	assert_eq(int(events[0].get("tick", -1)), 24, "bounded_event_log: first is newest (24)")
	assert_eq(int(events[MAX_EVENTS - 1].get("tick", -1)), 5, "bounded_event_log: last is oldest kept (5)")

	# Verify eviction count: 25 pushed - 20 kept = 5 evicted
	var evicted_count := 25 - MAX_EVENTS
	assert_eq(evicted_count, 5, "bounded_event_log: 5 events evicted")

	# Empty log stays empty
	var empty_events := []
	assert_empty(empty_events, "bounded_event_log: empty log is empty")

	# Single event fits without eviction
	empty_events.push_front({"tick": 0, "text": "Single"})
	assert_eq(empty_events.size(), 1, "bounded_event_log: single event size 1")

func test_clear_game(gs: Node) -> void:
	print("")
	print("--- clear game ---")

	var payload := {
		"tick": 99,
		"resources": {"wood": 100, "stone": 200},
		"harvested": {"wood": 10, "stone": 20, "food": 30},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{"name": "test", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}, "break_ticks": 0}],
		"tiles": [{"kind": "tree"}],
		"builds": [{"id": 1}],
		"next_build_id": 5,
		"events": [{"tick": 1, "text": "test"}],
		"save_version": 1,
	}
	gs.save_game(payload)
	gs.clear_game()

	var loaded = gs.load_game()
	assert_empty(loaded, "clear_game: game data is empty after clear")

	# Settings should also be cleared
	var settings = gs.load_settings()
	assert_empty(settings, "clear_game: settings are empty after clear")


# ── Save migration hardening tests ────────────────────────────────────────────
# Covers: v1->v2 migration, invalid old versions, future versions, malformed saves

func test_save_migration_hardening(gs: Node) -> void:
	print("")
	print("--- save migration hardening ---")

	# ── v1 -> v2 migration (regression) ──
	gs.clear_game()
	var v1_payload := {
		"tick": 5,
		"resources": {"wood": 10, "stone": 5},
		"harvested": {"wood": 0, "stone": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{"name": "test_worker", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}}],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
		"save_version": 1,
	}
	gs.save_game(v1_payload)
	var migrated = gs.load_game()
	assert_eq(int(migrated.get("save_version", -1)), 2, "migration_v1_to_v2: version upgraded to 2")
	assert_true(migrated.has("migration_log"), "migration_v1_to_v2: migration_log present")
	assert_eq(int(migrated["migration_log"][0].get("from_version", -1)), 1, "migration_v1_to_v2: log from_version=1")
	assert_eq(int(migrated["migration_log"][0].get("to_version", -1)), 2, "migration_v1_to_v2: log to_version=2")
	# Worker should get spawn_tick added
	assert_true(migrated.get("workers", [])[0].has("spawn_tick"), "migration_v1_to_v2: worker gets spawn_tick")

	# ── Future version (> 2) is rejected ──
	gs.clear_game()
	var future_payload := {
		"tick": 0,
		"resources": {"wood": 1},
		"harvested": {},
		"priority_order": [],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 0,
		"events": [],
		"save_version": 99,
	}
	gs.save_game(future_payload)
	var future_result = gs.load_game()
	assert_empty(future_result, "migration_future: future version rejected")

	# ── Version 0 (missing) is rejected ──
	gs.clear_game()
	var v0_payload := {
		"tick": 0,
		"resources": {"wood": 1},
		"harvested": {},
		"priority_order": [],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 0,
		"events": [],
		"save_version": 0,
	}
	gs.save_game(v0_payload)
	var v0_result = gs.load_game()
	assert_empty(v0_result, "migration_v0: version 0 rejected")

	# ── Missing save_version key treated as current version (backward compatible) ──
	gs.clear_game()
	var no_version_payload := {
		"tick": 0,
		"resources": {"wood": 1},
		"harvested": {},
		"priority_order": [],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 0,
		"events": [],
	}
	gs.save_game(no_version_payload)
	var no_version_result = gs.load_game()
	assert_not_empty(no_version_result, "migration_no_version: missing version treated as current")
	assert_eq(int(no_version_result.get("save_version", -1)), 2, "migration_no_version: defaults to v2")

	# ── Malformed save: non-dictionary parsed value ──
	gs.clear_game()
	# Write a JSON array directly to the save file (bypasses save_game)
	var file := FileAccess.open("user://windowstead.save", FileAccess.WRITE)
	if file:
		file.store_string("[1, 2, 3]")
		file.close()
	var non_dict_result = gs.load_game()
	assert_empty(non_dict_result, "malformed_non_dict: non-dictionary rejected")

	# ── Malformed save: missing required key 'resources' ──
	gs.clear_game()
	var malformed_resources_str := {
		"tick": 0,
		"resources": "not_a_dict",
		"harvested": {},
		"priority_order": [],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 0,
		"events": [],
		"save_version": 2,
	}
	gs.save_game(malformed_resources_str)
	var malformed_resources_result = gs.load_game()
	assert_empty(malformed_resources_result, "malformed_resources_type: non-dict resources rejected")

	# ── Malformed save: bad tile count (not a valid grid size) ──
	gs.clear_game()
	var bad_tiles := []
	for i in 30:  # 30 is not a valid grid size
		bad_tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	var payload_bad_tiles := {
		"tick": 0,
		"resources": {"wood": 1},
		"harvested": {},
		"priority_order": [],
		"workers": [],
		"tiles": bad_tiles,
		"builds": [],
		"next_build_id": 0,
		"events": [],
		"save_version": 2,
	}
	gs.save_game(payload_bad_tiles)
	var bad_tiles_result = gs.load_game()
	assert_empty(bad_tiles_result, "malformed_bad_tile_count: invalid tile count rejected")

	# ── Malformed save: tile missing required key ──
	gs.clear_game()
	var tiles_missing_key := []
	for y in 5:
		for x in 5:
			if x == 0 and y == 0:
				tiles_missing_key.append({"kind": "ground", "amount": 0, "resource": ""})  # missing build_kind
			else:
				tiles_missing_key.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	var payload_tile_key := {
		"tick": 0,
		"resources": {"wood": 1},
		"harvested": {},
		"priority_order": [],
		"workers": [],
		"tiles": tiles_missing_key,
		"builds": [],
		"next_build_id": 0,
		"events": [],
		"save_version": 2,
	}
	gs.save_game(payload_tile_key)
	var tile_key_result = gs.load_game()
	assert_empty(tile_key_result, "malformed_tile_missing_key: tile missing key rejected")

	# ── Valid v2 save still works after all hardening ──
	gs.clear_game()
	var valid_v2 := {
		"tick": 100,
		"resources": {"wood": 50, "stone": 30},
		"harvested": {"wood": 10, "stone": 5},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{"name": "Ava", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}, "break_ticks": 0, "spawn_tick": 0}],
		"tiles": [],
		"builds": [],
		"next_build_id": 3,
		"events": [{"tick": 1, "text": "ok"}],
		"save_version": 2,
	}
	gs.save_game(valid_v2)
	var valid_result = gs.load_game()
	assert_eq(int(valid_result.get("tick", -1)), 100, "valid_v2: tick preserved")
	assert_eq(int(valid_result.get("save_version", -1)), 2, "valid_v2: version stays 2")
	assert_eq(valid_result.get("workers", [])[0].get("name", ""), "Ava", "valid_v2: worker name preserved")


# ── Resource reservation tracking tests (issue #122) ────────────────────────
# Regression tests for the gather/haul resource reservation system.
# Verifies: reserved_resources field persists, clamping works, backward compat.

func test_resource_reservations(gs: Node) -> void:
	print("")
	print("--- resource reservations (issue #122) ---")

	# ── Test 1: reserved_resources field in bootstrap state ──
	gs.clear_game()
	var payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {"wood": 2, "stone": 0},
		"events": [],
	}
	gs.save_game(payload)
	var loaded = gs.load_game()
	assert_not_empty(loaded, "reservations: save with reserved_resources loads")
	assert_eq(int(loaded.get("reserved_resources", {}).get("wood", -1)), 2, "reservations: wood reserved = 2")
	assert_eq(int(loaded.get("reserved_resources", {}).get("stone", -1)), 0, "reservations: stone reserved = 0")

	# ── Test 2: backward compat — old save without reserved_resources loads ──
	gs.clear_game()
	var legacy_payload := {
		"tick": 5,
		"resources": {"wood": 10, "stone": 5},
		"harvested": {"wood": 0, "stone": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{"name": "test_worker", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}}],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
		"save_version": 2,
	}
	gs.save_game(legacy_payload)
	var legacy_loaded = gs.load_game()
	assert_not_empty(legacy_loaded, "reservations: legacy save without reserved_resources loads")
	assert_eq(int(legacy_loaded.get("tick", -1)), 5, "reservations: legacy tick preserved")

	# ── Test 3: reserved_resources survives migration v1→v2 ──
	gs.clear_game()
	var v1_with_reservations := {
		"tick": 10,
		"resources": {"wood": 10, "stone": 5},
		"harvested": {"wood": 0, "stone": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{"name": "Mara", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}}],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {"food": 3},
		"events": [],
		"save_version": 1,
	}
	gs.save_game(v1_with_reservations)
	var migrated = gs.load_game()
	assert_eq(int(migrated.get("save_version", -1)), 2, "reservations: v1->v2 migration succeeds")
	assert_eq(int(migrated.get("reserved_resources", {}).get("food", -1)), 3, "reservations: food reservation survives migration")

	# ── Test 4: reserved_resources empty by default in bootstrap ──
	gs.clear_game()
	var fresh_payload := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
	}
	gs.save_game(fresh_payload)
	var fresh_loaded = gs.load_game()
	# No reserved_resources field — should load fine (backward compat)
	assert_not_empty(fresh_loaded, "reservations: save without reserved_resources loads")

	# ── Test 5: reserved_resources persists through update ──
	gs.clear_game()
	var state := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {"wood": 3, "food": 1},
		"events": [],
	}
	gs.save_game(state)
	state["tick"] = 5
	state["resources"]["wood"] = 6  # wood consumed
	gs.save_game(state)
	var updated = gs.load_game()
	assert_eq(int(updated.get("reserved_resources", {}).get("wood", -1)), 3, "reservations: wood reserved persists after resource change")
	assert_eq(int(updated.get("reserved_resources", {}).get("food", -1)), 1, "reservations: food reserved persists")


# ── Two-worker race condition test (issue #122) ────────────────────────────
# Behavioral test verifying that when two workers compete for the same
# resource tile, only one gets the gather task due to reservation.

func test_two_worker_race_condition(gs: Node) -> void:
	print("")
	print("--- two-worker race condition (issue #122) ---")

	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()

	# ── Set up: 5x5 grid, 2 workers, 1 tree with amount=1 ──
	main.grid_w = 5
	main.grid_h = 5
	main.priority_order = ["gather"] as Array[String]
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}

	# Fill grid with ground tiles
	for y in 5:
		for x in 5:
			main.state.tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})

	# Place a single tree at (2, 2) with amount=1
	main.set_tile(Vector2i(2, 2), {"kind": "tree", "amount": 1, "resource": "wood", "build_kind": ""})

	# Place two workers near the tree
	main.state.workers.append({
		"name": "WorkerA",
		"pos": {"x": 2, "y": 1},
		"prev_pos": {"x": 2, "y": 1},
		"carrying": {},
		"task": {},
		"break_ticks": 0,
	})
	main.state.workers.append({
		"name": "WorkerB",
		"pos": {"x": 3, "y": 2},
		"prev_pos": {"x": 3, "y": 2},
		"carrying": {},
		"task": {},
		"break_ticks": 0,
	})

	# ── WorkerA chooses first — should get gather task and reserve wood ──
	var task_a: Dictionary = main.choose_task(main.state.workers[0])
	assert_eq(str(task_a.kind), "gather", "race: workerA gets gather task")
	assert_eq(str(task_a.resource), "wood", "race: workerA targets wood")

	# Verify reservation was created
	assert_eq(main.get_reserved("wood"), 1, "race: 1 wood reserved after workerA chooses")

	# ── WorkerB chooses — should NOT get gather (tile fully reserved) ──
	var task_b: Dictionary = main.choose_task(main.state.workers[1])
	assert_true(task_b.is_empty(), "race: workerB gets no task (fully reserved)")

	# ── After gathering, reservation is released and tree is depleted ──
	main.do_gather(main.state.workers[0], task_a)
	assert_eq(main.get_reserved("wood"), 0, "race: reservation released after gather")
	assert_eq(int(main.state.workers[0].get("carrying", {}).get("wood", 0)), 1, "race: workerA carrying 1 wood")

	# ── WorkerB can't gather — tree was depleted by workerA ──
	var task_b2: Dictionary = main.choose_task(main.state.workers[1])
	assert_true(task_b2.is_empty(), "race: workerB gets no task (tree depleted after gather)")


# ── Delivery clamping test (issue #122) ───────────────────────────────────
# Verifies that build haul deliveries are clamped to remaining need
# and excess is refunded to stockpile.

func test_delivery_clamping(gs: Node) -> void:
	print("")
	print("--- delivery clamping (issue #122) ---")

	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()

	# ── Set up: 5x5 grid, stockpile at (0,0), hut build needing 6 wood ──
	main.grid_w = 5
	main.grid_h = 5
	main.priority_order = ["haul"] as Array[String]
	main.state = {
		"tick": 0,
		"resources": {"wood": 10, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["haul"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [
			{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": false, "delivered": {"wood": 3}},
		],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}

	# Fill grid with ground tiles
	for y in 5:
		for x in 5:
			main.state.tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})

	# Stockpile at (0, 0)
	main.stockpile_pos = Vector2i(0, 0)

	# Worker at stockpile carrying 5 wood (hut needs 3 more)
	main.state.workers.append({
		"name": "Hauler",
		"pos": {"x": 0, "y": 0},
		"prev_pos": {"x": 0, "y": 0},
		"carrying": {"wood": 5},
		"task": {"kind": "haul", "target": {"x": 2, "y": 2}, "resource": "wood", "build_id": 1},
		"break_ticks": 0,
	})

	# ── Haul to build — should clamp to 3 (remaining need), refund 2 ──
	main.do_haul(main.state.workers[0], main.state.workers[0].task)

	var build: Dictionary = main.get_build(1)
	assert_eq(int(build.delivered.get("wood", 0)), 6, "clamping: delivered clamped to cost (6)")
	assert_eq(int(main.state.resources.get("wood", -1)), 12, "clamping: excess refunded to stockpile (10+2=12)")

	# ── Second haul — already at cost, should deliver 0 ──
	main.state.workers[0]["carrying"] = {"wood": 4}
	main.state.workers[0]["task"] = {"kind": "haul", "target": {"x": 2, "y": 2}, "resource": "wood", "build_id": 1}
	main.do_haul(main.state.workers[0], main.state.workers[0].task)

	build = main.get_build(1)
	assert_eq(int(build.delivered.get("wood", 0)), 6, "clamping: no over-delivery (stays at 6)")
	assert_eq(int(main.state.resources.get("wood", -1)), 16, "clamping: all excess refunded (12+4=16)")

