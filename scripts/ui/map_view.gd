## Renders the dungeon grid as colored ASCII glyphs with FOV and depth label.
class_name MapView
extends Node2D

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")
const SECRET_WALL_GLYPH: String = "?"
const FLOOR_GLYPHS: Array[String] = [".", "·", "'", "`"]
const WALL_GLYPHS: Array[String] = ["#", "▓", "▒"]
const GLYPH_SHADOW_OFFSET: Vector2 = Vector2(1, 1)
const CELL_BURST_DURATION: float = 0.55
const BOSS_SPAWN_INTRO_SECONDS: float = 0.90
const CELL_BURST_LIFT: float = 9.0
const TILE_FOREGROUND_COLORS: Dictionary = {
	DungeonDataScript.TileType.FLOOR: Color(0.72, 0.70, 0.62),
	DungeonDataScript.TileType.WALL: Color(0.42, 0.36, 0.50),
	DungeonDataScript.TileType.DOOR: Color(0.82, 0.57, 0.30),
	DungeonDataScript.TileType.OPEN_DOOR: Color(0.63, 0.52, 0.39),
	DungeonDataScript.TileType.STAIRS_DOWN: Color(1.0, 0.88, 0.47),
	DungeonDataScript.TileType.BOSS_DOOR: Color(1.0, 0.72, 0.22),
	DungeonDataScript.TileType.SEALED_BOSS_DOOR: Color(1.0, 0.24, 0.18),
}
const TILE_BACKGROUND_COLORS: Dictionary = {
	DungeonDataScript.TileType.FLOOR: Color(0.06, 0.075, 0.095),
	DungeonDataScript.TileType.WALL: Color(0.105, 0.095, 0.145),
	DungeonDataScript.TileType.DOOR: Color(0.18, 0.11, 0.06),
	DungeonDataScript.TileType.OPEN_DOOR: Color(0.10, 0.085, 0.065),
	DungeonDataScript.TileType.STAIRS_DOWN: Color(0.22, 0.19, 0.05),
	DungeonDataScript.TileType.BOSS_DOOR: Color(0.16, 0.08, 0.02),
	DungeonDataScript.TileType.SEALED_BOSS_DOOR: Color(0.20, 0.02, 0.02),
}

# === Exports ===
@export var font: Font
@export var font_size: int = 16
@export var cell_width: int = 14
@export var cell_height: int = 17
@export var margin: Vector2 = Vector2(20, 44)
@export var playfield_size: Vector2 = Vector2(680, 590)
@export var border_color: Color = Color(0.047, 0.059, 0.082)
@export var border_frame_color: Color = Color(0.282, 0.259, 0.392)
@export var outer_bg_tint: Color = Color(0.0, 0.02, 0.035)
@export var background_color: Color = Color(0.025, 0.032, 0.047)
# === Private Variables ===
var _map_data: Array = []
var _visible_cells: Dictionary = {}
var _explored_cells: Dictionary = {}
var _actors: Array = []
var _items: Dictionary = {}
var _containers: Dictionary = {}
var _target_cursor: Vector2i = Vector2i.ZERO
var _targeting_active: bool = false
var _target_range_cells: Dictionary = {}
var _target_area_cells: Dictionary = {}
var _trap_data: Dictionary = {}
var _revealed_traps: Dictionary = {}
var _triggered_traps: Dictionary = {}
var _secret_walls: Dictionary = {}
var _revealed_secret_walls: Dictionary = {}
var _secret_wall_hint_color: Color = Color(0.72, 0.58, 1.0)
var _biome_theme: Dictionary = BiomeCatalogScript.theme_for_floor(1)
var _cell_bursts: Array[Dictionary] = []
var _enemy_intents: Dictionary = {}
var _boss_room_cells: Dictionary = {}
var _boss_door_cells: Array[Vector2i] = []
var _boss_room_locked: bool = false
var _boss_visuals: Dictionary = {}
var _boss_occupied_cells: Dictionary = {}
var _boss_telegraphs: Dictionary = {}
var _boss_frame_elapsed: float = 0.0
var _boss_frame_index: int = 0
var _boss_spawn_effects: Dictionary = {}
# === Atmosphere State ===
var _atmosphere_enabled: bool = true
var _atmosphere_time: float = 0.0
var _atmosphere_draw_time: float = 0.0
var _atmosphere_profile: Dictionary = {}


