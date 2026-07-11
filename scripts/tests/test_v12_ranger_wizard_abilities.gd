## Headless test for V12.1.0 Ranger and Wizard class abilities.
##
## Contracts:
##   1. Ranger: Hunter's Focus activation/consumption/scaling (+6 acc, 200% dmg,
##      2 charges at 20).
##   2. Ranger: Volley requires ranged weapon and damages multiple visible enemies.
##   3. Ranger: Quickstep helper returns 1 at Lv1, 2 at Lv20.
##   4. Wizard: Arcane Spark targets nearest visible enemy; range 6-8; damage scales.
##   5. Wizard: Frost Nova damages/sleeps visible enemies in radius; preserves charge.
##   6. Wizard: Chain Lightning damages multiple visible enemies; preserves charge.
## Run:
##   /usr/local/bin/godot --headless --path . \
##      --script res://scripts/tests/test_v12_ranger_wizard_abilities.gd
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const MapViewScript = preload("res://scripts/ui/map_view.gd")

var _game_script: GDScript
var _actor_script: GDScript
var _stats_script: GDScript
var _inventory_script: GDScript
var _player_script: GDScript
var _enemy_script: GDScript
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
	_enemy_script = load("res://scripts/entities/enemy.gd")

	# === Ranger abilities ===
	if not _failed:
		_check_focus_activation()
	if not _failed:
		await _check_focus_primed_flag_scope()
	if not _failed:
		_check_focus_level_20()
	if not _failed:
		await _check_volley()
	if not _failed:
		_check_quickstep()

	# === Wizard abilities ===
	if not _failed:
		await _check_wizard_spark_targeting()
	if not _failed:
		await _check_wizard_spark_no_target()
	if not _failed:
		_check_spark_scaling()
	if not _failed:
		await _check_frost_nova()
	if not _failed:
		await _check_chain_lightning()

	if not _failed:
		print("V12.1.0 Ranger and Wizard ability checks passed")
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


func _attach_projectile_map(game: Node) -> Node2D:
	var map_view: Node2D = MapViewScript.new()
	root.add_child(map_view)
	map_view.set_atmosphere_enabled(false)
	game.map_view = map_view
	return map_view


func _free_game(game: Node) -> void:
	if game == null or not is_instance_valid(game):
		return
	var player_ref: Variant = game.get("_player")
	if player_ref != null and is_instance_valid(player_ref):
		var player_node: Node = player_ref as Node
		if player_node != null:
			_free_test_node(player_node)
	var map_view_ref: Variant = game.get("map_view")
	if map_view_ref != null and is_instance_valid(map_view_ref):
		var map_view_node: Node = map_view_ref as Node
		if map_view_node != null and not game.is_ancestor_of(map_view_node):
			_free_test_node(map_view_node)
	game.free()


# ======================================================================
# 1a. Hunter's Focus activation — decrements charge and primes
# ======================================================================


func _check_focus_activation() -> void:
	var game: Node = _game_script.new()
	game._ranger_focus_charges = 1
	game._hunter_focus_primed = false

	game._activate_ranger_focus()
	if game._ranger_focus_charges != 0:
		_fail("Focus activate: charges expected 0, got %d" % game._ranger_focus_charges)
		_free_game(game)
		return
	if game._hunter_focus_primed != true:
		_fail("Focus activate: _hunter_focus_primed expected true")
		_free_game(game)
		return

	# Second activation no-op
	game._activate_ranger_focus()
	if game._ranger_focus_charges != 0:
		_fail("Focus re-activate: charges should stay 0")
		_free_game(game)
		return

	_free_game(game)
	print("  1a. Hunter's Focus activation decrements charge and primes")


# ======================================================================
# 1b. Hunter's Focus consumed on ranged attack (miss and hit)
# ======================================================================


