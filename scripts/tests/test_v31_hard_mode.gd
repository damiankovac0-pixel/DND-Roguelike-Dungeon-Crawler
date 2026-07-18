## Deterministic V31 Hard-mode gameplay contract coverage.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v31_hard_mode.gd
extends SceneTree

const EnemyDataScript = preload("res://scripts/resources/enemy_data.gd")
const BossAttackDataScript = preload("res://scripts/resources/boss_attack_data.gd")
const EnemyScript = preload("res://scripts/entities/enemy.gd")

const BOSS_PATHS: Dictionary = {
	&"observer": "res://resources/enemies/the_observer.tres",
	&"seraphine": "res://resources/enemies/seraphine_thorn_saint.tres",
	&"vorrak": "res://resources/enemies/vorrak_ashen_maw.tres",
	&"kaelros": "res://resources/enemies/kaelros_drowned_king.tres",
	&"nyxara": "res://resources/enemies/nyxara_mirror_witch.tres",
}

var _failed: bool = false
var _game_manager: Node
var _difficulty_snapshot: StringName
var _history_snapshot: Array
var _floor_snapshot: int
var _name_snapshot: String
var _scores_snapshot: Dictionary
var _class_snapshot: StringName
var _debug_snapshot: bool


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		printerr("GameManager autoload missing")
		quit(1)
		return
	_snapshot_game_manager()
	_game_manager.character_history = [
		{"name": "V31 fixture", "victory": true, "difficulty": &"normal"}
	]
	_game_manager.set_pending_difficulty(&"hard")
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.sensory_feedback.set_audio_enabled(false, false, false)
	_expect(game._player != null, "game fixture did not initialize its player")
	if not _failed:
		_test_elite_chance_and_eligibility(game)
	if not _failed:
		_test_owned_deep_duplicates(game)
	if not _failed:
		_test_floor_hard_elite_ordering(game)
	if not _failed:
		_test_elite_identity_behavior_and_cadence(game)
	if not _failed:
		await _test_rewards_and_rerolls(game)
	if not _failed:
		_test_hard_boss_scaling(game)
	if not _failed:
		_test_boss_immunities(game)
	await _finish(game)


func _snapshot_game_manager() -> void:
	_difficulty_snapshot = _game_manager.pending_difficulty
	_history_snapshot = _game_manager.character_history.duplicate(true)
	_floor_snapshot = _game_manager.current_floor
	_name_snapshot = _game_manager.pending_character_name
	_scores_snapshot = _game_manager.pending_ability_scores.duplicate(true)
	_class_snapshot = _game_manager.pending_character_class
	_debug_snapshot = _game_manager.pending_debug_loadout


func _finish(game: Node) -> void:
	if is_instance_valid(game):
		var sensory: Node = game.sensory_feedback
		for audio_player: AudioStreamPlayer in sensory._audio_players:
			audio_player.stop()
			audio_player.stream = null
		if is_instance_valid(sensory._ambience_player):
			sensory._ambience_player.stop()
			sensory._ambience_player.stream = null
		if is_instance_valid(sensory._music_player):
			sensory._music_player.stop()
			sensory._music_player.stream = null
		sensory._ambience_stream = null
		sensory._boss_music_stream = null
		sensory._boss_climax_stream = null
		sensory._cue_streams.clear()
		sensory._boss_attack_streams.clear()
		await process_frame
		game.queue_free()
		await process_frame
	_game_manager.pending_difficulty = _difficulty_snapshot
	_game_manager.character_history = _history_snapshot.duplicate(true)
	_game_manager.current_floor = _floor_snapshot
	_game_manager.pending_character_name = _name_snapshot
	_game_manager.pending_ability_scores = _scores_snapshot.duplicate(true)
	_game_manager.pending_character_class = _class_snapshot
	_game_manager.pending_debug_loadout = _debug_snapshot
	if _failed:
		quit(1)
		return
	print("V31 Hard-mode gameplay contract checks passed")
	quit(0)


func _set_difficulty(difficulty: StringName) -> void:
	_game_manager.pending_difficulty = difficulty


