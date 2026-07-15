extends "res://tests/test_case.gd"
# Tests for milestone_manager.gd — misospace/windowstead#132

const MS := preload("res://scripts/milestone_manager.gd")


func run_tests() -> void:
	test_catalog_exists(MS)
	test_make_goal_state(MS)
	test_get_current_milestone(MS)
	test_evaluate_build_milestone(MS)
	test_evaluate_stockpile_milestone(MS)
	test_evaluate_worker_milestone(MS)
	test_is_milestone_complete(MS)
	test_advance_to_next(MS)
	test_milestone_description(MS)
	test_save_load_compatibility(MS)


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_catalog_exists(ms: Variant) -> void:
	print("")
	print("--- catalog ---")

	var catalog = ms.MILESTONE_CATALOG
	assert_true(catalog.size() > 0, "catalog_not_empty")
	assert_eq(catalog.size(), 5, "catalog_has_5_entries")

	# Check expected types are present
	var types := {}
	for entry in catalog:
		types[entry["type"]] = true
	assert_true(types.has(ms.MILESTONE_TYPE_BUILD), "catalog_has_build_type")
	assert_true(types.has(ms.MILESTONE_TYPE_STOCKPILE), "catalog_has_stockpile_type")
	assert_true(types.has(ms.MILESTONE_TYPE_WORKER), "catalog_has_worker_type")

	# Check all 5 milestone IDs from the issue examples
	var expected_ids := ["build_hut", "stockpile_food", "build_workshop", "build_garden", "support_third_worker"]
	for eid in expected_ids:
		assert_true(catalog.any(func(e): return e["id"] == eid), "catalog_has_id_%s" % eid)

	# Check each entry has required fields
	for entry in catalog:
		assert_true(entry.has("id"), "entry_%s_has_id" % entry.get("id", "?"))
		assert_true(entry.has("name"), "entry_%s_has_name" % entry.get("id", "?"))
		assert_true(entry.has("type"), "entry_%s_has_type" % entry.get("id", "?"))
		assert_true(entry.has("target"), "entry_%s_has_target" % entry.get("id", "?"))
		assert_true(entry.has("description"), "entry_%s_has_description" % entry.get("id", "?"))

	# Verify order matches the issue example chain
	assert_eq(catalog[0]["id"], "build_hut", "first_milestone_is_build_hut")
	assert_eq(catalog[1]["id"], "stockpile_food", "second_milestone_is_stockpile_food")
	assert_eq(catalog[2]["id"], "build_workshop", "third_milestone_is_build_workshop")
	assert_eq(catalog[3]["id"], "build_garden", "fourth_milestone_is_build_garden")
	assert_eq(catalog[4]["id"], "support_third_worker", "fifth_milestone_is_support_third_worker")


func test_make_goal_state(ms: Variant) -> void:
	print("")
	print("--- make_goal_state ---")

	var state = ms.make_goal_state()
	assert_true(state.has("milestone_id"), "state_has_milestone_id")
	assert_true(state.has("completed_ids"), "state_has_completed_ids")
	assert_eq(state["milestone_id"], "build_hut", "goal_starts_at_first_milestone")
	assert_eq(state["completed_ids"].size(), 0, "goal_has_empty_completed_ids")

	# Verify completed_ids is a fresh array (not shared)
	state["completed_ids"].append("fake")
	var state2 = ms.make_goal_state()
	assert_eq(state2["completed_ids"].size(), 0, "fresh_state_has_no_contamination")


func test_get_current_milestone(ms: Variant) -> void:
	print("")
	print("--- get_current_milestone ---")

	var current = ms.get_current_milestone(ms.MILESTONE_CATALOG, "build_hut")
	assert_eq(current["id"], "build_hut", "get_returns_correct_id")
	assert_eq(current["name"], "Build a hut", "get_returns_correct_name")

	# Non-existent milestone returns empty dict
	var missing = ms.get_current_milestone(ms.MILESTONE_CATALOG, "nonexistent")
	assert_true(missing.is_empty(), "get_nonexistent_returns_empty")


