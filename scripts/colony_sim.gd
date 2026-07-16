## Scene-free colony simulation — owns the game-state dictionary and all
## worker/task/economy logic so the sim can run and be tested without UI nodes.
## main.gd holds one instance, proxies its own legacy members onto it, and
## renders whatever this class mutates. See the altitude findings in the
## /simplify review and misospace/windowstead#177 for the extraction lineage.
class_name ColonySim
extends RefCounted

const Constants := preload("res://scripts/constants.gd")
const LayoutMath := preload("res://scripts/layout_math.gd")
const ColonyStance := preload("res://scripts/colony_stance.gd")
const RotatingGoal := preload("res://scripts/rotating_goal.gd")
const GoalProgression := preload("res://scripts/goal_progression.gd")
const GoalReward := preload("res://scripts/goal_reward.gd")
const MilestoneManager := preload("res://scripts/milestone_manager.gd")
const WorkerCapLogic := preload("res://scripts/worker_cap_logic.gd")

# Food granted when a structure of each kind completes.
const BUILD_COMPLETION_FOOD := {"hut": 1, "garden": 3}

## The single source of truth for all persisted colony data.
var state: Dictionary = {}
var grid_w: int = LayoutMath.BOTTOM_GRID_W
var grid_h: int = LayoutMath.BOTTOM_GRID_H
var stockpile_pos: Vector2i = LayoutMath.stockpile_pos_for_anchor("bottom")
var priority_order: Array[String] = ["build", "haul", "gather"]
var rng := RandomNumberGenerator.new()
## Set on any state mutation; cleared by the owner when it persists.
var dirty := false
## Incremented on every event push so renderers can skip unchanged logs.
var event_rev := 0


func mark_dirty() -> void:
	dirty = true


func tick() -> int:
	return int(state.get("tick", 0))


func colony_stance() -> String:
	return String(state.get("colony_stance", ColonyStance.STANCE_BALANCED))


## Fill in any state keys missing from older saves or fresh bootstraps so the
## rest of the sim can mutate them without existence checks.
func ensure_defaults() -> void:
	if not state.has("reserved_resources"):
		state["reserved_resources"] = {}
	if not state.has("events"):
		state["events"] = []
	if not state.has("completed_goal_ids"):
		state["completed_goal_ids"] = []
	if not state.has("active_rewards"):
		state["active_rewards"] = []
	if not state.has("active_goal"):
		state["active_goal"] = GoalProgression.init_goals(state["completed_goal_ids"])
	if not state.has("colony_stance"):
		state["colony_stance"] = ColonyStance.STANCE_BALANCED
	var milestone_seed: Dictionary = MilestoneManager.make_goal_state()
	if not state.has("current_milestone_id"):
		state["current_milestone_id"] = milestone_seed["milestone_id"]
	if not state.has("completed_milestone_ids"):
		state["completed_milestone_ids"] = milestone_seed["completed_ids"]
	for worker in state.get("workers", []):
		if not worker.has("break_ticks"):
			worker["break_ticks"] = 0
	# The event list may have been swapped wholesale (load/bootstrap); force
	# rev-gated renderers to refresh.
	event_rev += 1


# ── Events ────────────────────────────────────────────────────────────────────

func push_event(text: String) -> void:
	if not state.has("events"):
		return
	state.events.push_front({"tick": tick(), "text": text})
	while state.events.size() > Constants.MAX_EVENT_LOG:
		state.events.pop_back()
	event_rev += 1
	mark_dirty()


# ── Tick orchestration ────────────────────────────────────────────────────────

func process_tick() -> void:
	state["tick"] = tick() + 1
	maybe_fire_event()
	_clean_stale_reservations()

	# Food upkeep (issue #147)
	if tick() % Constants.FOOD_UPKEEP_INTERVAL_TICKS == 0:
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

	_process_goals()
	_process_milestones()


func _process_goals() -> void:
	var active_goal: Dictionary = state.get("active_goal", {})
	var completed_ids: Array = state.get("completed_goal_ids", [])
	var result: Dictionary = GoalProgression.process_tick(active_goal, completed_ids, state)
	state["active_goal"] = result["active_goal"]
	state["completed_goal_ids"] = result["completed_ids"]
	if result["was_completed"]:
		push_event("Goal completed: %s. The colony moves on." % result["goal_id"])
		var new_reward: Dictionary = GoalReward.apply_reward(result["goal_id"])
		if not new_reward.is_empty():
			state["active_rewards"].append(new_reward)
			push_event("Reward: %s" % new_reward["label"])
		mark_dirty()
	# Tick active rewards (expiration + trickle payouts)
	var reward_result: Dictionary = GoalReward.tick_rewards(state.get("active_rewards", []), state)
	state["active_rewards"] = reward_result["new_rewards"]
	for evt in reward_result["events"]:
		push_event(evt)
	for expired_label in reward_result["expired"]:
		push_event("Reward ended: %s" % expired_label)


