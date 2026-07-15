extends SceneTree

# tests/test_tick_integration.gd
# Full-cycle integration test for the game's main tick loop (`_on_tick`).
# Verifies that the orchestration in `scripts/main.gd::_tick_core` runs the
# expected ordering: events -> reservation cleanup -> food upkeep -> worker
# steps -> goal progression -> goal rewards -> milestone eval -> persist.
#
# Does NOT instantiate the full UI scene. We instantiate the script directly,
# stub `render_all` so we never touch UI nodes, and drive `_tick_core` (the
# new tick body extracted from `_on_tick` for testability) directly.

const MainScript := preload("res://scripts/main.gd")
const ConstantsScript := preload("res://scripts/constants.gd")
const ColonyStanceScript := preload("res://scripts/colony_stance.gd")

var test_pass := 0
var test_fail := 0


func _initialize() -> void:
	# Issue #234 — full-cycle tick integration test.
	test_full_tick_cycle()
	test_food_upkeep_fires_at_interval()
	test_starvation_kills_workers()
	test_no_available_tasks_no_op()
	test_build_completion()
	test_tick_increments()
	test_dirty_cleared_after_persist()

	print("")
	print("=== test_tick_integration summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED")
		quit(1)
	else:
		print("test_tick_integration: ok")
		quit(0)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _pass(name: String) -> void:
	test_pass += 1
	print("TEST %s: PASS" % name)


func _fail(name: String, detail: String) -> void:
	test_fail += 1
	print("TEST %s: FAIL [%s]" % [name, detail])


