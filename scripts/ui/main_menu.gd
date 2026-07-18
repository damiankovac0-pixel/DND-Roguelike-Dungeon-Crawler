## Landing screen with an unlock-aware difficulty choice before character creation.
## Preserves the short title entrance while the modal owns input and focus.
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
@onready var difficulty_modal: Control = $DifficultyModal
@onready
var normal_button: Button = $DifficultyModal/SafeMargin/Center/Panel/Margin/VBox/NormalButton
@onready var hard_button: Button = $DifficultyModal/SafeMargin/Center/Panel/Margin/VBox/HardButton
@onready var difficulty_status_label: Label = get_node(
	"DifficultyModal/SafeMargin/Center/Panel/Margin/VBox/StatusLabel"
)
@onready
var difficulty_back_button: Button = $DifficultyModal/SafeMargin/Center/Panel/Margin/VBox/BackButton


# === Lifecycle Methods ===
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	library_button.pressed.connect(_on_library_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	normal_button.pressed.connect(_on_normal_pressed)
	hard_button.pressed.connect(_on_hard_pressed)
	difficulty_back_button.pressed.connect(_close_difficulty_modal)
	GameManager.set_pending_difficulty(GameManager.pending_difficulty)
	_refresh_difficulty_modal()
	_apply_motion_preferences()
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_cancel_event(event):
		return
	if difficulty_modal.visible:
		_close_difficulty_modal()
	elif is_instance_valid(quit_button):
		quit_button.grab_focus()
	get_viewport().set_input_as_handled()


# === Private Methods ===
func _is_cancel_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE)
	)


func _open_difficulty_modal() -> void:
	_refresh_difficulty_modal()
	_set_main_controls_enabled(false)
	difficulty_modal.show()
	if not hard_button.disabled and GameManager.pending_difficulty == GameManager.DIFFICULTY_HARD:
		hard_button.grab_focus()
	else:
		normal_button.grab_focus()


func _close_difficulty_modal() -> void:
	difficulty_modal.hide()
	_set_main_controls_enabled(true)
	start_button.grab_focus()


func _refresh_difficulty_modal() -> void:
	var hard_unlocked: bool = GameManager.is_hard_mode_unlocked()
	hard_button.disabled = not hard_unlocked
	hard_button.focus_mode = Control.FOCUS_ALL if hard_unlocked else Control.FOCUS_NONE
	if hard_unlocked:
		difficulty_status_label.text = ("HARD UNLOCKED // A harsher descent awaits. Choose carefully.")
	else:
		difficulty_status_label.text = ("HARD LOCKED // Win a non-debug Normal run to unlock Hard.")
	_wire_difficulty_focus(hard_unlocked)


func _wire_difficulty_focus(hard_unlocked: bool) -> void:
	var next_after_normal: Button = hard_button if hard_unlocked else difficulty_back_button
	var previous_before_back: Button = hard_button if hard_unlocked else normal_button

	normal_button.focus_neighbor_top = normal_button.get_path_to(difficulty_back_button)
	normal_button.focus_neighbor_bottom = normal_button.get_path_to(next_after_normal)
	normal_button.focus_previous = normal_button.get_path_to(difficulty_back_button)
	normal_button.focus_next = normal_button.get_path_to(next_after_normal)

	hard_button.focus_neighbor_top = hard_button.get_path_to(normal_button)
	hard_button.focus_neighbor_bottom = hard_button.get_path_to(difficulty_back_button)
	hard_button.focus_previous = hard_button.get_path_to(normal_button)
	hard_button.focus_next = hard_button.get_path_to(difficulty_back_button)

	difficulty_back_button.focus_neighbor_top = difficulty_back_button.get_path_to(
		previous_before_back
	)
	difficulty_back_button.focus_neighbor_bottom = difficulty_back_button.get_path_to(normal_button)
	difficulty_back_button.focus_previous = difficulty_back_button.get_path_to(previous_before_back)
	difficulty_back_button.focus_next = difficulty_back_button.get_path_to(normal_button)


func _set_main_controls_enabled(enabled: bool) -> void:
	start_button.disabled = not enabled
	library_button.disabled = not enabled
	quit_button.disabled = not enabled


func _navigate_to_character_creation() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")


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
	_open_difficulty_modal()


func _on_normal_pressed() -> void:
	GameManager.set_pending_difficulty(GameManager.DIFFICULTY_NORMAL)
	_navigate_to_character_creation()


func _on_hard_pressed() -> void:
	if not GameManager.is_hard_mode_unlocked():
		_refresh_difficulty_modal()
		normal_button.grab_focus()
		return
	GameManager.set_pending_difficulty(GameManager.DIFFICULTY_HARD)
	_navigate_to_character_creation()


func _on_library_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/library.tscn")


func _on_quit_pressed() -> void:
	if OS.has_feature("web") and Engine.has_singleton(&"JavaScriptBridge"):
		var bridge: Object = Engine.get_singleton(&"JavaScriptBridge")
		bridge.call("eval", "window.close();", true)
		return
	get_tree().quit()
