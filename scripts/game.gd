## Main game scene controller: floor generation, combat, shop, containers, traps, items, and player input.
extends Node2D

# === Constants ===
const PLAYER_SCENE_NAME: String = "Player"
const EXTRACTION_INTERVAL: int = 3
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
]
const STARTER_WEAPON_PATH: String = "res://resources/items/dagger.tres"
const SHOP_SPAWN_CHANCE: float = 0.90
const SHOP_STOCK_SIZE: int = 6
const SHOP_STOCK_MAX_BONUS: int = 3
const SHOP_EFFECTIVE_FLOOR_BONUS_FACTOR: float = 0.75
const SHOP_DEPTH_PICK_BONUS_FACTOR: float = 0.40
const SHOP_REROLL_BASE_COST: int = 20
const SHOP_REROLL_FLOOR_COST: int = 5
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
const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const CombatSystemScript = preload("res://scripts/systems/combat_system.gd")
const PathfindingScript = preload("res://scripts/systems/pathfinding.gd")
const FOVSystemScript = preload("res://scripts/systems/fov_system.gd")
const TrapDataScript = preload("res://scripts/resources/trap_data.gd")
const TrapSystem = preload("res://scripts/systems/trap_system.gd")
const CONTAINER_TYPE_CHEST: StringName = &"chest"
const CONTAINER_TYPE_CLUTTER: StringName = &"clutter"
const CHEST_GLYPHS: Array[String] = ["c", "c", "C", "C", "C", "C", "C"]
const CLUTTER_NAMES: Array[String] = ["Cracked Vase", "Old Box"]
const CLUTTER_GLYPHS: Array[String] = ["v", "b"]
const CLUTTER_COLORS: Array[Color] = [Color(0.55, 0.45, 0.35), Color(0.45, 0.34, 0.24)]
const SECRET_WALL_HP: int = 2
const SECRET_WALL_HINT_COLOR: Color = Color(0.72, 0.58, 1.0)
const SECRET_WALL_LISTEN_RADIUS: int = 8
const VASE_XP_ORB_CHANCE: float = 0.35
const VASE_XP_MIN_PERCENT: int = 5
const VASE_XP_MAX_PERCENT: int = 10
const DASH_LOG_NAME: String = "Windstep"
const BASE_FOV_RADIUS: int = 8
const INT_FOV_BONUS_SCORE: int = 15
const INT_FOV_MASTER_SCORE: int = 20

# === Private Variables ===
var _generator: RefCounted = DungeonGeneratorScript.new()
var _player: Node2D
var _enemies: Array = []
var _item_positions: Dictionary = {}
var _container_positions: Dictionary = {}
var _secret_walls: Dictionary = {}
var _revealed_secret_walls: Dictionary = {}
var _secret_floor_cells: Dictionary = {}
var _explored_cells: Dictionary = {}
var _visible_cells: Dictionary = {}
var _stairs_position: Vector2i = Vector2i.ZERO
var _shopkeeper: Node2D
var _enemy_resources: Array = []
var _item_resources: Array = []
var _shop_stock: Array = []
var _shop_reroll_count: int = 0
var _targeting_active: bool = false
var _target_cursor: Vector2i = Vector2i.ZERO
var _targeting_item: Resource
var _targeting_source: StringName = &""
var _targeting_range_cells: Dictionary = {}
var _targeting_area_cells: Dictionary = {}
var _shield_turns: int = 0
var _shield_armor_bonus: int = 0
var _haste_enemy_phases: int = 0
var _regen_turns: int = 0
var _regen_heal_amount: int = 0
var _dash_charge: int = 0
var _poison_turns: int = 0
var _poison_damage_sides: int = 4
var _enemy_action_counts: Dictionary = {}
var _sleeping_enemies: Dictionary = {}
var _ranged_recovery_enemies: Dictionary = {}
var _trap_data: Dictionary = {}
var _revealed_traps: Dictionary = {}
var _triggered_traps: Dictionary = {}
var _trap_resources: Array = []
var _resume_turn_after_level_choice: bool = false

# === Onready ===
@onready var map_view: Node2D = $MapView
@onready var hud: Control = $UI/HUD
@onready var inventory_panel: PanelContainer = $UI/InventoryPanel
@onready var character_sheet: PanelContainer = $UI/CharacterSheet
@onready var shop_panel: PanelContainer = $UI/ShopPanel
@onready var consumable_panel: PanelContainer = $UI/ConsumablePanel
@onready var level_up_panel: LevelUpPanel = $UI/LevelUpPanel
@onready var extraction_panel: PanelContainer = $UI/ExtractionPanel
@onready var extraction_label: Label = $UI/ExtractionPanel/Margin/VBox/PromptLabel
@onready var leave_button: Button = $UI/ExtractionPanel/Margin/VBox/Buttons/LeaveButton
@onready var descend_button: Button = $UI/ExtractionPanel/Margin/VBox/Buttons/DescendButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var pause_hint_label: Label = $UI/PausePanel/Margin/VBox/HintLabel
@onready var pause_resume_button: Button = $UI/PausePanel/Margin/VBox/ResumeButton
@onready var pause_main_menu_button: Button = $UI/PausePanel/Margin/VBox/MainMenuButton
@onready var debug_descend_button: Button = $UI/PausePanel/Margin/VBox/DebugDescendButton
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
	shop_panel.connect("sell_requested", _on_shop_panel_sell_requested)
	shop_panel.connect("reroll_requested", _on_shop_panel_reroll_requested)
	consumable_panel.connect("close_requested", _on_consumable_panel_close_requested)
	debug_descend_button.pressed.connect(_debug_descend_deeper)
	consumable_panel.connect("use_requested", _on_consumable_panel_use_requested)
	level_up_panel.stat_selected.connect(_on_level_up_panel_stat_selected)
	level_up_panel.visibility_changed.connect(_refresh_overlay_visibility)
	consumable_panel.visibility_changed.connect(_refresh_overlay_visibility)
	_start_or_resume_player()
	_generate_floor(GameManager.current_floor)


func _input(event: InputEvent) -> void:
	if _is_debug_descend_key(event):
		_debug_descend_deeper()
		get_viewport().set_input_as_handled()
		return
	if not _is_escape_key(event):
		return
	if _targeting_active:
		_cancel_targeting()
		get_viewport().set_input_as_handled()
		return
	if level_up_panel.visible:
		get_viewport().set_input_as_handled()
		return
	if pause_panel.visible:
		_close_pause_menu()
	elif not _close_open_overlay():
		_open_pause_menu()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if (
		not GameManager.is_player_turn
		or extraction_panel.visible
		or shop_panel.visible
		or pause_panel.visible
		or consumable_panel.visible
		or level_up_panel.visible
	):
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
			_open_consumable_menu()
	elif not character_sheet.visible:
		var direction: Vector2i = _input_direction(event)
		if event.is_action_pressed(&"use_potion"):
			_open_consumable_menu()
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
			var secret_found: int = _search_for_secret_walls(false)
			if secret_found > 0:
				GameManager.add_log_message(
					(
						"You hear hollow stone nearby: %d weak wall%s revealed."
						% [secret_found, "s" if secret_found != 1 else ""]
					),
					&"neutral"
				)
			_finish_player_action()


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


func _is_debug_descend_key(event: InputEvent) -> bool:
	if not GameManager.pending_debug_loadout:
		return false
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and (
			key_event.keycode == KEY_PAGEDOWN
			or (key_event.keycode == KEY_PERIOD and key_event.shift_pressed)
		)
	)


# ===== Pause & Overlay Management =====
func _open_pause_menu() -> void:
	_clear_targeting()
	pause_panel.visible = true
	debug_descend_button.visible = GameManager.pending_debug_loadout
	if GameManager.pending_debug_loadout:
		pause_hint_label.text = "The dungeon waits. Debug: Shift+> or PageDown descends."
	else:
		pause_hint_label.text = "The dungeon waits."
	pause_resume_button.grab_focus()


func _close_pause_menu() -> void:
	pause_panel.visible = false


func _on_pause_resume_pressed() -> void:
	_close_pause_menu()


func _debug_descend_deeper() -> void:
	if not GameManager.pending_debug_loadout or _player == null:
		return
	_clear_targeting()
	_close_pause_menu()
	_close_open_overlay()
	var next_floor: int = max(1, GameManager.current_floor) + 1
	_generate_floor(next_floor)


func _on_pause_main_menu_pressed() -> void:
	GameManager.abandon_run()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _close_open_overlay() -> bool:
	if shop_panel.visible:
		shop_panel.visible = false
		return true
	if consumable_panel.visible:
		consumable_panel.visible = false
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
		and not consumable_panel.visible
		and not level_up_panel.visible
	)


# ===== Consumables & Level-Up =====
func _open_consumable_menu() -> void:
	var consumables: Array = _player.inventory_component.get_consumables()
	if consumables.is_empty():
		GameManager.add_log_message("You have no potions or scrolls to use.", &"warning")
		return
	inventory_panel.visible = false
	character_sheet.visible = false
	consumable_panel.refresh(_player)
	consumable_panel.visible = true


func _on_consumable_panel_close_requested() -> void:
	consumable_panel.visible = false


