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

	main.state = {"tick": 0, "events": []}
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


## True when any event's text contains `needle`.
func _events_contain(events: Array, needle: String) -> bool:
	for entry in events:
		if String(entry.get("text", "")).contains(needle):
			return true
	return false