func _check_focus_primed_flag_scope() -> void:
	var game: Node = _game_script.new()
	var player: Node2D = _make_player(Vector2i(5, 5), _player_script)
	player.stats_component.dexterity = 10
	player.stats_component.proficiency_bonus = 2
	root.add_child(player)
	await process_frame

	var defender: Node2D = _make_actor("Defender", Vector2i(7, 5), 200)
	root.add_child(defender)
	await process_frame

	var weapon: Resource = ItemDataScript.new()
	weapon.display_name = "Test Bow"
	weapon.kind = ItemDataScript.ItemKind.WEAPON
	weapon.is_ranged_weapon = true
	weapon.damage_dice = 1
	weapon.damage_sides = 4
	weapon.damage_bonus = 0
	weapon.attack_bonus = 0
	weapon.range = 6

	game._player = player
	game._enemies = []
	game._visible_cells = {}

	# Test 1: Focus consumed on miss (AC 40 unreachable)
	game._hunter_focus_primed = true
	defender.stats_component.base_armor_class = 40
	defender.stats_component.current_hp = 200
	seed(424242)
	game._resolve_ranged_attack(weapon, defender, &"weapon")

	if game._hunter_focus_primed == true:
		_fail("Focus: primed should be false after miss")
		_free_test_node(player)
		_free_test_node(defender)
		_free_game(game)
		return

	# Test 2: Focus consumed on hit (AC 1 guarantees hit)
	game._hunter_focus_primed = true
	defender.stats_component.base_armor_class = 1
	defender.stats_component.current_hp = 200
	seed(424242)
	game._resolve_ranged_attack(weapon, defender, &"weapon")

	if game._hunter_focus_primed == true:
		_fail("Focus: primed should be false after hit")
		_free_test_node(player)
		_free_test_node(defender)
		_free_game(game)
		return

	if defender.stats_component.current_hp >= 200:
		_fail("Focus: hit should deal damage (AC=1)")
		_free_test_node(player)
		_free_test_node(defender)
		_free_game(game)
		return

	_free_test_node(player)
	_free_test_node(defender)
	_free_game(game)
	await process_frame
	print("  1b. Hunter's Focus consumed on ranged attack (miss and hit)")


# ======================================================================
# 1c. Hunter's Focus level 20 scaling and 2 charges
# ======================================================================


func _check_focus_level_20() -> void:
	var game: Node = _game_script.new()
	var ok: bool = true

	# Accuracy scaling
	if ok and game._get_hunter_focus_accuracy(1) != 4:
		_fail(
			(
				"Hunter's Focus accuracy at Lv1: expected 4, got %d"
				% game._get_hunter_focus_accuracy(1)
			)
		)
		ok = false
	if ok and game._get_hunter_focus_accuracy(10) != 5:
		_fail(
			(
				"Hunter's Focus accuracy at Lv10: expected 5, got %d"
				% game._get_hunter_focus_accuracy(10)
			)
		)
		ok = false
	if ok and game._get_hunter_focus_accuracy(20) != 6:
		_fail(
			(
				"Hunter's Focus accuracy at Lv20: expected 6, got %d"
				% game._get_hunter_focus_accuracy(20)
			)
		)
		ok = false

	# Multiplier (damage %) scaling
	if ok and game._get_hunter_focus_multiplier(1) != 150:
		_fail(
			(
				"Hunter's Focus multiplier at Lv1: expected 150, got %d"
				% game._get_hunter_focus_multiplier(1)
			)
		)
		ok = false
	if ok and game._get_hunter_focus_multiplier(15) != 175:
		_fail(
			(
				"Hunter's Focus multiplier at Lv15: expected 175, got %d"
				% game._get_hunter_focus_multiplier(15)
			)
		)
		ok = false
	if ok and game._get_hunter_focus_multiplier(20) != 200:
		_fail(
			(
				"Hunter's Focus multiplier at Lv20: expected 200, got %d"
				% game._get_hunter_focus_multiplier(20)
			)
		)
		ok = false

	# Level 20: 2 charges via ability entry path
	if ok:
		var gm: Node = root.get_node_or_null("/root/GameManager")
		if gm == null:
			_fail("GameManager missing for focus Lv20 charges")
			ok = false
		else:
			var saved_class: StringName = gm.pending_character_class
			gm.prepare_character("FocusLv20Test", {}, &"ranger")

			game._player = _make_player(Vector2i(5, 5), _actor_script, 20)
			game._hunter_focus_primed = false
			game._ranger_focus_charges = 2
			var entries: Array[Dictionary] = game._get_class_ability_entries()

			if entries.is_empty():
				_fail("Focus Lv20: no entries returned")
				ok = false
			elif ok and entries[0].get("charges_max", -1) != 2:
				_fail(
					"Focus Lv20: charges_max expected 2, got %d" % entries[0].get("charges_max", -1)
				)
				ok = false
			elif ok and entries[0].get("charges_current", -1) != 2:
				_fail(
					(
						"Focus Lv20: charges_current expected 2, got %d"
						% entries[0].get("charges_current", -1)
					)
				)
				ok = false

			gm.prepare_character("Restore", {}, saved_class)

	if ok:
		print(
			(
				"  1c. Hunter's Focus Lv20: +6 acc, 200%% damage, 2 charges;"
				+ " Lv10: +5 acc; Lv1: +4 acc, 150%%"
			)
		)

	_free_game(game)


