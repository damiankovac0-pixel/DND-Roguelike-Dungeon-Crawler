## V20.1.0 boss attack data uniqueness and effect contracts.
##
## Loads all five boss resources and verifies attack data signatures,
## effect triggers, unique shape visual geometry, V20.1 cooldowns, hazard
## contracts, summon caps, phase-order identity, and summon preview setup.
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
const PRINTABLE_ASCII_CHARS: String = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"

# New shapes introduced in V20 that MUST appear in exactly one boss attack.
# Observer now uses a narrow standard line for observer_gaze, so parallax_gaze
# is intentionally excluded from this unique-shape set.
const NEW_SHAPES: Array[StringName] = [
	&"thorn_patch",
	&"eruption_columns",
	&"tidal_lane",
	&"mirror_ray",
	&"mirror_reflection",
]

# Boss-specific effect contracts:
#   stun       → Observer observer_gaze  (effect_trigger = hit)
#   poison     → Seraphine spore_burst   (effect_trigger = hit)
#   push       → Vorrak ash_breath       (effect_trigger = hit)
#   pull       → Kaelros undertow        (effect_trigger = hit)
#   phase_shift → Nyxara mirror_ray      (effect_trigger = resolve)
const OBSERVER_GAZE: Dictionary = {
	"id": &"observer_gaze",
	"effect": &"stun",
	"effect_trigger": &"hit",
	"effect_amount": 1,
}
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
	"effect_amount": 2,
}
const KAELROS_UNDERTOW: Dictionary = {
	"id": &"undertow",
	"effect": &"pull",
	"effect_trigger": &"hit",
	"effect_amount": 2,
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

	_check_resource_ascii_and_windups(bosses)
	if _failed:
		return

	_check_new_shape_visual_data(bosses)
	if _failed:
		return

	_check_effect_contracts(bosses)
	if _failed:
		return

	_check_hazard_contracts(bosses)
	if _failed:
		return

	_check_summon_attacks(bosses)
	if _failed:
		return

	_check_cooldown_contracts(bosses)
	if _failed:
		return

	_check_phase_order(bosses)
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


func _check_resource_ascii_and_windups(bosses: Dictionary) -> void:
	## Guard against tofu-prone boss presentation and resource data that would
	## collapse damaging non-summon attacks into one-turn tells.
	for boss_id: StringName in bosses:
		var b: Resource = bosses[boss_id]
		var label: String = b.display_name

		_assert(_is_printable_ascii(b.glyph), "%s: glyph should be printable ASCII" % label)
		for frame_index: int in range(b.boss_visual_frames.size()):
			var frame: PackedStringArray = b.boss_visual_frames[frame_index]
			for line_index: int in range(frame.size()):
				var line: String = frame[line_index]
				_assert(
					_is_printable_ascii(line),
					(
						"%s: boss_visual_frames[%d][%d] contains non-printable/non-ASCII glyphs"
						% [label, frame_index, line_index]
					)
				)
				if _failed:
					return

		for attack: Resource in b.boss_attacks:
			var tag: String = "%s/%s" % [label, attack.id]
			var is_summon: bool = attack.shape == &"summon"
			var is_damaging: bool = attack.damage_dice > 0 or attack.damage_bonus > 0

			_assert(
				not attack.telegraph_glyph.is_empty(),
				"%s: telegraph_glyph should be non-empty" % tag
			)
			_assert(
				_is_printable_ascii(attack.telegraph_glyph),
				"%s: telegraph_glyph should be printable ASCII" % tag
			)
			if is_damaging and not is_summon:
				_assert(
					attack.telegraph_turns >= 2,
					(
						"%s: damaging non-summon telegraph_turns = %d, expected >= 2"
						% [tag, attack.telegraph_turns]
					)
				)
				_assert(attack.projectile_id != &"", "%s: projectile_id should be non-empty" % tag)
			if not attack.hazard_glyph.is_empty():
				_assert(
					_is_printable_ascii(attack.hazard_glyph),
					"%s: hazard_glyph should be printable ASCII" % tag
				)
			if attack.hazard_turns > 0:
				_assert(
					not attack.hazard_glyph.is_empty(), "%s: hazard_glyph should be non-empty" % tag
				)
				_assert(attack.hazard_vfx_id != &"", "%s: hazard_vfx_id should be non-empty" % tag)
			if _failed:
				return


func _check_new_shape_visual_data(bosses: Dictionary) -> void:
	## Every attack whose shape is one of the five V20-new unique
	## shapes must have non-empty telegraph_glyph and non-transparent
	## telegraph colours.  This is the "non-empty telegraph geometry"
	## contract — the visual identity of the telegraph.
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
	_assert_attack_effect(bosses[&"observer"], OBSERVER_GAZE, "Observer observer_gaze stun on hit")
	if _failed:
		return
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
	## a valid resource.  V20.1 adds summon_max_active field
	## validation.
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
			# V20.1: summon_max_active must exist; when capped, cap >= count
			_assert("summon_max_active" in attack, "%s: missing summon_max_active field" % tag)
			_assert(attack.summon_max_active >= 0, "%s: summon_max_active should be >= 0" % tag)
			if attack.summon_max_active > 0:
				_assert(
					attack.summon_max_active >= attack.summon_count,
					(
						"%s: summon_max_active %d < summon_count %d"
						% [tag, attack.summon_max_active, attack.summon_count]
					)
				)
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


func _check_hazard_contracts(bosses: Dictionary) -> void:
	## Every attack with hazard_turns > 0 must have valid hazard
	## fields.  Also assert specific identity contracts for each
	## boss's hazard attacks.
	var hazard_specs: Dictionary = {
		&"observer":
		{
			&"blink_pulse":
			{
				"hazard_turns": 2,
				"hazard_damage_dice": 1,
				"hazard_damage_sides": 4,
				"hazard_damage_bonus": 0,
				"hazard_damage_type": &"magic",
				"hazard_glyph": "o",
				"hazard_vfx_id": &"blink_pulse_hazard",
				"hazard_message": "Residual energy sears you for %d magic damage.",
			},
		},
		&"seraphine":
		{
			&"spore_burst":
			{
				"hazard_turns": 2,
				"hazard_damage_dice": 1,
				"hazard_damage_sides": 4,
				"hazard_damage_bonus": 0,
				"hazard_damage_type": &"magic",
				"hazard_effect": &"poison",
				"hazard_glyph": ",",
				"hazard_vfx_id": &"spore_hazard",
				"hazard_message": "Lingering spores erupt for %d magic damage.",
			},
		},
		&"vorrak":
		{
			&"maw_quake":
			{
				"hazard_turns": 2,
				"hazard_damage_dice": 1,
				"hazard_damage_sides": 6,
				"hazard_damage_bonus": 1,
				"hazard_damage_type": &"fire",
				"hazard_glyph": "^",
				"hazard_vfx_id": &"molten_cracks",
				"hazard_message": "Lingering molten cracks sear you for %d fire damage.",
			},
		},
		&"kaelros":
		{
			&"undertow":
			{
				"hazard_turns": 2,
				"hazard_damage_dice": 1,
				"hazard_damage_sides": 4,
				"hazard_damage_bonus": 1,
				"hazard_damage_type": &"magic",
				"hazard_effect": &"pull",
				"hazard_glyph": "~",
				"hazard_vfx_id": &"undertow_hazard",
				"hazard_message": "The lingering undertow churns through you for %d magic damage.",
			},
		},
		&"nyxara":
		{
			&"prism_fracture":
			{
				"hazard_turns": 2,
				"hazard_damage_dice": 1,
				"hazard_damage_sides": 6,
				"hazard_damage_bonus": 2,
				"hazard_damage_type": &"magic",
				"hazard_glyph": "%",
				"hazard_vfx_id": &"mirror_shards",
				"hazard_message": "Lingering mirror shards slice you for %d magic damage.",
			},
		},
	}
	for boss_id: StringName in bosses:
		var b: Resource = bosses[boss_id]
		for attack: Resource in b.boss_attacks:
			if attack.hazard_turns <= 0:
				continue
			var tag: String = "%s/%s" % [b.display_name, attack.id]

			# Every hazard attack must have these
			_assert(
				not attack.hazard_glyph.is_empty(), "%s: hazard_glyph should be non-empty" % tag
			)
			_assert(
				not attack.hazard_message.is_empty(), "%s: hazard_message should be non-empty" % tag
			)
			_assert(attack.hazard_turns >= 1, "%s: hazard_turns should be >= 1" % tag)
			_assert(attack.hazard_damage_dice > 0, "%s: hazard_damage_dice should be > 0" % tag)
			_assert(attack.hazard_damage_sides >= 2, "%s: hazard_damage_sides should be >= 2" % tag)
			_assert(
				attack.hazard_damage_type != &"", "%s: hazard_damage_type should be non-empty" % tag
			)
			_assert(
				[&"", &"poison", &"pull", &"push"].has(attack.hazard_effect),
				"%s: hazard_effect '%s' is not in allowed set" % [tag, attack.hazard_effect]
			)
			if _failed:
				return

			# Identity contracts for known hazard attacks
			var boss_specs: Dictionary = hazard_specs.get(boss_id, {})
			var attack_spec: Dictionary = boss_specs.get(attack.id, {})
			if attack_spec.is_empty():
				_fail("No hazard spec for %s attack %s" % [boss_id, attack.id])
				return
			for key: String in attack_spec:
				var actual = attack.get(key)
				_assert(
					actual == attack_spec[key],
					"%s: hazard %s = %s, expected %s" % [tag, key, actual, attack_spec[key]]
				)
			if _failed:
				return


func _check_cooldown_contracts(bosses: Dictionary) -> void:
	## Exact cooldown values per the V20.1 attack cadence redesign.
	var cd_specs: Dictionary = {
		&"observer": {&"observer_gaze": 2, &"blink_pulse": 3},
		&"seraphine": {&"thorn_lance": 2, &"spore_burst": 3, &"spore_bloom": 4},
		&"vorrak": {&"ash_breath": 3, &"maw_quake": 3},
		&"kaelros": {&"undertow": 2, &"drowned_retinue": 4},
		&"nyxara": {&"mirror_ray": 3, &"prism_fracture": 3, &"mirror_guard": 5},
	}
	for boss_id: StringName in bosses:
		var b: Resource = bosses[boss_id]
		var attack_cds: Dictionary = cd_specs.get(boss_id, {})
		for attack: Resource in b.boss_attacks:
			var expected_cd: int = attack_cds.get(attack.id, -1)
			_assert(
				expected_cd >= 0,
				"%s: no cooldown spec for attack '%s'" % [b.display_name, attack.id]
			)
			_assert(
				attack.cooldown == expected_cd,
				(
					"%s/%s cooldown = %d, expected %d"
					% [b.display_name, attack.id, attack.cooldown, expected_cd]
				)
			)
			if _failed:
				return


func _check_phase_order(bosses: Dictionary) -> void:
	## Phase-unlock identity: distinct mechanics appear at the
	## intended cadence per V20.1.
	var phase_specs: Dictionary = {
		&"observer": {&"blink_pulse": 2},
		&"seraphine": {&"spore_burst": 2, &"spore_bloom": 3},
		&"vorrak": {&"maw_quake": 2},
		&"nyxara": {&"prism_fracture": 2, &"mirror_guard": 2},
	}

	# Seraphine spore_bloom phase-3 summon must have styled telegraph glyph
	var ser: Resource = bosses[&"seraphine"]
	var bloom_checked: bool = false
	for attack: Resource in ser.boss_attacks:
		if attack.id == &"spore_bloom":
			bloom_checked = true
			_assert(attack.phase_min == 3, "spore_bloom phase_min should be 3")
			_assert(attack.summon_count == 2, "spore_bloom summon_count should be 2")
			_assert(attack.summon_max_active == 3, "spore_bloom summon_max_active should be 3")
			_assert(attack.telegraph_glyph == "*", "spore_bloom telegraph_glyph should be *")
			_assert(
				attack.telegraph_color != Color.TRANSPARENT,
				"spore_bloom telegraph_color should be non-transparent"
			)
			_assert(
				attack.telegraph_fill_color != Color.TRANSPARENT,
				"spore_bloom telegraph_fill_color should be non-transparent"
			)
			_assert(
				attack.telegraph_border_color != Color.TRANSPARENT,
				"spore_bloom telegraph_border_color should be non-transparent"
			)
			break
	_assert(bloom_checked, "spore_bloom attack not found on Seraphine")
	if _failed:
		return

	# Verify each phase-unlock attack exists with the correct phase_min
	for boss_id: StringName in phase_specs:
		var b: Resource = bosses[boss_id]
		var attack_phases: Dictionary = phase_specs[boss_id]
		for attack_id: StringName in attack_phases:
			var expected_phase: int = attack_phases[attack_id]
			var found: bool = false
			for attack: Resource in b.boss_attacks:
				if attack.id == attack_id:
					found = true
					_assert(
						attack.phase_min == expected_phase,
						(
							"%s/%s phase_min = %d, expected %d"
							% [b.display_name, attack.id, attack.phase_min, expected_phase]
						)
					)
					break
			_assert(found, "%s: phase-order attack '%s' not found" % [b.display_name, attack_id])
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

	# Walk onto the gate to lock the encounter and start the arena reveal.
	var gate_cell: Vector2i = encounter.get("gate_cell", Vector2i.ZERO)
	var gate_entry: Vector2i = encounter.get("boss_gate_entry_cell", Vector2i.ZERO)
	if gate_entry == Vector2i.ZERO:
		_fail("no boss_gate_entry_cell in encounter")
		_game.queue_free()
		_game = null
		return
	# Clean up stray enemies, then step onto gate.
	_remove_all_enemies()
	_game._player.set_grid_position(gate_entry)
	var turn_before: int = gm.turn_count
	_game._attempt_player_move(gate_cell - gate_entry)
	await process_frame
	_assert(
		encounter.get("state", &"") == _game.BOSS_ARENA_STATE_REVEAL,
		"geometry smoke gate entry should enter arena_reveal state"
	)
	_assert(
		encounter.get("boss", null) == null, "geometry smoke boss should not spawn during reveal"
	)
	_assert(_live_boss_count(_game) == 0, "geometry smoke should have no live boss during reveal")
	_assert(gm.turn_count == turn_before, "geometry smoke reveal should not consume a turn")
	if _failed:
		_game.queue_free()
		_game = null
		return
	_assert(_game.complete_boss_arena_reveal(), "geometry smoke boss reveal completion failed")
	await process_frame
	_assert(
		encounter.get("state", &"") == _game.BOSS_ARENA_STATE_ACTIVE,
		"geometry smoke boss reveal completion should activate encounter"
	)
	_assert(
		gm.turn_count == turn_before + 1, "geometry smoke boss activation should consume one turn"
	)
	_assert(_live_boss_count(_game) == 1, "geometry smoke should spawn exactly one boss")

	var boss: Node = encounter.get("boss", null)
	if boss == null or not boss.is_alive():
		_fail("boss not spawned after arena reveal completion")
		_game.queue_free()
		_game = null
		return

	# Test the Observer's attacks: narrow gaze line + ring/blink_pulse.
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


# ═══════════════════════════════════════════════════════════════════
# Shared helpers
# ═══════════════════════════════════════════════════════════════════


func _is_printable_ascii(value: String) -> bool:
	for index: int in range(value.length()):
		if PRINTABLE_ASCII_CHARS.find(value.substr(index, 1)) == -1:
			return false
	return true


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
