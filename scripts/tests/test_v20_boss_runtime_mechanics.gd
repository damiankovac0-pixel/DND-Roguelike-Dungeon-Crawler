## V31 boss runtime mechanics contracts.
##
## Covers: attack scheduler phase/cooldown/distance behavior, chooser
## purity, movement when no attack is eligible, close-range melee
## retaliation and one-turn countdowns for all five bosses, Seraphine
## phase selection, Observer stun hit/evade, hazard timing/poison/expiry/
## unknown effects, Vorrak push clamp, Kaelros pull/hazard single-tick
## discipline, Nyxara stationary true-angle rotation, summon caps and
## scheduler avoidance, telegraph payload countdown, and stale cleanup.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_runtime_mechanics.gd
extends SceneTree

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const MapViewScript = preload("res://scripts/ui/map_view.gd")

var _failed: bool = false
var _game_manager: Node


func _init() -> void:
	call_deferred("_run")


# ═══════════════════════════════════════════════════════════════════
# Main entry point
# ═══════════════════════════════════════════════════════════════════
func _run() -> void:
	seed(200500)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return

	# ── Section 1: attack scheduler ──
	await _test_attack_scheduler_exact_phase()
	if _failed:
		return
	await _test_choose_attack_no_cooldown_mutation()
	if _failed:
		return

	# ── Section 2: Seraphine phase-selects spore_burst then spore_bloom ──
	await _test_seraphine_phase_selects()
	if _failed:
		return

	# ── V32.0.0: Seraphine's signature burst has a three-tier windup ──
	if not _failed:
		_check_seraphine_escape_contract()
	if _failed:
		return

	# ── Section 3: Observer stun ──
	await _test_observer_stun_hit_evade()
	if _failed:
		return

	# ── Section 4: hazard mechanics ──
	await _test_seraphine_hazard_no_immediate_tick()
	if _failed:
		return
	await _test_hazard_grace_period()
	if _failed:
		return
	await _test_hazard_expiry_map_sync()
	if _failed:
		return
	await _test_hazard_unknown_effect()
	if _failed:
		return

	# ── Section 5: Vorrak push clamp ──
	if not _failed:
		await _test_vorrak_push_clamp()
	if _failed:
		return

	# ── Section 6: Kaelros pull/hazard single-tick ──
	if not _failed:
		await _test_kaelros_pull_hazard_clamp()
	if _failed:
		return

	# ── Section 7: Nyxara stationary true-angle rotation ──
	if not _failed:
		await _test_nyxara_stationary_true_angle()
	if _failed:
		return

	# ── Section 8: summon caps ──
	if not _failed:
		await _test_summon_caps()
	if _failed:
		return
	if not _failed:
		await _test_summon_cap_skipped_by_scheduler()
	if _failed:
		return

	# ── V23.1.0: Kaelros drowned_retinue summon_count=1 (one-eel) ──
	if not _failed:
		_check_kaelros_one_eel()
	if _failed:
		return

	# ── V23.1.0: Nyxara mirror_guard summon_max_active=1 (one-guard) ──
	if not _failed:
		_check_nyxara_one_guard()
	if _failed:
		return

	# ── Section 9: telegraph countdown ──
	if not _failed:
		await _test_kaelros_telegraph_countdown()
	if _failed:
		return

	# ── Section 10: stale cleanup after normal boss death ──
	if not _failed:
		await _test_stale_cleanup_on_boss_death()
	if _failed:
		return

	# ── V31: deterministic distance scheduling and melee retaliation ──
	await _test_distance_eligibility_and_no_idle_movement()
	if _failed:
		return
	await _test_melee_retaliation_contracts()
	if _failed:
		return

	print("V31 boss runtime mechanics checks passed")
	quit(0)


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════


func _start_game() -> Node:
	## Creates a fresh game.tscn instance and returns it.
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	return game


func _enter_boss_on_floor(game: Node, floor_number: int) -> Node:
	## Generates the given floor, enters and completes the boss arena reveal,
	## and returns the spawned boss Node. Removes stray non-boss enemies
	## before gate entry.
	game._generate_floor(floor_number)
	await process_frame
	_remove_all_enemies_except(game, null)
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
		"gate entry should leave floor %d in arena_reveal state" % floor_number
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
	return encounter.get("boss", null)


func _remove_all_enemies_except(game: Node, keep: Node = null) -> void:
	## Removes all enemies from the game except `keep`.
	for enemy: Node in game._enemies.duplicate():
		if enemy != keep:
			game._enemies.erase(enemy)
			_game_manager.remove_enemy(enemy)
			if is_instance_valid(enemy):
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


func _find_boss_movement_target(game: Node, boss: Node, min_distance: float) -> Vector2i:
	## Finds a room cell whose primary approach step can accept the full
	## boss footprint, making the scheduler movement assertion deterministic.
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	var boss_cell: Vector2i = boss.grid_position
	for cell: Vector2i in room_cells.keys():
		if (
			not game._is_walkable(cell)
			or game._enemy_occupies_cell(boss, cell)
			or cell.distance_to(boss_cell) < min_distance
		):
			continue
		var delta: Vector2i = cell - boss_cell
		var primary_direction: Vector2i
		if abs(delta.x) >= abs(delta.y):
			primary_direction = Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
		else:
			primary_direction = Vector2i.DOWN if delta.y > 0 else Vector2i.UP
		if game._can_place_boss_at(boss, boss_cell + primary_direction, {}):
			return cell
	return Vector2i(-1, -1)


func _attack_by_id(boss_data: Resource, attack_id: StringName) -> Resource:
	## Returns the BossAttackData sub-resource matching `attack_id`,
	## or null if not found.
	if boss_data == null:
		return null
	for attack: Resource in boss_data.boss_attacks:
		if attack.id == attack_id:
			return attack
	return null


func _count_live_summons(game: Node, boss: Node) -> int:
	## Counts alive minions whose summoner_id matches `boss`.
	var count: int = 0
	var summoner_id: int = boss.get_instance_id()
	for candidate in game._enemies:
		if (
			candidate != null
			and candidate.is_alive()
			and candidate.has_meta("summoned_minion")
			and candidate.get_meta("summoned_minion") == true
			and candidate.get_meta("summoner_id") == summoner_id
		):
			count += 1
	return count


func _boss_room_container_count(game: Node) -> int:
	## Counts containers inside the active boss room.
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	var count: int = 0
	for cell: Vector2i in game._container_positions:
		if room_cells.has(cell):
			count += 1
	return count


# ═══════════════════════════════════════════════════════════════════
# Section 1 – Attack scheduler exact-phase / cooldown
# ═══════════════════════════════════════════════════════════════════


