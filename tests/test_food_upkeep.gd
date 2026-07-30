extends "res://tests/test_case.gd"
# Tests for food upkeep model (issue #147, links to #133).
# Validates: base workers no pressure, extra workers create pressure,
# low-food slowdown, starvation pause, and food-gathering bias.

const Constants := preload("res://scripts/constants.gd")
const ColonySim := preload("res://scripts/colony_sim.gd")


func run_tests() -> void:
	# main.gd references the GameState autoload, so it must be load()ed at
	# runtime — preload() compiles before autoloads are registered in --script mode.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()

	# ── Test: base workers do not create food pressure ────────────────────────
	print("")
	print("--- base workers no upkeep ---")
	main.state = {"workers": []}  # empty = 0 workers, below BASE_WORKERS_NO_UPKEEP
	var extra_0: int = main.get_extra_workers_count()
	assert_eq(extra_0, 0, "0 workers should produce 0 extra")

	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
	]}  # 2 workers = base
	var extra_2: int = main.get_extra_workers_count()
	assert_eq(extra_2, 0, "Base 2 workers should produce 0 extra")

	# ── Test: extra workers create clear food pressure ────────────────────────
	print("")
	print("--- extra workers create pressure ---")
	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
		{"name": "C", "pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}},
		{"name": "D", "pos": {"x": 3, "y": 0}, "carrying": {}, "task": {}},
	]}  # 4 workers = 2 extra
	var extra_4: int = main.get_extra_workers_count()
	assert_eq(extra_4, 2, "4 workers should produce 2 extra")

	# Food cost for 2 extra = 2 * FOOD_PER_EXTRA_WORKER
	var food_cost := extra_4 * Constants.FOOD_PER_EXTRA_WORKER
	assert_eq(food_cost, 2, "4 workers should cost 2 food per upkeep cycle (1 per extra)")

	# ── Test: one extra worker costs exactly one food per interval ────────────
	print("")
	print("--- one extra worker cost ---")
	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
		{"name": "C", "pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}},
	]}  # 3 workers = 1 extra
	var extra_3: int = main.get_extra_workers_count()
	assert_eq(extra_3, 1, "3 workers (1 extra) should cost 1 food")

	# ── Test: upkeep never drives food negative ───────────────────────────────
	print("")
	print("--- upkeep never negative ---")
	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
		{"name": "C", "pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}},
		{"name": "D", "pos": {"x": 3, "y": 0}, "carrying": {}, "task": {}},
	], "resources": {"food": 2}}  # 4 workers = 2 extra = 2 food cost, exactly the 2 food on hand
	main.apply_food_upkeep()
	var remaining := int(main.state.resources.get("food", -1))
	assert_eq(remaining, 0, "Upkeep should clamp to 0, not go negative")

	# ── Test: no slowdown when food is above threshold ────────────────────────
	print("")
	print("--- no slowdown when food ok ---")
	main.state = {"resources": {"food": 10}}
	var factor_ok: float = main.get_food_slowdown_factor()
	assert_eq(factor_ok, 1.0, "High food should give full speed (1.0)")

	# ── Test: low-food slowdown at threshold ──────────────────────────────────
	print("")
	print("--- low food slowdown at threshold ---")
	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD}}
	var factor_low: float = main.get_food_slowdown_factor()
	assert_eq(factor_low, Constants.LOW_FOOD_SPEED_FACTOR,
		"At low food threshold, speed should be 50%")

	# ── Test: starvation pause at starvation threshold ────────────────────────
	print("")
	print("--- starvation pause ---")
	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD}}
	var factor_starve: float = main.get_food_slowdown_factor()
	assert_eq(factor_starve, Constants.STARVATION_SPEED_FACTOR,
		"At starvation threshold, speed should be 0%")

	# ── Test: linear interpolation between starvation and low ────────────────
	print("")
	print("--- linear interpolation ---")
	# STARVATION=1, LOW=3, so food=2 is exactly in the middle
	main.state = {"resources": {"food": 2}}
	var factor_mid: float = main.get_food_slowdown_factor()
	var expected = lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, 0.5)
	assert_eq(factor_mid, expected, "Food at midpoint should give interpolated slowdown")

	# ── Test: food level classification ───────────────────────────────────────
	print("")
	print("--- food level classification ---")
	main.state = {"resources": {"food": 0}}
	assert_eq(main.get_low_food_level(), "starving", "Zero food is starving")

	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD}}
	assert_eq(main.get_low_food_level(), "starving",
		"At starvation threshold, still starving")

	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD + 1}}
	assert_eq(main.get_low_food_level(), "low",
		"One above starvation is low")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD}}
	assert_eq(main.get_low_food_level(), "low",
		"At low threshold, still low")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD + 1}}
	assert_eq(main.get_low_food_level(), "ok",
		"One above low threshold is ok")

	# ── Test: bias to food gathering when low ────────────────────────────────
	print("")
	print("--- bias to food when low ---")
	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD}}
	assert_true(main.should_bias_to_food_gathering(), "Should bias when starving")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD}}
	assert_true(main.should_bias_to_food_gathering(), "Should bias when low")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD + 1}}
	assert_true(not main.should_bias_to_food_gathering(), "Should not bias when ok")

	# ── Test: upkeep interval constant ────────────────────────────────────────
	print("")
	print("--- upkeep interval ---")
	assert_eq(Constants.FOOD_UPKEEP_INTERVAL_TICKS, 10,
		"Upkeep should trigger every 10 ticks")

	# ── Test: base workers constant ───────────────────────────────────────────
	print("")
	print("--- base workers constant ---")
	assert_eq(Constants.BASE_WORKERS_NO_UPKEEP, 2,
		"Base workers without upkeep should be 2")

	# ── Test: food per extra worker constant ──────────────────────────────────
	print("")
	print("--- food per extra worker ---")
	assert_eq(Constants.FOOD_PER_EXTRA_WORKER, 1,
		"Each extra worker consumes 1 food per interval")

	# ── Test: constants are consistent with acceptance criteria ───────────────
	print("")
	print("--- constants consistency ---")
	# STARVATION < LOW ensures interpolation range exists
	assert_true(Constants.STARVATION_FOOD_THRESHOLD < Constants.LOW_FOOD_THRESHOLD,
		"Starvation threshold must be below low threshold",
		"%s < %s should be true" % [str(Constants.STARVATION_FOOD_THRESHOLD), str(Constants.LOW_FOOD_THRESHOLD)])
	# Speed factors are in [0, 1]
	assert_true(Constants.STARVATION_SPEED_FACTOR >= 0.0, "Starvation factor >= 0")
	assert_true(Constants.STARVATION_SPEED_FACTOR <= 1.0, "Starvation factor <= 1")
	assert_true(Constants.LOW_FOOD_SPEED_FACTOR >= 0.0, "Low food factor >= 0")
	assert_true(Constants.LOW_FOOD_SPEED_FACTOR <= 1.0, "Low food factor <= 1")

	# ── Test: equal thresholds guard (division-by-zero protection) ───────────
	print("")
	print("--- equal thresholds guard ---")
	# When thresholds are equal, food must be > starvation_threshold to reach the low-food branch.
	# We set starvation=1, low=1, food=1 → hits starvation branch first (returns 0.0).
	# To exercise the range_size==0 guard, we need food > starvation but <= low, which is
	# impossible when thresholds are equal. So we test with food=2, starvation=1, low=1:
	#   - food(2) > starvation(1) → skip first branch
	#   - food(2) > low(1) → skip second branch → returns 1.0
	# The guard is exercised when food is between thresholds but range_size == 0, which
	# requires food > starvation AND food <= low with starvation == low (impossible).
	# We verify the function doesn't crash with equal thresholds:
	var result_starving := ColonySim.compute_food_slowdown_factor(
		1,  # food value at threshold
		1,  # starvation threshold (equal to low threshold)
		1,  # low threshold
		0.0,  # starvation speed factor
		0.5   # low food speed factor
	)
	assert_eq(result_starving, 0.0, "Food at equal thresholds returns starvation speed")

	# Verify function works normally with different thresholds:
	var result_normal := ColonySim.compute_food_slowdown_factor(
		2,  # food value between thresholds
		1,  # starvation threshold
		3,  # low threshold
		0.0,  # starvation speed factor
		0.5   # low food speed factor
	)
	assert_eq(result_normal, 0.25, "Normal interpolation works correctly")

	main.free()
