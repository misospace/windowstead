extends "res://tests/test_case.gd"

# =============================================================================
# Tests for timestamped save backup/restore and extended validation.
#
# Covers:
#   1. backup_save() creates a timestamped file
#   2. restore_backup() restores from the latest backup
#   3. list_backups() returns newest-first sorted list
#   4. validate_save_schema rejects invalid worker/build/task shapes
#   5. validate_save_schema accepts valid worker/build/task shapes
#   6. Numeric bounds: negative break_ticks rejected, missing keys caught
#   7. Grid sizing: tile count must match grid_w*grid_h (issue #236)
#   8. active_goal/completed_goal_ids/colony_stance/active_rewards validation
#   9. restore snapshots the live save (undoable restores, named restores,
#      pending-revert flag) — issue #525
#
# Assertion helpers and the summary come from tests/test_case.gd.
# =============================================================================

func run_tests() -> void:
	var previous_user_data := capture_user_data()

	# Autoloads are not running in --script mode — instantiate game_state.gd
	# manually (same pattern as test_runner.gd).
	var game_state_script := load("res://scripts/game_state.gd")
	var gs = game_state_script.new()
	root.add_child(gs)
	await process_frame

	flow_backup_creates_file(gs)
	flow_restore_from_backup(gs)
	flow_list_backups_sorted(gs)
	flow_backup_pruning(gs)
	flow_backup_same_second_counter_ordering(gs)
	flow_clear_game_keeps_backups(gs)
	flow_restore_snapshot_is_undoable(gs)
	flow_restore_named_backup(gs)
	flow_restore_pending_flag(gs)

	flow_copy_failure_preserves_destination(gs)
	flow_rename_failure_preserves_destination(gs)
	flow_validation_rejects_invalid(gs)
	flow_validation_accepts_valid(gs)
	flow_grid_sizing_consistency(gs)
	flow_goal_and_stance_validation(gs)
	restore_user_data(previous_user_data)

# ---------------------------------------------------------------------------
# Flow 1: backup_save creates a timestamped file
# ---------------------------------------------------------------------------

func flow_backup_creates_file(gs: Node) -> void:
	print("\n=== Flow 1: backup_save creates a timestamped file ===")
	gs.clear_game()

	# Save some state first
	var state := {
		"tick": 5,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"workers": [],
		"tiles": [],
		"builds": [],
		"events": [],
		"save_version": 2,
	}
	gs.save_game(state)

	# Backup
	var backup_path: String = gs.backup_save()
	assert_true(not backup_path.is_empty(), "backup_save returns a path")
	assert_true(backup_path.begins_with("user://"), "backup path starts with user://")
	assert_true(backup_path.contains("windowstead-backup-"), "backup filename has prefix",
		"got %s" % backup_path)

# ---------------------------------------------------------------------------
# Flow 2: restore_backup restores from the latest backup
# ---------------------------------------------------------------------------

func flow_restore_from_backup(gs: Node) -> void:
	print("\n=== Flow 2: restore_backup restores from the latest backup ===")
	gs.clear_game()

	# Save original state
	var state1 := {
		"tick": 10,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"workers": [],
		"tiles": [],
		"builds": [],
		"events": [],
		"save_version": 2,
	}
	gs.save_game(state1)
	gs.backup_save()

	# Modify save (simulate game progression)
	var state2 := {
		"tick": 50,
		"resources": {"wood": 100, "stone": 50, "food": 30},
		"workers": [{"name": "Jun", "pos": {"x": 11, "y": 2}, "prev_pos": {"x": 11, "y": 2}, "carrying": {}, "task": {}, "break_ticks": 0}],
		"tiles": [],
		"builds": [{"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": true}],
		"events": [],
		"save_version": 2,
	}
	gs.save_game(state2)

	# Verify modified state
	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 50, "modified tick is 50")
	assert_eq(loaded.get("resources", {}).get("wood", -1), 100, "modified wood is 100")

	# Restore backup
	var restored_path: String = gs.restore_backup()
	if not assert_true(not restored_path.is_empty(), "restore_backup returns a path"):
		# Restore failed (list_backups found nothing) — skip the dependent
		# state checks so one root cause doesn't cascade into extra FAILs.
		return

	# Verify restored state
	loaded = gs.load_game()
	assert_eq(loaded.get("tick", -1), 10, "restored tick is 10")
	assert_eq(loaded.get("resources", {}).get("wood", -1), 8, "restored wood is 8")
	assert_eq(loaded.get("workers", []).size(), 0, "restored workers empty")
	assert_eq(loaded.get("builds", []).size(), 0, "restored builds empty")

# ---------------------------------------------------------------------------
# Flow 3: list_backups returns newest-first sorted list
# ---------------------------------------------------------------------------

## Remove backup files left over from earlier flows/runs so counts are exact.
func _clear_backups(gs: Node) -> void:
	for backup_path in gs.list_backups():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(backup_path)))

func flow_list_backups_sorted(gs: Node) -> void:
	print("\n=== Flow 3: list_backups returns newest-first sorted list ===")
	gs.clear_game()
	_clear_backups(gs)

	# Create multiple backups
	var state := {"tick": 1, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2}
	gs.save_game(state)
	gs.backup_save()
	OS.delay_msec(50)
	state["tick"] = 2
	gs.save_game(state)
	gs.backup_save()
	OS.delay_msec(50)
	state["tick"] = 3
	gs.save_game(state)
	gs.backup_save()

	var backups: Array = gs.list_backups()
	if not assert_eq(backups.size(), 3, "three backups exist"):
		# Backups not discoverable — skip ordering checks (would index OOB).
		return
	assert_true(backups[0] > backups[1], "first backup is newest (sorted reverse)")
	assert_true(backups[1] > backups[2], "second backup is older than first")

