extends "res://tests/test_case.gd"

# =============================================================================
# Tests for the web (localStorage) backup lifecycle in GameState (issue #404).
#
# backup_save()/list_backups()/restore_backup() were filesystem-only, so on the
# web build the pre-reset backup in main.gd never happened and list/restore
# could not see a localStorage save. The web branch now stores all backups as
# an aggregated JSON dictionary under BACKUP_STORAGE_KEY, a separate key from
# SAVE_KEY so backups survive clear_game().
#
# The web branch is forced with use_local_storage=true and the reader, writer,
# and remover hooks are stubbed with closures over an in-memory dictionary of
# raw string payloads, so the branch runs headless with no browser.
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node
var _ls: Dictionary = {}
var _fail_write_keys: Dictionary = {}
var _prior_use: bool
var _prior_reader: Callable
var _prior_writer: Callable
var _prior_remover: Callable

func run_tests() -> void:
	await setup()
	flow_backup_creates_web_backup()
	flow_list_backups_newest_first_web()
	flow_restore_backup_web()
	flow_backup_pruning_web()
	flow_clear_game_keeps_web_backups()
	flow_backup_skips_when_no_live_save()
	flow_backup_write_failure_returns_empty()
	flow_restore_write_failure_returns_empty()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	await process_frame
	_prior_use = _gs.use_local_storage
	_prior_reader = _gs._local_storage_reader
	_prior_writer = _gs._local_storage_writer
	_prior_remover = _gs._local_storage_remover
	_gs.use_local_storage = true
	_gs._local_storage_reader = func(key: String) -> Dictionary:
		if not _ls.has(key):
			return {}
		var parsed = JSON.parse_string(String(_ls[key]))
		if typeof(parsed) == TYPE_STRING:
			parsed = JSON.parse_string(parsed)
		return parsed if parsed is Dictionary else {}
	_gs._local_storage_writer = func(key: String, payload: String) -> bool:
		if _fail_write_keys.has(key):
			return false
		_ls[key] = payload
		return true
	_gs._local_storage_remover = func(key: String) -> void:
		_ls.erase(key)

func teardown() -> void:
	if _gs and is_instance_valid(_gs):
		_gs.use_local_storage = _prior_use
		_gs._local_storage_reader = _prior_reader
		_gs._local_storage_writer = _prior_writer
		_gs._local_storage_remover = _prior_remover
		_gs.queue_free()
	_gs = null
	_ls = {}
	_fail_write_keys.clear()

# 1) backup_save() persists the live save into the aggregated web-backup key.
func flow_backup_creates_web_backup() -> void:
	_ls.clear()
	_gs.save_game(_valid_state(1))
	var key: String = _gs.backup_save()
	assert_true(not key.is_empty(), "web backup_save returns a non-empty key")
	assert_true(key.begins_with(GameState.BACKUP_PREFIX), "web backup key carries the backup prefix")
	assert_true(_ls.has(GameState.BACKUP_STORAGE_KEY), "web backup stored under BACKUP_STORAGE_KEY")
	var backups := _parsed_backups()
	assert_true(backups.has(key), "BACKUP_STORAGE_KEY contains the returned key")
	if backups.has(key):
		assert_eq(int((backups[key] as Dictionary).get("tick", -1)), 1, "stored web backup holds the saved tick")

# 2) list_backups() exposes web backups newest-first.
func flow_list_backups_newest_first_web() -> void:
	_ls.clear()
	_gs._backup_counter = 0
	_gs.save_game(_valid_state(1))
	_gs.backup_save()
	_gs.save_game(_valid_state(2))
	_gs.backup_save()
	_gs.save_game(_valid_state(3))
	_gs.backup_save()
	var names: Array[String] = _gs.list_backups()
	if not assert_eq(names.size(), 3, "three web backups are listed"):
		return
	assert_true(names[0] > names[1], "web list_backups is newest-first (0 > 1)")
	assert_true(names[1] > names[2], "web list_backups is newest-first (1 > 2)")
	var backups := _parsed_backups()
	assert_eq(int((backups[names[0]] as Dictionary).get("tick", -1)), 3, "newest web backup holds tick 3")
	assert_eq(int((backups[names[2]] as Dictionary).get("tick", -1)), 1, "oldest web backup holds tick 1")

