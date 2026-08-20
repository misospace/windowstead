extends "res://tests/test_case.gd"

# ── Full-cycle tick integration tests (issue #234) ────────────────────────────
# Drives ColonySim.process_tick() — the entire per-tick orchestration that
# main.gd's _on_tick delegates to — against a minimal real game state, with no
# scene tree, UI, or autoloads. Covers worker movement, gathering + hauling,
# food upkeep cadence, goal completion/rotation, the dirty flag contract,
# starvation stalls, idle behavior, and build completion.

const ColonySim := preload("res://scripts/colony_sim.gd")
const Constants := preload("res://scripts/constants.gd")

const GRID := 5


func run_tests() -> void:
	test_tick_advances_and_worker_moves()
	test_gather_and_haul_cycle()
	test_food_upkeep_interval()
	test_goal_completion_and_rotation()
	test_dirty_flag_contract()
	test_starvation_stalls_builds()
	test_idle_when_no_tasks()
	test_build_completion()
	test_zero_workers_event_path()


# ── Setup helpers ─────────────────────────────────────────────────────────────

func _new_sim(resources: Dictionary, worker_positions: Array) -> ColonySim:
	var sim := ColonySim.new()
	sim.grid_w = GRID
	sim.grid_h = GRID
	sim.stockpile_pos = Vector2i(0, 0)
	sim.priority_order = ["build", "haul", "gather"] as Array[String]
	sim.rng.seed = 1234
	var tiles: Array = []
	for i in GRID * GRID:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	var workers: Array = []
	for i in worker_positions.size():
		var pos: Vector2i = worker_positions[i]
		workers.append({
			"name": Constants.WORKER_NAMES[i],
			"pos": {"x": pos.x, "y": pos.y},
			"prev_pos": {"x": pos.x, "y": pos.y},
			"carrying": {},
			"task": {},
			"break_ticks": 0,
		})
	sim.state = {
		"tick": 0,
		"resources": resources,
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": workers,
		"tiles": tiles,
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	sim.ensure_defaults()
	return sim


func _run_ticks(sim: ColonySim, count: int) -> void:
	for i in count:
		sim.process_tick()


func _has_event_containing(sim: ColonySim, needle: String) -> bool:
	for entry in sim.state.events:
		if String(entry.text).contains(needle):
			return true
	return false


# ── Tests ─────────────────────────────────────────────────────────────────────

func test_tick_advances_and_worker_moves() -> void:
	print("\n--- tick advances and worker moves toward resource ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(0, 0)])
	sim.set_tile(Vector2i(3, 0), {"kind": "tree", "amount": 2, "resource": "wood", "build_kind": ""})

	sim.process_tick()
	assert_eq(sim.tick(), 1, "tick: incremented to 1")
	var worker: Dictionary = sim.state.workers[0]
	assert_eq(String(worker.task.get("kind", "")), "gather", "tick: worker picked a gather task")
	assert_eq(sim.get_reserved("wood"), 1, "tick: gather task reserved the resource")
	assert_eq(ColonySim.data_to_vec(worker.pos), Vector2i(1, 0), "tick: worker stepped toward the tree")
	assert_eq(ColonySim.data_to_vec(worker.prev_pos), Vector2i(0, 0), "tick: prev_pos captured for interpolation")

	sim.process_tick()
	assert_eq(ColonySim.data_to_vec(sim.state.workers[0].pos), Vector2i(2, 0), "tick: worker keeps approaching")


func test_gather_and_haul_cycle() -> void:
	print("\n--- gather and haul cycle deposits resources ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(0, 0)])
	sim.set_tile(Vector2i(3, 0), {"kind": "tree", "amount": 2, "resource": "wood", "build_kind": ""})

	# 3 ticks out + gather + 3 ticks back + deposit, twice over ≈ 16 ticks.
	_run_ticks(sim, 20)
	assert_eq(int(sim.state.resources.get("wood", 0)), 2, "cycle: both wood units delivered to stockpile")
	assert_eq(int(sim.state.harvested.get("wood", 0)), 2, "cycle: harvested tally recorded")
	assert_eq(String(sim.get_tile(Vector2i(3, 0)).kind), "ground", "cycle: depleted tree reverted to ground")
	assert_eq(sim.get_reserved("wood"), 0, "cycle: reservation released after depletion")


func test_food_upkeep_interval() -> void:
	print("\n--- food upkeep fires on its interval ---")
	# 3 workers = 1 above BASE_WORKERS_NO_UPKEEP; empty grid so nobody works.
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 2)])

	_run_ticks(sim, Constants.FOOD_UPKEEP_INTERVAL_TICKS - 1)
	assert_eq(int(sim.state.resources.food), 10, "upkeep: no deduction before the interval")

	sim.process_tick()
	assert_eq(int(sim.state.resources.food), 10 - Constants.FOOD_PER_EXTRA_WORKER, "upkeep: deducted exactly on the interval tick")
	assert_true(_has_event_containing(sim, "The crew ate"), "upkeep: event logged")

	_run_ticks(sim, Constants.FOOD_UPKEEP_INTERVAL_TICKS)
	assert_eq(int(sim.state.resources.food), 10 - 2 * Constants.FOOD_PER_EXTRA_WORKER, "upkeep: fires again next interval")


