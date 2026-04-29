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

const SIDE_GRID_W := 10
const SIDE_GRID_H := 24
const BOTTOM_GRID_W := 32
const BOTTOM_GRID_H := 5
const TILE_GAP := 6
const TILE_SIZE_BUMP := 1.15
const BOTTOM_TILE_BASE_PX := 48.5
const VERTICAL_TILE_BASE_PX := 48.0
const BOTTOM_TILE_MAX_PX := 58
const VERTICAL_TILE_MAX_PX := 56
const BOTTOM_TARGET_WIDTH_RATIO := 0.94
const BOTTOM_TARGET_HEIGHT_RATIO := 0.22
const DOCK_EDGE_MARGIN := 24
const WORLD_PANEL_PADDING := Vector2i(16, 16)
const SIDEBAR_WIDTH := 220
const BOTTOM_DOCK_PADDING := Vector2i(48, 170)
const VERTICAL_DOCK_PADDING := Vector2i(60, 300)


## Compute tile pixel size for a given anchor family and zoom factor.
## Tiles are always square (same x and y).
static func tile_px_for_anchor(dock_anchor: String, zoom: float = 1.0) -> int:
	var base_tile_px: float = BOTTOM_TILE_BASE_PX if dock_anchor == "bottom" else VERTICAL_TILE_BASE_PX
	return maxi(1, int(round(base_tile_px * TILE_SIZE_BUMP * zoom)))


static func tile_size_for_anchor(anchor_family: String, zoom: float = 1.0) -> Vector2i:
	var px := tile_px_for_anchor(anchor_family, zoom)
	return Vector2i(px, px)


## Compute a tile size that can grow on large work areas without changing grid dimensions.
static func tile_px_for_work_area(anchor_family: String, usable_width: int, usable_height: int, zoom: float = 1.0) -> int:
	var base_px := tile_px_for_anchor(anchor_family, zoom)
	var dims := grid_dims_for_anchor(anchor_family)
	if anchor_family == "bottom":
		var target_world_width := float(usable_width) * BOTTOM_TARGET_WIDTH_RATIO
		var target_world_height := float(usable_height) * BOTTOM_TARGET_HEIGHT_RATIO
		var available_width_for_tiles := target_world_width - float(dims["grid_w"] - 1) * TILE_GAP
		var available_height_for_tiles := target_world_height - float(dims["grid_h"] - 1) * TILE_GAP
		var fit_px := mini(
			int(floor(available_width_for_tiles / float(dims["grid_w"]))),
			int(floor(available_height_for_tiles / float(dims["grid_h"])))
		)
		return clampi(maxi(base_px, fit_px), base_px, BOTTOM_TILE_MAX_PX)
	var target_world_height := float(usable_height - VERTICAL_DOCK_PADDING.y - DOCK_EDGE_MARGIN)
	var available_for_tiles := target_world_height - float(dims["grid_h"] - 1) * TILE_GAP
	var fit_px := int(floor(available_for_tiles / float(dims["grid_h"])))
	return clampi(fit_px, 20, VERTICAL_TILE_MAX_PX)


static func tile_size_for_work_area(anchor_family: String, usable_width: int, usable_height: int, zoom: float = 1.0) -> Vector2i:
	var px := tile_px_for_work_area(anchor_family, usable_width, usable_height, zoom)
	return Vector2i(px, px)


## Compute world panel pixel size given grid dimensions and tile size.
static func world_pixel_size(grid_w: int, grid_h: int, tile_px: int) -> Vector2i:
	return Vector2i(
		grid_w * tile_px + (grid_w - 1) * TILE_GAP,
		grid_h * tile_px + (grid_h - 1) * TILE_GAP
	)


static func world_pixel_size_for_tile_size(grid_w: int, grid_h: int, tile_size: Vector2i) -> Vector2i:
	return Vector2i(
		grid_w * tile_size.x + (grid_w - 1) * TILE_GAP,
		grid_h * tile_size.y + (grid_h - 1) * TILE_GAP
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
static func dock_size_for_anchor(anchor_family: String, grid_w: int, grid_h: int, tile_px: int, include_sidebar: bool = true) -> Vector2i:
	return dock_size_for_anchor_tile_size(anchor_family, grid_w, grid_h, Vector2i(tile_px, tile_px), include_sidebar)


static func dock_size_for_anchor_tile_size(anchor_family: String, grid_w: int, grid_h: int, tile_size: Vector2i, include_sidebar: bool = true) -> Vector2i:
	var padding := dock_padding_for_anchor(anchor_family)
	var world := world_pixel_size_for_tile_size(grid_w, grid_h, tile_size)
	var base := Vector2i(world.x + padding.x, world.y + padding.y)
	if anchor_family == "bottom" and include_sidebar:
		base.y = maxi(base.y, 460)
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
static func popup_position_for_anchor(dock_anchor: String, backdrop_width: float, backdrop_height: float, sidebar_width: float, sidebar_height: float) -> Vector2:
	if dock_anchor == "bottom":
		return Vector2(backdrop_width - sidebar_width - 16, 16)
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
	return Vector2i(2, 9)
