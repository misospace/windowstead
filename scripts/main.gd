extends Control

const SIDE_GRID_W := 7
const SIDE_GRID_H := 16
const BOTTOM_GRID_W := 30
const BOTTOM_GRID_H := 5
const SIDE_STOCKPILE_POS := Vector2i(2, 7)
const BOTTOM_STOCKPILE_POS := Vector2i(11, 2)
const TILE_GAP := 6
const TILE_SIZE_BUMP := 1.15
const BOTTOM_TILE_BASE_PX := 40.0
const VERTICAL_TILE_BASE_PX := 48.0
const WORLD_PANEL_PADDING := Vector2i(16, 16)
const SIDEBAR_WIDTH := 240
const BOTTOM_DOCK_PADDING := Vector2i(48, 110)
const VERTICAL_DOCK_PADDING := Vector2i(60, 120)
const WORKER_NAMES := ["Jun", "Mara"]
const BASE_TICK_SECONDS := 0.9
const EVENT_INTERVAL_TICKS := 66
const RESOURCE_COLORS := {
	"wood": Color("#5d8f58"),
	"stone": Color("#8b96a4"),
	"food": Color("#c99e53"),
}
const STRUCTURE_COLORS := {
	"hut": Color("#a26f47"),
	"workshop": Color("#5f7da3"),
	"garden": Color("#78a85d"),
}
const TILE_BACKDROPS := {
	"ground": Color("#232a33"),
	"tree": Color("#294131"),
	"rock": Color("#3a434d"),
	"berries": Color("#4a3144"),
	"foundation": Color("#57442e"),
	"hut": Color("#5a4031"),
	"workshop": Color("#32465d"),
	"garden": Color("#30523a"),
	"stockpile": Color("#66522a"),
}
const WORKER_BADGE_COLORS := {
	"Jun": Color("#f58f6c"),
	"Mara": Color("#75c7ff"),
}
const BUILD_COSTS := {
	"hut": {"wood": 6, "stone": 2},
	"workshop": {"wood": 4, "stone": 6},
	"garden": {"wood": 3, "stone": 1},
}
const BUILD_UNLOCKS := {
	"hut": true,
	"workshop": "hut",
	"garden": "workshop",
}

@onready var world_grid: GridContainer = %WorldGrid
@onready var world_overlay: Control = %WorldOverlay
@onready var resource_label: Label = %ResourceLabel
@onready var status_label: Label = %StatusLabel
@onready var activity_label: Label = %ActivityLabel
@onready var world_label: Label = %WorldLabel
@onready var root_box: BoxContainer = get_node("Backdrop/Margin/Root")
@onready var left_column: VBoxContainer = get_node("Backdrop/Margin/Root/Left")
@onready var world_panel: PanelContainer = get_node("Backdrop/Margin/Root/Left/WorldPanel")
@onready var sidebar_scroll: ScrollContainer = get_node("Backdrop/Margin/Root/SidebarScroll")
@onready var title_label: Label = get_node("Backdrop/Margin/Root/Left/Title")
@onready var subtitle_label: Label = get_node("Backdrop/Margin/Root/Left/Subtitle")
@onready var crew_list: VBoxContainer = %CrewList
@onready var event_log: RichTextLabel = %EventLog
@onready var gather_rank: Label = %GatherRank
@onready var haul_rank: Label = %HaulRank
@onready var build_rank: Label = %BuildRank
@onready var menu_button: Button = %HudMenuButton
@onready var menu_hint: Label = %HudHint
@onready var build_mode_button: Button = %BuildModeButton
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
var rng := RandomNumberGenerator.new()
var tick_timer: Timer
var worker_texture_cache: Dictionary = {}
var pending_build_kind := ""
var priority_order: Array[String] = ["build", "haul", "gather"]
var hover_tile_index := -1
var grid_w := BOTTOM_GRID_W
var grid_h := BOTTOM_GRID_H
var stockpile_pos := BOTTOM_STOCKPILE_POS
var anchor_family := "bottom"
var tile_size := Vector2i(56, 56)
var worker_overlay_nodes: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	load_settings()
	configure_window()
	title_label.visible = false
	subtitle_label.visible = false
	activity_label.visible = false
	world_grid.columns = grid_w
	build_world()
	wire_controls()
	load_or_boot()
	tick_timer = Timer.new()
	tick_timer.wait_time = tick_seconds_for_setting()
	tick_timer.autostart = true
	tick_timer.timeout.connect(_on_tick)
	add_child(tick_timer)
	update_menu_button_text()
	render_all()

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
func configure_window() -> void:
	keep_window_pinned()
	apply_dock_position()

