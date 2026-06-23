class_name LibraryMenu
extends Control

# === Constants ===
const ENEMY_DIR: String = "res://resources/enemies"
const ITEM_DIR: String = "res://resources/items"
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const ENEMY_NOTES: Dictionary = {
	"Rat": "Low HP, low AC, low damage. Early chip threat; dangerous only in numbers.",
	"Bat": "High AC and +4 to hit, but only 4 HP. Harder to hit than it is to kill.",
	"Goblin": "Baseline early melee enemy. No max floor, so it remains filler later.",
	"Kobold": "Better accuracy than a goblin, lower damage die. Punishes low AC.",
	"Skeleton": "Floor 2+ guard enemy. AC 13 and d6+2 make it a steady weapon check.",
	"Zombie": "Large HP pool, AC 9. Easy to hit; wastes turns if ignored.",
	"Orc": "Mid-depth bruiser. d8+3 damage makes failed armor checks expensive.",
	"Cultist": "Floor 4+ striker. +5 to hit and d8+2 damage in a lighter body.",
	"Wraith": "Floor 6+ elite. AC 15, +6 to hit, d10+3 damage.",
	"Troll": "Floor 8+ heavy. 36 HP, +7 to hit, d10+5 damage.",
}
const ITEM_TYPE_LORE: Dictionary = {
	ItemDataScript.ItemKind.CONSUMABLE:
	"Consumed with H. Some act instantly; targeted scrolls open targeting mode.",
	ItemDataScript.ItemKind.WEAPON:
	"Equipped weapon sets melee damage. Ranged weapons fire with F.",
	ItemDataScript.ItemKind.ARMOR: "Equipped armor adds its AC bonus.",
	ItemDataScript.ItemKind.ACCESSORY:
	"One accessory slot. Adds listed attack, damage, and/or AC bonuses.",
}

# === Onready ===
@onready var back_button: Button = $Margin/VBox/Header/BackButton
@onready var tabs: TabContainer = $Margin/VBox/Tabs
@onready var bestiary_text: RichTextLabel = $Margin/VBox/Tabs/Bestiary/BestiaryText
@onready var scribes_text: RichTextLabel = $Margin/VBox/Tabs/Scribes/ScribesText


# === Lifecycle Methods ===
func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	bestiary_text.bbcode_enabled = true
	scribes_text.bbcode_enabled = true
	bestiary_text.text = _build_bestiary_text()
	scribes_text.text = _build_scribes_text()
	back_button.grab_focus()


func _input(event: InputEvent) -> void:
	if _is_escape_key(event):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_left"):
		tabs.current_tab = wrapi(tabs.current_tab - 1, 0, tabs.get_tab_count())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"ui_right"):
		tabs.current_tab = wrapi(tabs.current_tab + 1, 0, tabs.get_tab_count())
		get_viewport().set_input_as_handled()


# === Private Methods ===
func _build_bestiary_text() -> String:
	var enemies: Array[Resource] = _load_resources_with_paths(ENEMY_PATHS)
	enemies.sort_custom(_sort_enemy)
	var lines: Array[String] = [
		"[font_size=24][color=#f1c75b]BESTIARY[/color][/font_size]",
		"",
		"Base monster data from enemy resources.",
		"Runtime depth scaling: +2 HP per floor after floor 1;",
		"+1 AC, attack, and damage every 3 floors.",
		"",
	]
	for enemy: Resource in enemies:
		lines.append_array(_enemy_entry(enemy))
		lines.append("")
	return "\n".join(lines)


func _build_scribes_text() -> String:
	var items: Array[Resource] = _load_resources_with_paths(ITEM_PATHS)
	items.sort_custom(_sort_item)
	var lines: Array[String] = [
		"[font_size=24][color=#f1c75b]SCRIBES[/color][/font_size]",
		"",
		"Item data from item resources. Shops and dungeon drops use floor gates,",
		"spawn weight, and rarity weight. depth = floor - 1.",
		"",
		"[color=#f1c75b]ITEM TYPES[/color]",
	]
	for item_kind: int in [
		ItemDataScript.ItemKind.CONSUMABLE,
		ItemDataScript.ItemKind.WEAPON,
		ItemDataScript.ItemKind.ARMOR,
		ItemDataScript.ItemKind.ACCESSORY,
	]:
		lines.append(
			(
				"- [color=#8fb3ff]%s[/color]: %s"
				% [_item_kind_name(item_kind), ITEM_TYPE_LORE[item_kind]]
			)
		)
	lines.append("")
	lines.append("[color=#f1c75b]RARITIES[/color]")
	for rarity_index: int in range(ItemDataScript.RARITY_NAMES.size()):
		lines.append(_rarity_entry(rarity_index))
	lines.append("")
	lines.append("[color=#f1c75b]KNOWN ITEMS[/color]")
	var current_kind: int = -1
	for item: Resource in items:
		if item.kind != current_kind:
			current_kind = item.kind
			lines.append("")
			lines.append(
				(
					"[font_size=20][color=#8fb3ff]%s[/color][/font_size]"
					% item.get_kind_name().to_upper()
				)
			)
		lines.append_array(_item_entry(item))
	return "\n".join(lines)