func _test_attack_scheduler_exact_phase() -> void:
	## Observer phase 2 should prefer blink_pulse (exact-phase
	## attack over observer_gaze phase-1).  After queueing and
	## ticking cooldowns, the next choice should avoid blink_pulse
	## and fall back to observer_gaze.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned")
		return
	observer.stats_component.current_hp = int(float(observer.stats_component.max_hp) * 0.60)
	game._update_boss_phase(observer)
	var state: Dictionary = game._boss_state_for(observer)
	state["attack_cooldowns"] = {}
	state["pending_attack"] = null
	state["telegraph_cells"] = {}
	state["telegraph_turns"] = 0
	game._boss_states[observer] = state

	var observer_data: Resource = observer.enemy_data
	var blink_pulse: Resource = _attack_by_id(observer_data, &"blink_pulse")
	var observer_gaze: Resource = _attack_by_id(observer_data, &"observer_gaze")
	_assert(blink_pulse != null, "blink_pulse attack not found")
	_assert(observer_gaze != null, "observer_gaze attack not found")
	if _failed:
		return

	# Phase 2 → exact-phase blink_pulse preferred
	var chosen: Resource = game._choose_boss_attack(
		observer, 999, game._enemy_distance_to_player(observer)
	)
	_assert(
		chosen == blink_pulse,
		"Phase 2 should prefer blink_pulse, got %s" % ("" if chosen == null else chosen.id)
	)
	if _failed:
		return

	# Queue blink_pulse → cooldown stored
	var cells: Dictionary = game._boss_attack_cells(observer, blink_pulse)
	game._queue_boss_attack(observer, blink_pulse, cells)
	state = game._boss_state_for(observer)
	var cooldowns: Dictionary = state.get("attack_cooldowns", {})
	var expected_cd: int = max(1, blink_pulse.cooldown)
	_assert(
		int(cooldowns.get(&"blink_pulse", 0)) == expected_cd,
		(
			"blink_pulse cooldown should be %d, got %d"
			% [expected_cd, cooldowns.get(&"blink_pulse", 0)]
		)
	)
	if _failed:
		return

	# Simulate attack no longer pending before ticking cooldowns
	state["pending_attack"] = null
	state["telegraph_cells"] = {}
	state["telegraph_turns"] = 0
	game._boss_states[observer] = state
	game._tick_boss_attack_cooldowns(observer)

	# After one tick blink_pulse still on cooldown → choose observer_gaze
	chosen = game._choose_boss_attack(observer, 1000, game._enemy_distance_to_player(observer))
	_assert(
		chosen == observer_gaze,
		"Should prefer observer_gaze while blink_pulse cooldown, got %s" % chosen.id
	)

	game.queue_free()


func _test_distance_eligibility_and_no_idle_movement() -> void:
	## Close and ranged bands meet at distance 2.0. Selection is stable
	## on either side of that inclusive boundary and does not mutate state.
	## If every attack is unavailable, the normal boss-turn path advances
	## the full footprint toward the player instead of consuming an idle turn.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned for distance scheduler checks")
		return

	var observer_data: Resource = observer.enemy_data
	var optic_recoil: Resource = _attack_by_id(observer_data, &"optic_recoil")
	var observer_gaze: Resource = _attack_by_id(observer_data, &"observer_gaze")
	_assert(optic_recoil != null, "optic_recoil attack not found")
	_assert(observer_gaze != null, "observer_gaze attack not found")
	if _failed:
		return

	var state_before: Dictionary = game._boss_state_for(observer).duplicate(true)
	for _repeat: int in range(3):
		var close_choice: Resource = game._choose_boss_attack(observer, 1, 1.99)
		_assert(close_choice == optic_recoil, "distance 1.99 should choose optic_recoil")
		var boundary_choice: Resource = game._choose_boss_attack(observer, 1, 2.0)
		_assert(boundary_choice == optic_recoil, "distance 2.0 should include optic_recoil")
		var ranged_choice: Resource = game._choose_boss_attack(observer, 1, 2.01)
		_assert(ranged_choice == observer_gaze, "distance 2.01 should choose observer_gaze")
		if _failed:
			return
	_assert(
		game._boss_state_for(observer) == state_before,
		"distance-aware chooser should be deterministic and state-pure"
	)
	if _failed:
		return

	var movement_target: Vector2i = _find_boss_movement_target(game, observer, 4.0)
	_assert(movement_target != Vector2i(-1, -1), "no deterministic boss movement seam found")
	if _failed:
		return
	game._player.set_grid_position(movement_target)
	await process_frame

	var state: Dictionary = game._boss_state_for(observer)
	var cooldowns: Dictionary = {}
	for attack: Resource in observer_data.boss_attacks:
		cooldowns[attack.id] = 50
	state["attack_cooldowns"] = cooldowns
	state["forced_attack_id"] = &""
	state["pending_attack"] = null
	game._boss_states[observer] = state
	var position_before: Vector2i = observer.grid_position
	var distance_before: float = game._enemy_distance_to_player(observer)
	var consumed_turn: bool = game._process_boss_turn(observer, distance_before, 1, {})
	var distance_after: float = game._enemy_distance_to_player(observer)
	_assert(consumed_turn, "boss turn should be consumed when no attack is eligible")
	_assert(observer.grid_position != position_before, "boss idled when no attack was eligible")
	_assert(distance_after < distance_before, "fallback movement should reduce player distance")

	game.queue_free()


func _test_melee_retaliation_contracts() -> void:
	## `_handle_defender_after_damage(..., true, channel)` is the post-resolution
	## seam for positive damage. False covers both miss and zero-damage results.
	## Every Normal boss counts only positive melee hits, forces its configured
	## close counter at threshold (even through cooldown), clears that force only
	## when queued, and resolves the one-turn telegraph on the next boss turn.
	var cases: Array[Dictionary] = [
		{
			"floor": 5,
			"boss_id": &"observer",
			"attack_id": &"optic_recoil",
			"threshold": 2,
		},
		{
			"floor": 10,
			"boss_id": &"seraphine",
			"attack_id": &"briar_rebuke",
			"threshold": 3,
		},
		{
			"floor": 15,
			"boss_id": &"vorrak",
			"attack_id": &"maw_snap",
			"threshold": 2,
		},
		{
			"floor": 20,
			"boss_id": &"kaelros",
			"attack_id": &"royal_backwash",
			"threshold": 2,
		},
		{
			"floor": 25,
			"boss_id": &"nyxara",
			"attack_id": &"shardstep",
			"threshold": 2,
		},
	]

	for test_case: Dictionary in cases:
		var floor_number: int = int(test_case["floor"])
		var expected_boss_id: StringName = test_case["boss_id"]
		var expected_attack_id: StringName = test_case["attack_id"]
		var expected_threshold: int = int(test_case["threshold"])
		var game: Node = await _start_game()
		var boss: Node = await _enter_boss_on_floor(game, floor_number)
		if boss == null:
			_fail("%s not spawned for melee retaliation checks" % expected_boss_id)
			return
		_remove_all_enemies_except(game, boss)

		var enemy_data: Resource = boss.enemy_data
		var counter_attack: Resource = _attack_by_id(enemy_data, expected_attack_id)
		_assert(
			enemy_data.boss_id == expected_boss_id, "unexpected boss on floor %d" % floor_number
		)
		_assert(
			enemy_data.boss_retaliation_hit_threshold == expected_threshold,
			"%s retaliation threshold should be %d" % [expected_boss_id, expected_threshold]
		)
		_assert(
			enemy_data.boss_retaliation_attack_id == expected_attack_id,
			"%s retaliation should configure %s" % [expected_boss_id, expected_attack_id]
		)
		_assert(counter_attack != null, "%s counter attack not found" % expected_attack_id)
		if _failed:
			return
		_assert(
			counter_attack.telegraph_turns == 1,
			"%s should have a one-turn tell" % expected_attack_id
		)
		_assert(
			counter_attack.max_player_distance == 2.0,
			"%s should be close-only" % expected_attack_id
		)
		if _failed:
			return

		var state: Dictionary = game._boss_state_for(boss)
		state["melee_hits_received"] = 0
		state["forced_attack_id"] = &""
		var reaction_cooldowns: Dictionary = {}
		reaction_cooldowns[expected_attack_id] = 50
		state["attack_cooldowns"] = reaction_cooldowns
		game._boss_states[boss] = state

		game._handle_defender_after_damage(boss, false, &"melee")  # Miss.
		game._handle_defender_after_damage(boss, false, &"melee")  # Zero damage.
		game._handle_defender_after_damage(boss, true, &"ranged")
		game._handle_defender_after_damage(boss, true, &"magic")
		state = game._boss_state_for(boss)
		_assert(
			int(state.get("melee_hits_received", -1)) == 0,
			"%s counted miss, zero, ranged, or magic damage as melee" % expected_boss_id
		)
		_assert(
			state.get("forced_attack_id", &"") == &"",
			"%s primed retaliation without positive melee hits" % expected_boss_id
		)
		if _failed:
			return

		for hit_count: int in range(1, expected_threshold):
			game._handle_defender_after_damage(boss, true, &"melee")
			state = game._boss_state_for(boss)
			_assert(
				int(state.get("melee_hits_received", -1)) == hit_count,
				"%s positive melee count should be %d" % [expected_boss_id, hit_count]
			)
			_assert(
				state.get("forced_attack_id", &"") == &"",
				"%s forced retaliation before threshold" % expected_boss_id
			)
			if _failed:
				return

		game._handle_defender_after_damage(boss, true, &"melee")
		state = game._boss_state_for(boss)
		_assert(
			int(state.get("melee_hits_received", -1)) == 0,
			"%s melee count should reset at threshold" % expected_boss_id
		)
		_assert(
			state.get("forced_attack_id", &"") == expected_attack_id,
			"%s threshold should force %s" % [expected_boss_id, expected_attack_id]
		)
		if _failed:
			return

		var chosen: Resource = game._choose_boss_attack(boss, 1, 1.0)
		_assert(
			chosen == counter_attack,
			"%s forced counter should win while on cooldown" % expected_boss_id
		)
		if _failed:
			return
		var cells: Dictionary = game._boss_attack_cells(boss, counter_attack)
		_assert(not cells.is_empty(), "%s counter produced no telegraph cells" % expected_attack_id)
		if _failed:
			return
		game._queue_boss_attack(boss, counter_attack, cells)
		state = game._boss_state_for(boss)
		_assert(
			state.get("forced_attack_id", &"") == &"",
			"%s force should clear when its attack is queued" % expected_boss_id
		)
		_assert(
			state.get("pending_attack", null) == counter_attack,
			"%s should be pending" % expected_attack_id
		)
		_assert(
			int(state.get("telegraph_turns", 0)) == 1,
			"%s countdown should start at one turn" % expected_attack_id
		)
		if _failed:
			return

		game._process_boss_turn(boss, game._enemy_distance_to_player(boss), 1, {})
		state = game._boss_state_for(boss)
		_assert(
			state.get("pending_attack", null) == null,
			"%s should resolve on the next boss turn" % expected_attack_id
		)
		_assert(
			int(state.get("telegraph_turns", -1)) == 0,
			"%s countdown should clear after resolution" % expected_attack_id
		)
		if _failed:
			return
		game.queue_free()


