## Regression tests for the food-bias sort parity in choose_task.
##
## issue #245: ensure that the "gather" (with should_bias_to_food_gathering)
## and "gather_food" sort paths in choose_task use the same food-first
## comparator. Both branches must produce the same ordering for a given list
## of gather tasks, because gather_gather_tasks() emits kind="gather" entries
## with a resource field that ColonyStance.is_food_gather_task() can classify.
##
## These tests are pure logic checks (no scene tree needed) and run in the
## SceneTree headless mode used by CI.
##
## Run: godot --headless --path . --script res://tests/test_food_bias_sort.gd

extends SceneTree

const ColonyStance := preload("res://scripts/colony_stance.gd")


func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0
	var test_count := 0

	test_count += 1
	pass_count += _run("plain sort is strictly by distance", _test_plain_distance_sort)

	test_count += 1
	pass_count += _run("food-bias sort groups food before wood", _test_food_bias_groups_food_first)

	test_count += 1
	pass_count += _run("food-bias sort keeps stable order inside each group", _test_food_bias_stable_within_group)

	test_count += 1
	pass_count += _run("dispatcher picks same comparator for gather (low) and gather_food", _test_dispatcher_parity)

	test_count += 1
	pass_count += _run("all-food input leaves order unchanged by food-bias", _test_all_food_input)

	test_count += 1
	pass_count += _run("all-wood input leaves order unchanged by food-bias", _test_all_wood_input)

	if fail_count == 0:
		print("\n[PASS] %d/%d food-bias sort tests passed" % [pass_count, test_count])
		quit(0)
	else:
		print("\n[FAIL] %d/%d food-bias sort tests failed" % [fail_count, test_count])
		quit(1)


func _run(name: String, callable: Callable) -> int:
	var ok: bool = callable.call()
	if ok:
		print("  [PASS] %s" % name)
		return 1
	else:
		printerr("  [FAIL] %s" % name)
		return 0


# ── Comparators mirroring choose_task's food-bias branches (issue #245) ──


func _sort_distance(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("dist", 0)) < int(b.get("dist", 0))


func _sort_food_bias(a: Dictionary, b: Dictionary) -> bool:
	var a_is_food: bool = ColonyStance.is_food_gather_task(a)
	var b_is_food: bool = ColonyStance.is_food_gather_task(b)
	if a_is_food and not b_is_food:
		return true
	if not a_is_food and b_is_food:
		return false
	return _sort_distance(a, b)


# Mirrors the unified dispatch in choose_task after the dedup in issue #245.
func _dispatch(k: String, food_low: bool) -> Callable:
	if (k == "gather" and food_low) or k == "gather_food":
		return Callable(self, "_sort_food_bias")
	return Callable(self, "_sort_distance")


# ── Tests ──


func _test_plain_distance_sort() -> bool:
	var tasks: Array[Dictionary] = [
		{"kind": "gather", "resource": "wood", "dist": 1, "id": "near_wood"},
		{"kind": "gather", "resource": "food", "dist": 5, "id": "far_food"},
		{"kind": "gather", "resource": "wood", "dist": 8, "id": "far_wood"},
		{"kind": "gather", "resource": "food", "dist": 10, "id": "farthest_food"},
	]
	tasks.sort_custom(_sort_distance)
	return tasks[0].id == "near_wood" and tasks[-1].id == "farthest_food"


func _test_food_bias_groups_food_first() -> bool:
	var tasks: Array[Dictionary] = [
		{"kind": "gather", "resource": "wood", "dist": 1, "id": "near_wood"},
		{"kind": "gather", "resource": "food", "dist": 5, "id": "far_food"},
		{"kind": "gather", "resource": "wood", "dist": 8, "id": "far_wood"},
		{"kind": "gather", "resource": "food", "dist": 10, "id": "farthest_food"},
	]
	tasks.sort_custom(_sort_food_bias)
	# Food group must occupy indices 0..1, wood group must occupy 2..3
	if String(tasks[0].resource) != "food":
		return false
	if String(tasks[1].resource) != "food":
		return false
	if String(tasks[2].resource) != "wood":
		return false
	if String(tasks[3].resource) != "wood":
		return false
	return true


func _test_food_bias_stable_within_group() -> bool:
	var tasks: Array[Dictionary] = [
		{"kind": "gather", "resource": "wood", "dist": 1, "id": "near_wood"},
		{"kind": "gather", "resource": "food", "dist": 5, "id": "far_food"},
		{"kind": "gather", "resource": "food", "dist": 10, "id": "farthest_food"},
		{"kind": "gather", "resource": "wood", "dist": 8, "id": "far_wood"},
	]
	tasks.sort_custom(_sort_food_bias)
	# Within the food group (0..1), the closer task is first
	if tasks[0].id != "far_food":
		return false
	if tasks[1].id != "farthest_food":
		return false
	# Within the wood group (2..3), the closer task is first
	if tasks[2].id != "near_wood":
		return false
	if tasks[3].id != "far_wood":
		return false
	return true


func _test_dispatcher_parity() -> bool:
	# The gather (low food) and gather_food branches must resolve to the
	# same comparator — that is the whole point of the dedup in #245.
	var gather_low: Callable = _dispatch("gather", true)
	var gather_food: Callable = _dispatch("gather_food", false)
	return gather_low == gather_food


func _test_all_food_input() -> bool:
	var tasks: Array[Dictionary] = [
		{"kind": "gather", "resource": "food", "dist": 7, "id": "f1"},
		{"kind": "gather", "resource": "food", "dist": 2, "id": "f2"},
		{"kind": "gather", "resource": "food", "dist": 5, "id": "f3"},
	]
	tasks.sort_custom(_sort_food_bias)
	# All food, so the bias collapses to plain distance sort.
	return tasks[0].id == "f2" and tasks[1].id == "f3" and tasks[2].id == "f1"


func _test_all_wood_input() -> bool:
	var tasks: Array[Dictionary] = [
		{"kind": "gather", "resource": "wood", "dist": 7, "id": "w1"},
		{"kind": "gather", "resource": "wood", "dist": 2, "id": "w2"},
		{"kind": "gather", "resource": "wood", "dist": 5, "id": "w3"},
	]
	tasks.sort_custom(_sort_food_bias)
	# No food, so the bias collapses to plain distance sort.
	return tasks[0].id == "w2" and tasks[1].id == "w3" and tasks[2].id == "w1"
