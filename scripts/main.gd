extends Control
const Constants := preload("res://scripts/constants.gd")
const WORKER_NAMES := Constants.WORKER_NAMES
const BASE_TICK_SECONDS := Constants.BASE_TICK_SECONDS
const EVENT_INTERVAL_TICKS := Constants.EVENT_INTERVAL_TICKS
const RESOURCE_COLORS := Constants.RESOURCE_COLORS
const STRUCTURE_COLORS := Constants.STRUCTURE_COLORS
const TILE_BACKDROPS := Constants.TILE_BACKDROPS
const WORKER_BADGE_COLORS := Constants.WORKER_BADGE_COLORS
const BUILD_COSTS := Constants.BUILD_COSTS
const BUILD_EFFECTS := Constants.BUILD_EFFECTS
const LayoutMath := preload("res://scripts/layout_math.gd")
const BUILD_UNLOCKS := Constants.BUILD_UNLOCKS
const RotatingGoal := preload("res://scripts/rotating_goal.gd")
const RESOURCE_TRENDS := Constants.RESOURCE_TRENDS
const ColonyStance := preload("res://scripts/colony_stance.gd")


@onready var world_grid: GridContainer = %WorldGrid
@onready var world_overlay: Control = %WorldOverlay
@onready var resource_label: Label = %ResourceLabel
@onready var goal_label: Label = %GoalLabel
@onready var status_label: Label = %StatusLabel
@onready var activity_label: Label = %ActivityLabel
@onready var world_label: Label = %WorldLabel
@onready var root_box: BoxContainer = get_node("Backdrop/Margin/Root")
@onready var left_column: VBoxContainer = get_node("Backdrop/Margin/Root/Left")
@onready var world_panel: PanelContainer = get_node("Backdrop/Margin/Root/Left/WorldPanel")
@onready var sidebar_scroll: ScrollContainer = get_node("Backdrop/Margin/Root/SidebarScroll")
@onready var backdrop: Panel = get_node("Backdrop")
@onready var title_label: Label = get_node("Backdrop/Margin/Root/Left/Title")
@onready var subtitle_label: Label = get_node("Backdrop/Margin/Root/Left/Subtitle")
@onready var crew_list: VBoxContainer = %CrewList
@onready var crew_cap_info: Label = %CrewCapInfo
@onready var crew_food_info: Label = %CrewFoodInfo
@onready var recruit_button: Button = %RecruitButton
@onready var crew_warning: Label = %CrewWarning
@onready var event_log: RichTextLabel = %EventLog
@onready var gather_rank: Label = %GatherRank
@onready var haul_rank: Label = %HaulRank
@onready var build_rank: Label = %BuildRank
@onready var menu_button: Button = %HudMenuButton
@onready var menu_hint: Label = %HudHint
@onready var build_mode_button: Button = %BuildModeButton
@onready var build_preview_label: Label = %BuildPreviewLabel
@onready var menu_actions: VBoxContainer = %MenuActions
@onready var management_panels: VBoxContainer = %ManagementPanels
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var dock_side_option: OptionButton = %DockSideOption
@onready var tick_speed_slider: HSlider = %TickSpeedSlider
@onready var tick_speed_value: Label = %TickSpeedValue

var tile_views: Array[Dictionary] = []
var state: Dictionary = {}
var settings: Dictionary = {}
var tick := 0
var food_upkeep_tracker := 0
var rng := RandomNumberGenerator.new()
var prev_resources: Dictionary = {}
var tick_timer: Timer
var worker_texture_cache: Dictionary = {}
var pending_build_kind := ""
var priority_order: Array[String] = ["build", "haul", "gather"]
var colony_stance := ColonyStance.STANCE_BALANCED
var hover_tile_index := -1
var drag_start_pos := Vector2i(-9999, -9999)
var edge_snap_cooldown := 0.0
const EDGE_SNAP_THRESHOLD := 40
var grid_w := LayoutMath.BOTTOM_GRID_W
var grid_h := LayoutMath.BOTTOM_GRID_H
var stockpile_pos := LayoutMath.stockpile_pos_for_anchor("bottom")
var anchor_family := "bottom"
var tile_size := Vector2i(56, 56)
var _last_usable_rect: Rect2i
var _dock_recheck_timer: float = 0.0
const DOCK_RECHECK_COOLDOWN := 0.5
var worker_overlay_nodes: Dictionary = {}
var startup_panel: PanelContainer
var startup_anchor_buttons: Dictionary = {}
var startup_selected_anchor := "bottom"
var side_header_row: HBoxContainer
var side_button_row: HBoxContainer
var side_status_column: VBoxContainer
var bottom_header_row: HBoxContainer
var bottom_status_column: VBoxContainer
var bottom_button_row: HBoxContainer
var game_active := false
var active_goal: Dictionary = {}
var completed_goal_ids: Array = []

func make_panel_style(bg: Color, border: Color, corner_radius: int = 12) -> StyleBoxFlat:
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

func make_empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()

func maybe_node(path: String) -> Node:
	return get_node(path) if has_node(path) else null

func apply_theme() -> void:
	var backdrop_style := make_panel_style(Color(0.06, 0.08, 0.11, 0.82), Color(0.23, 0.29, 0.36, 0.55), 18)
	backdrop.add_theme_stylebox_override("panel", backdrop_style)

	var section_style := make_panel_style(Color(0.11, 0.14, 0.18, 0.92), Color(0.28, 0.34, 0.41, 0.75), 12)
	for panel_name in ["WorldPanel", "BuildPanel", "PriorityPanel", "CrewPanel", "EventPanel", "SettingsPanel", "MenuPanel", "ActionPanel"]:
		var panel := maybe_node("%%%s" % panel_name) as PanelContainer
		if panel:
			panel.add_theme_stylebox_override("panel", section_style.duplicate())

	for margin_name in ["MenuMargin", "BuildMargin", "PriorityMargin", "CrewMargin", "EventMargin", "SettingsMargin"]:
		var margin := maybe_node("%%%s" % margin_name) as MarginContainer
		if margin:
			margin.add_theme_constant_override("margin_left", 14)
			margin.add_theme_constant_override("margin_top", 14)
			margin.add_theme_constant_override("margin_right", 14)
			margin.add_theme_constant_override("margin_bottom", 14)

	for box_name in ["BuildBox", "PriorityBox", "CrewBox", "EventBox", "SettingsBox"]:
		var box := maybe_node("%%%s" % box_name) as BoxContainer
		if box:
			box.add_theme_constant_override("separation", 10)

	for title_name in ["BuildTitle", "PriorityTitle", "CrewTitle", "EventTitle", "SettingsTitle", "ResourceLabel"]:
		var label := maybe_node("%%%s" % title_name) as Label
		if label:
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0, 0.96))

	for label_name in ["GatherLabel", "HaulLabel", "BuildLabel", "DockSideLabel", "TickSpeedLabel", "WorldLabel", "ActivityLabel", "StatusLabel", "HudHint", "TickSpeedValue", "BuildPreviewLabel"]:
		var info_label := maybe_node("%%%s" % label_name) as Label
		if info_label:
			info_label.add_theme_font_size_override("font_size", 12)
			info_label.add_theme_color_override("font_color", Color(0.86, 0.9, 0.95, 0.84))

	for rank_name in ["GatherRank", "HaulRank", "BuildRank"]:
		var rank := maybe_node("%%%s" % rank_name) as Label
		if rank:
			rank.add_theme_font_size_override("font_size", 12)
			rank.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0, 1.0))

	var button_normal := make_panel_style(Color(0.18, 0.23, 0.3, 0.96), Color(0.36, 0.45, 0.55, 0.9), 10)
	var button_hover := make_panel_style(Color(0.23, 0.3, 0.39, 1.0), Color(0.49, 0.64, 0.78, 1.0), 10)
	var button_pressed := make_panel_style(Color(0.13, 0.18, 0.24, 1.0), Color(0.42, 0.58, 0.71, 0.95), 10)
	var button_disabled := make_panel_style(Color(0.12, 0.15, 0.19, 0.65), Color(0.24, 0.28, 0.33, 0.45), 10)
	for button_name in ["BuildModeButton", "HudMenuButton", "MenuButton", "GatherUpButton", "GatherDownButton", "HaulUpButton", "HaulDownButton", "BuildUpButton", "BuildDownButton", "SaveButton", "ResetButton", "NewGameButton", "SaveGameButton", "LoadGameButton", "SettingsButton", "ExitButton", "SettingsCloseButton"]:
		var button := maybe_node("%%%s" % button_name) as Button
		if button:
			button.add_theme_stylebox_override("normal", button_normal.duplicate())
			button.add_theme_stylebox_override("hover", button_hover.duplicate())
			button.add_theme_stylebox_override("pressed", button_pressed.duplicate())
			button.add_theme_stylebox_override("disabled", button_disabled.duplicate())
			button.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.98))
			button.add_theme_color_override("font_disabled_color", Color(0.72, 0.76, 0.82, 0.6))
			button.add_theme_constant_override("h_separation", 6)

	var build_buttons := maybe_node("%BuildButtons") as VBoxContainer
	if build_buttons:
		build_buttons.add_theme_constant_override("separation", 6)
		for child in build_buttons.get_children():
			if child is Button:
				child.add_theme_stylebox_override("normal", button_normal.duplicate())
				child.add_theme_stylebox_override("hover", button_hover.duplicate())
				child.add_theme_stylebox_override("pressed", button_pressed.duplicate())
				child.add_theme_stylebox_override("disabled", button_disabled.duplicate())
				child.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.98))
				child.add_theme_color_override("font_disabled_color", Color(0.72, 0.76, 0.82, 0.6))

	var slider := maybe_node("%TickSpeedSlider") as HSlider
	if slider:
		slider.add_theme_stylebox_override("slider", make_empty_style())
		slider.add_theme_stylebox_override("grabber_area", make_panel_style(Color(0.17, 0.21, 0.27, 0.85), Color(0.26, 0.32, 0.39, 0.8), 6))
		slider.add_theme_stylebox_override("grabber_area_highlight", make_panel_style(Color(0.24, 0.31, 0.39, 0.95), Color(0.44, 0.58, 0.72, 0.95), 6))
		slider.custom_minimum_size = Vector2(0, 24)

	var option := maybe_node("%DockSideOption") as OptionButton
	if option:
		option.add_theme_stylebox_override("normal", button_normal.duplicate())
		option.add_theme_stylebox_override("hover", button_hover.duplicate())
		option.add_theme_stylebox_override("pressed", button_pressed.duplicate())
		option.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.98))

