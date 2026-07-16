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
	test_gather_speed_multiplier(GR)
	test_haul_speed_multiplier(GR)
	test_format_active_rewards(GR)
	test_get_reward_label(GR)
	test_multiple_trickle_rewards(GR)
	test_tick_returns_surviving(GR)


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
	var consumed = GoalReward.consume_ambient_improve(rewards)
	assert_true(consumed, "Returns true when consuming")
	assert_false(GoalReward.has_active_reward(rewards, GoalReward.REWARD_AMBIENT_IMPROVE), "Gone after consume")


func test_recruit_discount_consumption(_script: Script) -> void:
	var GoalReward = _script
	var rewards := [{"type": GoalReward.REWARD_RECRUIT_DISCOUNT, "label": "next recruit -1 food", "remaining": 0}]

	assert_true(GoalReward.has_active_reward(rewards, GoalReward.REWARD_RECRUIT_DISCOUNT), "Has recruit discount")
	var consumed = GoalReward.consume_recruit_discount(rewards)
	assert_true(consumed, "Returns true when consuming")
	assert_false(GoalReward.has_active_reward(rewards, GoalReward.REWARD_RECRUIT_DISCOUNT), "Gone after consume")


func test_build_speed_bonus(_script: Script) -> void:
	var GoalReward = _script
	var rewards := []
	assert_eq(GoalReward.get_build_speed_bonus(rewards), 0.0, "No bonus without reward")

	rewards.append({"type": GoalReward.REWARD_BUILD_SPEED, "remaining": 20})
	assert_eq(GoalReward.get_build_speed_bonus(rewards), 0.16, "Returns 0.16 bonus")


func test_gather_speed_multiplier(_script: Script) -> void:
	var GoalReward = _script
	var rewards := []
	assert_eq(GoalReward.get_gather_speed_multiplier(rewards), 1.0, "No multiplier without reward")

	rewards.append({"type": GoalReward.REWARD_GATHER_SPEED, "remaining": 20})
	assert_eq(GoalReward.get_gather_speed_multiplier(rewards), 1.5, "Returns 1.5x multiplier")


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
		{"type": GoalReward.REWARD_HAUL_SPEED, "label": "haul speed +10%", "remaining": 15},
	]

	var text = GoalReward.format_active_rewards(rewards)
	assert_true(text.find("+1 food trickle") >= 0, "Contains first reward label")
	assert_true(text.find("haul speed +10%") >= 0, "Contains second reward label")
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
