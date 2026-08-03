extends "res://tests/test_case.gd"
# ── Unit tests for ColonySim static utility methods (data_to_vec, vec_to_data,
# step_toward) and instance methods (find_open_ground, is_pos_in_bounds,
# is_near_stockpile, seed_tile, rebuild_reservations_from_workers).
#
# Most of these are pure functions; the rest only need a minimal ColonySim
# instance with `state["tiles"]` and `state["workers"]` initialised.

const ColonySim := preload("res://scripts/colony_sim.gd")
const LayoutMath := preload("res://scripts/layout_math.gd")

const TILE_KIND_GROUND := "ground"
const TILE_KIND_TREE := "tree"
const TILE_KIND_ROCK := "rock"
const TILE_KIND_BERRIES := "berries"


func run_tests() -> void:
	test_data_to_vec_basic()
	test_data_to_vec_negative()
	test_data_to_vec_zero()
	test_vec_to_data_basic()
	test_vec_to_data_negative()
	test_data_to_vec_roundtrip()
	test_step_toward_positive_direction()
	test_step_toward_negative_direction()
	test_step_toward_same_position()
	test_step_toward_diagonal_adjacent()
	test_step_toward_distance_decreases()
	test_is_pos_in_bounds_inside()
	test_is_pos_in_bounds_negative()
	test_is_pos_in_bounds_at_max_boundary()
	test_is_pos_in_bounds_past_boundary()
	test_is_near_stockpile_far()
	test_find_open_ground_returns_valid_tile()
	test_seed_tile_deterministic()
	test_seed_tile_different_positions()
	test_seed_tile_kind_values()
	test_seed_tile_ground_zero_amount()
	test_rebuild_empty_state()
	test_rebuild_trust_existing_keeps_prior()
	test_rebuild_no_trust_overwrites()
	test_rebuild_gather_task()
	test_rebuild_haul_task()
	test_rebuild_mixed_tasks()
	test_rebuild_missing_task()
	test_rebuild_missing_resource_key()


# Build a minimal ColonySim instance for the instance-method tests. The default
# `_init()` leaves `state["tiles"]` empty, so we populate a tiles array sized to
# the bottom grid and seed it with `ground` so the open-ground finder works.
func _sim() -> ColonySim:
	var sim := ColonySim.new()
	var tiles: Array = []
	var total: int = LayoutMath.BOTTOM_GRID_W * LayoutMath.BOTTOM_GRID_H
	for i in total:
		tiles.append({"kind": TILE_KIND_GROUND, "amount": 0})
	sim.state["tiles"] = tiles
	sim.state["workers"] = []
	sim.state["reserved_resources"] = {}
	sim.state["dirty_tiles"] = {}
	return sim

# ─── Static: data_to_vec / vec_to_data ───────────────────────────────────────

func test_data_to_vec_basic() -> void:
	var v: Vector2i = ColonySim.data_to_vec({x = 3, y = 5})
	assert_eq(v.x, 3, "data_to_vec x")
	assert_eq(v.y, 5, "data_to_vec y")

func test_data_to_vec_negative() -> void:
	var v: Vector2i = ColonySim.data_to_vec({x = -2, y = -7})
	assert_eq(v.x, -2, "data_to_vec negative x")
	assert_eq(v.y, -7, "data_to_vec negative y")

func test_data_to_vec_zero() -> void:
	var v: Vector2i = ColonySim.data_to_vec({x = 0, y = 0})
	assert_eq(v.x, 0, "data_to_vec zero x")
	assert_eq(v.y, 0, "data_to_vec zero y")

func test_vec_to_data_basic() -> void:
	var d: Dictionary = ColonySim.vec_to_data(Vector2i(3, 5))
	assert_eq(int(d["x"]), 3, "vec_to_data x")
	assert_eq(int(d["y"]), 5, "vec_to_data y")

func test_vec_to_data_negative() -> void:
	var d: Dictionary = ColonySim.vec_to_data(Vector2i(-4, -9))
	assert_eq(int(d["x"]), -4, "vec_to_data negative x")
	assert_eq(int(d["y"]), -9, "vec_to_data negative y")

func test_data_to_vec_roundtrip() -> void:
	# Round-tripping a Vector2i through vec_to_data / data_to_vec should yield
	# the original values.
	var original := Vector2i(11, 17)
	var v: Vector2i = ColonySim.data_to_vec(ColonySim.vec_to_data(original))
	assert_eq(v.x, original.x, "roundtrip x")
	assert_eq(v.y, original.y, "roundtrip y")

# ─── Static: step_toward ──────────────────────────────────────────────────────
#
# step_toward moves one tile toward `target` on the x-axis first, then the
# y-axis. So from (0, 0) → (5, 3) the next step is (1, 0); only when the x
# distances equalise does y move.

