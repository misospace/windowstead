## Tests for WorkerRenderer (issue #232).
## Verifies that worker_texture() extracted module produces correct
## cached textures for various worker name/frame/carrying combinations.

extends SceneTree

const WorkerRenderer := preload("res://scripts/worker_renderer.gd")

var test_pass := 0
var test_fail := 0

func _initialize() -> void:
	test_returns_texture_for_known_name()
	test_returns_same_instance_for_repeat_call()
	test_different_frames_produce_different_textures()
	test_carrying_changes_texture()
	test_unknown_name_falls_back_white_accent()
	test_clear_cache_invalidates_cache()

	print("")
	print("=== test_worker_renderer summary: %d passed, %d failed ===" % [test_pass, test_fail])
	if test_fail > 0:
		print("FAILURES DETECTED")
		quit(1)
	else:
		print("test_worker_renderer: ok")
		quit(0)


func _assert(condition: Variant, name: String, detail: String = "") -> void:
	if not condition:
		test_fail += 1
		if not detail.is_empty():
			print("TEST %s: FAIL — %s" % [name, detail])
		else:
			print("TEST %s: FAIL" % name)
	else:
		test_pass += 1
		print("TEST %s: PASS" % name)


func _assert_eq(actual: Variant, expected: Variant, name: String) -> void:
	_assert(actual == expected, name, "expected %s, got %s" % [str(expected), str(actual)])


func test_returns_texture_for_known_name() -> void:
	print("")
	print("--- worker_renderer: known name ---")
	WorkerRenderer.clear_cache()
	var tex := WorkerRenderer.worker_texture("Jun", 0, "")
	_assert(tex != null, "known_name: returns texture")
	_assert(tex is Texture2D, "known_name: result is Texture2D")
	_assert_eq(tex.get_width(), 12, "known_name: width 12")
	_assert_eq(tex.get_height(), 14, "known_name: height 14")


func test_returns_same_instance_for_repeat_call() -> void:
	print("")
	print("--- worker_renderer: cache identity ---")
	WorkerRenderer.clear_cache()
	var tex_a := WorkerRenderer.worker_texture("Mara", 0, "")
	var tex_b := WorkerRenderer.worker_texture("Mara", 0, "")
	_assert(tex_a == tex_b, "cache_identity: same args → same Texture2D instance")


func test_different_frames_produce_different_textures() -> void:
	print("")
	print("--- worker_renderer: frame variation ---")
	WorkerRenderer.clear_cache()
	var tex_even := WorkerRenderer.worker_texture("Jun", 0, "")
	var tex_odd := WorkerRenderer.worker_texture("Jun", 1, "")
	_assert(tex_even != tex_odd, "frame_variation: frame 0 vs 1 are different instances")


func test_carrying_changes_texture() -> void:
	print("")
	print("--- worker_renderer: carrying variation ---")
	WorkerRenderer.clear_cache()
	var tex_empty := WorkerRenderer.worker_texture("Jun", 0, "")
	var tex_wood := WorkerRenderer.worker_texture("Jun", 0, "wood")
	var tex_food := WorkerRenderer.worker_texture("Jun", 0, "food")
	_assert(tex_empty != tex_wood, "carrying_variation: empty vs wood differ")
	_assert(tex_wood != tex_food, "carrying_variation: wood vs food differ")


func test_unknown_name_falls_back_white_accent() -> void:
	print("")
	print("--- worker_renderer: unknown name fallback ---")
	WorkerRenderer.clear_cache()
	# Should not crash, returns a valid texture for unknown worker names.
	var tex := WorkerRenderer.worker_texture("Nonexistent", 0, "")
	_assert(tex != null, "unknown_name: returns texture (no crash)")
	_assert(tex is Texture2D, "unknown_name: result is Texture2D")


func test_clear_cache_invalidates_cache() -> void:
	print("")
	print("--- worker_renderer: clear cache ---")
	var tex_a := WorkerRenderer.worker_texture("Jun", 0, "")
	WorkerRenderer.clear_cache()
	var tex_b := WorkerRenderer.worker_texture("Jun", 0, "")
	_assert(tex_a != tex_b, "clear_cache: new instance after clear")