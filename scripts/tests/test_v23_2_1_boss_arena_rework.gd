## V23.2.1 boss arena rework regression coverage.
##
## Asserts arena geometry (21x19), Seraphine thorn_patch windup escape
## via _ensure_boss_telegraph_escape, effective 2-turn windup for
## damaging non-summon attacks, and dodge-to-refuge evasion resolve.
##
## Contract:
##   - Boss arenas are exactly 21x19.
##   - Gates render G dormant and X sealed.
##   - Bosses remain at their spawn anchor.
##   - Damaging non-summon attacks use an effective windup of at
##     least 2 even when resource data is lower.
##   - Telegraph snapshots threaten the player's current cell but
##     expose a deterministic legal cardinal refuge whenever all
##     legal neighbors would otherwise be threatened.
##   - Moving to that refuge before the second enemy turn evades
##     resolution.
##   - Boss art and telegraph/hazard glyph fields are printable
##     ASCII.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v23_2_1_boss_arena_rework.gd
extends SceneTree

const CARDINAL_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const SERAPHINE_BOSS_FLOOR: int = 10
const EXPECTED_ARENA_SIZE: Vector2i = Vector2i(21, 19)

var _failed: bool = false
var _game_manager: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(232021)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_WIZARD)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.map_view.set_atmosphere_enabled(false)
	game.map_view.set_reduced_vfx_enabled(false)
	await process_frame

	if not _failed:
		await _test_arena_dodge_refuge(game)

	if _failed:
		return
	print("V23.2.1 boss arena rework checks passed")
	quit(0)


# ═══════════════════════════════════════════════════════════════════
# Main test
# ═══════════════════════════════════════════════════════════════════


