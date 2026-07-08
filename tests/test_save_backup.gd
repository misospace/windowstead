extends SceneTree

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
# =============================================================================

var tests_run := 0
var tests_passed := 0
var tests_failed := 0
var failures := []

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _assert(condition: bool, msg: String) -> void:
	tests_run += 1
	if condition:
		tests_passed += 1
	else:
		failures.append("FAIL: %s" % msg)

func _assert_eq(actual, expected, msg: String) -> void:
	tests_run += 1
	if actual == expected:
		tests_passed += 1
	else:
		failures.append("FAIL: %s (expected %s, got %s)" % [msg, str(expected), str(actual)])

# ---------------------------------------------------------------------------
# Flow 1: backup_save creates a timestamped file
# ---------------------------------------------------------------------------

func flow_backup_creates_file() -> void:
	print("\n=== Flow 1: backup_save creates a timestamped file ===")
	var gs := load_game_state()
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
	var backup_path := gs.backup_save()
	_assert(not backup_path.is_empty(), "backup_save returns a path")
	_assert(backup_path.begins_with("user://"), "backup path starts with user://")
	_assert(backup_path.contains("windowstead-backup-"), "backup filename has prefix")

# ---------------------------------------------------------------------------
# Flow 2: restore_backup restores from the latest backup
# ---------------------------------------------------------------------------

func flow_restore_from_backup() -> void:
	print("\n=== Flow 2: restore_backup restores from the latest backup ===")
	var gs := load_game_state()
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
	var loaded := gs.load_game()
	_assert_eq(loaded.get("tick", -1), 50, "modified tick is 50")
	_assert_eq(loaded.get("resources", {}).get("wood", -1), 100, "modified wood is 100")

	# Restore backup
	var restored_path := gs.restore_backup()
	_assert(not restored_path.is_empty(), "restore_backup returns a path")

	# Verify restored state
	loaded = gs.load_game()
	_assert_eq(loaded.get("tick", -1), 10, "restored tick is 10")
	_assert_eq(loaded.get("resources", {}).get("wood", -1), 8, "restored wood is 8")
	_assert_eq(loaded.get("workers", []).size(), 0, "restored workers empty")
	_assert_eq(loaded.get("builds", []).size(), 0, "restored builds empty")

# ---------------------------------------------------------------------------
# Flow 3: list_backups returns newest-first sorted list
# ---------------------------------------------------------------------------

func flow_list_backups_sorted() -> void:
	print("\n=== Flow 3: list_backups returns newest-first sorted list ===")
	var gs := load_game_state()
	gs.clear_game()

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

	var backups := gs.list_backups()
	_assert_eq(backups.size(), 3, "three backups exist")
	_assert(backups[0] > backups[1], "first backup is newest (sorted reverse)")
	_assert(backups[1] > backups[2], "second backup is older than first")

# ---------------------------------------------------------------------------
# Flow 4: validate_save_schema rejects invalid worker/build/task shapes
# ---------------------------------------------------------------------------

func flow_validation_rejects_invalid() -> void:
	print("\n=== Flow 4: validate_save_schema rejects invalid shapes ===")
	var gs := load_game_state()

	# Invalid worker: missing name
	var bad_worker := {
		"tick": 0, "resources": {"wood": 1}, "harvested": {},
		"workers": [{"pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}}],
		"tiles": [], "builds": [], "events": [],
	}
	var result := gs.validate_save_schema(bad_worker)
	_assert(not result.valid, "rejects worker missing name")

	# Invalid worker: negative break_ticks
	bad_worker["workers"] = [{"name": "Jun", "pos": {"x": 0, "y": 0}, "carrying": {}, "task": {}, "break_ticks": -5}]
	result = gs.validate_save_schema(bad_worker)
	_assert(not result.valid, "rejects negative break_ticks")

	# Invalid build: missing id
	var bad_build := {
		"tick": 0, "resources": {"wood": 1}, "harvested": {},
		"workers": [], "tiles": [],
		"builds": [{"kind": "hut", "pos": {"x": 0, "y": 0}, "complete": false}],
		"events": [],
	}
	result = gs.validate_save_schema(bad_build)
	_assert(not result.valid, "rejects build missing id")

	# Invalid worker: non-numeric carrying value
	bad_worker["workers"] = [{"name": "Jun", "pos": {"x": 0, "y": 0}, "carrying": {"wood": "bad"}, "task": {}}]
	result = gs.validate_save_schema(bad_worker)
	_assert(not result.valid, "rejects non-numeric carrying value")

# ---------------------------------------------------------------------------
# Flow 5: validate_save_schema accepts valid worker/build/task shapes
# ---------------------------------------------------------------------------

func flow_validation_accepts_valid() -> void:
	print("\n=== Flow 5: validate_save_schema accepts valid shapes ===")
	var gs := load_game_state()

	var good_state := {
		"tick": 10, "resources": {"wood": 8, "stone": 4}, "harvested": {"wood": 0},
		"workers": [
			{"name": "Jun", "pos": {"x": 11, "y": 2}, "prev_pos": {"x": 11, "y": 2}, "carrying": {"wood": 2}, "task": {"kind": "haul"}, "break_ticks": 0},
		],
		"tiles": [{"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""}],
		"builds": [
			{"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": false, "delivered": {}, "progress": 0.5},
		],
		"events": [{"tick": 5, "text": "test event"}],
	}
	var result := gs.validate_save_schema(good_state)
	_assert(result.valid, "accepts valid worker/build/task shapes")

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

func _initialize() -> void:
	print("===========================================")
	print("  Windowstead Save Backup & Validation Tests")
	print("===========================================")

	flow_backup_creates_file()
	flow_restore_from_backup()
	flow_list_backups_sorted()
	flow_validation_rejects_invalid()
	flow_validation_accepts_valid()

	print("\n===========================================")
	print("  Results: %d/%d passed, %d failed" % [tests_passed, tests_run, tests_failed])
	print("===========================================")

	for f in failures:
		print("  " + f)

	if tests_failed > 0:
		print("\nBackup & validation tests FAILED")
		quit(1)
	else:
		print("\nAll backup & validation tests passed")
		quit(0)


func load_game_state() -> Node:
	var gs_script := load("res://scripts/game_state.gd")
	return gs_script.new()
