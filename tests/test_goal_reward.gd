extends "res://tests/test_case.gd"
# Tests for goal_reward.gd — misospace/windowstead#134
# Run with: godot --headless --path . --script res://tests/test_goal_reward.gd

const GR := preload("res://scripts/goal_reward.gd")


func run_tests() -> void:
	test_apply_reward_returns_dict(GR)
	test_apply_reward_returns_empty_for_unknown(GR)
	test_resource_trickle_payouts(GR)
	test_reward_expiration(GR)
	test_ambient_improve_consumption(GR)
	test_recruit_discount_consumption(GR)
	test_build_speed_bonus(GR)
	test_haul_speed_multiplier(GR)
	test_format_active_rewards(GR)
	test_get_reward_label(GR)
	test_multiple_trickle_rewards(GR)
	test_tick_returns_surviving(GR)
	# Duration-0 one-time reward tests (Fixes #311)
	test_one_time_reward_survives_ticks(GR)
	test_one_time_ambient_improve_survives_ticks(GR)
	test_consume_recruit_discount_removes_one_time_reward(GR)
	test_consume_ambient_improve_removes_one_time_reward(GR)
	test_timed_reward_still_expires_on_schedule(GR)
	# Sim-path tests (issue #414): the multiplier must be consumed by
	# ColonySim.step_worker, not just exposed by the getter.
	test_step_worker_advances_one_tile_per_tick_without_reward()
	test_step_worker_advances_two_tiles_per_tick_with_reward()


func test_apply_reward_returns_dict(_script: Script) -> void:
	var GoalReward = _script
	var reward = GoalReward.apply_reward("gather_wood")
	assert_true(not reward.is_empty(), "apply_reward returns dict for known goal")
	assert_eq(reward["type"], GoalReward.REWARD_RESOURCE_TRICKLE, "Type is resource_trickle")
	assert_eq(reward["resource"], "food", "Resource is food")
	assert_true(reward["remaining"] > 0, "Has positive remaining ticks")


func test_apply_reward_returns_empty_for_unknown(_script: Script) -> void:
	var GoalReward = _script
	var reward = GoalReward.apply_reward("nonexistent_goal")
	assert_true(reward.is_empty(), "apply_reward returns empty for unknown goal")


func test_resource_trickle_payouts(_script: Script) -> void:
	var GoalReward = _script
	var reward = GoalReward.apply_reward("gather_wood")
	var game_state := {"resources": {"food": 10, "wood": 5, "stone": 3}}

	assert_eq(game_state.resources.food, 10, "Initial food is 10")

	var rewards := [reward]
	for i in range(9):
		var result = GoalReward.tick_rewards(rewards, game_state)
		rewards = result["new_rewards"]

	assert_eq(game_state.resources.food, 10, "Food still 10 after 9 ticks")

	var result = GoalReward.tick_rewards(rewards, game_state)
	rewards = result["new_rewards"]
	assert_eq(game_state.resources.food, 11, "Food is 11 after trickle payout")
	assert_eq(result.events.size(), 1, "One event message on payout")


func test_reward_expiration(_script: Script) -> void:
	var GoalReward = _script
	var reward = GoalReward.apply_reward("gather_wood")
	reward["remaining"] = 3
	var game_state := {"resources": {"food": 0}}

	var rewards := [reward]
	# tick_rewards reports only the labels that expired on that specific tick
	# (later ticks return a fresh empty "expired" list), so accumulate across
	# the loop instead of inspecting only the final result — the old check on
	# the last result was stale.
	var all_expired := []
	for i in range(5):
		var result = GoalReward.tick_rewards(rewards, game_state)
		rewards = result["new_rewards"]
		all_expired.append_array(result["expired"])

	assert_true(rewards.is_empty(), "Reward expired after ticks")
	assert_true(all_expired.size() > 0, "Has expired label")


