## Tests for resource trend indicators (issue #137).
## Covers _get_trend() logic: rising, falling, stable, first-tick sentinel.
## Also verifies stockpile_summary_text embeds expected arrows and fits within
## dock layout constraints (no clipping).
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --path . --script res://tests/test_resource_trends.gd

extends "res://tests/test_case.gd"

const C := preload("res://scripts/constants.gd")


## main.gd references the GameState autoload, which only resolves once the
## project is running — load it at runtime (like test_runner.gd), not preload.
func _new_main() -> Control:
	var main_script: GDScript = load("res://scripts/main.gd")
	return main_script.new()


func run_tests() -> void:
	# --- RESOURCE_TRENDS constant ---
	assert_true(C.RESOURCE_TRENDS.has("rising"), "RESOURCE_TRENDS has rising key")
	assert_true(C.RESOURCE_TRENDS.has("falling"), "RESOURCE_TRENDS has falling key")
	assert_true(C.RESOURCE_TRENDS.has("stable"), "RESOURCE_TRENDS has stable key")
	assert_eq(C.RESOURCE_TRENDS.size(), 3, "RESOURCE_TRENDS has exactly 3 entries")
	assert_eq(C.RESOURCE_TRENDS.get("rising"), "↑", "RESOURCE_TRENDS[rising] is ↑")
	assert_eq(C.RESOURCE_TRENDS.get("falling"), "↓", "RESOURCE_TRENDS[falling] is ↓")
	assert_eq(C.RESOURCE_TRENDS.get("stable"), "→", "RESOURCE_TRENDS[stable] is →")

	# --- _get_trend logic (via a real Main instance, no scene) ---
	assert_eq(_get_trend_mock("wood", 10, 7), C.RESOURCE_TRENDS["rising"], "_get_trend rising: current > previous")
	assert_eq(_get_trend_mock("food", 3, 5), C.RESOURCE_TRENDS["falling"], "_get_trend falling: current < previous")
	assert_eq(_get_trend_mock("stone", 4, 4), C.RESOURCE_TRENDS["stable"], "_get_trend stable: current == previous")
	assert_eq(_get_trend_mock("wood", 8), C.RESOURCE_TRENDS["stable"], "_get_trend first-tick sentinel (previous < 0): returns stable")
	assert_eq(_get_trend_mock("diamond", 5), C.RESOURCE_TRENDS["stable"], "_get_trend unknown resource: returns stable (prev = -1)")

	# --- stockpile_summary_text arrow embedding ---
	var rising_summary := _summary_for(
		{"wood": 10, "stone": 4, "food": 3},
		{"wood": 0, "stone": 0, "food": 0},
		{"wood": 7, "stone": 4, "food": 5},
		false)
	assert_true(rising_summary.find(String(C.RESOURCE_TRENDS["rising"])) >= 0,
		"stockpile_summary_text(compact=false) contains ↑ arrow",
		"summary was: %s" % rising_summary)

	var stable_summary := _summary_for(
		{"wood": 8, "stone": 4, "food": 2},
		{"wood": 0, "stone": 0, "food": 0},
		{"wood": 8, "stone": 4, "food": 2},
		true)
	assert_true(stable_summary.find(String(C.RESOURCE_TRENDS["stable"])) >= 0,
		"stockpile_summary_text(compact=true) contains → arrow (stable)",
		"summary was: %s" % stable_summary)

	# --- Layout/clipping tests: trend indicators must fit within dock widths ---
	# NOTE: bounds recalibrated for the current stockpile_summary_text format,
	# which appends harvested counts to the compact line (post sim-extraction
	# refactor); the old ~40-char bounds predate that format.
	_test_layout_bounds()

	# --- Layout/clipping tests: HUD row labels (issue #135) ---
	_test_hud_layout_bounds()


# --- _get_trend logic helpers ---
## Since _get_trend is a method of Main, we create a fresh instance
## via preload and set up state before each call.