func test_goal_completion_and_rotation() -> void:
	print("\n--- goal completes and rotates ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(0, 0)])
	assert_eq(String(sim.state.active_goal.get("id", "")), "gather_wood", "goal: first catalog goal seeded")

	# Satisfy the gather_wood target (10 harvested wood) out-of-band.
	sim.state.harvested["wood"] = 10
	sim.process_tick()

	assert_true(sim.state.completed_goal_ids.has("gather_wood"), "goal: completed id recorded")
	assert_eq(String(sim.state.active_goal.get("id", "")), "gather_stone", "goal: rotated to next catalog goal")
	assert_true(_has_event_containing(sim, "Goal completed: gather_wood"), "goal: completion event logged")
	assert_not_empty(sim.state.active_rewards, "goal: completion reward granted")
	assert_eq(String(sim.state.active_rewards[0].get("label", "")), "+1 food trickle", "goal: reward label from GoalReward catalog")


func test_dirty_flag_contract() -> void:
	print("\n--- dirty flag set by mutations, clearable by persist owner ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(0, 0)])
	sim.set_tile(Vector2i(3, 0), {"kind": "tree", "amount": 1, "resource": "wood", "build_kind": ""})
	sim.dirty = false

	# Movement alone is intentionally not a mutation point; the gather on the
	# 4th tick (3 tiles of travel, then harvest) is what dirties the state.
	_run_ticks(sim, 4)
	assert_true(sim.dirty, "dirty: tick with a gather mutation marks state dirty")

	sim.dirty = false
	var quiet := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(0, 0)])
	quiet.dirty = false
	quiet.process_tick()
	assert_false(quiet.dirty, "dirty: idle tick on an empty world stays clean")