# ---------------------------------------------------------------------------
# Flow 3b: backup_save prunes oldest entries beyond MAX_BACKUPS
# ---------------------------------------------------------------------------

func flow_backup_pruning(gs: Node) -> void:
	print("\n=== Flow 3b: backup_save prunes oldest entries beyond MAX_BACKUPS ===")
	gs.clear_game()
	_clear_backups(gs)

	# Create MAX_BACKUPS + 1 backups so pruning must kick in on the last call.
	var max_keep: int = int(gs.MAX_BACKUPS)
	var total: int = max_keep + 1
	var state := {"tick": 1, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2}
	for i in total:
		gs.save_game(state)
		gs.backup_save()
		OS.delay_msec(1100)  # ensure distinct timestamps in the filename

	var backups: Array = gs.list_backups()
	if not assert_eq(backups.size(), max_keep, "only MAX_BACKUPS backups remain after pruning"):
		# Pruning didn't reach the cap — still validate the oldest went.
		pass
	# Still assert that we did not keep every backup we created.
	assert_true(backups.size() < total, "pruning reduced backup count below total created")
	assert_true(backups[0] > backups[backups.size() - 1], "list_backups remains newest-first after pruning")

# ---------------------------------------------------------------------------
# Flow 3c: a backup survives clear_game on desktop
# ---------------------------------------------------------------------------

func flow_clear_game_keeps_backups(gs: Node) -> void:
	print("\n=== Flow 3c: a backup survives clear_game on desktop ===")
	gs.clear_game()
	_clear_backups(gs)
	gs.save_game({"tick": 21, "resources": {"wood": 3}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})
	var backup_path: String = gs.backup_save()
	if not assert_true(not backup_path.is_empty(), "desktop backup created before clear"):
		return
	gs.clear_game()
	assert_true(gs.list_backups().size() >= 1, "desktop backups survive clear_game")
	var restored: String = gs.restore_backup()
	if not assert_true(not restored.is_empty(), "desktop restore works after clear_game"):
		return
	assert_eq(int(gs.load_game().get("tick", -1)), 21, "desktop restore recovers the pre-clear save")
	_clear_backups(gs)

# ---------------------------------------------------------------------------
# Flow 3d: same-second backup counter ordering (issue #411)
# ---------------------------------------------------------------------------
# Regression: with the second-resolution timestamp and an unpadded counter
# (e.g. `_9.save`, `_10.save`), reverse-lexicographic ordering put
# `_10.save` AFTER `_1.save`, so the freshly created snapshot landed
# below the MAX_BACKUPS cap and was pruned by backup_save() the same
# instant it was created. The fix compares the counter numerically once
# the timestamps tie, and backup_save() now refuses to return a path
# that was just pruned. This flow pins a single timestamp via
# _timestamp_source so the 9-to-10 boundary is hit deterministically
# without sleeping.

func flow_backup_same_second_counter_ordering(gs: Node) -> void:
	print("\n=== Flow 3d: same-second backup counter ordering (issue #411) ===")
	gs.clear_game()
	_clear_backups(gs)

	# Save a base state so backup_save() has something to copy. Each
	# iteration will overwrite `tick` so the backup file content tracks
	# the counter, letting us verify which snapshot "won" after pruning.
	var state := {"tick": 0, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2}
	gs.save_game(state)

	# Pin a single timestamp so every backup collides on the same
	# second. Year 2099 keeps the test independent of system clock.
	var fixed_ts := "20990101T000000"
	var previous_source: Callable = gs._timestamp_source
	gs._timestamp_source = func() -> String: return fixed_ts
	# Reset the process-local counter so the names start at _1.save.
	gs._backup_counter = 0

	# Walk counters 1..11. The 9->10 transition is the smoking gun from
	# the issue: without the numeric tiebreak, _10.save sorts behind
	# the retained _5.save.._9.save and gets pruned in the same call.
	for counter in range(1, 12):
		state["tick"] = counter
		gs.save_game(state)
		var path: String = gs.backup_save()
		# backup_save() must return a path that actually exists — before
		# the fix, counters 10 and 11 returned a path that was just
		# pruned, and the caller had no way to tell.
		assert_true(not path.is_empty() and FileAccess.file_exists(path),
			"backup_save() returns an existing path for counter %d" % counter,
			"got %s" % path)

	# After 11 same-second backups, only the 5 newest (counters 7..11)
	# must remain. This is the core retention assertion.
	var backups: Array = gs.list_backups()
	if not assert_eq(backups.size(), gs.MAX_BACKUPS,
			"only MAX_BACKUPS backups remain after crossing the 9-to-10 boundary"):
		gs._timestamp_source = previous_source
		_clear_backups(gs)
		return

	# The survivors must be ordered numerically (newest counter first),
	# not by lex on the unpadded suffix.
	var actual_counters: Array = []
	for b in backups:
		var info: Dictionary = gs.parse_backup_name(String(b))
		actual_counters.append(int(info.counter))
	var expected_counters := [11, 10, 9, 8, 7]
	for i in range(gs.MAX_BACKUPS):
		if not assert_eq(actual_counters[i], expected_counters[i],
				"survivor[%d] counter is %d (numeric, same-second tiebreak)" % [i, expected_counters[i]]):
			pass

	# The first entry of list_backups() is the newest — its file must
	# be on disk. With the old sort this was true by construction (the
	# oldest got pruned), but we reassert it explicitly so a future
	# regression that lets pruning eat the newest snapshot fails here
	# rather than only in the restore check below.
	var latest: String = String(backups[0])
	assert_true(FileAccess.file_exists(latest),
		"latest backup path exists on disk after pruning",
		"got %s" % latest)

	# restore_backup() must return the latest path and load its content
	# — this is the user-visible payoff of the fix.
	var restored: String = gs.restore_backup()
	if not assert_eq(restored, latest, "restore_backup() returns the latest path"):
		gs._timestamp_source = previous_source
		_clear_backups(gs)
		return
	var loaded: Dictionary = gs.load_game()
	assert_eq(int(loaded.get("tick", -1)), 11,
		"restored tick matches the newest backup (counter 11)")

	# Restore the default timestamp source and clean up so subsequent
	# flows see the system clock again.
	gs._timestamp_source = previous_source
	_clear_backups(gs)

