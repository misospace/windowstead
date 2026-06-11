extends SceneTree
# Tests for rotating_goal.gd — misospace/windowstead#142

var test_pass := 0
var test_fail := 0

func _initialize() -> void:
	var goal_script := load("res://scripts/rotating_goal.gd")

	test_catalog_exists(goal_script)
	test_apply_goal_template(goal_script)
	test_select_next_active_goal(goal_script)
	test_update_resource_progress(goal_script)
	test_compute_resource_progress(goal_script)
	test_compute_build_progress(goal_script)
	test_compute_build_complete_progress(goal_script)
	test_is_goal_complete(goal_script)
	test_complete_goal_noop_reward(goal_script)
	test_rotate_after_completion(goal_script)
	test_reward_preview_text(goal_script)

	print("")
	print("=== test_rotating_goal summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("test_rotating_goal: ok")
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

func test_catalog_exists(gs: Variant) -> void:
	print("")
	print("--- catalog ---")

	var catalog = gs.GOAL_CATALOG
	_assert(catalog.size() > 0, "catalog_not_empty")
	_assert_eq(catalog.size(), 7, "catalog_size_7_entries")

	# Check expected types are present
	var types := {}
	for entry in catalog:
		types[entry["type"]] = true
	_assert(types.has(gs.GOAL_TYPE_RESOURCE), "catalog_has_resource_type")
	_assert(types.has(gs.GOAL_TYPE_BUILD), "catalog_has_build_type")
	_assert(types.has(gs.GOAL_TYPE_BUILD_COMPLETE), "catalog_has_build_complete_type")

	# Check all 7 goal IDs
	var ids := ["gather_wood", "gather_stone", "gather_food", "build_hut", "build_workshop", "build_garden", "any_build"]
	for id in ids:
		_assert(gs.GOAL_CATALOG.any(func(e): return e["id"] == id), "catalog_has_id_%s" % id)


func test_apply_goal_template(gs: Variant) -> void:
	print("")
	print("--- apply_goal_template ---")

	var template = gs.GOAL_CATALOG[0]  # gather_wood
	var goal = gs.apply_goal_template(template)

	_assert_str_eq(goal["id"], "gather_wood", "template_id")
	_assert_str_eq(goal["type"], gs.GOAL_TYPE_RESOURCE, "template_type")
	_assert_eq(goal["target"]["resource"], "wood", "template_target_resource")
	_assert_eq(goal["target"]["amount"], 10, "template_target_amount")
	_assert_eq(goal["current_progress"], 0, "template_progress_starts_zero")
	_assert(not goal["completed"], "template_not_completed")

	# Verify target is a deep copy (modifying one doesn't affect catalog)
	goal["target"]["amount"] = 999
	_assert_eq(gs.GOAL_CATALOG[0]["target"]["amount"], 10, "template_deep_copies_target")


func test_select_next_active_goal(gs: Variant) -> void:
	print("")
	print("--- select_next_active_goal ---")

	# First call: should return first catalog entry (gather_wood)
	var goal = gs.select_next_active_goal([])
	_assert_str_eq(goal["id"], "gather_wood", "select_first_returns_gather_wood")
	_assert(not goal.is_empty(), "select_returns_non_empty")

	# Skip gather_wood: should return gather_stone
	goal = gs.select_next_active_goal(["gather_wood"])
	_assert_str_eq(goal["id"], "gather_stone", "select_skips_completed")

	# Skip all but last: should return any_build
	var completed := ["gather_wood", "gather_stone", "gather_food", "build_hut", "build_workshop", "build_garden"]
	goal = gs.select_next_active_goal(completed)
	_assert_str_eq(goal["id"], "any_build", "select_returns_last_remaining")

	# All completed: should return empty dict
	goal = gs.select_next_active_goal(gs.GOAL_CATALOG.map(func(e): return e["id"]))
	_assert(goal.is_empty(), "select_all_completed_returns_empty")


func test_update_resource_progress(gs: Variant) -> void:
	print("")
	print("--- update_resource_progress ---")

	var goal := {"id": "gather_wood", "type": gs.GOAL_TYPE_RESOURCE, "target": {"resource": "wood", "amount": 10}, "current_progress": 0, "completed": false}  # gather_wood, target=10

	gs.update_resource_progress(goal, 3)
	_assert_eq(goal["current_progress"], 3, "progress_add_3")

	gs.update_resource_progress(goal, 5)
	_assert_eq(goal["current_progress"], 8, "progress_add_5_more")

	gs.update_resource_progress(goal, 10)  # should clamp at 10
	_assert_eq(goal["current_progress"], 10, "progress_clamped_at_target")


func test_compute_resource_progress(gs: Variant) -> void:
	print("")
	print("--- compute_resource_progress ---")

	var goal = gs.apply_goal_template(gs.GOAL_CATALOG[1])  # gather_stone, target=5

	var game_state := {
		"harvested": {"wood": 3, "stone": 4, "food": 2},
	}
	gs.compute_resource_progress(goal, game_state)
	_assert_eq(goal["current_progress"], 4, "compute_stone_from_harvested")

	game_state = {
		"harvested": {"iron": 1},
	}
	var goal2 = gs.apply_goal_template(gs.GOAL_CATALOG[0])  # gather_wood
	gs.compute_resource_progress(goal2, game_state)
	_assert_eq(goal2["current_progress"], 0, "compute_missing_resource_is_zero")


func test_compute_build_progress(gs: Variant) -> void:
	print("")
	print("--- compute_build_progress ---")

	var goal = gs.apply_goal_template(gs.GOAL_CATALOG[3])  # build_hut

	var game_state := {
		"builds": [
			{"kind": "hut", "id": 1},
			{"kind": "workshop", "id": 2},
			{"kind": "hut", "id": 3},
		],
	}
	gs.compute_build_progress(goal, game_state)
	_assert_eq(goal["current_progress"], 2, "compute_build_counts_target_kind")

	# No builds of target kind
	var goal2 = gs.apply_goal_template(gs.GOAL_CATALOG[4])  # build_workshop
	var game_state2 := {
		"builds": [{"kind": "hut", "id": 1}],
	}
	gs.compute_build_progress(goal2, game_state2)
	_assert_eq(goal2["current_progress"], 0, "compute_build_no_match_is_zero")


func test_compute_build_complete_progress(gs: Variant) -> void:
	print("")
	print("--- compute_build_complete_progress ---")

	var goal = gs.apply_goal_template(gs.GOAL_CATALOG[6])  # any_build

	var game_state := {
		"builds": [
			{"kind": "hut", "id": 1},
			{"kind": "workshop", "id": 2},
		],
	}
	gs.compute_build_complete_progress(goal, game_state)
	_assert_eq(goal["current_progress"], 2, "build_complete_counts_all_builds")

	var game_state_empty := {"builds": []}
	gs.compute_build_complete_progress(goal, game_state_empty)
	_assert_eq(goal["current_progress"], 0, "build_complete_no_builds_is_zero")


func test_is_goal_complete(gs: Variant) -> void:
	print("")
	print("--- is_goal_complete ---")

	# Resource goal: not complete at 0
	var goal := {"id": "gather_wood", "type": gs.GOAL_TYPE_RESOURCE, "target": {"resource": "wood", "amount": 10}, "current_progress": 0, "completed": false}  # gather_wood, target=10
	_assert(not gs.is_goal_complete(goal), "resource_not_complete_at_zero")

	gs.update_resource_progress(goal, 10)
	_assert(gs.is_goal_complete(goal), "resource_complete_at_target")

	# Build goal: not complete at 0 progress
	goal = gs.apply_goal_template(gs.GOAL_CATALOG[3])  # build_hut
	_assert(not gs.is_goal_complete(goal), "build_not_complete_at_zero")

	goal["current_progress"] = 1
	_assert(gs.is_goal_complete(goal), "build_complete_with_one_build")

	# Build-complete goal
	goal = gs.apply_goal_template(gs.GOAL_CATALOG[6])  # any_build
	_assert(not gs.is_goal_complete(goal), "build_complete_not_at_zero")

	goal["current_progress"] = 1
	_assert(gs.is_goal_complete(goal), "build_complete_complete_with_one_build")


func test_complete_goal_noop_reward(gs: Variant) -> void:
	print("")
	print("--- complete_goal_noop_reward ---")

	var goal := {"id": "gather_wood", "type": gs.GOAL_TYPE_RESOURCE, "target": {"resource": "wood", "amount": 10}, "current_progress": 0, "completed": false}
	_assert(not goal["completed"], "goal_not_completed_initially")

	gs.complete_goal(goal)
	_assert(goal["completed"], "goal_marked_completed")

	# Verify no reward field was added (no-op completion)
	_assert(not goal.has("reward"), "complete_no_reward_field_added")


func test_rotate_after_completion(gs: Variant) -> void:
	print("")
	print("--- rotate_after_completion ---")

	# Test 1: Rotate from gather_wood → gather_stone, no prior completed IDs
	var active = gs.apply_goal_template(gs.GOAL_CATALOG[0])  # gather_wood
	var new_goal = gs.rotate_after_completion(active, [])
	_assert_str_eq(new_goal["id"], "gather_stone", "rotate_from_wood_to_stone_no_prior")
	_assert(active["completed"], "active_goal_marked_completed")
	_assert(not new_goal["completed"], "new_goal_not_completed")
	_assert_eq(new_goal["current_progress"], 0, "new_goal_progress_starts_zero")

	# Test 2: Rotate with prior completed IDs — skip them
	active = gs.apply_goal_template(gs.GOAL_CATALOG[1])  # gather_stone
	new_goal = gs.rotate_after_completion(active, ["gather_wood"])
	_assert_str_eq(new_goal["id"], "gather_food", "rotate_skips_prior_completed")

	# Test 3: Rotate from last goal (any_build) → empty when all done
	active = gs.apply_goal_template(gs.GOAL_CATALOG[6])  # any_build
	var all_ids := ["gather_wood", "gather_stone", "gather_food", "build_hut", "build_workshop", "build_garden"]
	new_goal = gs.rotate_after_completion(active, all_ids)
	_assert(new_goal.is_empty(), "rotate_all_done_returns_empty")

	# Test 4: Completed goal does not immediately repeat — verify active_goal's ID is in the skip set
	active = gs.apply_goal_template(gs.GOAL_CATALOG[0])  # gather_wood
	new_goal = gs.rotate_after_completion(active, [])
	_assert_str_eq(new_goal["id"], "gather_stone", "no_immediate_repeat_of_active")

	# Test 5: Completed IDs passed in are deduplicated (duplicates shouldn't cause issues)
	active = gs.apply_goal_template(gs.GOAL_CATALOG[2])  # gather_food
	new_goal = gs.rotate_after_completion(active, ["gather_wood", "gather_wood"])
	_assert_str_eq(new_goal["id"], "gather_stone", "deduplicate_prior_completed_ids")

	# Test 6: Rotation chains correctly — complete one, get next, complete that, get next
	active = gs.apply_goal_template(gs.GOAL_CATALOG[0])  # gather_wood
	var completed_ids := []
	var chain := []
	for _i in range(3):
		new_goal = gs.rotate_after_completion(active, completed_ids)
		if new_goal.is_empty():
			break
		chain.append(new_goal["id"])
		completed_ids.append(active["id"])
		active = new_goal
	_assert_eq(chain.size(), 3, "rotation_chain_length_3")
	_assert_str_eq(chain[0], "gather_stone", "chain_step_1_gather_stone")
	_assert_str_eq(chain[1], "gather_food", "chain_step_2_gather_food")
	_assert_str_eq(chain[2], "build_hut", "chain_step_3_build_hut")


func test_reward_preview_text(gs: Variant) -> void:
	print("")
	print("--- reward preview ---")

	# Test 1: Resource goal with reward text
	var goal := {"id": "gather_wood", "type": gs.GOAL_TYPE_RESOURCE, "target": {"resource": "wood", "amount": 10}, "current_progress": 0, "completed": false, "reward": "+1 food"}  # gather_wood, reward="+1 food"
	var preview = gs.get_reward_preview_text(goal)
	_assert_str_eq(preview, "Reward: +1 food", "resource_goal_has_reward_preview")

	# Test 2: Build goal with reward text
	goal = gs.apply_goal_template(gs.GOAL_CATALOG[3])  # build_hut, reward="haul speed +10%"
	preview = gs.get_reward_preview_text(goal)
	_assert_str_eq(preview, "Reward: haul speed +10%", "build_goal_has_reward_preview")

	# Test 3: Goal without reward field returns empty string
	var no_reward := {"id": "custom", "type": gs.GOAL_TYPE_RESOURCE, "target": {"resource": "wood", "amount": 5}, "current_progress": 0, "completed": false}
	preview = gs.get_reward_preview_text(no_reward)
	_assert_str_eq(preview, "", "goal_without_reward_field_returns_empty")

	# Test 4: Goal with empty reward string returns empty
	var empty_reward := no_reward.duplicate()
	empty_reward["reward"] = ""
	preview = gs.get_reward_preview_text(empty_reward)
	_assert_str_eq(preview, "", "goal_with_empty_reward_returns_empty")

	# Test 5: Empty goal dict returns empty
	var empty_goal := {}
	preview = gs.get_reward_preview_text(empty_goal)
	_assert_str_eq(preview, "", "empty_goal_returns_empty")

	# Test 6: Compact dock UI fit — reward text should be short enough for compact label
	goal = gs.apply_goal_template(gs.GOAL_CATALOG[5])  # build_garden, reward="ambient event improves"
	preview = gs.get_reward_preview_text(goal)
	_assert(preview.length() < 40, "reward_preview_fits_compact_dock")
	_assert_str_eq(preview, "Reward: ambient event improves", "garden_goal_reward_preview")

	# Test 7: all catalog goals have non-empty reward strings
	for entry in gs.GOAL_CATALOG:
		var g = gs.apply_goal_template(entry)
		var p = gs.get_reward_preview_text(g)
		_assert(not p.is_empty(), "catalog_entry_%s_has_reward" % entry["id"])
