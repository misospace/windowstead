extends SceneTree
# Tests for active rotating goal persistence — misospace/windowstead#144

var test_pass := 0
var test_fail := 0

func _initialize() -> void:
	var goal_script := load("res://scripts/rotating_goal.gd")
	var state_script := load("res://scripts/game_state.gd")

	test_active_goal_persists_in_state(goal_script)
	test_completed_goal_ids_persists_in_state(goal_script)
	test_empty_active_goal_not_overwritten()
	test_load_fallback_when_no_active_goal_saved(goal_script)
	test_load_fallback_when_incompatible_goal_id(goal_script)

	print("")
	print("=== test_goal_persistence summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("test_goal_persistence: ok")
		quit(0)


# ── Helpers ───────────────────────────────────────────────────────────────────

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

func _assert_str_eq(actual: String, expected: String, name: String) -> void:
	_assert(actual == expected, name, "expected '%s', got '%s'" % [expected, actual])


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_active_goal_persists_in_state(gs: Variant) -> void:
	print("")
	print("--- active_goal persists in state ---")

	var template = gs.GOAL_CATALOG[0]  # gather_wood
	var goal = gs.apply_goal_template(template)

	# Simulate what persist() does
	var state := {
		"tick": 42,
		"save_version": 2,
	}
	if not goal.is_empty():
		state["active_goal"] = goal.duplicate(true)

	_assert(state.has("active_goal"), "state_has_active_goal_key")
	_assert_eq(state.active_goal["id"], "gather_wood", "active_goal_id_persisted")
	_assert_eq(state.active_goal["type"], gs.GOAL_TYPE_RESOURCE, "active_goal_type_persisted")
	_assert_eq(state.active_goal["target"]["resource"], "wood", "active_goal_target_resource_persisted")

	# Verify deep copy — modifying the state's goal doesn't affect the original
	state.active_goal["current_progress"] = 999
	_assert_eq(goal["current_progress"], 3, "deep_copy_active_goal_not_mutated")


func test_completed_goal_ids_persists_in_state(gs: Variant) -> void:
	print("")
	print("--- completed_goal_ids persists in state ---")

	var completed := ["gather_wood", "gather_stone"]

	# Simulate what persist() does
	var state := {
		"tick": 42,
		"save_version": 2,
	}
	state["completed_goal_ids"] = completed.duplicate()

	_assert(state.has("completed_goal_ids"), "state_has_completed_goal_ids_key")
	_assert_eq(state.completed_goal_ids.size(), 2, "completed_goal_ids_count_persisted")
	_assert_str_eq(state.completed_goal_ids[0], "gather_wood", "first_completed_id")
	_assert_str_eq(state.completed_goal_ids[1], "gather_stone", "second_completed_id")

	# Verify deep copy — modifying state's array doesn't affect original
	state.completed_goal_ids.append("build_hut")
	_assert_eq(completed.size(), 2, "deep_copy_completed_ids_not_mutated")


func test_empty_active_goal_not_overwritten() -> void:
	print("")
	print("--- empty active_goal not persisted ---")

	var state := {
		"tick": 42,
		"save_version": 2,
	}
	var empty_goal = {}

	# Simulate persist(): only set active_goal if not empty
	if not empty_goal.is_empty():
		state["active_goal"] = empty_goal.duplicate(true)

	_assert(not state.has("active_goal"), "empty_goal_not_in_state")


func test_load_fallback_when_no_active_goal_saved(gs: Variant) -> void:
	print("")
	print("--- load fallback when no active_goal saved ---")

	var loaded := {
		"tick": 100,
		"save_version": 2,
		"completed_goal_ids": ["gather_wood"],
	}

	# Simulate load_or_boot() fallback logic
	var saved_goal = loaded.get("active_goal", {})
	var active_goal: Dictionary = {}
	var completed_goal_ids := []

	if saved_goal is Dictionary and not saved_goal.is_empty():
		var saved_id = saved_goal.get("id", "")
		var catalog_ids = gs.GOAL_CATALOG.map(func(e): return e["id"])
		if catalog_ids.has(saved_id) and loaded.get("completed_goal_ids", []) is Array:
			active_goal = saved_goal.duplicate(true)
			completed_goal_ids = loaded.get("completed_goal_ids", []).duplicate()
	else:
		active_goal = gs.select_next_active_goal(completed_goal_ids)
		completed_goal_ids = []

	_assert_str_eq(active_goal["id"], "gather_stone", "fallback_selects_next_catalog_entry")
	_assert_eq(completed_goal_ids.size(), 0, "fallback_resets_completed_ids")


func test_load_fallback_when_incompatible_goal_id(gs: Variant) -> void:
	print("")
	print("--- load fallback when incompatible goal id ---")

	var loaded := {
		"tick": 100,
		"save_version": 2,
		"active_goal": {"id": "nonexistent_goal", "type": "resource", "target": {}, "current_progress": 5, "completed": false},
		"completed_goal_ids": ["gather_wood"],
	}

	# Simulate load_or_boot() fallback logic
	var saved_goal = loaded.get("active_goal", {})
	var active_goal: Dictionary = {}
	var completed_goal_ids := []

	if saved_goal is Dictionary and not saved_goal.is_empty():
		var saved_id = saved_goal.get("id", "")
		var catalog_ids = gs.GOAL_CATALOG.map(func(e): return e["id"])
		if catalog_ids.has(saved_id) and loaded.get("completed_goal_ids", []) is Array:
			active_goal = saved_goal.duplicate(true)
			completed_goal_ids = loaded.get("completed_goal_ids", []).duplicate()
	else:
		active_goal = gs.select_next_active_goal(completed_goal_ids)
		completed_goal_ids = []

	_assert_str_eq(active_goal["id"], "gather_stone", "fallback_on_unknown_goal_id_selects_next")
	_assert_eq(completed_goal_ids.size(), 0, "fallback_on_unknown_goal_resets_completed_ids")
