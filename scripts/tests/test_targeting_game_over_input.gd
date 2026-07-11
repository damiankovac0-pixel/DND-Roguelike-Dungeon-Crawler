## Regression test for targeting input when the confirming action ends the run.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_targeting_game_over_input.gd
extends SceneTree

var _failed: bool = false
var _game_manager: Node
var _game_over_results: Array[bool] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(440001)
	_game_over_results.clear()
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return
	_connect_game_over_signal()
	if _failed:
		return
	_game_manager.prepare_character(
		"Tester",
		{"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 10, "cha": 10},
		_game_manager.CLASS_RANGER
	)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	_remove_generated_enemies(game, _game_manager)
	var enemy: Node2D = _spawn_killing_enemy(game, _game_manager)
	_prepare_targeting_state(game, enemy)
	var turn_before: int = _game_manager.turn_count
	game._handle_targeting_input(_accept_event())
	await process_frame
	await process_frame
	_assert_game_over_contract(game, turn_before)
	if _failed:
		return
	await _assert_old_scene_non_actionable(game)
	if _failed:
		return
	await _cleanup_nodes(game)
	_disconnect_game_over_signal()
	if not _failed:
		print("targeting game-over input check passed")
		quit(0)


func _connect_game_over_signal() -> void:
	if not _game_manager.has_signal(&"game_over_won"):
		_fail("GameManager game_over_won signal missing")
		return
	if _game_manager.is_connected(&"game_over_won", _on_game_over_won):
		_game_manager.disconnect(&"game_over_won", _on_game_over_won)
	_game_manager.connect(&"game_over_won", _on_game_over_won)


func _disconnect_game_over_signal() -> void:
	if _game_manager != null and _game_manager.is_connected(&"game_over_won", _on_game_over_won):
		_game_manager.disconnect(&"game_over_won", _on_game_over_won)


func _on_game_over_won(victory: bool) -> void:
	_game_over_results.append(victory)


func _accept_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"ui_accept"
	event.pressed = true
	return event


func _assert_game_over_contract(game: Variant, turn_before: int) -> void:
	if _game_over_results.size() != 1:
		_fail("expected exactly one game_over_won signal, got %d" % _game_over_results.size())
		return
	if _game_over_results[0]:
		_fail("targeting death emitted a victorious game_over_won signal")
		return
	if _game_manager.has_active_run:
		_fail("targeting death left the run active")
		return
	if _game_manager.is_player_turn:
		_fail("player turn reopened after targeting death")
		return
	if _game_manager.turn_count != turn_before + 1:
		_fail(
			(
				"targeting death should resolve exactly one turn, got %d after %d"
				% [_game_manager.turn_count, turn_before]
			)
		)
		return
	var scene: Node = current_scene
	if scene == null:
		_fail("targeting death did not transition to a game-over scene")
		return
	if is_instance_valid(game) and scene == game:
		_fail("targeting death left the old game scene current")
		return
	if scene.name != "GameOver":
		_fail("targeting death transitioned to %s, expected GameOver" % scene.name)
		return
	if is_instance_valid(game) and bool(game.get("_targeting_active")):
		_fail("targeting death left the old game in targeting mode")
		return


func _assert_old_scene_non_actionable(game: Variant) -> void:
	var signal_count_before: int = _game_over_results.size()
	var turn_count_before: int = _game_manager.turn_count
	var scene_before: Node = current_scene
	if is_instance_valid(game) and game.is_inside_tree():
		game._unhandled_input(_accept_event())
		await process_frame
	else:
		await process_frame
	if _game_over_results.size() != signal_count_before:
		_fail("old game scene emitted another game_over_won signal after transition")
		return
	if _game_manager.has_active_run:
		_fail("old game scene reactivated the ended run")
		return
	if _game_manager.is_player_turn:
		_fail("old game scene reopened player input after transition")
		return
	if _game_manager.turn_count != turn_count_before:
		_fail("old game scene advanced an extra turn after transition")
		return
	if current_scene != scene_before:
		_fail("old game scene changed the active scene after transition")
		return
	if is_instance_valid(game) and game.is_inside_tree() and bool(game.get("_targeting_active")):
		_fail("old game scene stayed in targeting mode after transition")
		return


func _cleanup_nodes(old_game: Variant) -> void:
	if is_instance_valid(old_game) and old_game.is_inside_tree():
		old_game.queue_free()
	var scene: Node = current_scene
	if scene != null and is_instance_valid(scene) and scene.is_inside_tree():
		scene.queue_free()
	current_scene = null
	await process_frame


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
	_disconnect_game_over_signal()
	printerr(message)
	quit(1)