func _test_elite_chance_and_eligibility(game: Node) -> void:
	_expect_equal(game._elite_chance_for_floor(2), 0, "elites must not roll before floor 3")
	_expect_equal(game._elite_chance_for_floor(3), 8, "floor 3 elite chance must begin at 8%")
	_expect_equal(game._elite_chance_for_floor(7), 8, "8% band must include floor 7")
	_expect_equal(game._elite_chance_for_floor(8), 10, "floor 8 must begin the 10% band")
	_expect_equal(game._elite_chance_for_floor(12), 10, "10% band must include floor 12")
	_expect_equal(game._elite_chance_for_floor(13), 12, "floor 13 must begin the 12% band")
	_expect_equal(game._elite_chance_for_floor(28), 18, "elite chance must reach 18% at floor 28")
	_expect_equal(game._elite_chance_for_floor(100), 18, "elite chance must remain capped at 18%")

	var regular: Resource = _make_enemy_data("Boundary Foe")
	var boss: Resource = _make_enemy_data("Boundary Boss")
	boss.is_boss = true
	_set_difficulty(&"hard")
	_expect(game._should_make_elite(regular, 3, true, 1), "roll 1 must pass at floor 3")
	_expect(game._should_make_elite(regular, 3, true, 8), "roll equal to chance must pass")
	_expect(not game._should_make_elite(regular, 3, true, 0), "roll 0 must be rejected")
	_expect(not game._should_make_elite(regular, 3, true, 9), "roll above chance must fail")
	_expect(not game._should_make_elite(regular, 3, false, 1), "regular summons must be excluded")
	_expect(not game._should_make_elite(regular, 15, false, 1), "boss summons must be excluded")
	_expect(not game._should_make_elite(regular, 25, false, 1), "ambush spawns must be excluded")
	_expect(
		not game._should_make_elite(regular, 2, true, 1),
		"floor eligibility must gate a passing roll"
	)
	_expect(not game._should_make_elite(boss, 25, true, 1), "bosses must never become elites")
	_expect(not game._should_make_elite(null, 25, true, 1), "null templates must be ineligible")
	_set_difficulty(&"normal")
	_expect(
		not game._should_make_elite(regular, 25, true, 1), "Normal must reject every elite roll"
	)
	_set_difficulty(&"hard")
	var excluded_spawn: Node = game._spawn_enemy_instance(regular, Vector2i(1, 1), 25, false, false)
	_expect(not excluded_spawn.is_elite, "allow_elite=false must remain authoritative at spawn")
	_dispose_enemy(game, excluded_spawn)


func _test_owned_deep_duplicates(game: Node) -> void:
	_set_difficulty(&"hard")
	var template: Resource = _make_enemy_data("Owned Template")
	template.ranged_damage_sides = 6
	template.ranged_damage_bonus = 2
	var attack_template: Resource = BossAttackDataScript.new()
	attack_template.id = &"nested_contract"
	attack_template.damage_bonus = 7
	var attacks: Array[Resource] = [attack_template]
	template.boss_attacks = attacks
	var phases: Array[int] = [70, 40]
	template.boss_phase_hp_percents = phases

	var first: Node = game._spawn_enemy_instance(template, Vector2i(2, 1), 1, false, false)
	var second: Node = game._spawn_enemy_instance(template, Vector2i(3, 1), 1, false, false)
	_expect(first.enemy_data != template, "first spawn must own its EnemyData clone")
	_expect(second.enemy_data != template, "second spawn must own its EnemyData clone")
	_expect(first.enemy_data != second.enemy_data, "two spawns must not share EnemyData")
	_expect(
		first.enemy_data.boss_attacks[0] != attack_template,
		"spawn clone must own nested attack resources"
	)
	_expect(
		first.enemy_data.boss_attacks[0] != second.enemy_data.boss_attacks[0],
		"sibling spawns must not share nested attacks"
	)
	first.enemy_data.display_name = "Mutated Instance"
	first.enemy_data.boss_attacks[0].damage_bonus = 99
	first.enemy_data.boss_phase_hp_percents[0] = 5
	game._scale_enemy_special_attacks(first, 3)
	_expect_equal(
		template.display_name, "Owned Template", "instance identity leaked into its template"
	)
	_expect_equal(
		second.enemy_data.display_name, "Owned Template", "instance identity leaked to sibling"
	)
	_expect_equal(attack_template.damage_bonus, 7, "nested attack mutation leaked into template")
	_expect_equal(
		second.enemy_data.boss_attacks[0].damage_bonus,
		7,
		"nested attack mutation leaked to sibling"
	)
	_expect_equal(
		template.boss_phase_hp_percents[0], 70, "nested array mutation leaked into template"
	)
	_expect_equal(
		second.enemy_data.boss_phase_hp_percents[0], 70, "nested array mutation leaked to sibling"
	)
	_expect_equal(first.enemy_data.ranged_damage_bonus, 5, "special scaling missed owned clone")
	_expect_equal(template.ranged_damage_bonus, 2, "special scaling mutated source template")
	_expect_equal(second.enemy_data.ranged_damage_bonus, 2, "special scaling mutated sibling clone")
	_dispose_enemy(game, first)
	_dispose_enemy(game, second)


