## Pure worker sprite rendering — pixel-art texture generation and crowd
## offsets. No scene references; main.gd owns the texture cache and calls in.
class_name WorkerRenderer

const Constants := preload("res://scripts/constants.gd")


## Build the 12x14 pixel-art texture for a worker. Deterministic per
## (name, frame, carrying) — callers should cache by that key.
static func create_texture(worker_name: String, frame: int, carrying: String = "") -> Texture2D:
	var accent: Color = Constants.WORKER_BADGE_COLORS.get(worker_name, Color.WHITE)
	var shadow := accent.darkened(0.45)
	var skin := Color("#f2d0b1")
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
		var cargo_color := Color("#9aa3aa")
		if carrying == "wood":
			cargo_color = Color("#8b5a2b")
		elif carrying == "food":
			cargo_color = Color("#6fbf73")
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

	return ImageTexture.create_from_image(image)


## Offset for the slot-th of total workers sharing one tile: occupants are
## spread evenly around a ring, so any crowd size stays visually distinct
## (the old fixed six-offset table wrapped and overlapped above six).
static func collision_offset(slot: int, total: int, spacing: float) -> Vector2:
	if total <= 1:
		return Vector2.ZERO
	var angle := TAU * float(slot % total) / float(total)
	return Vector2(cos(angle), sin(angle)) * spacing * 1.25
