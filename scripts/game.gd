extends Node2D

# === Constants ===
const PLAYER_SCENE_NAME: String = "Player"
const EXTRACTION_INTERVAL: int = 3
const CARDINAL_DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const STARTER_WEAPON_PATH: String = "res://resources/items/dagger.tres"
const SHOP_SPAWN_CHANCE: float = 0.75
const SHOP_STOCK_SIZE: int = 5
const SHOPKEEPER_NAME: String = "Shopkeeper"
const SHOPKEEPER_GLYPH: String = "S"
const SHOPKEEPER_COLOR: Color = Color(1.0, 0.82, 0.32)
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const DungeonGeneratorScript = preload("res://scripts/dungeon/dungeon_generator.gd")
const ActorScript = preload("res://scripts/entities/actor.gd")
const PlayerScript = preload("res://scripts/entities/player.gd")
const EnemyScript = preload("res://scripts/entities/enemy.gd")
const StatsComponentScript = preload("res://scripts/components/stats_component.gd")
const InventoryComponentScript = preload("res://scripts/components/inventory_component.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const CombatSystemScript = preload("res://scripts/systems/combat_system.gd")
const PathfindingScript = preload("res://scripts/systems/pathfinding.gd")
const FOVSystemScript = preload("res://scripts/systems/fov_system.gd")
const TrapDataScript = preload("res://scripts/resources/trap_data.gd")
const TrapSystem = preload("res://scripts/systems/trap_system.gd")

# === Private Variables ===
var _generator: RefCounted = DungeonGeneratorScript.new()
var _player: Node2D
var _enemies: Array = []
var _item_positions: Dictionary = {}
var _explored_cells: Dictionary = {}
var _visible_cells: Dictionary = {}
var _stairs_position: Vector2i = Vector2i.ZERO
var _shopkeeper: Node2D
var _enemy_resources: Array = []
var _item_resources: Array = []
var _shop_stock: Array = []
var _targeting_active: bool = false
var _target_cursor: Vector2i = Vector2i.ZERO
var _targeting_item: Resource
var _targeting_source: StringName = &""
var _targeting_range_cells: Dictionary = {}
var _shield_turns: int = 0
var _shield_armor_bonus: int = 0
var _haste_enemy_phases: int = 0
var _sleeping_enemies: Dictionary = {}
var _trap_data: Dictionary = {}
var _revealed_traps: Dictionary = {}
var _triggered_traps: Dictionary = {}
var _trap_resources: Array = []

# === Onready ===
@onready var map_view: Node2D = $MapView
@onready var hud: Control = $UI/HUD
@onready var inventory_panel: PanelContainer = $UI/InventoryPanel
@onready var character_sheet: PanelContainer = $UI/CharacterSheet
@onready var shop_panel: PanelContainer = $UI/ShopPanel
@onready var extraction_panel: PanelContainer = $UI/ExtractionPanel
@onready var extraction_label: Label = $UI/ExtractionPanel/Margin/VBox/PromptLabel
@onready var leave_button: Button = $UI/ExtractionPanel/Margin/VBox/Buttons/LeaveButton
@onready var descend_button: Button = $UI/ExtractionPanel/Margin/VBox/Buttons/DescendButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var pause_resume_button: Button = $UI/PausePanel/Margin/VBox/ResumeButton
@onready var pause_main_menu_button: Button = $UI/PausePanel/Margin/VBox/MainMenuButton
@onready var turn_manager: Node = $TurnManager


# === Lifecycle Methods ===
func _ready() -> void:
	if (
		GameManager.pending_character_name.is_empty()
		or GameManager.pending_ability_scores.is_empty()
	):
		get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")
		return
	_load_content()
	GameManager.reset_run()
	turn_manager.enemy_phase_finished.connect(_on_enemy_phase_finished)
	leave_button.pressed.connect(_on_leave_dungeon)
	descend_button.pressed.connect(_on_descend_deeper)
	shop_panel.connect("close_requested", _on_shop_panel_close_requested)
	inventory_panel.visibility_changed.connect(_refresh_overlay_visibility)
	character_sheet.visibility_changed.connect(_refresh_overlay_visibility)
	shop_panel.visibility_changed.connect(_refresh_overlay_visibility)
	extraction_panel.visibility_changed.connect(_refresh_overlay_visibility)
	pause_resume_button.pressed.connect(_on_pause_resume_pressed)
	pause_main_menu_button.pressed.connect(_on_pause_main_menu_pressed)
	pause_panel.visibility_changed.connect(_refresh_overlay_visibility)
	shop_panel.connect("purchase_requested", _on_shop_panel_purchase_requested)
	_start_or_resume_player()
	_generate_floor(GameManager.current_floor)


func _input(event: InputEvent) -> void:
	if not _is_escape_key(event):
		return
	if pause_panel.visible:
		_close_pause_menu()
	elif not _close_open_overlay():
		_open_pause_menu()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.is_player_turn or extraction_panel.visible or shop_panel.visible or pause_panel.visible:
		return
	if _targeting_active:
		_handle_targeting_input(event)
	elif _is_escape_key(event):
		_close_open_overlay()
	elif event.is_action_pressed(&"inventory"):
		inventory_panel.visible = not inventory_panel.visible
		if inventory_panel.visible:
			character_sheet.visible = false
			inventory_panel.refresh(_player)
	elif event.is_action_pressed(&"character_sheet"):
		character_sheet.visible = not character_sheet.visible
		if character_sheet.visible:
			inventory_panel.visible = false
			character_sheet.refresh(_player)
	elif inventory_panel.visible:
		if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
			inventory_panel.select_previous()
		elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
			inventory_panel.select_next()
		elif event.is_action_pressed(&"ui_accept"):
			var equipment_message: String = inventory_panel.toggle_selected_equipment()
			if not equipment_message.is_empty():
				GameManager.add_log_message(equipment_message, &"equipment")
			hud.bind_player(_player)
			character_sheet.refresh(_player)
		elif event.is_action_pressed(&"use_potion"):
			_use_selected_inventory_item()
	elif not character_sheet.visible:
		var direction: Vector2i = _input_direction(event)
		if event.is_action_pressed(&"use_potion"):
			_use_potion()
		elif event.is_action_pressed(&"fire_ranged"):
			_attempt_fire_ranged()
		elif direction != Vector2i.ZERO:
			_attempt_player_move(direction)
		elif event.is_action_pressed(&"wait"):
			GameManager.add_log_message("You search for traps and listen.", &"neutral")
			var found: int = TrapSystem.search_for_traps(
				_player.grid_position,
				_trap_data,
				_revealed_traps,
				_triggered_traps,
				_visible_cells,
				_get_perception_bonus()
			)
			if found > 0:
				GameManager.add_log_message(
					"You detect %d trap%s nearby." % [found, "s" if found != 1 else ""], &"neutral"
				)
			_end_player_turn()


# === Private Methods ===


func _is_escape_key(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE)
	)


