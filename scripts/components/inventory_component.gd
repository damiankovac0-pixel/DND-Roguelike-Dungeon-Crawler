## Holds items and equipped weapon/armor/accessory slots with add/remove/equip logic.
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
			return _toggle_weapon(item)
		ItemDataScript.ItemKind.ARMOR:
			return _toggle_armor(item)
		ItemDataScript.ItemKind.ACCESSORY:
			return _toggle_accessory(item)
	return false


func _toggle_weapon(item: Resource) -> bool:
	var equipped_slot: Resource = (
		equipped_ranged_weapon if item.is_ranged_weapon else equipped_melee_weapon
	)
	var is_now_equipped: bool = equipped_slot != item
	# Class gating: block equip if wrong class, allow unequip always.
	if is_now_equipped and not _can_equip(item):
		return false
	if item.is_ranged_weapon:
		equipped_ranged_weapon = item if is_now_equipped else null
	else:
		equipped_melee_weapon = item if is_now_equipped else null
	equipped_weapon = item if is_now_equipped else null
	return is_now_equipped


func _toggle_armor(item: Resource) -> bool:
	var is_now_equipped: bool = equipped_armor != item
	if is_now_equipped and not _can_equip(item):
		return false
	equipped_armor = item if is_now_equipped else null
	return is_now_equipped


func _toggle_accessory(item: Resource) -> bool:
	if not _can_equip(item) and equipped_accessory_1 != item and equipped_accessory_2 != item:
		return false
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
		if not _can_equip(item):
			continue
		var score: int = (
			item.damage_dice * max(1, item.damage_sides) + item.damage_bonus + item.attack_bonus * 2
		)
		if wants_ranged:
			score += item.range
		if score > best_score:
			best_score = score
			best_weapon = item
	return best_weapon


func get_class_damage_percent_bonus(damage_type: StringName) -> int:
	var total_bonus: int = 0
	var player_class: StringName = GameManager.pending_character_class
	for item: Resource in [
		equipped_melee_weapon,
		equipped_ranged_weapon,
		equipped_armor,
		equipped_accessory_1,
		equipped_accessory_2
	]:
		if item == null:
			continue
		if item.class_damage_percent_bonus == 0:
			continue
		if item.class_damage_type != damage_type:
			continue
		var required: StringName = item.required_class
		if required == &"" or required == player_class:
			total_bonus += item.class_damage_percent_bonus
	return total_bonus


func _get_active_set_bonuses() -> Array[Dictionary]:
	var set_data: Dictionary = {}
	for item: Resource in get_equipped_items():
		if item.set_id == &"":
			continue
		var key: String = String(item.set_id)
		if not set_data.has(key):
			set_data[key] = _new_set_bonus_data(item)
		var data: Dictionary = set_data[key]
		data["count"] = int(data["count"]) + 1
		data["required_count"] = max(int(data["required_count"]), item.set_required_count)
		data["damage_resist_percent"] = max(
			int(data["damage_resist_percent"]), item.set_damage_resist_percent
		)
		data["proc_chance_percent"] = max(
			int(data["proc_chance_percent"]), item.set_proc_chance_percent
		)
		data["proc_heal_percent"] = max(int(data["proc_heal_percent"]), item.set_proc_heal_percent)
	var active_sets: Array[Dictionary] = []
	for key: String in set_data:
		var data: Dictionary = set_data[key]
		if int(data["count"]) >= max(2, int(data["required_count"])):
			active_sets.append(data)
	return active_sets


func _get_equipped_set_piece_count(set_id: StringName) -> int:
	var count: int = 0
	for item: Resource in get_equipped_items():
		if item.set_id == set_id:
			count += 1
	return count


func _get_set_damage_resist_percent() -> int:
	var resist_percent: int = 0
	for data: Dictionary in _get_active_set_bonuses():
		resist_percent = max(resist_percent, int(data["damage_resist_percent"]))
	return resist_percent


func _get_set_proc_chance_percent() -> int:
	var proc_chance: int = 0
	for data: Dictionary in _get_active_set_bonuses():
		proc_chance = max(proc_chance, int(data["proc_chance_percent"]))
	return proc_chance


func _get_set_proc_heal_percent() -> int:
	var heal_percent: int = 0
	for data: Dictionary in _get_active_set_bonuses():
		heal_percent = max(heal_percent, int(data["proc_heal_percent"]))
	return heal_percent


func _get_set_proc_display_name() -> String:
	for data: Dictionary in _get_active_set_bonuses():
		if int(data["proc_chance_percent"]) > 0 and int(data["proc_heal_percent"]) > 0:
			return data["display_name"]
	return "Set bonus"


func _new_set_bonus_data(item: Resource) -> Dictionary:
	var display_name: String = item.set_display_name
	if display_name.is_empty():
		display_name = String(item.set_id).capitalize()
	return {
		"set_id": item.set_id,
		"display_name": display_name,
		"count": 0,
		"required_count": max(2, item.set_required_count),
		"damage_resist_percent": max(0, item.set_damage_resist_percent),
		"proc_chance_percent": max(0, item.set_proc_chance_percent),
		"proc_heal_percent": max(0, item.set_proc_heal_percent),
	}


func _can_equip(item: Resource) -> bool:
	var required: StringName = item.required_class
	if required == &"":
		return true
	return required == GameManager.pending_character_class
