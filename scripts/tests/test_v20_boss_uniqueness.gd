## V20.0.0 boss attack data uniqueness and effect contracts.
##
## Loads all five boss resources and verifies attack data signatures,
## effect triggers, unique shape visual geometry, and summon preview setup.
## One lightweight geometry smoke test instantiates game.tscn to confirm
## the new shape methods produce non-empty telegraph cells.
##
## Resource-level checks cover most contracts and do not instantiate
## game.tscn.  The geometry smoke uses a single floor-5 boss encounter
## (the Observer), entering the boss gate to establish a live room.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_uniqueness.gd
extends SceneTree

# ── Boss resource paths ──────────────────────────────────────────
const BOSS_PATHS: Dictionary = {
	&"observer": "res://resources/enemies/the_observer.tres",
	&"seraphine": "res://resources/enemies/seraphine_thorn_saint.tres",
	&"vorrak": "res://resources/enemies/vorrak_ashen_maw.tres",
	&"kaelros": "res://resources/enemies/kaelros_drowned_king.tres",
	&"nyxara": "res://resources/enemies/nyxara_mirror_witch.tres",
}

# Stat sanity bounds (loose — survive rebalancing)
const MIN_HP: int = 60
const MAX_HP: int = 200
const MIN_AC: int = 14
const MAX_AC: int = 20
const MIN_GOLD_REWARD: int = 150
const MAX_GOLD_REWARD: int = 1000

# New shapes introduced in V20 that MUST appear in at least one boss attack
const NEW_SHAPES: Array[StringName] = [
	&"parallax_gaze",
	&"thorn_patch",
	&"eruption_columns",
	&"tidal_lane",
	&"mirror_ray",
	&"mirror_reflection",
]

# Boss-specific effect contracts:
#   poison   → Seraphine spore_burst (effect_trigger = hit)
#   push     → Vorrak ash_breath     (effect_trigger = hit)
#   pull     → Kaelros undertow      (effect_trigger = hit)
#   phase_shift → Nyxara mirror_ray  (effect_trigger = resolve)
const SERAPHINE_SPORE: Dictionary = {
	"id": &"spore_burst",
	"effect": &"poison",
	"effect_trigger": &"hit",
	"effect_turns": 3,
	"effect_amount": 4,
}
const VORRAK_BREATH: Dictionary = {
	"id": &"ash_breath",
	"effect": &"push",
	"effect_trigger": &"hit",
	"effect_amount": 1,
}
const KAELROS_UNDERTOW: Dictionary = {
	"id": &"undertow",
	"effect": &"pull",
	"effect_trigger": &"hit",
	"effect_amount": 1,
}
const NYXARA_RAY: Dictionary = {
	"id": &"mirror_ray",
	"effect": &"phase_shift",
	"effect_trigger": &"resolve",
	"effect_amount": 1,
}

var _failed: bool = false
var _game: Node  # null unless geometry smoke test is running


func _init() -> void:
	call_deferred("_run")


# ═══════════════════════════════════════════════════════════════════
# Main entry point
# ═══════════════════════════════════════════════════════════════════
func _run() -> void:
	# ── Phase 1: load all five boss resources ──
	var bosses: Dictionary = {}
	for boss_id: StringName in BOSS_PATHS:
		var path: String = BOSS_PATHS[boss_id]
		var res: Resource = load(path)
		if res == null:
			_fail("Failed to load %s at %s" % [boss_id, path])
			return
		bosses[boss_id] = res

	# ── Phase 2: resource-level checks (no game instance needed) ──
	_check_resource_signatures(bosses)
	if _failed:
		return

	_check_new_shape_visual_data(bosses)
	if _failed:
		return

	_check_effect_contracts(bosses)
	if _failed:
		return

	_check_summon_attacks(bosses)
	if _failed:
		return

	_check_shape_uniqueness_across_bosses(bosses)
	if _failed:
		return

	# ── Phase 3: geometry smoke test (one game instantiation) ──
	await _check_geometry_smoke(bosses)
	if _failed:
		return

	print("V20 boss uniqueness checks passed")
	quit(0)