func _open_pause_menu() -> void:
	_clear_targeting()
	pause_panel.visible = true
	pause_resume_button.grab_focus()


func _close_pause_menu() -> void:
	pause_panel.visible = false


func _on_pause_resume_pressed() -> void:
	_close_pause_menu()


func _on_pause_main_menu_pressed() -> void:
	GameManager.abandon_run()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _close_open_overlay() -> bool:
	if shop_panel.visible:
		shop_panel.visible = false
		return true
	if inventory_panel.visible:
		inventory_panel.visible = false
		return true
	if character_sheet.visible:
		character_sheet.visible = false
		return true
	if extraction_panel.visible:
		extraction_panel.visible = false
		return true
	return false


func _refresh_overlay_visibility() -> void:
	hud.visible = (
		not inventory_panel.visible
		and not character_sheet.visible
		and not shop_panel.visible
		and not extraction_panel.visible
		and not pause_panel.visible
	)


## Resource path lists (explicit — DirAccess does not work in web exports)
const ENEMY_RESOURCE_PATHS: Array[String] = [
	"res://resources/enemies/bat.tres",
	"res://resources/enemies/cultist.tres",
	"res://resources/enemies/goblin.tres",
	"res://resources/enemies/kobold.tres",
	"res://resources/enemies/orc.tres",
	"res://resources/enemies/rat.tres",
	"res://resources/enemies/skeleton.tres",
	"res://resources/enemies/troll.tres",
	"res://resources/enemies/wraith.tres",
	"res://resources/enemies/zombie.tres",
]
const ITEM_RESOURCE_PATHS: Array[String] = [
	"res://resources/items/amulet_of_guarding.tres",
	"res://resources/items/battle_axe.tres",
	"res://resources/items/bracers_of_power.tres",
	"res://resources/items/chainmail.tres",
	"res://resources/items/dagger.tres",
	"res://resources/items/dragonbone_blade.tres",
	"res://resources/items/elixir_of_life.tres",
	"res://resources/items/elixir_of_swiftness.tres",
	"res://resources/items/elven_chain.tres",
	"res://resources/items/flail.tres",
	"res://resources/items/greater_health_potion.tres",
	"res://resources/items/greatsword.tres",
	"res://resources/items/half_plate.tres",
	"res://resources/items/hand_crossbow.tres",
	"res://resources/items/health_potion.tres",
	"res://resources/items/heavy_crossbow.tres",
	"res://resources/items/iron_axe.tres",
	"res://resources/items/leather_armor.tres",
	"res://resources/items/longbow.tres",
	"res://resources/items/longsword.tres",
	"res://resources/items/mace.tres",
	"res://resources/items/mythril_plate.tres",
	"res://resources/items/plate_armor.tres",
	"res://resources/items/potion_of_giant_strength.tres",
	"res://resources/items/potion_of_haste.tres",
	"res://resources/items/ring_of_accuracy.tres",
	"res://resources/items/ring_of_power.tres",
	"res://resources/items/ring_of_protection.tres",
	"res://resources/items/scale_mail.tres",
	"res://resources/items/scimitar.tres",
	"res://resources/items/scroll_fire_bolt.tres",
	"res://resources/items/scroll_lightning_bolt.tres",
	"res://resources/items/scroll_magic_missile.tres",
	"res://resources/items/scroll_shield.tres",
	"res://resources/items/scroll_sleep.tres",
	"res://resources/items/shortbow.tres",
	"res://resources/items/spear.tres",
	"res://resources/items/splint_armor.tres",
	"res://resources/items/starfall_charm.tres",
	"res://resources/items/studded_leather.tres",
	"res://resources/items/superior_health_potion.tres",
	"res://resources/items/tonic_of_regeneration.tres",
	"res://resources/items/warhammer.tres",
]
const TRAP_RESOURCE_PATHS: Array[String] = [
	"res://resources/traps/alarm_trap.tres",
	"res://resources/traps/poison_dart_trap.tres",
	"res://resources/traps/spike_trap.tres",
	"res://resources/traps/teleport_trap.tres",
]

func _load_content() -> void:
	_enemy_resources = _load_explicit_resources(ENEMY_RESOURCE_PATHS)
	_item_resources = _load_explicit_resources(ITEM_RESOURCE_PATHS)
	_trap_resources = _load_explicit_resources(TRAP_RESOURCE_PATHS)


