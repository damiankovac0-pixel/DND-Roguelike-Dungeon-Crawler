## Regression test for targeting input when the confirming action ends the run.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_targeting_game_over_input.gd
extends SceneTree

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(440001)
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	gm.prepare_character(
		"Tester",
		{"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10},
		gm.CLASS_RANGER
	)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_remove_generated_enemies(game, gm)
	var enemy: Node2D = _spawn_killing_enemy(game, gm)
	_prepare_targeting_state(game, enemy)
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	game._handle_targeting_input(event)
	await process_frame
	if not _failed:
		print("targeting game-over input check passed")
		quit(0)


func _remove_generated_enemies(game: Node, gm: Node) -> void:
	for enemy: Node in game._enemies.duplicate():
		game._enemies.erase(enemy)
		gm.remove_enemy(enemy)
		enemy.queue_free()


func _spawn_killing_enemy(game: Node, gm: Node) -> Node2D:
	var enemy_data: Resource = load("res://resources/enemies/ancient_dragon.tres")
	var player_cell: Vector2i = game._player.grid_position
	var enemy: Node2D = game._spawn_enemy_instance(
		enemy_data, player_cell + Vector2i.RIGHT, gm.current_floor, false
	)
	enemy.stats_component.current_hp = 999
	enemy.stats_component.base_attack_bonus = 99
	enemy.stats_component.base_damage_sides = 20
	enemy.stats_component.base_damage_bonus = 99
	game._player.stats_component.current_hp = 1
	return enemy


func _prepare_targeting_state(game: Node, enemy: Node2D) -> void:
	game._visible_cells[enemy.grid_position] = true
	game._explored_cells[enemy.grid_position] = true
	var bow: Resource = load("res://resources/items/hunting_bow.tres")
	game._start_targeting(bow, &"weapon")
	game._target_cursor = enemy.grid_position
	game._refresh_targeting_area()


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
