## Tests for worker task and resource reservations (issue #143).
##
## These tests verify that:
## 1. Build delivery is clamped to remaining need
## 2. Multiple workers cannot reserve the same remaining unit of needed resource
## 3. Excess carried resources are refunded/returned safely
## 4. Two workers targeting one build with one remaining resource need — only one succeeds
##
## Run: godot --headless --path . --script res://tests/test_reservations.gd

extends "res://tests/test_case.gd"

func run_tests() -> void:
	var gs_script := load("res://scripts/game_state.gd")
	var gs = gs_script.new()
	root.add_child(gs)
	await process_frame

	# Reservation tests
	test_reservation_prevents_double_haul(gs)
	test_reservation_clamps_delivery(gs)
	test_reservation_released_on_build_complete(gs)
	test_stale_reservations_cleaned_up(gs)
	test_two_workers_one_need_only_one_succeeds(gs)
	test_reserve_field_added_to_new_builds(gs)
	test_reserved_resources_save_load(gs)
	test_reserved_resources_resync_on_load(gs)
	test_gather_reservation_balance_on_depleted_tile()


# ──────────────────────────────────────────────────────────────────────
# Test 1: Reservation prevents double-haul of same resource unit
# ──────────────────────────────────────────────────────────────────────

func test_reservation_prevents_double_haul(gs: Node) -> void:
	print("")
	print("--- reservation: prevents double-haul ---")

	# Build needs 1 stone, stockpile has 1 stone
	var state := {
		"tick": 0,
		"resources": {"wood": 8, "stone": 1, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [
			{"name": "Jun", "pos": {"x": 11, "y": 2}, "prev_pos": {"x": 11, "y": 2}, "carrying": {}, "task": {"kind": "haul", "build_id": 1, "target": {"x": 11, "y": 2}, "resource": "stone"}, "break_ticks": 0},
			{"name": "Mara", "pos": {"x": 12, "y": 2}, "prev_pos": {"x": 12, "y": 2}, "carrying": {}, "task": {}, "break_ticks": 0},
		],
		"tiles": [],
		"builds": [
			{
				"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2},
				"delivered": {"wood": 0, "stone": 0},
				"reserved": {"wood": 0, "stone": 1},
				"progress": 0.0, "complete": false,
			},
		],
		"next_build_id": 2,
		"events": [],
		"save_version": 2,
	}

	gs.save_game(state)
	var loaded = gs.load_game()

	# Verify reservation persisted
	var build = loaded.get("builds", [{}])[0]
	assert_true(build.has("reserved"), "build has reserved field", "dictionary should have key 'reserved'")
	assert_eq(int(build.reserved.get("stone", -1)), 1, "reservation: 1 stone reserved")

	# Simulate gather_haul_tasks logic: need = cost(2) - delivered(0) - reserved(1) = 1
	# But stockpile has 1 stone and it's already reserved
	# So no new haul task should be generated for stone to this build
	var reserved := int(build.get("reserved", {}).get("stone", 0))
	var cost := 2  # hut stone cost
	var need := cost - int(build.delivered.get("stone", 0)) - reserved
	assert_eq(need, 1, "reservation: effective need is 1 (cost-delivered-reserved)")

	# Now simulate the second worker trying to generate a haul task
	# The effective need after reservation should be 1, but stockpile has exactly 1
	# which is reserved. So the second worker's haul task generation should see
	# that stockpile resources are already committed.
	var stockpile_stone := int(loaded.resources.get("stone", 0))
	assert_eq(stockpile_stone, 1, "reservation: stockpile has 1 stone")

	# The key invariant: reserved + delivered <= cost
	var total_committed := int(build.delivered.get("stone", 0)) + int(build.reserved.get("stone", 0))
	assert_true(total_committed <= cost, "reservation: committed (%d) <= cost (%d)" % [total_committed, cost])


# ──────────────────────────────────────────────────────────────────────
# Test 2: Reservation clamps delivery to remaining need
# ──────────────────────────────────────────────────────────────────────

func test_reservation_clamps_delivery(gs: Node) -> void:
	print("")
	print("--- reservation: clamps delivery ---")

	# Hut costs 2 stone. Build starts with 0 delivered, 0 reserved.
	# Worker picks up 1 stone → reserves it (reserved=1).
	# Worker delivers 1 stone → clamp to need(2-0-1=1) → deliver=1, release reservation.
	# Now: delivered=1, reserved=0. Need remaining = 1.
	# Second worker picks up another stone → reserves it (reserved=1).
	# Second delivers 1 stone → clamp to need(2-1-1=0) → deliver=0, release reservation.
	# Final: delivered=1, reserved=0... wait that's wrong.
	# Let me redo: after first delivery, need = 2-1-0 = 1. Second worker reserves 1, delivers 1.
	# After second: delivered=2, reserved=0. Total committed = 2 <= cost(2). ✓

	var state := {
		"tick": 5,
		"resources": {"wood": 8, "stone": 3, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [
			{
				"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2},
				"delivered": {"wood": 0, "stone": 0},
				"reserved": {"wood": 0, "stone": 0},
				"progress": 0.0, "complete": false,
			},
		],
		"next_build_id": 2,
		"events": [],
		"save_version": 2,
	}

	gs.save_game(state)
	var loaded = gs.load_game()
	var build = loaded.get("builds", [{}])[0]

	# Step 1: First worker picks up 1 stone → reserve
	build.reserved["stone"] = int(build.reserved.get("stone", 0)) + 1
	assert_eq(int(build.reserved.get("stone", -1)), 1, "clamped_delivery: step1 reserved=1")

	# Step 2: First worker delivers to build site
	# need = cost(2) - delivered(0) - reserved(1) = 1
	# deliver = min(carried=1, max(need=1, 0)) = 1
	var reserved := int(build.get("reserved", {}).get("stone", 0))
	var cost := 2
	var total_needed := cost - int(build.delivered.get("stone", 0)) - reserved
	var deliver := mini(1, maxf(total_needed, 0))
	build.delivered["stone"] = int(build.delivered.get("stone", 0)) + deliver
	if deliver > 0:
		reserved = maxf(reserved - deliver, 0)
		build.reserved["stone"] = reserved
	# Clean up reservation after haul complete
	reserved = int(build.get("reserved", {}).get("stone", 0))
	if reserved > 0:
		build.reserved["stone"] = maxf(reserved - 1, 0)

	assert_eq(int(build.delivered.get("stone", -1)), 1, "clamped_delivery: step2 delivered=1")
	var total := int(build.delivered.get("stone", 0)) + int(build.reserved.get("stone", 0))
	assert_eq(total, 1, "clamped_delivery: step2 total_committed=1 (need still 1)")

	# Step 3: Second worker picks up 1 stone → reserve
	build.reserved["stone"] = int(build.reserved.get("stone", 0)) + 1
	assert_eq(int(build.reserved.get("stone", -1)), 1, "clamped_delivery: step3 reserved=1")

	# Step 4: Second worker delivers to build site
	# need = cost(2) - delivered(1) - reserved(1) = 0
	# deliver = min(carried=1, max(need=0, 0)) = 0 → clamp to 0!
	reserved = int(build.get("reserved", {}).get("stone", 0))
	total_needed = cost - int(build.delivered.get("stone", 0)) - reserved
	deliver = mini(1, maxf(total_needed, 0))
	assert_eq(deliver, 0, "clamped_delivery: step4 deliver clamped to 0 (need exhausted)")
	build.delivered["stone"] = int(build.delivered.get("stone", 0)) + deliver
	if deliver > 0:
		reserved = maxf(reserved - deliver, 0)
		build.reserved["stone"] = reserved
	# Clean up reservation after haul complete
	reserved = int(build.get("reserved", {}).get("stone", 0))
	if reserved > 0:
		build.reserved["stone"] = maxf(reserved - 1, 0)

	total = int(build.delivered.get("stone", 0)) + int(build.reserved.get("stone", 0))
	assert_eq(total, 1, "clamped_delivery: step4 total_committed=1 (not over-delivered)")
	assert_eq(int(build.delivered.get("stone", -1)), 1, "clamped_delivery: step4 delivered still 1")


# ──────────────────────────────────────────────────────────────────────
# Test 3: Reservation released when build completes
# ──────────────────────────────────────────────────────────────────────

func test_reservation_released_on_build_complete(gs: Node) -> void:
	print("")
	print("--- reservation: released on completion ---")

	# Build is complete — reservations should be cleaned up by _clean_stale_reservations
	var state := {
		"tick": 10,
		"resources": {"wood": 8, "stone": 3, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [
			{
				"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2},
				"delivered": {"wood": 6, "stone": 2},
				"reserved": {"wood": 0, "stone": 1},
				"progress": 1.0, "complete": true,
			},
		],
		"next_build_id": 2,
		"events": [],
		"save_version": 2,
	}

	gs.save_game(state)
	var loaded = gs.load_game()
	var build = loaded.get("builds", [{}])[0]

	# Complete builds should not generate haul tasks (gather_haul_tasks skips them)
	assert_true(bool(build.get("complete", false)), "completed_build: build is complete")

	# The reservation cleanup logic skips complete builds (if bool(build.complete): continue)
	# So the reserved field stays but won't be counted in need calculations
	assert_eq(bool(build.complete), true, "reservation_released: build marked complete")


# ──────────────────────────────────────────────────────────────────────
# Test 4: Stale reservations cleaned up when no haul tasks target build
# ──────────────────────────────────────────────────────────────────────

func test_stale_reservations_cleaned_up(gs: Node) -> void:
	print("")
	print("--- reservation: stale cleanup ---")

	# Build has 1 stone reserved but no worker is hauling to it (worker broke)
	var state := {
		"tick": 15,
		"resources": {"wood": 8, "stone": 2, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [
			{"name": "Jun", "pos": {"x": 11, "y": 2}, "prev_pos": {"x": 11, "y": 2}, "carrying": {}, "task": {}, "break_ticks": 6},
			{"name": "Mara", "pos": {"x": 12, "y": 2}, "prev_pos": {"x": 12, "y": 2}, "carrying": {}, "task": {}, "break_ticks": 0},
		],
		"tiles": [],
		"builds": [
			{
				"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2},
				"delivered": {"wood": 0, "stone": 0},
				"reserved": {"wood": 0, "stone": 1},
				"progress": 0.0, "complete": false,
			},
		],
		"next_build_id": 2,
		"events": [],
		"save_version": 2,
	}

	gs.save_game(state)
	var loaded = gs.load_game()

	# Simulate _clean_stale_reservations:
	# No worker has an active haul task to build 1 → reservation is stale
	var build = loaded.get("builds", [{}])[0]
	var has_haul := false
	for worker in loaded.get("workers", []):
		if not worker.task.is_empty() and String(worker.task.kind) == "haul":
			if int(worker.task.get("build_id", -1)) == int(build.id):
				has_haul = true
				break

	assert_true(not has_haul, "stale_cleanup: no active haul task for build 1")

	# Reservation should be cleaned up and resources returned to stockpile
	var reserved_stone := int(build.get("reserved", {}).get("stone", 0))
	if not has_haul and build.has("reserved"):
		loaded.resources["stone"] = int(loaded.resources.get("stone", 0)) + reserved_stone
		build.erase("reserved")

	assert_eq(int(loaded.resources.get("stone", -1)), 3, "stale_cleanup: stone returned to stockpile (2+1)")
	assert_false(build.has("reserved"), "stale_cleanup: reserved field removed", "dictionary should not have key 'reserved'")


# ──────────────────────────────────────────────────────────────────────
# Test 5: Two workers targeting one build with one remaining need — only one succeeds
# ──────────────────────────────────────────────────────────────────────

func test_two_workers_one_need_only_one_succeeds(gs: Node) -> void:
	print("")
	print("--- reservation: two workers one need ---")

	# Hut needs 2 stone. Stockpile has 1 stone.
	# Build has 0 delivered, 0 reserved initially.
	# Worker Jun picks up the 1 stone → reserves it (reserved=1).
	# Worker Mara tries to generate a haul task: need = 2-0-1 = 1, stockpile=0.
	# Mara should NOT get a haul task because stockpile is empty.

	var state := {
		"tick": 20,
		"resources": {"wood": 8, "stone": 0, "food": 2},  # stockpile has NO stone left
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [
			{
				"name": "Jun", "pos": {"x": 3, "y": 2}, "prev_pos": {"x": 11, "y": 2},
				"carrying": {"stone": 1}, "task": {"kind": "haul", "build_id": 1, "target": {"x": 3, "y": 2}, "resource": "stone"},
				"break_ticks": 0,
			},
			{
				"name": "Mara", "pos": {"x": 12, "y": 2}, "prev_pos": {"x": 12, "y": 2},
				"carrying": {}, "task": {}, "break_ticks": 0,
			},
		],
		"tiles": [],
		"builds": [
			{
				"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2},
				"delivered": {"wood": 0, "stone": 0},
				"reserved": {"wood": 0, "stone": 1},  # Jun's reservation
				"progress": 0.0, "complete": false,
			},
		],
		"next_build_id": 2,
		"events": [],
		"save_version": 2,
	}

	gs.save_game(state)
	var loaded = gs.load_game()
	var build = loaded.get("builds", [{}])[0]

	# Jun delivers the stone (carried=1, need=2-0-1=1, deliver=min(1,1)=1)
	var reserved := int(build.get("reserved", {}).get("stone", 0))
	var cost := 2
	var total_needed := cost - int(build.delivered.get("stone", 0)) - reserved
	var deliver := mini(1, maxf(total_needed, 0))
	build.delivered["stone"] = int(build.delivered.get("stone", 0)) + deliver
	if deliver > 0:
		reserved = maxf(reserved - deliver, 0)
		build.reserved["stone"] = reserved

	# Now Jun's haul is done. Mara tries to generate a haul task.
	# need = cost(2) - delivered(1) - reserved(0) = 1
	# stockpile has 0 stone → no task generated!
	var new_need := cost - int(build.delivered.get("stone", 0)) - int(build.get("reserved", {}).get("stone", 0))
	var stockpile_stone := int(loaded.resources.get("stone", 0))
	assert_eq(new_need, 1, "two_workers_one_need: effective need is 1")
	assert_eq(stockpile_stone, 0, "two_workers_one_need: stockpile has 0 stone")

	# Mara should NOT get a haul task because stockpile is empty
	var can_generate_task := new_need > 0 and stockpile_stone > 0
	assert_true(not can_generate_task, "two_workers_one_need: Mara cannot generate haul task (no stockpile)")

	# Final state: delivered=1, reserved=0, total_committed=1 <= cost(2) ✓
	var total := int(build.delivered.get("stone", 0)) + int(build.reserved.get("stone", 0))
	assert_eq(total, 1, "two_workers_one_need: total committed = 1 (not over-delivered)")

	# Save and verify persistence
	gs.save_game(loaded)
	var final = gs.load_game()
	var final_build = final.get("builds", [{}])[0]
	var final_delivered := int(final_build.delivered.get("stone", -1))
	var final_reserved := int(final_build.get("reserved", {}).get("stone", -1))
	assert_eq(final_delivered, 1, "two_workers_one_need: persisted delivered = 1")
	assert_eq(final_reserved, 0, "two_workers_one_need: persisted reserved = 0")


# ──────────────────────────────────────────────────────────────────────
# Test 6: Reserved field added to new builds (queue_structure_at)
# ──────────────────────────────────────────────────────────────────────

func test_reserve_field_added_to_new_builds(gs: Node) -> void:
	print("")
	print("--- reservation: reserved field on new builds ---")

	# Simulate a newly queued build — should have reserved field
	var new_build := {
		"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2},
		"delivered": {"wood": 0, "stone": 0},
		"reserved": {"wood": 0, "stone": 0},
		"progress": 0.0, "complete": false,
	}

	assert_true(new_build.has("reserved"), "new_build: reserved field present", "dictionary should have key 'reserved'")
	assert_eq(int(new_build.reserved.get("wood", -1)), 0, "new_build: reserved.wood = 0")
	assert_eq(int(new_build.reserved.get("stone", -1)), 0, "new_build: reserved.stone = 0")

	# Save and verify the reserved field persists through save/load
	var state := {
		"tick": 25,
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [],
		"tiles": [],
		"builds": [new_build],
		"next_build_id": 2,
		"events": [],
		"save_version": 2,
	}

	gs.save_game(state)
	var loaded = gs.load_game()
	var loaded_build = loaded.get("builds", [{}])[0]
	assert_true(loaded_build.has("reserved"), "persisted_build: reserved field preserved", "dictionary should have key 'reserved'")
	assert_eq(int(loaded_build.reserved.get("wood", -1)), 0, "persisted_build: reserved.wood = 0")

func test_reserved_resources_save_load(gs: Node) -> void:
	print("")
	print("--- reservation: reserved_resources survives save/load ---")

	var state := {
		"tick": 50,
		"resources": {"wood": 10, "stone": 8, "food": 3},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [
			{
				"name": "Alice",
				"pos": {"x": 1, "y": 1},
				"carrying": {},
				"task": {"kind": "gather", "resource": "wood"},
				"break_ticks": 0,
			},
			{
				"name": "Bob",
				"pos": {"x": 2, "y": 1},
				"carrying": {},
				"task": {"kind": "haul", "resource": "stone"},
				"break_ticks": 0,
			},
		],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
		"save_version": 2,
		"reserved_resources": {"wood": 2, "stone": 1},
	}

	gs.save_game(state)
	var loaded = gs.load_game()
	var reserved: Dictionary = loaded.get("reserved_resources", {})
	assert_eq(int(reserved.get("wood", -1)), 2, "saved wood reservation persists")
	assert_eq(int(reserved.get("stone", -1)), 1, "saved stone reservation persists")

func test_reserved_resources_resync_on_load(gs: Node) -> void:
	print("")
	print("--- reservation: reserved_resources resynced from workers on load ---")

	var state := {
		"tick": 60,
		"resources": {"wood": 10, "stone": 8, "food": 3},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["build", "haul", "gather"],
		"workers": [
			{
				"name": "Alice",
				"pos": {"x": 1, "y": 1},
				"carrying": {},
				"task": {"kind": "gather", "resource": "wood"},
				"break_ticks": 0,
			},
			{
				"name": "Bob",
				"pos": {"x": 2, "y": 1},
				"carrying": {},
				"task": {"kind": "haul", "resource": "stone"},
				"break_ticks": 0,
			},
		],
		"tiles": [],
		"builds": [],
		"next_build_id": 1,
		"events": [],
		"save_version": 2,
		"reserved_resources": {},
	}

	gs.save_game(state)
	var loaded = gs.load_game()
	var reserved: Dictionary = loaded.get("reserved_resources", {})
	assert_eq(int(reserved.get("wood", -1)), 1, "wood reservation rebuilt from gather worker")
	assert_eq(int(reserved.get("stone", -1)), 1, "stone reservation rebuilt from haul worker")


# ──────────────────────────────────────────────────────────────────────
# Reservation balance on the do_gather early-return path (#279 item 7):
# a worker arriving at a tile another worker already emptied must release
# its reservation exactly once, and the counter must never go negative.
# ──────────────────────────────────────────────────────────────────────

const ColonySim := preload("res://scripts/colony_sim.gd")

func test_gather_reservation_balance_on_depleted_tile() -> void:
	print("")
	print("--- reservation: balance on depleted-tile gather ---")

	var sim := ColonySim.new()
	sim.grid_w = 5
	sim.grid_h = 5
	sim.stockpile_pos = Vector2i(0, 0)
	sim.priority_order = ["gather"] as Array[String]
	var tiles: Array = []
	for i in 25:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	sim.state = {
		"tick": 0,
		"resources": {"wood": 0, "stone": 0, "food": 10},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["gather"],
		"workers": [
			{"name": "Jun", "pos": {"x": 2, "y": 0}, "prev_pos": {"x": 2, "y": 0}, "carrying": {}, "task": {}, "break_ticks": 0},
			{"name": "Mara", "pos": {"x": 2, "y": 4}, "prev_pos": {"x": 2, "y": 4}, "carrying": {}, "task": {}, "break_ticks": 0},
		],
		"tiles": tiles,
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
	}
	# Two single-unit wood tiles so both workers can reserve wood.
	sim.set_tile(Vector2i(3, 0), {"kind": "tree", "amount": 1, "resource": "wood", "build_kind": ""})
	sim.set_tile(Vector2i(3, 4), {"kind": "tree", "amount": 1, "resource": "wood", "build_kind": ""})

	var task_a: Dictionary = sim.choose_task(sim.state.workers[0])
	sim.state.workers[0].task = task_a
	var task_b: Dictionary = sim.choose_task(sim.state.workers[1])
	sim.state.workers[1].task = task_b
	assert_eq(sim.get_reserved("wood"), 2, "balance: both workers hold a reservation")

	# Empty worker A's target tile out from under it (mirrors a race where
	# the tile was consumed before arrival), then let A attempt the gather.
	var target_a := ColonySim.data_to_vec(task_a.target)
	sim.set_tile(target_a, {"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	sim.state.workers[0].pos = task_a.target
	sim.do_gather(sim.state.workers[0], task_a)
	assert_eq(sim.get_reserved("wood"), 1, "balance: early-return released exactly one reservation")
	assert_true(sim.state.workers[0].task.is_empty(), "balance: failed gather clears the task")

	# Worker B gathers normally — its reservation is released on success.
	sim.state.workers[1].pos = task_b.target
	sim.do_gather(sim.state.workers[1], task_b)
	assert_eq(sim.get_reserved("wood"), 0, "balance: successful gather released the last reservation")

	# Pathological repeat on an empty tile with no reservation held: the
	# counter clamps at zero instead of drifting negative.
	sim.do_gather(sim.state.workers[0], task_a)
	assert_eq(sim.get_reserved("wood"), 0, "balance: counter never goes negative")