func _enemy_entry(enemy: Resource) -> Array[String]:
	var color: String = enemy.color.to_html(false)
	var lines: Array[String] = [
		(
			"[font_size=20][color=#%s]%s[/color][/font_size]  [color=#777777]'%s'[/color]"
			% [color, enemy.display_name, enemy.glyph]
		),
		(
			"Floors: %s    Spawn Weight: %d    XP: %d"
			% [_floor_range(enemy.min_floor, enemy.max_floor), enemy.spawn_weight, enemy.xp_reward]
		),
		"Defense: AC %d, HP %d" % [enemy.armor_class, enemy.max_hp],
		(
			"Offense: attack %+d, damage 1d%d%+d"
			% [enemy.attack_bonus, enemy.damage_sides, enemy.damage_bonus]
		),
		"Note: %s" % ENEMY_NOTES.get(enemy.display_name, _enemy_stat_note(enemy)),
	]
	return lines


func _item_entry(item: Resource) -> Array[String]:
	var lines: Array[String] = [
		(
			"[color=%s]%s[/color]  %s %s  %s  Price %dg  Spawn Weight %d"
			% [
				item.get_rarity_color(),
				item.display_name,
				item.get_rarity_name(),
				item.get_kind_name(),
				_floor_range(item.min_floor, item.max_floor),
				item.get_price(),
				item.spawn_weight
			]
		),
		"  Text: %s" % item.description,
		"  Stats: %s" % _item_stats_line(item),
	]
	return lines


func _item_stats_line(item: Resource) -> String:
	var stats: Array[String] = []
	if item.use_effect != ItemDataScript.ItemUse.NONE:
		stats.append(_item_use_name(item.use_effect))
	if item.range > 1:
		stats.append("range %d" % item.range)
	if item.healing_amount > 0:
		stats.append("heals %d HP" % item.healing_amount)
	if item.damage_sides > 0:
		stats.append("damage %dd%d%+d" % [item.damage_dice, item.damage_sides, item.damage_bonus])
	if item.attack_bonus != 0:
		stats.append("attack %+d" % item.attack_bonus)
	elif item.damage_bonus != 0:
		stats.append("damage %+d" % item.damage_bonus)
	if item.armor_bonus != 0:
		stats.append("AC %+d" % item.armor_bonus)
	if item.effect_duration > 0:
		stats.append("duration %d" % item.effect_duration)
	if item.target_radius > 0:
		stats.append("radius %d" % item.target_radius)
	if stats.is_empty():
		stats.append("no direct combat stat")
	return ", ".join(stats)


func _item_use_name(item_use: int) -> String:
	var name: String = "none"
	match item_use:
		ItemDataScript.ItemUse.HEAL:
			name = "heal"
		ItemDataScript.ItemUse.RANGED_ATTACK:
			name = "ranged attack"
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			name = "magic missile"
		ItemDataScript.ItemUse.SHIELD:
			name = "shield"
		ItemDataScript.ItemUse.SLEEP:
			name = "sleep"
		ItemDataScript.ItemUse.HASTE:
			name = "haste"
	return name


func _rarity_entry(rarity_index: int) -> String:
	var name: String = ItemDataScript.RARITY_NAMES[rarity_index]
	var color: String = ItemDataScript.RARITY_COLORS[rarity_index]
	var note: String = "weight 1"
	match rarity_index:
		ItemDataScript.ItemRarity.COMMON:
			note = "weight max(8, 60 - 5 × depth)"
		ItemDataScript.ItemRarity.UNCOMMON:
			note = "weight 22 + 3 × depth"
		ItemDataScript.ItemRarity.RARE:
			note = "weight max(0, 5 × depth - 6)"
		ItemDataScript.ItemRarity.EPIC:
			note = "weight max(0, 4 × depth - 16)"
		ItemDataScript.ItemRarity.LEGENDARY:
			note = "weight max(0, 3 × depth - 18)"
		ItemDataScript.ItemRarity.MYTHIC:
			note = "weight max(0, 2 × depth - 14)"
	return "- [color=%s]%s[/color]: %s" % [color, name, note]