func apply_dock_position() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var dock_anchor := String(settings.get("dock_anchor", "bottom"))
	apply_anchor_geometry(dock_anchor)
	update_tile_metrics(dock_anchor)
	apply_anchor_layout(dock_anchor)
	var dock_size := dock_size_for_anchor(dock_anchor)
	DisplayServer.window_set_min_size(dock_size)
	DisplayServer.window_set_size(dock_size)
	DisplayServer.window_set_position(dock_position_for_anchor(usable_rect, dock_size, dock_anchor))

func update_tile_metrics(dock_anchor: String) -> void:
	var tile_px: int = tile_px_for_anchor(dock_anchor)
	tile_size = Vector2i(tile_px, tile_px)

func tile_px_for_anchor(dock_anchor: String) -> int:
	var base_tile_px: float = BOTTOM_TILE_BASE_PX if dock_anchor == "bottom" else VERTICAL_TILE_BASE_PX
	var zoom: float = float(settings.get("zoom_factor", 1.0))
	return maxi(1, int(round(base_tile_px * TILE_SIZE_BUMP * zoom)))

func world_pixel_size() -> Vector2i:
	return Vector2i(
		grid_w * tile_size.x + (grid_w - 1) * TILE_GAP,
		grid_h * tile_size.y + (grid_h - 1) * TILE_GAP
	)

func dock_padding_for_anchor(dock_anchor: String) -> Vector2i:
	return BOTTOM_DOCK_PADDING if dock_anchor == "bottom" else VERTICAL_DOCK_PADDING

func apply_anchor_geometry(dock_anchor: String) -> void:
	if dock_anchor == "bottom":
		anchor_family = "bottom"
	else:
		anchor_family = "vertical"
	if anchor_family == "bottom":
		grid_w = BOTTOM_GRID_W
		grid_h = BOTTOM_GRID_H
		stockpile_pos = BOTTOM_STOCKPILE_POS
	else:
		grid_w = SIDE_GRID_W
		grid_h = SIDE_GRID_H
		stockpile_pos = SIDE_STOCKPILE_POS
func apply_anchor_layout(dock_anchor: String) -> void:
	var is_bottom := anchor_family == "bottom"
	var world_size: Vector2i = world_pixel_size()
	root_box.vertical = true
	left_column.size_flags_horizontal = 3
	left_column.size_flags_vertical = 3
	world_panel.custom_minimum_size = Vector2(world_size.x + WORLD_PANEL_PADDING.x, world_size.y + WORLD_PANEL_PADDING.y)
	sidebar_scroll.custom_minimum_size = Vector2(240, 200) if is_bottom else Vector2(220, 300)
	world_grid.custom_minimum_size = Vector2(world_size.x, world_size.y)
	if world_grid:
		world_grid.columns = grid_w
	# HUD label tuning for bottom mode (issue #21)
	if status_label:
		status_label.add_theme_font_size_override("font_size", 12 if is_bottom else 14)
	if menu_hint:
		menu_hint.add_theme_font_size_override("font_size", 11 if is_bottom else 13)
	position_popup_panel(dock_anchor)
func position_popup_panel(dock_anchor: String) -> void:
	var backdrop_size: Vector2 = get_node("Backdrop").size
	var popup_size: Vector2 = sidebar_scroll.custom_minimum_size
	if dock_anchor == "bottom":
		sidebar_scroll.position = Vector2(backdrop_size.x - SIDEBAR_WIDTH - 16, 16)
	else:
		sidebar_scroll.position = Vector2(16, 16)
	if dock_anchor == "right":
		sidebar_scroll.position.x = max(16.0, backdrop_size.x - popup_size.x - 16)
	sidebar_scroll.size = popup_size