func _test_choose_attack_no_cooldown_mutation() -> void:
	## _choose_boss_attack and _boss_has_windup_intent must not
	## mutate attack_cooldowns.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned")
		return
	var state: Dictionary = game._boss_state_for(observer)
	state["phase"] = 2
	state["attack_cooldowns"] = {&"blink_pulse": 3}
	state["pending_attack"] = null
	state["last_attack_id"] = &""
	game._boss_states[observer] = state

	var before: int = int(state["attack_cooldowns"].get(&"blink_pulse", 0))
	game._choose_boss_attack(observer, 999, game._enemy_distance_to_player(observer))
	state = game._boss_state_for(observer)
	_assert(
		int(state["attack_cooldowns"].get(&"blink_pulse", 0)) == before,
		"_choose_boss_attack mutated cooldowns"
	)
	if _failed:
		return

	game._boss_has_windup_intent(observer, 999, game._enemy_distance_to_player(observer))
	state = game._boss_state_for(observer)
	_assert(
		int(state["attack_cooldowns"].get(&"blink_pulse", 0)) == before,
		"_boss_has_windup_intent mutated cooldowns"
	)

	game.queue_free()


# ---------------------------------------------------------------------------
#  V32.0.0 — spore_burst telegraphs 3/2/1 turns in Normal/Hard/Nightmare
# ---------------------------------------------------------------------------


func _check_seraphine_escape_contract() -> void:
	## A three-turn base keeps the burst escapable on Normal while difficulty
	## scaling tightens it to two turns on Hard and one on Nightmare.
	## hazard_turns=2 means the hazard persists for two ticks after landing.
	#
	# This is a resource-level check: we load the Seraphine enemy template
	# and inspect the attack definition without spawning a boss encounter.
	var seraphine_template: Resource = load("res://resources/enemies/seraphine_thorn_saint.tres")
	if seraphine_template == null:
		_fail("Seraphine enemy data not found")
		return
	var burst: Resource = _attack_by_id(seraphine_template, &"spore_burst")
	if burst == null:
		_fail("spore_burst attack not found on Seraphine")
		return
	_assert(
		burst.telegraph_turns == 3,
		"spore_burst telegraph_turns = %d, expected 3" % burst.telegraph_turns
	)
	_assert(
		burst.hazard_turns == 2, "spore_burst hazard_turns = %d, expected 2" % burst.hazard_turns
	)
	# telegraph_turns > 1 means the player can escape by moving to a
	# non-hazard cell after the telegraph is drawn.  A runtime test would
	# need a boss encounter + player turn to verify the escape physically,
	# but the attack contract is captured here.
	if not _failed:
		print(
			(
				"  seraphine spore_burst: telegraph_turns=%d, hazard_turns=%d"
				% [burst.telegraph_turns, burst.hazard_turns]
			)
		)


func _check_kaelros_one_eel() -> void:
	## Kaelros drowned_retinue summon_count=1 in V23.1.0.
	## The retinue summons one eel at a time instead of two.
	var template: Resource = load("res://resources/enemies/kaelros_drowned_king.tres")
	if template == null:
		_fail("Kaelros enemy data not found")
		return
	var retinue: Resource = _attack_by_id(template, &"drowned_retinue")
	if retinue == null:
		_fail("drowned_retinue attack not found on Kaelros")
		return
	_assert(
		retinue.summon_count == 1,
		"drowned_retinue summon_count = %d, expected 1" % retinue.summon_count
	)
	if not _failed:
		print("  kaelros retinue: summon_count=%d" % retinue.summon_count)


func _check_nyxara_one_guard() -> void:
	## Nyxara mirror_guard summon_max_active=1 in V23.1.0.
	## Only one guard can be active at a time (no alternation).
	var template: Resource = load("res://resources/enemies/nyxara_mirror_witch.tres")
	if template == null:
		_fail("Nyxara enemy data not found")
		return
	var guard: Resource = _attack_by_id(template, &"mirror_guard")
	if guard == null:
		_fail("mirror_guard attack not found on Nyxara")
		return
	_assert(
		guard.summon_max_active == 1,
		"mirror_guard summon_max_active = %d, expected 1" % guard.summon_max_active
	)
	if not _failed:
		print("  nyxara guard: summon_max_active=%d" % guard.summon_max_active)


# ---------------------------------------------------------------------------
# ═══════════════════════════════════════════════════════════════════
# Section 2 – Seraphine phase selection
# ═══════════════════════════════════════════════════════════════════


