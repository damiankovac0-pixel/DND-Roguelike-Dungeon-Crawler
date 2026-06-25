class_name MainMenu
extends Control

# === Onready ===
@onready var start_button: Button = $Center/VBox/StartButton
@onready var library_button: Button = $Center/VBox/LibraryButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var history_output: RichTextLabel = $HistoryPanel/HistoryOutput


# === Lifecycle Methods ===
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	library_button.pressed.connect(_on_library_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	history_output.bbcode_enabled = true
	_refresh_history()
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


func _refresh_history() -> void:
	var lines: Array[String] = GameManager.get_history_lines()
	var history_text: String = (
		"[color=#555566]-- CHARACTER HISTORY --[/color]"
		+ "\n\n[color=#777777]No previous characters.[/color]"
	)
	if not lines.is_empty():
		history_text = "[color=#555566]-- CHARACTER HISTORY --[/color]\n\n%s" % "\n".join(lines)
	history_output.clear()
	history_output.parse_bbcode(history_text)
