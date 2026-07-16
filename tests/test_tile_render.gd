## Regression tests for scripts/tile_render.gd.
## Tests pure rendering functions without scene tree instantiation.
##
## Run: godot --headless --quit
## Or:  godot --headless --main-pack windowstead.pck --script tests/test_tile_render.gd

extends "res://tests/test_case.gd"

const TileRender := preload("res://scripts/tile_render.gd")
const C := preload("res://scripts/constants.gd")


func run_tests() -> void:
	# --- tile_style tests ---
	check("tile_style returns StyleBoxFlat", _test_tile_style_returns_stylebox)
	check("tile_style sets border color to accent", _test_tile_style_border_color)
	check("tile_style uses TILE_BACKDROPS for bg", _test_tile_style_bg_from_backdrops)
	check("tile_style stockpile override", _test_tile_style_stockpile_override)
	check("tile_style unknown kind default backdrop", _test_tile_style_unknown_kind)
	check("tile_style corner radius is 8", _test_tile_style_corner_radius)
	check("tile_style shadow color and size", _test_tile_style_shadow)

	# --- tile_accent tests ---
	check("tile_accent build placement valid (green)", _test_accent_build_valid)
	check("tile_accent build placement invalid (red)", _test_accent_build_invalid)
	check("tile_accent no build placement default", _test_accent_no_build)
	check("tile_accent stockpile gold", _test_accent_stockpile)
	check("tile_accent resource color", _test_accent_resource_color)
	check("tile_accent structure color", _test_accent_structure_color)
	check("tile_accent foundation accent", _test_accent_foundation)
	check("tile_accent hover mismatch no highlight", _test_accent_hover_mismatch)
	check("tile_accent empty context default", _test_accent_empty_context)

	# --- Integration with constants ---
	check("tile_accent uses real RESOURCE_COLORS", _test_accent_real_resource_colors)
	check("tile_accent uses real STRUCTURE_COLORS", _test_accent_real_structure_colors)

	# --- main.gd → TileRender wiring ---
	_test_main_theme_wiring()


## Runs a check callable and reports it through the shared assertion API.
## The callable may return a bool or a {ok, msg} Dictionary.
func check(name: String, fn: Callable) -> void:
	var ok := true
	var error_msg := ""
	var result: Variant = fn.call()
	if result is Dictionary:
		ok = result.get("ok", false)
		error_msg = result.get("msg", "no detail")
	elif result == false:
		ok = false
		error_msg = "returned false"

	assert_true(ok, name, error_msg)


# --- tile_style tests ---

func _test_tile_style_returns_stylebox() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var theme := {"TILE_BACKDROPS": {"ground": Color("#1b2128")}}
	var accent := Color(1, 1, 1, 0.35)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return style is StyleBoxFlat


func _test_tile_style_border_color() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var theme := {"TILE_BACKDROPS": {}}
	var accent := Color(0.5, 0.3, 0.1, 1.0)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return style.border_color == accent


func _test_tile_style_bg_from_backdrops() -> bool:
	var tile := {"kind": "tree", "resource": ""}
	var pos := Vector2i(0, 0)
	var theme := {"TILE_BACKDROPS": {"tree": Color("#2d4a2d")}}
	var accent := Color(1, 1, 1, 0.35)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return style.bg_color == Color("#2d4a2d")


func _test_tile_style_stockpile_override() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(5, 3)
	var theme := {
		"TILE_BACKDROPS": {"ground": Color("#1b2128"), "stockpile": Color("#d4b36f")},
		"stockpile_pos": Vector2i(5, 3),
	}
	var accent := Color(1, 1, 1, 0.35)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return style.bg_color == Color("#d4b36f")


func _test_tile_style_unknown_kind() -> bool:
	var tile := {"kind": "unknown", "resource": ""}
	var pos := Vector2i(0, 0)
	var theme := {"TILE_BACKDROPS": {}}
	var accent := Color(1, 1, 1, 0.35)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return style.bg_color == Color("#1b2128")


