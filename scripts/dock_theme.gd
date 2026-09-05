## Dock theme/style construction — extracted from main.gd so styling concerns
## stop growing the simulation facade (issue #358).
##
## Pure: holds no scene references. apply_theme() takes the dock root node and
## resolves themed controls by unique name, so it can be exercised in --script
## mode against a hand-built node graph (see tests/test_dock_theme.gd).

class_name DockTheme


## Shared button styleboxes, cached once and reused across every themed
## button — they are never mutated per-button, so one instance per state
## suffices (audit #279 item 4).
var _button_styles: Dictionary = {}


## Returns a StyleBoxFlat with a 1px border and a uniform corner radius.
static func make_panel_style(bg: Color, border: Color, corner_radius: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	return style


## Returns an empty (invisible) stylebox for controls that should not draw a
## background (e.g. the tick-speed slider track).
static func make_empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


## Resolves a node by path under `root`, or null when absent.
static func maybe_node(root: Node, path: String) -> Node:
	return root.get_node(path) if root.has_node(path) else null


## Applies the full dock theme: backdrop, section panels, margins, boxes,
## labels, themed buttons, the tick-speed slider, and the dock-side option.
## `root` is the dock Control that owns the themed controls.
func apply_theme(root: Node) -> void:
	var backdrop := maybe_node(root, "Backdrop") as Panel
	if backdrop:
		backdrop.add_theme_stylebox_override("panel", make_panel_style(Color(0.06, 0.08, 0.11, 0.82), Color(0.23, 0.29, 0.36, 0.55), 18))

	var section_style := make_panel_style(Color(0.11, 0.14, 0.18, 0.92), Color(0.28, 0.34, 0.41, 0.75), 12)
	for panel_name in ["WorldPanel", "BuildPanel", "PriorityPanel", "CrewPanel", "EventPanel", "SettingsPanel", "MenuPanel", "ActionPanel"]:
		var panel := maybe_node(root, "%%%s" % panel_name) as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", section_style.duplicate())

	for margin_name in ["MenuMargin", "BuildMargin", "PriorityMargin", "CrewMargin", "EventMargin", "SettingsMargin"]:
		var margin := maybe_node(root, "%%%s" % margin_name) as MarginContainer
		if margin:
			margin.add_theme_constant_override("margin_left", 14)
			margin.add_theme_constant_override("margin_top", 14)
			margin.add_theme_constant_override("margin_right", 14)
			margin.add_theme_constant_override("margin_bottom", 14)

	for box_name in ["BuildBox", "PriorityBox", "CrewBox", "EventBox", "SettingsBox"]:
		var box := maybe_node(root, "%%%s" % box_name) as BoxContainer
		if box:
			box.add_theme_constant_override("separation", 10)

	for title_name in ["BuildTitle", "PriorityTitle", "CrewTitle", "EventTitle", "SettingsTitle", "ResourceLabel"]:
		var label := maybe_node(root, "%%%s" % title_name) as Label
		if label:
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0, 0.96))

	for label_name in ["GatherLabel", "HaulLabel", "BuildLabel", "DockSideLabel", "TickSpeedLabel", "WorldLabel", "ActivityLabel", "StatusLabel", "HudHint", "TickSpeedValue", "BuildPreviewLabel"]:
		var info_label := maybe_node(root, "%%%s" % label_name) as Label
		if info_label:
			info_label.add_theme_font_size_override("font_size", 12)
			info_label.add_theme_color_override("font_color", Color(0.86, 0.9, 0.95, 0.84))

	for rank_name in ["GatherRank", "HaulRank", "BuildRank"]:
		var rank := maybe_node(root, "%%%s" % rank_name) as Label
		if rank:
			rank.add_theme_font_size_override("font_size", 12)
			rank.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0, 1.0))

	for button_name in ["BuildModeButton", "HudMenuButton", "MenuButton", "GatherUpButton", "GatherDownButton", "HaulUpButton", "HaulDownButton", "BuildUpButton", "BuildDownButton", "SaveButton", "ResetButton", "NewGameButton", "SaveGameButton", "LoadGameButton", "SettingsButton", "ExitButton", "SettingsCloseButton"]:
		var button := maybe_node(root, "%%%s" % button_name) as Button
		if button:
			apply_button_theme(button)
			button.add_theme_constant_override("h_separation", 6)

	var build_buttons := maybe_node(root, "%BuildButtons") as VBoxContainer
	if build_buttons:
		build_buttons.add_theme_constant_override("separation", 6)
		for child in build_buttons.get_children():
			if child is Button:
				apply_button_theme(child)

	var slider := maybe_node(root, "%TickSpeedSlider") as HSlider
	if slider:
		slider.add_theme_stylebox_override("slider", make_empty_style())
		slider.add_theme_stylebox_override("grabber_area", make_panel_style(Color(0.17, 0.21, 0.27, 0.85), Color(0.26, 0.32, 0.39, 0.8), 6))
		slider.add_theme_stylebox_override("grabber_area_highlight", make_panel_style(Color(0.24, 0.31, 0.39, 0.95), Color(0.44, 0.58, 0.72, 0.95), 6))
		slider.custom_minimum_size = Vector2(0, 24)

	var option := maybe_node(root, "%DockSideOption") as OptionButton
	if option:
		option.add_theme_stylebox_override("normal", make_panel_style(Color(0.18, 0.23, 0.3, 0.96), Color(0.36, 0.45, 0.55, 0.9), 10))
		option.add_theme_stylebox_override("hover", make_panel_style(Color(0.23, 0.3, 0.39, 1.0), Color(0.49, 0.64, 0.78, 1.0), 10))
		option.add_theme_stylebox_override("pressed", make_panel_style(Color(0.13, 0.18, 0.24, 1.0), Color(0.42, 0.58, 0.71, 0.95), 10))
		option.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.98))


## Shared button styling for every themed Button in the dock UI.
func apply_button_theme(button: Button) -> void:
	if _button_styles.is_empty():
		_button_styles = {
			"normal": make_panel_style(Color(0.18, 0.23, 0.3, 0.96), Color(0.36, 0.45, 0.55, 0.9), 10),
			"hover": make_panel_style(Color(0.23, 0.3, 0.39, 1.0), Color(0.49, 0.64, 0.78, 1.0), 10),
			"pressed": make_panel_style(Color(0.13, 0.18, 0.24, 1.0), Color(0.42, 0.58, 0.71, 0.95), 10),
			"disabled": make_panel_style(Color(0.12, 0.15, 0.19, 0.65), Color(0.24, 0.28, 0.33, 0.45), 10),
		}
	for state in _button_styles:
		button.add_theme_stylebox_override(state, _button_styles[state])
	button.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.98))
	button.add_theme_color_override("font_disabled_color", Color(0.72, 0.76, 0.82, 0.6))
