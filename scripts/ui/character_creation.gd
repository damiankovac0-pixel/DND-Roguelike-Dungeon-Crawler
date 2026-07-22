## Rolls ability scores and prepares a character before entering the dungeon.
class_name CharacterCreation
extends Control

# === Constants ===
const STAT_KEYS: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const STAT_LABELS: Array[String] = [
	"Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"
]
const STAT_DESCRIPTIONS: Array[String] = [
	"STR: melee accuracy and melee damage.",
	"DEX: armor class and ranged weapon accuracy.",
	"CON: max HP now and HP gained every level.",
	"INT: stronger potions; sight radius +1 at 15 and +2 at 20.",
	"WIS: scroll accuracy and stronger scroll damage.",
	"CHA: shops sell cheaper, buy for more, and feature one golden deal at 15+.",
]
const CLASS_IDS: Array[StringName] = [&"fighter", &"ranger", &"wizard"]
const NORMAL_DIFFICULTY_COLOR: Color = Color(0.6, 0.843137, 0.898039, 1.0)
const HARD_DIFFICULTY_COLOR: Color = Color(1.0, 0.33, 0.47, 1.0)
const NIGHTMARE_DIFFICULTY_COLOR: Color = Color(0.78, 0.48, 1.0, 1.0)
# === Private Variables ===
var _rolls: Array[int] = []
var _selectors: Array[OptionButton] = []
var _assignments: Array[int] = []
var _is_swapping: bool = false
var _selected_class_index: int = 0

# === Onready ===
@onready var name_input: LineEdit = $Center/Panel/Margin/VBox/NameInput
@onready var class_selector: OptionButton = $Center/Panel/Margin/VBox/ClassRow/ClassSelector
@onready var class_description: Label = $Center/Panel/Margin/VBox/ClassRow/ClassDescription
@onready var difficulty_label: Label = $Center/Panel/Margin/VBox/DifficultyLabel
@onready var assignments: VBoxContainer = $Center/Panel/Margin/VBox/Assignments
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var reroll_button: Button = $Center/Panel/Margin/VBox/Buttons/RerollButton
@onready var begin_button: Button = $Center/Panel/Margin/VBox/Buttons/BeginButton
@onready var back_button: Button = $Center/Panel/Margin/VBox/Buttons/BackButton
@onready var background: AsciiBackdrop = $Background


# === Lifecycle Methods ===
func _ready() -> void:
	_apply_motion_preferences()
	_update_difficulty_confirmation()
	reroll_button.pressed.connect(_roll_abilities)
	begin_button.pressed.connect(_begin_run)
	back_button.pressed.connect(_go_back)
	name_input.text_changed.connect(_on_selection_changed)
	class_selector.item_selected.connect(_on_class_selected)
	_populate_class_selector()
	_build_assignment_rows()
	_roll_abilities()
	name_input.call_deferred("grab_focus")


func _input(event: InputEvent) -> void:
	if OS.get_name() != "Web" and not OS.has_feature("web"):
		return
	if not name_input.has_focus():
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if not _is_backspace_key(key_event):
		return
	if name_input.has_selection():
		var selection_start: int = name_input.get_selection_from_column()
		name_input.delete_text(selection_start, name_input.get_selection_to_column())
		name_input.caret_column = selection_start
	elif name_input.caret_column > 0:
		var delete_from: int = name_input.caret_column - 1
		name_input.delete_text(delete_from, name_input.caret_column)
		name_input.caret_column = delete_from
	_update_validation()
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()


func _is_backspace_key(key_event: InputEventKey) -> bool:
	return (
		key_event.keycode == KEY_BACKSPACE
		or key_event.physical_keycode == KEY_BACKSPACE
		or key_event.key_label == KEY_BACKSPACE
		or key_event.unicode == 8
	)


# === Private Methods ===
func _apply_motion_preferences() -> void:
	background.motion_enabled = not SensoryFeedback.is_reduced_vfx_preferred()


