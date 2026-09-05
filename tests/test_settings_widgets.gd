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
	# unavailable in --script mode, so a subclass no-ops it.
	var main_script: GDScript = load("res://scripts/main.gd")
	var stub_script := GDScript.new()
	stub_script.source_code = "extends \"res://scripts/main.gd\"\nfunc save_settings() -> void:\n\tpass\n"
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

	main.free()
	main_scene.free()