func test_ambient_improve_consumption(_script: Script) -> void:
	var GoalReward = _script
	var rewards := [{"type": GoalReward.REWARD_AMBIENT_IMPROVE, "label": "ambient event improves", "remaining": 0}]

	assert_true(GoalReward.has_active_reward(rewards, GoalReward.REWARD_AMBIENT_IMPROVE), "Has ambient improve")
	var consumed = GoalReward.consume_reward(rewards, GoalReward.REWARD_AMBIENT_IMPROVE)
	assert_true(consumed, "Returns true when consuming")
	assert_false(GoalReward.has_active_reward(rewards, GoalReward.REWARD_AMBIENT_IMPROVE), "Gone after consume")


func test_recruit_discount_consumption(_script: Script) -> void:
	var GoalReward = _script
	var rewards := [{"type": GoalReward.REWARD_RECRUIT_DISCOUNT, "label": "next recruit -1 food", "remaining": 0}]

	assert_true(GoalReward.has_active_reward(rewards, GoalReward.REWARD_RECRUIT_DISCOUNT), "Has recruit discount")
	var consumed = GoalReward.consume_reward(rewards, GoalReward.REWARD_RECRUIT_DISCOUNT)
	assert_true(consumed, "Returns true when consuming")
	assert_false(GoalReward.has_active_reward(rewards, GoalReward.REWARD_RECRUIT_DISCOUNT), "Gone after consume")


func test_build_speed_bonus(_script: Script) -> void:
	var GoalReward = _script
	var rewards := []
	assert_eq(GoalReward.get_build_speed_bonus(rewards), 0.0, "No bonus without reward")

	rewards.append({"type": GoalReward.REWARD_BUILD_SPEED, "remaining": 20})
	assert_eq(GoalReward.get_build_speed_bonus(rewards), 0.16, "Returns 0.16 bonus")


func test_haul_speed_multiplier(_script: Script) -> void:
	var GoalReward = _script
	var rewards := []
	assert_eq(GoalReward.get_haul_speed_multiplier(rewards), 1.0, "No multiplier without reward")

	rewards.append({"type": GoalReward.REWARD_HAUL_SPEED, "remaining": 20})
	assert_eq(GoalReward.get_haul_speed_multiplier(rewards), 1.5, "Returns 1.5x multiplier")


func test_format_active_rewards(_script: Script) -> void:
	var GoalReward = _script
	var rewards := [
		{"type": GoalReward.REWARD_RESOURCE_TRICKLE, "label": "+1 food trickle", "remaining": 30},
		{"type": GoalReward.REWARD_HAUL_SPEED, "label": "haul speed +50%", "remaining": 15},
	]

	var text = GoalReward.format_active_rewards(rewards)
	assert_true(text.find("+1 food trickle") >= 0, "Contains first reward label")
	assert_true(text.find("haul speed +50%") >= 0, "Contains second reward label")
	assert_true(text.find("(30)") >= 0, "Contains remaining ticks")


func test_get_reward_label(_script: Script) -> void:
	var GoalReward = _script
	var label = GoalReward.get_reward_label("gather_wood")
	assert_true(not label.is_empty(), "Non-empty label for known goal")
	assert_true(label.find("food") >= 0, "Label mentions food")

	var empty_label = GoalReward.get_reward_label("nonexistent")
	assert_true(empty_label.is_empty(), "Empty string for unknown goal")


func test_multiple_trickle_rewards(_script: Script) -> void:
	var GoalReward = _script
	var reward1 = GoalReward.apply_reward("gather_wood")
	var reward2 = GoalReward.apply_reward("gather_stone")
	var game_state := {"resources": {"food": 0, "wood": 0, "stone": 0}}

	var rewards := [reward1, reward2]

	for i in range(GoalReward.TRICKLE_INTERVAL):
		var result = GoalReward.tick_rewards(rewards, game_state)
		rewards = result["new_rewards"]

	assert_eq(game_state.resources.food, 2, "Food is 2 from two trickle rewards")


func test_tick_returns_surviving(_script: Script) -> void:
	var GoalReward = _script
	var reward1 = GoalReward.apply_reward("gather_wood")
	reward1["remaining"] = 5
	var reward2 = GoalReward.apply_reward("build_hut")
	reward2["remaining"] = 2

	var game_state := {"resources": {}}
	var rewards := [reward1, reward2]

	var result = GoalReward.tick_rewards(rewards, game_state)
	assert_eq(result.new_rewards.size(), 2, "Both survive first tick")

	for i in range(2):
		result = GoalReward.tick_rewards(result.new_rewards, game_state)

	assert_eq(result.new_rewards.size(), 1, "Only reward1 survives")
	assert_true(result.expired.size() > 0, "Has one expired reward")


