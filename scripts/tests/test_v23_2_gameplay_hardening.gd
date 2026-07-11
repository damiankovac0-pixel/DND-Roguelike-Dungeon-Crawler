## Regression coverage for V23.2 gameplay hardening fixes.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v23_2_gameplay_hardening.gd
extends SceneTree

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const TrapDataScript = preload("res://scripts/resources/trap_data.gd")
const TrapSystem = preload("res://scripts/systems/trap_system.gd")

const CENTER_CELL: Vector2i = Vector2i(10, 10)
const GOBLIN_PATH: String = "res://resources/enemies/goblin.tres"
const HUNTING_BOW_PATH: String = "res://resources/items/hunting_bow.tres"
const MAGIC_MISSILE_PATH: String = "res://resources/items/scroll_magic_missile.tres"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(2302001)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	if not _failed:
		_check_pause_hides_biome_overlay(game)
	if not _failed:
		await _check_nonlethal_trap_entry(game, game_manager)
	if not _failed:
		await _check_teleport_exclusions(game, game_manager)
	if not _failed:
		_check_death_turn_guard(game, game_manager)
	if not _failed:
		await _check_stunned_targeting_contracts(game, game_manager)
	if not _failed:
		_check_lethal_trap_entry(game, game_manager)

	if not _failed:
		print("v23.2 gameplay hardening check passed")
		quit(0)


func _check_pause_hides_biome_overlay(game: Node) -> void:
	game.biome_overlay.visible = true
	game.biome_overlay.modulate = Color.WHITE
	game._open_pause_menu()
	var biome_hidden: bool = not game.biome_overlay.visible
	var pause_visible: bool = game.pause_panel.visible
	game._close_pause_menu()
	if not biome_hidden:
		_fail("opening pause should dismiss the active biome introduction")
		return
	if not pause_visible:
		_fail("opening pause should show the pause panel")
		return
	if paused:
		_fail("closing pause should resume SceneTree processing")
		return
	print("  pause menu cleanly supersedes active biome introductions")


func _check_nonlethal_trap_entry(game: Node, game_manager: Node) -> void:
	_reset_fixture(game, game_manager, CENTER_CELL)
	var trap_cell: Vector2i = CENTER_CELL + Vector2i.RIGHT
	game._trap_data[trap_cell] = _make_trap(TrapDataScript.TrapEffect.DAMAGE, 3, 3)
	var hp_before: int = game._player.stats_component.current_hp
	var turn_before: int = game_manager.turn_count

	game._attempt_player_move(Vector2i.RIGHT)
	await process_frame

	if game._player.grid_position != trap_cell:
		_fail(
			(
				"nonlethal trap should leave player on entry cell %s, got %s"
				% [trap_cell, game._player.grid_position]
			)
		)
		return
	if game._player.stats_component.current_hp != hp_before - 3:
		_fail(
			(
				"nonlethal trap HP = %d, expected %d"
				% [game._player.stats_component.current_hp, hp_before - 3]
			)
		)
		return
	if not game_manager.has_active_run:
		_fail("nonlethal trap ended the active run")
		return
	if game_manager.turn_count != turn_before + 1:
		_fail(
			(
				"nonlethal trap turn count = %d, expected %d"
				% [game_manager.turn_count, turn_before + 1]
			)
		)
		return
	print("  nonlethal trap entry keeps the player on the trap and spends a turn")


