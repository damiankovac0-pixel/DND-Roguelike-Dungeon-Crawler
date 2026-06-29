class_name LevelUpPanel
extends PanelContainer

signal stat_selected(stat_key: String)

# === Constants ===
const STAT_KEYS: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]

# === Private Variables ===
var _player: Node
var _stat_buttons: Array[Button] = []

# === Onready ===
@onready var output: RichTextLabel = $Margin/VBox/Output
@onready var buttons: VBoxContainer = $Margin/VBox/Buttons


# === Lifecycle Methods ===
func _ready() -> void:
	output.bbcode_enabled = true
	_build_buttons()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var key_index: int = key_event.keycode - KEY_1
	if key_index >= 0 and key_index < STAT_KEYS.size():
		_request_stat(STAT_KEYS[key_index])
		get_viewport().set_input_as_handled()
		return
	if _is_previous_key(key_event):
		_focus_relative(-1)
		get_viewport().set_input_as_handled()
	elif _is_next_key(key_event):
		_focus_relative(1)
		get_viewport().set_input_as_handled()
	elif _is_accept_key(key_event):
		_request_focused_stat()
		get_viewport().set_input_as_handled()


# === Public Methods ===
func refresh(player: Node) -> void:
	_player = player
	_render()
	_grab_first_enabled_button()


# === Private Methods ===
func _build_buttons() -> void:
	if not _stat_buttons.is_empty():
		return
	for stat_key: String in STAT_KEYS:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(420, 34)
		button.pressed.connect(_request_stat.bind(stat_key))
		buttons.add_child(button)
		_stat_buttons.append(button)


func _render() -> void:
	if _player == null:
		return
	var stats: StatsComponent = _player.stats_component
	var lines: Array[String] = [
		"[font_size=24][color=#d899ff]LEVEL UP[/color][/font_size]",
		"[color=#8a86a0]Choose one ability score to increase by +1. Scores cannot exceed 20.[/color]",
		"[color=#8a86a0]Press 1-6, W/S or A/D + Enter, or click a stat. Choices left: %d[/color]" % stats.pending_stat_increases,
		"",
	]
	var ability_data: Array[Dictionary] = stats.get_ability_effects()
	for index: int in range(ability_data.size()):
		var ability: Dictionary = ability_data[index]
		var value: int = ability["value"]
		var modifier: int = ability["modifier"]
		var key: String = ability["key"]
		var stat_name: String = ability["name"]
		var can_raise: bool = stats.can_increase_ability(key)
		var status: String = "MAX" if value >= StatsComponent.MAX_ABILITY_SCORE else "+1"
		var color: String = "#777788" if not can_raise else "#f2f2f2"
		lines.append(
			"%d. [color=%s]%s %2d (%+d)[/color]  [color=#f1c75b]%s[/color]"
			% [index + 1, color, stat_name, value, modifier, status]
		)
		lines.append("   [color=#aaa6b8]%s[/color]" % ability["effects"])
		var button: Button = _stat_buttons[index]
		button.text = "%d  %s %d -> %d" % [index + 1, stat_name, value, min(value + 1, StatsComponent.MAX_ABILITY_SCORE)]
		button.disabled = not can_raise
	output.text = "\n".join(lines)


func _request_stat(stat_key: String) -> void:
	if _player == null:
		return
	var stats: StatsComponent = _player.stats_component
	if not stats.can_increase_ability(stat_key):
		return
	stat_selected.emit(stat_key)

func _request_focused_stat() -> void:
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	for index: int in range(_stat_buttons.size()):
		if _stat_buttons[index] == focus_owner:
			_request_stat(STAT_KEYS[index])
			return
	_grab_first_enabled_button()



func _focus_relative(step: int) -> void:
	if _stat_buttons.is_empty():
		return
	var current_index: int = 0
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	for index: int in range(_stat_buttons.size()):
		if _stat_buttons[index] == focus_owner:
			current_index = index
			break
	for offset: int in range(1, _stat_buttons.size() + 1):
		var candidate_index: int = wrapi(
			current_index + step * offset, 0, _stat_buttons.size()
		)
		var button: Button = _stat_buttons[candidate_index]
		if not button.disabled:
			button.grab_focus()
			return


func _is_previous_key(key_event: InputEventKey) -> bool:
	return _matches_key(key_event, KEY_W) or _matches_key(key_event, KEY_A)


func _is_next_key(key_event: InputEventKey) -> bool:
	return _matches_key(key_event, KEY_S) or _matches_key(key_event, KEY_D)

func _is_accept_key(key_event: InputEventKey) -> bool:
	return (
		_matches_key(key_event, KEY_ENTER)
		or _matches_key(key_event, KEY_KP_ENTER)
		or _matches_key(key_event, KEY_SPACE)
	)




func _matches_key(key_event: InputEventKey, keycode: Key) -> bool:
	return key_event.keycode == keycode or key_event.physical_keycode == keycode



func _grab_first_enabled_button() -> void:
	for button: Button in _stat_buttons:
		if not button.disabled:
			button.grab_focus()
			return