# === Public Methods ===
func configure_map(map_data: Array) -> void:
	_map_data = map_data
	queue_redraw()


func set_biome_theme(theme: Dictionary) -> void:
	_biome_theme = theme.duplicate(true)
	_atmosphere_profile = BiomeCatalogScript.atmosphere_for_biome_index(
		_biome_theme.get("index", 1)
	)
	_update_processing_state()
	queue_redraw()


func set_visibility(visible_cells: Dictionary, explored_cells: Dictionary) -> void:
	_visible_cells = visible_cells
	_explored_cells = explored_cells
	queue_redraw()


func set_actors(actors: Array) -> void:
	_actors = actors
	queue_redraw()


func set_items(items: Dictionary) -> void:
	_items = items
	queue_redraw()


func set_containers(containers: Dictionary) -> void:
	_containers = containers
	queue_redraw()


func set_enemy_intents(enemy_intents: Dictionary) -> void:
	_enemy_intents = enemy_intents
	queue_redraw()


func set_targeting(
	active: bool, cursor: Vector2i, range_cells: Dictionary, area_cells: Dictionary = {}
) -> void:
	_targeting_active = active
	_target_cursor = cursor
	_target_range_cells = range_cells
	_target_area_cells = area_cells
	queue_redraw()


func set_traps(
	trap_data: Dictionary, revealed_traps: Dictionary, triggered_traps: Dictionary
) -> void:
	_trap_data = trap_data
	_revealed_traps = revealed_traps
	_triggered_traps = triggered_traps
	queue_redraw()


func set_secret_walls(
	secret_walls: Dictionary, revealed_secret_walls: Dictionary, hint_color: Color
) -> void:
	_secret_walls = secret_walls
	_revealed_secret_walls = revealed_secret_walls
	_secret_wall_hint_color = hint_color
	queue_redraw()


func set_boss_room(room_cells: Dictionary, door_cells: Array, locked: bool) -> void:
	_boss_room_cells = room_cells.duplicate(true)
	_boss_door_cells.clear()
	for door_cell: Vector2i in door_cells:
		_boss_door_cells.append(door_cell)
	_boss_room_locked = locked
	queue_redraw()


func set_boss_visuals(boss_visuals: Dictionary) -> void:
	_boss_visuals = boss_visuals.duplicate(true)
	_rebuild_boss_occupied_cells()
	_update_processing_state()
	queue_redraw()


func play_boss_spawn_intro(anchor_cell: Vector2i, visual: Dictionary) -> void:
	var effect: Dictionary = visual.duplicate(true)
	effect["age"] = 0.0
	effect["duration"] = BOSS_SPAWN_INTRO_SECONDS
	_boss_spawn_effects[anchor_cell] = effect
	_update_processing_state()
	queue_redraw()


func clear_boss_visuals() -> void:
	_boss_visuals.clear()
	_boss_occupied_cells.clear()
	_boss_spawn_effects.clear()
	_boss_frame_elapsed = 0.0
	_update_processing_state()
	queue_redraw()


func set_boss_telegraphs(telegraphs: Dictionary) -> void:
	_boss_telegraphs = telegraphs.duplicate(true)
	queue_redraw()


func has_active_boss_visuals() -> bool:
	return not _boss_visuals.is_empty()


func play_cell_burst(cell: Vector2i, color: Color, glyph: String = "✦") -> void:
	(
		_cell_bursts
		. append(
			{
				"cell": cell,
				"color": color,
				"glyph": glyph,
				"age": 0.0,
			}
		)
	)
	set_process(true)
	queue_redraw()


func has_active_cell_bursts() -> bool:
	return not _cell_bursts.is_empty()


func set_atmosphere_enabled(enabled: bool) -> void:
	_atmosphere_enabled = enabled
	_update_processing_state()
	queue_redraw()


func is_atmosphere_enabled() -> bool:
	return _atmosphere_enabled


func has_active_atmosphere_animation() -> bool:
	return _atmosphere_enabled and not _atmosphere_profile.is_empty()


func get_atmosphere_profile() -> Dictionary:
	return _atmosphere_profile.duplicate(true)


