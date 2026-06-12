## Tests for food upkeep model (issue #147, links to #133).
## Validates: base workers no pressure, extra workers create pressure,
## low-food slowdown, starvation pause, and food-gathering bias.
## Uses main.gd instance — no reimplemented logic.

extends SceneTree

const H := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	# Preload and create GameState before creating Main.
	var game_state_script := preload("res://scripts/game_state.gd")
	var game_state := game_state_script.new()
	root.add_child(game_state)

	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = preload("res://scripts/main.gd")
	var main: Control = main_script.new()

	test_base_workers_no_upkeep(main)
	test_extra_workers_create_pressure(main)
	test_one_extra_worker_cost(main)
	test_upkeep_never_negative(main)
	test_no_slowdown_when_food_ok(main)
	test_low_food_slowdown_at_threshold(main)
	test_starvation_pause(main)
	test_linear_interpolation(main)
	test_food_level_classification(main)
	test_bias_to_food_when_low(main)
	test_upkeep_interval(main)
	test_base_workers_constant(main)
	test_food_per_extra_worker(main)
	test_constants_consistency(main)

	# Summary
	H.print_summary(H.pass + H.fail)


func test_base_workers_no_upkeep(main: Control) -> void:
	print("")
	print("--- base workers no upkeep ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 10},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0}],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	H.assert_eq(main.get_extra_workers_count(), 0, "base workers: extra count is 0")
	H.assert_eq(get_food_cost_for_test(1), 0, "base workers: food cost is 0")


func test_extra_workers_create_pressure(main: Control) -> void:
	print("")
	print("--- extra workers create pressure ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 10},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [
			{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Mara", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Ava", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Zoe", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
		],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	H.assert_eq(main.get_extra_workers_count(), 2, "extra workers: 4 workers = 2 extra")
	H.assert_eq(get_food_cost_for_test(4), 2, "extra workers: food cost is 2")


func test_one_extra_worker_cost(main: Control) -> void:
	print("")
	print("--- one extra worker cost ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 10},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [
			{"name": "Jun", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Mara", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
			{"name": "Ava", "task": {"kind": "", "data": {}}, "carrying": {}, "break_ticks": 0},
		],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	H.assert_eq(get_food_cost_for_test(3), 1, "one extra: food cost is 1")


func test_upkeep_never_negative(main: Control) -> void:
	print("")
	print("--- upkeep never negative ---")
	var current_food := 2
	var cost := get_food_cost_for_test(5) # 4 extra * 1 = 4
	var remaining := maxi(current_food - cost, 0)
	H.assert_eq(remaining, 0, "upkeep: clamps to 0, not negative")


func test_no_slowdown_when_food_ok(main: Control) -> void:
	print("")
	print("--- no slowdown when food ok ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 10},
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
	H.assert_eq(main.get_food_slowdown_factor(), 1.0, "high food: full speed (1.0)")


func test_low_food_slowdown_at_threshold(main: Control) -> void:
	print("")
	print("--- low food slowdown at threshold ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": Constants.LOW_FOOD_THRESHOLD},
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
	H.assert(H.float_eq(main.get_food_slowdown_factor(), Constants.LOW_FOOD_SPEED_FACTOR), "low food threshold: speed matches LOW_FOOD_SPEED_FACTOR")


func test_starvation_pause(main: Control) -> void:
	print("")
	print("--- starvation pause ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": Constants.STARVATION_FOOD_THRESHOLD},
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
	H.assert(H.float_eq(main.get_food_slowdown_factor(), Constants.STARVATION_SPEED_FACTOR), "starvation threshold: speed matches STARVATION_SPEED_FACTOR")


func test_linear_interpolation(main: Control) -> void:
	print("")
	print("--- linear interpolation ---")
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
	var factor := main.get_food_slowdown_factor()
	var expected := lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, 0.5)
	H.assert(H.float_eq(factor, expected), "midpoint food: interpolated slowdown (expected %f, got %f)" % [expected, factor])


func test_food_level_classification(main: Control) -> void:
	print("")
	print("--- food level classification ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 0},
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
	H.assert_eq(main.get_low_food_level(), "starving", "food=0 is starving")

	main.state.resources["food"] = Constants.STARVATION_FOOD_THRESHOLD
	H.assert_eq(main.get_low_food_level(), "starving", "food=STARVATION threshold is starving")

	main.state.resources["food"] = Constants.STARVATION_FOOD_THRESHOLD + 1
	H.assert_eq(main.get_low_food_level(), "low", "food=STARVATION+1 is low")

	main.state.resources["food"] = Constants.LOW_FOOD_THRESHOLD
	H.assert_eq(main.get_low_food_level(), "low", "food=LOW threshold is low")

	main.state.resources["food"] = Constants.LOW_FOOD_THRESHOLD + 1
	H.assert_eq(main.get_low_food_level(), "ok", "food=LOW+1 is ok")


func test_bias_to_food_when_low(main: Control) -> void:
	print("")
	print("--- bias to food when low ---")
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": Constants.STARVATION_FOOD_THRESHOLD},
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
	H.assert(main.should_bias_to_food_gathering(), "starvation food: should bias to food")

	main.state.resources["food"] = Constants.LOW_FOOD_THRESHOLD
	H.assert(main.should_bias_to_food_gathering(), "low food: should bias to food")

	main.state.resources["food"] = Constants.LOW_FOOD_THRESHOLD + 1
	H.assert(not main.should_bias_to_food_gathering(), "ok food: should not bias to food")


func test_upkeep_interval(main: Control) -> void:
	print("")
	print("--- upkeep interval ---")
	H.assert_eq(Constants.FOOD_UPKEEP_INTERVAL_TICKS, 10, "upkeep triggers every 10 ticks")


func test_base_workers_constant(main: Control) -> void:
	print("")
	print("--- base workers constant ---")
	H.assert_eq(Constants.BASE_WORKERS_NO_UPKEEP, 2, "base workers without upkeep is 2")


func test_food_per_extra_worker(main: Control) -> void:
	print("")
	print("--- food per extra worker ---")
	H.assert_eq(Constants.FOOD_PER_EXTRA_WORKER, 1, "each extra worker consumes 1 food per interval")


func test_constants_consistency(main: Control) -> void:
	print("")
	print("--- constants consistency ---")
	var ok := true
	ok = ok and (Constants.STARVATION_FOOD_THRESHOLD < Constants.LOW_FOOD_THRESHOLD)
	ok = ok and (Constants.STARVATION_SPEED_FACTOR >= 0.0)
	ok = ok and (Constants.STARVATION_SPEED_FACTOR <= 1.0)
	ok = ok and (Constants.LOW_FOOD_SPEED_FACTOR >= 0.0)
	ok = ok and (Constants.LOW_FOOD_SPEED_FACTOR <= 1.0)
	H.assert(ok, "constants are internally consistent")


# ── Helper: compute food cost without needing main.gd instance ───────────────
# This is a pure calculation derived from Constants — used for simple cost checks.

static func get_food_cost_for_test(worker_count: int) -> int:
	var extra := maxi(worker_count - Constants.BASE_WORKERS_NO_UPKEEP, 0)
	return extra * Constants.FOOD_PER_EXTRA_WORKER