func _check_teleport_exclusions(game: Node, game_manager: Node) -> void:
	_reset_fixture(game, game_manager, CENTER_CELL)
	_build_closed_fixture_map(game_manager)
	var start_cell: Vector2i = CENTER_CELL
	var teleport_cell: Vector2i = start_cell + Vector2i.RIGHT
	var trapped_destination: Vector2i = start_cell + Vector2i.RIGHT * 2
	var enemy_destination: Vector2i = start_cell + Vector2i.RIGHT * 3
	var safe_destination: Vector2i = start_cell + Vector2i.RIGHT * 4
	var floor_cells: Array[Vector2i] = [
		start_cell,
		teleport_cell,
		trapped_destination,
		enemy_destination,
		safe_destination,
	]
	for cell: Vector2i in floor_cells:
		_set_tile(game_manager, cell, DungeonDataScript.TileType.FLOOR)
	game._player.set_grid_position(teleport_cell)
	game._trap_data.clear()
	game._triggered_traps.clear()
	game._trap_data[start_cell] = _make_trap(TrapDataScript.TrapEffect.DAMAGE, 0, 0)
	game._trap_data[teleport_cell] = _make_trap(TrapDataScript.TrapEffect.TELEPORT, 0, 0)
	game._trap_data[trapped_destination] = _make_trap(TrapDataScript.TrapEffect.DAMAGE, 0, 0)
	var blocker: Node2D = _spawn_enemy(game, game_manager, enemy_destination)
	blocker.stats_component.max_hp = 50
	blocker.stats_component.current_hp = 50

	var safe_cells: Array[Vector2i] = TrapSystem._get_safe_teleport_cells(
		teleport_cell,
		game._trap_data,
		game._player,
		game._enemies,
		game_manager.map_data,
		game._current_actor_blocked_cells()
	)
	if safe_cells.size() != 1 or safe_cells[0] != safe_destination:
		_fail("teleport safe cells = %s, expected only %s" % [safe_cells, safe_destination])
		return

	game._player.set_grid_position(start_cell)
	game._refresh_visibility()
	game._refresh_map()
	var turn_before: int = game_manager.turn_count
	game._attempt_player_move(Vector2i.RIGHT)
	await process_frame

	if game._player.grid_position != safe_destination:
		_fail(
			(
				"teleport trap landed at %s, expected safe destination %s"
				% [game._player.grid_position, safe_destination]
			)
		)
		return
	if (
		game._player.grid_position
		in [start_cell, teleport_cell, trapped_destination, enemy_destination]
	):
		_fail("teleport landed on an excluded cell %s" % game._player.grid_position)
		return
	if game_manager.turn_count != turn_before + 1:
		_fail(
			(
				"teleport trap turn count = %d, expected %d"
				% [game_manager.turn_count, turn_before + 1]
			)
		)
		return
	print("  teleport trap excludes current, trap, trapped, and occupied cells")


func _check_death_turn_guard(game: Node, game_manager: Node) -> void:
	_reset_fixture(game, game_manager, CENTER_CELL)
	game_manager.turn_count = 7
	game_manager.is_player_turn = true
	game_manager.has_active_run = true
	game._player.stats_component.current_hp = 0

	game._finish_player_action()

	if game_manager.turn_count != 7:
		_fail("dead-player guard advanced turn count to %d" % game_manager.turn_count)
		return
	if not game_manager.is_player_turn:
		_fail("dead-player guard ended the player turn")
		return
	game._player.stats_component.current_hp = game._player.stats_component.max_hp
	print("  dead players cannot advance turns or start enemy phases")