func _test_floor_hard_elite_ordering(game: Node) -> void:
	var template: Resource = _make_enemy_data("Ordering Foe")
	template.max_hp = 80
	template.armor_class = 10
	template.attack_bonus = 2
	template.damage_bonus = 3
	template.xp_reward = 100
	template.ranged_attack_range = 6
	template.ranged_attack_interval = 4
	template.ranged_damage_sides = 6
	template.ranged_damage_bonus = 2
	template.fireball_range = 5
	template.fireball_interval = 4
	template.fireball_damage_dice = 1
	template.fireball_damage_sides = 6
	template.fireball_damage_bonus = 1

	_set_difficulty(&"normal")
	var normal: Node = game._spawn_enemy_instance(template, Vector2i(4, 1), 11, true, false)
	_assert_enemy_stats(normal, 91, 11, 3, 4, 130, 3, 2, "Normal floor scaling")
	_expect(not normal.is_elite, "Normal scaled enemy became elite")

	_set_difficulty(&"hard")
	var hard: Node = game._spawn_enemy_instance(template, Vector2i(5, 1), 11, true, false)
	_assert_enemy_stats(hard, 102, 11, 4, 5, 130, 3, 2, "Hard ordinary scaling")

	var elite: Node = game._spawn_enemy_instance(template, Vector2i(6, 1), 11, false, false)
	game._apply_elite_identity(elite, elite.enemy_data)
	game._scale_enemy_for_floor(elite, 11)
	_assert_enemy_stats(elite, 128, 12, 5, 6, 195, 4, 3, "Hard elite scaling")
	_expect_equal(
		elite.stats_component.current_hp, 128, "current HP must be set once after all multipliers"
	)
	_expect_equal(template.max_hp, 80, "floor/Hard/elite scaling leaked into source HP")
	_expect_equal(
		template.ranged_damage_bonus, 2, "special scaling leaked into source ranged damage"
	)
	_expect_equal(
		template.fireball_damage_bonus, 1, "special scaling leaked into source fireball damage"
	)
	_dispose_enemy(game, normal)
	_dispose_enemy(game, hard)
	_dispose_enemy(game, elite)


func _assert_enemy_stats(
	enemy: Node,
	hp: int,
	armor: int,
	attack: int,
	damage: int,
	xp: int,
	ranged_bonus: int,
	fireball_bonus: int,
	label: String
) -> void:
	_expect_equal(enemy.stats_component.max_hp, hp, "%s HP ordering regressed" % label)
	_expect_equal(enemy.stats_component.current_hp, hp, "%s current HP is stale" % label)
	_expect_equal(enemy.stats_component.base_armor_class, armor, "%s AC regressed" % label)
	_expect_equal(enemy.stats_component.base_attack_bonus, attack, "%s attack regressed" % label)
	_expect_equal(
		enemy.stats_component.base_damage_bonus, damage, "%s base damage regressed" % label
	)
	_expect_equal(enemy.stats_component.xp_reward, xp, "%s XP rounding regressed" % label)
	_expect_equal(
		enemy.enemy_data.ranged_damage_bonus, ranged_bonus, "%s ranged damage regressed" % label
	)
	_expect_equal(
		enemy.enemy_data.fireball_damage_bonus,
		fireball_bonus,
		"%s fireball damage regressed" % label
	)


func _test_elite_identity_behavior_and_cadence(game: Node) -> void:
	var caller_data: Resource = _make_enemy_data("Invoker")
	caller_data.color = Color(0.2, 0.4, 0.6, 1.0)
	caller_data.summon_interval = 5
	caller_data.fireball_range = 5
	caller_data.fireball_interval = 4
	caller_data.fireball_damage_dice = 1
	caller_data.ranged_attack_range = 6
	caller_data.ranged_attack_interval = 4
	var caller: Node = EnemyScript.new()
	game._apply_elite_identity(caller, caller_data)
	_expect(caller.is_elite, "elite identity flag was not set before initialization")
	_expect_equal(caller.elite_behavior, &"caller", "summon behavior must have first priority")
	_expect_equal(caller_data.display_name, "Elite Invoker", "elite name prefix regressed")
	_expect_equal(caller_data.summon_interval, 4, "caller cadence must improve by exactly one")
	_expect_equal(caller_data.fireball_interval, 4, "caller must not also gain volatile cadence")
	_expect_equal(
		caller_data.ranged_attack_interval, 4, "caller must not also gain skirmisher cadence"
	)
	_expect_color(
		caller_data.color,
		Color(0.2, 0.4, 0.6, 1.0).lerp(game.ELITE_GOLD_COLOR, 0.62),
		"elite identity tint"
	)

	var volatile_data: Resource = _make_enemy_data("Bomber")
	volatile_data.fireball_range = 5
	volatile_data.fireball_interval = 3
	volatile_data.fireball_damage_dice = 1
	volatile_data.ranged_attack_range = 6
	volatile_data.ranged_attack_interval = 5
	var volatile: Node = EnemyScript.new()
	game._apply_elite_identity(volatile, volatile_data)
	_expect_equal(volatile.elite_behavior, &"volatile", "fireball behavior must outrank ranged")
	_expect_equal(
		volatile_data.fireball_interval, 2, "volatile cadence floor or decrement regressed"
	)
	_expect_equal(
		volatile_data.ranged_attack_interval, 5, "volatile elite gained a second behavior"
	)

	var skirmisher_data: Resource = _make_enemy_data("Archer")
	skirmisher_data.ranged_attack_range = 4
	skirmisher_data.ai_preferred_range = 3
	skirmisher_data.ranged_attack_interval = 3
	var skirmisher: Node = EnemyScript.new()
	game._apply_elite_identity(skirmisher, skirmisher_data)
	_expect_equal(skirmisher.elite_behavior, &"skirmisher", "ranged elite behavior regressed")
	_expect_equal(skirmisher_data.ai_preferred_range, 4, "preferred range must rise by one and cap")
	_expect_equal(skirmisher_data.ranged_attack_interval, 2, "ranged cadence floor regressed")

	var hunter_data: Resource = _make_enemy_data("Pursuer")
	var hunter: Node = EnemyScript.new()
	game._apply_elite_identity(hunter, hunter_data)
	_expect_equal(hunter.elite_behavior, &"hunter", "plain elite must use hunter behavior")
	_expect_equal(game._enemy_chase_radius(hunter), 10.0, "hunter chase radius must be 10")
	var ordinary: Node = EnemyScript.new()
	_expect_equal(game._enemy_chase_radius(ordinary), 8.0, "ordinary chase radius must remain 8")
	_expect_equal(
		game._advance_enemy_action(hunter), 1, "elite must receive one action count per phase"
	)
	_expect_equal(
		game._advance_enemy_action(ordinary), 1, "ordinary action cadence must remain unchanged"
	)
	caller.free()
	volatile.free()
	skirmisher.free()
	hunter.free()
	ordinary.free()


