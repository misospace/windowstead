extends SceneTree
# Tests for food upkeep model (issue #147, links to #133).
# Validates: base workers no pressure, extra workers create pressure,
# low-food slowdown, starvation pause, and food-gathering bias.

const Constants := preload("res://scripts/constants.gd")

var test_pass := 0
var test_fail := 0


func _initialize() -> void:
	test_base_workers_no_upkeep()
	test_extra_workers_create_pressure()
	test_one_extra_worker_cost()
	test_upkeep_never_negative()
	test_no_slowdown_when_food_ok()
	test_low_food_slowdown_at_threshold()
	test_starvation_pause()
	test_linear_interpolation()
	test_food_level_classification()
	test_bias_to_food_when_low()
	test_upkeep_interval()
	test_base_workers_constant()
	test_food_per_extra_worker()
	test_constants_consistency()

	# Summary
	print("")
	print("=== test_food_upkeep summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED")
		quit(1)
	else:
		print("test_food_upkeep: ok")
		quit(0)


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


# ── Test: base workers do not create food pressure ───────────────────────────
func test_base_workers_no_upkeep() -> void:
	var extra := get_extra_workers_count(2)
	_assert_eq(extra, 0, "Base 2 workers should produce 0 extra")

	var food_cost := get_food_cost(2, Constants.FOOD_PER_EXTRA_WORKER)
	_assert_eq(food_cost, 0, "Base workers should cost 0 food per upkeep cycle")


# ── Test: extra workers create clear food pressure ───────────────────────────
func test_extra_workers_create_pressure() -> void:
	var extra := get_extra_workers_count(4)
	_assert_eq(extra, 2, "4 workers should produce 2 extra")

	var food_cost := get_food_cost(4, Constants.FOOD_PER_EXTRA_WORKER)
	_assert_eq(food_cost, 2, "4 workers should cost 2 food per upkeep cycle (1 per extra)")


# ── Test: one extra worker costs exactly one food per interval ───────────────
func test_one_extra_worker_cost() -> void:
	var food_cost := get_food_cost(3, Constants.FOOD_PER_EXTRA_WORKER)
	_assert_eq(food_cost, 1, "3 workers (1 extra) should cost 1 food")


# ── Test: upkeep never drives food negative ──────────────────────────────────
func test_upkeep_never_negative() -> void:
	var current_food := 2
	var cost := get_food_cost(5, Constants.FOOD_PER_EXTRA_WORKER) # 4 extra * 1 = 4
	var remaining := apply_upkeep(current_food, cost)
	_assert_eq(remaining, 0, "Upkeep should clamp to 0, not go negative")


# ── Test: no slowdown when food is above threshold ───────────────────────────
func test_no_slowdown_when_food_ok() -> void:
	var factor := get_slowdown_factor(10)
	_assert_eq(factor, 1.0, "High food should give full speed (1.0)")


# ── Test: low-food slowdown at threshold ─────────────────────────────────────
func test_low_food_slowdown_at_threshold() -> void:
	# At exactly LOW_FOOD_THRESHOLD (3), should be at LOW_FOOD_SPEED_FACTOR (0.5)
	var factor := get_slowdown_factor(Constants.LOW_FOOD_THRESHOLD)
	_assert_eq(factor, Constants.LOW_FOOD_SPEED_FACTOR,
		"At low food threshold, speed should be 50%")


# ── Test: starvation pause at starvation threshold ───────────────────────────
func test_starvation_pause() -> void:
	var factor := get_slowdown_factor(Constants.STARVATION_FOOD_THRESHOLD)
	_assert_eq(factor, Constants.STARVATION_SPEED_FACTOR,
		"At starvation threshold, speed should be 0%")


# ── Test: linear interpolation between starvation and low ────────────────────
func test_linear_interpolation() -> void:
	# STARVATION=1, LOW=3, so food=2 is exactly in the middle
	var factor := get_slowdown_factor(2)
	var expected = lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, 0.5)
	_assert_eq(factor, expected, "Food at midpoint should give interpolated slowdown")