# ── Duration-0 one-time rewards survive tick_rewards until consumed ──────────
func test_one_time_reward_survives_ticks(_script: Script) -> void:
	"""Duration-0 (one-time) rewards must persist through tick_rewards until consumed.

	Fixes #311: build_workshop and build_garden use duration 0, which previously
	caused them to expire on the very next tick before they could be consumed."""
	var GoalReward = _script
	var game_state := {"resources": {"food": 50, "wood": 20}}
	var rewards := []

	# Apply a one-time reward (duration 0) — e.g. REWARD_RECRUIT_DISCOUNT from build_workshop
	rewards.append(GoalReward.apply_reward("build_workshop"))
	assert_eq(rewards.size(), 1, "One reward applied")
	assert_eq(rewards[0]["duration"], 0, "Duration is 0 (one-time)")

	# Run 70 ticks — well past EVENT_INTERVAL_TICKS (66) — reward must survive
	for i in range(70):
		var result = GoalReward.tick_rewards(rewards, game_state)
		rewards = result.new_rewards
		assert_eq(result.expired.size(), 0, "One-time reward should not expire on tick %d" % i)

	assert_eq(rewards.size(), 1, "One-time reward still active after 70 ticks")


func test_one_time_ambient_improve_survives_ticks(_script: Script) -> void:
	"""REWARD_AMBIENT_IMPROVE (from build_garden) must survive past EVENT_INTERVAL_TICKS."""
	var GoalReward = _script
	var game_state := {"resources": {"food": 50, "wood": 20}}
	var rewards := []

	rewards.append(GoalReward.apply_reward("build_garden"))
	assert_eq(rewards[0]["type"], GoalReward.REWARD_AMBIENT_IMPROVE, "build_garden grants an ambient improve")
	assert_eq(rewards[0]["duration"], 0, "Ambient improve is a one-time reward")

	# Run 70 ticks past the ambient event boundary
	for i in range(70):
		var result = GoalReward.tick_rewards(rewards, game_state)
		rewards = result.new_rewards
		assert_eq(result.expired.size(), 0, "Ambient improve should not expire on tick %d" % i)

	assert_eq(rewards.size(), 1, "Ambient improve reward still active after 70 ticks")


func test_consume_recruit_discount_removes_one_time_reward(_script: Script) -> void:
	"""consume_reward must remove the one-time recruit discount from active list."""
	var GoalReward = _script
	var rewards := []

	rewards.append(GoalReward.apply_reward("build_workshop"))
	assert_eq(rewards.size(), 1, "Reward is active before consumption")

	# Consume the discount — reward should be removed
	var consumed = GoalReward.consume_reward(rewards, GoalReward.REWARD_RECRUIT_DISCOUNT)
	assert_true(consumed, "Recruit discount was consumed")
	assert_eq(rewards.size(), 0, "One-time reward removed after consumption")


func test_consume_ambient_improve_removes_one_time_reward(_script: Script) -> void:
	"""consume_reward must remove the one-time ambient improve from active list."""
	var GoalReward = _script
	var rewards := []

	rewards.append(GoalReward.apply_reward("build_garden"))
	assert_eq(rewards.size(), 1, "Reward is active before consumption")

	# Consume the ambient improve — reward should be removed
	var consumed = GoalReward.consume_reward(rewards, GoalReward.REWARD_AMBIENT_IMPROVE)
	assert_true(consumed, "Ambient improve was consumed")
	assert_eq(rewards.size(), 0, "One-time reward removed after consumption")


