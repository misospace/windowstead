extends Node

const SAVE_KEY := "windowstead-save-v2"
const SAVE_PATH := "user://windowstead.save"
const SAVE_VERSION := 2
const SETTINGS_KEY := "windowstead-settings-v1"
const SETTINGS_PATH := "user://windowstead.settings"

var save_supported := false
var use_local_storage := false

func _ready() -> void:
	save_supported = true
	use_local_storage = OS.has_feature("web") and JavaScriptBridge.eval("typeof localStorage !== 'undefined'", true)

func save_game(data: Dictionary) -> void:
	var payload := JSON.stringify(data)
	if use_local_storage:
		JavaScriptBridge.eval("localStorage.setItem('%s', %s)" % [SAVE_KEY, JSON.stringify(payload)], true)
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(payload)

func load_game() -> Dictionary:
	if use_local_storage:
		var raw = JavaScriptBridge.eval("localStorage.getItem('%s')" % SAVE_KEY, true)
		if raw == null or String(raw).is_empty() or String(raw) == "null":
			return {}
		var parsed = JSON.parse_string(String(raw))
		if typeof(parsed) == TYPE_STRING:
			return JSON.parse_string(parsed) if JSON.parse_string(parsed) is Dictionary else {}
		return parsed if parsed is Dictionary else {}
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
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

	return migrate_save(parsed)

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
			# Accept common grid sizes: 5x5=25, 6x6=36, 8x8=64, 10x10=100
			var expected_sizes := [25, 36, 64, 100]
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

	# Validate 'workers' is an array (if present)
	if data.has("workers"):
		var workers = data.get("workers", [])
		if not workers is Array:
			return {"valid": false, "reason": "'workers' must be an array"}

	# Validate 'builds' is an array (if present)
	if data.has("builds"):
		var builds = data.get("builds", [])
		if not builds is Array:
			return {"valid": false, "reason": "'builds' must be an array"}

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
