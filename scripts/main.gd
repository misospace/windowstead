extends Control

const GRID_W := 4
const GRID_H := 12
const TILE_SIZE := Vector2i(44, 44)
const STOCKPILE_POS := Vector2i(1, 5)
const DOCK_WIDTH := 240
const DOCK_HEIGHT := 900
const WORKER_NAMES := ["Jun", "Mara"]
const BASE_TICK_SECONDS := 0.45
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
	"ground": Color("#1b2128"),
	"tree": Color("#233528"),
	"rock": Color("#2c3138"),
	"berries": Color("#352832"),
	"foundation": Color("#3b3124"),
	"hut": Color("#3b2d24"),
	"workshop": Color("#253142"),
	"garden": Color("#233426"),
	"stockpile": Color("#43361f"),
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
@onready var resource_label: Label = %ResourceLabel
@onready var status_label: Label = %StatusLabel
@onready var crew_list: VBoxContainer = %CrewList
@onready var event_log: RichTextLabel = %EventLog
@onready var gather_slider: HSlider = %GatherSlider
@onready var haul_slider: HSlider = %HaulSlider
@onready var build_slider: HSlider = %BuildSlider
@onready var menu_actions: VBoxContainer = %MenuActions
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var tick_speed_slider: HSlider = %TickSpeedSlider
@onready var tick_speed_value: Label = %TickSpeedValue

var tile_views: Array[Dictionary] = []
var state: Dictionary = {}
var settings: Dictionary = {}
var tick := 0
var rng := RandomNumberGenerator.new()
var tick_timer: Timer
var worker_texture_cache: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	configure_window()
	world_grid.columns = GRID_W
	build_world()
	load_settings()
	wire_controls()
	load_or_boot()
	tick_timer = Timer.new()
	tick_timer.wait_time = tick_seconds_for_setting()
	tick_timer.autostart = true
	tick_timer.timeout.connect(_on_tick)
	add_child(tick_timer)
	render_all()

func configure_window() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	var screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen)
	var dock_height := min(DOCK_HEIGHT, max(640, usable_rect.size.y - 24))
	var dock_size := Vector2i(DOCK_WIDTH, dock_height)
	DisplayServer.window_set_min_size(Vector2i(DOCK_WIDTH, 640))
	DisplayServer.window_set_size(dock_size)
	DisplayServer.window_set_position(Vector2i(
		usable_rect.position.x + usable_rect.size.x - dock_size.x - 12,
		usable_rect.position.y + usable_rect.size.y - dock_size.y - 12
	))

func build_world() -> void:
	for child in world_grid.get_children():
		child.queue_free()
	tile_views.clear()
	for i in GRID_W * GRID_H:
		var tile_panel := PanelContainer.new()
		tile_panel.custom_minimum_size = TILE_SIZE
		world_grid.add_child(tile_panel)

		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile_panel.add_child(box)

		var icon_label := Label.new()
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.theme_override_font_sizes.font_size = 20
		box.add_child(icon_label)

		var amount_label := Label.new()
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.theme_override_font_sizes.font_size = 10
		amount_label.modulate = Color(1, 1, 1, 0.72)
		box.add_child(amount_label)

		var progress_label := Label.new()
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		progress_label.theme_override_font_sizes.font_size = 9
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
			row.pressed.connect(func() -> void: queue_structure(String(row.get_meta("kind"))))
	for slider in [gather_slider, haul_slider, build_slider]:
		slider.drag_ended.connect(func(_changed: bool) -> void: persist())
	%SaveButton.pressed.connect(save_game)
	%ResetButton.pressed.connect(start_new_game)
	%MenuButton.pressed.connect(toggle_menu)
	%NewGameButton.pressed.connect(start_new_game)
	%SaveGameButton.pressed.connect(save_game)
	%LoadGameButton.pressed.connect(load_saved_game)
	%SettingsButton.pressed.connect(open_settings)
	%ExitButton.pressed.connect(exit_game)
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
		apply_priority_sliders()

func bootstrap_state() -> void:
	state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"priorities": {"gather": 3.0, "haul": 2.0, "build": 3.0},
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
			"pos": vec_to_data(Vector2i(1 + i, 6)),
			"carrying": {},
			"task": {},
			"break_ticks": 0,
		})
	for y in GRID_H:
		for x in GRID_W:
			state.tiles.append(seed_tile(Vector2i(x, y)))
	set_tile(STOCKPILE_POS, {"kind": "stockpile", "amount": 0, "resource": "", "build_kind": ""})
	tick = 0
	apply_priority_sliders()
	persist()

func load_settings() -> void:
	settings = {
		"tick_speed": 1,
	}
	settings.merge(GameState.load_settings(), true)
	tick_speed_slider.value = float(settings.get("tick_speed", 1))
	update_tick_speed_label()

