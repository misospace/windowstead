## Tests for recruit worker decision logic (issue #149, links to #133, #135).
## Verifies: successful recruit, blocked recruit at cap, name cycling, food impact messaging.

extends SceneTree

var test_pass := 0
var test_fail := 0

func _initialize() -> void:
	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = load("res://scripts/main.gd") as GDScript
	var main: Control = main_script.new()

	test_can_recruit_with_capacity(main)
	test_cannot_recruit_at_cap(main)
	test_recruit_adds_worker_to_state(main)
	test_recruit_cycles_through_names(main)
	test_recruit_with_no_workers_returns_true(main)
	test_food_impact_messaging_for_extra_workers(main)
	test_food_impact_no_upkeep_when_under_threshold(main)

	# Summary
	print("")
	print("=== test_recruit_worker summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED")
		quit(1)
	else:
		print("test_recruit_worker: ok")
		quit(0)


func _assert(condition: Variant, name: String, detail: String = "") -> void:
	if not condition:
		test_fail += 1
		if not detail.is_empty():
			print("TEST %s: FAIL — %s" % [name, detail])
		else:
			print("TEST %s: FAIL" % name)
	else:
		test_pass += 1
		print("TEST %s: PASS" % name)


func _assert_eq(actual: Variant, expected: Variant, name: String) -> void:
	_assert(actual == expected, name, "expected %s, got %s" % [str(expected), str(actual)])


# ── Test 1: can_recruit returns true when under cap ──
func test_can_recruit_with_capacity(main: Control) -> void:
	print("")
	print("--- recruit with capacity ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
	]
	_setup_state(main, builds, [{"name": "Jun", "task": {"kind": "", "data": {}}}])
	# Cap is 4 (base 2 + hut bonus 2), 1 worker → can recruit
	_assert(main.can_recruit_worker(), "can_recruit: returns true when under cap (1/4)")


# ── Test 2: can_recruit returns false at cap ──
func test_cannot_recruit_at_cap(main: Control) -> void:
	print("")
	print("--- blocked at cap ---")
	var builds = []
	_setup_state(main, builds, [
		{"name": "Jun", "task": {"kind": "", "data": {}}},
		{"name": "Mara", "task": {"kind": "", "data": {}}},
	])
	# Cap is 2 (base), 2 workers → cannot recruit
	_assert(not main.can_recruit_worker(), "can_recruit: returns false at cap (2/2)")


# ── Test 3: recruit adds worker to state ──
func test_recruit_adds_worker_to_state(main: Control) -> void:
	print("")
	print("--- recruit adds worker ---")
	var builds = []
	_setup_state(main, builds, [
		{"name": "Jun", "task": {"kind": "", "data": {}}},
	])
	_assert(main.can_recruit_worker(), "precondition: can recruit")
	var initial_count: int = main.state.workers.size()
	main.recruit_worker()
	_assert_eq(main.state.workers.size(), initial_count + 1, "recruit: state workers count increases by 1")


# ── Test 4: name cycling through WORKER_NAMES ──
func test_recruit_cycles_through_names(main: Control) -> void:
	print("")
	print("--- name cycling ---")
	var builds = []
	_setup_state(main, builds, [])
	# First recruit should pick index 0 ("Jun")
	main.recruit_worker()
	_assert_eq(main.state.workers[0].name, "Jun", "first recruit gets first name 'Jun'")

	# Second recruit should pick index 1 ("Mara")
	main.recruit_worker()
	_assert_eq(main.state.workers[1].name, "Mara", "second recruit gets second name 'Mara'")

	# Third recruit should wrap to index 0 again ("Jun")
	main.recruit_worker()
	_assert_eq(main.state.workers[2].name, "Jun", "third recruit wraps to first name 'Jun'")


# ── Test 5: can_recruit returns true when no workers exist yet ──
func test_recruit_with_no_workers_returns_true(main: Control) -> void:
	print("")
	print("--- recruit with no workers ---")
	var builds = []
	_setup_state(main, builds, [])
	_assert(main.can_recruit_worker(), "can_recruit: returns true when no workers (empty state)")


# ── Test 6: food impact messaging for extra workers ──
func test_food_impact_messaging_for_extra_workers(main: Control) -> void:
	print("")
	print("--- food impact messaging ---")
	var builds = []
	_setup_state(main, builds, [
		{"name": "Jun", "task": {"kind": "", "data": {}}},
		{"name": "Mara", "task": {"kind": "", "data": {}}},
	])
	# At base threshold (2 workers), extra = 0, so recruiting the 3rd triggers food cost
	main.recruit_worker()
	var events := main.state.get("events", [])
	var found_food_msg := false
	for evt in events:
		if "Food impact" in str(evt.get("text", "")):
			found_food_msg = true
	_assert(found_food_msg, "recruit extra worker: food impact message logged")


# ── Test 7: no food cost when under base threshold ──
func test_food_impact_no_upkeep_when_under_threshold(main: Control) -> void:
	print("")
	print("--- no food cost under threshold ---")
	var builds = []
	_setup_state(main, builds, [])
	main.recruit_worker()
	var events := main.state.get("events", [])
	var found_food_msg := false
	for evt in events:
		if "Food impact" in str(evt.get("text", "")):
			found_food_msg = true
	_assert(not found_food_msg, "recruit under threshold: no food impact message")


# ── Helper ──
func _setup_state(main: Control, builds: Array, workers: Array) -> void:
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
