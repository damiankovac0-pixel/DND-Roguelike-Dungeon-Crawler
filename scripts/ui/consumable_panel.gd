class_name ConsumablePanel
extends PanelContainer

signal close_requested
signal use_requested(inventory_index: int)

# === Constants ===
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

# === Private Variables ===
var _player: Node
var _selected_index: int = 0
var _consumable_indices: Array[int] = []

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
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"use_potion"):
		_request_use_selected()
		get_viewport().set_input_as_handled()


# === Public Methods ===
func refresh(player: Node) -> void:
	_player = player
	_rebuild_consumable_indices()
	if _consumable_indices.is_empty():
		_selected_index = 0
	else:
		_selected_index = clampi(_selected_index, 0, _consumable_indices.size() - 1)
	_render()


func has_consumables() -> bool:
	return not _consumable_indices.is_empty()


# === Private Methods ===
func _rebuild_consumable_indices() -> void:
	_consumable_indices.clear()
	if _player == null:
		return
	var inventory: Node = _player.inventory_component
	for index: int in range(inventory.items.size()):
		var item: Resource = inventory.items[index]
		if item.kind == ItemDataScript.ItemKind.CONSUMABLE:
			_consumable_indices.append(index)


func _render() -> void:
	var lines: Array[String] = [
		"[font_size=24][color=#9bbcff]CONSUMABLES[/color][/font_size]",
		"[color=#8a86a0]Up/Down select   Enter/H use   Esc close[/color]",
		"",
	]
	if _player == null or _consumable_indices.is_empty():
		lines.append("[color=#c8c4d8]No potions or scrolls in your pack.[/color]")
		output.text = "\n".join(lines)
		return
	var inventory: Node = _player.inventory_component
	for list_index: int in range(_consumable_indices.size()):
		var item: Resource = inventory.items[_consumable_indices[list_index]]
		var marker: String = ">" if list_index == _selected_index else " "
		lines.append("%s %s  [color=#777788]%s[/color]" % [marker, _colored_item_name(item), _effect_summary(item)])
	lines.append("")
	lines.append("[color=#3f3a4c]──────────────────────────────────[/color]")
	lines.append_array(_selected_details())
	output.text = "\n".join(lines)


func _selected_details() -> Array[String]:
	if _player == null or _consumable_indices.is_empty():
		return []
	var inventory: Node = _player.inventory_component
	var item: Resource = inventory.items[_consumable_indices[_selected_index]]
	return [
		_colored_item_name(item),
		"%s Consumable" % item.get_rarity_name(),
		item.description,
		_effect_detail(item),
	]


func _select_previous() -> void:
	if _consumable_indices.is_empty():
		return
	_selected_index = wrapi(_selected_index - 1, 0, _consumable_indices.size())
	_render()


func _select_next() -> void:
	if _consumable_indices.is_empty():
		return
	_selected_index = wrapi(_selected_index + 1, 0, _consumable_indices.size())
	_render()


func _request_use_selected() -> void:
	if _consumable_indices.is_empty():
		return
	use_requested.emit(_consumable_indices[_selected_index])


func _effect_summary(item: Resource) -> String:
	match item.use_effect:
		ItemDataScript.ItemUse.HEAL:
			return "+%d HP +INT" % item.healing_amount
		ItemDataScript.ItemUse.REGEN:
			return "regen %d x %d" % [item.healing_amount, item.effect_duration]
		ItemDataScript.ItemUse.SHIELD:
			return "+%d AC" % item.armor_bonus
		ItemDataScript.ItemUse.HASTE:
			return "haste %d" % item.effect_duration
		ItemDataScript.ItemUse.RANGED_ATTACK:
			return "target %dd%d +WIS" % [item.damage_dice, item.damage_sides]
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			return "force %dd%d +WIS" % [item.damage_dice, item.damage_sides]
		ItemDataScript.ItemUse.SLEEP:
			return "sleep r%d" % item.target_radius
		ItemDataScript.ItemUse.AREA_DAMAGE:
			return "area r%d %dd%d +WIS" % [item.target_radius, item.damage_dice, item.damage_sides]
	return "unknown"


func _effect_detail(item: Resource) -> String:
	match item.use_effect:
		ItemDataScript.ItemUse.HEAL:
			return "Use immediately: restores %d HP plus INT modifier (min +0). Not consumed at full HP." % item.healing_amount
		ItemDataScript.ItemUse.REGEN:
			return "Use immediately: restores %d HP for %d turns." % [item.healing_amount, item.effect_duration]
		ItemDataScript.ItemUse.SHIELD:
			return "Use immediately: %+d AC for %d turns." % [item.armor_bonus, item.effect_duration]
		ItemDataScript.ItemUse.HASTE:
			return "Use immediately: skips %d enemy phase." % item.effect_duration
		ItemDataScript.ItemUse.RANGED_ATTACK:
			return "Targets one creature in range %d. Damage adds WIS modifier (min +0). Canceling does not consume it." % item.range
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			return "Targets one creature in range %d and cannot miss. Damage adds WIS modifier (min +0)." % item.range
		ItemDataScript.ItemUse.SLEEP:
			return "Targets a cell in range %d; sleeps enemies in radius %d." % [item.range, item.target_radius]
		ItemDataScript.ItemUse.AREA_DAMAGE:
			return "Targets a cell in range %d; damages enemies in radius %d and adds WIS modifier (min +0)." % [item.range, item.target_radius]
	return "No effect."


func _colored_item_name(item: Resource) -> String:
	return "[color=%s]%s[/color]" % [item.get_rarity_color(), item.display_name]


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
