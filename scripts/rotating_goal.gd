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
# }

# ── Goal catalog (fixed, deterministic) ──────────────────────────────────────
# Each entry is a template; apply_goal_template creates an active goal.
const GOAL_CATALOG := [
	{"id": "gather_wood",    "type": GOAL_TYPE_RESOURCE,   "target": {"resource": "wood",    "amount": 10}},
	{"id": "gather_stone",   "type": GOAL_TYPE_RESOURCE,   "target": {"resource": "stone",   "amount": 5}},
	{"id": "gather_food",    "type": GOAL_TYPE_RESOURCE,   "target": {"resource": "food",    "amount": 8}},
	{"id": "build_hut",      "type": GOAL_TYPE_BUILD,      "target": {"build_kind": "hut"}},
	{"id": "build_workshop", "type": GOAL_TYPE_BUILD,      "target": {"build_kind": "workshop"}},
	{"id": "build_garden",   "type": GOAL_TYPE_BUILD,      "target": {"build_kind": "garden"}},
	{"id": "any_build",      "type": GOAL_TYPE_BUILD_COMPLETE, "target": {}},
]

# ── Create an active goal from a catalog entry ───────────────────────────────
static func apply_goal_template(template: Dictionary) -> Dictionary:
	return {
		"id": template["id"],
		"type": template["type"],
		"target": template["target"].duplicate(true),
		"current_progress": 0,
		"completed": false,
	}

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
