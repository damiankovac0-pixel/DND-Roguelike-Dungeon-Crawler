## Landing screen with start, library, and quit buttons.
## V16 keeps the title fade but removes looping button-scale motion.
class_name MainMenu
extends Control

# === Constants ===
const ENTRANCE_DURATION: float = 0.5
const ENTRANCE_STAGGER: float = 0.12

# === Onready ===
@onready var start_button: Button = $Center/VBox/StartButton
@onready var library_button: Button = $Center/VBox/LibraryButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle_label: Label = $Center/VBox/Subtitle
@onready var background: AsciiBackdrop = $Background


# === Lifecycle Methods ===
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	library_button.pressed.connect(_on_library_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	_apply_motion_preferences()
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and is_instance_valid(quit_button):
		quit_button.grab_focus()
		get_viewport().set_input_as_handled()


# === Private Methods ===
func _apply_motion_preferences() -> void:
	var reduced_motion: bool = SensoryFeedback.is_reduced_vfx_preferred()
	background.motion_enabled = not reduced_motion
	if reduced_motion:
		_show_entrance_immediately()
	else:
		_play_entrance()


func _show_entrance_immediately() -> void:
	var entrance_nodes: Array[Control] = [
		title_label, subtitle_label, start_button, library_button, quit_button
	]
	for node: Control in entrance_nodes:
		node.modulate = Color.WHITE


func _play_entrance() -> void:
	## Short staggered fade: enough ceremony for the title screen, no long wait.
	var entrance_nodes: Array[Control] = [
		title_label, subtitle_label, start_button, library_button, quit_button
	]
	for index: int in range(entrance_nodes.size()):
		var node: Control = entrance_nodes[index]
		node.modulate = Color(1, 1, 1, 0)
		var tween: Tween = create_tween()
		tween.tween_interval(float(index) * ENTRANCE_STAGGER)
		(
			tween
			. tween_property(node, "modulate", Color.WHITE, ENTRANCE_DURATION)
			. set_ease(Tween.EASE_OUT)
			. set_trans(Tween.TRANS_CUBIC)
		)


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
