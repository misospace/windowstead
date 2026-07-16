class_name GoalReward
# Goal reward system — applies small temporary bonuses on goal completion.
# Rewards only affect existing systems; no new resources are introduced.
# See misospace/windowstead#134.

const REWARD_RESOURCE_TRICKLE := "resource_trickle"
const REWARD_GATHER_SPEED := "gather_speed"
const REWARD_HAUL_SPEED := "haul_speed"
const REWARD_BUILD_SPEED := "build_speed"
const REWARD_AMBIENT_IMPROVE := "ambient_improve"
const REWARD_RECRUIT_DISCOUNT := "recruit_discount"

# Default durations (in ticks) for temporary rewards.
const DURATION_GATHER_SPEED := 30
const DURATION_HAUL_SPEED := 30
const DURATION_BUILD_SPEED := 40
const DURATION_RESOURCE_TRICKLE := 50
const TRICKLE_INTERVAL := 10  # ticks between trickle payouts

# Strength of each reward type — kept next to the catalog so labels and
# effects are tuned in one place (speed rewards are multipliers, build speed
# is an additive bonus, trickle is units per payout).
const REWARD_MAGNITUDES := {
	REWARD_GATHER_SPEED: 1.5,
	REWARD_HAUL_SPEED: 1.5,
	REWARD_BUILD_SPEED: 0.16,
	REWARD_RESOURCE_TRICKLE: 1,
}

# Reward catalog: maps goal IDs to reward definitions.
# Each entry is a dictionary with keys:
#   "type": String — REWARD_* constant
#   "resource": String (optional) — resource affected by trickle
#   "duration": int — how many ticks the reward lasts (0 = one-time)
#   "label": String — short human-readable label for event log
const REWARD_CATALOG := {
	"gather_wood":    {"type": REWARD_RESOURCE_TRICKLE, "resource": "food",    "duration": DURATION_RESOURCE_TRICKLE, "label": "+1 food trickle"},
	"gather_stone":   {"type": REWARD_RESOURCE_TRICKLE, "resource": "food",    "duration": DURATION_RESOURCE_TRICKLE, "label": "+1 food trickle"},
	"gather_food":    {"type": REWARD_RESOURCE_TRICKLE, "resource": "food",    "duration": DURATION_RESOURCE_TRICKLE, "label": "+1 food trickle"},
	"build_hut":      {"type": REWARD_HAUL_SPEED,       "duration": DURATION_HAUL_SPEED,         "label": "haul speed +10%"},
	"build_workshop": {"type": REWARD_RECRUIT_DISCOUNT,  "duration": 0,                              "label": "next recruit -1 food"},
	"build_garden":   {"type": REWARD_AMBIENT_IMPROVE,   "duration": 0,                              "label": "ambient event improves"},
	"any_build":      {"type": REWARD_RESOURCE_TRICKLE, "resource": "food",    "duration": DURATION_RESOURCE_TRICKLE, "label": "+1 food trickle"},
}


# ── Reward state ─────────────────────────────────────────────────────────────
# An active reward is a dictionary:
# {
#   "type": String,           # REWARD_* constant
#   "resource": String,       # (optional) resource for trickle
#   "remaining": int,         # ticks remaining
#   "duration": int,          # original duration (for display)
#   "trickle_ticks": int,     # accumulator for resource_trickle payouts
#   "label": String,          # human-readable label
# }


# ── Apply reward from goal completion ────────────────────────────────────────
# Returns a new active reward dictionary, or empty dict if no reward defined.
static func apply_reward(goal_id: String) -> Dictionary:
	var entry: Dictionary = REWARD_CATALOG.get(goal_id, {})
	if entry.is_empty():
		return {}

	var reward := {
		"type": entry["type"],
		"remaining": entry.get("duration", 0),
		"duration": entry.get("duration", 0),
		"trickle_ticks": 0,
		"label": entry.get("label", ""),
	}

	if entry.has("resource"):
		reward["resource"] = entry["resource"]

	return reward


