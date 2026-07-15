extends Node

const LayoutMath := preload("res://scripts/layout_math.gd")
const RotatingGoal := preload("res://scripts/rotating_goal.gd")
const ColonyStance := preload("res://scripts/colony_stance.gd")
const GoalReward := preload("res://scripts/goal_reward.gd")

const SAVE_KEY := "windowstead-save-v2"
const BACKUP_PREFIX := "windowstead-backup-"
const SAVE_PATH := "user://windowstead.save"
const SAVE_VERSION := 2
const SETTINGS_KEY := "windowstead-settings-v1"
const SETTINGS_PATH := "user://windowstead.settings"

# Grid sizes are derived from LayoutMath's known anchor families; small legacy
# sizes are kept only for historical save compatibility.
const _LEGACY_GRID_SIZES: Array = [25, 36, 64, 100, 150]

var save_supported := false
var use_local_storage := false

var _backup_counter := 0

func _ready() -> void:
	save_supported = true
	if OS.has_feature("web"):
		use_local_storage = JavaScriptBridge.eval("typeof localStorage !== 'undefined'", true)

func save_game(data: Dictionary, path: String = "") -> void:
	var target_path := path if not path.is_empty() else SAVE_PATH
	var payload := JSON.stringify(data)
	if use_local_storage:
		JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [SAVE_KEY, JSON.stringify(payload)], true)
		return
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file:
		file.store_string(payload)
		file.close()

func load_game(path: String = "") -> Dictionary:
	var target_path := path if not path.is_empty() else SAVE_PATH
	if use_local_storage:
		var raw = JavaScriptBridge.eval("localStorage.getItem('%s')" % SAVE_KEY, true)
		if raw == null or String(raw).is_empty() or String(raw) == "null":
			return {}
		var parsed = JSON.parse_string(String(raw))
		if typeof(parsed) == TYPE_STRING:
			return JSON.parse_string(parsed) if JSON.parse_string(parsed) is Dictionary else {}
		if parsed is Dictionary and not parsed.is_empty():
			rebuild_reservations_from_workers(parsed)
		return parsed
	if not FileAccess.file_exists(target_path):
		return {}
	var file := FileAccess.open(target_path, FileAccess.READ)
	if not file:
		return {}
	var text := file.get_as_text()
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}

	# Validate schema before migration
	var validation_result := validate_save_schema(parsed)
	if not validation_result.valid:
		print("SAVE_SCHEMA_VALIDATION_ERROR: %s" % validation_result.reason)
		return {}

	var migrated := migrate_save(parsed)
	if not migrated.is_empty():
		rebuild_reservations_from_workers(migrated)
	return migrated

# ── Rebuild reserved_resources from active worker tasks ──────────────────────
# Called after load/migration to prevent double-booking when reservations are
# missing or stale. Only rebuilds when the field is empty (missing from old saves).

func rebuild_reservations_from_workers(state: Dictionary) -> void:
	var existing: Dictionary = state.get("reserved_resources", {})
	if not existing.is_empty():
		return  # Already has reservations — trust them

	state["reserved_resources"] = {}
	var workers: Array = state.get("workers", [])
	for worker in workers:
		var task: Dictionary = worker.get("task", {})
		if task.is_empty():
			continue
		var kind: String = task.get("kind", "")
		if kind == "gather" or kind == "haul":
			var resource: String = task.get("resource", "")
			if not resource.is_empty():
				state["reserved_resources"][resource] = state["reserved_resources"].get(resource, 0) + 1

# ── Schema validation ────────────────────────────────────────────────────────
# Returns {valid: bool, reason: String}
# Only validates fields that are present; missing optional fields are allowed.

