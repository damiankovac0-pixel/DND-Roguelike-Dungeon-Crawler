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
		"[color=#8db7ff]CHARACTER SHEET[/color]",
		"",
		"[color=#f1c75b]COMBAT[/color]",
		"AC       %d" % stats.get_armor_class(),
		"Attack   %+d" % stats.get_attack_bonus(),
		"Damage   d%d%+d" % [stats.get_damage_sides(), stats.get_damage_bonus()],
		"HP       %d / %d" % [stats.current_hp, stats.max_hp],
		"Level    %d" % stats.level,
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
		var line: String = (
			"[color=#c8c8d0]%s[/color]  %2d  [color=%s](%s)[/color]  [color=#9999aa]%s[/color]"
			% [ability["name"], ability["value"], mod_color, mod_str, ability["effects"]]
		)
		lines.append(line)
		lines.append("  [color=#666677]%s[/color]" % ability["flavor"])
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
