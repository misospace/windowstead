## Centralised game constants for Windowstead.
## Extracted from scripts/main.gd to reduce its blast radius.
## All values are immutable const dictionaries/arrays — safe to preload anywhere.

const WORKER_NAMES := ["Jun", "Mara"]

const BASE_TICK_SECONDS := 0.9
const EVENT_INTERVAL_TICKS := 66

const RESOURCE_COLORS := {
	"wood": Color("#5d8f58"),
	"stone": Color("#8b96a4"),
	"food": Color("#c99e53"),
}

const STRUCTURE_COLORS := {
	"hut": Color("#a26f47"),
	"workshop": Color("#5f7da3"),
	"garden": Color("#78a85d"),
}

const TILE_BACKDROPS := {
	"ground": Color("#232a33"),
	"tree": Color("#294131"),
	"rock": Color("#3a434d"),
	"berries": Color("#4a3144"),
	"foundation": Color("#57442e"),
	"hut": Color("#5a4031"),
	"workshop": Color("#32465d"),
	"garden": Color("#30523a"),
	"stockpile": Color("#66522a"),
}

const WORKER_BADGE_COLORS := {
	"Jun": Color("#f58f6c"),
	"Mara": Color("#75c7ff"),
}

const BUILD_COSTS := {
	"hut": {"wood": 6, "stone": 2},
	"workshop": {"wood": 4, "stone": 6},
	"garden": {"wood": 3, "stone": 1},
}

const BUILD_UNLOCKS := {
	"hut": true,
	"workshop": "hut",
	"garden": "workshop",
}
