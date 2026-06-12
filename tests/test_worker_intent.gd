## Tests for worker intent icons and text (issue #136).
## Verifies: icon/text mapping for all task kinds, idle reasons, break state.

extends SceneTree

const H := preload("res://tests/test_harness.gd")


func _initialize() -> void:
	# Preload and create GameState before creating Main.
	var game_state_script := load("res://scripts/game_state.gd")
	var game_state := game_state_script.new()
	root.add_child(game_state)

	# Load main.gd and create an instance (no UI nodes needed for logic tests)
	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()

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

	# Summary
	H.print_summary(H.pass + H.fail)


# ── Icon Tests ───────────────────────────────────────────────────────────────

func test_worker_intent_icon_gather_wood(main: Control) -> void:
	print("")
	print("--- icon: gather wood ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "wood"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_icon(worker), "🪓", "gather wood icon is 🪓")


func test_worker_intent_icon_gather_stone(main: Control) -> void:
	print("")
	print("--- icon: gather stone ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "stone"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_icon(worker), "⛏", "gather stone icon is ⛏")


func test_worker_intent_icon_gather_food(main: Control) -> void:
	print("")
	print("--- icon: gather food ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "food"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_icon(worker), "🫐", "gather food icon is 🫐")


func test_worker_intent_icon_haul(main: Control) -> void:
	print("")
	print("--- icon: haul ---")
	var worker := {"name": "Jun", "task": {"kind": "haul", "resource": "wood"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_icon(worker), "📦", "haul icon is 📦")


func test_worker_intent_icon_build_hut(main: Control) -> void:
	print("")
	print("--- icon: build hut ---")
	var worker := {"name": "Jun", "task": {"kind": "build", "build_kind": "hut"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_icon(worker), "🏗", "build hut icon is 🏗")


func test_worker_intent_icon_idle(main: Control) -> void:
	print("")
	print("--- icon: idle ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_icon(worker), "💤", "idle icon is 💤")


func test_worker_intent_icon_break(main: Control) -> void:
	print("")
	print("--- icon: break ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 5}
	H.assert_eq(main.worker_intent_icon(worker), "☕", "break icon is ☕")


# ── Text Tests ───────────────────────────────────────────────────────────────

func test_worker_intent_text_gather_wood(main: Control) -> void:
	print("")
	print("--- text: gather wood ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "wood"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_text(worker), "gathering wood", "gather wood text is correct")


func test_worker_intent_text_gather_stone(main: Control) -> void:
	print("")
	print("--- text: gather stone ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "stone"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_text(worker), "gathering stone", "gather stone text is correct")


func test_worker_intent_text_gather_food(main: Control) -> void:
	print("")
	print("--- text: gather food ---")
	var worker := {"name": "Jun", "task": {"kind": "gather", "resource": "food"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_text(worker), "gathering food", "gather food text is correct")


func test_worker_intent_text_haul_to_build(main: Control) -> void:
	print("")
	print("--- text: haul to build ---")
	var worker := {"name": "Jun", "task": {"kind": "haul", "resource": "wood", "build_id": 1}, "break_ticks": 0}
	main.state = {
		"builds": [{"id": 1, "kind": "hut", "complete": false}],
		"workers": [worker],
	}
	var text := main.worker_intent_text(worker)
	H.assert("hauling wood to hut" in text, "haul to build includes build kind")


func test_worker_intent_text_haul_to_stockpile(main: Control) -> void:
	print("")
	print("--- text: haul to stockpile ---")
	var worker := {"name": "Jun", "task": {"kind": "haul", "resource": "stone"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_text(worker), "hauling stone", "haul to stockpile text is correct")


func test_worker_intent_text_build_hut(main: Control) -> void:
	print("")
	print("--- text: build hut ---")
	var worker := {"name": "Jun", "task": {"kind": "build", "build_kind": "hut"}, "break_ticks": 0}
	H.assert_eq(main.worker_intent_text(worker), "building hut", "build hut text is correct")


func test_worker_intent_text_idle_no_task(main: Control) -> void:
	print("")
	print("--- text: idle no task ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	main.state = {
		"builds": [],
		"resources": {"wood": 0, "stone": 0, "food": 2},
	}
	var text := main.worker_intent_text(worker)
	H.assert("No valid task" in text, "idle with no builds shows 'No valid task'")


func test_worker_intent_text_break(main: Control) -> void:
	print("")
	print("--- text: break ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 3}
	H.assert_eq(main.worker_intent_text(worker), "on break", "break text is 'on break'")


# ── Idle Reason Tests ────────────────────────────────────────────────────────

func test_worker_idle_reason_no_task(main: Control) -> void:
	print("")
	print("--- idle reason: no task ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	main.state = {
		"builds": [],
		"resources": {"wood": 0, "stone": 0, "food": 2},
	}
	H.assert_eq(main.worker_idle_reason(worker), "idle_no_task", "no builds → idle_no_task")


func test_worker_idle_reason_food_priority(main: Control) -> void:
	print("")
	print("--- idle reason: food priority ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	main.state = {
		"builds": [],
		"resources": {"wood": 1, "stone": 1, "food": 2},
	}
	H.assert_eq(main.worker_idle_reason(worker), "idle_food_priority", "low food → idle_food_priority")


func test_worker_idle_reason_stockpile_full(main: Control) -> void:
	print("")
	print("--- idle reason: stockpile full ---")
	var worker := {"name": "Jun", "task": {}, "break_ticks": 0}
	main.state = {
		"builds": [{"id": 1, "kind": "hut", "complete": false}],
		"resources": {"wood": 100, "stone": 100},
	}
	H.assert_eq(main.worker_idle_reason(worker), "idle_stockpile_full", "build waiting for resources with full stockpile → idle_stockpile_full")


func test_worker_intent_icon_build_id_fallback(main: Control) -> void:
	print("")
	print("--- icon: build_id fallback ---")
	var worker := {"name": "Jun", "task": {"kind": "build", "build_id": 1}, "break_ticks": 0}
	main.state = {
		"builds": [{"id": 1, "kind": "hut", "complete": false}],
		"workers": [worker],
	}
	H.assert_eq(main.worker_intent_icon(worker), "🏗", "build_id fallback resolves to hut icon")
