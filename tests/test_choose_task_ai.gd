## Unit tests for scripts/choose_task_ai.gd — the worker-AI subsystem
## extracted from scripts/main.gd as part of the issue #243 refactor.
##
## Each test builds a fake host object that supplies the small set of
## callable dependencies the AI logic needs (data_to_vec / vec_to_data,
## get_tile / get_reserved, has_costs_delivered, should_bias_to_food_*
## and reserve_resource), then drives the public static functions of
## ChooseTaskAI directly through a context bag.
##
## Tests follow the same SceneTree-style convention as
## tests/test_food_bias_sort.gd: each test function returns true on
## pass and the runner counts and reports the result.
##
## Run: godot --headless --path . --script res://tests/test_choose_task_ai.gd

extends SceneTree

const CHOOSE_TASK_AI := preload("res://scripts/choose_task_ai.gd")


func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0
	var test_count := 0

	test_count += 1
	pass_count += _run("task_distance is Manhattan", _test_task_distance)
	test_count += 1
	pass_count += _run("count_total_resource sums matching tiles", _test_count_total_resource)
	test_count += 1
	pass_count += _run("gather_haul_tasks emits stock tasks", _test_gather_haul_tasks)
	test_count += 1
	pass_count += _run("gather_haul_tasks skips completed builds", _test_gather_haul_tasks_skips_completed)
	test_count += 1
	pass_count += _run("gather_build_tasks emits ready builds", _test_gather_build_tasks)
	test_count += 1
	pass_count += _run("tasks_for_kind dispatches every kind", _test_tasks_for_kind_dispatcher)
	test_count += 1
	pass_count += _run("choose_task picks build via priority_order", _test_choose_task_build)
	test_count += 1
	pass_count += _run("choose_task calls reserve_resource for gather", _test_choose_task_gather_reserves)
	test_count += 1
	pass_count += _run("choose_task returns {} when nothing fits", _test_choose_task_empty)

	fail_count = test_count - pass_count
	print("---")
	print("test_choose_task_ai: %d/%d passed" % [pass_count, test_count])
	if fail_count > 0:
		print("test_choose_task_ai: %d FAILED" % fail_count)
		quit(1)
	else:
		quit(0)


# ── harness ────────────────────────────────────────────────────────────────


func _run(name: String, callable: Callable) -> int:
	var ok: bool = callable.call(_new_host())
	if ok:
		print("  [PASS] %s" % name)
		return 1
	else:
		printerr("  [FAIL] %s" % name)
		return 0


func _new_host() -> Node:
	var host := Node.new()
	host.set("data_to_vec", func(data) -> Vector2i:
		if data is Vector2i:
			return data
		return Vector2i(int(data[0]), int(data[1]))
	)
	host.set("vec_to_data", func(vec: Vector2i) -> Array:
		return [vec.x, vec.y]
	)
	# Mutable state bag the tests can pre-populate.
	host.set("p_calls", {})
	return host


func _ctx(host: Node, state: Dictionary, priority_order: Array = [], opts := {}) -> Dictionary:
	var seed := {
		"state": state,
		"grid_w": state.get("grid_w", 0),
		"grid_h": state.get("grid_h", 0),
		"priority_order": priority_order,
		"colony_stance": opts.get("colony_stance", "balanced"),
		"build_costs": Constants.BUILD_COSTS,
		"stockpile_pos": opts.get("stockpile_pos", Vector2i(0, 0)),
	}
	return CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
	]), seed)


# `_assert` is a small mini-framework: returns the bool that `_run` uses,
# allows short-circuiting out of a test by `return`, and reports the
# failing assertion location.
var _had_failure := false


func _check(condition: bool, msg: String) -> void:
	if not condition:
		_had_failure = true
		printerr("    %s" % msg)


# ── tests ──────────────────────────────────────────────────────────────────


func _test_task_distance(host: Node) -> bool:
	_had_failure = false
	var ctx := _ctx(host, {}, [])
	var worker := {"pos": [1, 2]}
	var task := {"target": [4, 6]}
	_check(CHOOSE_TASK_AI.task_distance(worker, task, ctx) == 7, "task_distance Manhattan = 7")
	return not _had_failure


