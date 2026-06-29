class_name MainMenu
extends Control

# === Onready ===
@onready var start_button: Button = $Center/VBox/StartButton
@onready var library_button: Button = $Center/VBox/LibraryButton
@onready var quit_button: Button = $Center/VBox/QuitButton


# === Lifecycle Methods ===
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	library_button.pressed.connect(_on_library_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()


# === Private Methods ===
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")


func _on_library_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/library.tscn")


func _on_quit_pressed() -> void:
	if OS.has_feature("web") and Engine.has_singleton(&"JavaScriptBridge"):
		var bridge: Object = Engine.get_singleton(&"JavaScriptBridge")
		bridge.call("eval", "window.close();", true)
		return
	get_tree().quit()
