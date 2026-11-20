extends "res://tests/test_case.gd"
## Issue #522: pin the shared user:// teardown guard (capture_user_data() /
## restore_user_data() in tests/test_case.gd) that protects a developer's
## live save, settings, and backup history when suites run locally.
##
## The pattern proven in tests/test_startup_dock_side_backup.gd (PR #518
## review), lifted to the shared harness: capture BEFORE the first
## destructive call, restore at teardown; captured Strings (even "" for
## zero-byte files) come back byte-for-byte under their original names,
## files created after an absent capture are removed, and this suite leaves
## no residue on machines that already have a real save (CI's empty user
## dir stays empty).
##
## Every fixture file uses the "pin522-" backup-name marker so teardown can
## recognize and clean suite-created files even if a test exits early.

const FIXTURE_SAVE := "SAVE-DEVELOPER-COLONY"
const FIXTURE_SETTINGS := "SETTINGS-DEVELOPER"
const MARKER := "pin522-"
const FIXTURE_BACKUP_A := "user://%s%s-a" % [USER_BACKUP_PREFIX, MARKER]
const FIXTURE_BACKUP_B := "user://%s%s-b" % [USER_BACKUP_PREFIX, MARKER]
const FIXTURE_BACKUP_NEW := "user://%s%s-new" % [USER_BACKUP_PREFIX, MARKER]


func run_tests() -> void:
	var previous_user_data := capture_user_data()
	_trampled_data_restores_byte_for_byte()
	_ci_shape_absent_capture_removes_run_files()
	_zero_byte_captures_restore_verbatim()
	restore_user_data(previous_user_data)
	_remove_all_pin_backups()


## Capture, overwrite save/settings, delete the captured backups, add a new
## backup, restore: every original name and content must return verbatim and
## the run-created backup must be gone.
func _trampled_data_restores_byte_for_byte() -> void:
	print("")
	print("--- trampled save, settings, and backups restore byte-for-byte (issue #522) ---")
	_write_user_text(USER_SAVE_PATH, FIXTURE_SAVE)
	_write_user_text(USER_SETTINGS_PATH, FIXTURE_SETTINGS)
	_write_user_text(FIXTURE_BACKUP_A, "BACKUP-A")
	_write_user_text(FIXTURE_BACKUP_B, "BACKUP-B")
	var captured := capture_user_data()
	_write_user_text(USER_SAVE_PATH, "SAVE-TRAMPLED")
	_write_user_text(USER_SETTINGS_PATH, "SETTINGS-TRAMPLED")
	_remove_user_path(FIXTURE_BACKUP_A)
	_remove_user_path(FIXTURE_BACKUP_B)
	_write_user_text(FIXTURE_BACKUP_NEW, "BACKUP-NEW")
	if not assert_true(FileAccess.file_exists(USER_SAVE_PATH)
			and not FileAccess.file_exists(FIXTURE_BACKUP_A),
			"fixture: save overwritten and backups deleted"):
		return
	restore_user_data(captured)
	assert_eq(_read_user_text(USER_SAVE_PATH), FIXTURE_SAVE,
			"captured save restored byte-for-byte")
	assert_eq(_read_user_text(USER_SETTINGS_PATH), FIXTURE_SETTINGS,
			"captured settings restored byte-for-byte")
	assert_eq(_read_user_text(FIXTURE_BACKUP_A), "BACKUP-A",
			"captured backup A back under original name and content")
	assert_eq(_read_user_text(FIXTURE_BACKUP_B), "BACKUP-B",
			"captured backup B back under original name and content")
	assert_false(FileAccess.file_exists(FIXTURE_BACKUP_NEW),
			"backup created after capture removed by restore")


## CI shape: nothing at the save/settings paths at capture time. Files the
## run writes there afterwards must not survive teardown — an empty user dir
## stays empty.
func _ci_shape_absent_capture_removes_run_files() -> void:
	print("")
	print("--- absent capture deletes run-created save and settings (issue #522) ---")
	# Make absence deterministic on machines that hold a real save: removing
	# after the suite-start capture is safe, teardown puts it back.
	_remove_user_path(USER_SAVE_PATH)
	_remove_user_path(USER_SETTINGS_PATH)
	var captured := capture_user_data()
	assert_false(captured["save"], "no save at capture")
	assert_false(captured["settings"], "no settings at capture")
	_write_user_text(USER_SAVE_PATH, "FIXTURE-SAVE")
	_write_user_text(USER_SETTINGS_PATH, "FIXTURE-SETTINGS")
	restore_user_data(captured)
	assert_false(FileAccess.file_exists(USER_SAVE_PATH),
			"save created after absent capture cleaned up")
	assert_false(FileAccess.file_exists(USER_SETTINGS_PATH),
			"settings created after absent capture cleaned up")


## A pre-existing zero-byte save or backup must come back zero-byte, not be
## deleted because its captured content looked like "absent"; files created
## after the capture must still be cleaned up.
func _zero_byte_captures_restore_verbatim() -> void:
	print("")
	print("--- zero-byte captures restore; run-created files cleaned up (issue #522) ---")
	_write_user_text(USER_SAVE_PATH, "")
	_write_user_text(FIXTURE_BACKUP_A, "")
	if not assert_true(FileAccess.file_exists(USER_SAVE_PATH)
			and FileAccess.file_exists(FIXTURE_BACKUP_A),
			"fixture: zero-byte save and backup on disk"):
		return
	var captured := capture_user_data()
	# Trample exactly as a destructive suite does: overwrite save, add backup.
	_write_user_text(USER_SAVE_PATH, "SAVE-TRAMPLED")
	_write_user_text(FIXTURE_BACKUP_NEW, "BACKUP-NEW")
	restore_user_data(captured)
	assert_true(FileAccess.file_exists(USER_SAVE_PATH),
			"zero-byte save recreated, not left deleted")
	assert_true(FileAccess.file_exists(FIXTURE_BACKUP_A),
			"zero-byte backup recreated, not left deleted")
	assert_eq(_read_user_text(USER_SAVE_PATH), "",
			"restored save holds its zero bytes")
	assert_eq(_read_user_text(FIXTURE_BACKUP_A), "",
			"restored backup holds its zero bytes")
	assert_false(FileAccess.file_exists(FIXTURE_BACKUP_NEW),
			"backup created after capture cleaned up")


func _read_user_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<absent>"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "<unreadable>"
	var text := file.get_as_text()
	file.close()
	return text


func _remove_user_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _remove_all_pin_backups() -> void:
	for file_name in _user_backup_file_names():
		if file_name.contains(MARKER):
			DirAccess.remove_absolute(
					ProjectSettings.globalize_path("user://%s" % file_name))
