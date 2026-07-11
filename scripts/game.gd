## Main game scene controller: floor generation, combat, shop, containers,
## traps, items, and player input.
extends Node2D

# === Constants ===
const PLAYER_SCENE_NAME: String = "Player"
const FINAL_VICTORY_FLOOR: int = 25
const GOLD_TIER_FLOOR_SPAN: int = 3
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
]
const STARTER_WEAPON_FIGHTER: String = "res://resources/items/training_sword.tres"
const STARTER_WEAPON_RANGER: String = "res://resources/items/hunting_bow.tres"
const STARTER_WEAPON_WIZARD: String = "res://resources/items/apprentice_staff.tres"
const SHOP_STOCK_SIZE: int = 6
const SHOP_STOCK_MAX_BONUS: int = 3
const SHOP_EFFECTIVE_FLOOR_BONUS_FACTOR: float = 0.25
const SHOP_DEPTH_PICK_BONUS_FACTOR: float = 0.25
const SHOP_REROLL_BASE_COST: int = 15
const SHOP_REROLL_FLOOR_COST: int = 4
const BUILD_MATCH_WEIGHT_PERCENT: int = 190
const WRONG_CLASS_WEIGHT_PERCENT: int = 35
const SET_COMPLETION_WEIGHT_PERCENT: int = 260
const LATE_TRAP_DAMAGE_DEPTH_STEP: int = 4
const LATE_TRAP_MAX_DC_BONUS: int = 4
const PAUSE_VOLUME_SLIDER_PATH: String = "MasterVolumeRow/MasterVolumeSlider"
const PAUSE_VOLUME_VALUE_LABEL_PATH: String = "MasterVolumeRow/MasterVolumeValueLabel"
const PAUSE_REDUCED_VFX_BUTTON_PATH: String = "ReducedVfxButton"
const BOSS_FLOORS: Dictionary = {
	5: &"observer",
	10: &"seraphine",
	15: &"vorrak",
	20: &"kaelros",
	25: &"nyxara",
}
const BOSS_ARENA_STATE_WAITING_AT_GATE: StringName = &"waiting_at_gate"
const BOSS_ARENA_STATE_REVEAL: StringName = &"arena_reveal"
const BOSS_ARENA_STATE_ACTIVE: StringName = &"active"
const BOSS_ARENA_STATE_DEFEATED: StringName = &"defeated"
const BOSS_ARENA_REVEAL_SECONDS: float = 2.10
const BOSS_RESOURCE_BY_ID: Dictionary = {
	&"observer": "res://resources/enemies/the_observer.tres",
	&"seraphine": "res://resources/enemies/seraphine_thorn_saint.tres",
	&"vorrak": "res://resources/enemies/vorrak_ashen_maw.tres",
	&"kaelros": "res://resources/enemies/kaelros_drowned_king.tres",
	&"nyxara": "res://resources/enemies/nyxara_mirror_witch.tres",
}
const BOSS_STORY_BY_ID: Dictionary = {
	&"observer":
	{
		"kicker": "THE GATE UNBLINKS",
		"title": "THE OBSERVER",
		"subtitle": "A lidless eye turns the dungeon inside out.",
		"entry": "The boss gate opens into a sky that should not fit underground.",
	},
	&"seraphine":
	{
		"kicker": "THE THORNS PART",
		"title": "SERAPHINE, THORN SAINT",
		"subtitle": "A blooming reliquary drinks the torchlight.",
		"entry": "The boss gate flowers into a chapel of roots and bone.",
	},
	&"vorrak":
	{
		"kicker": "THE ASHEN MAW OPENS",
		"title": "VORRAK, THE ASHEN MAW",
		"subtitle": "Heat rolls across a battlefield of black glass.",
		"entry": "The boss gate tears open on cinders and a breathing furnace.",
	},
	&"kaelros":
	{
		"kicker": "THE DROWNED COURT RISES",
		"title": "KAELROS, DROWNED KING",
		"subtitle": "Cold surf beats against a throne below the world.",
		"entry": "The boss gate spills brine around your boots.",
	},
	&"nyxara":
	{
		"kicker": "THE MIRROR BREAKS",
		"title": "NYXARA, THE MIRROR WITCH",
		"subtitle": "Every reflection waits half a heartbeat late.",
		"entry": "The boss gate folds into a hall of impossible reflections.",
	},
}
const AMBUSH_APEX_EXCLUDE_NAMES: Array[String] = [
	"Ancient Dragon",
	"Void Herald",
	"Deep Maw",
	"Starved Godling",
]
const ACTION_BURST_LOOT_COLOR: Color = Color(1.0, 0.82, 0.18)
const ACTION_BURST_HIT_COLOR: Color = Color(1.0, 0.34, 0.47)
const ACTION_BURST_MAGIC_COLOR: Color = Color(0.68, 0.48, 1.0)
const ACTION_BURST_MISS_COLOR: Color = Color(0.64, 0.62, 0.50)
const ACTION_BURST_WARNING_COLOR: Color = Color(1.0, 0.54, 0.20)
const SHOPKEEPER_NAME: String = "Shopkeeper"
const SHOPKEEPER_GLYPH: String = "S"
const SHOPKEEPER_COLOR: Color = Color(1.0, 0.82, 0.32)
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")
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
const ProjectileSystemScript = preload("res://scripts/systems/projectile_system.gd")
const TrapDataScript = preload("res://scripts/resources/trap_data.gd")
const TrapSystem = preload("res://scripts/systems/trap_system.gd")
const CONTAINER_TYPE_CHEST: StringName = &"chest"
const CONTAINER_TYPE_CLUTTER: StringName = &"clutter"
const CHEST_GLYPHS: Array[String] = ["c", "c", "C", "C", "C", "C", "C"]
const CLUTTER_NAMES: Array[String] = ["Cracked Vase", "Old Box"]
const CLUTTER_GLYPHS: Array[String] = ["v", "b"]
const CLUTTER_COLORS: Array[Color] = [Color(0.55, 0.45, 0.35), Color(0.45, 0.34, 0.24)]
const SECRET_WALL_HP: int = 2
const MAGIC_MISSILE_DEFAULT_TARGET_COUNT: int = 3
const SCROLL_DAMAGE_DEPTH_STEP: int = 6
const SECRET_WALL_HINT_COLOR: Color = Color(0.72, 0.58, 1.0)
const SECRET_WALL_LISTEN_RADIUS: int = 8
const VASE_XP_ORB_CHANCE: float = 0.35
const VASE_XP_MIN_PERCENT: int = 5
const VASE_XP_MAX_PERCENT: int = 10
const DASH_LOG_NAME: String = "Windstep"
const BASE_FOV_RADIUS: int = 8
const INT_FOV_BONUS_SCORE: int = 15
const INT_FOV_MASTER_SCORE: int = 20
const STUN_TRAP_ACTIONS: int = 3
const AMBUSH_TRAP_ENEMY_COUNT: int = 3
const AMBUSH_TRAP_MIN_DISTANCE: int = 2
const AMBUSH_TRAP_MAX_DISTANCE: int = 5
const AMBUSH_BASIC_ENEMY_NAMES: Array[String] = [
	"Rat",
	"Goblin",
	"Kobold",
	"Skeleton",
	"Clockwork Spider",
	"Zombie",
	"Thorn Lasher",
	"Spore Servant",
	"Ash Revenant",
	"Ember Archer",
	"Drowned Knight",
	"Harpooner",
	"Mirror Duelist",
	"Shard Golem",
]

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
var _stun_actions: int = 0
var _enemy_action_counts: Dictionary = {}
var _sleeping_enemies: Dictionary = {}
var _ranged_recovery_enemies: Dictionary = {}
var _boss_states: Dictionary = {}
var _active_boss_encounter: Dictionary = {}
var _boss_telegraphs: Dictionary = {}
var _boss_hazards: Dictionary = {}
var _unknown_boss_attack_shapes: Dictionary = {}
var _boss_activation_timer: Timer
var _unknown_boss_hazard_effects: Dictionary = {}
var _trap_data: Dictionary = {}
var _revealed_traps: Dictionary = {}
var _triggered_traps: Dictionary = {}
var _trap_resources: Array = []
var _resume_turn_after_level_choice: bool = false
var _last_announced_biome_index: int = -1
var _biome_overlay_tween: Tween
var _fighter_cleave_charges: int = 0
var _fighter_second_wind_charges: int = 0
var _fighter_whirlwind_charges: int = 0
var _ranger_focus_charges: int = 0
var _ranger_volley_charges: int = 0
var _ranger_quickstep_charges: int = 0
var _wizard_spark_charges: int = 0
var _wizard_frost_nova_charges: int = 0
var _wizard_chain_lightning_charges: int = 0
var _cleave_primed: bool = false
var _hunter_focus_primed: bool = false

# === Onready ===
@onready var map_view: Node2D = $MapView
@onready var hud: Control = $UI/HUD
@onready var inventory_panel: PanelContainer = $UI/InventoryPanel
@onready var character_sheet: PanelContainer = $UI/CharacterSheet
@onready var shop_panel: PanelContainer = $UI/ShopPanel
@onready var consumable_panel: PanelContainer = $UI/ConsumablePanel
@onready var level_up_panel: LevelUpPanel = $UI/LevelUpPanel
@onready var biome_overlay: Control = $UI/BiomeOverlay
@onready var biome_overlay_panel: PanelContainer = $UI/BiomeOverlay/Center/Panel
@onready var biome_kicker_label: Label = $UI/BiomeOverlay/Center/Panel/Margin/VBox/KickerLabel
@onready var biome_title_label: Label = $UI/BiomeOverlay/Center/Panel/Margin/VBox/TitleLabel
@onready var biome_divider: ColorRect = $UI/BiomeOverlay/Center/Panel/Margin/VBox/Divider
@onready var biome_subtitle_label: Label = $UI/BiomeOverlay/Center/Panel/Margin/VBox/SubtitleLabel
@onready var extraction_panel: PanelContainer = $UI/ExtractionPanel
@onready var extraction_title_label: Label = $UI/ExtractionPanel/Margin/VBox/TitleLabel
@onready var extraction_label: Label = $UI/ExtractionPanel/Margin/VBox/PromptLabel
@onready var leave_button: Button = $UI/ExtractionPanel/Margin/VBox/Buttons/LeaveButton
@onready var descend_button: Button = $UI/ExtractionPanel/Margin/VBox/Buttons/DescendButton
@onready var pause_panel: PanelContainer = $UI/PausePanel
@onready var pause_hint_label: Label = $UI/PausePanel/Margin/VBox/HintLabel
@onready var pause_resume_button: Button = $UI/PausePanel/Margin/VBox/ResumeButton
@onready var pause_main_menu_button: Button = $UI/PausePanel/Margin/VBox/MainMenuButton
@onready var debug_descend_button: Button = $UI/PausePanel/Margin/VBox/DebugDescendButton
@onready var sensory_feedback: Control = $UI/SensoryFeedback
@onready var pause_menu_box: VBoxContainer = $UI/PausePanel/Margin/VBox
@onready var pause_audio_header_label: Label = pause_menu_box.get_node("AudioHeaderLabel")
@onready var pause_audio_enabled_button: CheckButton = pause_menu_box.get_node("AudioEnabledButton")
@onready var pause_master_volume_slider: HSlider = pause_menu_box.get_node(PAUSE_VOLUME_SLIDER_PATH)
@onready
var pause_master_volume_value_label: Label = pause_menu_box.get_node(PAUSE_VOLUME_VALUE_LABEL_PATH)
@onready
var pause_ambience_enabled_button: CheckButton = pause_menu_box.get_node("AmbienceEnabledButton")
@onready
var pause_reduced_vfx_button: CheckButton = pause_menu_box.get_node(PAUSE_REDUCED_VFX_BUTTON_PATH)
@onready var turn_manager: Node = $TurnManager
@onready var class_ability_panel: PanelContainer = $UI/ClassAbilityPanel


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
	class_ability_panel.connect("close_requested", _on_class_ability_panel_close_requested)
	class_ability_panel.connect("ability_requested", _on_class_ability_requested)
	class_ability_panel.visibility_changed.connect(_refresh_overlay_visibility)
	consumable_panel.visibility_changed.connect(_refresh_overlay_visibility)
	# Audio controls
	pause_audio_enabled_button.toggled.connect(_on_audio_enabled_toggled)
	pause_master_volume_slider.value_changed.connect(_on_volume_slider_changed)
	pause_ambience_enabled_button.toggled.connect(_on_ambience_enabled_toggled)
	pause_reduced_vfx_button.toggled.connect(_on_reduced_vfx_toggled)
	_setup_boss_activation_timer()
	_refresh_audio_controls()
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
	if _is_boss_arena_revealing():
		return
	if (
		not GameManager.is_player_turn
		or extraction_panel.visible
		or shop_panel.visible
		or pause_panel.visible
		or consumable_panel.visible
		or level_up_panel.visible
		or class_ability_panel.visible
	):
		return
	if _targeting_active:
		_handle_targeting_input(event)
	elif _is_escape_key(event):
		_close_open_overlay()
	elif _stun_actions > 0 and _handle_stunned_input(event):
		return
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
	elif event.is_action_pressed(&"class_ability"):
		_toggle_class_ability_panel()
		get_viewport().set_input_as_handled()
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


func _handle_stunned_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"use_potion"):
		_open_consumable_menu()
		return true
	if event.is_action_pressed(&"inventory") or event.is_action_pressed(&"character_sheet"):
		GameManager.add_log_message("You are stunned; only consumables respond.", &"warning")
		return true
	if event.is_action_pressed(&"class_ability"):
		GameManager.add_log_message("You are stunned; only consumables respond.", &"warning")
		return true
	if (
		_input_direction(event) != Vector2i.ZERO
		or event.is_action_pressed(&"fire_ranged")
		or event.is_action_pressed(&"wait")
		or event.is_action_pressed(&"ui_accept")
	):
		_spend_stunned_action()
		return true
	return false


func _spend_stunned_action() -> void:
	GameManager.add_log_message(
		(
			"You are stunned and lose the action (%d action%s left)."
			% [_stun_actions, "" if _stun_actions == 1 else "s"]
		),
		&"warning"
	)
	_finish_player_action()


# ===== Pause & Overlay Management =====
func _open_pause_menu() -> void:
	_clear_targeting()
	pause_panel.visible = true
	debug_descend_button.visible = GameManager.pending_debug_loadout
	if GameManager.pending_debug_loadout:
		pause_hint_label.text = "The dungeon waits. Debug: Shift+> or PageDown descends."
	else:
		pause_hint_label.text = "The dungeon waits."
	_refresh_audio_controls()
	pause_resume_button.grab_focus()


func _close_pause_menu() -> void:
	pause_panel.visible = false


## Synchronises the pause-menu audio controls with the current SensoryFeedback
## state.  Safe to call when sensory_feedback is null.
func _sync_map_reduced_vfx() -> void:
	if map_view == null or not map_view.has_method(&"set_reduced_vfx_enabled"):
		return
	var reduced: bool = false
	if (
		is_instance_valid(sensory_feedback)
		and sensory_feedback.has_method(&"is_reduced_vfx_enabled")
	):
		reduced = bool(sensory_feedback.call(&"is_reduced_vfx_enabled"))
	map_view.call(&"set_reduced_vfx_enabled", reduced)


func _refresh_audio_controls() -> void:
	_sync_map_reduced_vfx()
	if not is_instance_valid(sensory_feedback):
		return
	var sf: Object = sensory_feedback
	if sf.has_method(&"is_audio_enabled"):
		pause_audio_enabled_button.set_pressed_no_signal(bool(sf.call(&"is_audio_enabled")))
	if sf.has_method(&"is_ambience_enabled"):
		pause_ambience_enabled_button.set_pressed_no_signal(bool(sf.call(&"is_ambience_enabled")))
	if sf.has_method(&"is_reduced_vfx_enabled"):
		pause_reduced_vfx_button.set_pressed_no_signal(bool(sf.call(&"is_reduced_vfx_enabled")))
	if sf.has_method(&"get_master_volume"):
		var vol: float = float(sf.call(&"get_master_volume"))
		var vol_int: int = int(round(vol * 100.0))
		pause_master_volume_slider.set_value_no_signal(float(vol_int))
		pause_master_volume_value_label.text = "%d%%" % vol_int
	_sync_map_reduced_vfx()


func _on_audio_enabled_toggled(button_pressed: bool) -> void:
	if is_instance_valid(sensory_feedback) and sensory_feedback.has_method(&"set_audio_enabled"):
		sensory_feedback.call(&"set_audio_enabled", button_pressed, false)


func _on_volume_slider_changed(value: float) -> void:
	if is_instance_valid(sensory_feedback) and sensory_feedback.has_method(&"set_master_volume"):
		var normalized: float = clampf(value / 100.0, 0.0, 1.0)
		sensory_feedback.call(&"set_master_volume", normalized)
		pause_master_volume_value_label.text = "%d%%" % int(round(normalized * 100.0))


func _on_ambience_enabled_toggled(button_pressed: bool) -> void:
	if is_instance_valid(sensory_feedback) and sensory_feedback.has_method(&"set_ambience_enabled"):
		sensory_feedback.call(&"set_ambience_enabled", button_pressed)


func _on_reduced_vfx_toggled(button_pressed: bool) -> void:
	if (
		is_instance_valid(sensory_feedback)
		and sensory_feedback.has_method(&"set_reduced_vfx_enabled")
	):
		sensory_feedback.call(&"set_reduced_vfx_enabled", button_pressed, true)
	_sync_map_reduced_vfx()


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
	var closed_overlay: bool = false
	if shop_panel.visible:
		shop_panel.visible = false
		closed_overlay = true
	elif consumable_panel.visible:
		consumable_panel.visible = false
		closed_overlay = true
	elif inventory_panel.visible:
		inventory_panel.visible = false
		closed_overlay = true
	elif character_sheet.visible:
		character_sheet.visible = false
		closed_overlay = true
	elif extraction_panel.visible:
		extraction_panel.visible = false
		closed_overlay = true
	elif class_ability_panel.visible:
		class_ability_panel.visible = false
		closed_overlay = true
	return closed_overlay