# Current-milestone lookup cache — the catalog entry only changes when the
# chain advances, so the per-tick scan + deep copy is skipped otherwise.
var _milestone_cache: Dictionary = {}
var _milestone_cache_id := "__unset__"

func _current_milestone(milestone_id: String) -> Dictionary:
	if _milestone_cache_id != milestone_id:
		_milestone_cache_id = milestone_id
		_milestone_cache = MilestoneManager.get_current_milestone(MilestoneManager.MILESTONE_CATALOG, milestone_id)
	return _milestone_cache

func _process_milestones() -> void:
	# Milestone evaluation (issue #237)
	var current_id: String = String(state.get("current_milestone_id", ""))
	var active_milestone: Dictionary = _current_milestone(current_id)
	if active_milestone.is_empty() or not MilestoneManager.is_milestone_complete(active_milestone, state):
		return
	state["completed_milestone_ids"].append(current_id)
	push_event("Milestone reached: %s" % MilestoneManager.milestone_description(active_milestone))
	state["current_milestone_id"] = MilestoneManager.advance_to_next(state["completed_milestone_ids"], current_id)
	mark_dirty()


# ── Ambient events ────────────────────────────────────────────────────────────

func maybe_fire_event() -> void:
	if tick() % Constants.EVENT_INTERVAL_TICKS != 0:
		return
	var event_roll := rng.randi_range(0, 2)
	# If ambient_improve reward is active, convert negative events to positive
	if event_roll == 1 and GoalReward.consume_ambient_improve(state.get("active_rewards", [])):
		event_roll = 0
		push_event("A goal reward smooths things over.")
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
	var kinds: Array = Constants.RESOURCE_TILES.keys()
	var resource_kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	var drop: Dictionary = Constants.RESOURCE_TILES[resource_kind]
	set_tile(pos, {"kind": resource_kind, "amount": drop.drop_amount, "resource": drop.resource, "build_kind": ""})
	push_event(drop.drop_message)


# ── Food upkeep (issue #147, links to #133) ───────────────────────────────────

func get_extra_workers_count() -> int:
	if not state.has("workers"):
		return 0
	var total: int = state.workers.size()
	return maxi(total - Constants.BASE_WORKERS_NO_UPKEEP, 0)


func apply_food_upkeep() -> void:
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
		mark_dirty()


func get_food_slowdown_factor() -> float:
	var food := int(state.resources.get("food", 0))
	if food <= Constants.STARVATION_FOOD_THRESHOLD:
		return Constants.STARVATION_SPEED_FACTOR
	if food <= Constants.LOW_FOOD_THRESHOLD:
		# Linear interpolation between starvation and low-food threshold
		var range_size := float(Constants.LOW_FOOD_THRESHOLD - Constants.STARVATION_FOOD_THRESHOLD)
		if range_size == 0:
			return Constants.LOW_FOOD_SPEED_FACTOR
		var progress := float(food - Constants.STARVATION_FOOD_THRESHOLD) / range_size
		return lerp(Constants.STARVATION_SPEED_FACTOR, Constants.LOW_FOOD_SPEED_FACTOR, progress)
	return 1.0


func get_low_food_level() -> String:
	var food := int(state.resources.get("food", 0))
	if food <= Constants.STARVATION_FOOD_THRESHOLD:
		return "starving"
	if food <= Constants.LOW_FOOD_THRESHOLD:
		return "low"
	return "ok"


func should_bias_to_food_gathering() -> bool:
	var level := get_low_food_level()
	return level == "low" or level == "starving"


# ── Worker cap and recruiting (issue #149) ────────────────────────────────────

func get_worker_cap() -> int:
	return WorkerCapLogic.calculate_worker_cap(state.get("builds", []))


func can_recruit_worker() -> bool:
	return WorkerCapLogic.can_recruit(state.get("builds", []), state.get("workers", []))


