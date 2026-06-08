class_name GoalProgression
# Goal progression controller — pure game logic, no UI.
# Extracted from main.gd as part of misospace/windowstead#177.
#
# Responsibilities:
#   - Initialize active goal from completed-IDs list
#   - Compute progress for every goal type each tick
#   - Detect completion and rotate to the next catalog goal
#   - Return structured results so callers can render or persist

const RotatingGoal := preload("res://scripts/rotating_goal.gd")


# ── Result type ──────────────────────────────────────────────────────────────
# Returned by process_tick() after progress computation and rotation.
# {
#   "active_goal": Dictionary,      # New or unchanged active goal
#   "completed_ids": Array,         # Updated completed-IDs list
#   "was_completed": bool,          # True if a goal was rotated this tick
#   "goal_id": String               # ID of the completed goal (empty if none)
# }


# ── Initialize active goal ───────────────────────────────────────────────────
# Called once at game start or after loading saved state.
static func init_goals(completed_ids: Array) -> Dictionary:
	return RotatingGoal.select_next_active_goal(completed_ids)


# ── Compute progress for the current active goal ─────────────────────────────
# Reads from game_state and updates active_goal in place.
# Call every tick before checking completion.
static func compute_progress(goal: Dictionary, game_state: Dictionary) -> void:
	if goal.is_empty():
		return
	RotatingGoal.compute_resource_progress(goal, game_state)
	RotatingGoal.compute_build_progress(goal, game_state)
	RotatingGoal.compute_build_complete_progress(goal, game_state)


# ── Check completion and rotate ──────────────────────────────────────────────
# If the active goal is complete, mark it done, rotate, and return a result.
# Otherwise returns an unchanged result.
static func check_and_rotate(goal: Dictionary, completed_ids: Array) -> Dictionary:
	if goal.is_empty() or not RotatingGoal.is_goal_complete(goal):
		return {
			"active_goal": goal.duplicate(true),
			"completed_ids": completed_ids.duplicate(),
			"was_completed": false,
			"goal_id": "",
		}

	var goal_id := String(goal.get("id", "unknown"))
	var new_goal = RotatingGoal.rotate_after_completion(goal, completed_ids)
	completed_ids.append(goal["id"])

	return {
		"active_goal": new_goal,
		"completed_ids": completed_ids.duplicate(),
		"was_completed": true,
		"goal_id": goal_id,
	}


# ── Full tick processing (compute + rotate) ──────────────────────────────────
# Convenience wrapper: compute progress then check/rotate in one call.
static func process_tick(goal: Dictionary, completed_ids: Array, game_state: Dictionary) -> Dictionary:
	if not goal.is_empty():
		compute_progress(goal, game_state)

	return check_and_rotate(goal, completed_ids)
