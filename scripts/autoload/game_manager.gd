## Autoload singleton: floor state, turn order, player/enemy registry, XP, and run history.
extends Node

signal player_damaged(new_hp: int, max_hp: int)
signal xp_changed(current_xp: int, xp_to_next: int)
signal level_up(new_level: int)
signal floor_changed(new_floor: int)
signal turn_advanced(turn_count: int)
signal game_over_won(victory: bool)
signal shards_changed(collected: int, total: int)
signal dungeon_generated
signal log_message_added(message: String, message_type: StringName)

# === Constants ===
const HISTORY_PATH: String = "user://character_history.json"
const GAME_VERSION: String = "32.0.0"
const LAST_UPDATED: String = "2026-07-18"
const CLASS_FIGHTER: StringName = &"fighter"
const CLASS_RANGER: StringName = &"ranger"
const CLASS_WIZARD: StringName = &"wizard"
const DEFAULT_CHARACTER_CLASS: StringName = CLASS_FIGHTER
const DIFFICULTY_NORMAL: StringName = &"normal"
const DIFFICULTY_HARD: StringName = &"hard"
const DIFFICULTY_NIGHTMARE: StringName = &"nightmare"
const DEFAULT_DIFFICULTY: StringName = DIFFICULTY_NORMAL
const SHOP_FEATURED_DEAL_MIN_CHARISMA: int = 15
const SHOP_FEATURED_DEAL_DISCOUNT_PERCENT: int = 15
const HARD_BUY_MARKUP_DIVISOR: int = 10
const HARD_SELL_PRICE_MULTIPLIER: float = 0.90
const NIGHTMARE_BUY_PRICE_MULTIPLIER: float = 1.25
const NIGHTMARE_SELL_PRICE_MULTIPLIER: float = 0.78
const SCORE_PER_FLOOR: int = 1000
const SCORE_PER_BOSS: int = 3500
const SCORE_PER_ENEMY: int = 90
const SCORE_PER_ELITE_BONUS: int = 260
const SCORE_PER_GOLD: int = 2
const SCORE_VICTORY_BONUS: int = 10000
const SCORE_ENDLESS_FLOOR_BONUS: int = 2500
const SCORE_PACE_TURN_BUDGET: int = 50
const SCORE_PACE_SAVED_TURN_CAP: int = 20
const SCORE_PER_SAVED_TURN: int = 10
const SCORE_MULTIPLIER_NORMAL: int = 100
const SCORE_MULTIPLIER_HARD: int = 140
const SCORE_MULTIPLIER_NIGHTMARE: int = 190
const TOTAL_PORTAL_SHARDS: int = 5

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
var pending_difficulty: StringName = DEFAULT_DIFFICULTY
var pending_debug_loadout: bool = false
var character_history: Array = []
var last_run_summary: Dictionary = {}
var run_stats: Dictionary = {}


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


func set_pending_difficulty(value: StringName) -> void:
	var normalized_difficulty: StringName = _normalize_difficulty(value)
	if normalized_difficulty == DIFFICULTY_HARD and not is_hard_mode_unlocked():
		normalized_difficulty = DEFAULT_DIFFICULTY
	elif normalized_difficulty == DIFFICULTY_NIGHTMARE and not is_nightmare_mode_unlocked():
		normalized_difficulty = DEFAULT_DIFFICULTY
	pending_difficulty = normalized_difficulty


func get_difficulty_label(value: StringName = &"") -> String:
	var resolved_difficulty: StringName = (
		pending_difficulty if value == &"" else _normalize_difficulty(value)
	)
	match resolved_difficulty:
		DIFFICULTY_HARD:
			return "Hard"
		DIFFICULTY_NIGHTMARE:
			return "Nightmare"
		_:
			return "Normal"


func is_hard_mode() -> bool:
	## Hard-or-higher rules also apply to Nightmare.
	return pending_difficulty == DIFFICULTY_HARD or pending_difficulty == DIFFICULTY_NIGHTMARE


