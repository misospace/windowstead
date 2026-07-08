## Regression tests for scripts/render_module.gd.
## Tests that tile_style and tile_accent produce correct results.
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_render_module.gd

extends SceneTree

const RM := preload("res://scripts/render_module.gd")
const C := preload("res://scripts/constants.gd")


func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0
	var test_count := 0

	# --- tile_accent tests ---
	test_count += 1; pass_count += test("tile_accent returns stockpile accent for stockpile pos", _test_accent_stockpile)
	test_count += 1; pass_count += test("tile_accent returns resource color for wood tile", _test_accent_resource_wood)
	test_count += 1; pass_count += test("tile_accent returns resource color for stone tile", _test_accent_resource_stone)
	test_count += 1; pass_count += test("tile_accent returns structure color for hut", _test_accent_structure_hut)
	test_count += 1; pass_count += test("tile_accent returns foundation color for foundation", _test_accent_foundation)
	test_count += 1; pass_count += test("tile_accent returns default color for unknown kind", _test_accent_default)
	test_count += 1; pass_count += test("tile_accent returns green for pending build on hovered tile (can place)", _test_accent_pending_green)
	test_count += 1; pass_count += test("tile_accent returns red for pending build on hovered tile (cannot place)", _test_accent_pending_red)
	test_count += 1; pass_count += test("tile_accent ignores pending build when not on hovered tile", _test_accent_pending_ignored)

	# --- tile_style tests ---
	test_count += 1; pass_count += test("tile_style returns StyleBoxFlat", _test_style_returns_stylebox)
	test_count += 1; pass_count += test("tile_style sets correct corner radius", _test_style_corner_radius)
	test_count += 1; pass_count += test("tile_style sets correct border width", _test_style_border_width)
	test_count += 1; pass_count += test("tile_style uses stockpile backdrop for stockpile pos", _test_style_stockpile_backdrop)
	test_count += 1; pass_count += test("tile_style uses tile kind backdrop for non-stockpile", _test_style_kind_backdrop)
	test_count += 1; pass_count += test("tile_style sets shadow color and size", _test_style_shadow)

	fail_count = test_count - pass_count
	print("\n=== RenderModule Regression Tests ===")
	print("Passed: %d" % pass_count)
	print("Failed: %d" % fail_count)

	if fail_count > 0:
		print("REGRESSION FAILURES DETECTED")
		quit(1)
	else:
		print("All render_module regression tests passed.")
		quit(0)


func test(name: String, fn: Callable) -> int:
	var ok := true
	var error_msg := ""
	var result: Variant = fn.call()
	if result is Dictionary:
		ok = result.get("ok", false)
		error_msg = result.get("msg", "no detail")
	elif result == false:
		ok = false
		error_msg = "returned false"

	if ok:
		print("  ✓ %s" % name)
		return 1
	else:
		print("  ✗ %s: %s" % [name, error_msg])
		return 0


# --- tile_accent tests ---

func _test_accent_stockpile() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, stockpile_pos, stockpile_pos)
	return accent == Color("#d4b36f")


func _test_accent_resource_wood() -> bool:
	var tile := {"kind": "tree", "resource": "wood"}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos)
	return accent == C.RESOURCE_COLORS["wood"]


func _test_accent_resource_stone() -> bool:
	var tile := {"kind": "rock", "resource": "stone"}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos)
	return accent == C.RESOURCE_COLORS["stone"]


func _test_accent_structure_hut() -> bool:
	var tile := {"kind": "hut", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos)
	return accent == C.STRUCTURE_COLORS["hut"]


func _test_accent_foundation() -> bool:
	var tile := {"kind": "foundation", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos)
	return accent == Color("#c7a25e")


func _test_accent_default() -> bool:
	var tile := {"kind": "unknown_kind", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos)
	return accent == Color(1, 1, 1, 0.35)


func _test_accent_pending_green() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(1, 1)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos, "hut", pos, true)
	return accent == Color("#73d38c")


func _test_accent_pending_red() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(1, 1)
	var stockpile_pos := Vector2i(2, 2)
	var accent := RM.tile_accent(tile, pos, stockpile_pos, "hut", pos, false)
	return accent == Color("#d36b6b")


func _test_accent_pending_ignored() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(1, 1)
	var stockpile_pos := Vector2i(2, 2)
	var hovered_pos := Vector2i(3, 3)
	var accent := RM.tile_accent(tile, pos, stockpile_pos, "hut", hovered_pos, true)
	# Should fall through to default since pos != hovered_pos
	return accent == Color(1, 1, 1, 0.35)


# --- tile_style tests ---

func _test_style_returns_stylebox() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var style := RM.tile_style(tile, pos, stockpile_pos)
	return style is StyleBoxFlat


func _test_style_corner_radius() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var style := RM.tile_style(tile, pos, stockpile_pos)
	return style.corner_radius_top_left == 8 and style.corner_radius_bottom_right == 8


func _test_style_border_width() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var style := RM.tile_style(tile, pos, stockpile_pos)
	return style.border_width_left == 2 and style.border_width_bottom == 2


func _test_style_stockpile_backdrop() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var stockpile_pos := Vector2i(2, 2)
	var style := RM.tile_style(tile, stockpile_pos, stockpile_pos)
	return style.bg_color == C.TILE_BACKDROPS["stockpile"]


func _test_style_kind_backdrop() -> bool:
	var tile := {"kind": "tree", "resource": "wood"}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var style := RM.tile_style(tile, pos, stockpile_pos)
	return style.bg_color == C.TILE_BACKDROPS["tree"]


func _test_style_shadow() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var stockpile_pos := Vector2i(2, 2)
	var style := RM.tile_style(tile, pos, stockpile_pos)
	return style.shadow_color == Color(0, 0, 0, 0.25) and style.shadow_size == 2