# ---------------------------------------------------------------------------
# Flow 3e: restore snapshots the live save so restoring is undoable (#525)
# ---------------------------------------------------------------------------

## Remove the undo snapshot left over from earlier flows/runs.
func _clear_undo(gs: Node) -> void:
	if FileAccess.file_exists(String(gs.UNDO_SAVE_PATH)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(gs.UNDO_SAVE_PATH)))

func flow_restore_snapshot_is_undoable(gs: Node) -> void:
	print("\n=== Flow 3e: restore snapshots the live save so restoring is undoable ===")
	gs.clear_game()
	_clear_backups(gs)
	_clear_undo(gs)

	gs.save_game({"tick": 10, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})
	var backup_path: String = gs.backup_save()
	if not assert_true(not backup_path.is_empty(), "backup created before restore flow"):
		return
	# Progress the colony past the backup.
	gs.save_game({"tick": 50, "resources": {"wood": 9}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})

	var restored: String = gs.restore_backup()
	if not assert_true(not restored.is_empty(), "restore_backup returns a path"):
		return
	assert_eq(int(gs.load_game().get("tick", -1)), 10, "restore applied the backup")
	assert_true(gs.has_restore_undo(), "pre-restore snapshot exists after restore")
	assert_eq(gs.list_backups().size(), 1, "pre-restore snapshot stays out of list_backups")

	var undo: String = gs.undo_restore_backup()
	if not assert_eq(undo, String(gs.UNDO_SAVE_PATH), "undo_restore_backup returns the undo slot"):
		return
	assert_eq(int(gs.load_game().get("tick", -1)), 50, "undo_restore_backup recovers the pre-restore save")
	assert_false(gs.has_restore_undo(), "undo consumes the snapshot")
	assert_eq(gs.undo_restore_backup(), "", "a second undo finds no snapshot")

	# Undo must not consume or mutate the backups themselves.
	assert_eq(gs.list_backups().size(), 1, "backups survive an undo")
	assert_eq(gs.restore_backup(), String(backup_path), "the same backup is restorable again after undo")
	assert_eq(int(gs.load_game().get("tick", -1)), 10, "second restore applies the same backup")
	_clear_backups(gs)
	_clear_undo(gs)

# ---------------------------------------------------------------------------
# Flow 3f: restore_backup(path) restores a chosen backup without
# displacing the newest slot (issue #525)
# ---------------------------------------------------------------------------

func flow_restore_named_backup(gs: Node) -> void:
	print("\n=== Flow 3f: restore_backup(path) restores the named backup ===")
	gs.clear_game()
	_clear_backups(gs)
	_clear_undo(gs)
	gs._backup_counter = 0

	var state := {"tick": 1, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2}
	gs.save_game(state)
	var older: String = gs.backup_save()
	state["tick"] = 2
	gs.save_game(state)
	var newer: String = gs.backup_save()
	if not assert_true(not older.is_empty() and not newer.is_empty(), "two backups created"):
		return
	# Live save moves past both backups.
	state["tick"] = 3
	gs.save_game(state)

	var restored: String = gs.restore_backup(older)
	if not assert_eq(restored, older, "restore_backup(path) returns the named path"):
		return
	assert_eq(int(gs.load_game().get("tick", -1)), 1, "named restore applies the older backup")
	assert_eq(String(gs.list_backups()[0]), newer, "the newest backup keeps the top slot after a named restore")

	# An unknown path must not touch the live save.
	assert_eq(gs.restore_backup("user://windowstead-backup-nope_9999.save"), "",
		"restore_backup rejects an unknown path")
	assert_eq(int(gs.load_game().get("tick", -1)), 1, "rejected restore leaves the live save untouched")
	_clear_backups(gs)
	_clear_undo(gs)

# ---------------------------------------------------------------------------
# Flow 3g: the pending-revert flag tracks unreconciled restores (#525)
# ---------------------------------------------------------------------------