func _load_explicit_resources(paths: Array[String]) -> Array:
	var resources: Array = []
	for path: String in paths:
		var loaded: Resource = load(path)
		if loaded != null:
			resources.append(loaded)
	return resources


func _start_or_resume_player() -> void:
	_player = get_node_or_null(PLAYER_SCENE_NAME)
	if _player != null:
		return

	_player = PlayerScript.new()
	_player.name = PLAYER_SCENE_NAME
	var stats_component: Node = StatsComponentScript.new()
	stats_component.name = "StatsComponent"
	_player.add_child(stats_component)
	var inventory_component: Node = InventoryComponentScript.new()
	inventory_component.name = "InventoryComponent"
	_player.add_child(inventory_component)
	add_child(_player)
	var ability_scores: Dictionary = GameManager.pending_ability_scores
	if ability_scores.is_empty():
		ability_scores = Dice.roll_ability_scores()
	_player.initialize_from_rolls(ability_scores)
	if not GameManager.pending_character_name.is_empty():
		_player.display_name = GameManager.pending_character_name
	_grant_starter_weapon()
	GameManager.register_player(_player)
	hud.bind_player(_player)

func _grant_starter_weapon() -> void:
	var starter_template: Resource = load(STARTER_WEAPON_PATH)
	if starter_template == null:
		push_warning("Starter weapon missing: %s" % STARTER_WEAPON_PATH)
		return
	var starter_weapon: Resource = starter_template.duplicate(true)
	_player.inventory_component.add_item(starter_weapon)
	_player.inventory_component.equipped_weapon = starter_weapon
	GameManager.add_log_message("You grip a reliable dagger.", &"equipment")


func _generate_floor(floor_number: int) -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemies.clear()
	if _shopkeeper != null and is_instance_valid(_shopkeeper):
		_shopkeeper.queue_free()
	_shopkeeper = null
	GameManager.clear_enemies()
	_item_positions.clear()
	_shop_stock.clear()
	_explored_cells.clear()
	_visible_cells.clear()
	_clear_targeting()
	_shield_turns = 0
	_shield_armor_bonus = 0
	_haste_enemy_phases = 0
	_sleeping_enemies.clear()
	_trap_data.clear()
	_revealed_traps.clear()
	_triggered_traps.clear()
	var generation_result: Dictionary = _generator.generate(
		DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, floor_number
	)
	GameManager.set_map_data(generation_result["map"])
	GameManager.start_floor(floor_number)
	_stairs_position = generation_result["stairs_position"]
	_player.set_grid_position(generation_result["player_start"])
	_spawn_shopkeeper(generation_result, floor_number)
	_spawn_enemies(generation_result["enemy_spawns"], floor_number)
	_spawn_items(generation_result["item_spawns"])
	_spawn_traps(generation_result.get("trap_spawns", []), floor_number)
	_refresh_visibility()
	_refresh_map()
	inventory_panel.visible = false
	character_sheet.visible = false
	shop_panel.visible = false
	pause_panel.visible = false
	GameManager.add_log_message("You descend to floor %d." % floor_number, &"floor")
	if _shopkeeper != null:
		GameManager.add_log_message("A shopkeeper waits near the entrance.", &"loot")


func _spawn_enemies(spawn_positions: Array, floor_number: int) -> void:
	for spawn_position: Vector2i in spawn_positions:
		var enemy: Node2D = EnemyScript.new()
		var stats_component: Node = StatsComponentScript.new()
		stats_component.name = "StatsComponent"
		enemy.add_child(stats_component)
		add_child(enemy)
		var enemy_data: Resource = _choose_enemy_data_for_floor(floor_number)
		enemy.initialize_from_data(enemy_data, spawn_position)
		_scale_enemy_for_floor(enemy, floor_number)
		enemy.died.connect(_on_enemy_died)
		_enemies.append(enemy)
		GameManager.register_enemy(enemy)


func _spawn_items(spawn_positions: Array) -> void:
	for spawn_position: Vector2i in spawn_positions:
		var item: Resource = _choose_item_data_for_floor(GameManager.current_floor)
		_item_positions[spawn_position] = item


func _spawn_shopkeeper(generation_result: Dictionary, floor_number: int) -> void:
	if floor_number < 2 or randf() >= SHOP_SPAWN_CHANCE:
		return
	var rooms: Array = generation_result.get("rooms", [])
	if rooms.is_empty():
		return
	var player_start: Vector2i = generation_result["player_start"]
	var shopkeeper_position: Vector2i = _find_shopkeeper_position(rooms[0], player_start)
	if shopkeeper_position == Vector2i.ZERO:
		return

	_shopkeeper = ActorScript.new()
	_shopkeeper.name = SHOPKEEPER_NAME
	var stats_component: Node = StatsComponentScript.new()
	stats_component.name = "StatsComponent"
	_shopkeeper.add_child(stats_component)
	_shopkeeper.setup_actor(
		SHOPKEEPER_NAME, SHOPKEEPER_GLYPH, SHOPKEEPER_COLOR, shopkeeper_position
	)
	add_child(_shopkeeper)
	_shop_stock = _generate_shop_stock(floor_number)


func _spawn_traps(trap_spawns: Array, _floor_number: int) -> void:
	for spawn_position: Vector2i in trap_spawns:
		if _trap_resources.is_empty():
			return
		var trap: Resource = _trap_resources[randi_range(0, _trap_resources.size() - 1)]
		_trap_data[spawn_position] = trap


