## Autoload singleton: floor state, turn order, player/enemy registry, XP, and run history.
extends Node

signal player_damaged(new_hp: int, max_hp: int)
signal xp_changed(current_xp: int, xp_to_next: int)
signal level_up(new_level: int)
signal floor_changed(new_floor: int)
signal turn_advanced(turn_count: int)
signal game_over_won(victory: bool)
signal dungeon_generated
signal log_message_added(message: String, message_type: StringName)

# === Constants ===
const HISTORY_PATH: String = "user://character_history.json"
const GAME_VERSION: String = "23.0.0"
const LAST_UPDATED: String = "2026-07-10"
const CLASS_FIGHTER: StringName = &"fighter"
const CLASS_RANGER: StringName = &"ranger"
const CLASS_WIZARD: StringName = &"wizard"
const DEFAULT_CHARACTER_CLASS: StringName = CLASS_FIGHTER
const SHOP_FEATURED_DEAL_MIN_CHARISMA: int = 15
const SHOP_FEATURED_DEAL_DISCOUNT_PERCENT: int = 15
const LEGACY_TEST_HISTORY_NAMES: Array[String] = [
	"debug",
	"Fresh Delver",
	"Old Delver",
	"Patch Hero",
	"Long Debug Name",
]

# === Public Variables ===
var player: Node2D
var enemies: Array[Node2D] = []
var map_data: Array = []
var map_width: int = 48
var map_height: int = 32
var current_floor: int = 1
var turn_count: int = 0
var is_player_turn: bool = true
var has_active_run: bool = false
var pending_character_name: String = ""
var pending_ability_scores: Dictionary = {}
var pending_character_class: StringName = DEFAULT_CHARACTER_CLASS
var pending_debug_loadout: bool = false
var character_history: Array = []


# === Lifecycle Methods ===
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_character_history()


# === Public Methods ===
func prepare_character(
	character_name: String,
	ability_scores: Dictionary,
	character_class: StringName = DEFAULT_CHARACTER_CLASS
) -> void:
	pending_character_name = character_name.strip_edges()
	pending_character_class = _normalize_character_class(character_class)
	pending_debug_loadout = pending_character_name.to_lower() == "debug"
	if pending_debug_loadout:
		pending_ability_scores = {
			"str": 20,
			"dex": 20,
			"con": 20,
			"int": 20,
			"wis": 20,
			"cha": 20,
		}
	else:
		pending_ability_scores = ability_scores.duplicate(true)


func get_character_class_label(character_class: StringName = &"") -> String:
	match _resolve_character_class(character_class):
		CLASS_RANGER:
			return "Ranger"
		CLASS_WIZARD:
			return "Wizard"
		_:
			return "Fighter"


func get_character_class_description(character_class: StringName = &"") -> String:
	match _resolve_character_class(character_class):
		CLASS_RANGER:
			return (
				"Damage: melee 50% (60/70 at Lv15/20), ranged 150% "
				+ "(160/170/175 at Lv10/15/20).\n"
				+ "Starter: Hunting Bow. Q: Focus Lv1, Volley Lv6, Quickstep Lv12.\n"
				+ "Plan: keep distance, buy ranged gear, and sell off-class drops."
			)
		CLASS_WIZARD:
			return (
				"Damage: magic 200% (220/240 at Lv15/20), melee/ranged 60% "
				+ "(70 at Lv20).\n"
				+ "Starter: Apprentice Staff. Staffs use WIS, F to fire, and magic damage.\n"
				+ "Plan: scale WIS, use staffs/scrolls, and respect magic-resistant enemies."
			)
		_:
			return (
				"Damage: melee 150% (160/170/180 at Lv10/15/20).\n"
				+ "Starter: Training Sword. Q: Cleave Lv1, Second Wind Lv6, Whirlwind Lv12.\n"
				+ "Plan: close distance, buy melee gear, and use armor to survive trades."
			)


func get_character_class_damage_percent(
	damage_type: StringName, character_class: StringName = &"", character_level: int = 1
) -> int:
	var resolved_class: StringName = _resolve_character_class(character_class)
	var damage_percent: int = 100
	if resolved_class == CLASS_RANGER:
		if damage_type == &"melee":
			if character_level >= 20:
				damage_percent = 70
			elif character_level >= 15:
				damage_percent = 60
			else:
				damage_percent = 50
		elif damage_type == &"ranged":
			if character_level >= 20:
				damage_percent = 175
			elif character_level >= 15:
				damage_percent = 170
			elif character_level >= 10:
				damage_percent = 160
			else:
				damage_percent = 150
	elif resolved_class == CLASS_WIZARD:
		if damage_type == &"magic":
			if character_level >= 20:
				damage_percent = 240
			elif character_level >= 15:
				damage_percent = 220
			else:
				damage_percent = 200
		elif damage_type == &"melee" or damage_type == &"ranged":
			if character_level >= 20:
				damage_percent = 70
			else:
				damage_percent = 60
	elif damage_type == &"melee":
		if character_level >= 20:
			damage_percent = 180
		elif character_level >= 15:
			damage_percent = 170
		elif character_level >= 10:
			damage_percent = 160
		else:
			damage_percent = 150
	return damage_percent