func test_timed_reward_still_expires_on_schedule(_script: Script) -> void:
	"""Regression: duration > 0 rewards must still expire on schedule (no regression)."""
	var GoalReward = _script
	var game_state := {"resources": {"food": 50, "wood": 20}}
	var rewards := []

	rewards.append(GoalReward.apply_reward("gather_wood"))
	assert_eq(rewards[0]["duration"], GoalReward.DURATION_RESOURCE_TRICKLE, "Trickle reward keeps its scheduled duration")

	# tick_rewards checks `remaining <= 0` BEFORE decrementing, so a reward
	# created with remaining == duration survives `duration` ticks and expires
	# on the next one. That is pre-existing behaviour and unchanged by the
	# duration-0 guard above; tick one past the duration to observe expiry.
	for i in range(GoalReward.DURATION_RESOURCE_TRICKLE + 1):
		var result = GoalReward.tick_rewards(rewards, game_state)
		rewards = result.new_rewards

	assert_eq(rewards.size(), 0, "Timed reward expired after its duration")


# ── Sim-path tests (issue #414) ─────────────────────────────────────────────
# The build_hut goal grants a haul-speed reward; previously the reward's
# multiplier was exposed by get_haul_speed_multiplier but never consumed by
# ColonySim.step_worker, so a worker always advanced exactly one tile per
# tick. These tests drive step_worker directly and assert the multiplier
# changes the movement count.

const ColonySimForRewardTests := preload("res://scripts/colony_sim.gd")


func _new_step_worker_sim(reward_active: bool) -> ColonySimForRewardTests:
	"""Build a minimal sim with one worker holding a gather task whose
	target is several tiles away from the worker's starting position."""
	var sim := ColonySimForRewardTests.new()
	sim.grid_w = 5
	sim.grid_h = 5
	sim.stockpile_pos = Vector2i(0, 0)
	sim.priority_order = ["gather"] as Array[String]
	var tiles: Array = []
	for i in 25:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	var worker := {
		"name": "Tester",
		"pos": {"x": 0, "y": 0},
		"prev_pos": {"x": 0, "y": 0},
		"carrying": {},
		"task": {"kind": "gather", "target": {"x": 4, "y": 4}, "resource": "wood"},
		"break_ticks": 0,
	}
	var active_rewards: Array = []
	if reward_active:
		active_rewards.append({
			"type": "haul_speed",
			"label": "haul speed +50%",
			"remaining": 30,
			"duration": 30,
		})
	sim.state = {
		"tick": 0,
		"resources": {"wood": 0, "stone": 0, "food": 0},
		"harvested": {"wood": 0, "stone": 0, "food": 0},
		"priority_order": ["gather"],
		"workers": [worker],
		"tiles": tiles,
		"builds": [],
		"next_build_id": 1,
		"reserved_resources": {},
		"events": [],
		"active_rewards": active_rewards,
	}
	sim.ensure_defaults()
	return sim


func test_step_worker_advances_one_tile_per_tick_without_reward() -> void:
	"""Without the haul-speed reward, step_worker must advance exactly
	one tile per tick (regression guard: do not break baseline movement)."""
	var sim := _new_step_worker_sim(false)
	var before: Vector2i = ColonySimForRewardTests.data_to_vec(sim.state.workers[0].pos)
	sim.step_worker(sim.state.workers[0])
	var after: Vector2i = ColonySimForRewardTests.data_to_vec(sim.state.workers[0].pos)
	var distance: int = abs(after.x - before.x) + abs(after.y - before.y)
	assert_eq(distance, 1, "step_worker advances 1 tile per tick without reward")


func test_step_worker_advances_two_tiles_per_tick_with_reward() -> void:
	"""With the haul-speed reward active (multiplier 1.5), step_worker must
	advance at least 2 tiles per tick — the previously-silent reward now
	has a measurable effect on worker movement (issue #414 acceptance)."""
	var sim := _new_step_worker_sim(true)
	var before: Vector2i = ColonySimForRewardTests.data_to_vec(sim.state.workers[0].pos)
	sim.step_worker(sim.state.workers[0])
	var after: Vector2i = ColonySimForRewardTests.data_to_vec(sim.state.workers[0].pos)
	var distance: int = abs(after.x - before.x) + abs(after.y - before.y)
	assert_true(distance >= 2, "step_worker advances >= 2 tiles per tick when haul-speed reward is active")
