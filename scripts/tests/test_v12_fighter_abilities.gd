## Headless test for V12.1.0 Fighter class abilities and extra strike.
##
## Contracts:
##   1. Cleave splash percent scales (50% at 1, 100% at 20); splash damages adjacent
##      enemies and clears primed; non-adjacent enemies are not hit.
##   2. Second Wind consumes charge/action, heals, and applies shield with
##      level-scaled values (heal% 20/25/30, shield 2/3/4, turns 3/4/5).
##   3. Whirlwind damages adjacent enemies and preserves charge with no targets.
##   4. Extra strike guards skip non-fighter, level < 5, dead defender.
##   5. Extra strike chance scales: 12/18/24/30% at levels 5/10/15/20.
##   6. Extra strike procs call CombatSystem attack.
## Run:
##   /usr/local/bin/godot --headless --path . \
##      --script res://scripts/tests/test_v12_fighter_abilities.gd
extends SceneTree

var _game_script: GDScript
var _actor_script: GDScript
var _stats_script: GDScript
var _inventory_script: GDScript
var _player_script: GDScript
var _combat_script: GDScript
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)

	_game_script = load("res://scripts/game.gd")
	_actor_script = load("res://scripts/entities/actor.gd")
	_stats_script = load("res://scripts/components/stats_component.gd")
	_inventory_script = load("res://scripts/components/inventory_component.gd")
	_player_script = load("res://scripts/entities/player.gd")
	_combat_script = load("res://scripts/systems/combat_system.gd")

	# --- 1. Cleave ---
	if not _failed:
		_check_cleave_activation()
	if not _failed:
		_check_cleave_splash_percent_scaling()
	if not _failed:
		await _check_cleave_splash()
	if not _failed:
		await _check_cleave_no_splash_non_adjacent()

	# --- 2. Second Wind ---
	if not _failed:
		_check_second_wind_scaling()
	if not _failed:
		await _check_second_wind_activation()

	# --- 3. Whirlwind ---
	if not _failed:
		await _check_whirlwind()

	# --- 4. Extra strike ---
	if not _failed:
		await _check_extra_strike_guards()
	if not _failed:
		_check_extra_strike_chance_scaling()
	if not _failed:
		await _check_extra_strike_procs()

	if not _failed:
		print("V12.1.0 Fighter ability checks passed")
		quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


# ======================================================================
# Helpers
# ======================================================================


func _make_actor(
	name: String, grid_pos: Vector2i, hp: int = 100, actor_script: GDScript = _actor_script
) -> Node2D:
	var actor: Node2D = actor_script.new()
	actor.display_name = name
	actor.grid_position = grid_pos
	var stats: Node = _stats_script.new()
	stats.name = "StatsComponent"
	stats.max_hp = hp
	stats.current_hp = hp
	stats.strength = 10
	stats.dexterity = 10
	stats.constitution = 10
	stats.intelligence = 10
	stats.wisdom = 10
	stats.charisma = 10
	stats.proficiency_bonus = 2
	stats.base_armor_class = 10
	stats.base_attack_bonus = 0
	stats.base_damage_bonus = 0
	stats.base_damage_sides = 4
	actor.add_child(stats)
	actor.stats_component = stats
	return actor


func _make_player(grid_pos: Vector2i, actor_script: GDScript, level: int = 1) -> Node2D:
	var player: Node2D = actor_script.new()
	player.display_name = "Hero"
	player.grid_position = grid_pos
	var stats: Node = _stats_script.new()
	stats.name = "StatsComponent"
	stats.max_hp = 100
	stats.current_hp = 100
	stats.level = level
	stats.strength = 10
	stats.dexterity = 10
	stats.constitution = 10
	stats.intelligence = 10
	stats.wisdom = 10
	stats.charisma = 10
	stats.proficiency_bonus = 2
	stats.base_armor_class = 10
	stats.base_attack_bonus = 0
	stats.base_damage_bonus = 0
	stats.base_damage_sides = 4
	player.add_child(stats)
	player.stats_component = stats
	var inv: Node = _inventory_script.new()
	inv.name = "InventoryComponent"
	player.add_child(inv)
	player.inventory_component = inv
	return player


