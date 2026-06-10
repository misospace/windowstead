extends SceneTree
# Tests for food upkeep model (issue #147, links to #133).
# Validates: base workers no pressure, extra workers create pressure,
# low-food slowdown, starvation pause, and food-gathering bias.
# Harness: extends SceneTree — instantiate Main and call actual methods.

const Constants := preload("res://scripts/constants.gd")

var test_pass := 0
var test_fail := 0


func _initialize() -> void:
	var main_script: GDScript = preload("res://scripts/main.gd")
	var main := main_script.new()

	# ── Test: base workers do not create food pressure ────────────────────────
	print("")
	print("--- base workers no upkeep ---")
	main.state = {"workers": []}  # empty = 0 workers, below BASE_WORKERS_NO_UPKEEP
	var extra_0 := main.get_extra_workers_count()
	_assert_eq(extra_0, 0, "0 workers should produce 0 extra")

	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
	]}  # 2 workers = base
	var extra_2 := main.get_extra_workers_count()
	_assert_eq(extra_2, 0, "Base 2 workers should produce 0 extra")

	# ── Test: extra workers create clear food pressure ────────────────────────
	print("")
	print("--- extra workers create pressure ---")
	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
		{"name": "C", "pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}},
		{"name": "D", "pos": {"x": 3, "y": 0}, "carrying": {}, "task": {}},
	]}  # 4 workers = 2 extra
	var extra_4 := main.get_extra_workers_count()
	_assert_eq(extra_4, 2, "4 workers should produce 2 extra")

	# Food cost for 2 extra = 2 * FOOD_PER_EXTRA_WORKER
	var food_cost := extra_4 * Constants.FOOD_PER_EXTRA_WORKER
	_assert_eq(food_cost, 2, "4 workers should cost 2 food per upkeep cycle (1 per extra)")

	# ── Test: one extra worker costs exactly one food per interval ────────────
	print("")
	print("--- one extra worker cost ---")
	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
		{"name": "C", "pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}},
	]}  # 3 workers = 1 extra
	var extra_3 := main.get_extra_workers_count()
	_assert_eq(extra_3, 1, "3 workers (1 extra) should cost 1 food")

	# ── Test: upkeep never drives food negative ───────────────────────────────
	print("")
	print("--- upkeep never negative ---")
	main.state = {"workers": [
		{"name": "A", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}},
		{"name": "B", "pos": {"x": 1, "y": 0}, "carrying": {}, "task": {}},
		{"name": "C", "pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}},
		{"name": "D", "pos": {"x": 3, "y": 0}, "carrying": {}, "task": {}},
	], "resources": {"food": 2}}  # 4 workers = 4 extra = 4 food cost, but only 2 food
	main.apply_food_upkeep()
	var remaining := int(main.state.resources.get("food", -1))
	_assert_eq(remaining, 0, "Upkeep should clamp to 0, not go negative")

	# ── Test: no slowdown when food is above threshold ────────────────────────
	print("")
	print("--- no slowdown when food ok ---")
	main.state = {"resources": {"food": 10}}
	var factor_ok := main.get_food_slowdown_factor()
	_assert_eq(factor_ok, 1.0, "High food should give full speed (1.0)")

	# ── Test: low-food slowdown at threshold ──────────────────────────────────
	print("")
	print("--- low food slowdown at threshold ---")
	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD}}
	var factor_low := main.get_food_slowdown_factor()
	_assert_eq(factor_low, Constants.LOW_FOOD_SPEED_FACTOR,
		"At low food threshold, speed should be 50%")

	# ── Test: starvation pause at starvation threshold ────────────────────────
	print("")
	print("--- starvation pause ---")
	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD}}
	var factor_starve := main.get_food_slowdown_factor()
	_assert_eq(factor_starve, Constants.STARVATION_SPEED_FACTOR,
		"At starvation threshold, speed should be 0%")

	# ── Test: linear interpolation between starvation and low ────────────────
	print("")
	print("--- linear interpolation ---")
	# STARVATION=1, LOW=3, so food=2 is exactly in the middle
	main.state = {"resources": {"food": 2}}
	var factor_mid := main.get_food_slowdown_factor()
	var expected = lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, 0.5)
	_assert_eq(factor_mid, expected, "Food at midpoint should give interpolated slowdown")

	# ── Test: food level classification ───────────────────────────────────────
	print("")
	print("--- food level classification ---")
	main.state = {"resources": {"food": 0}}
	_assert_eq(main.get_low_food_level(), "starving", "Zero food is starving")

	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD}}
	_assert_eq(main.get_low_food_level(), "starving",
		"At starvation threshold, still starving")

	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD + 1}}
	_assert_eq(main.get_low_food_level(), "low",
		"One above starvation is low")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD}}
	_assert_eq(main.get_low_food_level(), "low",
		"At low threshold, still low")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD + 1}}
	_assert_eq(main.get_low_food_level(), "ok",
		"One above low threshold is ok")

	# ── Test: bias to food gathering when low ────────────────────────────────
	print("")
	print("--- bias to food when low ---")
	main.state = {"resources": {"food": Constants.STARVATION_FOOD_THRESHOLD}}
	_assert(main.should_bias_to_food_gathering(), "Should bias when starving")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD}}
	_assert(main.should_bias_to_food_gathering(), "Should bias when low")

	main.state = {"resources": {"food": Constants.LOW_FOOD_THRESHOLD + 1}}
	_assert(not main.should_bias_to_food_gathering(), "Should not bias when ok")

	# ── Test: upkeep interval constant ────────────────────────────────────────
	print("")
	print("--- upkeep interval ---")
	_assert_eq(Constants.FOOD_UPKEEP_INTERVAL_TICKS, 10,
		"Upkeep should trigger every 10 ticks")

	# ── Test: base workers constant ───────────────────────────────────────────
	print("")
	print("--- base workers constant ---")
	_assert_eq(Constants.BASE_WORKERS_NO_UPKEEP, 2,
		"Base workers without upkeep should be 2")

	# ── Test: food per extra worker constant ──────────────────────────────────
	print("")
	print("--- food per extra worker ---")
	_assert_eq(Constants.FOOD_PER_EXTRA_WORKER, 1,
		"Each extra worker consumes 1 food per interval")

	# ── Test: constants are consistent with acceptance criteria ───────────────
	print("")
	print("--- constants consistency ---")
	# STARVATION < LOW ensures interpolation range exists
	_assert_lt(Constants.STARVATION_FOOD_THRESHOLD, Constants.LOW_FOOD_THRESHOLD,
		"Starvation threshold must be below low threshold")
	# Speed factors are in [0, 1]
	_assert_gte(Constants.STARVATION_SPEED_FACTOR, 0.0, "Starvation factor >= 0")
	_assert_lte(Constants.STARVATION_SPEED_FACTOR, 1.0, "Starvation factor <= 1")
	_assert_gte(Constants.LOW_FOOD_SPEED_FACTOR, 0.0, "Low food factor >= 0")
	_assert_lte(Constants.LOW_FOOD_SPEED_FACTOR, 1.0, "Low food factor <= 1")

	# Summary
	print("")
	print("=== test_runner summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("test_runner: ok")
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


func _assert_lt(a: Variant, b: Variant, name: String) -> void:
	_assert(a < b, name, "%s < %s should be true" % [str(a), str(b)])


func _assert_gt(a: Variant, b: Variant, name: String) -> void:
	_assert(a > b, name, "%s > %s should be true" % [str(a), str(b)])


func _assert_lte(a: Variant, b: Variant, name: String) -> void:
	_assert(a <= b, name, "%s <= %s should be true" % [str(a), str(b)])


func _assert_gte(a: Variant, b: Variant, name: String) -> void:
	_assert(a >= b, name, "%s >= %s should be true" % [str(a), str(b)])