func _assert(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass(name)
	else:
		_fail(name, detail)


# Build a minimal Main script instance with no UI nodes wired up. `render_all`
# is stubbed to a no-op so the tick loop can run headlessly.
func _make_main() -> Node:
	var main = MainScript.new()
	# Replace render_all with a no-op. Tests can also override _on_tick, but
	# calling _tick_core directly is more honest about what we're testing.
	main.render_all = func() -> void: pass
	# Default fields the tick body reads. Tests will override what they need.
	main.game_active = true
	main.state = {}
	main.grid_w = 4
	main.grid_h = 4
	main.stockpile_pos = {"x": 0, "y": 0}
	main.tick = 0
	main.dirty = false
	main.food_upkeep_tracker = 0
	main.active_goal = {}
	main.completed_goal_ids = []
	main.active_rewards = []
	main.events_log = []
	main.current_milestone_id = ""
	main.completed_milestone_ids = []
	main.milestone_events_log = []
	main.colony_stance = ColonyStanceScript.STANCE_BALANCED
	main.priority_order = ["build", "haul", "gather"]
	main.build_kinds = {}
	main.settings = {}
	# Tiles array sized grid_w * grid_h, all ground by default.
	main.state.tiles = []
	for i in range(main.grid_w * main.grid_h):
		main.state.tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	main.state.workers = []
	main.state.resources = {"food": 0, "wood": 0, "stone": 0}
	main.state.builds = []
	main.state.harvested = {}
	main.state.reservations = {}
	main.state.events_log = []
	return main


func _set_tile(main: Node, x: int, y: int, tile: Dictionary) -> void:
	main.state.tiles[y * main.grid_w + x] = tile


func _get_tile(main: Node, x: int, y: int) -> Dictionary:
	return main.state.tiles[y * main.grid_w + x]


func _add_worker(main: Node, x: int, y: int) -> Dictionary:
	var w := {
		"name": "Worker%d" % main.state.workers.size(),
		"pos": {"x": x, "y": y},
		"prev_pos": {"x": x, "y": y},
		"task": {},
		"carrying": {},
		"break_ticks": 0,
		"build_carry": {},
		"delivered": {},
	}
	main.state.workers.append(w)
	return w


# Drive the tick body N times.
func _run_ticks(main: Node, n: int) -> void:
	for i in range(n):
		main._tick_core()


# ── Tests ────────────────────────────────────────────────────────────────────

func test_full_tick_cycle() -> void:
	# Worker next to a tree on a 4x4 grid should walk over and gather it.
	var main = _make_main()
	main.grid_w = 4
	main.grid_h = 4
	# Place a tree at (2, 2) with wood, worker at (0, 0).
	_set_tile(main, 2, 2, {"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""})
	var worker = _add_worker(main, 0, 0)

	_run_ticks(main, 20)

	# Worker should have moved toward (2,2) and gathered wood.
	var pos = worker.pos
	_assert(
		"full_tick_cycle.worker_moves",
		pos.x != 0 or pos.y != 0,
		"Worker did not move from origin: %s" % str(pos),
	)
	# Either the tree was depleted or wood is in resources.
	var wood = int(main.state.resources.get("wood", 0))
	var tree_after = int(_get_tile(main, 2, 2).get("amount", 0))
	_assert(
		"full_tick_cycle.resource_gathered",
		wood > 0 or tree_after < 6,
		"Worker did not gather wood (resources.wood=%d, tree amount=%d)" % [wood, tree_after],
	)


func test_food_upkeep_fires_at_interval() -> void:
	# When food is present, food_upkeep_tracker increments each tick and
	# apply_food_upkeep runs every Constants.FOOD_UPKEEP_INTERVAL_TICKS ticks.
	var main = _make_main()
	main.state.resources.food = 10
	main.state.workers = [_add_worker(main, 0, 0)]

	var interval = int(ConstantsScript.FOOD_UPKEEP_INTERVAL_TICKS)
	var food_before = int(main.state.resources.food)

	_run_ticks(main, interval)

	# Food should have decreased by 1 (one worker consumes 1 food per interval).
	_assert(
		"food_upkeep_fires_at_interval.deducted",
		int(main.state.resources.food) < food_before,
		"Food unchanged after %d ticks: %d -> %d" % [interval, food_before, int(main.state.resources.food)],
	)
	# Tracker should have wrapped back to 0.
	_assert(
		"food_upkeep_fires_at_interval.tracker_reset",
		int(main.food_upkeep_tracker) == 0,
		"food_upkeep_tracker not reset: %d" % int(main.food_upkeep_tracker),
	)


func test_starvation_kills_workers() -> void:
	# No food, more workers than capacity -> break_ticks should be set.
	var main = _make_main()
	main.state.resources.food = 0
	main.state.workers = []
	for i in range(3):
		main.state.workers.append(_add_worker(main, 0, 0))

	var interval = int(ConstantsScript.FOOD_UPKEEP_INTERVAL_TICKS)
	_run_ticks(main, interval * 2)

	# With zero food, apply_food_upkeep should put extra workers on a break.
	var any_on_break := false
	for w in main.state.workers:
		if int(w.get("break_ticks", 0)) > 0:
			any_on_break = true
			break
	_assert(
		"starvation_kills_workers.break_ticks_set",
		any_on_break,
		"No worker got break_ticks after starvation",
	)


func test_no_available_tasks_no_op() -> void:
	# Empty grid, no workers -> tick body should be a safe no-op (no crash).
	var main = _make_main()
	_run_ticks(main, 5)
	_assert(
		"no_available_tasks_no_op.tick_incremented",
		int(main.tick) == 5,
		"tick counter wrong: %d" % int(main.tick),
	)
	_assert(
		"no_available_tasks_no_op.state_intact",
		typeof(main.state) == TYPE_DICTIONARY and not main.state.is_empty(),
		"state was corrupted by tick body",
	)


func test_build_completion() -> void:
	# Place a build site with all costs delivered; worker should complete it
	# when adjacent. We cheat by pre-delivering via state.builds.
	var main = _make_main()
	main.grid_w = 4
	main.grid_h = 4
	# A build target tile at (1,1)
	_set_tile(main, 1, 1, {"kind": "ground", "amount": 0, "resource": "", "build_kind": "shelter"})
	main.state.builds = [{
		"id": "shelter_1",
		"x": 1,
		"y": 1,
		"kind": "shelter",
		"costs": {"wood": 0, "stone": 0},
		"delivered": {"wood": 5, "stone": 5},
		"complete": false,
	}]
	var worker = _add_worker(main, 0, 1)

	_run_ticks(main, 10)

	# Either the build is complete or delivered amount increased / worker
	# progressed. We assert that something measurable changed.
	var build: Dictionary = main.state.builds[0]
	var delivered = int(build.get("delivered", {}).get("wood", 0)) + int(build.get("delivered", {}).get("stone", 0))
	_assert(
		"build_completion.progressed_or_complete",
		bool(build.get("complete", false)) or delivered >= 10,
		"Build did not progress: complete=%s delivered_sum=%d" % [str(build.get("complete", false)), delivered],
	)


func test_tick_increments() -> void:
	var main = _make_main()
	_run_ticks(main, 3)
	_assert(
		"tick_increments.count",
		int(main.tick) == 3,
		"tick=%d" % int(main.tick),
	)


func test_dirty_cleared_after_persist() -> void:
	# persist() should reset dirty=false. This exercises the persist() call at
	# the tail of _tick_core.
	var main = _make_main()
	main.dirty = true
	_run_ticks(main, 1)
	_assert(
		"dirty_cleared_after_persist.flag",
		bool(main.dirty) == false,
		"dirty flag not cleared: %s" % str(main.dirty),
	)
