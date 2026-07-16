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
