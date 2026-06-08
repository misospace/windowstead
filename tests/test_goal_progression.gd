## Regression tests for GoalProgression — pure game logic extracted from main.gd.
## Tests the extracted domain controller for goal lifecycle management.
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_goal_progression.gd

extends SceneTree

const GP := preload("res://scripts/goal_progression.gd")
const RG := preload("res://scripts/rotating_goal.gd")

func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0

	# --- init_goals ---
	pass_count += test("init_goals returns first non-completed goal", _test_init_goals_first)
	pass_count += test("init_goals skips completed goals", _test_init_goals_skip_completed)
	pass_count += test("init_goals returns empty dict when all done", _test_init_goals_all_done)

	# --- compute_progress (resource) ---
	pass_count += test("compute_progress updates resource progress from game_state", _test_compute_resource_progress)
	pass_count += test("compute_progress does nothing for non-resource goals", _test_compute_resource_no_op)

	# --- compute_progress (build) ---
	pass_count += test("compute_progress updates build progress from builds array", _test_compute_build_progress)
	pass_count += test("compute_progress ignores non-build goals", _test_compute_build_no_op)

	# --- check_and_rotate (no completion) ---
	pass_count += test("check_and_rotate returns unchanged when not complete", _test_check_rotate_not_complete)

	# --- check_and_rotate (completion + rotation) ---
	pass_count += test("check_and_rotate marks completed and rotates to next goal", _test_check_rotate_completes)
	pass_count += test("check_and_rotate appends completed ID to completed_ids", _test_check_rotate_appends_id)
	pass_count += test("check_and_rotate returns was_completed=true on rotation", _test_check_rotate_was_completed)

	# --- process_tick (full flow) ---
	pass_count += test("process_tick computes progress and detects completion in one call", _test_process_tick_flow)
	pass_count += test("process_tick with empty goal returns unchanged result", _test_process_tick_empty_goal)

	# --- Integration: multi-goal rotation ---
	pass_count += test("multi-goal rotation: completes first, rotates to second", _test_multi_goal_rotation)

	fail_count = 14 - pass_count
	print("\n=== Goal Progression Tests ===")
	print("Passed: %d" % pass_count)
	print("Failed: %d" % fail_count)

	if fail_count > 0:
		print("REGRESSION FAILURES DETECTED")
		quit(1)
	else:
		print("All goal progression tests passed.")
		quit(0)


func test(name: String, fn: Callable) -> int:
	var ok := true
	var error_msg := ""
	var result: Variant = fn.call()
	if result is Dictionary:
		ok = result.get("ok", false)
		error_msg = result.get("msg", "no detail")
	elif result == false:
		ok = false
		error_msg = "returned false"

	if ok:
		print("  ✓ %s" % name)
		return 1
	else:
		print("  ✗ %s: %s" % [name, error_msg])
		return 0


# --- Individual tests ---

func _test_init_goals_first() -> Dictionary:
	var result := GP.init_goals([])
	if result.is_empty():
		return {"ok": false, "msg": "expected first goal, got empty"}
	if result["id"] != "gather_wood":
		return {"ok": false, "msg": "expected gather_wood, got %s" % result.get("id", "?")}
	return {"ok": true}


func _test_init_goals_skip_completed() -> Dictionary:
	var result := GP.init_goals(["gather_wood"])
	if result.is_empty():
		return {"ok": false, "msg": "expected second goal, got empty"}
	if result["id"] != "gather_stone":
		return {"ok": false, "msg": "expected gather_stone, got %s" % result.get("id", "?")}
	return {"ok": true}


func _test_init_goals_all_done() -> Dictionary:
	var all_ids := []
	for t in RG.GOAL_CATALOG:
		all_ids.append(t["id"])
	var result := GP.init_goals(all_ids)
	if not result.is_empty():
		return {"ok": false, "msg": "expected empty dict when all goals done, got %s" % result}
	return {"ok": true}


func _test_compute_resource_progress() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	var game_state := {"harvested": {"wood": 5}}
	GP.compute_progress(goal, game_state)
	if goal["current_progress"] != 5:
		return {"ok": false, "msg": "expected progress 5, got %d" % goal["current_progress"]}
	return {"ok": true}


func _test_compute_resource_no_op() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[3])  # build_hut (non-resource)
	var game_state := {"harvested": {"wood": 100}}
	GP.compute_progress(goal, game_state)
	if goal["current_progress"] != 0:
		return {"ok": false, "msg": "resource progress should not change for build goal, got %d" % goal["current_progress"]}
	return {"ok": true}


