## V20.0.0 boss room generation contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_rooms.gd
extends SceneTree

const BOSS_FLOORS: Array[int] = [5, 10, 15, 20, 25]
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const CARDINAL_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const DungeonGeneratorScript = preload("res://scripts/dungeon/dungeon_generator.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for floor_number: int in BOSS_FLOORS:
		seed(200000 + floor_number)
		var generator: RefCounted = DungeonGeneratorScript.new()
		var result: Dictionary = generator.generate(
			DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, floor_number
		)
		_check_boss_floor(result, floor_number)
		if _failed:
			return
	seed(200004)
	var normal_generator: RefCounted = DungeonGeneratorScript.new()
	var normal_result: Dictionary = normal_generator.generate(
		DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, 4
	)
	_check_non_boss_floor(normal_result)
	if not _failed:
		print("V20 boss room generation checks passed")
		quit(0)


func _check_boss_floor(result: Dictionary, floor_number: int) -> void:
	var encounter: Dictionary = result.get("boss_encounter", {})
	var rooms: Array = result.get("rooms", [])
	var boss_room: Rect2i = encounter.get("boss_room", Rect2i())
	var boss_arena: Rect2i = encounter.get("boss_arena", boss_room)
	_assert(bool(encounter.get("active", false)), "floor %d inactive boss" % floor_number)
	if not _failed:
		_assert(
			boss_room.size.x > 0 and boss_room.size.y > 0,
			"floor %d boss arena is empty" % floor_number
		)
	if not _failed:
		for room_index: int in range(rooms.size()):
			if _failed:
				break
			var normal_room: Rect2i = rooms[room_index]
			_assert(
				not boss_arena.intersects(normal_room),
				(
					"floor %d boss arena intersects normal room %d at %s"
					% [floor_number, room_index, normal_room]
				)
			)
	if not _failed:
		_check_boss_gate_and_stand_cells(result, encounter, floor_number)
	if not _failed:
		_check_boss_internal_cells(encounter, floor_number)
	if not _failed:
		var stairs_cell: Vector2i = encounter.get("boss_stairs_cell", Vector2i.ZERO)
		_assert(
			result["map"][stairs_cell.y][stairs_cell.x] == DungeonDataScript.TileType.FLOOR,
			"floor %d boss stairs should stay FLOOR before victory" % floor_number
		)
	if not _failed:
		_check_reserved_room_overlap(result, encounter, floor_number)


func _check_boss_gate_and_stand_cells(
	result: Dictionary, encounter: Dictionary, floor_number: int
) -> void:
	var boss_doors: Array = encounter.get("boss_door_cells", [])
	var gate_cell: Vector2i = encounter.get("boss_gate_cell", Vector2i.ZERO)
	_assert(
		boss_doors.size() == 1,
		"floor %d expected 1 boss gate, got %d" % [floor_number, boss_doors.size()]
	)
	_assert(gate_cell != Vector2i.ZERO, "floor %d boss_gate_cell is zero" % floor_number)
	if _failed:
		return
	_assert(
		gate_cell == boss_doors[0],
		"floor %d gate cell mismatch: gate=%s door[0]=%s" % [floor_number, gate_cell, boss_doors[0]]
	)
	_assert(
		result["map"][gate_cell.y][gate_cell.x] == DungeonDataScript.TileType.BOSS_DOOR,
		"floor %d boss gate tile is not BOSS_DOOR at %s" % [floor_number, gate_cell]
	)
	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	_assert(
		gate_entry_cell != Vector2i.ZERO, "floor %d boss_gate_entry_cell is zero" % floor_number
	)
	if _failed:
		return
	_assert(
		result["map"][gate_entry_cell.y][gate_entry_cell.x] == DungeonDataScript.TileType.FLOOR,
		"floor %d gate entry cell is not FLOOR at %s" % [floor_number, gate_entry_cell]
	)
	var is_adjacent: bool = false
	for dir: Vector2i in CARDINAL_DIRS:
		if gate_entry_cell + dir == gate_cell:
			is_adjacent = true
			break
	_assert(
		is_adjacent,
		(
			"floor %d gate entry %s not adjacent to gate %s"
			% [floor_number, gate_entry_cell, gate_cell]
		)
	)
	if not _failed:
		var reachable: Dictionary = _flood_fill_floor(result["map"], gate_entry_cell)
		_assert(
			reachable.size() > 1,
			(
				"floor %d gate entry cell %s is isolated (no other walkable cells reachable)"
				% [floor_number, gate_entry_cell]
			)
		)


func _flood_fill_floor(map_data: Array, start: Vector2i) -> Dictionary:
	var width: int = map_data[0].size() if map_data.size() > 0 else 0
	var height: int = map_data.size()
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	visited[start] = true
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for dir: Vector2i in CARDINAL_DIRS:
			var neighbor: Vector2i = current + dir
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= width or neighbor.y >= height:
				continue
			if visited.has(neighbor):
				continue
			var tile: int = map_data[neighbor.y][neighbor.x]
			if (
				tile == DungeonDataScript.TileType.FLOOR
				or tile == DungeonDataScript.TileType.OPEN_DOOR
				or tile == DungeonDataScript.TileType.STAIRS_DOWN
			):
				visited[neighbor] = true
				queue.append(neighbor)
	return visited


func _check_boss_internal_cells(encounter: Dictionary, floor_number: int) -> void:
	var arena_cells: Dictionary = encounter.get(
		"boss_arena_cells", encounter.get("boss_room_cells", {})
	)
	var entry_cell: Vector2i = encounter.get("boss_entry_cell", Vector2i.ZERO)
	var spawn_cell: Vector2i = encounter.get("boss_spawn_cell", Vector2i.ZERO)
	var stairs_cell: Vector2i = encounter.get("boss_stairs_cell", Vector2i.ZERO)
	var chest_cell: Vector2i = encounter.get("boss_chest_cell", Vector2i.ZERO)
	_assert(
		arena_cells.has(entry_cell),
		"floor %d entry cell %s not in arena" % [floor_number, entry_cell]
	)
	_assert(
		arena_cells.has(spawn_cell),
		"floor %d spawn cell %s not in arena" % [floor_number, spawn_cell]
	)
	_assert(
		arena_cells.has(stairs_cell),
		"floor %d stairs cell %s not in arena" % [floor_number, stairs_cell]
	)
	_assert(
		arena_cells.has(chest_cell),
		"floor %d chest cell %s not in arena" % [floor_number, chest_cell]
	)


func _check_reserved_room_overlap(
	result: Dictionary, encounter: Dictionary, floor_number: int
) -> void:
	var arena_cells: Dictionary = encounter.get(
		"boss_arena_cells", encounter.get("boss_room_cells", {})
	)
	_assert(
		not arena_cells.is_empty(), "floor %d boss_arena_cells/room_cells are empty" % floor_number
	)
	for key: String in ["enemy_spawns", "item_spawns", "trap_spawns"]:
		for cell: Vector2i in result.get(key, []):
			if _failed:
				break
			_assert(
				not arena_cells.has(cell),
				"floor %d %s contains arena cell %s" % [floor_number, key, cell]
			)
	for container: Dictionary in result.get("secret_containers", []):
		if _failed:
			break
		var cell: Vector2i = container.get("cell", Vector2i.ZERO)
		_assert(
			not arena_cells.has(cell),
			"floor %d secret container overlaps arena at %s" % [floor_number, cell]
		)


func _check_non_boss_floor(result: Dictionary) -> void:
	_assert(not bool(result.get("boss_encounter", {}).get("active", true)), "floor 4 active boss")
	if not _failed:
		var stairs_position: Vector2i = result.get("stairs_position", Vector2i.ZERO)
		_assert(
			(
				result["map"][stairs_position.y][stairs_position.x]
				== DungeonDataScript.TileType.STAIRS_DOWN
			),
			"floor 4 should place normal stairs immediately"
		)


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
