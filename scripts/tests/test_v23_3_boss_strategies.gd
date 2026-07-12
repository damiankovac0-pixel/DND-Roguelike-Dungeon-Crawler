## Permanent deterministic regression coverage for V23.3 boss strategies,
## biome wall languages, and boss-marker discipline.
##
## Tests: five boss floors sequentially — Observer, Seraphine, Vorrak,
## Kaelros, Nyxara — plus biome-wall glyph contract.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v23_3_boss_strategies.gd
extends SceneTree

const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")
const SUMMON_PATHS: Dictionary = {
	&"kaelros": "res://resources/enemies/abyssal_eel.tres",
	&"nyxara": "res://resources/enemies/mirror_duelist.tres",
}
const BOSS_IDS: Array[StringName] = [
	&"observer",
	&"seraphine",
	&"vorrak",
	&"kaelros",
	&"nyxara",
]
const BOSS_FLOORS: Array[int] = [5, 10, 15, 20, 25]

var _failed: bool = false
var _game_manager: Node
var _game: Node


func _init() -> void:
	call_deferred("_run")


# ═══════════════════════════════════════════════════════════════════
# Main — deterministic seed, one game, five floors, cleanup
# ═══════════════════════════════════════════════════════════════════
func _run() -> void:
	seed(2330001)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		_finish()
		return
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	await process_frame
	_game.map_view.set_atmosphere_enabled(false)
	_game.map_view.set_reduced_vfx_enabled(true)

	var bosses: Dictionary = {}
	for idx: int in BOSS_IDS.size():
		var boss_id: StringName = BOSS_IDS[idx]
		var boss: Node = await _enter_boss(BOSS_FLOORS[idx])
		if boss == null:
			return
		bosses[boss_id] = boss
		_check_base_viability(boss_id, boss)
		if _failed:
			return
		_check_no_ordinary_aware_marker(boss)
		if _failed:
			return
		match boss_id:
			&"observer":
				_check_observer(boss)
			&"seraphine":
				_check_seraphine(boss)
			&"vorrak":
				_check_vorrak(boss)
			&"kaelros":
				_check_kaelros(boss)
			&"nyxara":
				_check_nyxara(boss)
		if _failed:
			return

	if not _failed:
		_check_biome_walls()

	print("V23.3 boss strategies, viability, marker, and walls passed")
	_finish()


# ═══════════════════════════════════════════════════════════════════
# Boss floor entry helper — generate floor, clear ads, enter gate
# ═══════════════════════════════════════════════════════════════════
func _enter_boss(floor_number: int) -> Node:
	_game._generate_floor(floor_number)
	await process_frame
	for enemy: Node in _game._enemies.duplicate():
		_game._enemies.erase(enemy)
		_game_manager.remove_enemy(enemy)
		if is_instance_valid(enemy):
			enemy.queue_free()
	var encounter: Dictionary = _game._active_boss_encounter
	if encounter.is_empty():
		_fail("no boss encounter on floor %d" % floor_number)
		return null
	var entry: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	var gate: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	if gate == Vector2i.ZERO or entry == Vector2i.ZERO:
		_fail("boss encounter missing gate cells on floor %d" % floor_number)
		return null
	_game._player.set_grid_position(entry)
	_game._attempt_player_move(gate - entry)
	await process_frame
	if not _game.complete_boss_arena_reveal():
		_fail("boss reveal failed on floor %d" % floor_number)
		return null
	await process_frame
	var boss: Node = encounter.get("boss", null)
	if boss == null:
		_fail("boss missing on floor %d" % floor_number)
		return null
	return boss


