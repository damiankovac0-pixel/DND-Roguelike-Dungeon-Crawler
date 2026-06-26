class_name InventoryComponent
extends Node

# === Constants ===
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

# === Public Variables ===
var items: Array = []
var equipped_weapon: Resource
var equipped_melee_weapon: Resource
var equipped_ranged_weapon: Resource
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
	if equipped_melee_weapon == item:
		equipped_melee_weapon = null
	if equipped_ranged_weapon == item:
		equipped_ranged_weapon = null
	if equipped_armor == item:
		equipped_armor = null
	if equipped_accessory_1 == item:
		equipped_accessory_1 = null
	if equipped_accessory_2 == item:
		equipped_accessory_2 = null


func get_attack_bonus() -> int:
	var bonus: int = 0
	var melee_weapon: Resource = get_preferred_melee_weapon()
	if melee_weapon != null:
		bonus += melee_weapon.attack_bonus
	if equipped_accessory_1 != null:
		bonus += equipped_accessory_1.attack_bonus
	if equipped_accessory_2 != null:
		bonus += equipped_accessory_2.attack_bonus
	return bonus


func get_damage_bonus() -> int:
	var bonus: int = 0
	var melee_weapon: Resource = get_preferred_melee_weapon()
	if melee_weapon != null:
		bonus += melee_weapon.damage_bonus
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
	var melee_weapon: Resource = get_preferred_melee_weapon()
	if melee_weapon == null or melee_weapon.damage_sides <= 0:
		return 4
	return melee_weapon.damage_sides


func get_preferred_melee_weapon() -> Resource:
	if equipped_melee_weapon != null:
		return equipped_melee_weapon
	if equipped_weapon != null and not equipped_weapon.is_ranged_weapon:
		return equipped_weapon
	return _find_best_weapon(false)


func get_equipped_ranged_weapon() -> Resource:
	if equipped_ranged_weapon != null:
		return equipped_ranged_weapon
	if equipped_weapon != null and equipped_weapon.is_ranged_weapon:
		return equipped_weapon
	return _find_best_weapon(true)

func get_equipped_items() -> Array[Resource]:
	var equipped_items: Array[Resource] = []
	for item: Resource in [
		get_preferred_melee_weapon(),
		get_equipped_ranged_weapon(),
		equipped_armor,
		equipped_accessory_1,
		equipped_accessory_2,
	]:
		if item != null and not equipped_items.has(item):
			equipped_items.append(item)
	return equipped_items


func get_equipped_special_items(special_effect: int) -> Array[Resource]:
	var special_items: Array[Resource] = []
	for item: Resource in get_equipped_items():
		if item.special_effect == special_effect:
			special_items.append(item)
	return special_items


func toggle_equipped(item: Resource) -> bool:
	match item.kind:
		ItemDataScript.ItemKind.WEAPON:
			var equipped_slot: Resource = equipped_ranged_weapon if item.is_ranged_weapon else equipped_melee_weapon
			var is_now_equipped: bool = equipped_slot != item
			if item.is_ranged_weapon:
				equipped_ranged_weapon = item if is_now_equipped else null
			else:
				equipped_melee_weapon = item if is_now_equipped else null
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
		or equipped_melee_weapon == item
		or equipped_ranged_weapon == item
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

func _find_best_weapon(wants_ranged: bool) -> Resource:
	var best_weapon: Resource = null
	var best_score: int = -1
	for item: Resource in items:
		if item.kind != ItemDataScript.ItemKind.WEAPON or item.is_ranged_weapon != wants_ranged:
			continue
		var score: int = item.damage_dice * max(1, item.damage_sides) + item.damage_bonus + item.attack_bonus * 2
		if wants_ranged:
			score += item.range
		if score > best_score:
			best_score = score
			best_weapon = item
	return best_weapon
