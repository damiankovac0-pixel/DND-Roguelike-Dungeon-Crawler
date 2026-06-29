## Permanent test harness for shop floor-scaling behavior.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_shop_scaling.gd
##
## Verifies that shop stock scales with floor depth and that debug floor-skip
## correctly produces floor-appropriate stock.
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(123456)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	# Descend 9 floors via debug to reach floor 10
	for _index: int in range(9):
		game._debug_descend_deeper()
		await process_frame
	if game_manager.current_floor != 10:
		_fail("debug descend reached floor %d, expected 10" % game_manager.current_floor)
		return

	# Verify shop stock at key floor thresholds
	_check_stock(game, 2, 6, 5, ItemDataScript.ItemRarity.COMMON, true, 0)
	_check_stock(game, 10, 8, 19, ItemDataScript.ItemRarity.RARE, false, 2)
	_check_stock(game, 14, 9, 26, ItemDataScript.ItemRarity.EPIC, false, 4)
	print("shop scaling check passed")
	quit(0)


func _check_stock(
	game: Node,
	floor_number: int,
	expected_size: int,
	expected_effective_floor: int,
	expected_minimum_rarity: int,
	must_preview_future_floor: bool,
	minimum_mythic_plus: int
) -> void:
	var effective_floor: int = game._get_effective_shop_floor(floor_number)
	if effective_floor != expected_effective_floor:
		_fail(
			(
				"floor %d effective shop floor %d, expected %d"
				% [floor_number, effective_floor, expected_effective_floor]
			)
		)
		return
	if game._get_shop_minimum_rarity(floor_number) != expected_minimum_rarity:
		_fail("floor %d minimum rarity mismatch" % floor_number)
		return
	var stock: Array = game._generate_shop_stock(floor_number)
	if stock.size() != expected_size:
		_fail("floor %d stock size %d, expected %d" % [floor_number, stock.size(), expected_size])
		return
	var future_floor_items: int = 0
	var mythic_plus_items: int = 0
	for item: Resource in stock:
		if not game._can_spawn_item(item, effective_floor):
			_fail("%s cannot spawn at effective floor %d" % [item.display_name, effective_floor])
			return
		if item.min_floor > floor_number:
			future_floor_items += 1
		if item.rarity >= ItemDataScript.ItemRarity.MYTHIC:
			mythic_plus_items += 1
	if must_preview_future_floor and future_floor_items == 0:
		_fail("floor %d shop did not preview any future-floor item" % floor_number)
		return
	if mythic_plus_items < minimum_mythic_plus:
		_fail(
			(
				"floor %d shop had %d mythic+ items, expected at least %d"
				% [floor_number, mythic_plus_items, minimum_mythic_plus]
			)
		)
		return


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