func test_starvation_stalls_builds() -> void:
	print("\n--- starvation stalls build progress ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 0}, [Vector2i(2, 2)])
	# Fully delivered hut ready to build, worker already standing on it.
	sim.state.builds.append({
		"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2},
		"delivered": {"wood": 6, "stone": 2}, "progress": 0.0, "complete": false,
	})

	_run_ticks(sim, 5)
	var build: Dictionary = sim.get_build(1)
	assert_eq(float(build.progress), 0.0, "starvation: build progress frozen at zero food")
	assert_false(bool(build.complete), "starvation: build never completes")


func test_idle_when_no_tasks() -> void:
	print("\n--- workers idle when no tasks exist ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [Vector2i(2, 2)])
	_run_ticks(sim, 3)
	var worker: Dictionary = sim.state.workers[0]
	assert_true(worker.task.is_empty(), "idle: worker has no task on an empty world")
	assert_eq(ColonySim.data_to_vec(worker.pos), Vector2i(2, 2), "idle: worker does not wander")


func test_build_completion() -> void:
	print("\n--- build completes, grants bonus, satisfies milestone ---")
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 5}, [Vector2i(2, 2)])
	sim.state.builds.append({
		"id": 1, "kind": "hut", "pos": {"x": 2, "y": 2},
		"delivered": {"wood": 6, "stone": 2}, "progress": 0.0, "complete": false,
	})
	sim.set_tile(Vector2i(2, 2), {"kind": "foundation", "amount": 0, "resource": "", "build_kind": "hut"})

	# Build speed is 0.34/tick at full food → complete on the 3rd work tick.
	# Stop at 3 ticks so the chain ends at stockpile_food instead of racing past
	# it (stockpile_food is satisfied once resources.food reaches its target).
	_run_ticks(sim, 3)
	var build: Dictionary = sim.get_build(1)
	assert_true(bool(build.complete), "build: hut completed")
	assert_eq(String(sim.get_tile(Vector2i(2, 2)).kind), "hut", "build: tile converted to the structure")
	assert_eq(int(sim.state.resources.food), 5 + int(ColonySim.BUILD_COMPLETION_FOOD["hut"]), "build: completion food bonus granted")
	assert_true(_has_event_containing(sim, "finished"), "build: completion event logged")
	# The build_hut milestone should have completed and advanced.
	assert_true(sim.state.completed_milestone_ids.has("build_hut"), "build: hut milestone recorded")
	assert_eq(String(sim.state.current_milestone_id), "stockpile_food", "build: milestone chain advanced")


func test_zero_workers_event_path() -> void:
	print("\n--- zero-worker state survives ambient-event tick ---")
	# Regression test for issue #346 — a hand-edited / corrupt-but-schema-valid
	# save may carry an empty workers array. process_tick() already tolerates
	# this for the per-worker loop, but maybe_fire_event()'s break branch
	# indexed state.workers[rng.randi_range(0, size()-1)] without a guard, so
	# any time event_roll == 1 fired it raised on workers[0]/-1 and the tick
	# aborted. The fix must let the break branch no-op so the tick completes
	# without raising. CI's "SCRIPT ERROR" log grep is the regression check —
	# the assertions below just drive the path that previously crashed.
	var sim := _new_sim({"wood": 0, "stone": 0, "food": 10}, [])
	# Force the worker array to be empty — _new_sim seeds one worker, so we
	# override after construction.
	sim.state.workers = []
	assert_eq(sim.state.workers.size(), 0, "zero-worker state: workers array is empty")

	# Drive the tick loop well past one EVENT_INTERVAL_TICKS so
	# maybe_fire_event() runs under the default RNG. We don't depend on a
	# specific event_roll here — the previous bug raised any time it was 1,
	# so a non-crashing run over several intervals is the regression check.
	_run_ticks(sim, Constants.EVENT_INTERVAL_TICKS * 4)

	# Pin the RNG to a seed that reliably produces event_roll == 1 from
	# rng.randi_range(0, 2) and align tick to an EVENT_INTERVAL_TICKS
	# boundary so maybe_fire_event() actually runs. The convention matches
	# test_break_event_releases_gather_reservation in test_reservations.gd.
	sim.rng.seed = 2
	sim.state.tick = Constants.EVENT_INTERVAL_TICKS
	sim.maybe_fire_event()  # must not raise on an empty workers array
	assert_true(true, "zero-worker state: break event branch returned without error")

	# Keep ticking past the guarded fire to confirm process_tick() resumes
	# cleanly afterwards — the early return must not leave the loop in a
	# bad state.
	_run_ticks(sim, Constants.EVENT_INTERVAL_TICKS)
