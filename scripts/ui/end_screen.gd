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
	var character_name: String = GameManager.pending_character_name
	if character_name.is_empty():
		character_name = "Your character"
	body_label.text = (
		"%s\n\n%s\nReached floor %d." % [character_name, body_text, GameManager.current_floor]
	)
	retry_button.pressed.connect(_on_retry_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


# === Private Methods ===
func _on_retry_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")


func _on_quit_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
