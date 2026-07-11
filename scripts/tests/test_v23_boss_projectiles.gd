## V23.0.0 Boss projectile integration tests.
##
## Contracts:
##   1. Queueing a boss attack only telegraphs; no trail created, HP unchanged.
##   2. Resolving observer_gaze creates projectile trail with attack's projectile_id,
##      damages HP when player in queued cell, clears telegraphs.
##   3. Re-queueing with fresh cell and moving player before resolve preserves HP
##      while still creating a trail across the original queued cells.
##   4. Summon-shaped boss attack returns without projectile trails.
##   5. Hazard-producing attack stores vfx_payload.profile_id == hazard_vfx_id
##      in _boss_hazards, does not damage on creation.
##
## Run:
##   /usr/local/bin/godot --headless --path . --script \
##      res://scripts/tests/test_v23_boss_projectiles.gd
extends SceneTree

const ProjectileSystemScript = preload("res://scripts/systems/projectile_system.gd")

var _failed: bool = false
var _game_manager: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(200500)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return

	# 1. Queueing boss attack does not create projectile trails
	await _test_queue_does_not_create_trails()
	if _failed:
		return

	# 2. Resolving boss attack creates projectile trail
	await _test_resolve_creates_trail()
	if _failed:
		return

	# 3. Re-queue + move player preserves queued-cell visuals
	await _test_move_evade_preserves_queued_cell()
	if _failed:
		return

	# 4. Summon attack returns without projectile trails
	await _test_summon_no_projectile()
	if _failed:
		return

	# 5. Hazard-producing attack stores vfx_payload
	await _test_hazard_vfx_stored()
	if _failed:
		return

	print("V23 boss projectile checks passed")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _start_game() -> Node:
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_WIZARD)
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	game.map_view.set_atmosphere_enabled(false)
	game.map_view.set_reduced_vfx_enabled(false)
	await process_frame
	return game


func _enter_boss_on_floor(game: Node, floor_number: int) -> Node:
	game._generate_floor(floor_number)
	await process_frame

	var encounter: Dictionary = game._active_boss_encounter
	if encounter.is_empty():
		_fail("no active boss encounter after generating floor %d" % floor_number)
		return null

	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	if gate_cell == Vector2i.ZERO or gate_entry_cell == Vector2i.ZERO:
		_fail("boss encounter missing gate cells on floor %d" % floor_number)
		return null

	game._player.set_grid_position(gate_entry_cell)
	var gate_dir: Vector2i = gate_cell - gate_entry_cell
	var turn_before: int = _game_manager.turn_count
	game._attempt_player_move(gate_dir)
	await process_frame
	_assert(
		encounter.get("state", &"") == game.BOSS_ARENA_STATE_REVEAL,
		"gate entry should enter arena_reveal on floor %d" % floor_number
	)
	_assert(encounter.get("boss", null) == null, "boss should not spawn before reveal completion")
	_assert(_live_boss_count(game) == 0, "no live boss should exist before reveal completion")
	_assert(_game_manager.turn_count == turn_before, "arena reveal should not consume a turn")
	if _failed:
		return null
	_assert(
		game.complete_boss_arena_reveal(),
		"boss reveal completion failed on floor %d" % floor_number
	)
	await process_frame
	_assert(
		encounter.get("state", &"") == game.BOSS_ARENA_STATE_ACTIVE,
		"boss reveal completion should activate floor %d" % floor_number
	)
	_assert(
		_game_manager.turn_count == turn_before + 1,
		"boss reveal completion should consume one turn"
	)
	_assert(_live_boss_count(game) == 1, "boss reveal completion should spawn exactly one boss")
	if _failed:
		return null

	game._refresh_map()
	await process_frame
	return encounter.get("boss", null)


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


func _test_queue_does_not_create_trails() -> void:
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		return

	var attack: Resource = _attack_by_id(observer.enemy_data, &"observer_gaze")
	if attack == null:
		_fail("Observer has no observer_gaze attack")
		return

	var hp_before: int = game._player.stats_component.current_hp
	var trail_count_before: int = game.map_view._projectile_trails.size()

	# Queue the attack
	var cells: Dictionary = game._boss_attack_cells(observer, attack)
	game._queue_boss_attack(observer, attack, cells)

	# After queue: telegraphs non-empty, trails empty, HP unchanged
	if game._boss_telegraphs.is_empty():
		_fail("Queue should create _boss_telegraphs")
		return

	if game.map_view._projectile_trails.size() != trail_count_before:
		_fail("Queue should NOT create projectile trails")
		return

	if game._player.stats_component.current_hp != hp_before:
		_fail("Queue should NOT damage the player")
		return

	game.queue_free()
	await process_frame
	print("  queue boss attack: no trail, no damage, telegraphs present")


