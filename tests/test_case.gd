extends SceneTree
## Shared test harness for all tests/*.gd suites (issue #281).
##
## Each suite extends this script by path and overrides run_tests():
##
##   extends "res://tests/test_case.gd"
##
##   func run_tests() -> void:
##       assert_eq(1 + 1, 2, "math works")
##
## Conventions:
## - Suites stay individually runnable via
##   `godot --headless --path . --script res://tests/<file>.gd`.
## - Output contract (CI greps these): one `TEST <name>: <PASS|FAIL>` line per
##   assertion (FAIL lines carry an optional `— <detail>` suffix), then a
##   summary line; the process exits non-zero when anything failed.
## - Scripts from scripts/ have no class_name unless noted; access them with
##   `const X := preload("res://scripts/x.gd")`, never as bare globals.

var test_pass := 0
var test_fail := 0

## Suite name shown in the summary; defaults to the script's file name.
var suite_name := ""


func _initialize() -> void:
	# Any suite run — even one that never touches user:// — recovers a journal
	# an interrupted run left behind (see the teardown guard below).
	_recover_pending_user_data()
	if suite_name.is_empty():
		suite_name = String(get_script().resource_path).get_file().get_basename()
	await run_tests()
	_finish()


## Override in each suite. May use await.
func run_tests() -> void:
	assert_true(false, "%s: run_tests() not implemented" % suite_name)


func _finish() -> void:
	print("")
	print("=== %s summary: %d passed, %d failed ===" % [suite_name, test_pass, test_fail])
	if test_pass == 0 and test_fail == 0:
		# Zero assertions means something upstream broke (a preload failed to
		# compile, run_tests aborted) — never report that as success.
		print("TEST %s: FAIL — no assertions ran" % suite_name)
		quit(1)
	elif test_fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("%s: ok" % suite_name)
		quit(0)


# ── Assertion vocabulary ──────────────────────────────────────────────────────
# All assertions record the result, print the contract line, and return the
# boolean outcome so callers can branch (e.g. skip dependent checks).

func assert_true(condition: Variant, name: String, detail: String = "") -> bool:
	var ok := bool(condition)
	if ok:
		test_pass += 1
		print("TEST %s: PASS" % name)
	else:
		test_fail += 1
		if detail.is_empty():
			print("TEST %s: FAIL" % name)
		else:
			print("TEST %s: FAIL — %s" % [name, detail])
	return ok


func assert_false(condition: Variant, name: String, detail: String = "") -> bool:
	return assert_true(not bool(condition), name, detail)