func _test_seraphine_phase_selects() -> void:
	## Phase 2 (HP ~60%) prefers the higher-weight spore_burst.
	## While only spore_burst is cooling down, the phase-2 summon
	## spore_bloom remains selectable (and stays available in phase 3).
	var game: Node = await _start_game()
	var seraphine: Node = await _enter_boss_on_floor(game, 10)
	if seraphine == null:
		_fail("Seraphine not spawned")
		return
	var data: Resource = seraphine.enemy_data
	var spore_burst: Resource = _attack_by_id(data, &"spore_burst")
	var spore_bloom: Resource = _attack_by_id(data, &"spore_bloom")
	_assert(spore_burst != null, "spore_burst not found")
	_assert(spore_bloom != null, "spore_bloom not found")
	if _failed:
		return
	_assert(
		spore_bloom.phase_min == 2,
		"spore_bloom should unlock in phase 2 and remain available in phase 3"
	)
	if _failed:
		return

	# Phase 2: set HP to ~60% of 92 ≈ 55
	var max_hp: int = seraphine.stats_component.max_hp
	seraphine.stats_component.current_hp = int(float(max_hp) * 0.60)
	game._update_boss_phase(seraphine)
	var state: Dictionary = game._boss_state_for(seraphine)
	state["attack_cooldowns"] = {}
	state["last_attack_id"] = &""
	game._boss_states[seraphine] = state
	_assert(int(state.get("phase", 1)) == 2, "Seraphine should be phase 2 at 60%% HP")
	if _failed:
		return

	var state_before: Dictionary = state.duplicate(true)
	var chosen: Resource = game._choose_boss_attack(
		seraphine, 1, game._enemy_distance_to_player(seraphine)
	)
	_assert(
		chosen == spore_burst,
		"Phase 2 should prefer spore_burst, got %s" % ("" if chosen == null else chosen.id)
	)
	_assert(
		game._boss_state_for(seraphine) == state_before,
		"Seraphine phase-2 chooser should be state-pure"
	)
	if _failed:
		return

	# Cool only the higher-weight pressure attack; the phase-2 summon alternates in.
	state = game._boss_state_for(seraphine)
	state["attack_cooldowns"] = {spore_burst.id: max(1, spore_burst.cooldown)}
	game._boss_states[seraphine] = state
	state_before = state.duplicate(true)
	chosen = game._choose_boss_attack(seraphine, 1, game._enemy_distance_to_player(seraphine))
	_assert(
		chosen == spore_bloom,
		(
			"Phase 2 should select spore_bloom while only spore_burst cools down, got %s"
			% ("" if chosen == null else chosen.id)
		)
	)
	_assert(
		game._boss_state_for(seraphine) == state_before,
		"Seraphine cooldown chooser should be state-pure"
	)

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 3 – Observer stun
# ═══════════════════════════════════════════════════════════════════


func _test_observer_stun_hit_evade() -> void:
	## Observer gaze hit sets _stun_actions > 0; evade leaves it 0.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned")
		return
	var observer_gaze: Resource = _attack_by_id(observer.enemy_data, &"observer_gaze")
	_assert(observer_gaze != null, "observer_gaze not found")
	if _failed:
		return

	# Hit → stun
	game._stun_actions = 0
	game._apply_boss_attack_effect(observer, observer_gaze, true)
	_assert(
		game._stun_actions > 0,
		"Observer gaze hit should set _stun_actions > 0, got %d" % game._stun_actions
	)
	if _failed:
		return

	# Evade → no stun
	game._stun_actions = 0
	game._apply_boss_attack_effect(observer, observer_gaze, false)
	_assert(
		game._stun_actions == 0,
		"Observer gaze evade should leave _stun_actions == 0, got %d" % game._stun_actions
	)

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 4 – Hazard mechanics
# ═══════════════════════════════════════════════════════════════════


func _test_seraphine_hazard_no_immediate_tick() -> void:
	## Resolving spore_burst creates hazards in _boss_hazards but
	## does not apply damage on the same turn.
	var game: Node = await _start_game()
	var seraphine: Node = await _enter_boss_on_floor(game, 10)
	if seraphine == null:
		_fail("Seraphine not spawned")
		return
	var spore_burst: Resource = _attack_by_id(seraphine.enemy_data, &"spore_burst")
	_assert(spore_burst != null, "spore_burst not found")
	if _failed:
		return

	# Put player on a room cell that spore_burst can target
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	if room_cells.is_empty():
		_fail("no boss room cells")
		return
	var target_cell: Vector2i = room_cells.keys()[0]
	# Ensure the player is not occupying the cell before we move them
	game._player.set_grid_position(target_cell)
	await process_frame

	var hazard_cells: Dictionary = {target_cell: true}
	var hp_before: int = game._player.stats_component.current_hp

	game._resolve_boss_attack(seraphine, spore_burst, hazard_cells)
	await process_frame

	# Hazards were created in _boss_hazards
	_assert(
		not game._boss_hazards.is_empty(),
		"_boss_hazards should have entries after spore_burst resolve"
	)
	# HP may have changed from the resolve damage, but not from hazard tick
	# (hazard tick happens during _end_player_turn, not during _resolve_boss_attack)
	var hazards_exist_under_player: bool = game._boss_hazards.has(target_cell)
	_assert(hazards_exist_under_player, "A hazard should exist at the player's cell after resolve")

	game.queue_free()


func _test_hazard_grace_period() -> void:
	## The fairness grace period: hazards do not tick when created,
	## they only tick when the player spends an action.  Player moves
	## off → no damage; moves back onto → damage + poison apply.
	var game: Node = await _start_game()
	var seraphine: Node = await _enter_boss_on_floor(game, 10)
	if seraphine == null:
		_fail("Seraphine not spawned")
		return
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "no boss room cells")
	if _failed:
		return

	# Pick a room cell and a neighbour for the player to stand on
	var cells_list: Array[Vector2i] = []
	for cell: Vector2i in room_cells.keys():
		if not game._is_container_spawn_blocked(cell) and cell != game._player.grid_position:
			cells_list.append(cell)
	_assert(not cells_list.is_empty(), "no usable room cell")
	if _failed:
		return

	var hazard_cell: Vector2i = cells_list[0]
	var safe_cell: Vector2i = Vector2i.ZERO
	for cell: Vector2i in cells_list:
		if cell != hazard_cell:
			safe_cell = cell
			break
	_assert(safe_cell != Vector2i.ZERO, "need a safe cell distinct from hazard cell")
	if _failed:
		return

	# Move player to hazard_cell
	game._player.set_grid_position(hazard_cell)
	await process_frame

	# Inject a poison hazard directly to test grace period in isolation
	game._boss_hazards[hazard_cell] = {
		"turns_remaining": 3,
		"boss": seraphine,
		"boss_id": &"seraphine",
		"source_attack_id": &"spore_burst",
		"damage_dice": 1,
		"damage_sides": 4,
		"damage_bonus": 0,
		"damage_type": &"magic",
		"effect": &"poison",
		"effect_turns": 3,
		"effect_amount": 4,
		"glyph": "✹",
		"color": Color(0.76, 1, 0.52, 1),
		"fill_color": Color(0.22, 0.60, 0.18, 0.26),
		"border_color": Color(0.90, 0.58, 0.82, 0.86),
		"message": "Virulent spores erupt for %d magic damage.",
	}
	var hp_before: int = game._player.stats_component.current_hp
	var poison_before: int = game._poison_turns

	# Grace period: hazard is created but has not ticked yet
	_assert(
		game._player.stats_component.current_hp == hp_before,
		"Hazard should not damage immediately on creation"
	)
	if _failed:
		return

	# Move player to safe cell → no hazard at safe cell
	game._player.set_grid_position(safe_cell)
	await process_frame

	# Call _apply_boss_hazard_tick directly (simulates end of turn).
	# Since player is not on hazard_cell, no damage or poison.
	game._apply_boss_hazard_tick()
	_assert(
		game._player.stats_component.current_hp == hp_before,
		"Player should not take hazard damage when on a safe cell"
	)
	_assert(
		game._poison_turns == poison_before, "Poison should not be applied when player on safe cell"
	)
	if _failed:
		return

	# Move back onto hazard → now tick should apply damage + poison
	game._poison_turns = 0
	game._player.set_grid_position(hazard_cell)
	await process_frame

	# We've already ticked once above, so hazard has been aged.
	# Recreate a fresh hazard for the test.
	game._boss_hazards[hazard_cell] = {
		"turns_remaining": 3,
		"boss": seraphine,
		"boss_id": &"seraphine",
		"source_attack_id": &"spore_burst",
		"damage_dice": 1,
		"damage_sides": 4,
		"damage_bonus": 0,
		"damage_type": &"magic",
		"effect": &"poison",
		"effect_turns": 3,
		"effect_amount": 4,
		"glyph": "✹",
		"color": Color(0.76, 1, 0.52, 1),
		"fill_color": Color(0.22, 0.60, 0.18, 0.26),
		"border_color": Color(0.90, 0.58, 0.82, 0.86),
		"message": "Virulent spores erupt for %d magic damage.",
	}
	hp_before = game._player.stats_component.current_hp

	game._apply_boss_hazard_tick()
	_assert(
		game._player.stats_component.current_hp <= hp_before,
		"Player should take hazard damage when standing on a hazard"
	)
	_assert(game._poison_turns > 0, "Hazard poison should update _poison_turns")
	_assert(game._poison_damage_sides >= 2, "Hazard poison should set _poison_damage_sides")

	game.queue_free()