func _ready() -> void:
	rng.randomize()
	load_settings()
	configure_window()
	title_label.visible = false
	subtitle_label.visible = false
	activity_label.visible = false
	world_grid.columns = grid_w
	wire_controls()
	tick_timer = Timer.new()
	tick_timer.wait_time = tick_seconds_for_setting()
	tick_timer.autostart = true
	tick_timer.timeout.connect(_on_tick)
	add_child(tick_timer)
	update_menu_button_text()
	apply_theme()
	create_startup_menu()

	# Focus Mode and Zoom Controls (Issue #19)
	var focus_mode_btn := CheckButton.new()
	focus_mode_btn.text = "Focus Mode"
	focus_mode_btn.button_pressed = settings.get('focus_mode', false)
	focus_mode_btn.toggled.connect(func(val): 
		settings['focus_mode'] = val
		save_settings()
		if tick_timer:
			tick_timer.wait_time = tick_seconds_for_setting()
	)
	settings_panel.get_node("SettingsMargin/SettingsBox").add_child(focus_mode_btn)
	
	var zoom_label := Label.new()
	zoom_label.text = "Zoom: " + str(round(settings.get('zoom_factor', 1.0) * 100) / 100.0)
	settings_panel.get_node("SettingsMargin/SettingsBox").add_child(zoom_label)
	
	var zoom_slider := HSlider.new()
	zoom_slider.min_value = 0.5
	zoom_slider.max_value = 2.0
	zoom_slider.step = 0.1
	zoom_slider.value = settings.get('zoom_factor', 1.0)
	zoom_slider.value_changed.connect(func(val): 
		settings['zoom_factor'] = val
		save_settings()
		zoom_label.text = "Zoom: " + str(round(val * 100) / 100.0)
		if tick_timer:
			tick_timer.wait_time = tick_seconds_for_setting()
	)
	settings_panel.get_node("SettingsMargin/SettingsBox").add_child(zoom_slider)
	position_startup_panel()
	show_startup_menu()

func create_startup_menu() -> void:
	startup_panel = PanelContainer.new()
	startup_panel.top_level = true
	startup_panel.custom_minimum_size = Vector2(380, 300)
	startup_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.08, 0.1, 0.14, 0.96), Color(0.44, 0.58, 0.72, 0.95), 16))
	backdrop.add_child(startup_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	startup_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Windowstead"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Choose how this colony lives on your desktop. The dock style is locked for the save."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.72)
	box.add_child(hint)

	startup_selected_anchor = String(settings.get("dock_anchor", "bottom"))
	var anchor_row := HBoxContainer.new()
	anchor_row.add_theme_constant_override("separation", 8)
	box.add_child(anchor_row)
	startup_anchor_buttons.clear()
	for option in [
		{"label": "Bottom", "anchor": "bottom"},
		{"label": "Left", "anchor": "left"},
		{"label": "Right", "anchor": "right"},
	]:
		var anchor := String(option.anchor)
		var button := Button.new()
		button.text = String(option.label)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void:
			select_startup_anchor(anchor)
		)
		startup_anchor_buttons[anchor] = button
		anchor_row.add_child(button)
	select_startup_anchor(startup_selected_anchor)

	var new_button := Button.new()
	new_button.text = "New Game"
	new_button.pressed.connect(_on_startup_new_game)
	box.add_child(new_button)

	var load_button := Button.new()
	load_button.text = "Load Game"
	load_button.pressed.connect(_on_startup_load_game)
	box.add_child(load_button)

	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(func() -> void:
		hide_startup_menu()
		open_settings()
	)
	box.add_child(settings_button)

	var exit_button := Button.new()
	exit_button.text = "Exit"
	exit_button.pressed.connect(exit_game)
	box.add_child(exit_button)

func show_startup_menu() -> void:
	if startup_panel:
		position_startup_panel()
		startup_panel.visible = true

func hide_startup_menu() -> void:
	if startup_panel:
		startup_panel.visible = false
		apply_dock_position()

func position_startup_panel() -> void:
	if not startup_panel:
		return
	var backdrop_size: Vector2 = backdrop.size
	var panel_size := startup_panel.custom_minimum_size
	startup_panel.position = Vector2(
		max(16.0, (backdrop_size.x - panel_size.x) * 0.5),
		max(16.0, (backdrop_size.y - 280.0) * 0.5)
	)

func _on_startup_new_game() -> void:
	var chosen_anchor := startup_selected_anchor
	settings["dock_anchor"] = chosen_anchor
	sync_dock_option(chosen_anchor)
	save_settings()
	apply_dock_position()
	build_world()
	bootstrap_state()
	game_active = true
	hide_startup_menu()
	render_all()

func select_startup_anchor(anchor: String) -> void:
	if not ["bottom", "left", "right"].has(anchor):
		anchor = "bottom"
	startup_selected_anchor = anchor
	for key in startup_anchor_buttons.keys():
		var button: Button = startup_anchor_buttons[key]
		button.button_pressed = String(key) == startup_selected_anchor

func _on_startup_load_game() -> void:
	load_saved_game()
	if game_active:
		hide_startup_menu()

func open_startup_menu() -> void:
	close_menu()
	game_active = false
	show_startup_menu()
	apply_dock_position()
func configure_window() -> void:
	keep_window_pinned()
	apply_dock_position()

func apply_dock_position() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var dock_anchor := String(settings.get("dock_anchor", "bottom"))
	apply_anchor_geometry(dock_anchor)
	update_tile_metrics(dock_anchor, usable_rect)
	apply_anchor_layout(dock_anchor)
	var dock_size := dock_size_for_anchor(dock_anchor)
	DisplayServer.window_set_min_size(dock_size)
	DisplayServer.window_set_size(dock_size)
	DisplayServer.window_set_position(dock_position_for_anchor(usable_rect, dock_size, dock_anchor))
	_last_usable_rect = usable_rect

func update_tile_metrics(dock_anchor: String, usable_rect: Rect2i) -> void:
	tile_size = tile_size_for_anchor(dock_anchor, usable_rect)

func tile_px_for_anchor(dock_anchor: String, usable_rect: Rect2i) -> int:
	var family := LayoutMath.anchor_family_from_dock_anchor(dock_anchor)
	return LayoutMath.tile_px_for_work_area(family, usable_rect.size.x, usable_rect.size.y, float(settings.get("zoom_factor", 1.0)))

func tile_size_for_anchor(dock_anchor: String, usable_rect: Rect2i) -> Vector2i:
	var family := LayoutMath.anchor_family_from_dock_anchor(dock_anchor)
	return LayoutMath.tile_size_for_work_area(family, usable_rect.size.x, usable_rect.size.y, float(settings.get("zoom_factor", 1.0)))

func world_pixel_size() -> Vector2i:
	return LayoutMath.world_pixel_size_for_tile_size(grid_w, grid_h, tile_size)

func dock_padding_for_anchor(dock_anchor: String) -> Vector2i:
	return LayoutMath.dock_padding_for_anchor(anchor_family)

func apply_anchor_geometry(dock_anchor: String) -> void:
	var family := LayoutMath.anchor_family_from_dock_anchor(dock_anchor)
	anchor_family = family
	var dims := LayoutMath.grid_dims_for_anchor(family)
	grid_w = dims["grid_w"]
	grid_h = dims["grid_h"]
	stockpile_pos = LayoutMath.stockpile_pos_for_anchor(family)

func ensure_side_header() -> void:
	if side_header_row:
		return
	side_header_row = HBoxContainer.new()
	side_header_row.name = "SideHeaderRow"
	side_header_row.add_theme_constant_override("separation", 14)
	side_header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_button_row = HBoxContainer.new()
	side_button_row.name = "SideButtonRow"
	side_button_row.add_theme_constant_override("separation", 8)
	side_status_column = VBoxContainer.new()
	side_status_column.name = "SideStatusColumn"
	side_status_column.add_theme_constant_override("separation", 6)
	side_status_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_header_row.add_child(side_button_row)
	side_header_row.add_child(side_status_column)
	left_column.add_child(side_header_row)

func ensure_bottom_header() -> void:
	if bottom_header_row:
		return
	bottom_header_row = HBoxContainer.new()
	bottom_header_row.name = "BottomHeaderRow"
	bottom_header_row.add_theme_constant_override("separation", 14)
	bottom_header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_status_column = VBoxContainer.new()
	bottom_status_column.name = "BottomStatusColumn"
	bottom_status_column.add_theme_constant_override("separation", 4)
	bottom_status_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_button_row = HBoxContainer.new()
	bottom_button_row.name = "BottomButtonRow"
	bottom_button_row.alignment = BoxContainer.ALIGNMENT_END
	bottom_button_row.add_theme_constant_override("separation", 8)
	bottom_status_column.add_child(bottom_button_row)
	bottom_header_row.add_child(bottom_status_column)
	left_column.add_child(bottom_header_row)

func apply_anchor_layout(dock_anchor: String) -> void:
	var is_bottom := anchor_family == "bottom"
	var world_size: Vector2i = world_pixel_size()
	root_box.vertical = true
	left_column.alignment = BoxContainer.ALIGNMENT_CENTER
	left_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	world_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	world_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	world_panel.custom_minimum_size = Vector2(world_size.x + LayoutMath.WORLD_PANEL_PADDING.x, world_size.y + LayoutMath.WORLD_PANEL_PADDING.y)
	world_panel.size = world_panel.custom_minimum_size
	sidebar_scroll.custom_minimum_size = Vector2(320, 340) if is_bottom else Vector2(280, 300)
	world_grid.custom_minimum_size = Vector2(world_size.x, world_size.y)
	world_grid.size = Vector2(world_size.x, world_size.y)
	if world_grid:
		world_grid.columns = grid_w
	var hud_row := menu_button.get_parent() as HBoxContainer
	if hud_row:
		hud_row.alignment = BoxContainer.ALIGNMENT_END if is_bottom else BoxContainer.ALIGNMENT_BEGIN
		if is_bottom:
			if side_header_row:
				side_header_row.visible = false
			ensure_bottom_header()
			bottom_header_row.visible = true
			if bottom_header_row.get_parent() != left_column:
				bottom_header_row.get_parent().remove_child(bottom_header_row)
				left_column.add_child(bottom_header_row)
			if resource_label.get_parent() != bottom_header_row:
				resource_label.get_parent().remove_child(resource_label)
				bottom_header_row.add_child(resource_label)
			if bottom_status_column.get_parent() != bottom_header_row:
				bottom_status_column.get_parent().remove_child(bottom_status_column)
				bottom_header_row.add_child(bottom_status_column)
			if hud_row.get_parent() != bottom_button_row:
				hud_row.get_parent().remove_child(hud_row)
				bottom_button_row.add_child(hud_row)
			if status_label.get_parent() != bottom_status_column:
				status_label.get_parent().remove_child(status_label)
				bottom_status_column.add_child(status_label)
			status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			status_label.clip_text = false
			status_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			resource_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			menu_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
			left_column.move_child(bottom_header_row, 0)
			bottom_header_row.move_child(resource_label, 0)
			bottom_header_row.move_child(bottom_status_column, 1)
			bottom_status_column.move_child(bottom_button_row, 0)
			bottom_status_column.move_child(status_label, 1)
			hud_row.move_child(menu_button, 0)
			hud_row.move_child(build_mode_button, 1)
			hud_row.move_child(menu_hint, 2)
		else:
			if bottom_header_row:
				bottom_header_row.visible = false
			ensure_side_header()
			side_header_row.visible = true
			if side_header_row.get_parent() != left_column:
				side_header_row.get_parent().remove_child(side_header_row)
				left_column.add_child(side_header_row)
			if resource_label.get_parent() != side_header_row:
				resource_label.get_parent().remove_child(resource_label)
				side_header_row.add_child(resource_label)
			if side_status_column.get_parent() != side_header_row:
				side_status_column.get_parent().remove_child(side_status_column)
				side_header_row.add_child(side_status_column)
			if side_button_row.get_parent() != side_header_row:
				side_button_row.get_parent().remove_child(side_button_row)
				side_header_row.add_child(side_button_row)
			if hud_row.get_parent() != side_button_row:
				hud_row.get_parent().remove_child(hud_row)
				side_button_row.add_child(hud_row)
			if status_label.get_parent() != side_status_column:
				status_label.get_parent().remove_child(status_label)
				side_status_column.add_child(status_label)
			left_column.move_child(side_header_row, 0)
			side_header_row.move_child(resource_label, 0)
			side_header_row.move_child(side_button_row, 1)
			side_header_row.move_child(side_status_column, 2)
			side_status_column.move_child(status_label, 0)
			status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status_label.clip_text = false
			status_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			resource_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			menu_hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			hud_row.move_child(menu_button, 0)
			hud_row.move_child(build_mode_button, 1)
			hud_row.move_child(menu_hint, 2)
	# HUD label tuning for bottom mode (issue #21)
	if status_label:
		status_label.add_theme_font_size_override("font_size", 14 if is_bottom else 14)
	if menu_hint:
		menu_hint.add_theme_font_size_override("font_size", 13 if is_bottom else 13)
	position_popup_panel(dock_anchor)