func validate_save_schema(data: Dictionary) -> Dictionary:
	# Validate 'save_version' if present — must be a known version
	if data.has("save_version"):
		var sv = int(data["save_version"])
		if sv < 0:
			return {"valid": false, "reason": "save_version is negative"}

	# Validate 'resources' is a dictionary with numeric values (if present)
	if data.has("resources"):
		var resources = data.get("resources", {})
		if not resources is Dictionary:
			return {"valid": false, "reason": "'resources' must be a dictionary"}
		for resource_name in resources:
			var val = resources[resource_name]
			if typeof(val) != TYPE_INT and typeof(val) != TYPE_FLOAT:
				return {"valid": false, "reason": "'resources.%s' must be numeric" % resource_name}

	# Validate 'harvested' is a dictionary with numeric values (if present)
	if data.has("harvested"):
		var harvested = data.get("harvested", {})
		if not harvested is Dictionary:
			return {"valid": false, "reason": "'harvested' must be a dictionary"}
		for resource_name in harvested:
			var val = harvested[resource_name]
			if typeof(val) != TYPE_INT and typeof(val) != TYPE_FLOAT:
				return {"valid": false, "reason": "'harvested.%s' must be numeric" % resource_name}

	# Validate 'tiles' is an array (if present)
	if data.has("tiles"):
		var tiles = data.get("tiles", [])
		if not tiles is Array:
			return {"valid": false, "reason": "'tiles' must be an array"}

		# If tiles are present and non-empty, validate grid size and shape
		var tile_count = tiles.size()
		if tile_count > 0:
			# Derive the expected grid sizes from the anchor family configuration
			# exported by LayoutMath rather than maintaining a hardcoded list.
			var expected_sizes: Array = _expected_grid_sizes()
			if not expected_sizes.has(tile_count):
				return {"valid": false, "reason": "'tiles' count %d does not match expected grid sizes (%s)" % [tile_count, str(expected_sizes)]}

			# Internal consistency: tile count must equal grid_w * grid_h for the
			# anchor family declared in the save (when both fields are present).
			if data.has("grid_w") and data.has("grid_h"):
				var gw_var = data["grid_w"]
				var gh_var = data["grid_h"]
				if typeof(gw_var) != TYPE_INT or typeof(gh_var) != TYPE_INT:
					return {"valid": false, "reason": "'grid_w' and 'grid_h' must be integers"}
				var gw: int = int(gw_var)
				var gh: int = int(gh_var)
				if gw <= 0 or gh <= 0:
					return {"valid": false, "reason": "'grid_w' and 'grid_h' must be positive"}
				if tile_count != gw * gh:
					return {"valid": false, "reason": "'tiles' count %d does not match grid_w*grid_h=%d" % [tile_count, gw * gh]}

			# Validate each tile has required shape
			for i in range(tiles.size()):
				var tile = tiles[i]
				if not tile is Dictionary:
					return {"valid": false, "reason": "tile[%d] must be a dictionary" % i}
				for tile_key in ["kind", "amount", "resource", "build_kind"]:
					if not tile.has(tile_key):
						return {"valid": false, "reason": "tile[%d] missing key '%s'" % [i, tile_key]}
				# Validate tile shape: amount must be numeric, resource must be string
				var amt: Variant = tile.get("amount", -1)
				if typeof(amt) != TYPE_INT and typeof(amt) != TYPE_FLOAT:
					return {"valid": false, "reason": "tile[%d].amount must be numeric" % i}
				var res: Variant = tile.get("resource", "")
				if typeof(res) != TYPE_STRING:
					return {"valid": false, "reason": "tile[%d].resource must be string" % i}
				# build_kind is optional; if present must be string
				if tile.has("build_kind") and typeof(tile["build_kind"]) != TYPE_STRING:
					return {"valid": false, "reason": "tile[%d].build_kind must be string" % i}

	# Validate 'workers' is an array (if present)
	if data.has("workers"):
		var workers = data.get("workers", [])
		if not workers is Array:
			return {"valid": false, "reason": "'workers' must be an array"}

		# Validate each worker has required shape and numeric bounds
		for k in range(workers.size()):
			var worker = workers[k]
			if not worker is Dictionary:
				return {"valid": false, "reason": "worker[%d] must be a dictionary" % k}
			# Validate name is string
			var wname = worker.get("name", "")
			if typeof(wname) != TYPE_STRING or String(wname).is_empty():
				return {"valid": false, "reason": "worker[%d].name must be non-empty string" % k}
			# Validate pos is a dictionary (vec2 serialized as {x, y})
			var wpos = worker.get("pos", {})
			if not wpos is Dictionary:
				return {"valid": false, "reason": "worker[%d].pos must be dictionary" % k}
			# Validate carrying is a dictionary with numeric values
			var wcarrying = worker.get("carrying", {})
			if not wcarrying is Dictionary:
				return {"valid": false, "reason": "worker[%d].carrying must be dictionary" % k}
			for res_name in wcarrying:
				var cv = wcarrying[res_name]
				if typeof(cv) != TYPE_INT and typeof(cv) != TYPE_FLOAT:
					return {"valid": false, "reason": "worker[%d].carrying.%s must be numeric" % [k, res_name]}
			# Validate task is a dictionary
			var wtask = worker.get("task", {})
			if not wtask is Dictionary:
				return {"valid": false, "reason": "worker[%d].task must be dictionary" % k}
			# Validate break_ticks is numeric and non-negative (optional — missing defaults to 0 for v1 compat)
			if worker.has("break_ticks"):
				var wbreak = worker.get("break_ticks", 0)
				if typeof(wbreak) != TYPE_INT and typeof(wbreak) != TYPE_FLOAT:
					return {"valid": false, "reason": "worker[%d].break_ticks must be numeric" % k}
				if float(wbreak) < 0:
					return {"valid": false, "reason": "worker[%d].break_ticks must be non-negative" % k}

	# Validate 'builds' is an array (if present)
	if data.has("builds"):
		var builds = data.get("builds", [])
		if not builds is Array:
			return {"valid": false, "reason": "'builds' must be an array"}

		# Validate each build has required shape and numeric bounds
		for j in range(builds.size()):
			var build = builds[j]
			if not build is Dictionary:
				return {"valid": false, "reason": "build[%d] must be a dictionary" % j}
			for build_key in ["id", "kind", "pos", "complete"]:
				if not build.has(build_key):
					return {"valid": false, "reason": "build[%d] missing key '%s'" % [j, build_key]}
			# Validate id is numeric
			var bid = build.get("id", -1)
			if typeof(bid) != TYPE_INT and typeof(bid) != TYPE_FLOAT:
				return {"valid": false, "reason": "build[%d].id must be numeric" % j}
			# Validate kind is string
			var bkind = build.get("kind", "")
			if typeof(bkind) != TYPE_STRING:
				return {"valid": false, "reason": "build[%d].kind must be string" % j}
			# Validate pos is a dictionary (vec2 serialized as {x, y})
			var bpos = build.get("pos", {})
			if not bpos is Dictionary:
				return {"valid": false, "reason": "build[%d].pos must be dictionary" % j}
			# Validate complete is boolean
			var bcomplete = build.get("complete", false)
			if typeof(bcomplete) != TYPE_BOOL:
				return {"valid": false, "reason": "build[%d].complete must be boolean" % j}

	# Validate 'priority_order' is an array (if present)
	if data.has("priority_order"):
		var priority_order = data.get("priority_order", [])
		if not priority_order is Array:
			return {"valid": false, "reason": "'priority_order' must be an array"}

	# Validate 'events' is an array (if present)
	if data.has("events"):
		var events = data.get("events", [])
		if not events is Array:
			return {"valid": false, "reason": "'events' must be an array"}

	# Validate 'active_rewards' is an array of structurally valid reward dicts (if present)
	if data.has("active_rewards"):
		var active_rewards = data.get("active_rewards", [])
		if not active_rewards is Array:
			return {"valid": false, "reason": "'active_rewards' must be an array"}
		var reward_err := _validate_active_rewards(active_rewards)
		if not reward_err.is_empty():
			return {"valid": false, "reason": reward_err}

	# Validate 'active_goal' (if present) — must be {} or reference a known goal template
	if data.has("active_goal"):
		var goal_err := _validate_active_goal(data["active_goal"])
		if not goal_err.is_empty():
			return {"valid": false, "reason": goal_err}

	# Validate 'completed_goal_ids' (if present) — every entry must reference a known goal
	if data.has("completed_goal_ids"):
		var completed = data["completed_goal_ids"]
		if not completed is Array:
			return {"valid": false, "reason": "'completed_goal_ids' must be an array"}
		var known_ids := _known_goal_ids()
		for ci in range(completed.size()):
			var entry = completed[ci]
			if typeof(entry) != TYPE_STRING:
				return {"valid": false, "reason": "completed_goal_ids[%d] must be a string" % ci}
			if not known_ids.has(entry):
				return {"valid": false, "reason": "completed_goal_ids[%d]='%s' is not a known goal" % [ci, entry]}

	# Validate 'colony_stance' (if present) — must be one of the known stances or empty
	if data.has("colony_stance"):
		var stance_holder = data["colony_stance"]
		if typeof(stance_holder) != TYPE_STRING:
			return {"valid": false, "reason": "'colony_stance' must be a string"}
		var stance := String(stance_holder)
		if not stance.is_empty() and not _known_stances().has(stance):
			return {"valid": false, "reason": "'colony_stance'='%s' is not a known stance" % stance}

	return {"valid": true, "reason": ""}

