## Headless test for V12.2.0 staff and class gear mechanics.
##
## Contracts:
##   1. New staff/class resources load with required class, damage type, and bonuses.
##   2. Class-restricted gear stays sellable in inventory but cannot equip for wrong classes.
##   3. Equipped class gear adds damage percent only for matching class and damage type.
##   4. Wizard staffs use WIS-based magic damage and do not consume Hunter's Focus.
## Run:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v12_staff_gear.gd
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const APPRENTICE_STAFF_PATH: String = "res://resources/items/apprentice_staff.tres"
const ASCENDANT_STAFF_PATH: String = "res://resources/items/staff_ascendant.tres"
const EMBER_STAFF_PATH: String = "res://resources/items/staff_ember.tres"
const WARRIORS_RING_PATH: String = "res://resources/items/warriors_ring.tres"
const DEFT_GLOVES_PATH: String = "res://resources/items/deft_gloves.tres"
const ARCANE_ROBES_PATH: String = "res://resources/items/arcane_robes.tres"
const VANGUARD_BLADE_PATH: String = "res://resources/items/vanguard_blade.tres"
const WARLORD_GREATSWORD_PATH: String = "res://resources/items/warlord_greatsword.tres"
const EAGLEWOOD_BOW_PATH: String = "res://resources/items/eaglewood_bow.tres"
const MOONSTRING_LONGBOW_PATH: String = "res://resources/items/moonstring_longbow.tres"

var _game_script: GDScript
var _actor_script: GDScript
var _stats_script: GDScript
var _inventory_script: GDScript
var _failed: bool = false
var _apprentice_staff: Resource
var _ascendant_staff: Resource
var _ember_staff: Resource
var _warriors_ring: Resource
var _deft_gloves: Resource
var _arcane_robes: Resource
var _vanguard_blade: Resource
var _warlord_greatsword: Resource
var _eaglewood_bow: Resource
var _moonstring_longbow: Resource


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)
	_game_script = load("res://scripts/game.gd")
	_actor_script = load("res://scripts/entities/actor.gd")
	_stats_script = load("res://scripts/components/stats_component.gd")
	_inventory_script = load("res://scripts/components/inventory_component.gd")
	_load_item_resources()

	_check_resource_contracts()
	if not _failed:
		_check_class_restricted_equipping()
	if not _failed:
		_check_class_damage_bonus_helper()
	if not _failed:
		await _check_staff_attack_uses_magic_pipeline()

	if not _failed:
		print("V12.2.0 staff and class gear checks passed")
		quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _make_player(grid_pos: Vector2i, level: int = 1) -> Node2D:
	var player: Node2D = _actor_script.new()
	player.display_name = "Hero"
	player.grid_position = grid_pos
	var stats: Node = _stats_script.new()
	stats.name = "StatsComponent"
	stats.max_hp = 100
	stats.current_hp = 100
	stats.level = level
	stats.strength = 10
	stats.dexterity = 10
	stats.constitution = 10
	stats.intelligence = 10
	stats.wisdom = 10
	stats.charisma = 10
	stats.proficiency_bonus = 2
	stats.base_armor_class = 10
	stats.base_attack_bonus = 0
	stats.base_damage_bonus = 0
	stats.base_damage_sides = 4
	player.add_child(stats)
	player.stats_component = stats
	var inv: Node = _inventory_script.new()
	inv.name = "InventoryComponent"
	player.add_child(inv)
	player.inventory_component = inv
	return player


func _make_defender(grid_pos: Vector2i, hp: int = 100, armor_class: int = 10) -> Node2D:
	var defender: Node2D = _actor_script.new()
	defender.display_name = "Target"
	defender.grid_position = grid_pos
	var stats: Node = _stats_script.new()
	stats.name = "StatsComponent"
	stats.max_hp = hp
	stats.current_hp = hp
	stats.base_armor_class = armor_class
	stats.proficiency_bonus = 2
	defender.add_child(stats)
	defender.stats_component = stats
	return defender


func _free_test_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


func _free_game(game: Node) -> void:
	if game == null or not is_instance_valid(game):
		return
	var player_ref: Variant = game.get("_player")
	if player_ref != null and is_instance_valid(player_ref):
		var player_node: Node = player_ref as Node
		if player_node != null:
			_free_test_node(player_node)
	game.free()


