extends SceneTree
## Shared test harness for all tests/*.gd suites (issue #281).
##
## Each suite extends this script by path and overrides run_tests():
##
##   extends "res://tests/test_case.gd"
##
##   func run_tests() -> void:
##       assert_eq(1 + 1, 2, "math works")
##
## Conventions:
## - Suites stay individually runnable via
##   `godot --headless --path . --script res://tests/<file>.gd`.
## - Output contract (CI greps these): one `TEST <name>: <PASS|FAIL>` line per
##   assertion (FAIL lines carry an optional `— <detail>` suffix), then a
##   summary line; the process exits non-zero when anything failed.
## - Scripts from scripts/ have no class_name unless noted; access them with
##   `const X := preload("res://scripts/x.gd")`, never as bare globals.

var test_pass := 0
var test_fail := 0

## Suite name shown in the summary; defaults to the script's file name.
var suite_name := ""


func _initialize() -> void:
	if suite_name.is_empty():
		suite_name = String(get_script().resource_path).get_file().get_basename()
	await run_tests()
	_finish()


## Override in each suite. May use await.
func run_tests() -> void:
	assert_true(false, "%s: run_tests() not implemented" % suite_name)


func _finish() -> void:
	print("")
	print("=== %s summary: %d passed, %d failed ===" % [suite_name, test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("%s: ok" % suite_name)
		quit(0)


# ── Assertion vocabulary ──────────────────────────────────────────────────────
# All assertions record the result, print the contract line, and return the
# boolean outcome so callers can branch (e.g. skip dependent checks).

func assert_true(condition: Variant, name: String, detail: String = "") -> bool:
	var ok := bool(condition)
	if ok:
		test_pass += 1
		print("TEST %s: PASS" % name)
	else:
		test_fail += 1
		if detail.is_empty():
			print("TEST %s: FAIL" % name)
		else:
			print("TEST %s: FAIL — %s" % [name, detail])
	return ok


func assert_false(condition: Variant, name: String, detail: String = "") -> bool:
	return assert_true(not bool(condition), name, detail)


func assert_eq(actual: Variant, expected: Variant, name: String) -> bool:
	return assert_true(actual == expected, name, "expected %s, got %s" % [str(expected), str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, name: String) -> bool:
	return assert_true(actual != unexpected, name, "expected anything but %s" % str(unexpected))


func assert_null(value: Variant, name: String) -> bool:
	return assert_true(value == null, name, "expected null, got %s" % str(value))


func assert_not_null(value: Variant, name: String) -> bool:
	return assert_true(value != null, name, "expected non-null value")


## Works for any value exposing is_empty() (Dictionary, Array, String, ...).
func assert_empty(value: Variant, name: String) -> bool:
	return assert_true(value.is_empty(), name, "expected empty, got %s" % str(value))


func assert_not_empty(value: Variant, name: String) -> bool:
	return assert_true(not value.is_empty(), name, "expected non-empty value")
