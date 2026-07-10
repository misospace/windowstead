extends RefCounted

## Render helpers for tile styling and accent colors.

const Constants := preload("res://scripts/constants.gd")


static func tile_style(tile: Dictionary, pos: Vector2i, stockpile_pos: Vector2i, pending_build_kind: String = "", hovered_pos: Vector2i = Vector2i(-1, -1), can_place: bool = false) -> StyleBoxFlat:
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
	var kind := "stockpile" if pos == stockpile_pos else String(tile.kind)
	style.bg_color = Constants.TILE_BACKDROPS.get(kind, Color("#1b2128"))
	style.border_color = tile_accent(tile, pos, stockpile_pos, pending_build_kind, hovered_pos, can_place)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 2
	return style


static func tile_accent(tile: Dictionary, pos: Vector2i, stockpile_pos: Vector2i, pending_build_kind: String = "", hovered_pos: Vector2i = Vector2i(-1, -1), can_place: bool = false) -> Color:
	if not pending_build_kind.is_empty() and pos == hovered_pos:
		return Color("#73d38c") if can_place else Color("#d36b6b")
	if pos == stockpile_pos:
		return Color("#d4b36f")
	if Constants.RESOURCE_COLORS.has(String(tile.resource)):
		return Constants.RESOURCE_COLORS[String(tile.resource)]
	if Constants.STRUCTURE_COLORS.has(String(tile.kind)):
		return Constants.STRUCTURE_COLORS[String(tile.kind)]
	if String(tile.kind) == "foundation":
		return Color("#c7a25e")
	return Color(1, 1, 1, 0.35)