func _update_processing_state() -> void:
	set_process(
		(
			not _cell_bursts.is_empty()
			or not _boss_visuals.is_empty()
			or not _boss_spawn_effects.is_empty()
			or (_atmosphere_enabled and not _atmosphere_profile.is_empty())
		)
	)


# === Lifecycle Methods ===
func _ready() -> void:
	set_process(false)
	_atmosphere_profile = BiomeCatalogScript.atmosphere_for_biome_index(
		_biome_theme.get("index", 1)
	)
	_update_processing_state()


func _process(delta: float) -> void:
	_atmosphere_time += delta
	if not _boss_visuals.is_empty():
		_boss_frame_elapsed += delta
		var frame_seconds: float = _boss_visual_frame_seconds()
		if _boss_frame_elapsed >= frame_seconds:
			_boss_frame_elapsed = 0.0
			_boss_frame_index += 1
			queue_redraw()
	var spawn_effect_changed: bool = false
	for anchor_cell: Vector2i in _boss_spawn_effects.keys():
		var effect: Dictionary = _boss_spawn_effects[anchor_cell]
		effect["age"] = float(effect.get("age", 0.0)) + delta
		if float(effect["age"]) >= float(effect.get("duration", BOSS_SPAWN_INTRO_SECONDS)):
			_boss_spawn_effects.erase(anchor_cell)
		else:
			_boss_spawn_effects[anchor_cell] = effect
		spawn_effect_changed = true
	if spawn_effect_changed:
		queue_redraw()
	for index: int in range(_cell_bursts.size() - 1, -1, -1):
		_cell_bursts[index]["age"] = float(_cell_bursts[index].get("age", 0.0)) + delta
		if float(_cell_bursts[index]["age"]) >= CELL_BURST_DURATION:
			_cell_bursts.remove_at(index)
	if not _cell_bursts.is_empty():
		queue_redraw()
	if _atmosphere_enabled and not _atmosphere_profile.is_empty():
		_atmosphere_draw_time += delta
		if _atmosphere_draw_time >= 0.12:
			_atmosphere_draw_time = 0.0
			queue_redraw()
	_update_processing_state()