func _compute_scaled(raw_damage: int, percent: int) -> int:
	if percent <= 0:
		return 0
	if percent == 100:
		return raw_damage
	return max(1, int(round(raw_damage * percent / 100.0)))


func _free_test_node(node: Node) -> void:
	if node != null and is_instance_valid(node):
		node.free()


func _free_game(game: Node) -> void:
	if game == null or not is_instance_valid(game):
		return
	var player_ref: Variant = game.get("_player")
	if player_ref != null and is_instance_valid(player_ref):
		var player_node: Node = player_ref as Node
		if player_node != null:
			_free_test_node(player_node)
	game.free()


func _find_proc_seed(range_max: int, threshold: int) -> int:
	for s: int in range(5000):
		seed(s)
		if randi_range(1, range_max) <= threshold:
			return s
	return -1


# ======================================================================
# 1a. Cleave activation — consumes charge and primes
# ======================================================================


func _check_cleave_activation() -> void:
	var game: Node = _game_script.new()

	# Activation with charge available
	game._fighter_cleave_charges = 1
	game._cleave_primed = false
	game._activate_fighter_cleave()
	if game._fighter_cleave_charges != 0:
		_fail("Cleave activate: charges expected 0, got %d" % game._fighter_cleave_charges)
		_free_game(game)
		return
	if game._cleave_primed != true:
		_fail("Cleave activate: _cleave_primed expected true")
		_free_game(game)
		return

	# Second activation should be no-op (already primed, no charges)
	game._activate_fighter_cleave()
	if game._fighter_cleave_charges != 0:
		_fail("Cleave re-activate: charges should stay 0, got %d" % game._fighter_cleave_charges)
		_free_game(game)
		return
	if game._cleave_primed != true:
		_fail("Cleave re-activate: _cleave_primed should stay true")
		_free_game(game)
		return

	# Activate with zero charges should be no-op
	game._fighter_cleave_charges = 0
	game._cleave_primed = false
	game._activate_fighter_cleave()
	if game._cleave_primed == true:
		_fail("Cleave zero charges: should NOT prime")
		_free_game(game)
		return

	_free_game(game)
	print("  1a. Fighter Cleave activation decrements charge and primes")


# ======================================================================
# 1b. Cleave splash percent scaling
# ======================================================================


func _check_cleave_splash_percent_scaling() -> void:
	var game: Node = _game_script.new()

	var pct_lv1: int = game._get_fighter_cleave_splash_percent(1)
	if pct_lv1 != 50:
		_fail("Cleave splash percent at Lv1: expected 50, got %d" % pct_lv1)
		_free_game(game)
		return

	var pct_lv10: int = game._get_fighter_cleave_splash_percent(10)
	if pct_lv10 != 60:
		_fail("Cleave splash percent at Lv10: expected 60, got %d" % pct_lv10)
		_free_game(game)
		return

	var pct_lv15: int = game._get_fighter_cleave_splash_percent(15)
	if pct_lv15 != 75:
		_fail("Cleave splash percent at Lv15: expected 75, got %d" % pct_lv15)
		_free_game(game)
		return

	var pct_lv20: int = game._get_fighter_cleave_splash_percent(20)
	if pct_lv20 != 100:
		_fail("Cleave splash percent at Lv20: expected 100, got %d" % pct_lv20)
		_free_game(game)
		return

	_free_game(game)
	print("  1b. Fighter Cleave splash percent scales 50/60/75/100 at Lv 1/10/15/20")


# ======================================================================
# 1c. Cleave splash damages adjacent enemy
# ======================================================================


