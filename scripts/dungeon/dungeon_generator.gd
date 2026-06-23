class_name DungeonGenerator
extends RefCounted

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const MIN_LEAF_SIZE: int = 10
const MIN_ROOM_SIZE: int = 5
const MAX_DEPTH: int = 4
const TRAP_CHANCE: float = 0.3


# === Public Methods ===
func generate(width: int, height: int, floor_number: int) -> Dictionary:
	var map_data: Array = _create_filled_map(width, height, DungeonDataScript.TileType.WALL)
	var rooms: Array[Rect2i] = []
	var leaves: Array[Rect2i] = []
	_split_leaf(Rect2i(1, 1, width - 2, height - 2), 0, leaves)
	for leaf: Rect2i in leaves:
		var room: Rect2i = _create_room_in_leaf(leaf)
		if room.size.x > 0 and room.size.y > 0:
			rooms.append(room)
			_carve_room(map_data, room)
	for i: int in range(1, rooms.size()):
		_connect_rooms(map_data, rooms[i - 1], rooms[i])

	var player_start: Vector2i = rooms[0].get_center()
	var stairs_position: Vector2i = rooms[rooms.size() - 1].get_center()
	map_data[stairs_position.y][stairs_position.x] = DungeonDataScript.TileType.STAIRS_DOWN

	var enemy_spawns: Array[Vector2i] = []
	var item_spawns: Array[Vector2i] = []
	var occupied_spawns: Dictionary = {
		player_start: true,
		stairs_position: true,
	}
	for room_index: int in range(1, rooms.size()):
		var room_center: Vector2i = rooms[room_index].get_center()
		if room_center != stairs_position:
			_add_spawn_if_free(enemy_spawns, occupied_spawns, room_center)
		if room_index % 2 == 0:
			_add_spawn_if_free(
				item_spawns, occupied_spawns, Vector2i(room_center.x + 1, room_center.y)
			)

	if rooms.size() > 1:
		var extra_enemy_attempts: int = floor_number + 2
		for attempt: int in range(extra_enemy_attempts):
			var room: Rect2i = rooms[randi_range(1, rooms.size() - 1)]
			_add_spawn_if_free(enemy_spawns, occupied_spawns, _random_cell_in_room(room))
	enemy_spawns.shuffle()
	var trap_spawns: Array[Vector2i] = []
	for room_index: int in range(1, rooms.size()):
		var room: Rect2i = rooms[room_index]
		var room_center: Vector2i = room.get_center()
		if room_center == stairs_position:
			continue
		if room_index == 1 and randf() > 0.4:
			continue
		if randf() < TRAP_CHANCE:
			var trap_cell: Vector2i = _random_cell_in_room(room)
			if not occupied_spawns.has(trap_cell):
				occupied_spawns[trap_cell] = true
				trap_spawns.append(trap_cell)
		if room_index == 1 and trap_spawns.is_empty() and randf() < 0.5:
			var trap_cell: Vector2i = _random_cell_in_room(room)
			if not occupied_spawns.has(trap_cell):
				occupied_spawns[trap_cell] = true
				trap_spawns.append(trap_cell)
	trap_spawns.shuffle()
	var trap_limit: int = min(trap_spawns.size(), 2 + floor_number)
	var enemy_limit: int = min(enemy_spawns.size(), 6 + floor_number + int(floor_number / 2))
	var item_limit: int = min(item_spawns.size(), 2 + int(floor_number / 3))
	return {
		"map": map_data,
		"rooms": rooms,
		"player_start": player_start,
		"stairs_position": stairs_position,
		"enemy_spawns": enemy_spawns.slice(0, enemy_limit),
		"item_spawns": item_spawns.slice(0, item_limit),
		"trap_spawns": trap_spawns.slice(0, trap_limit),
	}


# === Private Methods ===
func _create_filled_map(width: int, height: int, tile_type: int) -> Array:
	var rows: Array = []
	for y: int in range(height):
		var row: Array[int] = []
		for x: int in range(width):
			row.append(tile_type)
		rows.append(row)
	return rows


