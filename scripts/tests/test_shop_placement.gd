## Permanent test harness for shop placement on floors 1-3.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_shop_placement.gd
##
## Verifies that every generated floor produces a valid shopkeeper and
## non-empty shop stock across multiple deterministic seeds.  This catches
## the closed-door connectivity regression where `_keeps_floor_connected`
## used a walkability check that excluded DOOR tiles, causing the BFS to
## fail on maps with closed doors.
extends SceneTree

const SEEDS: Array[int] = [100, 200, 300, 400, 500]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return

	for current_seed: int in SEEDS:
		seed(current_seed)
		game_manager.abandon_run()
		await process_frame
		game_manager.prepare_character("debug", {})

		var game: Node = game_scene.instantiate()
		root.add_child(game)
		await process_frame

		# Floor 1 is generated during _ready
		_check_shop(game, current_seed, 1)

		# Descend to floor 2
		game._debug_descend_deeper()
		await process_frame
		_check_shop(game, current_seed, 2)

		# Descend to floor 3
		game._debug_descend_deeper()
		await process_frame
		_check_shop(game, current_seed, 3)

		game.queue_free()
		await process_frame

	print("shop placement check passed across %d seeds" % SEEDS.size())
	quit(0)


func _check_shop(game: Node, seed_value: int, floor_number: int) -> void:
	if game._shopkeeper == null or not is_instance_valid(game._shopkeeper):
		_fail(
			"seed %d floor %d: no shopkeeper" % [seed_value, floor_number]
		)
		return
	if game._shop_stock.is_empty():
		_fail(
			"seed %d floor %d: empty shop stock" % [seed_value, floor_number]
		)
		return


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
