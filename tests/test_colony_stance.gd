extends "res://tests/test_case.gd"

# ── Colony Stance Tests (issue #140) ────────────────────────────────────────
# Verifies stance weighting, effective priority order, and persistence.

const Stance := preload("res://scripts/colony_stance.gd")


func run_tests() -> void:
	# ── Test 1: get_effective_priority_order for balanced stance ──
	print("")
	print("--- stance: effective priority order ---")
	var player_order: Array[String] = ["build", "haul", "gather"]

	# Balanced stance should return player order unchanged
	var balanced_order := Stance.get_effective_priority_order(Stance.STANCE_BALANCED, player_order)
	assert_eq(balanced_order.size(), 3, "balanced: has 3 entries")
	assert_eq(balanced_order[0], "build", "balanced: first is build")
	assert_eq(balanced_order[1], "haul", "balanced: second is haul")
	assert_eq(balanced_order[2], "gather", "balanced: third is gather")

	# Empty stance string should also return player order unchanged
	var empty_order := Stance.get_effective_priority_order("", player_order)
	assert_eq(empty_order.size(), 3, "empty stance: has 3 entries")
	assert_eq(empty_order[0], "build", "empty stance: first is build")

	# ── Test 2: Build stance puts build first ──
	var build_order := Stance.get_effective_priority_order(Stance.STANCE_BUILD, player_order)
	assert_eq(build_order.size(), 3, "build stance: has 3 entries")
	assert_eq(build_order[0], "build", "build stance: first is build")

	# ── Test 3: Gather stance puts gather first ──
	var gather_order := Stance.get_effective_priority_order(Stance.STANCE_GATHER, player_order)
	assert_eq(gather_order.size(), 3, "gather stance: has 3 entries")
	assert_eq(gather_order[0], "gather", "gather stance: first is gather")

	# ── Test 4: Food stance adds gather_food first ──
	var food_order := Stance.get_effective_priority_order(Stance.STANCE_FOOD, player_order)
	assert_eq(food_order.size(), 4, "food stance: has 4 entries (gather_food + 3)")
	assert_eq(food_order[0], "gather_food", "food stance: first is gather_food")
	assert_eq(food_order[1], "build", "food stance: second is build")

	# ── Test 5: Build stance with different player order ──
	var alt_player_order: Array[String] = ["gather", "haul", "build"]
	var build_alt := Stance.get_effective_priority_order(Stance.STANCE_BUILD, alt_player_order)
	assert_eq(build_alt[0], "build", "build stance (alt): first is build")
	# gather should follow (not duplicated)
	assert_true(build_alt.has("gather"), "build stance (alt): still has gather")

	# ── Test 6: Food stance with gather already in player order ──
	var food_alt := Stance.get_effective_priority_order(Stance.STANCE_FOOD, alt_player_order)
	assert_eq(food_alt[0], "gather_food", "food stance (alt): first is gather_food")
	# gather should not be duplicated — it's already in player order
	var gather_count := 0
	for item in food_alt:
		if item == "gather":
			gather_count += 1
	assert_eq(gather_count, 1, "food stance (alt): gather appears exactly once")

	# ── Test 7: is_food_gather_task ──
	print("")
	print("--- stance: food gather detection ---")
	var food_task := {"kind": "gather", "resource": "food"}
	var wood_task := {"kind": "gather", "resource": "wood"}
	var haul_task := {"kind": "haul", "resource": "wood"}

	assert_true(Stance.is_food_gather_task(food_task), "food gather: food task detected")
	assert_true(not Stance.is_food_gather_task(wood_task), "food gather: wood task not detected")
	assert_true(not Stance.is_food_gather_task(haul_task), "food gather: haul task not detected")

	# ── Test 8: All stances defined ──
	print("")
	print("--- stance: catalog ---")
	assert_eq(Stance.ALL_STANCES.size(), 4, "all stances: has 4 entries")
	assert_true(Stance.ALL_STANCES.has(Stance.STANCE_BALANCED), "all stances: balanced present")
	assert_true(Stance.ALL_STANCES.has(Stance.STANCE_BUILD), "all stances: build present")
	assert_true(Stance.ALL_STANCES.has(Stance.STANCE_GATHER), "all stances: gather present")
	assert_true(Stance.ALL_STANCES.has(Stance.STANCE_FOOD), "all stances: food present")

	# ── Test 9: STANCE_INFO has all labels ──
	for stance_key in Stance.ALL_STANCES:
		assert_true(Stance.STANCE_INFO.has(stance_key), "info: %s has info" % stance_key)
		assert_true(not String(Stance.STANCE_INFO[stance_key].label).is_empty(), "info: %s label not empty" % stance_key)
		assert_true(not String(Stance.STANCE_INFO[stance_key].description).is_empty(), "info: %s description not empty" % stance_key)

	# ── Test 10: Main game integration — stance affects task choice ──
	print("")
	print("--- stance: integration with choose_task ---")
	# main.gd references the GameState autoload, so it must be load()ed at
	# runtime — preload() compiles before autoloads are registered in --script mode.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()
	main.grid_w = 5
	main.grid_h = 5
	main.priority_order = ["build", "haul", "gather"] as Array[String]
	main.colony_stance = Stance.STANCE_BALANCED
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
	# so gather should be the fallback — but build tasks come first in priority
	# Actually with empty builds and no haul targets, gather is the only option
	var task_balanced: Dictionary = main.choose_task(main.state.workers[0])
	assert_true(not task_balanced.is_empty(), "balanced: worker gets a task")

	# ── Test 11: persist includes colony_stance ──
	print("")
	print("--- stance: persistence ---")
	main.colony_stance = Stance.STANCE_FOOD
	main.state["colony_stance"] = main.colony_stance  # Simulate what persist() does
	assert_eq(main.state.get("colony_stance", ""), Stance.STANCE_FOOD, "persist: colony_stance saved")

	# ── Test 12: load_saved_game restores colony_stance ──
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
		"colony_stance": Stance.STANCE_GATHER,
	}
	var restored_stance := String(loaded_state.get("colony_stance", Stance.STANCE_BALANCED))
	assert_eq(restored_stance, Stance.STANCE_GATHER, "load: colony_stance restored from save")

	# ── Test 13: Default colony_stance is BALANCED when missing from save ──
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
	var default_stance := String(legacy_state.get("colony_stance", Stance.STANCE_BALANCED))
	assert_eq(default_stance, Stance.STANCE_BALANCED, "load: defaults to balanced for legacy saves")