func _test_rewards_and_rerolls(game: Node) -> void:
	var reward_data: Resource = _make_enemy_data("Reward Foe")
	var enemy: Node = game._spawn_enemy_instance(reward_data, Vector2i(7, 1), 7, false, false)
	_game_manager.current_floor = 7
	var saw_single_round_boundary: bool = false
	for seed_value: int in range(101, 133):
		_set_difficulty(&"normal")
		enemy.is_elite = false
		seed(seed_value)
		var normal_reward: int = game._roll_enemy_gold_reward(enemy)
		_set_difficulty(&"hard")
		seed(seed_value)
		var hard_reward: int = game._roll_enemy_gold_reward(enemy)
		enemy.is_elite = true
		seed(seed_value)
		var elite_reward: int = game._roll_enemy_gold_reward(enemy)
		_expect_equal(
			hard_reward,
			max(1, roundi(normal_reward * 0.90)),
			"Hard ordinary gold must apply 0.90 after the base roll"
		)
		_expect_equal(
			elite_reward,
			max(1, roundi(normal_reward * 0.90 * 1.60)),
			"elite gold must apply the net 1.44 multiplier with one final rounding"
		)
		var staged_rounding: int = roundi(roundi(normal_reward * 0.90) * 1.60)
		if staged_rounding != roundi(normal_reward * 0.90 * 1.60):
			saw_single_round_boundary = true
	_expect(
		saw_single_round_boundary, "reward fixtures did not exercise a staged-rounding boundary"
	)
	_dispose_enemy(game, enemy)

	game._shop_reroll_count = 0
	_game_manager.current_floor = 1
	_set_difficulty(&"normal")
	_expect_equal(game._get_shop_reroll_cost(), 33, "Normal first reroll must remain 33 on floor 1")
	_set_difficulty(&"hard")
	_expect_equal(game._get_shop_reroll_cost(), 38, "Hard reroll must ceil 33 x 1.15 to 38")
	_game_manager.current_floor = 2
	_set_difficulty(&"normal")
	_expect_equal(game._get_shop_reroll_cost(), 41, "Normal floor-2 reroll must remain 41")
	_set_difficulty(&"hard")
	_expect_equal(game._get_shop_reroll_cost(), 48, "Hard reroll must ceil 41 x 1.15 to 48")
	_game_manager.current_floor = 1
	game._shop_reroll_count = 1
	_expect_equal(
		game._get_shop_reroll_cost(), 76, "Hard second reroll must ceil after count scaling"
	)

	var boss_reward_data: Resource = _make_enemy_data("Reward Boss")
	boss_reward_data.is_boss = true
	boss_reward_data.boss_id = &"reward_fixture"
	boss_reward_data.boss_reward_gold = 101
	boss_reward_data.boss_reward_chest_rarity = 3
	_set_difficulty(&"normal")
	_expect_equal(
		_exercise_boss_reward(game, boss_reward_data),
		101,
		"Normal boss gold must remain the fixed resource reward"
	)
	_set_difficulty(&"hard")
	_expect_equal(
		_exercise_boss_reward(game, boss_reward_data),
		116,
		"Hard boss gold must round fixed 101 x 1.15 to 116"
	)
	# Let both exact-runtime reward timers expire against the cleared fixture.
	await create_timer(game.BOSS_REWARD_CHEST_DEFER_SECONDS + 0.05).timeout