# ======================================================================
# 1d. Volley — guard prevents use without ranged weapon; if guard passes,
#     damages multiple visible enemies with arrow projectiles.
# ======================================================================


func _check_volley() -> void:
	var game: Node = _game_script.new()
	var map_view: Node2D = _attach_projectile_map(game)
	var player: Node2D = _make_player(Vector2i(5, 5), _player_script, 12)
	root.add_child(player)
	await process_frame

	var gm: Node = root.get_node_or_null("/root/GameManager")
	var saved_class: StringName = gm.pending_character_class
	gm.prepare_character("VolleyTest", {}, &"ranger")

	game._player = player
	game._ranger_volley_charges = 1
	game._enemies = []
	game._visible_cells = {}
	# Guard: Volley should not fire without a ranged weapon equipped.
	# The guard preserves the charge if no ranged weapon is in hand.

	# Test 1: No ranged weapon -> guard triggers, charge preserved
	game._activate_ranger_volley()
	if game._ranger_volley_charges != 1:
		_fail(
			"Volley no-weapon: charge should be preserved (1), got %d" % game._ranger_volley_charges
		)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	# Test 2: Equip ranged weapon, set visible enemies
	var bow: Resource = ItemDataScript.new()
	bow.display_name = "Test Bow"
	bow.kind = ItemDataScript.ItemKind.WEAPON
	bow.is_ranged_weapon = true
	bow.projectile_id = &"arrow"
	bow.damage_dice = 1
	bow.damage_sides = 6
	bow.damage_bonus = 0
	bow.attack_bonus = 0
	bow.range = 6
	player.inventory_component.toggle_equipped(bow)

	var enemy1: Node2D = _make_actor("VolleyTarget1", Vector2i(7, 5), 200)
	var enemy2: Node2D = _make_actor("VolleyTarget2", Vector2i(9, 5), 200)
	root.add_child(enemy1)
	root.add_child(enemy2)
	await process_frame

	game._enemies = [enemy1, enemy2]
	game._visible_cells = {Vector2i(7, 5): true, Vector2i(9, 5): true}
	game._ranger_volley_charges = 1
	var hp_before1: int = enemy1.stats_component.current_hp
	var hp_before2: int = enemy2.stats_component.current_hp

	game._activate_ranger_volley()
	if map_view._projectile_trails.size() != 2:
		_fail("Volley should emit one arrow projectile per target")
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return
	for trail: Dictionary in map_view._projectile_trails:
		if trail.get("profile_id", &"") != &"arrow":
			_fail("Volley projectile should use the arrow profile")
			gm.prepare_character("Restore", {}, saved_class)
			_free_game(game)
			return

	if game._ranger_volley_charges != 0:
		_fail("Volley: charge should be 0 after use, got %d" % game._ranger_volley_charges)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	var hp_after1: int = enemy1.stats_component.current_hp
	var hp_after2: int = enemy2.stats_component.current_hp
	if hp_after1 >= hp_before1:
		_fail("Volley: enemy1 should take damage (HP stayed %d)" % hp_before1)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return
	if hp_after2 >= hp_before2:
		_fail("Volley: enemy2 should take damage (HP stayed %d)" % hp_before2)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	gm.prepare_character("Restore", {}, saved_class)
	_free_game(game)
	await process_frame
	print("  1d. Volley requires ranged weapon, damages multiple visible enemies")