# ═══════════════════════════════════════════════════════════════════
# Base viability — all affinities 100, damage modes positive
# ═══════════════════════════════════════════════════════════════════
func _check_base_viability(boss_id: StringName, boss: Node) -> void:
	var data: Resource = boss.enemy_data
	_assert(
		data.melee_damage_percent == 100,
		"%s melee affinity should be 100, got %d" % [boss_id, data.melee_damage_percent]
	)
	_assert(
		data.ranged_damage_percent == 100,
		"%s ranged affinity should be 100, got %d" % [boss_id, data.ranged_damage_percent]
	)
	_assert(
		data.magic_damage_percent == 100,
		"%s magic affinity should be 100, got %d" % [boss_id, data.magic_damage_percent]
	)
	_assert(
		data.boss_guarded_damage_percent > 0,
		(
			"%s guarded percent must stay positive, got %d"
			% [boss_id, data.boss_guarded_damage_percent]
		)
	)
	_assert(
		data.boss_exposed_damage_percent > 100,
		(
			"%s exposure should reward counterplay, got %d"
			% [boss_id, data.boss_exposed_damage_percent]
		)
	)
	for damage_type: StringName in [&"melee", &"ranged", &"magic"]:
		_assert(
			_game._get_damage_percent(boss, damage_type) > 0,
			"%s %s path was hard-locked" % [boss_id, damage_type]
		)


# ═══════════════════════════════════════════════════════════════════
# Boss-marker discipline — idle boss never gets ordinary aware
# ═══════════════════════════════════════════════════════════════════
func _check_no_ordinary_aware_marker(boss: Node) -> void:
	_game._visible_cells[boss.grid_position] = true
	_game._visible_cells[_game._player.grid_position] = true
	var state: Dictionary = _game._boss_state_for(boss)
	var cooldowns: Dictionary = {}
	for attack: Resource in boss.enemy_data.boss_attacks:
		cooldowns[attack.id] = 99
	state["attack_cooldowns"] = cooldowns
	state["pending_attack"] = null
	_game._boss_states[boss] = state
	var intents: Dictionary = _game._build_enemy_intents()
	_assert(
		intents.get(boss.grid_position, &"") != &"aware",
		"%s received ordinary aware intent" % boss.display_name
	)
	state["attack_cooldowns"] = {}
	_game._boss_states[boss] = state


# ═══════════════════════════════════════════════════════════════════
# Observer strategy — evade opens eye, many_eyes geometry
# ═══════════════════════════════════════════════════════════════════
func _check_observer(boss: Node) -> void:
	var state: Dictionary = _game._boss_state_for(boss)
	# Guarded default
	_assert(
		_game._get_damage_percent(boss, &"melee") == boss.enemy_data.boss_guarded_damage_percent,
		"Observer should begin guarded at %d" % boss.enemy_data.boss_guarded_damage_percent
	)
	# Evade (hit=false) opens the eye
	_game._on_boss_strategy_attack_resolved(boss, false)
	state = _game._boss_state_for(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns,
		(
			"Observer evade should open %d turns, got %d"
			% [boss.enemy_data.boss_exposed_turns, state.get("exposed_turns", 0)]
		)
	)
	var exposed_percent: int = boss.enemy_data.boss_exposed_damage_percent
	_assert(
		_game._get_damage_percent(boss, &"ranged") == exposed_percent,
		"Observer open eye should expose all attack modes to %d" % exposed_percent
	)
	# Tick exposure down
	_game._tick_boss_exposure(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns - 1,
		"Observer exposure should decrement after tick"
	)
	_game._tick_boss_exposure(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == 0,
		"Observer exposure should close after %d ticks" % boss.enemy_data.boss_exposed_turns
	)
	# many_eyes cross geometry exists
	var many_eyes: Resource = _attack_by_id(boss, &"many_eyes")
	_assert(many_eyes != null, "Observer many_eyes attack not found")
	_assert(
		not _game._boss_attack_cells(boss, many_eyes).is_empty(),
		"Observer many_eyes cross geometry missing"
	)