func is_nightmare_mode() -> bool:
	return pending_difficulty == DIFFICULTY_NIGHTMARE


func is_hard_mode_unlocked() -> bool:
	return _has_non_debug_victory(DIFFICULTY_NORMAL)


func is_nightmare_mode_unlocked() -> bool:
	return _has_non_debug_victory(DIFFICULTY_HARD)


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
	var normal_price: int = max(1, ceili(base_price * multiplier))
	if is_nightmare_mode():
		return max(1, ceili(normal_price * NIGHTMARE_BUY_PRICE_MULTIPLIER))
	if is_hard_mode():
		@warning_ignore("integer_division")
		var hard_markup: int = normal_price / HARD_BUY_MARKUP_DIVISOR
		if normal_price % HARD_BUY_MARKUP_DIVISOR != 0:
			hard_markup += 1
		return max(1, normal_price + hard_markup)
	return normal_price


func _get_shop_sell_price(item: Resource, charisma: int) -> int:
	var cha_mod: int = Dice.modifier(charisma)
	var multiplier: float = clampf(0.35 + 0.02 * cha_mod, 0.25, 0.50)
	var normal_price: int = max(1, floori(item.get_price() * multiplier))
	if is_nightmare_mode():
		return max(1, floori(normal_price * NIGHTMARE_SELL_PRICE_MULTIPLIER))
	if is_hard_mode():
		return max(1, floori(normal_price * HARD_SELL_PRICE_MULTIPLIER))
	return normal_price


func reset_run() -> void:
	current_floor = 1
	turn_count = 0
	is_player_turn = true
	has_active_run = true
	player = null
	map_data.clear()
	clear_enemies()
	last_run_summary = {}
	run_stats = _new_run_stats()
	shards_changed.emit(0, TOTAL_PORTAL_SHARDS)


func abandon_run() -> void:
	_clear_run_context()
	last_run_summary = {}


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
	if not run_stats.is_empty():
		run_stats["max_floor"] = max(int(run_stats.get("max_floor", 1)), current_floor)
	floor_changed.emit(current_floor)


func advance_turn() -> void:
	turn_count += 1
	is_player_turn = false
	turn_advanced.emit(turn_count)


func begin_player_turn() -> void:
	is_player_turn = true


func record_player_action(
	source_name: String, damage_channel: StringName, category: StringName
) -> void:
	if not has_active_run:
		return
	var source_key: String = _normalize_source_name(source_name)
	var source_stats: Dictionary = _damage_source_stats(source_key, damage_channel, category)
	source_stats["uses"] = int(source_stats.get("uses", 0)) + 1
	_store_damage_source_stats(source_key, source_stats)


func record_damage_dealt(
	amount: int,
	source_name: String,
	damage_channel: StringName,
	category: StringName = &"",
) -> void:
	if not has_active_run or amount <= 0:
		return
	var source_key: String = _normalize_source_name(source_name)
	var source_stats: Dictionary = _damage_source_stats(source_key, damage_channel, category)
	source_stats["damage"] = int(source_stats.get("damage", 0)) + amount
	source_stats["hits"] = int(source_stats.get("hits", 0)) + 1
	_store_damage_source_stats(source_key, source_stats)
	run_stats["damage_dealt"] = int(run_stats.get("damage_dealt", 0)) + amount
	run_stats["biggest_hit"] = max(int(run_stats.get("biggest_hit", 0)), amount)
	var damage_by_channel: Dictionary = run_stats.get("damage_by_channel", {})
	var channel_key: String = str(damage_channel)
	damage_by_channel[channel_key] = int(damage_by_channel.get(channel_key, 0)) + amount
	run_stats["damage_by_channel"] = damage_by_channel