func _refresh_overlay_visibility() -> void:
	hud.visible = (
		not inventory_panel.visible
		and not character_sheet.visible
		and not shop_panel.visible
		and not extraction_panel.visible
		and not pause_panel.visible
		and not consumable_panel.visible
		and not class_ability_panel.visible
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
	if level_up_panel and level_up_panel.visible:
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
	var starter_path: String
	var starter_message: String
	var is_ranged: bool = false
	match GameManager.pending_character_class:
		&"ranger":
			starter_path = STARTER_WEAPON_RANGER
			starter_message = "You notch an arrow on your hunting bow."
			is_ranged = true
		&"wizard":
			starter_path = STARTER_WEAPON_WIZARD
			starter_message = "The apprentice staff hums with latent energy."
			is_ranged = true
		_:
			starter_path = STARTER_WEAPON_FIGHTER
			starter_message = "You heft your trusty training sword."
	var starter_template: Resource = load(starter_path)
	if starter_template == null:
		push_warning("Starter weapon missing: %s" % starter_path)
		return
	var starter_weapon: Resource = starter_template.duplicate(true)
	_player.inventory_component.add_item(starter_weapon)
	if is_ranged:
		_player.inventory_component.equipped_ranged_weapon = starter_weapon
		_player.inventory_component.equipped_weapon = starter_weapon
	else:
		_player.inventory_component.equipped_melee_weapon = starter_weapon
		_player.inventory_component.equipped_weapon = starter_weapon
	GameManager.add_log_message(starter_message, &"equipment")


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
	_raise_debug_player_to_level_twenty()
	GameManager.add_log_message(
		"Debug kit granted: level 20, 20 stats, full item set, and 9999 gold.", &"loot"
	)


func _raise_debug_player_to_level_twenty() -> void:
	var stats: StatsComponent = _player.stats_component
	stats.level = StatsComponent.STAT_LEVEL_CAP
	stats.xp = 0
	stats.last_levels_gained = 0
	stats.pending_stat_increases = 0
	stats.proficiency_bonus = 2 + int((StatsComponent.STAT_LEVEL_CAP - 1) / 4)
	var constitution_modifier: int = Dice.modifier(stats.constitution)
	var level_hp_gain: int = max(1, 5 + constitution_modifier)
	stats.max_hp = 12 + constitution_modifier + (StatsComponent.STAT_LEVEL_CAP - 1) * level_hp_gain
	stats.current_hp = stats.max_hp


# ===== Floor Generation & Spawning =====
func _generate_floor(floor_number: int) -> void:
	_cancel_boss_activation()
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
	_stun_actions = 0
	_enemy_action_counts.clear()
	_sleeping_enemies.clear()
	_ranged_recovery_enemies.clear()
	_boss_states.clear()
	_active_boss_encounter.clear()
	_boss_telegraphs.clear()
	_boss_hazards.clear()
	_clear_projectile_trails()
	_unknown_boss_attack_shapes.clear()
	_trap_data.clear()
	_revealed_traps.clear()
	_triggered_traps.clear()
	var player_level: int = _get_player_level()
	_fighter_cleave_charges = 2 if player_level >= 20 else 1
	_fighter_second_wind_charges = 1
	_fighter_whirlwind_charges = 1
	_ranger_focus_charges = 2 if player_level >= 20 else 1
	_ranger_volley_charges = 1
	_ranger_quickstep_charges = 1
	_wizard_spark_charges = 2 if player_level >= 20 else 1
	_wizard_frost_nova_charges = 1
	_wizard_chain_lightning_charges = 1
	_cleave_primed = false
	_hunter_focus_primed = false
	var generation_result: Dictionary = _generator.generate(
		DungeonDataScript.MAP_WIDTH, DungeonDataScript.MAP_HEIGHT, floor_number
	)
	GameManager.set_map_data(generation_result["map"])
	_secret_walls = generation_result.get("secret_walls", {}).duplicate(true)
	for secret_floor_cell: Vector2i in generation_result.get("secret_floor_cells", []):
		_secret_floor_cells[secret_floor_cell] = true
	GameManager.start_floor(floor_number)
	var biome_theme: Dictionary = _apply_biome_theme(floor_number)
	if (
		is_instance_valid(sensory_feedback)
		and sensory_feedback.has_method(&"set_floor_audio_context")
	):
		sensory_feedback.call(&"set_floor_audio_context", floor_number, biome_theme)
	_stairs_position = generation_result["stairs_position"]
	_player.set_grid_position(generation_result["player_start"])
	_spawn_shopkeeper(generation_result, floor_number)
	_spawn_enemies(generation_result["enemy_spawns"], floor_number)
	_spawn_items(generation_result["item_spawns"], floor_number)
	_spawn_traps(generation_result.get("trap_spawns", []), floor_number)
	_spawn_containers(generation_result, floor_number)
	_initialize_boss_encounter(generation_result, floor_number)
	hud.set_floor_context(floor_number, _shopkeeper != null)
	_refresh_visibility()
	_refresh_map()
	inventory_panel.visible = false
	character_sheet.visible = false
	shop_panel.visible = false
	pause_panel.visible = false
	consumable_panel.visible = false
	GameManager.add_log_message("You descend to floor %d." % floor_number, &"floor")
	_show_biome_title_if_needed(floor_number, biome_theme)
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


func _spawn_traps(trap_spawns: Array, floor_number: int) -> void:
	for spawn_position: Vector2i in trap_spawns:
		if _trap_resources.is_empty():
			return
		var trap: Resource = _trap_resources[randi_range(0, _trap_resources.size() - 1)].duplicate(
			true
		)
		_scale_trap_for_floor(trap, floor_number)
		_trap_data[spawn_position] = trap


func _scale_trap_for_floor(trap: Resource, floor_number: int) -> void:
	var depth: int = max(0, floor_number - 1)
	var dc_bonus: int = clampi(int(depth / 6), 0, LATE_TRAP_MAX_DC_BONUS)
	trap.detect_dc += dc_bonus
	if trap.min_damage <= 0 and trap.max_damage <= 0:
		return
	var damage_step: int = max(0, int(depth / LATE_TRAP_DAMAGE_DEPTH_STEP))
	trap.min_damage += max(0, damage_step - 1)
	trap.max_damage += damage_step * 2


func _spawn_containers(generation_result: Dictionary, floor_number: int) -> void:
	var rooms: Array = generation_result.get("rooms", [])
	if rooms.size() <= 1:
		return
	var chest_limit: int = min(max(1, 1 + int(floor_number / 5)), max(1, int(rooms.size() / 3)))
	var clutter_limit: int = min(2 + int(floor_number / 8), 4)
	var boss_encounter: Dictionary = generation_result.get("boss_encounter", {"active": false})
	var boss_room: Rect2i = boss_encounter.get("boss_room", Rect2i())
	var chest_count: int = 0
	var clutter_count: int = 0
	for room_index: int in range(1, rooms.size()):
		var room: Rect2i = rooms[room_index]
		if bool(boss_encounter.get("active", false)) and room == boss_room:
			continue
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


func _boss_id_for_floor(floor_number: int) -> StringName:
	return BOSS_FLOORS.get(floor_number, &"")


func _boss_resource_for_floor(floor_number: int) -> Resource:
	var boss_id: StringName = _boss_id_for_floor(floor_number)
	if boss_id == &"":
		return null
	for enemy_data: Resource in _enemy_resources:
		if enemy_data.is_boss and enemy_data.boss_id == boss_id:
			return enemy_data
	var path: String = BOSS_RESOURCE_BY_ID.get(boss_id, "")
	if path.is_empty():
		return null
	return load(path)


func _initialize_boss_encounter(generation_result: Dictionary, floor_number: int) -> void:
	_cancel_boss_activation()
	_active_boss_encounter.clear()
	_boss_telegraphs.clear()
	_boss_hazards.clear()
	_clear_projectile_trails()
	var boss_metadata: Dictionary = generation_result.get("boss_encounter", {"active": false})
	if not bool(boss_metadata.get("active", false)):
		_refresh_boss_presentation()
		return
	var boss_data: Resource = _boss_resource_for_floor(floor_number)
	var stairs_cell: Vector2i = boss_metadata.get(
		"boss_stairs_cell", generation_result["stairs_position"]
	)
	if boss_data == null:
		GameManager.add_log_message(
			"Boss resource missing for floor %d." % floor_number, &"warning"
		)
		GameManager.map_data[stairs_cell.y][stairs_cell.x] = DungeonDataScript.TileType.STAIRS_DOWN
		_stairs_position = stairs_cell
		_refresh_boss_presentation()
		return
	var boss_spawn_cell: Vector2i = boss_metadata.get("boss_spawn_cell", stairs_cell)
	var boss_entry_cell: Vector2i = boss_metadata.get("boss_entry_cell", boss_spawn_cell)
	var boss_gate_cell: Vector2i = boss_metadata.get("boss_gate_cell", Vector2i.ZERO)
	var room_cells: Dictionary = boss_metadata.get("boss_room_cells", {})
	_active_boss_encounter = {
		"active": true,
		"state": BOSS_ARENA_STATE_WAITING_AT_GATE,
		"boss_id": boss_data.boss_id,
		"boss_name": boss_data.display_name,
		"boss": null,
		"boss_data": boss_data,
		"room": boss_metadata.get("boss_room", Rect2i()),
		"room_cells": room_cells,
		"boss_arena_view_cells": boss_metadata.get("boss_arena_view_cells", room_cells),
		"boss_arena_isolated": bool(boss_metadata.get("boss_arena_isolated", false)),
		"door_cells": boss_metadata.get("boss_door_cells", []),
		"gate_cell": boss_gate_cell,
		"boss_gate_cell": boss_gate_cell,
		"boss_gate_entry_cell": boss_metadata.get("boss_gate_entry_cell", Vector2i.ZERO),
		"boss_entry_cell": boss_entry_cell,
		"boss_spawn_cell": boss_spawn_cell,
		"entry_cell": boss_entry_cell,
		"spawn_cell": boss_spawn_cell,
		"locked": false,
		"defeated": false,
		"stairs_cell": stairs_cell,
		"chest_cell": boss_metadata.get("boss_chest_cell", stairs_cell),
		"entered": false,
		"activation_completed": false,
	}
	GameManager.add_log_message("A boss gate waits at the far chamber.", &"boss_gate")
	_refresh_boss_presentation()


func _spawn_active_boss() -> Node2D:
	if _active_boss_encounter.is_empty():
		return null
	var existing_boss: Node2D = _active_boss_encounter.get("boss", null)
	if is_instance_valid(existing_boss) and existing_boss.is_alive():
		return existing_boss
	var boss_data: Resource = _active_boss_encounter.get("boss_data", null)
	if boss_data == null:
		return null
	var spawn_cell: Vector2i = _active_boss_encounter.get("spawn_cell", Vector2i.ZERO)
	var boss: Node2D = _spawn_enemy_instance(boss_data, spawn_cell, GameManager.current_floor, true)
	_boss_states[boss] = _make_boss_state(boss)
	_active_boss_encounter["boss"] = boss
	_refresh_boss_occupied_cells(boss)
	return boss


func _enter_boss_gate(gate_cell: Vector2i) -> bool:
	if _active_boss_encounter.is_empty():
		return false
	if bool(_active_boss_encounter.get("defeated", false)):
		return false
	if bool(_active_boss_encounter.get("entered", false)):
		GameManager.add_log_message("The sealed boss gate refuses to reopen.", &"warning")
		return true
	var door_cells: Array = _active_boss_encounter.get("door_cells", [])
	if not door_cells.has(gate_cell):
		return false
	var entry_cell: Vector2i = _active_boss_encounter.get("entry_cell", Vector2i.ZERO)
	if entry_cell == Vector2i.ZERO or not _is_cell_in_active_boss_room(entry_cell):
		entry_cell = _active_boss_encounter.get("spawn_cell", gate_cell)
	var boss_id: StringName = _active_boss_encounter.get("boss_id", &"")
	var story: Dictionary = BOSS_STORY_BY_ID.get(boss_id, {})
	GameManager.add_log_message(
		str(story.get("entry", "The boss gate opens onto a place outside the dungeon.")),
		&"boss_story"
	)
	_play_action_burst(gate_cell, &"door")
	_player.set_grid_position(entry_cell)
	_seal_boss_encounter(false)
	_active_boss_encounter["state"] = BOSS_ARENA_STATE_REVEAL
	_active_boss_encounter["entered"] = true
	_active_boss_encounter["locked"] = true
	_focus_boss_arena_exploration()
	_refresh_visibility()
	_focus_boss_arena_exploration()
	_show_boss_title(boss_id, str(_active_boss_encounter.get("boss_name", "The Boss")))
	_schedule_boss_activation()
	_refresh_boss_presentation()
	_refresh_map()
	return true


func _setup_boss_activation_timer() -> void:
	if _boss_activation_timer != null:
		return
	_boss_activation_timer = Timer.new()
	_boss_activation_timer.one_shot = true
	_boss_activation_timer.autostart = false
	_boss_activation_timer.wait_time = BOSS_ARENA_REVEAL_SECONDS
	_boss_activation_timer.timeout.connect(_on_boss_activation_timeout)
	add_child(_boss_activation_timer)


func _schedule_boss_activation() -> void:
	_setup_boss_activation_timer()
	_boss_activation_timer.stop()
	_boss_activation_timer.wait_time = BOSS_ARENA_REVEAL_SECONDS
	_boss_activation_timer.start()


func _cancel_boss_activation() -> void:
	if _boss_activation_timer != null:
		_boss_activation_timer.stop()


func _on_boss_activation_timeout() -> void:
	complete_boss_arena_reveal()


func complete_boss_arena_reveal() -> bool:
	if _active_boss_encounter.is_empty():
		return false
	if (
		_active_boss_encounter.get("state", BOSS_ARENA_STATE_WAITING_AT_GATE)
		!= BOSS_ARENA_STATE_REVEAL
	):
		return false
	if bool(_active_boss_encounter.get("activation_completed", false)):
		return false
	_cancel_boss_activation()
	var boss: Node2D = _spawn_active_boss()
	if boss == null:
		_fail_open_boss_gate_after_spawn_failure()
		return false
	_active_boss_encounter["activation_completed"] = true
	_active_boss_encounter["state"] = BOSS_ARENA_STATE_ACTIVE
	var boss_id: StringName = _active_boss_encounter.get("boss_id", &"")
	if (
		map_view != null
		and map_view.has_method(&"play_boss_spawn_intro")
		and _boss_states.has(boss)
	):
		(
			map_view
			. call(
				&"play_boss_spawn_intro",
				boss.grid_position,
				{
					"display_name": boss.display_name,
					"color": boss.color,
					"occupied_cells": _boss_states[boss].get("occupied_cells", []),
					"spawn_glyphs": _boss_spawn_glyphs(boss_id),
				}
			)
		)
	if is_instance_valid(sensory_feedback) and sensory_feedback.has_method(&"play_boss_intro_cue"):
		sensory_feedback.call(&"play_boss_intro_cue", boss_id)
	_start_boss_music()
	_refresh_boss_presentation()
	_refresh_map()
	GameManager.advance_turn()
	GameManager.begin_player_turn()
	return true


func _is_boss_arena_revealing() -> bool:
	return (
		not _active_boss_encounter.is_empty()
		and (
			_active_boss_encounter.get("state", BOSS_ARENA_STATE_WAITING_AT_GATE)
			== BOSS_ARENA_STATE_REVEAL
		)
	)


func _focus_boss_arena_exploration() -> void:
	if _active_boss_encounter.is_empty():
		return
	var focused_cells: Variant = _active_boss_encounter.get("boss_arena_view_cells", {})
	if focused_cells is Dictionary and focused_cells.is_empty():
		focused_cells = _active_boss_encounter.get("room_cells", {})
	elif focused_cells is Array and focused_cells.is_empty():
		focused_cells = _active_boss_encounter.get("room_cells", {})
	_explored_cells.clear()
	if focused_cells is Dictionary:
		for cell: Vector2i in focused_cells.keys():
			_explored_cells[cell] = true
	elif focused_cells is Array:
		for cell: Vector2i in focused_cells:
			_explored_cells[cell] = true


func _fail_open_boss_gate_after_spawn_failure() -> void:
	if _active_boss_encounter.is_empty():
		return
	_cancel_boss_activation()
	if bool(_active_boss_encounter.get("defeated", false)):
		_active_boss_encounter["state"] = BOSS_ARENA_STATE_DEFEATED
		return
	for door_cell: Vector2i in _active_boss_encounter.get("door_cells", []):
		if _is_inside_map(door_cell):
			GameManager.map_data[door_cell.y][door_cell.x] = DungeonDataScript.TileType.OPEN_DOOR
	var stairs_cell: Vector2i = _active_boss_encounter.get("stairs_cell", _stairs_position)
	if _is_inside_map(stairs_cell):
		GameManager.map_data[stairs_cell.y][stairs_cell.x] = DungeonDataScript.TileType.STAIRS_DOWN
		_stairs_position = stairs_cell
	_active_boss_encounter["locked"] = false
	_active_boss_encounter["entered"] = true
	_active_boss_encounter["defeated"] = true
	_active_boss_encounter["state"] = BOSS_ARENA_STATE_DEFEATED
	_boss_telegraphs.clear()
	_boss_hazards.clear()
	_clear_projectile_trails()
	GameManager.add_log_message("The boss gate collapses; the way forward opens.", &"warning")
	_refresh_boss_presentation()
	_refresh_visibility()
	_refresh_map()


func _make_boss_state(enemy: Node) -> Dictionary:
	return {
		"phase": 1,
		"pending_attack": null,
		"telegraph_turns": 0,
		"telegraph_cells": {},
		"last_attack_id": &"",
		"occupied_cells": _calculate_enemy_occupied_cells(enemy),
		"reward_claimed": false,
		"nyxara_summon_toggle": false,
		"attack_cooldowns": {},
	}


func _boss_state_for(enemy: Node) -> Dictionary:
	if not _boss_states.has(enemy):
		_boss_states[enemy] = _make_boss_state(enemy)
	return _boss_states[enemy]


func _is_boss_enemy(enemy: Node) -> bool:
	var enemy_actor: Enemy = enemy as Enemy
	return enemy_actor != null and enemy_actor.enemy_data != null and enemy_actor.enemy_data.is_boss


func _calculate_enemy_occupied_cells(enemy: Node) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if enemy == null:
		return cells
	if not _is_boss_enemy(enemy):
		cells.append(enemy.grid_position)
		return cells
	var enemy_actor: Enemy = enemy as Enemy
	var offsets: Array = enemy_actor.enemy_data.boss_footprint_offsets
	if offsets.is_empty():
		cells.append(enemy.grid_position)
		return cells
	for offset: Vector2i in offsets:
		cells.append(enemy.grid_position + offset)
	return cells


func _refresh_boss_occupied_cells(enemy: Node) -> void:
	if not _is_boss_enemy(enemy):
		return
	var state: Dictionary = _boss_state_for(enemy)
	state["occupied_cells"] = _calculate_enemy_occupied_cells(enemy)
	_boss_states[enemy] = state


func _enemy_occupied_cells(enemy: Node) -> Array[Vector2i]:
	if _is_boss_enemy(enemy):
		_refresh_boss_occupied_cells(enemy)
		return _boss_state_for(enemy).get("occupied_cells", [])
	var cells: Array[Vector2i] = []
	if enemy != null:
		cells.append(enemy.grid_position)
	return cells


func _enemy_occupies_cell(enemy: Node, cell: Vector2i) -> bool:
	for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
		if occupied_cell == cell:
			return true
	return false


func _is_cell_in_active_boss_room(cell: Vector2i) -> bool:
	if _active_boss_encounter.is_empty():
		return false
	var room_cells: Dictionary = _active_boss_encounter.get("room_cells", {})
	return room_cells.has(cell)


func _check_boss_room_entry(previous_cell: Vector2i, new_cell: Vector2i) -> void:
	if _active_boss_encounter.is_empty():
		return
	if bool(_active_boss_encounter.get("defeated", false)):
		return
	if bool(_active_boss_encounter.get("locked", false)):
		return
	var room_cells: Dictionary = _active_boss_encounter.get("room_cells", {})
	if room_cells.has(previous_cell) or not room_cells.has(new_cell):
		return
	_seal_boss_encounter()


func _seal_boss_encounter(start_music: bool = true) -> void:
	if _active_boss_encounter.is_empty():
		return
	for door_cell: Vector2i in _active_boss_encounter.get("door_cells", []):
		if _is_inside_map(door_cell):
			GameManager.map_data[door_cell.y][door_cell.x] = (
				DungeonDataScript.TileType.SEALED_BOSS_DOOR
			)
	_active_boss_encounter["locked"] = true
	_active_boss_encounter["entered"] = true
	GameManager.add_log_message(
		(
			"The gate slams shut. Defeat %s to leave."
			% _active_boss_encounter.get("boss_name", "the boss")
		),
		&"boss_gate"
	)
	if start_music:
		_start_boss_music()
	_refresh_boss_presentation()
	_refresh_visibility()
	_refresh_map()


func _start_boss_music() -> void:
	if not is_instance_valid(sensory_feedback):
		return
	if not sensory_feedback.has_method(&"start_boss_music"):
		return
	var boss_data: Resource = _active_boss_encounter.get("boss_data", null)
	var boss_id: StringName = _active_boss_encounter.get("boss_id", &"")
	var base_stream: AudioStream = boss_data.boss_music_stream if boss_data != null else null
	var climax_stream: AudioStream = (
		boss_data.boss_climax_music_stream if boss_data != null else null
	)
	sensory_feedback.call(&"start_boss_music", boss_id, base_stream, climax_stream)


func _release_boss_encounter() -> void:
	if _active_boss_encounter.is_empty():
		return
	_cancel_boss_activation()
	if bool(_active_boss_encounter.get("defeated", false)):
		_active_boss_encounter["state"] = BOSS_ARENA_STATE_DEFEATED
		return
	for door_cell: Vector2i in _active_boss_encounter.get("door_cells", []):
		if _is_inside_map(door_cell):
			GameManager.map_data[door_cell.y][door_cell.x] = DungeonDataScript.TileType.OPEN_DOOR
	_active_boss_encounter["locked"] = false
	_active_boss_encounter["defeated"] = true
	_active_boss_encounter["state"] = BOSS_ARENA_STATE_DEFEATED
	var stairs_cell: Vector2i = _active_boss_encounter.get("stairs_cell", _stairs_position)
	GameManager.map_data[stairs_cell.y][stairs_cell.x] = DungeonDataScript.TileType.STAIRS_DOWN
	_stairs_position = stairs_cell
	var boss_data: Resource = _active_boss_encounter.get("boss_data", null)
	var chest_rarity: int = ItemDataScript.ItemRarity.MYTHIC
	var gold_reward: int = 0
	if boss_data != null:
		chest_rarity = boss_data.boss_reward_chest_rarity
		gold_reward = boss_data.boss_reward_gold
	var chest_cell: Vector2i = _active_boss_encounter.get("chest_cell", Vector2i.ZERO)
	var reward_cell: Vector2i = _find_boss_chest_reward_cell(chest_cell)
	if reward_cell == Vector2i.ZERO:
		GameManager.add_log_message("No safe space remains for the boss chest.", &"warning")
	else:
		_container_positions[reward_cell] = _make_chest_container(chest_rarity)
		_play_action_burst(reward_cell, &"loot")
	if gold_reward > 0:
		_player.stats_component.gold += gold_reward
		GameManager.add_log_message(
			(
				"%s drops %d gold."
				% [_active_boss_encounter.get("boss_name", "The boss"), gold_reward]
			),
			&"gold"
		)
	_play_action_burst(stairs_cell, &"floor")
	_boss_telegraphs.clear()
	_boss_hazards.clear()
	_clear_projectile_trails()
	if is_instance_valid(sensory_feedback) and sensory_feedback.has_method(&"play_boss_defeat_cue"):
		sensory_feedback.call(&"play_boss_defeat_cue", _active_boss_encounter.get("boss_id", &""))
	if is_instance_valid(sensory_feedback) and sensory_feedback.has_method(&"stop_boss_music"):
		sensory_feedback.call(&"stop_boss_music", 0.6)
	_refresh_boss_presentation()
	_refresh_visibility()
	_refresh_map()


func _find_boss_chest_reward_cell(preferred_cell: Vector2i) -> Vector2i:
	if preferred_cell != Vector2i.ZERO and not _is_container_spawn_blocked(preferred_cell):
		return preferred_cell
	if _active_boss_encounter.is_empty():
		return Vector2i.ZERO
	var room_cells: Dictionary = _active_boss_encounter.get("room_cells", {})
	for radius: int in range(1, 9):
		var candidates: Array[Vector2i] = []
		for cell: Vector2i in room_cells.keys():
			if (
				preferred_cell != Vector2i.ZERO
				and max(abs(cell.x - preferred_cell.x), abs(cell.y - preferred_cell.y)) != radius
			):
				continue
			if not _is_container_spawn_blocked(cell):
				candidates.append(cell)
		if not candidates.is_empty():
			candidates.sort_custom(
				func(a: Vector2i, b: Vector2i) -> bool:
					return (
						a.distance_squared_to(preferred_cell)
						< b.distance_squared_to(preferred_cell)
					)
			)
			return candidates[0]
	return Vector2i.ZERO


func _handle_boss_defeated(enemy: Node) -> bool:
	if not _is_boss_enemy(enemy):
		return false
	var state: Dictionary = _boss_state_for(enemy)
	if bool(state.get("reward_claimed", false)):
		return true
	state["reward_claimed"] = true
	_boss_states[enemy] = state
	_release_boss_encounter()
	return true


func _refresh_boss_presentation() -> void:
	var boss_alive: bool = false
	var boss: Node = null
	var boss_data: Resource = null
	if not _active_boss_encounter.is_empty():
		boss = _active_boss_encounter.get("boss", null)
		boss_data = _active_boss_encounter.get("boss_data", null)
		boss_alive = (
			boss != null
			and boss.is_alive()
			and not bool(_active_boss_encounter.get("defeated", false))
		)
	if map_view != null and map_view.has_method(&"set_boss_room"):
		if (
			_active_boss_encounter.is_empty()
			or not bool(_active_boss_encounter.get("entered", false))
		):
			map_view.call(&"set_boss_room", {}, [], false)
		else:
			var locked: bool = bool(_active_boss_encounter.get("locked", false))
			map_view.call(
				&"set_boss_room",
				_active_boss_encounter.get("room_cells", {}),
				_active_boss_encounter.get("door_cells", []),
				locked,
				_boss_room_tint_color(_active_boss_encounter.get("boss_id", &""), locked)
			)
	if map_view != null and map_view.has_method(&"set_boss_visuals"):
		if boss_alive and boss_data != null:
			var state: Dictionary = _boss_state_for(boss)
			var visuals: Dictionary = {
				boss.grid_position:
				{
					"display_name": boss_data.display_name,
					"frames": boss_data.boss_visual_frames,
					"frame_seconds": boss_data.boss_visual_frame_seconds,
					"color": boss.color,
					"occupied_cells": state.get("occupied_cells", []),
					"phase": state.get("phase", 1),
					"spawn_glyphs": _boss_spawn_glyphs(boss_data.boss_id),
				}
			}
			map_view.call(&"set_boss_visuals", visuals)
		elif map_view.has_method(&"clear_boss_visuals"):
			map_view.call(&"clear_boss_visuals")
	if map_view != null and map_view.has_method(&"set_boss_telegraphs"):
		map_view.call(&"set_boss_telegraphs", _build_boss_telegraph_payload() if boss_alive else {})
	map_view.call(&"set_boss_hazards", _build_boss_hazard_payload() if boss_alive else {})
	if hud != null:
		if hud.has_method(&"set_boss_goal_state"):
			hud.call(
				&"set_boss_goal_state",
				_active_boss_encounter.get("boss_name", ""),
				not _active_boss_encounter.is_empty(),
				bool(_active_boss_encounter.get("locked", false)),
				bool(_active_boss_encounter.get("defeated", false)),
				_active_boss_encounter.get("state", BOSS_ARENA_STATE_WAITING_AT_GATE)
			)
		if boss_alive and boss != null and hud.has_method(&"show_boss_health"):
			var state: Dictionary = _boss_state_for(boss)
			var phase: int = int(state.get("phase", 1))
			var room_title: String = ""
			if boss_data != null:
				room_title = str(boss_data.boss_room_title)
			var windup_label: String = ""
			if state.get("pending_attack", null) != null:
				windup_label = str(state["pending_attack"].id)
			hud.call(
				&"show_boss_health",
				boss.display_name,
				boss.stats_component.current_hp,
				boss.stats_component.max_hp,
				_boss_accent_color(_active_boss_encounter.get("boss_id", &"")),
				phase,
				room_title,
				windup_label
			)
		elif hud.has_method(&"hide_boss_health"):
			hud.call(&"hide_boss_health")
	if (
		boss_alive
		and (
			_active_boss_encounter.get("state", BOSS_ARENA_STATE_WAITING_AT_GATE)
			== BOSS_ARENA_STATE_ACTIVE
		)
		and bool(_active_boss_encounter.get("locked", false))
		and is_instance_valid(sensory_feedback)
	):
		if sensory_feedback.has_method(&"update_boss_music_intensity"):
			sensory_feedback.call(
				&"update_boss_music_intensity",
				boss.stats_component.current_hp,
				boss.stats_component.max_hp
			)
		if (
			sensory_feedback.has_method(&"is_boss_music_playing")
			and sensory_feedback.has_method(&"start_boss_music")
		):
			if not bool(sensory_feedback.call(&"is_boss_music_playing")) and boss_data != null:
				sensory_feedback.call(
					&"start_boss_music",
					_active_boss_encounter.get("boss_id", &""),
					boss_data.boss_music_stream,
					boss_data.boss_climax_music_stream
				)


func _can_place_boss_at(enemy: Node, anchor_cell: Vector2i, blocked_cells: Dictionary) -> bool:
	if not _is_boss_enemy(enemy):
		return false
	var enemy_actor: Enemy = enemy as Enemy
	for offset: Vector2i in enemy_actor.enemy_data.boss_footprint_offsets:
		var cell: Vector2i = anchor_cell + offset
		if not _is_cell_in_active_boss_room(cell):
			return false
		if not _is_walkable(cell):
			return false
		if cell == _player.grid_position:
			return false
		if blocked_cells.has(cell):
			return false
		if _is_sealed_boss_door(cell):
			return false
		var occupying_enemy: Node2D = _get_enemy_at(cell)
		if occupying_enemy != null and occupying_enemy != enemy:
			return false
	return true


func _try_move_boss_toward_player(enemy: Node, blocked_cells: Dictionary) -> bool:
	if not _is_boss_enemy(enemy):
		return false
	var delta: Vector2i = _player.grid_position - enemy.grid_position
	var directions: Array[Vector2i] = []
	if abs(delta.x) >= abs(delta.y):
		directions.append(Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT)
		if delta.y != 0:
			directions.append(Vector2i.DOWN if delta.y > 0 else Vector2i.UP)
	else:
		directions.append(Vector2i.DOWN if delta.y > 0 else Vector2i.UP)
		if delta.x != 0:
			directions.append(Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT)
	for direction: Vector2i in directions:
		var target_anchor: Vector2i = enemy.grid_position + direction
		if _can_place_boss_at(enemy, target_anchor, blocked_cells):
			enemy.set_grid_position(target_anchor)
			_refresh_boss_occupied_cells(enemy)
			return true
	return false


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
	if _stun_actions > 0:
		_spend_stunned_action()
		return
	if _is_boss_door(target):
		if _enter_boss_gate(target):
			return
		GameManager.add_log_message("The boss gate is dormant.", &"warning")
		return
	if _is_sealed_boss_door(target):
		GameManager.add_log_message(
			(
				"The boss gate is sealed. Defeat %s."
				% _active_boss_encounter.get("boss_name", "the boss")
			),
			&"warning"
		)
		return
	if _is_closed_door(target):
		GameManager.map_data[target.y][target.x] = DungeonDataScript.TileType.OPEN_DOOR
		GameManager.add_log_message("You open the door.", &"neutral")
		_play_action_burst(target, &"door")
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
			_game_over,
			_handle_special_trap
		)
		_play_action_burst(target, &"trap")
		_finish_player_action()
		return

	var dash_target: Vector2i = _get_dash_destination(direction, target)
	if dash_target != target:
		_dash_charge = 0
		target = dash_target
		GameManager.add_log_message("%s carries you two tiles." % DASH_LOG_NAME, &"magic")

	var previous_cell: Vector2i = _player.grid_position
	_player.set_grid_position(target)
	_check_boss_room_entry(previous_cell, target)
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
	var attacker_damage_percent: int = _get_attacker_damage_percent(attacker, &"melee")
	var outcome: Dictionary = CombatSystemScript.attack(
		attacker, defender, damage_percent, attacker_damage_percent
	)
	if outcome["hit"]:
		_log_damage_affinity(
			defender, &"melee", outcome["attacker_scaled_damage"], outcome["damage"]
		)
		var critical_text: String = " (critical)" if outcome["critical"] else ""
		GameManager.add_log_message(
			(
				"%s hits %s for %d melee damage%s."
				% [attacker.display_name, defender.display_name, outcome["damage"], critical_text]
			),
			&"combat_hit"
		)
		_play_action_burst(
			defender.grid_position, &"critical" if outcome["critical"] else &"melee_hit"
		)
	else:
		GameManager.add_log_message(
			"%s misses %s." % [attacker.display_name, defender.display_name], &"combat_miss"
		)
		_play_action_burst(defender.grid_position, &"miss")

	_try_apply_attack_poison(attacker, defender, outcome)
	_handle_defender_after_damage(defender, outcome["damage"] > 0)

	if attacker == _player and _cleave_primed and outcome["hit"]:
		_apply_cleave_splash(defender, outcome)

	if attacker == _player and outcome["hit"]:
		_apply_fighter_extra_strike(defender)


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
	var class_scaled_damage: int = _scale_damage(
		raw_damage, _get_player_class_damage_percent(damage_type, _get_player_level())
	)
	var damage_percent: int = _get_damage_percent(defender, damage_type)
	var damage: int = _scale_damage(class_scaled_damage, damage_percent)
	_log_damage_affinity(defender, damage_type, class_scaled_damage, damage)
	if damage > 0:
		damage = defender.stats_component.apply_damage(damage)
	return damage