func _on_consumable_panel_use_requested(inventory_index: int) -> void:
	var inventory: Node = _player.inventory_component
	if inventory_index < 0 or inventory_index >= inventory.items.size():
		consumable_panel.refresh(_player)
		return
	var item: Resource = inventory.items[inventory_index]
	if item.kind != ItemDataScript.ItemKind.CONSUMABLE:
		consumable_panel.refresh(_player)
		return
	var used: bool = _use_consumable(item)
	if used:
		consumable_panel.visible = false
	else:
		consumable_panel.refresh(_player)


func _open_level_up_panel() -> void:
	if _player == null:
		return
	var stats: StatsComponent = _player.stats_component
	if stats.pending_stat_increases <= 0:
		return
	if not stats.has_available_stat_increase():
		stats.pending_stat_increases = 0
		GameManager.add_log_message("All ability scores are already 20.", &"level")
		return
	_close_open_overlay()
	level_up_panel.refresh(_player)
	level_up_panel.visible = true


func _on_level_up_panel_stat_selected(stat_key: String) -> void:
	if _player == null:
		return
	var stats: StatsComponent = _player.stats_component
	if not stats.increase_ability(stat_key):
		level_up_panel.refresh(_player)
		return
	GameManager.add_log_message(
		"%s rises to %d." % [_get_ability_label(stat_key), _get_ability_value(stat_key)], &"level"
	)
	GameManager.emit_player_damaged()
	GameManager.emit_xp_changed()
	hud.bind_player(_player)
	character_sheet.refresh(_player)
	if stats.pending_stat_increases > 0 and stats.has_available_stat_increase():
		level_up_panel.refresh(_player)
		return
	if not stats.has_available_stat_increase():
		stats.pending_stat_increases = 0
	level_up_panel.visible = false
	_refresh_overlay_visibility()
	if _resume_turn_after_level_choice:
		_resume_turn_after_level_choice = false
		_end_player_turn()


func _grant_player_xp(amount: int) -> bool:
	if not _player.stats_component.grant_xp(amount):
		return false
	_handle_player_level_up()
	return true


func _handle_player_level_up() -> void:
	var stats: StatsComponent = _player.stats_component
	var first_level: int = stats.level - stats.last_levels_gained + 1
	for gained_level: int in range(first_level, stats.level + 1):
		GameManager.level_up.emit(gained_level)
		GameManager.add_log_message(
			"You advance to level %s." % stats.format_level_bbcode(gained_level), &"level"
		)
	if first_level <= StatsComponent.STAT_LEVEL_CAP and stats.level > StatsComponent.STAT_LEVEL_CAP:
		GameManager.add_log_message("Level 20 reached: future levels only raise HP.", &"level")
	GameManager.emit_player_damaged()
	_open_level_up_panel()


func _finish_player_action() -> void:
	if level_up_panel.visible:
		_resume_turn_after_level_choice = true
		return
	_end_player_turn()


func _get_ability_label(stat_key: String) -> String:
	match stat_key:
		"str":
			return "Strength"
		"dex":
			return "Dexterity"
		"con":
			return "Constitution"
		"int":
			return "Intelligence"
		"wis":
			return "Wisdom"
		"cha":
			return "Charisma"
	return "Ability"


func _get_ability_value(stat_key: String) -> int:
	var stats: StatsComponent = _player.stats_component
	match stat_key:
		"str":
			return stats.strength
		"dex":
			return stats.dexterity
		"con":
			return stats.constitution
		"int":
			return stats.intelligence
		"wis":
			return stats.wisdom
		"cha":
			return stats.charisma
	return 0


# ===== Resource Loading & Player Setup =====
func _load_content() -> void:
	_enemy_resources = _load_explicit_resources(ResourcePathsScript.ENEMY_PATHS)
	_item_resources = _load_explicit_resources(ResourcePathsScript.ITEM_PATHS)
	_trap_resources = _load_explicit_resources(ResourcePathsScript.TRAP_PATHS)


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
	if GameManager.pending_debug_loadout:
		_grant_debug_loadout()
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
	_player.inventory_component.equipped_melee_weapon = starter_weapon
	GameManager.add_log_message("You grip a reliable dagger.", &"equipment")


func _grant_debug_loadout() -> void:
	for item_template: Resource in _item_resources:
		var item: Resource = item_template.duplicate(true)
		_player.inventory_component.add_item(item)
		if item.kind == ItemDataScript.ItemKind.WEAPON:
			if item.is_ranged_weapon and _player.inventory_component.equipped_ranged_weapon == null:
				_player.inventory_component.equipped_ranged_weapon = item
			elif (
				not item.is_ranged_weapon
				and _player.inventory_component.equipped_melee_weapon == null
			):
				_player.inventory_component.equipped_melee_weapon = item
		elif (
			item.kind == ItemDataScript.ItemKind.ARMOR
			and _player.inventory_component.equipped_armor == null
		):
			_player.inventory_component.equipped_armor = item
		elif item.kind == ItemDataScript.ItemKind.ACCESSORY:
			if _player.inventory_component.equipped_accessory_1 == null:
				_player.inventory_component.equipped_accessory_1 = item
			elif _player.inventory_component.equipped_accessory_2 == null:
				_player.inventory_component.equipped_accessory_2 = item
	_player.inventory_component.equipped_weapon = _player.inventory_component.equipped_melee_weapon
	_player.stats_component.gold = 9999
	GameManager.add_log_message(
		"Debug kit granted: 20 stats, full item set, and 9999 gold.", &"loot"
	)


# ===== Floor Generation & Spawning =====
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
	_container_positions.clear()
	_secret_walls.clear()
	_revealed_secret_walls.clear()
	_secret_floor_cells.clear()
	_shop_stock.clear()
	_shop_reroll_count = 0
	_explored_cells.clear()
	_visible_cells.clear()
	_clear_targeting()
	_shield_turns = 0
	_shield_armor_bonus = 0
	_haste_enemy_phases = 0
	_regen_turns = 0
	_regen_heal_amount = 0
	_poison_turns = 0
	_poison_damage_sides = 4
	_enemy_action_counts.clear()
	_sleeping_enemies.clear()
	_ranged_recovery_enemies.clear()
	_trap_data.clear()
	_revealed_traps.clear()
	_triggered_traps.clear()
	var generation_result: Dictionary = _generator.generate(
		DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, floor_number
	)
	GameManager.set_map_data(generation_result["map"])
	_secret_walls = generation_result.get("secret_walls", {}).duplicate(true)
	for secret_floor_cell: Vector2i in generation_result.get("secret_floor_cells", []):
		_secret_floor_cells[secret_floor_cell] = true
	GameManager.start_floor(floor_number)
	_stairs_position = generation_result["stairs_position"]
	_player.set_grid_position(generation_result["player_start"])
	_spawn_shopkeeper(generation_result, floor_number)
	_spawn_enemies(generation_result["enemy_spawns"], floor_number)
	_spawn_items(generation_result["item_spawns"], floor_number)
	_spawn_traps(generation_result.get("trap_spawns", []), floor_number)
	_spawn_containers(generation_result, floor_number)
	_refresh_visibility()
	_refresh_map()
	inventory_panel.visible = false
	character_sheet.visible = false
	shop_panel.visible = false
	pause_panel.visible = false
	consumable_panel.visible = false
	GameManager.add_log_message("You descend to floor %d." % floor_number, &"floor")
	if _shopkeeper != null:
		GameManager.add_log_message("A shopkeeper waits near the entrance.", &"loot")


func _spawn_enemies(spawn_positions: Array, floor_number: int) -> void:
	for spawn_position: Vector2i in spawn_positions:
		var enemy_data: Resource = _choose_enemy_data_for_floor(floor_number)
		_spawn_enemy_instance(enemy_data, spawn_position, floor_number, true)


func _spawn_enemy_instance(
	enemy_data: Resource, spawn_position: Vector2i, floor_number: int, apply_floor_scaling: bool
) -> Node2D:
	var enemy: Node2D = EnemyScript.new()
	var stats_component: Node = StatsComponentScript.new()
	stats_component.name = "StatsComponent"
	enemy.add_child(stats_component)
	add_child(enemy)
	enemy.initialize_from_data(enemy_data, spawn_position)
	if apply_floor_scaling:
		_scale_enemy_for_floor(enemy, floor_number)
	enemy.died.connect(_on_enemy_died)
	_enemies.append(enemy)
	GameManager.register_enemy(enemy)
	return enemy


func _spawn_items(spawn_positions: Array, floor_number: int) -> void:
	for spawn_position: Vector2i in spawn_positions:
		var item: Resource = _choose_item_data_for_floor(floor_number)
		_item_positions[spawn_position] = item


func _spawn_shopkeeper(generation_result: Dictionary, floor_number: int) -> void:
	if floor_number < 2:
		return
	if floor_number > 2 and randf() >= SHOP_SPAWN_CHANCE:
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


