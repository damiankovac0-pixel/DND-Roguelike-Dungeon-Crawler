## Focused V16 regression coverage for enemy intent telegraphs.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v16_enemy_intents.gd
extends SceneTree

const GOBLIN_RESOURCE_PATH: String = "res://resources/enemies/goblin.tres"
const EMBER_ARCHER_RESOURCE_PATH: String = "res://resources/enemies/ember_archer.tres"
const LICH_RESOURCE_PATH: String = "res://resources/enemies/lich.tres"
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN
]

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(160016)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	if game_scene == null:
		_fail("game scene failed to load")
		return
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	_clear_enemies(game, game_manager)
	game._refresh_visibility()

	_check_melee_intent(game, game_manager)
	if _failed:
		return
	_check_hidden_enemy_omitted(game, game_manager)
	if _failed:
		return
	_check_sleep_priority_and_no_count_mutation(game, game_manager)
	if _failed:
		return
	_check_ranged_interval_intent(game, game_manager)
	if _failed:
		return
	_check_summon_interval_intent(game, game_manager)
	if _failed:
		return
	_check_ui_intent_apis(game)
	if _failed:
		return

	print("V16 enemy intent telegraph checks passed")
	quit(0)


func _check_melee_intent(game: Node, game_manager: Node) -> void:
	_clear_enemies(game, game_manager)
	var cell: Vector2i = _find_adjacent_visible_spawn_cell(game)
	if cell == Vector2i.ZERO:
		_fail("could not find adjacent visible spawn cell for melee intent")
		return
	var enemy: Node2D = _spawn_enemy(game, GOBLIN_RESOURCE_PATH, cell)
	var intents: Dictionary = game._build_enemy_intents()
	if intents.get(enemy.grid_position, &"") != &"melee":
		_fail("adjacent visible enemy should report melee intent, got %s" % intents)
		return
	print("  melee intent: adjacent visible enemy marks !")


func _check_hidden_enemy_omitted(game: Node, game_manager: Node) -> void:
	_clear_enemies(game, game_manager)
	var cell: Vector2i = _find_hidden_spawn_cell(game)
	if cell == Vector2i.ZERO:
		_fail("could not find hidden spawn cell")
		return
	var enemy: Node2D = _spawn_enemy(game, GOBLIN_RESOURCE_PATH, cell)
	var intents: Dictionary = game._build_enemy_intents()
	if intents.has(enemy.grid_position):
		_fail("hidden enemy should not appear in intents, got %s" % intents)
		return
	print("  visibility gate: hidden enemy omitted")


func _check_sleep_priority_and_no_count_mutation(game: Node, game_manager: Node) -> void:
	_clear_enemies(game, game_manager)
	var cell: Vector2i = _find_adjacent_visible_spawn_cell(game)
	if cell == Vector2i.ZERO:
		_fail("could not find adjacent visible spawn cell for sleep priority")
		return
	var enemy: Node2D = _spawn_enemy(game, GOBLIN_RESOURCE_PATH, cell)
	game._sleeping_enemies[enemy] = 2
	game._enemy_action_counts[enemy] = 4
	var intents: Dictionary = game._build_enemy_intents()
	if intents.get(enemy.grid_position, &"") != &"sleeping":
		_fail("sleeping enemy should report sleeping before melee, got %s" % intents)
		return
	if int(game._sleeping_enemies.get(enemy, 0)) != 2:
		_fail("intent build should not decrement sleeping turns")
		return
	if int(game._enemy_action_counts.get(enemy, 0)) != 4:
		_fail("intent build should not mutate action counts for sleeping enemy")
		return
	print("  sleep priority: sleeping marker wins without consuming turns")


func _check_ranged_interval_intent(game: Node, game_manager: Node) -> void:
	_clear_enemies(game, game_manager)
	var cell: Vector2i = _find_visible_spawn_cell(game, 2.0, 5.0)
	if cell == Vector2i.ZERO:
		_fail("could not find visible ranged spawn cell")
		return
	var enemy: Node2D = _spawn_enemy(game, EMBER_ARCHER_RESOURCE_PATH, cell)
	game._enemy_action_counts[enemy] = 2
	var intents: Dictionary = game._build_enemy_intents()
	if intents.get(enemy.grid_position, &"") != &"ranged":
		_fail("ranged enemy on next interval should report ranged intent, got %s" % intents)
		return
	if int(game._enemy_action_counts.get(enemy, 0)) != 2:
		_fail("intent build should not mutate ranged enemy action count")
		return
	print("  ranged intent: next attack interval marks →")


