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
## dir stays empty). The first capture also journals the snapshot in the OS
## temp dir, and a later run recovers an interrupted run from it;
## journaling, one-shot recovery, and rejection of malformed journals are
## all pinned here.
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
	assert_true(FileAccess.file_exists(_pending_snapshot_path()),
			"first capture journals the snapshot for crash recovery")
	_trampled_data_restores_byte_for_byte()
	_ci_shape_absent_capture_removes_run_files()
	_zero_byte_captures_restore_verbatim()
	_interrupted_run_recovers_from_journal()
	_malformed_journal_is_discarded_unapplied()
	restore_user_data(previous_user_data)
	assert_false(FileAccess.file_exists(_pending_snapshot_path()),
			"restore with the first capture clears the journal")
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
	assert_true(FileAccess.file_exists(_pending_snapshot_path()),
			"restore of a nested (non-first) capture keeps the journal")
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
	# after the suite-start capture is safe — teardown puts it back, and the
	# crash journal from that capture recovers it even if this run is
	# interrupted midway.
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


## Crash shape: a suite died before its final restore, leaving its journal
## behind. Recovery puts trampled data back byte-for-byte, removes files the
## crashed run created, and consumes the journal exactly once. The journal is
## a probe file at its own path — this test never rewrites the live journal,
## so an interruption here still recovers the developer's real bytes. The
## journal's backup map is a real capture (a recovery must never delete real
## backups that postdate the fixture), with the fixture entries pinned in.
func _interrupted_run_recovers_from_journal() -> void:
	print("")
	print("--- interrupted run recovers from its journal, exactly once (issue #522) ---")
	var probe_journal := OS.get_temp_dir().path_join(
			"windowstead-test-user-data-guard-probe.json")
	if FileAccess.file_exists(probe_journal):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_journal))
	# What the interrupted run's first capture saw.
	var journal := capture_user_data()
	journal["save"] = FIXTURE_SAVE
	journal["settings"] = FIXTURE_SETTINGS
	var journal_backups: Dictionary = journal["backups"]
	journal_backups[FIXTURE_BACKUP_A] = "BACKUP-A"
	# The journal file only exists from here; it is gone before the first
	# assertion can return early, so no branch can strand it.
	var journal_file := FileAccess.open(probe_journal, FileAccess.WRITE)
	if journal_file != null:
		journal_file.store_string(JSON.stringify(journal))
		journal_file.close()
	# Lay out the on-disk state the recovery is meant to undo.
	_write_user_text(USER_SAVE_PATH, FIXTURE_SAVE)
	_write_user_text(USER_SETTINGS_PATH, FIXTURE_SETTINGS)
	_write_user_text(FIXTURE_BACKUP_A, "BACKUP-A")
	if assert_true(journal_file != null, "probe journal file writable"):
		# What the crashed run left behind: overwritten save, deleted settings,
		# deleted backup, and a run-created backup.
		_write_user_text(USER_SAVE_PATH, "SAVE-TRAMPLED")
		_remove_user_path(USER_SETTINGS_PATH)
		_remove_user_path(FIXTURE_BACKUP_A)
		_write_user_text(FIXTURE_BACKUP_NEW, "BACKUP-NEW")
		_recover_pending_user_data(probe_journal)
		assert_eq(_read_user_text(USER_SAVE_PATH), FIXTURE_SAVE,
				"journal puts the trampled save back byte-for-byte")
		assert_eq(_read_user_text(USER_SETTINGS_PATH), FIXTURE_SETTINGS,
				"journal puts a deleted settings file back")
		assert_eq(_read_user_text(FIXTURE_BACKUP_A), "BACKUP-A",
				"journal recreates a deleted backup under its original name")
		assert_false(FileAccess.file_exists(FIXTURE_BACKUP_NEW),
				"journal removes the backup the crashed run created")
	assert_false(FileAccess.file_exists(probe_journal),
			"recovery consumes the journal (applied exactly once)")


## The journal lives in a shared temp dir, so recovery must only apply
## values a capture could actually hold. A journal with a foreign value type
## is discarded unapplied: it deletes and clobbers nothing.
func _malformed_journal_is_discarded_unapplied() -> void:
	print("")
	print("--- malformed journal is discarded, data untouched (issue #522) ---")
	var probe_journal := OS.get_temp_dir().path_join(
			"windowstead-test-user-data-guard-malformed-probe.json")
	_write_user_text(USER_SAVE_PATH, "SAVE-SHOULD-SURVIVE")
	var journal_file := FileAccess.open(probe_journal, FileAccess.WRITE)
	if not assert_true(journal_file != null, "malformed probe journal writable"):
		return
	journal_file.store_string(JSON.stringify(
			{"save": 123, "settings": false, "backups": {}}))
	journal_file.close()
	_recover_pending_user_data(probe_journal)
	assert_false(FileAccess.file_exists(probe_journal),
			"malformed journal is consumed, not looped across runs")
	assert_eq(_read_user_text(USER_SAVE_PATH), "SAVE-SHOULD-SURVIVE",
			"malformed journal rewrote and deleted nothing")
	# A value-valid journal whose backup keys escape the user:// backup
	# namespace is equally untrusted: keys are write targets.
	var evil_target := OS.get_temp_dir().path_join("windowstead-evil-target.txt")
	if FileAccess.file_exists(evil_target):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(evil_target))
	var evil_journal := FileAccess.open(probe_journal, FileAccess.WRITE)
	if not assert_true(evil_journal != null, "escaped-key probe journal writable"):
		return
	evil_journal.store_string(JSON.stringify({
		"save": false, "settings": false,
		"backups": {evil_target: "PWNED"},
	}))
	evil_journal.close()
	_recover_pending_user_data(probe_journal)
	assert_false(FileAccess.file_exists(evil_target),
			"escaped backup key wrote nothing")
	assert_eq(_read_user_text(USER_SAVE_PATH), "SAVE-SHOULD-SURVIVE",
			"escaped-key journal deleted nothing")
	assert_false(FileAccess.file_exists(probe_journal),
			"escaped-key journal is consumed")


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