func _get_attacker_damage_percent(attacker: Node, damage_type: StringName) -> int:
	if attacker == _player:
		return _get_player_class_damage_percent(damage_type, _get_player_level())
	return 100


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


func _handle_defender_after_damage(defender: Node, took_damage: bool = true) -> void:
	if defender == _player:
		GameManager.emit_player_damaged()
		if took_damage:
			_try_apply_player_set_proc()
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


func _try_apply_player_set_proc() -> void:
	if _player == null or not _player.is_alive():
		return
	var inventory: Node = _player.inventory_component
	if inventory == null:
		return
	var proc_chance: int = inventory._get_set_proc_chance_percent()
	var heal_percent: int = inventory._get_set_proc_heal_percent()
	if proc_chance <= 0 or heal_percent <= 0:
		return
	if randi_range(1, 100) > proc_chance:
		return
	var heal_amount: int = max(1, int(ceil(_player.stats_component.max_hp * heal_percent / 100.0)))
	var before_hp: int = _player.stats_component.current_hp
	_player.stats_component.heal(heal_amount)
	var healed: int = _player.stats_component.current_hp - before_hp
	if healed <= 0:
		return
	GameManager.emit_player_damaged()
	GameManager.add_log_message(
		"%s restores %d HP." % [inventory._get_set_proc_display_name(), healed], &"heal"
	)


# ===== Class Abilities =====
func _toggle_class_ability_panel() -> void:
	if _stun_actions > 0:
		GameManager.add_log_message("You are stunned; only consumables respond.", &"warning")
		return
	if class_ability_panel.visible:
		class_ability_panel.visible = false
	else:
		_close_open_overlay()
		class_ability_panel.refresh(_get_class_ability_entries())
		class_ability_panel.visible = true


func _get_class_ability_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var player_class: StringName = GameManager.pending_character_class
	var player_level: int = _get_player_level()
	match player_class:
		GameManager.CLASS_FIGHTER:
			entries.append(_make_fighter_ability_entry(&"fighter_cleave", player_level))
			entries.append(_make_fighter_ability_entry(&"fighter_second_wind", player_level))
			entries.append(_make_fighter_ability_entry(&"fighter_whirlwind", player_level))
		GameManager.CLASS_RANGER:
			entries.append(_make_ranger_ability_entry(&"ranger_focus", player_level))
			entries.append(_make_ranger_ability_entry(&"ranger_volley", player_level))
			entries.append(_make_ranger_ability_entry(&"ranger_quickstep", player_level))
		GameManager.CLASS_WIZARD:
			entries.append(_make_wizard_ability_entry(&"arcane_spark", player_level))
			entries.append(_make_wizard_ability_entry(&"wizard_frost_nova", player_level))
			entries.append(_make_wizard_ability_entry(&"wizard_chain_lightning", player_level))
	return entries


func _make_ability_entry_core(
	ability_id: StringName,
	name: String,
	player_level: int,
	summary: String,
	details: String,
	active: bool
) -> Dictionary:
	var unlock_level: int = _get_ability_unlock_level(ability_id)
	var charges_current: int = _get_ability_charges_current(ability_id)
	var charges_max: int = _get_ability_charges_max(ability_id)
	var unlocked: bool = player_level >= unlock_level
	var entry: Dictionary = {
		"ability_id": ability_id,
		"name": name,
		"charges_current": charges_current if unlocked else 0,
		"charges_max": charges_max,
		"summary": summary,
		"details": details,
		"active": active if unlocked else false,
	}
	if unlocked:
		entry["enabled"] = charges_current > 0 and not active
	else:
		entry["enabled"] = false
		entry["unlock_level"] = unlock_level
		entry["disabled_reason"] = "Unlocks at level %d." % unlock_level
	return entry


func _make_fighter_ability_entry(ability_id: StringName, player_level: int) -> Dictionary:
	match ability_id:
		&"fighter_cleave":
			var splash_percent: int = _get_fighter_cleave_splash_percent(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Cleave",
				player_level,
				"Next melee attack splashes adjacent enemies for %d%% damage." % splash_percent,
				(
					(
						"Your next successful melee hit deals %d%% splash damage to adjacent enemies. "
						+ "Does not consume your turn to activate."
					)
					% splash_percent
				),
				_cleave_primed
			)
		&"fighter_second_wind":
			var heal_percent: int = _get_second_wind_heal_percent(player_level)
			var shield_value: int = _get_second_wind_shield_value(player_level)
			var shield_turns_count: int = _get_second_wind_shield_turns(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Second Wind",
				player_level,
				(
					"Heal %d%% max HP and gain +%d AC for %d turns."
					% [heal_percent, shield_value, shield_turns_count]
				),
				(
					(
						"Recover %d%% of your maximum HP and gain +%d AC for %d turns. "
						+ "Consumes your action."
					)
					% [heal_percent, shield_value, shield_turns_count]
				),
				false
			)
		&"fighter_whirlwind":
			return _make_ability_entry_core(
				ability_id,
				"Whirlwind",
				player_level,
				"Melee attack all adjacent enemies once.",
				(
					"Lash out at every enemy cardinally adjacent to you with a melee attack. "
					+ "Consumes your action only when at least one enemy is hit."
				),
				false
			)
	return _make_ability_entry_core(ability_id, "Unknown", player_level, "", "", false)


func _make_ranger_ability_entry(ability_id: StringName, player_level: int) -> Dictionary:
	match ability_id:
		&"ranger_focus":
			var accuracy_bonus: int = _get_hunter_focus_accuracy(player_level)
			var multiplier: int = _get_hunter_focus_multiplier(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Hunter's Focus",
				player_level,
				(
					"Next ranged shot gains +%d accuracy and %d%% damage."
					% [accuracy_bonus, multiplier]
				),
				(
					(
						"Your next ranged weapon attack gains +%d attack and %d%% raw damage. "
						+ "Consumed on hit or miss. Does not consume your turn to activate."
					)
					% [accuracy_bonus, multiplier]
				),
				_hunter_focus_primed
			)
		&"ranger_volley":
			var target_count: int = _get_volley_target_count(player_level)
			var damage_percent: int = _get_volley_damage_percent(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Volley",
				player_level,
				(
					"Fire at %d nearest enemies in weapon range for %d%% damage each."
					% [target_count, damage_percent]
				),
				(
					(
						"Requires equipped ranged weapon. Hits the %d nearest visible enemies in range "
						+ "for %d%% raw ranged damage each. Consumes your action only with targets."
					)
					% [target_count, damage_percent]
				),
				false
			)
		&"ranger_quickstep":
			var haste_phases: int = _get_quickstep_haste_phases(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Quickstep",
				player_level,
				"Your next %d enemy phases are hasted." % haste_phases,
				(
					(
						"Move faster than the dungeon: your next %d enemy phase%s is skipped. "
						+ "Consumes your action."
					)
					% [haste_phases, "" if haste_phases == 1 else "s"]
				),
				false
			)
	return _make_ability_entry_core(ability_id, "Unknown", player_level, "", "", false)


func _make_wizard_ability_entry(ability_id: StringName, player_level: int) -> Dictionary:
	match ability_id:
		&"arcane_spark":
			var spark_range: int = _get_arcane_spark_range(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Arcane Spark",
				player_level,
				(
					"Strike nearest visible enemy in range %d for 1d4+WIS+level/5 magic damage."
					% spark_range
				),
				(
					(
						"Unleash a bolt at the nearest visible enemy in range %d. "
						+ "Damage: 1d4 + WIS modifier + level/5 magic damage."
					)
					% spark_range
				),
				false
			)
		&"wizard_frost_nova":
			var nova_radius: int = _get_frost_nova_radius(player_level)
			var sleep_turns: int = _get_frost_nova_sleep_turns(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Frost Nova",
				player_level,
				(
					"Freeze visible enemies within radius %d for 1d4+WIS+level/4 magic damage."
					% nova_radius
				),
				(
					(
						"Blast visible enemies within radius %d for 1d4 + WIS modifier + level/4 magic damage "
						+ "and sleep them for %d turn%s. Consumes action only if at least one enemy is affected."
					)
					% [nova_radius, sleep_turns, "" if sleep_turns == 1 else "s"]
				),
				false
			)
		&"wizard_chain_lightning":
			var chain_range: int = _get_chain_lightning_range(player_level)
			var target_count: int = _get_chain_lightning_target_count(player_level)
			return _make_ability_entry_core(
				ability_id,
				"Chain Lightning",
				player_level,
				(
					"Chain to %d nearest enemies in range %d for 1d6+WIS+level/2 magic damage each."
					% [target_count, chain_range]
				),
				(
					(
						"Strike the %d nearest visible enemies in range %d for 1d6 + WIS modifier + level/2 "
						+ "magic damage each. Consumes action only if at least one enemy is hit."
					)
					% [target_count, chain_range]
				),
				false
			)
	return _make_ability_entry_core(ability_id, "Unknown", player_level, "", "", false)