func position_popup_panel(dock_anchor: String) -> void:
	var backdrop_size: Vector2 = get_node("Backdrop").size
	var popup_size: Vector2 = sidebar_scroll.custom_minimum_size
	var popup_pos := LayoutMath.popup_position_for_anchor(dock_anchor, backdrop_size.x, backdrop_size.y, popup_size.x, popup_size.y)
	sidebar_scroll.position = popup_pos
	sidebar_scroll.size = popup_size

func dock_size_for_anchor(dock_anchor: String) -> Vector2i:
	var size := LayoutMath.dock_size_for_anchor_tile_size(anchor_family, grid_w, grid_h, tile_size, sidebar_scroll.visible)
	if startup_panel and startup_panel.visible:
		size.x = maxi(size.x, int(startup_panel.custom_minimum_size.x) + 64)
		size.y = maxi(size.y, 460)
	return size

func dock_position_for_anchor(usable_rect: Rect2i, dock_size: Vector2i, dock_anchor: String) -> Vector2i:
	return LayoutMath.dock_position_for_anchor(
		usable_rect.position.x, usable_rect.position.y,
		usable_rect.size.x, usable_rect.size.y,
		dock_size, dock_anchor
	)

func keep_window_pinned() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)

func build_world() -> void:
	for child in world_grid.get_children():
		child.queue_free()
	tile_views.clear()
	for i in grid_w * grid_h:
		var tile_index := i
		var tile_panel := Panel.new()
		tile_panel.custom_minimum_size = tile_size
		tile_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		tile_panel.clip_children = 0

		var tp_style := StyleBoxFlat.new()
		tp_style.bg_color = Color(0.14, 0.17, 0.21, 0.9)
		tp_style.border_width_left = 1
		tp_style.border_width_top = 1
		tp_style.border_width_right = 1
		tp_style.border_width_bottom = 1
		tp_style.border_color = Color(0.25, 0.28, 0.34, 0.6)
		tp_style.corner_radius_top_left = 6
		tp_style.corner_radius_top_right = 6
		tp_style.corner_radius_bottom_right = 6
		tp_style.corner_radius_bottom_left = 6
		tile_panel.add_theme_stylebox_override("panel", tp_style)
		world_grid.add_child(tile_panel)
		tile_panel.mouse_entered.connect(func() -> void:
			hover_tile_index = tile_index
			render_world()
		)
		tile_panel.mouse_exited.connect(func() -> void:
			if hover_tile_index == tile_index:
				hover_tile_index = -1
				render_world()
		)
		tile_panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				handle_tile_click(tile_index)
			elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				cancel_build_placement()
		)

		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 0
		box.offset_top = 0
		box.offset_right = 0
		box.offset_bottom = 0
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 0 if anchor_family == "bottom" else 2)
		tile_panel.add_child(box)

		var icon_label := Label.new()
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", int(tile_size.y * 0.82))
		box.add_child(icon_label)

		var amount_label := Label.new()
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.add_theme_font_size_override("font_size", 10 if anchor_family == "bottom" else 12)
		amount_label.modulate = Color(1, 1, 1, 0.72)
		box.add_child(amount_label)

		var progress_label := Label.new()
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_label.add_theme_font_size_override("font_size", 10 if anchor_family == "bottom" else 11)
		progress_label.modulate = Color(1, 1, 1, 0.58)
		progress_label.visible = anchor_family != "bottom"
		box.add_child(progress_label)

		tile_views.append({
			"panel": tile_panel,
			"icon": icon_label,
			"amount": amount_label,
			"progress": progress_label,
		})

func wire_controls() -> void:
	for row in %BuildButtons.get_children():
		if row is Button:
			var kind := String(row.get_meta("kind"))
			row.pressed.connect(func() -> void: begin_build_placement(kind))
			row.mouse_entered.connect(func() -> void: update_build_preview(kind))
			row.focus_entered.connect(func() -> void: update_build_preview(kind))
	%SaveButton.pressed.connect(save_game)
	%ResetButton.pressed.connect(start_new_game)
	menu_button.pressed.connect(toggle_menu)
	%MenuButton.pressed.connect(close_menu)
	build_mode_button.pressed.connect(open_build_popup)
	%NewGameButton.pressed.connect(start_new_game)
	%SaveGameButton.pressed.connect(save_game)
	%LoadGameButton.pressed.connect(load_saved_game)
	%SettingsButton.pressed.connect(open_settings)
	%ExitButton.pressed.connect(exit_game)
	dock_side_option.item_selected.connect(_on_dock_side_selected)
	%GatherUpButton.pressed.connect(func() -> void: move_priority("gather", -1))
	%GatherDownButton.pressed.connect(func() -> void: move_priority("gather", 1))
	%HaulUpButton.pressed.connect(func() -> void: move_priority("haul", -1))
	%HaulDownButton.pressed.connect(func() -> void: move_priority("haul", 1))
	%BuildUpButton.pressed.connect(func() -> void: move_priority("build", -1))
	%BuildDownButton.pressed.connect(func() -> void: move_priority("build", 1))
	tick_speed_slider.value_changed.connect(_on_tick_speed_changed)
	%SettingsCloseButton.pressed.connect(close_settings)
	%RecruitButton.pressed.connect(_on_recruit_worker_pressed)

func load_or_boot() -> void:
	var loaded := GameState.load_game()
	if not loaded.is_empty():
		apply_loaded_dock_anchor(loaded)
	if loaded.is_empty() or not is_save_compatible(loaded):
		bootstrap_state()
	else:
		state = loaded
		tick = int(state.get("tick", 0))
		for worker in state.get("workers", []):
			if not worker.has("break_ticks"):
				worker.break_ticks = 0
		apply_priority_order()
	apply_orientation_lock_ui()

func apply_loaded_dock_anchor(loaded: Dictionary) -> void:
	var loaded_anchor := String(loaded.get("dock_anchor", settings.get("dock_anchor", "bottom")))
	loaded["dock_anchor"] = loaded_anchor
	settings["dock_anchor"] = loaded_anchor
	sync_dock_option(loaded_anchor)
	save_settings()
	apply_dock_position()
	build_world()

func bootstrap_state() -> void:
	state = {
		"tick": 0,
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"priority_order": ["build", "haul", "gather"],
		"colony_stance": ColonyStance.STANCE_BALANCED,
		"dock_anchor": String(settings.get("dock_anchor", "bottom")),
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [
			{"tick": 0, "text": "Windowstead wakes up. The tiny crew gets moving."},
			{"tick": 0, "text": "Start with a hut, unlock a workshop, then a garden for steady snacks."},
		],
	}
	for i in WORKER_NAMES.size():
		state.workers.append({
			"name": WORKER_NAMES[i],
			"pos": vec_to_data(stockpile_pos + Vector2i(i, 1)),
			"prev_pos": vec_to_data(stockpile_pos + Vector2i(i, 1)),
			"carrying": {},
			"task": {},
			"break_ticks": 0,
		})
	for y in grid_h:
		for x in grid_w:
			state.tiles.append(seed_tile(Vector2i(x, y)))
	set_tile(stockpile_pos, {"kind": "stockpile", "amount": 0, "resource": "", "build_kind": ""})
	tick = 0
	apply_priority_order()
	# Initialize active goal
	active_goal = RotatingGoal.select_next_active_goal(completed_goal_ids)
	completed_goal_ids = []
	persist()
	apply_orientation_lock_ui()

func load_settings() -> void:
	settings = {
		"dock_anchor": "bottom",
		"tick_speed": 0,
	}
	settings.merge(GameState.load_settings(), true)
	dock_side_option.clear()
	dock_side_option.add_item("Right")
	dock_side_option.add_item("Left")
	dock_side_option.add_item("Bottom")
	sync_dock_option(String(settings.get("dock_anchor", "bottom")))
	tick_speed_slider.value = float(settings.get("tick_speed", 0))
	update_tick_speed_label()

func sync_dock_option(dock_anchor: String) -> void:
	match dock_anchor:
		"left":
			dock_side_option.select(1)
		"bottom":
			dock_side_option.select(2)
		_:
			dock_side_option.select(0)

func apply_orientation_lock_ui() -> void:
	dock_side_option.disabled = true
	dock_side_option.tooltip_text = "Dock style is chosen when starting a colony and locked for that save."

func save_settings() -> void:
	settings["dock_anchor"] = dock_anchor_from_option(dock_side_option.selected)
	settings["tick_speed"] = int(tick_speed_slider.value)
	GameState.save_settings(settings)

func dock_anchor_from_option(index: int) -> String:
	match index:
		1:
			return "left"
		2:
			return "bottom"
		_:
			return "right"

func toggle_menu() -> void:
	var is_open := not sidebar_scroll.visible
	sidebar_scroll.visible = is_open
	menu_actions.visible = is_open
	management_panels.visible = false
	settings_panel.visible = false
	apply_dock_position()
	position_popup_panel(String(settings.get("dock_anchor", "bottom")))
	if is_open:
		render_all()
	else:
		close_menu()
	update_menu_button_text()

func close_menu() -> void:
	sidebar_scroll.visible = false
	menu_actions.visible = false
	management_panels.visible = false
	settings_panel.visible = false
	if not pending_build_kind.is_empty():
		world_label.text = 'Colony  •  click ground for %s' % cap(pending_build_kind)
	else:
		world_label.text = 'Colony'
	render_all()

func open_build_popup() -> void:
	if not pending_build_kind.is_empty():
		cancel_build_placement()
		return
	sidebar_scroll.visible = true
	menu_actions.visible = false
	management_panels.visible = true
	apply_dock_position()
	position_popup_panel(String(settings.get("dock_anchor", "bottom")))
	for child in management_panels.get_children():
		child.visible = child != settings_panel
	settings_panel.visible = false
	update_build_preview(first_visible_build_kind())
	update_menu_button_text()

func open_settings() -> void:
	sidebar_scroll.visible = true
	menu_actions.visible = false
	management_panels.visible = true
	apply_dock_position()
	position_popup_panel(String(settings.get("dock_anchor", "bottom")))
	for child in management_panels.get_children():
		child.visible = child == settings_panel
	settings_panel.visible = true
	update_menu_button_text()

