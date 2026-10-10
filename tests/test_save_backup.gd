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
#
# Assertion helpers and the summary come from tests/test_case.gd.
# =============================================================================

func run_tests() -> void:
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
	flow_validation_rejects_invalid(gs)
	flow_validation_accepts_valid(gs)
	flow_grid_sizing_consistency(gs)
	flow_goal_and_stance_validation(gs)

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
