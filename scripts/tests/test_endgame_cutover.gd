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
	game._generate_floor(FINAL_VICTORY_FLOOR_REFERENCE)
	await process_frame
	if _failed:
		return
	await _check_victory_choice_gated_by_final_boss(game)
	if _failed:
		return
	await _check_endless_descent_after_choice(game)
	if _failed:
		return
	if not _failed:
		await _check_nyxara_fail_open_final_choice()
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


func _check_victory_choice_gated_by_final_boss(game: Node) -> void:
	game.extraction_panel.visible = false
	game._reach_stairs()
	await process_frame
	if game.extraction_panel.visible:
		_fail("victory choice panel appeared before the floor 25 boss died")
		return
	# Active boss encounter metadata exists before gate entry
	var encounter: Dictionary = game._active_boss_encounter
	if encounter.is_empty():
		_fail("no active boss encounter on floor 25")
		return
	if encounter.get("boss_id", &"") != &"nyxara":
		_fail("floor 25 boss encounter should be Nyxara, got %s" % encounter.get("boss_id", &""))
		return
	# Boss is not yet spawned lazy before gate entry
	if encounter.get("boss") != null:
		_fail("boss should not be spawned before gate entry")
		return
	# Enter boss gate to trigger lazy spawn
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	if gate_cell == Vector2i.ZERO or gate_entry_cell == Vector2i.ZERO:
		_fail("boss encounter missing gate cell or gate entry cell")
		return
	game._player.set_grid_position(gate_entry_cell)
	var gate_dir: Vector2i = gate_cell - gate_entry_cell
	game._attempt_player_move(gate_dir)
	await process_frame
	# Lazy-spawned boss should now exist
	var boss: Node = encounter.get("boss")
	if boss == null or not boss.is_alive():
		_fail("Nyxara not spawned after gate entry")
		return
	if boss.display_name != "Nyxara, the Mirror Witch":
		_fail("spawned boss is %s, expected Nyxara, the Mirror Witch" % boss.display_name)
		return
	# Kill the boss to unlock victory
	boss.stats_component.apply_damage(99999)
	await process_frame
	game._reach_stairs()
	await process_frame
	if not game.extraction_panel.visible:
		_fail("victory choice panel did not appear after floor 25 boss defeat")
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


func _check_nyxara_fail_open_final_choice() -> void:
	_game_manager.prepare_character("debug", {})
	var nyx_game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(nyx_game)
	await process_frame
	nyx_game._generate_floor(FINAL_VICTORY_FLOOR_REFERENCE)
	await process_frame
	var encounter: Dictionary = nyx_game._active_boss_encounter
	if encounter.is_empty():
		_fail("Nyxara fail-open: no active encounter on floor 25")
		return
	if encounter.get("boss_id", &"") != &"nyxara":
		_fail("Nyxara fail-open: boss_id should be nyxara, got %s" % encounter.get("boss_id", &""))
		return
	# Pre-gate victory gating: _reach_stairs must not show the panel before boss is defeated
	nyx_game.extraction_panel.visible = false
	nyx_game._reach_stairs()
	await process_frame
	if nyx_game.extraction_panel.visible:
		_fail("Nyxara fail-open: victory panel appeared before fail-open")
		nyx_game.queue_free()
		await process_frame
		return
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	if gate_cell == Vector2i.ZERO or gate_entry_cell == Vector2i.ZERO:
		_fail("Nyxara fail-open: missing gate cell or gate entry cell")
		nyx_game.queue_free()
		await process_frame
		return
	# Remove non-boss enemies
	for enemy: Node in nyx_game._enemies.duplicate():
		nyx_game._enemies.erase(enemy)
		_game_manager.remove_enemy(enemy)
		enemy.queue_free()
	nyx_game._player.set_grid_position(gate_entry_cell)
	# Record state before gate entry
	var turn_before: int = _game_manager.turn_count
	var gold_before: int = nyx_game._player.stats_component.gold
	var container_count_before: int = nyx_game._container_positions.size()
	var room_cells: Dictionary = encounter.get("room_cells", {})
	var boss_room_containers_before: int = 0
	for cell: Vector2i in nyx_game._container_positions:
		if room_cells.has(cell):
			boss_room_containers_before += 1
	# Sabotage boss spawn
	encounter["boss_data"] = null
	# Step onto the gate cell
	var gate_dir: Vector2i = gate_cell - gate_entry_cell
	nyx_game._attempt_player_move(gate_dir)
	await process_frame
	if not bool(encounter.get("defeated", false)):
		_fail("Nyxara fail-open should set defeated=true")
		nyx_game.queue_free()
		await process_frame
		return
	if bool(encounter.get("locked", true)):
		_fail("Nyxara fail-open should set locked=false")
		nyx_game.queue_free()
		await process_frame
		return
	# Assert stairs tile is STAIRS_DOWN
	var stairs_cell: Vector2i = encounter.get("stairs_cell", nyx_game._stairs_position)
	if (
		_game_manager.map_data[stairs_cell.y][stairs_cell.x]
		!= nyx_game.DungeonDataScript.TileType.STAIRS_DOWN
	):
		_fail("Nyxara fail-open should reveal stairs tile")
		nyx_game.queue_free()
		await process_frame
		return
	# Assert no turn consumed
	if _game_manager.turn_count != turn_before:
		_fail("Nyxara fail-open should not consume a turn")
		nyx_game.queue_free()
		await process_frame
		return
	# Assert no gold reward
	if nyx_game._player.stats_component.gold != gold_before:
		_fail("Nyxara fail-open should not grant gold")
		nyx_game.queue_free()
		await process_frame
		return
	# Assert no containers added
	if nyx_game._container_positions.size() != container_count_before:
		_fail("Nyxara fail-open should not add containers")
		nyx_game.queue_free()
		await process_frame
		return
	var boss_room_containers_after: int = 0
	for cell: Vector2i in nyx_game._container_positions:
		if room_cells.has(cell):
			boss_room_containers_after += 1
	if boss_room_containers_after != boss_room_containers_before:
		_fail("Nyxara fail-open should not add boss-room containers")
		nyx_game.queue_free()
		await process_frame
		return
	# _reach_stairs should show the final choice panel because encounter is marked defeated
	nyx_game.extraction_panel.visible = false
	nyx_game._reach_stairs()
	await process_frame
	if not nyx_game.extraction_panel.visible:
		_fail("Nyxara fail-open: victory choice panel did not appear after fail-open")
		nyx_game.queue_free()
		await process_frame
		return
	if nyx_game.leave_button.text != "Leave Victorious":
		_fail(
			(
				"Nyxara fail-open: leave button text is %s, expected Leave Victorious"
				% nyx_game.leave_button.text
			)
		)
		nyx_game.queue_free()
		await process_frame
		return
	if nyx_game.descend_button.text != "Delve Forever":
		_fail(
			(
				"Nyxara fail-open: descend button text is %s, expected Delve Forever"
				% nyx_game.descend_button.text
			)
		)
		nyx_game.queue_free()
		await process_frame
		return
	nyx_game.queue_free()
	await process_frame


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