# ── Schema helpers ──────────────────────────────────────────────────────────

# Compute valid tile counts from the LayoutMath anchor family configuration.
# Legacy grid sizes (25/36/64/100/150) are still accepted so historical saves
# remain loadable until they are migrated.
func _expected_grid_sizes() -> Array:
	var sizes: Array = []
	# Mirror the canonical anchor families in layout_math.gd; new anchors added
	# there will need to be appended here as well.
	var anchors: Array = ["bottom", "side"]
	for anchor in anchors:
		var dims = LayoutMath.grid_dims_for_anchor(anchor)
		if typeof(dims) != TYPE_DICTIONARY or dims.is_empty():
			continue
		var w: int = int(dims.get("grid_w", 0))
		var h: int = int(dims.get("grid_h", 0))
		if w <= 0 or h <= 0:
			continue
		var total: int = w * h
		if not sizes.has(total):
			sizes.append(total)
	# Sanity check: make sure both LayoutMath-published constants are covered.
	var bottom_size: int = int(LayoutMath.BOTTOM_GRID_W) * int(LayoutMath.BOTTOM_GRID_H)
	var side_size: int = int(LayoutMath.SIDE_GRID_W) * int(LayoutMath.SIDE_GRID_H)
	for raw in [bottom_size, side_size]:
		if raw > 0 and not sizes.has(raw):
			sizes.append(raw)
	for legacy in _LEGACY_GRID_SIZES:
		if not sizes.has(legacy):
			sizes.append(legacy)
	return sizes