# ── Get reward label for a goal (preview) ────────────────────────────────────
static func get_reward_label(goal_id: String) -> String:
	var entry: Dictionary = REWARD_CATALOG.get(goal_id, {})
	if entry.is_empty():
		return ""
	return entry.get("label", "")


# ── Tick all active rewards ──────────────────────────────────────────────────
# Decrements remaining ticks. Returns list of expired reward labels.
# Also applies resource trickle payouts when interval is reached.
# Modifies state.resources for trickle payouts.
static func tick_rewards(active_rewards: Array, game_state: Dictionary) -> Dictionary:
	# {expired: Array[String], events: Array[String], new_rewards: Array[Dictionary]}
	var result := {"expired": [], "events": [], "new_rewards": []}

	var surviving := []
	for reward in active_rewards:
		var rtype := String(reward.get("type", ""))

		if rtype == REWARD_RESOURCE_TRICKLE:
			# Accumulate and pay out at interval
			reward["trickle_ticks"] = reward.get("trickle_ticks", 0) + 1
			if reward["trickle_ticks"] >= TRICKLE_INTERVAL:
				reward["trickle_ticks"] = 0
				var res := String(reward.get("resource", "food"))
				var amount := int(REWARD_MAGNITUDES[REWARD_RESOURCE_TRICKLE])
				if game_state.has("resources"):
					game_state.resources[res] = int(game_state.resources.get(res, 0)) + amount
				result["events"].append("+%d %s (goal reward)" % [amount, res])

		if reward["remaining"] <= 0:
			result["expired"].append(reward.get("label", rtype))
			continue

		reward["remaining"] -= 1
		surviving.append(reward)

	result["new_rewards"] = surviving
	return result


# ── Check if a specific reward type is active ────────────────────────────────
static func has_active_reward(active_rewards: Array, reward_type: String) -> bool:
	for reward in active_rewards:
		if String(reward.get("type", "")) == reward_type:
			return true
	return false


# ── Get gather speed multiplier from active rewards ──────────────────────────
static func get_gather_speed_multiplier(active_rewards: Array) -> float:
	if has_active_reward(active_rewards, REWARD_GATHER_SPEED):
		return float(REWARD_MAGNITUDES[REWARD_GATHER_SPEED])
	return 1.0


# ── Get haul speed multiplier from active rewards ────────────────────────────
static func get_haul_speed_multiplier(active_rewards: Array) -> float:
	if has_active_reward(active_rewards, REWARD_HAUL_SPEED):
		return float(REWARD_MAGNITUDES[REWARD_HAUL_SPEED])
	return 1.0


# ── Get build speed bonus from active rewards ────────────────────────────────
static func get_build_speed_bonus(active_rewards: Array) -> float:
	if has_active_reward(active_rewards, REWARD_BUILD_SPEED):
		return float(REWARD_MAGNITUDES[REWARD_BUILD_SPEED])
	return 0.0


# ── Check if ambient event should be improved ────────────────────────────────
# Returns true and consumes the one-time reward if active.
static func consume_ambient_improve(active_rewards: Array) -> bool:
	for i in range(active_rewards.size()):
		var reward = active_rewards[i]
		if String(reward.get("type", "")) == REWARD_AMBIENT_IMPROVE:
			active_rewards.remove_at(i)
			return true
	return false


# ── Check if recruit discount is active ──────────────────────────────────────
# Returns true and consumes the one-time reward if active.
static func consume_recruit_discount(active_rewards: Array) -> bool:
	for i in range(active_rewards.size()):
		var reward = active_rewards[i]
		if String(reward.get("type", "")) == REWARD_RECRUIT_DISCOUNT:
			active_rewards.remove_at(i)
			return true
	return false


# ── Format active rewards for UI display ─────────────────────────────────────
# Returns a short string summarizing active rewards.
static func format_active_rewards(active_rewards: Array) -> String:
	if active_rewards.is_empty():
		return ""

	var parts := []
	for reward in active_rewards:
		var label := String(reward.get("label", ""))
		var remaining := int(reward.get("remaining", 0))
		if label.is_empty():
			label = reward.get("type", "?")
		parts.append("%s (%d)" % [label, remaining])

	return " | ".join(parts)