## Resource path lists (explicit — DirAccess does not work in web exports)
const ENEMY_PATHS: Array[String] = [
	"res://resources/enemies/bat.tres",
	"res://resources/enemies/cultist.tres",
	"res://resources/enemies/goblin.tres",
	"res://resources/enemies/kobold.tres",
	"res://resources/enemies/orc.tres",
	"res://resources/enemies/rat.tres",
	"res://resources/enemies/skeleton.tres",
	"res://resources/enemies/troll.tres",
	"res://resources/enemies/wraith.tres",
	"res://resources/enemies/zombie.tres",
]
const ITEM_PATHS: Array[String] = [
	"res://resources/items/amulet_of_guarding.tres",
	"res://resources/items/battle_axe.tres",
	"res://resources/items/bracers_of_power.tres",
	"res://resources/items/chainmail.tres",
	"res://resources/items/dagger.tres",
	"res://resources/items/dragonbone_blade.tres",
	"res://resources/items/elixir_of_life.tres",
	"res://resources/items/elixir_of_swiftness.tres",
	"res://resources/items/elven_chain.tres",
	"res://resources/items/flail.tres",
	"res://resources/items/greater_health_potion.tres",
	"res://resources/items/greatsword.tres",
	"res://resources/items/half_plate.tres",
	"res://resources/items/hand_crossbow.tres",
	"res://resources/items/health_potion.tres",
	"res://resources/items/heavy_crossbow.tres",
	"res://resources/items/iron_axe.tres",
	"res://resources/items/leather_armor.tres",
	"res://resources/items/longbow.tres",
	"res://resources/items/longsword.tres",
	"res://resources/items/mace.tres",
	"res://resources/items/mythril_plate.tres",
	"res://resources/items/plate_armor.tres",
	"res://resources/items/potion_of_giant_strength.tres",
	"res://resources/items/potion_of_haste.tres",
	"res://resources/items/ring_of_accuracy.tres",
	"res://resources/items/ring_of_power.tres",
	"res://resources/items/ring_of_protection.tres",
	"res://resources/items/scale_mail.tres",
	"res://resources/items/scimitar.tres",
	"res://resources/items/scroll_fire_bolt.tres",
	"res://resources/items/scroll_lightning_bolt.tres",
	"res://resources/items/scroll_magic_missile.tres",
	"res://resources/items/scroll_shield.tres",
	"res://resources/items/scroll_sleep.tres",
	"res://resources/items/shortbow.tres",
	"res://resources/items/spear.tres",
	"res://resources/items/splint_armor.tres",
	"res://resources/items/starfall_charm.tres",
	"res://resources/items/studded_leather.tres",
	"res://resources/items/superior_health_potion.tres",
	"res://resources/items/tonic_of_regeneration.tres",
	"res://resources/items/warhammer.tres",
]

func _load_resources_from_dir(_dir_path: String) -> Array[Resource]:
	# DirAccess does not work in web exports, so this always returns empty.
	# Use explicit path lists (ENEMY_PATHS, ITEM_PATHS) and load_with_paths() instead.
	return []


func _load_resources_with_paths(paths: Array[String]) -> Array[Resource]:
	var resources: Array[Resource] = []
	for path: String in paths:
		var loaded: Resource = load(path)
		if loaded != null:
			resources.append(loaded)
	return resources


func _sort_enemy(left: Resource, right: Resource) -> bool:
	if left.min_floor == right.min_floor:
		return left.display_name < right.display_name
	return left.min_floor < right.min_floor


func _sort_item(left: Resource, right: Resource) -> bool:
	if left.kind != right.kind:
		return left.kind < right.kind
	if left.rarity != right.rarity:
		return left.rarity < right.rarity
	if left.min_floor != right.min_floor:
		return left.min_floor < right.min_floor
	return left.display_name < right.display_name


func _enemy_stat_note(enemy: Resource) -> String:
	var tags: Array[String] = []
	if enemy.armor_class >= 14:
		tags.append("high AC")
	if enemy.max_hp >= 18:
		tags.append("large HP pool")
	if enemy.attack_bonus >= 5:
		tags.append("accurate")
	if enemy.damage_sides + enemy.damage_bonus >= 11:
		tags.append("high damage")
	if tags.is_empty():
		return "standard melee enemy"
	return ", ".join(tags)


func _floor_range(min_floor: int, max_floor: int) -> String:
	if max_floor > 0:
		return "floors %d-%d" % [min_floor, max_floor]
	return "floor %d+" % min_floor


func _item_kind_name(item_kind: int) -> String:
	var item: Resource = ItemDataScript.new()
	item.kind = item_kind
	return item.get_kind_name()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