func _attempt_player_move(direction: Vector2i) -> void:
	var target: Vector2i = _player.grid_position + direction
	if not _is_walkable(target):
		GameManager.add_log_message("You bump into stone.", &"warning")
		return

	if _is_shopkeeper_at(target):
		_open_shop()
		return

	var enemy: Node2D = _get_enemy_at(target)
	if enemy != null:
		_resolve_attack(_player, enemy)
		_end_player_turn()
		return

	if _trap_data.has(target) and _triggered_traps.has(target):
		GameManager.add_log_message("The spent trap mechanism crunches underfoot.", &"neutral")
	if (
		_trap_data.has(target)
		and not _triggered_traps.has(target)
		and not _revealed_traps.has(target)
	):
		TrapSystem.trigger_trap(
			target,
			_trap_data,
			_triggered_traps,
			_player,
			_enemies,
			GameManager.map_data,
			GameManager.add_log_message,
			_refresh_trap_aftermath,
			_game_over
		)
		_end_player_turn()
		return

	_player.set_grid_position(target)
	_collect_item_at(target)
	if target == _stairs_position:
		_reach_stairs()
		return
	TrapSystem.detect_traps_around(
		target,
		_trap_data,
		_revealed_traps,
		_triggered_traps,
		_get_perception_bonus(),
		GameManager.add_log_message
	)
	_refresh_visibility()
	_refresh_map()
	_end_player_turn()


func _resolve_attack(attacker: Node, defender: Node) -> void:
	var outcome: Dictionary = CombatSystemScript.attack(attacker, defender)
	if outcome["hit"]:
		var critical_text: String = " Critical hit!" if outcome["critical"] else ""
		GameManager.add_log_message(
			(
				"%s hits %s for %d damage.%s"
				% [attacker.display_name, defender.display_name, outcome["damage"], critical_text]
			),
			&"combat_hit"
		)
	else:
		GameManager.add_log_message(
			"%s misses %s." % [attacker.display_name, defender.display_name], &"combat_miss"
		)

	_handle_defender_after_damage(defender)


func _handle_defender_after_damage(defender: Node) -> void:
	if defender == _player:
		GameManager.emit_player_damaged()
		if not _player.is_alive():
			_game_over(false)
	elif not defender.is_alive():
		var xp_reward: int = defender.stats_component.xp_reward
		if _player.stats_component.grant_xp(xp_reward):
			GameManager.level_up.emit(_player.stats_component.level)
			GameManager.add_log_message(
				"You advance to level %d." % _player.stats_component.level, &"level"
			)
			GameManager.emit_player_damaged()
		GameManager.emit_xp_changed()


func _collect_item_at(cell: Vector2i) -> void:
	if not _item_positions.has(cell):
		return
	var item: Resource = _item_positions[cell]
	_player.inventory_component.add_item(item)
	_item_positions.erase(cell)
	GameManager.add_log_message("You pick up %s." % item.display_name, &"loot")
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)


func _reach_stairs() -> void:
	if GameManager.current_floor % EXTRACTION_INTERVAL == 0:
		extraction_label.text = (
			"You survived floor %d.\nLeave safely, or descend deeper for greater danger?"
			% GameManager.current_floor
		)
		extraction_panel.visible = true
		leave_button.grab_focus()
		return
	_generate_floor(GameManager.current_floor + 1)


func _end_player_turn() -> void:
	if _shield_turns > 0:
		_shield_turns -= 1
	_refresh_temporary_stats()
	_refresh_visibility()
	_refresh_map()
	GameManager.advance_turn()
	if _haste_enemy_phases > 0:
		_haste_enemy_phases -= 1
		GameManager.add_log_message("You move faster than the dungeon can answer.", &"magic")
		GameManager.begin_player_turn()
		_refresh_map()
		return
	turn_manager.run_enemy_phase(_process_enemy_turns)


func _process_enemy_turns() -> void:
	var blocked_cells: Dictionary = {}
	for enemy in _enemies:
		if enemy != null and enemy.is_alive():
			blocked_cells[enemy.grid_position] = true
	if _shopkeeper != null:
		blocked_cells[_shopkeeper.grid_position] = true
	blocked_cells[_player.grid_position] = true

	for enemy in _enemies:
		if enemy == null or not enemy.is_alive():
			continue
		if _is_enemy_sleeping(enemy):
			continue
		blocked_cells.erase(enemy.grid_position)
		var distance_to_player: float = enemy.grid_position.distance_to(_player.grid_position)
		if distance_to_player <= 1.1:
			_resolve_attack(enemy, _player)
			if not _player.is_alive():
				return
		elif distance_to_player <= 8.0:
			var next_step: Vector2i = PathfindingScript.find_next_step(
				enemy.grid_position, _player.grid_position, GameManager.map_data, blocked_cells
			)
			if next_step != enemy.grid_position and next_step != _player.grid_position:
				enemy.set_grid_position(next_step)
		blocked_cells[enemy.grid_position] = true


func _refresh_visibility() -> void:
	_visible_cells = FOVSystemScript.calculate_visible_cells(
		_player.grid_position, 8, GameManager.map_data
	)
	for cell: Vector2i in _visible_cells.keys():
		_explored_cells[cell] = true


func _refresh_map() -> void:
	var actors: Array = [_player]
	if _shopkeeper != null:
		actors.append(_shopkeeper)
	for enemy in _enemies:
		actors.append(enemy)
	map_view.configure_map(GameManager.map_data)
	map_view.set_visibility(_visible_cells, _explored_cells)
	map_view.set_actors(actors)
	map_view.set_items(_item_positions)
	map_view.set_targeting(_targeting_active, _target_cursor, _targeting_range_cells)
	map_view.set_traps(_trap_data, _revealed_traps, _triggered_traps)
	hud.bind_player(_player)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)