func _on_class_ability_panel_close_requested() -> void:
	class_ability_panel.visible = false


func _on_class_ability_requested(ability_id: StringName) -> void:
	match ability_id:
		&"fighter_cleave":
			_activate_fighter_cleave()
		&"fighter_second_wind":
			_activate_fighter_second_wind()
		&"fighter_whirlwind":
			_activate_fighter_whirlwind()
		&"ranger_focus":
			_activate_ranger_focus()
		&"ranger_volley":
			_activate_ranger_volley()
		&"ranger_quickstep":
			_activate_ranger_quickstep()
		&"arcane_spark":
			_activate_wizard_spark()
		&"wizard_frost_nova":
			_activate_wizard_frost_nova()
		&"wizard_chain_lightning":
			_activate_wizard_chain_lightning()
	class_ability_panel.visible = false


func _activate_fighter_cleave() -> void:
	if _fighter_cleave_charges <= 0 or _cleave_primed:
		return
	_fighter_cleave_charges -= 1
	_cleave_primed = true
	GameManager.add_log_message(
		"Cleave primed: your next melee attack splashes to adjacent enemies.", &"magic"
	)


func _activate_fighter_second_wind() -> void:
	if _fighter_second_wind_charges <= 0:
		return
	var player_level: int = _get_player_level()
	var heal_percent: int = _get_second_wind_heal_percent(player_level)
	var shield_value: int = _get_second_wind_shield_value(player_level)
	var shield_turns_count: int = _get_second_wind_shield_turns(player_level)
	_fighter_second_wind_charges -= 1
	# Heal
	var heal_amount: int = max(1, int(round(_player.stats_component.max_hp * heal_percent / 100.0)))
	var before_hp: int = _player.stats_component.current_hp
	_player.stats_component.heal(heal_amount)
	var healed: int = _player.stats_component.current_hp - before_hp
	if healed > 0:
		GameManager.add_log_message("Second Wind restores %d HP." % healed, &"heal")
	# Shield
	_shield_turns = max(_shield_turns, shield_turns_count + 1)
	_shield_armor_bonus = max(_shield_armor_bonus, shield_value)
	_refresh_temporary_stats()
	GameManager.add_log_message(
		"Second Wind grants +%d AC for %d turns." % [shield_value, shield_turns_count], &"magic"
	)
	GameManager.emit_player_damaged()
	_finish_player_action()


func _activate_fighter_whirlwind() -> void:
	if _fighter_whirlwind_charges <= 0:
		return
	var adjacent_enemies: Array[Node2D] = _get_adjacent_enemies(_player.grid_position)
	if adjacent_enemies.is_empty():
		GameManager.add_log_message("Whirlwind has no adjacent enemies.", &"warning")
		return
	_fighter_whirlwind_charges -= 1
	for target: Node2D in adjacent_enemies:
		var damage_percent: int = _get_damage_percent(target, &"melee")
		var attacker_damage_percent: int = _get_player_class_damage_percent(
			&"melee", _get_player_level()
		)
		var outcome: Dictionary = CombatSystemScript.attack(
			_player, target, damage_percent, attacker_damage_percent
		)
		if outcome["hit"]:
			_log_damage_affinity(
				target, &"melee", outcome["attacker_scaled_damage"], outcome["damage"]
			)
			GameManager.add_log_message(
				"Whirlwind hits %s for %d melee damage." % [target.display_name, outcome["damage"]],
				&"combat_hit"
			)
		else:
			GameManager.add_log_message(
				"Whirlwind misses %s." % target.display_name, &"combat_miss"
			)
		_handle_defender_after_damage(target)
	_finish_player_action()


func _activate_ranger_focus() -> void:
	if _ranger_focus_charges <= 0 or _hunter_focus_primed:
		return
	_ranger_focus_charges -= 1
	_hunter_focus_primed = true
	var player_level: int = _get_player_level()
	var accuracy: int = _get_hunter_focus_accuracy(player_level)
	var multiplier: int = _get_hunter_focus_multiplier(player_level)
	(
		GameManager
		. add_log_message(
			(
				("Hunter's Focus primed: your next ranged weapon shot gains +%d accuracy and %d%% damage.")
				% [accuracy, multiplier]
			),
			&"magic"
		)
	)


func _activate_ranger_volley() -> void:
	if _ranger_volley_charges <= 0:
		return
	if not _has_ranged_weapon():
		GameManager.add_log_message("Volley requires an equipped ranged weapon.", &"warning")
		return
	var ranged_weapon: Resource = _player.inventory_component.get_equipped_ranged_weapon()
	var volley_range: int = ranged_weapon.range
	var visible_enemies: Array[Node2D] = _find_visible_enemies_in_range(volley_range)
	if visible_enemies.is_empty():
		GameManager.add_log_message(
			"Volley has no visible targets within weapon range %d." % volley_range, &"warning"
		)
		return
	_ranger_volley_charges -= 1
	var player_level: int = _get_player_level()
	var target_count: int = _get_volley_target_count(player_level)
	var damage_percent: int = _get_volley_damage_percent(player_level)
	var targets: Array[Node2D] = []
	# Sort by distance, take up to target_count
	visible_enemies.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				a.grid_position.distance_to(_player.grid_position)
				< b.grid_position.distance_to(_player.grid_position)
			)
	)
	for i: int in range(min(target_count, visible_enemies.size())):
		targets.append(visible_enemies[i])
	var volley_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		ranged_weapon, &"weapon", &"ranged"
	)
	for target: Node2D in targets:
		_play_projectile_between(_player.grid_position, target.grid_position, volley_payload)
	for target: Node2D in targets:
		var dex_mod: int = Dice.modifier(_player.stats_component.dexterity)
		var raw_damage: int = max(1, Dice.roll(ranged_weapon.damage_sides) + dex_mod)
		raw_damage = max(1, int(round(raw_damage * damage_percent / 100.0)))
		var damage: int = _apply_typed_damage(target, raw_damage, &"ranged")
		GameManager.add_log_message(
			"Volley hits %s for %d damage." % [target.display_name, damage], &"combat_hit"
		)
		_handle_defender_after_damage(target)
	_finish_player_action()


func _activate_ranger_quickstep() -> void:
	if _ranger_quickstep_charges <= 0:
		return
	_ranger_quickstep_charges -= 1
	var haste_phases: int = _get_quickstep_haste_phases(_get_player_level())
	_haste_enemy_phases = max(_haste_enemy_phases, haste_phases)
	GameManager.add_log_message(
		(
			"Quickstep: your next %d enemy phase%s will be skipped."
			% [haste_phases, "" if haste_phases == 1 else "s"]
		),
		&"magic"
	)
	_finish_player_action()


func _activate_wizard_spark() -> void:
	if _wizard_spark_charges <= 0:
		return
	var player_level: int = _get_player_level()
	var spark_range: int = _get_arcane_spark_range(player_level)
	var nearest_enemy: Node2D = _find_nearest_visible_enemy_in_range(spark_range)
	if nearest_enemy == null:
		GameManager.add_log_message(
			"Arcane Spark has no visible target within range %d." % spark_range, &"warning"
		)
		return
	_wizard_spark_charges -= 1
	_play_projectile_between(
		_player.grid_position,
		nearest_enemy.grid_position,
		ProjectileSystemScript.payload_for_id(&"arcane_spark", &"magic", ACTION_BURST_MAGIC_COLOR)
	)
	var wis_mod: int = Dice.modifier(_player.stats_component.wisdom)
	var raw_damage: int = Dice.roll(4) + max(0, wis_mod) + int(player_level / 5)
	var damage: int = _apply_typed_damage(nearest_enemy, raw_damage, &"magic")
	GameManager.add_log_message(
		"Arcane Spark hits %s for %d force damage." % [nearest_enemy.display_name, damage], &"magic"
	)
	_handle_defender_after_damage(nearest_enemy)
	_finish_player_action()


func _activate_wizard_frost_nova() -> void:
	if _wizard_frost_nova_charges <= 0:
		return
	var player_level: int = _get_player_level()
	var nova_radius: int = _get_frost_nova_radius(player_level)
	var sleep_turns: int = _get_frost_nova_sleep_turns(player_level)
	# Collect affected enemies
	var affected_enemies: Array[Node2D] = []
	for enemy: Node2D in _enemies:
		if enemy == null or not enemy.is_alive():
			continue
		if not _visible_cells.has(enemy.grid_position):
			continue
		if enemy.grid_position.distance_to(_player.grid_position) <= nova_radius:
			affected_enemies.append(enemy)
	if affected_enemies.is_empty():
		GameManager.add_log_message(
			"Frost Nova has no visible enemies within radius %d." % nova_radius, &"warning"
		)
		return
	_wizard_frost_nova_charges -= 1
	var wis_mod: int = Dice.modifier(_player.stats_component.wisdom)
	var base_damage: int = Dice.roll(4) + max(0, wis_mod) + int(player_level / 4)
	var nova_cells: Array[Vector2i] = []
	for target: Node2D in affected_enemies:
		nova_cells.append(target.grid_position)
	_play_projectile_cells(
		nova_cells,
		ProjectileSystemScript.payload_for_id(&"frost_nova", &"magic", Color(0.62, 0.90, 1.0))
	)
	for target: Node2D in affected_enemies:
		var damage: int = _apply_typed_damage(target, base_damage, &"magic")
		GameManager.add_log_message(
			"Frost Nova hits %s for %d cold damage." % [target.display_name, damage], &"combat_hit"
		)
		_sleeping_enemies[target] = sleep_turns
		_handle_defender_after_damage(target)
	_finish_player_action()


func _activate_wizard_chain_lightning() -> void:
	if _wizard_chain_lightning_charges <= 0:
		return
	var player_level: int = _get_player_level()
	var chain_range: int = _get_chain_lightning_range(player_level)
	var target_count: int = _get_chain_lightning_target_count(player_level)
	var candidates: Array[Node2D] = _find_visible_enemies_in_range(chain_range)
	if candidates.is_empty():
		GameManager.add_log_message(
			"Chain Lightning has no visible targets within range %d." % chain_range, &"warning"
		)
		return
	_wizard_chain_lightning_charges -= 1
	# Sort by distance, take up to target_count
	candidates.sort_custom(
		func(a: Node2D, b: Node2D) -> bool:
			return (
				a.grid_position.distance_to(_player.grid_position)
				< b.grid_position.distance_to(_player.grid_position)
			)
	)
	var targets: Array[Node2D] = []
	for i: int in range(min(target_count, candidates.size())):
		targets.append(candidates[i])
	var chain_payload: Dictionary = ProjectileSystemScript.payload_for_id(
		&"chain_lightning", &"magic", ACTION_BURST_MAGIC_COLOR
	)
	var chain_source: Vector2i = _player.grid_position
	for target: Node2D in targets:
		_play_projectile_between(chain_source, target.grid_position, chain_payload)
		chain_source = target.grid_position
	var wis_mod: int = Dice.modifier(_player.stats_component.wisdom)
	var base_damage: int = Dice.roll(6) + max(0, wis_mod) + int(player_level / 2)
	for target: Node2D in targets:
		var damage: int = _apply_typed_damage(target, base_damage, &"magic")
		GameManager.add_log_message(
			"Chain Lightning strikes %s for %d lightning damage." % [target.display_name, damage],
			&"combat_hit"
		)
		_handle_defender_after_damage(target)
	_finish_player_action()


func _find_nearest_visible_enemy_in_range(target_range: int) -> Node2D:
	var nearest_enemy: Node2D = null
	var nearest_distance: float = INF
	for enemy: Node2D in _enemies:
		if enemy == null or not enemy.is_alive():
			continue
		var distance: float = enemy.grid_position.distance_to(_player.grid_position)
		if (
			distance <= target_range
			and _visible_cells.has(enemy.grid_position)
			and distance < nearest_distance
		):
			nearest_distance = distance
			nearest_enemy = enemy
	return nearest_enemy


# ===== Class Ability Helpers =====
func _get_player_level() -> int:
	if _player == null:
		return 1
	if _player.stats_component == null:
		return 1
	return _player.stats_component.level


func _get_ability_unlock_level(ability_id: StringName) -> int:
	match ability_id:
		&"fighter_cleave", &"ranger_focus", &"arcane_spark":
			return 1
		&"fighter_second_wind", &"ranger_volley", &"wizard_frost_nova":
			return 6
		&"fighter_whirlwind", &"ranger_quickstep", &"wizard_chain_lightning":
			return 12
	return 99


func _get_ability_charges_current(ability_id: StringName) -> int:
	var charges: int = 0
	match ability_id:
		&"fighter_cleave":
			charges = _fighter_cleave_charges
		&"fighter_second_wind":
			charges = _fighter_second_wind_charges
		&"fighter_whirlwind":
			charges = _fighter_whirlwind_charges
		&"ranger_focus":
			charges = _ranger_focus_charges
		&"ranger_volley":
			charges = _ranger_volley_charges
		&"ranger_quickstep":
			charges = _ranger_quickstep_charges
		&"arcane_spark":
			charges = _wizard_spark_charges
		&"wizard_frost_nova":
			charges = _wizard_frost_nova_charges
		&"wizard_chain_lightning":
			charges = _wizard_chain_lightning_charges
	return charges


func _get_ability_charges_max(ability_id: StringName) -> int:
	var player_level: int = _get_player_level()
	# Core level-1 abilities gain a second charge at level 20
	match ability_id:
		&"fighter_cleave", &"ranger_focus", &"arcane_spark":
			return 2 if player_level >= 20 else 1
	return 1


func _get_player_class_damage_percent(damage_type: StringName, character_level: int = 1) -> int:
	var base_percent: int = GameManager.get_character_class_damage_percent(
		damage_type, GameManager.pending_character_class, character_level
	)
	if _player != null and _player.inventory_component != null:
		base_percent += _player.inventory_component.get_class_damage_percent_bonus(damage_type)
	return base_percent


func _find_visible_enemies_in_range(target_range: int) -> Array[Node2D]:
	var enemies_in_range: Array[Node2D] = []
	for enemy: Node2D in _enemies:
		if enemy == null or not enemy.is_alive():
			continue
		var distance: float = enemy.grid_position.distance_to(_player.grid_position)
		if distance <= target_range and _visible_cells.has(enemy.grid_position):
			enemies_in_range.append(enemy)
	return enemies_in_range


func _get_adjacent_enemies(cell: Vector2i) -> Array[Node2D]:
	var adjacent: Array[Node2D] = []
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var neighbor: Vector2i = cell + direction
		var enemy: Node2D = _get_enemy_at(neighbor)
		if enemy != null and enemy.is_alive():
			adjacent.append(enemy)
	return adjacent


func _has_ranged_weapon() -> bool:
	if _player == null:
		return false
	return _player.inventory_component.get_equipped_ranged_weapon() != null


# ===== Level Scaling Helpers =====


# Fighter Cleave
func _get_fighter_cleave_splash_percent(player_level: int) -> int:
	if player_level >= 20:
		return 100
	if player_level >= 15:
		return 75
	if player_level >= 10:
		return 60
	return 50


# Fighter Second Wind
func _get_second_wind_heal_percent(player_level: int) -> int:
	if player_level >= 20:
		return 30
	if player_level >= 15:
		return 25
	return 20


func _get_second_wind_shield_value(player_level: int) -> int:
	if player_level >= 20:
		return 4
	if player_level >= 15:
		return 3
	return 2


func _get_second_wind_shield_turns(player_level: int) -> int:
	if player_level >= 20:
		return 5
	if player_level >= 15:
		return 4
	return 3


# Fighter Extra Strike Chance
func _get_fighter_extra_strike_chance(player_level: int) -> int:
	if player_level >= 20:
		return 30
	if player_level >= 15:
		return 24
	if player_level >= 10:
		return 18
	if player_level >= 5:
		return 12
	return 0


# Ranger Hunter's Focus
func _get_hunter_focus_accuracy(player_level: int) -> int:
	if player_level >= 20:
		return 6
	if player_level >= 10:
		return 5
	return 4


func _get_hunter_focus_multiplier(player_level: int) -> int:
	if player_level >= 20:
		return 200
	if player_level >= 15:
		return 175
	return 150


# Ranger Volley
func _get_volley_target_count(player_level: int) -> int:
	if player_level >= 20:
		return 4
	if player_level >= 15:
		return 3
	return 2


func _get_volley_damage_percent(player_level: int) -> int:
	if player_level >= 20:
		return 100
	if player_level >= 15:
		return 90
	return 80


# Ranger Quickstep
func _get_quickstep_haste_phases(player_level: int) -> int:
	return 2 if player_level >= 20 else 1


# Wizard Arcane Spark
func _get_arcane_spark_range(player_level: int) -> int:
	if player_level >= 20:
		return 8
	if player_level >= 10:
		return 7
	return 6


# Wizard Frost Nova
func _get_frost_nova_radius(player_level: int) -> int:
	if player_level >= 15:
		return 3
	return 2


func _get_frost_nova_sleep_turns(player_level: int) -> int:
	return 2 if player_level >= 20 else 1


# Wizard Chain Lightning
func _get_chain_lightning_range(player_level: int) -> int:
	if player_level >= 20:
		return 8
	return 7


func _get_chain_lightning_target_count(player_level: int) -> int:
	if player_level >= 20:
		return 4
	return 3


func _apply_cleave_splash(primary_target: Node, outcome: Dictionary) -> void:
	_cleave_primed = false
	var splash_percent: int = _get_fighter_cleave_splash_percent(_get_player_level())
	var splash_base: int = max(
		1, int(round(outcome["attacker_scaled_damage"] * splash_percent / 100.0))
	)
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		var splash_cell: Vector2i = primary_target.grid_position + direction
		var splash_target: Node2D = _get_enemy_at(splash_cell)
		if splash_target == null or not splash_target.is_alive():
			continue
		var splash_affinity: int = _get_damage_percent(splash_target, &"melee")
		var splash_damage: int = _scale_damage(splash_base, splash_affinity)
		if splash_damage > 0:
			splash_damage = splash_target.stats_component.apply_damage(splash_damage)
		if splash_damage > 0:
			GameManager.add_log_message(
				(
					"Cleave hits %s for %d splash damage."
					% [splash_target.display_name, splash_damage]
				),
				&"combat_hit"
			)
		_handle_defender_after_damage(splash_target)


func _apply_fighter_extra_strike(defender: Node) -> void:
	if GameManager.pending_character_class != GameManager.CLASS_FIGHTER:
		return
	var extra_strike_chance: int = _get_fighter_extra_strike_chance(_get_player_level())
	if extra_strike_chance <= 0:
		return
	if not defender.is_alive():
		return
	if randi_range(1, 100) > extra_strike_chance:
		return
	GameManager.add_log_message("Fighter's training kicks in: an extra strike!", &"combat_hit")
	# No recursive extra strikes — only one follow-up per hit, no chaining
	var damage_percent: int = _get_damage_percent(defender, &"melee")
	var attacker_damage_percent: int = _get_attacker_damage_percent(_player, &"melee")
	var extra_outcome: Dictionary = CombatSystemScript.attack(
		_player, defender, damage_percent, attacker_damage_percent
	)
	if extra_outcome["hit"]:
		_log_damage_affinity(
			defender, &"melee", extra_outcome["attacker_scaled_damage"], extra_outcome["damage"]
		)
		GameManager.add_log_message(
			(
				"Extra strike hits %s for %d melee damage."
				% [defender.display_name, extra_outcome["damage"]]
			),
			&"combat_hit"
		)
	else:
		GameManager.add_log_message(
			"Extra strike misses %s." % [defender.display_name], &"combat_miss"
		)
	_handle_defender_after_damage(defender)


# ===== Items & Containers =====
func _collect_item_at(cell: Vector2i) -> void:
	if not _item_positions.has(cell):
		return
	var item: Resource = _item_positions[cell]
	_player.inventory_component.add_item(item)
	_item_positions.erase(cell)
	GameManager.add_log_message("You pick up %s." % item.display_name, &"loot")
	_play_action_burst(cell, &"loot")
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)