func _test_count_total_resource(host: Node) -> bool:
	_had_failure = false
	var tiles := {
		Vector2i(0, 0): {"kind": "tree", "resource": "wood", "amount": 5},
		Vector2i(1, 0): {"kind": "tree", "resource": "wood", "amount": 3},
		Vector2i(2, 0): {"kind": "berries", "resource": "food", "amount": 2},
	}
	var state := {"grid_w": 3, "grid_h": 1}
	host.set("get_tile", func(pos) -> Dictionary:
		if tiles.has(pos):
			return tiles[pos]
		return {"kind": "", "resource": "", "amount": 0}
	)
	var ctx := CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
		"get_tile",
	]), {"state": state, "grid_w": state.grid_w, "grid_h": state.grid_h})
	_check(CHOOSE_TASK_AI.count_total_resource("wood", ctx) == 8, "two tree tiles sum to 8")
	_check(CHOOSE_TASK_AI.count_total_resource("food", ctx) == 2, "food tile counted as food")
	_check(CHOOSE_TASK_AI.count_total_resource("stone", ctx) == 0, "no tiles have stone")
	return not _had_failure


func _test_gather_haul_tasks(host: Node) -> bool:
	_had_failure = false
	var state := {
		"builds": [
			{"id": 1, "kind": "shelter", "complete": false, "delivered": {"wood": 0}, "reserved": {"wood": 0}},
		],
		"resources": {"wood": 5},
	}
	var ctx := _ctx(host, state, [])
	ctx["stockpile_pos"] = Vector2i(2, 3)
	var tasks := CHOOSE_TASK_AI.gather_haul_tasks(ctx)
	_check(tasks.size() == 1, "exactly one haul task")
	_check(String(tasks[0].kind) == "haul", "kind=haul")
	_check(int(tasks[0].build_id) == 1, "build_id matches")
	_check(String(tasks[0].resource) == "wood", "resource matches")
	_check(tasks[0].target == [2, 3], "stockpile_pos vectorized via vec_to_data")
	return not _had_failure


func _test_gather_haul_tasks_skips_completed(host: Node) -> bool:
	_had_failure = false
	var state := {
		"builds": [
			{"id": 1, "kind": "shelter", "complete": true, "delivered": {}, "reserved": {}},
		],
		"resources": {"wood": 5},
	}
	var ctx := _ctx(host, state, [])
	_check(CHOOSE_TASK_AI.gather_haul_tasks(ctx).is_empty(), "completed builds filtered out")
	return not _had_failure


func _test_gather_build_tasks(host: Node) -> bool:
	_had_failure = false
	var state := {
		"builds": [
			{"id": 1, "kind": "shelter", "complete": false, "pos": [0, 0]},
			{"id": 2, "kind": "shelter", "complete": true, "pos": [1, 1]},
		],
	}
	host.set("has_costs_delivered", func(_b) -> bool: return true)
	var ctx := CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
		"has_costs_delivered",
	]), {"state": state, "grid_w": state.grid_w, "grid_h": state.grid_h})
	var tasks := CHOOSE_TASK_AI.gather_build_tasks(ctx)
	_check(tasks.size() == 1, "only unfinished build produces a task")
	if not tasks.is_empty():
		_check(int(tasks[0].build_id) == 1, "correct build_id")
		_check(String(tasks[0].kind) == "build", "kind=build")
	return not _had_failure


func _test_tasks_for_kind_dispatcher(host: Node) -> bool:
	_had_failure = false
	host.set("has_costs_delivered", func(_b) -> bool: return false)
	var state := {"builds": [], "resources": {}, "grid_w": 0, "grid_h": 0}
	var ctx := CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
		"has_costs_delivered",
	]), {
		"state": state,
		"grid_w": state.grid_w,
		"grid_h": state.grid_h,
		"build_costs": Constants.BUILD_COSTS,
		"stockpile_pos": Vector2i.ZERO,
	})
	_check(CHOOSE_TASK_AI.tasks_for_kind("build", ctx) == [], "build dispatched (empty)")
	_check(CHOOSE_TASK_AI.tasks_for_kind("haul", ctx) == [], "haul dispatched (empty)")
	_check(CHOOSE_TASK_AI.tasks_for_kind("gather", ctx) == [], "gather dispatched (empty)")
	_check(CHOOSE_TASK_AI.tasks_for_kind("gather_food", ctx) == [], "gather_food dispatched (empty)")
	_check(CHOOSE_TASK_AI.tasks_for_kind("__nope__", ctx) == [], "unknown kind returns empty")
	return not _had_failure