func _exercise_boss_reward(game: Node, boss_data: Resource) -> int:
	var stairs_cell: Vector2i = game._stairs_position
	var gold_before: int = game._player.stats_component.gold
	game._active_boss_encounter = {
		"defeated": false,
		"entered": true,
		"locked": true,
		"door_cells": [],
		"stairs_cell": stairs_cell,
		"room_cells": {},
		"boss_data": boss_data,
		"boss_name": boss_data.display_name,
		"boss_id": boss_data.boss_id,
	}
	game._release_boss_encounter()
	var granted: int = game._player.stats_component.gold - gold_before
	game._active_boss_encounter.clear()
	return granted


func _test_hard_boss_scaling(game: Node) -> void:
	var source: Resource = load(BOSS_PATHS[&"observer"])
	var source_attack: Resource = source.boss_attacks[0]
	var source_attack_bonus: int = source_attack.damage_bonus
	_set_difficulty(&"normal")
	var normal: Node = game._spawn_enemy_instance(source, Vector2i(8, 1), 5, true, false)
	var normal_hp: int = normal.stats_component.max_hp
	var normal_ac: int = normal.stats_component.base_armor_class
	var normal_attack: int = normal.stats_component.base_attack_bonus
	var normal_damage: int = normal.stats_component.base_damage_bonus
	var normal_xp: int = normal.stats_component.xp_reward
	_expect_equal(
		game._scale_boss_special_damage(13), 13, "Normal direct boss damage must be unchanged"
	)
	_expect_equal(
		game._scale_boss_special_damage(5, true), 5, "Normal hazard damage must be unchanged"
	)
	_expect_equal(
		game._boss_attack_effective_windup(source_attack),
		source_attack.telegraph_turns,
		"Normal windup changed"
	)

	_set_difficulty(&"hard")
	var hard: Node = game._spawn_enemy_instance(source, Vector2i(9, 1), 5, true, false)
	_expect_equal(
		hard.stats_component.max_hp,
		ceili(normal_hp * 1.25),
		"Hard boss HP must follow floor scaling"
	)
	_expect_equal(
		hard.stats_component.current_hp,
		hard.stats_component.max_hp,
		"Hard boss current HP is stale"
	)
	_expect_equal(
		hard.stats_component.base_armor_class, normal_ac + 1, "Hard boss AC must gain exactly one"
	)
	_expect_equal(
		hard.stats_component.base_attack_bonus,
		normal_attack + 1,
		"Hard boss attack must gain exactly one"
	)
	_expect_equal(
		hard.stats_component.base_damage_bonus,
		normal_damage + 1,
		"Hard boss melee damage must gain exactly one"
	)
	_expect_equal(
		hard.stats_component.xp_reward, roundi(normal_xp * 1.25), "Hard boss XP rounding regressed"
	)
	_expect_equal(
		game._scale_boss_special_damage(13), 15, "Hard direct damage must round 13 x 1.12 to 15"
	)
	_expect_equal(
		game._scale_boss_special_damage(5, true), 6, "Hard hazard damage must round 5 x 1.10 to 6"
	)
	_expect_equal(
		game._boss_attack_effective_windup(source_attack),
		max(1, source_attack.telegraph_turns - 1),
		"Hard windup must preserve exactly one player response"
	)
	var one_turn_attack: Resource = BossAttackDataScript.new()
	one_turn_attack.telegraph_turns = 1
	_expect_equal(
		game._boss_attack_effective_windup(one_turn_attack), 1, "Hard windup must never reach zero"
	)
	_expect_equal(
		source_attack.damage_bonus, source_attack_bonus, "boss attack resource was mutated"
	)
	_expect(
		normal.enemy_data.boss_attacks[0] != hard.enemy_data.boss_attacks[0],
		"boss instances share attack resources"
	)
	_dispose_enemy(game, normal)
	_dispose_enemy(game, hard)


func _test_boss_immunities(game: Node) -> void:
	_set_difficulty(&"hard")
	var bosses: Dictionary = {}
	var x_position: int = 10
	for boss_id: StringName in BOSS_PATHS:
		var boss: Node = game._spawn_enemy_instance(
			load(BOSS_PATHS[boss_id]), Vector2i(x_position, 1), 1, false, false
		)
		bosses[boss_id] = boss
		x_position += 1
	_test_observer_immunity(game, bosses[&"observer"])
	if _failed:
		_dispose_boss_fixture(game, bosses, null)
		return
	_test_seraphine_immunity(game, bosses[&"seraphine"])
	if _failed:
		_dispose_boss_fixture(game, bosses, null)
		return
	_test_vorrak_immunity(game, bosses[&"vorrak"])
	if _failed:
		_dispose_boss_fixture(game, bosses, null)
		return
	var retainer: Node = _test_kaelros_immunity(game, bosses[&"kaelros"])
	if _failed:
		_dispose_boss_fixture(game, bosses, retainer)
		return
	_test_nyxara_immunity(game, bosses[&"nyxara"])
	if not _failed:
		_test_normal_immunity_absence(game, bosses, retainer)
	_dispose_boss_fixture(game, bosses, retainer)