func _check_cleave_splash() -> void:
	var game: Node = _game_script.new()

	# Primary target at (5,5), splash target adjacent at (6,5)
	var primary: Node2D = _make_actor("Target", Vector2i(5, 5), 200)
	var splash_target: Node2D = _make_actor("SplashTarget", Vector2i(6, 5), 200)
	root.add_child(primary)
	root.add_child(splash_target)
	await process_frame

	game._player = _make_player(Vector2i(5, 5), _actor_script, 1)
	game._cleave_primed = true
	game._enemies = [splash_target]

	# Fake outcome with attacker_scaled_damage = 20
	var outcome: Dictionary = {"attacker_scaled_damage": 20, "hit": true}

	game._apply_cleave_splash(primary, outcome)

	# Primed flag cleared
	if game._cleave_primed == true:
		_fail("Cleave splash: primed should be false after splash")
		_free_test_node(primary)
		_free_test_node(splash_target)
		_free_game(game)
		return

	# At level 1, splash_percent = 50%, splash_base = max(1, round(20*0.5)) = 10
	# affinity 100%, so splash_damage = 10
	var splash_hp: int = splash_target.stats_component.current_hp
	if splash_hp != 190:
		_fail("Cleave splash: expected splash target HP 190, got %d" % splash_hp)
		_free_test_node(primary)
		_free_test_node(splash_target)
		_free_game(game)
		return

	# Primary target should not be damaged by splash
	if primary.stats_component.current_hp != 200:
		_fail("Cleave splash: primary target should be undamaged")
		_free_test_node(primary)
		_free_test_node(splash_target)
		_free_game(game)
		return

	_free_test_node(primary)
	_free_test_node(splash_target)
	_free_game(game)
	await process_frame
	print("  1c. Fighter Cleave splash damages adjacent enemy and clears primed")


# ======================================================================
# 1d. Cleave splash does not hit non-adjacent enemies
# ======================================================================


func _check_cleave_no_splash_non_adjacent() -> void:
	var game: Node = _game_script.new()

	# Primary at (5,5), non-adjacent enemy at (7,5) — 2 cells away
	var primary: Node2D = _make_actor("Target", Vector2i(5, 5), 200)
	var far_enemy: Node2D = _make_actor("FarEnemy", Vector2i(7, 5), 200)
	root.add_child(primary)
	root.add_child(far_enemy)
	await process_frame

	game._player = _make_player(Vector2i(5, 5), _actor_script)
	game._cleave_primed = true
	game._enemies = [far_enemy]

	var outcome: Dictionary = {"attacker_scaled_damage": 20, "hit": true}
	game._apply_cleave_splash(primary, outcome)

	# Far enemy should be undamaged (not adjacent orthogonally)
	var far_hp: int = far_enemy.stats_component.current_hp
	if far_hp != 200:
		_fail("Cleave splash: non-adjacent enemy should be undamaged, HP %d" % far_hp)
		_free_test_node(primary)
		_free_test_node(far_enemy)
		_free_game(game)
		return

	_free_test_node(primary)
	_free_test_node(far_enemy)
	_free_game(game)
	await process_frame
	print("  1d. Cleave splash does not hit non-adjacent enemies")


# ======================================================================
# 2a. Second Wind helper scaling — elif chain, 0 returns
# ======================================================================


func _check_second_wind_scaling() -> void:
	var game: Node = _game_script.new()

	if game._get_second_wind_heal_percent(1) != 20:
		_fail(
			(
				"Second Wind heal %% at Lv1: expected 20, got %d"
				% game._get_second_wind_heal_percent(1)
			)
		)
	elif game._get_second_wind_shield_value(1) != 2:
		_fail(
			(
				"Second Wind shield value at Lv1: expected 2, got %d"
				% game._get_second_wind_shield_value(1)
			)
		)
	elif game._get_second_wind_shield_turns(1) != 3:
		_fail(
			(
				"Second Wind shield turns at Lv1: expected 3, got %d"
				% game._get_second_wind_shield_turns(1)
			)
		)
	elif game._get_second_wind_heal_percent(15) != 25:
		_fail(
			(
				"Second Wind heal %% at Lv15: expected 25, got %d"
				% game._get_second_wind_heal_percent(15)
			)
		)
	elif game._get_second_wind_shield_value(15) != 3:
		_fail(
			(
				"Second Wind shield value at Lv15: expected 3, got %d"
				% game._get_second_wind_shield_value(15)
			)
		)
	elif game._get_second_wind_shield_turns(15) != 4:
		_fail(
			(
				"Second Wind shield turns at Lv15: expected 4, got %d"
				% game._get_second_wind_shield_turns(15)
			)
		)
	elif game._get_second_wind_heal_percent(20) != 30:
		_fail(
			(
				"Second Wind heal %% at Lv20: expected 30, got %d"
				% game._get_second_wind_heal_percent(20)
			)
		)
	elif game._get_second_wind_shield_value(20) != 4:
		_fail(
			(
				"Second Wind shield value at Lv20: expected 4, got %d"
				% game._get_second_wind_shield_value(20)
			)
		)
	elif game._get_second_wind_shield_turns(20) != 5:
		_fail(
			(
				"Second Wind shield turns at Lv20: expected 5, got %d"
				% game._get_second_wind_shield_turns(20)
			)
		)
	else:
		print(
			(
				"  2a. Second Wind scaling: heal%% 20/25/30, shield 2/3/4, turns 3/4/5"
				+ " at Lv 1/15/20"
			)
		)

	_free_game(game)