func _spawn_containers(generation_result: Dictionary, floor_number: int) -> void:
	var rooms: Array = generation_result.get("rooms", [])
	if rooms.size() <= 1:
		return
	var chest_limit: int = min(max(1, 1 + int(floor_number / 5)), max(1, int(rooms.size() / 3)))
	var clutter_limit: int = min(2 + int(floor_number / 8), 4)
	var chest_count: int = 0
	var clutter_count: int = 0
	for room_index: int in range(1, rooms.size()):
		var room: Rect2i = rooms[room_index]
		if chest_count < chest_limit and randf() < clampf(0.16 + floor_number * 0.015, 0.16, 0.45):
			var chest_cell: Vector2i = _find_free_container_cell(room)
			if chest_cell != Vector2i.ZERO:
				var rarity: int = _choose_chest_rarity(floor_number)
				_container_positions[chest_cell] = _make_chest_container(rarity)
				chest_count += 1
		if clutter_count < clutter_limit and randf() < 0.12:
			var clutter_cell: Vector2i = _find_free_container_cell(room)
			if clutter_cell != Vector2i.ZERO:
				_container_positions[clutter_cell] = _make_clutter_container()
				clutter_count += 1
	for secret_container: Dictionary in generation_result.get("secret_containers", []):
		var cell: Vector2i = secret_container.get("cell", Vector2i.ZERO)
		if cell == Vector2i.ZERO or _container_positions.has(cell):
			continue
		if secret_container.get("type", CONTAINER_TYPE_CHEST) == CONTAINER_TYPE_CLUTTER:
			_container_positions[cell] = _make_clutter_container()
		else:
			_container_positions[cell] = _make_chest_container(
				secret_container.get("rarity", _choose_chest_rarity(floor_number))
			)


func _find_free_container_cell(room: Rect2i) -> Vector2i:
	for attempt: int in range(8):
		var cell: Vector2i = _random_cell_in_room(room)
		if not _is_container_spawn_blocked(cell):
			return cell
	return Vector2i.ZERO


func _random_cell_in_room(room: Rect2i) -> Vector2i:
	var min_x: int = room.position.x + 1
	var max_x: int = room.end.x - 2
	var min_y: int = room.position.y + 1
	var max_y: int = room.end.y - 2
	if min_x > max_x or min_y > max_y:
		return room.get_center()
	return Vector2i(randi_range(min_x, max_x), randi_range(min_y, max_y))


func _is_container_spawn_blocked(cell: Vector2i) -> bool:
	if cell == _player.grid_position or cell == _stairs_position:
		return true
	if not _is_walkable(cell):
		return true
	if _item_positions.has(cell) or _trap_data.has(cell) or _container_positions.has(cell):
		return true
	if _is_shopkeeper_at(cell) or _get_enemy_at(cell) != null:
		return true
	return false


func _make_chest_container(rarity: int) -> Dictionary:
	var chest_rarity: int = clampi(
		rarity, ItemDataScript.ItemRarity.COMMON, ItemDataScript.RARITY_NAMES.size() - 1
	)
	return {
		"type": CONTAINER_TYPE_CHEST,
		"rarity": chest_rarity,
		"display_name": "%s Chest" % ItemDataScript.RARITY_NAMES[chest_rarity],
		"glyph": CHEST_GLYPHS[clampi(chest_rarity, 0, CHEST_GLYPHS.size() - 1)],
		"color": Color.html(ItemDataScript.RARITY_COLORS[chest_rarity]),
	}


func _make_clutter_container() -> Dictionary:
	var index: int = randi_range(0, CLUTTER_NAMES.size() - 1)
	return {
		"type": CONTAINER_TYPE_CLUTTER,
		"rarity": ItemDataScript.ItemRarity.COMMON,
		"display_name": CLUTTER_NAMES[index],
		"glyph": CLUTTER_GLYPHS[index],
		"color": CLUTTER_COLORS[index],
	}


# ===== Player Movement & Dash =====
func _attempt_player_move(direction: Vector2i) -> void:
	var target: Vector2i = _player.grid_position + direction
	if _is_closed_door(target):
		GameManager.map_data[target.y][target.x] = DungeonDataScript.TileType.OPEN_DOOR
		GameManager.add_log_message("You open the door.", &"neutral")
		_refresh_visibility()
		_refresh_map()
		_finish_player_action()
		return
	if not _is_walkable(target):
		if _revealed_secret_walls.has(target):
			_damage_secret_wall(target, 1, &"melee")
			_finish_player_action()
			return
		GameManager.add_log_message("You bump into stone.", &"warning")
		return

	if _is_shopkeeper_at(target):
		_open_shop()
		return

	var enemy: Node2D = _get_enemy_at(target)
	if enemy != null:
		_resolve_attack(_player, enemy)
		_finish_player_action()
		return

	if _trap_data.has(target) and _triggered_traps.has(target):
		GameManager.add_log_message("The spent trap mechanism crunches underfoot.", &"neutral")
	if _trap_data.has(target) and not _triggered_traps.has(target):
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
		_finish_player_action()
		return

	var dash_target: Vector2i = _get_dash_destination(direction, target)
	if dash_target != target:
		_dash_charge = 0
		target = dash_target
		GameManager.add_log_message("%s carries you two tiles." % DASH_LOG_NAME, &"magic")

	_player.set_grid_position(target)
	_collect_item_at(target)
	_open_container_at(target)
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
	_finish_player_action()


func _get_dash_destination(direction: Vector2i, first_cell: Vector2i) -> Vector2i:
	if not _is_dash_ready():
		return first_cell
	if (
		_item_positions.has(first_cell)
		or _container_positions.has(first_cell)
		or first_cell == _stairs_position
	):
		return first_cell
	var second_cell: Vector2i = first_cell + direction
	if not _is_walkable(second_cell):
		return first_cell
	if (
		_is_shopkeeper_at(second_cell)
		or _get_enemy_at(second_cell) != null
		or _trap_data.has(second_cell)
	):
		return first_cell
	return second_cell


func _is_dash_ready() -> bool:
	var dash_item: Resource = _get_dash_item()
	if dash_item == null:
		return false
	return _dash_charge >= max(1, dash_item.special_cooldown)


func _get_dash_item() -> Resource:
	var dash_items: Array[Resource] = _player.inventory_component.get_equipped_special_items(
		ItemDataScript.ItemSpecial.DASH_CHARGE
	)
	if dash_items.is_empty():
		return null
	return dash_items[0]


func _advance_dash_charge() -> void:
	var dash_item: Resource = _get_dash_item()
	if dash_item == null:
		_dash_charge = 0
		return
	var cooldown: int = max(1, dash_item.special_cooldown)
	if _dash_charge >= cooldown:
		return
	_dash_charge += 1
	if _dash_charge >= cooldown:
		GameManager.add_log_message(
			"%s is ready: your next clear move dashes two tiles." % DASH_LOG_NAME, &"magic"
		)


# ===== Combat Resolution =====
func _resolve_attack(attacker: Node, defender: Node) -> void:
	var damage_percent: int = _get_damage_percent(defender, &"melee")
	var outcome: Dictionary = CombatSystemScript.attack(attacker, defender, damage_percent)
	if outcome["hit"]:
		_log_damage_affinity(defender, &"melee", outcome["raw_damage"], outcome["damage"])
		var critical_text: String = " (critical)" if outcome["critical"] else ""
		GameManager.add_log_message(
			(
				"%s hits %s for %d melee damage%s."
				% [attacker.display_name, defender.display_name, outcome["damage"], critical_text]
			),
			&"combat_hit"
		)
	else:
		GameManager.add_log_message(
			"%s misses %s." % [attacker.display_name, defender.display_name], &"combat_miss"
		)

	_try_apply_attack_poison(attacker, defender, outcome)
	_handle_defender_after_damage(defender)


func _get_damage_percent(defender: Node, damage_type: StringName) -> int:
	var enemy_actor: Enemy = defender as Enemy
	if enemy_actor == null or enemy_actor.enemy_data == null:
		return 100
	match damage_type:
		&"melee":
			return enemy_actor.enemy_data.melee_damage_percent
		&"ranged":
			return enemy_actor.enemy_data.ranged_damage_percent
		&"magic":
			return enemy_actor.enemy_data.magic_damage_percent
	return 100


func _apply_typed_damage(defender: Node, raw_damage: int, damage_type: StringName) -> int:
	var damage_percent: int = _get_damage_percent(defender, damage_type)
	var damage: int = _scale_damage(raw_damage, damage_percent)
	_log_damage_affinity(defender, damage_type, raw_damage, damage)
	if damage > 0:
		defender.stats_component.apply_damage(damage)
	return damage


func _scale_damage(raw_damage: int, damage_percent: int) -> int:
	if damage_percent <= 0:
		return 0
	if damage_percent == 100:
		return raw_damage
	return max(1, int(round(raw_damage * damage_percent / 100.0)))


func _log_damage_affinity(
	defender: Node, damage_type: StringName, raw_damage: int, damage: int
) -> void:
	if raw_damage <= 0 or defender == null:
		return
	if damage <= 0:
		GameManager.add_log_message(
			(
				"%s is immune to %s damage (%d -> 0)."
				% [defender.display_name, damage_type, raw_damage]
			),
			&"warning"
		)
	elif damage < raw_damage:
		GameManager.add_log_message(
			(
				"%s resists %s damage (%d -> %d)."
				% [defender.display_name, damage_type, raw_damage, damage]
			),
			&"warning"
		)
	elif damage > raw_damage:
		GameManager.add_log_message(
			(
				"%s is vulnerable to %s damage (%d -> %d)."
				% [defender.display_name, damage_type, raw_damage, damage]
			),
			&"magic"
		)


