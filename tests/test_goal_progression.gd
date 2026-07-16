## Regression tests for GoalProgression — pure game logic extracted from main.gd.
## Tests the extracted domain controller for goal lifecycle management.
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --path . --script res://tests/test_goal_progression.gd

extends "res://tests/test_case.gd"

const GP := preload("res://scripts/goal_progression.gd")
const RG := preload("res://scripts/rotating_goal.gd")


func run_tests() -> void:
	# --- init_goals ---
	_test_init_goals_first()
	_test_init_goals_skip_completed()
	_test_init_goals_all_done()

	# --- compute_progress (resource) ---
	_test_compute_resource_progress()
	_test_compute_resource_no_op()

	# --- compute_progress (build) ---
	_test_compute_build_progress()
	_test_compute_build_no_op()

	# --- check_and_rotate (no completion) ---
	_test_check_rotate_not_complete()

	# --- check_and_rotate (completion + rotation) ---
	_test_check_rotate_completes()
	_test_check_rotate_appends_id()
	_test_check_rotate_was_completed()

	# --- process_tick (full flow) ---
	_test_process_tick_flow()
	_test_process_tick_empty_goal()

	# --- Integration: multi-goal rotation ---
	_test_multi_goal_rotation()


# --- Individual tests ---

func _test_init_goals_first() -> void:
	var result := GP.init_goals([])
	assert_eq(result.get("id", ""), "gather_wood", "init_goals returns first non-completed goal")


func _test_init_goals_skip_completed() -> void:
	var result := GP.init_goals(["gather_wood"])
	assert_eq(result.get("id", ""), "gather_stone", "init_goals skips completed goals")


func _test_init_goals_all_done() -> void:
	var all_ids := []
	for t in RG.GOAL_CATALOG:
		all_ids.append(t["id"])
	var result := GP.init_goals(all_ids)
	assert_true(result.is_empty(), "init_goals returns empty dict when all done", "expected empty dict, got %s" % str(result))


func _test_compute_resource_progress() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	var game_state := {"harvested": {"wood": 5}}
	GP.compute_progress(goal, game_state)
	assert_eq(goal["current_progress"], 5, "compute_progress updates resource progress from game_state")


func _test_compute_resource_no_op() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[3])  # build_hut (non-resource)
	var game_state := {"harvested": {"wood": 100}}
	GP.compute_progress(goal, game_state)
	assert_eq(goal["current_progress"], 0, "compute_progress does nothing for non-resource goals")


func _test_compute_build_progress() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[3])  # build_hut
	var game_state := {"builds": [{"kind": "hut"}, {"kind": "hut"}, {"kind": "workshop"}]}
	GP.compute_progress(goal, game_state)
	assert_eq(goal["current_progress"], 2, "compute_progress updates build progress from builds array")


func _test_compute_build_no_op() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood (non-build)
	var game_state := {"builds": [{"kind": "hut"}]}
	GP.compute_progress(goal, game_state)
	assert_eq(goal["current_progress"], 0, "compute_progress ignores non-build goals")


func _test_check_rotate_not_complete() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	goal["current_progress"] = 5  # not complete yet
	var completed_ids := []
	var result := GP.check_and_rotate(goal, completed_ids)
	assert_false(result["was_completed"], "check_and_rotate returns unchanged when not complete", "expected was_completed=false when not done")
	assert_eq(result["goal_id"], "", "check_and_rotate not complete: empty goal_id")
	# check_and_rotate returns the ORIGINAL goal reference in the not-completed case.
	assert_eq(result["active_goal"]["id"], "gather_wood", "check_and_rotate not complete: active_goal unchanged")


func _test_check_rotate_completes() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	goal["current_progress"] = 10  # complete
	var completed_ids := []
	var result := GP.check_and_rotate(goal, completed_ids)
	assert_true(result["was_completed"], "check_and_rotate marks completed and rotates to next goal")
	assert_eq(result["goal_id"], "gather_wood", "check_and_rotate completes: goal_id is gather_wood")
	assert_eq(result["active_goal"].get("id", ""), "gather_stone", "check_and_rotate completes: rotates to gather_stone")


func _test_check_rotate_appends_id() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood
	goal["current_progress"] = 10
	var completed_ids := ["some_old_id"]
	var result := GP.check_and_rotate(goal, completed_ids)
	assert_true(result["completed_ids"].has("gather_wood"), "check_and_rotate appends completed ID to completed_ids")
	assert_eq(result["completed_ids"].size(), 2, "check_and_rotate appends: 2 completed IDs")


func _test_check_rotate_was_completed() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])
	goal["current_progress"] = 10
	var completed_ids := []
	var result := GP.check_and_rotate(goal, completed_ids)
	assert_true(result["was_completed"], "check_and_rotate returns was_completed=true on rotation")


func _test_process_tick_flow() -> void:
	var goal = RG.apply_goal_template(RG.GOAL_CATALOG[0])  # gather_wood, target 10
	var completed_ids := []
	# process_tick recomputes progress from game_state, so completion must
	# come from harvested amounts.
	var game_state := {"harvested": {"wood": 10}}
	var result := GP.process_tick(goal, completed_ids, game_state)
	assert_true(result["was_completed"], "process_tick computes progress and detects completion in one call")
	assert_eq(result["active_goal"].get("id", ""), "gather_stone", "process_tick flow: rotates to gather_stone")


func _test_process_tick_empty_goal() -> void:
	var goal := {}
	var completed_ids := []
	var game_state := {"harvested": {}}
	var result := GP.process_tick(goal, completed_ids, game_state)
	assert_false(result["was_completed"], "process_tick with empty goal returns unchanged result", "expected was_completed=false for empty goal")
	assert_true(result["active_goal"].is_empty(), "process_tick empty goal: active_goal stays empty")


func _test_multi_goal_rotation() -> void:
	# Simulate completing two goals in sequence via process_tick.
	var completed_ids := []

	# First tick: gather_wood. process_tick recomputes progress from
	# game_state, so drive completion through harvested amounts (the old
	# manually-set current_progress was overwritten by compute_progress and
	# the test aborted via bare assert()).
	var goal = GP.init_goals(completed_ids)
	if not assert_true(not goal.is_empty(), "multi-goal rotation: should have initial goal"):
		return
	var game_state := {"harvested": {"wood": 10, "stone": 5}}
	var result1 := GP.process_tick(goal, completed_ids, game_state)
	assert_true(result1["was_completed"], "multi-goal rotation: completes first, rotates to second", "first tick should complete")
	assert_eq(result1["active_goal"].get("id", ""), "gather_stone", "multi-goal rotation: should rotate to gather_stone")
	completed_ids = result1["completed_ids"]

	# Second tick: gather_stone completes (target 5, harvested stone = 5).
	goal = result1["active_goal"]
	var result2 := GP.process_tick(goal, completed_ids, game_state)
	assert_true(result2["was_completed"], "multi-goal rotation: second tick should complete")
	assert_eq(result2["active_goal"].get("id", ""), "gather_food", "multi-goal rotation: should rotate to gather_food")