func save_settings() -> void:
	settings["tick_speed"] = int(tick_speed_slider.value)
	GameState.save_settings(settings)

func toggle_menu() -> void:
	menu_actions.visible = not menu_actions.visible
	if not menu_actions.visible:
		close_settings()

func open_settings() -> void:
	menu_actions.visible = true
	settings_panel.visible = true

func close_settings() -> void:
	settings_panel.visible = false

func start_new_game() -> void:
	GameState.clear_game()
	bootstrap_state()
	push_event("Settlement reset. Nobody remembers the paperwork.")
	menu_actions.visible = false
	close_settings()
	render_all()

func save_game() -> void:
	persist()
	push_event("Game saved. Tiny bureaucracy, handled.")
	menu_actions.visible = false
	close_settings()
	render_sidebar()

func load_saved_game() -> void:
	var loaded := GameState.load_game()
	if loaded.is_empty() or not is_save_compatible(loaded):
		push_event("No compatible save found. The colony keeps improvising.")
		menu_actions.visible = false
		close_settings()
		render_sidebar()
		return
	state = loaded
	tick = int(state.get("tick", 0))
	for worker in state.get("workers", []):
		if not worker.has("break_ticks"):
			worker.break_ticks = 0
	apply_priority_sliders()
	push_event("Save loaded. Tiny lives resume their routines.")
	menu_actions.visible = false
	close_settings()
	render_all()

func exit_game() -> void:
	get_tree().quit()

func _on_tick_speed_changed(value: float) -> void:
	settings["tick_speed"] = int(value)
	update_tick_speed_label()
	if tick_timer:
		tick_timer.wait_time = tick_seconds_for_setting()
	save_settings()

func update_tick_speed_label() -> void:
	match int(tick_speed_slider.value):
		0:
			tick_speed_value.text = "Slow"
		1:
			tick_speed_value.text = "Normal"
		2:
			tick_speed_value.text = "Fast"

func tick_seconds_for_setting() -> float:
	match int(settings.get("tick_speed", 1)):
		0:
			return BASE_TICK_SECONDS * 1.45
		1:
			return BASE_TICK_SECONDS
		2:
			return BASE_TICK_SECONDS * 0.7
	return BASE_TICK_SECONDS

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
	tick += 1
	state.tick = tick
	maybe_fire_event()
	for worker in state.workers:
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

func choose_task(worker: Dictionary) -> Dictionary:
	var tasks: Array = []
	if build_slider.value > 0:
		tasks.append_array(gather_build_tasks())
	if haul_slider.value > 0:
		tasks.append_array(gather_haul_tasks())
	if gather_slider.value > 0:
		tasks.append_array(gather_gather_tasks())
	if tasks.is_empty():
		return {}
	tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return score_task(worker, a) > score_task(worker, b)
	)
	return tasks[0]

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
				tasks.append({"kind": "haul", "build_id": int(build.id), "target": vec_to_data(STOCKPILE_POS), "resource": resource})
	return tasks

func gather_gather_tasks() -> Array:
	var tasks: Array = []
	for y in GRID_H:
		for x in GRID_W:
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			if ["tree", "rock", "berries"].has(String(tile.kind)) and int(tile.amount) > 0:
				tasks.append({"kind": "gather", "target": vec_to_data(pos), "resource": tile.resource})
	return tasks

func score_task(worker: Dictionary, task: Dictionary) -> float:
	var priorities: Dictionary = state.priorities
	var pos := data_to_vec(worker.pos)
	var target := data_to_vec(task.target)
	var distance: int = abs(pos.x - target.x) + abs(pos.y - target.y)
	var base := float(priorities.get(task.kind, 1.0)) * 10.0
	if task.kind == "build":
		base += 4.0
	if task.kind == "haul":
		base += 2.0
	return base - float(distance)

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
	if int(tile.amount) <= 0:
		tile.kind = "ground"
		tile.resource = ""
	set_tile(target, tile)
	worker.task = {"kind": "haul", "target": vec_to_data(STOCKPILE_POS), "resource": task.resource, "build_id": -1}

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
	if data_to_vec(worker.pos) == STOCKPILE_POS and int(state.resources.get(resource, 0)) > 0 and int(task.build_id) >= 0:
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

func queue_structure(kind: String) -> void:
	if not is_structure_unlocked(kind):
		push_event("%s is locked. Build the previous upgrade first." % cap(kind))
		return
	var pos := find_open_ground()
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
	persist()
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
	return speed

func render_all() -> void:
	render_world()
	render_sidebar()
	render_build_buttons()

