extends "res://tests/test_case.gd"

# =============================================================================
# Tests for issue #331 — save failures must be reported, not swallowed.
#
# Covers:
#   1. _write_text_file returns false on an empty path
#   2. _write_text_file returns false on a null-byte path
#   3. _write_text_file returns false on an unwritable path
#   4. save_game returns false when the underlying write fails
#   5. save_game returns true when the underlying write succeeds
#   6. (issue #379) a second forced Save after a failed write re-attempts the
#      write instead of reporting success without saving
#   7. (issue #513) startup exit paths never write the empty state over the
#      existing save file
#   8. (issue #513) a colony created by the real bootstrap_state() path still
#      flushes on exit, even with the startup menu showing (game_active = false)
#   9. (issue #513 review) the load gate and the persist guard are both
#      type-strict on resources, so no save that loads can skip its exit flush
# =============================================================================

# Count of GameState.save_game invocations while a forced-failure hook is
# installed (Flow 6). A member (not a local) so the injected lambda can mutate
# it — a lambda captures `self`, not enclosing locals.
var _save_call_count := 0

func run_tests() -> void:
	# Autoloads are not running in --script mode — instantiate game_state.gd
	# manually (same pattern as test_save_backup.gd).
	var game_state_script := load("res://scripts/game_state.gd")
	var gs = game_state_script.new()
	root.add_child(gs)
	await process_frame

	flow_write_text_file_returns_false_for_empty_path(gs)
	flow_write_text_file_returns_false_for_unwritable_path(gs)
	flow_save_game_returns_false_when_write_fails(gs)
	flow_save_game_returns_true_on_successful_write(gs)
	flow_second_save_click_retries_after_failure()
	flow_startup_exit_never_touches_save()
	await flow_initialized_colony_flushes_on_exit()
	flow_both_guards_reject_non_dictionary_resources()


# ---------------------------------------------------------------------------
# Flow 1: empty path is rejected
# ---------------------------------------------------------------------------

func flow_write_text_file_returns_false_for_empty_path(gs: Node) -> void:
	print("\n=== Flow 1: _write_text_file rejects empty path ===")
	assert_eq(
		gs._write_text_file("", "{}"),
		false,
		"_write_text_file returns false for an empty path"
	)


# ---------------------------------------------------------------------------
# Flow 2: unwritable path is rejected
# ---------------------------------------------------------------------------

func flow_write_text_file_returns_false_for_unwritable_path(gs: Node) -> void:
	print("\n=== Flow 2: _write_text_file rejects unwritable path ===")
	assert_eq(
		gs._write_text_file("/this/path/does/not/exist/windowstead_save.json", "{}"),
		false,
		"_write_text_file returns false when FileAccess.open fails"
	)


# ---------------------------------------------------------------------------
# Flow 4: save_game reports a failed write
# ---------------------------------------------------------------------------

func flow_save_game_returns_false_when_write_fails(gs: Node) -> void:
	print("\n=== Flow 4: save_game returns false on failed write ===")
	var saved_local: bool = gs.use_local_storage
	gs.use_local_storage = false
	assert_eq(
		gs.save_game({"tick": 1}, "/this/path/does/not/exist/windowstead_save.json"),
		false,
		"save_game returns false when the underlying write fails"
	)
	gs.use_local_storage = saved_local


# ---------------------------------------------------------------------------
# Flow 5: save_game reports a successful write
# ---------------------------------------------------------------------------

func flow_save_game_returns_true_on_successful_write(gs: Node) -> void:
	print("\n=== Flow 5: save_game returns true on successful write ===")
	var saved_local: bool = gs.use_local_storage
	var tmp := "user://_windowstead_test_save_success.json"
	gs.use_local_storage = false
	assert_eq(
		gs.save_game({"tick": 1}, tmp),
		true,
		"save_game returns true when the underlying write succeeds"
	)
	# Clean up
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(tmp):
		dir.remove(tmp)
	gs.use_local_storage = saved_local


# ---------------------------------------------------------------------------
# Flow 6: (issue #379) a second forced Save after a failed write re-attempts
# the write instead of reporting success without saving.
#
# persist() used to clear sim.dirty *before* the write, so after a failed
# write a fast second Save click hit the `if not sim.dirty: return true`
# early-return and the caller pushed "Game saved" without writing. Now the
# dirty flag only clears on a successful write, so a forced save always
# re-invokes GameState.save_game.
# ---------------------------------------------------------------------------

