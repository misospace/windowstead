extends "res://scripts/main.gd"

# Records the quit request instead of quitting, so Flow 7 of
# test_save_failure_surfaced.gd can execute the startup Exit button chain
# (exit_game(): persist → quit) end to end. exit_game() ends in
# _quit_application() (main.gd); calling the real SceneTree.quit() would end
# the test runner before its assertions print. Everything above the seam —
# the persist(true) flush and the has_persistable_colony() skip — is the
# unmodified production chain.
#
# This lives in its own file and must be load()-ed at runtime, never
# referenced statically: a compile-time dependency on main.gd would compile
# main.gd before the GameState autoload exists, which fails in --script mode.

var quit_requested := false

func _quit_application() -> void:
	quit_requested = true
