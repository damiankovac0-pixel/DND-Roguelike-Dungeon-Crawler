## Headless test for V12.2.0 gear set bonuses.
##
## Contracts:
##   1. Guardian/Siphon set resources load and are registered for web export.
##   2. Two equipped Guardian pieces reduce incoming damage by 10%.
##   3. One set piece does not activate the set bonus.
##   4. Active Siphon-style proc bonuses expose chance/heal data and can heal after damage.
## Run:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v12_2_gear_sets.gd
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const ResourcePathsScript = preload("res://scripts/resource_paths.gd")

const GUARDIAN_MAIL_PATH: String = "res://resources/items/guardian_mail.tres"
const GUARDIAN_CHARM_PATH: String = "res://resources/items/guardian_charm.tres"
const SIPHON_RAPIER_PATH: String = "res://resources/items/siphon_rapier.tres"
const SIPHON_RING_PATH: String = "res://resources/items/siphon_ring.tres"

var _actor_script: GDScript
var _stats_script: GDScript
var _inventory_script: GDScript
var _game_script: GDScript
var _guardian_mail: Resource
var _guardian_charm: Resource
var _siphon_rapier: Resource
var _siphon_ring: Resource
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_actor_script = load("res://scripts/entities/actor.gd")
	_stats_script = load("res://scripts/components/stats_component.gd")
	_inventory_script = load("res://scripts/components/inventory_component.gd")
	_game_script = load("res://scripts/game.gd")
	_load_set_resources()

	_check_resource_contracts()
	if not _failed:
		_check_guardian_resistance()
	if not _failed:
		_check_single_piece_no_resistance()
	if not _failed:
		_check_siphon_proc_helpers()
	if not _failed:
		_check_set_proc_heals()

	if not _failed:
		print("V12.2.0 gear set checks passed")
		quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _load_set_resources() -> void:
	_guardian_mail = load(GUARDIAN_MAIL_PATH)
	_guardian_charm = load(GUARDIAN_CHARM_PATH)
	_siphon_rapier = load(SIPHON_RAPIER_PATH)
	_siphon_ring = load(SIPHON_RING_PATH)


func _make_player() -> Node2D:
	var player: Node2D = _actor_script.new()
	player.display_name = "SetTester"
	player.grid_position = Vector2i(5, 5)
	var stats: Node = _stats_script.new()
	stats.name = "StatsComponent"
	stats.max_hp = 100
	stats.current_hp = 100
	stats.level = 10
	stats.strength = 10
	stats.dexterity = 10
	stats.constitution = 10
	stats.intelligence = 10
	stats.wisdom = 10
	stats.charisma = 10
	stats.proficiency_bonus = 2
	stats.base_armor_class = 10
	player.add_child(stats)
	player.stats_component = stats
	var inv: Node = _inventory_script.new()
	inv.name = "InventoryComponent"
	player.add_child(inv)
	player.inventory_component = inv
	stats.inventory_component = inv
	return player


func _free_test_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


func _check_resource_contracts() -> void:
	var message: String = ""
	if _guardian_mail == null or _guardian_charm == null:
		message = "Guardian set resources failed to load"
	elif _siphon_rapier == null or _siphon_ring == null:
		message = "Siphon set resources failed to load"
	elif not _registered_set_paths():
		message = "ResourcePaths must register gear set resources"
	elif _guardian_mail.set_id != &"guardian" or _guardian_charm.set_id != &"guardian":
		message = "Guardian set pieces must share set_id"
	elif _guardian_mail.set_damage_resist_percent != 10:
		message = "Guardian set must define 10% damage resistance"
	elif _siphon_rapier.set_id != &"siphon" or _siphon_ring.set_id != &"siphon":
		message = "Siphon set pieces must share set_id"
	elif _siphon_ring.set_proc_chance_percent != 20 or _siphon_ring.set_proc_heal_percent != 6:
		message = "Siphon set must define 20% proc / 6% heal"

	if not message.is_empty():
		_fail(message)
	else:
		print("  gear set resources load and are registered")


func _registered_set_paths() -> bool:
	for path: String in [
		GUARDIAN_MAIL_PATH,
		GUARDIAN_CHARM_PATH,
		SIPHON_RAPIER_PATH,
		SIPHON_RING_PATH,
	]:
		if not ResourcePathsScript.ITEM_PATHS.has(path):
			return false
	return true


func _check_guardian_resistance() -> void:
	var player: Node2D = _make_player()
	var inv: Node = player.inventory_component
	inv.equipped_armor = _guardian_mail
	inv.equipped_accessory_1 = _guardian_charm

	var applied: int = player.stats_component.apply_damage(20)
	if applied != 18:
		_fail("Guardian 10% resistance should reduce 20 damage to 18, got %d" % applied)
		_free_test_node(player)
		return
	if player.stats_component.current_hp != 82:
		_fail("Guardian resistance HP expected 82, got %d" % player.stats_component.current_hp)
		_free_test_node(player)
		return

	_free_test_node(player)
	print("  Guardian two-piece set reduces incoming damage by 10%")


func _check_single_piece_no_resistance() -> void:
	var player: Node2D = _make_player()
	player.inventory_component.equipped_armor = _guardian_mail

	var applied: int = player.stats_component.apply_damage(20)
	if applied != 20:
		_fail("One Guardian piece should not reduce damage, got %d" % applied)
		_free_test_node(player)
		return

	_free_test_node(player)
	print("  one set piece does not activate set bonuses")


func _check_siphon_proc_helpers() -> void:
	var player: Node2D = _make_player()
	var inv: Node = player.inventory_component
	inv.equipped_melee_weapon = _siphon_rapier
	inv.equipped_weapon = _siphon_rapier
	inv.equipped_accessory_1 = _siphon_ring

	if inv._get_set_proc_chance_percent() != 20:
		_fail("Siphon proc chance expected 20, got %d" % inv._get_set_proc_chance_percent())
		_free_test_node(player)
		return
	if inv._get_set_proc_heal_percent() != 6:
		_fail("Siphon heal percent expected 6, got %d" % inv._get_set_proc_heal_percent())
		_free_test_node(player)
		return
	if inv._get_set_proc_display_name() != "Siphon Set":
		_fail(
			"Siphon display name expected 'Siphon Set', got %s" % inv._get_set_proc_display_name()
		)
		_free_test_node(player)
		return

	_free_test_node(player)
	print("  Siphon set exposes proc chance/heal helpers")


func _check_set_proc_heals() -> void:
	var player: Node2D = _make_player()
	var inv: Node = player.inventory_component
	var first: Resource = ItemDataScript.new()
	first.kind = ItemDataScript.ItemKind.ACCESSORY
	first.display_name = "Test Sigil A"
	first.set_id = &"test_siphon"
	first.set_display_name = "Test Siphon"
	first.set_proc_chance_percent = 100
	first.set_proc_heal_percent = 10
	var second: Resource = first.duplicate(true)
	second.display_name = "Test Sigil B"
	inv.equipped_accessory_1 = first
	inv.equipped_accessory_2 = second
	player.stats_component.current_hp = 50

	var game: Node = _game_script.new()
	game._player = player
	game._try_apply_player_set_proc()
	if player.stats_component.current_hp != 60:
		_fail("100% set proc should heal 10 HP, got %d" % player.stats_component.current_hp)
		game.free()
		_free_test_node(player)
		return

	game.free()
	_free_test_node(player)
	print("  after-damage set proc can heal the player")