func _try_apply_attack_poison(attacker: Node, defender: Node, outcome: Dictionary) -> void:
	var enemy_actor: Enemy = attacker as Enemy
	if not outcome.get("hit", false) or defender != _player or enemy_actor == null:
		return
	var poison_chance: int = enemy_actor.enemy_data.poison_chance_percent
	if poison_chance <= 0 or randi_range(1, 100) > poison_chance:
		return
	_poison_turns = max(_poison_turns, enemy_actor.enemy_data.poison_turns)
	_poison_damage_sides = max(2, enemy_actor.enemy_data.poison_damage_sides)
	GameManager.add_log_message(
		"%s poisons you for %d turns." % [attacker.display_name, _poison_turns], &"warning"
	)


func _handle_defender_after_damage(defender: Node) -> void:
	if defender == _player:
		GameManager.emit_player_damaged()
		if not _player.is_alive():
			_game_over(false)
	elif not defender.is_alive():
		var xp_reward: int = defender.stats_component.xp_reward
		_grant_player_xp(xp_reward)
		GameManager.emit_xp_changed()
		_apply_player_kill_specials()


func _apply_player_kill_specials() -> void:
	var regen_items: Array[Resource] = _player.inventory_component.get_equipped_special_items(
		ItemDataScript.ItemSpecial.KILL_REGEN_PERCENT
	)
	for item: Resource in regen_items:
		var heal_amount: int = max(
			1, int(ceil(_player.stats_component.max_hp * item.special_amount / 100.0))
		)
		var before_hp: int = _player.stats_component.current_hp
		_player.stats_component.heal(heal_amount)
		var healed: int = _player.stats_component.current_hp - before_hp
		if healed > 0:
			GameManager.emit_player_damaged()
			GameManager.add_log_message(
				"%s drinks the kill and restores %d HP." % [item.display_name, healed], &"heal"
			)


# ===== Items & Containers =====
func _collect_item_at(cell: Vector2i) -> void:
	if not _item_positions.has(cell):
		return
	var item: Resource = _item_positions[cell]
	_player.inventory_component.add_item(item)
	_item_positions.erase(cell)
	GameManager.add_log_message("You pick up %s." % item.display_name, &"loot")
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)


func _open_container_at(cell: Vector2i) -> void:
	if not _container_positions.has(cell):
		return
	var container_data: Dictionary = _container_positions[cell]
	_container_positions.erase(cell)
	if container_data.get("type", CONTAINER_TYPE_CHEST) == CONTAINER_TYPE_CLUTTER:
		_open_clutter_container(container_data)
	else:
		_open_chest_container(container_data)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)
	hud.bind_player(_player)


func _open_clutter_container(container_data: Dictionary) -> void:
	var display_name: String = container_data.get("display_name", "container")
	if display_name.contains("Vase") and randf() < VASE_XP_ORB_CHANCE:
		_grant_xp_orb(display_name)
		return
	if randf() < 0.40:
		var potion: Resource = _find_item_by_display_name("Health Potion")
		if potion != null:
			_player.inventory_component.add_item(potion.duplicate(true))
			GameManager.add_log_message(
				"You search the %s and find a Health Potion." % display_name, &"loot"
			)
			return
	var gold: int = randi_range(2, 8) + max(0, GameManager.current_floor - 1)
	_player.stats_component.gold += gold
	GameManager.add_log_message(
		"You search the %s and find %d gold." % [display_name, gold], &"gold"
	)


func _grant_xp_orb(display_name: String) -> void:
	var percent: int = randi_range(VASE_XP_MIN_PERCENT, VASE_XP_MAX_PERCENT)
	var xp_amount: int = max(
		1, int(ceil(_player.stats_component.xp_for_next_level() * percent / 100.0))
	)
	_grant_player_xp(xp_amount)
	GameManager.emit_xp_changed()
	GameManager.add_log_message(
		"An XP orb glows inside the %s. +%d XP." % [display_name, xp_amount], &"level"
	)


func _open_chest_container(container_data: Dictionary) -> void:
	var rarity: int = container_data.get("rarity", ItemDataScript.ItemRarity.COMMON)
	var display_name: String = container_data.get("display_name", "Chest")
	var gold: int = randi_range(
		10 + GameManager.current_floor * 2 + rarity * 12,
		24 + GameManager.current_floor * 5 + rarity * 28
	)
	_player.stats_component.gold += gold
	GameManager.add_log_message("You open the %s and find %d gold." % [display_name, gold], &"gold")
	var item_count: int = 1
	if rarity >= ItemDataScript.ItemRarity.RARE and randf() < 0.50:
		item_count += 1
	if rarity >= ItemDataScript.ItemRarity.MYTHIC and randf() < 0.35:
		item_count += 1
	for index: int in range(item_count):
		var reward: Resource = _choose_chest_reward_item(rarity, GameManager.current_floor)
		if reward == null:
			continue
		var reward_item: Resource = reward.duplicate(true)
		_player.inventory_component.add_item(reward_item)
		GameManager.add_log_message(
			"Inside the %s: %s." % [display_name, reward_item.display_name], &"loot"
		)


func _choose_chest_reward_item(chest_rarity: int, floor_number: int) -> Resource:
	var reward_floor: int = floor_number + chest_rarity * 2
	var candidates: Array[Resource] = _get_item_candidates_for_floor(reward_floor)
	var filtered: Array[Resource] = []
	var minimum_rarity: int = max(0, chest_rarity - 2)
	var maximum_rarity: int = chest_rarity
	for item_data: Resource in candidates:
		if item_data.rarity >= minimum_rarity and item_data.rarity <= maximum_rarity:
			filtered.append(item_data)
	if filtered.is_empty():
		filtered = candidates
	if filtered.is_empty():
		return null
	return _choose_weighted_item(filtered, reward_floor)


func _find_item_by_display_name(display_name: String) -> Resource:
	for item_data: Resource in _item_resources:
		if item_data.display_name == display_name:
			return item_data
	return null


# ===== Stairs, Status & Turn End =====
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


func _apply_regen_tick() -> void:
	if _regen_turns <= 0:
		return
	_regen_turns -= 1
	var before_hp: int = _player.stats_component.current_hp
	_player.stats_component.heal(_regen_heal_amount)
	var healed: int = _player.stats_component.current_hp - before_hp
	if healed > 0:
		GameManager.emit_player_damaged()
		GameManager.add_log_message("Regeneration restores %d HP." % healed, &"heal")


func _apply_poison_tick() -> bool:
	if _poison_turns <= 0:
		return true
	_poison_turns -= 1
	var damage: int = Dice.roll(_poison_damage_sides)
	_player.stats_component.apply_damage(damage)
	GameManager.emit_player_damaged()
	GameManager.add_log_message(
		(
			"Poison deals %d damage (%d turn%s left)."
			% [damage, _poison_turns, "" if _poison_turns == 1 else "s"]
		),
		&"warning"
	)
	if not _player.is_alive():
		_game_over(false)
		return false
	return true


func _end_player_turn() -> void:
	if _shield_turns > 0:
		_shield_turns -= 1
	if not _apply_poison_tick():
		return
	_apply_regen_tick()
	_advance_dash_charge()
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


# ===== Enemy AI =====
func _process_enemy_turns() -> void:
	var blocked_cells: Dictionary = {}
	for enemy in _enemies:
		if enemy != null and enemy.is_alive():
			blocked_cells[enemy.grid_position] = true
	if _shopkeeper != null:
		blocked_cells[_shopkeeper.grid_position] = true
	blocked_cells[_player.grid_position] = true

	for enemy in _enemies.duplicate():
		if enemy == null or not enemy.is_alive():
			continue
		if _is_enemy_sleeping(enemy):
			continue
		blocked_cells.erase(enemy.grid_position)
		var distance_to_player: float = enemy.grid_position.distance_to(_player.grid_position)
		var action_count: int = _advance_enemy_action(enemy)
		if _process_enemy_special_turn(enemy, distance_to_player, action_count, blocked_cells):
			if not _player.is_alive():
				return
		elif distance_to_player <= 1.1:
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


func _advance_enemy_action(enemy: Node) -> int:
	var action_count: int = int(_enemy_action_counts.get(enemy, 0)) + 1
	_enemy_action_counts[enemy] = action_count
	return action_count


