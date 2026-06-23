class_name InventoryComponent
extends Node

# === Constants ===
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

# === Public Variables ===
var items: Array = []
var equipped_weapon: Resource
var equipped_armor: Resource
var equipped_accessory_1: Resource
var equipped_accessory_2: Resource


# === Public Methods ===
func add_item(item: Resource) -> void:
	items.append(item)


func remove_item(item: Resource) -> void:
	items.erase(item)
	if equipped_weapon == item:
		equipped_weapon = null
	if equipped_armor == item:
		equipped_armor = null
	if equipped_accessory_1 == item:
		equipped_accessory_1 = null
	if equipped_accessory_2 == item:
		equipped_accessory_2 = null


func get_attack_bonus() -> int:
	var bonus: int = 0
	if equipped_weapon != null and not equipped_weapon.is_ranged_weapon:
		bonus += equipped_weapon.attack_bonus
	if equipped_accessory_1 != null:
		bonus += equipped_accessory_1.attack_bonus
	if equipped_accessory_2 != null:
		bonus += equipped_accessory_2.attack_bonus
	return bonus


func get_damage_bonus() -> int:
	var bonus: int = 0
	if equipped_weapon != null and not equipped_weapon.is_ranged_weapon:
		bonus += equipped_weapon.damage_bonus
	if equipped_accessory_1 != null:
		bonus += equipped_accessory_1.damage_bonus
	if equipped_accessory_2 != null:
		bonus += equipped_accessory_2.damage_bonus
	return bonus


func get_accessory_attack_bonus() -> int:
	var bonus: int = 0
	if equipped_accessory_1 != null:
		bonus += equipped_accessory_1.attack_bonus
	if equipped_accessory_2 != null:
		bonus += equipped_accessory_2.attack_bonus
	return bonus


func get_accessory_damage_bonus() -> int:
	var bonus: int = 0
	if equipped_accessory_1 != null:
		bonus += equipped_accessory_1.damage_bonus
	if equipped_accessory_2 != null:
		bonus += equipped_accessory_2.damage_bonus
	return bonus


func get_armor_bonus() -> int:
	var bonus: int = 0
	if equipped_armor != null:
		bonus += equipped_armor.armor_bonus
	if equipped_accessory_1 != null:
		bonus += equipped_accessory_1.armor_bonus
	if equipped_accessory_2 != null:
		bonus += equipped_accessory_2.armor_bonus
	return bonus


func get_weapon_damage_sides() -> int:
	if (
		equipped_weapon == null
		or equipped_weapon.is_ranged_weapon
		or equipped_weapon.damage_sides <= 0
	):
		return 4
	return equipped_weapon.damage_sides


func get_equipped_ranged_weapon() -> Resource:
	if equipped_weapon == null or not equipped_weapon.is_ranged_weapon:
		return null
	return equipped_weapon


func toggle_equipped(item: Resource) -> bool:
	match item.kind:
		ItemDataScript.ItemKind.WEAPON:
			var is_now_equipped: bool = equipped_weapon != item
			equipped_weapon = item if is_now_equipped else null
			return is_now_equipped
		ItemDataScript.ItemKind.ARMOR:
			var is_now_equipped: bool = equipped_armor != item
			equipped_armor = item if is_now_equipped else null
			return is_now_equipped
		ItemDataScript.ItemKind.ACCESSORY:
			if equipped_accessory_1 == item:
				equipped_accessory_1 = null
			elif equipped_accessory_2 == item:
				equipped_accessory_2 = null
			elif equipped_accessory_1 == null:
				equipped_accessory_1 = item
			elif equipped_accessory_2 == null:
				equipped_accessory_2 = item
			else:
				equipped_accessory_1 = item
			return equipped_accessory_1 == item or equipped_accessory_2 == item
		_:
			return false


func is_equipped(item: Resource) -> bool:
	return (
		equipped_weapon == item
		or equipped_armor == item
		or equipped_accessory_1 == item
		or equipped_accessory_2 == item
	)


func get_consumables() -> Array:
	var consumables: Array = []
	for item in items:
		if item.kind == ItemDataScript.ItemKind.CONSUMABLE:
			consumables.append(item)
	return consumables


func consume_first_potion() -> Resource:
	for item in items:
		if item.kind == ItemDataScript.ItemKind.CONSUMABLE and item.healing_amount > 0:
			remove_item(item)
			return item
	return null
