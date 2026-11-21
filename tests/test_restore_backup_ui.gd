extends "res://tests/test_case.gd"
## Issue #521: the Restore Backup action in the game UI.
##
## Players get a "Restore Backup" button on the startup menu and in the
## in-game menu. Pressing it opens a confirmation overlay BEFORE the active
## save is overwritten; confirming validates the backup payload through the
## same load gates first (GameState.validate_backup + is_save_compatible),
## and only then calls GameState.restore_backup() and reloads through the
## existing load_saved_game() path.
##
## The suite drives the real main.tscn scene so the assertions read the
## production side effects: the live startup button, the confirmation panel
## and its named children, the %RestoreBackupButton unique-name wiring, the
## live state, and the persisted user://windowstead.save file.
##
## The GameState autoload IS registered in --script mode (see flow 6 of
## test_save_failure_surfaced.gd), so the suite resolves it with
## root.get_node("GameState") and main.gd's GameState references hit it.
##
## Developer data safety (issue #521 review): the suite must never delete
## the developer's own user:// backups, the only recovery path for a real
## save. Instead of clearing user://, setup MOVES every pre-existing backup
## into a subdirectory that list_backups() cannot see (its name does not
## match BACKUP_PREFIX), and teardown moves them all back. The suite only
## ever deletes backup files it created itself.

const SAVE_PATH := "user://windowstead.save"
const SETTINGS_PATH := "user://windowstead.settings"
const GameStateScript := preload("res://scripts/game_state.gd")
## Must NOT start with BACKUP_PREFIX, or list_backups() would still see it.
const STASH_DIR_NAME := "restore_backup_ui_suite_stash"
const STASH_DIR := "user://" + STASH_DIR_NAME
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

	# Hide (never delete) the developer's backups before anything in this
	# suite writes or removes one, including anything main.tscn does on
	# ready. A run that died mid-suite leaves them in the stash; setup
	# returns them before stashing again. If stashing is impossible the
	# suite refuses to run rather than risk deleting them (issue #521 review).
	if not _stash_preexisting_backups():
		print("SETUP FAILED: developer backups could not be stashed; refusing to run")
		quit(1)
		return

	# Deterministic starting point: a bottom-docked session with a colony
	# already running, so push_event has a live event log to prepend to.
	game_state.save_settings({"dock_anchor": "bottom", "tick_speed": 0})
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# The colony tick timer would persist the running game over the fixture
	# saves and backups this suite writes.
	main.tick_timer.stop()
	_delete_suite_backups()
	_start_colony()

	await _startup_menu_exposes_the_action()
	await _no_backup_press_reports_instead_of_confirming()
	await _confirmation_gates_the_overwrite()
	await _confirm_restores_and_reloads()
	await _cancel_keeps_the_active_save()
	await _in_game_menu_button_is_wired()
	await _startup_menu_recovery_path()
	await _in_game_button_disabled_without_backups()
	await _rejected_restore_keeps_colony_and_backup()
	await _escape_dismisses_confirmation()
	await _confirmation_recenters_on_backdrop_resize()
	await _incompatible_backup_never_overwrites_the_live_save()

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

	_delete_suite_backups()
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
	_delete_suite_backups()
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
	_delete_suite_backups()
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

	_delete_suite_backups()
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
	_delete_suite_backups()
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


## Flow 8 (issue #521 review): the in-game menu button follows the same
## disabled-when-empty rule as the startup menu button.
func _in_game_button_disabled_without_backups() -> void:
	print("")
	print("--- in-game button disabled without backups (issue #521 review) ---")
	var menu_button: Button = main.get_node("%RestoreBackupButton") as Button
	_delete_suite_backups()
	# close_menu/toggle_menu are the real menu transitions, and each runs
	# the disabled-when-empty refresh (set_menu_mode), so no enum access
	# is needed here.
	main.close_menu()
	main.toggle_menu()
	assert_true(menu_button.disabled,
		"in-game restore button is disabled when no backups exist")

	game_state.save_game(_save_with_tick(40))
	game_state.backup_save()
	main.close_menu()
	main.toggle_menu()
	assert_false(menu_button.disabled,
		"in-game restore button is enabled once a backup exists")
	main.close_menu()


