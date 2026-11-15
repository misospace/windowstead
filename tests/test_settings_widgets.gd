extends "res://tests/test_case.gd"

# ── Scene-placed Focus Mode / Zoom settings widgets (#359) ───────────────────
# The Focus Mode CheckButton, Zoom label, and Zoom HSlider used to be built at
# runtime in main.gd _ready(); they now live in scenes/main.tscn inside the
# SettingsBox. This suite verifies the scene describes them and that
# wire_settings_controls() keeps the persisted-settings round-trip semantics.

const Constants := preload("res://scripts/constants.gd")

func run_tests() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert_not_null(scene, "scene: main.tscn loads")
	var main_scene: Node = scene.instantiate()
	await process_frame

	var settings_box := main_scene.get_node("Backdrop/Margin/Root/SidebarScroll/Right/ManagementPanels/SettingsPanel/SettingsMargin/SettingsBox")
	assert_not_null(settings_box, "scene: SettingsBox exists")

	var focus_btn := settings_box.get_node("FocusModeButton")
	assert_true(focus_btn is CheckButton, "scene: FocusModeButton is a CheckButton")
	assert_eq(focus_btn.text, "Focus Mode", "scene: FocusModeButton text")

	var zoom_label := settings_box.get_node("ZoomLabel")
	assert_true(zoom_label is Label, "scene: ZoomLabel is a Label")

	var zoom_slider := settings_box.get_node("ZoomSlider")
	assert_true(zoom_slider is HSlider, "scene: ZoomSlider is an HSlider")

	# main.gd must no longer construct these widgets at runtime.
	var main_source := FileAccess.get_file_as_string("res://scripts/main.gd")
	assert_false(main_source.contains("CheckButton.new()"), "main.gd: no runtime CheckButton construction")
	assert_false(main_source.contains("settings_panel.get_node(\"SettingsMargin/SettingsBox\")"), "main.gd: no path-coupled SettingsBox add_child")

	# ── wire_settings_controls: persisted-settings round-trip ──
	# save_settings() writes through the GameState autoload, which is
	# unavailable in --script mode, so a subclass no-ops it. Returns bool to
	# match the parent (issue #409).
	var main_script: GDScript = load("res://scripts/main.gd")
	var stub_script := GDScript.new()
	stub_script.source_code = "extends \"res://scripts/main.gd\"\nfunc save_settings() -> bool:\n\treturn true\n"
	assert_true(stub_script.reload() == OK, "stub: save_settings no-op subclass compiles")
	var main: Control = stub_script.new()
	main.focus_mode_btn = focus_btn
	main.zoom_label = zoom_label
	main.zoom_slider = zoom_slider
	# save_settings() is stubbed, but keep the members it reads assigned.
	var dock_option := OptionButton.new()
	for anchor in main.DOCK_OPTIONS:
		dock_option.add_item(anchor)
	main.dock_side_option = dock_option
	main.tick_speed_slider = HSlider.new()
	main.settings = {"focus_mode": true, "zoom_factor": 1.5}

	main.wire_settings_controls()
	assert_true(focus_btn.button_pressed, "wire: focus button reflects saved focus_mode")
	assert_eq(zoom_slider.value, 1.5, "wire: slider reflects saved zoom_factor")
	assert_eq(zoom_slider.min_value, Constants.ZOOM_MIN, "wire: slider min from Constants")
	assert_eq(zoom_slider.max_value, Constants.ZOOM_MAX, "wire: slider max from Constants")
	assert_eq(zoom_slider.step, Constants.ZOOM_STEP, "wire: slider step from Constants")
	assert_eq(zoom_label.text, "Zoom: 1.5", "wire: zoom label reflects saved zoom_factor")

	# Toggling the button persists focus_mode.
	focus_btn.button_pressed = false
	await process_frame
	assert_eq(main.settings.get("focus_mode"), false, "toggle: focus_mode persisted false")

	# Moving the slider persists zoom_factor and rebuilds the label.
	# In headless mode the Range value setter may not emit value_changed,
	# so we emit it explicitly to exercise the handler.
	zoom_slider.value = 0.8
	zoom_slider.emit_signal("value_changed", 0.8)
	await process_frame
	assert_eq(main.settings.get("zoom_factor"), 0.8, "slider: zoom_factor persisted")
	assert_eq(zoom_label.text, "Zoom: 0.8", "slider: label rebuilt from new value")

	# ── validate_settings: corrupt settings heal instead of crashing boot ──
	# load_settings() used to merge the raw file unchecked; float() on a
	# null/Dictionary/empty-string zoom_factor aborted _ready(), and
	# numeric-string or empty zoom parsed to 0.0 → 1px tiles (issue #490).
	# The heal is pure, so it runs directly on the stub instance.
	var corrupt_cases := [
		{"name": "heal: zoom_factor null boots default", "raw": {"zoom_factor": null}, "key": "zoom_factor", "want": 1.0},
		{"name": "heal: zoom_factor Dictionary boots default", "raw": {"zoom_factor": {"a": 1}}, "key": "zoom_factor", "want": 1.0},
		{"name": "heal: zoom_factor empty string boots default", "raw": {"zoom_factor": ""}, "key": "zoom_factor", "want": 1.0},
		{"name": "heal: zoom_factor numeric string boots default", "raw": {"zoom_factor": "1.5"}, "key": "zoom_factor", "want": 1.0},
		{"name": "heal: zoom_factor zero clamps to slider min", "raw": {"zoom_factor": 0.0}, "key": "zoom_factor", "want": Constants.ZOOM_MIN},
		{"name": "heal: zoom_factor huge clamps to slider max", "raw": {"zoom_factor": 99.0}, "key": "zoom_factor", "want": Constants.ZOOM_MAX},
		{"name": "heal: tick_speed string falls back to tier", "raw": {"tick_speed": "fast"}, "key": "tick_speed", "want": 0},
		{"name": "heal: tick_speed negative clamps into tiers", "raw": {"tick_speed": -3}, "key": "tick_speed", "want": 0},
		{"name": "heal: tick_speed huge clamps into tiers", "raw": {"tick_speed": 99}, "key": "tick_speed", "want": main.TICK_SPEEDS.size() - 1},
		{"name": "heal: tick_speed integral float accepted", "raw": {"tick_speed": 1.0}, "key": "tick_speed", "want": 1},
		{"name": "heal: focus_mode int falls back to default", "raw": {"focus_mode": 1}, "key": "focus_mode", "want": false},
		{"name": "heal: focus_mode string falls back to default", "raw": {"focus_mode": "yes"}, "key": "focus_mode", "want": false},
		{"name": "heal: dock_anchor unknown falls back to bottom", "raw": {"dock_anchor": "top"}, "key": "dock_anchor", "want": "bottom"},
		{"name": "heal: dock_anchor wrong type falls back to bottom", "raw": {"dock_anchor": 7}, "key": "dock_anchor", "want": "bottom"},
	]
	for corrupt_case in corrupt_cases:
		var healed: Dictionary = main.validate_settings(corrupt_case["raw"])
		assert_eq(healed.get(corrupt_case["key"]), corrupt_case["want"], corrupt_case["name"])

	# Unknown keys pass through untouched for forward compatibility.
	assert_eq(main.validate_settings({"future_key": "v"}).get("future_key"), "v", "heal: unknown keys pass through")

	# The integral-float tick tier is coerced to a real int, not left as float.
	assert_eq(typeof(main.validate_settings({"tick_speed": 1.0})["tick_speed"]), TYPE_INT, "heal: tick_speed coerced to int")

	# Valid values survive untouched (round-trip unchanged), and the healed
	# zoom feeds tile math without crashing.
	var valid: Dictionary = main.validate_settings({"dock_anchor": "left", "tick_speed": 2, "focus_mode": true, "zoom_factor": 1.5})
	assert_eq(valid.get("dock_anchor"), "left", "heal: valid dock_anchor unchanged")
	assert_eq(valid.get("tick_speed"), 2, "heal: valid tick_speed unchanged")
	assert_eq(valid.get("focus_mode"), true, "heal: valid focus_mode unchanged")
	assert_eq(valid.get("zoom_factor"), 1.5, "heal: valid zoom_factor unchanged")
	main.settings = valid
	assert_true(main.tile_size_for_anchor("left", Rect2i(0, 0, 1920, 1080)).x > 0, "heal: healed zoom feeds tile math")

	main.free()
	main_scene.free()