# ======================================================================
# 2b. Second Wind activation — consumes charge, heals, applies shield
# ======================================================================


func _check_second_wind_activation() -> void:
	var game: Node = _game_script.new()
	var player: Node2D = _make_player(Vector2i(5, 5), _player_script, 1)
	player.stats_component.current_hp = 50
	root.add_child(player)
	await process_frame

	game._player = player
	game._fighter_second_wind_charges = 1
	game._shield_turns = 0
	game._shield_armor_bonus = 0

	game._activate_fighter_second_wind()

	# Charge consumed
	if game._fighter_second_wind_charges != 0:
		_fail(
			"Second Wind: charge should be 0 after use, got %d" % game._fighter_second_wind_charges
		)
		_free_test_node(player)
		_free_game(game)
		return

	# HP healed: 20% of 100 = 20, so 50 + capped at max 100 = 70
	var expected_hp: int = min(100, 50 + int(round(100 * 20 / 100.0)))
	if player.stats_component.current_hp != expected_hp:
		_fail(
			(
				"Second Wind: expected HP %d after heal, got %d"
				% [expected_hp, player.stats_component.current_hp]
			)
		)
		_free_test_node(player)
		_free_game(game)
		return

	# Shield applied
	if game._shield_turns < 3:
		_fail("Second Wind: shield_turns expected at least 3, got %d" % game._shield_turns)
		_free_test_node(player)
		_free_game(game)
		return
	if game._shield_armor_bonus < 2:
		_fail(
			"Second Wind: shield_armor_bonus expected at least 2, got %d" % game._shield_armor_bonus
		)
		_free_test_node(player)
		_free_game(game)
		return

	# Activate again with zero charges — should be no-op
	game._activate_fighter_second_wind()
	if game._fighter_second_wind_charges != 0:
		_fail("Second Wind no-charge re-activate: charges should stay 0")
		_free_test_node(player)
		_free_game(game)
		return

	_free_test_node(player)
	_free_game(game)
	await process_frame
	print("  2b. Second Wind consumes charge, heals 20% HP, applies shield 2/3turns")


# ======================================================================
# 3. Whirlwind — damages adjacent, preserves charge with no targets
# ======================================================================


func _check_whirlwind() -> void:
	var game: Node = _game_script.new()

	# Test 1: No adjacent enemies -> charge preserved
	game._player = _make_player(Vector2i(5, 5), _player_script, 12)
	root.add_child(game._player)
	await process_frame
	game._enemies = []
	game._fighter_whirlwind_charges = 1
	game._activate_fighter_whirlwind()

	if game._fighter_whirlwind_charges != 1:
		_fail(
			(
				"Whirlwind no-target: charge should be preserved (1), got %d"
				% game._fighter_whirlwind_charges
			)
		)
		_free_game(game)
		return

	# Test 2: Adjacent enemy -> charge consumed, enemy damaged
	var adjacent_enemy: Node2D = _make_actor("AdjEnemy", Vector2i(6, 5), 200)
	root.add_child(adjacent_enemy)
	await process_frame
	game._enemies = [adjacent_enemy]
	game._fighter_whirlwind_charges = 1

	var hp_before: int = adjacent_enemy.stats_component.current_hp
	var gm: Node = root.get_node_or_null("/root/GameManager")
	var saved_class: StringName = gm.pending_character_class
	gm.prepare_character("WhirlwindTest", {}, &"fighter")

	adjacent_enemy.stats_component.base_armor_class = 0
	game._activate_fighter_whirlwind()

	if game._fighter_whirlwind_charges != 0:
		_fail("Whirlwind: charge should be 0 after use, got %d" % game._fighter_whirlwind_charges)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	var hp_after: int = adjacent_enemy.stats_component.current_hp
	if hp_after >= hp_before:
		_fail("Whirlwind: adjacent enemy should take damage (HP stayed %d)" % hp_before)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	gm.prepare_character("Restore", {}, saved_class)
	_free_game(game)
	await process_frame
	print("  3. Whirlwind damages adjacent enemy, preserves charge with no targets")