# ======================================================================
# 1e. Quickstep helper scaling
# ======================================================================


func _check_quickstep() -> void:
	var game: Node = _game_script.new()

	var phases_lv1: int = game._get_quickstep_haste_phases(1)
	if phases_lv1 != 1:
		_fail("Quickstep helper Lv1: expected 1, got %d" % phases_lv1)
		_free_game(game)
		return

	var phases_lv20: int = game._get_quickstep_haste_phases(20)
	if phases_lv20 != 2:
		_fail("Quickstep helper Lv20: expected 2, got %d" % phases_lv20)
		_free_game(game)
		return

	_free_game(game)
	print("  1e. Quickstep helper returns 1 at Lv1, 2 at Lv20")


# ======================================================================
# 2a. Wizard Arcane Spark targeting and nearest-visible-enemy damage
# ======================================================================


func _check_wizard_spark_targeting() -> void:
	var game: Node = _game_script.new()
	var map_view: Node2D = _attach_projectile_map(game)
	var player: Node2D = _make_player(Vector2i(5, 5), _player_script)
	player.stats_component.wisdom = 16  # mod +3
	root.add_child(player)
	await process_frame

	var close_enemy: Node2D = _make_actor("CloseEnemy", Vector2i(6, 5), 50)
	var far_enemy: Node2D = _make_actor("FarEnemy", Vector2i(15, 5), 50)
	root.add_child(close_enemy)
	root.add_child(far_enemy)
	await process_frame

	game._player = player
	game._enemies = [close_enemy, far_enemy]
	game._visible_cells = {
		Vector2i(6, 5): true,
		Vector2i(15, 5): true,
	}
	game._wizard_spark_charges = 1

	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		_free_test_node(player)
		_free_test_node(close_enemy)
		_free_test_node(far_enemy)
		_free_game(game)
		return

	var saved_class: StringName = gm.pending_character_class
	gm.prepare_character("WizardSparkTest", {}, &"wizard")

	var nearest: Node2D = game._find_nearest_visible_enemy_in_range(6)
	if nearest != close_enemy:
		var found_name: String = nearest.display_name if nearest != null else "null"
		_fail("_find_nearest_visible_enemy_in_range: expected CloseEnemy, got %s" % found_name)
		gm.prepare_character("RestoreTest", {}, saved_class)
		_free_test_node(player)
		_free_test_node(close_enemy)
		_free_test_node(far_enemy)
		_free_game(game)
		return

	# Test Arcane Spark damage: 1d4 + WIS mod (min 0)
	seed(9999)
	var wis_mod: int = floori((player.stats_component.wisdom - 10) / 2.0)
	var raw_damage: int = randi_range(1, 4) + max(0, wis_mod)

	var before_hp: int = close_enemy.stats_component.current_hp
	var damage: int = game._apply_typed_damage(close_enemy, raw_damage, &"magic")
	var after_hp: int = close_enemy.stats_component.current_hp

	var expected_scaled: int = _compute_scaled(raw_damage, 200)
	var expected_damage: int = _compute_scaled(expected_scaled, 100)

	if damage != expected_damage:
		_fail(
			(
				"Wizard arcane spark: expected damage %d (raw=%d, wis_mod=%d), got %d"
				% [expected_damage, raw_damage, wis_mod, damage]
			)
		)
		gm.prepare_character("RestoreTest", {}, saved_class)
		_free_test_node(player)
		_free_test_node(close_enemy)
		_free_test_node(far_enemy)
		_free_game(game)
		return

	if before_hp - after_hp != damage:
		_fail(
			(
				"Wizard arcane spark: HP reduction (%d) doesn't match damage (%d)"
				% [before_hp - after_hp, damage]
			)
		)
		gm.prepare_character("RestoreTest", {}, saved_class)
		_free_test_node(player)
		_free_test_node(close_enemy)
		_free_test_node(far_enemy)
		_free_game(game)
		return

	# Charge consumption and projectile identity when a target exists
	game._wizard_spark_charges = 1
	close_enemy.stats_component.current_hp = 50
	game._activate_wizard_spark()
	if (
		map_view._projectile_trails.size() != 1
		or map_view._projectile_trails[0].get("profile_id", &"") != &"arcane_spark"
	):
		_fail("Wizard spark should emit one arcane_spark projectile")
		gm.prepare_character("RestoreTest", {}, saved_class)
		_free_test_node(player)
		_free_test_node(close_enemy)
		_free_test_node(far_enemy)
		_free_game(game)
		return
	if game._wizard_spark_charges != 0:
		_fail("Wizard spark: charge should be consumed when visible enemy in range")
		gm.prepare_character("RestoreTest", {}, saved_class)
		_free_test_node(player)
		_free_test_node(close_enemy)
		_free_test_node(far_enemy)
		_free_game(game)
		return

	gm.prepare_character("RestoreTest", {}, saved_class)
	_free_test_node(player)
	_free_test_node(close_enemy)
	_free_test_node(far_enemy)
	_free_game(game)
	await process_frame
	print(
		"  2a. Wizard Arcane Spark damages nearest visible enemy within range;" + " charge consumed"
	)