func record_damage_taken(
	amount: int, source_name: String, damage_channel: StringName = &""
) -> void:
	if not has_active_run or amount <= 0:
		return
	var source_key: String = _normalize_source_name(source_name)
	run_stats["damage_taken"] = int(run_stats.get("damage_taken", 0)) + amount
	run_stats["last_damage_source"] = source_key
	run_stats["last_damage_channel"] = str(damage_channel)
	var incoming_sources: Dictionary = run_stats.get("incoming_sources", {})
	incoming_sources[source_key] = int(incoming_sources.get(source_key, 0)) + amount
	run_stats["incoming_sources"] = incoming_sources


func record_enemy_defeated(
	display_name: String,
	boss_id: StringName = &"",
	is_elite: bool = false,
	is_summon: bool = false,
) -> void:
	if not has_active_run:
		return
	if is_summon:
		run_stats["summon_kills"] = int(run_stats.get("summon_kills", 0)) + 1
		return
	if boss_id != &"":
		var boss_kills: Array = run_stats.get("boss_kills", [])
		for boss_entry: Variant in boss_kills:
			if boss_entry is Dictionary and str(boss_entry.get("id", "")) == str(boss_id):
				return
		(
			boss_kills
			. append(
				{
					"id": str(boss_id),
					"name": display_name,
					"floor": current_floor,
				}
			)
		)
		run_stats["boss_kills"] = boss_kills
		run_stats["enemy_kills"] = int(run_stats.get("enemy_kills", 0)) + 1
		shards_changed.emit(boss_kills.size(), TOTAL_PORTAL_SHARDS)
		return
	run_stats["enemy_kills"] = int(run_stats.get("enemy_kills", 0)) + 1
	if is_elite:
		run_stats["elite_kills"] = int(run_stats.get("elite_kills", 0)) + 1


func record_item_collected() -> void:
	if has_active_run:
		run_stats["items_collected"] = int(run_stats.get("items_collected", 0)) + 1


func record_container_opened() -> void:
	if has_active_run:
		run_stats["containers_opened"] = int(run_stats.get("containers_opened", 0)) + 1


func get_collected_shard_count() -> int:
	var boss_kills: Array = run_stats.get("boss_kills", [])
	return boss_kills.size()


func get_high_score(value: StringName = &"") -> int:
	var difficulty: StringName = (
		pending_difficulty if value == &"" else _normalize_difficulty(value)
	)
	var high_score: int = 0
	for entry: Variant in character_history:
		if not entry is Dictionary:
			continue
		var history_entry: Dictionary = entry
		if _is_debug_history_entry(history_entry):
			continue
		if _normalize_difficulty(history_entry.get("difficulty", DEFAULT_DIFFICULTY)) != difficulty:
			continue
		high_score = max(high_score, int(history_entry.get("score", 0)))
	return high_score


func calculate_run_score(metrics: Dictionary, difficulty: StringName) -> Dictionary:
	var floor_reached: int = max(1, int(metrics.get("floor", 1)))
	var turns: int = max(0, int(metrics.get("turns", 0)))
	var enemy_kills: int = max(0, int(metrics.get("enemy_kills", 0)))
	var elite_kills: int = max(0, int(metrics.get("elite_kills", 0)))
	var boss_value: Variant = metrics.get("boss_kills", 0)
	var boss_kills: int = boss_value.size() if boss_value is Array else max(0, int(boss_value))
	var final_gold: int = max(0, int(metrics.get("final_gold", 0)))
	var victory: bool = bool(metrics.get("victory", false))
	var progress_score: int = floor_reached * SCORE_PER_FLOOR
	var boss_score: int = boss_kills * SCORE_PER_BOSS
	var combat_score: int = enemy_kills * SCORE_PER_ENEMY + elite_kills * SCORE_PER_ELITE_BONUS
	var wealth_score: int = final_gold * SCORE_PER_GOLD
	var saved_turns: int = clampi(
		floor_reached * SCORE_PACE_TURN_BUDGET - turns,
		0,
		floor_reached * SCORE_PACE_SAVED_TURN_CAP,
	)
	var pace_score: int = saved_turns * SCORE_PER_SAVED_TURN
	var victory_score: int = SCORE_VICTORY_BONUS if victory else 0
	var endless_score: int = max(0, floor_reached - 25) * SCORE_ENDLESS_FLOOR_BONUS
	var subtotal: int = (
		progress_score
		+ boss_score
		+ combat_score
		+ wealth_score
		+ pace_score
		+ victory_score
		+ endless_score
	)
	var multiplier_percent: int = _score_multiplier_percent(difficulty)
	var total_score: int = roundi(float(subtotal * multiplier_percent) / 100.0)
	return {
		"progress": progress_score,
		"bosses": boss_score,
		"combat": combat_score,
		"wealth": wealth_score,
		"pace": pace_score,
		"victory": victory_score,
		"endless": endless_score,
		"saved_turns": saved_turns,
		"subtotal": subtotal,
		"multiplier_percent": multiplier_percent,
		"total": total_score,
	}