func _is_walkable(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= GameManager.map_data.size():
		return false
	if cell.x < 0 or cell.x >= GameManager.map_data[0].size():
		return false
	return DungeonDataScript.is_walkable(GameManager.map_data[cell.y][cell.x])


func _get_enemy_at(cell: Vector2i) -> Node2D:
	for enemy in _enemies:
		if enemy != null and enemy.is_alive() and enemy.grid_position == cell:
			return enemy
	return null


func _is_shopkeeper_at(cell: Vector2i) -> bool:
	return (
		_shopkeeper != null and is_instance_valid(_shopkeeper) and _shopkeeper.grid_position == cell
	)


func _open_shop() -> void:
	inventory_panel.visible = false
	character_sheet.visible = false
	shop_panel.refresh(_player, _shop_stock)
	shop_panel.visible = true
	GameManager.add_log_message("You approach the shopkeeper.", &"neutral")


func _find_shopkeeper_position(room: Rect2i, player_start: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = [
		player_start + Vector2i.RIGHT * 2,
		player_start + Vector2i.LEFT * 2,
		player_start + Vector2i.DOWN * 2,
		player_start + Vector2i.UP * 2,
		player_start + Vector2i(2, 1),
		player_start + Vector2i(2, -1),
		player_start + Vector2i(-2, 1),
		player_start + Vector2i(-2, -1),
		player_start + Vector2i(1, 2),
		player_start + Vector2i(-1, 2),
		player_start + Vector2i(1, -2),
		player_start + Vector2i(-1, -2),
	]
	for candidate: Vector2i in candidates:
		if _can_place_shopkeeper(candidate, room, player_start):
			return candidate

	for y: int in range(room.position.y, room.end.y):
		for x: int in range(room.position.x, room.end.x):
			var candidate: Vector2i = Vector2i(x, y)
			if _can_place_shopkeeper(candidate, room, player_start):
				return candidate
	return Vector2i.ZERO


func _can_place_shopkeeper(candidate: Vector2i, room: Rect2i, player_start: Vector2i) -> bool:
	if candidate == player_start or candidate == _stairs_position:
		return false
	if candidate.distance_to(player_start) < 2.0:
		return false
	if not room.has_point(candidate) or not _is_walkable(candidate):
		return false
	return _keeps_floor_connected(candidate, player_start)


func _keeps_floor_connected(blocked_cell: Vector2i, origin: Vector2i) -> bool:
	if origin == blocked_cell or not _is_walkable(origin):
		return false

	var walkable_count: int = 0
	for y: int in range(GameManager.map_data.size()):
		for x: int in range(GameManager.map_data[y].size()):
			var cell: Vector2i = Vector2i(x, y)
			if cell != blocked_cell and DungeonDataScript.is_walkable(GameManager.map_data[y][x]):
				walkable_count += 1

	var frontier: Array[Vector2i] = [origin]
	var visited: Dictionary = {origin: true}
	var cursor: int = 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if neighbor == blocked_cell or visited.has(neighbor) or not _is_walkable(neighbor):
				continue
			visited[neighbor] = true
			frontier.append(neighbor)
	return visited.size() == walkable_count


func _get_perception_bonus() -> int:
	if _player == null:
		return 0
	return Dice.modifier(_player.stats_component.wisdom) + _player.stats_component.proficiency_bonus


func _refresh_trap_aftermath() -> void:
	GameManager.emit_player_damaged()
	_refresh_visibility()
	_refresh_map()


func _use_potion() -> void:
	var potion: Resource = _player.inventory_component.consume_first_potion()
	if potion == null:
		GameManager.add_log_message("You have no potion to drink.", &"warning")
		return
	_player.stats_component.heal(potion.healing_amount)
	GameManager.emit_player_damaged()
	GameManager.add_log_message(
		"You drink %s and recover %d HP." % [potion.display_name, potion.healing_amount], &"heal"
	)
	_refresh_map()
	_end_player_turn()


func _use_selected_inventory_item() -> void:
	var item: Resource = inventory_panel.get_selected_item()
	if item == null:
		GameManager.add_log_message("Select a consumable to use.", &"warning")
		return
	if item.kind != ItemDataScript.ItemKind.CONSUMABLE:
		GameManager.add_log_message("Select a consumable to use.", &"warning")
		return
	_use_consumable(item)


func _use_consumable(item: Resource) -> bool:
	var used: bool = true
	match item.use_effect:
		ItemDataScript.ItemUse.HEAL:
			_player.inventory_component.remove_item(item)
			_player.stats_component.heal(item.healing_amount)
			GameManager.emit_player_damaged()
			GameManager.add_log_message(
				"You drink %s and recover %d HP." % [item.display_name, item.healing_amount],
				&"heal"
			)
			_refresh_map()
			_end_player_turn()
		ItemDataScript.ItemUse.SHIELD:
			_player.inventory_component.remove_item(item)
			_shield_turns = max(_shield_turns, item.effect_duration)
			_shield_armor_bonus = max(_shield_armor_bonus, item.armor_bonus)
			_refresh_temporary_stats()
			GameManager.add_log_message(
				(
					"%s grants %+d AC for %d turns."
					% [item.display_name, item.armor_bonus, item.effect_duration]
				),
				&"magic"
			)
			_refresh_map()
			_end_player_turn()
		ItemDataScript.ItemUse.HASTE:
			_player.inventory_component.remove_item(item)
			_haste_enemy_phases = max(_haste_enemy_phases, item.effect_duration)
			GameManager.add_log_message(
				"%s makes your next move too fast to answer." % item.display_name, &"magic"
			)
			_refresh_map()
			_end_player_turn()
		ItemDataScript.ItemUse.RANGED_ATTACK:
			_start_targeting(item, &"consumable")
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			_start_targeting(item, &"consumable")
		ItemDataScript.ItemUse.SLEEP:
			_start_targeting(item, &"consumable")
		_:
			GameManager.add_log_message("Nothing happens.", &"warning")
			used = false
	return used


func _attempt_fire_ranged() -> void:
	var ranged_weapon: Resource = _player.inventory_component.get_equipped_ranged_weapon()
	if ranged_weapon == null:
		GameManager.add_log_message("Equip a ranged weapon before pressing F.", &"warning")
		return
	_start_targeting(ranged_weapon, &"weapon")


func _handle_targeting_input(event: InputEvent) -> void:
	var direction: Vector2i = _input_direction(event)
	if _is_escape_key(event):
		_cancel_targeting()
	elif event.is_action_pressed(&"ui_accept"):
		_confirm_targeting()
	elif direction != Vector2i.ZERO:
		_move_target_cursor(direction)


func _start_targeting(item: Resource, source: StringName) -> void:
	_targeting_active = true
	_targeting_item = item
	_targeting_source = source
	_targeting_range_cells = _get_target_range_cells(item.range)
	_target_cursor = _nearest_targetable_enemy_cell(item.range)
	if _target_cursor == Vector2i.ZERO:
		_target_cursor = _player.grid_position
	inventory_panel.visible = false
	character_sheet.visible = false
	GameManager.add_log_message(
		"Choose a target for %s. Enter confirms, Esc cancels." % item.display_name, &"neutral"
	)
	_refresh_map()


func _get_target_range_cells(target_range: int) -> Dictionary:
	var range_cells: Dictionary = {}
	for y: int in range(GameManager.map_data.size()):
		for x: int in range(GameManager.map_data[y].size()):
			var cell: Vector2i = Vector2i(x, y)
			if _visible_cells.has(cell) and cell.distance_to(_player.grid_position) <= target_range:
				range_cells[cell] = true
	return range_cells


func _nearest_targetable_enemy_cell(target_range: int) -> Vector2i:
	var nearest_cell: Vector2i = Vector2i.ZERO
	var nearest_distance: float = INF
	for enemy in _enemies:
		if enemy == null or not enemy.is_alive():
			continue
		var distance: float = enemy.grid_position.distance_to(_player.grid_position)
		if (
			distance <= target_range
			and _visible_cells.has(enemy.grid_position)
			and distance < nearest_distance
		):
			nearest_distance = distance
			nearest_cell = enemy.grid_position
	return nearest_cell


func _move_target_cursor(direction: Vector2i) -> void:
	var next_cursor: Vector2i = _target_cursor + direction
	if not _is_inside_map(next_cursor):
		return
	_target_cursor = next_cursor
	_refresh_map()


func _confirm_targeting() -> void:
	if not _is_valid_target_cell(_target_cursor, _targeting_item):
		GameManager.add_log_message("No valid target there.", &"warning")
		return
	var resolved: bool = _resolve_targeted_item(_targeting_item, _target_cursor, _targeting_source)
	if not resolved:
		return
	if _targeting_source == &"consumable":
		_player.inventory_component.remove_item(_targeting_item)
	_clear_targeting()
	_refresh_map()
	_end_player_turn()


func _is_valid_target_cell(cell: Vector2i, item: Resource) -> bool:
	if not _visible_cells.has(cell) or not _targeting_range_cells.has(cell):
		return false
	if item.use_effect == ItemDataScript.ItemUse.SLEEP:
		return true
	return _get_enemy_at(cell) != null


func _resolve_targeted_item(item: Resource, cell: Vector2i, source: StringName) -> bool:
	match item.use_effect:
		ItemDataScript.ItemUse.RANGED_ATTACK:
			var ranged_target: Node2D = _get_enemy_at(cell)
			if ranged_target == null:
				return false
			_resolve_ranged_attack(item, ranged_target, source)
			return true
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			var missile_target: Node2D = _get_enemy_at(cell)
			if missile_target == null:
				return false
			var missile_damage: int = _roll_item_damage(item, 0)
			missile_target.stats_component.apply_damage(missile_damage)
			GameManager.add_log_message(
				(
					"%s hits %s for %d force damage."
					% [item.display_name, missile_target.display_name, missile_damage]
				),
				&"magic"
			)
			_handle_defender_after_damage(missile_target)
			return true
		ItemDataScript.ItemUse.SLEEP:
			return _resolve_sleep(item, cell)
	return false


func _resolve_ranged_attack(item: Resource, defender: Node2D, source: StringName) -> void:
	var roll_result: int = Dice.d20()
	var stats: Node = _player.stats_component
	var inventory: Node = _player.inventory_component
	var attack_total: int = (
		roll_result
		+ stats.proficiency_bonus
		+ Dice.modifier(stats.dexterity)
		+ item.attack_bonus
		+ inventory.get_accessory_attack_bonus()
	)
	var is_critical: bool = roll_result == 20
	var hit: bool = is_critical or attack_total >= defender.stats_component.get_armor_class()
	if hit:
		var damage: int = _roll_item_damage(
			item, Dice.modifier(stats.dexterity) + inventory.get_accessory_damage_bonus()
		)
		if is_critical:
			damage += _roll_item_base_dice(item)
		defender.stats_component.apply_damage(damage)
		var verb: String = "shoots" if source == &"weapon" else "scorches"
		GameManager.add_log_message(
			"%s %s %s for %d damage." % [_player.display_name, verb, defender.display_name, damage],
			&"combat_hit"
		)
		_handle_defender_after_damage(defender)
	else:
		GameManager.add_log_message(
			"%s misses %s." % [_player.display_name, defender.display_name], &"combat_miss"
		)


func _resolve_sleep(item: Resource, cell: Vector2i) -> bool:
	var affected_count: int = 0
	for enemy in _enemies:
		if enemy == null or not enemy.is_alive() or not _visible_cells.has(enemy.grid_position):
			continue
		if enemy.grid_position.distance_to(cell) <= item.target_radius:
			_sleeping_enemies[enemy] = item.effect_duration
			affected_count += 1
	if affected_count <= 0:
		GameManager.add_log_message("No enemies are in the sleep radius.", &"warning")
		return false
	GameManager.add_log_message("Sleep affects %d enemies." % affected_count, &"magic")
	return true


func _roll_item_damage(item: Resource, bonus: int) -> int:
	return max(1, _roll_item_base_dice(item) + item.damage_bonus + bonus)


func _roll_item_base_dice(item: Resource) -> int:
	var total: int = 0
	for _die_index: int in range(max(1, item.damage_dice)):
		total += Dice.roll(item.damage_sides)
	return total


func _cancel_targeting() -> void:
	_targeting_active = false
	_targeting_item = null
	_targeting_source = &""
	_targeting_range_cells.clear()
	map_view.set_targeting(false, Vector2i.ZERO, {})
	GameManager.add_log_message("Targeting canceled.", &"neutral")
	_refresh_map()


func _clear_targeting() -> void:
	_targeting_active = false
	_targeting_item = null
	_targeting_source = &""
	_targeting_range_cells.clear()
	map_view.set_targeting(false, Vector2i.ZERO, {})


func _is_inside_map(cell: Vector2i) -> bool:
	return (
		cell.y >= 0
		and cell.y < GameManager.map_data.size()
		and cell.x >= 0
		and cell.x < GameManager.map_data[0].size()
	)


func _is_enemy_sleeping(enemy: Node) -> bool:
	if not _sleeping_enemies.has(enemy):
		return false
	var turns_left: int = _sleeping_enemies.get(enemy, 0)
	if enemy == null or not enemy.is_alive() or turns_left <= 0:
		_sleeping_enemies.erase(enemy)
		return false
	if _visible_cells.has(enemy.grid_position):
		GameManager.add_log_message("%s sleeps." % enemy.display_name, &"magic")
	if turns_left <= 1:
		_sleeping_enemies.erase(enemy)
	else:
		_sleeping_enemies[enemy] = turns_left - 1
	return true


func _refresh_temporary_stats() -> void:
	if _player == null:
		return
	_player.stats_component.temporary_armor_bonus = _shield_armor_bonus if _shield_turns > 0 else 0


func _input_direction(event: InputEvent) -> Vector2i:
	if event.is_action_pressed(&"move_up") or event.is_action_pressed(&"ui_up"):
		return Vector2i.UP
	if event.is_action_pressed(&"move_down") or event.is_action_pressed(&"ui_down"):
		return Vector2i.DOWN
	if event.is_action_pressed(&"move_left") or event.is_action_pressed(&"ui_left"):
		return Vector2i.LEFT
	if event.is_action_pressed(&"move_right") or event.is_action_pressed(&"ui_right"):
		return Vector2i.RIGHT
	return Vector2i.ZERO


func _on_enemy_died(enemy: Node) -> void:
	var gold_reward: int = _roll_enemy_gold_reward()
	_player.stats_component.gold += gold_reward
	GameManager.add_log_message("%s dies." % enemy.display_name, &"death")
	GameManager.add_log_message("+%d gold" % gold_reward, &"gold")
	GameManager.remove_enemy(enemy)
	hud.bind_player(_player)
	_refresh_map()


func _on_enemy_phase_finished() -> void:
	_refresh_visibility()
	_refresh_map()
	GameManager.begin_player_turn()


func _on_leave_dungeon() -> void:
	extraction_panel.visible = false
	_game_over(true)


func _on_descend_deeper() -> void:
	extraction_panel.visible = false
	_generate_floor(GameManager.current_floor + 1)


func _on_shop_panel_close_requested() -> void:
	shop_panel.visible = false


func _on_shop_panel_purchase_requested(stock_index: int) -> void:
	if stock_index < 0 or stock_index >= _shop_stock.size():
		return
	var item: Resource = _shop_stock[stock_index]
	var price: int = _get_item_shop_price(item)
	if _player.stats_component.gold < price:
		GameManager.add_log_message(
			"You need %d gold for %s." % [price, item.display_name], &"warning"
		)
		shop_panel.refresh(_player, _shop_stock)
		return
	_player.stats_component.gold -= price
	_player.inventory_component.add_item(item.duplicate(true))
	_shop_stock.remove_at(stock_index)
	GameManager.add_log_message(
		(
			"You buy %s for %d gold.  Remaining: %d."
			% [item.display_name, price, _player.stats_component.gold]
		),
		&"gold"
	)
	hud.bind_player(_player)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)
	shop_panel.refresh(_player, _shop_stock)


func _scale_enemy_for_floor(enemy: Node, floor_number: int) -> void:
	var depth_bonus: int = max(0, floor_number - 1)
	var tier_bonus: int = int(depth_bonus / EXTRACTION_INTERVAL)
	enemy.stats_component.max_hp += depth_bonus * 2
	enemy.stats_component.current_hp = enemy.stats_component.max_hp
	enemy.stats_component.base_armor_class += tier_bonus
	enemy.stats_component.base_attack_bonus += tier_bonus
	enemy.stats_component.base_damage_bonus += tier_bonus
	enemy.stats_component.xp_reward += depth_bonus * 10


func _choose_enemy_data_for_floor(floor_number: int) -> Resource:
	var candidates: Array[Resource] = []
	var total_weight: int = 0
	for enemy_data: Resource in _enemy_resources:
		if not _can_spawn_enemy(enemy_data, floor_number):
			continue
		candidates.append(enemy_data)
		total_weight += max(1, enemy_data.spawn_weight)

	if candidates.is_empty():
		return _enemy_resources[0]

	var roll: int = randi_range(1, total_weight)
	var running_weight: int = 0
	for enemy_data: Resource in candidates:
		running_weight += max(1, enemy_data.spawn_weight)
		if roll <= running_weight:
			return enemy_data
	return candidates.back()


func _choose_item_data_for_floor(floor_number: int) -> Resource:
	var candidates: Array[Resource] = _get_item_candidates_for_floor(floor_number)
	if candidates.is_empty():
		return _item_resources[0]
	return _choose_weighted_item(candidates, floor_number)


func _choose_weighted_item(candidates: Array[Resource], floor_number: int) -> Resource:
	var total_weight: int = 0
	for item_data: Resource in candidates:
		total_weight += _item_loot_weight(item_data, floor_number)
	if total_weight <= 0:
		return candidates[0]
	var roll: int = randi_range(1, total_weight)
	var running_weight: int = 0
	for item_data: Resource in candidates:
		running_weight += _item_loot_weight(item_data, floor_number)
		if roll <= running_weight:
			return item_data
	return candidates.back()


func _can_spawn_enemy(enemy_data: Resource, floor_number: int) -> bool:
	if floor_number < enemy_data.min_floor:
		return false
	return enemy_data.max_floor <= 0 or floor_number <= enemy_data.max_floor


func _can_spawn_item(item_data: Resource, floor_number: int) -> bool:
	if floor_number < item_data.min_floor:
		return false
	return item_data.max_floor <= 0 or floor_number <= item_data.max_floor


func _get_item_candidates_for_floor(floor_number: int) -> Array[Resource]:
	var candidates: Array[Resource] = []
	for item_data: Resource in _item_resources:
		if _can_spawn_item(item_data, floor_number):
			candidates.append(item_data)
	return candidates


func _item_loot_weight(item_data: Resource, floor_number: int) -> int:
	var rarity_weight: int = _rarity_weight_for_floor(item_data.rarity, floor_number)
	if rarity_weight <= 0:
		return 0
	return max(1, item_data.spawn_weight) * rarity_weight


func _rarity_weight_for_floor(rarity: int, floor_number: int) -> int:
	var depth: int = max(0, floor_number - 1)
	var weight: int = 1
	match rarity:
		ItemDataScript.ItemRarity.COMMON:
			weight = max(8, 60 - depth * 5)
		ItemDataScript.ItemRarity.UNCOMMON:
			weight = 22 + depth * 3
		ItemDataScript.ItemRarity.RARE:
			weight = max(0, depth * 5 - 6)
		ItemDataScript.ItemRarity.EPIC:
			weight = max(0, depth * 4 - 16)
		ItemDataScript.ItemRarity.LEGENDARY:
			weight = max(0, depth * 3 - 18)
		ItemDataScript.ItemRarity.MYTHIC:
			weight = max(0, depth * 2 - 14)
	return weight


func _generate_shop_stock(floor_number: int) -> Array:
	var candidates: Array[Resource] = _get_item_candidates_for_floor(floor_number)
	var stock: Array = []
	var potion: Resource = _choose_guaranteed_shop_potion(floor_number)
	if potion != null:
		stock.append(potion)
		candidates.erase(potion)

	while stock.size() < SHOP_STOCK_SIZE and not candidates.is_empty():
		var item_data: Resource = _choose_weighted_item(candidates, floor_number)
		stock.append(item_data)
		candidates.erase(item_data)
	return stock


func _choose_guaranteed_shop_potion(floor_number: int) -> Resource:
	var potion_candidates: Array[Resource] = []
	for item_data: Resource in _item_resources:
		if not _can_spawn_item(item_data, floor_number):
			continue
		if item_data.kind == ItemDataScript.ItemKind.CONSUMABLE and item_data.healing_amount > 0:
			potion_candidates.append(item_data)
	if potion_candidates.is_empty():
		return null
	return _choose_weighted_item(potion_candidates, floor_number)


func _roll_enemy_gold_reward() -> int:
	var floor_number: int = max(1, GameManager.current_floor)
	var base_reward: int = randi_range(5, 10)
	var depth_bonus: int = randi_range(0, floor_number * 2)
	var tier_bonus: int = int(floor_number / EXTRACTION_INTERVAL) * 2
	return base_reward + depth_bonus + tier_bonus


func _game_over(victory: bool) -> void:
	GameManager.end_run(victory)
	if victory:
		get_tree().change_scene_to_file("res://scenes/victory.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/game_over.tscn")


# === Price Helpers ===
func _get_item_shop_price(item: Resource) -> int:
	"""Returns item price adjusted by player CHA modifier."""
	var base_price: int = item.get_price()
	var cha_mod: int = Dice.modifier(_player.stats_component.charisma)
	# 5% per CHA modifier point, min 50% of base price, cap penalty at +50%
	var multiplier: float = clampf(1.0 - 0.05 * cha_mod, 0.5, 1.5)
	return max(1, ceili(base_price * multiplier))
