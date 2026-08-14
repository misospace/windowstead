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
# =============================================================================

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