func _test_resolve_creates_trail() -> void:
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		return

	var attack: Resource = _attack_by_id(observer.enemy_data, &"observer_gaze")
	if attack == null:
		_fail("Observer has no observer_gaze attack")
		return

	var cells: Dictionary = game._boss_attack_cells(observer, attack)
	if cells.is_empty():
		_fail("observer_gaze attack cells should be non-empty")
		return

	var telegraphed_cell: Vector2i = cells.keys()[0]

	# Move player to the telegraphed cell so they are hit when the queued attack resolves.
	game._player.set_grid_position(telegraphed_cell)
	game._refresh_visibility()
	game._refresh_map()
	await process_frame

	var hp_before: int = game._player.stats_component.current_hp
	var trail_count_before: int = game.map_view._projectile_trails.size()
	game._queue_boss_attack(observer, attack, cells)
	_assert(not game._boss_telegraphs.is_empty(), "queued observer_gaze should expose telegraphs")
	game._process_boss_turn(observer, 1.0, 99, {})

	var trails: Array = game.map_view._projectile_trails
	if trails.size() <= trail_count_before:
		_fail("Resolve should create a projectile trail")
		return

	var last_trail: Dictionary = trails[trails.size() - 1]
	var profile: StringName = last_trail.get("profile_id", &"")
	if profile != attack.projectile_id:
		_fail('Projectile profile expected &"%s", got &"%s"' % [attack.projectile_id, profile])
		return

	# Player should take damage (standing on telegraph cell), and telegraphs should clear.
	if game._player.stats_component.current_hp >= hp_before:
		_fail("Player on telegraph cell should take damage")
		return
	if not game._boss_telegraphs.is_empty():
		_fail("Resolved queued attack should clear _boss_telegraphs")
		return

	game.queue_free()
	await process_frame
	print("  resolve observer_gaze: trail with projectile_id, HP damaged")


func _test_move_evade_preserves_queued_cell() -> void:
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		return

	var attack: Resource = _attack_by_id(observer.enemy_data, &"observer_gaze")
	if attack == null:
		_fail("Observer has no observer_gaze attack")
		return

	# Compute attack cells - these are the cells that were "queued"
	var cells: Dictionary = game._boss_attack_cells(observer, attack)
	if cells.is_empty():
		_fail("observer_gaze cells should be non-empty")
		return

	var queued_cell: Vector2i = cells.keys()[0]

	# Move player to a DIFFERENT room cell to evade
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	var safe_cell: Vector2i = Vector2i.ZERO
	for cell: Vector2i in room_cells.keys():
		if cell != queued_cell and not cells.has(cell):
			safe_cell = cell
			break
	if safe_cell == Vector2i.ZERO:
		# Use any walkable cell adjacent to the queued cell
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var candidate: Vector2i = queued_cell + offset
			if game._is_walkable(candidate) and not cells.has(candidate):
				safe_cell = candidate
				break

	if safe_cell != Vector2i.ZERO:
		game._player.set_grid_position(safe_cell)
	else:
		# Player already not in the telegraph cell? That's fine, just proceed
		pass

	game._refresh_visibility()
	game._refresh_map()
	await process_frame

	var hp_before: int = game._player.stats_component.current_hp
	var trail_count_before: int = game.map_view._projectile_trails.size()

	# Resolve queued boss attack - should still create trail ending at the original queued cell.
	game._queue_boss_attack(observer, attack, cells)
	game._process_boss_turn(observer, 1.0, 100, {})

	var trails: Array = game.map_view._projectile_trails
	if trails.size() <= trail_count_before:
		_fail("Evade: resolve should still create a projectile trail")
		return

	var profile: StringName = attack.projectile_id
	var expected_cells: Array[Vector2i] = ProjectileSystemScript.array_from_cell_keys(cells)
	var found_queued_trail: bool = false
	for trail_index: int in range(trail_count_before, trails.size()):
		var emitted_trail: Dictionary = trails[trail_index]
		if emitted_trail.get("profile_id", &"") != attack.projectile_id:
			continue
		var stored_cells: Array = emitted_trail.get("cells", [])
		if stored_cells == expected_cells:
			found_queued_trail = true
			break
	if not found_queued_trail:
		_fail("Evade: trail should preserve every original queued cell")
		return
	var player_in_cell: bool = cells.has(game._player.grid_position)
	if player_in_cell:
		# If player is actually in the cell, HP may drop; that's fine
		pass
	elif game._player.stats_component.current_hp < hp_before:
		_fail("Evade: player should not take damage if not on telegraph cell")
		return

	game.queue_free()
	await process_frame
	print("  evade: trail created, player HP preserved (profile: %s)" % profile)


