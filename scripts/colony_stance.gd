class_name ColonyStance
# Colony stance data model — pure data, no UI.
# Stances nudge task selection without micromanagement.
# See misospace/windowstead#140.

const STANCE_BALANCED := "balanced"
const STANCE_BUILD := "build"
const STANCE_GATHER := "gather"
const STANCE_FOOD := "food"

const ALL_STANCES := [STANCE_BALANCED, STANCE_BUILD, STANCE_GATHER, STANCE_FOOD]

# Stance display labels and descriptions shown in UI.
const STANCE_INFO := {
	STANCE_BALANCED: {"label": "Balanced",  "description": "Default priorities"},
	STANCE_BUILD:    {"label": "Build",     "description": "Focus on construction"},
	STANCE_GATHER:   {"label": "Gather",    "description": "Focus on resource gathering"},
	STANCE_FOOD:     {"label": "Food",      "description": "Prioritize food gathering"},
}

# Stance -> preferred task kind (the kind that gets tried first).
# "balanced" uses the player's manual priority_order as-is.
const STANCE_PREFERRED_KIND := {
	STANCE_BALANCED: "",       # empty = defer to player's priority_order
	STANCE_BUILD:    "build",
	STANCE_GATHER:   "gather",
	STANCE_FOOD:     "gather_food",  # special kind for food-biased gather
}

# ── Compute effective priority order given a stance and player's manual order ──
# Returns an array of task kinds in the order they should be tried.
static func get_effective_priority_order(colony_stance: String, player_order: Array[String]) -> Array[String]:
	if colony_stance == STANCE_BALANCED or colony_stance == "":
		return player_order.duplicate()

	var preferred: String = STANCE_PREFERRED_KIND.get(colony_stance, "")
	if preferred.is_empty():
		return player_order.duplicate()

	var result: Array[String] = []

	# For food stance, add a special gather_food kind first
	if colony_stance == STANCE_FOOD:
		result.append("gather_food")

	# Add the preferred kind if not already in player order
	if not player_order.has(preferred):
		result.append(preferred)

	# Then follow the player's manual priority_order, skipping the preferred kind
	for kind in player_order:
		if kind != preferred and not result.has(kind):
			result.append(kind)

	return result


# ── Check if a gather task matches food-biased stance ──
static func is_food_gather_task(task: Dictionary) -> bool:
	var kind := String(task.get("kind", ""))
	if kind != "gather" and kind != "gather_food":
		return false
	return String(task.get("resource", "")) == "food"