func flow_restore_pending_flag(gs: Node) -> void:
	print("\n=== Flow 3g: restore arms the pending-revert flag ===")
	gs.clear_game()
	_clear_backups(gs)
	_clear_undo(gs)
	# Earlier flows in this suite ran restores; start from a clean flag.
	gs.clear_restore_pending()

	gs.save_game({"tick": 12, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})
	if not assert_true(not gs.backup_save().is_empty(), "backup created for pending-flag flow"):
		return
	gs.save_game({"tick": 34, "resources": {"wood": 2}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})

	assert_false(gs.restore_is_pending(), "no restore has run yet")
	if not assert_true(not gs.restore_backup().is_empty(), "restore succeeds with a live save snapshotted"):
		return
	assert_true(gs.restore_is_pending(), "a restore that snapshotted the live save arms the flag")
	gs.clear_restore_pending()
	assert_false(gs.restore_is_pending(), "clear_restore_pending() resets the flag")

	# Undoing clears the flag too.
	if not assert_true(not gs.undo_restore_backup().is_empty(), "undo is available after clear_restore_pending"):
		return
	assert_false(gs.restore_is_pending(), "undo_restore_backup clears the flag")

	# clear_game discards the restore bookkeeping with the colony (#525).
	if not assert_true(not gs.restore_backup().is_empty(), "restore re-armed for the clear_game check"):
		return
	assert_true(gs.restore_is_pending(), "restore armed before clear_game")
	gs.clear_game()
	assert_false(gs.restore_is_pending(), "clear_game clears the pending flag")
	assert_false(gs.has_restore_undo(), "clear_game removes the undo slot")

	# A restore with no live save has nothing to revert and arms nothing.
	gs.clear_game()
	assert_true(not gs.restore_backup().is_empty(), "restore works with no live save")
	assert_false(gs.restore_is_pending(), "no-live-save restore arms nothing")

	# Same flow, but with a pre-existing undo slot: a landed unarmed
	# restore must drop the stale slot so it cannot be applied over the
	# freshly restored save by a later undo (issue #525).
	gs.save_game({"tick": 56, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})
	assert_true(not gs.snapshot_for_restore().is_empty(), "undo slot seeded for the stale-slot check")
	if FileAccess.file_exists(String(gs.SAVE_PATH)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(String(gs.SAVE_PATH)))
	assert_true(gs.has_restore_undo(), "the slot survives removing only the live save")
	assert_true(not gs.restore_backup().is_empty(), "restore lands with no live save but a stale slot")
	assert_false(gs.restore_is_pending(), "the stale-slot restore still arms nothing")
	assert_false(gs.has_restore_undo(), "a landed unarmed restore drops the stale slot")
	assert_eq(gs.undo_restore_backup(), "", "no stale snapshot is left to apply")

	# A failed restore must leave existing staging untouched.
	gs.save_game({"tick": 57, "resources": {"wood": 1}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2})
	assert_true(not gs.snapshot_for_restore().is_empty(), "undo slot seeded before the failed restore")
	assert_eq(gs.restore_backup("user://windowstead-backup-nope_9998.save"), "",
		"unknown path rejects the restore")
	assert_true(gs.has_restore_undo(), "a rejected restore leaves the existing slot in place")
	_clear_backups(gs)
	_clear_undo(gs)

# ---------------------------------------------------------------------------
# Flow 3h: a failed copy never destroys the destination (issue #526)
# ---------------------------------------------------------------------------
# Regression: _copy_file() used to open the destination with
# FileAccess.WRITE, which truncates it immediately. A failure between the
# truncate and the final byte (disk full, process killed) left a zero-byte
# or partial file where a good save used to be — backup_save() could lose
# the fresh snapshot, and restore_backup() could lose the live save. The
# copy now lands in a ".tmp_" sibling, gets reopened and verified, and is
# only then renamed over the destination. Failed attempts must leave the
# destination untouched and remove the temp file.

func _save_state_a() -> Dictionary:
	return {"tick": 42, "resources": {"wood": 7}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2}

func _save_state_b() -> Dictionary:
	return {"tick": 99, "resources": {"wood": 8}, "harvested": {}, "workers": [], "tiles": [], "builds": [], "events": [], "save_version": 2}

# The probe destination lives in the OS temp dir, not user://:
# capture_user_data()/restore_user_data() only own the save, settings, and
# backup-prefixed files, so a crashed run must not leave this scratch file
# in a developer's real user:// directory (issue #526 review). The OS temp
# dir is where the guard's own crash journal lives, so leftovers there are
# already an accepted outcome of an interrupted run.
func _probe_dst_path() -> String:
	return OS.get_temp_dir().path_join("windowstead-copy_probe.save")