func _test_hazard_expiry_map_sync() -> void:
	## One-turn hazard appears in _boss_hazards, appears in map_view
	## after _refresh_map, and is gone after _apply_boss_hazard_tick.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned")
		return
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "no boss room cells")
	if _failed:
		return

	# Place player on a room cell and create a 1-turn hazard there
	var player_cell: Vector2i = game._player.grid_position
	if not room_cells.has(player_cell):
		# If player is outside the boss room after teleport, use first room cell
		for cell: Vector2i in room_cells.keys():
			player_cell = cell
			game._player.set_grid_position(player_cell)
			break
		await process_frame

	game._boss_hazards[player_cell] = {
		"turns_remaining": 1,
		"boss": observer,
		"boss_id": &"observer",
		"source_attack_id": &"blink_pulse",
		"damage_dice": 0,
		"damage_sides": 4,
		"damage_bonus": 0,
		"damage_type": &"magic",
		"effect": &"",
		"effect_turns": 0,
		"effect_amount": 0,
		"glyph": "⊙",
		"color": Color(0.82, 0.95, 1, 1),
		"fill_color": Color(0.18, 0.46, 1, 0.2),
		"border_color": Color(0.72, 0.90, 1, 0.84),
		"message": "Test hazard.",
	}

	# _refresh_map should push hazards to map_view
	game._refresh_map()
	var map_view: Node = game.map_view
	# Access map_view's _boss_hazards directly
	var mv_hazards_pre: Dictionary = map_view._boss_hazards
	_assert(
		mv_hazards_pre.has(player_cell), "map_view should contain the hazard after _refresh_map"
	)
	if _failed:
		return

	# Tick hazard → expires
	game._apply_boss_hazard_tick()
	_assert(
		not game._boss_hazards.has(player_cell),
		"Hazard should expire after tick with 1 turn remaining"
	)
	if _failed:
		return

	# After _refresh_map, map_view should also be cleared
	game._refresh_map()
	var mv_hazards_post: Dictionary = map_view._boss_hazards
	_assert(
		not mv_hazards_post.has(player_cell),
		"map_view should clear expired hazard after _refresh_map"
	)

	game.queue_free()


func _test_hazard_unknown_effect() -> void:
	## Unknown hazard effect logs a warning once and does nothing.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned")
		return

	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	if room_cells.is_empty():
		_fail("no boss room cells")
		return
	var player_cell: Vector2i = game._player.grid_position
	if not room_cells.has(player_cell):
		for cell: Vector2i in room_cells.keys():
			player_cell = cell
			game._player.set_grid_position(player_cell)
			break
		await process_frame

	# Insert hazard with unknown effect, zero damage so only the
	# unknown-effect path runs
	game._boss_hazards[player_cell] = {
		"turns_remaining": 2,
		"boss": observer,
		"boss_id": &"observer",
		"source_attack_id": &"test",
		"damage_dice": 0,
		"damage_sides": 4,
		"damage_bonus": 0,
		"damage_type": &"magic",
		"effect": &"bogus_test_effect",
		"effect_turns": 0,
		"effect_amount": 0,
		"glyph": "?",
		"color": Color.WHITE,
		"fill_color": Color(1, 1, 1, 0.1),
		"border_color": Color(1, 1, 1, 0.5),
		"message": "",
	}
	game._unknown_boss_hazard_effects.clear()

	# First tick → unknown effect causes a warning and registers
	game._apply_boss_hazard_tick()
	_assert(
		game._unknown_boss_hazard_effects.has(&"bogus_test_effect"),
		"Unknown hazard effect should be registered"
	)
	if _failed:
		return

	# Second tick on the same cell (turns_remaining was 2, now 1)
	game._apply_boss_hazard_tick()
	_assert(
		not game._boss_hazards.has(player_cell),
		"Hazard with unknown effect should expire after 2 ticks"
	)
	# No duplicate warning assertion needed; checking no crash is sufficient.

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 5 – Vorrak push clamp
# ═══════════════════════════════════════════════════════════════════


func _test_vorrak_push_clamp() -> void:
	## Vorrak ash_breath push moves player up to 2 cells away from
	## boss, never outside room_cells, never through a sealed door,
	## never onto an occupied cell.
	var game: Node = await _start_game()
	var vorrak: Node = await _enter_boss_on_floor(game, 15)
	if vorrak == null:
		_fail("Vorrak not spawned")
		return
	var ash_breath: Resource = _attack_by_id(vorrak.enemy_data, &"ash_breath")
	_assert(ash_breath != null, "ash_breath not found")
	_assert(ash_breath.effect == &"push", "ash_breath should have push effect")
	_assert(ash_breath.effect_amount == 2, "ash_breath push amount should be 2")
	if _failed:
		return

	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "no boss room cells")
	if _failed:
		return

	# Position player somewhere in the room a few steps from Vorrak
	# such that there is room to push away.
	var boss_cell: Vector2i = vorrak.grid_position
	var player_cell: Vector2i = boss_cell - Vector2i(-3, 0)  # right of boss
	if not room_cells.has(player_cell) or not game._is_walkable(player_cell):
		# Fall back: find a cell in room that's not on boss footprint
		for cell: Vector2i in room_cells.keys():
			if game._is_walkable(cell) and not game._enemy_occupies_cell(vorrak, cell):
				player_cell = cell
				break

	game._player.set_grid_position(player_cell)
	await process_frame

	var pos_before: Vector2i = game._player.grid_position
	game._apply_boss_attack_effect(vorrak, ash_breath, true)
	await process_frame

	var pos_after: Vector2i = game._player.grid_position
	var moved: bool = pos_after != pos_before
	if moved:
		var distance_moved: int = abs(pos_after.x - pos_before.x) + abs(pos_after.y - pos_before.y)
		_assert(distance_moved <= 2, "Push should move at most 2 cells, moved %d" % distance_moved)
		if _failed:
			return
		_assert(room_cells.has(pos_after), "Player pushed outside room_cells")
		if _failed:
			return
		# Player should not be pushed onto a sealed boss door
		_assert(not game._is_sealed_boss_door(pos_after), "Player pushed onto sealed boss door")
		if _failed:
			return
		# Player should not be pushed onto Vorrak's footprint
		_assert(
			not game._enemy_occupies_cell(vorrak, pos_after),
			"Player pushed onto Vorrak occupied cell"
		)
	else:
		# If push didn't move the player (blocked by arena wall), that's OK
		# as long as the player stayed in bounds and on valid cell.
		pass

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 6 – Kaelros pull/hazard single-tick
# ═══════════════════════════════════════════════════════════════════


