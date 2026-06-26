class_name MapView
extends Node2D

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")

# === Exports ===
@export var font: Font
@export var font_size: int = 16
@export var cell_width: int = 14
@export var cell_height: int = 18
@export var margin: Vector2 = Vector2(20, 20)
@export var playfield_size: Vector2 = Vector2(680, 590)
@export var border_color: Color = Color(0.15, 0.14, 0.18)
@export var border_frame_color: Color = Color(0.25, 0.24, 0.28)
@export var outer_bg_tint: Color = Color(0.12, 0.08, 0.16)
@export var background_color: Color = Color(0.08, 0.06, 0.12)
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


# === Lifecycle Methods ===
func _draw() -> void:
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null or _map_data.is_empty():
		return

	var ascent: float = draw_font.get_ascent(font_size)
	var viewport_size: Vector2 = get_viewport_rect().size
	var playfield_rect: Rect2 = Rect2(Vector2(10, 10), playfield_size)

	# Outer background with atmospheric tint
	draw_rect(Rect2(Vector2.ZERO, viewport_size), outer_bg_tint)

	# Playfield background
	draw_rect(playfield_rect, background_color)

	# Border frame around playfield
	var b: Rect2 = playfield_rect
	draw_rect(Rect2(b.position.x, b.position.y - 1, b.size.x, 1), border_frame_color)
	draw_rect(Rect2(b.position.x, b.end.y, b.size.x, 1), border_frame_color)
	draw_rect(Rect2(b.position.x - 1, b.position.y, 1, b.size.y), border_frame_color)
	draw_rect(Rect2(b.end.x, b.position.y, 1, b.size.y), border_frame_color)

	# Corner decorations
	var corner_char: String = "+"
	var corner_color: Color = Color(0.4, 0.38, 0.42)
	for corner_pos: Vector2 in [
		Vector2(b.position.x - 1, b.position.y - 1),
		Vector2(b.end.x, b.position.y - 1),
		Vector2(b.position.x - 1, b.end.y),
		Vector2(b.end.x, b.end.y),
	]:
		draw_string(
			draw_font,
			corner_pos,
			corner_char,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			corner_color
		)

	# Floor label overlay at top-left of playfield
	var floor_number: int = GameManager.current_floor if GameManager != null else 1
	draw_string(
		draw_font,
		Vector2(b.position.x + 2, b.position.y + ascent - 2),
		"Depth %d" % floor_number,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.25, 0.22, 0.28)
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
			var color: Color = DungeonDataScript.TILE_COLORS[tile_type]
			if not _visible_cells.has(cell):
				color = color.darkened(0.55)
			draw_string(
				draw_font,
				point,
				DungeonDataScript.TILE_CHARS[tile_type],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				color
			)

	for item_position: Vector2i in _items.keys():
		if not _visible_cells.has(item_position):
			continue
		if _actor_at(item_position) != null:
			continue
		var item: Resource = _items[item_position]
		var item_point: Vector2 = _cell_draw_position(item_position, ascent)
		if not _is_inside_playfield(item_point, playfield_rect):
			continue
		draw_string(
			draw_font, item_point, item.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, item.color
		)


	for container_position: Vector2i in _containers.keys():
		if not _visible_cells.has(container_position):
			continue
		if _actor_at(container_position) != null:
			continue
		var container_data: Dictionary = _containers[container_position]
		var container_point: Vector2 = _cell_draw_position(container_position, ascent)
		if not _is_inside_playfield(container_point, playfield_rect):
			continue
		draw_string(
			draw_font,
			container_point,
			container_data.get("glyph", "?"),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			container_data.get("color", Color.WHITE)
		)
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
		draw_string(
			draw_font, trap_point, trap.glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, trap_color
		)

	for target_cell: Vector2i in _target_range_cells.keys():
		if not _visible_cells.has(target_cell) or not _explored_cells.has(target_cell):
			continue
		var target_point: Vector2 = _cell_draw_position(target_cell, ascent)
		if not _is_inside_playfield(target_point, playfield_rect):
			continue
		draw_string(
			draw_font,
			target_point,
			"·",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(0.42, 0.45, 0.2, 0.75)
		)

	for actor in _actors:
		if actor == null or not actor.is_alive():
			continue
		if not _visible_cells.has(actor.grid_position):
			continue
		var actor_point: Vector2 = _cell_draw_position(actor.grid_position, ascent)
		if not _is_inside_playfield(actor_point, playfield_rect):
			continue
		draw_string(
			draw_font,
			actor_point,
			actor.glyph,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			actor.color
		)

	if _targeting_active and _visible_cells.has(_target_cursor):
		var cursor_point: Vector2 = _cell_draw_position(_target_cursor, ascent)
		if _is_inside_playfield(cursor_point, playfield_rect):
			draw_string(
				draw_font,
				cursor_point,
				"X",
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				Color(1.0, 0.9, 0.2, 1.0)
			)


# === Private Methods ===
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