func end_run(victory: bool) -> void:
	last_run_summary = _build_last_run_summary(victory)
	if has_active_run and not bool(last_run_summary.get("archived_debug", false)):
		_record_character(last_run_summary)
	_clear_run_context()
	game_over_won.emit(victory)


func clear_finished_run_context() -> void:
	_clear_run_context()
	last_run_summary = {}


# === Private Methods ===


func _normalize_difficulty(value: Variant) -> StringName:
	var normalized_value: StringName = StringName(str(value).strip_edges().to_lower())
	match normalized_value:
		DIFFICULTY_HARD, DIFFICULTY_NIGHTMARE:
			return normalized_value
		_:
			return DEFAULT_DIFFICULTY


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


func _build_last_run_summary(victory: bool) -> Dictionary:
	var level: int = 1
	var final_hp: int = 0
	var max_hp: int = 0
	var final_gold: int = 0
	var final_xp: int = 0
	var character_name: String = (
		pending_character_name if not pending_character_name.is_empty() else "Nameless"
	)
	var loadout: Dictionary = {}
	var inventory_names: Array[String] = []
	if player != null:
		var stats: Variant = player.get("stats_component")
		if stats != null:
			level = int(stats.level)
			final_hp = int(stats.current_hp)
			max_hp = int(stats.max_hp)
			final_gold = int(stats.gold)
			final_xp = int(stats.xp)
		var actor_name: Variant = player.get("display_name")
		if actor_name is String and not actor_name.is_empty():
			character_name = actor_name
		var inventory: Variant = player.get("inventory_component")
		if inventory != null:
			loadout = _capture_loadout(inventory)
			inventory_names = _capture_inventory(inventory)
	var boss_kills: Array = run_stats.get("boss_kills", [])
	var metrics: Dictionary = {
		"floor": max(current_floor, int(run_stats.get("max_floor", current_floor))),
		"turns": turn_count,
		"enemy_kills": int(run_stats.get("enemy_kills", 0)),
		"elite_kills": int(run_stats.get("elite_kills", 0)),
		"boss_kills": boss_kills,
		"final_gold": final_gold,
		"victory": victory,
	}
	var score_breakdown: Dictionary = calculate_run_score(metrics, pending_difficulty)
	var previous_high_score: int = get_high_score(pending_difficulty)
	var run_score: int = int(score_breakdown.get("total", 0))
	var summary: Dictionary = {
		"name": character_name,
		"floor": int(metrics["floor"]),
		"level": level,
		"victory": victory,
		"class": String(pending_character_class),
		"version": GAME_VERSION,
		"archived_debug": pending_debug_loadout,
		"difficulty": String(pending_difficulty),
		"turns": turn_count,
		"final_hp": final_hp,
		"max_hp": max_hp,
		"final_gold": final_gold,
		"final_xp": final_xp,
		"enemy_kills": int(run_stats.get("enemy_kills", 0)),
		"elite_kills": int(run_stats.get("elite_kills", 0)),
		"summon_kills": int(run_stats.get("summon_kills", 0)),
		"boss_kills": boss_kills.duplicate(true),
		"shards_collected": boss_kills.size(),
		"damage_dealt": int(run_stats.get("damage_dealt", 0)),
		"damage_taken": int(run_stats.get("damage_taken", 0)),
		"biggest_hit": int(run_stats.get("biggest_hit", 0)),
		"damage_by_channel": run_stats.get("damage_by_channel", {}).duplicate(true),
		"damage_sources": _rank_damage_sources(),
		"incoming_sources": run_stats.get("incoming_sources", {}).duplicate(true),
		"most_used_attack": _best_damage_source(&"uses"),
		"most_damage_attack": _best_damage_source(&"damage"),
		"defeated_by": "" if victory else str(run_stats.get("last_damage_source", "Unknown")),
		"defeated_by_channel": "" if victory else str(run_stats.get("last_damage_channel", "")),
		"items_collected": int(run_stats.get("items_collected", 0)),
		"containers_opened": int(run_stats.get("containers_opened", 0)),
		"loadout": loadout,
		"inventory": inventory_names,
		"score": int(score_breakdown.get("total", 0)),
		"score_breakdown": score_breakdown,
		"previous_high_score": previous_high_score,
		"high_score":
		previous_high_score if pending_debug_loadout else max(previous_high_score, run_score),
		"is_new_high_score": not pending_debug_loadout and run_score > previous_high_score,
	}
	summary.make_read_only()
	return summary


