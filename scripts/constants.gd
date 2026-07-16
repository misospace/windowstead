## Centralised game constants for Windowstead.
## Extracted from scripts/main.gd to reduce its blast radius.
## All values are immutable const dictionaries/arrays — safe to preload anywhere.

const WORKER_NAMES := ["Jun", "Mara", "Kai", "Lia", "Ren", "Sia", "Nia", "Tao", "Yun", "Zoe"]

const BASE_TICK_SECONDS := 0.9
const EVENT_INTERVAL_TICKS := 66
const MAX_EVENT_LOG := 20

# Focus Mode slows the colony down while the player works (issue #19).
const FOCUS_MODE_TICK_MULTIPLIER := 2.5
# Zoom slider bounds/step for tile scaling.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1

const RESOURCE_COLORS := {
	"wood": Color("#5d8f58"),
	"stone": Color("#8b96a4"),
	"food": Color("#c99e53"),
}

const RESOURCE_TRENDS := {
	"rising": "↑",
	"stable": "→",
	"falling": "↓",
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

# Tile accent palette, consumed by TileRender via its theme context so the
# whole tile look is tuned from this file.
const TILE_ACCENTS := {
	"placement_ok": Color("#73d38c"),
	"placement_blocked": Color("#d36b6b"),
	"stockpile": Color("#d4b36f"),
	"foundation": Color("#c7a25e"),
	"default": Color(1, 1, 1, 0.35),
}
const TILE_DEFAULT_BACKDROP := Color("#1b2128")

const WORKER_BADGE_COLORS := {
	"Jun": Color("#f58f6c"),
	"Mara": Color("#75c7ff"),
	"Kai": Color("#a3e635"),
	"Lia": Color("#f472b6"),
	"Ren": Color("#facc15"),
	"Sia": Color("#c084fc"),
	"Nia": Color("#fb923c"),
	"Tao": Color("#34d399"),
	"Yun": Color("#60a5fa"),
	"Zoe": Color("#f87171"),
}

const BUILD_COSTS := {
	"hut": {"wood": 6, "stone": 2},
	"workshop": {"wood": 4, "stone": 6},
	"garden": {"wood": 3, "stone": 1},
}

const BUILD_EFFECTS := {
	"hut": "Housing support for future worker cap.",
	"workshop": "Improves build speed and unlocks garden.",
	"garden": "Adds a steady food supply boost.",
}

const BUILD_UNLOCKS := {
	"hut": true,
	"workshop": "hut",
	"garden": "workshop",
}

# Per-structure presentation: build/world icons and the short label shown on
# the tile. Adding a structure means adding a row here, not editing matches
# scattered through main.gd.
const STRUCTURE_ICONS := {
	"hut": "🏠",
	"workshop": "🛠",
	"garden": "🪴",
}

const TILE_ICONS := {
	"tree": "🌲",
	"rock": "🪨",
	"berries": "🫐",
}

# Everything that defines a gatherable resource tile: what it yields, how
# much a world-seeded tile holds, how much an ambient supply drop holds, and
# the drop announcement. The sim derives gatherability from membership here.
const RESOURCE_TILES := {
	"tree": {
		"resource": "wood",
		"seed_amount": 6,
		"drop_amount": 4,
		"drop_message": "A driftwood bundle lands nearby. Fresh wood appeared.",
	},
	"rock": {
		"resource": "stone",
		"seed_amount": 5,
		"drop_amount": 4,
		"drop_message": "A rubble drop lands nearby. Fresh stone appeared.",
	},
	"berries": {
		"resource": "food",
		"seed_amount": 4,
		"drop_amount": 3,
		"drop_message": "A snack crate lands nearby. Fresh food appeared.",
	},
}

const TILE_SHORT_LABELS := {
	"hut": "hut",
	"workshop": "shop",
	"garden": "grow",
}

const BASE_WORKER_CAP := 2

const WORKER_CAP_BONUSES := {
	"hut": 2,
}

# ── Food upkeep model (issue #147, links to #133) ────────────────────────────
# Base workers (up to BASE_WORKERS_NO_UPKEEP) do not consume food.
# Each extra worker above that threshold consumes FOOD_PER_EXTRA_WORKER
# every FOOD_UPKEEP_INTERVAL_TICKS ticks.
# Low-food soft penalties slow workers but never cause harsh failure.

const FOOD_UPKEEP_INTERVAL_TICKS := 10
const BASE_WORKERS_NO_UPKEEP := 2
const FOOD_PER_EXTRA_WORKER := 1
const LOW_FOOD_THRESHOLD := 3        # food <= this → slowdown begins
const STARVATION_FOOD_THRESHOLD := 1 # food <= this → workers pause

# Slowdown multipliers: speed = base_speed * factor
# At LOW_FOOD_THRESHOLD, workers operate at 50% speed.
# At STARVATION_FOOD_THRESHOLD, workers stop (0% speed) unless gathering food.
const LOW_FOOD_SPEED_FACTOR := 0.5
const STARVATION_SPEED_FACTOR := 0.0

# ── Worker intent icons and idle reasons (issue #136) ─────────────────────────
# Maps task kind + state to a compact emoji icon shown in the crew panel.
# Also provides human-readable reason text for idle states.

const WORKER_INTENT_ICONS := {
	"gather_wood": "🪓",
	"gather_stone": "⛏",
	"gather_food": "🫐",
	"haul": "📦",
	"build_hut": "🏗",
	"build_workshop": "🏗",
	"build_garden": "🏗",
	"idle": "💤",
	"break": "☕",
}

const WORKER_INTENT_REASONS := {
	"idle_no_task": "No valid task",
	"idle_stockpile_full": "Stockpile full",
	"idle_no_reachable_build": "No reachable build task",
	"idle_food_priority": "Food priority active",
}
