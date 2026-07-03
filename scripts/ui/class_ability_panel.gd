## Class ability selection overlay for Fighter, Ranger, and Wizard.
## Player selects from available class abilities and activates the chosen one.
class_name ClassAbilityPanel
extends PanelContainer

signal close_requested
signal ability_requested(ability_id: StringName)

# === Private Variables ===
var _abilities: Array[Dictionary] = []
var _selected_index: int = 0

# === Onready ===
@onready var output: RichTextLabel = $Margin/VBox/Output


# === Lifecycle Methods ===
func _ready() -> void:
	output.bbcode_enabled = true


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_escape_key(event):
		close_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
		_select_previous()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
		_select_next()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_accept"):
		_request_selected_ability()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"class_ability"):
		_request_selected_ability()
		get_viewport().set_input_as_handled()


# === Public Methods ===
func refresh(abilities: Array[Dictionary]) -> void:
	_abilities = abilities
	if _abilities.is_empty():
		_selected_index = 0
	else:
		_selected_index = clampi(_selected_index, 0, _abilities.size() - 1)
	_render()


# === Private Methods ===
func _render() -> void:
	var lines: Array[String] = [
		"[font_size=24][color=#d899ff]CLASS ABILITY[/color][/font_size]",
		"[color=#8a86a0]Up/Down select   Enter/Q activate   Esc close[/color]",
		"",
	]
	if _abilities.is_empty():
		lines.append("[color=#c8c4d8]No class abilities available.[/color]")
		output.text = "\n".join(lines)
		return
	for list_index: int in range(_abilities.size()):
		var ability: Dictionary = _abilities[list_index]
		var marker: String = ">" if list_index == _selected_index else " "
		var usable: bool = _is_ability_usable(ability)
		var name_color: String = "#777788" if not usable else "#f2f2f2"
		var name: String = ability.get("name", "Unknown")
		var first_parts: Array[String] = [marker]
		first_parts.append("[color=%s]%s[/color]" % [name_color, name])
		var unlock_level: int = ability.get("unlock_level", 0)
		if unlock_level > 0 and not usable:
			first_parts.append("[color=#cc6666][Lv%d][/color]" % unlock_level)
		var charges_max: int = ability.get("charges_max", 0)
		if charges_max > 0:
			var charges_current: int = ability.get("charges_current", 0)
			first_parts.append("[color=#aaa6b8]%d/%d[/color]" % [charges_current, charges_max])
		if ability.get("active", false):
			first_parts.append("[color=#5bf0a4][Active][/color]")
		lines.append("  ".join(first_parts))
		var disabled_reason: String = ability.get("disabled_reason", "")
		if not disabled_reason.is_empty():
			lines.append("   [color=#cc6666]%s[/color]" % disabled_reason)
		elif not usable:
			lines.append("   [color=#cc6666]No charges remaining.[/color]")
		else:
			lines.append("   [color=#8a86a0]%s[/color]" % ability.get("summary", ""))
	lines.append("")
	lines.append("[color=#3f3a4c]──────────────────────────────────[/color]")
	lines.append_array(_selected_details())
	output.text = "\n".join(lines)


func _selected_details() -> Array[String]:
	if _abilities.is_empty():
		return []
	var ability: Dictionary = _abilities[_selected_index]
	var result: Array[String] = []
	var name: String = ability.get("name", "Unknown")
	var unlock_level: int = ability.get("unlock_level", 0)
	if unlock_level > 0:
		result.append(
			"[color=#ddd8e8]%s[/color]  [color=#cc6666](Lv%d)[/color]" % [name, unlock_level]
		)
	else:
		result.append("[color=#ddd8e8]%s[/color]" % name)
	result.append(
		(
			"Charges: [color=#f1c75b]%d/%d[/color]"
			% [ability.get("charges_current", 0), ability.get("charges_max", 0)]
		)
	)
	if ability.get("active", false):
		result.append("[color=#5bf0a4]Active[/color]")
	var disabled_reason: String = ability.get("disabled_reason", "")
	if not disabled_reason.is_empty():
		result.append("[color=#cc6666]%s[/color]" % disabled_reason)
	elif not _is_ability_usable(ability):
		result.append("[color=#cc6666]No charges — cannot activate.[/color]")
	var details: String = ability.get("details", "")
	if not details.is_empty():
		result.append("[color=#c8c4d8]%s[/color]" % details)
	return result


func _select_previous() -> void:
	if _abilities.is_empty():
		return
	_selected_index = wrapi(_selected_index - 1, 0, _abilities.size())
	_render()


func _select_next() -> void:
	if _abilities.is_empty():
		return
	_selected_index = wrapi(_selected_index + 1, 0, _abilities.size())
	_render()


func _request_selected_ability() -> void:
	if _abilities.is_empty():
		return
	var ability: Dictionary = _abilities[_selected_index]
	if not _is_ability_usable(ability):
		_render()
		return
	ability_requested.emit(ability.get("ability_id", &""))


func _is_ability_usable(ability: Dictionary) -> bool:
	var enabled: bool = ability.get("enabled", true)
	var charges: int = ability.get("charges_current", 0)
	return enabled and charges > 0


func _is_escape_key(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE)
	)
