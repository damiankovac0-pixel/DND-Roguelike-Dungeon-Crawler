class_name StatsComponent
extends Node

signal died

# === Constants ===
const MAX_ABILITY_SCORE: int = 20
const STAT_LEVEL_CAP: int = 20
const PRESTIGE_LEVEL_COLORS: Array[String] = [
	"#d899ff",
	"#c77dff",
	"#9d7dff",
	"#7db8ff",
	"#66fff0",
	"#7bd88f",
	"#ffb84d",
	"#ff5fd7",
]

# === Public Variables ===
var strength: int = 10
var dexterity: int = 10
var constitution: int = 10
var intelligence: int = 10
var wisdom: int = 10
var charisma: int = 10
var max_hp: int = 10
var current_hp: int = 10
var xp: int = 0
var level: int = 1
var pending_stat_increases: int = 0
var last_levels_gained: int = 0
var proficiency_bonus: int = 2
var base_armor_class: int = 10
var base_attack_bonus: int = 0
var base_damage_bonus: int = 0
var base_damage_sides: int = 4
var xp_reward: int = 0
var gold: int = 0
var temporary_armor_bonus: int = 0
var inventory_component: Node


# === Public Methods ===
func configure_player(ability_scores: Dictionary) -> void:
	strength = ability_scores.get("str", 10)
	dexterity = ability_scores.get("dex", 10)
	constitution = ability_scores.get("con", 10)
	intelligence = ability_scores.get("int", 10)
	wisdom = ability_scores.get("wis", 10)
	charisma = ability_scores.get("cha", 10)
	_recalculate_derived_stats()
	current_hp = max_hp


func configure_enemy(enemy_data: Resource) -> void:
	max_hp = enemy_data.max_hp
	current_hp = max_hp
	base_armor_class = enemy_data.armor_class
	base_attack_bonus = enemy_data.attack_bonus
	base_damage_bonus = enemy_data.damage_bonus
	base_damage_sides = enemy_data.damage_sides
	xp_reward = enemy_data.xp_reward


func apply_damage(amount: int) -> int:
	current_hp = max(0, current_hp - amount)
	if current_hp <= 0:
		died.emit()
	return current_hp


func heal(amount: int) -> int:
	current_hp = min(max_hp, current_hp + amount)
	return current_hp


func get_armor_class() -> int:
	var inventory_bonus: int = 0
	if inventory_component != null:
		inventory_bonus = inventory_component.get_armor_bonus()
	return base_armor_class + Dice.modifier(dexterity) + inventory_bonus + temporary_armor_bonus


func get_attack_bonus() -> int:
	var inventory_bonus: int = 0
	if inventory_component != null:
		inventory_bonus = inventory_component.get_attack_bonus()
	return base_attack_bonus + proficiency_bonus + Dice.modifier(strength) + inventory_bonus


func get_damage_bonus() -> int:
	var inventory_bonus: int = 0
	if inventory_component != null:
		inventory_bonus = inventory_component.get_damage_bonus()
	return base_damage_bonus + Dice.modifier(strength) + inventory_bonus


func get_damage_sides() -> int:
	if inventory_component != null:
		return max(base_damage_sides, inventory_component.get_weapon_damage_sides())
	return base_damage_sides


func grant_xp(amount: int) -> bool:
	xp += amount
	last_levels_gained = 0
	while xp >= xp_for_next_level():
		xp -= xp_for_next_level()
		level += 1
		last_levels_gained += 1
		proficiency_bonus = 2 + int((min(level, STAT_LEVEL_CAP) - 1) / 4)
		max_hp += max(1, 5 + Dice.modifier(constitution))
		current_hp = max_hp
		if level <= STAT_LEVEL_CAP and has_available_stat_increase():
			pending_stat_increases += 1
	return last_levels_gained > 0


func xp_for_next_level() -> int:
	return level * 100

func get_level_label() -> String:
	return format_level_label(level)


func get_level_bbcode() -> String:
	return format_level_bbcode(level)


func format_level_label(level_value: int) -> String:
	if level_value <= STAT_LEVEL_CAP:
		return "%d" % level_value
	return "%d+%d" % [STAT_LEVEL_CAP, level_value - STAT_LEVEL_CAP]


func format_level_bbcode(level_value: int) -> String:
	if level_value <= STAT_LEVEL_CAP:
		return "%d" % level_value
	var prestige_level: int = level_value - STAT_LEVEL_CAP
	return "%d[color=%s]+%d[/color]" % [
		STAT_LEVEL_CAP,
		get_prestige_level_color(prestige_level),
		prestige_level,
	]


func get_prestige_level_color(prestige_level: int) -> String:
	if prestige_level <= 0:
		return PRESTIGE_LEVEL_COLORS[0]
	return PRESTIGE_LEVEL_COLORS[(prestige_level - 1) % PRESTIGE_LEVEL_COLORS.size()]