# ═══════════════════════════════════════════════════════════════════
# Seraphine — 3 briars, 3 damage prunes, exposure lifecycle,
# no-damage callback does not prune
# ═══════════════════════════════════════════════════════════════════
func _check_seraphine(boss: Node) -> void:
	var state: Dictionary = _game._boss_state_for(boss)
	_assert(
		int(state.get("strategy_resource", 0)) == 3,
		"Seraphine should begin with three briars, got %d" % state.get("strategy_resource", 0)
	)

	# Three damaging calls prune all briars and open exposure
	for _index: int in range(3):
		_game._on_boss_damaged(boss)
	state = _game._boss_state_for(boss)
	_assert(
		int(state.get("strategy_resource", -1)) == 0,
		"three landed hits should prune Seraphine to zero briars"
	)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns,
		"Seraphine prune should open %d turns" % boss.enemy_data.boss_exposed_turns
	)
	_assert(
		bool(state.get("exposure_skip_tick", false)),
		"Seraphine prune-opened exposure should set skip_tick"
	)
	var exposed_percent: int = boss.enemy_data.boss_exposed_damage_percent
	_assert(
		_game._get_damage_percent(boss, &"magic") == exposed_percent,
		"Seraphine pruned sanctuary should expose all modes to %d" % exposed_percent
	)

	# Player-origin exposure survival: skip_tick prevents immediate decrement
	_game._tick_boss_exposure(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns,
		"player-origin exposure must skip immediate boss tick"
	)
	_assert(
		not bool(state.get("exposure_skip_tick", false)),
		"skip_tick should be consumed after one tick"
	)

	# Second action: decrement to 1 turn remaining
	_game._tick_boss_exposure(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == 1,
		"Seraphine should retain one turn after second tick"
	)

	# Third action: reseal, briars restored
	_game._tick_boss_exposure(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == 0, "Seraphine exposure should close after second tick"
	)
	_assert(
		int(state.get("strategy_resource", -1)) == int(state.get("strategy_resource_max", 3)),
		"Seraphine briars should reseal to max after exposure closes"
	)

	# Reset state for no-damage check
	state["strategy_resource"] = 3
	state["exposed_turns"] = 0
	state["exposure_skip_tick"] = false
	_game._boss_states[boss] = state

	# No-damage callback does not prune
	_game._handle_defender_after_damage(boss, false)
	state = _game._boss_state_for(boss)
	_assert(
		int(state.get("strategy_resource", -1)) == 3,
		"no-damage callback should not prune Seraphine briars"
	)
	_assert(int(state.get("exposed_turns", 0)) == 0, "no-damage callback should not open exposure")


# ═══════════════════════════════════════════════════════════════════
# Vorrak — 1+2 heat overload, furnace_vent radius-2 geometry
# ═══════════════════════════════════════════════════════════════════
func _check_vorrak(boss: Node) -> void:
	var state: Dictionary = _game._boss_state_for(boss)
	state["strategy_resource"] = 0
	state["exposed_turns"] = 0
	_game._boss_states[boss] = state

	# ash_breath adds 1 heat
	state["pending_attack"] = _attack_by_id(boss, &"ash_breath")
	_game._boss_states[boss] = state
	_game._on_boss_strategy_attack_resolved(boss, false)
	state = _game._boss_state_for(boss)
	_assert(int(state.get("strategy_resource", -1)) == 1, "ash_breath should add one heat")

	# maw_quake adds 2 heat => total 3 => overheat (resets heat, opens exposure)
	state["pending_attack"] = _attack_by_id(boss, &"maw_quake")
	_game._boss_states[boss] = state
	_game._on_boss_strategy_attack_resolved(boss, false)
	state = _game._boss_state_for(boss)
	_assert(
		int(state.get("strategy_resource", -1)) == 0,
		"Vorrak overheat should reset heat to zero, got %d" % state.get("strategy_resource", -1)
	)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns,
		"Vorrak overheat should expose %d turns" % boss.enemy_data.boss_exposed_turns
	)
	var exposed_percent: int = boss.enemy_data.boss_exposed_damage_percent
	_assert(
		_game._get_damage_percent(boss, &"melee") == exposed_percent,
		"Vorrak overload should reward close attacks to %d" % exposed_percent
	)

	# furnace_vent radius-2 ring geometry
	var vent: Resource = _attack_by_id(boss, &"furnace_vent")
	_assert(vent != null, "Vorrak furnace_vent attack not found")
	_assert(vent.radius == 2, "furnace_vent radius should be 2, got %d" % vent.radius)
	_assert(
		not _game._boss_attack_cells(boss, vent).is_empty(),
		"furnace_vent radius-2 ring geometry missing"
	)


