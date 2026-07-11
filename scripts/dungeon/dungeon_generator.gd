## BSP dungeon generator producing rooms, corridors, spawns, traps, and secret rooms.
class_name DungeonGenerator
extends RefCounted

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const MIN_LEAF_SIZE: int = 10
const MIN_ROOM_SIZE: int = 5
const MAX_DEPTH: int = 4
const TRAP_CHANCE: float = 0.3
const DOOR_KEEP_RATIO: float = 0.40
const MIN_DOORS_PER_LEVEL: int = 1
const DOOR_CORRIDOR_PAIR_BLOCK_DISTANCE: int = 7
const SECRET_ROOM_MIN_FLOOR: int = 2
const SECRET_ROOM_CHANCE: float = 0.50
const SECRET_ROOM_GUARANTEE_INTERVAL: int = 4
const SECRET_ROOM_MIN_SIZE: int = 3
const SECRET_ROOM_MAX_SIZE: int = 4
const SECRET_WALL_HP: int = 2
const SECRET_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
]
const BOSS_FLOORS: Array[int] = [5, 10, 15, 20, 25]
const BOSS_ARENA_SIZE: Vector2i = Vector2i(15, 13)
const BOSS_ARENA_MARGIN: int = 2
const BOSS_ARENA_MOAT_WIDTH: int = 1