func has_available_stat_increase() -> bool:
	return (
		strength < MAX_ABILITY_SCORE
		or dexterity < MAX_ABILITY_SCORE
		or constitution < MAX_ABILITY_SCORE
		or intelligence < MAX_ABILITY_SCORE
		or wisdom < MAX_ABILITY_SCORE
		or charisma < MAX_ABILITY_SCORE
	)


func can_increase_ability(stat_key: String) -> bool:
	if pending_stat_increases <= 0:
		return false
	return _get_ability_value(stat_key) < MAX_ABILITY_SCORE


func increase_ability(stat_key: String) -> bool:
	if not can_increase_ability(stat_key):
		return false
	var old_con_modifier: int = Dice.modifier(constitution)
	_set_ability_value(stat_key, _get_ability_value(stat_key) + 1)
	pending_stat_increases -= 1
	if stat_key == "con":
		var con_hp_gain: int = max(0, Dice.modifier(constitution) - old_con_modifier) * level
		max_hp += con_hp_gain
		current_hp += con_hp_gain
	return true



func get_summary_lines() -> Array[String]:
	return [
		"STR %d (%+d)" % [strength, Dice.modifier(strength)],
		"DEX %d (%+d)" % [dexterity, Dice.modifier(dexterity)],
		"CON %d (%+d)" % [constitution, Dice.modifier(constitution)],
		"INT %d (%+d)" % [intelligence, Dice.modifier(intelligence)],
		"WIS %d (%+d)" % [wisdom, Dice.modifier(wisdom)],
		"CHA %d (%+d)" % [charisma, Dice.modifier(charisma)],
	]


# === Private Methods ===
func _recalculate_derived_stats() -> void:
	max_hp = 12 + Dice.modifier(constitution)
	base_armor_class = 10
	base_attack_bonus = 0
	base_damage_bonus = 0
	base_damage_sides = 4


# === Stat Description Helpers ===
func get_ability_effects() -> Array[Dictionary]:
	var str_mod: int = Dice.modifier(strength)
	var dex_mod: int = Dice.modifier(dexterity)
	var con_mod: int = Dice.modifier(constitution)
	var int_mod: int = Dice.modifier(intelligence)
	var wis_mod: int = Dice.modifier(wisdom)
	var cha_mod: int = Dice.modifier(charisma)
	return [
		{
			"key": "str",
			"name": "STR",
			"value": strength,
			"modifier": str_mod,
			"effects": "Melee attack %+d, damage %+d" % [str_mod, str_mod],
			"flavor": "Raw power for blade and brawl.",
		},
		{
			"key": "dex",
			"name": "DEX",
			"value": dexterity,
			"modifier": dex_mod,
			"effects": "AC %+d, ranged attack %+d" % [dex_mod, dex_mod],
			"flavor": "Quick hands and steady aim.",
		},
		{
			"key": "con",
			"name": "CON",
			"value": constitution,
			"modifier": con_mod,
			"effects": "HP +%d per level" % max(1, 5 + con_mod),
			"flavor": "Grit to endure the depths.",
		},
		{
			"key": "int",
			"name": "INT",
			"value": intelligence,
			"modifier": int_mod,
			"effects": "Potions restore %+d HP (min +0)" % max(0, int_mod),
			"flavor": "A sharper mind wastes less medicine.",
		},
		{
			"key": "wis",
			"name": "WIS",
			"value": wisdom,
			"modifier": wis_mod,
			"effects": "Magic scroll damage %+d (min +0)" % max(0, wis_mod),
			"flavor": "Insight turns glyphs into force.",
		},
		{
			"key": "cha",
			"name": "CHA",
			"value": charisma,
			"modifier": cha_mod,
			"effects": (
				"Buy %d%%, sell %d%% value"
				% [
					max(50, 100 - 5 * cha_mod),
					int(clampf(0.35 + 0.02 * cha_mod, 0.25, 0.50) * 100.0),
				]
			),
			"flavor": "A silver tongue opens purses.",
		},
	]

func _get_ability_value(stat_key: String) -> int:
	match stat_key:
		"str":
			return strength
		"dex":
			return dexterity
		"con":
			return constitution
		"int":
			return intelligence
		"wis":
			return wisdom
		"cha":
			return charisma
	return MAX_ABILITY_SCORE


func _set_ability_value(stat_key: String, value: int) -> void:
	var capped_value: int = clampi(value, 1, MAX_ABILITY_SCORE)
	match stat_key:
		"str":
			strength = capped_value
		"dex":
			dexterity = capped_value
		"con":
			constitution = capped_value
		"int":
			intelligence = capped_value
		"wis":
			wisdom = capped_value
		"cha":
			charisma = capped_value
