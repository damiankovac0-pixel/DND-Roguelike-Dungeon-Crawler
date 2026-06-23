class_name StatsComponent
extends Node

signal died

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
	var leveled_up: bool = false
	while xp >= xp_for_next_level():
		xp -= xp_for_next_level()
		level += 1
		proficiency_bonus = 2 + int((level - 1) / 4)
		max_hp += max(1, 5 + Dice.modifier(constitution))
		current_hp = max_hp
		leveled_up = true
	return leveled_up


func xp_for_next_level() -> int:
	return level * 100


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
			"effects": "Unlocks arcane knowledge",
			"flavor": "Mind over darkness.",
		},
		{
			"key": "wis",
			"name": "WIS",
			"value": wisdom,
			"modifier": wis_mod,
			"effects": "Sharpens divine insight",
			"flavor": "Seeing what others miss.",
		},
		{
			"key": "cha",
			"name": "CHA",
			"value": charisma,
			"modifier": cha_mod,
			"effects": "Shop pays %d%% base price" % max(50, 100 - 5 * cha_mod),
			"flavor": "A silver tongue opens purses.",
		},
	]
