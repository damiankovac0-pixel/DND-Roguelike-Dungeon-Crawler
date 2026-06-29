class_name MapView
extends Node2D

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const SECRET_WALL_GLYPH: String = "?"
const FLOOR_GLYPHS: Array[String] = [".", "·", "'", "`"]
const WALL_GLYPHS: Array[String] = ["#", "▓", "▒"]
const GLYPH_SHADOW_OFFSET: Vector2 = Vector2(1, 1)
const TILE_FOREGROUND_COLORS: Dictionary = {
	DungeonDataScript.TileType.FLOOR: Color(0.72, 0.70, 0.62),
	DungeonDataScript.TileType.WALL: Color(0.42, 0.36, 0.50),
	DungeonDataScript.TileType.DOOR: Color(0.82, 0.57, 0.30),
	DungeonDataScript.TileType.OPEN_DOOR: Color(0.63, 0.52, 0.39),
	DungeonDataScript.TileType.STAIRS_DOWN: Color(1.0, 0.88, 0.47),
}
const TILE_BACKGROUND_COLORS: Dictionary = {
	DungeonDataScript.TileType.FLOOR: Color(0.06, 0.075, 0.095),
	DungeonDataScript.TileType.WALL: Color(0.105, 0.095, 0.145),
	DungeonDataScript.TileType.DOOR: Color(0.18, 0.11, 0.06),
	DungeonDataScript.TileType.OPEN_DOOR: Color(0.10, 0.085, 0.065),
	DungeonDataScript.TileType.STAIRS_DOWN: Color(0.22, 0.19, 0.05),
}

# === Exports ===
@export var font: Font
@export var font_size: int = 16
@export var cell_width: int = 14
@export var cell_height: int = 18
@export var margin: Vector2 = Vector2(20, 20)
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
var _trap_data: Dictionary = {}
var _revealed_traps: Dictionary = {}
var _triggered_traps: Dictionary = {}
var _secret_walls: Dictionary = {}
var _revealed_secret_walls: Dictionary = {}
var _secret_wall_hint_color: Color = Color(0.72, 0.58, 1.0)


# === Public Methods ===
func configure_map(map_data: Array) -> void:
	_map_data = map_data
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


func set_targeting(active: bool, cursor: Vector2i, range_cells: Dictionary) -> void:
	_targeting_active = active
	_target_cursor = cursor
	_target_range_cells = range_cells
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


# === Lifecycle Methods ===
func _draw() -> void:
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null or _map_data.is_empty():
		return

	var ascent: float = draw_font.get_ascent(font_size)
	var viewport_size: Vector2 = get_viewport_rect().size
	var playfield_rect: Rect2 = Rect2(Vector2(10, 10), playfield_size)

	draw_rect(Rect2(Vector2.ZERO, viewport_size), outer_bg_tint)
	draw_rect(playfield_rect.grow(6), border_color)
	draw_rect(playfield_rect.grow(2), border_frame_color)
	draw_rect(playfield_rect, background_color)

	var label_color: Color = Color(0.6, 0.843137, 0.898039)
	var muted_color: Color = Color(0.282353, 0.258824, 0.392157)
	_draw_glyph(
		draw_font,
		Vector2(playfield_rect.position.x + 10, playfield_rect.position.y + ascent - 2),
		"DEPTH %02d" % (GameManager.current_floor if GameManager != null else 1),
		label_color
	)
	_draw_glyph(
		draw_font,
		Vector2(playfield_rect.end.x - 126, playfield_rect.position.y + ascent - 2),
		"ASCII MODE",
		muted_color,
		false
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
				_tile_foreground(tile_type, is_visible, is_revealed_secret_wall)
			)

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

	for actor in _actors:
		if actor == null or not actor.is_alive():
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

	if _targeting_active and _visible_cells.has(_target_cursor):
		var cursor_point: Vector2 = _cell_draw_position(_target_cursor, ascent)
		if _is_inside_playfield(cursor_point, playfield_rect):
			_draw_cell_highlight(
				_target_cursor, Color(1.0, 0.72, 0.08, 0.20), Color(1.0, 0.72, 0.08, 1.0)
			)
			_draw_glyph(draw_font, cursor_point, "X", Color(1.0, 0.9, 0.2, 1.0))


# === Private Methods ===
func _draw_tile_backing(
	cell: Vector2i, tile_type: int, is_visible: bool, is_revealed_secret_wall: bool
) -> void:
	var color: Color = TILE_BACKGROUND_COLORS.get(tile_type, background_color)
	if is_revealed_secret_wall:
		color = Color(0.18, 0.11, 0.26)
	if not is_visible:
		color = color.darkened(0.45)
	var cell_rect: Rect2 = _inset_cell_rect(cell, 1.0)
	draw_rect(cell_rect, color)


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


func _tile_foreground(tile_type: int, is_visible: bool, is_revealed_secret_wall: bool) -> Color:
	var color: Color = TILE_FOREGROUND_COLORS.get(tile_type, DungeonDataScript.TILE_COLORS[tile_type])
	if is_revealed_secret_wall:
		color = _secret_wall_hint_color
	if not is_visible:
		color = color.darkened(0.22 if is_revealed_secret_wall else 0.55)
	return color


func _tile_glyph(cell: Vector2i, tile_type: int, is_revealed_secret_wall: bool) -> String:
	if is_revealed_secret_wall:
		return SECRET_WALL_GLYPH
	if tile_type == DungeonDataScript.TileType.FLOOR:
		var floor_index: int = abs(cell.x * 31 + cell.y * 17) % FLOOR_GLYPHS.size()
		return FLOOR_GLYPHS[floor_index]
	if tile_type == DungeonDataScript.TileType.WALL:
		var wall_index: int = abs(cell.x * 13 + cell.y * 19) % WALL_GLYPHS.size()
		return WALL_GLYPHS[wall_index]
	return DungeonDataScript.TILE_CHARS[tile_type]


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


func _actor_at(cell: Vector2i) -> Node2D:
	for actor in _actors:
		if actor != null and actor.grid_position == cell and actor.is_alive():
			return actor
	return null
