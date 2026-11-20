extends "res://tests/test_case.gd"
## Issue #515: changing the dock side across orientation families at the
## startup menu bootstraps a fresh colony, and bootstrap_state() force-
## persists it straight over SAVE_PATH. The previous colony must be copied
## to a timestamped backup first (mirroring the New Game path, issue #178),
## and the backup notice must actually reach the event log — sim.push_event()
## drops events while state has no "events" key, so notices pushed before
## bootstrap_state() were silently discarded.
##
## The suite drives the real main.tscn scene so the assertions read the
## production side effects: the live save file, the backup set on disk, and
## the live event log.
##
## game_state.gd is loaded at runtime (not preloaded): a preload() compiles
## before the GameState autoload is registered in --script mode.

const SAVE_PATH := "user://windowstead.save"
const SETTINGS_PATH := "user://windowstead.settings"
## A tick value no bootstrapped colony can produce, so a recovered save is
## unmistakably the pre-change colony.
const PREVIOUS_TICK := 99

## main.gd DOCK_OPTIONS order: ["right", "left", "bottom"].
const DOCK_OPTION_RIGHT := 0
const DOCK_OPTION_LEFT := 1
const DOCK_OPTION_BOTTOM := 2

var game_state: Node
var main: Node


func run_tests() -> void:
	var previous_settings := _read_text(SETTINGS_PATH)
	var previous_settings_existed := FileAccess.file_exists(SETTINGS_PATH)

	game_state = load("res://scripts/game_state.gd").new()
	root.add_child(game_state)
	await process_frame

	# Capture the developer's real save and backup set before the first
	# _reset_session() clears them, so teardown can put them back verbatim
	# (PR #518 review: running this suite locally must not destroy a
	# player colony or its backup history).
	var previous_user_data := _capture_save_and_backups()

	game_state.save_settings({"dock_anchor": "bottom", "tick_speed": 0})
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# The colony tick timer would persist state over the fixture saves.
	main.tick_timer.stop()

	await _orientation_change_backs_up_existing_save()
	await _bootstrapped_colony_locks_further_orientation_changes()
	await _orientation_change_without_prior_save_bootstraps_anyway()
	await _same_family_change_leaves_save_alone()
	await _new_game_backs_up_and_surfaces_notice()
	await _captured_user_data_restores_verbatim()

	main.queue_free()
	game_state.queue_free()
	_restore_user_data(previous_settings, previous_settings_existed, previous_user_data)


## Startup menu, an existing save on disk: switching bottom -> right must
## keep the old colony recoverable and tell the player about the backup.
func _orientation_change_backs_up_existing_save() -> void:
	print("")
	print("--- startup orientation change backs up the existing save (issue #515) ---")
	_reset_session("bottom")
	game_state.save_game(_previous_colony_save())
	if not assert_true(FileAccess.file_exists(SAVE_PATH), "fixture: save on disk"):
		return
	assert_eq(game_state.list_backups().size(), 0, "fixture: no backups yet")

	_select_dock_option(DOCK_OPTION_RIGHT)
	await process_frame

	var overwritten: Dictionary = game_state.load_game()
	assert_eq(int(overwritten.get("tick", -1)), 0,
		"fresh colony persisted over the old save")
	var backups: Array = game_state.list_backups()
	if not assert_eq(backups.size(), 1, "orientation change created one backup"):
		return
	var restored: String = game_state.restore_backup()
	if not assert_true(not restored.is_empty(), "restore_backup finds the backup"):
		return
	var recovered: Dictionary = game_state.load_game()
	assert_eq(int(recovered.get("tick", -1)), PREVIOUS_TICK,
		"the backup restores the pre-change colony")
	assert_true(_events_mention("Backup saved before reset"),
		"backup notice reaches the event log")
	assert_true(_events_mention("Dock orientation changed"),
		"orientation notice still surfaced")


