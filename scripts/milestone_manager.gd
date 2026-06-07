class_name MilestoneManager
# Fixed early-game milestone goals for Windowstead.
# See misospace/windowstead#132.
#
# Milestones sit above rotating micro-goals: they are a small,
# fixed progression chain that gives the player a sense of
# early-game direction without replacing the ambient desktop-
# companion feel.
#
# Evaluation is pure-data (reads game_state dictionaries only).
# Completion state persists in save data.

const MILESTONE_TYPE_BUILD := "build"
const MILESTONE_TYPE_STOCKPILE := "stockpile"
const MILESTONE_TYPE_WORKER := "worker"

# ── Milestone catalog (fixed, deterministic) ────────────────────────────────
# Each entry defines one step in the early progression chain.
# Order matters: milestones are evaluated sequentially.
const MILESTONE_CATALOG := [
	{
		"id": "build_hut",
		"name": "Build a hut",
		"type": MILESTONE_TYPE_BUILD,
		"target": {"build_kind": "hut"},
		"description": "Your first shelter. The crew gets a roof.",
	},
	{
		"id": "stockpile_food",
		"name": "Stockpile 10 food",
		"type": MILESTONE_TYPE_STOCKPILE,
		"target": {"resource": "food", "amount": 10},
		"description": "The larder is filling up. Rations secured.",
	},
	{
		"id": "build_workshop",
		"name": "Build a workshop",
		"type": MILESTONE_TYPE_BUILD,
		"target": {"build_kind": "workshop"},
		"description": "A proper workspace. Things are getting serious.",
	},
	{
		"id": "build_garden",
		"name": "Build a garden",
		"type": MILESTONE_TYPE_BUILD,
		"target": {"build_kind": "garden"},
		"description": "Fresh greens on the horizon. Self-sufficient vibes.",
	},
	{
		"id": "support_third_worker",
		"name": "Support a third worker",
		"type": MILESTONE_TYPE_WORKER,
		"target": {"worker_count": 3},
		"description": "A full crew. The colony is growing.",
	},
]

# ── Active goal state (per-save) ────────────────────────────────────────────
# {
#   "milestone_id": String,    # ID of the current milestone from catalog
#   "completed_ids": Array     # IDs of previously completed milestones
# }

# ── Create a fresh milestone goal state ─────────────────────────────────────
static func make_goal_state() -> Dictionary:
	return {
		"milestone_id": MILESTONE_CATALOG[0]["id"],
		"completed_ids": [],
	}

# ── Get the current milestone definition from catalog ────────────────────────
static func get_current_milestone(catalog: Array, milestone_id: String) -> Dictionary:
	for entry in catalog:
		if entry.get("id") == milestone_id:
			return entry.duplicate(true)
	return {}

# ── Progress evaluation (pure data, reads game_state) ────────────────────────

# Evaluate whether the current milestone is complete given game state.
# Returns {progress: int, total: int} for UI progress display.
static func evaluate_milestone(milestone: Dictionary, game_state: Dictionary) -> Dictionary:
	var mtype := String(milestone.get("type", ""))
	var target := milestone.get("target", {})

	match mtype:
		MILESTONE_TYPE_BUILD:
			var build_kind := String(target.get("build_kind", ""))
			var builds := game_state.get("builds", [])
			for build in builds:
				if bool(build.get("complete")) and String(build.get("kind", "")) == build_kind:
					return {"progress": 1, "total": 1}
			return {"progress": 0, "total": 1}

		MILESTONE_TYPE_STOCKPILE:
			var resource := String(target.get("resource", ""))
			var amount := int(target.get("amount", 0))
			var harvested := game_state.get("harvested", {})
			var current := int(harvested.get(resource, 0))
			return {"progress": mini(current, amount), "total": amount}

		MILESTONE_TYPE_WORKER:
			var count := int(target.get("worker_count", 0))
			var workers := game_state.get("workers", [])
			var active := 0
			for worker in workers:
				if int(worker.get("break_ticks", 0)) <= 0:
					active += 1
			return {"progress": mini(active, count), "total": count}

		_:
			return {"progress": 0, "total": 1}

# ── Completion check ────────────────────────────────────────────────────────
static func is_milestone_complete(milestone: Dictionary, game_state: Dictionary) -> bool:
	var eval := evaluate_milestone(milestone, game_state)
	return eval.get("progress", 0) >= eval.get("total", 1)

# ── Advance to next milestone ───────────────────────────────────────────────
static func advance_to_next(completed_ids: Array, current_id: String) -> String:
	# Find the index of the current milestone in the catalog
	var current_index := -1
	for i in range(MILESTONE_CATALOG.size()):
		if MILESTONE_CATALOG[i]["id"] == current_id:
			current_index = i
			break

	if current_index < 0 or current_index >= MILESTONE_CATALOG.size() - 1:
		return current_id  # No next milestone

	var next_index := current_index + 1
	return MILESTONE_CATALOG[next_index]["id"]

# ── Milestone description for event log ─────────────────────────────────────
static func milestone_description(milestone: Dictionary) -> String:
	return String(milestone.get("description", "A new milestone."))
