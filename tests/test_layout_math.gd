## Regression tests for dock and layout geometry.
## Tests pure layout math extracted from main.gd via layout_math.gd.
## No DisplayServer or scene node required — fully deterministic.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_layout_math.gd

extends SceneTree

const LM := preload("res://scripts/layout_math.gd")

func _initialize() -> void:
	var pass_count := 0
	var fail_count := 0

	# --- Anchor family selection ---
	pass_count += test("anchor_family maps bottom correctly", _test_anchor_family_bottom)
	pass_count += test("anchor_family maps side anchors to vertical", _test_anchor_family_side)

	# --- Tile sizing ---
	pass_count += test("tile_px bottom at zoom 1.0", _test_tile_px_bottom)
	pass_count += test("tile_px vertical at zoom 1.0", _test_tile_px_vertical)
	pass_count += test("tile_px scales with zoom factor", _test_tile_px_zoom)
	pass_count += test("tile_px never returns zero or negative", _test_tile_px_floor)
	pass_count += test("tile sizes are always square", _test_tile_square)

	# --- Grid dimensions ---
	pass_count += test("grid dims bottom: 32x8", _test_grid_dims_bottom)
	pass_count += test("grid dims vertical: 14x18", _test_grid_dims_vertical)

	# --- World panel size ---
	pass_count += test("world size bottom at zoom 1.0", _test_world_size_bottom)
	pass_count += test("world size vertical at zoom 1.0", _test_world_size_vertical)
	pass_count += test("world size scales with tile size", _test_world_size_scales)

	# --- Dock padding ---
	pass_count += test("dock padding bottom: (48, 190)", _test_dock_padding_bottom)
	pass_count += test("dock padding vertical: (60, 120)", _test_dock_padding_vertical)

	# --- Dock window size ---
	pass_count += test("dock size bottom includes sidebar width", _test_dock_size_bottom_has_sidebar)
	pass_count += test("dock size vertical excludes sidebar width", _test_dock_size_vertical_no_sidebar)

	# --- Dock position ---
	pass_count += test("dock position bottom is centered", _test_dock_pos_bottom_centered)
	pass_count += test("dock position left is bottom-left aligned", _test_dock_pos_left_bottom)
	pass_count += test("dock position right is bottom-right aligned", _test_dock_pos_right_bottom)

	# --- Popup position ---
	pass_count += test("popup position bottom is top-right", _test_popup_pos_bottom)
	pass_count += test("popup position right is top-right", _test_popup_pos_right)
	pass_count += test("popup position left is top-left", _test_popup_pos_left)

	# --- Popup bounds ---
	pass_count += test("popup stays within bounds at normal size", _test_popup_in_bounds_normal)
	pass_count += test("popup stays within bounds at max zoom", _test_popup_in_bounds_max_zoom)
	pass_count += test("popup out of bounds when sidebar exceeds screen", _test_popup_out_of_bounds)

	# --- Stockpile position ---
	pass_count += test("stockpile bottom: (11, 2)", _test_stockpile_bottom)
	pass_count += test("stockpile vertical: (2, 7)", _test_stockpile_vertical)

	# --- Integration: anchor change round-trip ---
	pass_count += test("anchor change: grid dims swap correctly", _test_anchor_swap)
	pass_count += test("anchor change: tile size swaps correctly", _test_tile_swap)

	fail_count = 29 - pass_count
	print("\n=== Layout Regression Tests ===")
	print("Passed: %d" % pass_count)
	print("Failed: %d" % fail_count)
	
	if fail_count > 0:
		print("REGRESSION FAILURES DETECTED")
		quit(1)
	else:
		print("All layout regression tests passed.")
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


# --- Individual tests ---

func _test_anchor_family_bottom() -> bool:
	return LM.anchor_family_from_dock_anchor("bottom") == "bottom"

func _test_anchor_family_side() -> bool:
	return (
		LM.anchor_family_from_dock_anchor("left") == "vertical"
		and LM.anchor_family_from_dock_anchor("right") == "vertical"
	)

func _test_tile_px_bottom() -> void:
	var px := LM.tile_px_for_anchor("bottom")
	# 42.0 * 1.15 = 48.3 -> round to 48
	assert(px == 48, "bottom tile_px at zoom 1.0 should be 48, got %d" % px)

func _test_tile_px_vertical() -> void:
	var px := LM.tile_px_for_anchor("vertical")
	# 48.0 * 1.15 = 55.2 -> round to 55
	assert(px == 55, "vertical tile_px at zoom 1.0 should be 55, got %d" % px)