func _draw() -> void:
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null or _map_data.is_empty():
		return

	var ascent: float = draw_font.get_ascent(font_size)
	var viewport_size: Vector2 = get_viewport_rect().size
	var playfield_rect: Rect2 = Rect2(Vector2(10, 10), playfield_size)

	draw_rect(Rect2(Vector2.ZERO, viewport_size), _theme_color("outer_bg_tint", outer_bg_tint))
	draw_rect(playfield_rect.grow(6), _theme_color("border_color", border_color))
	draw_rect(playfield_rect.grow(2), _theme_color("border_frame_color", border_frame_color))
	draw_rect(playfield_rect, _theme_color("background_color", background_color))

	var label_color: Color = _theme_color("label_color", Color(0.6, 0.843137, 0.898039))
	var biome_name: String = str(_biome_theme.get("name", "The Tower")).to_upper()
	var floor_number: int = 1
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager != null:
		floor_number = int(game_manager.current_floor)
	var depth_label: String = "%s  //  DEPTH %02d" % [biome_name, floor_number]
	_draw_glyph(
		draw_font,
		Vector2(playfield_rect.position.x + 10, playfield_rect.position.y + ascent - 2),
		depth_label,
		label_color
	)

	for y: int in range(_map_data.size()):
		for x: int in range(_map_data[y].size()):
			var cell: Vector2i = Vector2i(x, y)
			if not _explored_cells.has(cell):
				continue
			var point: Vector2 = _cell_draw_position(cell, ascent)
			if not _is_inside_playfield(point, playfield_rect):
				continue
			var tile_type: int = _map_data[y][x]
			var is_visible: bool = _visible_cells.has(cell)
			var is_revealed_secret_wall: bool = (
				_revealed_secret_walls.has(cell) and _secret_walls.has(cell)
			)
			_draw_tile_backing(cell, tile_type, is_visible, is_revealed_secret_wall)
			_draw_glyph(
				draw_font,
				point,
				_tile_glyph(cell, tile_type, is_revealed_secret_wall),
				_tile_foreground(cell, tile_type, is_visible, is_revealed_secret_wall)
			)

	_draw_boss_room_tint(playfield_rect)

	for target_cell: Vector2i in _target_range_cells.keys():
		if not _visible_cells.has(target_cell) or not _explored_cells.has(target_cell):
			continue
		var target_point: Vector2 = _cell_draw_position(target_cell, ascent)
		if not _is_inside_playfield(target_point, playfield_rect):
			continue
		_draw_cell_highlight(
			target_cell, Color(0.42, 0.45, 0.2, 0.28), Color(0.78, 0.82, 0.32, 0.72)
		)
		_draw_glyph(draw_font, target_point, "·", Color(0.86, 0.90, 0.36, 0.95), false)

	for area_cell: Vector2i in _target_area_cells.keys():
		if not _visible_cells.has(area_cell) or not _explored_cells.has(area_cell):
			continue
		var area_point: Vector2 = _cell_draw_position(area_cell, ascent)
		if not _is_inside_playfield(area_point, playfield_rect):
			continue
		_draw_cell_highlight(area_cell, Color(1.0, 0.30, 0.08, 0.24), Color(1.0, 0.55, 0.18, 0.78))
		_draw_glyph(draw_font, area_point, "*", Color(1.0, 0.72, 0.28, 0.95), false)
	_draw_boss_telegraphs(draw_font, ascent, playfield_rect)

	for item_position: Vector2i in _items.keys():
		if not _visible_cells.has(item_position):
			continue
		if _actor_at(item_position) != null:
			continue
		var item: Resource = _items[item_position]
		var item_point: Vector2 = _cell_draw_position(item_position, ascent)
		if not _is_inside_playfield(item_point, playfield_rect):
			continue
		_draw_cell_highlight(
			item_position, Color(item.color.r, item.color.g, item.color.b, 0.18), Color(0, 0, 0, 0)
		)
		_draw_glyph(draw_font, item_point, item.glyph, item.color)

	for container_position: Vector2i in _containers.keys():
		if not _visible_cells.has(container_position):
			continue
		if _actor_at(container_position) != null:
			continue
		var container_data: Dictionary = _containers[container_position]
		var container_point: Vector2 = _cell_draw_position(container_position, ascent)
		if not _is_inside_playfield(container_point, playfield_rect):
			continue
		var container_color: Color = container_data.get("color", Color.WHITE)
		_draw_cell_highlight(
			container_position,
			Color(container_color.r, container_color.g, container_color.b, 0.18),
			Color(0, 0, 0, 0)
		)
		_draw_glyph(draw_font, container_point, container_data.get("glyph", "?"), container_color)

	_draw_cell_bursts(draw_font, ascent, playfield_rect)

	for trap_cell: Vector2i in _trap_data.keys():
		var is_revealed: bool = _revealed_traps.has(trap_cell)
		var is_triggered: bool = _triggered_traps.has(trap_cell)
		if not is_revealed and not is_triggered:
			continue
		if not _explored_cells.has(trap_cell):
			continue
		if _actor_at(trap_cell) != null:
			continue
		var trap_point: Vector2 = _cell_draw_position(trap_cell, ascent)
		if not _is_inside_playfield(trap_point, playfield_rect):
			continue
		var trap: Resource = _trap_data[trap_cell]
		var trap_color: Color = trap.color
		if not _visible_cells.has(trap_cell):
			trap_color = trap_color.darkened(0.55)
		if is_triggered:
			trap_color = Color(0.4, 0.4, 0.4)
		_draw_cell_highlight(
			trap_cell, Color(trap_color.r, trap_color.g, trap_color.b, 0.16), Color(0, 0, 0, 0)
		)
		_draw_glyph(draw_font, trap_point, trap.glyph, trap_color)

	_draw_boss_spawn_effects(draw_font, ascent, playfield_rect)
	_draw_boss_visuals(draw_font, ascent, playfield_rect)

	for actor in _actors:
		if actor == null or not actor.is_alive():
			continue
		if _boss_visuals.has(actor.grid_position):
			continue
		if not _visible_cells.has(actor.grid_position):
			continue
		var actor_point: Vector2 = _cell_draw_position(actor.grid_position, ascent)
		if not _is_inside_playfield(actor_point, playfield_rect):
			continue
		_draw_cell_highlight(
			actor.grid_position,
			Color(actor.color.r, actor.color.g, actor.color.b, 0.20),
			Color(actor.color.r, actor.color.g, actor.color.b, 0.55)
		)
		_draw_glyph(draw_font, actor_point, actor.glyph, actor.color)
	_draw_enemy_intents(draw_font, ascent, playfield_rect)

	if _targeting_active and _visible_cells.has(_target_cursor):
		var cursor_point: Vector2 = _cell_draw_position(_target_cursor, ascent)
		if _is_inside_playfield(cursor_point, playfield_rect):
			_draw_cell_highlight(
				_target_cursor, Color(1.0, 0.72, 0.08, 0.20), Color(1.0, 0.72, 0.08, 1.0)
			)
			_draw_glyph(draw_font, cursor_point, "X", Color(1.0, 0.9, 0.2, 1.0))

	if _atmosphere_enabled and not _atmosphere_profile.is_empty():
		_draw_atmosphere_effects(draw_font, ascent, playfield_rect)


