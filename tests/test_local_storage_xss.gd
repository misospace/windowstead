extends "res://tests/test_case.gd"

# =============================================================================
# Tests for localStorage XSS prevention (issue #291 / #316).
#
# Two layers of coverage:
#
#   1. `JSON.stringify(...)` (used internally by game_state.gd) escapes every
#      character that could break out of a JavaScript string literal or
#      template literal — quotes, backticks, backslashes, control chars.
#
#   2. The exact JavaScript statement produced by the `build_local_storage_*`
#      helpers in game_state.gd is well-formed: each one is parseable as a
#      single function call whose JSON args round-trip back to the original
#      key/payload values. This catches regressions like #291 where the key
#      was concatenated directly into the eval string instead of being
#      JSON-encoded.
# =============================================================================

const GameState := preload("res://scripts/game_state.gd")

func run_tests() -> void:
	flow_json_stringify_escapes_single_quote()
	flow_json_stringify_escapes_backtick()
	flow_json_stringify_escapes_backslash()
	flow_json_stringify_escapes_double_quote()
	flow_json_stringify_escapes_newlines()
	flow_json_stringify_escapes_combined_special_chars()
	flow_write_eval_statement_round_trips_evil_key()
	flow_write_eval_statement_round_trips_evil_payload()
	flow_read_eval_statement_round_trips_evil_key()
	flow_remove_eval_statement_round_trips_evil_key()
	flow_eval_statement_has_single_call_shape()

# Verify that a key with a single quote is properly escaped by JSON.stringify.
# The output should use double quotes around the string, so single quotes pass through safely.
func flow_json_stringify_escapes_single_quote() -> void:
	var result = JSON.stringify("key'with'quotes")
	assert_true(result.begins_with('"') and result.ends_with('"'), "single-quote key is double-quoted by JSON.stringify")
	assert_true(result.find("'") >= 0, "single quotes preserved inside the string")

# Verify that a backtick (template literal delimiter) is safely handled.
func flow_json_stringify_escapes_backtick() -> void:
	var result = JSON.stringify("key`with`backticks")
	assert_true(result.begins_with('"') and result.ends_with('"'), "backtick key is double-quoted by JSON.stringify")
	assert_true(result.find("`") >= 0, "backticks preserved inside the string")

# Verify that backslashes are properly escaped.
func flow_json_stringify_escapes_backslash() -> void:
	var result = JSON.stringify("key\\with\\backslash")
	assert_true(result.begins_with('"') and result.ends_with('"'), "backslash key is double-quoted by JSON.stringify")
	assert_true(result.find("\\\\") >= 0, "backslashes are escaped in output")

# Verify that double quotes inside the key are escaped.
func flow_json_stringify_escapes_double_quote() -> void:
	var result = JSON.stringify('key"with"doubles')
	assert_true(result.begins_with('"') and result.ends_with('"'), "double-quote key is double-quoted by JSON.stringify")
	assert_true(result.find('\\"') >= 0, "inner double quotes are escaped with backslash")

# Verify that newlines and carriage returns are properly escaped.
func flow_json_stringify_escapes_newlines() -> void:
	var result = JSON.stringify("key\nwith\rnewlines")
	assert_true(result.begins_with('"') and result.ends_with('"'), "newline key is double-quoted by JSON.stringify")
	assert_true(result.find("\\n") >= 0, "newlines are escaped as \\n")
	assert_true(result.find("\\r") >= 0, "carriage returns are escaped as \\r")

# Verify that a combined attack string with multiple special characters round-trips safely.
func flow_json_stringify_escapes_combined_special_chars() -> void:
	var attack_key = "key'`\\\"with\nall\rchars"
	var result = JSON.stringify(attack_key)
	assert_true(result.begins_with('"') and result.ends_with('"'), "combined attack key is double-quoted")
	# Verify round-trip: parsing the stringified result gives back the original
	var parsed = JSON.parse_string(result)
	assert_eq(parsed, attack_key, "round-trip parse of combined special chars matches original")

# Verify the write eval statement, given an XSS-flavored key, still parses
# back to the original key — i.e. the key is fully encapsulated inside the
# JavaScript string literal and cannot terminate it.
func flow_write_eval_statement_round_trips_evil_key() -> void:
	var evil_key = "key';alert(1);//with\"backticks`and\\slashes"
	var statement = GameState.build_local_storage_write_eval(evil_key, "{}")
	var key_json = _extract_first_json_arg(statement, "localStorage.setItem(")
	assert_ne(key_json, "", "write statement has a key argument")
	var parsed = JSON.parse_string(key_json)
	assert_eq(parsed, evil_key, "write eval statement round-trips an evil key")

