extends "res://tests/test_case.gd"
# Tests for structure_build_speed (issue #390, links to #147).
# The food-based slowdown must scale the post-reward speed: at the starvation
# threshold the slowdown factor is 0.0, so build speed must be 0.0 even while a
# REWARD_BUILD_SPEED reward is active. Before the fix the reward bonus was added
# after the *= 0.0 and starving colonies kept building at the bonus rate.
# Run with: godot --headless --path . --script res://tests/test_build_speed_slowdown.gd

const Constants := preload("res://scripts/constants.gd")
const ColonySim := preload("res://scripts/colony_sim.gd")
const GoalReward := preload("res://scripts/goal_reward.gd")


func run_tests() -> void:
	var sim := _sim()

	# ── Full food, no reward: unscaled base speed ────────────────────────────
	sim.state["resources"]["food"] = 10
	assert_eq(sim.get_food_slowdown_factor(), 1.0, "full food: slowdown factor is 1.0")
	assert_eq(sim.structure_build_speed("hut"), 0.34, "full food, no reward: base build speed 0.34")

	# ── Full food + active build reward: full post-reward speed ──────────────
	sim.state["active_rewards"] = [{
		"type": GoalReward.REWARD_BUILD_SPEED,
		"remaining": 20,
	}]
	assert_eq(sim.structure_build_speed("hut"), 0.34 + 0.16, "full food + reward: post-reward speed 0.50")

	# ── Starvation + active build reward: nothing builds ─────────────────────
	sim.state["resources"]["food"] = Constants.STARVATION_FOOD_THRESHOLD
	assert_eq(sim.get_food_slowdown_factor(), 0.0, "starvation: slowdown factor is 0.0")
	assert_eq(sim.structure_build_speed("hut"), 0.0, "starvation + reward: build speed is 0.0")

	# ── Starvation, no reward (control): nothing builds ──────────────────────
	sim.state["active_rewards"] = []
	assert_eq(sim.structure_build_speed("hut"), 0.0, "starvation, no reward: build speed is 0.0")

	# ── Low food: reward bonus scaled by the low-food factor ─────────────────
	sim.state["resources"]["food"] = Constants.LOW_FOOD_THRESHOLD
	sim.state["active_rewards"] = [{
		"type": GoalReward.REWARD_BUILD_SPEED,
		"remaining": 20,
	}]
	assert_eq(
		sim.structure_build_speed("hut"),
		(0.34 + 0.16) * Constants.LOW_FOOD_SPEED_FACTOR,
		"low food + reward: post-reward speed scaled by factor"
	)


func _sim() -> ColonySim:
	var sim := ColonySim.new()
	sim.state["resources"] = {"food": 10, "wood": 0, "stone": 0}
	sim.state["active_rewards"] = []
	sim.state["builds"] = []
	return sim