# === Public Methods ===
func generate(width: int, height: int, floor_number: int) -> Dictionary:
	var map_data: Array = _create_filled_map(width, height, DungeonDataScript.TileType.WALL)
	var rooms: Array[Rect2i] = []
	var leaves: Array[Rect2i] = []
	_split_leaf(_normal_generation_rect(width, height, floor_number), 0, leaves)
	for leaf: Rect2i in leaves:
		var room: Rect2i = _create_room_in_leaf(leaf)
		if room.size.x > 0 and room.size.y > 0:
			rooms.append(room)
			_carve_room(map_data, room)
	for i: int in range(1, rooms.size()):
		_connect_rooms(map_data, rooms[i - 1], rooms[i])
	_place_room_doors(map_data, rooms)

	var player_start: Vector2i = rooms[0].get_center()
	var boss_encounter: Dictionary = {"active": false}
	var boss_room: Rect2i = Rect2i()
	var boss_spawn_cell: Vector2i = Vector2i.ZERO
	var boss_stairs_cell: Vector2i = rooms[rooms.size() - 1].get_center()
	var boss_chest_cell: Vector2i = Vector2i.ZERO
	if _is_boss_floor(floor_number):
		boss_room = _boss_arena_rect(width, height)
		_carve_room(map_data, boss_room)
		_enforce_boss_arena_moat(map_data, boss_room)
		boss_spawn_cell = boss_room.get_center()
		var boss_entry_cell: Vector2i = Vector2i(boss_room.position.x + 1, boss_spawn_cell.y)
		boss_stairs_cell = _find_boss_room_reward_cell(boss_room, boss_spawn_cell, Vector2i.RIGHT)
		boss_chest_cell = _find_boss_room_reward_cell(boss_room, boss_spawn_cell, Vector2i.LEFT)
		var boss_gate_cell: Vector2i = _place_boss_gate(map_data, rooms)
		var boss_gate_entry_cell: Vector2i = _find_boss_gate_stand_cell(map_data, boss_gate_cell)
		var boss_door_cells: Array[Vector2i] = []
		if boss_gate_cell != Vector2i.ZERO:
			boss_door_cells.append(boss_gate_cell)
		var boss_room_cells: Dictionary = _room_floor_cells(map_data, boss_room)
		var boss_arena_view_cells: Dictionary = _boss_arena_view_cells(map_data, boss_room)
		boss_encounter = {
			"active": true,
			"boss_floor": floor_number,
			"boss_room": boss_room,
			"boss_arena": boss_room,
			"boss_room_cells": boss_room_cells,
			"boss_arena_cells": boss_room_cells,
			"boss_arena_view_cells": boss_arena_view_cells,
			"boss_door_cells": boss_door_cells,
			"boss_gate_cell": boss_gate_cell,
			"boss_gate_entry_cell": boss_gate_entry_cell,
			"boss_entry_cell": boss_entry_cell,
			"boss_spawn_cell": boss_spawn_cell,
			"boss_stairs_cell": boss_stairs_cell,
			"boss_chest_cell": boss_chest_cell,
			"boss_arena_isolated": true,
		}

	var stairs_position: Vector2i = boss_stairs_cell
	if not bool(boss_encounter.get("active", false)):
		stairs_position = rooms[rooms.size() - 1].get_center()
		map_data[stairs_position.y][stairs_position.x] = DungeonDataScript.TileType.STAIRS_DOWN

	var enemy_spawns: Array[Vector2i] = []
	var item_spawns: Array[Vector2i] = []
	var occupied_spawns: Dictionary = {
		player_start: true,
		stairs_position: true,
	}
	if bool(boss_encounter.get("active", false)):
		occupied_spawns[boss_spawn_cell] = true
		occupied_spawns[boss_stairs_cell] = true
		occupied_spawns[boss_chest_cell] = true
	for room_index: int in range(1, rooms.size()):
		var room_center: Vector2i = rooms[room_index].get_center()
		if room_center != stairs_position:
			_add_spawn_if_free(enemy_spawns, occupied_spawns, room_center)
		if room_index % 2 == 0:
			_add_spawn_if_free(
				item_spawns, occupied_spawns, Vector2i(room_center.x + 1, room_center.y)
			)

	var spawn_room_indices: Array[int] = []
	for room_index: int in range(1, rooms.size()):
		spawn_room_indices.append(room_index)
	if not spawn_room_indices.is_empty():
		var extra_enemy_attempts: int = 2 + int(floor_number * 0.45)
		if floor_number >= 10:
			extra_enemy_attempts = 6 + int((floor_number - 10) * 0.35)
		for attempt: int in range(extra_enemy_attempts):
			var room: Rect2i = rooms[spawn_room_indices[randi_range(
				0, spawn_room_indices.size() - 1
			)]]
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
	var enemy_limit: int = min(enemy_spawns.size(), 5 + int(floor_number * 0.7))
	if floor_number >= 10:
		enemy_limit = min(enemy_spawns.size(), 12 + int((floor_number - 10) * 0.5))
	var item_limit: int = min(item_spawns.size(), 2 + int(floor_number / 3))
	var reserved_boss_room: Rect2i = boss_room
	if bool(boss_encounter.get("active", false)):
		reserved_boss_room = _boss_arena_moat_rect(boss_room)
	var secret_data: Dictionary = _generate_secret_room(
		map_data, rooms, occupied_spawns, floor_number, reserved_boss_room
	)
	return {
		"map": map_data,
		"rooms": rooms,
		"player_start": player_start,
		"stairs_position": stairs_position,
		"enemy_spawns": enemy_spawns.slice(0, enemy_limit),
		"item_spawns": item_spawns.slice(0, item_limit),
		"trap_spawns": trap_spawns.slice(0, trap_limit),
		"secret_walls": secret_data.get("secret_walls", {}),
		"secret_containers": secret_data.get("secret_containers", []),
		"secret_floor_cells": secret_data.get("secret_floor_cells", []),
		"boss_encounter": boss_encounter,
	}


func _is_boss_floor(floor_number: int) -> bool:
	return BOSS_FLOORS.has(floor_number)


func _normal_generation_rect(width: int, height: int, floor_number: int) -> Rect2i:
	if not _is_boss_floor(floor_number):
		return Rect2i(1, 1, width - 2, height - 2)
	var arena: Rect2i = _boss_arena_rect(width, height)
	var max_normal_width: int = arena.position.x - BOSS_ARENA_MOAT_WIDTH - 1
	return Rect2i(1, 1, max(1, max_normal_width), height - 2)