func _record_character(summary: Dictionary) -> void:
	var archive_entry: Dictionary = summary.duplicate(true)
	archive_entry.erase("archived_debug")
	character_history.push_front(archive_entry)
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
		if character_history != raw_history:
			_save_character_history()


func _save_character_history() -> void:
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(character_history))


func _filter_character_history(raw_history: Array) -> Array:
	var filtered: Array = []
	for entry: Variant in raw_history:
		if entry is Dictionary and not _is_debug_history_entry(entry):
			filtered.append(_migrate_character_history_entry(entry))
	return filtered


func _migrate_character_history_entry(entry: Dictionary) -> Dictionary:
	var migrated_entry: Dictionary = entry.duplicate(true)
	if str(migrated_entry.get("class", "")) == "mage":
		migrated_entry["class"] = String(CLASS_WIZARD)
	migrated_entry["difficulty"] = String(
		_normalize_difficulty(migrated_entry.get("difficulty", DEFAULT_DIFFICULTY))
	)
	return migrated_entry


func _clear_run_context() -> void:
	has_active_run = false
	player = null
	map_data.clear()
	clear_enemies()
	pending_character_name = ""
	pending_ability_scores.clear()
	pending_character_class = DEFAULT_CHARACTER_CLASS
	pending_debug_loadout = false
	run_stats = {}
	shards_changed.emit(0, TOTAL_PORTAL_SHARDS)


func _is_debug_history_entry(entry: Dictionary) -> bool:
	if bool(entry.get("archived_debug", false)):
		return true
	return str(entry.get("name", "")).strip_edges().to_lower() == "debug"


func _new_run_stats() -> Dictionary:
	return {
		"max_floor": 1,
		"enemy_kills": 0,
		"elite_kills": 0,
		"summon_kills": 0,
		"boss_kills": [],
		"damage_dealt": 0,
		"damage_taken": 0,
		"biggest_hit": 0,
		"damage_by_channel": {},
		"damage_sources": {},
		"incoming_sources": {},
		"last_damage_source": "",
		"last_damage_channel": "",
		"items_collected": 0,
		"containers_opened": 0,
	}


func _has_non_debug_victory(difficulty: StringName) -> bool:
	for entry: Variant in character_history:
		if not entry is Dictionary:
			continue
		var history_entry: Dictionary = entry
		if _is_debug_history_entry(history_entry):
			continue
		var victory_value: Variant = history_entry.get("victory", false)
		if typeof(victory_value) != TYPE_BOOL or not victory_value:
			continue
		if _normalize_difficulty(history_entry.get("difficulty", DEFAULT_DIFFICULTY)) == difficulty:
			return true
	return false


