## Permanent test harness for generated door placement.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_door_placement.gd
##
## Verifies that closed doors are generated in corridor cells, not inside room
## floor tiles, and that doorway counts stay bounded across deterministic maps.
extends SceneTree

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const DungeonGeneratorScript = preload("res://scripts/dungeon/dungeon_generator.gd")
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
]
const TEST_SEEDS: Array[int] = [1001, 1002, 1003, 20240630, 998]
const MAX_DOOR_RATIO: float = 0.45
const PAIRED_DOOR_SCAN_DISTANCE: int = 7
const EXPECTED_DOOR_GLYPHS: Dictionary = {
	DungeonDataScript.TileType.DOOR: "+",
	DungeonDataScript.TileType.OPEN_DOOR: "/",
	DungeonDataScript.TileType.BOSS_DOOR: "G",
	DungeonDataScript.TileType.SEALED_BOSS_DOOR: "X",
}

# === Private Variables ===
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_door_glyphs()
	if _failed:
		return
	for test_seed: int in TEST_SEEDS:
		seed(test_seed)
		var generator: RefCounted = DungeonGeneratorScript.new()
		var result: Dictionary = generator.generate(
			DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, 4
		)
		_check_generated_doors(result, test_seed)
		if _failed:
			return
	for boss_floor: int in [5, 10, 15, 20, 25]:
		seed(220000 + boss_floor)
		var boss_generator: RefCounted = DungeonGeneratorScript.new()
		var boss_result: Dictionary = boss_generator.generate(
			DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, boss_floor
		)
		_check_boss_doors(boss_result, boss_floor)
		if _failed:
			return
	print("door placement check passed")
	quit(0)


func _check_door_glyphs() -> void:
	for tile_type: int in EXPECTED_DOOR_GLYPHS:
		var expected_glyph: String = EXPECTED_DOOR_GLYPHS[tile_type]
		var actual_glyph: String = DungeonDataScript.TILE_CHARS.get(tile_type, "")
		if actual_glyph != expected_glyph:
			_fail(
				(
					"tile type %d glyph is '%s', expected readable door glyph '%s'"
					% [tile_type, actual_glyph, expected_glyph]
				)
			)
			return


func _check_generated_doors(result: Dictionary, test_seed: int) -> void:
	var map_data: Array = result["map"]
	var rooms: Array = result["rooms"]
	var doors: Array[Vector2i] = _collect_doors(map_data)
	if doors.is_empty():
		_fail("seed %d generated no doors" % test_seed)
		return
	var candidate_count: int = _count_potential_door_candidates(map_data, rooms)
	var max_expected_doors: int = max(1, int(ceil(candidate_count * MAX_DOOR_RATIO)))
	if doors.size() > max_expected_doors:
		_fail(
			(
				"seed %d generated %d doors from %d candidates, expected at most %d"
				% [test_seed, doors.size(), candidate_count, max_expected_doors]
			)
		)
		return
	for door: Vector2i in doors:
		if _is_room_cell(rooms, door):
			_fail("seed %d placed door inside room at %s" % [test_seed, door])
			return
		if not _has_room_to_corridor_axis(map_data, rooms, door):
			_fail("seed %d placed door without room/corridor axis at %s" % [test_seed, door])
			return
		if _has_paired_corridor_door(map_data, rooms, door):
			_fail("seed %d placed paired corridor doors near %s" % [test_seed, door])
			return


func _check_boss_doors(result: Dictionary, boss_floor: int) -> void:
	var map_data: Array = result["map"]
	var encounter: Dictionary = result.get("boss_encounter", {})
	var boss_room: Rect2i = encounter.get("boss_room", Rect2i())
	if not bool(encounter.get("active", false)):
		_fail("floor %d did not generate boss door metadata" % boss_floor)
		return
	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	if gate_entry_cell == Vector2i.ZERO:
		_fail("floor %d has no boss_gate_entry_cell" % boss_floor)
		return
	for door: Vector2i in encounter.get("boss_door_cells", []):
		if map_data[door.y][door.x] != DungeonDataScript.TileType.BOSS_DOOR:
			_fail("floor %d boss door tile mismatch at %s" % [boss_floor, door])
			return
		if _is_room_cell([boss_room], door):
			_fail("floor %d placed boss door inside boss room at %s" % [boss_floor, door])
			return
		if abs(door.x - gate_entry_cell.x) + abs(door.y - gate_entry_cell.y) != 1:
			_fail(
				(
					"floor %d boss gate entry cell %s not adjacent to door %s"
					% [boss_floor, gate_entry_cell, door]
				)
			)
			return
	if _is_room_cell([boss_room], gate_entry_cell):
		_fail(
			(
				"floor %d placed boss gate entry cell inside boss room at %s"
				% [boss_floor, gate_entry_cell]
			)
		)
		return
	if not _is_floor_or_door(map_data[gate_entry_cell.y][gate_entry_cell.x]):
		_fail(
			(
				"floor %d boss gate entry cell %s tile is not traversable"
				% [boss_floor, gate_entry_cell]
			)
		)
		return


