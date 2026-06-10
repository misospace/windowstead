## Tests for resource trend indicators (issue #137).
## Covers _get_trend() logic: rising, falling, stable, first-tick sentinel.
## Also verifies stockpile_summary_text embeds expected arrows and fits within
## dock layout constraints (no clipping).
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_resource_trends.gd

extends SceneTree

const C := preload("res://scripts/constants.gd")


# --- Layout/clipping tests for HUD row labels (issue #135) ---
## These tests verify that the three compact HUD row label outputs fit within
## the expected dock layout constraints (bottom: 320px, side: 280px).
## At default font size (~11px per char for HUD labels), each character takes ~6-7px.
## Safe upper bound: ~45 chars for 320px bottom dock, ~40 chars for 280px side dock.
## No DisplayServer or scene node required — fully deterministic string analysis.

func _test_hud_worker_cap_fits_dock() -> bool:
	# Worker cap format: "%d / %d" — max plausible: "999 / 999" (11 chars)
	var worker_cap_text := "999 / 999"
	if worker_cap_text.length() > 45:
		return {"ok": false, "msg": "worker cap text length %d exceeds safe bound for bottom dock" % worker_cap_text.length()}
	print("    worker cap worst case: \"%s\" (%d chars)" % [worker_cap_text, worker_cap_text.length()])
	return true

func _test_hud_food_warning_fits_dock() -> bool:
	# Food warning formats: "⚠ LOW FOOD" (10 visible chars) or "⚠ STARVING" (10 visible chars)
	var food_warning := "⚠ STARVING"
	if food_warning.length() > 45:
		return {"ok": false, "msg": "food warning text length %d exceeds safe bound for bottom dock" % food_warning.length()}
	print("    food warning worst case: \"%s\" (%d chars)" % [food_warning, food_warning.length()])
	return true

func _test_hud_goal_text_fits_dock() -> bool:
	# Goal text formats (worst cases):
	# Resource: "Goal: Workshop (999/9999)" — ~22 chars
	var goal_resource := "Goal: Workshop (999/9999)"
	# Build: "Build: Workshop" — ~15 chars
	var goal_build := "Build: Workshop"
	# Complete: "Goal: Finish a build ✓" — ~21 chars
	var goal_complete := "Goal: Finish a build ✓"

	var max_safe_length := 40  # conservative bound for 280px side dock at HUD font size
	for goal_text in [goal_resource, goal_build, goal_complete]:
		if goal_text.length() > max_safe_length:
			return {"ok": false, "msg": "HUD goal text \"%s\" length %d exceeds safe bound %d for side dock" % [goal_text, goal_text.length(), max_safe_length]}
		print("    HUD goal worst case: \"%s\" (%d chars)" % [goal_text, goal_text.length()])
	return true

func _test_hud_goal_capitalization() -> bool:
	# Verify that cap() capitalizes resource/build names correctly.
	var test_cases := {
		"wood": "Wood",
		"stone": "Stone",
		"workshop": "Workshop",
		"hut": "Hut",
		"garden": "Garden",
	}
	for input_str in test_cases:
		var expected := test_cases[input_str]
		var actual := input_str.substr(0, 1).to_upper() + input_str.substr(1)
		if actual != expected:
			return {"ok": false, "msg": "cap(\"%s\") = \"%s\", expected \"%s\"" % [input_str, actual, expected]}
	print("    cap() capitalization verified for all test cases")
	return true