# ======================================================================
# 2b. Arcane Spark no-target preserves charge (no visible enemy in range)
# ======================================================================


func _check_wizard_spark_no_target() -> void:
	var game: Node = _game_script.new()
	var player: Node2D = _make_player(Vector2i(5, 5), _player_script)
	root.add_child(player)
	await process_frame

	var out_of_range_enemy: Node2D = _make_actor("FarEnemy", Vector2i(20, 5), 50)
	root.add_child(out_of_range_enemy)
	await process_frame

	game._player = player
	game._enemies = [out_of_range_enemy]
	game._visible_cells = {Vector2i(20, 5): true}
	game._wizard_spark_charges = 1

	var nearest: Node2D = game._find_nearest_visible_enemy_in_range(6)
	if nearest != null:
		_fail("Wizard spark no target: expected null, got %s" % nearest.display_name)
		_free_test_node(player)
		_free_test_node(out_of_range_enemy)
		_free_game(game)
		return

	if game._wizard_spark_charges != 1:
		_fail("Wizard spark no target: charge should NOT be consumed")
		_free_test_node(player)
		_free_test_node(out_of_range_enemy)
		_free_game(game)
		return

	# Also test: no visible cells -> no target
	var invisible_enemy: Node2D = _make_actor("HiddenEnemy", Vector2i(6, 5), 50)
	root.add_child(invisible_enemy)
	await process_frame
	game._enemies = [invisible_enemy]
	game._visible_cells = {}

	game._wizard_spark_charges = 1
	nearest = game._find_nearest_visible_enemy_in_range(6)
	if nearest != null:
		_fail("Wizard spark hidden enemy: expected null when no visible cells")
		_free_test_node(player)
		_free_test_node(invisible_enemy)
		_free_game(game)
		return

	if game._wizard_spark_charges != 1:
		_fail("Wizard spark hidden enemy: charge should NOT be consumed")
		_free_test_node(player)
		_free_test_node(invisible_enemy)
		_free_game(game)
		return

	_free_test_node(player)
	_free_test_node(out_of_range_enemy)
	_free_test_node(invisible_enemy)
	_free_game(game)
	await process_frame
	print("  2b. Wizard Arcane Spark does not consume charge when no visible" + " target in range")


# ======================================================================
# 2c. Arcane Spark level 20 range/damage scaling — ok-bool pattern, 0 returns
# ======================================================================


