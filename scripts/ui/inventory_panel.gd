class_name InventoryPanel
extends PanelContainer

# === Constants ===
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

# === Private Variables ===
var _player: Node
var _selected_index: int = 0

# === Onready ===
@onready var output: RichTextLabel = $Output


# === Lifecycle Methods ===
func _ready() -> void:
	output.bbcode_enabled = true


func _input(event: InputEvent) -> void:
	if visible and _is_escape_key(event):
		visible = false
		get_viewport().set_input_as_handled()


# === Public Methods ===
func refresh(player: Node) -> void:
	_player = player
	var inventory: Node = player.inventory_component
	if inventory.items.is_empty():
		_selected_index = 0
	else:
		_selected_index = clampi(_selected_index, 0, inventory.items.size() - 1)

	var lines: Array[String] = [
		"[font_size=22][color=#9bbcff]INVENTORY[/color][/font_size]",
		"[color=#8a86a0]Up/Down select   Enter equip/unequip   H opens consumables   Esc close[/color]",
		"",
	]
	for index: int in range(inventory.items.size()):
		var item: Resource = inventory.items[index]
		var marker: String = ">" if index == _selected_index else " "
		var equipped_tag: String = (
			"  [color=#7bd88f][equipped][/color]" if inventory.is_equipped(item) else ""
		)
		lines.append("%s %s%s" % [marker, _colored_item_name(item), equipped_tag])
	if inventory.items.is_empty():
		lines.append("[color=#c8c4d8]Your pack is empty.[/color]")
		lines.append("[color=#7d788f]Find potions, scrolls, weapons, and armor in the dungeon.[/color]")
	lines.append("")
	lines.append("[color=#3f3a4c]──────────────────────────────────[/color]")
	lines.append_array(_get_selected_item_details())
	output.text = "\n".join(lines)


func select_previous() -> void:
	if _player == null or _player.inventory_component.items.is_empty():
		return
	_selected_index = wrapi(_selected_index - 1, 0, _player.inventory_component.items.size())
	refresh(_player)


func select_next() -> void:
	if _player == null or _player.inventory_component.items.is_empty():
		return
	_selected_index = wrapi(_selected_index + 1, 0, _player.inventory_component.items.size())
	refresh(_player)


func toggle_selected_equipment() -> String:
	if _player == null or _player.inventory_component.items.is_empty():
		return ""
	var inventory: Node = _player.inventory_component
	var item: Resource = inventory.items[_selected_index]
	if item.kind == ItemDataScript.ItemKind.CONSUMABLE:
		return "Press H to open the consumable menu."
	var equipped: bool = inventory.toggle_equipped(item)
	refresh(_player)
	return "%s %s." % ["Equipped" if equipped else "Unequipped", item.display_name]


func get_selected_item() -> Resource:
	if _player == null or _player.inventory_component.items.is_empty():
		return null
	return _player.inventory_component.items[_selected_index]


func has_selection() -> bool:
	return _player != null and not _player.inventory_component.items.is_empty()


