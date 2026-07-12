## Floor-band visual theme catalog for V10 biome presentation.
extends RefCounted

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const BIOME_SPAN: int = 5
const MAX_BIOME_INDEX: int = 6
const THEMES: Array = [
	{
		"index": 1,
		"name": "The Tower",
		"range_label": "Depths 1-5",
		"kicker": "ENTERING THE TOWER",
		"title_color": Color(0.82, 0.82, 0.90),
		"subtitle_color": Color(0.66, 0.66, 0.72),
		"accent_color": Color(0.70, 0.72, 0.80),
		"label_color": Color(0.70, 0.72, 0.80),
		"overlay_bg_color": Color(0.050, 0.050, 0.062, 0.94),
		"outer_bg_tint": Color(0.020, 0.020, 0.030),
		"border_color": Color(0.050, 0.050, 0.062),
		"border_frame_color": Color(0.300, 0.300, 0.360),
		"background_color": Color(0.030, 0.030, 0.040),
		"tile_foreground_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.68, 0.67, 0.70),
			DungeonDataScript.TileType.WALL: Color(0.36, 0.35, 0.40),
			DungeonDataScript.TileType.DOOR: Color(0.60, 0.56, 0.50),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.48, 0.45, 0.42),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.85, 0.85, 0.92),
		},
		"tile_background_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.058, 0.058, 0.070),
			DungeonDataScript.TileType.WALL: Color(0.085, 0.082, 0.105),
			DungeonDataScript.TileType.DOOR: Color(0.14, 0.12, 0.085),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.080, 0.072, 0.058),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.18, 0.18, 0.20),
		},
		"floor_glyphs": [".", "'", "`", ","],
		"wall_glyphs": ["#", "H", "I"],
		"floor_decoration_glyphs": [":", ";"],
		"wall_decoration_glyphs": ["="],
		"floor_decoration_chance_percent": 8,
		"wall_decoration_chance_percent": 5,
	},
	{
		"index": 2,
		"name": "The Rotting Garden",
		"range_label": "Depths 6-10",
		"kicker": "ENTERING THE ROTTING GARDEN",
		"title_color": Color(0.85, 0.55, 0.62),
		"subtitle_color": Color(0.72, 0.82, 0.52),
		"accent_color": Color(0.80, 0.45, 0.55),
		"label_color": Color(0.72, 0.82, 0.52),
		"overlay_bg_color": Color(0.030, 0.058, 0.038, 0.94),
		"outer_bg_tint": Color(0.012, 0.025, 0.016),
		"border_color": Color(0.022, 0.052, 0.034),
		"border_frame_color": Color(0.20, 0.45, 0.26),
		"background_color": Color(0.014, 0.038, 0.024),
		"tile_foreground_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.58, 0.72, 0.52),
			DungeonDataScript.TileType.WALL: Color(0.28, 0.42, 0.26),
			DungeonDataScript.TileType.DOOR: Color(0.78, 0.62, 0.24),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.50, 0.42, 0.20),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.90, 0.80, 0.42),
		},
		"tile_background_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.026, 0.062, 0.038),
			DungeonDataScript.TileType.WALL: Color(0.036, 0.085, 0.050),
			DungeonDataScript.TileType.DOOR: Color(0.12, 0.082, 0.030),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.070, 0.058, 0.028),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.075, 0.10, 0.036),
		},
		"floor_glyphs": [",", ".", "'", "`"],
		"wall_glyphs": ["{", "}", "|"],
		"floor_decoration_glyphs": [";", ","],
		"wall_decoration_glyphs": [";"],
		"floor_decoration_chance_percent": 12,
		"wall_decoration_chance_percent": 8,
	},
	{
		"index": 3,
		"name": "The Cinder Wastes",
		"range_label": "Depths 11-15",
		"kicker": "ENTERING THE CINDER WASTES",
		"title_color": Color(1.0, 0.45, 0.18),
		"subtitle_color": Color(0.85, 0.58, 0.40),
		"accent_color": Color(0.70, 0.16, 0.12),
		"label_color": Color(1.0, 0.52, 0.24),
		"overlay_bg_color": Color(0.075, 0.028, 0.020, 0.94),
		"outer_bg_tint": Color(0.030, 0.008, 0.004),
		"border_color": Color(0.060, 0.018, 0.014),
		"border_frame_color": Color(0.50, 0.16, 0.10),
		"background_color": Color(0.040, 0.012, 0.010),
		"tile_foreground_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.50, 0.30, 0.22),
			DungeonDataScript.TileType.WALL: Color(0.22, 0.14, 0.12),
			DungeonDataScript.TileType.DOOR: Color(0.80, 0.42, 0.16),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.50, 0.28, 0.14),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(1.0, 0.55, 0.20),
		},
		"tile_background_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.058, 0.022, 0.016),
			DungeonDataScript.TileType.WALL: Color(0.085, 0.030, 0.022),
			DungeonDataScript.TileType.DOOR: Color(0.12, 0.045, 0.014),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.072, 0.030, 0.014),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.16, 0.072, 0.016),
		},
		"floor_glyphs": [".", ",", "`", ":"],
		"wall_glyphs": ["^", "A", "M"],
		"floor_decoration_glyphs": ["*", ":"],
		"wall_decoration_glyphs": ["*"],
		"floor_decoration_chance_percent": 10,
		"wall_decoration_chance_percent": 6,
	},
	{
		"index": 4,
		"name": "The Sunken Halls",
		"range_label": "Depths 16-20",
		"kicker": "ENTERING THE SUNKEN HALLS",
		"title_color": Color(0.45, 0.70, 0.82),
		"subtitle_color": Color(0.58, 0.72, 0.68),
		"accent_color": Color(0.72, 0.50, 0.28),
		"label_color": Color(0.45, 0.70, 0.82),
		"overlay_bg_color": Color(0.020, 0.048, 0.075, 0.94),
		"outer_bg_tint": Color(0.006, 0.020, 0.038),
		"border_color": Color(0.014, 0.038, 0.062),
		"border_frame_color": Color(0.16, 0.36, 0.52),
		"background_color": Color(0.010, 0.026, 0.044),
		"tile_foreground_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.42, 0.62, 0.58),
			DungeonDataScript.TileType.WALL: Color(0.20, 0.36, 0.52),
			DungeonDataScript.TileType.DOOR: Color(0.62, 0.48, 0.28),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.42, 0.34, 0.22),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.50, 0.80, 0.85),
		},
		"tile_background_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.020, 0.044, 0.058),
			DungeonDataScript.TileType.WALL: Color(0.030, 0.060, 0.090),
			DungeonDataScript.TileType.DOOR: Color(0.048, 0.038, 0.022),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.034, 0.030, 0.020),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.030, 0.072, 0.082),
		},
		"floor_glyphs": ["~", ".", ",", "'"],
		"wall_glyphs": ["~", "=", "-"],
		"floor_decoration_glyphs": ["~", ","],
		"wall_decoration_glyphs": ["_"],
		"floor_decoration_chance_percent": 12,
		"wall_decoration_chance_percent": 7,
	},
	{
		"index": 5,
		"name": "The Glass Labyrinth",
		"range_label": "Depths 21-25",
		"kicker": "ENTERING THE GLASS LABYRINTH",
		"title_color": Color(0.78, 0.70, 1.0),
		"subtitle_color": Color(0.80, 0.80, 0.88),
		"accent_color": Color(0.80, 0.80, 0.88),
		"label_color": Color(0.78, 0.70, 1.0),
		"overlay_bg_color": Color(0.038, 0.028, 0.058, 0.94),
		"outer_bg_tint": Color(0.014, 0.010, 0.028),
		"border_color": Color(0.028, 0.020, 0.052),
		"border_frame_color": Color(0.32, 0.24, 0.52),
		"background_color": Color(0.018, 0.014, 0.036),
		"tile_foreground_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.62, 0.56, 0.78),
			DungeonDataScript.TileType.WALL: Color(0.28, 0.24, 0.38),
			DungeonDataScript.TileType.DOOR: Color(0.72, 0.68, 0.85),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.48, 0.45, 0.60),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.80, 0.76, 1.0),
		},
		"tile_background_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.034, 0.026, 0.058),
			DungeonDataScript.TileType.WALL: Color(0.050, 0.036, 0.085),
			DungeonDataScript.TileType.DOOR: Color(0.062, 0.048, 0.085),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.042, 0.034, 0.062),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.058, 0.044, 0.10),
		},
		"floor_glyphs": [".", "'", "`", ","],
		"wall_glyphs": ["/", "\\", "X"],
		"floor_decoration_glyphs": ["*", ":"],
		"wall_decoration_glyphs": ["+"],
		"floor_decoration_chance_percent": 9,
		"wall_decoration_chance_percent": 9,
	},
	{
		"index": 6,
		"name": "Endless Deeps",
		"range_label": "Depth 26+",
		"kicker": "ENTERING THE ENDLESS DEEPS",
		"title_color": Color(1.0, 0.40, 0.90),
		"subtitle_color": Color(0.72, 0.94, 1.0),
		"accent_color": Color(0.42, 1.0, 0.94),
		"label_color": Color(0.42, 1.0, 0.94),
		"overlay_bg_color": Color(0.026, 0.018, 0.045, 0.95),
		"outer_bg_tint": Color(0.004, 0.000, 0.020),
		"border_color": Color(0.026, 0.018, 0.060),
		"border_frame_color": Color(0.48, 0.16, 0.50),
		"background_color": Color(0.012, 0.008, 0.026),
		"tile_foreground_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.68, 0.76, 0.84),
			DungeonDataScript.TileType.WALL: Color(0.50, 0.28, 0.58),
			DungeonDataScript.TileType.DOOR: Color(0.72, 0.42, 0.82),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.46, 0.36, 0.58),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.42, 1.0, 0.94),
		},
		"tile_background_colors":
		{
			DungeonDataScript.TileType.FLOOR: Color(0.022, 0.018, 0.040),
			DungeonDataScript.TileType.WALL: Color(0.045, 0.022, 0.065),
			DungeonDataScript.TileType.DOOR: Color(0.070, 0.030, 0.085),
			DungeonDataScript.TileType.OPEN_DOOR: Color(0.042, 0.028, 0.055),
			DungeonDataScript.TileType.STAIRS_DOWN: Color(0.018, 0.070, 0.076),
		},
		"floor_glyphs": [".", "'", "`", ","],
		"wall_glyphs": ["!", ":", ";"],
		"floor_decoration_glyphs": ["*", ":"],
		"wall_decoration_glyphs": ["."],
		"floor_decoration_chance_percent": 14,
		"wall_decoration_chance_percent": 10,
	},
]
const ATMOSPHERE_KEYS: Dictionary = {
	1:
	{
		"ambient_glyphs": [".", "'", "`"],
		"ambient_speed": 0.8,
		"ambient_intensity": 0.12,
		"shimmer_color": Color(0.15, 0.15, 0.20, 0.04),
		"void_glyph": ".",
		"void_color": Color(0.12, 0.12, 0.18, 0.20),
		"fov_breathe_intensity": 0.06,
		"fov_breathe_speed": 1.2,
	},
	2:
	{
		"ambient_glyphs": [",", ";", "."],
		"ambient_speed": 0.6,
		"ambient_intensity": 0.15,
		"shimmer_color": Color(0.22, 0.35, 0.18, 0.05),
		"void_glyph": ".",
		"void_color": Color(0.18, 0.28, 0.12, 0.25),
		"fov_breathe_intensity": 0.08,
		"fov_breathe_speed": 0.9,
	},
	3:
	{
		"ambient_glyphs": ["*", ":", "."],
		"ambient_speed": 0.5,
		"ambient_intensity": 0.18,
		"shimmer_color": Color(0.40, 0.12, 0.06, 0.05),
		"void_glyph": ".",
		"void_color": Color(0.35, 0.08, 0.04, 0.28),
		"fov_breathe_intensity": 0.10,
		"fov_breathe_speed": 1.4,
	},
	4:
	{
		"ambient_glyphs": ["~", ".", ","],
		"ambient_speed": 0.7,
		"ambient_intensity": 0.14,
		"shimmer_color": Color(0.08, 0.22, 0.32, 0.04),
		"void_glyph": "~",
		"void_color": Color(0.06, 0.18, 0.28, 0.22),
		"fov_breathe_intensity": 0.07,
		"fov_breathe_speed": 1.0,
	},
	5:
	{
		"ambient_glyphs": [".", "*", ":"],
		"ambient_speed": 1.0,
		"ambient_intensity": 0.10,
		"shimmer_color": Color(0.20, 0.18, 0.35, 0.06),
		"void_glyph": ".",
		"void_color": Color(0.18, 0.14, 0.30, 0.18),
		"fov_breathe_intensity": 0.05,
		"fov_breathe_speed": 1.5,
	},
	6:
	{
		"ambient_glyphs": [".", "*", ":"],
		"ambient_speed": 0.9,
		"ambient_intensity": 0.20,
		"shimmer_color": Color(0.20, 0.30, 0.40, 0.07),
		"void_glyph": ".",
		"void_color": Color(0.15, 0.22, 0.35, 0.30),
		"fov_breathe_intensity": 0.12,
		"fov_breathe_speed": 1.1,
	},
}