func dock_size_for_anchor(dock_anchor: String) -> Vector2i:
	var base := world_pixel_size() + dock_padding_for_anchor(dock_anchor)
	if dock_anchor == "bottom":
		base.x += SIDEBAR_WIDTH + 16  # account for popup sidebar in bottom mode
	return base

func dock_position_for_anchor(usable_rect: Rect2i, dock_size: Vector2i, dock_anchor: String) -> Vector2i:
	if dock_anchor == "left":
		return Vector2i(
			usable_rect.position.x + 12,
			usable_rect.position.y + usable_rect.size.y - dock_size.y - 12
		)
	if dock_anchor == "bottom":
		return Vector2i(
			usable_rect.position.x + int((usable_rect.size.x - dock_size.x) / 2),
			usable_rect.position.y + usable_rect.size.y - dock_size.y - 12
		)
	return Vector2i(
		usable_rect.position.x + usable_rect.size.x - dock_size.x - 12,
		usable_rect.position.y + usable_rect.size.y - dock_size.y - 12
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
		var tile_panel := PanelContainer.new()
		tile_panel.custom_minimum_size = tile_size
		tile_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		tile_panel.clip_children = Control.ClipChildren.ALWAYS
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
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_SHRINK_END
		tile_panel.add_child(box)

		var icon_label := Label.new()
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", 24 if anchor_family == "bottom" else 20)
		box.add_child(icon_label)

		var amount_label := Label.new()
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.add_theme_font_size_override("font_size", 12 if anchor_family == "bottom" else 10)
		amount_label.modulate = Color(1, 1, 1, 0.72)
		box.add_child(amount_label)

		var progress_label := Label.new()
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_label.add_theme_font_size_override("font_size", 11 if anchor_family == "bottom" else 9)
		progress_label.modulate = Color(1, 1, 1, 0.58)
		box.add_child(progress_label)

		var worker_row := HBoxContainer.new()
		worker_row.alignment = BoxContainer.ALIGNMENT_CENTER
		worker_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		worker_row.add_theme_constant_override("separation", 2)
		box.add_child(worker_row)

		tile_views.append({
			"panel": tile_panel,
			"icon": icon_label,
			"amount": amount_label,
			"progress": progress_label,
			"worker_row": worker_row,
		})

func wire_controls() -> void:
	for row in %BuildButtons.get_children():
		if row is Button:
			row.pressed.connect(func() -> void: begin_build_placement(String(row.get_meta("kind"))))
	%SaveButton.pressed.connect(save_game)
	%ResetButton.pressed.connect(start_new_game)
	menu_button.pressed.connect(toggle_menu)
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

func load_or_boot() -> void:
	var loaded := GameState.load_game()
	if loaded.is_empty() or not is_save_compatible(loaded):
		bootstrap_state()
	else:
		state = loaded
		tick = int(state.get("tick", 0))
		for worker in state.get("workers", []):
			if not worker.has("break_ticks"):
				worker.break_ticks = 0
		apply_priority_order()

func bootstrap_state() -> void:
	state = {
		"tick": 0,
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
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
	persist()

func load_settings() -> void:
	settings = {
		"dock_anchor": "right",
		"tick_speed": 0,
	}
	settings.merge(GameState.load_settings(), true)
	dock_side_option.clear()
	dock_side_option.add_item("Right")
	dock_side_option.add_item("Left")
	dock_side_option.add_item("Bottom")
	match String(settings.get("dock_anchor", "right")):
		"left":
			dock_side_option.select(1)
		"bottom":
			dock_side_option.select(2)
		_:
			dock_side_option.select(0)
	tick_speed_slider.value = float(settings.get("tick_speed", 0))
	update_tick_speed_label()

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
	management_panels.visible = is_open
	if not is_open:
		close_settings()
		pending_build_kind = ""
		world_label.text = "Colony"
	update_menu_button_text()

func open_build_popup() -> void:
	if not pending_build_kind.is_empty():
		cancel_build_placement()
		return
	sidebar_scroll.visible = true
	menu_actions.visible = true
	management_panels.visible = true
	settings_panel.visible = false
	update_menu_button_text()

func open_settings() -> void:
	sidebar_scroll.visible = true
	menu_actions.visible = true
	management_panels.visible = true
	settings_panel.visible = true
	update_menu_button_text()

func close_settings() -> void:
	settings_panel.visible = false
	update_menu_button_text()

func start_new_game() -> void:
	GameState.clear_game()
	bootstrap_state()
	push_event("Settlement reset. Nobody remembers the paperwork.")
	menu_actions.visible = false
	sidebar_scroll.visible = false
	management_panels.visible = false
	close_settings()
	update_menu_button_text()
	render_all()

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
		push_event("No compatible save found. The colony keeps improvising.")
		menu_actions.visible = false
		close_settings()
		render_sidebar()
		return
	var save_version: int = int(loaded.get("save_version", 0))
	if save_version != GameState.SAVE_VERSION:
		push_event("Save version mismatch (%d → %d). Colony reset.".format([save_version, GameState.SAVE_VERSION]))
		menu_actions.visible = false
		close_settings()
		render_sidebar()
		return
	if not is_save_compatible(loaded):
		push_event("Save incompatible with current layout. Colony keeps improvising.")
		menu_actions.visible = false
		close_settings()
		render_sidebar()
		return
	state = loaded
	tick = int(state.get("tick", 0))
	for worker in state.get("workers", []):
		if not worker.has("break_ticks"):
			worker.break_ticks = 0
	apply_priority_order()
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

func _on_dock_side_selected(index: int) -> void:
	var previous_family := anchor_family
	var menu_was_open := sidebar_scroll.visible
	settings["dock_anchor"] = dock_anchor_from_option(index)
	save_settings()
	apply_dock_position()
	if menu_was_open:
		sidebar_scroll.visible = true
		menu_actions.visible = true
		management_panels.visible = true
		position_popup_panel(settings.get("dock_anchor", "right"))
		update_menu_button_text()
	if previous_family != anchor_family:
		build_world()
		bootstrap_state()
		push_event("Dock orientation changed. The colony replanned itself for the new strip.")
		render_all()
	sidebar_scroll.visible = menu_was_open
	if menu_was_open:
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
		menu_button.text = "Close Menu"
		menu_hint.text = "Planning" if pending_build_kind.is_empty() else "Place %s" % cap(pending_build_kind)
	else:
		menu_button.text = "Open Menu"
		menu_hint.text = "%d workers active" % active_worker_count()
	build_mode_button.text = "Cancel Build" if not pending_build_kind.is_empty() else "Build"

func active_worker_count() -> int:
	var active := 0
	for worker in state.workers:
		if int(worker.get("break_ticks", 0)) <= 0:
			active += 1
	return active

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

func stockpile_summary_text() -> String:
	var harvested: Dictionary = state.get("harvested", {})
	var wood := int(state.resources.get("wood", 0))
	var stone := int(state.resources.get("stone", 0))
	var food := int(state.resources.get("food", 0))
	return "Stored  W %d  S %d  F %d\nHarvested  W %d  S %d  F %d" % [wood, stone, food, int(harvested.get("wood", 0)), int(harvested.get("stone", 0)), int(harvested.get("food", 0))]

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
	keep_window_pinned()
	tick += 1
	state.tick = tick
	maybe_fire_event()
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
	persist()
	state.workers = state.workers
	render_all()

func _process(_delta: float) -> void:
	render_worker_overlay()

func choose_task(worker: Dictionary) -> Dictionary:
	for kind in priority_order:
		var tasks: Array = tasks_for_kind(String(kind))
		if tasks.is_empty():
			continue
		tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return task_distance(worker, a) < task_distance(worker, b)
		)
		return tasks[0]
	return {}

func tasks_for_kind(kind: String) -> Array:
	match kind:
		"build":
			return gather_build_tasks()
		"haul":
			return gather_haul_tasks()
		"gather":
			return gather_gather_tasks()
	return []

func task_distance(worker: Dictionary, task: Dictionary) -> int:
	var pos := data_to_vec(worker.pos)
	var target := data_to_vec(task.target)
	return abs(pos.x - target.x) + abs(pos.y - target.y)

func gather_build_tasks() -> Array:
	var tasks: Array = []
	for build in state.builds:
		if not bool(build.complete) and has_costs_delivered(build):
			tasks.append({"kind": "build", "build_id": int(build.id), "target": build.pos})
	return tasks

func gather_haul_tasks() -> Array:
	var tasks: Array = []
	for build in state.builds:
		if bool(build.complete):
			continue
		for resource in BUILD_COSTS[String(build.kind)].keys():
			var need := int(BUILD_COSTS[String(build.kind)][resource]) - int(build.delivered.get(resource, 0))
			if need > 0 and int(state.resources.get(resource, 0)) > 0:
				tasks.append({"kind": "haul", "build_id": int(build.id), "target": vec_to_data(stockpile_pos), "resource": resource})
	return tasks

func gather_gather_tasks() -> Array:
	var tasks: Array = []
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			if ["tree", "rock", "berries"].has(String(tile.kind)) and int(tile.amount) > 0:
				tasks.append({"kind": "gather", "target": vec_to_data(pos), "resource": tile.resource})
	return tasks

func step_worker(worker: Dictionary) -> void:
	var task: Dictionary = worker.task
	var target := data_to_vec(task.target)
	if task.kind == "haul" and int(worker.carrying.get(String(task.resource), 0)) > 0:
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
		return
	tile.amount = int(tile.amount) - 1
	worker.carrying[String(tile.resource)] = int(worker.carrying.get(String(tile.resource), 0)) + 1
	state.harvested[String(task.resource)] = int(state.get("harvested", {}).get(String(task.resource), 0)) + 1
	if int(tile.amount) <= 0:
		tile.kind = "ground"
		tile.resource = ""
	set_tile(target, tile)
	worker.task = {"kind": "haul", "target": vec_to_data(stockpile_pos), "resource": task.resource, "build_id": -1}

func do_haul(worker: Dictionary, task: Dictionary) -> void:
	var resource := String(task.resource)
	var carried := int(worker.carrying.get(resource, 0))
	if carried > 0:
		if int(task.build_id) >= 0:
			var build := get_build(int(task.build_id))
			if not build.is_empty() and not bool(build.complete):
				build.delivered[resource] = int(build.delivered.get(resource, 0)) + carried
				set_build(int(task.build_id), build)
			else:
				state.resources[resource] = int(state.resources.get(resource, 0)) + carried
		else:
			state.resources[resource] = int(state.resources.get(resource, 0)) + carried
		worker.carrying[resource] = 0
		worker.task = {}
		return
	if data_to_vec(worker.pos) == stockpile_pos and int(state.resources.get(resource, 0)) > 0 and int(task.build_id) >= 0:
		state.resources[resource] = int(state.resources.get(resource, 0)) - 1
		worker.carrying[resource] = 1
		var build := get_build(int(task.build_id))
		if build.is_empty():
			worker.task = {}
		else:
			worker.task.target = build.pos
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
	world_label.text = "Colony  •  placing %s" % cap(kind)
	push_event("Placement mode: click a ground tile for %s." % cap(kind))
	menu_actions.visible = false
	management_panels.visible = false
	settings_panel.visible = false
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
		"progress": 0.0,
		"complete": false,
	}
	state.next_build_id = int(state.next_build_id) + 1
	state.builds.append(build)
	set_tile(pos, {"kind": "foundation", "amount": 0, "resource": "", "build_kind": kind})
	push_event("%s queued. The workers will fake having a plan." % cap(kind))
	pending_build_kind = ""
	hover_tile_index = -1
	world_label.text = "Colony"
	persist()
	render_all()