func _boss_arena_rect(width: int, height: int) -> Rect2i:
	var min_arena_x: int = 1 + MIN_LEAF_SIZE + BOSS_ARENA_MOAT_WIDTH
	var max_arena_width: int = max(MIN_ROOM_SIZE, width - min_arena_x - 1)
	var arena_width: int = min(BOSS_ARENA_SIZE.x, max_arena_width)
	var arena_height: int = min(
		BOSS_ARENA_SIZE.y, max(MIN_ROOM_SIZE, height - BOSS_ARENA_MARGIN * 2)
	)
	var max_arena_x: int = max(BOSS_ARENA_MARGIN, width - arena_width - 1)
	var preferred_arena_x: int = max(BOSS_ARENA_MARGIN, width - arena_width - BOSS_ARENA_MARGIN)
	var arena_x: int = clampi(preferred_arena_x, min(min_arena_x, max_arena_x), max_arena_x)
	var arena_y: int = clampi(
		int(floor(float(height - arena_height) / 2.0)),
		BOSS_ARENA_MARGIN,
		max(BOSS_ARENA_MARGIN, height - arena_height - BOSS_ARENA_MARGIN)
	)
	return Rect2i(arena_x, arena_y, arena_width, arena_height)


func _place_boss_gate(map_data: Array, rooms: Array[Rect2i]) -> Vector2i:
	if rooms.is_empty():
		return Vector2i.ZERO
	var gate_room: Rect2i = rooms[rooms.size() - 1]
	var previous_center: Vector2i = gate_room.get_center()
	if rooms.size() >= 2:
		previous_center = rooms[rooms.size() - 2].get_center()
	var gate_cell: Vector2i = _find_existing_gate_room_door(map_data, gate_room, previous_center)
	if gate_cell == Vector2i.ZERO:
		gate_cell = _find_gate_room_corridor_cell(map_data, gate_room, previous_center)
	if gate_cell == Vector2i.ZERO:
		gate_cell = _find_gate_room_interior_cell(map_data, gate_room)
	if gate_cell != Vector2i.ZERO:
		map_data[gate_cell.y][gate_cell.x] = DungeonDataScript.TileType.BOSS_DOOR
	return gate_cell


func _find_existing_gate_room_door(
	map_data: Array, gate_room: Rect2i, previous_center: Vector2i
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for direction: Vector2i in SECRET_DIRECTIONS:
		for edge_cell: Vector2i in _room_edge_cells(gate_room, direction):
			var door_cell: Vector2i = edge_cell + direction
			if not _is_inside_map(map_data, door_cell):
				continue
			if map_data[door_cell.y][door_cell.x] == DungeonDataScript.TileType.DOOR:
				candidates.append(door_cell)
	return _closest_cell(candidates, previous_center)


func _find_gate_room_corridor_cell(
	map_data: Array, gate_room: Rect2i, previous_center: Vector2i
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for direction: Vector2i in SECRET_DIRECTIONS:
		for edge_cell: Vector2i in _room_edge_cells(gate_room, direction):
			var corridor_cell: Vector2i = edge_cell + direction
			if not _is_inside_map(map_data, corridor_cell):
				continue
			if map_data[edge_cell.y][edge_cell.x] != DungeonDataScript.TileType.FLOOR:
				continue
			if map_data[corridor_cell.y][corridor_cell.x] == DungeonDataScript.TileType.FLOOR:
				candidates.append(corridor_cell)
	return _closest_cell(candidates, previous_center)


func _find_gate_room_interior_cell(map_data: Array, gate_room: Rect2i) -> Vector2i:
	var room_center: Vector2i = gate_room.get_center()
	var candidates: Array[Vector2i] = []
	for y: int in range(gate_room.position.y + 1, gate_room.end.y - 1):
		for x: int in range(gate_room.position.x + 1, gate_room.end.x - 1):
			var cell: Vector2i = Vector2i(x, y)
			if map_data[cell.y][cell.x] == DungeonDataScript.TileType.FLOOR:
				candidates.append(cell)
	if candidates.is_empty():
		return Vector2i.ZERO
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if a.x == b.x:
				return abs(a.y - room_center.y) < abs(b.y - room_center.y)
			return a.x > b.x
	)
	return candidates[0]


func _closest_cell(candidates: Array[Vector2i], target: Vector2i) -> Vector2i:
	if candidates.is_empty():
		return Vector2i.ZERO
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.distance_squared_to(target) < b.distance_squared_to(target)
	)
	return candidates[0]