func _load_item_resources() -> void:
	_apprentice_staff = load(APPRENTICE_STAFF_PATH)
	_ascendant_staff = load(ASCENDANT_STAFF_PATH)
	_ember_staff = load(EMBER_STAFF_PATH)
	_warriors_ring = load(WARRIORS_RING_PATH)
	_deft_gloves = load(DEFT_GLOVES_PATH)
	_arcane_robes = load(ARCANE_ROBES_PATH)
	_vanguard_blade = load(VANGUARD_BLADE_PATH)
	_warlord_greatsword = load(WARLORD_GREATSWORD_PATH)
	_eaglewood_bow = load(EAGLEWOOD_BOW_PATH)
	_moonstring_longbow = load(MOONSTRING_LONGBOW_PATH)


func _registered_class_weapon_paths() -> bool:
	for path: String in [
		VANGUARD_BLADE_PATH, WARLORD_GREATSWORD_PATH, EAGLEWOOD_BOW_PATH, MOONSTRING_LONGBOW_PATH
	]:
		if not ResourcePathsScript.ITEM_PATHS.has(path):
			return false
	return true


func _check_resource_contracts() -> void:
	var message: String = ""
	if _apprentice_staff == null or _ascendant_staff == null or _warriors_ring == null:
		message = "Staff/class resources failed to load"
	elif _deft_gloves == null or _arcane_robes == null:
		message = "Class gear resources failed to load"
	elif not _apprentice_staff.is_staff or _apprentice_staff.required_class != &"wizard":
		message = "Apprentice Staff must be a wizard-only staff"
	elif _apprentice_staff.weapon_damage_type != &"magic" or not _apprentice_staff.is_ranged_weapon:
		message = "Apprentice Staff must be a ranged magic weapon"
	elif _ascendant_staff.class_damage_type != &"magic":
		message = "Ascendant Staff must provide a magic class bonus"
	elif _ascendant_staff.class_damage_percent_bonus < 30:
		message = "Ascendant Staff must provide a meaningful magic class bonus"
	elif (
		_warriors_ring.required_class != &"fighter" or _warriors_ring.class_damage_type != &"melee"
	):
		message = "Warrior's Ring must be fighter melee gear"
	elif _deft_gloves.required_class != &"ranger" or _deft_gloves.class_damage_type != &"ranged":
		message = "Deft Gloves must be ranger ranged gear"
	elif _arcane_robes.required_class != &"wizard" or _arcane_robes.class_damage_type != &"magic":
		message = "Arcane Robes must be wizard magic gear"
	elif not _registered_class_weapon_paths():
		message = "ResourcePaths must register class weapon resources"
	elif _vanguard_blade == null or _warlord_greatsword == null:
		message = "Fighter class weapon resources failed to load"
	elif _eaglewood_bow == null or _moonstring_longbow == null:
		message = "Ranger class weapon resources failed to load"
	elif (
		_vanguard_blade.required_class != &"fighter"
		or _vanguard_blade.weapon_damage_type != &"melee"
		or _vanguard_blade.class_damage_percent_bonus <= 0
	):
		message = "Vanguard Blade must be fighter melee class gear"
	elif (
		_warlord_greatsword.min_floor < 17
		or (
			_warlord_greatsword.class_damage_percent_bonus
			< _vanguard_blade.class_damage_percent_bonus
		)
	):
		message = "Warlord Greatsword must be a late fighter upgrade"
	elif (
		_eaglewood_bow.required_class != &"ranger"
		or not _eaglewood_bow.is_ranged_weapon
		or _eaglewood_bow.weapon_damage_type != &"ranged"
	):
		message = "Eaglewood Bow must be ranger ranged class gear"
	elif (
		_moonstring_longbow.range < 8
		or (
			_moonstring_longbow.class_damage_percent_bonus
			< _eaglewood_bow.class_damage_percent_bonus
		)
	):
		message = "Moonstring Longbow must be a late ranger upgrade"

	if not message.is_empty():
		_fail(message)
	else:
		print("  staff and class gear resources load with expected fields")