func cancel_build_placement() -> void:
	if pending_build_kind.is_empty():
		return
	var kind := pending_build_kind
	pending_build_kind = ""
	hover_tile_index = -1
	world_label.text = "Colony"
	if not kind.is_empty():
		world_label.text = "Colony  •  place another " + cap(kind)

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
	return speed

func render_all() -> void:
	render_world()
	render_worker_overlay()
	render_sidebar()
	render_build_buttons()

func render_world() -> void:
	for y in grid_h:
		for x in grid_w:
			var index := y * grid_w + x
			var view := tile_views[index]
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			var panel: PanelContainer = view.panel
			var icon_label: Label = view.icon
			var amount_label: Label = view.amount
			var progress_label: Label = view.progress
			var worker_row: HBoxContainer = view.worker_row
			panel.add_theme_stylebox_override("panel", tile_style(tile, pos))
			icon_label.text = tile_icon(tile, pos)
			amount_label.text = tile_amount_text(tile, pos)
			progress_label.text = tile_progress_text(tile, pos)
			var workers_here := workers_at_pos(pos)
			if not workers_here.is_empty():
				worker_row.visible = true
				render_worker_sprites(worker_row, workers_here)
			else:
				worker_row.visible = false

func render_worker_overlay() -> void:
	if tile_views.is_empty():
		return
	for child in world_overlay.get_children():
		child.visible = false
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
			sprite.custom_minimum_size = Vector2(22, 28)
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			world_overlay.add_child(sprite)
			worker_overlay_nodes[name] = sprite
		sprite.visible = true
		sprite.texture = worker_texture(name, worker_anim_frame(worker))
		var from_pos := data_to_vec(worker.get("prev_pos", worker.get("pos", vec_to_data(stockpile_pos))))
		var to_pos := data_to_vec(worker.get("pos", vec_to_data(stockpile_pos)))
		var from_center := tile_center(from_pos)
		var to_center := tile_center(to_pos)
		var eased := ease(progress, 0.3)
		var draw_pos := from_center.lerp(to_center, eased)
		sprite.position = draw_pos - sprite.custom_minimum_size * 0.5

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