func _find_boss_gate_stand_cell(map_data: Array, gate_cell: Vector2i) -> Vector2i:
	if gate_cell == Vector2i.ZERO:
		return Vector2i.ZERO
	for direction: Vector2i in SECRET_DIRECTIONS:
		var neighbor: Vector2i = gate_cell + direction
		if not _is_inside_map(map_data, neighbor):
			continue
		if map_data[neighbor.y][neighbor.x] == DungeonDataScript.TileType.FLOOR:
			return neighbor
	return Vector2i.ZERO


func _room_floor_cells(map_data: Array, room: Rect2i) -> Dictionary:
	var cells: Dictionary = {}
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if map_data[y][x] == DungeonDataScript.TileType.FLOOR:
				cells[cell] = true
	return cells


func _boss_arena_moat_rect(arena: Rect2i) -> Rect2i:
	if arena.size.x <= 0 or arena.size.y <= 0:
		return Rect2i()
	return Rect2i(
		arena.position - Vector2i(BOSS_ARENA_MOAT_WIDTH, BOSS_ARENA_MOAT_WIDTH),
		arena.size + Vector2i(BOSS_ARENA_MOAT_WIDTH * 2, BOSS_ARENA_MOAT_WIDTH * 2)
	)


func _boss_arena_view_cells(map_data: Array, arena: Rect2i) -> Dictionary:
	var cells: Dictionary = {}
	for y: int in range(
		arena.position.y - BOSS_ARENA_MOAT_WIDTH, arena.end.y + BOSS_ARENA_MOAT_WIDTH
	):
		for x: int in range(
			arena.position.x - BOSS_ARENA_MOAT_WIDTH, arena.end.x + BOSS_ARENA_MOAT_WIDTH
		):
			var cell: Vector2i = Vector2i(x, y)
			if _is_cell_in_map_bounds(map_data, cell):
				cells[cell] = true
	return cells


func _enforce_boss_arena_moat(map_data: Array, arena: Rect2i) -> void:
	for y: int in range(
		arena.position.y - BOSS_ARENA_MOAT_WIDTH, arena.end.y + BOSS_ARENA_MOAT_WIDTH
	):
		for x: int in range(
			arena.position.x - BOSS_ARENA_MOAT_WIDTH, arena.end.x + BOSS_ARENA_MOAT_WIDTH
		):
			var cell: Vector2i = Vector2i(x, y)
			if not _is_cell_in_map_bounds(map_data, cell):
				continue
			if _room_contains_cell(arena, cell):
				continue
			map_data[y][x] = DungeonDataScript.TileType.WALL


func _room_contains_cell(room: Rect2i, cell: Vector2i) -> bool:
	return (
		cell.x >= room.position.x
		and cell.x < room.end.x
		and cell.y >= room.position.y
		and cell.y < room.end.y
	)


func _find_boss_room_reward_cell(
	room: Rect2i, boss_spawn_cell: Vector2i, direction: Vector2i
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y: int in range(room.position.y + 1, room.end.y - 1):
		for x: int in range(room.position.x + 1, room.end.x - 1):
			var cell: Vector2i = Vector2i(x, y)
			if cell == boss_spawn_cell:
				continue
			var offset: Vector2i = cell - boss_spawn_cell
			if direction.x != 0 and offset.x * direction.x <= 0:
				continue
			if direction.y != 0 and offset.y * direction.y <= 0:
				continue
			candidates.append(cell)
	if candidates.is_empty():
		return boss_spawn_cell
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var a_offset: Vector2i = a - boss_spawn_cell
			var b_offset: Vector2i = b - boss_spawn_cell
			var a_axis: int = abs(a_offset.x * direction.x + a_offset.y * direction.y)
			var b_axis: int = abs(b_offset.x * direction.x + b_offset.y * direction.y)
			if a_axis == b_axis:
				return (
					a.distance_squared_to(boss_spawn_cell) < b.distance_squared_to(boss_spawn_cell)
				)
			return a_axis > b_axis
	)
	return candidates[0]


