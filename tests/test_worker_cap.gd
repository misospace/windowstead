## Tests for worker cap calculation (issue #146).
## Verifies: base cap, hut bonus, multiple huts, no structures, unknown structure types.

extends SceneTree

var test_pass := 0
var test_fail := 0

func _initialize() -> void:
	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = preload("res://scripts/main.gd")
	var main: Control = main_script.new()

	test_base_cap_no_structures(main)
	test_one_hut_bonus(main)
	test_multiple_huts_add_up(main)
	test_workshop_does_not_increase_cap(main)
	test_mixed_structures(main)
	test_incomplete_builds_do_not_count(main)

	# Summary
	print("")
	print("=== test_worker_cap summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED")
		quit(1)
	else:
		print("test_worker_cap: ok")
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


# ── Test 1: Base cap with no structures ──
func test_base_cap_no_structures(main: Control) -> void:
	print("")
	print("--- base cap ---")
	_setup_state(main, [])
	_assert_eq(main.get_worker_cap(), 2, "base_cap: returns BASE_WORKER_CAP (2) with no builds")


# ── Test 2: One completed hut adds bonus ──
func test_one_hut_bonus(main: Control) -> void:
	print("")
	print("--- one hut bonus ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
	]
	_setup_state(main, builds)
	_assert_eq(main.get_worker_cap(), 4, "one_hut: base(2) + hut_bonus(2) = 4")


# ── Test 3: Multiple huts stack ──
func test_multiple_huts_add_up(main: Control) -> void:
	print("")
	print("--- multiple huts ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 2, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
	]
	_setup_state(main, builds)
	_assert_eq(main.get_worker_cap(), 6, "multi_hut: base(2) + 2*hut_bonus(2) = 6")


# ── Test 4: Workshop does not increase cap ──
func test_workshop_does_not_increase_cap(main: Control) -> void:
	print("")
	print("--- workshop no bonus ---")
	var builds = [
		{"id": 1, "kind": "workshop", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 4, "stone": 6}, "progress": 1.0},
	]
	_setup_state(main, builds)
	_assert_eq(main.get_worker_cap(), 2, "workshop: no bonus for workshop, stays at base(2)")


# ── Test 5: Mixed structures ──
func test_mixed_structures(main: Control) -> void:
	print("")
	print("--- mixed structures ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 2, "kind": "workshop", "pos": {"x": 3, "y": 2}, "complete": true, "delivered": {"wood": 4, "stone": 6}, "progress": 1.0},
	]
	_setup_state(main, builds)
	_assert_eq(main.get_worker_cap(), 4, "mixed: base(2) + hut_bonus(2) = 4 (workshop adds nothing)")


# ── Test 6: Incomplete builds don't count ──
func test_incomplete_builds_do_not_count(main: Control) -> void:
	print("")
	print("--- incomplete builds ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": false, "delivered": {"wood": 3, "stone": 1}, "progress": 0.5},
	]
	_setup_state(main, builds)
	_assert_eq(main.get_worker_cap(), 2, "incomplete: incomplete hut doesn't count, stays at base(2)")


# ── Helper ──
func _setup_state(main: Control, builds: Array) -> void:
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": builds,
		"next_build_id": int(builds.size()) + 1,
		"reserved_resources": {},
		"events": [],
	}
