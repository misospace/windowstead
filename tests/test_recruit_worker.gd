## Tests for recruit worker decision logic (issue #149, links to #133, #135).
## Verifies: successful recruit, blocked recruit at cap, name cycling, food impact messaging.
## Uses main.gd instance — no reimplemented logic.

extends SceneTree

const H := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	# Preload and create GameState before creating Main, since main.gd references
	# GameState in method bodies and it's not available as an autoload in standalone mode.
	var game_state_script := preload("res://scripts/game_state.gd")
	var game_state := game_state_script.new()
	root.add_child(game_state)

	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = preload("res://scripts/main.gd")
	var main: Control = main_script.new()

	test_can_recruit_with_capacity(main)
	test_cannot_recruit_at_cap(main)
	test_recruit_adds_worker_to_state(main)
	test_recruit_cycles_through_names(main)
	test_recruit_with_no_workers_returns_true(main)
	test_food_impact_messaging_for_extra_workers(main)
	test_food_impact_no_upkeep_when_under_threshold(main)

	# Summary
	H.print_summary(H.pass + H.fail)


func test_can_recruit_with_capacity(main: Control) -> void:
	print("")
	print("--- recruit with capacity ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0}],
		"tiles": [],
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}
	# Cap is 4 (base 2 + hut bonus 2), 1 worker -> can recruit
	H.assert(main.can_recruit_worker(), "can_recruit: returns true when under cap (1/4)")


func test_cannot_recruit_at_cap(main: Control) -> void:
	print("")
	print("--- blocked at cap ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [
			{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Mara", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
		],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	# Cap is 2 (base), 2 workers -> cannot recruit
	H.assert(not main.can_recruit_worker(), "can_recruit: returns false at cap (2/2)")


func test_recruit_adds_worker_to_state(main: Control) -> void:
	print("")
	print("--- recruit adds worker ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0}],
		"tiles": [],
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}
	H.assert(main.can_recruit_worker(), "precondition: can recruit")
	var initial_count: int = main.state.workers.size()
	main.recruit_worker()
	H.assert_eq(main.state.workers.size(), initial_count + 1, "recruit: state workers count increases by 1")


func test_recruit_cycles_through_names(main: Control) -> void:
	print("")
	print("--- name cycling ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}
	# First recruit should pick index 0 ("Jun")
	main.recruit_worker()
	H.assert_eq(main.state.workers[0].name, "Jun", "first recruit gets first name 'Jun'")

	# Second recruit should pick index 1 ("Mara")
	main.recruit_worker()
	H.assert_eq(main.state.workers[1].name, "Mara", "second recruit gets second name 'Mara'")

	# Third recruit should wrap to index 0 again ("Jun")
	main.recruit_worker()
	H.assert_eq(main.state.workers[2].name, "Jun", "third recruit wraps to first name 'Jun'")


func test_recruit_with_no_workers_returns_true(main: Control) -> void:
	print("")
	print("--- recruit with no workers ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	H.assert(main.can_recruit_worker(), "can_recruit: returns true when no workers (empty state)")


func test_food_impact_messaging_for_extra_workers(main: Control) -> void:
	print("")
	print("--- food impact messaging ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [
			{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Mara", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
		],
		"tiles": [],
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}
	# At base threshold (2 workers), extra = 0, so recruiting the 3rd triggers food cost
	main.recruit_worker()
	var found_food_msg := false
	for evt in main.state.events:
		if "Food impact" in str(evt.get("text", "")):
			found_food_msg = true
	H.assert(found_food_msg, "recruit extra worker: food impact message logged")


func test_food_impact_no_upkeep_when_under_threshold(main: Control) -> void:
	print("")
	print("--- no food cost under threshold ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0}],
		"next_build_id": 2,
		"reserved_resources": {},
		"events": [],
	}
	main.recruit_worker()
	var found_food_msg := false
	for evt in main.state.events:
		if "Food impact" in str(evt.get("text", "")):
			found_food_msg = true
	H.assert(not found_food_msg, "recruit under threshold: no food impact message")