func _check_class_restricted_equipping() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	var inv: Node = _inventory_script.new()
	var robes: Resource = _arcane_robes
	inv.add_item(robes)

	gm.prepare_character("RangerWrongGear", {}, &"ranger")
	var blocked: bool = inv.toggle_equipped(robes)
	if blocked:
		_fail("Ranger should not equip wizard-only Arcane Robes")
		inv.free()
		return
	if inv.items.size() != 1 or inv.items[0] != robes:
		_fail("Wrong-class item should remain in inventory for selling")
		inv.free()
		return

	gm.prepare_character("WizardGear", {}, &"wizard")
	var equipped: bool = inv.toggle_equipped(robes)
	if not equipped or inv.equipped_armor != robes:
		_fail("Wizard should equip Arcane Robes")
		inv.free()
		return

	gm.prepare_character("RangerUnequip", {}, &"ranger")
	var unequipped_return: bool = inv.toggle_equipped(robes)
	if unequipped_return or inv.equipped_armor != null:
		_fail("Already-equipped wrong-class gear should still be removable")
		inv.free()
		return

	inv.free()
	print("  class-restricted gear blocks wrong-class equip but remains sellable")


func _check_class_damage_bonus_helper() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	var inv: Node = _inventory_script.new()
	var fighter_ring: Resource = _warriors_ring
	var wizard_robes: Resource = _arcane_robes
	var staff: Resource = _ember_staff

	gm.prepare_character("WizardBonus", {}, &"wizard")
	inv.equipped_armor = wizard_robes
	inv.equipped_ranged_weapon = staff
	inv.equipped_accessory_1 = fighter_ring

	var magic_bonus: int = inv.get_class_damage_percent_bonus(&"magic")
	if magic_bonus != wizard_robes.class_damage_percent_bonus + staff.class_damage_percent_bonus:
		_fail("Wizard magic class bonus summed incorrectly: got %d" % magic_bonus)
		inv.free()
		return
	if inv.get_class_damage_percent_bonus(&"melee") != 0:
		_fail("Wrong-class fighter melee gear should not add bonus for Wizard")
		inv.free()
		return

	gm.prepare_character("FighterBonus", {}, &"fighter")
	if inv.get_class_damage_percent_bonus(&"melee") != fighter_ring.class_damage_percent_bonus:
		_fail("Fighter melee gear bonus should apply for Fighter")
		inv.free()
		return
	if inv.get_class_damage_percent_bonus(&"magic") != 0:
		_fail("Wizard-only magic gear should not apply for Fighter")
		inv.free()
		return

	inv.free()
	print("  class damage bonus helper filters by class and damage type")


func _check_staff_attack_uses_magic_pipeline() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	gm.prepare_character("WizardStaff", {}, &"wizard")

	var game: Node = _game_script.new()
	var player: Node2D = _make_player(Vector2i(5, 5), 1)
	player.stats_component.dexterity = 8
	player.stats_component.wisdom = 18
	root.add_child(player)
	await process_frame

	var defender: Node2D = _make_defender(Vector2i(6, 5), 100, 1)
	root.add_child(defender)
	await process_frame

	var staff: Resource = ItemDataScript.new()
	staff.display_name = "Deterministic Test Staff"
	staff.kind = ItemDataScript.ItemKind.WEAPON
	staff.is_ranged_weapon = true
	staff.is_staff = true
	staff.weapon_damage_type = &"magic"
	staff.required_class = &"wizard"
	staff.use_effect = ItemDataScript.ItemUse.RANGED_ATTACK
	staff.range = 4
	staff.damage_dice = 1
	staff.damage_sides = 1
	staff.damage_bonus = 0
	staff.attack_bonus = 0
	player.inventory_component.add_item(staff)
	player.inventory_component.equipped_ranged_weapon = staff
	player.inventory_component.equipped_weapon = staff

	game._player = player
	game._hunter_focus_primed = true
	seed(11)
	game._resolve_ranged_attack(staff, defender, &"weapon")

	var damage_done: int = 100 - defender.stats_component.current_hp
	if damage_done < 10:
		_fail("Wizard staff should use WIS + magic scaling; got only %d damage" % damage_done)
		_free_test_node(defender)
		_free_game(game)
		return
	if damage_done > 12:
		_fail(
			(
				"Wizard staff damage unexpectedly exceeded deterministic WIS/magic range: %d"
				% damage_done
			)
		)
		_free_test_node(defender)
		_free_game(game)
		return
	if game._hunter_focus_primed != true:
		_fail("Wizard staff attack should not consume Hunter's Focus")
		_free_test_node(defender)
		_free_game(game)
		return

	_free_test_node(defender)
	_free_game(game)
	await process_frame
	print("  wizard staff attacks use WIS magic pipeline without consuming Hunter's Focus")