func recruit_worker() -> void:
	if not can_recruit_worker():
		push_event("Not enough housing for another worker. Build more huts.")
		return

	# Pick the next available name from WORKER_NAMES (cycle through)
	var current: int = state.workers.size()
	var next_index: int = current % Constants.WORKER_NAMES.size()
	var new_worker := {
		"name": Constants.WORKER_NAMES[next_index],
		"task": {"kind": "", "data": {}},
		"carrying": {},
		"break_ticks": 0,
		"spawn_tick": tick(),
	}
	state["workers"].append(new_worker)

	# Apply recruit discount reward if active (gives +1 food)
	if GoalReward.consume_recruit_discount(state.get("active_rewards", [])):
		state.resources["food"] = int(state.resources.get("food", 0)) + 1
	mark_dirty()

	var extra := get_extra_workers_count()
	if extra > 0:
		var food_cost := extra * Constants.FOOD_PER_EXTRA_WORKER
		push_event("New crew member %s joins! Food impact: +%d per cycle." % [new_worker.name, food_cost])
	else:
		push_event("New crew member %s joins the tiny colony." % new_worker.name)


# ── Task selection ────────────────────────────────────────────────────────────

func choose_task(worker: Dictionary) -> Dictionary:
	var effective_order := ColonyStance.get_effective_priority_order(colony_stance(), priority_order)
	for kind in effective_order:
		var tasks: Array[Dictionary] = tasks_for_kind(String(kind))
		if tasks.is_empty():
			continue
		# Food stance and low-food bias (issue #147) both sort food tasks first.
		var prefer_food: bool = String(kind) == "gather_food" \
			or (String(kind) == "gather" and should_bias_to_food_gathering())
		tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if prefer_food:
				var a_is_food := ColonyStance.is_food_gather_task(a)
				var b_is_food := ColonyStance.is_food_gather_task(b)
				if a_is_food != b_is_food:
					return a_is_food
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
		for resource in Constants.BUILD_COSTS[String(build.kind)].keys():
			var reserved := int(build.get("reserved", {}).get(resource, 0))
			var need := int(Constants.BUILD_COSTS[String(build.kind)][resource]) - int(build.delivered.get(resource, 0)) - reserved
			if need > 0 and int(state.resources.get(resource, 0)) > 0:
				tasks.append({"kind": "haul", "build_id": int(build.id), "target": vec_to_data(stockpile_pos), "resource": resource})
	return tasks


func gather_gather_tasks() -> Array[Dictionary]:
	# One pass to total each gatherable resource, so the reservation check
	# below is a lookup instead of a per-tile grid rescan.
	var totals := {}
	for y in grid_h:
		for x in grid_w:
			var tile := get_tile(Vector2i(x, y))
			if Constants.RESOURCE_TILES.has(String(tile.kind)):
				var resource := String(tile.resource)
				totals[resource] = int(totals.get(resource, 0)) + int(tile.amount)
	var tasks: Array[Dictionary] = []
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			var tile := get_tile(pos)
			if Constants.RESOURCE_TILES.has(String(tile.kind)) and int(tile.amount) > 0:
				# Skip if resource is fully reserved (reserved >= available anywhere)
				var resource := String(tile.resource)
				if get_reserved(resource) >= int(totals.get(resource, 0)):
					continue
				tasks.append({"kind": "gather", "target": vec_to_data(pos), "resource": tile.resource})
	return tasks


# ── Task execution ────────────────────────────────────────────────────────────

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
	mark_dirty()
	# Release reservation — resource is now in worker's possession
	release_resource(String(task.resource))
	worker.task = {"kind": "haul", "target": vec_to_data(stockpile_pos), "resource": task.resource, "build_id": -1}


func do_haul(worker: Dictionary, task: Dictionary) -> void:
	var resource := String(task.resource)
	var carried := int(worker.carrying.get(resource, 0))
	if carried > 0:
		_deliver_carried(worker, task, resource, carried)
		return
	if data_to_vec(worker.pos) == stockpile_pos and int(state.resources.get(resource, 0)) > 0 and int(task.build_id) >= 0:
		_pick_up_for_build(worker, task, resource)
		return
	worker.task = {}