func _update_difficulty_confirmation() -> void:
	var selected_difficulty: StringName = GameManager.pending_difficulty
	difficulty_label.text = (
		"Difficulty: %s" % GameManager.get_difficulty_label(selected_difficulty).to_upper()
	)
	var label_color: Color
	match selected_difficulty:
		GameManager.DIFFICULTY_HARD:
			label_color = HARD_DIFFICULTY_COLOR
		GameManager.DIFFICULTY_NIGHTMARE:
			label_color = NIGHTMARE_DIFFICULTY_COLOR
		_:
			label_color = NORMAL_DIFFICULTY_COLOR
	difficulty_label.add_theme_color_override(&"font_color", label_color)


func _build_assignment_rows() -> void:
	for index: int in range(STAT_KEYS.size()):
		var row: HBoxContainer = HBoxContainer.new()
		var label: Label = Label.new()
		label.custom_minimum_size = Vector2(150, 0)
		label.text = STAT_LABELS[index]
		var selector: OptionButton = OptionButton.new()
		selector.custom_minimum_size = Vector2(120, 0)
		selector.item_selected.connect(_on_roll_selected.bind(index))
		var description: Label = Label.new()
		description.custom_minimum_size = Vector2(460, 0)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.text = STAT_DESCRIPTIONS[index]
		row.add_child(label)
		row.add_child(selector)
		row.add_child(description)
		assignments.add_child(row)
		_selectors.append(selector)


func _populate_class_selector() -> void:
	class_selector.clear()
	for class_index: int in range(CLASS_IDS.size()):
		var class_id: StringName = CLASS_IDS[class_index]
		class_selector.add_item(GameManager.get_character_class_label(class_id), class_index)
	class_selector.select(_selected_class_index)
	_update_class_description()


func _selected_class_id() -> StringName:
	return CLASS_IDS[clamp(_selected_class_index, 0, CLASS_IDS.size() - 1)]


func _update_class_description() -> void:
	class_description.text = GameManager.get_character_class_description(_selected_class_id())


func _on_class_selected(selected_item_index: int) -> void:
	_selected_class_index = selected_item_index
	_update_class_description()


func _roll_abilities() -> void:
	_rolls.clear()
	_assignments.clear()
	for index: int in range(STAT_KEYS.size()):
		_rolls.append(Dice.roll_4d6_drop_lowest())
	for selector_index: int in range(_selectors.size()):
		var selector: OptionButton = _selectors[selector_index]
		selector.clear()
		for roll_index: int in range(_rolls.size()):
			selector.add_item("%d  (roll %d)" % [_rolls[roll_index], roll_index + 1], roll_index)
		selector.select(selector_index)
		_assignments.append(selector_index)
	_update_validation()


func _begin_run() -> void:
	if not _is_valid_assignment():
		return
	var ability_scores: Dictionary = {}
	for index: int in range(STAT_KEYS.size()):
		var roll_index: int = _selectors[index].get_selected_id()
		ability_scores[STAT_KEYS[index]] = _rolls[roll_index]
	GameManager.prepare_character(name_input.text, ability_scores, _selected_class_id())
	get_tree().change_scene_to_file("res://scenes/prologue.tscn")


func _go_back() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_selection_changed(_unused: String = "") -> void:
	_update_validation()


func _on_roll_selected(selected_item_index: int, selector_index: int) -> void:
	if _is_swapping:
		return
	var selected_roll: int = _selectors[selector_index].get_item_id(selected_item_index)
	var previous_roll: int = _assignments[selector_index]
	var other_selector_index: int = _assignments.find(selected_roll)

	_is_swapping = true
	_assignments[selector_index] = selected_roll
	if other_selector_index != -1 and other_selector_index != selector_index:
		_assignments[other_selector_index] = previous_roll
		_selectors[other_selector_index].select(previous_roll)
	_is_swapping = false
	_update_validation()


func _update_validation() -> void:
	var has_name: bool = not name_input.text.strip_edges().is_empty()
	begin_button.disabled = not has_name
	if not has_name:
		status_label.text = "Enter a name, brave soul. The dungeon waits."
	elif _has_good_stats():
		status_label.text = "The depths shudder. You are ready."
	else:
		status_label.text = "A capable adventurer. Luck favors the bold."


func _has_good_stats() -> bool:
	if _assignments.size() < 6:
		return false
	var total: int = 0
	for i: int in _assignments.size():
		if i < _rolls.size():
			total += _rolls[i]
	return total >= 80


func _is_valid_assignment() -> bool:
	return not name_input.text.strip_edges().is_empty()
