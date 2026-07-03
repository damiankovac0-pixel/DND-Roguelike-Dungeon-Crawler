## Displays player stats, equipment, and derived combat values.
class_name CharacterSheet
extends PanelContainer

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
	var stats: Node = player.stats_component
	var inventory: Node = player.inventory_component
	var weapon_name: String = "Unarmed"
	var armor_name: String = "Clothes"
	var accessory_1_name: String = ""
	var accessory_2_name: String = ""
	if inventory.equipped_weapon != null:
		weapon_name = inventory.equipped_weapon.display_name
	if inventory.equipped_armor != null:
		armor_name = inventory.equipped_armor.display_name
	if inventory.equipped_accessory_1 != null:
		accessory_1_name = inventory.equipped_accessory_1.display_name
	if inventory.equipped_accessory_2 != null:
		accessory_2_name = inventory.equipped_accessory_2.display_name

	var lines: Array[String] = [
		"[font_size=22][color=#f2f2f2]%s[/color][/font_size]" % player.display_name,
		"[color=#9bbcff]CHARACTER SHEET[/color]  [color=#7d788f]Esc close[/color]",
		"",
		"Class    %s" % GameManager.get_character_class_label(),
		"[color=#7d788f]%s[/color]" % GameManager.get_character_class_description(),
		"[color=#7d788f]Q abilities: Lv1/Lv6/Lv12.  Passives: Lv5/10/15/20.[/color]",
		"",
		"[color=#f1c75b]COMBAT[/color]",
		"AC              %d" % stats.get_armor_class(),
		"Melee accuracy %+d" % stats.get_attack_bonus(),
		"Melee damage   d%d%+d" % [stats.get_damage_sides(), stats.get_damage_bonus()],
		"HP       %d / %d" % [stats.current_hp, stats.max_hp],
		"Level    %s" % stats.get_level_bbcode(),
		"XP       %d / %d" % [stats.xp, stats.xp_for_next_level()],
		"Gold     %d" % stats.gold,
		"",
		"[color=#8fb3ff]EQUIPMENT[/color]",
		"Weapon   %s" % weapon_name,
		"Armor    %s" % armor_name,
	]
	if accessory_1_name != "" or accessory_2_name != "":
		if accessory_1_name != "":
			lines.append("Acc. 1   %s" % accessory_1_name)
		if accessory_2_name != "":
			lines.append("Acc. 2   %s" % accessory_2_name)
	else:
		lines.append("Acc.     (empty)")
	var class_bonus_line: String = _get_class_damage_bonus_line(inventory)
	if not class_bonus_line.is_empty():
		lines.append(class_bonus_line)
	var set_bonus_lines: Array[String] = _get_active_set_bonus_lines(inventory)
	if not set_bonus_lines.is_empty():
		lines.append_array(set_bonus_lines)
	lines.append("")
	lines.append("[color=#d899ff]ABILITIES[/color]")
	lines.append_array(_format_ability_lines(stats))
	output.text = "\n".join(lines)


# === Private Methods ===
func _format_ability_lines(stats: Node) -> Array[String]:
	var lines: Array[String] = []
	var ability_data: Array[Dictionary] = stats.get_ability_effects()
	for ability: Dictionary in ability_data:
		var mod_str: String = "%+d" % ability["modifier"]
		var mod_color: String = "#7bd88f" if ability["modifier"] >= 0 else "#f07d67"
		lines.append(
			(
				"[color=#d8d6e0]%s[/color]  %2d  [color=%s](%s)[/color]"
				% [ability["name"], ability["value"], mod_color, mod_str]
			)
		)
		lines.append("  [color=#aaa6b8]%s[/color]" % ability["effects"])
		lines.append("  [color=#7d788f]%s[/color]" % ability["flavor"])
	return lines


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


func _get_class_damage_bonus_line(inventory: Node) -> String:
	var class_bonus_parts: Array[String] = []
	for item: Resource in inventory.get_equipped_items():
		if item.class_damage_percent_bonus != 0:
			var dmg_type: String = (
				String(item.class_damage_type) if item.class_damage_type != &"" else "all"
			)
			class_bonus_parts.append(
				"%s: %+d%% %s" % [item.display_name, item.class_damage_percent_bonus, dmg_type]
			)
	if class_bonus_parts.is_empty():
		return ""
	var prefix: String = "[color=#aaa6b8]Class dmg bonus[/color] "
	return prefix + "  ".join(class_bonus_parts)


func _get_active_set_bonus_lines(inventory: Node) -> Array[String]:
	var lines: Array[String] = []
	if not inventory.has_method("_get_active_set_bonuses"):
		return lines
	for data: Dictionary in inventory._get_active_set_bonuses():
		var parts: Array[String] = []
		if int(data["damage_resist_percent"]) > 0:
			parts.append("-%d%% incoming damage" % int(data["damage_resist_percent"]))
		if int(data["proc_chance_percent"]) > 0 and int(data["proc_heal_percent"]) > 0:
			parts.append(
				(
					"%d%% after-damage heal %d%% HP"
					% [int(data["proc_chance_percent"]), int(data["proc_heal_percent"])]
				)
			)
		if not parts.is_empty():
			lines.append(
				"[color=#aaa6b8]Set[/color] %s: %s" % [data["display_name"], ", ".join(parts)]
			)
	return lines