func _test_observer_immunity(game: Node, observer: Node) -> void:
	var state: Dictionary = game._boss_state_for(observer)
	state["exposed_turns"] = 0
	state["pending_attack"] = game._boss_attack_by_id(observer, &"observer_gaze")
	game._boss_states[observer] = state
	_expect_equal(
		game._get_damage_percent(observer, &"ranged"),
		0,
		"closed Observer eye must be ranged-immune"
	)
	_expect(
		game._get_damage_percent(observer, &"melee") > 0,
		"Observer fixed immunity leaked into melee"
	)
	var hp_before: int = observer.stats_component.current_hp
	var blocked: int = game._apply_typed_damage(observer, 20, &"ranged")
	_expect_equal(blocked, 0, "Observer immunity must return true zero through typed damage")
	_expect_equal(observer.stats_component.current_hp, hp_before, "immune Observer hit changed HP")
	game._on_boss_strategy_attack_resolved(observer, false)
	state = game._boss_state_for(observer)
	_expect(int(state.get("exposed_turns", 0)) > 0, "evading an Observer tell must open the eye")
	_expect(
		game._get_damage_percent(observer, &"ranged") > 0,
		"open Observer eye retained fixed immunity"
	)


func _test_seraphine_immunity(game: Node, seraphine: Node) -> void:
	var hp_before: int = seraphine.stats_component.current_hp
	var first_damage: int = game._apply_typed_damage(seraphine, 20, &"ranged")
	_expect(first_damage > 0, "Seraphine first ranged hit must deal damage")
	game._handle_defender_after_damage(seraphine, first_damage > 0, &"ranged")
	var state: Dictionary = game._boss_state_for(seraphine)
	_expect_equal(
		state.get("consecutive_damage_count", 0), 1, "Seraphine first hit counter regressed"
	)
	_expect_equal(
		state.get("active_shield_turns", 0), 0, "Seraphine shield activated one hit early"
	)
	game._handle_defender_after_damage(seraphine, false, &"ranged")
	state = game._boss_state_for(seraphine)
	_expect_equal(
		state.get("consecutive_damage_count", 0), 1, "zero ranged damage built or reset the counter"
	)
	var hp_before_trigger: int = seraphine.stats_component.current_hp
	var trigger_damage: int = game._apply_typed_damage(seraphine, 20, &"ranged")
	_expect(trigger_damage > 0, "Seraphine triggering hit was blocked before activation")
	_expect_equal(
		seraphine.stats_component.current_hp,
		hp_before_trigger - trigger_damage,
		"Seraphine triggering hit did not land before shielding"
	)
	game._handle_defender_after_damage(seraphine, trigger_damage > 0, &"ranged")
	state = game._boss_state_for(seraphine)
	_expect_equal(
		state.get("active_shield_channel", &""), &"ranged", "Seraphine shield channel mismatch"
	)
	_expect_equal(
		state.get("active_shield_turns", 0), 2, "Seraphine shield duration must begin at two"
	)
	_expect_equal(
		state.get("forced_attack_id", &""), &"briar_rebuke", "Seraphine retaliation was not forced"
	)
	_expect(
		seraphine.stats_component.current_hp < hp_before,
		"Seraphine positive hits did not reduce HP"
	)
	state["attack_cooldowns"] = {&"briar_rebuke": 99}
	game._boss_states[seraphine] = state
	var forced: Resource = game._choose_boss_attack(seraphine, 1, 1.0)
	_expect(
		forced != null and forced.id == &"briar_rebuke",
		"forced Seraphine retaliation lost to cooldown/scheduler"
	)
	var immune_hp: int = seraphine.stats_component.current_hp
	_expect_equal(
		game._apply_typed_damage(seraphine, 20, &"ranged"), 0, "following ranged hit must be immune"
	)
	_expect_equal(
		seraphine.stats_component.current_hp, immune_hp, "immune ranged hit changed Seraphine HP"
	)
	_expect(
		game._apply_typed_damage(seraphine, 20, &"magic") > 0,
		"nonmatching magic must bypass ranged immunity"
	)
	var haste_snapshot: int = game._haste_enemy_phases
	var sleeping_snapshot: Dictionary = game._sleeping_enemies.duplicate()
	var turn_count_snapshot: int = _game_manager.turn_count
	var player_turn_snapshot: bool = _game_manager.is_player_turn
	game._haste_enemy_phases = 1
	game._end_player_turn()
	_expect_equal(
		game._boss_state_for(seraphine).get("active_shield_turns", 0),
		2,
		"triggering completed action must not consume a shield window"
	)
	game._haste_enemy_phases = 1
	game._end_player_turn()
	_expect_equal(
		game._boss_state_for(seraphine).get("active_shield_turns", 0),
		1,
		"Quickstep-style enemy-phase skip must consume exactly one shield window"
	)
	for enemy: Node in game._enemies:
		if enemy != seraphine:
			game._sleeping_enemies[enemy] = 1
	game._process_enemy_turns()
	_expect_equal(
		game._boss_state_for(seraphine).get("active_shield_turns", 0),
		1,
		"boss processing without a completed player action double-ticked the shield"
	)
	for enemy: Node in game._enemies:
		game._sleeping_enemies[enemy] = 1
	game._haste_enemy_phases = 0
	game._end_player_turn()
	_expect(
		not game._sleeping_enemies.has(seraphine),
		"sleeping boss fixture did not pass through the enemy phase"
	)
	game._haste_enemy_phases = haste_snapshot
	game._sleeping_enemies = sleeping_snapshot
	_game_manager.turn_count = turn_count_snapshot
	_game_manager.is_player_turn = player_turn_snapshot
	state = game._boss_state_for(seraphine)
	_expect_equal(
		state.get("active_shield_turns", -1), 0, "adaptive shield did not expire deterministically"
	)
	_expect_equal(
		state.get("active_shield_channel", &"stale"), &"", "expired shield retained its channel"
	)
	_expect(
		game._get_damage_percent(seraphine, &"ranged") > 0,
		"expired Seraphine shield still blocks ranged"
	)