const ENEMY_ROSTERS: Dictionary = {
	1:
	[
		"res://resources/enemies/rat.tres",
		"res://resources/enemies/bat.tres",
		"res://resources/enemies/goblin.tres",
		"res://resources/enemies/kobold.tres",
		"res://resources/enemies/skeleton.tres",
		"res://resources/enemies/stone_sentry.tres",
		"res://resources/enemies/eye_acolyte.tres",
		"res://resources/enemies/clockwork_spider.tres",
	],
	2:
	[
		"res://resources/enemies/zombie.tres",
		"res://resources/enemies/orc.tres",
		"res://resources/enemies/cultist.tres",
		"res://resources/enemies/wraith.tres",
		"res://resources/enemies/troll.tres",
		"res://resources/enemies/thorn_lasher.tres",
		"res://resources/enemies/spore_servant.tres",
		"res://resources/enemies/briar_witch.tres",
		"res://resources/enemies/frost_guardian.tres",
	],
	3:
	[
		"res://resources/enemies/ogre_brute.tres",
		"res://resources/enemies/abyss_knight.tres",
		"res://resources/enemies/lich.tres",
		"res://resources/enemies/ancient_dragon.tres",
		"res://resources/enemies/ash_revenant.tres",
		"res://resources/enemies/ember_archer.tres",
		"res://resources/enemies/flame_acolyte.tres",
		"res://resources/enemies/warleader.tres",
		"res://resources/enemies/shadow_weaver.tres",
	],
	4:
	[
		"res://resources/enemies/drowned_knight.tres",
		"res://resources/enemies/harpooner.tres",
		"res://resources/enemies/abyssal_eel.tres",
		"res://resources/enemies/tidecaller.tres",
		"res://resources/enemies/shadow_weaver.tres",
	],
	5:
	[
		"res://resources/enemies/abyss_knight.tres",
		"res://resources/enemies/lich.tres",
		"res://resources/enemies/ancient_dragon.tres",
		"res://resources/enemies/mirror_duelist.tres",
		"res://resources/enemies/prism_seer.tres",
		"res://resources/enemies/shard_golem.tres",
		"res://resources/enemies/glass_dragonling.tres",
	],
}