func flow_second_save_click_retries_after_failure() -> void:
	print("\n=== Flow 6: second forced Save re-attempts after a failed write ===")
	# main.gd references the GameState autoload — load at runtime, not preload.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()
	# The GameState autoload is registered once the engine has booted, so
	# persist() writes through it. Force every write to fail and count calls.
	var gs: Node = root.get_node("GameState")
	_save_call_count = 0
	gs._save_game_hook = func(_data: Dictionary, _path: String) -> bool:
		_save_call_count += 1
		return false

	# Issue #513: persist() now skips writes without a persistable colony
	# shape, so the mock state must carry a resources dictionary.
	main.state = {"tick": 0, "resources": {}, "events": []}
	main._mark_dirty()

	# First explicit Save click: the write fails.
	var first: bool = main.persist(true)
	assert_false(first, "first forced persist returns false when the write fails")
	assert_eq(_save_call_count, 1, "first forced persist invoked GameState.save_game once")
	# The core fix: dirty must stay set so the next forced save re-attempts.
	assert_true(main.sim.dirty, "sim.dirty stays true after a failed write")

	# Second explicit Save click immediately after the failure. Before the fix
	# this hit the dirty-skip early-return and returned true (→ "Game saved").
	var second: bool = main.persist(true)
	assert_false(second, "second forced persist returns false (re-attempts, does not report success)")
	assert_eq(_save_call_count, 2, "second forced persist re-invoked GameState.save_game")
	assert_true(main.sim.dirty, "sim.dirty still true after the second failed write")

	# The success branch (the only place "Game saved" is pushed) must not have
	# fired for either click.
	assert_false(
		_events_contain(main.state.get("events", []), "Game saved"),
		"no 'Game saved' event was pushed after failed writes"
	)

	# Once the write succeeds, a forced persist clears the dirty flag.
	gs._save_game_hook = func(_data: Dictionary, _path: String) -> bool:
		_save_call_count += 1
		return true
	var recovered: bool = main.persist(true)
	assert_true(recovered, "forced persist returns true once the write succeeds")
	assert_false(main.sim.dirty, "sim.dirty clears on a successful write")

	# Restore the real save path for any later flow.
	gs._save_game_hook = Callable(gs, "_save_game_impl")
	main.free()


# ---------------------------------------------------------------------------
# Flow 7: (issue #513) at the startup menu the in-memory state is empty, and
# every exit path (desktop close, web unload, explicit quit) calls
# persist(true). None of them may write, or the empty state clobbers the
# existing save file.
# ---------------------------------------------------------------------------

func flow_startup_exit_never_touches_save() -> void:
	print("\n=== Flow 7: startup exit paths never touch the save ===")
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()
	var gs = root.get_node("GameState")

	# Part A: with the default empty state the guard must skip the write
	# entirely — the save hook is never invoked — and report success so the
	# quit paths stay quiet.
	_save_call_count = 0
	gs._save_game_hook = func(_data: Dictionary, _path: String) -> bool:
		_save_call_count += 1
		return false
	assert_false(
		main.has_persistable_colony(),
		"empty startup state is not persistable"
	)
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	main._flush_save_on_unload([])
	var quiet_skip: bool = main.persist(true)
	assert_true(quiet_skip, "persist(true) on empty state returns true (quiet skip)")
	assert_eq(_save_call_count, 0, "no save write happens on any startup exit path")

	# Part B: with an existing save file on disk (real write path, no hook),
	# the same three calls must leave the file untouched.
	gs._save_game_hook = Callable(gs, "_save_game_impl")
	var saved_local: bool = gs.use_local_storage
	gs.use_local_storage = false
	var save_path: String = gs.SAVE_PATH

	# Snapshot the pre-existing file (if any) so cleanup can restore it.
	var existed_before := FileAccess.file_exists(save_path)
	var prior_text := FileAccess.get_file_as_string(save_path) if existed_before else ""

	assert_true(gs.save_game({"marker": "keep-me"}), "sentinel save seeded")
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	main._flush_save_on_unload([])
	main.persist(true)
	var reloaded: Dictionary = gs.load_game()

	# Cleanup runs BEFORE the assertion: the sentinel overwrote the real
	# user:// slot, and a failure must not leave {"marker":"keep-me"}
	# behind as the player's save.
	if existed_before:
		var restore_file := FileAccess.open(save_path, FileAccess.WRITE)
		restore_file.store_string(prior_text)
		restore_file = null
	else:
		var dir := DirAccess.open("user://")
		if dir != null and dir.file_exists(save_path):
			dir.remove(save_path)
	gs.use_local_storage = saved_local

	assert_eq(
		String(reloaded.get("marker", "")),
		"keep-me",
		"startup exit paths left the existing save file intact"
	)

	# Restore the real save path for any later flow.
	gs._save_game_hook = Callable(gs, "_save_game_impl")
	main.free()


# ---------------------------------------------------------------------------
# Flow 8: (issue #513 acceptance #2) the skip is keyed on the state's shape,
# not on the game_active flag — returning to the startup menu must still
# flush a real colony on desktop close and on web unload.
#
# The colony comes from the production bootstrap_state() call — the same one
# New Game makes — driven through the real main.tscn scene (its _ready wires
# the UI nodes bootstrap_state touches). A hand-crafted state dictionary
# could drift from what bootstrap actually seeds and still pass; seeding
# through the real path proves a freshly started colony is persistable.
# ---------------------------------------------------------------------------