func _process_enemy_special_turn(
	enemy: Node, distance_to_player: float, action_count: int, blocked_cells: Dictionary
) -> bool:
	var enemy_actor: Enemy = enemy as Enemy
	if enemy_actor == null or enemy_actor.enemy_data == null:
		return false
	var enemy_data: Resource = enemy_actor.enemy_data
	var recovering_from_shot: bool = _ranged_recovery_enemies.has(enemy)
	if recovering_from_shot:
		_ranged_recovery_enemies.erase(enemy)
	if (
		enemy_data.summon_interval > 0
		and action_count % enemy_data.summon_interval == 0
		and _visible_cells.has(enemy.grid_position)
		and _try_enemy_summon(enemy, blocked_cells)
	):
		return true
	if (
		enemy_data.fireball_range > 0
		and distance_to_player > 1.1
		and distance_to_player <= enemy_data.fireball_range
		and (action_count - 1) % max(1, enemy_data.fireball_interval) == 0
	):
		_resolve_enemy_fireball(enemy)
		return true
	if enemy_data.ranged_attack_range > 0:
		if (
			not recovering_from_shot
			and distance_to_player <= 1.1
			and enemy_data.ai_preferred_range > 1
			and _try_enemy_keep_range(enemy, blocked_cells)
		):
			return true
		if distance_to_player <= enemy_data.ranged_attack_range:
			if (action_count - 1) % max(1, enemy_data.ranged_attack_interval) == 0:
				_resolve_enemy_ranged_attack(enemy)
				_ranged_recovery_enemies[enemy] = true
				return true
			if (
				not recovering_from_shot
				and enemy_data.ai_preferred_range > 0
				and distance_to_player < enemy_data.ai_preferred_range
				and _try_enemy_keep_range(enemy, blocked_cells)
			):
				return true
			return distance_to_player > 1.1
	return false


func _try_enemy_keep_range(enemy: Node, blocked_cells: Dictionary) -> bool:
	var enemy_actor: Enemy = enemy as Enemy
	if enemy_actor == null or enemy_actor.enemy_data == null:
		return false
	var preferred_range: int = max(1, enemy_actor.enemy_data.ai_preferred_range)
	var attack_range: int = max(1, enemy_actor.enemy_data.ranged_attack_range)
	var current_distance: float = enemy.grid_position.distance_to(_player.grid_position)
	var best_cell: Vector2i = enemy.grid_position
	var best_distance: float = current_distance
	var best_score: float = absf(current_distance - float(preferred_range))
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var cell: Vector2i = enemy.grid_position + direction
		if not _is_free_enemy_spawn_cell(cell, blocked_cells):
			continue
		var distance: float = cell.distance_to(_player.grid_position)
		if distance > attack_range:
			continue
		var score: float = absf(distance - float(preferred_range))
		if score < best_score or (score == best_score and distance > best_distance):
			best_cell = cell
			best_distance = distance
			best_score = score
	if best_cell == enemy.grid_position:
		return false
	enemy.set_grid_position(best_cell)
	return true


func _resolve_enemy_ranged_attack(enemy: Node) -> void:
	var enemy_actor: Enemy = enemy as Enemy
	var enemy_data: Resource = enemy_actor.enemy_data
	var damage_sides: int = max(2, enemy_data.ranged_damage_sides)
	var damage: int = max(1, Dice.roll(damage_sides) + enemy_data.ranged_damage_bonus)
	var damage_type: StringName = enemy_data.ranged_damage_type
	if damage_type == &"":
		damage_type = &"piercing"
	_player.stats_component.apply_damage(damage)
	var action_text: String = "casts a spell at" if damage_type == &"magic" else "shoots"
	var message_type: StringName = &"magic" if damage_type == &"magic" else &"combat_hit"
	GameManager.add_log_message(
		"%s %s you for %d %s damage." % [enemy.display_name, action_text, damage, damage_type],
		message_type
	)
	_handle_defender_after_damage(_player)


func _resolve_enemy_fireball(enemy: Node) -> void:
	var enemy_actor: Enemy = enemy as Enemy
	var enemy_data: Resource = enemy_actor.enemy_data
	var raw_damage: int = enemy_data.fireball_damage_bonus
	for _die_index: int in range(max(1, enemy_data.fireball_damage_dice)):
		raw_damage += Dice.roll(max(2, enemy_data.fireball_damage_sides))
	var damage: int = max(1, raw_damage)
	_player.stats_component.apply_damage(damage)
	GameManager.add_log_message(
		"%s hurls a fireball at you for %d fire damage." % [enemy.display_name, damage], &"magic"
	)
	_handle_defender_after_damage(_player)


func _try_enemy_summon(enemy: Node, blocked_cells: Dictionary) -> bool:
	var enemy_actor: Enemy = enemy as Enemy
	var enemy_data: Resource = enemy_actor.enemy_data
	var active_minions: int = _count_summoned_minions(enemy)
	if active_minions >= enemy_data.summon_max_active:
		return false
	var summon_data: Resource = load(enemy_data.summon_enemy_path)
	if summon_data == null:
		return false
	var summon_count: int = min(
		enemy_data.summon_count, enemy_data.summon_max_active - active_minions
	)
	var spawned: int = 0
	for _index: int in range(summon_count):
		var summon_cell: Vector2i = _find_summon_cell(enemy.grid_position, blocked_cells)
		if summon_cell == Vector2i.ZERO:
			break
		var minion: Node2D = _spawn_enemy_instance(
			summon_data, summon_cell, GameManager.current_floor, false
		)
		minion.set_meta("summoned_minion", true)
		minion.set_meta("summoner_id", enemy.get_instance_id())
		minion.stats_component.max_hp = max(4, int(ceil(minion.stats_component.max_hp * 0.6)))
		minion.stats_component.current_hp = minion.stats_component.max_hp
		minion.stats_component.base_attack_bonus = max(
			1, minion.stats_component.base_attack_bonus - 1
		)
		minion.stats_component.base_damage_bonus = max(
			0, minion.stats_component.base_damage_bonus - 1
		)
		minion.stats_component.xp_reward = 0
		blocked_cells[summon_cell] = true
		spawned += 1
	if spawned > 0:
		GameManager.add_log_message(
			(
				"%s raises %d brittle skeleton%s."
				% [enemy.display_name, spawned, "" if spawned == 1 else "s"]
			),
			&"magic"
		)
		return true
	return false


func _count_summoned_minions(enemy: Node) -> int:
	var count: int = 0
	var summoner_id: int = enemy.get_instance_id()
	for candidate in _enemies:
		if (
			candidate != null
			and candidate.is_alive()
			and candidate.get_meta("summoner_id", 0) == summoner_id
		):
			count += 1
	return count


func _find_summon_cell(origin: Vector2i, blocked_cells: Dictionary) -> Vector2i:
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var cell: Vector2i = origin + direction
		if _is_free_enemy_spawn_cell(cell, blocked_cells):
			return cell
	for y_offset: int in range(-1, 2):
		for x_offset: int in range(-1, 2):
			var cell: Vector2i = origin + Vector2i(x_offset, y_offset)
			if _is_free_enemy_spawn_cell(cell, blocked_cells):
				return cell
	return Vector2i.ZERO


func _is_free_enemy_spawn_cell(cell: Vector2i, blocked_cells: Dictionary) -> bool:
	return (
		cell != Vector2i.ZERO
		and _is_walkable(cell)
		and not blocked_cells.has(cell)
		and not _trap_data.has(cell)
		and not _container_positions.has(cell)
		and not _is_shopkeeper_at(cell)
		and _get_enemy_at(cell) == null
	)


# ===== Visibility & Map =====
func _refresh_visibility() -> void:
	_visible_cells = FOVSystemScript.calculate_visible_cells(
		_player.grid_position, _get_fov_radius(), GameManager.map_data
	)
	for cell: Vector2i in _visible_cells.keys():
		_explored_cells[cell] = true
	_search_for_secret_walls(true)


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
	map_view.set_containers(_container_positions)
	map_view.set_targeting(
		_targeting_active, _target_cursor, _targeting_range_cells, _targeting_area_cells
	)
	map_view.set_traps(_trap_data, _revealed_traps, _triggered_traps)
	map_view.set_secret_walls(_secret_walls, _revealed_secret_walls, SECRET_WALL_HINT_COLOR)
	hud.bind_player(_player)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)


func _is_walkable(cell: Vector2i) -> bool:
	if cell.y < 0 or cell.y >= GameManager.map_data.size():
		return false
	if cell.x < 0 or cell.x >= GameManager.map_data[0].size():
		return false
	return DungeonDataScript.is_walkable(GameManager.map_data[cell.y][cell.x])


func _is_closed_door(cell: Vector2i) -> bool:
	if not _is_inside_map(cell):
		return false
	return GameManager.map_data[cell.y][cell.x] == DungeonDataScript.TileType.DOOR


func _get_enemy_at(cell: Vector2i) -> Node2D:
	for enemy in _enemies:
		if enemy != null and enemy.is_alive() and enemy.grid_position == cell:
			return enemy
	return null


func _is_shopkeeper_at(cell: Vector2i) -> bool:
	return (
		_shopkeeper != null and is_instance_valid(_shopkeeper) and _shopkeeper.grid_position == cell
	)


# ===== Shopkeeper Placement =====
func _open_shop() -> void:
	inventory_panel.visible = false
	character_sheet.visible = false
	shop_panel.refresh(_player, _shop_stock, _get_shop_reroll_cost())
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
			if (
				cell != blocked_cell
				and not _secret_floor_cells.has(cell)
				and DungeonDataScript.is_walkable(GameManager.map_data[y][x])
			):
				walkable_count += 1

	var frontier: Array[Vector2i] = [origin]
	var visited: Dictionary = {origin: true}
	var cursor: int = 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if (
				neighbor == blocked_cell
				or visited.has(neighbor)
				or _secret_floor_cells.has(neighbor)
				or not _is_walkable(neighbor)
			):
				continue
			visited[neighbor] = true
			frontier.append(neighbor)
	return visited.size() == walkable_count


