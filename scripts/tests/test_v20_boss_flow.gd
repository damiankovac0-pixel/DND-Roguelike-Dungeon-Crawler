## V20.0.0 boss encounter runtime flow contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_flow.gd
extends SceneTree

const BOSS_FLOOR: int = 5
const CARDINAL_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _failed: bool = false
var _game_manager: Node
var _game: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(200500)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	await process_frame
	while _game_manager.current_floor < BOSS_FLOOR:
		_game._debug_descend_deeper()
		await process_frame
	_check_boss_not_spawned_before_gate()
	if not _failed:
		await _check_gate_entry_and_rewards()
	if not _failed:
		print("V20 boss flow checks passed")
		quit(0)


func _check_boss_not_spawned_before_gate() -> void:
	var encounter: Dictionary = _game._active_boss_encounter
	_assert(not encounter.is_empty(), "no active encounter on boss floor")
	if _failed:
		return
	_assert(encounter.get("boss", null) == null, "boss should not be spawned before gate entry")
	for enemy: Node in _game._enemies:
		if _failed:
			break
		if enemy != null and enemy.enemy_data != null and enemy.enemy_data.is_boss:
			_fail("boss enemy present in _enemies before gate entry")
			break
	# Random spawn filter: is_boss enemies must not be spawnable
	for enemy_data: Resource in _game._enemy_resources:
		if _failed:
			break
		_assert(
			not enemy_data.is_boss or not _game._can_spawn_enemy(enemy_data, enemy_data.boss_floor),
			"%s can spawn as a random enemy" % enemy_data.display_name
		)


func _check_gate_entry_and_rewards() -> void:
	var encounter: Dictionary = _game._active_boss_encounter
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var entry_cell: Vector2i = encounter.get("entry_cell", Vector2i.ZERO)
	_assert(gate_cell != Vector2i.ZERO, "no gate cell in encounter")
	_assert(entry_cell != Vector2i.ZERO, "no entry cell in encounter")
	if _failed:
		return
	# Find stand cell outside the gate (boss_gate_entry_cell from generator)
	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	if gate_entry_cell == Vector2i.ZERO:
		_fail("no boss_gate_entry_cell in encounter")
		return
	# Remove all enemies to clean the slate before the boss fight
	_remove_non_boss_enemies(null)
	# Position player outside the gate
	_game._player.set_grid_position(gate_entry_cell)
	# Move onto the gate cell, triggering teleport + spawn
	var gate_dir: Vector2i = gate_cell - gate_entry_cell
	var turn_before: int = _game_manager.turn_count
	_game._attempt_player_move(gate_dir)
	await process_frame
	# Teleport: player should now be inside the arena
	_assert(
		_game._player.grid_position == entry_cell,
		"player not teleported to entry cell %s; at %s" % [entry_cell, _game._player.grid_position]
	)
	_assert(bool(encounter.get("locked", false)), "gate entry did not lock encounter")
	_assert(bool(encounter.get("entered", false)), "gate entry did not set entered flag")
	_assert(
		_game_manager.turn_count == turn_before + 1, "gate entry should consume exactly one turn"
	)
	# Lazy spawn: boss should now exist
	var boss: Node = encounter.get("boss", null)
	_assert(boss != null, "boss not spawned after gate entry")
	_assert(boss.is_alive(), "boss not alive after spawn")
	if _failed:
		return
	# Check sealed doors, boss banner, music
	_check_sealed_boss_presentation()
	if _failed:
		return
	# Check telegraph queue + resolve
	_check_boss_telegraph_damage(boss)
	if _failed:
		return
	# Check defeat rewards
	await _check_boss_defeat_rewards(boss)


func _remove_non_boss_enemies(boss: Node) -> void:
	for enemy: Node in _game._enemies.duplicate():
		if enemy != boss:
			_game._enemies.erase(enemy)
			_game_manager.remove_enemy(enemy)
			enemy.queue_free()


func _check_sealed_boss_presentation() -> void:
	for boss_door: Vector2i in _game._active_boss_encounter.get("door_cells", []):
		if _failed:
			break
		_assert(
			(
				_game_manager.map_data[boss_door.y][boss_door.x]
				== _game.DungeonDataScript.TileType.SEALED_BOSS_DOOR
			),
			"boss door did not seal at %s" % boss_door
		)
	_assert(_game.hud.boss_banner.visible, "boss banner did not become visible")
	_assert(_game.sensory_feedback.is_boss_music_playing(), "boss music did not start")


func _check_boss_telegraph_damage(boss: Node) -> void:
	var attack: Resource = boss.enemy_data.boss_attacks[0]
	var player_pos: Vector2i = _game._player.grid_position
	var hp_before_queue: int = _game._player.stats_component.current_hp
	_game._queue_boss_attack(boss, attack, {player_pos: true})
	_assert(
		not _game._build_boss_telegraph_payload().is_empty(),
		"queued boss attack did not expose telegraph payload"
	)
	_assert(
		_game._player.stats_component.current_hp == hp_before_queue,
		"boss telegraph damaged player on queue turn"
	)
	# Evade — move player out of telegraph cell
	_game._player.set_grid_position(player_pos + Vector2i.RIGHT)
	_game._process_boss_turn(boss, 1.0, 99, {})
	_assert(
		_game._player.stats_component.current_hp == hp_before_queue,
		"evading boss telegraph should preserve HP"
	)
	# Stand in telegraph on resolve
	_game._queue_boss_attack(boss, attack, {_game._player.grid_position: true})
	_game._process_boss_turn(boss, 1.0, 100, {})
	_assert(
		_game._player.stats_component.current_hp < hp_before_queue,
		"standing in boss telegraph should take damage on resolve"
	)


func _check_boss_defeat_rewards(boss: Node) -> void:
	var gold_before: int = _game._player.stats_component.gold
	boss.stats_component.apply_damage(99999)
	await process_frame
	_assert(
		bool(_game._active_boss_encounter.get("defeated", false)),
		"boss defeat did not mark encounter defeated"
	)
	var stairs: Vector2i = _game._active_boss_encounter.get("stairs_cell")
	_assert(
		_game_manager.map_data[stairs.y][stairs.x] == _game.DungeonDataScript.TileType.STAIRS_DOWN,
		"boss defeat did not reveal stairs"
	)
	var room_cells: Dictionary = _game._active_boss_encounter.get("room_cells", {})
	var chest_in_boss_room: bool = false
	for placed_cell: Vector2i in _game._container_positions:
		if room_cells.has(placed_cell):
			chest_in_boss_room = true
			break
	_assert(chest_in_boss_room, "boss defeat did not create a chest inside the boss room")
	_assert(
		not _game.sensory_feedback.is_boss_music_playing(), "boss music did not stop after defeat"
	)
	_assert(
		_game._player.stats_component.gold == gold_before + boss.enemy_data.boss_reward_gold,
		"boss gold reward should not include normal enemy gold"
	)


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