func flow_copy_failure_preserves_destination(gs: Node) -> void:
	print("\n=== Flow 3h: a failed copy never destroys the destination (issue #526) ===")
	gs.clear_game()
	_clear_backups(gs)

	# Live save (tick 42) plus a good backup of it, created while the
	# default copy hook is still in place.
	var original := _save_state_a()
	gs.save_game(original)
	var backup_path: String = gs.backup_save()
	if not assert_true(not backup_path.is_empty(), "baseline backup exists for the failure flows"):
		return

	# Progress the live save so a botched restore has something to lose.
	gs.save_game(_save_state_b())
	var probe_dst := _probe_dst_path()
	gs.save_game(_save_state_a(), probe_dst)

	var previous_hook: Callable = gs._copy_write_hook
	var failing_hooks := {
		"write that opens nothing": func(_tmp_path: String, _content: String) -> bool: return false,
		"truncated write that reports success": func(tmp_path: String, content: String) -> bool:
			# Adversarial: stores part of the payload yet claims success —
			# exactly what a lying flush/close looks like. The reopen +
			# content-equality verification in _copy_file must catch it.
			var f := FileAccess.open(tmp_path, FileAccess.WRITE)
			if f == null:
				return false
			f.store_string(content.substr(0, 3))
			f.close()
			return true,
		"write that claims success but stores nothing": func(tmp_path: String, _content: String) -> bool:
			var f := FileAccess.open(tmp_path, FileAccess.WRITE)
			if f == null:
				return false
			f.close()
			return true,
	}
	for label in failing_hooks:
		gs._copy_write_hook = failing_hooks[label]
		assert_false(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
			"copy with %s returns false" % label)
		assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 42,
			"destination keeps its content after the %s" % label)
		# The restore direction is where the live save was at stake:
		# backup → SAVE_PATH truncated the save before the fix.
		assert_eq(gs.restore_backup(), "", "restore_backup returns empty on the %s" % label)
		assert_eq(int(gs.load_game().get("tick", -1)), 99,
			"live save survives the failed restore copy (%s)" % label)
		# backup_save's snapshot direction: failure must report empty, not
		# a path (restore_backup() trusts returned paths — issue #411).
		assert_eq(gs.backup_save(), "", "backup_save returns empty on the %s" % label)
		assert_eq(_tmp_file_names().size(), 0,
			"no temp files left behind by the %s" % label)
		assert_false(FileAccess.file_exists(String(gs._copy_tmp_path(probe_dst))),
			"no temp file left beside the probe destination after the %s" % label)
	gs._copy_write_hook = previous_hook

	# The successful path through the same atomic machinery still works:
	# restore recovers the tick-42 backup and leaves no temp files.
	var restored: String = gs.restore_backup()
	if assert_eq(restored, backup_path, "restore still works after the failure injections"):
		assert_eq(int(gs.load_game().get("tick", -1)), 42, "restored tick is the backup's 42")
	assert_eq(_copy_probe_text(gs), "ok", "successful _copy_file over an existing destination writes fully")
	assert_eq(_tmp_file_names().size(), 0, "no temp files left behind by the successful copy")
	assert_false(FileAccess.file_exists(String(gs._copy_tmp_path(probe_dst))),
		"no temp file left beside the probe destination after the successful copy")

	# A temp name can never be mistaken for a backup: list_backups()
	# filters on BACKUP_PREFIX, and the dot-prefixed ".tmp_" name breaks
	# that prefix even when the destination is itself a backup file.
	var tmp_name := String(gs._copy_tmp_path("user://%sdemo.save" % gs.BACKUP_PREFIX))
	assert_false(tmp_name.trim_prefix("user://").begins_with(String(gs.BACKUP_PREFIX)),
		"temp name next to a backup destination cannot match BACKUP_PREFIX",
		"got %s" % tmp_name)

	# The temp file must stay in the destination's own directory so the
	# rename never crosses filesystems — even for nested destinations.
	var nested_tmp := String(gs._copy_tmp_path("user://deep/nest/demo.save"))
	assert_eq(nested_tmp, "user://deep/nest/.tmp_demo.save",
		"temp path keeps the destination's directory for nested paths")

	gs.clear_game()
	_clear_backups(gs)
	_remove_if_exists_path(probe_dst)

# ---------------------------------------------------------------------------
# Flow 3i: a failed replace never loses the destination's previous bytes
# (issue #526 review, #534)
# ---------------------------------------------------------------------------
# POSIX rename(2) failure leaves the destination untouched, but the Windows
# engine (pinned 4.7.1-stable DirAccessWindows::rename) removes an existing
# destination BEFORE its MoveFileW call — its ReplaceFileW branch only
# serves case-only name changes, which our distinct ".tmp_" names never
# are — so a move failing after that removal used to destroy the live save.
# _replace_file() instead stages the destination aside as the dot-prefixed
# ".tmp_<dst>.old" sibling when OS.has_feature("windows") reports Windows:
# a failing move moves the staged bytes back, and the double failure keeps
# them in the staged file (the destination's PREVIOUS bytes, not a second
# copy of the source) until the next copy for the destination supersedes
# them. No CI job executes GDScript on Windows (runtime coverage is tracked
# in #533), so the arms are driven with the _os_has_feature_hook and
# _rename_hook seams — a same-directory rename cannot portably be made to
# fail for real.