func _open_container_at(cell: Vector2i) -> void:
	if not _container_positions.has(cell):
		return
	var container_data: Dictionary = _container_positions[cell]
	_play_container_open_burst(cell, container_data)
	_container_positions.erase(cell)
	if container_data.get("type", CONTAINER_TYPE_CHEST) == CONTAINER_TYPE_CLUTTER:
		_open_clutter_container(container_data)
	else:
		_open_chest_container(container_data)
	inventory_panel.refresh(_player)
	character_sheet.refresh(_player)
	hud.bind_player(_player)


func _play_action_burst(cell: Vector2i, burst_type: StringName) -> void:
	if map_view == null or not map_view.has_method("play_cell_burst"):
		return
	var color: Color = ACTION_BURST_HIT_COLOR
	var glyph: String = "*"
	match burst_type:
		&"critical":
			color = ACTION_BURST_LOOT_COLOR
			glyph = "✦"
		&"ranged_hit":
			color = Color(0.58, 0.82, 1.0)
			glyph = "›"
		&"magic_hit":
			color = ACTION_BURST_MAGIC_COLOR
			glyph = "✦"
		&"miss":
			color = ACTION_BURST_MISS_COLOR
			glyph = "·"
		&"loot":
			color = ACTION_BURST_LOOT_COLOR
			glyph = "$"
		&"door":
			color = Color(0.82, 0.57, 0.30)
			glyph = "+"
		&"floor":
			color = Color(1.0, 0.88, 0.47)
			glyph = ">"
		&"trap":
			color = ACTION_BURST_WARNING_COLOR
			glyph = "!"
	map_view.play_cell_burst(cell, color, glyph)


func _play_projectile_between(
	source_cell: Vector2i, target_cell: Vector2i, payload: Dictionary
) -> void:
	var cells: Array[Vector2i] = ProjectileSystemScript.line_cells(source_cell, target_cell)
	_play_projectile_trail(cells, payload)


func _play_projectile_cells(cells: Array[Vector2i], payload: Dictionary) -> void:
	_play_projectile_trail(cells, payload)


func _play_projectile_trail(cells: Array[Vector2i], payload: Dictionary) -> void:
	if map_view == null or not map_view.has_method(&"play_projectile_trail"):
		return
	map_view.call(&"play_projectile_trail", cells, payload)


func _projectile_area_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var cells: Dictionary = {}
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _is_inside_map(cell):
				continue
			if not _visible_cells.has(cell) or not _explored_cells.has(cell):
				continue
			if center.distance_to(cell) > radius:
				continue
			cells[cell] = true
	return ProjectileSystemScript.array_from_cell_keys(cells)


func _clear_projectile_trails() -> void:
	if map_view == null or not map_view.has_method(&"clear_projectile_trails"):
		return
	map_view.call(&"clear_projectile_trails")


func _play_container_open_burst(cell: Vector2i, container_data: Dictionary) -> void:
	if map_view == null or not map_view.has_method("play_cell_burst"):
		return
	var burst_color: Color = container_data.get("color", Color(1.0, 0.88, 0.47))
	var burst_glyph: String = "✦"
	if container_data.get("type", CONTAINER_TYPE_CHEST) == CONTAINER_TYPE_CLUTTER:
		burst_glyph = "·"
	map_view.play_cell_burst(cell, burst_color, burst_glyph)


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
	if (
		not _active_boss_encounter.is_empty()
		and not bool(_active_boss_encounter.get("defeated", false))
		and BOSS_FLOORS.has(GameManager.current_floor)
	):
		GameManager.add_log_message(
			"The stairs are sealed by %s." % _active_boss_encounter.get("boss_name", "the boss"),
			&"warning"
		)
		return
	if GameManager.current_floor == FINAL_VICTORY_FLOOR:
		_show_victory_choice()
		return
	_generate_floor(GameManager.current_floor + 1)


func _show_victory_choice() -> void:
	extraction_title_label.text = "FINAL CHOICE"
	extraction_label.text = (
		"You reached the end of the dungeon.\n"
		+ "Leave victorious, or descend into the Endless Deeps until death?"
	)
	leave_button.text = "Leave Victorious"
	descend_button.text = "Delve Forever"
	extraction_panel.visible = true
	leave_button.grab_focus()


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
	damage = _player.stats_component.apply_damage(damage)
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
	_try_apply_player_set_proc()
	return true


func _apply_boss_hazard_tick() -> bool:
	if _boss_hazards.is_empty():
		return true
	if _boss_hazards.has(_player.grid_position):
		var hazard: Dictionary = _boss_hazards[_player.grid_position]
		var source_boss: Node = hazard.get("boss", null)
		var damage_dice: int = int(hazard.get("damage_dice", 0))
		var damage_sides: int = max(2, int(hazard.get("damage_sides", 4)))
		var damage_bonus: int = int(hazard.get("damage_bonus", 0))
		var damage_type: StringName = hazard.get("damage_type", &"magic")
		if damage_dice > 0:
			var raw_damage: int = damage_bonus
			for _i: int in range(damage_dice):
				raw_damage += Dice.roll(damage_sides)
			var damage: int = _player.stats_component.apply_damage(max(1, raw_damage))
			GameManager.emit_player_damaged()
			var message: String = str(hazard.get("message", ""))
			if message.contains("%d"):
				message = message % damage
			elif message.is_empty():
				message = "The boss hazard deals %d %s damage." % [damage, damage_type]
			GameManager.add_log_message(message, &"warning")
			if not _player.is_alive():
				_game_over(false)
				return false
		var effect: StringName = hazard.get("effect", &"")
		if effect != &"":
			if effect == &"poison":
				_poison_turns = max(_poison_turns, max(1, int(hazard.get("effect_turns", 3))))
				_poison_damage_sides = max(2, int(hazard.get("effect_amount", 4)))
				GameManager.add_log_message("Virulent spores cling to you.", &"warning")
			elif effect == &"pull":
				if is_instance_valid(source_boss):
					_try_displace_player_from_boss(
						source_boss, true, max(1, int(hazard.get("effect_amount", 1)))
					)
			elif effect == &"push":
				if is_instance_valid(source_boss):
					_try_displace_player_from_boss(
						source_boss, false, max(1, int(hazard.get("effect_amount", 1)))
					)
			else:
				if not _unknown_boss_hazard_effects.has(effect):
					_unknown_boss_hazard_effects[effect] = true
					GameManager.add_log_message(
						"Unknown boss hazard effect %s; ignoring it." % effect, &"warning"
					)
	var cells_to_erase: Array[Vector2i] = []
	for cell: Vector2i in _boss_hazards.keys():
		var hazard: Dictionary = _boss_hazards.get(cell, {})
		var turns_left: int = int(hazard.get("turns_remaining", 0)) - 1
		if turns_left <= 0:
			cells_to_erase.append(cell)
		else:
			hazard["turns_remaining"] = turns_left
			_boss_hazards[cell] = hazard.duplicate(true)
	for cell: Vector2i in cells_to_erase:
		_boss_hazards.erase(cell)
	return true


func _tick_stun_action() -> void:
	if _stun_actions <= 0:
		return
	_stun_actions -= 1
	if _stun_actions == 0:
		GameManager.add_log_message("You shake off the stun.", &"heal")


func _end_player_turn() -> void:
	if _shield_turns > 0:
		_shield_turns -= 1
	_tick_stun_action()
	if not _apply_poison_tick():
		return
	if not _apply_boss_hazard_tick():
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
	if turn_manager != null:
		turn_manager.run_enemy_phase(_process_enemy_turns)


# ===== Enemy AI =====
func _process_enemy_turns() -> void:
	var blocked_cells: Dictionary = {}
	for enemy in _enemies:
		if enemy != null and enemy.is_alive() and not _should_skip_enemy_for_boss_arena(enemy):
			for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
				blocked_cells[occupied_cell] = true
	if _shopkeeper != null:
		blocked_cells[_shopkeeper.grid_position] = true
	blocked_cells[_player.grid_position] = true

	for enemy in _enemies.duplicate():
		if enemy == null or not enemy.is_alive():
			continue
		if _should_skip_enemy_for_boss_arena(enemy):
			continue
		if _is_enemy_sleeping(enemy):
			continue
		for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
			blocked_cells.erase(occupied_cell)
		var distance_to_player: float = _enemy_distance_to_player(enemy)
		var action_count: int = _advance_enemy_action(enemy)
		if _process_enemy_special_turn(enemy, distance_to_player, action_count, blocked_cells):
			if not _player.is_alive():
				return
		elif distance_to_player <= 1.1:
			_resolve_attack(enemy, _player)
			if not _player.is_alive():
				return
		elif _is_boss_enemy(enemy):
			_try_move_boss_toward_player(enemy, blocked_cells)
		elif distance_to_player <= 8.0:
			var next_step: Vector2i = PathfindingScript.find_next_step(
				enemy.grid_position, _player.grid_position, GameManager.map_data, blocked_cells
			)
			if next_step != enemy.grid_position and next_step != _player.grid_position:
				enemy.set_grid_position(next_step)
		for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
			blocked_cells[occupied_cell] = true


func _should_skip_enemy_for_boss_arena(enemy: Node) -> bool:
	if _active_boss_encounter.is_empty():
		return false
	if not bool(_active_boss_encounter.get("entered", false)):
		return false
	if _is_boss_enemy(enemy):
		return false
	for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
		if _is_cell_in_active_boss_room(occupied_cell):
			return false
	return true


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
	if (
		enemy_data.is_boss
		and _process_boss_turn(enemy, distance_to_player, action_count, blocked_cells)
	):
		return true
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
	_play_projectile_between(
		enemy.grid_position,
		_player.grid_position,
		ProjectileSystemScript.payload_from_enemy_ranged(enemy_data)
	)
	damage = _player.stats_component.apply_damage(damage)
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
	_play_projectile_between(
		enemy.grid_position,
		_player.grid_position,
		ProjectileSystemScript.payload_from_enemy_fireball(enemy_data)
	)
	damage = _player.stats_component.apply_damage(damage)
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
	var summon_data: Resource = _create_summoned_enemy_data(enemy_data)
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


func _create_summoned_enemy_data(summoner_data: Resource) -> Resource:
	var summon_data: Resource = load(summoner_data.summon_enemy_path)
	if summon_data == null:
		return null
	var summoned_data: Resource = summon_data.duplicate(true)
	if summoner_data.display_name == "Lich":
		summoned_data.display_name = "Brittle Skeleton"
		summoned_data.ranged_attack_range = 0
		summoned_data.ranged_attack_interval = 0
		summoned_data.ranged_damage_sides = 0
		summoned_data.ranged_damage_bonus = 0
		summoned_data.ai_preferred_range = 0
	return summoned_data


