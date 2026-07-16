extends "res://tests/test_case.gd"

## Tests for worker cap calculation (issue #146).
## Verifies: base cap, hut bonus, multiple huts, no structures, unknown structure types.


func run_tests() -> void:
	# main.gd references the GameState autoload, so it must be load()ed at
	# runtime — preload() compiles before autoloads are registered in --script mode.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()

	test_base_cap_no_structures(main)
	test_one_hut_bonus(main)
	test_multiple_huts_add_up(main)
	test_workshop_does_not_increase_cap(main)
	test_mixed_structures(main)
	test_incomplete_builds_do_not_count(main)

	main.free()


# ── Test 1: Base cap with no structures ──
func test_base_cap_no_structures(main) -> void:
	print("")
	print("--- base cap ---")
	_setup_state(main, [])
	assert_eq(main.get_worker_cap(), 2, "base_cap: returns BASE_WORKER_CAP (2) with no builds")


# ── Test 2: One completed hut adds bonus ──
func test_one_hut_bonus(main) -> void:
	print("")
	print("--- one hut bonus ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
	]
	_setup_state(main, builds)
	assert_eq(main.get_worker_cap(), 4, "one_hut: base(2) + hut_bonus(2) = 4")


# ── Test 3: Multiple huts stack ──
func test_multiple_huts_add_up(main) -> void:
	print("")
	print("--- multiple huts ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 2, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
	]
	_setup_state(main, builds)
	assert_eq(main.get_worker_cap(), 6, "multi_hut: base(2) + 2*hut_bonus(2) = 6")


# ── Test 4: Workshop does not increase cap ──
func test_workshop_does_not_increase_cap(main) -> void:
	print("")
	print("--- workshop no bonus ---")
	var builds = [
		{"id": 1, "kind": "workshop", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 4, "stone": 6}, "progress": 1.0},
	]
	_setup_state(main, builds)
	assert_eq(main.get_worker_cap(), 2, "workshop: no bonus for workshop, stays at base(2)")


# ── Test 5: Mixed structures ──
func test_mixed_structures(main) -> void:
	print("")
	print("--- mixed structures ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 2, "kind": "workshop", "pos": {"x": 3, "y": 2}, "complete": true, "delivered": {"wood": 4, "stone": 6}, "progress": 1.0},
	]
	_setup_state(main, builds)
	assert_eq(main.get_worker_cap(), 4, "mixed: base(2) + hut_bonus(2) = 4 (workshop adds nothing)")


# ── Test 6: Incomplete builds don't count ──
func test_incomplete_builds_do_not_count(main) -> void:
	print("")
	print("--- incomplete builds ---")
	var builds = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": false, "delivered": {"wood": 3, "stone": 1}, "progress": 0.5},
	]
	_setup_state(main, builds)
	assert_eq(main.get_worker_cap(), 2, "incomplete: incomplete hut doesn't count, stays at base(2)")


# ── Helper ──
func _setup_state(main, builds: Array) -> void:
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
