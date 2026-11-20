extends "res://tests/test_case.gd"
## Issue #521: the Restore Backup action in the game UI.
##
## Players get a "Restore Backup" button on the startup menu and in the
## in-game menu. Pressing it opens a confirmation overlay BEFORE the active
## save is overwritten; confirming calls GameState.restore_backup() and
## reloads the restored save through the existing load_saved_game() path.
##
## The suite drives the real main.tscn scene so the assertions read the
## production side effects: the live startup button, the confirmation panel
## and its named children, the %RestoreBackupButton unique-name wiring, the
## live state, and the persisted user://windowstead.save file.
##
## The GameState autoload IS registered in --script mode (see flow 6 of
## test_save_failure_surfaced.gd), so the suite resolves it with
## root.get_node("GameState") and main.gd's GameState references hit it.

const SAVE_PATH := "user://windowstead.save"
const SETTINGS_PATH := "user://windowstead.settings"
## LayoutMath's bottom anchor-family grid size: 32x5.
const BOTTOM_TILES := 32 * 5

var game_state: Node
var main: Node


func run_tests() -> void:
	var previous_save := _read_text(SAVE_PATH)
	var previous_save_existed := FileAccess.file_exists(SAVE_PATH)
	var previous_settings := _read_text(SETTINGS_PATH)
	var previous_settings_existed := FileAccess.file_exists(SETTINGS_PATH)

	game_state = root.get_node("GameState")

	# Deterministic starting point: a bottom-docked session with a colony
	# already running, so push_event has a live event log to prepend to.
	game_state.save_settings({"dock_anchor": "bottom", "tick_speed": 0})
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# The colony tick timer would persist the running game over the fixture
	# saves and backups this suite writes.
	main.tick_timer.stop()
	_clear_backups()
	_start_colony()

	await _startup_menu_exposes_the_action()
	await _no_backup_press_reports_instead_of_confirming()
	await _confirmation_gates_the_overwrite()
	await _confirm_restores_and_reloads()
	await _cancel_keeps_the_active_save()
	await _in_game_menu_button_is_wired()
	await _startup_menu_recovery_path()

	_teardown(previous_save, previous_save_existed, previous_settings, previous_settings_existed)
	main.queue_free()


## The running colony the restore flows below operate on.
func _start_colony() -> void:
	main.state = {
		"tick": 1,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": _tiles(BOTTOM_TILES),
		"builds": [],
		"next_build_id": 1,
		"events": [{"tick": 0, "text": "Colony already running."}],
		"dock_anchor": "bottom",
	}
	main.game_active = true
	main.build_world()


## Flow 1: the startup menu carries the action and gates it on backup
## availability.
func _startup_menu_exposes_the_action() -> void:
	print("")
	print("--- startup menu exposes Restore Backup (issue #521) ---")
	assert_not_null(main.startup_restore_button,
		"startup menu builds the restore button")
	assert_eq(main.startup_restore_button.text, "Restore Backup",
		"startup restore button is labeled 'Restore Backup'")

	_clear_backups()
	main.show_startup_menu()
	assert_true(main.startup_restore_button.disabled,
		"startup restore button is disabled when no backups exist")

	game_state.save_game(_save_with_tick(2))
	game_state.backup_save()
	main.show_startup_menu()
	assert_false(main.startup_restore_button.disabled,
		"startup restore button is re-enabled once a backup exists")


## Flow 2: with nothing to restore, the press reports and never opens the
## confirmation overlay.
func _no_backup_press_reports_instead_of_confirming() -> void:
	print("")
	print("--- no-backup press reports instead of confirming (issue #521) ---")
	_clear_backups()
	main._on_restore_backup_pressed()
	assert_false(main.restore_confirm_panel.visible,
		"pressing Restore Backup with no backups leaves the panel hidden")
	assert_true(_latest_event_mentions("No save backup"),
		"pressing Restore Backup with no backups surfaces the event")


## Flow 3: pressing restore only opens the confirmation; the active save is
## untouched until the player confirms.
func _confirmation_gates_the_overwrite() -> void:
	print("")
	print("--- confirmation gates the overwrite (issue #521) ---")
	_clear_backups()
	game_state.save_game(_save_with_tick(10))
	game_state.backup_save()
	game_state.save_game(_save_with_tick(50))
	main.load_saved_game()
	await process_frame
	assert_eq(int(main.state.get("tick", -1)), 50,
		"pre-restore load picks up the current save")

	main._on_restore_backup_pressed()
	assert_true(main.restore_confirm_panel.visible,
		"pressing Restore Backup opens the confirmation panel")
	assert_eq(int(game_state.load_game().get("tick", -1)), 50,
		"the active save is not overwritten before confirming")


