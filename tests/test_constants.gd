## Regression tests for scripts/constants.gd.
## Tests that all extracted constants retain their exact values.
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_constants.gd

extends SceneTree

const C := preload("res://scripts/constants.gd")

func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0
	var test_count := 0

	# --- Worker names ---
	test_count += 1; pass_count += test("WORKER_NAMES has exactly 2 entries", _test_worker_names_count)
	test_count += 1; pass_count += test("WORKER_NAMES[0] is Jun", _test_worker_names_first)
	test_count += 1; pass_count += test("WORKER_NAMES[1] is Mara", _test_worker_names_second)

	# --- Timing constants ---
	test_count += 1; pass_count += test("BASE_TICK_SECONDS is 0.9", _test_base_tick_seconds)
	test_count += 1; pass_count += test("EVENT_INTERVAL_TICKS is 66", _test_event_interval_ticks)

	# --- Resource colors ---
	test_count += 1; pass_count += test("RESOURCE_COLORS has wood key", _test_resource_color_wood)
	test_count += 1; pass_count += test("RESOURCE_COLORS has stone key", _test_resource_color_stone)
	test_count += 1; pass_count += test("RESOURCE_COLORS has food key", _test_resource_color_food)
	test_count += 1; pass_count += test("RESOURCE_COLORS has exactly 3 entries", _test_resource_color_count)

	# --- Structure colors ---
	test_count += 1; pass_count += test("STRUCTURE_COLORS has hut key", _test_structure_color_hut)
	test_count += 1; pass_count += test("STRUCTURE_COLORS has workshop key", _test_structure_color_workshop)
	test_count += 1; pass_count += test("STRUCTURE_COLORS has garden key", _test_structure_color_garden)
	test_count += 1; pass_count += test("STRUCTURE_COLORS has exactly 3 entries", _test_structure_color_count)

	# --- Tile backdrops ---
	test_count += 1; pass_count += test("TILE_BACKDROPS has ground key", _test_tile_backdrop_ground)
	test_count += 1; pass_count += test("TILE_BACKDROPS has tree key", _test_tile_backdrop_tree)
	test_count += 1; pass_count += test("TILE_BACKDROPS has rock key", _test_tile_backdrop_rock)
	test_count += 1; pass_count += test("TILE_BACKDROPS has berries key", _test_tile_backdrop_berries)
	test_count += 1; pass_count += test("TILE_BACKDROPS has foundation key", _test_tile_backdrop_foundation)
	test_count += 1; pass_count += test("TILE_BACKDROPS has stockpile key", _test_tile_backdrop_stockpile)
	test_count += 1; pass_count += test("TILE_BACKDROPS has exactly 9 entries", _test_tile_backdrop_count)

	# --- Worker badge colors ---
	test_count += 1; pass_count += test("WORKER_BADGE_COLORS has Jun", _test_badge_color_jun)
	test_count += 1; pass_count += test("WORKER_BADGE_COLORS has Mara", _test_badge_color_mara)
	test_count += 1; pass_count += test("WORKER_BADGE_COLORS has exactly 2 entries", _test_badge_color_count)

	# --- Build costs ---
	test_count += 1; pass_count += test("BUILD_COSTS hut: 6 wood, 2 stone", _test_build_cost_hut)
	test_count += 1; pass_count += test("BUILD_COSTS workshop: 4 wood, 6 stone", _test_build_cost_workshop)
	test_count += 1; pass_count += test("BUILD_COSTS garden: 3 wood, 1 stone", _test_build_cost_garden)
	test_count += 1; pass_count += test("BUILD_COSTS has exactly 3 entries", _test_build_cost_count)

	# --- Build effects ---
	test_count += 1; pass_count += test("BUILD_EFFECTS hut describes housing support", _test_build_effect_hut)
	test_count += 1; pass_count += test("BUILD_EFFECTS workshop describes unlock/build speed", _test_build_effect_workshop)
	test_count += 1; pass_count += test("BUILD_EFFECTS garden describes food supply", _test_build_effect_garden)
	test_count += 1; pass_count += test("BUILD_EFFECTS has exactly 3 entries", _test_build_effect_count)

	# --- Build unlocks ---
	test_count += 1; pass_count += test("BUILD_UNLOCKS hut is true (unlocked)", _test_unlock_hut)
	test_count += 1; pass_count += test("BUILD_UNLOCKS workshop requires hut", _test_unlock_workshop)
	test_count += 1; pass_count += test("BUILD_UNLOCKS garden requires workshop", _test_unlock_garden)
	test_count += 1; pass_count += test("BUILD_UNLOCKS has exactly 3 entries", _test_unlock_count)

	# --- Consistency: all build costs have wood+stone ---
	test_count += 1; pass_count += test("All BUILD_COSTS entries have wood and stone keys", _test_build_costs_complete)
	test_count += 1; pass_count += test("All BUILD_COSTS entries have effect copy", _test_build_effects_complete)

	fail_count = test_count - pass_count
	print("\n=== Constants Regression Tests ===")
	print("Passed: %d" % pass_count)
	print("Failed: %d" % fail_count)

	if fail_count > 0:
		print("REGRESSION FAILURES DETECTED")
		quit(1)
	else:
		print("All constants regression tests passed.")
		quit(0)