func close_settings() -> void:
	settings_panel.visible = false
	management_panels.visible = false
	menu_actions.visible = sidebar_scroll.visible
	update_menu_button_text()

func start_new_game() -> void:
	open_startup_menu()

func save_game() -> void:
	persist()
	push_event("Game saved. Tiny bureaucracy, handled.")
	menu_actions.visible = false
	sidebar_scroll.visible = false
	management_panels.visible = false
	close_settings()
	update_menu_button_text()
	render_sidebar()

func load_saved_game() -> void:
	var loaded := GameState.load_game()
	if loaded.is_empty():
		if state.has("events"):
			push_event("No compatible save found. The colony keeps improvising.")
		menu_actions.visible = false
		close_settings()
		if game_active:
			render_sidebar()
		return
	apply_loaded_dock_anchor(loaded)
	if not is_save_compatible(loaded):
		if state.has("events"):
			push_event("Save incompatible with current layout. Colony keeps improvising.")
		menu_actions.visible = false
		close_settings()
		if game_active:
			render_sidebar()
		return
	state = loaded
	game_active = true
	tick = int(state.get("tick", 0))
	for worker in state.get("workers", []):
		if not worker.has("break_ticks"):
			worker.break_ticks = 0
	colony_stance = String(state.get("colony_stance", ColonyStance.STANCE_BALANCED))
	apply_priority_order()
	apply_orientation_lock_ui()
	push_event("Save loaded. Tiny lives resume their routines.")
	menu_actions.visible = false
	sidebar_scroll.visible = false
	management_panels.visible = false
	close_settings()
	update_menu_button_text()
	render_all()

func exit_game() -> void:
	get_tree().quit()

func _on_tick_speed_changed(value: float) -> void:
	settings["tick_speed"] = int(value)
	update_tick_speed_label()
	if tick_timer:
		tick_timer.wait_time = tick_seconds_for_setting()
	save_settings()

func _unhandled_input(event: InputEvent) -> void:
	if pending_build_kind.is_empty():
		return
	if event.is_action_pressed("ui_cancel"):
		cancel_build_placement()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		drag_start_pos = DisplayServer.window_get_position()

func _on_dock_side_selected(index: int) -> void:
	if not state.is_empty():
		sync_dock_option(String(settings.get("dock_anchor", "bottom")))
		push_event("Dock style is locked for this colony. Start a new game to choose a different style.")
		render_sidebar()
		return
	var previous_family := anchor_family
	var menu_was_open := sidebar_scroll.visible
	var menu_actions_was_visible := menu_actions.visible
	var management_was_visible := management_panels.visible
	var settings_was_visible := settings_panel.visible
	settings["dock_anchor"] = dock_anchor_from_option(index)
	save_settings()
	apply_dock_position()
	if previous_family != anchor_family:
		build_world()
		bootstrap_state()
		push_event("Dock orientation changed. The colony replanned itself for the new strip.")
		render_all()
	sidebar_scroll.visible = menu_was_open
	if menu_was_open:
		menu_actions.visible = menu_actions_was_visible
		management_panels.visible = management_was_visible
		for child in management_panels.get_children():
			if settings_was_visible:
				child.visible = child == settings_panel
			else:
				child.visible = child != settings_panel
		settings_panel.visible = settings_was_visible
		position_popup_panel(settings["dock_anchor"])
	update_menu_button_text()

func update_tick_speed_label() -> void:
	match int(tick_speed_slider.value):
		0:
			tick_speed_value.text = "Slow"
		1:
			tick_speed_value.text = "Normal"
		2:
			tick_speed_value.text = "Fast"

func update_menu_button_text() -> void:
	if sidebar_scroll.visible:
		menu_button.text = "Menu"
		menu_hint.text = "Planning" if pending_build_kind.is_empty() else "Place %s" % cap(pending_build_kind)
	else:
		menu_button.text = "Menu"
		menu_hint.text = "%d workers active" % active_worker_count()
	build_mode_button.text = "Cancel Build" if not pending_build_kind.is_empty() else "Build"

func active_worker_count() -> int:
	if not state.has("workers"):
		return 0
	var active := 0
	for worker in state.workers:
		if int(worker.get("break_ticks", 0)) <= 0:
			active += 1
	return active


# ── Food upkeep helpers (issue #147, links to #133) ──────────────────────────

func get_extra_workers_count() -> int:
	"""Return number of workers above BASE_WORKERS_NO_UPKEEP."""
	if not state.has("workers"):
		return 0
	var total: int = state.workers.size()
	var extra: int = total - Constants.BASE_WORKERS_NO_UPKEEP
	return maxi(extra, 0)


func apply_food_upkeep() -> void:
	"""Deduct food for extra workers. Soft model — never negative."""
	if not state.has("workers"):
		return
	var extra := get_extra_workers_count()
	if extra <= 0:
		return
	var food_cost := extra * Constants.FOOD_PER_EXTRA_WORKER
	var current_food := int(state.resources.get("food", 0))
	var new_food := maxi(current_food - food_cost, 0)
	if new_food < current_food:
		state.resources["food"] = new_food
		push_event("The crew ate. Food -%d." % (current_food - new_food))


func get_food_slowdown_factor() -> float:
	"""Return speed multiplier based on current food level."""
	var food := int(state.resources.get("food", 0))
	if food <= Constants.STARVATION_FOOD_THRESHOLD:
		return Constants.STARVATION_SPEED_FACTOR
	if food <= Constants.LOW_FOOD_THRESHOLD:
		# Linear interpolation between starvation and low-food threshold
		var range_size = float(Constants.LOW_FOOD_THRESHOLD - Constants.STARVATION_FOOD_THRESHOLD)
		if range_size == 0:
			return Constants.LOW_FOOD_SPEED_FACTOR
		var progress = float(food - Constants.STARVATION_FOOD_THRESHOLD) / range_size
		return lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, progress)
	return 1.0


func get_low_food_level() -> String:
	"""Return 'starving', 'low', or 'ok' based on current food."""
	var food := int(state.resources.get("food", 0))
	if food <= Constants.STARVATION_FOOD_THRESHOLD:
		return "starving"
	if food <= Constants.LOW_FOOD_THRESHOLD:
		return "low"
	return "ok"


func should_bias_to_food_gathering() -> bool:
	"""Return true when low food should bias workers toward gathering food."""
	var level := get_low_food_level()
	return level == "low" or level == "starving"

func get_worker_cap() -> int:
	var cap := Constants.BASE_WORKER_CAP
	for build in state.get("builds", []):
		if bool(build.complete):
			var kind := String(build.kind)
			cap += int(Constants.WORKER_CAP_BONUSES.get(kind, 0))
	return cap


# ── Recruit worker decision (issue #149, links to #133, #135) ─────────────────

func can_recruit_worker() -> bool:
	"""Return true if the colony has capacity for another worker."""
	if not state.has("workers"):
		return true
	var current: int = state.workers.size()
	var cap := get_worker_cap()
	return current < cap


func recruit_worker() -> void:
	"""Add a new worker to the colony. No cost — just a decision point."""
	var cap := get_worker_cap()
	var current: int = state.workers.size()
	if current >= cap:
		push_event("Not enough housing for another worker. Build more huts.")
		return

	# Pick the next available name from WORKER_NAMES (cycle through)
	var next_index: int = current % len(WORKER_NAMES)
	var new_worker := {
		"name": WORKER_NAMES[next_index],
		"task": {"kind": "", "data": {}},
		"carrying": {},
		"break_ticks": 0,
		"spawn_tick": tick,
	}
	state["workers"].append(new_worker)

	# Update food info text for the new worker count
	var extra := get_extra_workers_count()
	if extra > 0:
		var food_cost := extra * Constants.FOOD_PER_EXTRA_WORKER
		push_event("New crew member %s joins! Food impact: +%d per cycle." % [new_worker.name, food_cost])
	else:
		push_event("New crew member %s joins the tiny colony." % new_worker.name)

	persist()


func _on_recruit_worker_pressed() -> void:
	"""Handle recruit button press — check cap, show food tradeoff, warn when unsafe."""
	if can_recruit_worker():
		recruit_worker()
	else:
		var current: int = state.workers.size()
		var cap := get_worker_cap()
		push_event("Colony at capacity (%d/%d). Build more huts to recruit." % [current, cap])


@onready var stance_buttons: Dictionary = {}
var stance_panel: PanelContainer = null

func render_stance_toggle() -> void:
	# Find or create stance panel in sidebar under menu_actions
	if not is_instance_valid(menu_actions):
		return
	
	# Remove existing stance panel if present
	if stance_panel and stance_panel.get_parent():
		stance_panel.get_parent().remove_child(stance_panel)
		stance_panel.queue_free()
		stance_panel = null
	
	stance_panel = PanelContainer.new()
	stance_panel.name = "StancePanel"
	stance_panel.add_theme_stylebox_override("panel", make_panel_style(Color(0.11, 0.14, 0.18, 0.92), Color(0.28, 0.34, 0.41, 0.75), 12))
	stance_panel.add_theme_constant_override("margin_left", 14)
	stance_panel.add_theme_constant_override("margin_top", 14)
	stance_panel.add_theme_constant_override("margin_right", 14)
	stance_panel.add_theme_constant_override("margin_bottom", 14)
	
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	stance_panel.add_child(box)
	
	var title := Label.new()
	title.text = "Colony Stance"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.93, 0.95, 1.0, 0.96))
	box.add_child(title)
	
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	box.add_child(btn_row)
	
	var button_normal := make_panel_style(Color(0.18, 0.23, 0.3, 0.96), Color(0.36, 0.45, 0.55, 0.9), 10)
	var button_hover := make_panel_style(Color(0.23, 0.3, 0.39, 1.0), Color(0.49, 0.64, 0.78, 1.0), 10)
	var button_pressed := make_panel_style(Color(0.13, 0.18, 0.24, 1.0), Color(0.42, 0.58, 0.71, 0.95), 10)
	
	stance_buttons.clear()
	for stance_key in ColonyStance.ALL_STANCES:
		var info: Dictionary = ColonyStance.STANCE_INFO[stance_key]
		var btn := Button.new()
		btn.text = info.label
		btn.toggle_mode = true
		btn.button_pressed = (colony_stance == stance_key)
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_stylebox_override("normal", button_normal.duplicate())
		btn.add_theme_stylebox_override("hover", button_hover.duplicate())
		btn.add_theme_stylebox_override("pressed", button_pressed.duplicate())
		btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 0.98))
		btn.tooltip_text = info.description
		btn.pressed.connect(func(s = stance_key):
			change_stance(s)
		)
		stance_buttons[stance_key] = btn
		btn_row.add_child(btn)
	
	# Add description label
	var desc_label := Label.new()
	desc_label.name = "StanceDescription"
	desc_label.text = ColonyStance.STANCE_INFO[colony_stance].description
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.86, 0.9, 0.95, 0.84))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc_label)
	
	menu_actions.add_child(stance_panel)


func change_stance(new_stance: String) -> void:
	if not ColonyStance.ALL_STANCES.has(new_stance):
		return
	if new_stance == colony_stance:
		return
	colony_stance = new_stance
	var new_label: String = ColonyStance.STANCE_INFO[new_stance].label
	push_event("Colony stance changed to %s. Workers adjust priorities." % new_label)
	render_all()


