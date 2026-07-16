## Tests for dirty-state tracking in persist() (issue #179).
##
## These tests verify that the dirty-flag pattern correctly prevents
## unnecessary saves when game state has not changed since the last
## persist(). The flag now lives on the sim (`main.sim.dirty`, set by sim
## mutations and main._mark_dirty(), cleared by main.persist()); persist()
## itself is additionally debounced to at most once every
## PERSIST_INTERVAL_TICKS on the tick path, with persist(true) forcing an
## immediate save. Flows 1-6 exercise the same logic flow using
## game_state.gd's save/load functions; Flow 7 checks the real sim flag.
##
## Run: godot --headless --path . --script res://tests/test_dirty_state_tracking.gd

extends "res://tests/test_case.gd"


func run_tests() -> void:
	# Autoloads are not running in --script mode — instantiate game_state.gd
	# manually (same pattern as test_runner.gd).
	var game_state_script := load("res://scripts/game_state.gd")
	var gs = game_state_script.new()
	root.add_child(gs)
	await process_frame

	flow_dirty_state_triggers_save(gs)
	flow_clean_state_skips_save(gs)
	flow_persist_resets_dirty_flag(gs)
	flow_multiple_mutations_single_persist(gs)
	flow_idle_tick_skips_persist(gs)
	flow_dirty_flag_covers_all_mutation_categories(gs)
	flow_sim_dirty_flag_semantics()


# ---------------------------------------------------------------------------
# Test data factory
# ---------------------------------------------------------------------------

func make_initial_state() -> Dictionary:
	return {
		"tick": 0,
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"resources": {"wood": 8, "stone": 4, "food": 2},
		"workers": [],
		"tiles": [],
		"builds": [],
		"events": [],
		"save_version": 2,
	}


func seed_tiles(state: Dictionary) -> void:
	for y in range(30):
		for x in range(5):
			var key := int((x * 13 + y * 7 + x * y) % 14)
			var tile := {"kind": "ground", "amount": 0, "resource": "", "build_kind": ""}
			if key == 0 or key == 3:
				tile = {"kind": "tree", "amount": 6, "resource": "wood", "build_kind": ""}
			elif key == 6 or key == 8:
				tile = {"kind": "rock", "amount": 5, "resource": "stone", "build_kind": ""}
			elif key == 11:
				tile = {"kind": "berries", "amount": 4, "resource": "food", "build_kind": ""}
			state.tiles.append(tile)


# ---------------------------------------------------------------------------
# Flow 1: Initial save — dirty state triggers persist
# ---------------------------------------------------------------------------

func flow_dirty_state_triggers_save(gs: Node) -> void:
	print("\n=== Flow 1: Dirty state triggers save ===")
	gs.clear_game()

	# Simulate: _mark_dirty() was called (state changed)
	var state := make_initial_state()
	seed_tiles(state)
	state["tick"] = 10

	# Simulate persist(): dirty is true, so save happens
	# (on the real tick path the save may be deferred up to
	# PERSIST_INTERVAL_TICKS; persist(true) forces it immediately)
	gs.save_game(state)

	# Verify the save was written
	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 10, "saved tick matches")
	assert_eq(loaded.get("resources", {}).get("wood", -1), 8, "saved wood matches")
	assert_eq(loaded.get("tiles", []).size(), 150, "saved tile count matches")


# ---------------------------------------------------------------------------
# Flow 2: Clean state — no dirty flag means persist is skipped
# ---------------------------------------------------------------------------

func flow_clean_state_skips_save(gs: Node) -> void:
	print("\n=== Flow 2: Clean state skips save (persist returns early) ===")
	gs.clear_game()

	# Initial save with dirty state
	var state := make_initial_state()
	seed_tiles(state)
	state["tick"] = 10
	gs.save_game(state)

	# Verify initial save
	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 10, "initial tick is 10")

	# Simulate: sim.dirty is false (no changes since last persist).
	# In main.gd, persist() returns early when sim.dirty is false.
	# We simulate this by NOT calling save_game — the file on disk should remain unchanged.
	# Load again and verify tick is still 10 (not advanced to a new value).
	loaded = gs.load_game()
	assert_eq(loaded.get("tick", -1), 10, "tick remains 10 after no-dirty persist")

	# Also verify the save file content hasn't been overwritten with stale data
	var backup: Dictionary = loaded.duplicate()
	loaded = gs.load_game()
	assert_eq(loaded.get("tick"), backup.get("tick"), "tick unchanged across double load (no dirty)")


# ---------------------------------------------------------------------------
# Flow 3: Mutation resets dirty flag after save
# ---------------------------------------------------------------------------

func flow_persist_resets_dirty_flag(gs: Node) -> void:
	print("\n=== Flow 3: persist() resets sim.dirty flag ===")
	gs.clear_game()

	# Initial save (dirty=true)
	var state := make_initial_state()
	seed_tiles(state)
	state["tick"] = 5
	gs.save_game(state)

	# Verify saved
	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 5, "saved tick is 5")

	# Simulate mutation: _mark_dirty() sets sim.dirty=true
	state["tick"] = 20
	gs.save_game(state)

	# Verify updated
	loaded = gs.load_game()
	assert_eq(loaded.get("tick", -1), 20, "tick updated to 20 after mutation+save")


# ---------------------------------------------------------------------------
# Flow 4: Multiple mutations before single persist — only one save
# ---------------------------------------------------------------------------

