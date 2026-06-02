## Tests for resource trend indicators (issue #137).
## Covers _get_trend() logic: rising, falling, stable, first-tick sentinel.
## Also verifies stockpile_summary_text embeds expected arrows.
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_resource_trends.gd

extends SceneTree

const C := preload("res://scripts/constants.gd")

func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0
	var test_count := 0

	# --- RESOURCE_TRENDS constant ---
	test_count += 1; pass_count += test("RESOURCE_TRENDS has rising key", _test_trend_rising_key)
	test_count += 1; pass_count += test("RESOURCE_TRENDS has falling key", _test_trend_falling_key)
	test_count += 1; pass_count += test("RESOURCE_TRENDS has stable key", _test_trend_stable_key)
	test_count += 1; pass_count += test("RESOURCE_TRENDS has exactly 3 entries", _test_trend_count)
	test_count += 1; pass_count += test("RESOURCE_TRENDS[rising] is ↑", _test_trend_rising_value)
	test_count += 1; pass_count += test("RESOURCE_TRENDS[falling] is ↓", _test_trend_falling_value)
	test_count += 1; pass_count += test("RESOURCE_TRENDS[stable] is →", _test_trend_stable_value)

	# --- _get_trend logic (simulated via a minimal mock) ---
	test_count += 1; pass_count += test("_get_trend rising: current > previous", _test_get_trend_rising)
	test_count += 1; pass_count += test("_get_trend falling: current < previous", _test_get_trend_falling)
	test_count += 1; pass_count += test("_get_trend stable: current == previous", _test_get_trend_stable)
	test_count += 1; pass_count += test("_get_trend first-tick sentinel (previous < 0): returns stable", _test_get_trend_first_tick)
	test_count += 1; pass_count += test("_get_trend unknown resource: returns stable (prev = -1)", _test_get_trend_unknown_resource)

	# --- stockpile_summary_text arrow embedding ---
	test_count += 1; pass_count += test("stockpile_summary_text(compact=false) contains ↑ arrow", _test_summary_contains_rising_arrow)
	test_count += 1; pass_count += test("stockpile_summary_text(compact=true) contains → arrow (stable)", _test_summary_contains_stable_arrow)

	fail_count = test_count - pass_count
	print("\n=== Resource Trend Tests ===")
	print("Passed: %d" % pass_count)
	print("Failed: %d" % fail_count)

	if fail_count > 0:
		print("TREND TEST FAILURES DETECTED")
		quit(1)
	else:
		print("All resource trend tests passed.")
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


# --- RESOURCE_TRENDS constant tests ---

func _test_trend_rising_key() -> bool:
	return C.RESOURCE_TRENDS.has("rising")

func _test_trend_falling_key() -> bool:
	return C.RESOURCE_TRENDS.has("falling")

func _test_trend_stable_key() -> bool:
	return C.RESOURCE_TRENDS.has("stable")

func _test_trend_count() -> bool:
	return C.RESOURCE_TRENDS.size() == 3

func _test_trend_rising_value() -> bool:
	return C.RESOURCE_TRENDS.get("rising") == "↑"

func _test_trend_falling_value() -> bool:
	return C.RESOURCE_TRENDS.get("falling") == "↓"

func _test_trend_stable_value() -> bool:
	return C.RESOURCE_TRENDS.get("stable") == "→"


# --- _get_trend logic tests ---
## Since _get_trend is a method of Main (an autoload singleton), we call it
## directly through the autoload reference. The function signature is:
##   func _get_trend(resource_name: String) -> String
## It reads from `state.resources` and `prev_resources`, so we set those up
## before each call.

func _get_trend_mock(resource_name: String, current_val: int, previous_val: int = -1) -> String:
	"""Simulate _get_trend by setting state.resources and prev_resources then calling the method."""
	var main := Globals.get_node("/root/Main") as Node
	if main == null:
		return {"ok": false, "msg": "Main autoload not found"}

	# Set up state.resources
	main.state = {
		"resources": {
			resource_name: current_val,
			"wood": 0,
			"stone": 0,
			"food": 0
		}
	}

	# Set up prev_resources
	main.prev_resources = {resource_name: previous_val}

	var result := main._get_trend(resource_name)

	# Restore clean state
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	return result

func _test_get_trend_rising() -> bool:
	var result = _get_trend_mock("wood", 10, 7)
	if result is String:
		return result == C.RESOURCE_TRENDS["rising"]
	return {"ok": false, "msg": "returned non-string: %s" % result}

func _test_get_trend_falling() -> bool:
	var result = _get_trend_mock("food", 3, 5)
	if result is String:
		return result == C.RESOURCE_TRENDS["falling"]
	return {"ok": false, "msg": "returned non-string: %s" % result}

func _test_get_trend_stable() -> bool:
	var result = _get_trend_mock("stone", 4, 4)
	if result is String:
		return result == C.RESOURCE_TRENDS["stable"]
	return {"ok": false, "msg": "returned non-string: %s" % result}

func _test_get_trend_first_tick() -> bool:
	var result = _get_trend_mock("wood", 8)  # previous defaults to -1
	if result is String:
		return result == C.RESOURCE_TRENDS["stable"]
	return {"ok": false, "msg": "returned non-string: %s" % result}

func _test_get_trend_unknown_resource() -> bool:
	var result = _get_trend_mock("diamond", 5)  # not a known resource, prev = -1
	if result is String:
		return result == C.RESOURCE_TRENDS["stable"]
	return {"ok": false, "msg": "returned non-string: %s" % result}


# --- stockpile_summary_text arrow embedding tests ---

func _test_summary_contains_rising_arrow() -> bool:
	var main := Globals.get_node("/root/Main") as Node
	if main == null:
		return {"ok": false, "msg": "Main autoload not found"}

	main.state = {
		"resources": {"wood": 10, "stone": 4, "food": 3},
		"harvested": {"wood": 0, "stone": 0, "food": 0}
	}
	main.prev_resources = {"wood": 7, "stone": 4, "food": 5}

	var summary := main.stockpile_summary_text(false) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	var rising_arrow := C.RESOURCE_TRENDS["rising"]
	return summary.find(rising_arrow) >= 0

func _test_summary_contains_stable_arrow() -> bool:
	var main := Globals.get_node("/root/Main") as Node
	if main == null:
		return {"ok": false, "msg": "Main autoload not found"}

	main.state = {
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0}
	}
	main.prev_resources = {"wood": 8, "stone": 4, "food": 2}

	var summary := main.stockpile_summary_text(true) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	var stable_arrow := C.RESOURCE_TRENDS["stable"]
	return summary.find(stable_arrow) >= 0