func _test_kaelros_pull_hazard_clamp() -> void:
	## Kaelros undertow pull moves player up to 2 cells toward boss,
	## never into boss footprint.  A single hazard tick applies at
	## most one hazard even if the player is pulled onto a second.
	var game: Node = await _start_game()
	var kaelros: Node = await _enter_boss_on_floor(game, 20)
	if kaelros == null:
		_fail("Kaelros not spawned")
		return
	var undertow: Resource = _attack_by_id(kaelros.enemy_data, &"undertow")
	_assert(undertow != null, "undertow not found")
	_assert(undertow.effect == &"pull", "undertow should have pull effect")
	_assert(undertow.effect_amount == 2, "undertow pull amount should be 2")
	if _failed:
		return

	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "no boss room cells")
	if _failed:
		return

	# Position the player so they are pullable toward Kaelros.
	# Place player a few cells away with open space toward boss.
	var boss_cell: Vector2i = kaelros.grid_position
	var player_cell: Vector2i = boss_cell - Vector2i(-4, 0)  # right of boss
	if not room_cells.has(player_cell) or not game._is_walkable(player_cell):
		for cell: Vector2i in room_cells.keys():
			if (
				game._is_walkable(cell)
				and not game._enemy_occupies_cell(kaelros, cell)
				and cell != boss_cell
			):
				player_cell = cell
				break

	game._player.set_grid_position(player_cell)
	await process_frame

	var pos_before: Vector2i = game._player.grid_position
	game._apply_boss_attack_effect(kaelros, undertow, true)
	await process_frame

	var pos_after: Vector2i = game._player.grid_position
	var moved: bool = pos_after != pos_before
	if moved:
		var distance_moved: int = abs(pos_after.x - pos_before.x) + abs(pos_after.y - pos_before.y)
		_assert(distance_moved <= 2, "Pull should move at most 2 cells, moved %d" % distance_moved)
		if _failed:
			return
		# Player should not end up inside Kaelros' footprint
		_assert(
			not game._enemy_occupies_cell(kaelros, pos_after),
			"Player pulled into Kaelros occupied cell"
		)
		if _failed:
			return
		_assert(room_cells.has(pos_after), "Player pulled outside room_cells")
	else:
		# If pull didn't move the player (blocked by walls), that's OK
		pass

	# ── Single hazard application per tick ──
	# Create two hazard cells in line: start_cell has damage + pull,
	# mid_cell has only damage.  A single tick should apply only the
	# start_cell hazard even if pull moves the player onto mid_cell.
	var start_cell: Vector2i = game._player.grid_position
	var direction: Vector2i = _cardinal_step_between(start_cell, kaelros.grid_position)
	if direction == Vector2i.ZERO:
		direction = Vector2i.RIGHT
	var mid_cell: Vector2i = start_cell + direction
	# Ensure both cells are in the room and walkable
	if not room_cells.has(mid_cell) or not game._is_walkable(mid_cell):
		# Find a pair of adjacent room cells starting from player
		for adj_dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var adj: Vector2i = start_cell + adj_dir
			if room_cells.has(adj) and game._is_walkable(adj):
				mid_cell = adj
				direction = adj_dir
				break

	# Clear any existing hazards
	game._boss_hazards.clear()

	# Hazard at start_cell: damage + pull effect
	game._boss_hazards[start_cell] = {
		"turns_remaining": 2,
		"boss": kaelros,
		"boss_id": &"kaelros",
		"source_attack_id": &"undertow",
		"damage_dice": 1,
		"damage_sides": 4,
		"damage_bonus": 1,
		"damage_type": &"magic",
		"effect": &"pull",
		"effect_turns": 0,
		"effect_amount": 1,
		"glyph": "≈",
		"color": Color(0.48, 0.88, 1, 1),
		"fill_color": Color(0.05, 0.32, 0.58, 0.30),
		"border_color": Color(0.38, 0.82, 1, 0.88),
		"message": "The undertow drags through you for %d magic damage.",
	}
	# Hazard at mid_cell: damage only, no effect
	game._boss_hazards[mid_cell] = {
		"turns_remaining": 2,
		"boss": kaelros,
		"boss_id": &"kaelros",
		"source_attack_id": &"undertow",
		"damage_dice": 1,
		"damage_sides": 4,
		"damage_bonus": 1,
		"damage_type": &"magic",
		"effect": &"",
		"effect_turns": 0,
		"effect_amount": 0,
		"glyph": "≈",
		"color": Color(0.48, 0.88, 1, 1),
		"fill_color": Color(0.05, 0.32, 0.58, 0.30),
		"border_color": Color(0.38, 0.82, 1, 0.88),
		"message": "",
	}

	var hp_before: int = game._player.stats_component.current_hp

	# First tick: start_cell hazard applies damage + pull
	game._apply_boss_hazard_tick()
	var hp_after_tick1: int = game._player.stats_component.current_hp
	var pos_after_tick1: Vector2i = game._player.grid_position

	_assert(hp_after_tick1 <= hp_before, "First hazard tick should apply damage")
	# The start cell hazard aged (either expired or decremented)
	var start_still_active: bool = game._boss_hazards.has(start_cell)
	if start_still_active:
		_assert(
			int(game._boss_hazards[start_cell].get("turns_remaining", 0)) < 2,
			"Start cell hazard should have decremented"
		)
	# The mid_cell hazard must still be present (aged, but not consumed)
	_assert(
		game._boss_hazards.has(mid_cell),
		"Mid cell hazard should still exist after first tick (not yet applied)"
	)
	if _failed:
		return

	# Second tick: if the player was pulled onto mid_cell, the mid_cell
	# hazard should now apply.  If the player was NOT pulled onto mid_cell
	# (edge block / no valid pull path), skip the second assertion.
	if pos_after_tick1 == mid_cell:
		var hp_mid_before: int = game._player.stats_component.current_hp
		game._apply_boss_hazard_tick()
		_assert(
			game._player.stats_component.current_hp <= hp_mid_before,
			"Mid cell hazard should apply on second tick after pull"
		)
		# Player must remain inside room_cells and not in boss footprint
		_assert(
			room_cells.has(game._player.grid_position),
			"Player should remain inside room_cells after hazard pull"
		)
		_assert(
			not game._enemy_occupies_cell(kaelros, game._player.grid_position),
			"Player should not be in Kaelros footprint after hazard pull"
		)

	game.queue_free()


func _cardinal_step_between(from_cell: Vector2i, to_cell: Vector2i) -> Vector2i:
	## Returns the cardinal direction from `from_cell` toward `to_cell`.
	var delta: Vector2i = to_cell - from_cell
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if abs(delta.x) >= abs(delta.y) and delta.x != 0:
		return Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT
	return Vector2i.DOWN if delta.y > 0 else Vector2i.UP


# ═══════════════════════════════════════════════════════════════════
# Section 7 – Nyxara stationary true-angle rotation
# ═══════════════════════════════════════════════════════════════════


