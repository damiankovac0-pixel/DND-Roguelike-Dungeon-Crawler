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
	_game = _instantiate_game()
	root.add_child(_game)
	await process_frame
	while _game_manager.current_floor < BOSS_FLOOR:
		_game._debug_descend_deeper()
		await process_frame
	_check_boss_not_spawned_before_gate()
	if not _failed:
		await _check_gate_entry_and_rewards()
	if not _failed:
		await _check_fail_open_no_spawn()
	if not _failed:
		await _check_stale_reveal_cancellation()
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
	# Keep one normal dungeon enemy long enough to prove arena-context suspension.
	var suspended_enemy: Node = null
	for candidate: Node in _game._enemies:
		if candidate != null and candidate.is_alive() and not candidate.enemy_data.is_boss:
			suspended_enemy = candidate
			break
	# Position player outside the gate
	_game._player.set_grid_position(gate_entry_cell)
	# Move onto the gate cell, triggering teleport + arena reveal only.
	var gate_dir: Vector2i = gate_cell - gate_entry_cell
	var turn_before: int = _game_manager.turn_count
	_game._attempt_player_move(gate_dir)
	await process_frame
	# Teleport: player should now be inside the arena.
	_assert(
		_game._player.grid_position == entry_cell,
		"player not teleported to entry cell %s; at %s" % [entry_cell, _game._player.grid_position]
	)
	_assert(bool(encounter.get("locked", false)), "gate entry did not lock encounter")
	_assert(bool(encounter.get("entered", false)), "gate entry did not set entered flag")
	_assert(
		encounter.get("state", &"") == _game.BOSS_ARENA_STATE_REVEAL,
		"gate entry should enter arena_reveal state"
	)
	_assert(encounter.get("boss", null) == null, "boss should not spawn during arena reveal")
	_assert(_live_boss_count(_game) == 0, "no live boss should exist during arena reveal")
	_assert(_game_manager.turn_count == turn_before, "arena reveal should not consume a turn")
	_assert(not _game.sensory_feedback.is_boss_music_playing(), "boss music started during reveal")
	_assert(not _game.hud.boss_name_label.visible, "boss health appeared during reveal")
	_assert(_game._boss_telegraphs.is_empty(), "reveal should not create boss telegraphs")
	_assert(_game._boss_hazards.is_empty(), "reveal should not create boss hazards")
	_assert(_game.map_view._projectile_trails.is_empty(), "reveal should not create projectiles")
	var arena_view: Dictionary = encounter.get("boss_arena_view_cells", {})
	_assert(not arena_view.is_empty(), "arena reveal should expose arena view metadata")
	for explored_cell: Vector2i in _game._explored_cells:
		_assert(
			arena_view.has(explored_cell),
			"reveal exploration leaked dungeon cell %s" % explored_cell
		)
	if suspended_enemy != null:
		var suspended_position: Vector2i = suspended_enemy.grid_position
		var suspended_actions: int = int(_game._enemy_action_counts.get(suspended_enemy, 0))
		_assert(
			_game._should_skip_enemy_for_boss_arena(suspended_enemy), "dungeon enemy not suspended"
		)
		_game._process_enemy_turns()
		_assert(
			suspended_enemy.grid_position == suspended_position,
			"suspended enemy moved during reveal"
		)
		_assert(
			int(_game._enemy_action_counts.get(suspended_enemy, 0)) == suspended_actions,
			"suspended enemy consumed an action during reveal"
		)
	_remove_non_boss_enemies(null)
	if _failed:
		return
	_assert(_game.complete_boss_arena_reveal(), "boss arena reveal completion failed")
	await process_frame
	_assert(
		encounter.get("state", &"") == _game.BOSS_ARENA_STATE_ACTIVE,
		"completed boss reveal should enter active state"
	)
	_assert(
		_game_manager.turn_count == turn_before + 1,
		"boss activation should consume exactly one turn"
	)
	# Lazy spawn: boss should now exist.
	var boss: Node = encounter.get("boss", null)
	_assert(boss != null, "boss not spawned after arena reveal completion")
	_assert(boss.is_alive(), "boss not alive after spawn")
	_assert(_live_boss_count(_game) == 1, "arena reveal completion should spawn exactly one boss")
	var active_turn: int = _game_manager.turn_count
	_assert(not _game.complete_boss_arena_reveal(), "repeated reveal completion should be a no-op")
	_assert(encounter.get("boss", null) == boss, "repeated reveal completion replaced the boss")
	_assert(_game_manager.turn_count == active_turn, "repeated reveal completion advanced the turn")
	if _failed:
		return
	# Check sealed doors, boss sidebar HUD, music
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


func _live_boss_count(game: Node) -> int:
	var count: int = 0
	for enemy: Node in game._enemies:
		if (
			enemy != null
			and enemy.enemy_data != null
			and enemy.enemy_data.is_boss
			and enemy.is_alive()
		):
			count += 1
	return count


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
	_assert(_game.hud.boss_name_label.visible, "boss sidebar name did not become visible")
	_assert(_game.hud.boss_hp_label.visible, "boss sidebar HP did not become visible")
	_assert(not _game.hud.boss_banner.visible, "boss banner should stay hidden in sidebar HUD mode")
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