# Set of goal identifiers drawn from RotatingGoal's catalog. Anything outside
# this set cannot be loaded as a completed/active goal.
func _known_goal_ids() -> Array:
	var ids: Array = []
	for template in RotatingGoal.GOAL_CATALOG:
		if typeof(template) == TYPE_DICTIONARY and template.has("id"):
			var gid = String(template.get("id", ""))
			if not gid.is_empty() and not ids.has(gid):
				ids.append(gid)
	return ids

# Set of reward keys granted by GoalReward.apply_reward. Used to validate the
# shape of each entry in 'active_rewards'.
func _known_reward_keys() -> Array:
	return ["type", "remaining", "duration", "label", "trickle_ticks", "resource"]

# Set of recognized reward types (union of REWARD_* constants) used to
# validate the 'type' field on each active_rewards entry.
func _known_reward_types() -> Array:
	var types: Array = []
	for entry in GoalReward.REWARD_CATALOG.values():
		if typeof(entry) == TYPE_DICTIONARY and entry.has("type"):
			var t = String(entry["type"])
			if not t.is_empty() and not types.has(t):
				types.append(t)
	# Belt-and-suspenders: include the REWARD_* constants declared above the
	# catalog in case the catalog is empty/duplicated.
	for raw in [
		GoalReward.REWARD_RESOURCE_TRICKLE,
		GoalReward.REWARD_GATHER_SPEED,
		GoalReward.REWARD_HAUL_SPEED,
		GoalReward.REWARD_BUILD_SPEED,
		GoalReward.REWARD_AMBIENT_IMPROVE,
		GoalReward.REWARD_RECRUIT_DISCOUNT,
	]:
		if typeof(raw) == TYPE_STRING and not raw.is_empty() and not types.has(raw):
			types.append(raw)
	return types