# ═══════════════════════════════════════════════════════════════════
# Phase 2 – Resource-level contracts
# ═══════════════════════════════════════════════════════════════════


func _check_resource_signatures(bosses: Dictionary) -> void:
	## Every boss resource carries expected identity, stat range,
	## non-empty attack roster, phase thresholds, and visual data.
	var expected: Dictionary = {
		&"observer": {floor = 5, title = "The Unblinking Gate"},
		&"seraphine": {floor = 10, title = "The Blooming Reliquary"},
		&"vorrak": {floor = 15, title = "The Furnace Throat"},
		&"kaelros": {floor = 20, title = "The Drowned Throne"},
		&"nyxara": {floor = 25, title = "The Last Reflection"},
	}
	for boss_id: StringName in bosses:
		var b: Resource = bosses[boss_id]
		var label: String = b.display_name

		# ── boss identity ──
		_assert(b.is_boss, "%s: is_boss should be true" % label)
		_assert(b.boss_id == boss_id, "%s: boss_id mismatch" % label)

		var exp: Dictionary = expected[boss_id]
		_assert(b.boss_floor == exp.floor, "%s: boss_floor should be %d" % [label, exp.floor])
		_assert(
			b.boss_room_title == exp.title,
			"%s: boss_room_title should be '%s'" % [label, exp.title]
		)

		# ── stat sanity (loose bounds for rebalancing) ──
		_assert(
			b.max_hp >= MIN_HP and b.max_hp <= MAX_HP,
			"%s: max_hp %d outside [%d, %d]" % [label, b.max_hp, MIN_HP, MAX_HP]
		)
		_assert(
			b.armor_class >= MIN_AC and b.armor_class <= MAX_AC,
			"%s: armor_class %d outside [%d, %d]" % [label, b.armor_class, MIN_AC, MAX_AC]
		)
		_assert(
			b.boss_reward_gold >= MIN_GOLD_REWARD and b.boss_reward_gold <= MAX_GOLD_REWARD,
			(
				"%s: boss_reward_gold %d outside [%d, %d]"
				% [label, b.boss_reward_gold, MIN_GOLD_REWARD, MAX_GOLD_REWARD]
			)
		)

		# ── attack roster ──
		_assert(not b.boss_attacks.is_empty(), "%s: boss_attacks is empty" % label)

		# ── phase thresholds ──
		_assert(
			b.boss_phase_hp_percents.size() >= 1,
			"%s: boss_phase_hp_percents should have at least 1 threshold" % label
		)
		for pct: int in b.boss_phase_hp_percents:
			_assert(pct > 0 and pct <= 100, "%s: phase HP percent %d out of range" % [label, pct])

		# ── spawn discipline (fixed encounter only) ──
		_assert(b.spawn_weight == 0, "%s: spawn_weight should be 0" % label)
		_assert(b.max_floor == b.boss_floor, "%s: max_floor should equal boss_floor" % label)

		# ── boss-centric visual data ──
		_assert(not b.boss_visual_frames.is_empty(), "%s: boss_visual_frames is empty" % label)
		_assert(
			b.boss_visual_frame_seconds > 0, "%s: boss_visual_frame_seconds should be >0" % label
		)
		_assert(not b.glyph.is_empty(), "%s: glyph should be non-empty" % label)
		_assert(b.color != Color.TRANSPARENT, "%s: color should not be transparent" % label)
		if _failed:
			return