func flow_rename_failure_preserves_destination(gs: Node) -> void:
	print("\n=== Flow 3i: a failed replace preserves the destination's previous bytes (issue #534) ===")
	gs.clear_game()
	_clear_backups(gs)

	var original := _save_state_a()
	gs.save_game(original)
	var backup_path: String = gs.backup_save()
	if not assert_true(not backup_path.is_empty(), "baseline backup exists for the rename-failure flows"):
		return
	# Progress the live save so the copy under test has different content
	# to publish than the destination already holds.
	gs.save_game(_save_state_b())

	var probe_dst := _probe_dst_path()
	gs.save_game(_save_state_a(), probe_dst)
	var tmp_path := String(gs._copy_tmp_path(probe_dst))
	var stale_path := String(gs._copy_stale_path(probe_dst))
	var previous_hook: Callable = gs._rename_hook
	var previous_os_hook: Callable = gs._os_has_feature_hook

	# 1) POSIX-shaped failure: the rename reports an error and the
	#    destination survives untouched. The temp is dropped — safe, because
	#    the source still holds byte-identical content.
	gs._rename_hook = func(_from_path: String, _to_path: String) -> int:
		return ERR_FILE_CANT_WRITE
	assert_false(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
		"copy with a failing rename returns false")
	assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 42,
		"destination keeps its content after a failing rename")
	assert_false(FileAccess.file_exists(tmp_path),
		"temp is dropped after a POSIX-shaped rename failure")

	# 2) Windows-shaped replace with real renames: the destination is
	#    staged aside, the temp moves over the now-absent destination (the
	#    engine has no existing destination to remove), and the staged file
	#    is dropped.
	gs._rename_hook = previous_hook
	gs._os_has_feature_hook = func(feature: String) -> bool: return feature == "windows"
	assert_true(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
		"windows-stubbed copy over an existing destination succeeds")
	assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 99,
		"staged replace wrote the full source content")
	assert_false(FileAccess.file_exists(tmp_path), "no temp file after the staged success")
	assert_false(FileAccess.file_exists(stale_path), "no staged file after the staged success")

	# 3) Windows move failure: the staging rename is real, the move into
	#    the destination is emulated to fail — the exact window where the
	#    engine used to destroy the destination after removing it. The
	#    staged previous bytes must be moved back, so the destination still
	#    holds its OLD content, and the temp is dropped (the source still
	#    holds the new content, so keeping it could only create litter).
	gs.save_game(_save_state_a(), probe_dst)
	gs._rename_hook = func(from_path: String, to_path: String) -> int:
		if from_path == tmp_path and to_path == probe_dst:
			return ERR_FILE_CANT_WRITE
		return gs._rename_file(from_path, to_path)
	assert_false(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
		"copy reports failure when the staged move fails")
	assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 42,
		"failed staged move restores the destination's previous bytes")
	assert_false(FileAccess.file_exists(tmp_path), "no temp file after the staged move failure")
	assert_false(FileAccess.file_exists(stale_path), "no staged file left after the restore")

	# 3b) Staging-rename failure: the destination cannot even be moved
	#     aside. The copy must report failure with the destination intact
	#     and the temp dropped — no rename toward the destination was ever
	#     attempted, so no engine-side remove enters the picture.
	gs._rename_hook = func(from_path: String, to_path: String) -> int:
		if to_path == stale_path:
			return ERR_FILE_CANT_WRITE
		return gs._rename_file(from_path, to_path)
	assert_false(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
		"copy reports failure when the staging rename fails")
	assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 42,
		"destination keeps its content when the staging rename fails")
	assert_false(FileAccess.file_exists(tmp_path), "no temp left after a staging-rename failure")
	assert_false(FileAccess.file_exists(stale_path), "no staged file was created by the failed staging")

	# 4) Double failure: the move into the destination AND the restore
	#    rename both fail. The copy reports failure, the destination is
	#    absent, and the previous bytes survive at the recoverable staged
	#    path — the old flow kept a copy of the SOURCE instead, which
	#    preserved nothing that was at risk (issue #534).
	gs._rename_hook = func(from_path: String, to_path: String) -> int:
		if to_path == probe_dst and from_path != probe_dst:
			return ERR_FILE_CANT_WRITE
		return gs._rename_file(from_path, to_path)
	assert_false(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
		"copy reports failure when move and restore both fail")
	assert_false(FileAccess.file_exists(probe_dst),
		"the destination is absent when both the move and the restore fail")
	assert_false(FileAccess.file_exists(tmp_path),
		"no temp is kept when the source still holds the new content")
	assert_true(FileAccess.file_exists(stale_path),
		"previous bytes survive in the staged file when even the restore fails")
	assert_eq(int(gs.load_game(stale_path).get("tick", -1)), 42,
		"the staged file holds the destination's previous content")
	var stale_for_backup := String(gs._copy_stale_path("user://%sdemo.save" % gs.BACKUP_PREFIX))
	assert_false(stale_for_backup.trim_prefix("user://").begins_with(String(gs.BACKUP_PREFIX)),
		"a staged name cannot match BACKUP_PREFIX even for a backup-shaped destination",
		"got %s" % stale_for_backup)
	assert_true(stale_path.get_file().begins_with("."),
		"the staged name is dot-prefixed so backup listings skip it")

	# 5) Cleanup: the next successful copy for the same destination picks
	#    the staged leftover up. The destination is absent (post-double-
	#    failure), so this runs the plain-rename branch — which must still
	#    drop the superseded staged file.
	var rename_calls := {"n": 0}
	gs._rename_hook = func(from_path: String, to_path: String) -> int:
		rename_calls["n"] = int(rename_calls["n"]) + 1
		return gs._rename_file(from_path, to_path)
	assert_true(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
		"a later copy for the same destination succeeds again")
	assert_eq(int(rename_calls["n"]), 1,
		"the recovery copy with the destination absent uses exactly one rename (plain branch)")
	assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 99,
		"the recovering copy wrote the source content")
	assert_false(FileAccess.file_exists(stale_path),
		"the successful copy removed the staged leftover")
	assert_false(FileAccess.file_exists(tmp_path), "no temp left by the recovering copy")

	# 5b) Same pickup when the destination exists again: the staged
	#     replace supersedes a stale sibling (sentinel written by hand to
	#     stand in for an older double failure) up front.
	gs.save_game(_save_state_a(), probe_dst)
	var sentinel := FileAccess.open(stale_path, FileAccess.WRITE)
	if assert_true(sentinel != null, "staged sentinel for the supersede arm can be opened"):
		sentinel.store_string("stale")
		sentinel.close()
		assert_true(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
			"staged replace succeeds beside a stale sibling")
		assert_false(FileAccess.file_exists(stale_path),
			"staged replace superseded the stale sibling")
		assert_eq(int(gs.load_game(probe_dst).get("tick", -1)), 99,
			"supersede arm wrote the source content")

	# 5c) And on the non-staging (POSIX-shaped) branch the same pickup
	#     applies, so a staged leftover can never outlive one successful
	#     copy on any platform.
	gs._os_has_feature_hook = previous_os_hook
	_remove_if_exists_path(probe_dst)
	sentinel = FileAccess.open(stale_path, FileAccess.WRITE)
	if assert_true(sentinel != null, "staged sentinel for the POSIX pickup arm can be opened"):
		sentinel.store_string("stale")
		sentinel.close()
		assert_true(gs._copy_file(String(gs.SAVE_PATH), probe_dst),
			"POSIX-shaped copy succeeds with the destination absent")
		assert_false(FileAccess.file_exists(stale_path),
			"the POSIX-shaped success also removes the staged leftover")

	# 6) Saves must never close the recovery window a double failure
	#    opens: save_game() (the autosave/manual-save path) writes its
	#    destination directly and never routes through _replace_file(),
	#    so a staged sibling at the save path survives it, intact, until
	#    an explicit backup/restore action targets that destination
	#    again (issue #534 review).
	var save_stale := String(gs._copy_stale_path(String(gs.SAVE_PATH)))
	var save_tmp := String(gs._copy_tmp_path(String(gs.SAVE_PATH)))
	sentinel = FileAccess.open(save_stale, FileAccess.WRITE)
	if assert_true(sentinel != null, "staged sentinel at the save destination can be created"):
		sentinel.store_string("previous-live-bytes")
		sentinel.close()
		assert_true(gs.save_game(_save_state_b()),
			"save_game succeeds with a staged sibling at its destination")
		assert_true(FileAccess.file_exists(save_stale),
			"save_game never removes the staged sibling holding the last previous bytes")
		assert_eq(FileAccess.get_file_as_string(save_stale), "previous-live-bytes",
			"save_game leaves the staged sibling's content untouched")
		assert_false(FileAccess.file_exists(save_tmp),
			"save_game creates no temp sibling of its own")
		_remove_if_exists_path(save_stale)

	gs._rename_hook = previous_hook
	gs._os_has_feature_hook = previous_os_hook
	_remove_if_exists_path(tmp_path)
	_remove_if_exists_path(stale_path)
	_remove_if_exists_path(probe_dst)
	gs.clear_game()
	_clear_backups(gs)