func render_crew_panel() -> void:
	"""Update the crew panel with current cap, food impact, and recruit button state."""
	if not is_instance_valid(crew_cap_info):
		return

	var current: int = state.workers.size() if state.has("workers") else 0
	var cap := get_worker_cap()
	var extra := get_extra_workers_count()

	# Cap info: show current / cap
	crew_cap_info.text = "%d / %d workers" % [current, cap]

	# Food impact text
	if extra <= 0:
		crew_food_info.text = "Food impact: none"
		crew_food_info.modulate = Color(1, 1, 1, 0.6)
	else:
		var food_cost := extra * Constants.FOOD_PER_EXTRA_WORKER
		crew_food_info.text = "Food impact: +%d per cycle" % food_cost
		# Color-code based on food level
		var food_level := get_low_food_level()
		if food_level == "starving":
			crew_food_info.modulate = Color(1, 0.4, 0.3)
		elif food_level == "low":
			crew_food_info.modulate = Color(1, 0.75, 0.3)
		else:
			crew_food_info.modulate = Color(1, 1, 1, 0.6)

	# Recruit button state
	if can_recruit_worker():
		recruit_button.disabled = false
		recruit_button.text = "Recruit Worker"
	else:
		recruit_button.disabled = true
		recruit_button.text = "At Cap (%d/%d)" % [current, cap]

	# Warning when food is low and trying to recruit
	if crew_warning:
		var food_level := get_low_food_level()
		if food_level == "starving":
			crew_warning.text = "Warning: colony is starving! New workers will worsen this."
			crew_warning.visible = true
		elif food_level == "low" and extra > 0:
			crew_warning.text = "Warning: low food. Adding a worker increases pressure."
			crew_warning.visible = true
		else:
			crew_warning.visible = false

func apply_priority_order() -> void:
	var loaded_order: Array = state.get("priority_order", ["build", "haul", "gather"])
	priority_order.clear()
	for kind in loaded_order:
		var kind_name := String(kind)
		if ["build", "haul", "gather"].has(kind_name) and not priority_order.has(kind_name):
			priority_order.append(kind_name)
	for fallback in ["build", "haul", "gather"]:
		if not priority_order.has(fallback):
			priority_order.append(fallback)
	render_priority_controls()

func render_priority_controls() -> void:
	var labels := {
		"gather": gather_rank,
		"haul": haul_rank,
		"build": build_rank,
	}
	for kind in labels.keys():
		labels[kind].text = str(priority_order.find(kind) + 1)
	%GatherUpButton.disabled = priority_order.find("gather") == 0
	%HaulUpButton.disabled = priority_order.find("haul") == 0
	%BuildUpButton.disabled = priority_order.find("build") == 0
	%GatherDownButton.disabled = priority_order.find("gather") == priority_order.size() - 1
	%HaulDownButton.disabled = priority_order.find("haul") == priority_order.size() - 1
	%BuildDownButton.disabled = priority_order.find("build") == priority_order.size() - 1

func move_priority(kind: String, direction: int) -> void:
	var index := priority_order.find(kind)
	if index == -1:
		return
	var target := clampi(index + direction, 0, priority_order.size() - 1)
	if target == index:
		return
	priority_order[index] = priority_order[target]
	priority_order[target] = kind
	state["priority_order"] = priority_order.duplicate()
	render_priority_controls()
	persist()

func _get_trend(resource_name: String) -> String:
	var current := int(state.resources.get(resource_name, 0))
	var previous := int(prev_resources.get(resource_name, -1))
	if previous < 0:
		return RESOURCE_TRENDS["stable"]
	elif current > previous:
		return RESOURCE_TRENDS["rising"]
	elif current < previous:
		return RESOURCE_TRENDS["falling"]
	else:
		return RESOURCE_TRENDS["stable"]

func stockpile_summary_text(compact: bool = false) -> String:
	var harvested: Dictionary = state.get("harvested", {})
	var wood := int(state.resources.get("wood", 0))
	var stone := int(state.resources.get("stone", 0))
	var food := int(state.resources.get("food", 0))
	var w_trend := _get_trend("wood")
	var s_trend := _get_trend("stone")
	var f_trend := _get_trend("food")
	if compact:
		return "Stored  W %d %s  S %d %s  F %d %s  •  Harvested  W %d  S %d  F %d" % [wood, w_trend, stone, s_trend, food, f_trend, int(harvested.get("wood", 0)), int(harvested.get("stone", 0)), int(harvested.get("food", 0))]
	return "Stored  W %d %s  S %d %s  F %d %s\nHarvested  W %d  S %d  F %d" % [wood, w_trend, stone, s_trend, food, f_trend, int(harvested.get("wood", 0)), int(harvested.get("stone", 0)), int(harvested.get("food", 0))]

func activity_summary_text() -> String:
	var lines := []
	for worker in state.workers:
		lines.append("%s: %s" % [String(worker.name), worker_brief(worker)])
	if lines.is_empty():
		return "Activity\nNo crew activity"
	return "Activity\n%s" % "\n".join(lines)

func worker_brief(worker: Dictionary) -> String:
	var summary := task_name(worker)
	var carrying := carrying_name(worker.get("carrying", {}))
	if carrying != "hands free":
		summary += " (%s)" % carrying
	return summary

func tick_seconds_for_setting() -> float:
	var multiplier := 1.0
	if settings.get('focus_mode', false):
		multiplier = 2.5
	match int(settings.get("tick_speed", 0)):
		0:
			return BASE_TICK_SECONDS * 1.6 * multiplier
		1:
			return BASE_TICK_SECONDS * multiplier
		2:
			return BASE_TICK_SECONDS * 0.65 * multiplier
	return BASE_TICK_SECONDS * multiplier

func seed_tile(pos: Vector2i) -> Dictionary:
	var key := int((pos.x * 13 + pos.y * 7 + pos.x * pos.y) % 14)
	if key == 0 or key == 3:
		return {"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""}
	if key == 6 or key == 8:
		return {"kind": "rock", "amount": 5, "resource": "stone", "build_kind": ""}
	if key == 11:
		return {"kind": "berries", "amount": 4, "resource": "food", "build_kind": ""}
	return {"kind": "ground", "amount": 0, "resource": "", "build_kind": ""}

func _on_tick() -> void:
	if not game_active or state.is_empty():
		return
	keep_window_pinned()
	tick += 1
	state.tick = tick
	maybe_fire_event()
	_clean_stale_reservations()

	# Food upkeep (issue #147)
	food_upkeep_tracker += 1
	if food_upkeep_tracker >= Constants.FOOD_UPKEEP_INTERVAL_TICKS:
		food_upkeep_tracker = 0
		apply_food_upkeep()

	for worker in state.workers:
		worker.prev_pos = worker.get("pos", vec_to_data(stockpile_pos))
		if int(worker.get("break_ticks", 0)) > 0:
			worker.break_ticks = int(worker.break_ticks) - 1
			if int(worker.break_ticks) <= 0:
				push_event("%s is back from a dramatic five-second break." % worker.name)
			continue
		if worker.task.is_empty():
			worker.task = choose_task(worker)
		if not worker.task.is_empty():
			step_worker(worker)

	# Check goal completion and rotate
	if not active_goal.is_empty() and RotatingGoal.is_goal_complete(active_goal):
		var new_goal = RotatingGoal.rotate_after_completion(active_goal, completed_goal_ids)
		completed_goal_ids.append(active_goal["id"])
		active_goal = new_goal
	persist()
	state.workers = state.workers
	render_all()

func _process(delta: float) -> void:
	# Edge snapping: snap window to screen edge when dragging near boundary
	# Reapply dock geometry when screen work area changes
	if _dock_recheck_timer > 0.0:
		_dock_recheck_timer -= delta
		return
	var screen_idx := DisplayServer.window_get_current_screen()
	var current_usable := DisplayServer.screen_get_usable_rect(screen_idx)
	if current_usable != _last_usable_rect:
		_last_usable_rect = current_usable
		apply_dock_position()
	_dock_recheck_timer = DOCK_RECHECK_COOLDOWN
	edge_snap_cooldown = maxf(edge_snap_cooldown - delta, 0.0)
	var current_pos := DisplayServer.window_get_position()
	var window_size := DisplayServer.window_get_size()
	var dragging := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and current_pos != drag_start_pos
	if dragging:
		if drag_start_pos == Vector2i(-9999, -9999):
			drag_start_pos = current_pos
		var screen := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var right_edge := current_pos.x + window_size.x
		var bottom_edge := current_pos.y + window_size.y
		if current_pos.x - usable.position.x <= EDGE_SNAP_THRESHOLD and edge_snap_cooldown <= 0.0:
			DisplayServer.window_set_position(Vector2i(usable.position.x, current_pos.y))
			edge_snap_cooldown = 0.15
		elif usable.position.x + usable.size.x - right_edge <= EDGE_SNAP_THRESHOLD and edge_snap_cooldown <= 0.0:
			DisplayServer.window_set_position(Vector2i(int(usable.position.x + usable.size.x - window_size.x), current_pos.y))
			edge_snap_cooldown = 0.15
		elif current_pos.y - usable.position.y <= EDGE_SNAP_THRESHOLD and edge_snap_cooldown <= 0.0:
			DisplayServer.window_set_position(Vector2i(current_pos.x, usable.position.y))
			edge_snap_cooldown = 0.15
		elif usable.position.y + usable.size.y - bottom_edge <= EDGE_SNAP_THRESHOLD and edge_snap_cooldown <= 0.0:
			DisplayServer.window_set_position(Vector2i(current_pos.x, int(usable.position.y + usable.size.y - window_size.y)))
			edge_snap_cooldown = 0.15
	render_worker_overlay()

func choose_task(worker: Dictionary) -> Dictionary:
	var effective_order := ColonyStance.get_effective_priority_order(colony_stance, priority_order)
	for kind in effective_order:
		var tasks: Array[Dictionary] = tasks_for_kind(String(kind))
		if tasks.is_empty():
			continue
		# Bias toward food gathering when food is low (issue #147)
		if String(kind) == "gather" and should_bias_to_food_gathering():
			tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_is_food := String(a.get("resource", "")) == "food"
				var b_is_food := String(b.get("resource", "")) == "food"
				if a_is_food and not b_is_food:
					return true
				if not a_is_food and b_is_food:
					return false
				return task_distance(worker, a) < task_distance(worker, b)
			)
		elif String(kind) == "gather_food":
			# Food stance: sort food gather tasks first
			tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_is_food := ColonyStance.is_food_gather_task(a)
				var b_is_food := ColonyStance.is_food_gather_task(b)
				if a_is_food and not b_is_food:
					return true
				if not a_is_food and b_is_food:
					return false
				return task_distance(worker, a) < task_distance(worker, b)
			)
		else:
			tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return task_distance(worker, a) < task_distance(worker, b)
			)
		var chosen := tasks[0]
		if (String(chosen.kind) == "gather" or String(chosen.kind) == "gather_food") and chosen.has("resource"):
			reserve_resource(String(chosen.resource))
		return chosen
	return {}

func tasks_for_kind(kind: String) -> Array[Dictionary]:
	match kind:
		"build":
			return gather_build_tasks()
		"haul":
			return gather_haul_tasks()
		"gather", "gather_food":
			return gather_gather_tasks()
	return []

