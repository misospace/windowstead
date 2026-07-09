extends Node

const SAVE_KEY := "windowstead-save-v2"
const BACKUP_PREFIX := "windowstead-backup-"
const SAVE_PATH := "user://windowstead.save"
const SAVE_VERSION := 2
const SETTINGS_KEY := "windowstead-settings-v1"
const SETTINGS_PATH := "user://windowstead.settings"

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
			# Accept common grid sizes used by the game:
			#   Bottom anchor: 32x5=160, Side anchor: 10x24=240
			#   Plus smaller grids for testing
			var expected_sizes := [25, 36, 64, 100, 150, 160, 240]
			if not expected_sizes.has(tile_count):
				return {"valid": false, "reason": "'tiles' count %d does not match expected grid sizes (%s)" % [tile_count, str(expected_sizes)]}

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

	# Validate 'active_rewards' is an array (if present)
	if data.has("active_rewards"):
		var active_rewards = data.get("active_rewards", [])
		if not active_rewards is Array:
			return {"valid": false, "reason": "'active_rewards' must be an array"}

	return {"valid": true, "reason": ""}

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
