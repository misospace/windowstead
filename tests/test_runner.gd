extends SceneTree

func _initialize() -> void:
	var game_state_script := load("res://scripts/game_state.gd")
	var game_state = game_state_script.new()
	root.add_child(game_state)
	await process_frame

	var payload := {
		"tick": 42,
		"resources": {"wood": 7, "stone": 3},
		"events": [{"tick": 42, "text": "test event"}],
	}

	game_state.use_local_storage = false
	game_state.save_game(payload)
	var loaded = game_state.load_game()
	assert(int(loaded.get("tick", -1)) == 42)
	assert(int(loaded.get("resources", {}).get("wood", -1)) == 7)
	assert(int(loaded.get("resources", {}).get("stone", -1)) == 3)
	assert(loaded.get("events", []).size() == 1)
	game_state.clear_game()
	assert(game_state.load_game().is_empty())

	print("test_runner: ok")
	quit()