# 3) restore_backup() rewrites the live web save from the latest backup.
func flow_restore_backup_web() -> void:
	_ls.clear()
	_gs._backup_counter = 0
	_gs.save_game(_valid_state(10))
	_gs.backup_save()
	_gs.save_game(_valid_state(50))
	var restored: String = _gs.restore_backup()
	assert_true(not restored.is_empty(), "web restore_backup returns a non-empty key")
	var loaded: Dictionary = _gs.load_game()
	assert_eq(int(loaded.get("tick", -1)), 10, "web restore_backup restores the pre-overwrite save")

# 4) backup_save() prunes the oldest web backups beyond MAX_BACKUPS.
func flow_backup_pruning_web() -> void:
	_ls.clear()
	# Zero-padding-free counters are only unique-per-second; resetting keeps
	# created names strictly increasing within this flow so lexicographic
	# newest-first ordering is deterministic without wall-clock delays.
	_gs._backup_counter = 0
	var created: Array[String] = []
	for i in int(GameState.MAX_BACKUPS) + 1:
		_gs.save_game(_valid_state(i + 1))
		created.append(_gs.backup_save())
	var names: Array[String] = _gs.list_backups()
	assert_eq(names.size(), int(GameState.MAX_BACKUPS), "web pruning keeps only MAX_BACKUPS backups")
	assert_false(names.has(created[0]), "web pruning drops the oldest backup")
	assert_true(names.has(created[created.size() - 1]), "web pruning keeps the newest backup")

# 5) clear_game() removes the live save but leaves web backups restorable.
func flow_clear_game_keeps_web_backups() -> void:
	_ls.clear()
	_gs._backup_counter = 0
	_gs.save_game(_valid_state(7))
	assert_true(not _gs.backup_save().is_empty(), "web backup created before clear_game")
	_gs.clear_game()
	assert_false(_ls.has(GameState.SAVE_KEY), "clear_game removes the live web save")
	assert_true(_ls.has(GameState.BACKUP_STORAGE_KEY), "clear_game keeps the web backup storage key")
	assert_true(not _gs.list_backups().is_empty(), "web backups remain listable after clear_game")
	var restored: String = _gs.restore_backup()
	assert_true(not restored.is_empty(), "web restore_backup works after clear_game")
	var loaded: Dictionary = _gs.load_game()
	assert_eq(int(loaded.get("tick", -1)), 7, "web restore_backup recovers the pre-clear save")

# 6) backup_save() is a no-op when there is no live save to back up.
func flow_backup_skips_when_no_live_save() -> void:
	_ls.clear()
	assert_eq(_gs.backup_save(), "", "web backup_save with no live save returns empty")
	assert_false(_ls.has(GameState.BACKUP_STORAGE_KEY), "web backup_save writes no storage key without a live save")

# 7) backup_save() reports empty when the aggregated write fails.
func flow_backup_write_failure_returns_empty() -> void:
	_ls.clear()
	_gs.save_game(_valid_state(4))
	_fail_write_keys[GameState.BACKUP_STORAGE_KEY] = true
	assert_eq(_gs.backup_save(), "", "web backup_save returns empty when the write fails")
	_fail_write_keys.clear()

# 8) restore_backup() reports empty when rewriting the live save fails.
func flow_restore_write_failure_returns_empty() -> void:
	_ls.clear()
	_gs._backup_counter = 0
	_gs.save_game(_valid_state(8))
	_gs.backup_save()
	_gs.save_game(_valid_state(80))
	_fail_write_keys[GameState.SAVE_KEY] = true
	assert_eq(_gs.restore_backup(), "", "web restore_backup returns empty when the live write fails")
	_fail_write_keys.clear()
	assert_eq(int(_gs.load_game().get("tick", -1)), 80, "failed web restore leaves the live save untouched")

# ── Helpers ──────────────────────────────────────────────────────────────────

func _valid_state(tick: int) -> Dictionary:
	return {
		"save_version": 2,
		"tick": tick,
		"resources": {"wood": 0, "stone": 0, "food": 0},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"workers": [],
		"tiles": [],
		"builds": [],
		"events": [],
	}

func _parsed_backups() -> Dictionary:
	if not _ls.has(GameState.BACKUP_STORAGE_KEY):
		return {}
	var parsed: Variant = JSON.parse_string(String(_ls[GameState.BACKUP_STORAGE_KEY]))
	return parsed if parsed is Dictionary else {}