func _collect_doors(map_data: Array) -> Array[Vector2i]:
	var doors: Array[Vector2i] = []
	for y: int in range(map_data.size()):
		for x: int in range(map_data[y].size()):
			if map_data[y][x] == DungeonDataScript.TileType.DOOR:
				doors.append(Vector2i(x, y))
	return doors


func _count_potential_door_candidates(map_data: Array, rooms: Array) -> int:
	var count: int = 0
	for room: Rect2i in rooms:
		for x: int in range(room.position.x + 1, room.end.x - 1):
			if _is_potential_door_candidate(
				map_data, rooms, Vector2i(x, room.position.y), Vector2i.UP
			):
				count += 1
			if _is_potential_door_candidate(
				map_data, rooms, Vector2i(x, room.end.y - 1), Vector2i.DOWN
			):
				count += 1
		for y: int in range(room.position.y + 1, room.end.y - 1):
			if _is_potential_door_candidate(
				map_data, rooms, Vector2i(room.position.x, y), Vector2i.LEFT
			):
				count += 1
			if _is_potential_door_candidate(
				map_data, rooms, Vector2i(room.end.x - 1, y), Vector2i.RIGHT
			):
				count += 1
	return count


func _is_potential_door_candidate(
	map_data: Array, rooms: Array, room_edge_cell: Vector2i, outward: Vector2i
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
		and _is_floor_or_door(map_data[door_cell.y][door_cell.x])
		and _is_floor_or_door(map_data[corridor_cell.y][corridor_cell.x])
		and not _is_room_cell(rooms, door_cell)
		and not _is_room_cell(rooms, corridor_cell)
	)


func _is_floor_or_door(tile_type: int) -> bool:
	return (
		tile_type == DungeonDataScript.TileType.FLOOR
		or tile_type == DungeonDataScript.TileType.DOOR
		or tile_type == DungeonDataScript.TileType.BOSS_DOOR
		or tile_type == DungeonDataScript.TileType.SEALED_BOSS_DOOR
	)


func _has_paired_corridor_door(map_data: Array, rooms: Array, door: Vector2i) -> bool:
	var outward: Vector2i = _door_outward_direction(map_data, rooms, door)
	if outward == Vector2i.ZERO:
		return false
	for step: int in range(1, PAIRED_DOOR_SCAN_DISTANCE + 1):
		var cell: Vector2i = door + outward * step
		if not _is_inside_map(map_data, cell):
			return false
		var tile_type: int = map_data[cell.y][cell.x]
		if tile_type == DungeonDataScript.TileType.DOOR:
			return true
		if tile_type != DungeonDataScript.TileType.FLOOR:
			return false
	return false


func _door_outward_direction(map_data: Array, rooms: Array, door: Vector2i) -> Vector2i:
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var room_cell: Vector2i = door - direction
		var corridor_cell: Vector2i = door + direction
		if not _is_inside_map(map_data, room_cell) or not _is_inside_map(map_data, corridor_cell):
			continue
		if _is_room_cell(rooms, room_cell) and not _is_room_cell(rooms, corridor_cell):
			return direction
	return Vector2i.ZERO


func _has_room_to_corridor_axis(map_data: Array, rooms: Array, door: Vector2i) -> bool:
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var room_cell: Vector2i = door - direction
		var corridor_cell: Vector2i = door + direction
		if not _is_inside_map(map_data, room_cell) or not _is_inside_map(map_data, corridor_cell):
			continue
		if not _is_room_cell(rooms, room_cell):
			continue
		if _is_room_cell(rooms, corridor_cell):
			continue
		if map_data[room_cell.y][room_cell.x] != DungeonDataScript.TileType.FLOOR:
			continue
		if not _is_floor_or_door(map_data[corridor_cell.y][corridor_cell.x]):
			continue
		return true
	return false


func _is_room_cell(rooms: Array, cell: Vector2i) -> bool:
	for room: Rect2i in rooms:
		if (
			cell.x >= room.position.x
			and cell.x < room.end.x
			and cell.y >= room.position.y
			and cell.y < room.end.y
		):
			return true
	return false


func _is_inside_map(map_data: Array, cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < map_data.size() and cell.x >= 0 and cell.x < map_data[0].size()


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