func _test_vorrak_immunity(game: Node, vorrak: Node) -> void:
	var first: int = game._apply_typed_damage(vorrak, 20, &"melee")
	game._handle_defender_after_damage(vorrak, first > 0, &"melee")
	var state: Dictionary = game._boss_state_for(vorrak)
	_expect_equal(state.get("active_shield_turns", 0), 0, "Vorrak shield activated one hit early")
	var second: int = game._apply_typed_damage(vorrak, 20, &"melee")
	_expect(second > 0, "Vorrak triggering melee hit must deal damage")
	game._handle_defender_after_damage(vorrak, second > 0, &"melee")
	state = game._boss_state_for(vorrak)
	_expect_equal(state.get("active_shield_channel", &""), &"melee", "Vorrak must adapt to melee")
	_expect_equal(state.get("forced_attack_id", &""), &"maw_snap", "Vorrak maw_snap was not forced")
	state["attack_cooldowns"] = {&"maw_snap": 99}
	game._boss_states[vorrak] = state
	var forced: Resource = game._choose_boss_attack(vorrak, 1, 1.0)
	_expect(
		forced != null and forced.id == &"maw_snap", "forced maw_snap lost to cooldown/scheduler"
	)
	_expect_equal(
		game._get_damage_percent(vorrak, &"melee"), 0, "Vorrak following melee must be immune"
	)
	_expect(
		game._get_damage_percent(vorrak, &"ranged") > 0, "Vorrak melee immunity leaked into ranged"
	)


func _test_kaelros_immunity(game: Node, kaelros: Node) -> Node:
	var retainer_data: Resource = _make_enemy_data("Owned Retainer")
	var retainer: Node = game._spawn_enemy_instance(retainer_data, Vector2i(15, 1), 1, false, false)
	retainer.set_meta("summoned_minion", true)
	retainer.set_meta("summoner_id", kaelros.get_instance_id())
	_expect_equal(game._count_summoned_minions(kaelros), 1, "Kaelros retinue fixture is not owned")
	_expect_equal(
		game._get_damage_percent(kaelros, &"magic"),
		0,
		"living Kaelros retinue must grant magic immunity"
	)
	_expect(
		game._get_damage_percent(kaelros, &"melee") > 0,
		"Kaelros retinue immunity leaked into melee"
	)
	var hp_before: int = kaelros.stats_component.current_hp
	_expect_equal(
		game._apply_typed_damage(kaelros, 20, &"magic"),
		0,
		"Kaelros magic immunity did not return zero"
	)
	_expect_equal(kaelros.stats_component.current_hp, hp_before, "immune magic changed Kaelros HP")
	retainer.stats_component.current_hp = 0
	_expect_equal(
		game._count_summoned_minions(kaelros), 0, "dead last retainer still counted as alive"
	)
	_expect(
		game._get_damage_percent(kaelros, &"magic") > 0,
		"killing last retainer did not remove magic immunity"
	)
	return retainer