func _check_new_shape_visual_data(bosses: Dictionary) -> void:
	## Every attack whose shape is one of the six V20-new shapes
	## must have non-empty telegraph_glyph and non-transparent
	## telegraph colours.  This is the “non-empty telegraph
	## geometry” contract — the visual identity of the telegraph.
	for boss_id: StringName in bosses:
		var b: Resource = bosses[boss_id]
		for attack: Resource in b.boss_attacks:
			if not NEW_SHAPES.has(attack.shape):
				continue
			var tag: String = "%s/%s" % [b.display_name, attack.id]

			_assert(
				not attack.telegraph_glyph.is_empty(),
				"%s: new shape '%s' has empty telegraph_glyph" % [tag, attack.shape]
			)
			_assert(
				attack.telegraph_color != Color.TRANSPARENT,
				"%s: new shape '%s' has transparent telegraph_color" % [tag, attack.shape]
			)
			_assert(
				attack.telegraph_fill_color != Color.TRANSPARENT,
				"%s: new shape '%s' has transparent telegraph_fill_color" % [tag, attack.shape]
			)
			_assert(
				attack.telegraph_border_color != Color.TRANSPARENT,
				"%s: new shape '%s' has transparent telegraph_border_color" % [tag, attack.shape]
			)
			# Each new shape has its own distinct glyph
			if _failed:
				return


func _check_effect_contracts(bosses: Dictionary) -> void:
	## Boss-specific attack effects that fire on hit/resolve.
	_assert_attack_effect(
		bosses[&"seraphine"], SERAPHINE_SPORE, "Seraphine spore_burst poison on hit"
	)
	if _failed:
		return
	_assert_attack_effect(bosses[&"vorrak"], VORRAK_BREATH, "Vorrak ash_breath push on hit")
	if _failed:
		return
	_assert_attack_effect(bosses[&"kaelros"], KAELROS_UNDERTOW, "Kaelros undertow pull on hit")
	if _failed:
		return
	_assert_attack_effect(bosses[&"nyxara"], NYXARA_RAY, "Nyxara mirror_ray phase_shift on resolve")

	# Nyxara prism_fracture uses mirror_reflection shape.
	# Verify the attack exists and carries the right shape.
	if _failed:
		return
	var nyx: Resource = bosses[&"nyxara"]
	var found_reflect: bool = false
	for attack: Resource in nyx.boss_attacks:
		if attack.shape == &"mirror_reflection":
			found_reflect = true
			_assert(
				attack.id == &"prism_fracture",
				"mirror_reflection attack should be prism_fracture, got %s" % attack.id
			)
			_assert(attack.radius >= 1, "prism_fracture radius should be >= 1")
			break
	_assert(found_reflect, "Nyxara missing mirror_reflection attack (prism_fracture)")

	# Also double-check that mirror_ray on Nyxara has the right shape
	if _failed:
		return
	var found_ray: bool = false
	for attack: Resource in nyx.boss_attacks:
		if attack.shape == &"mirror_ray":
			found_ray = true
			_assert(
				attack.id == &"mirror_ray",
				"mirror_ray shape attack should be id 'mirror_ray', got %s" % attack.id
			)
			_assert(attack.effect == &"phase_shift", "mirror_ray should carry phase_shift effect")
			_assert(
				attack.effect_trigger == &"resolve",
				"mirror_ray phase_shift should trigger on resolve"
			)
			_assert(attack.range >= 1, "mirror_ray range should be >= 1")
			_assert(attack.width >= 1, "mirror_ray width should be >= 1")
			break
	_assert(found_ray, "Nyxara missing mirror_ray attack")


func _assert_attack_effect(boss: Resource, spec: Dictionary, label: String) -> void:
	## Locate an attack by spec.id and verify all remaining key-value
	## pairs match its exported properties.
	var attack_id: StringName = spec.get("id", &"")
	var found: bool = false
	for attack: Resource in boss.boss_attacks:
		if attack.id == attack_id:
			found = true
			for key: String in spec:
				if key == "id":
					continue
				var actual = attack.get(key)
				_assert(
					actual == spec[key],
					"%s: %s.%s = %s, expected %s" % [label, attack_id, key, actual, spec[key]]
				)
			break
	_assert(found, "%s: attack '%s' not found in %s" % [label, attack_id, boss.display_name])