## A cross-family change can happen only once per session: bootstrap_state()
## seeds a non-empty state and disables the dropdown (apply_orientation_lock_ui),
## so a second change — even cross-family — bails out at the state check and
## can never back up the already-fresh colony a second time. This is what
## keeps the backup rotation from evicting the original colony's backup with
## repeated nudges (PR #518 review question).
func _bootstrapped_colony_locks_further_orientation_changes() -> void:
	print("")
	print("--- bootstrapped colony locks further orientation changes (issue #515) ---")
	_reset_session("bottom")
	game_state.save_game(_previous_colony_save())

	_select_dock_option(DOCK_OPTION_RIGHT)
	await process_frame
	if not assert_eq(game_state.list_backups().size(), 1,
			"fixture: first change took the one backup"):
		return
	assert_true(main.dock_side_option.disabled,
		"dropdown locked after the colony bootstrapped")
	if not assert_true(not main.state.is_empty(),
			"fixture: in-memory colony is non-empty"):
		return
	var save_after_first := _read_text(SAVE_PATH)

	# Fire the signal directly: a disabled OptionButton cannot emit it, but
	# the state check must hold even if it somehow arrives.
	_select_dock_option(DOCK_OPTION_BOTTOM)
	await process_frame

	assert_eq(_read_text(SAVE_PATH), save_after_first,
		"second change leaves the bootstrapped save untouched")
	assert_eq(game_state.list_backups().size(), 1,
		"second change takes no backup of the live save")
	assert_true(_events_mention("locked"),
		"second change reports the dock-style lock")


## First run (no save on disk): the bootstrap must still write a fresh
## colony, create no empty backup, and stay quiet about backups.
func _orientation_change_without_prior_save_bootstraps_anyway() -> void:
	print("")
	print("--- startup orientation change on a fresh install (issue #515) ---")
	_reset_session("right")
	if not assert_false(FileAccess.file_exists(SAVE_PATH),
			"fixture: no save on disk"):
		return

	_select_dock_option(DOCK_OPTION_BOTTOM)
	await process_frame

	assert_true(FileAccess.file_exists(SAVE_PATH),
		"fresh colony bootstrapped to disk with no prior save")
	assert_eq(game_state.list_backups().size(), 0,
		"nothing to back up: no backup file created")
	assert_false(_events_mention("Backup saved"),
		"no backup notice when there was no save")


## Within one orientation family the world is not rebuilt and nothing is
## persisted: the save file must be byte-identical afterwards.
func _same_family_change_leaves_save_alone() -> void:
	print("")
	print("--- same-family startup change leaves the save alone (issue #515) ---")
	_reset_session("left")
	game_state.save_game(_previous_colony_save())
	var save_before := _read_text(SAVE_PATH)

	_select_dock_option(DOCK_OPTION_RIGHT)
	await process_frame

	assert_eq(_read_text(SAVE_PATH), save_before,
		"same-family change does not touch the save file")
	assert_eq(game_state.list_backups().size(), 0,
		"same-family change creates no backup")
	assert_true(main.state.is_empty(),
		"same-family change does not bootstrap a colony")


## The New Game path already backed up before the destructive reset, but its
## notice was pushed before bootstrap_state() replaced the event log, so the
## player never saw it. Pin both halves.
func _new_game_backs_up_and_surfaces_notice() -> void:
	print("")
	print("--- new game backs up and surfaces the notice (issue #515) ---")
	_reset_session("bottom")
	game_state.save_game(_previous_colony_save())

	main.select_startup_anchor("bottom")
	main._on_startup_new_game()
	await process_frame

	assert_eq(game_state.list_backups().size(), 1,
		"new game creates exactly one backup")
	var overwritten: Dictionary = game_state.load_game()
	assert_eq(int(overwritten.get("tick", -1)), 0,
		"new game bootstrapped over the old save")
	var restored: String = game_state.restore_backup()
	assert_true(not restored.is_empty(), "restore_backup finds the new-game backup")
	assert_eq(int(game_state.load_game().get("tick", -1)), PREVIOUS_TICK,
		"new-game backup restores the previous colony")
	assert_true(_events_mention("Backup saved before reset"),
		"new game surfaces the backup notice")


