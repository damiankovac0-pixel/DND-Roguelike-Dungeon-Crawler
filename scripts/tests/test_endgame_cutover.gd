## Endgame cutover test for V10.2.0.
##
## Verifies that every-three-floor extraction is gone, that floor 25 presents the
## victory choice, and that the Endless Deeps continue past floor 25 until death.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_endgame_cutover.gd
extends SceneTree

const FINAL_VICTORY_FLOOR_REFERENCE: int = 25

var _failed: bool = false
var _game_manager: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(717171)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return
	_game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	await _check_extraction_removed_on_floor_three(game)
	if _failed:
		return
	await _descend_to_victory_floor(game)
	if _failed:
		return
	await _check_victory_choice_presented(game)
	if _failed:
		return
	await _check_endless_descent_after_choice(game)
	if _failed:
		return
	print("endgame cutover check passed")
	quit(0)


func _check_extraction_removed_on_floor_three(game: Node) -> void:
	game.extraction_panel.visible = false
	_game_manager.current_floor = 3
	game._reach_stairs()
	await process_frame
	if game.extraction_panel.visible:
		_fail(
			"extraction panel appeared on floor 3; every-three-floor extraction should be removed"
		)
		return
	if _game_manager.current_floor != 4:
		_fail("expected floor 4 after stairs on floor 3, got %d" % _game_manager.current_floor)
		return


func _descend_to_victory_floor(game: Node) -> void:
	while _game_manager.current_floor < FINAL_VICTORY_FLOOR_REFERENCE:
		game._debug_descend_deeper()
		await process_frame
	if _game_manager.current_floor != FINAL_VICTORY_FLOOR_REFERENCE:
		_fail(
			(
				"debug descent landed on floor %d, expected %d"
				% [_game_manager.current_floor, FINAL_VICTORY_FLOOR_REFERENCE]
			)
		)


func _check_victory_choice_presented(game: Node) -> void:
	game.extraction_panel.visible = false
	game._reach_stairs()
	await process_frame
	if not game.extraction_panel.visible:
		_fail("victory choice panel did not appear on floor 25")
		return
	if game.leave_button.text != "Leave Victorious":
		_fail("leave button text is %s, expected Leave Victorious" % game.leave_button.text)
		return
	if game.descend_button.text != "Delve Forever":
		_fail("descend button text is %s, expected Delve Forever" % game.descend_button.text)
		return


func _check_endless_descent_after_choice(game: Node) -> void:
	game._on_descend_deeper()
	await process_frame
	if game.extraction_panel.visible:
		_fail("extraction panel stayed visible after choosing to delve forever")
		return
	if _game_manager.current_floor != FINAL_VICTORY_FLOOR_REFERENCE + 1:
		_fail(
			(
				"expected floor %d after endless delve choice, got %d"
				% [FINAL_VICTORY_FLOOR_REFERENCE + 1, _game_manager.current_floor]
			)
		)
		return
	game.extraction_panel.visible = false
	game._reach_stairs()
	await process_frame
	if game.extraction_panel.visible:
		_fail("victory choice reappeared past floor 25 during endless descent")
		return


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