# Set of recognized colony stances exported by ColonyStance.
func _known_stances() -> Array:
	var stances: Array = []
	for s in ColonyStance.ALL_STANCES:
		if typeof(s) == TYPE_STRING and not stances.has(s):
			stances.append(s)
	return stances

# Validate an active_goal value. Returns empty string when valid, or a reason.
func _validate_active_goal(value) -> String:
	# No active goal is encoded as an empty Dictionary by the runtime.
	if typeof(value) == TYPE_DICTIONARY:
		if value.is_empty():
			return ""
		if not value.has("id"):
			return "'active_goal' dictionary missing key 'id'"
		var gid = String(value.get("id", ""))
		if not _known_goal_ids().has(gid):
			return "'active_goal.id'='%s' is not a known goal" % gid
		return ""
	return "'active_goal' must be a dictionary"

# Validate the contents of an active_rewards array. Returns empty string on
# success, or a human-readable reason for the first failure.
func _validate_active_rewards(rewards: Array) -> String:
	var known_keys := _known_reward_keys()
	var known_types := _known_reward_types()
	for ri in range(rewards.size()):
		var r = rewards[ri]
		if typeof(r) != TYPE_DICTIONARY:
			return "active_rewards[%d] must be a dictionary" % ri
		if not r.has("type"):
			return "active_rewards[%d] missing key 'type'" % ri
		var rtype = String(r.get("type", ""))
		if rtype.is_empty():
			return "active_rewards[%d].type must be non-empty" % ri
		if not known_types.has(rtype):
			return "active_rewards[%d].type='%s' is not a known reward type" % [ri, rtype]
		for key in known_keys:
			if not r.has(key):
				continue
			var v = r[key]
			if key in ["type", "label", "resource"] and typeof(v) != TYPE_STRING:
				return "active_rewards[%d].%s must be a string" % [ri, key]
			if key in ["remaining", "duration", "trickle_ticks"]:
				if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
					return "active_rewards[%d].%s must be numeric" % [ri, key]
				if float(v) < 0:
					return "active_rewards[%d].%s must be non-negative" % [ri, key]
	return ""

func migrate_save(data: Dictionary) -> Dictionary:
	# Missing version key means "current" — backward compatible
	if not data.has("save_version"):
		data["save_version"] = SAVE_VERSION
		return data

	var save_version: int = int(data.get("save_version", 0))

	# Reject unknown or future versions explicitly
	if save_version > SAVE_VERSION:
		print("SAVE_MIGRATION_ERROR: unknown future version %d (expected <=%d)" % [save_version, SAVE_VERSION])
		return {}

	# Version 0: treat as invalid/unsupported
	if save_version == 0:
		print("SAVE_MIGRATION_ERROR: missing or version 0 save is not supported")
		return {}

	if save_version == SAVE_VERSION:
		return data

	if save_version < 1:
		# Anything below v1 is unsupported — fail explicitly
		print("SAVE_MIGRATION_ERROR: unsupported save version %d (minimum: 1)" % save_version)
		return {}

	if save_version == 1:
		data = migrate_v1_to_v2(data)
		data["save_version"] = SAVE_VERSION
		persist_migrated_save(data)
		return data

	# Fallback: should not reach here, but handle defensively
	print("SAVE_MIGRATION_ERROR: unhandled save version %d" % save_version)
	return {}

func migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	# Add migration_log to track history
	if not data.has("migration_log"):
		data["migration_log"] = []
	data["migration_log"].append({"from_version": 1, "to_version": 2, "step": "initial_v2_schema"})
	# Ensure all workers have a spawn_tick for future tracking
	for worker in data.get("workers", []):
		if not worker.has("spawn_tick"):
			worker["spawn_tick"] = int(data.get("tick", 0))
	return data

func persist_migrated_save(data: Dictionary) -> void:
	save_game(data)

func clear_game() -> void:
	if use_local_storage:
		JavaScriptBridge.eval("localStorage.removeItem('%s')" % SAVE_KEY, true)
		JavaScriptBridge.eval("localStorage.removeItem('%s')" % SETTINGS_KEY, true)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


# ── Timestamped backup / restore ─────────────────────────────────────────────

func _backup_filename() -> String:
	"""Generate a unique timestamped backup filename."""
	_backup_counter += 1
	var ts := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace(" ", "_")
	return "%s_%d.save" % [ts, _backup_counter]

func backup_save() -> String:
	"""Create a timestamped backup of the current save file.
	Returns the backup path on success, empty string on failure."""
	if not FileAccess.file_exists(SAVE_PATH):
		return ""

	var backup_path := "user://%s" % _backup_filename()
	var src := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not src:
		return ""

	var content := src.get_as_text()
	src.close()

	var dst := FileAccess.open(backup_path, FileAccess.WRITE)
	if not dst:
		return ""
	dst.store_string(content)
	dst.close()
	return backup_path

func list_backups() -> Array[String]:
	"""Return sorted (newest-first) list of backup file paths."""
	var backups := [] as Array[String]
	var dir := DirAccess.open("user://")
	if not dir:
		return backups

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with(BACKUP_PREFIX):
			backups.append("user://%s" % file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort newest first (filenames embed timestamps, so reverse alphabetical works)
	backups.sort_custom(func(a: String, b: String) -> bool:
		return a > b
	)
	return backups

func restore_backup() -> String:
	"""Restore from the latest backup.
	Returns the restored backup path on success, empty string on failure."""
	var backups := list_backups()
	if backups.is_empty():
		return ""

	var latest := backups[0]
	var src := FileAccess.open(latest, FileAccess.READ)
	if not src:
		return ""

	var content := src.get_as_text()
	src.close()

	var dst := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not dst:
		return ""
	dst.store_string(content)
	dst.close()
	return latest

# ── Settings persistence ────────────────────────────────────────────────────

func save_settings(data: Dictionary) -> void:
	var payload := JSON.stringify(data)
	if use_local_storage:
		JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [SETTINGS_KEY, JSON.stringify(payload)], true)
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(payload)

func load_settings() -> Dictionary:
	if use_local_storage:
		var raw = JavaScriptBridge.eval("localStorage.getItem('%s')" % SETTINGS_KEY, true)
		if raw == null or String(raw).is_empty() or String(raw) == "null":
			return {}
		var parsed = JSON.parse_string(String(raw))
		if typeof(parsed) == TYPE_STRING:
			return JSON.parse_string(parsed) if JSON.parse_string(parsed) is Dictionary else {}
		return parsed if parsed is Dictionary else {}
	if not FileAccess.file_exists(SETTINGS_PATH):
		return {}
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if not file:
		return {}
	var text := file.get_as_text()
	if text.strip_edges().is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