func _check_stunned_targeting_contracts(game: Node, game_manager: Node) -> void:
	_reset_fixture(game, game_manager, CENTER_CELL)
	var target_cell: Vector2i = CENTER_CELL + Vector2i.RIGHT * 2
	var consumable_target: Node2D = _spawn_enemy(game, game_manager, target_cell)
	consumable_target.stats_component.max_hp = 500
	consumable_target.stats_component.current_hp = 500
	game._visible_cells[target_cell] = true
	game._explored_cells[target_cell] = true
	var missile_template: Resource = load(MAGIC_MISSILE_PATH)
	var missile: Resource = missile_template.duplicate(true)
	game._player.inventory_component.add_item(missile)
	game._stun_actions = 2
	var hp_before: int = consumable_target.stats_component.current_hp
	var turn_before: int = game_manager.turn_count

	var started: bool = game._use_consumable(missile)
	if not started:
		_fail("stunned targeted consumable did not enter targeting")
		return
	if not game._targeting_active or game._targeting_source != &"consumable":
		_fail("stunned targeted consumable did not keep consumable targeting active")
		return
	game._target_cursor = target_cell
	game._refresh_targeting_area()
	game._confirm_targeting()
	await process_frame

	if consumable_target.stats_component.current_hp >= hp_before:
		_fail("stunned targeted consumable did not damage its target")
		return
	if game._player.inventory_component.items.has(missile):
		_fail("resolved targeted consumable was not removed from inventory")
		return
	if game._targeting_active:
		_fail("resolved targeted consumable left targeting active")
		return
	if game._stun_actions != 1:
		_fail("targeted consumable stun actions = %d, expected 1" % game._stun_actions)
		return
	if game_manager.turn_count != turn_before + 1:
		_fail(
			(
				"targeted consumable turn count = %d, expected %d"
				% [game_manager.turn_count, turn_before + 1]
			)
		)
		return

	_reset_fixture(game, game_manager, CENTER_CELL)
	var weapon_target_cell: Vector2i = CENTER_CELL + Vector2i.RIGHT * 2
	var weapon_target: Node2D = _spawn_enemy(game, game_manager, weapon_target_cell)
	weapon_target.stats_component.max_hp = 500
	weapon_target.stats_component.current_hp = 500
	weapon_target.stats_component.base_armor_class = 0
	game._visible_cells[weapon_target_cell] = true
	game._explored_cells[weapon_target_cell] = true
	var bow_template: Resource = load(HUNTING_BOW_PATH)
	var bow: Resource = bow_template.duplicate(true)
	game._player.inventory_component.add_item(bow)
	game._player.inventory_component.equipped_ranged_weapon = bow
	game._player.inventory_component.equipped_weapon = bow
	game._stun_actions = 2
	hp_before = weapon_target.stats_component.current_hp
	turn_before = game_manager.turn_count

	game._start_targeting(bow, &"weapon")
	game._target_cursor = weapon_target_cell
	game._refresh_targeting_area()
	game._confirm_targeting()
	await process_frame

	if weapon_target.stats_component.current_hp != hp_before:
		_fail("stunned weapon targeting damaged a target")
		return
	if game._targeting_active:
		_fail("blocked weapon targeting left targeting active")
		return
	if game._stun_actions != 1:
		_fail("blocked weapon targeting stun actions = %d, expected 1" % game._stun_actions)
		return
	if game_manager.turn_count != turn_before + 1:
		_fail(
			(
				"blocked weapon targeting turn count = %d, expected %d"
				% [game_manager.turn_count, turn_before + 1]
			)
		)
		return
	print("  stunned targeting allows consumables but blocks weapon attacks")


func _check_lethal_trap_entry(game: Node, game_manager: Node) -> void:
	_reset_fixture(game, game_manager, CENTER_CELL)
	var trap_cell: Vector2i = CENTER_CELL + Vector2i.RIGHT
	game._trap_data[trap_cell] = _make_trap(TrapDataScript.TrapEffect.DAMAGE, 5, 5)
	game._player.stats_component.current_hp = 2
	var turn_before: int = game_manager.turn_count

	game._attempt_player_move(Vector2i.RIGHT)

	if game._player.grid_position != trap_cell:
		_fail(
			(
				"lethal trap should resolve after entry at %s, got %s"
				% [trap_cell, game._player.grid_position]
			)
		)
		return
	if game._player.is_alive():
		_fail("lethal trap left the player alive")
		return
	if game_manager.has_active_run:
		_fail("lethal trap did not end the active run")
		return
	if game_manager.turn_count != turn_before:
		_fail(
			(
				"lethal trap advanced turn count to %d, expected %d"
				% [game_manager.turn_count, turn_before]
			)
		)
		return
	print("  lethal trap resolves on the entered cell without advancing turns")


