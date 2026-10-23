extends "res://tests/test_case.gd"

# =============================================================================
# Tests for save_game()/load_game() path routing on the web build (issue #398).
#
# Both functions accept an optional `path` argument, but on the localStorage
# branch it was silently discarded: save_game always wrote SAVE_KEY and
# load_game always read SAVE_KEY. The web branch now maps a non-empty path to
# a distinct, deterministic localStorage slot (see
# GameState.local_storage_key_for_path) while the empty path keeps using
# SAVE_KEY, so the same in-process API round-trips identically on both
# platforms and existing web saves keep loading.
#
# The web branch is forced with use_local_storage=true and the reader/writer
# hooks are stubbed with closures over an in-memory dictionary of raw JSON
# payloads keyed by the ACTUAL key passed, so the branch runs headless with no
# browser.
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node
var _ls: Dictionary = {}
var _prior_use: bool
var _prior_reader: Callable
var _prior_writer: Callable

func run_tests() -> void:
	await setup()
	flow_default_path_uses_save_key_web()
	flow_custom_path_round_trips_web()
	flow_custom_paths_are_isolated_web()
	flow_custom_path_does_not_clobber_default_web()
	flow_key_mapping_is_deterministic()
	flow_derived_key_round_trips_through_json_eval()
	flow_desktop_branch_honors_path()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	root.add_child(_gs)
	await process_frame
	_prior_use = _gs.use_local_storage
	_prior_reader = _gs._local_storage_reader
	_prior_writer = _gs._local_storage_writer
	_gs.use_local_storage = true
	# Reader/writer stubs are keyed on the actual key argument, so a routing
	# regression (writing or reading the wrong key) shows up as an empty load.
	_gs._local_storage_reader = func(key: String) -> Dictionary:
		if not _ls.has(key):
			return {}
		var parsed = JSON.parse_string(String(_ls[key]))
		if typeof(parsed) == TYPE_STRING:
			parsed = JSON.parse_string(parsed)
		return parsed if parsed is Dictionary else {}
	_gs._local_storage_writer = func(key: String, payload: String) -> bool:
		_ls[key] = payload
		return true

func teardown() -> void:
	if _gs and is_instance_valid(_gs):
		_gs.use_local_storage = _prior_use
		_gs._local_storage_reader = _prior_reader
		_gs._local_storage_writer = _prior_writer
		_gs.queue_free()
	_gs = null
	_ls = {}

# 1) The default (empty path) still uses SAVE_KEY, so existing web saves load.
func flow_default_path_uses_save_key_web() -> void:
	_ls.clear()
	_gs.save_game(_valid_state(3))
	assert_true(_ls.has(GameState.SAVE_KEY), "web save with no path writes SAVE_KEY")
	var loaded: Dictionary = _gs.load_game()
	assert_eq(int(loaded.get("tick", -1)), 3, "web load with no path reads SAVE_KEY")

# 2) A non-empty path round-trips on the web branch instead of being discarded.
func flow_custom_path_round_trips_web() -> void:
	_ls.clear()
	_gs.save_game(_valid_state(42), "/foo")
	assert_true(_ls.has(GameState.local_storage_key_for_path("/foo")), "web custom path writes its routed key")
	assert_false(_ls.has(GameState.SAVE_KEY), "web custom path does not write SAVE_KEY")
	var loaded: Dictionary = _gs.load_game("/foo")
	assert_eq(int(loaded.get("tick", -1)), 42, "web custom path load returns the saved dictionary")

# 3) Two custom paths do not collide.
func flow_custom_paths_are_isolated_web() -> void:
	_ls.clear()
	_gs.save_game(_valid_state(11), "/a")
	_gs.save_game(_valid_state(22), "/b")
	assert_eq(int(_gs.load_game("/a").get("tick", -1)), 11, "web path /a is isolated from /b")
	assert_eq(int(_gs.load_game("/b").get("tick", -1)), 22, "web path /b is isolated from /a")

# 4) Writing a custom path must not overwrite the default SAVE_KEY slot.
func flow_custom_path_does_not_clobber_default_web() -> void:
	_ls.clear()
	_gs.save_game(_valid_state(10))
	_gs.save_game(_valid_state(99), "/slot2")
	assert_eq(int(_gs.load_game().get("tick", -1)), 10, "web default slot survives a custom-path save")
	assert_eq(int(_gs.load_game("/slot2").get("tick", -1)), 99, "web custom slot holds its own save")

# 5) The key mapping is deterministic and the empty path maps to SAVE_KEY.
func flow_key_mapping_is_deterministic() -> void:
	assert_eq(GameState.local_storage_key_for_path(""), GameState.SAVE_KEY, "empty path maps to SAVE_KEY")
	var first := GameState.local_storage_key_for_path("user://slot.save")
	var second := GameState.local_storage_key_for_path("user://slot.save")
	assert_eq(first, second, "same path maps to the same key")
	assert_ne(first, GameState.SAVE_KEY, "non-empty path maps away from SAVE_KEY")
	assert_ne(first, GameState.local_storage_key_for_path("user://other.save"), "different paths map to different keys")

# 6) A generated key still flows through the JSON-encoded eval helpers, so an
#    attacker-ish path cannot break out of the localStorage call (issue #316).
func flow_derived_key_round_trips_through_json_eval() -> void:
	var weird_path := "/weird\";alert(1)//`\\"
	var key := GameState.local_storage_key_for_path(weird_path)
	var statement := GameState.build_local_storage_read_eval(key)
	var arg := statement.substr("localStorage.getItem(".length(), statement.length() - "localStorage.getItem(".length() - 1)
	assert_eq(JSON.parse_string(arg), key, "derived key is JSON-encoded in the read eval statement")
	var write_statement := GameState.build_local_storage_write_eval(key, "{}")
	assert_true(write_statement.ends_with("; \"windowstead-write-ok\""), "derived key write eval keeps the success sentinel")

# 7) Desktop parity: the file branch honors a custom path too, so the same
#    call round-trips on both platforms.
func flow_desktop_branch_honors_path() -> void:
	_gs.use_local_storage = false
	var path := "user://test_path_routing.save"
	var other := "user://test_path_routing_other.save"
	_gs.save_game(_valid_state(7), path)
	assert_eq(int(_gs.load_game(path).get("tick", -1)), 7, "desktop custom path round-trips")
	assert_true(_gs.load_game(other).is_empty(), "desktop unset path is empty")
	_remove_save_file(path)
	_remove_save_file(other)

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

func _remove_save_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
