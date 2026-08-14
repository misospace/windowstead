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
	_test_render_tile_label_sig_skip()


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


# ── render_tile label-sig cache (#333) ─────────────────────────────────────────
# render_world re-runs render_tile for every tile on every tick, but the
# per-label text writes are dirty even when the string is identical. The fix
# caches a per-tile render signature and skips the three label writes (plus the
# amount visibility flag) when nothing affecting them has changed. The test
# exercises the skip path directly: same tile state on the second pass must
# leave the label texts untouched.
func _test_render_tile_label_sig_skip() -> void:
	var main_script = load("res://scripts/main.gd")
	var main = main_script.new()
	main.grid_w = 1
	main.grid_h = 1
	# Keep the stockpile off (0, 0) — tile_amount_text returns "hub" for the
	# stockpile tile regardless of amount, which would mask the cache miss
	# we want to assert.
	main.stockpile_pos = Vector2i(-1, -1)
	main.hover_tile_index = -1
	var tiles: Array = []
	tiles.append({"kind": "tree", "amount": 3, "resource": "wood", "build_kind": ""})
	main.state = {"tiles": tiles, "workers": [], "builds": [], "resources": {}, "events": []}

	# Build a single tile_view by hand so the test stays independent of the
	# theme/sprite wiring that build_tile_views() depends on.
	var panel := Panel.new()
	var icon_label := Label.new()
	var amount_label := Label.new()
	var progress_label := Label.new()
	panel.add_child(icon_label)
	panel.add_child(amount_label)
	panel.add_child(progress_label)
	main.tile_views = ([{
		"panel": panel,
		"icon": icon_label,
		"amount": amount_label,
		"progress": progress_label,
	}] as Array[Dictionary])

	# First pass: populate the labels and the cached signature.
	main.render_tile(0)
	var first_sig = main.tile_views[0].get("label_sig")
	assert_true(first_sig != null, "label_sig cached after first render")
	assert_eq(icon_label.text, main.tile_icon(main.get_tile(Vector2i(0, 0)), Vector2i(0, 0)),
		"first render writes the icon")
	assert_eq(amount_label.text, "3", "first render writes the amount")

	# Sentinel: overwrite the labels with a known string. If the skip path
	# is taken on the next pass these sentinels must survive.
	icon_label.text = "SENTINEL_ICON"
	amount_label.text = "SENTINEL_AMOUNT"
	progress_label.text = "SENTINEL_PROGRESS"

	# Second pass with no state change: skip path must leave the labels
	# untouched and the cached signature must be preserved.
	main.render_tile(0)
	var second_sig = main.tile_views[0].get("label_sig")
	assert_eq(second_sig, first_sig, "unchanged tile: label_sig stays stable across passes")
	assert_eq(icon_label.text, "SENTINEL_ICON", "unchanged tile: icon label is NOT re-written")
	assert_eq(amount_label.text, "SENTINEL_AMOUNT", "unchanged tile: amount label is NOT re-written")
	assert_eq(progress_label.text, "SENTINEL_PROGRESS", "unchanged tile: progress label is NOT re-written")
	assert_eq(amount_label.visible, false, "unchanged tile: amount visibility preserved")

	# Mutate tile amount — same kind, same resource, different amount string.
	# The amount text changes, so the cache must miss and the writes must run.
	tiles[0]["amount"] = 4
	main.state = {"tiles": tiles, "workers": [], "builds": [], "resources": {}, "events": []}
	main.render_tile(0)
	var third_sig = main.tile_views[0].get("label_sig")
	assert_true(third_sig != first_sig, "amount change: label_sig updates")
	assert_eq(icon_label.text, main.tile_icon(main.get_tile(Vector2i(0, 0)), Vector2i(0, 0)),
		"amount change: icon label re-written with real content (no longer sentinel)")
	assert_eq(amount_label.text, "4", "amount change: amount label re-written with the new amount")

	# Mutate amount back to 3 — same signature as the first pass. This
	# confirms the cache uses value-based identity, not "did we change since
	# last render".
	tiles[0]["amount"] = 3
	main.state = {"tiles": tiles, "workers": [], "builds": [], "resources": {}, "events": []}
	main.render_tile(0)
	var fourth_sig = main.tile_views[0].get("label_sig")
	assert_eq(fourth_sig, first_sig, "matching state: label_sig returns to the same value")

	# Hover toggles the amount visibility, which is part of the signature.
	# Re-sentinel then flip hover; the labels must be re-written.
	icon_label.text = "SENTINEL_ICON"
	amount_label.text = "SENTINEL_AMOUNT"
	amount_label.visible = false
	main.hover_tile_index = 0
	main.render_tile(0)
	assert_eq(icon_label.text, main.tile_icon(main.get_tile(Vector2i(0, 0)), Vector2i(0, 0)),
		"hover change: icon label re-written")
	assert_eq(amount_label.text, main.tile_amount_text(main.get_tile(Vector2i(0, 0)), Vector2i(0, 0)),
		"hover change: amount label re-written")
	assert_eq(amount_label.visible, true, "hover change: amount visibility flips on")

	# Hover stays on but the same tile state — second pass with hover on
	# should also skip.
	icon_label.text = "SENTINEL_ICON"
	amount_label.text = "SENTINEL_AMOUNT"
	main.render_tile(0)
	assert_eq(icon_label.text, "SENTINEL_ICON", "hover-stable tile: icon label is NOT re-written")
	assert_eq(amount_label.text, "SENTINEL_AMOUNT", "hover-stable tile: amount label is NOT re-written")
	assert_eq(amount_label.visible, true, "hover-stable tile: amount visibility preserved")

	main.free()
