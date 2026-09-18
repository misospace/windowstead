extends "res://tests/test_case.gd"

# =============================================================================
# Tests for per-entry 'events' shape validation in validate_save_schema
# (issue #392).
#
# validate_save_schema accepted data.events as long as it was an Array, without
# checking the shape of each entry. _render_event_log and render_event_drawer
# then call int(entry.tick) / String(entry.text) on every entry, so a
# hand-edited or partially-migrated save with a non-Dictionary entry (or a
# Dictionary missing 'tick', or a non-numeric tick / non-string text) would
# raise a runtime error in main.gd instead of being rejected at load time.
#
# This suite asserts each malformed shape is rejected with a stable reason, and
# that a malformed 'events' entry is rejected through the real load path
# (load_game) so the player falls back to a fresh start, matching the existing
# state.resources rejection path (issue #378).
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

var _gs: Node

func run_tests() -> void:
	setup()
	flow_string_entry_rejected()
	flow_empty_dict_entry_rejected()
	flow_dict_missing_tick_rejected()
	flow_dict_missing_text_rejected()
	flow_nonnumeric_tick_rejected()
	flow_nonstring_text_rejected()
	flow_valid_events_accepted()
	flow_load_path_rejects_malformed_events()
	teardown()

func setup() -> void:
	_gs = GameState.new()
	# SceneTree-based: parent under the root viewport (issue #281 harness note).
	root.add_child(_gs)

func teardown() -> void:
	if _gs and is_instance_valid(_gs):
		_gs.queue_free()
	_gs = null

# A minimal state that passes every other check, so only 'events' can fail.
# The events array is the single variable under test.
func _state_with_events(events: Array) -> Dictionary:
	return {
		"save_version": 2,
		"tick": 3,
		"resources": {"wood": 1, "stone": 0, "food": 0},
		"workers": [],
		"tiles": [],
		"builds": [],
		"events": events,
	}

# 1) A non-Dictionary entry (a bare string) must be rejected.
func flow_string_entry_rejected() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events(["a plain string"]))
	assert_false(result.valid, "events[0] string entry rejected")
	assert_eq(result.reason, "events[0] must be a dictionary", "string entry stable reason")

# 2) A Dictionary missing 'tick' (empty dict) must be rejected.
func flow_empty_dict_entry_rejected() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events([{}]))
	assert_false(result.valid, "events[0] empty dict entry rejected")
	assert_eq(result.reason, "events[0] missing key 'tick'", "empty dict entry stable reason")

# 3) A Dictionary missing 'tick' (only 'text' present) must be rejected.
func flow_dict_missing_tick_rejected() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events([{"text": "x"}]))
	assert_false(result.valid, "events[0] missing tick rejected")
	assert_eq(result.reason, "events[0] missing key 'tick'", "missing-tick entry stable reason")

# 4) A Dictionary missing 'text' (only 'tick' present) must be rejected.
func flow_dict_missing_text_rejected() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events([{"tick": 5}]))
	assert_false(result.valid, "events[0] missing text rejected")
	assert_eq(result.reason, "events[0] missing key 'text'", "missing-text entry stable reason")

# 5) A Dictionary with a non-numeric tick (e.g. "nope") must be rejected.
func flow_nonnumeric_tick_rejected() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events([{"tick": "nope", "text": "x"}]))
	assert_false(result.valid, "events[0] non-numeric tick rejected")
	assert_eq(result.reason, "events[0].tick must be numeric", "non-numeric tick stable reason")

# 6) A Dictionary with a non-string text (e.g. an int) must be rejected.
func flow_nonstring_text_rejected() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events([{"tick": 5, "text": 42}]))
	assert_false(result.valid, "events[0] non-string text rejected")
	assert_eq(result.reason, "events[0].text must be string", "non-string text stable reason")

# 7) Well-formed entries (numeric tick + string text) must still be accepted.
func flow_valid_events_accepted() -> void:
	var result: Dictionary = _gs.validate_save_schema(_state_with_events([
		{"tick": 0, "text": "Colony started"},
		{"tick": 5, "text": "First tree gathered"},
	]))
	assert_true(result.valid, "well-formed events accepted", str(result.get("reason", "")))

# 8) A malformed 'events' entry is rejected through the real load path
#    (load_game) so the player falls back to a fresh start — matching the
#    state.resources rejection path from issue #378.
func flow_load_path_rejects_malformed_events() -> void:
	_gs.use_local_storage = false
	var path := "user://test_save_schema_events.save"
	_gs.save_game(_state_with_events([{"tick": "nope", "text": "x"}]), path)
	var loaded: Dictionary = _gs.load_game(path)
	assert_empty(loaded, "load_game returns {} for a malformed events entry")
	_remove_save_file(path)

# Helper: remove a temporary save file written by the load-path test.
func _remove_save_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