func _check_fail_open_no_spawn() -> void:
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	var fail_game: Node = _instantiate_game()
	root.add_child(fail_game)
	await process_frame
	fail_game._generate_floor(BOSS_FLOOR)
	await process_frame
	var encounter: Dictionary = fail_game._active_boss_encounter
	_assert(not encounter.is_empty(), "fail-open: no active encounter on boss floor")
	if _failed:
		fail_game.queue_free()
		await process_frame
		return
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	_assert(gate_cell != Vector2i.ZERO, "fail-open: no gate cell in encounter")
	_assert(gate_entry_cell != Vector2i.ZERO, "fail-open: no gate entry cell in encounter")
	if _failed:
		fail_game.queue_free()
		await process_frame
		return
	# Remove all enemies
	for enemy: Node in fail_game._enemies.duplicate():
		fail_game._enemies.erase(enemy)
		_game_manager.remove_enemy(enemy)
		enemy.queue_free()
	# Position player outside the gate
	fail_game._player.set_grid_position(gate_entry_cell)
	# Record state before gate entry
	var turn_before: int = _game_manager.turn_count
	var gold_before: int = fail_game._player.stats_component.gold
	var container_count_before: int = fail_game._container_positions.size()
	var room_cells: Dictionary = encounter.get("room_cells", {})
	var boss_room_containers_before: int = 0
	for cell: Vector2i in fail_game._container_positions:
		if room_cells.has(cell):
			boss_room_containers_before += 1
	# Sabotage boss spawn
	encounter["boss_data"] = null
	# Step onto the gate cell: fail-open is evaluated only when reveal completion runs.
	var gate_dir: Vector2i = gate_cell - gate_entry_cell
	fail_game._attempt_player_move(gate_dir)
	await process_frame
	_assert(bool(encounter.get("entered", false)), "fail-open reveal should set entered=true")
	_assert(bool(encounter.get("locked", false)), "fail-open reveal should set locked=true")
	_assert(
		encounter.get("state", &"") == fail_game.BOSS_ARENA_STATE_REVEAL,
		"fail-open gate entry should enter arena_reveal state"
	)
	_assert(encounter.get("boss", null) == null, "fail-open reveal should not spawn a boss")
	_assert(_live_boss_count(fail_game) == 0, "fail-open reveal should have no live boss")
	_assert(_game_manager.turn_count == turn_before, "fail-open reveal should not consume a turn")
	# Complete reveal with sabotaged boss data, asserting fail-open state.
	_assert(
		not fail_game.complete_boss_arena_reveal(), "fail-open completion should report failure"
	)
	await process_frame
	_assert(bool(encounter.get("entered", false)), "fail-open should keep entered=true")
	_assert(bool(encounter.get("defeated", false)), "fail-open should set defeated=true")
	_assert(not bool(encounter.get("locked", true)), "fail-open should set locked=false")
	if _failed:
		fail_game.queue_free()
		await process_frame
		return
	# Assert all door tiles changed to OPEN_DOOR
	for door_cell: Vector2i in encounter.get("door_cells", []):
		if fail_game._is_inside_map(door_cell):
			_assert(
				(
					_game_manager.map_data[door_cell.y][door_cell.x]
					== fail_game.DungeonDataScript.TileType.OPEN_DOOR
				),
				"fail-open should open boss door at %s" % door_cell
			)
	# Assert stairs tile is STAIRS_DOWN
	var stairs_cell: Vector2i = encounter.get("stairs_cell", fail_game._stairs_position)
	_assert(
		(
			_game_manager.map_data[stairs_cell.y][stairs_cell.x]
			== fail_game.DungeonDataScript.TileType.STAIRS_DOWN
		),
		"fail-open should reveal stairs tile"
	)
	# Assert no turn consumed
	_assert(_game_manager.turn_count == turn_before, "fail-open should not consume a turn")
	# Assert no gold reward
	_assert(
		fail_game._player.stats_component.gold == gold_before, "fail-open should not grant gold"
	)
	# Assert no containers added
	_assert(
		fail_game._container_positions.size() == container_count_before,
		"fail-open should not add containers"
	)
	var boss_room_containers_after: int = 0
	for cell: Vector2i in fail_game._container_positions:
		if room_cells.has(cell):
			boss_room_containers_after += 1
	_assert(
		boss_room_containers_after == boss_room_containers_before,
		"fail-open should not add boss-room containers"
	)
	if _failed:
		fail_game.queue_free()
		await process_frame
		return
	# _reach_stairs should advance to floor 6 because encounter is marked defeated
	fail_game._reach_stairs()
	await process_frame
	_assert(
		_game_manager.current_floor == BOSS_FLOOR + 1,
		(
			"fail-open _reach_stairs should advance to floor %d, got %d"
			% [BOSS_FLOOR + 1, _game_manager.current_floor]
		)
	)
	fail_game.queue_free()
	await process_frame


func _check_stale_reveal_cancellation() -> void:
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	var stale_game: Node = _instantiate_game()
	root.add_child(stale_game)
	await process_frame
	stale_game._generate_floor(BOSS_FLOOR)
	await process_frame
	var encounter: Dictionary = stale_game._active_boss_encounter
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var gate_entry: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	stale_game._player.set_grid_position(gate_entry)
	stale_game._attempt_player_move(gate_cell - gate_entry)
	await process_frame
	_assert(
		encounter.get("state", &"") == stale_game.BOSS_ARENA_STATE_REVEAL,
		"stale-cancel setup did not enter arena_reveal"
	)
	stale_game._generate_floor(BOSS_FLOOR + 1)
	await process_frame
	var turn_before_callback: int = _game_manager.turn_count
	stale_game._on_boss_activation_timeout()
	await process_frame
	_assert(not stale_game.complete_boss_arena_reveal(), "old reveal completed after floor change")
	_assert(
		_game_manager.turn_count == turn_before_callback, "stale reveal callback advanced the turn"
	)
	for enemy: Node in stale_game._enemies:
		_assert(
			enemy == null or enemy.enemy_data == null or not enemy.enemy_data.is_boss,
			"stale reveal callback spawned a boss on a normal floor"
		)
	stale_game.queue_free()
	await process_frame


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	return game_scene.instantiate()


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
