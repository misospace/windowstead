class_name ChooseTaskAI extends RefCounted

# Worker task-selection logic extracted from scripts/main.gd as part of
# the tech-debt refactor tracked by issue #243. All functions here are
# pure reads except for `choose_task`, which only mutates caller state
# by invoking the `reserve_resource` callable in the context bag.
#
# Callers construct the context dictionary once per selection pass. The
# context carries every variable the AI logic needs - most of them as
# plain Dictionary / Vector2i / String / Array references plus a small
# bag of Callables for methods that live on main.gd (or any other host
# script). This keeps the AI logic independent of main.gd and testable
# on its own.

const HARVESTABLE_KINDS := ["tree", "rock", "berries"]

const KIND_BUILD := "build"
const KIND_HAUL := "haul"
const KIND_GATHER := "gather"
const KIND_GATHER_FOOD := "gather_food"


# Builds a fresh context dictionary the ChooseTaskAI helpers expect.
# The Callables in `callable_names` are looked up as methods on `host`,
# so passing a fake/test object with the same methods works. Any extra
# `seed` entries (state, priority_order, build_costs, ...) are carried
# through unchanged.
static func make_ctx(
	host: Object,
	callable_names: PackedStringArray,
	seed: Dictionary,
) -> Dictionary:
	var ctx: Dictionary = seed.duplicate(true)
	for name in callable_names:
		ctx[name] = Callable(host, name)
	return ctx


# Chooses the next task for a worker, applying the colony stance and
# the configured priority order. When the dispatched kind is a gather
# task and food bias is active (or the kind itself is `gather_food`)
# tasks are sorted so food gathers come first and ties are broken by
# task distance. Otherwise tasks are picked by closest distance only.
# Returns an empty Dictionary when no task fits.
static func choose_task(worker: Dictionary, ctx: Dictionary) -> Dictionary:
	var priority_order: Array = ctx["priority_order"]
	var colony_stance: String = ctx["colony_stance"]
	var should_bias_food: Callable = ctx["should_bias_food"]
	var reserve_resource: Callable = ctx["reserve_resource"]

	var effective_order: Array = ColonyStance.get_effective_priority_order(colony_stance, priority_order)
	for kind in effective_order:
		var tasks: Array = tasks_for_kind(String(kind), ctx)
		if tasks.is_empty():
			continue
		# Bias toward food gathering when food is low (issue #147) or the
		# food stance has injected a gather_food task. Both paths share
		# the same food-first comparator because gather_gather_tasks()
		# emits kind="gather" tasks with a resource field, so
		# is_food_gather_task() works uniformly across them (issue
		# #245).
		if (String(kind) == KIND_GATHER and bool(should_bias_food.call())) or String(kind) == KIND_GATHER_FOOD:
			tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_is_food: bool = ColonyStance.is_food_gather_task(a)
				var b_is_food: bool = ColonyStance.is_food_gather_task(b)
				if a_is_food and not b_is_food:
					return true
				if not a_is_food and b_is_food:
					return false
				return task_distance(worker, a, ctx) < task_distance(worker, b, ctx))
		else:
			tasks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return task_distance(worker, a, ctx) < task_distance(worker, b, ctx))
		var chosen: Dictionary = tasks[0]
		if (String(chosen.kind) == KIND_GATHER or String(chosen.kind) == KIND_GATHER_FOOD) and chosen.has("resource"):
			reserve_resource.call(String(chosen.resource))
		return chosen
	return {}


# Dispatches to the gather helper for the given priority kind.
# Unknown kinds produce an empty array.
static func tasks_for_kind(kind: String, ctx: Dictionary) -> Array:
	match kind:
		KIND_BUILD:
			return gather_build_tasks(ctx)
		KIND_HAUL:
			return gather_haul_tasks(ctx)
		KIND_GATHER, KIND_GATHER_FOOD:
			return gather_gather_tasks(ctx)
	return []


# Manhattan distance between a worker and a task target. Pure (modulo
# the `data_to_vec` callable which is responsible for converting data
# positions to grid positions).
static func task_distance(worker: Dictionary, task: Dictionary, ctx: Dictionary) -> int:
	var data_to_vec: Callable = ctx["data_to_vec"]
	var pos: Vector2i = data_to_vec.call(worker.pos)
	var target: Vector2i = data_to_vec.call(task.target)
	return abs(pos.x - target.x) + abs(pos.y - target.y)


# In-progress builds whose materials have been fully delivered and so
# are ready for an assembly worker.
static func gather_build_tasks(ctx: Dictionary) -> Array:
	var state: Dictionary = ctx["state"]
	var has_costs_delivered: Callable = ctx["has_costs_delivered"]
	var tasks: Array = []
	for build in state.builds:
		if not bool(build.complete) and bool(has_costs_delivered.call(build)):
			tasks.append({"kind": KIND_BUILD, "build_id": int(build.id), "target": build.pos})
	return tasks


# Haul-tasks moving stock from the stockpile onto builds whose material
# needs are unmet. `stockpile_pos` is converted to data form via the
# supplied `vec_to_data` callable so the API matches the format used
# by the rest of the simulation.
static func gather_haul_tasks(ctx: Dictionary) -> Array:
	var state: Dictionary = ctx["state"]
	var build_costs: Dictionary = ctx["build_costs"]
	var vec_to_data: Callable = ctx["vec_to_data"]
	var stockpile_pos: Vector2i = ctx["stockpile_pos"]
	var tasks: Array = []
	for build in state.builds:
		if bool(build.complete):
			continue
		var reserved: Dictionary = build.get("reserved", {})
		for resource in build_costs[String(build.kind)].keys():
			var need: int = int(build_costs[String(build.kind)][resource]) - int(build.delivered.get(resource, 0)) - int(reserved.get(resource, 0))
			if need > 0 and int(state.resources.get(resource, 0)) > 0:
				tasks.append({
					"kind": KIND_HAUL,
					"build_id": int(build.id),
					"target": vec_to_data.call(stockpile_pos),
					"resource": String(resource),
				})
	return tasks


# Harvestable gather-tasks for every collectible resource on the map.
# Skips resources whose remaining supply is already fully reserved so
# we don't over-assign haulers.
static func gather_gather_tasks(ctx: Dictionary) -> Array:
	var get_tile: Callable = ctx["get_tile"]
	var get_reserved: Callable = ctx["get_reserved"]
	var vec_to_data: Callable = ctx["vec_to_data"]
	var grid_h: int = int(ctx["grid_h"])
	var grid_w: int = int(ctx["grid_w"])
	var tasks: Array = []
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			var tile: Dictionary = get_tile.call(pos)
			if HARVESTABLE_KINDS.has(String(tile.kind)) and int(tile.amount) > 0:
				var resource := String(tile.resource)
				var total_available := count_total_resource(resource, ctx)
				var reserved := int(get_reserved.call(resource))
				if reserved >= total_available:
					continue
				tasks.append({
					"kind": KIND_GATHER,
					"target": vec_to_data.call(pos),
					"resource": tile.resource,
				})
	return tasks


# Tile-amount sum for `resource` across the entire grid.
static func count_total_resource(resource: String, ctx: Dictionary) -> int:
	var get_tile: Callable = ctx["get_tile"]
	var grid_h: int = int(ctx["grid_h"])
	var grid_w: int = int(ctx["grid_w"])
	var total := 0
	for y in grid_h:
		for x in grid_w:
			var pos := Vector2i(x, y)
			var tile: Dictionary = get_tile.call(pos)
			if String(tile.resource) == resource and HARVESTABLE_KINDS.has(String(tile.kind)):
				total += int(tile.amount)
	return total