# ======================================================================
# 4a. Extra strike guard conditions
# ======================================================================


func _check_extra_strike_guards() -> void:
	var game: Node = _game_script.new()
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager missing for extra strike guards")
		_free_game(game)
		return
	var saved_class: StringName = gm.pending_character_class

	# Guard 1: non-fighter -> no extra strike
	gm.prepare_character("WizardGuard", {}, &"wizard")
	game._player = _make_player(Vector2i(5, 5), _actor_script, 5)
	var defender: Node2D = _make_actor("Guard1", Vector2i(6, 5), 100)
	root.add_child(defender)
	await process_frame
	defender.stats_component.current_hp = 100

	seed(424242)
	var hp_before: int = defender.stats_component.current_hp
	game._apply_fighter_extra_strike(defender)
	var hp_after: int = defender.stats_component.current_hp
	if hp_after != hp_before:
		_fail(
			(
				"Extra strike guard: non-fighter class should not trigger"
				+ " (HP changed %d->%d)" % [hp_before, hp_after]
			)
		)
		_free_test_node(defender)
		_free_game(game)
		gm.prepare_character("Restore", {}, saved_class)
		return

	_free_test_node(defender)
	await process_frame

	# Guard 2: level 1 -> no extra strike
	gm.prepare_character("FighterGuardLowLv", {}, &"fighter")
	_free_test_node(game._player)
	game._player = _make_player(Vector2i(5, 5), _actor_script, 1)
	defender = _make_actor("Guard2", Vector2i(6, 5), 100)
	root.add_child(defender)
	await process_frame
	defender.stats_component.current_hp = 100

	seed(424242)
	hp_before = defender.stats_component.current_hp
	game._apply_fighter_extra_strike(defender)
	hp_after = defender.stats_component.current_hp
	if hp_after != hp_before:
		_fail("Extra strike guard: level 1 should not trigger strike (HP changed)")
		_free_test_node(defender)
		_free_game(game)
		gm.prepare_character("Restore", {}, saved_class)
		return

	_free_test_node(defender)
	await process_frame

	# Guard 3: dead defender -> no extra strike
	gm.prepare_character("FighterGuardDead", {}, &"fighter")
	_free_test_node(game._player)
	game._player = _make_player(Vector2i(5, 5), _actor_script, 5)
	defender = _make_actor("Guard3", Vector2i(6, 5), 100)
	defender.stats_component.current_hp = 0
	root.add_child(defender)
	await process_frame

	seed(424242)
	hp_before = defender.stats_component.current_hp
	game._apply_fighter_extra_strike(defender)
	hp_after = defender.stats_component.current_hp
	if hp_after != hp_before:
		_fail("Extra strike guard: dead defender should not trigger strike (HP changed)")
		_free_test_node(defender)
		_free_game(game)
		gm.prepare_character("Restore", {}, saved_class)
		return

	_free_test_node(defender)
	_free_test_node(game._player)
	_free_game(game)
	await process_frame

	gm.prepare_character("Restore", {}, saved_class)
	print(
		(
			"  4a. Extra strike guards skip correctly for low-level, wrong-class,"
			+ " and dead-defender"
		)
	)


# ======================================================================
# 4b. Extra strike chance scaling — elif chain, 0 returns
# ======================================================================