func task_distance(worker: Dictionary, task: Dictionary) -> int:
	var pos := data_to_vec(worker.pos)
	var target := data_to_vec(task.target)
	return abs(pos.x - target.x) + abs(pos.y - target.y)

func gather_build_tasks() -> Array[Dictionary]:
	var tasks: Array[Dictionary] = []
	for build in state.builds:
		if not bool(build.complete) and has_costs_delivered(build):
			tasks.append({"kind": "build", "build_id": int(build.id), "target": build.pos})
	return tasks

func gather_haul_tasks() -> Array[Dictionary]:
	var tasks: Array[Dictionary] = []
	for build in state.builds:
		if bool(build.complete):
			continue
		for resource in BUILD_COSTS[String(build.kind)].keys():
			var reserved := int(build.get("reserved", {}).get(resource, 0))
			var need := int(BUILD_COSTS[String(build.kind)][resource]) - int(build.delivered.get(resource, 0)) - reserved
			if need > 0 and int(state.resources.get(resource, 0)) > 0:
				tasks.append({"kind": "haul", "build_id": int(build.id), "target": vec_to_data(stockpile_pos), "resource": resource})
	return tasks

func _clean_stale_reservations() -> void:
	# Remove reservations from builds that have no active haul tasks targeting them.
	# This handles: build completion, build deletion, worker break/cleanup.
	for build in state.builds:
		if bool(build.complete):
			continue
		var has_haul := false
		for worker in state.workers:
			if not worker.task.is_empty() and String(worker.task.kind) == "haul":
				if int(worker.task.get("build_id", -1)) == int(build.id):
					has_haul = true
					break
		if not has_haul and build.has("reserved"):
			var reserved: Dictionary = build.reserved
			for resource in reserved.keys():
				state.resources[resource] = int(state.resources.get(resource, 0)) + int(reserved[resource])
			build.erase("reserved")


func gather_gather_tasks() -> Array[Dictionary]:
	var tasks: Array[Dictionary] = []
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			if ["tree", "rock", "berries"].has(String(tile.kind)) and int(tile.amount) > 0:
				# Skip if resource is fully reserved (reserved >= available on tile)
				var resource := String(tile.resource)
				var reserved := get_reserved(resource)
				var total_available := count_total_resource(resource)
				if reserved >= total_available:
					continue
				tasks.append({"kind": "gather", "target": vec_to_data(pos), "resource": tile.resource})
	return tasks

func count_total_resource(resource: String) -> int:
	var total := 0
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			if String(tile.resource) == resource and ["tree", "rock", "berries"].has(String(tile.kind)):
				total += int(tile.amount)
	return total

func step_worker(worker: Dictionary) -> void:
	var task: Dictionary = worker.task
	if task.is_empty():
		return
	var target := data_to_vec(task.target)
	if String(task.kind) == "haul" and int(worker.carrying.get(String(task.resource), 0)) > 0:
		var build := get_build(int(task.build_id))
		if not build.is_empty():
			target = data_to_vec(build.pos)
	var current := data_to_vec(worker.pos)
	if current != target:
		worker.pos = vec_to_data(step_toward(current, target))
		return
	match String(task.kind):
		"gather": do_gather(worker, task)
		"haul": do_haul(worker, task)
		"build": do_build(worker, task)

func do_gather(worker: Dictionary, task: Dictionary) -> void:
	var target := data_to_vec(task.target)
	var tile := get_tile(target)
	if int(tile.amount) <= 0:
		worker.task = {}
		release_resource(String(task.resource))
		return
	tile.amount = int(tile.amount) - 1
	worker.carrying[String(tile.resource)] = int(worker.carrying.get(String(tile.resource), 0)) + 1
	state.harvested[String(task.resource)] = int(state.get("harvested", {}).get(String(task.resource), 0)) + 1
	if int(tile.amount) <= 0:
		tile.kind = "ground"
		tile.resource = ""
	set_tile(target, tile)
	# Release reservation — resource is now in worker's possession
	release_resource(String(task.resource))
	worker.task = {"kind": "haul", "target": vec_to_data(stockpile_pos), "resource": task.resource, "build_id": -1}

func do_haul(worker: Dictionary, task: Dictionary) -> void:
	var resource := String(task.resource)
	var carried := int(worker.carrying.get(resource, 0))
	if carried > 0:
		if int(task.build_id) >= 0:
			var build := get_build(int(task.build_id))
			if not build.is_empty() and not bool(build.complete):
				# Clamp delivery to remaining need (delivered + reserved already account for committed units)
				var reserved := int(build.get("reserved", {}).get(resource, 0))
				var cost := int(BUILD_COSTS[String(build.kind)][resource])
				var total_needed := cost - int(build.delivered.get(resource, 0)) - reserved
				var deliver := mini(carried, maxf(total_needed, 0))
				build.delivered[resource] = int(build.delivered.get(resource, 0)) + deliver
				# Refund excess back to stockpile
				var excess := carried - deliver
				if excess > 0:
					state.resources[resource] = int(state.resources.get(resource, 0)) + excess
				# Release reservation for delivered amount
				if deliver > 0:
					reserved = maxf(reserved - deliver, 0)
					build["reserved"] = build.get("reserved", {})
					build.reserved[resource] = reserved
					set_build(int(task.build_id), build)
			else:
				state.resources[resource] = int(state.resources.get(resource, 0)) + carried
		else:
			state.resources[resource] = int(state.resources.get(resource, 0)) + carried
		worker.carrying[resource] = 0
		worker.task = {}
		return
	if data_to_vec(worker.pos) == stockpile_pos and int(state.resources.get(resource, 0)) > 0 and int(task.build_id) >= 0:
		var build := get_build(int(task.build_id))
		if not build.is_empty() and not bool(build.complete):
			state.resources[resource] = int(state.resources.get(resource, 0)) - 1
			worker.carrying[resource] = 1
			# Reserve this unit for the build
			var reserved := int(build.get("reserved", {}).get(resource, 0))
			if not build.has("reserved"):
				build["reserved"] = {}
			build.reserved[resource] = reserved + 1
			set_build(int(task.build_id), build)
			worker.task.target = build.pos
		else:
			# Build gone or complete — clear task, resource stays in stockpile
			worker.task = {}
		return
	worker.task = {}

func do_build(worker: Dictionary, task: Dictionary) -> void:
	var build := get_build(int(task.build_id))
	if build.is_empty() or bool(build.complete):
		worker.task = {}
		return
	build.progress = float(build.progress) + structure_build_speed(String(build.kind))
	if float(build.progress) >= 1.0:
		build.complete = true
		set_tile(data_to_vec(build.pos), {"kind": build.kind, "amount": 0, "resource": "", "build_kind": ""})
		apply_structure_bonus(String(build.kind))
		push_event("%s finished. The colony looks slightly more legitimate." % cap(String(build.kind)))
	set_build(int(task.build_id), build)
	worker.task = {}

func begin_build_placement(kind: String) -> void:
	if not is_structure_unlocked(kind):
		push_event("%s is locked. Build the previous upgrade first." % cap(kind))
		return
	pending_build_kind = kind
	world_label.text = "Colony  •  placing %s  •  %s" % [cap(kind), build_cost_text(kind)]
	status_label.text = build_preview_text(kind)
	push_event("Placement mode: click a ground tile for %s." % cap(kind))
	sidebar_scroll.visible = false
	menu_actions.visible = false
	management_panels.visible = false
	settings_panel.visible = false
	apply_dock_position()
	update_menu_button_text()
	render_all()

func handle_tile_click(index: int) -> void:
	if pending_build_kind.is_empty():
		return
	var pos := Vector2i(index % grid_w, index / grid_w)
	place_structure_at(pos, pending_build_kind)

func place_structure_at(pos: Vector2i, kind: String) -> void:
	if String(get_tile(pos).kind) != "ground":
		push_event("That tile is busy. Pick open ground for %s." % cap(kind))
		return
	if abs(pos.x - stockpile_pos.x) + abs(pos.y - stockpile_pos.y) <= 1:
		push_event("Leave some breathing room around the stockpile.")
		return
	if not is_structure_unlocked(kind):
		push_event("%s is locked. Build the previous upgrade first." % cap(kind))
		return
	queue_structure_at(pos, kind)

func queue_structure_at(pos: Vector2i, kind: String) -> void:
	if pos == Vector2i(-1, -1):
		push_event("No room for %s. Dense urban planning strikes again." % kind)
		return
	var build := {
		"id": int(state.next_build_id),
		"kind": kind,
		"pos": vec_to_data(pos),
		"delivered": {"wood": 0, "stone": 0},
		"reserved": {"wood": 0, "stone": 0},
		"progress": 0.0,
		"complete": false,
	}
	state.next_build_id = int(state.next_build_id) + 1
	state.builds.append(build)
	set_tile(pos, {"kind": "foundation", "amount": 0, "resource": "", "build_kind": kind})
	push_event("%s queued. The workers will fake having a plan." % cap(kind))
	pending_build_kind = ""
	sidebar_scroll.visible = false
	menu_actions.visible = false
	management_panels.visible = false
	settings_panel.visible = false
	hover_tile_index = -1
	world_label.text = "Colony"
	apply_dock_position()
	update_menu_button_text()
	persist()
	render_all()

func cancel_build_placement() -> void:
	if pending_build_kind.is_empty():
		return
	var kind := pending_build_kind
	pending_build_kind = ""
	sidebar_scroll.visible = false
	menu_actions.visible = false
	management_panels.visible = false
	settings_panel.visible = false
	hover_tile_index = -1
	world_label.text = "Colony"
	if not kind.is_empty():
		world_label.text = "Colony  •  place another " + cap(kind)
	apply_dock_position()
	update_menu_button_text()
	render_all()

func maybe_fire_event() -> void:
	if tick % EVENT_INTERVAL_TICKS != 0:
		return
	var event_roll := rng.randi_range(0, 2)
	match event_roll:
		0:
			state.resources.food = int(state.resources.get("food", 0)) + 2
			push_event("A neighbor drops off trail mix. Food +2.")
		1:
			var worker: Dictionary = state.workers[rng.randi_range(0, state.workers.size() - 1)]
			worker.task = {}
			worker.break_ticks = 6
			push_event("%s takes a break and stares into the middle distance." % worker.name)
		2:
			spawn_resource_drop()

func spawn_resource_drop() -> void:
	var pos := find_open_ground()
	if pos == Vector2i(-1, -1):
		push_event("A supply crate tried to arrive but urban planning won.")
		return
	var options: Array[String] = ["tree", "rock", "berries"]
	var resource_kind: String = options[rng.randi_range(0, options.size() - 1)]
	match resource_kind:
		"tree":
			set_tile(pos, {"kind": "tree", "amount": 4, "resource": "wood", "build_kind": ""})
			push_event("A driftwood bundle lands nearby. Fresh wood appeared.")
		"rock":
			set_tile(pos, {"kind": "rock", "amount": 4, "resource": "stone", "build_kind": ""})
		"berries":
			set_tile(pos, {"kind": "berries", "amount": 3, "resource": "food", "build_kind": ""})
			push_event("A snack crate lands nearby. Fresh food appeared.")
	if resource_kind == "rock":
		push_event("A rubble drop lands nearby. Fresh stone appeared.")