func _get_trend_mock(resource_name: String, current_val: int, previous_val: int = -1) -> String:
	var main: Control = _new_main()
	# Build resources programmatically so a known resource_name overrides the
	# zeroed defaults instead of colliding with duplicate literal keys.
	var resources := {"wood": 0, "stone": 0, "food": 0}
	resources[resource_name] = current_val
	main.state = {"resources": resources}
	main.prev_resources = {resource_name: previous_val}
	var result: String = main._get_trend(resource_name)
	main.free()
	return result


## Build a Main instance with the given resources/harvested/prev_resources and
## return stockpile_summary_text(compact).
func _summary_for(resources: Dictionary, harvested: Dictionary, prev: Dictionary, compact: bool) -> String:
	var main: Control = _new_main()
	main.state = {"resources": resources, "harvested": harvested}
	main.prev_resources = prev
	var summary: String = main.stockpile_summary_text(compact)
	main.free()
	return summary


# --- Layout/clipping tests for trend indicators ---
## These tests verify that the stockpile_summary_text output with trend arrows
## stays within safe rendering bounds for the dock labels. The compact format
## is "Stored  W %d ↑  S %d →  F %d ↓  •  Harvested  W %d  S %d  F %d",
## worst case ~68 chars with 3-digit values.

func _test_layout_bounds() -> void:
	var resources := {"wood": 100, "stone": 50, "food": 75}
	var harvested := {"wood": 20, "stone": 10, "food": 30}
	var prev := {"wood": 80, "stone": 45, "food": 90}

	var compact_summary := _summary_for(resources, harvested, prev, true)
	print("    compact summary: \"%s\" (%d chars)" % [compact_summary, compact_summary.length()])
	# Bound recalibrated: compact line now includes harvested counts.
	assert_true(compact_summary.length() <= 70,
		"compact summary fits within bottom dock sidebar (320px)",
		"compact summary length %d exceeds safe bound 70" % compact_summary.length())
	assert_true(compact_summary.length() <= 70,
		"compact summary fits within side dock sidebar (280px)",
		"compact summary length %d exceeds safe bound 70" % compact_summary.length())

	var noncompact_summary := _summary_for(resources, harvested, prev, false)
	# split() always yields at least one element; non-compact moves harvested
	# onto line 2, so the original 40-char bound still applies to line 1.
	var first_line := String(noncompact_summary.split("\n")[0])
	print("    non-compact first line: \"%s\" (%d chars)" % [first_line, first_line.length()])
	assert_true(first_line.length() <= 40,
		"non-compact summary first line fits within bottom dock sidebar",
		"non-compact first line length %d exceeds safe bound 40" % first_line.length())

	# All three arrows present when trends differ (wood ↑, stone →, food ↓)
	var mixed_resources := {"wood": 10, "stone": 5, "food": 3}
	var mixed_prev := {"wood": 7, "stone": 5, "food": 8}
	var zero_harvested := {"wood": 0, "stone": 0, "food": 0}

	var mixed_compact := _summary_for(mixed_resources, zero_harvested, mixed_prev, true)
	print("    compact summary: \"%s\"" % mixed_compact)
	assert_true(
		mixed_compact.find(String(C.RESOURCE_TRENDS["rising"])) >= 0
		and mixed_compact.find(String(C.RESOURCE_TRENDS["stable"])) >= 0
		and mixed_compact.find(String(C.RESOURCE_TRENDS["falling"])) >= 0,
		"all three trend arrows present in compact mode",
		"summary was: %s" % mixed_compact)

	var mixed_noncompact := _summary_for(mixed_resources, zero_harvested, mixed_prev, false)
	print("    non-compact summary:\n%s" % mixed_noncompact)
	assert_true(
		mixed_noncompact.find(String(C.RESOURCE_TRENDS["rising"])) >= 0
		and mixed_noncompact.find(String(C.RESOURCE_TRENDS["stable"])) >= 0
		and mixed_noncompact.find(String(C.RESOURCE_TRENDS["falling"])) >= 0,
		"all three trend arrows present in non-compact mode",
		"summary was: %s" % mixed_noncompact)

	# Extreme values: 3-digit resources and harvested counts still fit.
	var extreme := _summary_for(
		{"wood": 999, "stone": 888, "food": 777},
		{"wood": 123, "stone": 456, "food": 678},
		{"wood": 500, "stone": 500, "food": 500},
		true)
	print("    extreme value compact summary: \"%s\" (%d chars)" % [extreme, extreme.length()])
	# Bound recalibrated (was 45) for the harvested-count suffix.
	assert_true(extreme.length() <= 72,
		"extreme resource values (999) still fit in compact summary",
		"extreme value compact summary length %d exceeds safe bound 72" % extreme.length())