func _test_tile_style_corner_radius() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var theme := {"TILE_BACKDROPS": {}}
	var accent := Color(1, 1, 1, 0.35)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return (style.corner_radius_top_left == 8 and
			style.corner_radius_top_right == 8 and
			style.corner_radius_bottom_right == 8 and
			style.corner_radius_bottom_left == 8)


func _test_tile_style_shadow() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var theme := {"TILE_BACKDROPS": {}}
	var accent := Color(1, 1, 1, 0.35)
	var style := TileRender.tile_style(tile, pos, theme, accent)
	return style.shadow_color == Color(0, 0, 0, 0.25) and style.shadow_size == 2


# --- tile_accent tests ---

func _test_accent_build_valid() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(2, 2)
	var can_place_fn := func(_p: Vector2i, _k: String): return true
	var context := {
		"pending_build_kind": "house",
		"hover_pos": Vector2i(2, 2),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": can_place_fn,
	}
	var theme := {"RESOURCE_COLORS": {}, "STRUCTURE_COLORS": {}}
	return TileRender.tile_accent(tile, pos, context, theme) == Color("#73d38c")


func _test_accent_build_invalid() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(2, 2)
	var can_place_fn := func(_p: Vector2i, _k: String): return false
	var context := {
		"pending_build_kind": "house",
		"hover_pos": Vector2i(2, 2),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": can_place_fn,
	}
	var theme := {"RESOURCE_COLORS": {}, "STRUCTURE_COLORS": {}}
	return TileRender.tile_accent(tile, pos, context, theme) == Color("#d36b6b")


func _test_accent_no_build() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(2, 2)
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(2, 2),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {"RESOURCE_COLORS": {}, "STRUCTURE_COLORS": {}}
	return TileRender.tile_accent(tile, pos, context, theme) == Color(1, 1, 1, 0.35)


func _test_accent_stockpile() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(5, 3)
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(-1, -1),
		"stockpile_pos": Vector2i(5, 3),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {"RESOURCE_COLORS": {}, "STRUCTURE_COLORS": {}}
	return TileRender.tile_accent(tile, pos, context, theme) == Color("#d4b36f")


func _test_accent_resource_color() -> bool:
	var tile := {"kind": "ground", "resource": "wood"}
	var pos := Vector2i(0, 0)
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(-1, -1),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {
		"RESOURCE_COLORS": {"wood": Color("#8b5e3c")},
		"STRUCTURE_COLORS": {},
	}
	return TileRender.tile_accent(tile, pos, context, theme) == Color("#8b5e3c")


func _test_accent_structure_color() -> bool:
	var tile := {"kind": "house", "resource": ""}
	var pos := Vector2i(0, 0)
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(-1, -1),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {
		"RESOURCE_COLORS": {},
		"STRUCTURE_COLORS": {"house": Color("#6b8cce")},
	}
	return TileRender.tile_accent(tile, pos, context, theme) == Color("#6b8cce")


func _test_accent_foundation() -> bool:
	var tile := {"kind": "foundation", "resource": ""}
	var pos := Vector2i(0, 0)
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(-1, -1),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {"RESOURCE_COLORS": {}, "STRUCTURE_COLORS": {}}
	return TileRender.tile_accent(tile, pos, context, theme) == Color("#c7a25e")