func _count_summoned_minions(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var summoner_id: int = enemy.get_instance_id()
	var count: int = 0
	for candidate in _enemies:
		if (
			candidate != null
			and is_instance_valid(candidate)
			and candidate.has_meta("summoned_minion")
			and bool(candidate.get_meta("summoned_minion", false))
			and int(candidate.get_meta("summoner_id", 0)) == summoner_id
			and candidate.is_alive()
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


func _enemy_distance_to_player(enemy: Node) -> float:
	var best_distance: float = INF
	for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
		best_distance = min(best_distance, occupied_cell.distance_to(_player.grid_position))
	return (
		best_distance
		if best_distance < INF
		else enemy.grid_position.distance_to(_player.grid_position)
	)


func _process_boss_turn(
	enemy: Node, distance_to_player: float, action_count: int, blocked_cells: Dictionary
) -> bool:
	if not _is_boss_enemy(enemy):
		return false
	if (
		_active_boss_encounter.get("state", BOSS_ARENA_STATE_WAITING_AT_GATE)
		!= BOSS_ARENA_STATE_ACTIVE
	):
		return true
	_update_boss_phase(enemy)
	var state: Dictionary = _boss_state_for(enemy)
	var pending_attack: Resource = state.get("pending_attack", null)
	if pending_attack != null:
		state["telegraph_turns"] = int(state.get("telegraph_turns", 0)) - 1
		if int(state["telegraph_turns"]) <= 0:
			_resolve_boss_attack(enemy, pending_attack, state.get("telegraph_cells", {}))
			state["pending_attack"] = null
			state["telegraph_cells"] = {}
			state["telegraph_turns"] = 0
			_boss_telegraphs.clear()
		else:
			_sync_boss_telegraph_turns(enemy, state)
		_boss_states[enemy] = state
		_refresh_boss_presentation()
		_refresh_map()
		return true
	var enemy_actor: Enemy = enemy as Enemy
	_tick_boss_attack_cooldowns(enemy)
	if enemy_actor.enemy_data.boss_id == &"observer" and distance_to_player > 2.0:
		if _try_move_boss_toward_player(enemy, blocked_cells):
			return true
	var attack: Resource = _choose_boss_attack(enemy, action_count, distance_to_player)
	if attack == null:
		if distance_to_player > 2.0 and _try_move_boss_toward_player(enemy, blocked_cells):
			return true
		return true
	var cells: Dictionary = _boss_attack_cells(enemy, attack)
	if cells.is_empty() and attack.shape != &"summon":
		if distance_to_player > 2.0 and _try_move_boss_toward_player(enemy, blocked_cells):
			return true
		return true
	_queue_boss_attack(enemy, attack, cells)
	if not attack.warning_text.is_empty():
		GameManager.add_log_message(attack.warning_text, &"boss_telegraph")
	else:
		GameManager.add_log_message(
			"%s prepares %s." % [enemy.display_name, attack.id], &"boss_telegraph"
		)
	_refresh_boss_presentation()
	_refresh_map()
	return true


func _update_boss_phase(enemy: Node) -> void:
	if not _is_boss_enemy(enemy):
		return
	var enemy_actor: Enemy = enemy as Enemy
	var state: Dictionary = _boss_state_for(enemy)
	var hp_percent: float = (
		float(enemy.stats_component.current_hp)
		/ max(1.0, float(enemy.stats_component.max_hp))
		* 100.0
	)
	var phase: int = 1
	for threshold: int in enemy_actor.enemy_data.boss_phase_hp_percents:
		if hp_percent <= float(threshold):
			phase += 1
	var previous_phase: int = int(state.get("phase", 1))
	state["phase"] = phase
	_boss_states[enemy] = state
	if phase != previous_phase:
		GameManager.add_log_message(
			"%s shifts into phase %d." % [enemy.display_name, phase], &"boss_phase"
		)
		if (
			is_instance_valid(sensory_feedback)
			and sensory_feedback.has_method(&"play_boss_phase_cue")
		):
			var enemy_data: Resource = enemy_actor.enemy_data
			sensory_feedback.call(&"play_boss_phase_cue", enemy_data.boss_id, phase)


func _tick_boss_attack_cooldowns(enemy: Node) -> void:
	var state: Dictionary = _boss_state_for(enemy)
	var cooldowns: Dictionary = state.get("attack_cooldowns", {})
	var expired: Array[StringName] = []
	for raw_attack_id in cooldowns.keys():
		var attack_id: StringName = raw_attack_id
		var turns_left: int = int(cooldowns.get(attack_id, 0)) - 1
		if turns_left <= 0:
			expired.append(attack_id)
		else:
			cooldowns[attack_id] = turns_left
	for attack_id: StringName in expired:
		cooldowns.erase(attack_id)
	state["attack_cooldowns"] = cooldowns
	_boss_states[enemy] = state


func _choose_boss_attack(enemy: Node, _action_count: int, _distance_to_player: float) -> Resource:
	var enemy_actor: Enemy = enemy as Enemy
	if enemy_actor == null or enemy_actor.enemy_data == null:
		return null
	var state: Dictionary = _boss_state_for(enemy)
	var phase: int = int(state.get("phase", 1))
	var cooldowns: Dictionary = state.get("attack_cooldowns", {})
	var candidates: Array[Resource] = []
	for attack: Resource in enemy_actor.enemy_data.boss_attacks:
		if attack == null:
			continue
		if attack.phase_min > phase:
			continue
		if int(cooldowns.get(attack.id, 0)) > 0:
			continue
		if attack.shape == &"summon" and _boss_summon_slots_available(enemy, attack) <= 0:
			continue
		candidates.append(attack)
	if candidates.is_empty():
		return null
	var exact_phase_candidates: Array[Resource] = []
	for attack: Resource in candidates:
		if attack.phase_min == phase:
			exact_phase_candidates.append(attack)
	if not exact_phase_candidates.is_empty():
		candidates = exact_phase_candidates
	var last_attack_id: StringName = state.get("last_attack_id", &"")
	var preferred: Resource = null
	for attack: Resource in candidates:
		if attack.id != last_attack_id:
			preferred = attack
			break
	if preferred != null:
		return preferred
	return candidates[0]


func _boss_has_windup_intent(enemy: Node, action_count: int, distance_to_player: float) -> bool:
	_update_boss_phase(enemy)
	var attack: Resource = _choose_boss_attack(enemy, action_count, distance_to_player)
	if attack == null:
		return false
	return attack.shape == &"summon" or not _boss_attack_cells(enemy, attack).is_empty()


func _boss_attack_cells(enemy: Node, attack: Resource) -> Dictionary:
	var cells: Dictionary = {}
	if attack == null or _player == null:
		return cells
	var shape: StringName = attack.shape
	match shape:
		&"single_player":
			_add_boss_attack_cell(cells, _player.grid_position)
		&"line_to_player":
			_add_boss_line_cells(cells, enemy, attack)
		&"cross":
			_add_boss_cross_cells(cells, enemy, attack)
		&"ring":
			_add_boss_ring_cells(cells, enemy, attack)
		&"cone":
			_add_boss_cone_cells(cells, enemy, attack)
		&"parallax_gaze":
			_add_boss_parallax_gaze_cells(cells, enemy, attack)
		&"thorn_patch":
			_add_boss_thorn_patch_cells(cells, attack)
		&"eruption_columns":
			_add_boss_eruption_columns_cells(cells, attack)
		&"tidal_lane":
			_add_boss_tidal_lane_cells(cells, enemy, attack)
		&"mirror_ray":
			_add_boss_mirror_ray_cells(cells, enemy, attack)
		&"mirror_reflection":
			_add_boss_mirror_reflection_cells(cells, enemy, attack)
		&"summon":
			_add_boss_summon_preview_cells(cells, enemy, attack)
		_:
			if not _unknown_boss_attack_shapes.has(shape):
				_unknown_boss_attack_shapes[shape] = true
				GameManager.add_log_message(
					"Unknown boss attack shape %s; targeting you instead." % shape, &"warning"
				)
			_add_boss_attack_cell(cells, _player.grid_position)
	return cells


func _add_boss_attack_cell(cells: Dictionary, cell: Vector2i) -> void:
	if _is_inside_map(cell) and _is_cell_in_active_boss_room(cell):
		cells[cell] = true


func _dominant_direction_to_player(enemy: Node) -> Vector2i:
	var delta: Vector2i = _player.grid_position - enemy.grid_position
	if abs(delta.x) >= abs(delta.y):
		return Vector2i.RIGHT if delta.x >= 0 else Vector2i.LEFT
	return Vector2i.DOWN if delta.y >= 0 else Vector2i.UP


func _perpendicular(direction: Vector2i) -> Vector2i:
	if direction.x != 0:
		return Vector2i.DOWN
	return Vector2i.RIGHT


func _add_boss_line_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var direction: Vector2i = _dominant_direction_to_player(enemy)
	var perpendicular: Vector2i = _perpendicular(direction)
	var half_width: int = max(0, int(floor(float(max(1, attack.width)) / 2.0)))
	var occupied: Array[Vector2i] = _enemy_occupied_cells(enemy)
	for origin: Vector2i in occupied:
		if occupied.has(origin + direction):
			continue
		for distance: int in range(1, max(1, attack.range) + 1):
			var center: Vector2i = origin + direction * distance
			for side: int in range(-half_width, half_width + 1):
				_add_boss_attack_cell(cells, center + perpendicular * side)


func _add_boss_cross_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	for direction: Vector2i in CARDINAL_DIRECTIONS:
		for distance: int in range(1, max(1, attack.range) + 1):
			_add_boss_attack_cell(cells, enemy.grid_position + direction * distance)
	_add_boss_attack_cell(cells, _player.grid_position)


func _add_boss_ring_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var radius: int = max(1, attack.radius)
	var occupied_cells: Array[Vector2i] = _enemy_occupied_cells(enemy)
	if occupied_cells.is_empty():
		return
	var min_x: int = occupied_cells[0].x
	var max_x: int = occupied_cells[0].x
	var min_y: int = occupied_cells[0].y
	var max_y: int = occupied_cells[0].y
	for occupied_cell: Vector2i in occupied_cells:
		min_x = min(min_x, occupied_cell.x)
		max_x = max(max_x, occupied_cell.x)
		min_y = min(min_y, occupied_cell.y)
		max_y = max(max_y, occupied_cell.y)
	for y: int in range(min_y - radius, max_y + radius + 1):
		for x: int in range(min_x - radius, max_x + radius + 1):
			var candidate: Vector2i = Vector2i(x, y)
			var minimum_distance: int = radius + 1
			for occupied_cell: Vector2i in occupied_cells:
				var distance: int = max(
					abs(candidate.x - occupied_cell.x), abs(candidate.y - occupied_cell.y)
				)
				minimum_distance = min(minimum_distance, distance)
			if minimum_distance == radius:
				_add_boss_attack_cell(cells, candidate)


func _add_boss_cone_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var direction: Vector2i = _dominant_direction_to_player(enemy)
	var perpendicular: Vector2i = _perpendicular(direction)
	var max_range: int = max(1, attack.range)
	var cone_width: int = max(1, attack.width)
	for distance: int in range(1, max_range + 1):
		var spread: int = max(1, int(floor(float(distance * cone_width) / float(max_range))))
		var center: Vector2i = enemy.grid_position + direction * distance
		for side: int in range(-spread, spread + 1):
			_add_boss_attack_cell(cells, center + perpendicular * side)


func _add_boss_line_in_direction(
	cells: Dictionary, enemy: Node, attack: Resource, direction: Vector2i
) -> void:
	var perpendicular: Vector2i = _perpendicular(direction)
	var half_width: int = max(0, int(floor(float(max(1, attack.width)) / 2.0)))
	var occupied: Array[Vector2i] = _enemy_occupied_cells(enemy)
	for origin: Vector2i in occupied:
		if occupied.has(origin + direction):
			continue
		for distance: int in range(1, max(1, attack.range) + 1):
			var center: Vector2i = origin + direction * distance
			for side: int in range(-half_width, half_width + 1):
				_add_boss_attack_cell(cells, center + perpendicular * side)


func _add_boss_parallax_gaze_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var direction: Vector2i = _dominant_direction_to_player(enemy)
	var perpendicular: Vector2i = _perpendicular(direction)
	var lane_radius: int = max(1, attack.radius)
	var occupied: Array[Vector2i] = _enemy_occupied_cells(enemy)
	for origin: Vector2i in occupied:
		if occupied.has(origin + direction):
			continue
		for lane: int in range(-lane_radius, lane_radius + 1):
			for distance: int in range(1, max(1, attack.range) + 1):
				_add_boss_attack_cell(cells, origin + direction * distance + perpendicular * lane)


func _add_boss_thorn_patch_cells(cells: Dictionary, attack: Resource) -> void:
	var radius: int = max(1, attack.radius)
	for y_offset: int in range(-radius, radius + 1):
		for x_offset: int in range(-radius, radius + 1):
			var distance: int = abs(x_offset) + abs(y_offset)
			if distance > radius + 1:
				continue
			if distance == 0 or x_offset == 0 or y_offset == 0 or abs(x_offset) == abs(y_offset):
				_add_boss_attack_cell(cells, _player.grid_position + Vector2i(x_offset, y_offset))


func _add_boss_eruption_columns_cells(cells: Dictionary, attack: Resource) -> void:
	var half_width: int = max(1, int(floor(float(max(1, attack.width)) / 2.0)))
	for lane: int in range(-half_width, half_width + 1):
		var column_x: int = _player.grid_position.x + lane * 2
		for y_offset: int in range(-max(1, attack.range), max(1, attack.range) + 1):
			_add_boss_attack_cell(cells, Vector2i(column_x, _player.grid_position.y + y_offset))


func _add_boss_tidal_lane_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var direction: Vector2i = _dominant_direction_to_player(enemy)
	var perpendicular: Vector2i = _perpendicular(direction)
	var half_width: int = max(0, int(floor(float(max(1, attack.width)) / 2.0)))
	for distance: int in range(-max(1, attack.range), max(1, attack.range) + 1):
		var center: Vector2i = _player.grid_position + direction * distance
		for side: int in range(-half_width, half_width + 1):
			_add_boss_attack_cell(cells, center + perpendicular * side)


func _add_boss_mirror_ray_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var direction: Vector2i = _dominant_direction_to_player(enemy)
	_add_boss_line_in_direction(cells, enemy, attack, direction)
	_add_boss_line_in_direction(cells, enemy, attack, Vector2i(-direction.x, -direction.y))


func _add_boss_mirror_reflection_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var mirrored_cell: Vector2i = Vector2i(
		enemy.grid_position.x * 2 - _player.grid_position.x,
		enemy.grid_position.y * 2 - _player.grid_position.y
	)
	_add_boss_attack_cell(cells, _player.grid_position)
	_add_boss_attack_cell(cells, mirrored_cell)
	var diagonals: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]
	for direction: Vector2i in diagonals:
		for distance: int in range(1, max(1, attack.radius) + 1):
			_add_boss_attack_cell(cells, _player.grid_position + direction * distance)
			_add_boss_attack_cell(cells, mirrored_cell + direction * distance)


func _add_boss_summon_preview_cells(cells: Dictionary, enemy: Node, attack: Resource) -> void:
	var slots: int = _boss_summon_slots_available(enemy, attack)
	if slots <= 0:
		return
	var blocked_cells: Dictionary = _current_actor_blocked_cells()
	for _index: int in range(slots):
		var summon_cell: Vector2i = _find_boss_room_summon_cell(enemy.grid_position, blocked_cells)
		if summon_cell == Vector2i.ZERO:
			break
		cells[summon_cell] = true
		blocked_cells[summon_cell] = true


func _play_boss_projectile_resolution(enemy: Node, attack: Resource, cells: Dictionary) -> void:
	if attack == null or attack.shape == &"summon":
		return
	var queued_cells: Array[Vector2i] = ProjectileSystemScript.array_from_cell_keys(cells)
	if queued_cells.is_empty():
		return
	var payload: Dictionary = ProjectileSystemScript.payload_from_boss_attack(attack)
	if attack.shape == &"single_player":
		_play_projectile_between(enemy.grid_position, queued_cells[0], payload)
	else:
		_play_projectile_cells(queued_cells, payload)


func _resolve_boss_attack(enemy: Node, attack: Resource, cells: Dictionary) -> void:
	if attack == null:
		return
	if attack.shape == &"summon":
		_resolve_boss_summon(enemy, attack, cells)
		return
	_play_boss_projectile_resolution(enemy, attack, cells)
	var hit: bool = cells.has(_player.grid_position)
	if hit:
		var raw_damage: int = attack.damage_bonus
		for _die_index: int in range(max(1, attack.damage_dice)):
			raw_damage += Dice.roll(max(2, attack.damage_sides))
		var damage: int = _player.stats_component.apply_damage(max(1, raw_damage))
		var message: String = attack.resolve_text
		if message.is_empty():
			message = (
				"%s's %s hits you for %d %s damage."
				% [enemy.display_name, attack.id, damage, attack.damage_type]
			)
		elif message.contains("%d"):
			message = message % damage
		GameManager.add_log_message(
			message,
			(
				&"magic"
				if attack.damage_type == &"magic" or attack.damage_type == &"fire"
				else &"combat_hit"
			)
		)
		_handle_defender_after_damage(_player, damage > 0)
		_play_action_burst(_player.grid_position, &"magic_hit")
	else:
		GameManager.add_log_message(
			"You evade %s's %s." % [enemy.display_name, attack.id], &"combat_miss"
		)
	if _player != null and _player.is_alive():
		_apply_boss_attack_effect(enemy, attack, hit)
	if (
		attack.shape != &"summon"
		and is_instance_valid(enemy)
		and enemy.is_alive()
		and not _active_boss_encounter.is_empty()
		and not bool(_active_boss_encounter.get("defeated", false))
	):
		_queue_boss_hazards(enemy, attack, cells)


func _boss_summon_slots_available(enemy: Node, attack: Resource) -> int:
	var requested: int = max(1, attack.summon_count)
	if attack.summon_max_active <= 0:
		return requested
	var active_minions: int = _count_summoned_minions(enemy)
	return min(requested, max(0, attack.summon_max_active - active_minions))


func _resolve_boss_summon(enemy: Node, attack: Resource, preferred_cells: Dictionary = {}) -> void:
	var active_minions: int = _count_summoned_minions(enemy)
	if attack.summon_max_active > 0 and active_minions >= attack.summon_max_active:
		GameManager.add_log_message(
			"%s already commands enough summons." % enemy.display_name, &"warning"
		)
		return
	var allowed_spawns: int = max(1, attack.summon_count)
	if attack.summon_max_active > 0:
		allowed_spawns = min(allowed_spawns, max(0, attack.summon_max_active - active_minions))
	var blocked_cells: Dictionary = _current_actor_blocked_cells()
	var preferred_list: Array[Vector2i] = []
	for raw_cell in preferred_cells.keys():
		if raw_cell is Vector2i:
			preferred_list.append(raw_cell)
	var spawned: int = 0
	for _index: int in range(allowed_spawns):
		var summon_path: String = _boss_summon_path(enemy, attack)
		if summon_path.is_empty():
			break
		var summon_data: Resource = load(summon_path) if not summon_path.is_empty() else null
		if summon_data == null:
			GameManager.add_log_message(
				"%s's summons fail to answer." % enemy.display_name, &"warning"
			)
			break
		var summon_cell: Vector2i = _take_preferred_summon_cell(preferred_list, blocked_cells)
		if summon_cell == Vector2i.ZERO:
			summon_cell = _find_boss_room_summon_cell(enemy.grid_position, blocked_cells)
		if summon_cell == Vector2i.ZERO:
			break
		var minion: Node2D = _spawn_enemy_instance(
			summon_data, summon_cell, GameManager.current_floor, true
		)
		minion.set_meta("summoned_minion", true)
		minion.set_meta("summoner_id", enemy.get_instance_id())
		minion.stats_component.xp_reward = 0
		blocked_cells[summon_cell] = true
		spawned += 1
	if spawned <= 0:
		GameManager.add_log_message("%s's summons find no room." % enemy.display_name, &"warning")
	else:
		GameManager.add_log_message(
			"%s summons %d ally%s." % [enemy.display_name, spawned, "" if spawned == 1 else "ies"],
			&"magic"
		)


func _take_preferred_summon_cell(
	preferred_cells: Array[Vector2i], blocked_cells: Dictionary
) -> Vector2i:
	while not preferred_cells.is_empty():
		var cell: Vector2i = preferred_cells.pop_front()
		if _is_free_enemy_spawn_cell(cell, blocked_cells):
			return cell
	return Vector2i.ZERO


func _apply_boss_attack_effect(enemy: Node, attack: Resource, hit: bool) -> void:
	if attack.effect == &"":
		return
	var trigger: StringName = attack.effect_trigger
	if trigger == &"hit" and not hit:
		return
	if trigger == &"evade" and hit:
		return
	match attack.effect:
		&"poison":
			_apply_boss_poison_effect(attack)
		&"pull":
			_try_displace_player_from_boss(enemy, true, max(1, attack.effect_amount))
		&"push":
			_try_displace_player_from_boss(enemy, false, max(1, attack.effect_amount))
		&"phase_shift":
			_try_phase_shift_boss(enemy)
		&"stun":
			_apply_boss_stun_effect(enemy, attack)


func _apply_boss_poison_effect(attack: Resource) -> void:
	_poison_turns = max(_poison_turns, max(1, attack.effect_turns))
	_poison_damage_sides = max(2, attack.effect_amount)
	GameManager.add_log_message("Virulent spores cling to you.", &"warning")


func _apply_boss_stun_effect(enemy: Node, attack: Resource) -> void:
	var actions: int = max(1, attack.effect_amount)
	_stun_actions = max(_stun_actions, actions + 1)
	GameManager.add_log_message(
		(
			"%s pins you in place for %d action%s."
			% [enemy.display_name, actions, "" if actions == 1 else "s"]
		),
		&"warning"
	)


func _try_displace_player_from_boss(enemy: Node, toward_boss: bool, steps: int) -> bool:
	var direction: Vector2i = _cardinal_step_between(_player.grid_position, enemy.grid_position)
	if not toward_boss:
		direction = Vector2i(-direction.x, -direction.y)
	if direction == Vector2i.ZERO:
		return false
	var moved: bool = false
	for _step: int in range(steps):
		var target_cell: Vector2i = _player.grid_position + direction
		if not _can_force_player_to_boss_cell(target_cell):
			break
		_player.set_grid_position(target_cell)
		moved = true
	if moved:
		var verb: String = "pulls" if toward_boss else "hurls"
		GameManager.add_log_message(
			"%s %s you across the arena." % [enemy.display_name, verb], &"magic"
		)
		_play_action_burst(_player.grid_position, &"magic_hit")
		_refresh_visibility()
	return moved


func _cardinal_step_between(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	var delta: Vector2i = to_cell - from_cell
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if abs(delta.x) >= abs(delta.y) and delta.x != 0:
		return Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
	if delta.y != 0:
		return Vector2i.DOWN if delta.y > 0 else Vector2i.UP
	return Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT


func _can_force_player_to_boss_cell(cell: Vector2i) -> bool:
	if not _is_cell_in_active_boss_room(cell):
		return false
	if not _is_walkable(cell):
		return false
	if _is_sealed_boss_door(cell):
		return false
	if _get_enemy_at(cell) != null:
		return false
	if _is_shopkeeper_at(cell):
		return false
	return true


func _try_phase_shift_boss(enemy: Node) -> bool:
	if not _is_boss_enemy(enemy):
		return false
	var blocked_cells: Dictionary = _current_actor_blocked_cells()
	for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
		blocked_cells.erase(occupied_cell)
	var mirrored_anchor: Vector2i = Vector2i(
		_player.grid_position.x * 2 - enemy.grid_position.x,
		_player.grid_position.y * 2 - enemy.grid_position.y
	)
	if _try_place_phase_shifted_boss(enemy, mirrored_anchor, blocked_cells):
		return true
	var candidates: Array[Vector2i] = []
	var room_cells: Dictionary = _active_boss_encounter.get("room_cells", {})
	for cell: Vector2i in room_cells.keys():
		if cell == enemy.grid_position:
			continue
		if _can_place_boss_at(enemy, cell, blocked_cells):
			candidates.append(cell)
	if candidates.is_empty():
		return false
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (
				a.distance_squared_to(_player.grid_position)
				> b.distance_squared_to(_player.grid_position)
			)
	)
	return _try_place_phase_shifted_boss(enemy, candidates[0], blocked_cells)


func _try_place_phase_shifted_boss(
	enemy: Node, anchor_cell: Vector2i, blocked_cells: Dictionary
) -> bool:
	if not _can_place_boss_at(enemy, anchor_cell, blocked_cells):
		return false
	enemy.set_grid_position(anchor_cell)
	_refresh_boss_occupied_cells(enemy)
	GameManager.add_log_message(
		"%s steps through a broken reflection." % enemy.display_name, &"magic"
	)
	_play_action_burst(anchor_cell, &"magic_hit")
	return true


func _boss_summon_path(enemy: Node, attack: Resource) -> String:
	var enemy_actor: Enemy = enemy as Enemy
	if (
		enemy_actor != null
		and enemy_actor.enemy_data.boss_id == &"nyxara"
		and attack.id == &"mirror_guard"
	):
		var state: Dictionary = _boss_state_for(enemy)
		var use_prism: bool = bool(state.get("nyxara_summon_toggle", false))
		state["nyxara_summon_toggle"] = not use_prism
		_boss_states[enemy] = state
		return (
			"res://resources/enemies/prism_seer.tres"
			if use_prism
			else "res://resources/enemies/mirror_duelist.tres"
		)
	return attack.summon_enemy_path


func _find_boss_room_summon_cell(origin: Vector2i, blocked_cells: Dictionary) -> Vector2i:
	var room_cells: Dictionary = _active_boss_encounter.get("room_cells", {})
	for radius: int in range(1, 9):
		var candidates: Array[Vector2i] = []
		for cell: Vector2i in room_cells.keys():
			if max(abs(cell.x - origin.x), abs(cell.y - origin.y)) != radius:
				continue
			if _is_free_enemy_spawn_cell(cell, blocked_cells):
				candidates.append(cell)
		if not candidates.is_empty():
			candidates.shuffle()
			return candidates[0]
	return Vector2i.ZERO


func _queue_boss_attack(enemy: Node, attack: Resource, cells: Dictionary) -> void:
	var state: Dictionary = _boss_state_for(enemy)
	state["pending_attack"] = attack
	state["telegraph_turns"] = max(1, attack.telegraph_turns)
	state["telegraph_cells"] = cells.duplicate(true)
	state["last_attack_id"] = attack.id
	var cooldowns: Dictionary = state.get("attack_cooldowns", {})
	cooldowns[attack.id] = max(1, attack.cooldown)
	state["attack_cooldowns"] = cooldowns
	_boss_states[enemy] = state
	_boss_telegraphs.clear()
	var payload: Dictionary = _boss_telegraph_payload_for(enemy, attack)
	var telegraph_turns: int = max(1, attack.telegraph_turns)
	var enemy_actor: Enemy = enemy as Enemy
	var boss_id: StringName = &""
	if enemy_actor != null and enemy_actor.enemy_data != null:
		boss_id = enemy_actor.enemy_data.boss_id
	for cell: Vector2i in cells.keys():
		_boss_telegraphs[cell] = payload.duplicate(true)
		_boss_telegraphs[cell]["attack_id"] = attack.id
		_boss_telegraphs[cell]["shape"] = attack.shape
		_boss_telegraphs[cell]["boss"] = enemy
		_boss_telegraphs[cell]["boss_id"] = boss_id
		_boss_telegraphs[cell]["turns_remaining"] = telegraph_turns
		_boss_telegraphs[cell]["telegraph_turns"] = telegraph_turns


func _sync_boss_telegraph_turns(enemy: Node, state: Dictionary) -> void:
	for cell: Vector2i in _boss_telegraphs.keys():
		var payload: Dictionary = _boss_telegraphs.get(cell, {})
		if payload.get("boss", null) != enemy:
			continue
		payload["turns_remaining"] = max(1, int(state.get("telegraph_turns", 1)))
		_boss_telegraphs[cell] = payload


func _queue_boss_hazards(enemy: Node, attack: Resource, cells: Dictionary) -> void:
	if attack == null or attack.hazard_turns <= 0:
		return
	var payload: Dictionary = _boss_telegraph_payload_for(enemy, attack).duplicate(true)
	payload["fill_color"] = Color(
		payload.get("fill_color", Color(1, 1, 1, 1)).r,
		payload.get("fill_color", Color(1, 1, 1, 1)).g,
		payload.get("fill_color", Color(1, 1, 1, 1)).b,
		payload.get("fill_color", Color(1, 1, 1, 1)).a * 0.55
	)
	payload["border_color"] = Color(
		payload.get("border_color", Color(1, 1, 1, 1)).r,
		payload.get("border_color", Color(1, 1, 1, 1)).g,
		payload.get("border_color", Color(1, 1, 1, 1)).b,
		payload.get("border_color", Color(1, 1, 1, 1)).a * 0.70
	)
	var glyph: String = attack.hazard_glyph
	if glyph.is_empty():
		glyph = attack.telegraph_glyph
	if glyph.is_empty():
		glyph = "~"
	var enemy_actor: Enemy = enemy as Enemy
	var boss_id: StringName = &""
	if enemy_actor != null and enemy_actor.enemy_data != null:
		boss_id = enemy_actor.enemy_data.boss_id
	var hazard_vfx_payload: Dictionary = ProjectileSystemScript.payload_from_boss_hazard(attack)
	for cell: Vector2i in cells.keys():
		if not _is_cell_in_active_boss_room(cell):
			continue
		_boss_hazards[cell] = {
			"turns_remaining": max(1, attack.hazard_turns),
			"boss": enemy,
			"boss_id": boss_id,
			"source_attack_id": attack.id,
			"damage_dice": max(0, attack.hazard_damage_dice),
			"damage_sides": max(2, attack.hazard_damage_sides),
			"damage_bonus": max(0, attack.hazard_damage_bonus),
			"damage_type": attack.hazard_damage_type,
			"effect": attack.hazard_effect,
			"effect_turns": max(0, attack.effect_turns),
			"effect_amount": max(0, attack.effect_amount),
			"glyph": glyph,
			"color": payload.get("color", Color(1, 1, 1, 1)),
			"fill_color": payload.get("fill_color", Color(1, 1, 1, 1)),
			"border_color": payload.get("border_color", Color(1, 1, 1, 1)),
			"message": attack.hazard_message,
			"vfx_payload": hazard_vfx_payload.duplicate(true),
		}


func _boss_telegraph_payload_for(enemy: Node, attack: Resource) -> Dictionary:
	var enemy_actor: Enemy = enemy as Enemy
	var boss_id: StringName = &""
	if enemy_actor != null and enemy_actor.enemy_data != null:
		boss_id = enemy_actor.enemy_data.boss_id
	var glyph: String = "!"
	var color: Color = Color(1.0, 0.64, 0.20, 1.0)
	var fill_color: Color = Color(1.0, 0.16, 0.10, 0.26)
	var border_color: Color = Color(1.0, 0.52, 0.18, 0.78)
	match boss_id:
		&"observer":
			glyph = "⊙"
			color = Color(0.68, 0.88, 1.0, 1.0)
			fill_color = Color(0.18, 0.46, 1.0, 0.20)
			border_color = Color(0.42, 0.78, 1.0, 0.82)
		&"seraphine":
			glyph = "^"
			color = Color(0.78, 1.0, 0.44, 1.0)
			fill_color = Color(0.18, 0.50, 0.16, 0.24)
			border_color = Color(0.66, 0.94, 0.34, 0.78)
		&"vorrak":
			glyph = "*"
			color = Color(1.0, 0.38, 0.12, 1.0)
			fill_color = Color(1.0, 0.18, 0.02, 0.26)
			border_color = Color(1.0, 0.58, 0.18, 0.84)
		&"kaelros":
			glyph = "≈"
			color = Color(0.42, 0.82, 1.0, 1.0)
			fill_color = Color(0.05, 0.30, 0.54, 0.25)
			border_color = Color(0.34, 0.76, 1.0, 0.80)
		&"nyxara":
			glyph = "◇"
			color = Color(0.96, 0.78, 1.0, 1.0)
			fill_color = Color(0.50, 0.14, 0.72, 0.24)
			border_color = Color(0.92, 0.62, 1.0, 0.84)
	if attack != null:
		if attack.shape == &"summon":
			glyph = "+"
		if not attack.telegraph_glyph.is_empty():
			glyph = attack.telegraph_glyph
		if attack.telegraph_color.a > 0.0:
			color = attack.telegraph_color
		if attack.telegraph_fill_color.a > 0.0:
			fill_color = attack.telegraph_fill_color
		if attack.telegraph_border_color.a > 0.0:
			border_color = attack.telegraph_border_color
	return {
		"glyph": glyph,
		"color": color,
		"fill_color": fill_color,
		"border_color": border_color,
	}


func _build_boss_telegraph_payload() -> Dictionary:
	return _boss_telegraphs.duplicate(true)


func _build_boss_hazard_payload() -> Dictionary:
	return _boss_hazards.duplicate(true)


# ===== Biome Presentation =====
func _apply_biome_theme(floor_number: int) -> Dictionary:
	var theme: Dictionary = BiomeCatalogScript.theme_for_floor(floor_number)
	map_view.set_biome_theme(theme)
	hud.set_biome_theme(theme)
	return theme


func _show_biome_title_if_needed(floor_number: int, theme: Dictionary) -> void:
	var biome_index: int = BiomeCatalogScript.biome_index_for_floor(floor_number)
	if biome_index == _last_announced_biome_index:
		return
	_last_announced_biome_index = biome_index
	_show_biome_title(theme)


func _show_biome_title(theme: Dictionary) -> void:
	var accent_color: Color = _theme_color(theme, "accent_color", Color(0.6, 0.843, 0.898))
	var title_color: Color = _theme_color(theme, "title_color", Color(1.0, 0.82, 0.32))
	var subtitle_color: Color = _theme_color(theme, "subtitle_color", Color(0.72, 0.70, 0.62))
	_apply_biome_overlay_style(theme, accent_color)
	biome_kicker_label.text = str(theme.get("kicker", "ENTERING BIOME"))
	biome_kicker_label.add_theme_color_override("font_color", accent_color)
	biome_title_label.text = str(theme.get("name", "The Tower"))
	biome_title_label.add_theme_color_override("font_color", title_color)
	biome_subtitle_label.text = str(theme.get("range_label", "Depths 1-5"))
	biome_subtitle_label.add_theme_color_override("font_color", subtitle_color)
	biome_divider.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.85)
	if _biome_overlay_tween != null and _biome_overlay_tween.is_valid():
		_biome_overlay_tween.kill()
	biome_overlay.visible = true
	biome_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_biome_overlay_tween = create_tween()
	_biome_overlay_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_biome_overlay_tween.set_trans(Tween.TRANS_CUBIC)
	_biome_overlay_tween.set_ease(Tween.EASE_OUT)
	_biome_overlay_tween.tween_property(biome_overlay, "modulate:a", 1.0, 0.35)
	_biome_overlay_tween.tween_interval(1.15)
	_biome_overlay_tween.set_ease(Tween.EASE_IN)
	_biome_overlay_tween.tween_property(biome_overlay, "modulate:a", 0.0, 0.45)
	_biome_overlay_tween.tween_callback(_hide_biome_overlay)