## Deposit whatever the worker carries: into the target build (clamped to its
## remaining need, excess refunded) or into the stockpile when there is no
## live build target.
func _deliver_carried(worker: Dictionary, task: Dictionary, resource: String, carried: int) -> void:
	var build: Dictionary = get_build(int(task.build_id)) if int(task.build_id) >= 0 else {}
	if build.is_empty() or bool(build.complete):
		state.resources[resource] = int(state.resources.get(resource, 0)) + carried
	else:
		# Clamp delivery to remaining need (delivered + reserved already
		# account for committed units).
		var reserved := int(build.get("reserved", {}).get(resource, 0))
		var cost := int(Constants.BUILD_COSTS[String(build.kind)][resource])
		var total_needed := cost - int(build.delivered.get(resource, 0)) - reserved
		var deliver := mini(carried, maxi(total_needed, 0))
		build.delivered[resource] = int(build.delivered.get(resource, 0)) + deliver
		# Refund excess back to stockpile
		var excess := carried - deliver
		if excess > 0:
			state.resources[resource] = int(state.resources.get(resource, 0)) + excess
		# Release reservation for the delivered amount
		if deliver > 0:
			build["reserved"] = build.get("reserved", {})
			build.reserved[resource] = maxi(reserved - deliver, 0)
			set_build(int(task.build_id), build)
	mark_dirty()
	worker.carrying[resource] = 0
	worker.task = {}


## Take one unit from the stockpile, reserve it for the build, and head there.
func _pick_up_for_build(worker: Dictionary, task: Dictionary, resource: String) -> void:
	var build := get_build(int(task.build_id))
	if build.is_empty() or bool(build.complete):
		# Build gone or complete — clear task, resource stays in stockpile
		worker.task = {}
		return
	state.resources[resource] = int(state.resources.get(resource, 0)) - 1
	worker.carrying[resource] = 1
	if not build.has("reserved"):
		build["reserved"] = {}
	build.reserved[resource] = int(build.reserved.get(resource, 0)) + 1
	mark_dirty()
	set_build(int(task.build_id), build)
	worker.task.target = build.pos


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
		push_event("%s finished. The colony looks slightly more legitimate." % String(build.kind).capitalize())
	set_build(int(task.build_id), build)
	mark_dirty()
	worker.task = {}


# ── Structures ────────────────────────────────────────────────────────────────

func apply_structure_bonus(kind: String) -> void:
	var bonus := int(BUILD_COMPLETION_FOOD.get(kind, 0))
	if bonus > 0:
		state.resources.food = int(state.resources.get("food", 0)) + bonus
		mark_dirty()


func structure_build_speed(kind: String) -> float:
	var speed := 0.34
	if kind != "workshop" and is_structure_complete("workshop"):
		speed += 0.16
	# Apply food-based slowdown (issue #147)
	speed *= get_food_slowdown_factor()
	# Apply goal reward build speed bonus
	speed += GoalReward.get_build_speed_bonus(state.get("active_rewards", []))
	return speed


func has_costs_delivered(build: Dictionary) -> bool:
	for resource in Constants.BUILD_COSTS[String(build.kind)].keys():
		if int(build.delivered.get(resource, 0)) < int(Constants.BUILD_COSTS[String(build.kind)][resource]):
			return false
	return true


func is_structure_unlocked(kind: String) -> bool:
	var unlock: Variant = Constants.BUILD_UNLOCKS.get(kind, true)
	if typeof(unlock) == TYPE_BOOL and bool(unlock):
		return true
	return is_structure_complete(String(unlock))


func is_structure_complete(kind: String) -> bool:
	for build in state.builds:
		if String(build.kind) == kind and bool(build.complete):
			return true
	return false


# ── Resource reservations (issue #122) ────────────────────────────────────────

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
	mark_dirty()


func get_reserved(resource: String) -> int:
	if not state.has("reserved_resources"):
		return 0
	return int(state.reserved_resources.get(resource, 0))


## Rebuild reserved_resources from active worker tasks. The single
## implementation both GameState (load path, trusts existing reservations)
## and the runtime (force rebuild) delegate to — static and autoload-free so
## the sim stays testable in --script mode.
static func rebuild_reservations_from_workers(target_state: Dictionary, trust_existing := true) -> void:
	if trust_existing:
		var existing: Dictionary = target_state.get("reserved_resources", {})
		if not existing.is_empty():
			return  # Already has reservations — trust them
	target_state["reserved_resources"] = {}
	for worker in target_state.get("workers", []):
		var task: Dictionary = worker.get("task", {})
		if task.is_empty():
			continue
		var kind: String = task.get("kind", "")
		if kind == "gather" or kind == "haul":
			var resource: String = task.get("resource", "")
			if not resource.is_empty():
				target_state["reserved_resources"][resource] = target_state["reserved_resources"].get(resource, 0) + 1