func _check_summon_interval_intent(game: Node, game_manager: Node) -> void:
	_clear_enemies(game, game_manager)
	var cell: Vector2i = _find_visible_spawn_cell(game, 2.0, 8.0)
	if cell == Vector2i.ZERO:
		_fail("could not find visible summon spawn cell")
		return
	var lich_data: Resource = load(LICH_RESOURCE_PATH)
	if lich_data == null:
		_fail("lich resource failed to load")
		return
	lich_data = lich_data.duplicate(true)
	lich_data.ranged_attack_range = 0
	lich_data.fireball_range = 0
	var lich: Node2D = game._spawn_enemy_instance(lich_data, cell, 12, false)
	game._enemy_action_counts[lich] = 5
	var intents: Dictionary = game._build_enemy_intents()
	if intents.get(lich.grid_position, &"") != &"summon":
		_fail("visible summoner on next interval should report summon intent, got %s" % intents)
		return
	if int(game._enemy_action_counts.get(lich, 0)) != 5:
		_fail("intent build should not mutate summoner action count")
		return
	print("  summon intent: next summon interval marks +")


func _check_ui_intent_apis(game: Node) -> void:
	var map_view_script: GDScript = load("res://scripts/ui/map_view.gd")
	if map_view_script == null:
		_fail("MapView script failed to load")
		return
	var map_view: Node2D = map_view_script.new()
	var marker_cell: Vector2i = Vector2i(1, 1)
	map_view.set_enemy_intents({marker_cell: &"melee"})
	if map_view._enemy_intents.get(marker_cell, &"") != &"melee":
		map_view.free()
		_fail("MapView did not retain enemy intent dictionary")
		return
	map_view.free()

	var hud: Control = game.hud
	if hud == null:
		_fail("game HUD missing")
		return
	hud.set_visible_enemy_intents({marker_cell: &"melee"})
	if not "Intent:" in hud.help_label.text:
		_fail("HUD intent legend missing after non-empty intents")
		return
	hud.set_visible_enemy_intents({})
	if "Intent:" in hud.help_label.text:
		_fail("HUD intent legend should clear when intents are empty")
		return
	print("  UI APIs: MapView stores intents and HUD legend toggles")


func _spawn_enemy(game: Node, resource_path: String, cell: Vector2i) -> Node2D:
	var enemy_data: Resource = load(resource_path)
	if enemy_data == null:
		_fail("enemy resource failed to load: %s" % resource_path)
		return null
	return game._spawn_enemy_instance(enemy_data, cell, 1, false)


func _clear_enemies(game: Node, game_manager: Node) -> void:
	for enemy in game._enemies.duplicate():
		if enemy != null and is_instance_valid(enemy):
			enemy.queue_free()
	game._enemies.clear()
	game._enemy_action_counts.clear()
	game._sleeping_enemies.clear()
	game_manager.clear_enemies()


func _find_adjacent_visible_spawn_cell(game: Node) -> Vector2i:
	var player_cell: Vector2i = game._player.grid_position
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var cell: Vector2i = player_cell + direction
		if game._visible_cells.has(cell) and game._is_free_enemy_spawn_cell(cell, {}):
			return cell
	return Vector2i.ZERO


func _find_visible_spawn_cell(game: Node, min_distance: float, max_distance: float) -> Vector2i:
	var player_cell: Vector2i = game._player.grid_position
	for cell: Vector2i in game._visible_cells.keys():
		var distance: float = cell.distance_to(player_cell)
		if distance < min_distance or distance > max_distance:
			continue
		if game._is_free_enemy_spawn_cell(cell, {}):
			return cell
	return Vector2i.ZERO


func _find_hidden_spawn_cell(game: Node) -> Vector2i:
	var player_cell: Vector2i = game._player.grid_position
	var map_data: Array = root.get_node("/root/GameManager").map_data
	for y: int in range(map_data.size()):
		for x: int in range(map_data[0].size()):
			var cell: Vector2i = Vector2i(x, y)
			if game._visible_cells.has(cell):
				continue
			if cell.distance_to(player_cell) < 10.0:
				continue
			if game._is_free_enemy_spawn_cell(cell, {}):
				return cell
	return Vector2i.ZERO


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
