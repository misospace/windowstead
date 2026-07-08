class_name WorkerRenderer
extends RefCounted

const Constants := preload("res://scripts/constants.gd")

# Pure data → texture rendering for workers, with an internal cache.
# No scene dependencies — safe to call from any context.

const _SKIN := Color("#f2d0b1")
const _CARGO_DEFAULT := Color("#9aa3aa")
const _CARGO_WOOD := Color("#8b5a2b")
const _CARGO_FOOD := Color("#6fbf73")

static var _cache: Dictionary = {}

static func worker_texture(name: String, frame: int, carrying: String = "") -> Texture2D:
	var cache_key := "%s:%d:%s" % [name, frame, carrying]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var accent: Color = Constants.WORKER_BADGE_COLORS.get(name, Color.WHITE)
	var shadow := accent.darkened(0.45)
	var skin := _SKIN
	var image := Image.create(12, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	# head
	for y in range(0, 4):
		for x in range(4, 8):
			image.set_pixel(x, y, skin)

	# body
	for y in range(4, 10):
		for x in range(3, 9):
			image.set_pixel(x, y, accent)

	# arms
	for y in range(5, 9):
		image.set_pixel(2, y, shadow)
		image.set_pixel(9, y, shadow)

	if not carrying.is_empty():
		var cargo_color := _CARGO_DEFAULT
		if carrying == "wood":
			cargo_color = _CARGO_WOOD
		elif carrying == "food":
			cargo_color = _CARGO_FOOD
		for y in range(5, 9):
			for x in range(0, 3):
				image.set_pixel(x, y, cargo_color)
		image.set_pixel(1, 4, cargo_color.lightened(0.25))

	# legs alternate per frame for a simple walk bob
	if frame % 2 == 0:
		image.set_pixel(4, 10, shadow)
		image.set_pixel(4, 11, shadow)
		image.set_pixel(7, 10, shadow)
		image.set_pixel(7, 11, shadow)
	else:
		image.set_pixel(5, 10, shadow)
		image.set_pixel(4, 11, shadow)
		image.set_pixel(6, 10, shadow)
		image.set_pixel(7, 11, shadow)

	# feet
	image.set_pixel(3, 13, shadow)
	image.set_pixel(7, 13, shadow)

	var texture := ImageTexture.create_from_image(image)
	_cache[cache_key] = texture
	return texture

static func clear_cache() -> void:
	_cache.clear()