func flow_initialized_colony_flushes_on_exit() -> void:
	print("\n=== Flow 8: bootstrapped colony still flushes on exit ===")
	var gs = root.get_node("GameState")
	# The save hook intercepts every write, so the flow never touches the
	# player's save file on disk.
	_save_call_count = 0
	gs._save_game_hook = func(_data: Dictionary, _path: String) -> bool:
		_save_call_count += 1
		return true

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# The colony tick timer would interleave debounced writes with the
	# counted exit flushes below.
	main.tick_timer.stop()

	# The real New Game path (main.gd: bootstrap_state(); game_active = true).
	# bootstrap_state() seeds the colony and force-persists it once itself.
	main.bootstrap_state()
	main.game_active = true
	assert_true(
		main.state.get("resources", null) is Dictionary,
		"bootstrap_state() seeds a Dictionary resources"
	)
	assert_true(
		main.has_persistable_colony(),
		"a freshly bootstrapped colony passes has_persistable_colony()"
	)
	assert_true(
		main.is_save_compatible(main.state),
		"a freshly bootstrapped colony also clears the load compatibility gate"
	)
	var writes: int = _save_call_count
	assert_true(writes >= 1, "bootstrap_state() force-persists the new colony")

	# Desktop close flushes the bootstrapped colony.
	main._mark_dirty()
	main._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(_save_call_count, writes + 1, "desktop close flushes an initialized colony")

	# Startup menu showing (game_active = false) must not block the unload
	# flush: the guard keys on the state's resources dictionary, not the flag.
	main.game_active = false
	main._mark_dirty()
	main._flush_save_on_unload([])
	assert_eq(_save_call_count, writes + 2, "unload flush writes even with the startup menu showing")

	# An explicit forced persist goes through as well.
	var flushed: bool = main.persist(true)
	assert_true(flushed, "forced persist returns true for a persistable colony")
	assert_eq(_save_call_count, writes + 3, "forced persist invoked GameState.save_game once more")

	# The explicit Save button keeps its own has_persistable_colony() branch
	# (the "duplicate" the review flagged; now an early return) precisely
	# because persist() skips quietly with true: without it a Save click at
	# the startup menu would claim "Game saved" after a skipped write — and
	# re-render the colony UI from a bare state. Pin the contract on a TRUE
	# cold start (state == {}, no events array yet): save_game seeds one so
	# the notice reaches the event drawer (sim.push_event drops messages
	# without it), the skip message shows, no write happens, and "Game
	# saved" never fires.
	main.state = {}
	main.save_game()
	assert_eq(_save_call_count, writes + 3, "Save click on a skipped write performs no write")
	assert_false(
		main.has_persistable_colony(),
		"the events array seeded by the skip notice is not a persistable colony"
	)
	assert_true(
		_events_contain(main.state.get("events", []), "nothing to save"),
		"Save click with no persistable colony reports nothing to save"
	)
	assert_false(
		_events_contain(main.state.get("events", []), "Game saved"),
		"skipped Save click never claims 'Game saved'"
	)

	# Restore the real save path for any later flow.
	gs._save_game_hook = Callable(gs, "_save_game_impl")
	main.free()


# ---------------------------------------------------------------------------
# Flow 9: (issue #513 review) the persist guard skips writes for states whose
# resources value is not a Dictionary — so it must match the load gate's own
# strictness, or a legacy save with, say, resources = "wood" could load and
# then silently skip its exit flush. Both guards reject every non-Dictionary
# shape, including a missing key and an explicit null.
# ---------------------------------------------------------------------------

func flow_both_guards_reject_non_dictionary_resources() -> void:
	print("\n=== Flow 9: load gate and persist guard both reject non-Dictionary resources ===")
	var main_script: GDScript = load("res://scripts/main.gd")
	var main = main_script.new()

	# Load gate: the resources check runs before any geometry, so these save
	# shapes never need to be grid-valid.
	assert_false(
		main.is_save_compatible({"tiles": [], "workers": [], "builds": []}),
		"load gate rejects a save with no resources key"
	)
	for bad in ["wood", 7, [1, 2], null]:
		assert_false(
			main.is_save_compatible({"resources": bad, "tiles": [], "workers": [], "builds": []}),
			"load gate rejects resources of type %s" % type_string(typeof(bad))
		)

	# Persist guard: same strictness, so the two predicates accept exactly the
	# same state shape.
	for bad in ["wood", 7, [1, 2], null]:
		main.state = {"tick": 1, "resources": bad}
		assert_false(
			main.has_persistable_colony(),
			"persist guard rejects resources of type %s" % type_string(typeof(bad))
		)
	main.state = {"tick": 1}
	assert_false(main.has_persistable_colony(), "persist guard rejects a missing resources key")

	main.free()


## True when any event's text contains `needle`.
func _events_contain(events: Array, needle: String) -> bool:
	for entry in events:
		if String(entry.get("text", "")).contains(needle):
			return true
	return false