## Flow 9 (issue #521 review): a corrupt backup must never reach the live
## save. The confirm press validates the payload BEFORE copying, reports the
## rejection, and leaves the live save file, the live colony, and the backup
## all untouched.
func _rejected_restore_keeps_colony_and_backup() -> void:
	print("")
	print("--- rejected restore keeps colony and backup (issue #521 review) ---")
	_delete_suite_backups()
	game_state.save_game(_save_with_tick(80))
	main.load_saved_game()
	await process_frame
	assert_eq(int(main.state.get("tick", -1)), 80,
		"pre-restore load picks up tick 80")

	# A backup whose contents the load gate must reject. The "zz" timestamp
	# sorts newest, so the restore flow picks this one.
	_write_text("user://%szz_corrupt.save" % GameStateScript.BACKUP_PREFIX,
		"corrupt-not-a-save")
	main._on_restore_backup_pressed()
	assert_true(main.restore_confirm_panel.visible,
		"confirmation opens because a backup file exists")
	var restore_button: Button = main.restore_confirm_panel.find_child(
		"RestoreConfirmRestore", true, false) as Button
	restore_button.pressed.emit()

	assert_false(main.restore_confirm_panel.visible,
		"confirming hides the panel even when the backup is rejected")
	assert_true(_latest_event_mentions("Restore not started"),
		"a rejected backup reports failure before any overwrite")
	assert_false(_latest_event_mentions("Save restored"),
		"a rejected restore never reports success")
	assert_eq(int(game_state.load_game().get("tick", -1)), 80,
		"the live save file is untouched by a backup the gate rejects")
	assert_eq(int(main.state.get("tick", -1)), 80,
		"the live colony keeps running after a rejected restore")
	assert_true(main.game_active, "the colony stays active after a rejected restore")
	assert_not_empty(game_state.list_backups(),
		"the corrupt backup stays available for a retry")


## Flow 10 (issue #521 review): Escape dismisses the confirmation overlay
## without touching the save, and unrelated unhandled input is not swallowed
## — the confirmation only claims ui_cancel (review round 2).
func _escape_dismisses_confirmation() -> void:
	print("")
	print("--- Escape dismisses the confirmation (issue #521 review) ---")
	_delete_suite_backups()
	game_state.save_game(_save_with_tick(81))
	game_state.backup_save()
	main._on_restore_backup_pressed()
	assert_true(main.restore_confirm_panel.visible,
		"confirmation opens before the Escape dismissal")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._unhandled_input(click)
	assert_true(main.restore_confirm_panel.visible,
		"unrelated input leaves the confirmation open")

	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	main._unhandled_input(escape)

	assert_false(main.restore_confirm_panel.visible,
		"Escape dismisses the confirmation panel")
	assert_eq(int(game_state.load_game().get("tick", -1)), 81,
		"dismissing with Escape leaves the active save alone")


## Flow 11 (issue #521 review): a backdrop resize re-centers the open
## confirmation overlay instead of leaving it where it was pressed.
func _confirmation_recenters_on_backdrop_resize() -> void:
	print("")
	print("--- confirmation recenters on backdrop resize (issue #521 review) ---")
	# Flow 10's backup is still present.
	main._on_restore_backup_pressed()
	assert_true(main.restore_confirm_panel.visible,
		"confirmation opens for the recenter check")

	main.restore_confirm_panel.position = Vector2(3, 7)
	main.backdrop.resized.emit()

	var panel_size: Vector2 = main.restore_confirm_panel.custom_minimum_size
	var expected := Vector2(
		maxf(16.0, (main.backdrop.size.x - panel_size.x) * 0.5),
		maxf(16.0, (main.backdrop.size.y - panel_size.y) * 0.5))
	assert_eq(main.restore_confirm_panel.position, expected,
		"a backdrop resize re-centers the open confirmation panel")
	main._close_restore_confirm()