func _boss_accent_color(boss_id: StringName) -> Color:
	match boss_id:
		&"observer":
			return Color(0.68, 0.88, 1.0, 1.0)
		&"seraphine":
			return Color(0.82, 1.0, 0.42, 1.0)
		&"vorrak":
			return Color(1.0, 0.38, 0.12, 1.0)
		&"kaelros":
			return Color(0.42, 0.82, 1.0, 1.0)
		&"nyxara":
			return Color(0.96, 0.72, 1.0, 1.0)
	return Color(1.0, 0.34, 0.47, 1.0)


func _boss_title_color(boss_id: StringName) -> Color:
	match boss_id:
		&"observer":
			return Color(0.90, 0.96, 1.0, 1.0)
		&"seraphine":
			return Color(1.0, 0.72, 0.86, 1.0)
		&"vorrak":
			return Color(1.0, 0.72, 0.28, 1.0)
		&"kaelros":
			return Color(0.68, 0.94, 1.0, 1.0)
		&"nyxara":
			return Color(1.0, 0.82, 1.0, 1.0)
	return Color(1.0, 0.82, 0.32, 1.0)


func _boss_subtitle_color(boss_id: StringName) -> Color:
	match boss_id:
		&"observer":
			return Color(0.72, 0.84, 0.94, 1.0)
		&"seraphine":
			return Color(0.80, 0.94, 0.66, 1.0)
		&"vorrak":
			return Color(0.94, 0.62, 0.42, 1.0)
		&"kaelros":
			return Color(0.62, 0.82, 0.94, 1.0)
		&"nyxara":
			return Color(0.84, 0.72, 0.94, 1.0)
	return Color(0.92, 0.86, 0.74, 1.0)


func _boss_overlay_theme(boss_id: StringName) -> Dictionary:
	var accent_color: Color = _boss_accent_color(boss_id)
	return {
		"overlay_bg_color":
		Color(accent_color.r * 0.055, accent_color.g * 0.040, accent_color.b * 0.065, 0.96),
	}


func _boss_room_tint_color(boss_id: StringName, locked: bool) -> Color:
	var accent_color: Color = _boss_accent_color(boss_id)
	var alpha: float = 0.12 if locked else 0.07
	return Color(accent_color.r, accent_color.g, accent_color.b, alpha)


func _boss_spawn_glyphs(boss_id: StringName) -> Array[String]:
	match boss_id:
		&"observer":
			return ["·", "⊙", "◎", "◉"]
		&"seraphine":
			return ["v", "^", "✹", "╋"]
		&"vorrak":
			return [".", "*", "※", "▴"]
		&"kaelros":
			return ["~", "≈", "≋", "♒"]
		&"nyxara":
			return ["◇", "◆", "◇", "✦"]
	return ["·", "◇", "◆", "■"]


func _show_boss_title(boss_id: StringName, fallback_name: String) -> void:
	var story: Dictionary = BOSS_STORY_BY_ID.get(boss_id, {})
	var accent_color: Color = _boss_accent_color(boss_id)
	var title_color: Color = _boss_title_color(boss_id)
	var subtitle_color: Color = _boss_subtitle_color(boss_id)
	var theme: Dictionary = _boss_overlay_theme(boss_id)
	_apply_biome_overlay_style(theme, accent_color)
	biome_kicker_label.text = str(story.get("kicker", "BOSS ENCOUNTER"))
	biome_kicker_label.add_theme_color_override("font_color", accent_color)
	biome_title_label.text = str(story.get("title", fallback_name)).to_upper()
	biome_title_label.add_theme_color_override("font_color", title_color)
	biome_subtitle_label.text = str(story.get("subtitle", "The room seals behind you."))
	biome_subtitle_label.add_theme_color_override("font_color", subtitle_color)
	biome_divider.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.88)
	if _biome_overlay_tween != null and _biome_overlay_tween.is_valid():
		_biome_overlay_tween.kill()
	biome_overlay.visible = true
	biome_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_biome_overlay_tween = create_tween()
	_biome_overlay_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_biome_overlay_tween.set_trans(Tween.TRANS_CUBIC)
	_biome_overlay_tween.set_ease(Tween.EASE_OUT)
	_biome_overlay_tween.tween_property(biome_overlay, "modulate:a", 1.0, 0.25)
	_biome_overlay_tween.tween_interval(1.40)
	_biome_overlay_tween.set_ease(Tween.EASE_IN)
	_biome_overlay_tween.tween_property(biome_overlay, "modulate:a", 0.0, 0.40)
	_biome_overlay_tween.tween_callback(_hide_biome_overlay)


func _apply_biome_overlay_style(theme: Dictionary, accent_color: Color) -> void:
	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = _theme_color(theme, "overlay_bg_color", Color(0.047, 0.059, 0.082, 0.94))
	panel_style.border_color = accent_color
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.content_margin_left = 28.0
	panel_style.content_margin_top = 22.0
	panel_style.content_margin_right = 28.0
	panel_style.content_margin_bottom = 22.0
	biome_overlay_panel.add_theme_stylebox_override("panel", panel_style)


func _hide_biome_overlay() -> void:
	biome_overlay.visible = false
	biome_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _theme_color(theme: Dictionary, key: String, fallback: Color) -> Color:
	var color: Variant = theme.get(key, fallback)
	if color is Color:
		return color
	return fallback


# ===== Visibility & Map =====
func _refresh_visibility() -> void:
	_visible_cells = FOVSystemScript.calculate_visible_cells(
		_player.grid_position, _get_fov_radius(), GameManager.map_data
	)
	for cell: Vector2i in _visible_cells.keys():
		_explored_cells[cell] = true
	_search_for_secret_walls(true)


func _build_enemy_intents() -> Dictionary:
	var intents: Dictionary = {}
	if _player == null:
		return intents
	for enemy in _enemies:
		if enemy == null or not enemy.is_alive():
			continue
		if not _visible_cells.has(enemy.grid_position):
			continue
		if int(_sleeping_enemies.get(enemy, 0)) > 0:
			intents[enemy.grid_position] = &"sleeping"
			continue
		var enemy_actor: Enemy = enemy as Enemy
		if enemy_actor == null or enemy_actor.enemy_data == null:
			continue
		var enemy_data: Resource = enemy_actor.enemy_data
		var distance_to_player: float = _enemy_distance_to_player(enemy)
		var next_action_count: int = int(_enemy_action_counts.get(enemy, 0)) + 1
		if enemy_data.is_boss:
			var state: Dictionary = _boss_state_for(enemy)
			if state.get("pending_attack", null) != null:
				intents[enemy.grid_position] = &"boss_attack"
			elif _boss_has_windup_intent(enemy, next_action_count, distance_to_player):
				intents[enemy.grid_position] = &"boss_windup"
			elif distance_to_player <= 8.0:
				intents[enemy.grid_position] = &"aware"
			continue
		if distance_to_player <= 1.1:
			intents[enemy.grid_position] = &"melee"
		elif (
			enemy_data.fireball_range > 0
			and distance_to_player <= enemy_data.fireball_range
			and next_action_count % max(1, enemy_data.fireball_interval) == 0
		):
			intents[enemy.grid_position] = &"fireball"
		elif (
			enemy_data.ranged_attack_range > 0
			and distance_to_player <= enemy_data.ranged_attack_range
			and next_action_count % max(1, enemy_data.ranged_attack_interval) == 0
		):
			intents[enemy.grid_position] = &"ranged"
		elif enemy_data.summon_interval > 0 and next_action_count % enemy_data.summon_interval == 0:
			intents[enemy.grid_position] = &"summon"
		elif distance_to_player <= 8.0:
			intents[enemy.grid_position] = &"aware"
	return intents


func _refresh_map() -> void:
	var actors: Array = [_player]
	if _shopkeeper != null:
		actors.append(_shopkeeper)
	for enemy in _enemies:
		actors.append(enemy)
	var enemy_intents: Dictionary = _build_enemy_intents()
	if map_view != null:
		map_view.configure_map(GameManager.map_data)
		map_view.set_visibility(_visible_cells, _explored_cells)
		map_view.set_actors(actors)
		map_view.set_items(_item_positions)
		map_view.set_containers(_container_positions)
		if map_view.has_method(&"set_enemy_intents"):
			map_view.set_enemy_intents(enemy_intents)
	if map_view != null:
		map_view.set_targeting(
			_targeting_active, _target_cursor, _targeting_range_cells, _targeting_area_cells
		)
		if map_view.has_method(&"set_boss_telegraphs"):
			map_view.call(&"set_boss_telegraphs", _build_boss_telegraph_payload())
		map_view.call(&"set_boss_hazards", _build_boss_hazard_payload())
	if map_view != null:
		map_view.set_traps(_trap_data, _revealed_traps, _triggered_traps)
		map_view.set_secret_walls(_secret_walls, _revealed_secret_walls, SECRET_WALL_HINT_COLOR)
	if hud != null and _player != null:
		hud.bind_player(_player)
		if hud.has_method(&"set_visible_enemy_intents"):
			hud.set_visible_enemy_intents(enemy_intents)
	_refresh_boss_presentation()
	if inventory_panel != null and _player != null:
		inventory_panel.refresh(_player)
	if character_sheet != null and _player != null:
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


func _is_boss_door(cell: Vector2i) -> bool:
	if not _is_inside_map(cell):
		return false
	return GameManager.map_data[cell.y][cell.x] == DungeonDataScript.TileType.BOSS_DOOR


func _is_sealed_boss_door(cell: Vector2i) -> bool:
	if not _is_inside_map(cell):
		return false
	return GameManager.map_data[cell.y][cell.x] == DungeonDataScript.TileType.SEALED_BOSS_DOOR


func _get_enemy_at(cell: Vector2i) -> Node2D:
	for enemy in _enemies:
		if enemy != null and enemy.is_alive() and _enemy_occupies_cell(enemy, cell):
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
			if _is_connectivity_walkable(cell, blocked_cell):
				walkable_count += 1

	var frontier: Array[Vector2i] = [origin]
	var visited: Dictionary = {origin: true}
	var cursor: int = 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var neighbor: Vector2i = current + direction
			if visited.has(neighbor) or not _is_connectivity_walkable(neighbor, blocked_cell):
				continue
			visited[neighbor] = true
			frontier.append(neighbor)
	return visited.size() == walkable_count


func _is_connectivity_walkable(cell: Vector2i, blocked_cell: Vector2i) -> bool:
	if cell == blocked_cell or _secret_floor_cells.has(cell) or not _is_inside_map(cell):
		return false
	var tile: int = GameManager.map_data[cell.y][cell.x]
	return (
		DungeonDataScript.is_walkable(tile)
		or tile == DungeonDataScript.TileType.DOOR
		or tile == DungeonDataScript.TileType.BOSS_DOOR
	)


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
	_try_apply_player_set_proc()
	_refresh_visibility()
	_refresh_map()


func _handle_special_trap(trap: Resource, trap_cell: Vector2i) -> void:
	match trap.effect:
		TrapDataScript.TrapEffect.STUN:
			_apply_stun_trap()
		TrapDataScript.TrapEffect.AMBUSH:
			_trigger_ambush_trap(trap_cell)


func _apply_stun_trap() -> void:
	_stun_actions = max(_stun_actions, STUN_TRAP_ACTIONS + 1)
	GameManager.add_log_message(
		"You are stunned for %d actions. Only consumables still work." % STUN_TRAP_ACTIONS,
		&"warning"
	)


func _trigger_ambush_trap(_trap_cell: Vector2i) -> void:
	var blocked_cells: Dictionary = _current_actor_blocked_cells()
	var spawned: int = 0
	for _index: int in range(AMBUSH_TRAP_ENEMY_COUNT):
		var enemy_data: Resource = _choose_ambush_enemy_data()
		if enemy_data == null:
			break
		var spawn_cell: Vector2i = _find_ambush_spawn_cell(_player.grid_position, blocked_cells)
		if spawn_cell == Vector2i.ZERO:
			break
		_spawn_enemy_instance(enemy_data, spawn_cell, GameManager.current_floor, true)
		blocked_cells[spawn_cell] = true
		spawned += 1
	if spawned <= 0:
		GameManager.add_log_message("The ambush trap clicks, but nothing answers.", &"neutral")
		return
	GameManager.add_log_message(
		"%d enem%s rush from the shadows!" % [spawned, "y" if spawned == 1 else "ies"], &"warning"
	)


func _current_actor_blocked_cells() -> Dictionary:
	var blocked_cells: Dictionary = {_player.grid_position: true}
	if _shopkeeper != null:
		blocked_cells[_shopkeeper.grid_position] = true
	for enemy in _enemies:
		if enemy != null and enemy.is_alive():
			for occupied_cell: Vector2i in _enemy_occupied_cells(enemy):
				blocked_cells[occupied_cell] = true
	return blocked_cells


func _choose_ambush_enemy_data() -> Resource:
	var candidates: Array[Resource] = []
	for enemy_data: Resource in _enemy_resources:
		if not AMBUSH_BASIC_ENEMY_NAMES.has(enemy_data.display_name):
			continue
		if _can_spawn_enemy(enemy_data, GameManager.current_floor):
			candidates.append(enemy_data)
	if candidates.is_empty() and GameManager.current_floor >= 16:
		for enemy_data: Resource in _enemy_resources:
			if AMBUSH_APEX_EXCLUDE_NAMES.has(enemy_data.display_name):
				continue
			if _can_spawn_enemy(enemy_data, GameManager.current_floor):
				candidates.append(enemy_data)
	if candidates.is_empty():
		return null
	return candidates[randi_range(0, candidates.size() - 1)]


func _find_ambush_spawn_cell(origin: Vector2i, blocked_cells: Dictionary) -> Vector2i:
	for radius: int in range(AMBUSH_TRAP_MIN_DISTANCE, AMBUSH_TRAP_MAX_DISTANCE + 1):
		var candidates: Array[Vector2i] = []
		for y_offset: int in range(-radius, radius + 1):
			for x_offset: int in range(-radius, radius + 1):
				if max(abs(x_offset), abs(y_offset)) != radius:
					continue
				var cell: Vector2i = origin + Vector2i(x_offset, y_offset)
				if _is_free_enemy_spawn_cell(cell, blocked_cells):
					candidates.append(cell)
		if not candidates.is_empty():
			return candidates[randi_range(0, candidates.size() - 1)]
	return Vector2i.ZERO


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
			_use_targeted_consumable_or_spend_stun(item)
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			_use_targeted_consumable_or_spend_stun(item)
		ItemDataScript.ItemUse.SLEEP:
			_use_targeted_consumable_or_spend_stun(item)
		ItemDataScript.ItemUse.AREA_DAMAGE:
			_use_targeted_consumable_or_spend_stun(item)
		_:
			GameManager.add_log_message("Nothing happens.", &"warning")
			used = false
	return used