func test_evaluate_build_milestone(ms: Variant) -> void:
	print("")
	print("--- evaluate_build_milestone ---")

	# Build hut not yet built
	var game_state := {
		"builds": [
			{"kind": "hut", "complete": false, "id": 1},
			{"kind": "workshop", "complete": true, "id": 2},
		],
	}
	var hut_milestone = ms.MILESTONE_CATALOG[0]  # build_hut
	var result = ms.evaluate_milestone(hut_milestone, game_state)
	assert_eq(result["progress"], 0, "hut_not_built_yet_progress_0")
	assert_eq(result["total"], 1, "hut_total_is_1")

	# Build hut completed
	game_state = {
		"builds": [
			{"kind": "hut", "complete": true, "id": 1},
			{"kind": "workshop", "complete": true, "id": 2},
		],
	}
	result = ms.evaluate_milestone(hut_milestone, game_state)
	assert_eq(result["progress"], 1, "hut_built_progress_1")

	# Build workshop not yet built
	var workshop_milestone = ms.MILESTONE_CATALOG[2]  # build_workshop
	game_state = {
		"builds": [
			{"kind": "hut", "complete": true, "id": 1},
		],
	}
	result = ms.evaluate_milestone(workshop_milestone, game_state)
	assert_eq(result["progress"], 0, "workshop_not_built_progress_0")

	game_state = {
		"builds": [
			{"kind": "hut", "complete": true, "id": 1},
			{"kind": "workshop", "complete": true, "id": 2},
		],
	}
	result = ms.evaluate_milestone(workshop_milestone, game_state)
	assert_eq(result["progress"], 1, "workshop_built_progress_1")

	# No builds at all
	game_state = {"builds": []}
	result = ms.evaluate_milestone(hut_milestone, game_state)
	assert_eq(result["progress"], 0, "no_builds_progress_0")


func test_evaluate_stockpile_milestone(ms: Variant) -> void:
	print("")
	print("--- evaluate_stockpile_milestone ---")

	var stockpile_milestone = ms.MILESTONE_CATALOG[1]  # stockpile_food, target=10

	# No food harvested
	var game_state := {"harvested": {}}
	var result = ms.evaluate_milestone(stockpile_milestone, game_state)
	assert_eq(result["progress"], 0, "stockpile_no_harvest_progress_0")
	assert_eq(result["total"], 10, "stockpile_total_is_10")

	# Partial progress
	game_state = {"harvested": {"food": 4}}
	result = ms.evaluate_milestone(stockpile_milestone, game_state)
	assert_eq(result["progress"], 4, "stockpile_partial_progress_4")

	# Exactly at target
	game_state = {"harvested": {"food": 10}}
	result = ms.evaluate_milestone(stockpile_milestone, game_state)
	assert_eq(result["progress"], 10, "stockpile_at_target_progress_10")

	# Over target (should clamp)
	game_state = {"harvested": {"food": 15, "wood": 3}}
	result = ms.evaluate_milestone(stockpile_milestone, game_state)
	assert_eq(result["progress"], 10, "stockpile_clamped_at_target")

	# Other resources shouldn't interfere
	game_state = {"harvested": {"wood": 50}}
	result = ms.evaluate_milestone(stockpile_milestone, game_state)
	assert_eq(result["progress"], 0, "stockpile_other_resource_ignored")


func test_evaluate_worker_milestone(ms: Variant) -> void:
	print("")
	print("--- evaluate_worker_milestone ---")

	var worker_milestone = ms.MILESTONE_CATALOG[4]  # support_third_worker, target=3

	# No workers
	var game_state := {"workers": []}
	var result = ms.evaluate_milestone(worker_milestone, game_state)
	assert_eq(result["progress"], 0, "worker_no_workers_progress_0")
	assert_eq(result["total"], 3, "worker_total_is_3")

	# One active worker (break_ticks == 0 means active)
	game_state = {
		"workers": [
			{"name": "w1", "break_ticks": 0},
		],
	}
	result = ms.evaluate_milestone(worker_milestone, game_state)
	assert_eq(result["progress"], 1, "worker_one_active")

	# Two active workers
	game_state = {
		"workers": [
			{"name": "w1", "break_ticks": 0},
			{"name": "w2", "break_ticks": 0},
		],
	}
	result = ms.evaluate_milestone(worker_milestone, game_state)
	assert_eq(result["progress"], 2, "worker_two_active")

	# Three active workers (milestone complete)
	game_state = {
		"workers": [
			{"name": "w1", "break_ticks": 0},
			{"name": "w2", "break_ticks": 0},
			{"name": "w3", "break_ticks": 0},
		],
	}
	result = ms.evaluate_milestone(worker_milestone, game_state)
	assert_eq(result["progress"], 3, "worker_three_active_progress_3")

	# Worker with break_ticks > 0 is not active
	game_state = {
		"workers": [
			{"name": "w1", "break_ticks": 0},
			{"name": "w2", "break_ticks": 5},
			{"name": "w3", "break_ticks": 0},
		],
	}
	result = ms.evaluate_milestone(worker_milestone, game_state)
	assert_eq(result["progress"], 2, "worker_excludes_broken_out")