func _generate_secret_room(
	map_data: Array,
	rooms: Array[Rect2i],
	_occupied_spawns: Dictionary,
	floor_number: int,
	reserved_room: Rect2i = Rect2i()
) -> Dictionary:
	var result: Dictionary = {
		"secret_walls": {},
		"secret_containers": [],
		"secret_floor_cells": [],
	}
	if floor_number < SECRET_ROOM_MIN_FLOOR or rooms.is_empty():
		return result
	var should_generate: bool = (
		randf() <= SECRET_ROOM_CHANCE or floor_number % SECRET_ROOM_GUARANTEE_INTERVAL == 0
	)
	if not should_generate:
		return result
	var candidates: Array[Dictionary] = _get_secret_room_candidates(rooms)
	candidates.shuffle()
	for candidate: Dictionary in candidates:
		var direction: Vector2i = candidate["direction"]
		var entrance_floor: Vector2i = candidate["entrance_floor"]
		var wall_cell: Vector2i = candidate["wall_cell"]
		var secret_room: Rect2i = _secret_room_rect_from_wall(wall_cell, direction)
		if _room_overlaps_reserved_room(secret_room, reserved_room):
			return result
		if not _can_place_secret_room(map_data, secret_room, wall_cell, entrance_floor):
			continue
		_carve_room(map_data, secret_room)
		_add_secret_floor_cells(result["secret_floor_cells"], secret_room)
		result["secret_walls"][wall_cell] = {"hp": SECRET_WALL_HP}
		_add_secret_containers(result["secret_containers"], secret_room, floor_number)
		return result
	return result


