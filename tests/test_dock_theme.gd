## Unit tests for scripts/dock_theme.gd (issue #358).
##
## DockTheme is pure — no scene references — so it can be exercised in
## --script mode against a hand-built node graph. Covers:
##   - stylebox caching (same key returns the same reference)
##   - panel/button theme application
##   - the _button_styles LRU-style re-use
##
## Run: godot --headless --path . --script res://tests/test_dock_theme.gd

extends "res://tests/test_case.gd"

const DockTheme := preload("res://scripts/dock_theme.gd")


func run_tests() -> void:
	# --- make_panel_style ---
	assert_true(DockTheme.make_panel_style(Color(0.1, 0.2, 0.3), Color(0.4, 0.5, 0.6)) is StyleBoxFlat,
		"make_panel_style returns a StyleBoxFlat")
	var s := DockTheme.make_panel_style(Color(0.1, 0.2, 0.3), Color(0.4, 0.5, 0.6), 7)
	assert_eq(s.bg_color, Color(0.1, 0.2, 0.3), "make_panel_style sets bg color")
	assert_eq(s.border_color, Color(0.4, 0.5, 0.6), "make_panel_style sets border color")
	assert_eq(s.corner_radius_top_left, 7, "make_panel_style applies corner radius")
	assert_eq(s.border_width_left, 1, "make_panel_style uses a 1px border")
	var s_default := DockTheme.make_panel_style(Color.BLACK, Color.WHITE)
	assert_eq(s_default.corner_radius_bottom_right, 12, "make_panel_style default radius is 12")

	# --- make_empty_style ---
	assert_true(DockTheme.make_empty_style() is StyleBoxEmpty,
		"make_empty_style returns a StyleBoxEmpty")

	# --- _button_styles caching: same key returns the same reference ---
	var theme := DockTheme.new()
	var b1 := Button.new()
	var b2 := Button.new()
	theme.apply_button_theme(b1)
	theme.apply_button_theme(b2)
	assert_true(theme._button_styles.has("normal"), "_button_styles populated with normal")
	assert_true(theme._button_styles.has("hover"), "_button_styles populated with hover")
	assert_true(theme._button_styles.has("pressed"), "_button_styles populated with pressed")
	assert_true(theme._button_styles.has("disabled"), "_button_styles populated with disabled")
	# The cached dict must hold the SAME instance across calls (no re-creation).
	assert_true(theme._button_styles["normal"] == b1.get_theme_stylebox("normal"),
		"button normal stylebox is the cached instance")
	assert_true(theme._button_styles["normal"] == b2.get_theme_stylebox("normal"),
		"second button reuses the same cached normal stylebox")
	assert_true(b1.get_theme_stylebox("hover") == b2.get_theme_stylebox("hover"),
		"hover stylebox shared across themed buttons")
	assert_true(b1.get_theme_stylebox("disabled") == b2.get_theme_stylebox("disabled"),
		"disabled stylebox shared across themed buttons")

	# --- button theme application: colors ---
	assert_eq(b1.get_theme_color("font_color"), Color(0.95, 0.97, 1.0, 0.98),
		"apply_button_theme sets font_color")
	assert_eq(b1.get_theme_color("font_disabled_color"), Color(0.72, 0.76, 0.82, 0.6),
		"apply_button_theme sets font_disabled_color")

	# --- panel theme application via apply_theme on a hand-built graph ---
	var root := _build_theme_harness()
	theme.apply_theme(root)
	var world_panel: PanelContainer = root.get_node("%WorldPanel")
	var panel_style: StyleBoxFlat = world_panel.get_theme_stylebox("panel")
	assert_true(panel_style is StyleBoxFlat, "apply_theme styles the WorldPanel")
	assert_eq(panel_style.bg_color, Color(0.11, 0.14, 0.18, 0.92),
		"apply_theme section panel bg color")
	assert_eq(panel_style.border_color, Color(0.28, 0.34, 0.41, 0.75),
		"apply_theme section panel border color")

	# Backdrop gets its own (non-section) style.
	var backdrop: Panel = root.get_node("Backdrop")
	var backdrop_style: StyleBoxFlat = backdrop.get_theme_stylebox("panel")
	assert_eq(backdrop_style.bg_color, Color(0.06, 0.08, 0.11, 0.82),
		"apply_theme backdrop bg color")
	assert_eq(backdrop_style.corner_radius_top_left, 18,
		"apply_theme backdrop corner radius is 18")

	# A themed button in the graph gets the shared button theme + h_separation.
	var menu_button: Button = root.get_node("%HudMenuButton")
	assert_true(menu_button.get_theme_stylebox("normal") == theme._button_styles["normal"],
		"apply_theme themes the HUD menu button with the cached stylebox")
	assert_eq(menu_button.get_theme_constant("h_separation"), 6,
		"apply_theme sets h_separation on themed buttons")

	# Slider + option get their own styleboxes.
	var slider: HSlider = root.get_node("%TickSpeedSlider")
	assert_true(slider.get_theme_stylebox("slider") is StyleBoxEmpty,
		"apply_theme gives the slider an empty track stylebox")
	assert_true(slider.get_theme_stylebox("grabber_area") is StyleBoxFlat,
		"apply_theme gives the slider a grabber_area stylebox")
	var option: OptionButton = root.get_node("%DockSideOption")
	assert_true(option.get_theme_stylebox("normal") is StyleBoxFlat,
		"apply_theme styles the dock-side option normal state")
	assert_eq(option.get_theme_color("font_color"), Color(0.95, 0.97, 1.0, 0.98),
		"apply_theme sets the option font color")

	# --- LRU-style re-use: a fresh theme instance re-caches independently ---
	var theme2 := DockTheme.new()
	var b3 := Button.new()
	theme2.apply_button_theme(b3)
	assert_true(theme2._button_styles["normal"] != theme._button_styles["normal"],
		"a separate DockTheme instance caches its own styleboxes")
	assert_true(theme2._button_styles["normal"] == b3.get_theme_stylebox("normal"),
		"the second instance's button uses its own cached stylebox")

	# --- maybe_node: resolves present nodes, null for absent ones ---
	assert_true(DockTheme.maybe_node(root, "%WorldPanel") != null,
		"maybe_node resolves an existing node")
	assert_true(DockTheme.maybe_node(root, "%DoesNotExist") == null,
		"maybe_node returns null for a missing node")


## Builds the minimal node graph apply_theme() touches, mirroring the scene
## structure without loading it. Unique names are registered so %Name paths
## resolve headless.
func _build_theme_harness() -> Control:
	var root := Control.new()
	root.name = "DockRoot"

	var backdrop := Panel.new()
	backdrop.name = "Backdrop"
	root.add_child(backdrop)

	var world_panel := PanelContainer.new()
	world_panel.name = "WorldPanel"
	root.add_child(world_panel)
	world_panel.owner = root
	world_panel.set_unique_name_in_owner(true)

	var menu_button := Button.new()
	menu_button.name = "HudMenuButton"
	root.add_child(menu_button)
	menu_button.owner = root
	menu_button.set_unique_name_in_owner(true)

	var slider := HSlider.new()
	slider.name = "TickSpeedSlider"
	root.add_child(slider)
	slider.owner = root
	slider.set_unique_name_in_owner(true)

	var option := OptionButton.new()
	option.name = "DockSideOption"
	root.add_child(option)
	option.owner = root
	option.set_unique_name_in_owner(true)

	return root