func assert_eq(actual: Variant, expected: Variant, name: String) -> bool:
	return assert_true(actual == expected, name, "expected %s, got %s" % [str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, name: String) -> bool:
	return assert_true(actual != unexpected, name, "expected anything but %s" % str(unexpected))


func assert_null(value: Variant, name: String) -> bool:
	return assert_true(value == null, name, "expected null, got %s" % str(value))


func assert_not_null(value: Variant, name: String) -> bool:
	return assert_true(value != null, name, "expected non-null value")


## Works for any value exposing is_empty() (Dictionary, Array, String, ...).
func assert_empty(value: Variant, name: String) -> bool:
	return assert_true(value.is_empty(), name, "expected empty, got %s" % str(value))


func assert_not_empty(value: Variant, name: String) -> bool:
	return assert_true(not value.is_empty(), name, "expected non-empty value")


# ── user:// teardown guard (issue #522) ──────────────────────────────────────
# Any suite that clears or overwrites user:// data — via GameState.clear_game()
# (which deletes the live save file) or by removing save/settings paths
# directly — must call capture_user_data() before its first destructive call
# and restore_user_data() at teardown, so running the suite locally cannot
# destroy the developer's live colony or its backup history. Suites that do
# not touch user:// need nothing. An empty user dir (CI) captures nothing and
# restores nothing: CI behavior is unchanged.
#
# Crash recovery: GDScript has no finally block, so the in-memory snapshot
# alone cannot restore after a mid-suite error. The first capture of a process
# therefore also journals the snapshot to a temp file OUTSIDE user://, and the
# owner restore removes it. If a suite dies before its final restore, the next
# suite run — any suite, via _initialize() — recovers the journal, so an
# interrupted run still leaves the developer's data intact. Suites run
# sequentially (the test-all loop in .justfile); the journal is one shared
# file on purpose.

const USER_SAVE_PATH := "user://windowstead.save"
const USER_SETTINGS_PATH := "user://windowstead.settings"
## Mirrors GameState.BACKUP_PREFIX (scripts/game_state.gd).
const USER_BACKUP_PREFIX := "windowstead-backup-"

## Snapshot the player data this suite may trample: save, settings, and every
## existing backup, keyed by "user://" path so teardown can put each file back
## under its original (timestamped) name. Call BEFORE any node exists that
## could write, i.e. as the first statement of run_tests(), keep the result,
## and pass it to restore_user_data() at teardown. A round-trip test may
## capture mid-run without clobbering its own teardown; only the first capture
## of the process owns (journals, and later clears) the crash-recovery file.
func capture_user_data() -> Dictionary:
	var is_first_capture := _guard_owner_capture.is_empty()
	var backups := {}
	for file_name in _user_backup_file_names():
		var backup_path := "user://%s" % file_name
		backups[backup_path] = _capture_user_file_text(backup_path)
	var snapshot := {
		"save": _capture_user_file_text(USER_SAVE_PATH),
		"settings": _capture_user_file_text(USER_SETTINGS_PATH),
		"backups": backups,
	}
	if is_first_capture:
		_guard_owner_capture = snapshot
		_write_pending_snapshot(snapshot)
	return snapshot


## Leave the player data directory exactly as capture_user_data() found it:
## rewrite original files (names and contents) and remove files the run
## created. Values follow the _capture_user_file_text tri-state contract:
## a captured String — even "" for a zero-byte file — is written back
## verbatim (WRITE truncates in place, so there is no window where a failed
## step could leave the real save gone); false (absent at capture) authorizes
## deleting whatever the run left at the path; null (exists but unreadable)
## is never rewritten or deleted (best effort: a mid-run reset may still
## have removed files). Restoring with the process's first capture also
## clears the crash-recovery journal.
func restore_user_data(captured: Dictionary) -> void:
	if captured.is_empty():
		return
	_apply_user_data_snapshot(captured)
	if is_same(captured, _guard_owner_capture):
		_remove_pending_snapshot()


## Re-apply one capture_user_data() snapshot (same tri-state contract).
func _apply_user_data_snapshot(snapshot: Dictionary) -> void:
	for key in ["save", "settings"]:
		var capture: Variant = snapshot[key]
		var path := USER_SAVE_PATH if key == "save" else USER_SETTINGS_PATH
		if typeof(capture) == TYPE_STRING:
			_write_user_text(path, String(capture))
		elif capture != null and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var backups: Dictionary = snapshot["backups"]
	for file_name in _user_backup_file_names():
		var backup_path := "user://%s" % file_name
		if not backups.has(backup_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	for backup_path in backups:
		var content: Variant = backups[backup_path]
		if typeof(content) == TYPE_STRING:
			_write_user_text(String(backup_path), String(content))


## First capture of the process; an empty Dictionary until then. Identity,
## not content: only this capture's restore clears the journal, so a nested
## round-trip capture can never delete or clobber it.
var _guard_owner_capture: Dictionary


## Crash-recovery journal for the active capture, OUTSIDE user:// (the temp
## dir is not player data). The name embeds the user data dir's hash because
## Godot's temp dir ignores TMPDIR and /tmp is shared on multi-user machines.
## JSON round-trips the tri-state contract: false, "", and null each parse
## back to themselves.
func _pending_snapshot_path() -> String:
	var owner := OS.get_user_data_dir().md5_text()
	return OS.get_temp_dir().path_join("windowstead-test-user-data-pending-%s.json" % owner)


func _write_pending_snapshot(snapshot: Dictionary) -> void:
	var file := FileAccess.open(_pending_snapshot_path(), FileAccess.WRITE)
	if file == null:
		print("note: could not journal user:// snapshot for crash recovery")
		return
	file.store_string(JSON.stringify(snapshot))
	file.close()


func _remove_pending_snapshot() -> void:
	var path := _pending_snapshot_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A journal only authorizes rewriting/deleting player data for as long as it
## plausibly belongs to an interrupted run. Recovery normally happens on the
## very next suite run, minutes later; a day-old journal is more likely to
## shadow files a human created in the meantime, so stale journals are
## discarded without being applied.
const JOURNAL_MAX_AGE_SECONDS := 24 * 60 * 60


## Values a capture can hold; anything else means the journal was not written
## by capture_user_data() (the temp dir is world-writable/shared) and is never
## applied. Note typeof, not ==: in GDScript 0 == false would slip an int
## past an equality gate into the delete arm.
func _is_journal_capture_value(value: Variant) -> bool:
	var value_type := typeof(value)
	return value_type == TYPE_STRING or value_type == TYPE_NIL \
			or (value_type == TYPE_BOOL and not value)


## Put back what a crashed suite run left trampled, from the journal its
## first capture wrote. Consumed exactly once: the journal is removed before
## the snapshot is applied, so a malformed journal cannot loop across runs.
## An empty path recovers this project's journal; tests pass their own probe
## path so pinning recovery never touches the live journal.
func _recover_pending_user_data(path := "") -> void:
	if path.is_empty():
		path = _pending_snapshot_path()
	if not FileAccess.file_exists(path):
		return
	var mod_time := FileAccess.get_modified_time(path)
	var age := Time.get_unix_time_from_system() - float(mod_time)
	if mod_time <= 0 or age > JOURNAL_MAX_AGE_SECONDS or age < 0:
		print("warning: pending user-data journal is stale; discarding it unapplied")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("warning: could not read %s; leaving user:// data alone" % path)
		return
	var text := file.get_as_text()
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		print("warning: pending user-data journal is malformed; ignoring it")
		return
	var journal: Dictionary = parsed
	if not journal.has("save") or not journal.has("settings") \
			or not (journal["backups"] is Dictionary) \
			or not _is_journal_capture_value(journal["save"]) \
			or not _is_journal_capture_value(journal["settings"]):
		print("warning: pending user-data journal is malformed; ignoring it")
		return
	for content: Variant in (journal["backups"] as Dictionary).values():
		if not _is_journal_capture_value(content):
			print("warning: pending user-data journal is malformed; ignoring it")
			return
	print("recovered user:// data journaled by an interrupted suite run")
	_apply_user_data_snapshot(journal)


## Names (not paths) of backup files currently in user://, listed directly via
## DirAccess so capture can run before any GameState node exists.
func _user_backup_file_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(USER_BACKUP_PREFIX):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return names


## The tri-state the teardown needs: false when the file is absent (so the run
## may not leave a file there), the text — possibly "" for a zero-byte file —
## when readable, and null when a file exists but could not be read, so a
## failed read can never clobber or delete a real save.
func _capture_user_file_text(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text()
	file.close()
	return text


func _write_user_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("teardown could not write %s" % path)
		return
	file.store_string(text)
	file.close()


## Runs a check callable and reports it through the shared assertion API.
## The callable may return a bool, a {ok, msg} Dictionary, or null (assert-based).
func check(name: String, fn: Callable) -> void:
	var ok := true
	var error_msg := ""
	var result: Variant = fn.call()
	if result is Dictionary:
		ok = result.get("ok", false)
		error_msg = result.get("msg", "no detail")
	elif result == false:
		ok = false
		error_msg = "returned false"
	assert_true(ok, name, error_msg)
