extends "res://tests/test_case.gd"

## Tests for worker intent icons and text (issue #136).
## Verifies: icon/text mapping for all task kinds, idle reasons, break state.


func run_tests() -> void:
	# main.gd references the GameState autoload, so it must be load()ed at
	# runtime — preload() compiles before autoloads are registered in --script mode.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()

	test_worker_intent_icon_gather_wood(main)
	test_worker_intent_icon_gather_stone(main)
	test_worker_intent_icon_gather_food(main)
	test_worker_intent_icon_haul(main)
	test_worker_intent_icon_build_hut(main)
	test_worker_intent_icon_idle(main)
	test_worker_intent_icon_break(main)
	test_worker_intent_text_gather_wood(main)
	test_worker_intent_text_gather_stone(main)
	test_worker_intent_text_gather_food(main)
	test_worker_intent_text_haul_to_build(main)
	test_worker_intent_text_haul_to_stockpile(main)
	test_worker_intent_text_build_hut(main)
	test_worker_intent_text_idle_no_task(main)
	test_worker_intent_text_break(main)
	test_worker_idle_reason_no_task(main)
	test_worker_idle_reason_food_priority(main)
	test_worker_idle_reason_stockpile_full(main)
	test_worker_intent_icon_build_id_fallback(main)

	main.free()


# ── Icon Tests ───────────────────────────────────────────────────────────────

func test_worker_intent_icon_gather_wood(main) -> void:
	print("")
	print("--- icon: gather wood ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "wood"}, "break_ticks": 0}
	assert_eq(main.worker_intent_icon(worker), "🪓", "gather wood icon is 🪓")


func test_worker_intent_icon_gather_stone(main) -> void:
	print("")
	print("--- icon: gather stone ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "stone"}, "break_ticks": 0}
	assert_eq(main.worker_intent_icon(worker), "⛏", "gather stone icon is ⛏")


func test_worker_intent_icon_gather_food(main) -> void:
	print("")
	print("--- icon: gather food ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "food"}, "break_ticks": 0}
	assert_eq(main.worker_intent_icon(worker), "🫐", "gather food icon is 🫐")


func test_worker_intent_icon_haul(main) -> void:
	print("")
	print("--- icon: haul ---")
	var worker := {"name": "Jun", "task": {"kind": "haul", "resource": "wood"}, "break_ticks": 0}
	assert_eq(main.worker_intent_icon(worker), "📦", "haul icon is 📦")


func test_worker_intent_icon_build_hut(main) -> void:
	print("")
	print("--- icon: build hut ---")
	var worker := {"name": "Jun", "task": {"kind": "build", "build_kind": "hut"}, "break_ticks": 0}
	assert_eq(main.worker_intent_icon(worker), "🏗", "build hut icon is 🏗")


func test_worker_intent_icon_idle(main) -> void:
	print("")
	print("--- icon: idle ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	assert_eq(main.worker_intent_icon(worker), "💤", "idle icon is 💤")


func test_worker_intent_icon_break(main) -> void:
	print("")
	print("--- icon: break ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 5}
	assert_eq(main.worker_intent_icon(worker), "☕", "break icon is ☕")


# ── Text Tests ───────────────────────────────────────────────────────────────

func test_worker_intent_text_gather_wood(main) -> void:
	print("")
	print("--- text: gather wood ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "wood"}, "break_ticks": 0}
	assert_eq(main.worker_intent_text(worker), "gathering wood", "gather wood text is correct")


func test_worker_intent_text_gather_stone(main) -> void:
	print("")
	print("--- text: gather stone ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "stone"}, "break_ticks": 0}
	assert_eq(main.worker_intent_text(worker), "gathering stone", "gather stone text is correct")


func test_worker_intent_text_gather_food(main) -> void:
	print("")
	print("--- text: gather food ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "food"}, "break_ticks": 0}
	assert_eq(main.worker_intent_text(worker), "gathering food", "gather food text is correct")


func test_worker_intent_text_haul_to_build(main) -> void:
	print("")
	print("--- text: haul to build ---")
	var worker := {"name": "Jun", "task": {"kind": "haul", "resource": "wood", "build_id": 1}, "break_ticks": 0}
	main.state = {
		"builds": [{"id": 1, "kind": "hut", "complete": false}],
		"workers": [worker],
	}
	var text: String = main.worker_intent_text(worker)
	assert_true("hauling wood to hut" in text, "haul to build includes build kind")


func test_worker_intent_text_haul_to_stockpile(main) -> void:
	print("")
	print("--- text: haul to stockpile ---")
	var worker := {"name": "Jun", "task": {"kind": "haul", "resource": "stone"}, "break_ticks": 0}
	assert_eq(main.worker_intent_text(worker), "hauling stone", "haul to stockpile text is correct")


func test_worker_intent_text_build_hut(main) -> void:
	print("")
	print("--- text: build hut ---")
	var worker := {"name": "Jun", "task": {"kind": "build", "build_kind": "hut"}, "break_ticks": 0}
	assert_eq(main.worker_intent_text(worker), "building hut", "build hut text is correct")


func test_worker_intent_text_idle_no_task(main) -> void:
	print("")
	print("--- text: idle no task ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	# food must be above LOW_FOOD_THRESHOLD (3) or the food-priority idle reason wins.
	main.state = {
		"builds": [],
		"resources": {"wood": 0, "stone": 0, "food": 5},
	}
	var text: String = main.worker_intent_text(worker)
	assert_true("No valid task" in text, "idle with no builds shows 'No valid task'")


func test_worker_intent_text_break(main) -> void:
	print("")
	print("--- text: break ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 3}
	assert_eq(main.worker_intent_text(worker), "on break", "break text is 'on break'")


# ── Idle Reason Tests ────────────────────────────────────────────────────────

func test_worker_idle_reason_no_task(main) -> void:
	print("")
	print("--- idle reason: no task ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	# food must be above LOW_FOOD_THRESHOLD (3) or the food-priority idle reason wins.
	main.state = {
		"builds": [],
		"resources": {"wood": 0, "stone": 0, "food": 5},
	}
	assert_eq(main.worker_idle_reason(worker), "idle_no_task", "no builds → idle_no_task")


func test_worker_idle_reason_food_priority(main) -> void:
	print("")
	print("--- idle reason: food priority ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	main.state = {
		"builds": [],
		"resources": {"wood": 1, "stone": 1, "food": 2},
	}
	# food=2 <= LOW_FOOD_THRESHOLD (3), so should_bias_to_food_gathering() → true
	assert_eq(main.worker_idle_reason(worker), "idle_food_priority", "low food → idle_food_priority")


func test_worker_idle_reason_stockpile_full(main) -> void:
	print("")
	print("--- idle reason: stockpile full ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	main.state = {
		"builds": [{"id": 1, "kind": "hut", "complete": false, "delivered": {}}],
		"resources": {"wood": 100, "stone": 100},
	}
	# Build needs wood+stone, both are available and delivered=0, so has_pending_haul=true
	# All costs resources > 0 → stockpile_full=true
	assert_eq(main.worker_idle_reason(worker), "idle_stockpile_full", "build waiting for resources with full stockpile → idle_stockpile_full")


func test_worker_intent_icon_build_id_fallback(main) -> void:
	print("")
	print("--- icon: build_id fallback ---")
	var worker := {"name": "Jun", "task": {"kind": "build", "build_id": 1}, "break_ticks": 0}
	main.state = {
		"builds": [{"id": 1, "kind": "hut", "complete": false}],
		"workers": [worker],
	}
	assert_eq(main.worker_intent_icon(worker), "🏗", "build_id fallback resolves to hut icon")