func _reset_fixture(game: Node, game_manager: Node, center: Vector2i) -> void:
	_clear_generated_enemies(game, game_manager)
	if game._shopkeeper != null and is_instance_valid(game._shopkeeper):
		game._shopkeeper.queue_free()
	game._shopkeeper = null
	game._trap_data.clear()
	game._revealed_traps.clear()
	game._triggered_traps.clear()
	game._item_positions.clear()
	game._container_positions.clear()
	game._secret_walls.clear()
	game._revealed_secret_walls.clear()
	game._secret_floor_cells.clear()
	game._boss_hazards.clear()
	game._boss_telegraphs.clear()
	game._active_boss_encounter.clear()
	game._enemy_action_counts.clear()
	game._sleeping_enemies.clear()
	game._ranged_recovery_enemies.clear()
	game._stun_actions = 0
	game._poison_turns = 0
	game._regen_turns = 0
	game._haste_enemy_phases = 0
	game._clear_targeting()
	game.inventory_panel.visible = false
	game.character_sheet.visible = false
	game.shop_panel.visible = false
	game.pause_panel.visible = false
	game.consumable_panel.visible = false
	game.level_up_panel.visible = false
	_clear_player_inventory(game._player)
	game._player.stats_component.max_hp = max(game._player.stats_component.max_hp, 50)
	game._player.stats_component.current_hp = game._player.stats_component.max_hp
	game._player.set_grid_position(center)
	game._stairs_position = Vector2i(-1, -1)
	_set_open_patch(game_manager, center, 8)
	game_manager.register_player(game._player)
	game_manager.turn_count = 0
	game_manager.is_player_turn = true
	game_manager.has_active_run = true
	game._refresh_visibility()
	_mark_patch_visible(game, center, 8)
	game._refresh_map()


func _clear_generated_enemies(game: Node, game_manager: Node) -> void:
	for enemy: Node in game._enemies.duplicate():
		game._enemies.erase(enemy)
		game_manager.remove_enemy(enemy)
		if is_instance_valid(enemy):
			enemy.queue_free()
	game._enemies.clear()
	game_manager.clear_enemies()


func _clear_player_inventory(player: Node) -> void:
	var inventory: Node = player.inventory_component
	inventory.items.clear()
	inventory.equipped_weapon = null
	inventory.equipped_melee_weapon = null
	inventory.equipped_ranged_weapon = null
	inventory.equipped_armor = null
	inventory.equipped_accessory_1 = null
	inventory.equipped_accessory_2 = null


func _build_closed_fixture_map(game_manager: Node) -> void:
	var map_data: Array = []
	for y: int in range(DungeonDataScript.MAP_HEIGHT):
		var row: Array[int] = []
		for x: int in range(DungeonDataScript.MAP_WIDTH):
			row.append(DungeonDataScript.TileType.WALL)
		map_data.append(row)
	game_manager.set_map_data(map_data)


func _set_open_patch(game_manager: Node, center: Vector2i, radius: int) -> void:
	for y_offset: int in range(-radius, radius + 1):
		for x_offset: int in range(-radius, radius + 1):
			var cell: Vector2i = center + Vector2i(x_offset, y_offset)
			if _is_inside_map(game_manager, cell):
				_set_tile(game_manager, cell, DungeonDataScript.TileType.FLOOR)


func _mark_patch_visible(game: Node, center: Vector2i, radius: int) -> void:
	for y_offset: int in range(-radius, radius + 1):
		for x_offset: int in range(-radius, radius + 1):
			var cell: Vector2i = center + Vector2i(x_offset, y_offset)
			if _is_inside_map(root.get_node("/root/GameManager"), cell):
				game._visible_cells[cell] = true
				game._explored_cells[cell] = true


func _set_tile(game_manager: Node, cell: Vector2i, tile: int) -> void:
	game_manager.map_data[cell.y][cell.x] = tile


func _is_inside_map(game_manager: Node, cell: Vector2i) -> bool:
	return (
		cell.y >= 0
		and cell.y < game_manager.map_data.size()
		and cell.x >= 0
		and cell.x < game_manager.map_data[0].size()
	)


func _spawn_enemy(game: Node, game_manager: Node, cell: Vector2i) -> Node2D:
	var enemy_data: Resource = load(GOBLIN_PATH)
	var enemy: Node2D = game._spawn_enemy_instance(
		enemy_data, cell, game_manager.current_floor, false
	)
	return enemy


func _make_trap(effect: int, min_damage: int, max_damage: int) -> Resource:
	var trap: Resource = TrapDataScript.new()
	trap.display_name = "Fixture Trap"
	trap.description = "Deterministic regression fixture."
	trap.glyph = "^"
	trap.effect = effect
	trap.min_damage = min_damage
	trap.max_damage = max_damage
	trap.detect_dc = 99
	trap.reveal_on_detect = false
	return trap


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