# ═══════════════════════════════════════════════════════════════════
# Kaelros — live summon guards, final death opens window
# ═══════════════════════════════════════════════════════════════════
func _check_kaelros(boss: Node) -> void:
	var minion_data: Resource = load(SUMMON_PATHS[&"kaelros"])
	if minion_data == null:
		_fail("Kaelros minion resource failed to load")
		return

	# Spawn a live summon — boss should be guarded
	var spawn_cell: Vector2i = boss.grid_position + Vector2i(0, 4)
	var minion: Node = _game._spawn_enemy_instance(minion_data, spawn_cell, 20, false)
	minion.set_meta("summoned_minion", true)
	minion.set_meta("summoner_id", boss.get_instance_id())
	_assert(
		_game._get_damage_percent(boss, &"melee") == boss.enemy_data.boss_guarded_damage_percent,
		"Kaelros summon should guard boss at %d" % boss.enemy_data.boss_guarded_damage_percent
	)

	# Kill the summon — should open exposure
	minion.stats_component.current_hp = 0
	_game._on_boss_summon_died(boss.get_instance_id())
	var state: Dictionary = _game._boss_state_for(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns,
		"Kaelros final summon death should expose for %d turns" % boss.enemy_data.boss_exposed_turns
	)
	_assert(
		bool(state.get("exposure_skip_tick", false)),
		"Kaelros death-opened exposure should skip immediate tick"
	)

	# Skip tick honored
	_game._tick_boss_exposure(boss)
	_assert(
		int(state.get("exposed_turns", 0)) == boss.enemy_data.boss_exposed_turns,
		"Kaelros exposure lost an action immediately (skip_tick failed)"
	)

	# Cleanup minion from game state
	_game._enemies.erase(minion)
	_game_manager.remove_enemy(minion)
	if is_instance_valid(minion):
		minion.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Nyxara — true/false angle, guard seals, guard death,
