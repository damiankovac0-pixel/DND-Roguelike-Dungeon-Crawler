## Victory or death screen with retry and quit options.
class_name EndScreen
extends Control

# === Exports ===
@export var title_text: String = "Game Over"
@export_multiline var body_text: String = ""
@export var restart_scene: String = "res://scenes/game.tscn"

# === Onready ===
@onready var title_label: Label = $Center/VBox/TitleLabel
@onready var body_label: Label = $Center/VBox/BodyLabel
@onready var retry_button: Button = $Center/VBox/RetryButton
@onready var quit_button: Button = $Center/VBox/QuitButton


# === Lifecycle Methods ===
func _ready() -> void:
	title_label.text = title_text
	body_label.text = _build_body_text()
	retry_button.pressed.connect(_on_retry_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


# === Private Methods ===
func _on_retry_pressed() -> void:
	GameManager.clear_finished_run_context()
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")


func _on_quit_pressed() -> void:
	GameManager.clear_finished_run_context()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _build_body_text() -> String:
	var summary: Dictionary = GameManager.last_run_summary
	if summary.is_empty():
		summary = _build_fallback_summary()
	var character_name: String = str(summary.get("name", "Your character")).strip_edges()
	if character_name.is_empty():
		character_name = "Your character"
	var character_class: StringName = StringName(str(summary.get("class", "")))
	var class_label: String = GameManager.get_character_class_label(character_class)
	var outcome_text: String = "Victory" if bool(summary.get("victory", false)) else "Defeat"
	var debug_text: String = "Yes" if bool(summary.get("archived_debug", false)) else "No"
	var lines: PackedStringArray = []
	if not body_text.strip_edges().is_empty():
		lines.append(body_text.strip_edges())
	lines.append("Outcome: %s" % outcome_text)
	lines.append("Character: %s the %s" % [character_name, class_label])
	lines.append(
		(
			"Reached floor %d at level %d."
			% [int(summary.get("floor", 1)), int(summary.get("level", 1))]
		)
	)
	lines.append("Version: %s" % str(summary.get("version", GameManager.GAME_VERSION)))
	lines.append("Debug run: %s" % debug_text)
	var output: String = ""
	for line: String in lines:
		if not output.is_empty():
			output += "\n\n"
		output += line
	return output


func _build_fallback_summary() -> Dictionary:
	var character_name: String = GameManager.pending_character_name
	if character_name.is_empty():
		character_name = "Your character"
	return {
		"name": character_name,
		"floor": GameManager.current_floor,
		"level": 1,
		"victory": title_text.to_lower().contains("conquered"),
		"class": String(GameManager.pending_character_class),
		"version": GameManager.GAME_VERSION,
		"archived_debug": GameManager.pending_debug_loadout,
	}