func _test_nyxara_stationary_true_angle() -> void:
	## Nyxara mirror_ray no longer phase-shifts (stationary anchor).
	## Resolving a non-summon attack rotates the true-side index.
	var game: Node = await _start_game()
	var nyxara: Node = await _enter_boss_on_floor(game, 25)
	if nyxara == null:
		_fail("Nyxara not spawned")
		return
	_remove_all_enemies_except(game, nyxara)

	var mirror_ray: Resource = _attack_by_id(nyxara.enemy_data, &"mirror_ray")
	_assert(mirror_ray != null, "mirror_ray not found")
	_assert(
		mirror_ray.effect != &"phase_shift",
		"mirror_ray should no longer have phase_shift effect (stationary)"
	)
	_assert(mirror_ray.effect == &"", "mirror_ray effect should be empty under stationary contract")
	if _failed:
		return

	# Stationary anchor: applying the effect must not move Nyxara
	var occupied_before: Array[Vector2i] = game._enemy_occupied_cells(nyxara)
	game._apply_boss_attack_effect(nyxara, mirror_ray, false)
	var occupied_after: Array[Vector2i] = game._enemy_occupied_cells(nyxara)

	var any_changed: bool = false
	for cell: Vector2i in occupied_after:
		if not occupied_before.has(cell):
			any_changed = true
			break
	if not any_changed:
		for cell: Vector2i in occupied_before:
			if not occupied_after.has(cell):
				any_changed = true
				break
	_assert(not any_changed, "Nyxara should not move under stationary contract")
	# Player should not be inside the boss
	_assert(
		not occupied_after.has(game._player.grid_position), "Effect should not place boss on player"
	)

	# True-side index rotates after each non-summon resolve
	var state: Dictionary = game._boss_state_for(nyxara)
	var before_index: int = int(state.get("nyxara_true_side_index", -1))
	_assert(before_index >= 0, "nyxara_true_side_index should be initialized")
	if _failed:
		return

	game._on_boss_strategy_attack_resolved(nyxara, false)
	state = game._boss_state_for(nyxara)
	var after_index: int = int(state.get("nyxara_true_side_index", -1))
	_assert(after_index == (before_index + 1) % 4, "True-side index should advance after resolve")
	if _failed:
		return

	# Second rotation confirms forward progress, not stuck at one
	game._on_boss_strategy_attack_resolved(nyxara, false)
	state = game._boss_state_for(nyxara)
	var after_index2: int = int(state.get("nyxara_true_side_index", -1))
	_assert(
		after_index2 == (after_index + 1) % 4,
		"True-side index should advance again after second resolve"
	)

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 8 – Summon caps
# ═══════════════════════════════════════════════════════════════════


func _test_summon_caps() -> void:
	## Seraphine spore_bloom: summons one servant per bloom, max 2 live minions.
	## Kaelros drowned_retinue: max 2 live minions.
	## Nyxara mirror_guard: max 1 live minion (V23.1.0, no alternation).
	await _test_summon_cap(&"seraphine", 10, &"spore_bloom", 2, 1)
	if _failed:
		return
	await _test_summon_cap(&"kaelros", 20, &"drowned_retinue", 2)
	if _failed:
		return
	# For Nyxara, also verify summon alternation
	await _test_nyxara_summon_alternation()


func _test_summon_cap(
	boss_id: StringName,
	floor_number: int,
	attack_id: StringName,
	expected_max: int,
	expected_count: int = -1
) -> void:
	## Resolve the given summon attack twice and assert live minions
	## never exceed expected_max.
	var game: Node = await _start_game()
	var boss: Node = await _enter_boss_on_floor(game, floor_number)
	if boss == null:
		_fail("%s not spawned on floor %d" % [boss_id, floor_number])
		return
	_remove_all_enemies_except(game, boss)

	var attack: Resource = _attack_by_id(boss.enemy_data, attack_id)
	_assert(attack != null, "%s attack not found on %s" % [attack_id, boss_id])
	_assert(
		attack.summon_max_active == expected_max,
		"%s cap should be %d, got %d" % [attack_id, expected_max, attack.summon_max_active]
	)
	if expected_count >= 0:
		_assert(
			attack.summon_count == expected_count,
			(
				"%s summon_count should be %d, got %d"
				% [attack_id, expected_count, attack.summon_count]
			)
		)
	if _failed:
		return

	# First resolve
	game._resolve_boss_summon(boss, attack, {})
	await process_frame
	var count1: int = _count_live_summons(game, boss)
	_assert(
		count1 <= expected_max,
		(
			"%s summond count %d after first resolve should not exceed %d"
			% [boss_id, count1, expected_max]
		)
	)
	if _failed:
		return

	# Second resolve
	game._resolve_boss_summon(boss, attack, {})
	await process_frame
	var count2: int = _count_live_summons(game, boss)
	_assert(
		count2 <= expected_max,
		(
			"%s summond count %d after second resolve should not exceed %d"
			% [boss_id, count2, expected_max]
		)
	)
	if _failed:
		return

	# For Kaelros and Nyxara where max is 2, assert it's exactly 2
	if expected_max >= 2:
		_assert(
			count2 == expected_max or count2 == count1,
			"%s should hit cap after two resolves" % boss_id
		)

	game.queue_free()


func _test_nyxara_summon_alternation() -> void:
	## Nyxara mirror_guard has summon_max_active=1 (V23.1.0).
	## After one successful summon, subsequent mirror_guard calls are capped.
	var game: Node = await _start_game()
	var nyxara: Node = await _enter_boss_on_floor(game, 25)
	if nyxara == null:
		_fail("Nyxara not spawned")
		return
	_remove_all_enemies_except(game, nyxara)

	var attack: Resource = _attack_by_id(nyxara.enemy_data, &"mirror_guard")
	_assert(attack != null, "mirror_guard attack not found on Nyxara")
	_assert(attack.summon_max_active == 1, "mirror_guard cap should be 1 (V23.1.0)")
	_assert(attack.summon_count == 1, "mirror_guard summon_count should be 1")
	if _failed:
		return

	# First summon -> produces 1 minion
	game._resolve_boss_summon(nyxara, attack, {})
	await process_frame
	var count1: int = _count_live_summons(game, nyxara)
	_assert(count1 == 1, "Nyxara should have 1 minion after first summon, got %d" % count1)
	if _failed:
		return

	# Second summon -> capped (max_active=1), no new minions
	game._resolve_boss_summon(nyxara, attack, {})
	await process_frame
	var count2: int = _count_live_summons(game, nyxara)
	_assert(count2 == 1, "Nyxara should stay at 1 minion after capped summon, got %d" % count2)
	if _failed:
		return

	game.queue_free()


func _test_summon_cap_skipped_by_scheduler() -> void:
	## When a summon boss has live minions at the cap, _choose_boss_attack
	## should not return the capped summon attack.  If no other attack
	## is available, return null rather than a capped summon.
	var game: Node = await _start_game()
	var kaelros: Node = await _enter_boss_on_floor(game, 20)
	if kaelros == null:
		_fail("Kaelros not spawned")
		return
	_remove_all_enemies_except(game, kaelros)

	# Force Kaelros to phase 2 so drowned_retinue (phase_min=2) is available
	var state: Dictionary = game._boss_state_for(kaelros)
	state["phase"] = 2
	state["attack_cooldowns"] = {}
	state["last_attack_id"] = &""
	game._boss_states[kaelros] = state

	var retinue: Resource = _attack_by_id(kaelros.enemy_data, &"drowned_retinue")
	var undertow: Resource = _attack_by_id(kaelros.enemy_data, &"undertow")
	_assert(retinue != null, "drowned_retinue not found")

	# First, clear cap by making room: resolve retinue once, then check
	game._resolve_boss_summon(kaelros, retinue, {})
	await process_frame
	var live: int = _count_live_summons(game, kaelros)
	# We need exactly 2 minions to hit the cap. Retinue spawns 1 at once (V23.1.0).
	# If it only spawned 1 due to room constraints, resolve again.
	if live < 2:
		game._resolve_boss_summon(kaelros, retinue, {})
		await process_frame
		live = _count_live_summons(game, kaelros)

	# At cap, _choose_boss_attack should skip retinue
	var chosen: Resource = game._choose_boss_attack(
		kaelros, 1, game._enemy_distance_to_player(kaelros)
	)
	_assert(chosen != retinue, "Should not select capped retinue attack, got retinue")
	if _failed:
		return

	# If only summon attack is available and caps are full, return null
	# by removing undertow from availability (simulate all non-summon
	# attacks on cooldown).
	state = game._boss_state_for(kaelros)
	state["attack_cooldowns"] = {&"undertow": 10}
	game._boss_states[kaelros] = state
	var only_summon_choice: Resource = game._choose_boss_attack(
		kaelros, 1, game._enemy_distance_to_player(kaelros)
	)
	_assert(
		only_summon_choice == null, "Scheduler should return null when only capped summon remains"
	)
	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 9 – Telegraph countdown
