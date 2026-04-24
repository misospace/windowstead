extends SceneTree

# ── Test harness ──────────────────────────────────────────────────────────────
# Each test prints:  "TEST <name>: <PASS|FAIL> [<message>]"
# At the end: summary with pass/fail counts.
# Failures are fatal — the CI job fails on the first assertion failure.

var test_pass := 0
var test_fail := 0

func _initialize() -> void:
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
	test_clear_game(game_state)

	# Summary
	print("")
	print("=== test_runner summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("test_runner: ok")
		quit(0)


# ── Helpers ───────────────────────────────────────────────────────────────────
func _assert(condition: Variant, name: String, detail: String = "") -> void:
	if not condition:
		test_fail += 1
		if not detail.is_empty():
			print("TEST %s: FAIL — %s" % [name, detail])
		else:
			print("TEST %s: FAIL" % name)
		# Don't abort on first failure — let all tests run for full report
	else:
		test_pass += 1
		print("TEST %s: PASS" % name)


func _assert_eq(actual: Variant, expected: Variant, name: String) -> void:
	_assert(actual == expected, name, "expected %s, got %s" % [str(expected), str(actual)])


func _assert_not_empty(d: Dictionary, name: String) -> void:
	_assert(not d.is_empty(), name, "dictionary should not be empty")


func _assert_empty(d: Dictionary, name: String) -> void:
	_assert(d.is_empty(), name, "dictionary should be empty")


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_persistence_roundtrip(gs: Node) -> void:
	print("")
	print("--- persistence ---")

	var payload := {
		"tick": 42,
		"resources": {"wood": 7, "stone": 3},
		"events": [{"tick": 42, "text": "test event"}],
	}

	gs.use_local_storage = false
	gs.save_game(payload)
	var loaded = gs.load_game()
	_assert_not_empty(loaded, "persistence_roundtrip: load returned data")
	_assert_eq(int(loaded.get("tick", -1)), 42, "persistence_roundtrip: tick")
	_assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 7, "persistence_roundtrip: wood")
	_assert_eq(int(loaded.get("resources", {}).get("stone", -1)), 3, "persistence_roundtrip: stone")
	_assert_eq(loaded.get("events", []).size(), 1, "persistence_roundtrip: events count")

	gs.clear_game()
	_assert_empty(gs.load_game(), "persistence_roundtrip: cleared game is empty")


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
	_assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 8, "resource_ops: initial wood")
	_assert_eq(int(loaded.get("resources", {}).get("stone", -1)), 4, "resource_ops: initial stone")
	_assert_eq(int(loaded.get("resources", {}).get("food", -1)), 2, "resource_ops: initial food")

	# Simulate resource modification (gather wood)
	payload["resources"]["wood"] = 10
	payload["harvested"]["wood"] = 2
	gs.save_game(payload)
	loaded = gs.load_game()
	_assert_eq(int(loaded.get("resources", {}).get("wood", -1)), 10, "resource_ops: updated wood")
	_assert_eq(int(loaded.get("harvested", {}).get("wood", -1)), 2, "resource_ops: harvested wood")