func test_step_toward_positive_direction() -> void:
	var result: Vector2i = ColonySim.step_toward(Vector2i(0, 0), Vector2i(5, 3))
	assert_eq(result.x, 1, "step_toward x should move toward target")
	assert_eq(result.y, 0, "step_toward y stays when x moved first")

func test_step_toward_negative_direction() -> void:
	var result: Vector2i = ColonySim.step_toward(Vector2i(5, 3), Vector2i(0, 0))
	assert_eq(result.x, 4, "step_toward x should move toward target")
	assert_eq(result.y, 3, "step_toward y stays when x moved first")

func test_step_toward_same_position() -> void:
	var result: Vector2i = ColonySim.step_toward(Vector2i(5, 3), Vector2i(5, 3))
	assert_eq(result.x, 5, "step_toward same position stays x")
	assert_eq(result.y, 3, "step_toward same position stays y")

func test_step_toward_diagonal_adjacent() -> void:
	# When the x-distance is zero, y should advance.
	var result: Vector2i = ColonySim.step_toward(Vector2i(5, 0), Vector2i(5, 4))
	assert_eq(result.x, 5, "step_toward diagonal keeps x")
	assert_eq(result.y, 1, "step_toward diagonal advances y")

func test_step_toward_distance_decreases() -> void:
	# Manhattan distance to the target must strictly decrease. Vector2i has no
	# `distance_to` method, so use a manual helper.
	var current := Vector2i(0, 0)
	var target := Vector2i(5, 3)
	var old_dist: float = float(abs(target.x - current.x) + abs(target.y - current.y))
	var new_pos: Vector2i = ColonySim.step_toward(current, target)
	var new_dist: float = float(abs(target.x - new_pos.x) + abs(target.y - new_pos.y))
	assert_true(new_dist < old_dist, "step_toward should reduce Manhattan distance to target")

# ─── Instance: is_pos_in_bounds ──────────────────────────────────────────────

func test_is_pos_in_bounds_inside() -> void:
	var sim := _sim()
	assert_true(sim.is_pos_in_bounds(Vector2i(2, 2)), "centre is in bounds")

func test_is_pos_in_bounds_negative() -> void:
	var sim := _sim()
	assert_false(sim.is_pos_in_bounds(Vector2i(-1, 0)), "negative x is out of bounds")
	assert_false(sim.is_pos_in_bounds(Vector2i(0, -1)), "negative y is out of bounds")

func test_is_pos_in_bounds_at_max_boundary() -> void:
	var sim := _sim()
	var max_pos := Vector2i(LayoutMath.BOTTOM_GRID_W - 1, LayoutMath.BOTTOM_GRID_H - 1)
	assert_true(sim.is_pos_in_bounds(max_pos), "at max boundary in bounds")

func test_is_pos_in_bounds_past_boundary() -> void:
	var sim := _sim()
	var past := Vector2i(LayoutMath.BOTTOM_GRID_W, 0)
	assert_false(sim.is_pos_in_bounds(past), "just past max x is out of bounds")

# ─── Instance: is_near_stockpile ─────────────────────────────────────────────

func test_is_near_stockpile_far() -> void:
	var sim := _sim()
	# No stockpile registered; any position should be far.
	assert_false(sim.is_near_stockpile(Vector2i(0, 0)), "no stockpile means nothing is near")

# ─── Instance: find_open_ground ──────────────────────────────────────────────

func test_find_open_ground_returns_valid_tile() -> void:
	var sim := _sim()
	# Fixture is all ground and no stockpile → first tile wins.
	var pos: Vector2i = sim.find_open_ground()
	assert_eq(pos, Vector2i(0, 0), "find_open_ground returns first ground tile")
	assert_true(sim.is_pos_in_bounds(pos), "find_open_ground result is in bounds")

# ─── Instance: seed_tile ─────────────────────────────────────────────────────

func test_seed_tile_deterministic() -> void:
	var sim := _sim()
	var p := Vector2i(4, 2)
	var t1: Dictionary = sim.seed_tile(p)
	var t2: Dictionary = sim.seed_tile(p)
	assert_eq(String(t1["kind"]), String(t2["kind"]), "same pos → same kind")
	assert_eq(int(t1["amount"]), int(t2["amount"]), "same pos → same amount")

func test_seed_tile_different_positions() -> void:
	var sim := _sim()
	# Sampling many positions should produce varying kinds (deterministic but
	# not constant across the strip).
	var kinds := {}
	for i in 32:
		var t: Dictionary = sim.seed_tile(Vector2i(i, 0))
		kinds[String(t["kind"])] = true
	assert_true(kinds.size() > 1, "different positions produce more than one kind")