# Verify the write eval statement, given an XSS-flavored payload, still
# parses back to the original payload.
func flow_write_eval_statement_round_trips_evil_payload() -> void:
	var evil_payload = "{\"inject\":\"`); evil(); //\"}"
	var statement = GameState.build_local_storage_write_eval("SAVE_KEY", evil_payload)
	var value_json = _extract_second_json_arg(statement, "localStorage.setItem(")
	assert_ne(value_json, "", "write statement has a value argument")
	var parsed = JSON.parse_string(value_json)
	assert_eq(parsed, evil_payload, "write eval statement round-trips an evil payload")

# Verify the read eval statement, given an XSS-flavored key, still parses
# back to the original key.
func flow_read_eval_statement_round_trips_evil_key() -> void:
	var evil_key = "key';alert(1);//with\"backticks`and\\slashes"
	var statement = GameState.build_local_storage_read_eval(evil_key)
	assert_true(statement.begins_with("localStorage.getItem("), "read statement calls localStorage.getItem(")
	var key_json = statement.substr("localStorage.getItem(".length(), statement.length() - "localStorage.getItem(".length() - 1)
	var parsed = JSON.parse_string(key_json)
	assert_eq(parsed, evil_key, "read eval statement round-trips an evil key")

# Verify the remove eval statement, given an XSS-flavored key, still parses
# back to the original key.
func flow_remove_eval_statement_round_trips_evil_key() -> void:
	var evil_key = "key';alert(1);//with\"backticks`and\\slashes"
	var statement = GameState.build_local_storage_remove_eval(evil_key)
	assert_true(statement.begins_with("localStorage.removeItem("), "remove statement calls localStorage.removeItem(")
	var key_json = statement.substr("localStorage.removeItem(".length(), statement.length() - "localStorage.removeItem(".length() - 1)
	var parsed = JSON.parse_string(key_json)
	assert_eq(parsed, evil_key, "remove eval statement round-trips an evil key")

# All three eval statements should be a single call with no trailing junk
# after the closing paren — i.e. the attacker can't append another statement
# to the eval'd string.
func flow_eval_statement_has_single_call_shape() -> void:
	# The first "(" must be the call-opening paren and the last char must be the
	# call-closing ")". Any attacker-supplied parens are confined to the JSON
	# string args and cannot terminate or extend the eval'd call.
	var evil_key = "key'); alert(1); ("
	var write = GameState.build_local_storage_write_eval(evil_key, "{}")
	var read = GameState.build_local_storage_read_eval(evil_key)
	var remove = GameState.build_local_storage_remove_eval(evil_key)
	assert_true(write.begins_with("localStorage.setItem("), "write call opens with localStorage.setItem(")
	assert_true(write.ends_with(")"), "write call closes with a single trailing paren")
	assert_true(read.begins_with("localStorage.getItem("), "read call opens with localStorage.getItem(")
	assert_true(read.ends_with(")"), "read call closes with a single trailing paren")
	assert_true(remove.begins_with("localStorage.removeItem("), "remove call opens with localStorage.removeItem(")
	assert_true(remove.ends_with(")"), "remove call closes with a single trailing paren")

# Helper: extract the first JSON-string argument from a `prefix(...)` call.
# The statement always ends with `)`, so we strip the prefix and the trailing
# paren and pull out everything before the first top-level comma.
func _extract_first_json_arg(statement: String, prefix: String) -> String:
	assert_true(statement.begins_with(prefix), "statement begins with prefix: " + prefix)
	assert_true(statement.ends_with(")"), "statement ends with closing paren")
	var inner = statement.substr(prefix.length(), statement.length() - prefix.length() - 1)
	var comma_index = _find_top_level_comma(inner)
	if comma_index < 0:
		return inner
	return inner.substr(0, comma_index)

# Helper: extract the second JSON-string argument from a `prefix(a, b)` call.
# Returns the substring after the first top-level comma, stripped of the
# trailing `)`.
func _extract_second_json_arg(statement: String, prefix: String) -> String:
	assert_true(statement.begins_with(prefix), "statement begins with prefix: " + prefix)
	assert_true(statement.ends_with(")"), "statement ends with closing paren")
	var inner = statement.substr(prefix.length(), statement.length() - prefix.length() - 1)
	var comma_index = _find_top_level_comma(inner)
	if comma_index < 0:
		return ""
	return inner.substr(comma_index + 1).strip_edges()

# Find the index of the first comma that sits at depth 0 — i.e. outside of
# any JSON string literal. JSON.stringify always quotes its output with `"`,
# so we just skip over anything between matched double quotes.
func _find_top_level_comma(s: String) -> int:
	var in_string := false
	var escaped := false
	for i in range(s.length()):
		var c := s[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
			continue
		if c == "\"":
			in_string = true
		elif c == ",":
			return i
	return -1
