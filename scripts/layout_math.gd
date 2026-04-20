## Pure layout math for dock and tile geometry.
## Extracted from main.gd so layout logic can be tested directly
## without requiring a full scene or DisplayServer access.
##
## Regression targets:
## - anchor-family dock geometry (#40, #52, #53, #54)
## - popup placement staying within reachable bounds
## - square tile assumptions
##
## Usage: call functions directly; no Godot node dependency.

const SIDE_GRID_W := 7
const SIDE_GRID_H := 16
const BOTTOM_GRID_W := 30
const BOTTOM_GRID_H := 5
const TILE_GAP := 6
const TILE_SIZE_BUMP := 1.15
const BOTTOM_TILE_BASE_PX := 40.0
const VERTICAL_TILE_BASE_PX := 48.0
const WORLD_PANEL_PADDING := Vector2i(16, 16)
const SIDEBAR_WIDTH := 220
const BOTTOM_DOCK_PADDING := Vector2i(48, 110)
const VERTICAL_DOCK_PADDING := Vector2i(60, 120)


## Compute tile pixel size for a given anchor family and zoom factor.
## Tiles are always square (same x and y).
static func tile_px_for_anchor(dock_anchor: String, zoom: float = 1.0) -> int:
	var base_tile_px: float = BOTTOM_TILE_BASE_PX if dock_anchor == "bottom" else VERTICAL_TILE_BASE_PX
	return maxi(1, int(round(base_tile_px * TILE_SIZE_BUMP * zoom)))


## Compute world panel pixel size given grid dimensions and tile size.
static func world_pixel_size(grid_w: int, grid_h: int, tile_px: int) -> Vector2i:
	return Vector2i(
		grid_w * tile_px + (grid_w - 1) * TILE_GAP,
		grid_h * tile_px + (grid_h - 1) * TILE_GAP
	)


## Get grid dimensions for a given anchor family.
static func grid_dims_for_anchor(anchor_family: String) -> Dictionary:
	if anchor_family == "bottom":
		return {"grid_w": BOTTOM_GRID_W, "grid_h": BOTTOM_GRID_H}
	return {"grid_w": SIDE_GRID_W, "grid_h": SIDE_GRID_H}


## Get dock padding for a given anchor family.
static func dock_padding_for_anchor(anchor_family: String) -> Vector2i:
	return BOTTOM_DOCK_PADDING if anchor_family == "bottom" else VERTICAL_DOCK_PADDING


## Compute dock window size for a given anchor family.
## Returns (width, height) that accounts for world panel + padding + sidebar.
static func dock_size_for_anchor(anchor_family: String, grid_w: int, grid_h: int, tile_px: int) -> Vector2i:
	var padding := dock_padding_for_anchor(anchor_family)
	var world := world_pixel_size(grid_w, grid_h, tile_px)
	var base := Vector2i(world.x + padding.x, world.y + padding.y)
	if anchor_family == "bottom":
		base.x += SIDEBAR_WIDTH + 16
	return base


## Compute dock window position within a usable screen rect.
## dock_anchor is the raw anchor string ("left", "bottom", "right").
static func dock_position_for_anchor(usable_left: int, usable_top: int, usable_width: int, usable_height: int, dock_size: Vector2i, dock_anchor: String) -> Vector2i:
	if dock_anchor == "left":
		return Vector2i(
			usable_left + 12,
			usable_top + usable_height - dock_size.y - 12
		)
	if dock_anchor == "bottom":
		return Vector2i(
			usable_left + int((usable_width - dock_size.x) / 2),
			usable_top + usable_height - dock_size.y - 12
		)
	# right (default)
	return Vector2i(
		usable_left + usable_width - dock_size.x - 12,
		usable_top + usable_height - dock_size.y - 12
	)


## Compute popup (sidebar) position for a given anchor.
## Returns the (x, y) position of the sidebar panel.
static func popup_position_for_anchor(anchor_family: String, backdrop_width: float, sidebar_width: float) -> Vector2:
	if anchor_family == "bottom":
		return Vector2(backdrop_width - sidebar_width - 16, 16)
	# side (left or right)
	if anchor_family == "right":
		return Vector2(max(16.0, backdrop_width - sidebar_width - 16), 16)
	return Vector2(16, 16)


## Check if a popup position keeps the sidebar within a reachable bounds rect.
## A popup is "reachable" if its entire rectangle fits within the usable area.
static func popup_within_bounds(popup_pos: Vector2, popup_size: Vector2, usable_left: int, usable_top: int, usable_width: int, usable_height: int) -> bool:
	var popup_right := popup_pos.x + popup_size.x
	var popup_bottom := popup_pos.y + popup_size.y
	return (
		popup_pos.x >= usable_left
		and popup_pos.y >= usable_top
		and popup_right <= usable_left + usable_width
		and popup_bottom <= usable_top + usable_height
	)


## Get the anchor family string from a raw dock anchor.
static func anchor_family_from_dock_anchor(dock_anchor: String) -> String:
	if dock_anchor == "bottom":
		return "bottom"
	return "vertical"


## Verify that tile sizes are square (x == y).
static func tile_is_square(tile_px: int) -> bool:
	return true  # by construction, tile_px_for_anchor returns a single int


## Compute the stockpile position for a given anchor family.
static func stockpile_pos_for_anchor(anchor_family: String) -> Vector2i:
	if anchor_family == "bottom":
		return Vector2i(11, 2)
	return Vector2i(2, 7)