func _test_choose_task_build(host: Node) -> bool:
	_had_failure = false
	var state := {
		"builds": [
			{"id": 1, "kind": "shelter", "complete": false, "pos": [5, 5]},
		],
		"grid_w": 8, "grid_h": 8,
	}
	host.set("has_costs_delivered", func(_b) -> bool: return true)
	host.set("should_bias_to_food_gathering", func() -> bool: return false)
	var reserved_calls := {"n": 0}
	host.set("reserve_resource", func(_r) -> void:
		reserved_calls["n"] += 1
	)
	var ctx := CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
		"has_costs_delivered",
		"should_bias_to_food_gathering",
		"reserve_resource",
	]), {
		"state": state,
		"priority_order": ["build", "haul", "gather"],
		"colony_stance": "balanced",
		"build_costs": Constants.BUILD_COSTS,
		"stockpile_pos": Vector2i(0, 0),
	})
	var chosen := CHOOSE_TASK_AI.choose_task({"pos": [0, 0]}, ctx)
	_check(String(chosen.kind) == "build", "choose_task picks build")
	_check(int(chosen.build_id) == 1, "correct build chosen")
	_check(reserved_calls["n"] == 0, "build picks do not call reserve_resource")
	return not _had_failure


func _test_choose_task_gather_reserves(host: Node) -> bool:
	_had_failure = false
	var tiles := {Vector2i(0, 0): {"kind": "tree", "resource": "wood", "amount": 5}}
	var state := {"builds": [], "grid_w": 1, "grid_h": 1}
	host.set("get_tile", func(pos) -> Dictionary:
		if tiles.has(pos):
			return tiles[pos]
		return {"kind": "", "resource": "", "amount": 0}
	)
	host.set("get_reserved", func(_r) -> int: return 0)
	host.set("should_bias_to_food_gathering", func() -> bool: return false)
	var reserved_resources: Array = []
	host.set("reserve_resource", func(r) -> void:
		reserved_resources.append(String(r))
	)
	var ctx := CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
		"get_tile",
		"get_reserved",
		"should_bias_to_food_gathering",
		"reserve_resource",
	]), {
		"state": state,
		"priority_order": ["gather"],
		"colony_stance": "balanced",
		"build_costs": Constants.BUILD_COSTS,
		"stockpile_pos": Vector2i(0, 0),
	})
	var chosen := CHOOSE_TASK_AI.choose_task({"pos": [0, 0]}, ctx)
	_check(String(chosen.kind) == "gather", "choose_task picks gather when build unavailable")
	_check(reserved_resources.size() == 1, "reserve_resource called once")
	if reserved_resources.size() >= 1:
		_check(reserved_resources[0] == "wood", "wood resource reserved")
	return not _had_failure


func _test_choose_task_empty(host: Node) -> bool:
	_had_failure = false
	var state := {"builds": [], "grid_w": 1, "grid_h": 1}
	host.set("has_costs_delivered", func(_b) -> bool: return false)
	host.set("should_bias_to_food_gathering", func() -> bool: return false)
	host.set("reserve_resource", func(_r) -> void: pass)
	var ctx := CHOOSE_TASK_AI.make_ctx(host, PackedStringArray([
		"data_to_vec",
		"vec_to_data",
		"has_costs_delivered",
		"should_bias_to_food_gathering",
		"reserve_resource",
	]), {
		"state": state,
		"priority_order": ["build", "haul", "gather"],
		"colony_stance": "balanced",
		"build_costs": Constants.BUILD_COSTS,
		"stockpile_pos": Vector2i(0, 0),
	})
	_check(CHOOSE_TASK_AI.choose_task({"pos": [0, 0]}, ctx).is_empty(), "nothing to do -> {}")
	return not _had_failure