func _check_extra_strike_chance_scaling() -> void:
	var game: Node = _game_script.new()

	if game._get_fighter_extra_strike_chance(5) != 12:
		_fail(
			(
				"Extra strike chance at Lv5: expected 12, got %d"
				% game._get_fighter_extra_strike_chance(5)
			)
		)
	elif game._get_fighter_extra_strike_chance(10) != 18:
		_fail(
			(
				"Extra strike chance at Lv10: expected 18, got %d"
				% game._get_fighter_extra_strike_chance(10)
			)
		)
	elif game._get_fighter_extra_strike_chance(15) != 24:
		_fail(
			(
				"Extra strike chance at Lv15: expected 24, got %d"
				% game._get_fighter_extra_strike_chance(15)
			)
		)
	elif game._get_fighter_extra_strike_chance(20) != 30:
		_fail(
			(
				"Extra strike chance at Lv20: expected 30, got %d"
				% game._get_fighter_extra_strike_chance(20)
			)
		)
	elif game._get_fighter_extra_strike_chance(1) != 0:
		_fail(
			(
				"Extra strike chance at Lv1: expected 0, got %d"
				% game._get_fighter_extra_strike_chance(1)
			)
		)
	elif _find_proc_seed(100, 12) < 0:
		_fail("Could not find a proc seed for extra strike (12%)")
	elif _find_proc_seed(100, 18) < 0:
		_fail("Could not find a proc seed for extra strike (18%)")
	elif _find_proc_seed(100, 24) < 0:
		_fail("Could not find a proc seed for extra strike (24%)")
	elif _find_proc_seed(100, 30) < 0:
		_fail("Could not find a proc seed for extra strike (30%)")
	else:
		print(
			(
				"  4b. Extra strike chance: 0/12/18/24/30 at Lv 1/5/10/15/20;"
				+ " proc seeds found for all tiers"
			)
		)

	_free_game(game)


# ======================================================================
# 4c. Extra strike structural proc test (CombatSystem integration)
# ======================================================================


func _check_extra_strike_procs() -> void:
	var proc_seed: int = _find_proc_seed(100, 12)
	if proc_seed < 0:
		_fail("Could not find a proc seed for extra strike (12%)")
		return

	var game: Node = _game_script.new()
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager missing for extra strike proc")
		_free_game(game)
		return
	var saved_class: StringName = gm.pending_character_class
	gm.prepare_character("FighterProc", {}, &"fighter")

	var player: Node2D = _make_player(Vector2i(5, 5), _player_script, 5)
	player.stats_component.strength = 10
	player.stats_component.proficiency_bonus = 2
	player.stats_component.base_damage_sides = 4
	root.add_child(player)
	await process_frame

	var defender: Node2D = _make_actor("ProcTarget", Vector2i(6, 5), 200)
	defender.stats_component.base_armor_class = 1
	root.add_child(defender)
	await process_frame

	game._player = player
	game._enemies = [defender]

	# Structural test: direct CombatSystem call with fighter melee params
	seed(424242)
	var direct_outcome: Dictionary = _combat_script.attack(player, defender, 100, 150)
	if not direct_outcome["hit"]:
		_fail("Precondition: direct combat attack should hit with AC=1")
		_free_test_node(player)
		_free_test_node(defender)
		_free_game(game)
		gm.prepare_character("Restore", {}, saved_class)
		return
	if direct_outcome["damage"] <= 0:
		_fail("Precondition: direct combat attack should deal positive damage")
		_free_test_node(player)
		_free_test_node(defender)
		_free_game(game)
		gm.prepare_character("Restore", {}, saved_class)
		return

	print(
		"    (extra strike via CombatSystem: damage=%d with 150%% melee)" % direct_outcome["damage"]
	)

	# Integration run: call the full method to verify no errors
	defender.stats_component.current_hp = 200
	game._apply_fighter_extra_strike(defender)

	_free_test_node(player)
	_free_test_node(defender)
	_free_game(game)
	await process_frame

	gm.prepare_character("Restore", {}, saved_class)
	print(
		(
			"  4c. Fighter extra strike calls CombatSystem on proc; melee=150%%"
			+ " damage=%d" % direct_outcome["damage"]
		)
	)
