extends "res://tests/test_case.gd"

# =============================================================================
# Tests for issue #519 — opening the popup menu (and other chrome-reachable
# render entry points) on the cold startup state must raise no SCRIPT ERROR.
#
# At the cold startup menu sim.state is {} (bootstrap_state() has not run),
# the startup panel is top_level so the dock chrome stays clickable, and the
# render path used to dot-access 'resources', 'events', and 'builds'
# unconditionally.
#
# Covers:
#   1. toggle_menu() on the empty startup state does not open the popup and
#      leaves state untouched (no stamping, no persistence of a colony that
#      never started).
#   2. The other chrome-reachable entry points — close_menu(),
#      toggle_event_drawer(), open_build_popup(), tile-hover render_tile(),
#      and render_all() itself — are no-ops on the empty state (the
#      SCRIPT ERROR rail on stderr catches any regression; test-all fails
#      the suite when the run logs one).
#   3. ColonySim.get_low_food_level()/is_structure_complete() tolerate the
#      empty state (gate + tolerate defense in depth).
#   4. With a bootstrapped (orientation-preview) state the popup open/close
#      path still renders normally — the gate must not swallow real colonies.
#
# The GameState autoload is loaded/instantiated the same way as
# test_save_load_gate.gd and test_save_failure_surfaced.gd.
# =============================================================================

func run_tests() -> void:
	# bootstrap_state() in Flow 4 persists; snapshot and restore the real
	# save so a local run cannot clobber a developer colony.
	const SAVE_PATH := "user://windowstead.save"
	var previous_save: Variant = _read_text(SAVE_PATH)
	var previous_save_existed := FileAccess.file_exists(SAVE_PATH)

	var game_state_script := load("res://scripts/game_state.gd")
	var game_state = game_state_script.new()
	root.add_child(game_state)
	await process_frame

	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Cold start: no colony, no ticking, no auto-persist.
	main.tick_timer.stop()

	flow_cold_toggle_menu_keeps_popup_closed(main)
	flow_cold_chrome_render_entry_points_are_safe(main)
	flow_colony_sim_helpers_tolerate_empty_state(main)
	flow_bootstrapped_state_still_opens_and_renders(main)

	_restore_user_data(SAVE_PATH, previous_save, previous_save_existed)
	main.queue_free()
	game_state.queue_free()


# ---------------------------------------------------------------------------
# Flow 1: cold menu click does not open the popup and does not touch state
# ---------------------------------------------------------------------------

func flow_cold_toggle_menu_keeps_popup_closed(main: Node) -> void:
	print("\n=== Flow 1: toggle_menu() on empty startup state ===")
	assert_true(main.state.is_empty(), "cold startup state is empty before the click")
	main.toggle_menu()
	assert_false(main.sidebar_scroll.visible, "popup does not open before a colony exists")
	assert_eq(int(main.menu_mode), int(main.MenuMode.CLOSED), "menu_mode stays CLOSED")
	assert_true(main.state.is_empty(), "state is still empty (no stamped keys)")


# ---------------------------------------------------------------------------
# Flow 2: remaining chrome-reachable entry points must not read
# colony-shaped keys off the empty state. Any dot-access regression prints
# "SCRIPT ERROR" to stderr and fails the suite via the test-all grep rail.
# ---------------------------------------------------------------------------

func flow_cold_chrome_render_entry_points_are_safe(main: Node) -> void:
	print("\n=== Flow 2: chrome entry points on empty state ===")
	main.close_menu()
	assert_true(main.state.is_empty(), "close_menu leaves the empty state alone")
	main.toggle_event_drawer()
	assert_true(main.state.is_empty(), "event drawer toggle leaves the empty state alone")
	main.render_all()
	assert_true(main.state.is_empty(), "render_all leaves the empty state alone")
	main.toggle_event_drawer()
	# Tile hover reaches render_tile() directly (no render_all gate); the
	# startup strip has tile panels, so this is the trivially reachable one.
	main.render_tile(0)
	main.render_tile(-1)
	assert_true(main.state.is_empty(), "tile hover render leaves the empty state alone")
	# build_mode_button is always-visible chrome; the management popup would
	# expose Place/Recruit on a colony that does not exist.
	main.open_build_popup()
	assert_false(main.sidebar_scroll.visible, "Build does not open the management popup before a colony exists")
	assert_eq(int(main.menu_mode), int(main.MenuMode.CLOSED), "menu_mode stays CLOSED for Build")
	assert_true(main.state.is_empty(), "open_build_popup leaves the empty state alone")


# ---------------------------------------------------------------------------
# Flow 3: ColonySim pure state readers tolerate the empty state
# ---------------------------------------------------------------------------

func flow_colony_sim_helpers_tolerate_empty_state(main: Node) -> void:
	print("\n=== Flow 3: ColonySim helpers on empty state ===")
	main.sim.state = {}
	assert_eq(main.sim.get_low_food_level(), "starving", "empty state reports starving food level")
	assert_true(main.sim.should_bias_to_food_gathering(), "bias check resolves (empty state reads as starving)")
	assert_false(main.sim.is_structure_complete("hut"), "nothing is complete with no builds")
	assert_true(main.sim.is_structure_unlocked("hut"), "always-unlocked kinds still resolve")


# ---------------------------------------------------------------------------
# Flow 4: after bootstrap_state() (orientation preview / real colony) the
# popup open path renders — the gate must not break working states
# ---------------------------------------------------------------------------

func flow_bootstrapped_state_still_opens_and_renders(main: Node) -> void:
	print("\n=== Flow 4: bootstrapped state opens and renders the popup ===")
	main.bootstrap_state()
	assert_false(main.state.is_empty(), "bootstrap_state() filled the state")
	main.toggle_menu()
	assert_true(main.sidebar_scroll.visible, "popup opens with a bootstrapped state")
	assert_eq(int(main.menu_mode), int(main.MenuMode.MENU), "menu_mode is MENU")
	assert_not_empty(main.resource_label.text, "header rendered the stockpile summary")
	main.close_menu()
	assert_false(main.sidebar_scroll.visible, "close_menu closes the popup")


## Returns the file's text ("" when absent), or null when it exists but
## cannot be opened — callers must then leave the file untouched rather
## than restore a blank over it.
func _read_text(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else null


func _restore_user_data(path: String, text: Variant, existed: bool) -> void:
	if text == null:
		return
	var dir := DirAccess.open("user://")
	if existed:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(String(text))
	elif dir != null and dir.file_exists(path):
		dir.remove(path)