func _get_secret_room_candidates(rooms: Array[Rect2i]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for room: Rect2i in rooms:
		for direction: Vector2i in SECRET_DIRECTIONS:
			for entrance_floor: Vector2i in _room_edge_cells(room, direction):
				(
					candidates
					. append(
						{
							"direction": direction,
							"entrance_floor": entrance_floor,
							"wall_cell": entrance_floor + direction,
						}
					)
				)
	return candidates


func _room_edge_cells(room: Rect2i, direction: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if direction == Vector2i.RIGHT or direction == Vector2i.LEFT:
		var x: int = room.end.x - 1 if direction == Vector2i.RIGHT else room.position.x
		for y: int in range(room.position.y + 1, room.end.y - 1):
			cells.append(Vector2i(x, y))
		return cells
	var y: int = room.end.y - 1 if direction == Vector2i.DOWN else room.position.y
	for x: int in range(room.position.x + 1, room.end.x - 1):
		cells.append(Vector2i(x, y))
	return cells


func _secret_room_rect_from_wall(wall_cell: Vector2i, direction: Vector2i) -> Rect2i:
	var room_size: Vector2i = Vector2i(
		randi_range(SECRET_ROOM_MIN_SIZE, SECRET_ROOM_MAX_SIZE),
		randi_range(SECRET_ROOM_MIN_SIZE, SECRET_ROOM_MAX_SIZE)
	)
	if direction == Vector2i.RIGHT:
		return Rect2i(wall_cell.x + 1, wall_cell.y - int(room_size.y / 2), room_size.x, room_size.y)
	if direction == Vector2i.LEFT:
		return Rect2i(
			wall_cell.x - room_size.x, wall_cell.y - int(room_size.y / 2), room_size.x, room_size.y
		)
	if direction == Vector2i.DOWN:
		return Rect2i(wall_cell.x - int(room_size.x / 2), wall_cell.y + 1, room_size.x, room_size.y)
	return Rect2i(
		wall_cell.x - int(room_size.x / 2), wall_cell.y - room_size.y, room_size.x, room_size.y
	)


func _room_overlaps_reserved_room(room: Rect2i, reserved_room: Rect2i) -> bool:
	if reserved_room.size.x <= 0 or reserved_room.size.y <= 0:
		return false
	return room.intersects(reserved_room)


func _can_place_secret_room(
	map_data: Array, room: Rect2i, wall_cell: Vector2i, entrance_floor: Vector2i
) -> bool:
	if not _is_inside_map(map_data, wall_cell) or not _is_inside_map(map_data, entrance_floor):
		return false
	if map_data[wall_cell.y][wall_cell.x] != DungeonDataScript.TileType.WALL:
		return false
	if not DungeonDataScript.is_walkable(map_data[entrance_floor.y][entrance_floor.x]):
		return false
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if not _is_inside_map(map_data, cell):
				return false
			if map_data[y][x] != DungeonDataScript.TileType.WALL:
				return false
			for direction: Vector2i in SECRET_DIRECTIONS:
				var neighbor: Vector2i = cell + direction
				if neighbor == wall_cell:
					continue
				if (
					_is_inside_map(map_data, neighbor)
					and DungeonDataScript.is_walkable(map_data[neighbor.y][neighbor.x])
				):
					return false
	return true


func _add_secret_floor_cells(secret_floor_cells: Array, room: Rect2i) -> void:
	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			secret_floor_cells.append(Vector2i(x, y))


func _add_secret_containers(secret_containers: Array, room: Rect2i, floor_number: int) -> void:
	var used_cells: Dictionary = {}
	var chest_cell: Vector2i = room.get_center()
	(
		secret_containers
		. append(
			{
				"cell": chest_cell,
				"type": &"chest",
				"rarity": min(int(floor_number / 4), 3),
			}
		)
	)
	used_cells[chest_cell] = true
	for _index: int in range(randi_range(1, 2)):
		var clutter_cell: Vector2i = _random_cell_in_room(room)
		if used_cells.has(clutter_cell):
			continue
		(
			secret_containers
			. append(
				{
					"cell": clutter_cell,
					"type": &"clutter",
				}
			)
		)
		used_cells[clutter_cell] = true


func _is_cell_in_map_bounds(map_data: Array, cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < map_data.size() and cell.x >= 0 and cell.x < map_data[0].size()


func _is_inside_map(map_data: Array, cell: Vector2i) -> bool:
	return (
		cell.y > 0
		and cell.y < map_data.size() - 1
		and cell.x > 0
		and cell.x < map_data[0].size() - 1
	)


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


func _place_room_doors(map_data: Array, rooms: Array[Rect2i]) -> void:
	var candidates: Array[Dictionary] = _collect_room_door_candidates(map_data, rooms)
	if candidates.is_empty():
		return
	candidates.shuffle()
	var target_count: int = max(
		MIN_DOORS_PER_LEVEL, int(round(candidates.size() * DOOR_KEEP_RATIO))
	)
	target_count = min(target_count, candidates.size())
	var placed: int = 0
	for candidate: Dictionary in candidates:
		if placed >= target_count:
			return
		var door_cell: Vector2i = candidate["door_cell"]
		var outward: Vector2i = candidate["outward"]
		if _has_adjacent_door(map_data, door_cell):
			continue
		if _has_corridor_run_door(map_data, door_cell, outward):
			continue
		map_data[door_cell.y][door_cell.x] = DungeonDataScript.TileType.DOOR
		placed += 1
	if placed == 0:
		_place_fallback_door(map_data, candidates)


func _collect_room_door_candidates(map_data: Array, rooms: Array[Rect2i]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for room: Rect2i in rooms:
		for x: int in range(room.position.x + 1, room.end.x - 1):
			_append_room_door_candidate(
				candidates, map_data, rooms, Vector2i(x, room.position.y), Vector2i.UP
			)
			_append_room_door_candidate(
				candidates, map_data, rooms, Vector2i(x, room.end.y - 1), Vector2i.DOWN
			)
		for y: int in range(room.position.y + 1, room.end.y - 1):
			_append_room_door_candidate(
				candidates, map_data, rooms, Vector2i(room.position.x, y), Vector2i.LEFT
			)
			_append_room_door_candidate(
				candidates, map_data, rooms, Vector2i(room.end.x - 1, y), Vector2i.RIGHT
			)
	return candidates


func _append_room_door_candidate(
	candidates: Array[Dictionary],
	map_data: Array,
	rooms: Array[Rect2i],
	room_edge_cell: Vector2i,
	outward: Vector2i
) -> void:
	if not _is_valid_room_door_candidate(map_data, rooms, room_edge_cell, outward):
		return
	candidates.append({"door_cell": room_edge_cell + outward, "outward": outward})


func _is_valid_room_door_candidate(
	map_data: Array, rooms: Array[Rect2i], room_edge_cell: Vector2i, outward: Vector2i
) -> bool:
	var door_cell: Vector2i = room_edge_cell + outward
	var corridor_cell: Vector2i = door_cell + outward
	var room_inside_cell: Vector2i = room_edge_cell - outward
	if (
		not _is_inside_map(map_data, door_cell)
		or not _is_inside_map(map_data, corridor_cell)
		or not _is_inside_map(map_data, room_inside_cell)
	):
		return false
	return (
		map_data[room_edge_cell.y][room_edge_cell.x] == DungeonDataScript.TileType.FLOOR
		and map_data[room_inside_cell.y][room_inside_cell.x] == DungeonDataScript.TileType.FLOOR
		and map_data[door_cell.y][door_cell.x] == DungeonDataScript.TileType.FLOOR
		and map_data[corridor_cell.y][corridor_cell.x] == DungeonDataScript.TileType.FLOOR
		and not _is_room_cell(rooms, door_cell)
		and not _is_room_cell(rooms, corridor_cell)
	)


func _place_fallback_door(map_data: Array, candidates: Array[Dictionary]) -> void:
	for candidate: Dictionary in candidates:
		var door_cell: Vector2i = candidate["door_cell"]
		if _has_adjacent_door(map_data, door_cell):
			continue
		map_data[door_cell.y][door_cell.x] = DungeonDataScript.TileType.DOOR
		return


func _is_room_cell(rooms: Array[Rect2i], cell: Vector2i) -> bool:
	for room: Rect2i in rooms:
		if _room_contains_cell(room, cell):
			return true
	return false


func _has_adjacent_door(map_data: Array, cell: Vector2i) -> bool:
	for direction: Vector2i in SECRET_DIRECTIONS:
		var neighbor: Vector2i = cell + direction
		if (
			_is_inside_map(map_data, neighbor)
			and map_data[neighbor.y][neighbor.x] == DungeonDataScript.TileType.DOOR
		):
			return true
	return false


func _has_corridor_run_door(map_data: Array, door_cell: Vector2i, outward: Vector2i) -> bool:
	for step: int in range(1, DOOR_CORRIDOR_PAIR_BLOCK_DISTANCE + 1):
		var cell: Vector2i = door_cell + outward * step
		if not _is_inside_map(map_data, cell):
			return false
		var tile_type: int = map_data[cell.y][cell.x]
		if tile_type == DungeonDataScript.TileType.DOOR:
			return true
		if tile_type != DungeonDataScript.TileType.FLOOR:
			return false
	return false


func _carve_hallway_horizontal(map_data: Array, from_x: int, to_x: int, y: int) -> void:
	for x: int in range(min(from_x, to_x), max(from_x, to_x) + 1):
		map_data[y][x] = DungeonDataScript.TileType.FLOOR


func _carve_hallway_vertical(map_data: Array, from_y: int, to_y: int, x: int) -> void:
	for y: int in range(min(from_y, to_y), max(from_y, to_y) + 1):
		map_data[y][x] = DungeonDataScript.TileType.FLOOR