func _test_arena_dodge_refuge(game: Node) -> void:
	## Start a boss encounter on floor 10 (Seraphine), verify arena
	## geometry, queue spore_burst centered on the player, assert
	## effective 2-turn windup, detect the refuge guaranteed by
	## _ensure_boss_telegraph_escape, move there, and step through
	## both telegraph turns without taking damage.

	# ── Enter boss arena ──
	var seraphine: Node = await _enter_boss_on_floor(game, SERAPHINE_BOSS_FLOOR)
	if seraphine == null:
		return

	var encounter: Dictionary = game._active_boss_encounter
	var room_cells: Dictionary = encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "boss arena has no room cells")
	if _failed:
		return

	# ── 1. Arena is exactly 21 x 19 ──
	var arena_rect: Rect2i = encounter.get("room", Rect2i())
	_assert(
		arena_rect.size == EXPECTED_ARENA_SIZE,
		"boss arena size = %s, expected %s" % [arena_rect.size, EXPECTED_ARENA_SIZE]
	)
	if _failed:
		return

	# ── 2. Gate tile G (BOSS_DOOR) before entry, X (SEALED_BOSS_DOOR) after ──
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var dun_data = preload("res://scripts/dungeon/dungeon_data.gd")
	# After full reveal + lock the gate should be sealed
	var tile: int = _game_manager.map_data[gate_cell.y][gate_cell.x]
	_assert(
		tile == dun_data.TileType.SEALED_BOSS_DOOR,
		"gate cell %s should be SEALED_BOSS_DOOR after reveal, got tile %d" % [gate_cell, tile]
	)
	if _failed:
		return

	# ── 3. Boss stays at spawn anchor ──
	var spawn_anchor: Vector2i = encounter.get("spawn_cell", Vector2i.ZERO)
	_assert(spawn_anchor != Vector2i.ZERO, "boss spawn anchor is zero")
	if _failed:
		return
	var boss_pos: Vector2i = seraphine.grid_position
	_assert(
		boss_pos == spawn_anchor,
		"Seraphine spawned at %s, expected anchor %s" % [boss_pos, spawn_anchor]
	)
	if _failed:
		return

	# ── 4. Get spore_burst and queue it ──
	var spore_burst: Resource = _attack_by_id(seraphine.enemy_data, &"spore_burst")
	_assert(spore_burst != null, "spore_burst not found on Seraphine")
	if _failed:
		return

	var player_pos: Vector2i = game._player.grid_position
	var cells: Dictionary = game._boss_attack_cells(seraphine, spore_burst)
	_assert(not cells.is_empty(), "spore_burst should produce non-empty attack cells")
	if _failed:
		return

	# thorn_patch (radius=2) centered on player must threaten player cell
	_assert(cells.has(player_pos), "thorn_patch should threaten player cell %s" % player_pos)
	if _failed:
		return

	var hp_before: int = game._player.stats_component.current_hp
	game._queue_boss_attack(seraphine, spore_burst, cells)

	# ── 5. Effective windup = 2 (damaging non-summon enforces >= 2) ──
	var state: Dictionary = game._boss_state_for(seraphine)
	var telegraph_turns: int = int(state.get("telegraph_turns", 0))
	var effective_windup: int = int(state.get("effective_windup", 0))
	_assert(telegraph_turns == 2, "state telegraph_turns = %d, expected 2" % telegraph_turns)
	if _failed:
		return
	_assert(effective_windup == 2, "state effective_windup = %d, expected 2" % effective_windup)
	if _failed:
		return

	# ── 6. Every telegraph cell payload reports 2 turns ──
	_assert(not game._boss_telegraphs.is_empty(), "no telegraph entries after queueing attack")
	if _failed:
		return
	var all_report_two: bool = true
	for cell: Vector2i in game._boss_telegraphs:
		var payload: Dictionary = game._boss_telegraphs[cell]
		if int(payload.get("turns_remaining", 0)) != 2:
			all_report_two = false
			break
		if int(payload.get("telegraph_turns", 0)) != 2:
			all_report_two = false
			break
	_assert(
		all_report_two,
		"every telegraph entry should report turns_remaining=2 and telegraph_turns=2"
	)
	if _failed:
		return

	# ── 7. Find a cardinal refuge that is NOT in telegraph cells ──
	# _ensure_boss_telegraph_escape inside _queue_boss_attack guarantees
	# at least one walkable, in-arena, unoccupied cardinal neighbor is
	# absent from the attack cells.
	var refuge: Vector2i = Vector2i.ZERO
	for dir: Vector2i in CARDINAL_DIRS:
		var neighbor: Vector2i = player_pos + dir
		if not _is_valid_boss_escape_cell(game, neighbor):
			continue
		if not game._boss_telegraphs.has(neighbor):
			refuge = neighbor
			break
	_assert(
		refuge != Vector2i.ZERO,
		"no safe cardinal refuge outside telegraph cells; all cardinals threatened or invalid"
	)
	if _failed:
		return

	# ── 8. Move player to refuge (no HP change) ──
	game._player.set_grid_position(refuge)
	await process_frame
	_assert(
		game._player.stats_component.current_hp == hp_before,
		"moving to refuge should not change HP"
	)
	if _failed:
		return

	# ── 9. First boss turn: telegraph decrements, does NOT resolve ──
	game._process_boss_turn(seraphine, 1.0, 99, {})
	await process_frame
	state = game._boss_state_for(seraphine)
	var still_pending: Resource = state.get("pending_attack", null)
	telegraph_turns = int(state.get("telegraph_turns", 0))
	_assert(still_pending != null, "pending_attack should remain after one telegraph turn")
	if _failed:
		return
	_assert(
		still_pending.id == &"spore_burst",
		"pending attack should still be spore_burst, got %s" % still_pending.id
	)
	if _failed:
		return
	_assert(telegraph_turns == 1, "telegraph_turns should decrement to 1, got %d" % telegraph_turns)
	if _failed:
		return

	# Telegraph still present
	var payloads: Dictionary = game._build_boss_telegraph_payload()
	_assert(not payloads.is_empty(), "telegraph should still have entries after one turn")
	if _failed:
		return
	_assert(
		game._player.stats_component.current_hp == hp_before,
		"first telegraph turn should not damage player at refuge"
	)
	if _failed:
		return

	# ── 10. Second boss turn: resolves, misses at refuge ──
	game._process_boss_turn(seraphine, 1.0, 99, {})
	await process_frame
	state = game._boss_state_for(seraphine)
	still_pending = state.get("pending_attack", null)
	_assert(still_pending == null, "pending_attack should be cleared after second turn")
	if _failed:
		return
	_assert(
		game._player.stats_component.current_hp == hp_before,
		"evading resolved telegraph should preserve HP at refuge"
	)
	if _failed:
		return

	# ── 11. Boss anchor never moved throughout ──
	_assert(
		seraphine.grid_position == spawn_anchor,
		"Seraphine moved from anchor %s to %s" % [spawn_anchor, seraphine.grid_position]
	)
	if _failed:
		return

	# ── 12. Boss art and telegraph glyphs are printable ASCII ──
	var boss_data: Resource = seraphine.enemy_data
	_assert(
		_printable_ascii(boss_data.glyph),
		"Seraphine glyph '%s' is not printable ASCII" % boss_data.glyph
	)
	if _failed:
		return
	for visual_frame: PackedStringArray in boss_data.boss_visual_frames:
		for frame_line: String in visual_frame:
			_assert(
				_printable_ascii(frame_line),
				"visual frame line '%s' contains non-printable characters" % frame_line
			)
			if _failed:
				return
	# telegraph glyphs
	for attack: Resource in boss_data.boss_attacks:
		_assert(
			_printable_ascii(attack.telegraph_glyph),
			(
				"attack %s telegraph_glyph '%s' is not printable ASCII"
				% [attack.id, attack.telegraph_glyph]
			)
		)
		if _failed:
			return
		if not attack.hazard_glyph.is_empty():
			_assert(
				_printable_ascii(attack.hazard_glyph),
				(
					"attack %s hazard_glyph '%s' is not printable ASCII"
					% [attack.id, attack.hazard_glyph]
				)
			)
			if _failed:
				return

	# Clean up
	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Boss encounter helpers