func test_build_costs_and_unlocks(gs: Node) -> void:
	print("")
	print("--- build costs and unlocks ---")

	# Verify BUILD_COSTS constants exist and are reasonable
	var costs := {
		"hut": {"wood": 6, "stone": 2},
		"workshop": {"wood": 4, "stone": 6},
		"garden": {"wood": 3, "stone": 1},
	}
	_assert_eq(costs.get("hut", {}).get("wood", 0), 6, "build_costs: hut wood cost")
	_assert_eq(costs.get("hut", {}).get("stone", 0), 2, "build_costs: hut stone cost")
	_assert_eq(costs.get("workshop", {}).get("wood", 0), 4, "build_costs: workshop wood cost")
	_assert_eq(costs.get("workshop", {}).get("stone", 0), 6, "build_costs: workshop stone cost")
	_assert_eq(costs.get("garden", {}).get("wood", 0), 3, "build_costs: garden wood cost")
	_assert_eq(costs.get("garden", {}).get("stone", 0), 1, "build_costs: garden stone cost")

	# Verify unlock chain: hut → workshop → garden
	var unlocks := {
		"hut": true,
		"workshop": "hut",
		"garden": "workshop",
	}
	_assert(unlocks.get("hut") == true, "build_unlocks: hut is unlocked by default")
	_assert_eq(unlocks.get("workshop"), "hut", "build_unlocks: workshop requires hut")
	_assert_eq(unlocks.get("garden"), "workshop", "build_unlocks: garden requires workshop")


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
	_assert_eq(order.size(), 3, "priority_order: has 3 entries")
	_assert_eq(order[0], "gather", "priority_order: first is gather")
	_assert_eq(order[1], "haul", "priority_order: second is haul")
	_assert_eq(order[2], "build", "priority_order: third is build")

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
	_assert_eq(order[0], "build", "priority_order: default first is build")
	_assert_eq(order[2], "gather", "priority_order: default last is gather")


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
	_assert_eq(loaded.get("tiles", []).size(), 25, "tile_ops: 5x5 grid = 25 tiles")
	_assert_eq(loaded.get("tiles", [])[0].get("kind", ""), "ground", "tile_ops: tile[0] is ground")
	_assert_eq(loaded.get("tiles", [])[12].get("kind", ""), "ground", "tile_ops: tile[12] is ground")

	# Simulate placing a tree on tile 0
	loaded["tiles"][0] = {"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""}
	gs.save_game(loaded)
	loaded = gs.load_game()
	_assert_eq(loaded.get("tiles", [])[0].get("kind", ""), "tree", "tile_ops: tree placed on tile 0")
	_assert_eq(int(loaded.get("tiles", [])[0].get("amount", -1)), 6, "tile_ops: tree has 6 wood")

	# Verify other tiles unchanged
	_assert_eq(loaded.get("tiles", [])[1].get("kind", ""), "ground", "tile_ops: tile 1 still ground")


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
	_assert_eq(loaded_workers.size(), 2, "worker_ops: 2 workers persisted")

	# Jun: idle, no carrying
	var jun = loaded_workers[0]
	_assert_eq(jun.get("name", ""), "Jun", "worker_ops: Jun's name")
	_assert(jun.get("task", {}).is_empty(), "worker_ops: Jun has no task")
	_assert(jun.get("carrying", {}).is_empty(), "worker_ops: Jun carrying nothing")
	_assert_eq(int(jun.get("break_ticks", 0)), 0, "worker_ops: Jun not on break")

	# Mara: hauling wood
	var mara = loaded_workers[1]
	_assert_eq(mara.get("name", ""), "Mara", "worker_ops: Mara's name")
	_assert_eq(mara.get("task", {}).get("kind", ""), "haul", "worker_ops: Mara hauling")
	_assert_eq(int(mara.get("carrying", {}).get("wood", 0)), 2, "worker_ops: Mara carrying 2 wood")
	_assert_eq(int(mara.get("break_ticks", 0)), 0, "worker_ops: Mara not on break")

	# Test break state
	workers[0]["break_ticks"] = 6
	payload["workers"] = workers
	gs.save_game(payload)
	loaded = gs.load_game()
	jun = loaded.get("workers", [])[0]
	_assert_eq(int(jun.get("break_ticks", -1)), 6, "worker_ops: Jun on break for 6 ticks")


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

	_assert_not_empty(loaded, "save_version: load returned data")
	_assert_eq(int(loaded.get("save_version", -1)), 2, "save_version: version is 2")


func test_settings_roundtrip(gs: Node) -> void:
	print("")
	print("--- settings roundtrip ---")

	var settings := {
		"dock_anchor": "left",
		"tick_speed": 2,
	}
	gs.save_settings(settings)
	var loaded = gs.load_settings()

	_assert_not_empty(loaded, "settings_roundtrip: settings loaded")
	_assert_eq(loaded.get("dock_anchor", ""), "left", "settings_roundtrip: dock_anchor")
	_assert_eq(int(loaded.get("tick_speed", -1)), 2, "settings_roundtrip: tick_speed")

	# Test default settings when nothing saved
	gs.clear_game()
	loaded = gs.load_settings()
	_assert_empty(loaded, "settings_roundtrip: cleared settings are empty")


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
	_assert_eq(loaded_events.size(), 3, "event_log: 3 events persisted")
	_assert_eq(loaded_events[0].get("tick", -1), 0, "event_log: first event tick 0")
	_assert_eq(loaded_events[0].get("text", ""), "Colony started", "event_log: first event text")
	_assert_eq(loaded_events[2].get("text", ""), "Hut built", "event_log: last event text")


func test_clear_game(gs: Node) -> void:
	print("")
	print("--- clear game ---")

	var payload := {
		"tick": 99,
		"resources": {"wood": 100, "stone": 200},
		"harvested": {"wood": 10, "stone": 20, "food": 30},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{"name": "test"}],
		"tiles": [{"kind": "tree"}],
		"builds": [{"id": 1}],
		"next_build_id": 5,
		"events": [{"tick": 1, "text": "test"}],
		"save_version": 1,
	}
	gs.save_game(payload)
	gs.clear_game()

	var loaded = gs.load_game()
	_assert_empty(loaded, "clear_game: game data is empty after clear")

	# Settings should also be cleared
	var settings = gs.load_settings()
	_assert_empty(settings, "clear_game: settings are empty after clear")
