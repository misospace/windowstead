extends Node

const LayoutMath := preload("res://scripts/layout_math.gd")
const RotatingGoal := preload("res://scripts/rotating_goal.gd")
const ColonyStance := preload("res://scripts/colony_stance.gd")
const GoalReward := preload("res://scripts/goal_reward.gd")
const ColonySim := preload("res://scripts/colony_sim.gd")

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

# ── Shared persistence plumbing ───────────────────────────────────────────────
# The web build stores a JSON string inside localStorage (hence the double
# stringify/parse dance); the desktop build writes plain JSON files. These
# four helpers are the only place either quirk lives.

func _local_storage_write(key: String, payload: String) -> void:
	JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [key, JSON.stringify(payload)], true)

func _local_storage_read(key: String) -> Dictionary:
	var raw = JavaScriptBridge.eval("localStorage.getItem('%s')" % key, true)
	if raw == null or String(raw).is_empty() or String(raw) == "null":
		return {}
	var parsed = JSON.parse_string(String(raw))
	if typeof(parsed) == TYPE_STRING:
		parsed = JSON.parse_string(parsed)
	return parsed if parsed is Dictionary else {}

func _write_text_file(path: String, payload: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(payload)
		file.close()

## Returns the parsed JSON from a file, or null when missing/empty/unreadable.
func _read_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var text := file.get_as_text()
	if text.strip_edges().is_empty():
		return null
	return JSON.parse_string(text)

func save_game(data: Dictionary, path: String = "") -> void:
	var target_path := path if not path.is_empty() else SAVE_PATH
	var payload := JSON.stringify(data)
	if use_local_storage:
		_local_storage_write(SAVE_KEY, payload)
		return
	_write_text_file(target_path, payload)

func load_game(path: String = "") -> Dictionary:
	var target_path := path if not path.is_empty() else SAVE_PATH
	if use_local_storage:
		var stored := _local_storage_read(SAVE_KEY)
		if not stored.is_empty():
			rebuild_reservations_from_workers(stored)
		return stored
	var parsed: Variant = _read_json_file(target_path)
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
# missing or stale. Only rebuilds when the field is empty (missing from old
# saves). The implementation lives in ColonySim so it exists exactly once.

func rebuild_reservations_from_workers(state: Dictionary) -> void:
	ColonySim.rebuild_reservations_from_workers(state)

# ── Schema validation ────────────────────────────────────────────────────────
# Returns {valid: bool, reason: String}
# Only validates fields that are present; missing optional fields are allowed.

func _is_numeric(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

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
			if not _is_numeric(resources[resource_name]):
				return {"valid": false, "reason": "'resources.%s' must be numeric" % resource_name}

	# Validate 'harvested' is a dictionary with numeric values (if present)
	if data.has("harvested"):
		var harvested = data.get("harvested", {})
		if not harvested is Dictionary:
			return {"valid": false, "reason": "'harvested' must be a dictionary"}
		for resource_name in harvested:
			if not _is_numeric(harvested[resource_name]):
				return {"valid": false, "reason": "'harvested.%s' must be numeric" % resource_name}

	# Validate declared grid dimensions whenever both are present — even for
	# tile-less saves, so a bad grid_w/grid_h can't slip through (issue #280).
	if data.has("grid_w") and data.has("grid_h"):
		if typeof(data["grid_w"]) != TYPE_INT or typeof(data["grid_h"]) != TYPE_INT:
			return {"valid": false, "reason": "'grid_w' and 'grid_h' must be integers"}
		if int(data["grid_w"]) <= 0 or int(data["grid_h"]) <= 0:
			return {"valid": false, "reason": "'grid_w' and 'grid_h' must be positive"}

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
			# anchor family declared in the save (when both fields are present;
			# dimensions were type/positivity-checked above).
			if data.has("grid_w") and data.has("grid_h"):
				if tile_count != int(data["grid_w"]) * int(data["grid_h"]):
					return {"valid": false, "reason": "'tiles' count %d does not match grid_w*grid_h=%d" % [tile_count, int(data["grid_w"]) * int(data["grid_h"])]}

			# Validate each tile has required shape
			for i in range(tiles.size()):
				var tile = tiles[i]
				if not tile is Dictionary:
					return {"valid": false, "reason": "tile[%d] must be a dictionary" % i}
				for tile_key in ["kind", "amount", "resource", "build_kind"]:
					if not tile.has(tile_key):
						return {"valid": false, "reason": "tile[%d] missing key '%s'" % [i, tile_key]}
				# Validate tile shape: amount must be numeric, resource must be string
				if not _is_numeric(tile.get("amount", -1)):
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
				if not _is_numeric(wcarrying[res_name]):
					return {"valid": false, "reason": "worker[%d].carrying.%s must be numeric" % [k, res_name]}
			# Validate task is a dictionary
			var wtask = worker.get("task", {})
			if not wtask is Dictionary:
				return {"valid": false, "reason": "worker[%d].task must be dictionary" % k}
			# Validate break_ticks is numeric and non-negative (optional — missing defaults to 0 for v1 compat)
			if worker.has("break_ticks"):
				var wbreak = worker.get("break_ticks", 0)
				if not _is_numeric(wbreak):
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
			if not _is_numeric(build.get("id", -1)):
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
	for anchor in LayoutMath.ALL_ANCHOR_FAMILIES:
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
	return [
		GoalReward.REWARD_RESOURCE_TRICKLE,
		GoalReward.REWARD_GATHER_SPEED,
		GoalReward.REWARD_HAUL_SPEED,
		GoalReward.REWARD_BUILD_SPEED,
		GoalReward.REWARD_AMBIENT_IMPROVE,
		GoalReward.REWARD_RECRUIT_DISCOUNT,
	]

# Set of recognized colony stances exported by ColonyStance.
func _known_stances() -> Array:
	return ColonyStance.ALL_STANCES

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
				if not _is_numeric(v):
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
	# BACKUP_PREFIX is what list_backups() filters on — without it backups
	# were written but could never be listed or restored.
	return "%s%s_%d.save" % [BACKUP_PREFIX, ts, _backup_counter]

func _copy_file(src_path: String, dst_path: String) -> bool:
	var src := FileAccess.open(src_path, FileAccess.READ)
	if not src:
		return false
	var content := src.get_as_text()
	src.close()
	var dst := FileAccess.open(dst_path, FileAccess.WRITE)
	if not dst:
		return false
	dst.store_string(content)
	dst.close()
	return true

func backup_save() -> String:
	"""Create a timestamped backup of the current save file.
	Returns the backup path on success, empty string on failure."""
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var backup_path := "user://%s" % _backup_filename()
	return backup_path if _copy_file(SAVE_PATH, backup_path) else ""

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
	return latest if _copy_file(latest, SAVE_PATH) else ""

# ── Settings persistence ────────────────────────────────────────────────────

func save_settings(data: Dictionary) -> void:
	var payload := JSON.stringify(data)
	if use_local_storage:
		_local_storage_write(SETTINGS_KEY, payload)
		return
	_write_text_file(SETTINGS_PATH, payload)

func load_settings() -> Dictionary:
	if use_local_storage:
		return _local_storage_read(SETTINGS_KEY)
	var parsed: Variant = _read_json_file(SETTINGS_PATH)
	return parsed if parsed is Dictionary else {}
