## Focused V12.5.0 balance and clarity contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script
##   res://scripts/tests/test_v12_5_balance_clarity.gd
extends SceneTree

const FINAL_FLOOR: int = 25
const SHOP_DEAL_DISCOUNT: float = 0.85

var _gm: Node
var _game: Node
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(125000)
	_gm = root.get_node_or_null("/root/GameManager")
	if _gm == null:
		_fail("GameManager autoload missing")
		return
	_gm.prepare_character("debug", {}, _gm.CLASS_RANGER)
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	await process_frame

	_check_shop_price_helpers()
	if not _failed:
		_check_build_relevance_weights()
	if not _failed:
		_check_trap_scaling()
	if not _failed:
		await _check_final_floor_capstone()

	if not _failed:
		print("V12.5.0 balance clarity checks passed")
		quit(0)


func _check_shop_price_helpers() -> void:
	if _failed:
		return
	var item: Resource = load("res://resources/items/dagger.tres")
	var base_price: int = item.get_price()
	var charisma_fourteen_price: int = _gm._get_shop_buy_price(item, 14, 0)
	var charisma_fifteen_slot_zero: int = _gm._get_shop_buy_price(item, 15, 0)
	var charisma_fifteen_slot_one: int = _gm._get_shop_buy_price(item, 15, 1)
	var expected_normal: int = ceili(base_price * 0.90)
	var expected_deal: int = ceili(base_price * 0.90 * SHOP_DEAL_DISCOUNT)
	var expected_sell: int = floori(base_price * 0.39)
	var sell_price: int = _gm._get_shop_sell_price(item, 14)
	if charisma_fourteen_price != expected_normal:
		_fail("CHA 14 should not trigger Golden Deal; got %d" % charisma_fourteen_price)
		return
	if charisma_fifteen_slot_zero != expected_deal:
		_fail(
			(
				"CHA 15 stock slot 0 price = %d, expected %d"
				% [charisma_fifteen_slot_zero, expected_deal]
			)
		)
		return
	if charisma_fifteen_slot_one != expected_normal:
		_fail(
			(
				"CHA 15 stock slot 1 price = %d, expected %d"
				% [charisma_fifteen_slot_one, expected_normal]
			)
		)
		return
	if sell_price != expected_sell:
		_fail("CHA 14 sell price = %d, expected %d" % [sell_price, expected_sell])
		return
	print("  shop price helpers: CHA deal applies only to first stock slot")


func _check_build_relevance_weights() -> void:
	if _failed:
		return
	_gm.pending_character_class = _gm.CLASS_RANGER
	_game._player.inventory_component.items.clear()
	var ranger_bow: Resource = load("res://resources/items/eaglewood_bow.tres")
	var wizard_staff: Resource = load("res://resources/items/apprentice_staff.tres")
	var guardian_mail: Resource = load("res://resources/items/guardian_mail.tres")
	var guardian_charm: Resource = load("res://resources/items/guardian_charm.tres")
	_game._player.inventory_component.items.append(guardian_mail)
	var ranger_weight: int = _game._build_relevance_weight_percent(ranger_bow)
	var wizard_weight: int = _game._build_relevance_weight_percent(wizard_staff)
	var set_weight: int = _game._build_relevance_weight_percent(guardian_charm)
	if ranger_weight <= 100:
		_fail("Ranger class gear weight should be boosted, got %d" % ranger_weight)
		return
	if wizard_weight >= 100:
		_fail("Wrong-class wizard gear weight should be reduced, got %d" % wizard_weight)
		return
	if set_weight <= ranger_weight:
		_fail(
			"Missing set pair weight %d should exceed class weight %d" % [set_weight, ranger_weight]
		)
		return
	print("  build relevance weights: class gear boosted, wrong class reduced, set pair boosted")


func _check_trap_scaling() -> void:
	if _failed:
		return
	var base_trap: Resource = load("res://resources/traps/poison_dart_trap.tres")
	var early_trap: Resource = base_trap.duplicate(true)
	var late_trap: Resource = base_trap.duplicate(true)
	_game._scale_trap_for_floor(early_trap, 1)
	_game._scale_trap_for_floor(late_trap, FINAL_FLOOR)
	if early_trap.min_damage != base_trap.min_damage or early_trap.detect_dc != base_trap.detect_dc:
		_fail("Floor 1 trap scaling should leave base trap unchanged")
		return
	if late_trap.min_damage <= base_trap.min_damage:
		_fail("Floor 25 trap min damage did not scale up")
		return
	if late_trap.max_damage <= base_trap.max_damage:
		_fail("Floor 25 trap max damage did not scale up")
		return
	if late_trap.detect_dc <= base_trap.detect_dc:
		_fail("Floor 25 trap detect DC did not scale up")
		return
	if base_trap.max_damage != 6:
		_fail("Trap scaling mutated the poison dart template")
		return
	print("  trap scaling: floor 25 damage/DC increases without mutating templates")


func _check_final_floor_capstone() -> void:
	if _failed:
		return
	while _gm.current_floor < FINAL_FLOOR:
		_game._debug_descend_deeper()
		await process_frame
	if _gm.current_floor != FINAL_FLOOR:
		_fail("Debug descend reached floor %d, expected %d" % [_gm.current_floor, FINAL_FLOOR])
		return
	var near_dragon_count: int = 0
	var near_guard_count: int = 0
	for enemy: Node in _game._enemies:
		if enemy == null or not enemy.is_alive():
			continue
		var distance: int = max(
			abs(enemy.grid_position.x - _game._stairs_position.x),
			abs(enemy.grid_position.y - _game._stairs_position.y)
		)
		if distance > 7:
			continue
		if enemy.display_name == "Ancient Dragon":
			near_dragon_count += 1
		elif _game.FINAL_CAPSTONE_GUARD_NAMES.has(enemy.display_name):
			near_guard_count += 1
	if near_dragon_count < 1:
		_fail("Floor 25 capstone should place an Ancient Dragon near the stairs")
		return
	if near_guard_count < 1:
		_fail("Floor 25 capstone should place at least one guard near the stairs")
		return
	print("  floor 25 capstone: Ancient Dragon and guard spawn near stairs")


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