func test_seed_tile_kind_values() -> void:
	# The seeded kind set should be a subset of the known kinds.
	var sim := _sim()
	var known := [TILE_KIND_GROUND, TILE_KIND_TREE, TILE_KIND_ROCK, TILE_KIND_BERRIES]
	var seen := {}
	for y in LayoutMath.BOTTOM_GRID_H:
		for x in LayoutMath.BOTTOM_GRID_W:
			var t: Dictionary = sim.seed_tile(Vector2i(x, y))
			seen[String(t["kind"])] = true
	for k in seen.keys():
		assert_true(known.has(k), "seed_tile produced known kind: " + k)

func test_seed_tile_ground_zero_amount() -> void:
	# Ground tiles (the fallback when no resource tile is selected) carry an
	# amount of zero — they have nothing to harvest until later code fills them.
	var sim := _sim()
	var ground_tile: Dictionary = {}
	for y in LayoutMath.BOTTOM_GRID_H:
		for x in LayoutMath.BOTTOM_GRID_W:
			var t: Dictionary = sim.seed_tile(Vector2i(x, y))
			if String(t["kind"]) == TILE_KIND_GROUND:
				ground_tile = t
				break
		if not ground_tile.is_empty():
			break
	assert_true(not ground_tile.is_empty(), "at least one ground tile was found")
	assert_eq(int(ground_tile["amount"]), 0, "ground tile seeded with amount=0")

# ─── Static: rebuild_reservations_from_workers ───────────────────────────────
#
# `rebuild_reservations_from_workers` walks every worker's current task and
# rebuilds `state["reserved_resources"]` as a `Dict[resource_name, count]`. The
# existing reservations are wiped first unless `trust_existing` is true.

func test_rebuild_empty_state() -> void:
	var sim := _sim()
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_eq(sim.state["reserved_resources"], {}, "empty workers → empty reservations")

func test_rebuild_trust_existing_keeps_prior() -> void:
	# With `trust_existing=true` and no workers, the prior reservation count
	# must survive untouched.
	var sim := _sim()
	sim.state["reserved_resources"]["wood"] = 3
	sim.state["workers"] = []
	ColonySim.rebuild_reservations_from_workers(sim.state, true)
	assert_true(sim.state["reserved_resources"].has("wood"), "trust_existing preserves wood key")
	assert_eq(int(sim.state["reserved_resources"]["wood"]), 3, "prior wood count intact")

func test_rebuild_no_trust_overwrites() -> void:
	var sim := _sim()
	sim.state["reserved_resources"]["wood"] = 3
	sim.state["workers"] = []
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_false(sim.state["reserved_resources"].has("wood"), "no-trust wipes prior wood entry")

func test_rebuild_gather_task() -> void:
	var sim := _sim()
	sim.state["workers"] = [
		{
			"task": {"kind": "gather", "resource": "wood"},
			"reservation": Vector2i(2, 1),
		},
	]
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_true(sim.state["reserved_resources"].has("wood"), "gather task adds wood key")
	assert_eq(int(sim.state["reserved_resources"]["wood"]), 1, "one gatherer reserves 1 wood")

func test_rebuild_haul_task() -> void:
	var sim := _sim()
	sim.state["workers"] = [
		{
			"task": {"kind": "haul", "resource": "stone"},
			"reservation": Vector2i(5, 4),
		},
	]
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_true(sim.state["reserved_resources"].has("stone"), "haul task adds stone key")
	assert_eq(int(sim.state["reserved_resources"]["stone"]), 1, "one hauler reserves 1 stone")

func test_rebuild_mixed_tasks() -> void:
	var sim := _sim()
	sim.state["workers"] = [
		{"task": {"kind": "gather", "resource": "wood"}, "reservation": Vector2i(1, 1)},
		{"task": {"kind": "haul", "resource": "stone"}, "reservation": Vector2i(2, 2)},
		{"task": {"kind": "build", "resource": ""}, "reservation": Vector2i(3, 3)},
	]
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_eq(int(sim.state["reserved_resources"]["wood"]), 1, "one wood reservation")
	assert_eq(int(sim.state["reserved_resources"]["stone"]), 1, "one stone reservation")
	assert_false(sim.state["reserved_resources"].has(""), "build task does not add empty-resource key")

func test_rebuild_missing_task() -> void:
	var sim := _sim()
	sim.state["workers"] = [
		{"reservation": Vector2i(1, 1)},
	]
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_eq(sim.state["reserved_resources"], {}, "worker without task contributes nothing")

func test_rebuild_missing_resource_key() -> void:
	var sim := _sim()
	sim.state["workers"] = [
		{"task": {"kind": "gather"}, "reservation": Vector2i(1, 1)},
	]
	# gather without a resource key should be skipped (continue branch).
	ColonySim.rebuild_reservations_from_workers(sim.state, false)
	assert_eq(sim.state["reserved_resources"], {}, "missing resource key skips reservation")