static func biome_index_for_floor(floor_number: int) -> int:
	var safe_floor: int = max(1, floor_number)
	var biome_index: int = int((safe_floor - 1) / BIOME_SPAN) + 1
	return min(biome_index, MAX_BIOME_INDEX)


static func theme_for_floor(floor_number: int) -> Dictionary:
	return theme_for_biome_index(biome_index_for_floor(floor_number))


static func theme_for_biome_index(biome_index: int) -> Dictionary:
	var safe_index: int = clampi(biome_index, 1, MAX_BIOME_INDEX)
	var theme: Dictionary = THEMES[safe_index - 1]
	return theme.duplicate(true)


static func atmosphere_for_biome_index(biome_index: int) -> Dictionary:
	var safe_index: int = clampi(biome_index, 1, MAX_BIOME_INDEX)
	return ATMOSPHERE_KEYS.get(safe_index, ATMOSPHERE_KEYS[1]).duplicate(true)


static func enemy_path_allowed_for_biome(enemy_path: String, biome_index: int) -> bool:
	var safe_index: int = clampi(biome_index, 1, MAX_BIOME_INDEX)
	if safe_index == MAX_BIOME_INDEX:
		return true
	return ENEMY_ROSTERS.get(safe_index, []).has(enemy_path)


static func enemy_roster_for_biome_index(biome_index: int) -> Array[String]:
	var safe_index: int = clampi(biome_index, 1, MAX_BIOME_INDEX)
	var source: Array = ENEMY_ROSTERS.get(safe_index, [])
	var paths: Array[String] = []
	for path: String in source:
		paths.append(path)
	return paths


static func biome_names_for_enemy_path(enemy_path: String) -> Array[String]:
	var names: Array[String] = []
	for theme: Dictionary in THEMES:
		var biome_index: int = theme.get("index", 0)
		if biome_index == MAX_BIOME_INDEX:
			continue
		if ENEMY_ROSTERS.get(biome_index, []).has(enemy_path):
			names.append(theme.get("name", ""))
	names.append(THEMES[MAX_BIOME_INDEX - 1].get("name", "Endless Deeps"))
	return names