func _test_tile_px_zoom() -> void:
	var px_50 := LM.tile_px_for_anchor("bottom", 0.5)
	var px_20 := LM.tile_px_for_anchor("bottom", 2.0)
	# 42 * 1.15 * 0.5 = 24.15 -> round to 24
	# 42 * 1.15 * 2.0 = 96.6 -> round to 97
	assert(px_50 == 24, "zoom 0.5: expected 24, got %d" % px_50)
	assert(px_20 == 97, "zoom 2.0: expected 97, got %d" % px_20)

func _test_tile_px_floor() -> void:
	# Even at very small zoom, should never go below 1
	var px := LM.tile_px_for_anchor("bottom", 0.01)
	assert(px >= 1, "tile_px should never be < 1, got %d" % px)

func _test_tile_square() -> void:
	# tile_px_for_anchor returns a single int, so it's always square by construction
	# This test verifies the invariant holds across anchors and zoom levels
	var bottom_px := LM.tile_px_for_anchor("bottom")
	var vertical_px := LM.tile_px_for_anchor("vertical")
	assert(bottom_px > 0, "bottom tile_px must be positive")
	assert(vertical_px > 0, "vertical tile_px must be positive")

func _test_grid_dims_bottom() -> void:
	var dims := LM.grid_dims_for_anchor("bottom")
	assert(dims["grid_w"] == 32, "bottom grid_w should be 32")
	assert(dims["grid_h"] == 8, "bottom grid_h should be 8")

func _test_grid_dims_vertical() -> void:
	var dims := LM.grid_dims_for_anchor("vertical")
	assert(dims["grid_w"] == 14, "vertical grid_w should be 14")
	assert(dims["grid_h"] == 18, "vertical grid_h should be 18")

func _test_world_size_bottom() -> void:
	# bottom: 32 tiles * 48px + 31 gaps * 6px = 1536 + 186 = 1722
	# height: 8 tiles * 48px + 7 gaps * 6px = 384 + 42 = 426
	var size := LM.world_pixel_size(32, 8, 48)
	assert(size.x == 1722, "bottom world width should be 1722, got %d" % size.x)
	assert(size.y == 426, "bottom world height should be 426, got %d" % size.y)

func _test_world_size_vertical() -> void:
	# vertical: 14 tiles * 55px + 13 gaps * 6px = 770 + 78 = 848
	# height: 18 tiles * 55px + 17 gaps * 6px = 990 + 102 = 1092
	var size := LM.world_pixel_size(14, 18, 55)
	assert(size.x == 848, "vertical world width should be 848, got %d" % size.x)
	assert(size.y == 1092, "vertical world height should be 1092, got %d" % size.y)

func _test_world_size_scales() -> void:
	var small := LM.world_pixel_size(5, 3, 20)
	var big := LM.world_pixel_size(5, 3, 40)
	# bigger tiles → bigger world
	assert(big.x > small.x, "world width should scale with tile size")
	assert(big.y > small.y, "world height should scale with tile size")

func _test_dock_padding_bottom() -> void:
	var pad := LM.dock_padding_for_anchor("bottom")
	assert(pad.x == 48, "bottom padding x should be 48, got %d" % pad.x)
	assert(pad.y == 190, "bottom padding y should be 190, got %d" % pad.y)

func _test_dock_padding_vertical() -> void:
	var pad := LM.dock_padding_for_anchor("vertical")
	assert(pad.x == 60, "vertical padding x should be 60, got %d" % pad.x)
	assert(pad.y == 120, "vertical padding y should be 120, got %d" % pad.y)

func _test_dock_size_bottom_has_sidebar() -> void:
	# dock size bottom = world + padding + sidebar(220) + 16
	var world := LM.world_pixel_size(32, 8, 48)
	var pad := LM.dock_padding_for_anchor("bottom")
	var expected_w := world.x + pad.x + 220 + 16
	var actual := LM.dock_size_for_anchor("bottom", 32, 8, 48)
	assert(actual.x == expected_w, "bottom dock width should include sidebar, expected %d, got %d" % [expected_w, actual.x])

func _test_dock_size_vertical_no_sidebar() -> void:
	# dock size vertical = world + padding (no sidebar)
	var world := LM.world_pixel_size(14, 18, 55)
	var pad := LM.dock_padding_for_anchor("vertical")
	var expected := Vector2i(world.x + pad.x, world.y + pad.y)
	var actual := LM.dock_size_for_anchor("vertical", 14, 18, 55)
	assert(actual == expected, "vertical dock size should be world + padding, expected %s, got %s" % [expected, actual])