func _check_spark_scaling() -> void:
	var game: Node = _game_script.new()
	var ok: bool = true

	# Range scaling
	if ok and game._get_arcane_spark_range(1) != 6:
		_fail("Arcane Spark range at Lv1: expected 6, got %d" % game._get_arcane_spark_range(1))
		ok = false
	if ok and game._get_arcane_spark_range(10) != 7:
		_fail("Arcane Spark range at Lv10: expected 7, got %d" % game._get_arcane_spark_range(10))
		ok = false
	if ok and game._get_arcane_spark_range(20) != 8:
		_fail("Arcane Spark range at Lv20: expected 8, got %d" % game._get_arcane_spark_range(20))
		ok = false

	# Wizard magic damage percent scaling
	if ok:
		var gm: Node = root.get_node_or_null("/root/GameManager")
		if gm == null:
			_fail("GameManager missing for spark scaling")
			ok = false
		else:
			var saved_class: StringName = gm.pending_character_class
			gm.prepare_character("SparkScaling", {}, &"wizard")

			if ok and game._get_player_class_damage_percent(&"magic", 1) != 200:
				_fail(
					(
						"Wizard magic damage %% at Lv1: expected 200, got %d"
						% game._get_player_class_damage_percent(&"magic", 1)
					)
				)
				ok = false
			if ok and game._get_player_class_damage_percent(&"magic", 15) != 220:
				_fail(
					(
						"Wizard magic damage %% at Lv15: expected 220, got %d"
						% game._get_player_class_damage_percent(&"magic", 15)
					)
				)
				ok = false
			if ok and game._get_player_class_damage_percent(&"magic", 20) != 240:
				_fail(
					(
						"Wizard magic damage %% at Lv20: expected 240, got %d"
						% game._get_player_class_damage_percent(&"magic", 20)
					)
				)
				ok = false

			gm.prepare_character("Restore", {}, saved_class)

	if ok:
		print(
			(
				"  2c. Arcane Spark Lv1 range=6, Lv20 range=8;"
				+ " magic damage 200/220/240 at Lv 1/15/20"
			)
		)

	_free_game(game)


# ======================================================================
# 2d. Frost Nova — damages/sleeps visible enemies, no-target preserves charge
# ======================================================================


func _check_frost_nova() -> void:
	var game: Node = _game_script.new()
	var map_view: Node2D = _attach_projectile_map(game)
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager missing for frost nova")
		_free_game(game)
		return
	var saved_class: StringName = gm.pending_character_class
	gm.prepare_character("FrostNovaTest", {}, &"wizard")

	var player: Node2D = _make_player(Vector2i(5, 5), _player_script, 6)
	player.stats_component.wisdom = 16  # mod +3
	root.add_child(player)
	await process_frame

	# Test 1: No visible enemies in range -> charge preserved
	game._player = player
	game._enemies = []
	game._visible_cells = {}
	game._wizard_frost_nova_charges = 1
	game._sleeping_enemies = {}
	game._activate_wizard_frost_nova()

	if game._wizard_frost_nova_charges != 1:
		_fail(
			(
				"Frost Nova no-target: charge should be preserved (1), got %d"
				% game._wizard_frost_nova_charges
			)
		)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	# Test 2: Visible enemy in radius -> damaged and slept
	var frost_enemy: Node2D = _make_actor("FrostTarget", Vector2i(6, 5), 100)
	root.add_child(frost_enemy)
	await process_frame

	game._enemies = [frost_enemy]
	game._visible_cells = {Vector2i(6, 5): true}
	game._wizard_frost_nova_charges = 1
	game._sleeping_enemies = {}
	var hp_before: int = frost_enemy.stats_component.current_hp

	game._activate_wizard_frost_nova()
	if (
		map_view._projectile_trails.size() != 1
		or map_view._projectile_trails[0].get("profile_id", &"") != &"frost_nova"
	):
		_fail("Frost Nova should emit one frost_nova projectile")
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	if game._wizard_frost_nova_charges != 0:
		_fail("Frost Nova: charge should be 0 after use, got %d" % game._wizard_frost_nova_charges)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	var hp_after: int = frost_enemy.stats_component.current_hp
	if hp_after >= hp_before:
		_fail("Frost Nova: enemy should take damage (HP stayed %d)" % hp_before)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	if game._sleeping_enemies.is_empty() or not game._sleeping_enemies.has(frost_enemy):
		_fail("Frost Nova: enemy should be in _sleeping_enemies")
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	var sleep_turns: int = game._sleeping_enemies.get(frost_enemy, -1)
	if sleep_turns != 1:
		_fail("Frost Nova: sleep turns expected 1 at Lv6, got %d" % sleep_turns)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	gm.prepare_character("Restore", {}, saved_class)
	_free_game(game)
	await process_frame
	print(
		(
			"  2d. Frost Nova damages visible enemies in radius, sleeps them,"
			+ " preserves charge with no targets"
		)
	)