func _score_multiplier_percent(difficulty: StringName) -> int:
	match _normalize_difficulty(difficulty):
		DIFFICULTY_HARD:
			return SCORE_MULTIPLIER_HARD
		DIFFICULTY_NIGHTMARE:
			return SCORE_MULTIPLIER_NIGHTMARE
		_:
			return SCORE_MULTIPLIER_NORMAL


func _normalize_source_name(source_name: String) -> String:
	var normalized_name: String = source_name.strip_edges()
	return normalized_name if not normalized_name.is_empty() else "Unknown"


func _damage_source_stats(
	source_key: String, damage_channel: StringName, category: StringName
) -> Dictionary:
	var damage_sources: Dictionary = run_stats.get("damage_sources", {})
	var source_stats: Dictionary = (
		damage_sources
		. get(
			source_key,
			{
				"name": source_key,
				"channel": str(damage_channel),
				"category": str(category),
				"uses": 0,
				"hits": 0,
				"damage": 0,
			},
		)
	)
	if str(source_stats.get("channel", "")).is_empty() and damage_channel != &"":
		source_stats["channel"] = str(damage_channel)
	if str(source_stats.get("category", "")).is_empty() and category != &"":
		source_stats["category"] = str(category)
	return source_stats


func _store_damage_source_stats(source_key: String, source_stats: Dictionary) -> void:
	var damage_sources: Dictionary = run_stats.get("damage_sources", {})
	damage_sources[source_key] = source_stats
	run_stats["damage_sources"] = damage_sources


func _rank_damage_sources() -> Array[Dictionary]:
	var ranked_sources: Array[Dictionary] = []
	var damage_sources: Dictionary = run_stats.get("damage_sources", {})
	for source_value: Variant in damage_sources.values():
		if source_value is Dictionary:
			ranked_sources.append(source_value.duplicate(true))
	ranked_sources.sort_custom(_damage_source_precedes)
	return ranked_sources


func _damage_source_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_damage: int = int(left.get("damage", 0))
	var right_damage: int = int(right.get("damage", 0))
	if left_damage != right_damage:
		return left_damage > right_damage
	var left_uses: int = int(left.get("uses", 0))
	var right_uses: int = int(right.get("uses", 0))
	if left_uses != right_uses:
		return left_uses > right_uses
	return str(left.get("name", "")) < str(right.get("name", ""))


func _best_damage_source(metric: StringName) -> Dictionary:
	var best_source: Dictionary = {}
	var best_value: int = 0
	var damage_sources: Dictionary = run_stats.get("damage_sources", {})
	for source_value: Variant in damage_sources.values():
		if not source_value is Dictionary:
			continue
		var source_stats: Dictionary = source_value
		var value: int = int(source_stats.get(String(metric), 0))
		if value > best_value:
			best_value = value
			best_source = source_stats
	return best_source.duplicate(true)


func _capture_loadout(inventory: Variant) -> Dictionary:
	var loadout: Dictionary = {}
	var melee_weapon: Variant = inventory.get("equipped_melee_weapon")
	var ranged_weapon: Variant = inventory.get("equipped_ranged_weapon")
	var slots: Dictionary = {
		"melee": melee_weapon,
		"ranged": ranged_weapon,
		"armor": inventory.get("equipped_armor"),
		"accessory_1": inventory.get("equipped_accessory_1"),
		"accessory_2": inventory.get("equipped_accessory_2"),
	}
	for slot_name: String in slots:
		var item: Variant = slots[slot_name]
		if item != null:
			loadout[slot_name] = _item_display_name(item)
	return loadout


func _capture_inventory(inventory: Variant) -> Array[String]:
	var item_names: Array[String] = []
	var inventory_items: Variant = inventory.get("items")
	if inventory_items is Array:
		for item: Variant in inventory_items:
			if item != null:
				item_names.append(_item_display_name(item))
	return item_names


func _item_display_name(item: Variant) -> String:
	var item_name: Variant = item.get("display_name")
	if item_name is String and not item_name.strip_edges().is_empty():
		return item_name
	return "Unnamed item"