func _test_nyxara_immunity(game: Node, nyxara: Node) -> void:
	var melee: int = game._apply_typed_damage(nyxara, 20, &"melee")
	game._handle_defender_after_damage(nyxara, melee > 0, &"melee")
	var state: Dictionary = game._boss_state_for(nyxara)
	_expect_equal(
		state.get("consecutive_damage_channel", &""),
		&"melee",
		"Nyxara did not remember first channel"
	)
	var ranged_first: int = game._apply_typed_damage(nyxara, 20, &"ranged")
	game._handle_defender_after_damage(nyxara, ranged_first > 0, &"ranged")
	state = game._boss_state_for(nyxara)
	_expect_equal(
		state.get("consecutive_damage_channel", &""),
		&"ranged",
		"Nyxara channel switch did not reset sequence"
	)
	_expect_equal(
		state.get("consecutive_damage_count", 0),
		1,
		"nonmatching channel incorrectly completed sequence"
	)
	_expect_equal(
		state.get("active_shield_turns", 0), 0, "Nyxara shield activated across mixed channels"
	)
	var ranged_trigger: int = game._apply_typed_damage(nyxara, 20, &"ranged")
	_expect(ranged_trigger > 0, "Nyxara triggering same-channel hit must deal damage")
	game._handle_defender_after_damage(nyxara, ranged_trigger > 0, &"ranged")
	state = game._boss_state_for(nyxara)
	_expect_equal(
		state.get("active_shield_channel", &""), &"ranged", "Nyxara adapted to the wrong channel"
	)
	_expect_equal(
		state.get("forced_attack_id", &""), &"shardstep", "Nyxara shardstep was not forced"
	)
	state["attack_cooldowns"] = {&"shardstep": 99}
	game._boss_states[nyxara] = state
	var forced: Resource = game._choose_boss_attack(nyxara, 1, 1.0)
	_expect(
		forced != null and forced.id == &"shardstep", "forced shardstep lost to cooldown/scheduler"
	)
	_expect_equal(
		game._get_damage_percent(nyxara, &"ranged"), 0, "Nyxara following ranged hit must be immune"
	)
	_expect(
		game._get_damage_percent(nyxara, &"magic") > 0, "Nyxara ranged immunity leaked into magic"
	)


func _test_normal_immunity_absence(game: Node, bosses: Dictionary, retainer: Node) -> void:
	_set_difficulty(&"normal")
	var observer: Node = bosses[&"observer"]
	var observer_state: Dictionary = game._boss_state_for(observer)
	observer_state["exposed_turns"] = 0
	game._boss_states[observer] = observer_state
	_expect(
		game._get_damage_percent(observer, &"ranged") > 0,
		"Normal Observer inherited Hard fixed immunity"
	)

	for boss_id: StringName in [&"seraphine", &"vorrak", &"nyxara"]:
		var boss: Node = bosses[boss_id]
		var state: Dictionary = game._boss_state_for(boss)
		state["active_shield_channel"] = &"ranged"
		state["active_shield_turns"] = 2
		state["consecutive_damage_channel"] = &""
		state["consecutive_damage_count"] = 0
		game._boss_states[boss] = state
		game._on_boss_damaged(boss, &"ranged")
		game._on_boss_damaged(boss, &"ranged")
		state = game._boss_state_for(boss)
		_expect(
			game._get_damage_percent(boss, &"ranged") > 0,
			"Normal %s inherited adaptive immunity" % boss_id
		)
		_expect_equal(
			state.get("consecutive_damage_count", 0),
			0,
			"Normal %s built a Hard hit counter" % boss_id
		)

	retainer.stats_component.current_hp = 1
	_expect(
		game._get_damage_percent(bosses[&"kaelros"], &"magic") > 0,
		"Normal Kaelros inherited retinue immunity"
	)


func _dispose_boss_fixture(game: Node, bosses: Dictionary, retainer: Node) -> void:
	if retainer != null and is_instance_valid(retainer):
		_dispose_enemy(game, retainer)
	for boss: Node in bosses.values():
		if is_instance_valid(boss):
			_dispose_enemy(game, boss)


func _make_enemy_data(display_name: String) -> Resource:
	var data: Resource = EnemyDataScript.new()
	data.display_name = display_name
	data.max_hp = 40
	data.armor_class = 10
	data.attack_bonus = 2
	data.damage_sides = 6
	data.damage_bonus = 1
	data.xp_reward = 20
	return data


func _dispose_enemy(game: Node, enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	game._enemies.erase(enemy)
	game._enemy_action_counts.erase(enemy)
	game._ranged_recovery_enemies.erase(enemy)
	game._boss_states.erase(enemy)
	_game_manager.remove_enemy(enemy)
	enemy.free()


func _expect(condition: bool, message: String) -> void:
	if condition or _failed:
		return
	_failed = true
	printerr(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, actual, expected])


func _expect_color(actual: Color, expected: Color, message: String) -> void:
	_expect(
		actual.is_equal_approx(expected), "%s (actual=%s expected=%s)" % [message, actual, expected]
	)