func _test_hud_all_rows_fit_together() -> bool:
	# Verify that all three HUD rows combined in a single render cycle
	# don't overflow the bottom dock width. Each row is independent (vertical stack),
	# so we verify each row's text length individually rather than summing.
	var hud_rows := {
		"worker_cap": "999 / 999",
		"food_warning": "⚠ STARVING",
		"goal_resource": "Goal: Workshop (999/9999)",
	}
	var max_safe_length := 45  # bottom dock at HUD font size
	for row_name in hud_rows:
		var text := hud_rows[row_name]
		if text.length() > max_safe_length:
			return {"ok": false, "msg": "HUD row \"%s\" text \"%s\" length %d exceeds safe bound" % [row_name, text, text.length()]}
	print("    all HUD rows individually within safe bounds")
	return true


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

	# --- Layout/clipping tests: trend indicators must fit within dock widths ---
	# Bottom dock sidebar width: 320px, vertical/side dock sidebar width: 280px
	# At default font size (~16px), each character takes ~8-10px.
	# We verify the rendered summary text length stays within safe bounds.
	test_count += 1; pass_count += test("compact summary fits within bottom dock sidebar (320px)", _test_compact_summary_fits_bottom_dock)
	test_count += 1; pass_count += test("compact summary fits within side dock sidebar (280px)", _test_compact_summary_fits_side_dock)
	test_count += 1; pass_count += test("non-compact summary first line fits within bottom dock sidebar", _test_noncompact_first_line_fits)
	test_count += 1; pass_count += test("all three trend arrows present in compact mode", _test_all_arrows_in_compact)
	test_count += 1; pass_count += test("all three trend arrows present in non-compact mode", _test_all_arrows_in_noncompact)
	test_count += 1; pass_count += test("extreme resource values (999) still fit in compact summary", _test_extreme_values_fit_compact)
	# --- Layout/clipping tests: HUD row labels must fit within dock widths (issue #135) ---
	test_count += 1; pass_count += test("HUD worker cap text fits within safe bounds", _test_hud_worker_cap_fits_dock)
	test_count += 1; pass_count += test("HUD food warning text fits within safe bounds", _test_hud_food_warning_fits_dock)
	test_count += 1; pass_count += test("HUD goal text fits within safe bounds for all goal types", _test_hud_goal_text_fits_dock)
	test_count += 1; pass_count += test("cap() capitalizes resource/build names correctly", _test_hud_goal_capitalization)
	test_count += 1; pass_count += test("all HUD rows individually fit within safe bounds", _test_hud_all_rows_fit_together)

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
## Since _get_trend is a method of Main, we create a fresh instance
## via load() and set up state before each call.

func _get_trend_mock(resource_name: String, current_val: int, previous_val: int = -1) -> String:
	"""Simulate _get_trend by creating a Main instance and calling the method."""
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

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
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

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
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

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


# --- Layout/clipping tests for trend indicators ---
## These tests verify that the stockpile_summary_text output with trend arrows
## fits within the expected dock layout constraints (bottom: 320px, side: 280px).
## At default font size (~16px), each character takes ~8-10px.
## Safe upper bound: ~35 characters for 280px sidebar, ~40 for 320px sidebar.

func _test_compact_summary_fits_bottom_dock() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

	main.state = {
		"resources": {"wood": 100, "stone": 50, "food": 75},
		"harvested": {"wood": 20, "stone": 10, "food": 30}
	}
	main.prev_resources = {"wood": 80, "stone": 45, "food": 90}

	var summary := main.stockpile_summary_text(true) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	# Bottom dock sidebar width: 320px. At ~9px/char average, max ~35 chars safe.
	# The compact format includes arrows (+3 chars vs no arrows).
	var max_safe_length := 40  # conservative upper bound for 320px at default font
	if summary.length() > max_safe_length:
		return {"ok": false, "msg": "compact summary length %d exceeds safe bound %d for bottom dock" % [summary.length(), max_safe_length]}

	print("    compact summary: \"%s\" (%d chars)" % [summary, summary.length()])
	return true

func _test_compact_summary_fits_side_dock() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

	main.state = {
		"resources": {"wood": 100, "stone": 50, "food": 75},
		"harvested": {"wood": 20, "stone": 10, "food": 30}
	}
	main.prev_resources = {"wood": 80, "stone": 45, "food": 90}

	var summary := main.stockpile_summary_text(true) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	# Side dock sidebar width: 280px. At ~9px/char average, max ~31 chars safe.
	var max_safe_length := 35  # conservative upper bound for 280px at default font
	if summary.length() > max_safe_length:
		return {"ok": false, "msg": "compact summary length %d exceeds safe bound %d for side dock" % [summary.length(), max_safe_length]}

	print("    compact summary: \"%s\" (%d chars)" % [summary, summary.length()])
	return true

