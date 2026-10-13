extends "res://tests/test_case.gd"

# =============================================================================
# Tests for issue #409 — save_settings must surface the underlying write
# result instead of swallowing it.
#
# Background: GameState.save_settings() used to discard the bool returned by
# the web (localStorage) writer on the JavaScriptBridge path and by the
# desktop FileAccess writer. A quota/security error on the web branch or a
# disk-full / permission-denied on the desktop branch went silent, so the
# caller could not retry or announce. The fix is to return the bool.
#
# These tests verify the contract on both branches plus the
# main.gd-side wrapper:
#   - desktop success returns true
#   - desktop failure (unwritable path) returns false
#   - web success returns true
#   - web failure (stubbed writer returns false) returns false
#   - main.gd:save_settings() returns the GameState bool
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node
var _prior_use_local_storage: bool = false
var _prior_writer: Callable

func run_tests() -> void:
	setup()
	flow_desktop_save_settings_returns_true_on_success()
	flow_desktop_save_settings_returns_false_on_bad_path()
	flow_web_save_settings_returns_true_on_success()
	flow_web_save_settings_returns_false_when_writer_fails()
	flow_main_save_settings_propagates_game_state_result()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	_prior_use_local_storage = _gs.use_local_storage
	_prior_writer = _gs._local_storage_writer

func teardown() -> void:
	if _gs and is_instance_valid(_gs):
		_gs.use_local_storage = _prior_use_local_storage
		_gs._local_storage_writer = _prior_writer
		_gs.queue_free()
	_gs = null

# Desktop branch: write to a valid path → save_settings returns true.
func flow_desktop_save_settings_returns_true_on_success() -> void:
	print("\n=== Flow: desktop save_settings returns true on success ===")
	_gs.use_local_storage = false
	var tmp := "user://_windowstead_test_settings_success.json"
	var result: bool = _gs.save_settings({"dock_anchor": "bottom"})
	assert_eq(result, true, "desktop save_settings returns true on a successful write")
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(tmp):
		dir.remove(tmp)

# Desktop branch: write to a path occupied by a directory → save_settings
# returns false. Before the fix this code path went silent (function
# returned void) so a disk-full / permission-denied was invisible to
# callers. We force the failure by replacing the settings file with a
# directory of the same name; FileAccess.open(..., WRITE) then returns
# null and _write_text_file reports failure, mirroring an unwritable
# filesystem.
func flow_desktop_save_settings_returns_false_on_bad_path() -> void:
	print("\n=== Flow: desktop save_settings returns false when SETTINGS_PATH is unwritable ===")
	_gs.use_local_storage = false
	var saved_path := ""
	var dir := DirAccess.open("user://")
	if dir and dir.file_exists("windowstead.settings"):
		# Read the existing file so we can restore it after the test.
		var existing := FileAccess.open("user://windowstead.settings", FileAccess.READ)
		if existing:
			saved_path = existing.get_as_text()
			existing.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://windowstead.settings"))
	# Place a directory at the path so FileAccess.open(..., WRITE) fails.
	if dir:
		dir.make_dir_recursive("windowstead.settings")
	var result: bool = _gs.save_settings({"tick_speed": 3})
	assert_eq(result, false, "save_settings returns false when the desktop writer fails")
	assert_eq(typeof(result), TYPE_BOOL, "save_settings always returns a bool on the desktop branch")
	# Restore the desktop file we displaced so other tests / runs see a
	# clean user:// state.
	if dir:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://windowstead.settings"))
		if not saved_path.is_empty():
			var restore := FileAccess.open("user://windowstead.settings", FileAccess.WRITE)
			if restore:
				restore.store_string(saved_path)
				restore.close()

# Web branch: stub the writer to succeed → save_settings returns true.
func flow_web_save_settings_returns_true_on_success() -> void:
	print("\n=== Flow: web save_settings returns true on success ===")
	_gs.use_local_storage = true
	_gs._local_storage_writer = func(_key: String, _payload: String) -> bool:
		return true
	var result: bool = _gs.save_settings({"dock_anchor": "left"})
	assert_eq(result, true, "web save_settings returns true when the writer returns true")

# Web branch: stub the writer to fail → save_settings returns false.
# This is the regression: a quota/security failure must be surfaced, not
# swallowed. Before issue #409 the bool was discarded and the caller could
# not detect the failure.
func flow_web_save_settings_returns_false_when_writer_fails() -> void:
	print("\n=== Flow: web save_settings returns false when the writer fails ===")
	_gs.use_local_storage = true
	_gs._local_storage_writer = func(_key: String, _payload: String) -> bool:
		return false
	var result: bool = _gs.save_settings({"dock_anchor": "right"})
	assert_eq(result, false, "web save_settings returns false when the writer returns false")

# main.gd's save_settings() wrapper must propagate the GameState bool so
# callers (future retry/announce wiring) can branch on the result. The
# main.gd lookup resolves to the GameState autoload, so we patch the
# autoload (root.get_node("GameState")) rather than the isolated test
# instance.
func flow_main_save_settings_propagates_game_state_result() -> void:
	print("\n=== Flow: main.gd save_settings() returns the GameState bool ===")
	var autoload_gs: Node = root.get_node("GameState")
	var prev_use_ls: bool = autoload_gs.use_local_storage
	var prev_writer: Callable = autoload_gs._local_storage_writer

	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()
	main.settings = {"dock_anchor": "bottom", "tick_speed": 1}
	# The dock slider and tick-speed slider are read inside the wrapper;
	# stub minimal stand-ins so the wrapper runs without UI.
	var dock_option := OptionButton.new()
	for anchor in main.DOCK_OPTIONS:
		dock_option.add_item(anchor)
	main.dock_side_option = dock_option
	main.tick_speed_slider = HSlider.new()

	# Force the autoload's GameState write to fail and verify the wrapper
	# propagates false instead of swallowing it like the old void return did.
	autoload_gs.use_local_storage = true
	autoload_gs._local_storage_writer = func(_key: String, _payload: String) -> bool:
		return false
	var failed: bool = main.save_settings()
	assert_eq(failed, false, "main.save_settings() returns false when GameState fails")

	# Success path — propagating true through the wrapper.
	autoload_gs._local_storage_writer = func(_key: String, _payload: String) -> bool:
		return true
	var ok: bool = main.save_settings()
	assert_eq(ok, true, "main.save_settings() returns true when GameState succeeds")

	# Restore autoload state so any later suites see a clean slate.
	autoload_gs._local_storage_writer = prev_writer
	autoload_gs.use_local_storage = prev_use_ls
	main.free()