func render_sidebar() -> void:
	resource_label.text = stockpile_summary_text()
	status_label.text = settlement_status_text()
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
			if unlocked:
				child.tooltip_text = "Click, then place a %s on an open tile." % cap(kind)
			else:
				child.tooltip_text = "Locked until %s is finished." % cap(String(BUILD_UNLOCKS[kind]))

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
			return ["·", "˙", "•"][(tick + pos.x + pos.y) % 3]

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
		sprite.custom_minimum_size = Vector2(12, 14)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		sprite.texture = worker_texture(String(worker.name), worker_anim_frame(worker))
		container.add_child(sprite)

func worker_anim_frame(worker: Dictionary) -> int:
	if int(worker.get("break_ticks", 0)) > 0:
		return 0
	var task: Dictionary = worker.get("task", {})
	if task.is_empty():
		return 0 if tick % 10 < 5 else 1
	return tick % 2

func worker_texture(name: String, frame: int) -> Texture2D:
	var cache_key := "%s:%d" % [name, frame]
	if worker_texture_cache.has(cache_key):
		return worker_texture_cache[cache_key]
	var accent: Color = WORKER_BADGE_COLORS.get(name, Color.WHITE)
	var shadow := accent.darkened(0.45)
	var skin := Color("#f2d0b1")
	var image := Image.create(8, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	# head
	for y in range(0, 3):
		for x in range(2, 6):
			image.set_pixel(x, y, skin)

	# body
	for y in range(3, 7):
		for x in range(2, 6):
			image.set_pixel(x, y, accent)

	# arms
	image.set_pixel(1, 4, shadow)
	image.set_pixel(6, 4, shadow)

	# legs alternate per frame for a simple walk bob
	if frame % 2 == 0:
		image.set_pixel(2, 7, shadow)
		image.set_pixel(2, 8, shadow)
		image.set_pixel(5, 7, shadow)
		image.set_pixel(5, 8, shadow)
	else:
		image.set_pixel(3, 7, shadow)
		image.set_pixel(2, 8, shadow)
		image.set_pixel(4, 7, shadow)
		image.set_pixel(5, 8, shadow)

	# feet
	image.set_pixel(1, 9, shadow)
	image.set_pixel(5, 9, shadow)

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

func settlement_status_text() -> String:
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
	state.tick = tick
	state["save_version"] = GameState.SAVE_VERSION
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

func cap(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)
