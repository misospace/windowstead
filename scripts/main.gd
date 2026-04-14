extends Control

const GRID_W := 16
const GRID_H := 9
const TILE_SIZE := Vector2i(54, 54)
const STOCKPILE_POS := Vector2i(7, 4)
const WORKER_NAMES := ["Jun", "Mara"]
const TICK_SECONDS := 0.45
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

var tile_buttons: Array[Button] = []
var state: Dictionary = {}
var tick := 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	configure_window()
	world_grid.columns = GRID_W
	build_world()
	wire_controls()
	load_or_boot()
	var timer := Timer.new()
	timer.wait_time = TICK_SECONDS
	timer.autostart = true
	timer.timeout.connect(_on_tick)
	add_child(timer)
	render_all()

func configure_window() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_min_size(Vector2i(560, 420))
	if not ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", false):
		DisplayServer.window_set_position(Vector2i(max(0, DisplayServer.screen_get_size().x - DisplayServer.window_get_size().x - 24), 24))

func build_world() -> void:
	for child in world_grid.get_children():
		child.queue_free()
	tile_buttons.clear()
	for i in GRID_W * GRID_H:
		var button := Button.new()
		button.custom_minimum_size = TILE_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.disabled = true
		button.flat = false
		world_grid.add_child(button)
		tile_buttons.append(button)

func wire_controls() -> void:
	for row in %BuildButtons.get_children():
		if row is Button:
			row.pressed.connect(func() -> void: queue_structure(String(row.get_meta("kind"))))
	for slider in [gather_slider, haul_slider, build_slider]:
		slider.drag_ended.connect(func(_changed: bool) -> void: persist())
	%SaveButton.pressed.connect(func() -> void:
		persist()
		push_event("Game saved. Tiny bureaucracy, handled.")
		render_sidebar()
	)
	%ResetButton.pressed.connect(func() -> void:
		GameState.clear_game()
		bootstrap_state()
		push_event("Settlement reset. Nobody remembers the paperwork.")
		render_all()
	)

func load_or_boot() -> void:
	var loaded := GameState.load_game()
	if loaded.is_empty():
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
			"pos": vec_to_data(Vector2i(6 + i, 5)),
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
			var button := tile_buttons[index]
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			button.text = tile_label(tile, pos)
			button.modulate = tile_color(tile, pos)

func render_sidebar() -> void:
	resource_label.text = "Stockpile  •  Wood %d   Stone %d   Food %d" % [int(state.resources.wood), int(state.resources.stone), int(state.resources.food)]
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

func tile_label(tile: Dictionary, pos: Vector2i) -> String:
	if pos == STOCKPILE_POS:
		return "📦\nStock"
	var workers_here := []
	for worker in state.workers:
		if data_to_vec(worker.pos) == pos:
			workers_here.append(String(worker.name).left(1))
	var worker_suffix := ""
	if not workers_here.is_empty():
		worker_suffix = "\n[%s]" % ",".join(workers_here)
	match String(tile.kind):
		"tree": return "🌲 %d%s" % [int(tile.amount), worker_suffix]
		"rock": return "🪨 %d%s" % [int(tile.amount), worker_suffix]
		"berries": return "🫐 %d%s" % [int(tile.amount), worker_suffix]
		"foundation": return "🏗 %s%s" % [cap(String(tile.build_kind)).left(4), worker_suffix]
		"hut": return "🏠 Hut%s" % worker_suffix
		"workshop": return "🛠 Shop%s" % worker_suffix
		"garden": return "🪴 Garden%s" % worker_suffix
		_: return "·%s" % worker_suffix

func tile_color(tile: Dictionary, pos: Vector2i) -> Color:
	if pos == STOCKPILE_POS:
		return Color("#d4b36f")
	if RESOURCE_COLORS.has(String(tile.resource)):
		return RESOURCE_COLORS[String(tile.resource)]
	if STRUCTURE_COLORS.has(String(tile.kind)):
		return STRUCTURE_COLORS[String(tile.kind)]
	if String(tile.kind) == "foundation":
		return Color("#c7a25e")
	return Color(1, 1, 1, 0.82)

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
	return "Tick %d  •  queued %d  •  building %d  •  idle %d  •  break %d\nNext milestone: %s" % [tick, queued, building, idle, on_break, next_unlock]

func next_unlock_text() -> String:
	if not is_structure_complete("hut"):
		return "Finish a hut to unlock the workshop"
	if not is_structure_complete("workshop"):
		return "Finish a workshop to unlock the garden"
	return "Garden tier unlocked. Keep the tiny settlement fed"

func find_open_ground() -> Vector2i:
	for y in GRID_H:
		for x in GRID_W:
			var pos := Vector2i(x, y)
			if abs(pos.x - STOCKPILE_POS.x) + abs(pos.y - STOCKPILE_POS.y) <= 3:
				continue
			if String(get_tile(pos).kind) == "ground":
				return pos
	return Vector2i(-1, -1)

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