# ===== Perception, FOV & Secrets =====
func _get_perception_bonus() -> int:
	if _player == null:
		return 0
	return Dice.modifier(_player.stats_component.wisdom) + _player.stats_component.proficiency_bonus


func _get_fov_radius() -> int:
	if _player == null:
		return BASE_FOV_RADIUS
	var intelligence: int = _player.stats_component.intelligence
	if intelligence >= INT_FOV_MASTER_SCORE:
		return BASE_FOV_RADIUS + 2
	if intelligence >= INT_FOV_BONUS_SCORE:
		return BASE_FOV_RADIUS + 1
	return BASE_FOV_RADIUS


func _get_secret_sense_bonus() -> int:
	if _player == null:
		return 0
	var stats: Node = _player.stats_component
	return (
		max(Dice.modifier(stats.wisdom), Dice.modifier(stats.intelligence))
		+ stats.proficiency_bonus
	)


func _search_for_secret_walls(passive: bool) -> int:
	var revealed_count: int = 0
	if _secret_walls.is_empty():
		return revealed_count
	var sense_bonus: int = _get_secret_sense_bonus()
	var base_chance: float = 0.18 if passive else 0.55
	var per_bonus: float = 0.055 if passive else 0.08
	var chance: float = clampf(base_chance + max(0, sense_bonus) * per_bonus, base_chance, 0.95)
	for cell: Vector2i in _secret_walls.keys():
		if _revealed_secret_walls.has(cell):
			continue
		if passive and not _visible_cells.has(cell):
			continue
		if not passive and cell.distance_to(_player.grid_position) > SECRET_WALL_LISTEN_RADIUS:
			continue
		if not passive and not _visible_cells.has(cell) and not _explored_cells.has(cell):
			continue
		if randf() <= chance:
			_revealed_secret_walls[cell] = true
			revealed_count += 1
	return revealed_count


func _damage_secret_wall(cell: Vector2i, amount: int, source: StringName) -> bool:
	if not _secret_walls.has(cell):
		return false
	var wall_data: Dictionary = _secret_walls[cell]
	var hp: int = wall_data.get("hp", SECRET_WALL_HP) - amount
	wall_data["hp"] = hp
	_secret_walls[cell] = wall_data
	if hp <= 0:
		GameManager.map_data[cell.y][cell.x] = DungeonDataScript.TileType.FLOOR
		_secret_walls.erase(cell)
		_revealed_secret_walls.erase(cell)
		GameManager.add_log_message("The weak wall collapses, revealing a hidden passage.", &"loot")
		_refresh_visibility()
	else:
		var method: String = "shot" if source == &"weapon" or source == &"consumable" else "strike"
		GameManager.add_log_message(
			"The suspicious wall cracks under your %s." % method, &"warning"
		)
	_refresh_map()
	return true


func _refresh_trap_aftermath() -> void:
	GameManager.emit_player_damaged()
	_refresh_visibility()
	_refresh_map()


# ===== Consumable Use & Targeting =====
func _use_potion() -> void:
	_open_consumable_menu()


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
			if _player.stats_component.current_hp >= _player.stats_component.max_hp:
				GameManager.add_log_message(
					"That would be a waste — you're already at full HP.", &"warning"
				)
				used = false
			else:
				_player.inventory_component.remove_item(item)
				var before_hp: int = _player.stats_component.current_hp
				_player.stats_component.heal(_get_potion_heal_amount(item))
				var healed: int = _player.stats_component.current_hp - before_hp
				GameManager.emit_player_damaged()
				GameManager.add_log_message(
					"You drink %s and recover %d HP." % [item.display_name, healed], &"heal"
				)
				_refresh_map()
				_finish_player_action()
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
			_finish_player_action()
		ItemDataScript.ItemUse.HASTE:
			_player.inventory_component.remove_item(item)
			_haste_enemy_phases = max(_haste_enemy_phases, item.effect_duration)
			GameManager.add_log_message(
				"%s makes your next move too fast to answer." % item.display_name, &"magic"
			)
			_refresh_map()
			_finish_player_action()
		ItemDataScript.ItemUse.REGEN:
			_player.inventory_component.remove_item(item)
			_regen_turns = max(_regen_turns, item.effect_duration)
			_regen_heal_amount = max(_regen_heal_amount, item.healing_amount)
			GameManager.add_log_message(
				"%s starts mending your wounds over time." % item.display_name, &"magic"
			)
			_refresh_map()
			_finish_player_action()
		ItemDataScript.ItemUse.RANGED_ATTACK:
			_start_targeting(item, &"consumable")
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			_start_targeting(item, &"consumable")
		ItemDataScript.ItemUse.SLEEP:
			_start_targeting(item, &"consumable")
		ItemDataScript.ItemUse.AREA_DAMAGE:
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
	if _is_escape_key(event) or event.is_action_pressed(&"fire_ranged"):
		_cancel_targeting()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_confirm_targeting()
		get_viewport().set_input_as_handled()
	elif direction != Vector2i.ZERO:
		_move_target_cursor(direction)
		get_viewport().set_input_as_handled()