func apply_structure_bonus(kind: String) -> void:
	match kind:
		"hut":
			state.resources.food = int(state.resources.get("food", 0)) + 1
		"garden":
			state.resources.food = int(state.resources.get("food", 0)) + 3

func structure_build_speed(kind: String) -> float:
	var speed := 0.34
	if kind != "workshop" and is_structure_complete("workshop"):
		speed += 0.16
	# Apply food-based slowdown (issue #147)
	speed *= get_food_slowdown_factor()
	return speed

func render_all() -> void:
	render_crew_panel()
	render_world()
	render_worker_overlay()
	render_goal()
	render_sidebar()
	render_build_buttons()
	render_stance_toggle()

func render_world() -> void:
	for y in grid_h:
		for x in grid_w:
			var index := y * grid_w + x
			var view := tile_views[index]
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			var panel: Panel = view.panel
			var icon_label: Label = view.icon
			var amount_label: Label = view.amount
			var progress_label: Label = view.progress
			panel.add_theme_stylebox_override("panel", tile_style(tile, pos))
			icon_label.text = tile_icon(tile, pos)
			amount_label.text = tile_amount_text(tile, pos)
			amount_label.visible = hover_tile_index == index
			progress_label.text = ""

func render_worker_overlay() -> void:
	if tile_views.is_empty():
		return
	for child in world_overlay.get_children():
		child.visible = false
	var collision_slots := {}
	for worker in state.get("workers", []):
		var pos_key := vec_key(data_to_vec(worker.get("pos", vec_to_data(stockpile_pos))))
		collision_slots[pos_key] = int(collision_slots.get(pos_key, 0)) + 1
	var used_slots := {}
	var progress := 1.0
	if tick_timer and tick_timer.wait_time > 0.0:
		progress = clampf(1.0 - (tick_timer.time_left / tick_timer.wait_time), 0.0, 1.0)
	for worker in state.get("workers", []):
		var name := String(worker.get("name", "worker"))
		var sprite: TextureRect
		if worker_overlay_nodes.has(name):
			sprite = worker_overlay_nodes[name]
		else:
			sprite = TextureRect.new()
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.stretch_mode = TextureRect.STRETCH_SCALE
			world_overlay.add_child(sprite)
			worker_overlay_nodes[name] = sprite
		sprite.custom_minimum_size = Vector2(int(tile_size.x * 0.96), int(tile_size.y * 1.08))
		sprite.size = sprite.custom_minimum_size
		sprite.visible = true
		sprite.texture = worker_texture(name, worker_anim_frame(worker), carried_resource(worker))
		var from_pos := data_to_vec(worker.get("prev_pos", worker.get("pos", vec_to_data(stockpile_pos))))
		var to_pos := data_to_vec(worker.get("pos", vec_to_data(stockpile_pos)))
		var from_center := tile_center(from_pos)
		var to_center := tile_center(to_pos)
		var eased := ease(progress, 0.3)
		var draw_pos := from_center.lerp(to_center, eased)
		var pos_key := vec_key(to_pos)
		var slot := int(used_slots.get(pos_key, 0))
		used_slots[pos_key] = slot + 1
		draw_pos += worker_collision_offset(slot, int(collision_slots.get(pos_key, 1)))
		sprite.position = draw_pos - sprite.custom_minimum_size * 0.5

func worker_collision_offset(slot: int, total: int) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var spacing := maxf(8.0, float(tile_size.x) * 0.18)
	var offsets := [
		Vector2(-spacing, -spacing),
		Vector2(spacing, spacing),
		Vector2(spacing, -spacing),
		Vector2(-spacing, spacing),
		Vector2(0, -spacing * 1.25),
		Vector2(0, spacing * 1.25),
	]
	return offsets[slot % offsets.size()]

func tile_center(pos: Vector2i) -> Vector2:
	var index := pos.y * grid_w + pos.x
	if index < 0 or index >= tile_views.size():
		return Vector2.ZERO
	var panel: Control = tile_views[index].panel
	return world_grid.position + panel.position + panel.size * 0.5

func hovered_tile_pos() -> Vector2i:
	if hover_tile_index < 0:
		return Vector2i(-1, -1)
	return Vector2i(hover_tile_index % grid_w, hover_tile_index / grid_w)

func can_place_at(pos: Vector2i, kind: String) -> bool:
	if kind.is_empty() or not is_pos_in_bounds(pos):
		return false
	if String(get_tile(pos).kind) != "ground":
		return false
	if abs(pos.x - stockpile_pos.x) + abs(pos.y - stockpile_pos.y) <= 1:
		return false
	return is_structure_unlocked(kind)

func structure_icon(kind: String) -> String:
	match kind:
		"hut":
			return "🏠"
		"workshop":
			return "🛠"
		"garden":
			return "🪴"
	return "🏗"

func render_goal() -> void:
	if not is_instance_valid(goal_label):
		return
	if active_goal.is_empty():
		goal_label.text = "Goal: —"
		goal_label.visible = false
		return
	goal_label.visible = true

	var goal_type := String(active_goal.get("type", ""))
	var progress := int(active_goal.get("current_progress", 0))
	var target := int(active_goal.get("target", {}).get("amount", 0))

	# Format compact goal text matching the spec examples
	var goal_text := ""
	match goal_type:
		RotatingGoal.GOAL_TYPE_RESOURCE:
			var resource := String(active_goal.get("target", {}).get("resource", ""))
			goal_text = "Goal: Reach %d %s" % [target, resource]
		RotatingGoal.GOAL_TYPE_BUILD:
			var build_kind := String(active_goal.get("target", {}).get("build_kind", ""))
			goal_text = "Goal: Build %s" % cap(build_kind)
		RotatingGoal.GOAL_TYPE_BUILD_COMPLETE:
			goal_text = "Goal: Finish a build"

	# Add progress when useful (not at 0 and not complete)
	var is_complete := RotatingGoal.is_goal_complete(active_goal)
	if target > 0 and progress > 0 and not is_complete:
		goal_text += " (%d/%d)" % [progress, target]
	elif is_complete:
		goal_text += " ✓"

	goal_label.text = goal_text


func render_sidebar() -> void:
	var compact_header := anchor_family != "bottom"
	resource_label.text = stockpile_summary_text(false)

	# Save current resources for trend comparison next tick
	prev_resources = {"wood": int(state.resources.get("wood", 0)), "stone": int(state.resources.get("stone", 0)), "food": int(state.resources.get("food", 0))}
	status_label.text = settlement_status_text(compact_header or anchor_family == "bottom")
	activity_label.text = activity_summary_text()
	world_label.text = "Colony" if pending_build_kind.is_empty() else "Colony  •  click ground for %s" % cap(pending_build_kind)
	for child in crew_list.get_children():
		child.queue_free()
	for worker in state.workers:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s  •  %s  •  %s" % [worker.name, task_name(worker), carrying_name(worker.carrying)]
		crew_list.add_child(label)
	event_log.clear()
	for entry in state.events:
		event_log.append_text("t%02d  %s\n" % [int(entry.tick), String(entry.text)])

func render_build_buttons() -> void:
	for child in %BuildButtons.get_children():
		if child is Button:
			var kind := String(child.get_meta("kind"))
			var unlocked := is_structure_unlocked(kind)
			var costs: Dictionary = BUILD_COSTS[kind]
			child.disabled = not unlocked
			child.text = "+ Place %s  •  %d wood / %d stone" % [cap(kind), int(costs.get("wood", 0)), int(costs.get("stone", 0))]
			child.tooltip_text = build_preview_text(kind)
	update_build_preview(pending_build_kind if not pending_build_kind.is_empty() else first_visible_build_kind())

func first_visible_build_kind() -> String:
	for child in %BuildButtons.get_children():
		if child is Button:
			return String(child.get_meta("kind"))
	return ""

func update_build_preview(kind: String) -> void:
	if kind.is_empty() or not is_instance_valid(build_preview_label):
		return
	build_preview_label.text = build_preview_text(kind)

func build_cost_text(kind: String) -> String:
	var costs: Dictionary = BUILD_COSTS.get(kind, {})
	var parts: Array[String] = []
	for resource in ["wood", "stone"]:
		var amount := int(costs.get(resource, 0))
		if amount > 0:
			parts.append("%d %s" % [amount, resource])
	return "free" if parts.is_empty() else " / ".join(parts)

func missing_build_resources(kind: String) -> Array[String]:
	var missing: Array[String] = []
	var costs: Dictionary = BUILD_COSTS.get(kind, {})
	for resource in ["wood", "stone"]:
		var shortage := int(costs.get(resource, 0)) - int(state.get("resources", {}).get(resource, 0))
		if shortage > 0:
			missing.append("%d %s" % [shortage, resource])
	return missing

func build_preview_text(kind: String) -> String:
	var missing := missing_build_resources(kind)
	var missing_text := "missing " + ", ".join(missing) if not missing.is_empty() else "available"
	var locked_text := ""
	if not is_structure_unlocked(kind):
		locked_text = "  •  locked until %s" % cap(String(BUILD_UNLOCKS[kind]))
	return "%s  •  cost %s  •  %s  •  %s%s" % [
		cap(kind),
		build_cost_text(kind),
		missing_text,
		String(BUILD_EFFECTS.get(kind, "Adds a colony upgrade.")),
		locked_text,
	]

func tile_icon(tile: Dictionary, pos: Vector2i) -> String:
	if not pending_build_kind.is_empty() and pos == hovered_tile_pos():
		return structure_icon(pending_build_kind) if can_place_at(pos, pending_build_kind) else "✕"
	if pos == stockpile_pos:
		return "📦"
	match String(tile.kind):
		"tree": return "🌲"
		"rock": return "🪨"
		"berries": return "🫐"
		"foundation":
			var build := get_build_at_pos(pos)
			if not build.is_empty() and has_costs_delivered(build) and tick % 2 == 0:
				return "🔨"
			return "🏗"
		"hut": return "🏠"
		"workshop": return "🛠"
		"garden": return "🪴"
		_:
			return ""

func tile_amount_text(tile: Dictionary, pos: Vector2i) -> String:
	if not pending_build_kind.is_empty() and pos == hovered_tile_pos():
		return cap(pending_build_kind).left(4) if can_place_at(pos, pending_build_kind) else "busy"
	if pos == stockpile_pos:
		return "hub"
	match String(tile.kind):
		"tree", "rock", "berries":
			return str(int(tile.amount))
		"foundation":
			return cap(String(tile.build_kind)).left(4)
		"hut":
			return "hut"
		"workshop":
			return "shop"
		"garden":
			return "grow"
		_:
			return ""

func tile_progress_text(tile: Dictionary, pos: Vector2i) -> String:
	if not pending_build_kind.is_empty() and pos == hovered_tile_pos():
		return "place" if can_place_at(pos, pending_build_kind) else "blocked"
	if String(tile.kind) != "foundation":
		var workers_here := workers_at_pos(pos)
		if not workers_here.is_empty():
			return worker_tile_status(workers_here[0])
		if String(tile.kind) == "ground":
			return ["open", "path", "wind"][(tick + pos.x * 2 + pos.y) % 3]
		return ""
	var build := get_build_at_pos(pos)
	if build.is_empty():
		return "queued"
	if not has_costs_delivered(build):
		var delivered: Dictionary = build.delivered
		return "%dw %ds" % [int(delivered.get("wood", 0)), int(delivered.get("stone", 0))]
	return "%d%%" % int(round(float(build.get("progress", 0.0)) * 100.0))

