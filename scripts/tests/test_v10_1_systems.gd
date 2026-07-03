## Permanent test harness for V10.1.0 trap and loot additions.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v10_1_systems.gd
extends SceneTree

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const TrapDataScript = preload("res://scripts/resources/trap_data.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	_check_ascended_sword_loaded(game)
	_prepare_open_test_area(game, game_manager, game_manager.player.grid_position)
	await _check_stun_trap(game, game_manager.player.grid_position)
	_prepare_open_test_area(game, game_manager, game_manager.player.grid_position)
	await _check_ambush_trap(game, game_manager, game_manager.player.grid_position)
	print("v10.1 systems check passed")
	quit(0)


func _check_ascended_sword_loaded(game: Node) -> void:
	for item: Resource in game._item_resources:
		if item.display_name != "Ascended Sword":
			continue
		if item.kind != ItemDataScript.ItemKind.WEAPON:
			_fail("Ascended Sword is not a weapon")
			return
		if item.rarity != ItemDataScript.ItemRarity.ASCENDED:
			_fail("Ascended Sword is not Ascended rarity")
			return
		if item.is_ranged_weapon:
			_fail("Ascended Sword should be a melee weapon")
			return
		return
	_fail("Ascended Sword missing from loaded item resources")


func _check_stun_trap(game: Node, player_position: Vector2i) -> void:
	var trap_cell: Vector2i = player_position + Vector2i.RIGHT
	var stun_trap: Resource = load("res://resources/traps/stun_trap.tres")
	if stun_trap == null or stun_trap.effect != TrapDataScript.TrapEffect.STUN:
		_fail("Stun Trap resource missing or wrong effect")
		return
	await _trigger_stun_trap(game, player_position, trap_cell, stun_trap)
	if _failed:
		return
	await _check_stunned_movement(game, player_position)
	if _failed:
		return
	await _check_stunned_healing(game)


func _trigger_stun_trap(
	game: Node, player_position: Vector2i, trap_cell: Vector2i, stun_trap: Resource
) -> void:
	game._trap_data.clear()
	game._triggered_traps.clear()
	game._trap_data[trap_cell] = stun_trap
	game._attempt_player_move(Vector2i.RIGHT)
	await process_frame
	if game._player.grid_position != player_position:
		_fail("stun trap moved player onto trap")
		return
	if game._stun_actions != 3:
		_fail("stun actions %d, expected 3 after trap action" % game._stun_actions)


func _check_stunned_movement(game: Node, player_position: Vector2i) -> void:
	game._attempt_player_move(Vector2i.RIGHT)
	await process_frame
	if game._player.grid_position != player_position:
		_fail("stunned movement changed player position")
		return
	if game._stun_actions != 2:
		_fail("blocked stunned action left %d actions, expected 2" % game._stun_actions)


func _check_stunned_healing(game: Node) -> void:
	var potion_template: Resource = game._find_item_by_display_name("Health Potion")
	if potion_template == null:
		_fail("Health Potion missing from loaded item resources")
		return
	var potion: Resource = potion_template.duplicate(true)
	game._player.inventory_component.add_item(potion)
	game._player.stats_component.apply_damage(8)
	var wounded_hp: int = game._player.stats_component.current_hp
	var used: bool = game._use_consumable(potion)
	await process_frame
	if not used or game._player.stats_component.current_hp <= wounded_hp:
		_fail("stunned player could not use a healing consumable")


func _check_ambush_trap(game: Node, game_manager: Node, player_position: Vector2i) -> void:
	var trap_cell: Vector2i = player_position + Vector2i.RIGHT
	var ambush_trap: Resource = load("res://resources/traps/ambush_trap.tres")
	if ambush_trap == null or ambush_trap.effect != TrapDataScript.TrapEffect.AMBUSH:
		_fail("Ambush Trap resource missing or wrong effect")
		return
	game._trap_data.clear()
	game._triggered_traps.clear()
	game._enemies.clear()
	game_manager.clear_enemies()
	game._trigger_ambush_trap(trap_cell)
	await process_frame
	if game._enemies.size() != 3:
		_fail("ambush spawned %d enemies, expected 3" % game._enemies.size())
		return
	for enemy in game._enemies:
		var distance: float = enemy.grid_position.distance_to(player_position)
		if distance < 2.0 or distance > 5.7:
			_fail("ambush enemy spawned at distance %.2f" % distance)
			return


func _prepare_open_test_area(game: Node, game_manager: Node, center: Vector2i) -> void:
	game._trap_data.clear()
	game._triggered_traps.clear()
	game._container_positions.clear()
	game._item_positions.clear()
	game._enemies.clear()
	game._stun_actions = 0
	game_manager.clear_enemies()
	for y_offset: int in range(-6, 7):
		for x_offset: int in range(-6, 7):
			var cell: Vector2i = center + Vector2i(x_offset, y_offset)
			if _is_inside_map(game_manager, cell):
				game_manager.map_data[cell.y][cell.x] = DungeonDataScript.TileType.FLOOR
	game._refresh_visibility()
	game._refresh_map()


func _is_inside_map(game_manager: Node, cell: Vector2i) -> bool:
	return (
		cell.y > 0
		and cell.y < game_manager.map_data.size() - 1
		and cell.x > 0
		and cell.x < game_manager.map_data[0].size() - 1
	)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
