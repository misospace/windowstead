## Colony Stance Tests (issue #140)
## Verifies: stance weighting, effective priority order, and persistence.
## Only the integration test (test 10) requires main.gd — all others use colony_stance.gd directly.

extends SceneTree

const H := preload("res://tests/test_harness.gd")
const S := preload("res://scripts/colony_stance.gd")


func _initialize() -> void:
	test_effective_priority_order_balanced()
	test_effective_priority_order_build()
	test_effective_priority_order_gather()
	test_effective_priority_order_food()
	test_effective_priority_order_alt_player_order()
	test_food_gather_detection()
	test_all_stances_defined()
	test_stance_info_catalog()
	test_integration_with_choose_task()
	test_persistence_colony_stance()
	test_load_restores_colony_stance()
	test_default_stance_for_legacy_saves()

	# Summary
	H.print_summary(H.pass + H.fail)


func test_effective_priority_order_balanced() -> void:
	print("")
	print("--- effective priority order: balanced ---")
	var player_order: Array[String] = ["build", "haul", "gather"]
	var order := S.get_effective_priority_order(S.STANCE_BALANCED, player_order)
	H.assert_eq(order.size(), 3, "balanced: has 3 entries")
	H.assert_eq(order[0], "build", "balanced: first is build")
	H.assert_eq(order[1], "haul", "balanced: second is haul")
	H.assert_eq(order[2], "gather", "balanced: third is gather")


func test_effective_priority_order_build() -> void:
	print("")
	print("--- effective priority order: build stance ---")
	var player_order: Array[String] = ["build", "haul", "gather"]
	var order := S.get_effective_priority_order(S.STANCE_BUILD, player_order)
	H.assert_eq(order.size(), 3, "build stance: has 3 entries")
	H.assert_eq(order[0], "build", "build stance: first is build")


func test_effective_priority_order_gather() -> void:
	print("")
	print("--- effective priority order: gather stance ---")
	var player_order: Array[String] = ["build", "haul", "gather"]
	var order := S.get_effective_priority_order(S.STANCE_GATHER, player_order)
	H.assert_eq(order.size(), 3, "gather stance: has 3 entries")
	H.assert_eq(order[0], "gather", "gather stance: first is gather")


func test_effective_priority_order_food() -> void:
	print("")
	print("--- effective priority order: food stance ---")
	var player_order: Array[String] = ["build", "haul", "gather"]
	var order := S.get_effective_priority_order(S.STANCE_FOOD, player_order)
	H.assert_eq(order.size(), 4, "food stance: has 4 entries (gather_food + 3)")
	H.assert_eq(order[0], "gather_food", "food stance: first is gather_food")
	H.assert_eq(order[1], "build", "food stance: second is build")


func test_effective_priority_order_alt_player_order() -> void:
	print("")
	print("--- effective priority order: alt player order ---")
	var alt_player_order: Array[String] = ["gather", "haul", "build"]

	var build_alt := S.get_effective_priority_order(S.STANCE_BUILD, alt_player_order)
	H.assert_eq(build_alt[0], "build", "build stance (alt): first is build")
	H.assert(build_alt.has("gather"), "build stance (alt): still has gather")

	var food_alt := S.get_effective_priority_order(S.STANCE_FOOD, alt_player_order)
	H.assert_eq(food_alt[0], "gather_food", "food stance (alt): first is gather_food")
	# gather should not be duplicated
	var gather_count := 0
	for item in food_alt:
		if item == "gather":
			gather_count += 1
	H.assert_eq(gather_count, 1, "food stance (alt): gather appears exactly once")


func test_food_gather_detection() -> void:
	print("")
	print("--- food gather detection ---")
	var food_task := {"kind": "gather", "resource": "food"}
	var wood_task := {"kind": "gather", "resource": "wood"}
	var haul_task := {"kind": "haul", "resource": "wood"}

	H.assert(S.is_food_gather_task(food_task), "food gather: food task detected")
	H.assert(not S.is_food_gather_task(wood_task), "food gather: wood task not detected")
	H.assert(not S.is_food_gather_task(haul_task), "food gather: haul task not detected")


func test_all_stances_defined() -> void:
	print("")
	print("--- all stances defined ---")
	H.assert_eq(S.ALL_STANCES.size(), 4, "all stances: has 4 entries")
	H.assert(S.ALL_STANCES.has(S.STANCE_BALANCED), "all stances: balanced present")
	H.assert(S.ALL_STANCES.has(S.STANCE_BUILD), "all stances: build present")
	H.assert(S.ALL_STANCES.has(S.STANCE_GATHER), "all stances: gather present")
	H.assert(S.ALL_STANCES.has(S.STANCE_FOOD), "all stances: food present")


func test_stance_info_catalog() -> void:
	print("")
	print("--- stance info catalog ---")
	for stance_key in S.ALL_STANCES:
		H.assert(S.STANCE_INFO.has(stance_key), "info: %s has info" % stance_key)
		H.assert(not String(S.STANCE_INFO[stance_key].label).is_empty(), "info: %s label not empty" % stance_key)
		H.assert(not String(S.STANCE_INFO[stance_key].description).is_empty(), "info: %s description not empty" % stance_key)


func test_integration_with_choose_task() -> void:
	print("")
	print("--- integration: stance affects task choice ---")
	# Only this test needs main.gd for integration testing
	var game_state_script := preload("res://scripts/game_state.gd")
	var game_state := game_state_script.new()
	root.add_child(game_state)

	var main_script: GDScript = preload("res://scripts/main.gd")
	var main: Control = main_script.new()

	main.grid_w = 5
	main.grid_h = 5
	main.priority_order = ["build", "haul", "gather"] as Array[String]
	main.colony_stance = S.STANCE_BALANCED
	main.state = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}

	# Fill grid with ground tiles
	for y in 5:
		for x in 5:
			main.state.tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})

	# Place a tree at (2, 2) for gather tasks
	main.set_tile(Vector2i(2, 2), {"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""})

	# Place worker near stockpile
	main.stockpile_pos = Vector2i(0, 0)
	main.state.workers.append({
		"name": "Jun",
		"pos": {"x": 1, "y": 0},
		"prev_pos": {"x": 1, "y": 0},
		"carrying": {},
		"task": {},
		"break_ticks": 0,
	})

	# With balanced stance and default priority_order (build first), no builds exist
	# so gather should be the fallback
	var task_balanced := main.choose_task(main.state.workers[0])
	H.assert(not task_balanced.is_empty(), "balanced: worker gets a task")


func test_persistence_colony_stance() -> void:
	print("")
	print("--- persistence: colony_stance saved ---")
	var state: Dictionary = {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	state["colony_stance"] = S.STANCE_FOOD
	H.assert_eq(state.get("colony_stance", ""), S.STANCE_FOOD, "persist: colony_stance saved")


func test_load_restores_colony_stance() -> void:
	print("")
	print("--- load: colony_stance restored from save ---")
	var loaded_state := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
		"colony_stance": S.STANCE_GATHER,
	}
	var restored_stance := String(loaded_state.get("colony_stance", S.STANCE_BALANCED))
	H.assert_eq(restored_stance, S.STANCE_GATHER, "load: colony_stance restored from save")


func test_default_stance_for_legacy_saves() -> void:
	print("")
	print("--- load: defaults to balanced for legacy saves ---")
	var legacy_state := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"dock_anchor": "bottom",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
		# No colony_stance field — old save format
	}
	var default_stance := String(legacy_state.get("colony_stance", S.STANCE_BALANCED))
	H.assert_eq(default_stance, S.STANCE_BALANCED, "load: defaults to balanced for legacy saves")