func _is_shop_featured_deal(charisma: int, stock_index: int) -> bool:
	return stock_index == 0 and charisma >= SHOP_FEATURED_DEAL_MIN_CHARISMA


func _get_shop_buy_price(item: Resource, charisma: int, stock_index: int = -1) -> int:
	var base_price: int = item.get_price()
	var cha_mod: int = Dice.modifier(charisma)
	var multiplier: float = clampf(1.0 - 0.05 * cha_mod, 0.5, 1.5)
	if _is_shop_featured_deal(charisma, stock_index):
		multiplier *= (100.0 - SHOP_FEATURED_DEAL_DISCOUNT_PERCENT) / 100.0
	return max(1, ceili(base_price * multiplier))


func _get_shop_sell_price(item: Resource, charisma: int) -> int:
	var cha_mod: int = Dice.modifier(charisma)
	var multiplier: float = clampf(0.35 + 0.02 * cha_mod, 0.25, 0.50)
	return max(1, floori(item.get_price() * multiplier))


func reset_run() -> void:
	current_floor = 1
	turn_count = 0
	is_player_turn = true
	has_active_run = true
	player = null
	map_data.clear()
	clear_enemies()


func abandon_run() -> void:
	has_active_run = false
	player = null
	map_data.clear()
	clear_enemies()
	pending_character_name = ""
	pending_ability_scores.clear()
	pending_character_class = DEFAULT_CHARACTER_CLASS
	pending_debug_loadout = false


func register_player(p: Node2D) -> void:
	player = p


func register_enemy(e: Node2D) -> void:
	enemies.append(e)


func remove_enemy(e: Node2D) -> void:
	enemies.erase(e)


func clear_enemies() -> void:
	enemies.clear()


func set_map_data(new_map_data: Array) -> void:
	map_data = new_map_data
	dungeon_generated.emit()


func emit_player_damaged() -> void:
	if player == null:
		return
	var stats: Variant = player.get("stats_component")
	if stats != null:
		player_damaged.emit(stats.current_hp, stats.max_hp)


func emit_xp_changed() -> void:
	if player == null:
		return
	var stats: Variant = player.get("stats_component")
	if stats != null:
		var next_level_xp: int = stats.xp_for_next_level()
		xp_changed.emit(stats.xp, next_level_xp)


func add_log_message(message: String, message_type: StringName = &"neutral") -> void:
	log_message_added.emit(message, message_type)


func get_version_label() -> String:
	return "Version %s • Updated %s" % [GAME_VERSION, LAST_UPDATED]


func start_floor(floor_number: int) -> void:
	current_floor = floor_number
	floor_changed.emit(current_floor)


func advance_turn() -> void:
	turn_count += 1
	is_player_turn = false
	turn_advanced.emit(turn_count)


func begin_player_turn() -> void:
	is_player_turn = true


func end_run(victory: bool) -> void:
	if has_active_run and not pending_debug_loadout:
		_record_character(victory)
	has_active_run = false
	game_over_won.emit(victory)


# === Private Methods ===
func _normalize_character_class(character_class: StringName) -> StringName:
	match character_class:
		CLASS_FIGHTER, CLASS_RANGER, CLASS_WIZARD:
			return character_class
		_:
			return DEFAULT_CHARACTER_CLASS


func _resolve_character_class(character_class: StringName) -> StringName:
	if character_class == &"":
		return pending_character_class
	return _normalize_character_class(character_class)


func _record_character(victory: bool) -> void:
	var level: int = 1
	var character_name: String = (
		pending_character_name if not pending_character_name.is_empty() else "Nameless"
	)
	if player != null:
		var stats: Variant = player.get("stats_component")
		if stats != null:
			level = stats.level
		var actor_name: Variant = player.get("display_name")
		if actor_name is String and not actor_name.is_empty():
			character_name = actor_name
	(
		character_history
		. push_front(
			{
				"name": character_name,
				"floor": current_floor,
				"level": level,
				"victory": victory,
				"version": GAME_VERSION,
				"class": String(pending_character_class),
			}
		)
	)
	_save_character_history()


func _load_character_history() -> void:
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		var raw_history: Array = parsed
		character_history = _filter_character_history(raw_history)
		if character_history.size() != raw_history.size():
			_save_character_history()


func _save_character_history() -> void:
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(character_history))


func _filter_character_history(raw_history: Array) -> Array:
	var filtered: Array = []
	for entry: Variant in raw_history:
		if entry is Dictionary and not _is_legacy_test_history_entry(entry):
			filtered.append(_migrate_character_history_entry(entry))
	return filtered


func _migrate_character_history_entry(entry: Dictionary) -> Dictionary:
	var migrated_entry: Dictionary = entry.duplicate(true)
	if str(migrated_entry.get("class", "")) == "mage":
		migrated_entry["class"] = String(CLASS_WIZARD)
	return migrated_entry


func _is_legacy_test_history_entry(entry: Dictionary) -> bool:
	var character_name: String = str(entry.get("name", "")).strip_edges()
	if character_name.to_lower() == "debug":
		return true
	return LEGACY_TEST_HISTORY_NAMES.has(character_name)