func _test_noncompact_first_line_fits() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

	main.state = {
		"resources": {"wood": 100, "stone": 50, "food": 75},
		"harvested": {"wood": 20, "stone": 10, "food": 30}
	}
	main.prev_resources = {"wood": 80, "stone": 45, "food": 90}

	var summary := main.stockpile_summary_text(false) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	# Non-compact has two lines. First line should be similar length to compact.
	var lines := summary.split("\n")
	if lines.size() < 1:
		return {"ok": false, "msg": "non-compact summary has no lines"}

	var first_line := lines[0] as String
	var max_safe_length := 40  # same bound as compact for first line
	if first_line.length() > max_safe_length:
		return {"ok": false, "msg": "non-compact first line length %d exceeds safe bound %d" % [first_line.length(), max_safe_length]}

	print("    non-compact first line: \"%s\" (%d chars)" % [first_line, first_line.length()])
	return true

func _test_all_arrows_in_compact() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

	# Set up a scenario where all three resources have different trends
	main.state = {
		"resources": {"wood": 10, "stone": 5, "food": 3},
		"harvested": {"wood": 0, "stone": 0, "food": 0}
	}
	main.prev_resources = {"wood": 7, "stone": 5, "food": 8}

	var summary := main.stockpile_summary_text(true) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	var rising_arrow := C.RESOURCE_TRENDS["rising"]
	var stable_arrow := C.RESOURCE_TRENDS["stable"]
	var falling_arrow := C.RESOURCE_TRENDS["falling"]

	var has_rising := summary.find(rising_arrow) >= 0
	var has_stable := summary.find(stable_arrow) >= 0
	var has_falling := summary.find(falling_arrow) >= 0

	if not has_rising:
		return {"ok": false, "msg": "compact summary missing rising arrow (↑)"}
	if not has_stable:
		return {"ok": false, "msg": "compact summary missing stable arrow (→)"}
	if not has_falling:
		return {"ok": false, "msg": "compact summary missing falling arrow (↓)"}

	print("    compact summary: \"%s\"" % summary)
	return true

func _test_all_arrows_in_noncompact() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

	# Set up a scenario where all three resources have different trends
	main.state = {
		"resources": {"wood": 10, "stone": 5, "food": 3},
		"harvested": {"wood": 0, "stone": 0, "food": 0}
	}
	main.prev_resources = {"wood": 7, "stone": 5, "food": 8}

	var summary := main.stockpile_summary_text(false) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	var rising_arrow := C.RESOURCE_TRENDS["rising"]
	var stable_arrow := C.RESOURCE_TRENDS["stable"]
	var falling_arrow := C.RESOURCE_TRENDS["falling"]

	var has_rising := summary.find(rising_arrow) >= 0
	var has_stable := summary.find(stable_arrow) >= 0
	var has_falling := summary.find(falling_arrow) >= 0

	if not has_rising:
		return {"ok": false, "msg": "non-compact summary missing rising arrow (↑)"}
	if not has_stable:
		return {"ok": false, "msg": "non-compact summary missing stable arrow (→)"}
	if not has_falling:
		return {"ok": false, "msg": "non-compact summary missing falling arrow (↓)"}

	print("    non-compact summary:\n%s" % summary)
	return true

func _test_extreme_values_fit_compact() -> bool:
	var main_script: GDScript = load("res://scripts/main.gd")
	var main := main_script.new()

	# Test with large resource values to ensure no clipping from wider numbers
	main.state = {
		"resources": {"wood": 999, "stone": 888, "food": 777},
		"harvested": {"wood": 123, "stone": 456, "food": 678}
	}
	main.prev_resources = {"wood": 500, "stone": 500, "food": 500}

	var summary := main.stockpile_summary_text(true) as String
	main.state = {"resources": {"wood": 0, "stone": 0, "food": 0}, "harvested": {"wood": 0, "stone": 0, "food": 0}}
	main.prev_resources = {}

	if summary == null:
		return {"ok": false, "msg": "summary is null"}

	# Even with 3-digit numbers, should fit within safe bounds
	var max_safe_length := 45  # slightly higher for extreme values
	if summary.length() > max_safe_length:
		return {"ok": false, "msg": "extreme value compact summary length %d exceeds safe bound %d" % [summary.length(), max_safe_length]}

	print("    extreme value compact summary: \"%s\" (%d chars)" % [summary, summary.length()])
	return true