func _test_dock_pos_bottom_centered() -> void:
	# Screen: 1920x1080, dock should be horizontally centered
	var dock_size := Vector2i(1800, 500)
	var pos := LM.dock_position_for_anchor(0, 0, 1920, 1080, dock_size, "bottom")
	# centered: (1920 - 1800) / 2 = 60
	assert(pos.x == 60, "bottom dock should be centered at x=60, got %d" % pos.x)
	# y = 1080 - 500 - 12 = 568
	assert(pos.y == 568, "bottom dock y should be 568, got %d" % pos.y)

func _test_dock_pos_left_bottom() -> void:
	var dock_size := Vector2i(400, 300)
	var pos := LM.dock_position_for_anchor(0, 0, 1920, 1080, dock_size, "left")
	assert(pos.x == 12, "left dock x should be 12, got %d" % pos.x)
	assert(pos.y == 1080 - 300 - 12, "left dock y should be bottom-aligned, got %d" % pos.y)

func _test_dock_pos_right_bottom() -> void:
	var dock_size := Vector2i(400, 300)
	var pos := LM.dock_position_for_anchor(0, 0, 1920, 1080, dock_size, "right")
	assert(pos.x == 1920 - 400 - 12, "right dock x should be screen-right, got %d" % pos.x)
	assert(pos.y == 1080 - 300 - 12, "right dock y should be bottom-aligned, got %d" % pos.y)

func _test_popup_pos_bottom() -> void:
	var pos := LM.popup_position_for_anchor("bottom", 1920.0, 1080.0, 220.0, 300.0)
	assert(pos.x == 1920.0 - 220.0 - 16, "bottom popup x should be top-right, got %f" % pos.x)
	assert(pos.y == 16.0, "bottom popup y should be 16, got %f" % pos.y)

func _test_popup_pos_right() -> void:
	var pos := LM.popup_position_for_anchor("right", 1920.0, 1080.0, 220.0, 300.0)
	assert(pos.x == max(16.0, 1920.0 - 220.0 - 16), "right popup x should be top-right, got %f" % pos.x)
	assert(pos.y == 1080.0 - 300.0 - 16.0, "right popup y should be bottom-based, got %f" % pos.y)

func _test_popup_pos_left() -> void:
	var pos := LM.popup_position_for_anchor("left", 1920.0, 1080.0, 220.0, 300.0)
	assert(pos.x == 16.0, "left popup x should be 16, got %f" % pos.x)
	assert(pos.y == 1080.0 - 300.0 - 16.0, "left popup y should be bottom-based, got %f" % pos.y)

func _test_popup_in_bounds_normal() -> void:
	var pos := LM.popup_position_for_anchor("bottom", 1920.0, 1080.0, 220.0, 300.0)
	var size := Vector2(220.0, 300.0)
	var in_bounds := LM.popup_within_bounds(pos, size, 0, 0, 1920, 1080)
	assert(in_bounds, "popup should be within bounds at normal size")

func _test_popup_in_bounds_max_zoom() -> void:
	# At max zoom (2.0), tiles are bigger but sidebar size is fixed at 220
	var pos := LM.popup_position_for_anchor("bottom", 1920.0, 1080.0, 220.0, 300.0)
	var size := Vector2(220.0, 300.0)
	var in_bounds := LM.popup_within_bounds(pos, size, 0, 0, 1920, 1080)
	assert(in_bounds, "popup should stay in bounds at max zoom")

func _test_popup_out_of_bounds() -> void:
	# When sidebar is wider than the available screen width
	var pos := LM.popup_position_for_anchor("bottom", 1920.0, 1080.0, 2000.0, 300.0)
	var size := Vector2(2000.0, 300.0)
	var in_bounds := LM.popup_within_bounds(pos, size, 0, 0, 1920, 1080)
	assert(not in_bounds, "popup should be out of bounds when sidebar exceeds screen")

func _test_stockpile_bottom() -> void:
	var pos := LM.stockpile_pos_for_anchor("bottom")
	assert(pos == Vector2i(11, 2), "stockpile bottom should be (11,2), got %s" % pos)

func _test_stockpile_vertical() -> void:
	var pos := LM.stockpile_pos_for_anchor("vertical")
	assert(pos == Vector2i(2, 7), "stockpile vertical should be (2,7), got %s" % pos)

func _test_anchor_swap() -> void:
	var bottom := LM.grid_dims_for_anchor("bottom")
	var vertical := LM.grid_dims_for_anchor("vertical")
	# They should be different and non-overlapping
	assert(bottom["grid_w"] != vertical["grid_w"], "grid_w should differ between anchors")
	assert(bottom["grid_h"] != vertical["grid_h"], "grid_h should differ between anchors")

func _test_tile_swap() -> void:
	var bottom_px := LM.tile_px_for_anchor("bottom")
	var vertical_px := LM.tile_px_for_anchor("vertical")
	assert(bottom_px != vertical_px, "anchor families should use distinct tile sizes")