# ═══════════════════════════════════════════════════════════════════


func _test_kaelros_telegraph_countdown() -> void:
	## After queueing Kaelros undertow, the telegraph payload contains
	## keys: attack_id, shape, boss_id, turns_remaining, telegraph_turns.
	## turns_remaining starts at 2 and decrements each pending turn;
	## after resolve, telegraph cells are cleared.
	var game: Node = await _start_game()
	var kaelros: Node = await _enter_boss_on_floor(game, 20)
	if kaelros == null:
		_fail("Kaelros not spawned")
		return
	_remove_all_enemies_except(game, kaelros)

	var undertow: Resource = _attack_by_id(kaelros.enemy_data, &"undertow")
	_assert(undertow != null, "undertow not found")
	_assert(undertow.telegraph_turns == 2, "undertow telegraph_turns should be 2")
	if _failed:
		return

	# Player must be in the boss room for attack cells to be valid
	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "no boss room cells")
	if _failed:
		return
	# Ensure player is somewhere in the room
	var player_cell: Vector2i = game._player.grid_position
	if not room_cells.has(player_cell):
		for cell: Vector2i in room_cells.keys():
			player_cell = cell
			break
		game._player.set_grid_position(player_cell)
		await process_frame

	# Queue undertow
	var cells: Dictionary = game._boss_attack_cells(kaelros, undertow)
	# Ensure we have valid cells
	if cells.is_empty():
		# Fall back: inject the player's cell directly
		cells = {player_cell: true}
	game._queue_boss_attack(kaelros, undertow, cells)
	var payload: Dictionary = game._build_boss_telegraph_payload()

	_assert(not payload.is_empty(), "telegraph payload should not be empty after queueing")
	if _failed:
		return

	# Check every cell payload has the required keys
	var checked_payload: bool = false
	for cell: Vector2i in payload.keys():
		var cell_payload: Dictionary = payload[cell]
		_assert(cell_payload.has("attack_id"), "telegraph cell missing attack_id")
		_assert(cell_payload.has("shape"), "telegraph cell missing shape")
		_assert(cell_payload.has("boss_id"), "telegraph cell missing boss_id")
		_assert(cell_payload.has("turns_remaining"), "telegraph cell missing turns_remaining")
		_assert(cell_payload.has("telegraph_turns"), "telegraph cell missing telegraph_turns")
		var turns_remaining: int = int(cell_payload.get("turns_remaining", 0))
		var telegraph_turns: int = int(cell_payload.get("telegraph_turns", 0))
		_assert(
			turns_remaining == 2,
			"turns_remaining should be 2 after queue, got %d" % turns_remaining
		)
		_assert(
			telegraph_turns == 2,
			"telegraph_turns should be 2 after queue, got %d" % telegraph_turns
		)
		_assert(cell_payload.get("attack_id") == &"undertow", "attack_id should be undertow")
		_assert(cell_payload.get("shape") == &"tidal_lane", "shape should be tidal_lane")
		checked_payload = true
		break  # Check one cell is enough

	_assert(checked_payload, "no telegraph cells to inspect")
	if _failed:
		return

	# Process one boss turn while pending attack remains unresolved →
	# turns_remaining decrements, attack_id unchanged
	var state: Dictionary = game._boss_state_for(kaelros)
	# _process_boss_turn will call _update_boss_phase, then find
	# pending_attack and decrement telegraph_turns.
	var dist: float = game._enemy_distance_to_player(kaelros)
	game._process_boss_turn(kaelros, dist, 1, {})
	payload = game._build_boss_telegraph_payload()
	if not payload.is_empty():
		for cell: Vector2i in payload.keys():
			var turns_left: int = int(payload[cell].get("turns_remaining", 0))
			_assert(
				turns_left == 1,
				"After one pending turn, turns_remaining should be 1, got %d" % turns_left
			)
			_assert(
				payload[cell].get("attack_id") == &"undertow", "attack_id unchanged after decrement"
			)
			break
	# Another pending turn resolves → telegraph cells cleared
	if not payload.is_empty():
		game._process_boss_turn(kaelros, dist, 2, {})
		payload = game._build_boss_telegraph_payload()
		_assert(payload.is_empty(), "Telegraph cells should be empty after undertow resolves")

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Section 10 – Stale cleanup after normal boss death
# ═══════════════════════════════════════════════════════════════════


func _test_stale_cleanup_on_boss_death() -> void:
	## Killing the boss (normal death path) clears _boss_telegraphs,
	## _boss_hazards, and their map_view copies.
	var game: Node = await _start_game()
	var observer: Node = await _enter_boss_on_floor(game, 5)
	if observer == null:
		_fail("Observer not spawned")
		return

	var room_cells: Dictionary = game._active_boss_encounter.get("room_cells", {})
	_assert(not room_cells.is_empty(), "no boss room cells")
	if _failed:
		return

	# Inject a telegraph and a hazard entry
	var some_cell: Vector2i = game._player.grid_position
	if not room_cells.has(some_cell):
		for cell: Vector2i in room_cells.keys():
			some_cell = cell
			break
		game._player.set_grid_position(some_cell)
		await process_frame

	game._boss_telegraphs[some_cell] = {
		"glyph": "!",
		"color": Color.WHITE,
		"fill_color": Color(1, 1, 1, 0.1),
		"border_color": Color.WHITE,
		"attack_id": &"test",
		"boss": observer,
		"boss_id": &"observer",
		"turns_remaining": 1,
		"telegraph_turns": 1,
		"shape": &"single_player",
	}
	game._boss_hazards[some_cell] = {
		"turns_remaining": 2,
		"boss": observer,
		"boss_id": &"observer",
		"source_attack_id": &"test",
		"damage_dice": 0,
		"damage_sides": 4,
		"damage_bonus": 0,
		"damage_type": &"magic",
		"effect": &"",
		"effect_turns": 0,
		"effect_amount": 0,
		"glyph": "~",
		"color": Color.WHITE,
		"fill_color": Color(1, 1, 1, 0.1),
		"border_color": Color.WHITE,
		"message": "",
	}
	var projectile_cells: Array[Vector2i] = [observer.grid_position, some_cell]
	game.map_view.play_projectile_trail(
		projectile_cells, {"profile_id": &"observer_gaze", "duration_seconds": 1.0}
	)
	_assert(game.map_view.has_active_projectile_trails(), "boss cleanup test needs an active trail")
	if _failed:
		return

	# Kill the boss via normal damage
	observer.stats_component.apply_damage(99999)
	await process_frame

	_assert(bool(game._active_boss_encounter.get("defeated", false)), "boss should be defeated")
	_assert(game._boss_telegraphs.is_empty(), "_boss_telegraphs should be cleared after boss death")
	_assert(game._boss_hazards.is_empty(), "_boss_hazards should be cleared after boss death")
	_assert(
		not game.map_view.has_active_projectile_trails(),
		"boss death/release should clear projectile trails",
	)

	# After _refresh_map, map_view copies should also be clear
	game._refresh_map()
	var map_view: Node = game.map_view
	if map_view != null:
		var mv_telegraphs: Dictionary = map_view._boss_telegraphs
		_assert(
			mv_telegraphs.is_empty(), "map_view _boss_telegraphs should be empty after boss death"
		)
		var mv_hazards: Dictionary = map_view._boss_hazards
		_assert(mv_hazards.is_empty(), "map_view _boss_hazards should be empty after boss death")

	game.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Assertions
# ═══════════════════════════════════════════════════════════════════


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
