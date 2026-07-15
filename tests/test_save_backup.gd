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
#   7. Grid sizing: tile count must match grid_w*grid_h (issue #236)
#   8. active_goal/completed_goal_ids/colony_stance/active_rewards validation
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
	var result := gs.validate_save_schema(good_state)
	_assert(result.valid, "accepts valid worker/build/task shapes")

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
	_assert(result.valid, "accepts side anchor with matching tile count")

# ---------------------------------------------------------------------------
# Flow 6: grid sizing consistency (issue #236)
# ---------------------------------------------------------------------------

func flow_grid_sizing_consistency() -> void:
	print("\n=== Flow 6: grid sizing consistency ===")
	var gs := load_game_state()

	var base := _minimal_valid_state()

	# Tile count does not match grid_w * grid_h
	base["grid_w"] = 32
	base["grid_h"] = 5
	# 158 tiles (not 160)
	var wrong_grid_tiles: Array = []
	for _i in range(158):
		wrong_grid_tiles.append({"kind": "tree", "amount": 0, "resource": "wood", "build_kind": ""})
	base["tiles"] = wrong_grid_tiles
	_assert(not gs.validate_save_schema(base).valid,
		"rejects tile count that does not equal grid_w*grid_h")

	# Hardcoded grid sizes that did not come from LayoutMath should be rejected
	# even when grid_w/grid_h are absent (no fallback to legacy after migration).
	var odd_sizes := _minimal_valid_state()
	odd_sizes["tiles"] = [{"kind": "tree", "amount": 1, "resource": "wood", "build_kind": ""}]
	_assert(not gs.validate_save_schema(odd_sizes).valid,
		"rejects a tile count (1) outside LayoutMath-derived grid sizes")

	# A known LayoutMath size (160) should be accepted without grid_w/grid_h.
	var sized := _minimal_valid_state()
	var t160: Array = []
	for _i in range(160):
		t160.append({"kind": "tree", "amount": 0, "resource": "wood", "build_kind": ""})
	sized["tiles"] = t160
	_assert(gs.validate_save_schema(sized).valid,
		"accepts 160 tiles (LayoutMath bottom anchor) without grid dims")

	# Negative or zero grid dims are rejected
	var bad_dims := _minimal_valid_state()
	bad_dims["grid_w"] = 0
	bad_dims["grid_h"] = 5
	_assert(not gs.validate_save_schema(bad_dims).valid,
		"rejects zero grid_w")

# ---------------------------------------------------------------------------
# Flow 7: active_goal / completed_goal_ids / colony_stance / active_rewards
# ---------------------------------------------------------------------------

func flow_goal_and_stance_validation() -> void:
	print("\n=== Flow 7: goal/stance/reward validation ===")
	var gs := load_game_state()

	# active_goal referencing an unknown id is rejected
	var bad_goal := _minimal_valid_state()
	bad_goal["active_goal"] = {
		"id": "no_such_goal", "type": "resource",
		"target": {"resource": "wood", "amount": 5},
		"current_progress": 0, "completed": false,
	}
	_assert(not gs.validate_save_schema(bad_goal).valid,
		"rejects active_goal with unknown id")

	# active_goal empty dict is valid; a known goal is valid
	var known_goal := _minimal_valid_state()
	known_goal["active_goal"] = {
		"id": "gather_wood", "type": "resource",
		"target": {"resource": "wood", "amount": 5},
		"current_progress": 0, "completed": false,
	}
	_assert(gs.validate_save_schema(known_goal).valid,
		"accepts active_goal with known goal id")

	# Unknown completed_goal_id is rejected
	var bad_completed := _minimal_valid_state()
	bad_completed["completed_goal_ids"] = ["gather_wood", "made_up_goal"]
	_assert(not gs.validate_save_schema(bad_completed).valid,
		"rejects completed_goal_ids with unknown entry")

	# Invalid colony_stance is rejected
	var bad_stance := _minimal_valid_state()
	bad_stance["colony_stance"] = "hyper_aggressive"
	_assert(not gs.validate_save_schema(bad_stance).valid,
		"rejects unknown colony_stance")
	# Empty stance is OK (off = no override)
	var off_stance := _minimal_valid_state()
	off_stance["colony_stance"] = ""
	_assert(gs.validate_save_schema(off_stance).valid,
		"accepts empty colony_stance")

	# active_rewards entries must be valid reward dictionaries
	var bad_reward := _minimal_valid_state()
	bad_reward["active_rewards"] = [{"type": "not_a_real_reward"}]
	_assert(not gs.validate_save_schema(bad_reward).valid,
		"rejects active_rewards with unknown reward type")

	# Non-dict reward entry is rejected
	var non_dict_reward := _minimal_valid_state()
	non_dict_reward["active_rewards"] = ["gather_speed"]
	_assert(not gs.validate_save_schema(non_dict_reward).valid,
		"rejects active_rewards entry that isn't a dictionary")

	# Completed with only known ids is accepted
	var good_completed := _minimal_valid_state()
	good_completed["completed_goal_ids"] = ["gather_wood", "build_hut"]
	_assert(gs.validate_save_schema(good_completed).valid,
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
	flow_grid_sizing_consistency()
	flow_goal_and_stance_validation()

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
