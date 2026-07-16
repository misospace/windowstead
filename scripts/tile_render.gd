## Pure tile rendering helpers — no scene references, fully testable.
## Consumes constants from constants.gd and a context dict from the caller.

class_name TileRender


## Returns a StyleBoxFlat for the given tile using the provided theme.
## `theme` must contain TILE_BACKDROPS (Dictionary of kind → Color).
static func tile_style(tile: Dictionary, pos: Vector2i, theme: Dictionary, accent_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.content_margin_left = 4
	style.content_margin_top = 3
	style.content_margin_right = 4
	style.content_margin_bottom = 3

	var kind := String(tile.kind)
	if theme.has("stockpile_pos") and pos == theme["stockpile_pos"]:
		kind = "stockpile"

	style.bg_color = theme.get("TILE_BACKDROPS", {}).get(kind, theme.get("DEFAULT_BACKDROP", Color("#1b2128")))
	style.border_color = accent_color
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 2
	return style


## Returns the accent (border) color for a tile based on context.
## `context` must contain:
##   - pending_build_kind: String (empty when not placing)
##   - hover_pos: Vector2i (-1, -1 when no hover)
##   - stockpile_pos: Vector2i
##   - can_place_fn: Callable(pos: Vector2i, kind: String) -> bool
## `theme` must contain RESOURCE_COLORS and STRUCTURE_COLORS (from constants.gd).
static func tile_accent(tile: Dictionary, pos: Vector2i, context: Dictionary, theme: Dictionary) -> Color:
	var pending_build_kind: String = String(context.get("pending_build_kind", ""))
	var hover_pos: Vector2i = Vector2i(context.get("hover_pos", Vector2i(-1, -1)))
	var stockpile_pos: Vector2i = Vector2i(context.get("stockpile_pos", Vector2i(-1, -1)))
	var can_place_fn: Callable = context.get("can_place_fn", func(_p: Vector2i, _k: String): return false)
	# Palette normally comes from constants.gd via the theme; the literals
	# below are fallbacks so a minimal theme still renders.
	var accents: Dictionary = theme.get("TILE_ACCENTS", {})

	# Build placement highlight
	if not pending_build_kind.is_empty() and pos == hover_pos:
		if can_place_fn.call(pos, pending_build_kind):
			return accents.get("placement_ok", Color("#73d38c"))
		return accents.get("placement_blocked", Color("#d36b6b"))

	# Stockpile accent
	if pos == stockpile_pos:
		return accents.get("stockpile", Color("#d4b36f"))

	# Resource accent
	var resource_colors: Dictionary = theme.get("RESOURCE_COLORS", {})
	if resource_colors.has(String(tile.resource)):
		return resource_colors[String(tile.resource)]

	# Structure accent
	var structure_colors: Dictionary = theme.get("STRUCTURE_COLORS", {})
	if structure_colors.has(String(tile.kind)):
		return structure_colors[String(tile.kind)]

	# Foundation accent
	if String(tile.kind) == "foundation":
		return accents.get("foundation", Color("#c7a25e"))

	return accents.get("default", Color(1, 1, 1, 0.35))