## The suite's teardown promise (PR #518 review): a developer's own save and
## backup files must survive a local run. Exercise capture → trample →
## restore and pin that names and contents come back byte-for-byte.
func _captured_user_data_restores_verbatim() -> void:
	print("")
	print("--- teardown restores the save and backups it captured (PR #518 review) ---")
	_reset_session("bottom")
	game_state.save_game(_previous_colony_save())
	var first_backup: String = String(game_state.backup_save())
	var later_colony: Dictionary = _previous_colony_save()
	later_colony["tick"] = PREVIOUS_TICK + 1
	game_state.save_game(later_colony)
	var second_backup: String = String(game_state.backup_save())
	if not assert_true(not first_backup.is_empty() and not second_backup.is_empty(),
			"fixture: two backups created"):
		return

	var captured := _capture_save_and_backups()
	var expected_save := _read_text(SAVE_PATH)
	var expected_backups: Array = game_state.list_backups()
	var expected_contents := {}
	for backup_path in expected_backups:
		expected_contents[String(backup_path)] = _read_text(String(backup_path))
	if not assert_eq(expected_backups.size(), 2, "fixture: two backups on disk"):
		return

	# Simulate the suite overwriting everything the capture held.
	game_state.clear_game()
	_clear_backups()
	if not assert_false(FileAccess.file_exists(SAVE_PATH),
			"fixture: save cleared after capture"):
		return

	_restore_save_and_backups(captured)
	assert_eq(_read_text(SAVE_PATH), expected_save,
		"the captured save is restored byte-for-byte")
	var restored_backups: Array = game_state.list_backups()
	assert_eq(restored_backups, expected_backups,
		"both backups return under their original names")
	for backup_path in expected_backups:
		assert_eq(_read_text(String(backup_path)),
			String(expected_contents[String(backup_path)]),
			"backup content restored unchanged: %s" % String(backup_path).get_file())


## Put the session in a known startup state: the given dock anchor applied,
## no colony in memory, and no save or backups on disk.
func _reset_session(anchor: String) -> void:
	main.settings["dock_anchor"] = anchor
	main.sync_dock_option(anchor)
	main.apply_dock_position()
	main.state = {}
	main.game_active = false
	game_state.clear_game()
	_clear_backups()


## Mimic the player changing the dropdown: the OptionButton selection must
## move too, because save_settings() re-derives dock_anchor from
## dock_side_option.selected (main.gd), and the handler arrives via the
## item_selected signal exactly as wire_controls connected it.
func _select_dock_option(index: int) -> void:
	main.dock_side_option.select(index)
	main.dock_side_option.item_selected.emit(index)


func _clear_backups() -> void:
	for backup_path in game_state.list_backups():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(backup_path)))


func _previous_colony_save() -> Dictionary:
	return {
		"tick": PREVIOUS_TICK,
		"resources": {"wood": 42, "stone": 7, "food": 3},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"colony_stance": "balanced",
		"workers": [],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [{"tick": 0, "text": "Colony worth backing up."}],
		"dock_anchor": "bottom",
		"save_version": 2,
	}


func _events_mention(needle: String) -> bool:
	var events: Array = main.state.get("events", [])
	for entry in events:
		if entry is Dictionary and String(entry.get("text", "")).find(needle) != -1:
			return true
	return false


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()


## Snapshot the real player data this suite overwrites: the save file and
## every existing backup, keyed by its "user://" path so teardown can put
## each file back under its original (timestamped) name.
func _capture_save_and_backups() -> Dictionary:
	var backups := {}
	for backup_path in game_state.list_backups():
		backups[String(backup_path)] = _read_text(String(backup_path))
	return {
		"save": _read_text(SAVE_PATH),
		"save_existed": FileAccess.file_exists(SAVE_PATH),
		"backups": backups,
	}


## Leave the player's data directory exactly as the suite found it: the
## original save and backup files (names and contents) and settings.
func _restore_save_and_backups(previous_user_data: Dictionary) -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_clear_backups()
	if bool(previous_user_data["save_existed"]):
		_write_text(SAVE_PATH, String(previous_user_data["save"]))
	var backups: Dictionary = previous_user_data["backups"]
	for backup_path in backups:
		_write_text(String(backup_path), String(backups[backup_path]))


func _restore_user_data(
		previous_settings: String,
		previous_settings_existed: bool,
		previous_user_data: Dictionary
) -> void:
	_restore_save_and_backups(previous_user_data)
	if previous_settings_existed:
		_write_text(SETTINGS_PATH, previous_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