# ── Test: food level classification ──────────────────────────────────────────
func test_food_level_classification() -> void:
	_assert_eq(get_food_level(0), "starving", "Zero food is starving")
	_assert_eq(get_food_level(Constants.STARVATION_FOOD_THRESHOLD), "starving",
		"At starvation threshold, still starving")
	_assert_eq(get_food_level(Constants.STARVATION_FOOD_THRESHOLD + 1), "low",
		"One above starvation is low")
	_assert_eq(get_food_level(Constants.LOW_FOOD_THRESHOLD), "low",
		"At low threshold, still low")
	_assert_eq(get_food_level(Constants.LOW_FOOD_THRESHOLD + 1), "ok",
		"One above low threshold is ok")


# ── Test: bias to food gathering when low ────────────────────────────────────
func test_bias_to_food_when_low() -> void:
	_assert_eq(should_bias_to_food(Constants.STARVATION_FOOD_THRESHOLD), true,
		"Should bias when starving")
	_assert_eq(should_bias_to_food(Constants.LOW_FOOD_THRESHOLD), true,
		"Should bias when low")
	_assert_eq(should_bias_to_food(Constants.LOW_FOOD_THRESHOLD + 1), false,
		"Should not bias when ok")


# ── Test: upkeep interval is 10 ticks ────────────────────────────────────────
func test_upkeep_interval() -> void:
	_assert_eq(Constants.FOOD_UPKEEP_INTERVAL_TICKS, 10,
		"Upkeep should trigger every 10 ticks")


# ── Test: base workers constant ──────────────────────────────────────────────
func test_base_workers_constant() -> void:
	_assert_eq(Constants.BASE_WORKERS_NO_UPKEEP, 2,
		"Base workers without upkeep should be 2")


# ── Test: food per extra worker constant ─────────────────────────────────────
func test_food_per_extra_worker() -> void:
	_assert_eq(Constants.FOOD_PER_EXTRA_WORKER, 1,
		"Each extra worker consumes 1 food per interval")


# ── Test: constants are consistent with acceptance criteria ──────────────────
func test_constants_consistency() -> void:
	# STARVATION < LOW ensures interpolation range exists
	_assert(Constants.STARVATION_FOOD_THRESHOLD < Constants.LOW_FOOD_THRESHOLD,
		"Starvation threshold must be below low threshold")
	# Speed factors are in [0, 1]
	_assert(Constants.STARVATION_SPEED_FACTOR >= 0.0, "Starvation factor >= 0")
	_assert(Constants.STARVATION_SPEED_FACTOR <= 1.0, "Starvation factor <= 1")
	_assert(Constants.LOW_FOOD_SPEED_FACTOR >= 0.0, "Low food factor >= 0")
	_assert(Constants.LOW_FOOD_SPEED_FACTOR <= 1.0, "Low food factor <= 1")


# ── Helper functions (mirroring main.gd logic for test isolation) ────────────

static func get_extra_workers_count(worker_count: int) -> int:
	return maxi(worker_count - Constants.BASE_WORKERS_NO_UPKEEP, 0)


static func get_food_cost(worker_count: int, food_per_worker: int) -> int:
	var extra = get_extra_workers_count(worker_count)
	return extra * food_per_worker


static func apply_upkeep(current_food: int, cost: int) -> int:
	return maxi(current_food - cost, 0)


static func get_slowdown_factor(food: int) -> float:
	if food <= Constants.STARVATION_FOOD_THRESHOLD:
		return Constants.STARVATION_SPEED_FACTOR
	if food <= Constants.LOW_FOOD_THRESHOLD:
		var range_size = float(Constants.LOW_FOOD_THRESHOLD - Constants.STARVATION_FOOD_THRESHOLD)
		if range_size == 0:
			return Constants.FOOD_SPEED_FACTOR
		var progress = float(food - Constants.STARVATION_FOOD_THRESHOLD) / range_size
		return lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, progress)
	return 1.0


static func get_food_level(food: int) -> String:
	if food <= Constants.STARVATION_FOOD_THRESHOLD:
		return "starving"
	if food <= Constants.LOW_FOOD_THRESHOLD:
		return "low"
	return "ok"


static func should_bias_to_food(food: int) -> bool:
	var level = get_food_level(food)
	return level == "low" or level == "starving"
