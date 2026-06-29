class_name CharacterCreation
extends Control

# === Constants ===
const STAT_KEYS: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const STAT_LABELS: Array[String] = [
	"Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"
]
const STAT_DESCRIPTIONS: Array[String] = [
	"STR: melee attack and melee damage.",
	"DEX: armor class and ranged attack accuracy.",
	"CON: max HP now and HP gained every level.",
	"INT: health potions restore bonus HP.",
	"WIS: magic scrolls deal bonus damage.",
	"CHA: shops sell cheaper and buy for more.",
]
# === Private Variables ===
var _rolls: Array[int] = []
var _selectors: Array[OptionButton] = []
var _assignments: Array[int] = []
var _is_swapping: bool = false

# === Onready ===
@onready var name_input: LineEdit = $Center/Panel/Margin/VBox/NameInput
@onready var assignments: VBoxContainer = $Center/Panel/Margin/VBox/Assignments
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var reroll_button: Button = $Center/Panel/Margin/VBox/Buttons/RerollButton
@onready var begin_button: Button = $Center/Panel/Margin/VBox/Buttons/BeginButton
@onready var back_button: Button = $Center/Panel/Margin/VBox/Buttons/BackButton
@onready var version_label: Label = $VersionLabel


# === Lifecycle Methods ===
func _ready() -> void:
	reroll_button.pressed.connect(_roll_abilities)
	begin_button.pressed.connect(_begin_run)
	back_button.pressed.connect(_go_back)
	name_input.text_changed.connect(_on_selection_changed)
	version_label.text = GameManager.get_version_label()
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


func _is_backspace_key(key_event: InputEventKey) -> bool:
	return (
		key_event.keycode == KEY_BACKSPACE
		or key_event.physical_keycode == KEY_BACKSPACE
		or key_event.key_label == KEY_BACKSPACE
		or key_event.unicode == 8
	)


# === Private Methods ===
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
	GameManager.prepare_character(name_input.text, ability_scores)
	get_tree().change_scene_to_file("res://scenes/game.tscn")



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