func _use_targeted_consumable_or_spend_stun(item: Resource) -> void:
	if _stun_actions > 0:
		_spend_stunned_action()
		return
	_start_targeting(item, &"consumable")


func _attempt_fire_ranged() -> void:
	var ranged_weapon: Resource = _player.inventory_component.get_equipped_ranged_weapon()
	if ranged_weapon == null:
		GameManager.add_log_message("Equip a ranged weapon before pressing F.", &"warning")
		return
	_start_targeting(ranged_weapon, &"weapon")


func _handle_targeting_input(event: InputEvent) -> void:
	var viewport: Viewport = get_viewport()
	var direction: Vector2i = _input_direction(event)
	if _is_escape_key(event) or event.is_action_pressed(&"fire_ranged"):
		_cancel_targeting()
		if viewport != null:
			viewport.set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_confirm_targeting()
		if viewport != null:
			viewport.set_input_as_handled()
	elif direction != Vector2i.ZERO:
		_move_target_cursor(direction)
		if viewport != null:
			viewport.set_input_as_handled()


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
	elif item.use_effect == ItemDataScript.ItemUse.MAGIC_MISSILE:
		area_hint = " Up to %d targets are highlighted." % _get_magic_missile_target_count(item)
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
	if item == null:
		return area_cells
	if item.use_effect == ItemDataScript.ItemUse.MAGIC_MISSILE:
		for target: Node2D in _get_magic_missile_targets(item, center):
			area_cells[target.grid_position] = true
		return area_cells
	if not _is_area_targeting_item(item):
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


func _get_magic_missile_targets(item: Resource, primary_cell: Vector2i) -> Array[Node2D]:
	var targets: Array[Node2D] = []
	var primary_target: Node2D = _get_enemy_at(primary_cell)
	if primary_target == null or not _is_enemy_valid_magic_missile_target(primary_target, item):
		return targets
	targets.append(primary_target)
	var target_count: int = _get_magic_missile_target_count(item)
	while targets.size() < target_count:
		var nearest_target: Node2D = null
		var nearest_primary_distance: float = INF
		var nearest_player_distance: float = INF
		for enemy in _enemies:
			if targets.has(enemy) or not _is_enemy_valid_magic_missile_target(enemy, item):
				continue
			var primary_distance: float = enemy.grid_position.distance_to(primary_cell)
			var player_distance: float = enemy.grid_position.distance_to(_player.grid_position)
			if (
				primary_distance < nearest_primary_distance
				or (
					is_equal_approx(primary_distance, nearest_primary_distance)
					and player_distance < nearest_player_distance
				)
			):
				nearest_target = enemy
				nearest_primary_distance = primary_distance
				nearest_player_distance = player_distance
		if nearest_target == null:
			break
		targets.append(nearest_target)
	return targets


func _is_enemy_valid_magic_missile_target(enemy: Node, item: Resource) -> bool:
	if enemy == null or not enemy.is_alive():
		return false
	if not _visible_cells.has(enemy.grid_position):
		return false
	return enemy.grid_position.distance_to(_player.grid_position) <= item.range


func _get_magic_missile_target_count(item: Resource) -> int:
	if item == null:
		return MAGIC_MISSILE_DEFAULT_TARGET_COUNT
	return max(1, item.target_count)


func _move_target_cursor(direction: Vector2i) -> void:
	var next_cursor: Vector2i = _target_cursor + direction
	if not _is_inside_map(next_cursor):
		return
	_target_cursor = next_cursor
	_refresh_targeting_area()
	_refresh_map()


func _confirm_targeting() -> void:
	if _stun_actions > 0:
		_clear_targeting()
		_refresh_map()
		_spend_stunned_action()
		return
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
		if (
			item.use_effect == ItemDataScript.ItemUse.RANGED_ATTACK
			or item.use_effect == ItemDataScript.ItemUse.MAGIC_MISSILE
			or item.use_effect == ItemDataScript.ItemUse.AREA_DAMAGE
		):
			var secret_damage_type: StringName = (
				&"magic" if source == &"consumable" else item.weapon_damage_type
			)
			_play_projectile_between(
				_player.grid_position,
				cell,
				ProjectileSystemScript.payload_from_item(item, source, secret_damage_type)
			)
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
			return _resolve_magic_missile(item, cell)
		ItemDataScript.ItemUse.AREA_DAMAGE:
			return _resolve_area_damage(item, cell)
		ItemDataScript.ItemUse.SLEEP:
			return _resolve_sleep(item, cell)
	return false


func _resolve_magic_missile(item: Resource, cell: Vector2i) -> bool:
	var missile_targets: Array[Node2D] = _get_magic_missile_targets(item, cell)
	if missile_targets.is_empty():
		GameManager.add_log_message("No visible enemy is in missile range.", &"warning")
		return false
	var missile_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		item, &"consumable", &"magic"
	)
	for target: Node2D in missile_targets:
		_play_projectile_between(_player.grid_position, target.grid_position, missile_payload)
		var raw_damage: int = _roll_item_damage(item, _get_scroll_damage_bonus(item))
		var damage: int = _apply_typed_damage(target, raw_damage, &"magic")
		GameManager.add_log_message(
			"%s strikes %s for %d magic damage." % [item.display_name, target.display_name, damage],
			&"magic"
		)
		_play_action_burst(target.grid_position, &"magic_hit")
		_handle_defender_after_damage(target)
	return true


func _resolve_ranged_attack(item: Resource, defender: Node2D, source: StringName) -> void:
	var is_magic_weapon: bool = (
		source == &"weapon" and (item.is_staff or item.weapon_damage_type == &"magic")
	)
	var roll_result: int = Dice.d20()
	var close_weapon_shot: bool = (
		source == &"weapon"
		and not is_magic_weapon
		and defender.grid_position.distance_to(_player.grid_position) <= 2.0
	)
	if close_weapon_shot:
		roll_result = min(roll_result, Dice.d20())
		GameManager.add_log_message("Too close for a clean shot — disadvantage.", &"warning")
	var stats: Node = _player.stats_component
	var inventory: Node = _player.inventory_component
	var ability_bonus: int
	if is_magic_weapon:
		ability_bonus = Dice.modifier(stats.wisdom)
	else:
		ability_bonus = Dice.modifier(stats.dexterity)
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
	var hunter_focus_active: bool = (
		_hunter_focus_primed and source == &"weapon" and not is_magic_weapon
	)
	if hunter_focus_active:
		var focus_accuracy: int = _get_hunter_focus_accuracy(_get_player_level())
		attack_total += focus_accuracy
	var is_critical: bool = roll_result == 20
	var hit: bool = is_critical or attack_total >= defender.stats_component.get_armor_class()
	var attack_damage_type: StringName = (
		&"magic" if is_magic_weapon or source == &"consumable" else &"ranged"
	)
	var attack_verb: String = (
		"blasts" if is_magic_weapon else ("shoots" if source == &"weapon" else "scorches")
	)
	_play_projectile_between(
		_player.grid_position,
		defender.grid_position,
		ProjectileSystemScript.payload_from_item(item, source, attack_damage_type)
	)
	if hit:
		var damage_bonus: int = _get_scroll_damage_bonus(item)
		if source == &"weapon":
			var weapon_stat_mod: int = (
				Dice.modifier(stats.wisdom) if is_magic_weapon else Dice.modifier(stats.dexterity)
			)
			damage_bonus = weapon_stat_mod + inventory.get_accessory_damage_bonus()
		var raw_damage: int = _roll_item_damage(item, damage_bonus)
		if is_critical:
			raw_damage += _roll_item_base_dice(item)
		var focus_mult: int = (
			_get_hunter_focus_multiplier(_get_player_level()) if hunter_focus_active else 100
		)
		raw_damage = max(1, int(round(raw_damage * focus_mult / 100.0)))
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
		var damage: int = _apply_typed_damage(defender, raw_damage, attack_damage_type)
		GameManager.add_log_message(
			(
				"%s %s %s for %d damage."
				% [_player.display_name, attack_verb, defender.display_name, damage]
			),
			&"combat_hit"
		)
		_play_action_burst(
			defender.grid_position,
			(
				&"critical"
				if is_critical
				else (&"magic_hit" if attack_damage_type == &"magic" else &"ranged_hit")
			)
		)
		_handle_defender_after_damage(defender)
	else:
		GameManager.add_log_message(
			"%s misses %s." % [_player.display_name, defender.display_name], &"combat_miss"
		)
		_play_action_burst(defender.grid_position, &"miss")
	if hunter_focus_active:
		_hunter_focus_primed = false
		if hit:
			GameManager.add_log_message("Hunter's Focus consumed.", &"magic")
		else:
			GameManager.add_log_message("Hunter's Focus consumed on the miss.", &"magic")


func _resolve_area_damage(item: Resource, cell: Vector2i) -> bool:
	var affected_enemies: Array[Node2D] = []
	for enemy in _enemies:
		if enemy == null or not enemy.is_alive() or not _visible_cells.has(enemy.grid_position):
			continue
		if enemy.grid_position.distance_to(cell) <= item.target_radius:
			affected_enemies.append(enemy)
	if affected_enemies.is_empty():
		GameManager.add_log_message("No enemies are caught in the blast.", &"warning")
		return false
	var area_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		item, &"consumable", &"fire" if item.projectile_id == &"fireball" else &"magic"
	)
	var area_vfx_cells: Array[Vector2i] = _projectile_area_cells(cell, item.target_radius)
	_play_projectile_between(_player.grid_position, cell, area_payload)
	_play_projectile_cells(area_vfx_cells, area_payload)
	for enemy: Node2D in affected_enemies:
		var raw_damage: int = _roll_item_damage(item, _get_scroll_damage_bonus(item))
		var damage: int = _apply_typed_damage(enemy, raw_damage, &"magic")
		GameManager.add_log_message(
			"%s erupts for %d damage around %s." % [item.display_name, damage, enemy.display_name],
			&"magic"
		)
		_play_action_burst(enemy.grid_position, &"magic_hit")
		_handle_defender_after_damage(enemy)
	return true


func _resolve_sleep(item: Resource, cell: Vector2i) -> bool:
	var affected_enemies: Array[Node2D] = []
	for enemy in _enemies:
		if enemy == null or not enemy.is_alive() or not _visible_cells.has(enemy.grid_position):
			continue
		if enemy.grid_position.distance_to(cell) <= item.target_radius:
			affected_enemies.append(enemy)
	if affected_enemies.is_empty():
		GameManager.add_log_message("No enemies are in the sleep radius.", &"warning")
		return false
	var sleep_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		item, &"consumable", &"magic"
	)
	var sleep_vfx_cells: Array[Vector2i] = _projectile_area_cells(cell, item.target_radius)
	_play_projectile_between(_player.grid_position, cell, sleep_payload)
	_play_projectile_cells(sleep_vfx_cells, sleep_payload)
	for target: Node2D in affected_enemies:
		_sleeping_enemies[target] = item.effect_duration
		_play_action_burst(target.grid_position, &"magic_hit")
	GameManager.add_log_message("Sleep affects %d enemies." % affected_enemies.size(), &"magic")
	return true


func _roll_item_damage(item: Resource, bonus: int) -> int:
	return max(1, _roll_item_base_dice(item) + item.damage_bonus + bonus)


func _get_potion_heal_amount(item: Resource) -> int:
	var intelligence_modifier: int = max(0, Dice.modifier(_player.stats_component.intelligence))
	var scaled_bonus: int = floori(item.healing_amount * intelligence_modifier * 0.10)
	return item.healing_amount + intelligence_modifier + scaled_bonus


func _get_magic_damage_bonus() -> int:
	return max(0, Dice.modifier(_player.stats_component.wisdom) * 2)


func _get_scroll_damage_bonus(item: Resource) -> int:
	return _get_magic_damage_bonus() + _get_scroll_depth_damage_bonus(item)


func _get_scroll_depth_damage_bonus(item: Resource) -> int:
	if item == null:
		return 0
	var starting_floor: int = max(1, item.min_floor)
	var depth_delta: int = max(0, GameManager.current_floor - starting_floor)
	return floori(float(depth_delta) / SCROLL_DAMAGE_DEPTH_STEP)


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
	if _handle_boss_defeated(enemy):
		GameManager.add_log_message("%s is defeated." % enemy.display_name, &"death")
	elif enemy.get_meta("summoned_minion", false):
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
	_boss_states.erase(enemy)
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
	var price: int = _get_item_shop_price(item, stock_index)
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
	var hp_bonus: int = int(ceil(early_depth * 0.75)) + late_depth
	var armor_bonus: int = int(depth_bonus / 8)
	var attack_bonus: int = int(depth_bonus / 7)
	var damage_bonus: int = int(max(0, depth_bonus - 3) / 8)
	enemy.stats_component.max_hp += hp_bonus
	enemy.stats_component.current_hp = enemy.stats_component.max_hp
	enemy.stats_component.base_armor_class += armor_bonus
	enemy.stats_component.base_attack_bonus += attack_bonus
	enemy.stats_component.base_damage_bonus += damage_bonus
	enemy.stats_component.xp_reward += depth_bonus * 6
	_scale_enemy_special_attacks(enemy, int(depth_bonus / 6))


func _scale_enemy_special_attacks(enemy: Node, special_damage_bonus: int) -> void:
	if special_damage_bonus <= 0:
		return
	var enemy_actor: Enemy = enemy as Enemy
	if enemy_actor == null or enemy_actor.enemy_data == null:
		return
	if (
		enemy_actor.enemy_data.ranged_damage_sides <= 0
		and enemy_actor.enemy_data.fireball_damage_dice <= 0
	):
		return
	enemy_actor.enemy_data = enemy_actor.enemy_data.duplicate(true)
	if enemy_actor.enemy_data.ranged_damage_sides > 0:
		enemy_actor.enemy_data.ranged_damage_bonus += special_damage_bonus
	if enemy_actor.enemy_data.fireball_damage_dice > 0:
		enemy_actor.enemy_data.fireball_damage_bonus += special_damage_bonus


func _choose_enemy_data_for_floor(floor_number: int) -> Resource:
	var candidates: Array[Resource] = []
	var total_weight: int = 0
	for enemy_data: Resource in _enemy_resources:
		if not _can_spawn_enemy(enemy_data, floor_number):
			continue
		candidates.append(enemy_data)
		total_weight += _enemy_spawn_weight(enemy_data, floor_number)

	if candidates.is_empty():
		return _enemy_resources[0]

	var roll: int = randi_range(1, total_weight)
	var running_weight: int = 0
	for enemy_data: Resource in candidates:
		running_weight += _enemy_spawn_weight(enemy_data, floor_number)
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
	if enemy_data.is_boss:
		return false
	if floor_number < enemy_data.min_floor:
		return false
	if not _is_endless_floor(floor_number):
		if enemy_data.max_floor > 0 and floor_number > enemy_data.max_floor:
			return false
	var biome_index: int = BiomeCatalogScript.biome_index_for_floor(floor_number)
	return BiomeCatalogScript.enemy_path_allowed_for_biome(enemy_data.resource_path, biome_index)


func _enemy_spawn_weight(enemy_data: Resource, floor_number: int) -> int:
	var weight: int = max(1, enemy_data.spawn_weight)
	if _is_endless_floor(floor_number) and enemy_data.max_floor > 0:
		return max(1, int(ceil(weight * 0.35)))
	return weight


func _is_endless_floor(floor_number: int) -> bool:
	return (
		BiomeCatalogScript.biome_index_for_floor(floor_number) == BiomeCatalogScript.MAX_BIOME_INDEX
	)


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
	var build_weight_percent: int = _build_relevance_weight_percent(item_data)
	return max(
		1, int(ceil(max(1, item_data.spawn_weight) * rarity_weight * build_weight_percent / 100.0))
	)


func _build_relevance_weight_percent(item_data: Resource) -> int:
	var weight_percent: int = 100
	if item_data.required_class != &"":
		if item_data.required_class == GameManager.pending_character_class:
			weight_percent = BUILD_MATCH_WEIGHT_PERCENT
		else:
			weight_percent = WRONG_CLASS_WEIGHT_PERCENT
	if _would_complete_known_set(item_data):
		weight_percent = max(weight_percent, SET_COMPLETION_WEIGHT_PERCENT)
	return weight_percent


func _is_wrong_class_item(item_data: Resource) -> bool:
	return (
		item_data.required_class != &""
		and item_data.required_class != GameManager.pending_character_class
	)


func _would_complete_known_set(item_data: Resource) -> bool:
	if item_data.set_id == &"" or _player == null or _player.inventory_component == null:
		return false
	var inventory: Node = _player.inventory_component
	var required_count: int = max(2, item_data.set_required_count)
	var owned_other_piece: bool = false
	var matching_count: int = 0
	for owned_item: Resource in inventory.items:
		if owned_item.set_id != item_data.set_id:
			continue
		matching_count += 1
		if owned_item.display_name != item_data.display_name:
			owned_other_piece = true
	return owned_other_piece and matching_count + 1 >= required_count


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
	if floor_number >= 16:
		return ItemDataScript.ItemRarity.EPIC
	if floor_number >= 11:
		return ItemDataScript.ItemRarity.RARE
	if floor_number >= 7:
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
	var build_item: Resource = _choose_build_relevant_shop_item(
		candidates, stock, safe_floor, effective_floor
	)
	if build_item != null and not stock.has(build_item):
		stock.append(build_item)
		candidates.erase(build_item)

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
	var potion_floor: int = effective_floor if floor_number <= 4 else floor_number
	var potion_candidates: Array[Resource] = _get_healing_shop_candidates(potion_floor)
	if potion_candidates.is_empty() and potion_floor != effective_floor:
		potion_floor = effective_floor
		potion_candidates = _get_healing_shop_candidates(potion_floor)
	if potion_candidates.is_empty():
		return null
	if floor_number <= 4:
		var best_potion: Resource = potion_candidates[0]
		for potion: Resource in potion_candidates:
			if potion.healing_amount > best_potion.healing_amount:
				best_potion = potion
		return best_potion
	return _choose_weighted_shop_item(potion_candidates, floor_number, potion_floor)


func _get_healing_shop_candidates(candidate_floor: int) -> Array[Resource]:
	var potion_candidates: Array[Resource] = []
	for item_data: Resource in _item_resources:
		if not _can_spawn_item(item_data, candidate_floor):
			continue
		if item_data.kind == ItemDataScript.ItemKind.CONSUMABLE and item_data.healing_amount > 0:
			potion_candidates.append(item_data)
	return potion_candidates


func _choose_build_relevant_shop_item(
	candidates: Array[Resource], stock: Array, floor_number: int, effective_floor: int
) -> Resource:
	if floor_number < 7:
		return null
	var build_candidates: Array[Resource] = []
	for item_data: Resource in candidates:
		if stock.has(item_data) or item_data.kind == ItemDataScript.ItemKind.CONSUMABLE:
			continue
		if _is_wrong_class_item(item_data):
			continue
		if item_data.required_class != &"" or _would_complete_known_set(item_data):
			build_candidates.append(item_data)
		elif item_data.rarity >= _get_shop_minimum_rarity(floor_number):
			build_candidates.append(item_data)
	if build_candidates.is_empty():
		return null
	return _choose_weighted_shop_item(build_candidates, floor_number, effective_floor)


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
	var build_weight_percent: int = _build_relevance_weight_percent(item_data)
	return max(
		1,
		int(
			ceil(
				(
					max(1, item_data.spawn_weight)
					* rarity_weight
					* floor_weight_percent
					* build_weight_percent
					/ 10000.0
				)
			)
		)
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
	var tier_bonus: int = int(floor_number / GOLD_TIER_FLOOR_SPAN) * 2
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
	_cancel_boss_activation()
	if not _active_boss_encounter.is_empty():
		_active_boss_encounter["state"] = BOSS_ARENA_STATE_DEFEATED
		_active_boss_encounter["defeated"] = true
	GameManager.end_run(victory)
	if victory:
		get_tree().change_scene_to_file("res://scenes/victory.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/game_over.tscn")


# === Price Helpers ===
func _get_item_shop_price(item: Resource, stock_index: int = -1) -> int:
	"""Returns item price adjusted by player CHA and first-slot Golden Deal."""
	return GameManager._get_shop_buy_price(item, _player.stats_component.charisma, stock_index)


func _get_item_sell_price(item: Resource) -> int:
	return GameManager._get_shop_sell_price(item, _player.stats_component.charisma)