func worker_tile_status(worker: Dictionary) -> String:
	if int(worker.get("break_ticks", 0)) > 0:
		return "rest"
	var task: Dictionary = worker.get("task", {})
	if task.is_empty():
		return "idle"
	match String(task.kind):
		"gather":
			return "gather"
		"haul":
			return "haul"
		"build":
			return "build"
	return String(task.kind)

func workers_at_pos(pos: Vector2i) -> Array:
	var workers_here: Array = []
	for worker in state.workers:
		if data_to_vec(worker.pos) == pos:
			workers_here.append(worker)
	return workers_here

func render_worker_sprites(container: HBoxContainer, workers_here: Array) -> void:
	for child in container.get_children():
		child.queue_free()
	for worker in workers_here:
		var sprite := TextureRect.new()
		sprite.custom_minimum_size = Vector2(int(tile_size.x * 0.62), int(tile_size.y * 0.7))
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_SCALE
		sprite.texture = worker_texture(String(worker.name), worker_anim_frame(worker), carried_resource(worker))
		container.add_child(sprite)

func carried_resource(worker: Dictionary) -> String:
	var carrying: Dictionary = worker.get("carrying", {})
	for key in ["stone", "wood", "food"]:
		if int(carrying.get(key, 0)) > 0:
			return key
	return ""

func worker_anim_frame(worker: Dictionary) -> int:
	if int(worker.get("break_ticks", 0)) > 0:
		return 0
	var task: Dictionary = worker.get("task", {})
	if task.is_empty():
		return 0 if tick % 10 < 5 else 1
	return tick % 2

func worker_texture(name: String, frame: int, carrying: String = "") -> Texture2D:
	var cache_key := "%s:%d:%s" % [name, frame, carrying]
	if worker_texture_cache.has(cache_key):
		return worker_texture_cache[cache_key]
	var accent: Color = WORKER_BADGE_COLORS.get(name, Color.WHITE)
	var shadow := accent.darkened(0.45)
	var skin := Color("#f2d0b1")
	var image := Image.create(12, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	# head
	for y in range(0, 4):
		for x in range(4, 8):
			image.set_pixel(x, y, skin)

	# body
	for y in range(4, 10):
		for x in range(3, 9):
			image.set_pixel(x, y, accent)

	# arms
	for y in range(5, 9):
		image.set_pixel(2, y, shadow)
		image.set_pixel(9, y, shadow)

	if not carrying.is_empty():
		var cargo_color := Color("#9aa3aa")
		if carrying == "wood":
			cargo_color = Color("#8b5a2b")
		elif carrying == "food":
			cargo_color = Color("#6fbf73")
		for y in range(5, 9):
			for x in range(0, 3):
				image.set_pixel(x, y, cargo_color)
		image.set_pixel(1, 4, cargo_color.lightened(0.25))

	# legs alternate per frame for a simple walk bob
	if frame % 2 == 0:
		image.set_pixel(4, 10, shadow)
		image.set_pixel(4, 11, shadow)
		image.set_pixel(7, 10, shadow)
		image.set_pixel(7, 11, shadow)
	else:
		image.set_pixel(5, 10, shadow)
		image.set_pixel(4, 11, shadow)
		image.set_pixel(6, 10, shadow)
		image.set_pixel(7, 11, shadow)

	# feet
	image.set_pixel(3, 13, shadow)
	image.set_pixel(7, 13, shadow)

	var texture := ImageTexture.create_from_image(image)
	worker_texture_cache[cache_key] = texture
	return texture

func tile_style(tile: Dictionary, pos: Vector2i) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 4
	style.content_margin_top = 3
	style.content_margin_right = 4
	style.content_margin_bottom = 3
	var kind := "stockpile" if pos == stockpile_pos else String(tile.kind)
	style.bg_color = TILE_BACKDROPS.get(kind, Color("#1b2128"))
	style.border_color = tile_accent(tile, pos)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 2
	return style

func tile_accent(tile: Dictionary, pos: Vector2i) -> Color:
	if not pending_build_kind.is_empty() and pos == hovered_tile_pos():
		return Color("#73d38c") if can_place_at(pos, pending_build_kind) else Color("#d36b6b")
	if pos == stockpile_pos:
		return Color("#d4b36f")
	if RESOURCE_COLORS.has(String(tile.resource)):
		return RESOURCE_COLORS[String(tile.resource)]
	if STRUCTURE_COLORS.has(String(tile.kind)):
		return STRUCTURE_COLORS[String(tile.kind)]
	if String(tile.kind) == "foundation":
		return Color("#c7a25e")
	return Color(1, 1, 1, 0.35)

func task_name(worker: Dictionary) -> String:
	if int(worker.get("break_ticks", 0)) > 0:
		return "taking five"
	var task: Dictionary = worker.task
	if task.is_empty():
		return "idle"
	match String(task.kind):
		"gather":
			return "gathering %s" % String(task.get("resource", "supplies"))
		"haul":
			if int(task.get("build_id", -1)) >= 0:
				var build := get_build(int(task.build_id))
				if not build.is_empty():
					return "hauling %s to %s" % [String(task.get("resource", "goods")), String(build.kind)]
			return "returning %s" % String(task.get("resource", "goods"))
		"build":
			var build := get_build(int(task.get("build_id", -1)))
			if not build.is_empty():
				return "building %s" % String(build.kind)
			return "building"
	return String(task.kind)

func carrying_name(carrying: Dictionary) -> String:
	var parts := []
	for key in carrying.keys():
		var amount := int(carrying[key])
		if amount > 0:
			parts.append("%d %s" % [amount, key])
	return ", ".join(parts) if not parts.is_empty() else "hands free"

func settlement_status_text(compact: bool = false) -> String:
	var queued := 0
	var building := 0
	var idle := 0
	var on_break := 0
	for build in state.builds:
		if not bool(build.complete):
			queued += 1
	for worker in state.workers:
		if int(worker.get("break_ticks", 0)) > 0:
			on_break += 1
			continue
		if worker.task.is_empty():
			idle += 1
		elif String(worker.task.kind) == "build":
			building += 1
	var next_unlock := next_unlock_text()
	var status := "Tick %d  •  queued %d  •  building %d  •  idle %d  •  break %d" % [tick, queued, building, idle, on_break]
	# Bottleneck hints for queued builds (issue #27)
	if queued > 0 and building == 0:
		if idle > 0:
			status += "  •  builds stalled: assign builders"
		else:
			status += "  •  builds queued"
	# Goal reward preview (issue #141)
	if not active_goal.is_empty() and active_goal.has("reward"):
		var reward_text = RotatingGoal.get_reward_preview_text(active_goal)
		if not reward_text.is_empty():
			status += "  •  " + reward_text
	if compact:
		return status + "\nNext: " + next_unlock
	return status + "\nNext: " + next_unlock

func next_unlock_text() -> String:
	if not is_structure_complete("hut"):
		return "Finish a hut to unlock the workshop"
	if not is_structure_complete("workshop"):
		return "Finish a workshop to unlock the garden"
	return "Garden tier unlocked. Keep the tiny settlement fed"

func is_save_compatible(loaded: Dictionary) -> bool:
	var tiles: Array = loaded.get("tiles", [])
	if tiles.size() != grid_w * grid_h:
		return false
	for worker in loaded.get("workers", []):
		if not is_pos_in_bounds(data_to_vec(worker.get("pos", {}))):
			return false
	for build in loaded.get("builds", []):
		if not is_pos_in_bounds(data_to_vec(build.get("pos", {}))):
			return false
	return true

func find_open_ground() -> Vector2i:
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			if abs(pos.x - stockpile_pos.x) + abs(pos.y - stockpile_pos.y) <= 1:
				continue
			if String(get_tile(pos).kind) == "ground":
				return pos
	return Vector2i(-1, -1)

func is_pos_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_w and pos.y >= 0 and pos.y < grid_h

func has_costs_delivered(build: Dictionary) -> bool:
	for resource in BUILD_COSTS[String(build.kind)].keys():
		if int(build.delivered.get(resource, 0)) < int(BUILD_COSTS[String(build.kind)][resource]):
			return false
	return true

func is_structure_unlocked(kind: String) -> bool:
	var unlock: Variant = BUILD_UNLOCKS.get(kind, true)
	if typeof(unlock) == TYPE_BOOL and bool(unlock):
		return true
	return is_structure_complete(String(unlock))

func is_structure_complete(kind: String) -> bool:
	for build in state.builds:
		if String(build.kind) == kind and bool(build.complete):
			return true
	return false

func push_event(text: String) -> void:
	state.events.push_front({"tick": tick, "text": text})
	while state.events.size() > 8:
		state.events.pop_back()

func persist() -> void:
	state["priority_order"] = priority_order.duplicate()
	state["colony_stance"] = colony_stance
	state["dock_anchor"] = String(settings.get("dock_anchor", "bottom"))
	state.tick = tick
	state["save_version"] = GameState.SAVE_VERSION
	if not state.has("reserved_resources"):
		state["reserved_resources"] = {}
	GameState.save_game(state)

func get_tile(pos: Vector2i) -> Dictionary:
	return state.tiles[pos.y * grid_w + pos.x]

func set_tile(pos: Vector2i, data: Dictionary) -> void:
	state.tiles[pos.y * grid_w + pos.x] = data

func get_build(id: int) -> Dictionary:
	for build in state.builds:
		if int(build.id) == id:
			return build
	return {}

func get_build_at_pos(pos: Vector2i) -> Dictionary:
	for build in state.builds:
		if data_to_vec(build.pos) == pos and not bool(build.complete):
			return build
	return {}

func set_build(id: int, updated: Dictionary) -> void:
	for i in state.builds.size():
		if int(state.builds[i].id) == id:
			state.builds[i] = updated
			return

func step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	if from.x != to.x:
		return Vector2i(from.x + signi(to.x - from.x), from.y)
	if from.y != to.y:
		return Vector2i(from.x, from.y + signi(to.y - from.y))
	return from

func data_to_vec(data: Variant) -> Vector2i:
	if data is Dictionary:
		return Vector2i(int(data.x), int(data.y))
	return Vector2i.ZERO

func vec_to_data(pos: Vector2i) -> Dictionary:
	return {"x": pos.x, "y": pos.y}

func vec_key(pos: Vector2i) -> String:
	return "%d,%d" % [pos.x, pos.y]


func reserve_resource(resource: String, amount: int = 1) -> void:
	if not state.has("reserved_resources"):
		state["reserved_resources"] = {}
	var current := int(state.reserved_resources.get(resource, 0))
	state.reserved_resources[resource] = current + amount

func release_resource(resource: String, amount: int = 1) -> void:
	if not state.has("reserved_resources"):
		return
	var current := maxi(0, int(state.reserved_resources.get(resource, 0)) - amount)
	state.reserved_resources[resource] = current

func get_reserved(resource: String) -> int:
	if not state.has("reserved_resources"):
		return 0
	return int(state.reserved_resources.get(resource, 0))

func cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)
