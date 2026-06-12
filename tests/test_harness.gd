## Shared test harness for all windowstead tests.
## Provides assertion helpers used across all individual test files.
## Import via:  const H := preload("res://tests/test_harness.gd")

extends SceneTree

static var pass := 0
static var fail := 0


func _initialize() -> void:
	# This file is a shared module — not meant to be run standalone.
	pass


# ── Assertion helpers ────────────────────────────────────────────────────────

static func assert(condition: Variant, name: String, detail: String = "") -> void:
	if condition:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s%s" % [name, " — " + detail if not detail.is_empty() else ""])
		fail += 1


static func assert_eq(actual: Variant, expected: Variant, name: String) -> void:
	if actual == expected:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s — expected %s, got %s" % [name, str(expected), str(actual)])
		fail += 1


static func assert_neq(actual: Variant, not_expected: Variant, name: String) -> void:
	if actual != not_expected:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s — should not be %s" % [name, str(not_expected)])
		fail += 1


static func assert_gt(a: Variant, b: Variant, name: String) -> void:
	if a > b:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s — expected %s > %s" % [name, str(a), str(b)])
		fail += 1


static func assert_lt(a: Variant, b: Variant, name: String) -> void:
	if a < b:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s — expected %s < %s" % [name, str(a), str(b)])
		fail += 1


static func assert_gte(a: Variant, b: Variant, name: String) -> void:
	if a >= b:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s — expected %s >= %s" % [name, str(a), str(b)])
		fail += 1


static func assert_lte(a: Variant, b: Variant, name: String) -> void:
	if a <= b:
		print("  PASS %s" % name)
		pass += 1
	else:
		print("  FAIL %s — expected %s <= %s" % [name, str(a), str(b)])
		fail += 1


static func assert_not_empty(d: Dictionary, name: String) -> void:
	assert(not d.is_empty(), name, "dictionary should not be empty")


static func assert_empty(d: Variant, name: String) -> void:
	assert(d.is_empty(), name, "should be empty")


# ── Float comparison helper ─────────────────────────────────────────────────

static func float_eq(a: float, b: float, epsilon: float = 0.001) -> bool:
	return abs(a - b) < epsilon


# ── Summary helper ───────────────────────────────────────────────────────────

static func print_summary(total: int) -> void:
	print("")
	print("=== test summary: %d passed, %d failed (total: %d) ===" % [pass, fail, total])
	if fail > 0:
		print("FAILURES DETECTED — CI should fail")
		quit(1)
	else:
		print("tests: ok")
		quit(0)