# rotation without movement, hall geometry
# ═══════════════════════════════════════════════════════════════════
func _check_nyxara(boss: Node) -> void:
	var anchor: Vector2i = boss.grid_position
	var state: Dictionary = _game._boss_state_for(boss)
	state["exposed_turns"] = 0
	state["exposure_skip_tick"] = false
	state["nyxara_true_side_index"] = 0  # North
	_game._boss_states[boss] = state

	# True angle (north) — exposed
	_game._player.set_grid_position(anchor + Vector2i.UP * 4)
	_assert(
		_game._get_damage_percent(boss, &"ranged") == boss.enemy_data.boss_exposed_damage_percent,
		"Nyxara north true angle should expose at %d" % boss.enemy_data.boss_exposed_damage_percent
	)

	# False angle (south) — guarded
	_game._player.set_grid_position(anchor + Vector2i.DOWN * 4)
	_assert(
		_game._get_damage_percent(boss, &"ranged") == boss.enemy_data.boss_guarded_damage_percent,
		(
			"Nyxara false angle should remain guarded at %d"
			% boss.enemy_data.boss_guarded_damage_percent
		)
	)

	# Live guard has strict precedence
	var guard_data: Resource = load(SUMMON_PATHS[&"nyxara"])
	if guard_data == null:
		_fail("Nyxara guard resource failed to load")
		return
	var guard: Node = _game._spawn_enemy_instance(guard_data, anchor + Vector2i(4, 0), 25, false)
	guard.set_meta("summoned_minion", true)
	guard.set_meta("summoner_id", boss.get_instance_id())
	_game._player.set_grid_position(anchor + Vector2i.UP * 4)
	_assert(
		_game._get_damage_percent(boss, &"magic") == 60,
		"Nyxara guard must seal even the true angle (expected 60)"
	)
	var label: String = _game._boss_strategy_label(
		boss, _game._boss_state_for(boss), boss.enemy_data
	)
	_assert(
		label.begins_with("MIRROR SEALED"),
		"Nyxara guard should show MIRROR SEALED in label, got %s" % label
	)

	# Guard death opens exposure
	guard.stats_component.current_hp = 0
	_game._on_boss_summon_died(boss.get_instance_id())
	_assert(
		_game._get_damage_percent(boss, &"magic") == boss.enemy_data.boss_exposed_damage_percent,
		"broken Nyxara guard should expose any angle"
	)

	# Cleanup guard
	_game._enemies.erase(guard)
	_game_manager.remove_enemy(guard)
	if is_instance_valid(guard):
		guard.queue_free()

	# Rotation without movement
	state = _game._boss_state_for(boss)
	state["exposed_turns"] = 0
	state["exposure_skip_tick"] = false
	var side_before: int = int(state.get("nyxara_true_side_index", 0))
	var position_before: Vector2i = boss.grid_position
	_game._on_boss_strategy_attack_resolved(boss, false)
	state = _game._boss_state_for(boss)
	_assert(boss.grid_position == position_before, "Nyxara moved despite stationary contract")
	_assert(
		int(state.get("nyxara_true_side_index", -1)) == (side_before + 1) % 4,
		"Nyxara true angle did not rotate clockwise"
	)

	# hall_of_mirrors cross geometry
	var hall: Resource = _attack_by_id(boss, &"hall_of_mirrors")
	_assert(hall != null, "Nyxara hall_of_mirrors attack not found")
	_assert(
		not _game._boss_attack_cells(boss, hall).is_empty(),
		"hall_of_mirrors cross geometry missing"
	)


# ═══════════════════════════════════════════════════════════════════
# Biome wall languages — six biomes, three printable glyphs each,
# pairwise disjoint
# ═══════════════════════════════════════════════════════════════════
func _check_biome_walls() -> void:
	var used: Dictionary = {}
	for theme: Dictionary in BiomeCatalogScript.THEMES:
		var glyphs: Array = theme.get("wall_glyphs", [])
		_assert(
			glyphs.size() == 3,
			"%s should have three wall glyphs, got %d" % [theme.get("name", "?"), glyphs.size()]
		)
		for glyph_value: Variant in glyphs:
			var glyph: String = str(glyph_value)
			var codepoint: int = glyph.unicode_at(0)
			_assert(
				codepoint >= 32 and codepoint <= 126,
				(
					"%s has non-printable wall glyph %s (codepoint %d)"
					% [theme.get("name", "?"), glyph, codepoint]
				)
			)
			_assert(
				not used.has(glyph),
				(
					"wall glyph %s reused across biomes: %s and %s"
					% [glyph, used.get(glyph, "?"), theme.get("name", "?")]
				)
			)
			used[glyph] = theme.get("name", "?")
	print("  walls: six pairwise-disjoint printable biome languages")


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════
func _attack_by_id(boss: Node, attack_id: StringName) -> Resource:
	for attack: Resource in boss.enemy_data.boss_attacks:
		if attack.id == attack_id:
			return attack
	return null


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr("FAIL: %s" % message)


func _finish() -> void:
	if _game_manager != null:
		_game_manager.abandon_run()
	if is_instance_valid(_game):
		_game.queue_free()
	if _failed:
		quit(1)
	else:
		quit(0)