func test_is_milestone_complete(ms: Variant) -> void:
	print("")
	print("--- is_milestone_complete ---")

	var game_state := {
		"builds": [{"kind": "hut", "complete": true, "id": 1}],
		"harvested": {"food": 10},
		"workers": [
			{"name": "w1", "break_ticks": 0},
			{"name": "w2", "break_ticks": 0},
			{"name": "w3", "break_ticks": 0},
		],
	}

	# Build hut should be complete
	var hut_milestone = ms.MILESTONE_CATALOG[0]
	assert_true(ms.is_milestone_complete(hut_milestone, game_state), "hut_complete_when_built")

	# Stockpile food should be complete
	var stockpile_milestone = ms.MILESTONE_CATALOG[1]
	assert_true(ms.is_milestone_complete(stockpile_milestone, game_state), "stockpile_complete_at_target")

	# Support third worker should be complete
	var worker_milestone = ms.MILESTONE_CATALOG[4]
	assert_true(ms.is_milestone_complete(worker_milestone, game_state), "worker_complete_at_three")

	# Workshop should NOT be complete
	var workshop_milestone = ms.MILESTONE_CATALOG[2]
	assert_true(not ms.is_milestone_complete(workshop_milestone, game_state), "workshop_not_complete_without_build")

	# Garden should NOT be complete
	var garden_milestone = ms.MILESTONE_CATALOG[3]
	assert_true(not ms.is_milestone_complete(garden_milestone, game_state), "garden_not_complete_without_build")

	# Empty game state — nothing should be complete
	var empty_state := {}
	assert_true(not ms.is_milestone_complete(hut_milestone, empty_state), "hut_not_complete_empty_state")


func test_advance_to_next(ms: Variant) -> void:
	print("")
	print("--- advance_to_next ---")

	# Advance from build_hut → stockpile_food
	var next = ms.advance_to_next([], "build_hut")
	assert_eq(next, "stockpile_food", "advance_from_hut_to_stockpile")

	# Advance from stockpile_food → build_workshop
	next = ms.advance_to_next(["build_hut"], "stockpile_food")
	assert_eq(next, "build_workshop", "advance_from_stockpile_to_workshop")

	# Advance through the chain
	next = ms.advance_to_next(["build_hut", "stockpile_food"], "build_workshop")
	assert_eq(next, "build_garden", "advance_from_workshop_to_garden")

	next = ms.advance_to_next(["build_hut", "stockpile_food", "build_workshop"], "build_garden")
	assert_eq(next, "support_third_worker", "advance_from_garden_to_worker")

	# Last milestone — should return itself (no next)
	next = ms.advance_to_next(["build_hut", "stockpile_food", "build_workshop", "build_garden"], "support_third_worker")
	assert_eq(next, "support_third_worker", "last_milestone_returns_itself")

	# Unknown milestone ID — should return itself (defensive)
	next = ms.advance_to_next([], "nonexistent")
	assert_eq(next, "nonexistent", "unknown_id_returns_itself")

	# Full chain traversal
	var completed_ids := []
	var current_id := "build_hut"
	var chain := ["build_hut"]
	for i in range(4):
		current_id = ms.advance_to_next(completed_ids, current_id)
		completed_ids.append(current_id)
		chain.append(current_id)
	# MILESTONE_CATALOG has 5 entries, so the full chain visits 5 milestones
	# (4 transitions) — the old expectation of 6 was stale.
	assert_eq(chain.size(), 5, "full_chain_has_5_transitions")
	assert_eq(chain[0], "build_hut", "chain_starts_with_hut")
	assert_eq(chain[1], "stockpile_food", "chain_step_2_stockpile")
	assert_eq(chain[2], "build_workshop", "chain_step_3_workshop")
	assert_eq(chain[3], "build_garden", "chain_step_4_garden")
	assert_eq(chain[4], "support_third_worker", "chain_step_5_worker")


func test_milestone_description(ms: Variant) -> void:
	print("")
	print("--- milestone_description ---")

	var hut_milestone = ms.MILESTONE_CATALOG[0]
	var desc = ms.milestone_description(hut_milestone)
	assert_eq(desc, "Your first shelter. The crew gets a roof.", "hut_description_matches")

	var worker_milestone = ms.MILESTONE_CATALOG[4]
	desc = ms.milestone_description(worker_milestone)
	assert_eq(desc, "A full crew. The colony is growing.", "worker_description_matches")

	# Milestone without description field returns default
	var no_desc := {"id": "test", "description": ""}
	desc = ms.milestone_description(no_desc)
	assert_eq(desc, "", "empty_description_returns_empty")


