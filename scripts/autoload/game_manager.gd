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
var character_history: Array = []


# === Lifecycle Methods ===
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_character_history()


# === Public Methods ===
func prepare_character(character_name: String, ability_scores: Dictionary) -> void:
	pending_character_name = character_name.strip_edges()
	pending_ability_scores = ability_scores.duplicate(true)


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
	if has_active_run:
		_record_character(victory)
	has_active_run = false
	game_over_won.emit(victory)


func get_history_lines() -> Array[String]:
	var lines: Array[String] = []
	for entry: Dictionary in character_history:
		var result: String = "Victory" if entry.get("victory", false) else "Fell"
		(
			lines
			. append(
				(
					"%s - Floor %d, Level %d - %s"
					% [
						entry.get("name", "Unknown"),
						entry.get("floor", 1),
						entry.get("level", 1),
						result,
					]
				)
			)
		)
	return lines


# === Private Methods ===
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
			}
		)
	)
	if character_history.size() > 12:
		character_history.resize(12)
	_save_character_history()


func _load_character_history() -> void:
	if not FileAccess.file_exists(HISTORY_PATH):
		return
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		character_history = parsed


func _save_character_history() -> void:
	var file: FileAccess = FileAccess.open(HISTORY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(character_history))