func _test_compute_build_progress() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[3])  # build_hut
	var game_state := {"builds": [{"kind": "hut"}, {"kind": "hut"}, {"kind": "workshop"}]}
	GP.compute_progress(goal, game_state)
	if goal["current_progress"] != 2:
		return {"ok": false, "msg": "expected build progress 2, got %d" % goal["current_progress"]}
	return {"ok": true}


func _test_compute_build_no_op() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood (non-build)
	var game_state := {"builds": [{"kind": "hut"}]}
	GP.compute_progress(goal, game_state)
	if goal["current_progress"] != 0:
		return {"ok": false, "msg": "build progress should not change for resource goal, got %d" % goal["current_progress"]}
	return {"ok": true}


func _test_check_rotate_not_complete() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	goal["current_progress"] = 5  # not complete yet
	var completed_ids := []
	var result := GP.check_and_rotate(goal, completed_ids)
	if result["was_completed"]:
		return {"ok": false, "msg": "expected was_completed=false when not done"}
	if result["goal_id"] != "":
		return {"ok": false, "msg": "expected empty goal_id when not complete"}
	if result["active_goal"]["id"] != "gather_wood":
		return {"ok": false, "msg": "expected active_goal unchanged"}
	return {"ok": true}


func _test_check_rotate_completes() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	goal["current_progress"] = 10  # complete
	var completed_ids := []
	var result := GP.check_and_rotate(goal, completed_ids)
	if not result["was_completed"]:
		return {"ok": false, "msg": "expected was_completed=true"}
	if result["goal_id"] != "gather_wood":
		return {"ok": false, "msg": "expected goal_id=gather_wood, got %s" % result["goal_id"]}
	if result["active_goal"]["id"] != "gather_stone":
		return {"ok": false, "msg": "expected rotation to gather_stone, got %s" % result["active_goal"]["id"]}
	return {"ok": true}


func _test_check_rotate_appends_id() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood
	goal["current_progress"] = 10
	var completed_ids := ["some_old_id"]
	var result := GP.check_and_rotate(goal, completed_ids)
	if not result["completed_ids"].has("gather_wood"):
		return {"ok": false, "msg": "expected completed_ids to include gather_wood"}
	if result["completed_ids"].size() != 2:
		return {"ok": false, "msg": "expected 2 completed IDs, got %d" % result["completed_ids"].size()}
	return {"ok": true}


func _test_check_rotate_was_completed() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])
	goal["current_progress"] = 10
	var completed_ids := []
	var result := GP.check_and_rotate(goal, completed_ids)
	if not result["was_completed"]:
		return {"ok": false, "msg": "expected was_completed=true on rotation"}
	return {"ok": true}


func _test_process_tick_flow() -> Dictionary:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	goal["current_progress"] = 10  # complete
	var completed_ids := []
	var game_state := {"harvested": {"wood": 10}}
	var result := GP.process_tick(goal, completed_ids, game_state)
	if not result["was_completed"]:
		return {"ok": false, "msg": "expected was_completed=true after full tick"}
	if result["active_goal"]["id"] != "gather_stone":
		return {"ok": false, "msg": "expected rotation to gather_stone, got %s" % result["active_goal"]["id"]}
	return {"ok": true}


func _test_process_tick_empty_goal() -> Dictionary:
	var goal := {}
	var completed_ids := []
	var game_state := {"harvested": {}}
	var result := GP.process_tick(goal, completed_ids, game_state)
	if result["was_completed"]:
		return {"ok": false, "msg": "expected was_completed=false for empty goal"}
	if not result["active_goal"].is_empty():
		return {"ok": false, "msg": "expected empty active_goal for empty input"}
	return {"ok": true}


func _test_multi_goal_rotation() -> Dictionary:
	# Simulate completing two goals in sequence via process_tick
	var completed_ids := []

	# First tick: get gather_wood, complete it
	var goal = GP.init_goals(completed_ids)
	assert(not goal.is_empty(), "should have initial goal")
	goal["current_progress"] = 10  # simulate completion
	var game_state := {"harvested": {}}
	var result1 := GP.process_tick(goal, completed_ids, game_state)
	assert(result1["was_completed"], "first tick should complete")
	assert(result1["active_goal"]["id"] == "gather_stone", "should rotate to gather_stone")
	completed_ids = result1["completed_ids"]

	# Second tick: get gather_stone, complete it
	goal = result1["active_goal"]
	goal["current_progress"] = 5  # simulate completion (target is 5)
	var result2 := GP.process_tick(goal, completed_ids, game_state)
	assert(result2["was_completed"], "second tick should complete")
	assert(result2["active_goal"]["id"] == "gather_food", "should rotate to gather_food")

	return {"ok": true}