func test_save_load_compatibility(ms: Variant) -> void:
	print("")
	print("--- save_load_compatibility ---")

	# Test 1: Fresh milestone state serializes and round-trips correctly
	var fresh_state = ms.make_goal_state()
	var serialized = JSON.stringify(fresh_state)
	var parsed = JSON.parse_string(serialized)
	assert_true(parsed is Dictionary, "fresh_state_serializes_to_dict")
	assert_eq(parsed["milestone_id"], "build_hut", "round_trip_milestone_id")
	assert_eq(parsed["completed_ids"].size(), 0, "round_trip_empty_completed")

	# Test 2: State with completed milestones round-trips
	var state_with_progress = {
		"milestone_id": "stockpile_food",
		"completed_ids": ["build_hut"],
	}
	serialized = JSON.stringify(state_with_progress)
	parsed = JSON.parse_string(serialized)
	assert_eq(parsed["milestone_id"], "stockpile_food", "progress_milestone_id_preserved")
	assert_eq(parsed["completed_ids"].size(), 1, "progress_completed_count_preserved")
	assert_eq(parsed["completed_ids"][0], "build_hut", "progress_completed_entry_preserved")

	# Test 3: All milestones completed — state round-trips
	var all_complete = {
		"milestone_id": "support_third_worker",
		"completed_ids": ["build_hut", "stockpile_food", "build_workshop", "build_garden"],
	}
	serialized = JSON.stringify(all_complete)
	parsed = JSON.parse_string(serialized)
	assert_eq(parsed["milestone_id"], "support_third_worker", "all_complete_milestone_id")
	assert_eq(parsed["completed_ids"].size(), 4, "all_complete_completed_count")

	# Test 4: State integrates with game_state save schema (harvested/builds/workers)
	var full_save := {
		"save_version": 2,
		"builds": [{"kind": "hut", "complete": true, "id": 1}],
		"harvested": {"food": 5},
		"workers": [
			{"name": "w1", "break_ticks": 0, "spawn_tick": 0},
			{"name": "w2", "break_ticks": 0, "spawn_tick": 0},
		],
	}
	serialized = JSON.stringify(full_save)
	parsed = JSON.parse_string(serialized)
	assert_true(parsed.has("milestone_id") == false, "full_save_no_milestone_keys_yet")

	# Test 5: Milestone state can be embedded in a full save and round-trips
	var full_save_with_milestones := {
		"save_version": 2,
		"builds": [{"kind": "hut", "complete": true, "id": 1}],
		"harvested": {"food": 5},
		"workers": [
			{"name": "w1", "break_ticks": 0, "spawn_tick": 0},
			{"name": "w2", "break_ticks": 0, "spawn_tick": 0},
		],
		"milestone_state": ms.make_goal_state(),
	}
	serialized = JSON.stringify(full_save_with_milestones)
	parsed = JSON.parse_string(serialized)
	assert_true(parsed.has("milestone_state"), "full_save_has_milestone_state")
	var ms_state = parsed["milestone_state"]
	assert_eq(ms_state["milestone_id"], "build_hut", "embedded_milestone_id")
	assert_eq(ms_state["completed_ids"].size(), 0, "embedded_empty_completed")

	# Test 6: Milestone state survives save/load with completed milestones
	var saved_ms_state := {
		"milestone_id": "build_workshop",
		"completed_ids": ["build_hut", "stockpile_food"],
	}
	full_save_with_milestones["milestone_state"] = saved_ms_state
	serialized = JSON.stringify(full_save_with_milestones)
	parsed = JSON.parse_string(serialized)
	ms_state = parsed["milestone_state"]
	assert_eq(ms_state["milestone_id"], "build_workshop", "saved_milestone_id")
	assert_eq(ms_state["completed_ids"].size(), 2, "saved_completed_count")

	# Test 7: Progress evaluation with round-tripped state gives correct results
	var game_state := {
		"builds": [{"kind": "hut", "complete": true, "id": 1}],
		"harvested": {"food": 7},
		"workers": [
			{"name": "w1", "break_ticks": 0},
		],
	}
	var stockpile_milestone = ms.MILESTONE_CATALOG[1]
	var eval_result = ms.evaluate_milestone(stockpile_milestone, game_state)
	assert_eq(eval_result["progress"], 7, "stockpile_progress_from_harvested")
	assert_eq(eval_result["total"], 10, "stockpile_total_10")
	assert_true(not ms.is_milestone_complete(stockpile_milestone, game_state), "stockpile_not_yet_complete_at_7")
