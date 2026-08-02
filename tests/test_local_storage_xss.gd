extends "res://tests/test_case.gd"

# =============================================================================
# Tests for localStorage XSS prevention (issue #291).
#
# Verifies that JSON.stringify() properly escapes special characters in keys,
# preventing injection of quote characters, backticks, or backslashes into the
# eval'd JavaScript.
# =============================================================================

func run_tests() -> void:
	flow_json_stringify_escapes_single_quote()
	flow_json_stringify_escapes_backtick()
	flow_json_stringify_escapes_backslash()
	flow_json_stringify_escapes_double_quote()
	flow_json_stringify_escapes_newlines()
	flow_json_stringify_escapes_combined_special_chars()

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