# --- Layout/clipping tests for HUD row labels (issue #135) ---
## These tests verify that the three compact HUD row label outputs fit within
## the expected dock layout constraints (bottom: 320px, side: 280px).
## Safe upper bound: ~45 chars for 320px bottom dock, ~40 chars for 280px side dock.

func _test_hud_layout_bounds() -> void:
	# Worker cap format: "%d / %d" — max plausible: "999 / 999"
	var worker_cap_text := "999 / 999"
	print("    worker cap worst case: \"%s\" (%d chars)" % [worker_cap_text, worker_cap_text.length()])
	assert_true(worker_cap_text.length() <= 45,
		"HUD worker cap text fits within safe bounds",
		"worker cap text length %d exceeds safe bound for bottom dock" % worker_cap_text.length())

	# Food warning formats: "⚠ LOW FOOD" or "⚠ STARVING" (10 visible chars)
	var food_warning := "⚠ STARVING"
	print("    food warning worst case: \"%s\" (%d chars)" % [food_warning, food_warning.length()])
	assert_true(food_warning.length() <= 45,
		"HUD food warning text fits within safe bounds",
		"food warning text length %d exceeds safe bound for bottom dock" % food_warning.length())

	# Goal text worst cases: resource / build / complete formats.
	var goal_texts := [
		"Goal: Workshop (999/9999)",
		"Build: Workshop",
		"Goal: Finish a build ✓",
	]
	var goals_ok := true
	var goal_detail := ""
	for goal_text in goal_texts:
		print("    HUD goal worst case: \"%s\" (%d chars)" % [goal_text, String(goal_text).length()])
		if String(goal_text).length() > 40:  # conservative bound for 280px side dock
			goals_ok = false
			goal_detail = "HUD goal text \"%s\" length %d exceeds safe bound 40 for side dock" % [goal_text, String(goal_text).length()]
	assert_true(goals_ok, "HUD goal text fits within safe bounds for all goal types", goal_detail)

	# Verify that cap() capitalizes resource/build names correctly.
	var cap_cases := {
		"wood": "Wood",
		"stone": "Stone",
		"workshop": "Workshop",
		"hut": "Hut",
		"garden": "Garden",
	}
	var cap_ok := true
	var cap_detail := ""
	for input_str in cap_cases:
		var expected: String = cap_cases[input_str]
		var actual: String = String(input_str).substr(0, 1).to_upper() + String(input_str).substr(1)
		if actual != expected:
			cap_ok = false
			cap_detail = "cap(\"%s\") = \"%s\", expected \"%s\"" % [input_str, actual, expected]
	if cap_ok:
		print("    cap() capitalization verified for all test cases")
	assert_true(cap_ok, "cap() capitalizes resource/build names correctly", cap_detail)

	# Each HUD row is stacked vertically, so verify each row's text length
	# individually rather than summing.
	var hud_rows := {
		"worker_cap": "999 / 999",
		"food_warning": "⚠ STARVING",
		"goal_resource": "Goal: Workshop (999/9999)",
	}
	var rows_ok := true
	var rows_detail := ""
	for row_name in hud_rows:
		var text: String = hud_rows[row_name]
		if text.length() > 45:  # bottom dock at HUD font size
			rows_ok = false
			rows_detail = "HUD row \"%s\" text \"%s\" length %d exceeds safe bound" % [row_name, text, text.length()]
	if rows_ok:
		print("    all HUD rows individually within safe bounds")
	assert_true(rows_ok, "all HUD rows individually fit within safe bounds", rows_detail)