## Force a rebuild after a load, discarding whatever was saved.
func rebuild_reservations() -> void:
	rebuild_reservations_from_workers(state, false)


func _clean_stale_reservations() -> void:
	# Remove reservations from builds that have no active haul tasks targeting them.
	# This handles: build completion, build deletion, worker break/cleanup.
	var hauled_build_ids := {}
	for worker in state.workers:
		if not worker.task.is_empty() and String(worker.task.kind) == "haul":
			hauled_build_ids[int(worker.task.get("build_id", -1))] = true
	for build in state.builds:
		if bool(build.complete):
			continue
		if not hauled_build_ids.has(int(build.id)) and build.has("reserved"):
			var reserved: Dictionary = build.reserved
			for resource in reserved.keys():
				state.resources[resource] = int(state.resources.get(resource, 0)) + int(reserved[resource])
			build.erase("reserved")
			mark_dirty()


# ── Grid and build accessors ──────────────────────────────────────────────────

func get_tile(pos: Vector2i) -> Dictionary:
	return state.tiles[pos.y * grid_w + pos.x]


func set_tile(pos: Vector2i, data: Dictionary) -> void:
	state.tiles[pos.y * grid_w + pos.x] = data
	mark_dirty()


# id → array-index cache for build lookups (hot path: every haul/build step).
# Builds are append-only, so the index only needs rebuilding when the array
# size changes or the state dictionary was swapped wholesale — the entry
# verification below catches both.
var _build_index: Dictionary = {}

func _rebuild_build_index() -> void:
	_build_index.clear()
	var builds: Array = state.get("builds", [])
	for i in builds.size():
		_build_index[int(builds[i].id)] = i

func _build_array_index(id: int) -> int:
	var builds: Array = state.get("builds", [])
	if _build_index.size() != builds.size():
		_rebuild_build_index()
	var idx := int(_build_index.get(id, -1))
	if idx >= 0 and idx < builds.size() and int(builds[idx].id) == id:
		return idx
	# Stale (same-sized state swapped in) — rebuild once and retry.
	_rebuild_build_index()
	idx = int(_build_index.get(id, -1))
	if idx >= 0 and int(builds[idx].id) == id:
		return idx
	return -1


func get_build(id: int) -> Dictionary:
	var idx := _build_array_index(id)
	return state.builds[idx] if idx >= 0 else {}


func get_build_at_pos(pos: Vector2i) -> Dictionary:
	for build in state.builds:
		if data_to_vec(build.pos) == pos and not bool(build.complete):
			return build
	return {}


func set_build(id: int, updated: Dictionary) -> void:
	var idx := _build_array_index(id)
	if idx >= 0:
		state.builds[idx] = updated


func is_pos_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_w and pos.y >= 0 and pos.y < grid_h


func is_near_stockpile(pos: Vector2i) -> bool:
	return abs(pos.x - stockpile_pos.x) + abs(pos.y - stockpile_pos.y) <= 1


func find_open_ground() -> Vector2i:
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			if is_near_stockpile(pos):
				continue
			if String(get_tile(pos).kind) == "ground":
				return pos
	return Vector2i(-1, -1)


func seed_tile(pos: Vector2i) -> Dictionary:
	# Deterministic placement hash — the constants just spread resource tiles
	# pleasingly across the strip; tile contents come from RESOURCE_TILES.
	var key := int((pos.x * 13 + pos.y * 7 + pos.x * pos.y) % 14)
	var kind := ""
	if key == 0 or key == 3:
		kind = "tree"
	elif key == 6 or key == 8:
		kind = "rock"
	elif key == 11:
		kind = "berries"
	if kind.is_empty():
		return {"kind": "ground", "amount": 0, "resource": "", "build_kind": ""}
	var def: Dictionary = Constants.RESOURCE_TILES[kind]
	return {"kind": kind, "amount": def.seed_amount, "resource": def.resource, "build_kind": ""}


# ── Coordinate helpers ────────────────────────────────────────────────────────

static func data_to_vec(data: Variant) -> Vector2i:
	if data is Dictionary:
		return Vector2i(int(data.x), int(data.y))
	return Vector2i.ZERO


static func vec_to_data(pos: Vector2i) -> Dictionary:
	return {"x": pos.x, "y": pos.y}


static func step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	if from.x != to.x:
		return Vector2i(from.x + signi(to.x - from.x), from.y)
	if from.y != to.y:
		return Vector2i(from.x, from.y + signi(to.y - from.y))
	return from
