## Tests for resource trend display logic (_get_trend in main.gd).
## Verifies: rising, falling, stable, and first-run (no previous data) trends.
## Uses main.gd instance — no reimplemented logic.

extends SceneTree

const H := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	# Preload and create GameState before creating Main.
	var game_state_script := load("res://scripts/game_state.gd")
	var game_state := game_state_script.new()
	root.add_child(game_state)

	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()

	test_trend_rising(main)
	test_trend_falling(main)
	test_trend_stable(main)
	test_trend_first_run_no_previous(main)
	test_trend_resource_missing_in_prev(main)

	# Summary
	H.print_summary(H.pass + H.fail)


func test_trend_rising(main: Control) -> void:
	print("")
	print("--- trend rising ---")
	main.state = {
		"tick": 5,
		"resources": {"wood": 10, "stone": 4, "food": 2},
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
	main.prev_resources = {"wood": 7}
	H.assert_eq(main._get_trend("wood"), main.RESOURCE_TRENDS["rising"], "wood trend: rising (7 -> 10)")


func test_trend_falling(main: Control) -> void:
	print("")
	print("--- trend falling ---")
	main.state = {
		"tick": 5,
		"resources": {"wood": 3, "stone": 4, "food": 2},
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
	main.prev_resources = {"wood": 7}
	H.assert_eq(main._get_trend("wood"), main.RESOURCE_TRENDS["falling"], "wood trend: falling (7 -> 3)")


func test_trend_stable(main: Control) -> void:
	print("")
	print("--- trend stable ---")
	main.state = {
		"tick": 5,
		"resources": {"wood": 5, "stone": 4, "food": 2},
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
	main.prev_resources = {"wood": 5}
	H.assert_eq(main._get_trend("wood"), main.RESOURCE_TRENDS["stable"], "wood trend: stable (5 -> 5)")


func test_trend_first_run_no_previous(main: Control) -> void:
	print("")
	print("--- trend first run no previous ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 10, "stone": 4, "food": 2},
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
	# prev_resources is empty — first run should be stable (no baseline yet)
	H.assert_eq(main._get_trend("wood"), main.RESOURCE_TRENDS["stable"], "first run: stable (no previous data)")


func test_trend_resource_missing_in_prev(main: Control) -> void:
	print("")
	print("--- trend resource missing in previous ---")
	main.state = {
		"tick": 5,
		"resources": {"wood": 10, "stone": 4, "food": 2},
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
	main.prev_resources = {"stone": 3}
	# wood not in prev_resources — previous defaults to -1, so current > previous → rising
	H.assert_eq(main._get_trend("wood"), main.RESOURCE_TRENDS["rising"], "missing prev resource: treated as rising")