## Flow 12 (issue #521 review round 2): a backup that parses cleanly but
## fails the geometry half of the load gate must also be rejected BEFORE
## restore_backup() copies it over the live save — the whole gate, not just
## the JSON/schema half, runs on the payload pre-copy.
func _incompatible_backup_never_overwrites_the_live_save() -> void:
	print("")
	print("--- incompatible backup rejected before the copy (issue #521 review) ---")
	_delete_suite_backups()
	game_state.save_game(_save_with_tick(83))
	main.load_saved_game()
	await process_frame
	assert_eq(int(main.state.get("tick", -1)), 83,
		"pre-restore load picks up tick 83")

	# Schema-valid save (160 tiles, well-shaped worker) whose worker stands
	# outside the grid: validate_save_schema() checks pos shape only — bounds
	# are is_save_compatible()'s job (scripts/main.gd) — so this payload must
	# be rejected by the geometry half of the gate before anything touches
	# the live save file.
	var bad := _save_with_tick(84)
	bad["workers"][0]["pos"] = {"x": 99, "y": 9}
	_write_text("user://%szz_incompatible.save" % GameStateScript.BACKUP_PREFIX,
		JSON.stringify(bad))
	main._on_restore_backup_pressed()
	assert_true(main.restore_confirm_panel.visible,
		"confirmation opens because a backup file exists")
	var restore_button: Button = main.restore_confirm_panel.find_child(
		"RestoreConfirmRestore", true, false) as Button
	restore_button.pressed.emit()

	assert_false(main.restore_confirm_panel.visible,
		"confirming hides the panel even when the backup is rejected")
	assert_true(_latest_event_mentions("Restore not started"),
		"an incompatible backup is rejected before the copy")
	assert_false(_latest_event_mentions("Save restored"),
		"an incompatible restore never reports success")
	assert_eq(int(game_state.load_game().get("tick", -1)), 83,
		"the live save file keeps its own contents")
	assert_eq(int(main.state.get("tick", -1)), 83,
		"the live colony keeps its own state")
	assert_true(main.game_active, "the colony stays active")
	assert_not_empty(game_state.list_backups(),
		"the incompatible backup stays available for inspection")


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


## Delete only the backup files the suite itself wrote. The developer's
## pre-existing backups are hidden in the stash directory for the whole run
## and are never listed here (issue #521 review).
func _delete_suite_backups() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for backup_name in _backup_file_names(dir):
		dir.remove(backup_name)


func _backup_file_names(dir: DirAccess) -> Array[String]:
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with(GameStateScript.BACKUP_PREFIX) and not dir.current_is_dir():
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return names


## Move every pre-existing backup into a subdirectory list_backups() cannot
## see, instead of deleting it. Also returns the stash left behind by a
## previously interrupted run before stashing again. Returns false when a
## backup could not be stashed: a backup left at the user:// root would be
## deleted by the suite's own cleanup, so the caller must refuse to run.
func _stash_preexisting_backups() -> bool:
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	_return_stashed_backups()
	var mk := dir.make_dir(STASH_DIR_NAME)
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		print("STASH FAILED: cannot create %s (%s)" % [STASH_DIR_NAME, error_string(mk)])
		return false
	for backup_name in _backup_file_names(dir):
		var err := dir.rename(backup_name, "%s/%s" % [STASH_DIR_NAME, backup_name])
		if err != OK:
			print("STASH FAILED: cannot move %s (%s)" % [backup_name, error_string(err)])
			return false
	return true


func _return_stashed_backups() -> void:
	var stash := DirAccess.open(STASH_DIR)
	if stash == null:
		return
	var names: Array[String] = []
	stash.list_dir_begin()
	var entry := stash.get_next()
	while entry != "":
		if not stash.current_is_dir():
			names.append(entry)
		entry = stash.get_next()
	stash.list_dir_end()
	for name in names:
		if stash.rename(name, "../" + name) != OK:
			# Safe-by-design leftover: the file stays in the stash where a
			# later run's setup retries the return.
			print("STASH NOTE: could not return %s yet; keeping it in the stash" % name)
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.remove(STASH_DIR_NAME)


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


## Leave the player's data directory as the suite found it: the suite's own
## backups are deleted, the developer's own backups come back from the stash.
func _teardown(previous_save: String, previous_save_existed: bool,
		previous_settings: String, previous_settings_existed: bool) -> void:
	_delete_suite_backups()
	_return_stashed_backups()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if previous_save_existed:
		_write_text(SAVE_PATH, previous_save)
	if previous_settings_existed:
		_write_text(SETTINGS_PATH, previous_settings)
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