func _copy_probe_text(gs: Node) -> String:
	# Exercises the default (verified atomic) hook over an existing
	# destination — replacing non-empty content with different non-empty
	# content — and reports whether the destination now matches the source.
	var src_path := "res://project.godot"
	var dst_path := _probe_dst_path()
	var src := FileAccess.open(src_path, FileAccess.READ)
	if src == null:
		return "source unreadable"
	var expected := src.get_as_text()
	src.close()
	if not bool(gs._copy_file(src_path, dst_path)):
		return "copy failed"
	var f := FileAccess.open(dst_path, FileAccess.READ)
	if f == null:
		return "dst unreadable"
	var text := f.get_as_text()
	f.close()
	return "ok" if text == expected else "dst content differs"

func _tmp_file_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return names
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(".tmp_"):
			names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return names

func _remove_if_exists_path(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

# ---------------------------------------------------------------------------
# Flow 4: validate_save_schema rejects invalid worker/build/task shapes
# ---------------------------------------------------------------------------

func flow_validation_rejects_invalid(gs: Node) -> void:
	print("\n=== Flow 4: validate_save_schema rejects invalid shapes ===")

	# Invalid worker: missing name
	var bad_worker := {
		"tick": 0, "resources": {"wood": 1}, "harvested": {},
		"workers": [{"pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}}],
		"tiles": [], "builds": [], "events": [],
	}
	var result: Dictionary = gs.validate_save_schema(bad_worker)
	assert_false(result.valid, "rejects worker missing name")

	# Invalid worker: negative break_ticks
	bad_worker["workers"] = [{"name": "Jun", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}, "break_ticks": -5}]
	result = gs.validate_save_schema(bad_worker)
	assert_false(result.valid, "rejects negative break_ticks")

	# Invalid build: missing id
	var bad_build := {
		"tick": 0, "resources": {"wood": 1}, "harvested": {},
		"workers": [], "tiles": [],
		"builds": [{"kind": "hut", "pos": {"x": 0, "y": 0}, "complete": false}],
		"events": [],
	}
	result = gs.validate_save_schema(bad_build)
	assert_false(result.valid, "rejects build missing id")

	# Invalid worker: non-numeric carrying value
	bad_worker["workers"] = [{"name": "Jun", "pos": {"x": 0, "y": 0}, "carrying": {"wood": "bad"}, "task": {}}]
	result = gs.validate_save_schema(bad_worker)
	assert_false(result.valid, "rejects non-numeric carrying value")

# ---------------------------------------------------------------------------
# Flow 5: validate_save_schema accepts valid worker/build/task shapes
# ---------------------------------------------------------------------------

func flow_validation_accepts_valid(gs: Node) -> void:
	print("\n=== Flow 5: validate_save_schema accepts valid shapes ===")

	var good_state := {
		"tick": 10, "resources": {"wood": 8, "stone": 4}, "harvested": {"wood": 0},
		"workers": [
			{"name": "Jun", "pos": {"x": 11, "y": 2}, "prev_pos": {"x": 11, "y": 2}, "carrying": {"wood": 2}, "task": {"kind": "haul"}, "break_ticks": 0},
		],
		# Match the LayoutMath-derived default grid (32x5=160 tiles) and supply
		# the corresponding grid_w/grid_h so internal-consistency checks accept.
		"tiles": [],
		"grid_w": 32,
		"grid_h": 5,
		"anchor_family": "bottom",
		"active_goal": {},
		"completed_goal_ids": [],
		"colony_stance": "balanced",
		"active_rewards": [],
		"builds": [
			{"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": false, "delivered": {}, "progress": 0.5},
		],
		"events": [{"tick": 5, "text": "test event"}],
	}
	var result: Dictionary = gs.validate_save_schema(good_state)
	assert_true(result.valid, "accepts valid worker/build/task shapes",
		str(result.get("error", "")))

	# A side anchor (10x24=240) should also be accepted.
	var side_state := good_state.duplicate()
	side_state["grid_w"] = 10
	side_state["grid_h"] = 24
	side_state["anchor_family"] = "side"
	# Pad tiles so we exercise the size-matching path rather than the
	# tile-empty shortcut above.
	var side_tiles: Array = []
	for _i in range(240):
		side_tiles.append({"kind": "tree", "amount": 0, "resource": "wood", "build_kind": ""})
	side_state["tiles"] = side_tiles
	result = gs.validate_save_schema(side_state)
	assert_true(result.valid, "accepts side anchor with matching tile count",
		str(result.get("error", "")))

# ---------------------------------------------------------------------------
# Flow 6: grid sizing consistency (issue #236)
# ---------------------------------------------------------------------------

func flow_grid_sizing_consistency(gs: Node) -> void:
	print("\n=== Flow 6: grid sizing consistency ===")

	var base := _minimal_valid_state()

	# Tile count does not match grid_w * grid_h
	base["grid_w"] = 32
	base["grid_h"] = 5
	# 158 tiles (not 160)
	var wrong_grid_tiles: Array = []
	for _i in range(158):
		wrong_grid_tiles.append({"kind": "tree", "amount": 0, "resource": "wood", "build_kind": ""})
	base["tiles"] = wrong_grid_tiles
	assert_false(gs.validate_save_schema(base).valid,
		"rejects tile count that does not equal grid_w*grid_h")

	# Hardcoded grid sizes that did not come from LayoutMath should be rejected
	# even when grid_w/grid_h are absent (no fallback to legacy after migration).
	var odd_sizes := _minimal_valid_state()
	odd_sizes["tiles"] = [{"kind": "tree", "amount": 1, "resource": "wood", "build_kind": ""}]
	assert_false(gs.validate_save_schema(odd_sizes).valid,
		"rejects a tile count (1) outside LayoutMath-derived grid sizes")

	# A known LayoutMath size (160) should be accepted without grid_w/grid_h.
	var sized := _minimal_valid_state()
	var t160: Array = []
	for _i in range(160):
		t160.append({"kind": "tree", "amount": 0, "resource": "wood", "build_kind": ""})
	sized["tiles"] = t160
	assert_true(gs.validate_save_schema(sized).valid,
		"accepts 160 tiles (LayoutMath bottom anchor) without grid dims")

	# Negative or zero grid dims are rejected
	var bad_dims := _minimal_valid_state()
	bad_dims["grid_w"] = 0
	bad_dims["grid_h"] = 5
	assert_false(gs.validate_save_schema(bad_dims).valid,
		"rejects zero grid_w")

# ---------------------------------------------------------------------------
# Flow 7: active_goal / completed_goal_ids / colony_stance / active_rewards
# ---------------------------------------------------------------------------

func flow_goal_and_stance_validation(gs: Node) -> void:
	print("\n=== Flow 7: goal/stance/reward validation ===")

	# active_goal referencing an unknown id is rejected
	var bad_goal := _minimal_valid_state()
	bad_goal["active_goal"] = {
		"id": "no_such_goal", "type": "resource",
		"target": {"resource": "wood", "amount": 5},
		"current_progress": 0, "completed": false,
	}
	assert_false(gs.validate_save_schema(bad_goal).valid,
		"rejects active_goal with unknown id")

	# active_goal empty dict is valid; a known goal is valid
	var known_goal := _minimal_valid_state()
	known_goal["active_goal"] = {
		"id": "gather_wood", "type": "resource",
		"target": {"resource": "wood", "amount": 5},
		"current_progress": 0, "completed": false,
	}
	assert_true(gs.validate_save_schema(known_goal).valid,
		"accepts active_goal with known goal id")

	# Unknown completed_goal_id is rejected
	var bad_completed := _minimal_valid_state()
	bad_completed["completed_goal_ids"] = ["gather_wood", "made_up_goal"]
	assert_false(gs.validate_save_schema(bad_completed).valid,
		"rejects completed_goal_ids with unknown entry")

	# Invalid colony_stance is rejected
	var bad_stance := _minimal_valid_state()
	bad_stance["colony_stance"] = "hyper_aggressive"
	assert_false(gs.validate_save_schema(bad_stance).valid,
		"rejects unknown colony_stance")
	# Empty stance is OK (off = no override)
	var off_stance := _minimal_valid_state()
	off_stance["colony_stance"] = ""
	assert_true(gs.validate_save_schema(off_stance).valid,
		"accepts empty colony_stance")

	# active_rewards entries must be valid reward dictionaries
	var bad_reward := _minimal_valid_state()
	bad_reward["active_rewards"] = [{"type": "not_a_real_reward"}]
	assert_false(gs.validate_save_schema(bad_reward).valid,
		"rejects active_rewards with unknown reward type")

	# Non-dict reward entry is rejected
	var non_dict_reward := _minimal_valid_state()
	non_dict_reward["active_rewards"] = ["gather_speed"]
	assert_false(gs.validate_save_schema(non_dict_reward).valid,
		"rejects active_rewards entry that isn't a dictionary")

	# Completed with only known ids is accepted
	var good_completed := _minimal_valid_state()
	good_completed["completed_goal_ids"] = ["gather_wood", "build_hut"]
	assert_true(gs.validate_save_schema(good_completed).valid,
		"accepts completed_goal_ids containing only known goals")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _minimal_valid_state() -> Dictionary:
	return {
		"tick": 0,
		"resources": {"wood": 0, "stone": 0, "food": 0},
		"workers": [],
		"tiles": [],
		"builds": [],
		"events": [],
		"save_version": 2,
	}