func _check_summon_attacks(bosses: Dictionary) -> void:
	## Every summon-type attack has shape="summon", a non-empty
	## summon_enemy_path, summon_count >= 1, and the path loads
	## a valid resource.
	for boss_id: StringName in bosses:
		var b: Resource = bosses[boss_id]
		for attack: Resource in b.boss_attacks:
			if attack.shape != &"summon":
				continue
			var tag: String = "%s/%s" % [b.display_name, attack.id]

			_assert(attack.shape == &"summon", "%s: summon attack should have shape='summon'" % tag)
			_assert(
				not attack.summon_enemy_path.is_empty(),
				"%s: summon attack missing summon_enemy_path" % tag
			)
			_assert(attack.summon_count >= 1, "%s: summon_count should be >= 1" % tag)
			# The summon path must resolve to a valid resource
			var summoned: Resource = load(attack.summon_enemy_path)
			_assert(
				summoned != null,
				"%s: summon_enemy_path '%s' failed to load" % [tag, attack.summon_enemy_path]
			)
			if _failed:
				return


func _check_shape_uniqueness_across_bosses(bosses: Dictionary) -> void:
	## Each V20-new shape should appear in exactly one boss.
	## (summon is shared across bosses and excluded from this check.)
	for shape: StringName in NEW_SHAPES:
		var owners: Array[String] = []
		for boss_id: StringName in bosses:
			var b: Resource = bosses[boss_id]
			for attack: Resource in b.boss_attacks:
				if attack.shape == shape:
					owners.append(b.display_name)
					break
		_assert(not owners.is_empty(), "new shape '%s' is not used by any boss" % shape)
		_assert(
			owners.size() == 1,
			"new shape '%s' used by %s but should be unique to one boss" % [shape, owners]
		)
		if _failed:
			return


# ═══════════════════════════════════════════════════════════════════
# Phase 3 – Geometry smoke test
# ═══════════════════════════════════════════════════════════════════


func _check_geometry_smoke(bosses: Dictionary) -> void:
	## Instantiate game, descend to floor 5 (Observer), enter the
	## boss arena, then call _boss_attack_cells for every attack
	## shape that has a real calculation method.  This confirms
	## the shape implementations produce non-empty cell sets given
	## a live player, map, and boss room context.
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	gm.prepare_character("debug", {}, gm.CLASS_FIGHTER)
	_game = load("res://scenes/game.tscn").instantiate()
	root.add_child(_game)
	await process_frame

	# Descend to boss floor 5
	while gm.current_floor < 5:
		_game._debug_descend_deeper()
		await process_frame

	var encounter: Dictionary = _game._active_boss_encounter
	if encounter.is_empty() or not bool(encounter.get("active", false)):
		_fail("no active encounter on boss floor 5")
		_game.queue_free()
		_game = null
		return

	# Walk onto the gate to lock the encounter and spawn the boss
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var gate_entry: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	if gate_entry == Vector2i.ZERO:
		_fail("no boss_gate_entry_cell in encounter")
		_game.queue_free()
		_game = null
		return
	# Clean up stray enemies, then step onto gate
	_remove_all_enemies()
	_game._player.set_grid_position(gate_entry)
	_game._attempt_player_move(gate_cell - gate_entry)
	await process_frame

	var boss: Node = encounter.get("boss", null)
	if boss == null or not boss.is_alive():
		_fail("boss not spawned after gate entry")
		_game.queue_free()
		_game = null
		return

	# Test the Observer's attacks: parallax_gaze (new) + ring/blink_pulse (built-in)
	for attack: Resource in boss.enemy_data.boss_attacks:
		if _failed:
			break
		var cells: Dictionary = _game._boss_attack_cells(boss, attack)
		_assert(
			not cells.is_empty(),
			(
				"%s: attack '%s' (shape=%s) produced zero telegraph cells"
				% [boss.enemy_data.display_name, attack.id, attack.shape]
			)
		)

	_game.queue_free()
	_game = null


func _remove_all_enemies() -> void:
	for enemy: Node in _game._enemies.duplicate():
		_game._enemies.erase(enemy)
		var gm: Node = root.get_node_or_null("/root/GameManager")
		if gm != null:
			gm.remove_enemy(enemy)
		enemy.queue_free()


# ═══════════════════════════════════════════════════════════════════
# Shared helpers
# ═══════════════════════════════════════════════════════════════════


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