func _start_targeting(item: Resource, source: StringName) -> void:
	_targeting_active = true
	_targeting_item = item
	_targeting_source = source
	_targeting_range_cells = _get_target_range_cells(item.range)
	_target_cursor = _nearest_targetable_enemy_cell(item.range)
	if _target_cursor == Vector2i.ZERO:
		_target_cursor = _player.grid_position
	_refresh_targeting_area()
	inventory_panel.visible = false
	character_sheet.visible = false
	consumable_panel.visible = false
	var area_hint: String = ""
	if _is_area_targeting_item(item):
		area_hint = " Radius %d is highlighted." % item.target_radius
	GameManager.add_log_message(
		(
			"Choose a target for %s.%s WASD moves marker; Enter confirms; F or Esc cancels."
			% [item.display_name, area_hint]
		),
		&"neutral"
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


func _refresh_targeting_area() -> void:
	_targeting_area_cells = _get_target_area_cells(_targeting_item, _target_cursor)


func _get_target_area_cells(item: Resource, center: Vector2i) -> Dictionary:
	var area_cells: Dictionary = {}
	if item == null or not _is_area_targeting_item(item):
		return area_cells
	if not _visible_cells.has(center) or not _targeting_range_cells.has(center):
		return area_cells
	var radius: int = max(0, item.target_radius)
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _is_inside_map(cell):
				continue
			if center.distance_to(cell) > radius:
				continue
			if _visible_cells.has(cell) and _explored_cells.has(cell):
				area_cells[cell] = true
	return area_cells


func _is_area_targeting_item(item: Resource) -> bool:
	return (
		item != null
		and (
			item.use_effect == ItemDataScript.ItemUse.AREA_DAMAGE
			or item.use_effect == ItemDataScript.ItemUse.SLEEP
		)
	)


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
	_refresh_targeting_area()
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
	_finish_player_action()


func _is_valid_target_cell(cell: Vector2i, item: Resource) -> bool:
	if not _visible_cells.has(cell) or not _targeting_range_cells.has(cell):
		return false
	if (
		_revealed_secret_walls.has(cell)
		and (
			item.use_effect == ItemDataScript.ItemUse.RANGED_ATTACK
			or item.use_effect == ItemDataScript.ItemUse.MAGIC_MISSILE
			or item.use_effect == ItemDataScript.ItemUse.AREA_DAMAGE
		)
	):
		return true
	if (
		item.use_effect == ItemDataScript.ItemUse.SLEEP
		or item.use_effect == ItemDataScript.ItemUse.AREA_DAMAGE
	):
		return true
	return _get_enemy_at(cell) != null


func _resolve_targeted_item(item: Resource, cell: Vector2i, source: StringName) -> bool:
	if _revealed_secret_walls.has(cell):
		_damage_secret_wall(cell, 1, source)
		return true
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
			var missile_raw_damage: int = _roll_item_damage(item, _get_magic_damage_bonus())
			var missile_damage: int = _apply_typed_damage(
				missile_target, missile_raw_damage, &"magic"
			)
			GameManager.add_log_message(
				(
					"%s hits %s for %d force damage."
					% [item.display_name, missile_target.display_name, missile_damage]
				),
				&"magic"
			)
			_handle_defender_after_damage(missile_target)
			return true
		ItemDataScript.ItemUse.AREA_DAMAGE:
			return _resolve_area_damage(item, cell)
		ItemDataScript.ItemUse.SLEEP:
			return _resolve_sleep(item, cell)
	return false


func _resolve_ranged_attack(item: Resource, defender: Node2D, source: StringName) -> void:
	var roll_result: int = Dice.d20()
	var close_weapon_shot: bool = (
		source == &"weapon" and defender.grid_position.distance_to(_player.grid_position) <= 2.0
	)
	if close_weapon_shot:
		roll_result = min(roll_result, Dice.d20())
		GameManager.add_log_message("Too close for a clean shot — disadvantage.", &"warning")
	var stats: Node = _player.stats_component
	var inventory: Node = _player.inventory_component
	var ability_bonus: int = Dice.modifier(stats.dexterity)
	var accessory_accuracy_bonus: int = inventory.get_accessory_attack_bonus()
	if source == &"consumable":
		ability_bonus = _get_scroll_hit_bonus()
		accessory_accuracy_bonus = 0
	var attack_total: int = (
		roll_result
		+ stats.proficiency_bonus
		+ ability_bonus
		+ item.attack_bonus
		+ accessory_accuracy_bonus
	)
	var is_critical: bool = roll_result == 20
	var hit: bool = is_critical or attack_total >= defender.stats_component.get_armor_class()
	if hit:
		var damage_bonus: int = _get_magic_damage_bonus()
		if source == &"weapon":
			damage_bonus = Dice.modifier(stats.dexterity) + inventory.get_accessory_damage_bonus()
		var raw_damage: int = _roll_item_damage(item, damage_bonus)
		if is_critical:
			raw_damage += _roll_item_base_dice(item)
		if item.special_effect == ItemDataScript.ItemSpecial.CURRENT_HP_DAMAGE_PERCENT:
			var percent_damage: int = max(
				1, int(ceil(defender.stats_component.current_hp * item.special_amount / 100.0))
			)
			raw_damage += percent_damage
			GameManager.add_log_message(
				(
					"%s shears %d current HP from %s."
					% [item.display_name, percent_damage, defender.display_name]
				),
				&"magic"
			)
		var damage_type: StringName = &"ranged" if source == &"weapon" else &"magic"
		var damage: int = _apply_typed_damage(defender, raw_damage, damage_type)
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


func _resolve_area_damage(item: Resource, cell: Vector2i) -> bool:
	var affected_count: int = 0
	for enemy in _enemies:
		if enemy == null or not enemy.is_alive() or not _visible_cells.has(enemy.grid_position):
			continue
		if enemy.grid_position.distance_to(cell) <= item.target_radius:
			var raw_damage: int = _roll_item_damage(item, _get_magic_damage_bonus())
			var damage: int = _apply_typed_damage(enemy, raw_damage, &"magic")
			GameManager.add_log_message(
				(
					"%s erupts for %d damage around %s."
					% [item.display_name, damage, enemy.display_name]
				),
				&"magic"
			)
			_handle_defender_after_damage(enemy)
			affected_count += 1
	if affected_count <= 0:
		GameManager.add_log_message("No enemies are caught in the blast.", &"warning")
		return false
	return true


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


func _get_potion_heal_amount(item: Resource) -> int:
	var intelligence_modifier: int = max(0, Dice.modifier(_player.stats_component.intelligence))
	var scaled_bonus: int = floori(item.healing_amount * intelligence_modifier * 0.10)
	return item.healing_amount + intelligence_modifier + scaled_bonus


func _get_magic_damage_bonus() -> int:
	return max(0, Dice.modifier(_player.stats_component.wisdom) * 2)


func _get_scroll_hit_bonus() -> int:
	return Dice.modifier(_player.stats_component.wisdom)


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
	_targeting_area_cells.clear()
	map_view.set_targeting(false, Vector2i.ZERO, {}, {})
	GameManager.add_log_message("Targeting canceled.", &"neutral")
	_refresh_map()


func _clear_targeting() -> void:
	_targeting_active = false
	_targeting_item = null
	_targeting_source = &""
	_targeting_range_cells.clear()
	_targeting_area_cells.clear()
	map_view.set_targeting(false, Vector2i.ZERO, {}, {})


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


# ===== Enemy Death & Revival =====
func _on_enemy_died(enemy: Node) -> void:
	if _try_enemy_revive(enemy):
		hud.bind_player(_player)
		_refresh_map()
		return
	if enemy.get_meta("summoned_minion", false):
		GameManager.add_log_message(
			"%s crumbles into dust (summoned; no reward)." % enemy.display_name, &"death"
		)
	else:
		var gold_reward: int = _roll_enemy_gold_reward(enemy)
		_player.stats_component.gold += gold_reward
		GameManager.add_log_message(
			"%s dies. +%d gold." % [enemy.display_name, gold_reward], &"death"
		)
	_enemy_action_counts.erase(enemy)
	_ranged_recovery_enemies.erase(enemy)
	GameManager.remove_enemy(enemy)
	hud.bind_player(_player)
	_refresh_map()


func _try_enemy_revive(enemy: Node) -> bool:
	var enemy_actor: Enemy = enemy as Enemy
	if enemy_actor == null or enemy_actor.enemy_data == null:
		return false
	if enemy.get_meta("revived_once", false):
		return false
	var revive_chance: int = enemy_actor.enemy_data.revive_chance_percent
	if revive_chance <= 0 or randi_range(1, 100) > revive_chance:
		return false
	enemy.set_meta("revived_once", true)
	var revive_hp: int = max(
		1,
		int(ceil(enemy.stats_component.max_hp * enemy_actor.enemy_data.revive_hp_percent / 100.0))
	)
	enemy.stats_component.current_hp = revive_hp
	GameManager.add_log_message(
		"%s revives once, lurching back up with %d HP." % [enemy.display_name, revive_hp],
		&"warning"
	)
	return true


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


# ===== Shop Panel Callbacks =====
func _on_shop_panel_close_requested() -> void:
	shop_panel.visible = false


func _on_shop_panel_purchase_requested(stock_index: int) -> void:
	if stock_index < 0 or stock_index >= _shop_stock.size():
		return
	var item: Resource = _shop_stock[stock_index]
	var price: int = _get_item_shop_price(item)
	if _player.stats_component.gold < price:
		GameManager.add_log_message(
			(
				"%s costs %d gold; you need %d more."
				% [item.display_name, price, price - _player.stats_component.gold]
			),
			&"warning"
		)
		shop_panel.refresh(_player, _shop_stock, _get_shop_reroll_cost())
		return
	_player.stats_component.gold -= price
	_player.inventory_component.add_item(item.duplicate(true))
	_shop_stock.remove_at(stock_index)
	GameManager.add_log_message(
		(
			"You buy %s for %d gold. Gold left: %d."
			% [item.display_name, price, _player.stats_component.gold]
		),
		&"gold"
	)
	hud.bind_player(_player)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)
	shop_panel.refresh(_player, _shop_stock, _get_shop_reroll_cost())


func _on_shop_panel_sell_requested(inventory_index: int) -> void:
	var inventory: Node = _player.inventory_component
	if inventory_index < 0 or inventory_index >= inventory.items.size():
		return
	var item: Resource = inventory.items[inventory_index]
	var sell_price: int = _get_item_sell_price(item)
	inventory.remove_item(item)
	_player.stats_component.gold += sell_price
	_shop_stock.append(item)
	GameManager.add_log_message(
		(
			"You sell %s for %d gold. Gold now: %d."
			% [item.display_name, sell_price, _player.stats_component.gold]
		),
		&"gold"
	)
	hud.bind_player(_player)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)
	shop_panel.refresh(_player, _shop_stock, _get_shop_reroll_cost())


func _on_shop_panel_reroll_requested() -> void:
	var cost: int = _get_shop_reroll_cost()
	if _player.stats_component.gold < cost:
		GameManager.add_log_message(
			"Reroll costs %d gold; you need %d more." % [cost, cost - _player.stats_component.gold],
			&"warning"
		)
		shop_panel.refresh(_player, _shop_stock, cost)
		return
	_player.stats_component.gold -= cost
	_shop_reroll_count += 1
	_shop_stock = _generate_shop_stock(GameManager.current_floor)
	GameManager.add_log_message(
		(
			"You reroll shop stock for %d gold. Next reroll: %d gold."
			% [cost, _get_shop_reroll_cost()]
		),
		&"gold"
	)
	hud.bind_player(_player)
	shop_panel.refresh(_player, _shop_stock, _get_shop_reroll_cost())


func _get_shop_reroll_cost() -> int:
	return (
		(SHOP_REROLL_BASE_COST + GameManager.current_floor * SHOP_REROLL_FLOOR_COST)
		* (_shop_reroll_count + 1)
	)


# ===== Floor Scaling & Selection =====
func _scale_enemy_for_floor(enemy: Node, floor_number: int) -> void:
	var depth_bonus: int = max(0, floor_number - 1)
	var early_depth: int = min(depth_bonus, 9)
	var late_depth: int = max(0, depth_bonus - 9)
	var armor_bonus: int = int(depth_bonus / 6)
	var attack_bonus: int = int(depth_bonus / 5)
	var damage_bonus: int = int(max(0, depth_bonus - 2) / 6)
	enemy.stats_component.max_hp += early_depth + late_depth * 2
	enemy.stats_component.current_hp = enemy.stats_component.max_hp
	enemy.stats_component.base_armor_class += armor_bonus
	enemy.stats_component.base_attack_bonus += attack_bonus
	enemy.stats_component.base_damage_bonus += damage_bonus
	enemy.stats_component.xp_reward += depth_bonus * 7


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
		ItemDataScript.ItemRarity.ASCENDED:
			weight = max(0, depth * 2 - 22)
	return weight