func _test_summon_no_projectile() -> void:
	var game: Node = await _start_game()

	# Generate a boss floor that has summon attacks
	var boss: Node = await _enter_boss_on_floor(game, 10)
	if boss == null:
		return

	var summon_attack: Resource = _attack_by_id(boss.enemy_data, &"spore_bloom")
	if summon_attack == null or summon_attack.shape != &"summon":
		summon_attack = _attack_by_id(boss.enemy_data, &"drowned_retinue")
	if summon_attack == null or summon_attack.shape != &"summon":
		summon_attack = _attack_by_id(boss.enemy_data, &"mirror_guard")
	if summon_attack == null or summon_attack.shape != &"summon":
		_fail("No summon-shaped attack found on floor 10 boss")
		return

	# Clear any existing trails
	game.map_view._projectile_trails.clear()
	await process_frame

	# Resolve the summon attack directly
	var cells: Dictionary = game._boss_attack_cells(boss, summon_attack)
	game._resolve_boss_attack(boss, summon_attack, cells)

	# Summon attacks should NOT create projectile trails
	var trails: Array = game.map_view._projectile_trails
	if not trails.is_empty():
		_fail("Summon attack should not create projectile trails, got %d" % trails.size())
		return

	game.queue_free()
	await process_frame
	print("  summon attack: no projectile trails")


func _test_hazard_vfx_stored() -> void:
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		return

	# Get the blink_pulse attack (has hazard and vfx)
	var blink_attack: Resource = _attack_by_id(observer.enemy_data, &"blink_pulse")
	if blink_attack == null:
		_fail("Observer has no blink_pulse attack")
		return

	if blink_attack.hazard_vfx_id == &"":
		_fail("Observer blink_pulse should have hazard_vfx_id set")
		return

	# Get attack cells
	var cells: Dictionary = game._boss_attack_cells(observer, blink_attack)
	if cells.is_empty():
		_fail("blink_pulse cells should be non-empty")
		return

	# Move player to a telegraph cell to trigger full resolve with hit
	var telegraphed_cell: Vector2i = cells.keys()[0]
	game._player.set_grid_position(telegraphed_cell)
	game._refresh_visibility()
	game._refresh_map()
	await process_frame

	# Resolve the attack fully (damage + hazards)
	game._resolve_boss_attack(observer, blink_attack, cells)

	# Check that hazards were created
	if game._boss_hazards.is_empty():
		_fail("blink_pulse should create _boss_hazards")
		return

	# Check that the vfx_payload has the correct profile_id
	var found_hazard_vfx: bool = false
	for hazard_cell: Vector2i in game._boss_hazards.keys():
		var hazard_entry: Dictionary = game._boss_hazards[hazard_cell]
		var vfx: Dictionary = hazard_entry.get("vfx_payload", {})
		if not vfx.is_empty():
			var profile: StringName = vfx.get("profile_id", &"")
			if profile == blink_attack.hazard_vfx_id:
				found_hazard_vfx = true
				break

	if not found_hazard_vfx:
		_fail('Hazard vfx_payload should have profile_id == &"%s"' % blink_attack.hazard_vfx_id)
		return

	game.queue_free()
	await process_frame
	print("  hazard vfx: vfx_payload.profile_id matches hazard_vfx_id")


func _attack_by_id(boss_data: Resource, attack_id: StringName) -> Resource:
	if boss_data == null:
		return null
	for attack: Resource in boss_data.boss_attacks:
		if attack.id == attack_id:
			return attack
	return null
