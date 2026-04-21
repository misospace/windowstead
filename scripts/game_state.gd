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
	return migrate_save(parsed)

func migrate_save(data: Dictionary) -> Dictionary:
	var save_version: int = int(data.get("save_version", 0))
	if save_version == SAVE_VERSION:
		return data
	if save_version < 1:
		return data
	if save_version == 1:
		data = migrate_v1_to_v2(data)
		data["save_version"] = SAVE_VERSION
		persist_migrated_save(data)
		return data
	# Unknown or future version – return raw data, caller decides what to do
	return data

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