# ═══════════════════════════════════════════════════════════════════


func _enter_boss_on_floor(game: Node, floor_number: int) -> Node:
	## Generate `floor_number`, remove stray non-boss enemies, enter
	## the boss gate, complete the reveal, and return the spawned boss.
	game._generate_floor(floor_number)
	await process_frame

	# Remove non-boss enemies (they are skipped but interfere with
	# escape-cell validation if they block telegraph cells)
	for enemy: Node in game._enemies.duplicate():
		if enemy != null and enemy.enemy_data != null and not enemy.enemy_data.is_boss:
			game._enemies.erase(enemy)
			_game_manager.remove_enemy(enemy)
			enemy.queue_free()

	var encounter: Dictionary = game._active_boss_encounter
	if encounter.is_empty():
		_fail("no active boss encounter after generating floor %d" % floor_number)
		return null

	var gate_entry_cell: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	if gate_cell == Vector2i.ZERO or gate_entry_cell == Vector2i.ZERO:
		_fail("boss encounter missing gate cells on floor %d" % floor_number)
		return null

	# Pre-entry gate should be BOSS_DOOR (not yet sealed)
	var dun_data = preload("res://scripts/dungeon/dungeon_data.gd")
	var tile: int = _game_manager.map_data[gate_cell.y][gate_cell.x]
	_assert(
		tile == dun_data.TileType.BOSS_DOOR,
		"gate cell %s should be BOSS_DOOR before entry, got tile %d" % [gate_cell, tile]
	)
	if _failed:
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
	_assert(_live_boss_count(game) == 1, "boss reveal should spawn exactly one boss")
	if _failed:
		return null
	return encounter.get("boss", null)


# ═══════════════════════════════════════════════════════════════════
# Utility helpers
# ═══════════════════════════════════════════════════════════════════


func _attack_by_id(boss_data: Resource, attack_id: StringName) -> Resource:
	if boss_data == null:
		return null
	for attack: Resource in boss_data.boss_attacks:
		if attack.id == attack_id:
			return attack
	return null


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


func _is_valid_boss_escape_cell(game: Node, cell: Vector2i) -> bool:
	## Mirror of game._is_valid_boss_escape_cell — walkable, inside
	## boss arena, not a sealed gate, not occupied, not a secret wall.
	if not game._is_cell_in_active_boss_room(cell):
		return false
	if not game._is_walkable(cell):
		return false
	if game._is_sealed_boss_door(cell):
		return false
	if game._get_enemy_at(cell) != null:
		return false
	return true


func _printable_ascii(text: String) -> bool:
	## Returns true if `text` contains only printable ASCII characters
	## (codes 32-126) or is empty.
	for i: int in text.length():
		var code: int = text.unicode_at(i)
		if code < 32 or code > 126:
			return false
	return true


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