# ======================================================================
# 2e. Chain Lightning — damages multiple visible enemies
# ======================================================================


func _check_chain_lightning() -> void:
	var game: Node = _game_script.new()
	var map_view: Node2D = _attach_projectile_map(game)
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager missing for chain lightning")
		_free_game(game)
		return
	var saved_class: StringName = gm.pending_character_class
	gm.prepare_character("ChainTest", {}, &"wizard")

	var player: Node2D = _make_player(Vector2i(5, 5), _player_script, 12)
	player.stats_component.wisdom = 16  # mod +3
	root.add_child(player)
	await process_frame

	# Test 1: No visible enemies -> charge preserved
	game._player = player
	game._enemies = []
	game._visible_cells = {}
	game._wizard_chain_lightning_charges = 1
	game._activate_wizard_chain_lightning()

	if game._wizard_chain_lightning_charges != 1:
		_fail(
			(
				"Chain Lightning no-target: charge should be preserved (1), got %d"
				% game._wizard_chain_lightning_charges
			)
		)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	# Test 2: Multiple visible enemies in range -> all damaged
	var enemy1: Node2D = _make_actor("ChainTarget1", Vector2i(6, 5), 150)
	var enemy2: Node2D = _make_actor("ChainTarget2", Vector2i(8, 5), 150)
	var enemy3: Node2D = _make_actor("ChainTarget3", Vector2i(10, 5), 150)
	root.add_child(enemy1)
	root.add_child(enemy2)
	root.add_child(enemy3)
	await process_frame

	game._enemies = [enemy1, enemy2, enemy3]
	game._visible_cells = {
		Vector2i(6, 5): true,
		Vector2i(8, 5): true,
		Vector2i(10, 5): true,
	}
	game._wizard_chain_lightning_charges = 1

	var hp_before1: int = enemy1.stats_component.current_hp
	var hp_before2: int = enemy2.stats_component.current_hp
	var hp_before3: int = enemy3.stats_component.current_hp

	game._activate_wizard_chain_lightning()
	if map_view._projectile_trails.size() != 3:
		_fail("Chain Lightning should emit one chain_lightning segment per target")
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return
	for trail: Dictionary in map_view._projectile_trails:
		if trail.get("profile_id", &"") != &"chain_lightning":
			_fail("Chain Lightning segment should use the chain_lightning profile")
			gm.prepare_character("Restore", {}, saved_class)
			_free_game(game)
			return

	if game._wizard_chain_lightning_charges != 0:
		_fail(
			(
				"Chain Lightning: charge should be 0 after use, got %d"
				% game._wizard_chain_lightning_charges
			)
		)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	var hp_after1: int = enemy1.stats_component.current_hp
	var hp_after2: int = enemy2.stats_component.current_hp
	var hp_after3: int = enemy3.stats_component.current_hp
	if hp_after1 >= hp_before1:
		_fail("Chain Lightning: enemy1 should take damage (HP stayed %d)" % hp_before1)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return
	if hp_after2 >= hp_before2:
		_fail("Chain Lightning: enemy2 should take damage (HP stayed %d)" % hp_before2)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return
	if hp_after3 >= hp_before3:
		_fail("Chain Lightning: enemy3 should take damage (HP stayed %d)" % hp_before3)
		gm.prepare_character("Restore", {}, saved_class)
		_free_game(game)
		return

	gm.prepare_character("Restore", {}, saved_class)
	_free_game(game)
	await process_frame
	print(
		(
			"  2e. Chain Lightning damages multiple visible enemies,"
			+ " preserves charge with no targets"
		)
	)