func render_world() -> void:
	for y in GRID_H:
		for x in GRID_W:
			var index := y * GRID_W + x
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
			render_worker_sprites(worker_row, workers_at_pos(pos))

func render_sidebar() -> void:
	resource_label.text = "Stockpile\nWood %d   Stone %d   Food %d" % [int(state.resources.wood), int(state.resources.stone), int(state.resources.food)]
	status_label.text = settlement_status_text()
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
			child.disabled = not unlocked
			if unlocked:
				child.tooltip_text = "%s is ready to queue." % cap(kind)
			else:
				child.tooltip_text = "Unlocks after %s." % cap(String(BUILD_UNLOCKS[kind]))

func tile_icon(tile: Dictionary, pos: Vector2i) -> String:
	if pos == STOCKPILE_POS:
		return "📦"
	match String(tile.kind):
		"tree": return "🌲"
		"rock": return "🪨"
		"berries": return "🫐"
		"foundation": return "🏗"
		"hut": return "🏠"
		"workshop": return "🛠"
		"garden": return "🪴"
		_: return "·"

func tile_amount_text(tile: Dictionary, pos: Vector2i) -> String:
	if pos == STOCKPILE_POS:
		return "stock"
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
	if String(tile.kind) != "foundation":
		return ""
	var build := get_build_at_pos(pos)
	if build.is_empty():
		return "queued"
	if not has_costs_delivered(build):
		var delivered := build.delivered
		return "%dw %ds" % [int(delivered.get("wood", 0)), int(delivered.get("stone", 0))]
	return "%d%%" % int(round(float(build.get("progress", 0.0)) * 100.0))

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
		sprite.custom_minimum_size = Vector2(10, 12)
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
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = 4
	style.content_margin_top = 3
	style.content_margin_right = 4
	style.content_margin_bottom = 3
	var kind := "stockpile" if pos == STOCKPILE_POS else String(tile.kind)
	style.bg_color = TILE_BACKDROPS.get(kind, Color("#1b2128"))
	style.border_color = tile_accent(tile, pos)
	return style

func tile_accent(tile: Dictionary, pos: Vector2i) -> Color:
	if pos == STOCKPILE_POS:
		return Color("#d4b36f")
	if RESOURCE_COLORS.has(String(tile.resource)):
		return RESOURCE_COLORS[String(tile.resource)]
	if STRUCTURE_COLORS.has(String(tile.kind)):
		return STRUCTURE_COLORS[String(tile.kind)]
	if String(tile.kind) == "foundation":
		return Color("#c7a25e")
	return Color(1, 1, 1, 0.18)

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
	return "Tick %d  •  queued %d  •  building %d\nIdle %d  •  break %d\nNext: %s" % [tick, queued, building, idle, on_break, next_unlock]

func next_unlock_text() -> String:
	if not is_structure_complete("hut"):
		return "Finish a hut to unlock the workshop"
	if not is_structure_complete("workshop"):
		return "Finish a workshop to unlock the garden"
	return "Garden tier unlocked. Keep the tiny settlement fed"

func is_save_compatible(loaded: Dictionary) -> bool:
	var tiles: Array = loaded.get("tiles", [])
	if tiles.size() != GRID_W * GRID_H:
		return false
	for worker in loaded.get("workers", []):
		if not is_pos_in_bounds(data_to_vec(worker.get("pos", {}))):
			return false
	for build in loaded.get("builds", []):
		if not is_pos_in_bounds(data_to_vec(build.get("pos", {}))):
			return false
	return true

func find_open_ground() -> Vector2i:
	for y in GRID_H:
		for x in GRID_W:
			var pos := Vector2i(x, y)
			if abs(pos.x - STOCKPILE_POS.x) + abs(pos.y - STOCKPILE_POS.y) <= 1:
				continue
			if String(get_tile(pos).kind) == "ground":
				return pos
	return Vector2i(-1, -1)

func is_pos_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_W and pos.y >= 0 and pos.y < GRID_H

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
	state.priorities = {
		"gather": gather_slider.value,
		"haul": haul_slider.value,
		"build": build_slider.value,
	}
	state.tick = tick
	GameState.save_game(state)

func apply_priority_sliders() -> void:
	var priorities: Dictionary = state.get("priorities", {"gather": 3.0, "haul": 2.0, "build": 3.0})
	gather_slider.value = float(priorities.get("gather", 3.0))
	haul_slider.value = float(priorities.get("haul", 2.0))
	build_slider.value = float(priorities.get("build", 3.0))

func get_tile(pos: Vector2i) -> Dictionary:
	return state.tiles[pos.y * GRID_W + pos.x]

func set_tile(pos: Vector2i, data: Dictionary) -> void:
	state.tiles[pos.y * GRID_W + pos.x] = data

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