func _test_accent_hover_mismatch() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(3, 3)
	var context := {
		"pending_build_kind": "house",
		"hover_pos": Vector2i(2, 2),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {"RESOURCE_COLORS": {}, "STRUCTURE_COLORS": {}}
	return TileRender.tile_accent(tile, pos, context, theme) == Color(1, 1, 1, 0.35)


func _test_accent_empty_context() -> bool:
	var tile := {"kind": "ground", "resource": ""}
	var pos := Vector2i(0, 0)
	var context := {}
	var theme := {}
	return TileRender.tile_accent(tile, pos, context, theme) == Color(1, 1, 1, 0.35)


# --- Integration with real constants ---

func _test_accent_real_resource_colors() -> bool:
	# Verify tile_accent uses RESOURCE_COLORS from constants.gd
	var wood_tile := {"kind": "ground", "resource": "wood"}
	var stone_tile := {"kind": "ground", "resource": "stone"}
	var food_tile := {"kind": "ground", "resource": "food"}
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(-1, -1),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {
		"RESOURCE_COLORS": C.RESOURCE_COLORS,
		"STRUCTURE_COLORS": {},
	}

	var wood_color := TileRender.tile_accent(wood_tile, Vector2i(0, 0), context, theme)
	var stone_color := TileRender.tile_accent(stone_tile, Vector2i(0, 0), context, theme)
	var food_color := TileRender.tile_accent(food_tile, Vector2i(0, 0), context, theme)

	return (wood_color == C.RESOURCE_COLORS["wood"] and
			stone_color == C.RESOURCE_COLORS["stone"] and
			food_color == C.RESOURCE_COLORS["food"])


func _test_accent_real_structure_colors() -> bool:
	# Verify tile_accent uses STRUCTURE_COLORS from constants.gd
	var hut_tile := {"kind": "hut", "resource": ""}
	var workshop_tile := {"kind": "workshop", "resource": ""}
	var garden_tile := {"kind": "garden", "resource": ""}
	var context := {
		"pending_build_kind": "",
		"hover_pos": Vector2i(-1, -1),
		"stockpile_pos": Vector2i(-1, -1),
		"can_place_fn": func(_p: Vector2i, _k: String): return true,
	}
	var theme := {
		"RESOURCE_COLORS": {},
		"STRUCTURE_COLORS": C.STRUCTURE_COLORS,
	}

	var hut_color := TileRender.tile_accent(hut_tile, Vector2i(0, 0), context, theme)
	var workshop_color := TileRender.tile_accent(workshop_tile, Vector2i(0, 0), context, theme)
	var garden_color := TileRender.tile_accent(garden_tile, Vector2i(0, 0), context, theme)

	return (hut_color == C.STRUCTURE_COLORS["hut"] and
			workshop_color == C.STRUCTURE_COLORS["workshop"] and
			garden_color == C.STRUCTURE_COLORS["garden"])


# ── main.gd theme wiring ───────────────────────────────────────────────────────
# Guards the seam between main.gd's cached theme dictionaries and TileRender:
# a bad dictionary KEY silently falls back to default colors (this regressed
# once — the constants-alias sweep rewrote "TILE_BACKDROPS" inside a string).
func _test_main_theme_wiring() -> void:
	var main_script = load("res://scripts/main.gd")
	var main = main_script.new()
	main.grid_w = 5
	main.grid_h = 5
	main.stockpile_pos = Vector2i(0, 0)
	var tiles: Array = []
	for i in 25:
		tiles.append({"kind": "ground", "amount": 0, "resource": "", "build_kind": ""})
	main.state = {"tiles": tiles, "workers": [], "builds": [], "resources": {}, "events": []}

	var tree_tile := {"kind": "tree", "amount": 3, "resource": "wood", "build_kind": ""}
	var accent: Color = main.tile_accent(tree_tile, Vector2i(3, 3))
	assert_eq(accent, C.RESOURCE_COLORS["wood"], "main wiring: resource accent comes from constants")

	var style: StyleBoxFlat = main.tile_style(tree_tile, Vector2i(3, 3))
	assert_eq(style.bg_color, C.TILE_BACKDROPS["tree"], "main wiring: backdrop comes from constants")
	assert_eq(style.border_color, C.RESOURCE_COLORS["wood"], "main wiring: border uses the accent")

	var cached: StyleBoxFlat = main.tile_style(tree_tile, Vector2i(2, 3))
	assert_true(cached == style, "main wiring: identical looks share one cached stylebox")
	main.free()