func test(name: String, fn: Callable) -> int:
	var ok := true
	var error_msg := ""
	var result: Variant = fn.call()
	if result is Dictionary:
		ok = result.get("ok", false)
		error_msg = result.get("msg", "no detail")
	elif result == false:
		ok = false
		error_msg = "returned false"

	if ok:
		print("  ✓ %s" % name)
		return 1
	else:
		print("  ✗ %s: %s" % [name, error_msg])
		return 0


# --- Individual tests ---

func _test_worker_names_count() -> bool:
	return C.WORKER_NAMES.size() == 2

func _test_worker_names_first() -> bool:
	return C.WORKER_NAMES[0] == "Jun"

func _test_worker_names_second() -> bool:
	return C.WORKER_NAMES[1] == "Mara"

func _test_base_tick_seconds() -> bool:
	return is_equal_approx(C.BASE_TICK_SECONDS, 0.9)

func _test_event_interval_ticks() -> bool:
	return C.EVENT_INTERVAL_TICKS == 66

func _test_resource_color_wood() -> bool:
	return C.RESOURCE_COLORS.has("wood")

func _test_resource_color_stone() -> bool:
	return C.RESOURCE_COLORS.has("stone")

func _test_resource_color_food() -> bool:
	return C.RESOURCE_COLORS.has("food")

func _test_resource_color_count() -> bool:
	return C.RESOURCE_COLORS.size() == 3

func _test_structure_color_hut() -> bool:
	return C.STRUCTURE_COLORS.has("hut")

func _test_structure_color_workshop() -> bool:
	return C.STRUCTURE_COLORS.has("workshop")

func _test_structure_color_garden() -> bool:
	return C.STRUCTURE_COLORS.has("garden")

func _test_structure_color_count() -> bool:
	return C.STRUCTURE_COLORS.size() == 3

func _test_tile_backdrop_ground() -> bool:
	return C.TILE_BACKDROPS.has("ground")

func _test_tile_backdrop_tree() -> bool:
	return C.TILE_BACKDROPS.has("tree")

func _test_tile_backdrop_rock() -> bool:
	return C.TILE_BACKDROPS.has("rock")

func _test_tile_backdrop_berries() -> bool:
	return C.TILE_BACKDROPS.has("berries")

func _test_tile_backdrop_foundation() -> bool:
	return C.TILE_BACKDROPS.has("foundation")

func _test_tile_backdrop_stockpile() -> bool:
	return C.TILE_BACKDROPS.has("stockpile")

func _test_tile_backdrop_count() -> bool:
	return C.TILE_BACKDROPS.size() == 9

func _test_badge_color_jun() -> bool:
	return C.WORKER_BADGE_COLORS.has("Jun")

func _test_badge_color_mara() -> bool:
	return C.WORKER_BADGE_COLORS.has("Mara")

func _test_badge_color_count() -> bool:
	return C.WORKER_BADGE_COLORS.size() == 2

func _test_build_cost_hut() -> bool:
	var c = C.BUILD_COSTS.get("hut", {})
	return c.get("wood", -1) == 6 and c.get("stone", -1) == 2

func _test_build_cost_workshop() -> bool:
	var c = C.BUILD_COSTS.get("workshop", {})
	return c.get("wood", -1) == 4 and c.get("stone", -1) == 6

func _test_build_cost_garden() -> bool:
	var c = C.BUILD_COSTS.get("garden", {})
	return c.get("wood", -1) == 3 and c.get("stone", -1) == 1

func _test_build_cost_count() -> bool:
	return C.BUILD_COSTS.size() == 3

func _test_build_effect_hut() -> bool:
	return String(C.BUILD_EFFECTS.get("hut", "")).find("Housing") >= 0

func _test_build_effect_workshop() -> bool:
	var effect := String(C.BUILD_EFFECTS.get("workshop", ""))
	return effect.find("build speed") >= 0 and effect.find("garden") >= 0

func _test_build_effect_garden() -> bool:
	return String(C.BUILD_EFFECTS.get("garden", "")).find("food") >= 0

func _test_build_effect_count() -> bool:
	return C.BUILD_EFFECTS.size() == 3

func _test_unlock_hut() -> bool:
	return C.BUILD_UNLOCKS.get("hut") == true

func _test_unlock_workshop() -> bool:
	return C.BUILD_UNLOCKS.get("workshop") == "hut"

func _test_unlock_garden() -> bool:
	return C.BUILD_UNLOCKS.get("garden") == "workshop"

func _test_unlock_count() -> bool:
	return C.BUILD_UNLOCKS.size() == 3

func _test_build_costs_complete() -> bool:
	for kind in C.BUILD_COSTS.keys():
		if not C.BUILD_COSTS[kind].has("wood") or not C.BUILD_COSTS[kind].has("stone"):
			return false
	return true

func _test_build_effects_complete() -> bool:
	for kind in C.BUILD_COSTS.keys():
		if not C.BUILD_EFFECTS.has(kind) or String(C.BUILD_EFFECTS[kind]).is_empty():
			return false
	return true