# === Private Methods ===
func _get_selected_item_details() -> Array[String]:
	if _player == null or _player.inventory_component.items.is_empty():
		return ["[color=#8a86a0]Loot appears here after you pick it up. H opens potions and scrolls; ranged weapons use F.[/color]"]

	var inventory: Node = _player.inventory_component
	var stats: Node = _player.stats_component
	var item: Resource = inventory.items[_selected_index]
	var lines: Array[String] = [
		_colored_item_name(item),
		"%s %s" % [item.get_rarity_name(), item.get_kind_name()],
		"Value: %d gold  |  Shops buy for less." % item.get_price(),
		item.description,
		"",
	]
	match item.kind:
		ItemDataScript.ItemKind.WEAPON:
			var current_weapon: Resource = (
				inventory.get_equipped_ranged_weapon()
				if item.is_ranged_weapon
				else inventory.get_preferred_melee_weapon()
			)
			var current_attack: int = 0 if current_weapon == null else current_weapon.attack_bonus
			var current_damage_sides: int = (
				4 if current_weapon == null else current_weapon.damage_sides
			)
			var current_damage_bonus: int = (
				0 if current_weapon == null else current_weapon.damage_bonus
			)
			var weapon_role: String = "ranged" if item.is_ranged_weapon else "melee"
			lines.append(
				(
					"Weapon: d%d%+d damage, %+d attack"
					% [item.damage_sides, item.damage_bonus, item.attack_bonus]
				)
			)
			if item.is_ranged_weapon:
				lines.append("Range: %d" % item.range)
			lines.append(
				(
					"Current %s: d%d%+d damage, %+d attack"
					% [weapon_role, current_damage_sides, current_damage_bonus, current_attack]
				)
			)
			(
				lines
				. append(
					(
						"Change: damage die %+d, damage %+d, attack %+d"
						% [
							item.damage_sides - current_damage_sides,
							item.damage_bonus - current_damage_bonus,
							item.attack_bonus - current_attack,
						]
					)
				)
			)
		ItemDataScript.ItemKind.ARMOR:
			var current_armor: Resource = inventory.equipped_armor
			var current_armor_bonus: int = 0 if current_armor == null else current_armor.armor_bonus
			var current_ac: int = stats.get_armor_class()
			var preview_ac: int = current_ac - current_armor_bonus + item.armor_bonus
			lines.append("Armor: %+d AC" % item.armor_bonus)
			lines.append(
				(
					"Current AC: %d  With item: %d  Change: %+d"
					% [current_ac, preview_ac, preview_ac - current_ac]
				)
			)
		ItemDataScript.ItemKind.ACCESSORY:
			var current_accessory_1: Resource = inventory.equipped_accessory_1
			var current_accessory_2: Resource = inventory.equipped_accessory_2
			var accessory_list: Array[Resource] = []
			if current_accessory_1 != null:
				accessory_list.append(current_accessory_1)
			if current_accessory_2 != null:
				accessory_list.append(current_accessory_2)

			lines.append(
				(
					"Accessory: %+d attack, %+d damage, %+d AC"
					% [item.attack_bonus, item.damage_bonus, item.armor_bonus]
				)
			)
			if accessory_list.is_empty():
				lines.append("Current: no accessories equipped.")
				lines.append(
					(
						"Change: attack %+d, damage %+d, AC %+d"
						% [item.attack_bonus, item.damage_bonus, item.armor_bonus]
					)
				)
			else:
				lines.append("Equipped accessories:")
				for acc: Resource in accessory_list:
					lines.append(
						(
							"  %s: %+d atk, %+d dmg, %+d AC"
							% [
								acc.display_name,
								acc.attack_bonus,
								acc.damage_bonus,
								acc.armor_bonus
							]
						)
					)
				var total_attack: int = (
					(current_accessory_1.attack_bonus if current_accessory_1 != null else 0)
					+ (current_accessory_2.attack_bonus if current_accessory_2 != null else 0)
				)
				var total_damage: int = (
					(current_accessory_1.damage_bonus if current_accessory_1 != null else 0)
					+ (current_accessory_2.damage_bonus if current_accessory_2 != null else 0)
				)
				var total_ac: int = (
					(current_accessory_1.armor_bonus if current_accessory_1 != null else 0)
					+ (current_accessory_2.armor_bonus if current_accessory_2 != null else 0)
				)
				(
					lines
					. append(
						(
							"Change: attack %+d, damage %+d, AC %+d"
							% [
								item.attack_bonus - total_attack,
								item.damage_bonus - total_damage,
								item.armor_bonus - total_ac,
							]
						)
					)
				)
		ItemDataScript.ItemKind.CONSUMABLE:
			_append_consumable_details(lines, item)
			lines.append("Press H to open the consumable menu.")
	var special_line: String = _special_detail(item)
	if not special_line.is_empty():
		lines.append(special_line)
	return lines


func _append_consumable_details(lines: Array[String], item: Resource) -> void:
	match item.use_effect:
		ItemDataScript.ItemUse.HEAL:
			lines.append("Consumable: restores %d HP" % item.healing_amount)
		ItemDataScript.ItemUse.SHIELD:
			lines.append(
				"Consumable: %+d AC for %d turns" % [item.armor_bonus, item.effect_duration]
			)
		ItemDataScript.ItemUse.HASTE:
			lines.append("Consumable: skips %d enemy phase" % item.effect_duration)
		ItemDataScript.ItemUse.REGEN:
			lines.append(
				"Consumable: restores %d HP for %d turns" % [item.healing_amount, item.effect_duration]
			)
		ItemDataScript.ItemUse.RANGED_ATTACK:
			(
				lines
				. append(
					(
						"Targeted: range %d, damage %dd%d%+d"
						% [
							item.range,
							item.damage_dice,
							item.damage_sides,
							item.damage_bonus,
						]
					)
				)
			)
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			(
				lines
				. append(
					(
						"Targeted: range %d, force damage %dd%d%+d"
						% [
							item.range,
							item.damage_dice,
							item.damage_sides,
							item.damage_bonus,
						]
					)
				)
			)
		ItemDataScript.ItemUse.SLEEP:
			lines.append(
				(
					"Targeted: range %d, radius %d, sleep %d turns"
					% [item.range, item.target_radius, item.effect_duration]
				)
			)
		ItemDataScript.ItemUse.AREA_DAMAGE:
			lines.append(
				(
					"Targeted: range %d, radius %d, area damage %dd%d%+d"
					% [
						item.range,
						item.target_radius,
						item.damage_dice,
						item.damage_sides,
						item.damage_bonus,
					]
				)
			)
		_:
			lines.append("Consumable: no effect")


func _special_detail(item: Resource) -> String:
	match item.special_effect:
		ItemDataScript.ItemSpecial.KILL_REGEN_PERCENT:
			return "Special: restores %d%% max HP when you kill an enemy." % item.special_amount
		ItemDataScript.ItemSpecial.CURRENT_HP_DAMAGE_PERCENT:
			return "Special: ranged hits add %d%% of the target's current HP." % item.special_amount
		ItemDataScript.ItemSpecial.DASH_CHARGE:
			return "Special: every %d actions, your next clear move dashes two tiles." % item.special_cooldown
	return ""


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