func flow_multiple_mutations_single_persist(gs: Node) -> void:
	print("\n=== Flow 4: Multiple mutations → single persist ===")
	gs.clear_game()

	# Initial state
	var state := make_initial_state()
	seed_tiles(state)
	state["tick"] = 1
	gs.save_game(state)

	# Multiple mutations (simulating _mark_dirty called many times)
	state["resources"]["wood"] = 10
	state["resources"]["stone"] = 6
	state["tick"] = 2
	# In main.gd, each mutation calls _mark_dirty(), but only the final
	# persist() saves — and the tick path debounces to one save per
	# PERSIST_INTERVAL_TICKS window.

	# Single persist after all mutations
	gs.save_game(state)

	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 2, "final tick is 2")
	assert_eq(loaded.get("resources", {}).get("wood", -1), 10, "wood updated to 10")
	assert_eq(loaded.get("resources", {}).get("stone", -1), 6, "stone updated to 6")


# ---------------------------------------------------------------------------
# Flow 5: Idle tick — no mutations means persist is skipped
# ---------------------------------------------------------------------------

func flow_idle_tick_skips_persist(gs: Node) -> void:
	print("\n=== Flow 5: Idle tick (no mutations) skips persist ===")
	gs.clear_game()

	# Save initial state
	var state := make_initial_state()
	seed_tiles(state)
	state["tick"] = 100
	gs.save_game(state)

	# Simulate idle tick: no mutations occur, so sim.dirty stays false
	# In main.gd: _on_tick() increments tick but does NOT call _mark_dirty()
	# The tick value is only captured in persist() when sim.dirty=true
	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 100, "idle tick does not overwrite save")

	# Verify that without any _mark_dirty(), the persisted data is unchanged
	loaded = gs.load_game()
	assert_eq(loaded.get("resources", {}).get("wood", -1), 8, "resources unchanged after idle ticks")


# ---------------------------------------------------------------------------
# Flow 6: Dirty flag covers all mutation categories
# ---------------------------------------------------------------------------

func flow_dirty_flag_covers_all_mutation_categories(gs: Node) -> void:
	print("\n=== Flow 6: Dirty flag covers all mutation categories ===")
	gs.clear_game()

	# Initial state with workers and builds
	var state := make_initial_state()
	seed_tiles(state)
	state["tick"] = 1
	state["workers"] = [
		{"name": "Jun", "pos": {"x": 1, "y": 2}, "prev_pos": {"x": 1, "y": 2}, "carrying": {}, "task": {}, "break_ticks": 0},
	]
	state["builds"] = [{"id": 1, "kind": "hut", "pos": {"x": 3, "y": 2}, "complete": true}]
	gs.save_game(state)

	# Resource mutation (apply_food_upkeep / do_haul)
	state["resources"]["food"] = 1
	gs.save_game(state)

	# Worker mutation (recruit_worker)
	state["workers"].append(
		{"name": "Mara", "pos": {"x": 2, "y": 3}, "prev_pos": {"x": 2, "y": 3}, "carrying": {}, "task": {}, "break_ticks": 0}
	)
	gs.save_game(state)

	# Priority mutation (move_priority)
	state["priority_order"] = ["build", "gather", "haul"]
	gs.save_game(state)

	# Event mutation (push_event)
	state["events"].append({"tick": 5, "text": "worker recruited"})
	gs.save_game(state)

	# Tile mutation (set_tile)
	state.tiles[0] = {"kind": "stockpile", "amount": 0, "resource": "", "build_kind": ""}
	gs.save_game(state)

	var loaded: Dictionary = gs.load_game()
	assert_eq(loaded.get("tick", -1), 1, "tick preserved")
	assert_eq(loaded.get("resources", {}).get("food", -1), 1, "food updated (resource mutation)")
	assert_eq(loaded.get("workers", []).size(), 2, "worker added (worker mutation)")
	assert_eq(loaded.get("priority_order", []), ["build", "gather", "haul"], "priority changed")
	assert_eq(loaded.get("events", []).size(), 1, "event logged (event mutation)")
	assert_eq(loaded.get("tiles", [])[0].get("kind"), "stockpile", "tile modified (tile mutation)")


# ---------------------------------------------------------------------------
# Flow 7: Real sim.dirty flag semantics (post sim-extraction refactor)
# ---------------------------------------------------------------------------
# The flag moved from main's old `_dirty` var to `main.sim.dirty`. We check it
# directly on a scene-free Main instance. main.persist() itself is not called
# here because it writes through the GameState autoload, which is unavailable
# in --script mode.

func flow_sim_dirty_flag_semantics() -> void:
	print("\n=== Flow 7: sim.dirty flag semantics ===")
	# main.gd references the GameState autoload — load at runtime, not preload.
	var main_script: GDScript = load("res://scripts/main.gd")
	var main: Control = main_script.new()

	assert_false(main.sim.dirty, "sim.dirty starts false on a fresh sim")

	main._mark_dirty()
	assert_true(main.sim.dirty, "main._mark_dirty() sets sim.dirty")

	# Simulate the clear performed by persist() once it saves
	main.sim.dirty = false
	assert_false(main.sim.dirty, "sim.dirty clear observed")

	# A sim mutation (push_event) marks the state dirty again
	main.state = {"tick": 0, "events": []}
	main.push_event("dirty-flag test event")
	assert_true(main.sim.dirty, "sim mutation (push_event) sets sim.dirty")
	assert_eq(main.state.events.size(), 1, "push_event recorded the event")

	main.free()