func _draw_boss_room_tint(playfield_rect: Rect2) -> void:
	if _boss_room_cells.is_empty():
		return
	var fill_color: Color = (
		Color(1.0, 0.18, 0.16, 0.10) if _boss_room_locked else Color(1.0, 0.72, 0.22, 0.06)
	)
	for cell: Vector2i in _boss_room_cells.keys():
		if not _visible_cells.has(cell) and not _explored_cells.has(cell):
			continue
		var point: Vector2 = _cell_draw_position(cell, 0.0)
		if not _is_inside_playfield(point + Vector2(0, font_size), playfield_rect):
			continue
		draw_rect(_inset_cell_rect(cell, 1.0), fill_color)


func _draw_boss_telegraphs(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	for cell: Vector2i in _boss_telegraphs.keys():
		if not _visible_cells.has(cell):
			continue
		var point: Vector2 = _cell_draw_position(cell, ascent)
		if not _is_inside_playfield(point, playfield_rect):
			continue
		var payload: Dictionary = _boss_telegraphs.get(cell, {})
		var glyph: String = str(payload.get("glyph", "!"))
		var fill_color: Color = payload.get("fill_color", Color(1.0, 0.16, 0.10, 0.26))
		var border_color: Color = payload.get("border_color", Color(1.0, 0.52, 0.18, 0.78))
		var glyph_color: Color = payload.get("color", Color(1.0, 0.64, 0.20, 1.0))
		_draw_cell_highlight(cell, fill_color, border_color)
		_draw_glyph(draw_font, point, glyph, glyph_color, false)


func _draw_boss_visuals(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	for anchor_cell: Vector2i in _boss_visuals.keys():
		var visual: Dictionary = _boss_visuals[anchor_cell]
		var frames: Array = visual.get("frames", [])
		if frames.is_empty():
			continue
		var frame: PackedStringArray = frames[_boss_frame_index % frames.size()]
		var frame_height: int = frame.size()
		var frame_width: int = _boss_frame_width(frame)
		var origin: Vector2i = anchor_cell - Vector2i(int(frame_width / 2), int(frame_height / 2))
		var color: Color = visual.get("color", Color.WHITE)
		for y: int in range(frame_height):
			var row: String = frame[y]
			for x: int in range(row.length()):
				var glyph: String = row.substr(x, 1)
				if glyph == " ":
					continue
				var cell: Vector2i = origin + Vector2i(x, y)
				if not _visible_cells.has(cell):
					continue
				var point: Vector2 = _cell_draw_position(cell, ascent)
				if not _is_inside_playfield(point, playfield_rect):
					continue
				_draw_cell_highlight(
					cell, Color(color.r, color.g, color.b, 0.16), Color(0, 0, 0, 0)
				)
				_draw_glyph(draw_font, point, glyph, color)


func _draw_boss_spawn_effects(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	for anchor_cell: Vector2i in _boss_spawn_effects.keys():
		var effect: Dictionary = _boss_spawn_effects[anchor_cell]
		var age: float = float(effect.get("age", 0.0))
		var duration: float = max(0.05, float(effect.get("duration", BOSS_SPAWN_INTRO_SECONDS)))
		var progress: float = clampf(age / duration, 0.0, 1.0)
		var color: Color = effect.get("color", Color(1.0, 0.72, 0.22, 1.0))
		var cells: Array = effect.get("occupied_cells", [])
		if cells.is_empty():
			cells = [anchor_cell]
		var pulse_alpha: float = sin(progress * PI) * 0.45
		var glyphs: Array[String] = ["·", "*", "✦", "✹"]
		var glyph: String = glyphs[int(floor(progress * float(glyphs.size()))) % glyphs.size()]
		for raw_cell in cells:
			if not (raw_cell is Vector2i):
				continue
			var cell: Vector2i = raw_cell
			if not _visible_cells.has(cell):
				continue
			var point: Vector2 = _cell_draw_position(cell, ascent)
			if not _is_inside_playfield(point, playfield_rect):
				continue
			_draw_cell_highlight(
				cell,
				Color(color.r, color.g, color.b, 0.12 + pulse_alpha),
				Color(color.r, color.g, color.b, 0.30 + pulse_alpha)
			)
			_draw_glyph(draw_font, point, glyph, Color(color.r, color.g, color.b, 0.90), false)


func _boss_frame_width(frame: PackedStringArray) -> int:
	var width: int = 0
	for row: String in frame:
		width = max(width, row.length())
	return width


func _boss_visual_frame_seconds() -> float:
	for anchor_cell: Vector2i in _boss_visuals.keys():
		var visual: Dictionary = _boss_visuals[anchor_cell]
		return max(0.05, float(visual.get("frame_seconds", 0.32)))
	return 0.32


func _rebuild_boss_occupied_cells() -> void:
	_boss_occupied_cells.clear()
	for anchor_cell: Vector2i in _boss_visuals.keys():
		var visual: Dictionary = _boss_visuals[anchor_cell]
		var occupied_cells: Array = visual.get("occupied_cells", [])
		for raw_cell in occupied_cells:
			if raw_cell is Vector2i:
				_boss_occupied_cells[raw_cell] = self


func _draw_cell_bursts(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	for burst: Dictionary in _cell_bursts:
		var cell: Vector2i = burst.get("cell", Vector2i.ZERO)
		if not _visible_cells.has(cell) and not _explored_cells.has(cell):
			continue
		var progress: float = clampf(float(burst.get("age", 0.0)) / CELL_BURST_DURATION, 0.0, 1.0)
		var alpha: float = 1.0 - progress
		var color: Color = burst.get("color", Color.WHITE)
		color.a = min(color.a, alpha)
		var point: Vector2 = (
			_cell_draw_position(cell, ascent) - Vector2(0, progress * CELL_BURST_LIFT)
		)
		if not _is_inside_playfield(point, playfield_rect):
			continue
		_draw_cell_highlight(
			cell,
			Color(color.r, color.g, color.b, 0.20 * alpha),
			Color(color.r, color.g, color.b, 0.65 * alpha)
		)
		_draw_glyph(draw_font, point, burst.get("glyph", "✦"), color, false)


func _draw_enemy_intents(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	for cell: Vector2i in _enemy_intents.keys():
		if not _visible_cells.has(cell):
			continue
		var point: Vector2 = _cell_draw_position(cell, ascent)
		if not _is_inside_playfield(point, playfield_rect):
			continue
		var glyph: String = "?"
		var color: Color = Color(0.66, 0.62, 0.48)
		match _enemy_intents[cell]:
			&"melee":
				glyph = "!"
				color = Color(1.0, 0.22, 0.34)
			&"ranged":
				glyph = "→"
				color = Color(1.0, 0.68, 0.22)
			&"fireball":
				glyph = "*"
				color = Color(0.88, 0.48, 1.0)
			&"summon":
				glyph = "+"
				color = Color(0.86, 0.82, 0.70)
			&"sleeping":
				glyph = "z"
				color = Color(0.48, 0.52, 0.58)
			&"boss_attack":
				glyph = "!"
				color = Color(1.0, 0.12, 0.10)
			&"boss_windup":
				glyph = "▲"
				color = Color(1.0, 0.62, 0.18)
			&"aware":
				glyph = "?"
				color = Color(0.66, 0.62, 0.48)
		_draw_glyph(draw_font, point + Vector2(7, -8), glyph, color, false)


# === Private Methods ===
func _draw_tile_backing(
	cell: Vector2i, tile_type: int, is_visible: bool, is_revealed_secret_wall: bool
) -> void:
	var color: Color = _tile_background(tile_type)
	if is_revealed_secret_wall:
		color = Color(0.18, 0.11, 0.26)
	if not is_visible:
		color = color.darkened(0.45)
	if _atmosphere_enabled and not _atmosphere_profile.is_empty():
		var shimmer_color: Color = _atmosphere_profile.get("shimmer_color", Color(0, 0, 0, 0))
		if shimmer_color.a > 0.001:
			var shimmer_seed: float = _cell_hash(cell, 37) * 0.0001
			var shimmer_phase: float = sin(_atmosphere_time * 1.8 + shimmer_seed)
			var shimmer_t: float = (shimmer_phase * 0.5 + 0.5) * shimmer_color.a
			color = color.lerp(shimmer_color, shimmer_t)
	var cell_rect: Rect2 = _inset_cell_rect(cell, 1.0)
	draw_rect(cell_rect, color)


func _tile_background(tile_type: int) -> Color:
	var colors: Dictionary = _biome_theme.get("tile_background_colors", {})
	var fallback: Color = TILE_BACKGROUND_COLORS.get(tile_type, background_color)
	return colors.get(tile_type, fallback)


func _draw_cell_highlight(cell: Vector2i, fill_color: Color, border: Color) -> void:
	var cell_rect: Rect2 = _inset_cell_rect(cell, 1.0)
	if fill_color.a > 0.0:
		draw_rect(cell_rect, fill_color)
	if border.a > 0.0:
		draw_rect(cell_rect, border, false, 1.0)


func _draw_glyph(
	draw_font: Font, point: Vector2, glyph: String, color: Color, shadow: bool = true
) -> void:
	if shadow:
		draw_string(
			draw_font,
			point + GLYPH_SHADOW_OFFSET,
			glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0, 0, 0, min(color.a, 0.75))
		)
	draw_string(draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _theme_color(key: String, fallback: Color) -> Color:
	var color: Variant = _biome_theme.get(key, fallback)
	if color is Color:
		return color
	return fallback


func _tile_foreground(
	cell: Vector2i, tile_type: int, is_visible: bool, is_revealed_secret_wall: bool
) -> Color:
	var colors: Dictionary = _biome_theme.get("tile_foreground_colors", {})
	var fallback: Color = TILE_FOREGROUND_COLORS.get(
		tile_type, DungeonDataScript.TILE_COLORS[tile_type]
	)
	var color: Color = colors.get(tile_type, fallback)
	if is_revealed_secret_wall:
		color = _secret_wall_hint_color
	if not is_visible:
		var darken: float = 0.22 if is_revealed_secret_wall else 0.55
		if _atmosphere_enabled and not _atmosphere_profile.is_empty():
			var breathe_intensity: float = _atmosphere_profile.get("fov_breathe_intensity", 0.06)
			var breathe_speed: float = _atmosphere_profile.get("fov_breathe_speed", 1.0)
			var breathe: float = breathe_intensity * 0.5
			var phase: float = _atmosphere_time * breathe_speed + _cell_hash(cell, 73) * 0.001
			darken += sin(phase) * breathe
			darken = clampf(darken, 0.0, 0.85)
		color = color.darkened(darken)
	return color


func _tile_glyph(cell: Vector2i, tile_type: int, is_revealed_secret_wall: bool) -> String:
	if is_revealed_secret_wall:
		return SECRET_WALL_GLYPH
	if tile_type == DungeonDataScript.TileType.FLOOR:
		var floor_decoration: String = _decoration_glyph(
			cell, "floor_decoration_glyphs", "floor_decoration_chance_percent", 11
		)
		if not floor_decoration.is_empty():
			return floor_decoration
		return _themed_glyph(cell, "floor_glyphs", FLOOR_GLYPHS, 31)
	if tile_type == DungeonDataScript.TileType.WALL:
		var wall_decoration: String = _decoration_glyph(
			cell, "wall_decoration_glyphs", "wall_decoration_chance_percent", 23
		)
		if not wall_decoration.is_empty():
			return wall_decoration
		return _themed_glyph(cell, "wall_glyphs", WALL_GLYPHS, 43)
	return DungeonDataScript.TILE_CHARS[tile_type]


func _decoration_glyph(cell: Vector2i, glyph_key: String, chance_key: String, salt: int) -> String:
	var chance_percent: int = int(_biome_theme.get(chance_key, 0))
	if chance_percent <= 0:
		return ""
	if _cell_hash(cell, salt) % 100 >= chance_percent:
		return ""
	var glyphs: Array = _theme_glyphs(glyph_key, [])
	if glyphs.is_empty():
		return ""
	return str(glyphs[_cell_hash(cell, salt + 1) % glyphs.size()])


func _themed_glyph(cell: Vector2i, glyph_key: String, fallback: Array[String], salt: int) -> String:
	var glyphs: Array = _theme_glyphs(glyph_key, fallback)
	return str(glyphs[_cell_hash(cell, salt) % glyphs.size()])


func _theme_glyphs(glyph_key: String, fallback: Array) -> Array:
	var glyphs: Variant = _biome_theme.get(glyph_key, fallback)
	if glyphs is Array and not glyphs.is_empty():
		return glyphs
	return fallback


func _cell_hash(cell: Vector2i, salt: int) -> int:
	return abs(cell.x * 73856093 + cell.y * 19349663 + salt * 83492791)


func _inset_cell_rect(cell: Vector2i, inset: float) -> Rect2:
	var position: Vector2 = margin + Vector2(cell.x * cell_width, cell.y * cell_height)
	var inset_vector: Vector2 = Vector2(inset, inset)
	return Rect2(position + inset_vector, Vector2(cell_width, cell_height) - inset_vector * 2.0)


func _cell_draw_position(cell: Vector2i, ascent: float) -> Vector2:
	return margin + Vector2(cell.x * cell_width, cell.y * cell_height + ascent)


func _is_inside_playfield(point: Vector2, playfield_rect: Rect2) -> bool:
	var glyph_top_left: Vector2 = point - Vector2(0, font_size)
	var glyph_rect: Rect2 = Rect2(glyph_top_left, Vector2(cell_width, cell_height))
	return playfield_rect.encloses(glyph_rect)


func _actor_at(cell: Vector2i) -> Variant:
	if _boss_occupied_cells.has(cell):
		return _boss_occupied_cells[cell]
	for actor in _actors:
		if actor != null and actor.grid_position == cell and actor.is_alive():
			return actor
	return null


func _draw_atmosphere_effects(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	_draw_void_edge_wisps(draw_font, ascent, playfield_rect)


func _draw_void_edge_wisps(draw_font: Font, ascent: float, playfield_rect: Rect2) -> void:
	var profile: Dictionary = _atmosphere_profile
	var void_color: Color = profile.get("void_color", Color(0.12, 0.12, 0.18, 0.20))
	var intensity: float = profile.get("ambient_intensity", 0.12)
	var speed: float = profile.get("ambient_speed", 0.8)
	var void_glyph_str: String = profile.get("void_glyph", "·")
	var wisp_glyphs: Array[String] = ["·", "`", "'", ",", "."]

	for explored_cell: Vector2i in _explored_cells:
		var is_edge: bool = false
		for dx: int in [-1, 0, 1]:
			for dy: int in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var neighbor: Vector2i = explored_cell + Vector2i(dx, dy)
				if not _explored_cells.has(neighbor):
					is_edge = true
					break
			if is_edge:
				break
		if not is_edge:
			continue

		var hash_val: int = _cell_hash(explored_cell, 59)
		var wisp_phase: float = fmod(
			float(hash_val & 0xFF) / 255.0 + _atmosphere_time * speed * 0.5, 1.0
		)
		var wisp_alpha: float = sin(wisp_phase * TAU) * 0.5 + 0.5
		wisp_alpha *= intensity * 0.6
		if wisp_alpha < 0.02:
			continue

		var point: Vector2 = _cell_draw_position(explored_cell, ascent)
		var offset: Vector2 = Vector2(
			sin(_atmosphere_time * speed + float(hash_val & 0xFF)) * 1.5,
			cos(_atmosphere_time * speed * 0.7 + float((hash_val >> 8) & 0xFF)) * 1.5
		)
		if not _is_inside_playfield(point + offset, playfield_rect):
			continue

		var use_glyph: String = (
			void_glyph_str
			if _cell_hash(explored_cell, 61) % 3 == 0
			else wisp_glyphs[_cell_hash(explored_cell, 63) % wisp_glyphs.size()]
		)
		var wisp_color: Color = void_color
		wisp_color.a = clampf(wisp_alpha, 0.0, void_color.a)
		_draw_glyph(draw_font, point + offset, use_glyph, wisp_color, false)