func _split_leaf(rect: Rect2i, depth: int, leaves: Array[Rect2i]) -> void:
	if depth >= MAX_DEPTH or rect.size.x < MIN_LEAF_SIZE * 2 or rect.size.y < MIN_LEAF_SIZE * 2:
		leaves.append(rect)
		return

	var split_horizontally: bool = rect.size.y > rect.size.x
	if rect.size.x > rect.size.y and rect.size.x / float(rect.size.y) >= 1.25:
		split_horizontally = false

	if split_horizontally:
		var split_y: int = randi_range(rect.position.y + MIN_LEAF_SIZE, rect.end.y - MIN_LEAF_SIZE)
		_split_leaf(
			Rect2i(rect.position, Vector2i(rect.size.x, split_y - rect.position.y)),
			depth + 1,
			leaves
		)
		_split_leaf(
			Rect2i(Vector2i(rect.position.x, split_y), Vector2i(rect.size.x, rect.end.y - split_y)),
			depth + 1,
			leaves
		)
	else:
		var split_x: int = randi_range(rect.position.x + MIN_LEAF_SIZE, rect.end.x - MIN_LEAF_SIZE)
		_split_leaf(
			Rect2i(rect.position, Vector2i(split_x - rect.position.x, rect.size.y)),
			depth + 1,
			leaves
		)
		_split_leaf(
			Rect2i(Vector2i(split_x, rect.position.y), Vector2i(rect.end.x - split_x, rect.size.y)),
			depth + 1,
			leaves
		)


func _create_room_in_leaf(leaf: Rect2i) -> Rect2i:
	var room_width: int = randi_range(MIN_ROOM_SIZE, max(MIN_ROOM_SIZE, leaf.size.x - 2))
	var room_height: int = randi_range(MIN_ROOM_SIZE, max(MIN_ROOM_SIZE, leaf.size.y - 2))
	var room_x: int = randi_range(leaf.position.x, leaf.end.x - room_width)
	var room_y: int = randi_range(leaf.position.y, leaf.end.y - room_height)
	return Rect2i(room_x, room_y, room_width, room_height)


func _random_cell_in_room(room: Rect2i) -> Vector2i:
	var min_x: int = room.position.x + 1
	var max_x: int = room.end.x - 2
	var min_y: int = room.position.y + 1
	var max_y: int = room.end.y - 2
	if min_x > max_x or min_y > max_y:
		return room.get_center()
	return Vector2i(randi_range(min_x, max_x), randi_range(min_y, max_y))


func _add_spawn_if_free(
	spawns: Array[Vector2i], occupied_spawns: Dictionary, cell: Vector2i
) -> void:
	if occupied_spawns.has(cell):
		return
	occupied_spawns[cell] = true
	spawns.append(cell)


func _carve_room(map_data: Array, room: Rect2i) -> void:
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			map_data[y][x] = DungeonDataScript.TileType.FLOOR


func _connect_rooms(map_data: Array, room_a: Rect2i, room_b: Rect2i) -> void:
	var point_a: Vector2i = room_a.get_center()
	var point_b: Vector2i = room_b.get_center()
	if randf() < 0.5:
		_carve_hallway_horizontal(map_data, point_a.x, point_b.x, point_a.y)
		_carve_hallway_vertical(map_data, point_a.y, point_b.y, point_b.x)
	else:
		_carve_hallway_vertical(map_data, point_a.y, point_b.y, point_a.x)
		_carve_hallway_horizontal(map_data, point_a.x, point_b.x, point_b.y)


func _carve_hallway_horizontal(map_data: Array, from_x: int, to_x: int, y: int) -> void:
	for x: int in range(min(from_x, to_x), max(from_x, to_x) + 1):
		map_data[y][x] = DungeonDataScript.TileType.FLOOR


func _carve_hallway_vertical(map_data: Array, from_y: int, to_y: int, x: int) -> void:
	for y: int in range(min(from_y, to_y), max(from_y, to_y) + 1):
		map_data[y][x] = DungeonDataScript.TileType.FLOOR