func _choose_chest_rarity(floor_number: int) -> int:
	var total_weight: int = 0
	var weights: Array[int] = []
	for rarity: int in range(ItemDataScript.RARITY_NAMES.size()):
		var weight: int = _chest_rarity_weight_for_floor(rarity, floor_number)
		weights.append(weight)
		total_weight += weight
	if total_weight <= 0:
		return ItemDataScript.ItemRarity.COMMON
	var roll: int = randi_range(1, total_weight)
	var running_weight: int = 0
	for rarity: int in range(weights.size()):
		running_weight += weights[rarity]
		if roll <= running_weight:
			return rarity
	return ItemDataScript.ItemRarity.COMMON


func _chest_rarity_weight_for_floor(rarity: int, floor_number: int) -> int:
	var depth: int = max(0, floor_number - 1)
	match rarity:
		ItemDataScript.ItemRarity.COMMON:
			return max(8, 70 - depth * 6)
		ItemDataScript.ItemRarity.UNCOMMON:
			return 24 + depth * 2
		ItemDataScript.ItemRarity.RARE:
			return max(0, depth * 5 - 5)
		ItemDataScript.ItemRarity.EPIC:
			return max(0, depth * 4 - 14)
		ItemDataScript.ItemRarity.LEGENDARY:
			return max(0, depth * 3 - 20)
		ItemDataScript.ItemRarity.MYTHIC:
			return max(0, depth * 3 - 28)
		ItemDataScript.ItemRarity.ASCENDED:
			return max(0, depth * 2 - 24)
	return 0


# ===== Shop Stock Generation =====
func _get_effective_shop_floor(floor_number: int) -> int:
	var safe_floor: int = max(1, floor_number)
	return safe_floor + 1 + int(ceil(safe_floor * SHOP_EFFECTIVE_FLOOR_BONUS_FACTOR))


func _get_shop_stock_size(floor_number: int) -> int:
	var safe_floor: int = max(1, floor_number)
	var floor_bonus: int = clampi(int(safe_floor / 4), 0, SHOP_STOCK_MAX_BONUS)
	return SHOP_STOCK_SIZE + floor_bonus


func _get_shop_minimum_rarity(floor_number: int) -> int:
	if floor_number >= 14:
		return ItemDataScript.ItemRarity.EPIC
	if floor_number >= 10:
		return ItemDataScript.ItemRarity.RARE
	if floor_number >= 6:
		return ItemDataScript.ItemRarity.UNCOMMON
	return ItemDataScript.ItemRarity.COMMON


func _generate_shop_stock(floor_number: int) -> Array:
	var safe_floor: int = max(1, floor_number)
	var effective_floor: int = _get_effective_shop_floor(safe_floor)
	var candidates: Array[Resource] = _get_shop_candidates_for_floor(safe_floor, effective_floor)
	var stock: Array = []
	var potion: Resource = _choose_guaranteed_shop_potion(safe_floor, effective_floor)
	if potion != null:
		stock.append(potion)
		candidates.erase(potion)
	var luxury_item: Resource = _choose_luxury_shop_item(safe_floor, effective_floor)
	if luxury_item != null and not stock.has(luxury_item):
		stock.append(luxury_item)
		candidates.erase(luxury_item)

	while stock.size() < _get_shop_stock_size(safe_floor) and not candidates.is_empty():
		var item_data: Resource = _choose_weighted_shop_item(
			candidates, safe_floor, effective_floor
		)
		if item_data == null:
			break
		stock.append(item_data)
		candidates.erase(item_data)
	return stock


func _get_shop_candidates_for_floor(floor_number: int, effective_floor: int) -> Array[Resource]:
	var candidates: Array[Resource] = []
	var minimum_rarity: int = _get_shop_minimum_rarity(floor_number)
	for item_data: Resource in _item_resources:
		if not _can_spawn_item(item_data, effective_floor):
			continue
		if (
			item_data.rarity < minimum_rarity
			and item_data.kind != ItemDataScript.ItemKind.CONSUMABLE
		):
			continue
		candidates.append(item_data)
	if candidates.is_empty():
		return _get_item_candidates_for_floor(effective_floor)
	return candidates


func _choose_guaranteed_shop_potion(floor_number: int, effective_floor: int) -> Resource:
	var potion_candidates: Array[Resource] = []
	for item_data: Resource in _item_resources:
		if not _can_spawn_item(item_data, effective_floor):
			continue
		if item_data.kind == ItemDataScript.ItemKind.CONSUMABLE and item_data.healing_amount > 0:
			potion_candidates.append(item_data)
	if potion_candidates.is_empty():
		return null
	if floor_number <= 4 or floor_number >= 10:
		var best_potion: Resource = potion_candidates[0]
		for potion: Resource in potion_candidates:
			if potion.healing_amount > best_potion.healing_amount:
				best_potion = potion
		return best_potion
	return _choose_weighted_shop_item(potion_candidates, floor_number, effective_floor)


func _choose_luxury_shop_item(floor_number: int, effective_floor: int) -> Resource:
	var luxury_candidates: Array[Resource] = []
	var minimum_item_floor: int = min(
		effective_floor,
		max(floor_number + 1, floor_number + int(ceil(floor_number * SHOP_DEPTH_PICK_BONUS_FACTOR)))
	)
	var minimum_rarity: int = max(
		ItemDataScript.ItemRarity.RARE, _get_shop_minimum_rarity(floor_number)
	)
	for item_data: Resource in _item_resources:
		if not _can_spawn_item(item_data, effective_floor):
			continue
		if item_data.min_floor >= minimum_item_floor or item_data.rarity >= minimum_rarity:
			luxury_candidates.append(item_data)
	if luxury_candidates.is_empty():
		return null
	return _choose_weighted_shop_item(luxury_candidates, floor_number, effective_floor)


func _choose_weighted_shop_item(
	candidates: Array[Resource], floor_number: int, effective_floor: int
) -> Resource:
	if candidates.is_empty():
		return null
	var total_weight: int = 0
	for item_data: Resource in candidates:
		total_weight += _shop_item_weight(item_data, floor_number, effective_floor)
	if total_weight <= 0:
		return candidates[0]
	var roll: int = randi_range(1, total_weight)
	var running_weight: int = 0
	for item_data: Resource in candidates:
		running_weight += _shop_item_weight(item_data, floor_number, effective_floor)
		if roll <= running_weight:
			return item_data
	return candidates.back()


func _shop_item_weight(item_data: Resource, floor_number: int, effective_floor: int) -> int:
	var rarity_weight: int = _shop_rarity_weight_for_floor(item_data.rarity, effective_floor)
	if rarity_weight <= 0:
		return 0
	var safe_floor: int = max(1, floor_number)
	var item_floor: int = max(1, item_data.min_floor)
	var floor_weight_percent: int = 100 + item_floor * 25
	if item_floor >= safe_floor:
		floor_weight_percent += (item_floor - safe_floor + 1) * 70
	elif safe_floor - item_floor > 4:
		floor_weight_percent = max(15, floor_weight_percent - (safe_floor - item_floor - 4) * 20)
	if item_data.rarity < _get_shop_minimum_rarity(safe_floor):
		floor_weight_percent = max(10, int(floor_weight_percent * 0.35))
	return max(
		1, int(ceil(max(1, item_data.spawn_weight) * rarity_weight * floor_weight_percent / 100.0))
	)


func _shop_rarity_weight_for_floor(rarity: int, floor_number: int) -> int:
	var depth: int = max(0, floor_number - 1)
	match rarity:
		ItemDataScript.ItemRarity.COMMON:
			return max(1, 28 - depth * 6)
		ItemDataScript.ItemRarity.UNCOMMON:
			return max(4, 28 - depth * 2)
		ItemDataScript.ItemRarity.RARE:
			return 18 + depth * 5
		ItemDataScript.ItemRarity.EPIC:
			return max(0, depth * 8 - 18)
		ItemDataScript.ItemRarity.LEGENDARY:
			return max(0, depth * 9 - 30)
		ItemDataScript.ItemRarity.MYTHIC:
			return max(0, depth * 9 - 42)
		ItemDataScript.ItemRarity.ASCENDED:
			return max(0, depth * 10 - 55)
	return 0


# ===== Gold & Pricing =====
func _roll_enemy_gold_reward(enemy: Node = null) -> int:
	var floor_number: int = max(1, GameManager.current_floor)
	var base_reward: int = randi_range(6, 12)
	var depth_bonus: int = randi_range(1, max(1, floor_number * 2))
	var tier_bonus: int = int(floor_number / EXTRACTION_INTERVAL) * 2
	var reward: int = base_reward + depth_bonus + tier_bonus
	var enemy_actor: Enemy = enemy as Enemy
	if (
		enemy_actor != null
		and enemy_actor.enemy_data.gold_bonus_chance_percent > 0
		and randi_range(1, 100) <= enemy_actor.enemy_data.gold_bonus_chance_percent
	):
		var bonus: int = max(
			1, int(round(reward * enemy_actor.enemy_data.gold_bonus_percent / 100.0))
		)
		reward += bonus
		GameManager.add_log_message(
			"%s carried extra plunder: +%d bonus gold." % [enemy.display_name, bonus], &"gold"
		)
	return reward


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


func _get_item_sell_price(item: Resource) -> int:
	var cha_mod: int = Dice.modifier(_player.stats_component.charisma)
	var multiplier: float = clampf(0.35 + 0.02 * cha_mod, 0.25, 0.50)
	return max(1, floori(item.get_price() * multiplier))