## Flow 4: confirming restores the latest backup over the active save and
## reloads it through the normal load path.
func _confirm_restores_and_reloads() -> void:
	print("")
	print("--- confirm restores and reloads (issue #521) ---")
	var restore_button: Button = main.restore_confirm_panel.find_child(
		"RestoreConfirmRestore", true, false) as Button
	assert_not_null(restore_button, "confirmation panel names its Restore button")
	restore_button.pressed.emit()

	assert_false(main.restore_confirm_panel.visible,
		"confirming hides the confirmation panel")
	assert_eq(int(game_state.load_game().get("tick", -1)), 10,
		"confirming overwrote the active save with the backup")
	assert_eq(int(main.state.get("tick", -1)), 10,
		"confirming reloaded the restored colony into the live state")
	assert_true(_latest_event_mentions("restored"),
		"confirming surfaces a restore event")


## Flow 5: cancelling closes the panel and leaves the active save alone.
func _cancel_keeps_the_active_save() -> void:
	print("")
	print("--- cancel keeps the active save (issue #521) ---")
	game_state.save_game(_save_with_tick(20))
	game_state.backup_save()
	game_state.save_game(_save_with_tick(60))
	main.load_saved_game()
	await process_frame
	assert_eq(int(main.state.get("tick", -1)), 60,
		"pre-cancel load picks up the current save")

	main._on_restore_backup_pressed()
	assert_true(main.restore_confirm_panel.visible,
		"pressing Restore Backup opens the confirmation panel again")
	var cancel_button: Button = main.restore_confirm_panel.find_child(
		"RestoreConfirmCancel", true, false) as Button
	assert_not_null(cancel_button, "confirmation panel names its Cancel button")
	cancel_button.pressed.emit()

	assert_false(main.restore_confirm_panel.visible,
		"cancelling hides the confirmation panel")
	assert_eq(int(game_state.load_game().get("tick", -1)), 60,
		"cancelling leaves the active save intact")
	assert_eq(int(main.state.get("tick", -1)), 60,
		"cancelling leaves the live colony intact")


## Flow 6: the in-game menu button exists in the scene and is wired to the
## same confirmation flow.
func _in_game_menu_button_is_wired() -> void:
	print("")
	print("--- in-game menu button is wired (issue #521) ---")
	var menu_button: Button = main.get_node("%RestoreBackupButton") as Button
	assert_not_null(menu_button, "main.tscn places RestoreBackupButton")
	assert_eq(menu_button.text, "Restore Backup",
		"in-game Restore Backup button is labeled correctly")

	_clear_backups()
	game_state.save_game(_save_with_tick(5))
	game_state.backup_save()
	menu_button.pressed.emit()
	assert_true(main.restore_confirm_panel.visible,
		"in-game press opens the confirmation panel")
	main._close_restore_confirm()


## Flow 7: a player at the startup menu can restore and get back into the
## restored colony without leaving the menu flow.
func _startup_menu_recovery_path() -> void:
	print("")
	print("--- startup-menu recovery path (issue #521) ---")
	_clear_backups()
	game_state.save_game(_save_with_tick(30))
	game_state.backup_save()
	game_state.save_game(_save_with_tick(70))
	main.load_saved_game()
	await process_frame
	main.open_startup_menu()
	assert_false(main.game_active, "opening the startup menu leaves the colony")

	var menu_button: Button = main.get_node("%RestoreBackupButton") as Button
	menu_button.pressed.emit()
	var restore_button: Button = main.restore_confirm_panel.find_child(
		"RestoreConfirmRestore", true, false) as Button
	restore_button.pressed.emit()

	assert_true(main.game_active,
		"restoring from the startup menu re-activates the colony")
	assert_false(main.startup_panel.visible,
		"restoring from the startup menu hides the startup panel")
	assert_eq(int(main.state.get("tick", -1)), 30,
		"restoring from the startup menu loads the restored colony")


## A save shaped like a real one and compatible with the bottom anchor:
## exactly 32x5 tiles and an in-bounds worker.
func _save_with_tick(tick_value: int) -> Dictionary:
	return {
		"tick": tick_value,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [{
			"name": "Jun",
			"pos": {"x": 2, "y": 2},
			"prev_pos": {"x": 2, "y": 2},
			"carrying": {},
			"task": {},
			"break_ticks": 0,
			"spawn_tick": 0,
		}],
		"tiles": _tiles(BOTTOM_TILES),
		"builds": [],
		"next_build_id": 1,
		"events": [],
		"dock_anchor": "bottom",
		"save_version": 2,
	}


func _tiles(count: int) -> Array:
	var tiles: Array = []
	for _i in count:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	return tiles


func _clear_backups() -> void:
	for backup_path in game_state.list_backups():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(backup_path)))


func _latest_event_mentions(needle: String) -> bool:
	var events: Array = main.state.get("events", [])
	if events.is_empty():
		return false
	var latest: Dictionary = events[0]
	return String(latest.get("text", "")).find(needle) != -1


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


## Leave the player's data directory as the suite found it.
func _teardown(previous_save: String, previous_save_existed: bool,
		previous_settings: String, previous_settings_existed: bool) -> void:
	_clear_backups()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if previous_save_existed:
		_write_text(SAVE_PATH, previous_save)
	if previous_settings_existed:
		_write_text(SETTINGS_PATH, previous_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
