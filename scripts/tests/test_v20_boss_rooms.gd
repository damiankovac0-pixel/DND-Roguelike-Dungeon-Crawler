## V20.0.0 boss room generation contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_rooms.gd
extends SceneTree

const BOSS_FLOORS: Array[int] = [5, 10, 15, 20, 25]
const EXPECTED_BOSS_ARENA_SIZE: Vector2i = Vector2i(21, 19)
const BOSS_FOOTPRINT_SIZE: Vector2i = Vector2i(5, 4)
const BOSS_FOOTPRINT_OFFSET: Vector2i = Vector2i(-2, -2)
const MIN_ENTRY_TO_SPAWN_DISTANCE: int = 8
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const CARDINAL_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const DungeonGeneratorScript = preload("res://scripts/dungeon/dungeon_generator.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for floor_number: int in BOSS_FLOORS:
		for sample_index: int in range(3):
			seed(200000 + floor_number * 10 + sample_index)
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
	_assert(
		bool(encounter.get("boss_arena_isolated", false)),
		"floor %d arena not isolated" % floor_number
	)
	_assert(not rooms.is_empty(), "floor %d should retain normal dungeon rooms" % floor_number)
	_assert(
		encounter.get("boss_room_cells", {}) == encounter.get("boss_arena_cells", {}),
		"floor %d room/arena cell aliases diverged" % floor_number
	)
	_assert(
		boss_arena.size == EXPECTED_BOSS_ARENA_SIZE,
		(
			"floor %d boss arena size is %s, expected %s"
			% [floor_number, boss_arena.size, EXPECTED_BOSS_ARENA_SIZE]
		)
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
		var final_room: Rect2i = rooms[rooms.size() - 1]
		var gate_cell: Vector2i = encounter.get("boss_gate_cell", Vector2i.ZERO)
		_assert(
			final_room.grow(1).has_point(gate_cell),
			"floor %d boss gate should border the final normal room" % floor_number
		)
	if not _failed:
		_check_boss_gate_and_stand_cells(result, encounter, floor_number)
	if not _failed:
		_check_boss_internal_cells(result, encounter, floor_number)
	if not _failed:
		_check_isolated_arena_topology(result, encounter, floor_number)
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


func _check_boss_internal_cells(
	result: Dictionary, encounter: Dictionary, floor_number: int
) -> void:
	var arena: Rect2i = encounter.get("boss_arena", Rect2i())
	var map_data: Array = result["map"]
	var arena_cells: Dictionary = encounter.get(
		"boss_arena_cells", encounter.get("boss_room_cells", {})
	)
	var entry_cell: Vector2i = encounter.get("boss_entry_cell", Vector2i.ZERO)
	var spawn_cell: Vector2i = encounter.get("boss_spawn_cell", Vector2i.ZERO)
	var stairs_cell: Vector2i = encounter.get("boss_stairs_cell", Vector2i.ZERO)
	var chest_cell: Vector2i = encounter.get("boss_chest_cell", Vector2i.ZERO)
	var boss_footprint: Rect2i = Rect2i(spawn_cell + BOSS_FOOTPRINT_OFFSET, BOSS_FOOTPRINT_SIZE)
	_assert(
		arena_cells.size() == EXPECTED_BOSS_ARENA_SIZE.x * EXPECTED_BOSS_ARENA_SIZE.y,
		(
			"floor %d arena cell count is %d, expected %d"
			% [
				floor_number,
				arena_cells.size(),
				EXPECTED_BOSS_ARENA_SIZE.x * EXPECTED_BOSS_ARENA_SIZE.y,
			]
		)
	)
	for y: int in range(arena.position.y, arena.end.y):
		for x: int in range(arena.position.x, arena.end.x):
			if _failed:
				return
			var arena_cell: Vector2i = Vector2i(x, y)
			_assert(
				arena_cells.has(arena_cell),
				"floor %d arena floor cell %s missing" % [floor_number, arena_cell]
			)
			_assert(
				map_data[arena_cell.y][arena_cell.x] == DungeonDataScript.TileType.FLOOR,
				"floor %d arena cell %s is not FLOOR" % [floor_number, arena_cell]
			)
	_assert(
		arena_cells.has(entry_cell),
		"floor %d entry cell %s not in arena" % [floor_number, entry_cell]
	)
	_assert(
		arena_cells.has(spawn_cell),
		"floor %d spawn cell %s not in arena" % [floor_number, spawn_cell]
	)
	_assert(
		(
			abs(entry_cell.x - spawn_cell.x) + abs(entry_cell.y - spawn_cell.y)
			>= MIN_ENTRY_TO_SPAWN_DISTANCE
		),
		"floor %d entry %s too close to spawn %s" % [floor_number, entry_cell, spawn_cell]
	)
	_assert(
		spawn_cell == arena.get_center(),
		(
			"floor %d spawn cell %s is not centered at %s"
			% [floor_number, spawn_cell, arena.get_center()]
		)
	)
	_check_boss_footprint_clearance(arena_cells, boss_footprint, floor_number)
	_check_boss_reward_cells(
		arena_cells, entry_cell, spawn_cell, stairs_cell, chest_cell, boss_footprint, floor_number
	)


func _check_boss_footprint_clearance(
	arena_cells: Dictionary, boss_footprint: Rect2i, floor_number: int
) -> void:
	for y: int in range(boss_footprint.position.y, boss_footprint.end.y):
		for x: int in range(boss_footprint.position.x, boss_footprint.end.x):
			if _failed:
				return
			var footprint_cell: Vector2i = Vector2i(x, y)
			_assert(
				arena_cells.has(footprint_cell),
				"floor %d boss footprint cell %s is outside arena" % [floor_number, footprint_cell]
			)


func _check_boss_reward_cells(
	arena_cells: Dictionary,
	entry_cell: Vector2i,
	spawn_cell: Vector2i,
	stairs_cell: Vector2i,
	chest_cell: Vector2i,
	boss_footprint: Rect2i,
	floor_number: int
) -> void:
	_assert(
		arena_cells.has(stairs_cell),
		"floor %d stairs cell %s not in arena" % [floor_number, stairs_cell]
	)
	_assert(
		arena_cells.has(chest_cell),
		"floor %d chest cell %s not in arena" % [floor_number, chest_cell]
	)
	_assert(
		stairs_cell != chest_cell,
		"floor %d stairs and chest overlap at %s" % [floor_number, stairs_cell]
	)
	_assert(
		stairs_cell != spawn_cell and chest_cell != spawn_cell,
		(
			"floor %d reward overlaps spawn at stairs=%s chest=%s"
			% [floor_number, stairs_cell, chest_cell]
		)
	)
	_assert(
		stairs_cell != entry_cell and chest_cell != entry_cell,
		(
			"floor %d reward overlaps entry at stairs=%s chest=%s"
			% [floor_number, stairs_cell, chest_cell]
		)
	)
	_assert(
		not boss_footprint.has_point(stairs_cell),
		"floor %d stairs cell %s overlaps boss footprint" % [floor_number, stairs_cell]
	)
	_assert(
		not boss_footprint.has_point(chest_cell),
		"floor %d chest cell %s overlaps boss footprint" % [floor_number, chest_cell]
	)
	_assert(
		(stairs_cell.x - spawn_cell.x) * (chest_cell.x - spawn_cell.x) < 0,
		(
			"floor %d stairs %s and chest %s are not on opposite horizontal sides of spawn %s"
			% [floor_number, stairs_cell, chest_cell, spawn_cell]
		)
	)


func _check_isolated_arena_topology(
	result: Dictionary, encounter: Dictionary, floor_number: int
) -> void:
	var arena_cells: Dictionary = encounter.get("boss_arena_cells", {})
	var view_cells: Dictionary = encounter.get("boss_arena_view_cells", {})
	var arena: Rect2i = encounter.get("boss_arena", Rect2i())
	var expected_view: Dictionary = {}
	var view_rect: Rect2i = arena.grow(1)
	var map_data: Array = result["map"]
	for y: int in range(view_rect.position.y, view_rect.end.y):
		for x: int in range(view_rect.position.x, view_rect.end.x):
			if y >= 0 and y < map_data.size() and x >= 0 and x < map_data[y].size():
				expected_view[Vector2i(x, y)] = true
	_assert(
		view_cells.size() == expected_view.size(),
		(
			"floor %d arena view size mismatch: got %d expected %d"
			% [floor_number, view_cells.size(), expected_view.size()]
		)
	)
	for cell: Vector2i in expected_view:
		_assert(view_cells.has(cell), "floor %d arena view missing %s" % [floor_number, cell])
	var gate_entry: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	var reachable: Dictionary = _flood_fill_floor(map_data, gate_entry)
	for cell: Vector2i in arena_cells:
		_assert(
			view_cells.has(cell), "floor %d arena view excludes interior %s" % [floor_number, cell]
		)
		_assert(
			not reachable.has(cell),
			"floor %d normal dungeon reaches isolated arena cell %s" % [floor_number, cell]
		)
	for cell: Vector2i in view_cells:
		if arena_cells.has(cell):
			continue
		_assert(
			map_data[cell.y][cell.x] == DungeonDataScript.TileType.WALL,
			"floor %d arena moat cell %s is not WALL" % [floor_number, cell]
		)


func _check_reserved_room_overlap(
	result: Dictionary, encounter: Dictionary, floor_number: int
) -> void:
	var reserved_cells: Dictionary = encounter.get(
		"boss_arena_view_cells",
		encounter.get("boss_arena_cells", encounter.get("boss_room_cells", {}))
	)
	_assert(
		not reserved_cells.is_empty(), "floor %d boss arena reservation is empty" % floor_number
	)
	for key: String in ["enemy_spawns", "item_spawns", "trap_spawns"]:
		for cell: Vector2i in result.get(key, []):
			if _failed:
				break
			_assert(
				not reserved_cells.has(cell),
				"floor %d %s contains reserved arena/moat cell %s" % [floor_number, key, cell]
			)
	for container: Dictionary in result.get("secret_containers", []):
		if _failed:
			break
		var cell: Vector2i = container.get("cell", Vector2i.ZERO)
		_assert(
			not reserved_cells.has(cell),
			"floor %d secret container overlaps arena/moat at %s" % [floor_number, cell]
		)
	for cell: Vector2i in result.get("secret_walls", {}):
		_assert(
			not reserved_cells.has(cell),
			"floor %d secret wall overlaps arena/moat at %s" % [floor_number, cell]
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
