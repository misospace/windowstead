# Regression test for issue #247: worker names must remain unique after the
# WORKER_NAMES pool is exhausted. Before the fix, the 11th worker was named
# "Jun" again — colliding with the 1st. The fix appends a numeric seed to
# the displayed name and preserves a `base_name` so badge color / sprite
# caches still resolve to the cycle-1 palette.
#
# Self-contained SceneTree runner, pattern mirrors tests/test_recruit_worker.gd.

extends SceneTree
## Tests that recruits past the WORKER_NAMES pool (size 10) get unique
## suffixed names and that their `base_name` still maps to the original
## WORKER_BADGE_COLORS palette entry (issue #247).

const Constants := preload("res://scripts/constants.gd")
const Main := preload("res://scripts/main.gd")


var _failures: Array[String] = []
var _test_pass: int = 0
var _test_fail: int = 0


func _initialize() -> void:
	_run_test("cycle_one_names_are_bare")
	_run_test("eleventh_worker_is_suffixed")
	_run_test("all_recruited_names_are_unique")
	_run_test("badge_color_key_prefers_base_name")
	print("")
	print("=== test_recruit_worker_pool_overflow summary: %d passed, %d failed ===" % [_test_pass, _test_fail])
	if _test_fail > 0:
		print("FAILURES DETECTED")
		quit(1)
	else:
		print("test_recruit_worker_pool_overflow: ok")
		quit(0)


func _run_test(method_name: String) -> void:
	print("")
	print("--- ", method_name, " ---")
	var runner: Main = Main.new()
	root.add_child(runner)
	# Seed with enough completed huts (cap = 2 + 2*N) so we can recruit
	# well past the 10-entry WORKER_NAMES pool. 5 huts → cap 12.
	var builds: Array = [
		{"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 2, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 3, "kind": "hut", "pos": {"x": 4, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 4, "kind": "hut", "pos": {"x": 5, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
		{"id": 5, "kind": "hut", "pos": {"x": 6, "y": 2}, "complete": true, "delivered": {"wood": 6, "stone": 2}, "progress": 1.0},
	]
	runner.state["buildings"] = builds
	# Recruit one more than the pool size (10 entries) so we cross into cycle 2.
	var pool_size: int = Constants.WORKER_NAMES.size()
	var total: int = pool_size + 1
	for _i in range(total):
		_assert(runner.can_recruit_worker(), "precondition: can recruit a worker")
		runner.recruit_worker()
	_assert_eq(runner.state.workers.size(), total, "all recruits persisted")
	call(method_name, runner)


func cycle_one_names_are_bare(runner: Main) -> void:
	# Workers 1..N (where N == pool_size) keep their bare, human-readable name.
	for i in range(Constants.WORKER_NAMES.size()):
		var worker: Dictionary = runner.state.workers[i]
		var expected: String = Constants.WORKER_NAMES[i]
		var actual: String = String(worker.get("name", ""))
		_assert_eq(actual, expected, "worker #%d bare name" % (i + 1))


func eleventh_worker_is_suffixed(runner: Main) -> void:
	# The worker recruited past the cycle boundary gets a numeric seed so it
	# cannot collide with workers 1..N.
	var worker: Dictionary = runner.state.workers[Constants.WORKER_NAMES.size()]
	var display: String = String(worker.get("name", ""))
	var base: String = String(worker.get("base_name", ""))
	_assert(display != base, "worker past pool has suffixed name", "expected suffixed name, got %s" % display)
	var expected_suffix: int = Constants.WORKER_NAMES.size() + 1
	if not display.ends_with(str(expected_suffix)):
		_test_fail += 1
		print("TEST worker past pool has numeric seed: FAIL — expected suffix %d, got %s" % [expected_suffix, display])
	else:
		_test_pass += 1
		print("TEST worker past pool has numeric seed: PASS")


func all_recruited_names_are_unique(runner: Main) -> void:
	var seen: Dictionary = {}
	var dupes: Array[String] = []
	for worker in runner.state.workers:
		var display: String = String(worker.get("name", ""))
		if seen.has(display):
			dupes.append(display)
		seen[display] = true
	_assert(dupes.is_empty(), "all recruited workers have unique names", "duplicates: %s" % str(dupes))


func badge_color_key_prefers_base_name(runner: Main) -> void:
	# Badge color / sprite-texture caches are keyed by `base_name`, not
	# `name`, so a cycle-2 worker named "Jun11" still resolves to the same
	# palette as cycle-1 "Jun".
	var pool_size: int = Constants.WORKER_NAMES.size()
	var last_worker: Dictionary = runner.state.workers[pool_size]
	var expected_base: String = Constants.WORKER_NAMES[0] # "Jun" because pool wraps
	var actual_base: String = String(last_worker.get("base_name", ""))
	_assert_eq(actual_base, expected_base, "base_name of overflow worker")
	_assert(Constants.WORKER_BADGE_COLORS.has(actual_base), "WORKER_BADGE_COLORS has base_name entry", "missing entry for %s" % actual_base)


# Minimal local assert helpers so the test stays self-contained (no shared
# script-test infra required).


func _assert(condition: Variant, name: String, detail: String = "") -> void:
	if not condition:
		_test_fail += 1
		if not detail.is_empty():
			print("TEST %s: FAIL — %s" % [name, detail])
		else:
			print("TEST %s: FAIL" % name)
	else:
		_test_pass += 1
		print("TEST %s: PASS" % name)


func _assert_eq(actual: Variant, expected: Variant, name: String) -> void:
	_assert(actual == expected, name, "expected %s, got %s" % [str(expected), str(actual)])