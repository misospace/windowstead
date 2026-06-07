class_name RotatingGoal
# Rotating colony goal data model — pure data, no UI.
# See misospace/windowstead#142 and #131.

const GOAL_TYPE_RESOURCE := "resource"
const GOAL_TYPE_BUILD := "build"
const GOAL_TYPE_BUILD_COMPLETE := "build_complete"

# ── Goal state (pure data dictionary) ────────────────────────────────────────
# {
#   "id": String,           # Unique identifier
#   "type": String,         # GOAL_TYPE_*
#   "target": Dictionary,   # {"resource": "wood", "amount": 10} or {"build_kind": "hut"}
#   "current_progress": int,# Current progress value
#   "completed": bool       # Whether the goal is satisfied
#   "reward": String        # Short reward label shown in UI preview (optional)
# }

# ── Goal catalog (fixed, deterministic) ──────────────────────────────────────
# Each entry is a template; apply_goal_template creates an active goal.
const GOAL_CATALOG := [
	{"id": "gather_wood",    "type": GOAL_TYPE_RESOURCE,   "target": {"resource": "wood",    "amount": 10},      "reward": "+1 food"},
	{"id": "gather_stone",   "type": GOAL_TYPE_RESOURCE,   "target": {"resource": "stone",   "amount": 5},       "reward": "+1 food"},
	{"id": "gather_food",    "type": GOAL_TYPE_RESOURCE,   "target": {"resource": "food",    "amount": 8},       "reward": "+1 food"},
	{"id": "build_hut",      "type": GOAL_TYPE_BUILD,      "target": {"build_kind": "hut"},                     "reward": "haul speed +10%"},
	{"id": "build_workshop", "type": GOAL_TYPE_BUILD,      "target": {"build_kind": "workshop"},                "reward": "next recruit -1 food"},
	{"id": "build_garden",   "type": GOAL_TYPE_BUILD,      "target": {"build_kind": "garden"},                  "reward": "ambient event improves"},
	{"id": "any_build",      "type": GOAL_TYPE_BUILD_COMPLETE, "target": {},                                  "reward": "+1 food"},
]

# ── Create an active goal from a catalog entry ───────────────────────────────
static func apply_goal_template(template: Dictionary) -> Dictionary:
	var goal := {
		"id": template["id"],
		"type": template["type"],
		"target": template["target"].duplicate(true),
		"current_progress": 0,
		"completed": false,
	}
	if template.has("reward") and not String(template["reward"]).is_empty():
		goal["reward"] = template["reward"]
	return goal

# ── Deterministic goal selection ─────────────────────────────────────────────
# Returns the first non-completed goal from the catalog, or null if all done.
static func select_next_active_goal(completed_ids: Array) -> Dictionary:
	for template in GOAL_CATALOG:
		if not completed_ids.has(template["id"]):
			return apply_goal_template(template)
	return {}

# ── Progress helpers ─────────────────────────────────────────────────────────

# Update progress for resource goals.
# current_progress += delta (clamped at target amount).
static func update_resource_progress(goal: Dictionary, delta: int) -> void:
	if goal.get("type") != GOAL_TYPE_RESOURCE:
		return
	var target_amount = goal.get("target", {}).get("amount", 0)
	goal["current_progress"] = min(goal["current_progress"] + delta, target_amount)

# Compute progress from game state for resource goals.
# Reads harvested or gathered amounts and sets current_progress.
static func compute_resource_progress(goal: Dictionary, game_state: Dictionary) -> void:
	if goal.get("type") != GOAL_TYPE_RESOURCE:
		return
	var resource_name = goal.get("target", {}).get("resource", "")
	var harvested = game_state.get("harvested", {})
	var amount = int(harvested.get(resource_name, 0))
	goal["current_progress"] = amount

# Compute progress from game state for build goals.
# Counts existing builds of the target kind.
static func compute_build_progress(goal: Dictionary, game_state: Dictionary) -> void:
	if goal.get("type") != GOAL_TYPE_BUILD:
		return
	var target_kind = goal.get("target", {}).get("build_kind", "")
	var builds = game_state.get("builds", [])
	var count = 0
	for build in builds:
		if build.get("kind", "") == target_kind or build.get("build_kind", "") == target_kind:
			count += 1
	goal["current_progress"] = count

# Compute progress for build-complete goals (total builds).
static func compute_build_complete_progress(goal: Dictionary, game_state: Dictionary) -> void:
	if goal.get("type") != GOAL_TYPE_BUILD_COMPLETE:
		return
	goal["current_progress"] = game_state.get("builds", []).size()

# ── Completion detection ─────────────────────────────────────────────────────

# Check if a resource goal is complete.
static func is_resource_complete(goal: Dictionary) -> bool:
	if goal.get("type") != GOAL_TYPE_RESOURCE:
		return false
	return goal.get("current_progress", 0) >= goal.get("target", {}).get("amount", 0)

# Check if a build goal is complete (at least one build of the target kind).
static func is_build_complete(goal: Dictionary) -> bool:
	if goal.get("type") != GOAL_TYPE_BUILD:
		return false
	return goal.get("current_progress", 0) > 0

# Check if a build-complete goal is complete.
static func is_build_complete_goal(goal: Dictionary) -> bool:
	if goal.get("type") != GOAL_TYPE_BUILD_COMPLETE:
		return false
	return goal.get("current_progress", 0) > 0

# Generic completion check — dispatches by type.
static func is_goal_complete(goal: Dictionary) -> bool:
	match goal.get("type"):
		GOAL_TYPE_RESOURCE:
			return is_resource_complete(goal)
		GOAL_TYPE_BUILD:
			return is_build_complete(goal)
		GOAL_TYPE_BUILD_COMPLETE:
			return is_build_complete_goal(goal)
	return false

# Mark a goal as completed (no-op reward; just sets flag).
static func complete_goal(goal: Dictionary) -> void:
	goal["completed"] = true

# ── Reward preview formatting ────────────────────────────────────────────────
# Returns a short string for the compact dock UI. Returns "" if no reward data.

# Format the reward label for display in the goal UI preview.
# The returned text is already short enough for compact dock layouts.
static func get_reward_preview_text(goal: Dictionary) -> String:
	if not goal.has("reward"):
		return ""
	var reward := String(goal["reward"])
	if reward.is_empty():
		return ""
	return "Reward: %s" % reward

# ── Goal rotation on completion ──────────────────────────────────────────────
# Completes the given goal and selects the next active goal from the catalog,
# avoiding immediate repeats of recently completed IDs.
# Returns the new active goal (Dictionary), or {} if all catalog goals are done.
static func rotate_after_completion(active_goal: Dictionary, completed_ids: Array) -> Dictionary:
	# Mark current goal as completed
	complete_goal(active_goal)

	# Collect unique completed IDs (deduplicate while preserving order)
	var unique_completed := []
	var seen := {}
	for cid in completed_ids:
		if not seen.has(cid):
			unique_completed.append(cid)
			seen[cid] = true

	# Always include the just-completed goal's ID to prevent immediate repeat
	if active_goal.has("id"):
		unique_completed.append(active_goal["id"])

	# Select next non-completed goal from catalog
	return select_next_active_goal(unique_completed)
