## Permanent test harness for the lich summoning sight gate.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_lich_sight_gate.gd
##
## Verifies that a Lich only raises skeletons while inside the player's line of
## sight, and stays silent when hidden off-screen.
extends SceneTree

const LICH_RESOURCE_PATH: String = "res://resources/enemies/lich.tres"
const MIN_SPAWN_DISTANCE: int = 12
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(777)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	var lich_data: Resource = load(LICH_RESOURCE_PATH)
	var map_data: Array = game_manager.map_data
	var lich_cell: Vector2i = _find_remote_spawn_cell(game, map_data)
	if lich_cell == Vector2i.ZERO:
		_fail("could not find a remote walkable cell with a free neighbor for the lich")
		return
	var lich: Node2D = game._spawn_enemy_instance(lich_data, lich_cell, 12, false)
	if lich == null:
		_fail("lich failed to spawn")
		return

	# A hidden lich must NOT summon, even on its summon interval.
	if game._visible_cells.has(lich_cell):
		_fail("lich cell is unexpectedly inside player sight at setup")
		return
	var distance: float = float(lich_cell.distance_to(game._player.grid_position))
	var blocked: Dictionary = {lich_cell: true}
	game._process_enemy_special_turn(lich, distance, 6, blocked)
	if game._count_summoned_minions(lich) != 0:
		_fail("hidden lich summoned a minion — sight gate failed")
		return

	# Once the lich is inside the player's sight, it may raise skeletons.
	game._visible_cells[lich_cell] = true
	blocked = {lich_cell: true}
	game._process_enemy_special_turn(lich, distance, 12, blocked)
	if game._count_summoned_minions(lich) < 1:
		_fail("visible lich failed to summon a minion")
		return

	print("lich sight gate check passed")
	quit(0)


func _find_remote_spawn_cell(game: Node, map_data: Array) -> Vector2i:
	var player_cell: Vector2i = game._player.grid_position
	for y: int in range(map_data.size()):
		for x: int in range(map_data[0].size()):
			var cell: Vector2i = Vector2i(x, y)
			if cell.distance_to(player_cell) < MIN_SPAWN_DISTANCE:
				continue
			if not game._is_walkable(cell):
				continue
			if _has_free_neighbor(game, cell, {cell: true}):
				return cell
	return Vector2i.ZERO


func _has_free_neighbor(game: Node, cell: Vector2i, blocked: Dictionary) -> bool:
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		if game._is_free_enemy_spawn_cell(cell + direction, blocked):
			return true
	return false


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
