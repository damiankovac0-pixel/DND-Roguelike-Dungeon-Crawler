## Headless test for V12.2.0 character class system with level-aware passives.
##
## Contracts:
##   1. GameManager.prepare_character stores the selected class and normalizes
##      invalid classes to Fighter (DEFAULT_CHARACTER_CLASS).
##   2. get_character_class_damage_percent returns correct per-class/per-type values
##      at levels 1/10/15/20 for each class.
##   3. CharacterCreation scene has a ClassSelector with Fighter, Ranger, Wizard.
##   4. Selecting Wizard before begin stores &"wizard" in GameManager.
##   5. CombatSystem.attack applies attacker_damage_percent and damage_percent at
##      independent stages of the damage pipeline.
##   6. Game._apply_typed_damage applies GameManager class damage_percent before
##      enemy affinity (wizard magic=240% at Lv20, wizard ranged=70% at Lv20).
##   7. Game._get_attacker_damage_percent returns class damage_percent for player
##      and 100 for non-player attackers.
## Run:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_character_classes.gd
extends SceneTree

var _actor_script: GDScript
var _stats_script: GDScript
var _combat_script: GDScript
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)

	# Preload shared scripts to avoid gdlint duplicated-load violations
	_actor_script = load("res://scripts/entities/actor.gd")
	_stats_script = load("res://scripts/components/stats_component.gd")
	_combat_script = load("res://scripts/systems/combat_system.gd")

	# === 1. prepare_character stores class and normalizes invalid ===
	_check_prepare_character_stores_class()

	# === 2. damage_percent values by class/damage-type ===
	if not _failed:
		_check_damage_percent_values()

	# === 2b. Level-aware damage_percent scaling at 10/15/20 ===
	if not _failed:
		_check_damage_percent_level_scaling()

	# === 3+4. CharacterCreation scene selector + Wizard selection stores ===
	if not _failed:
		await _check_character_creation_class_and_begin()

	# === 5. CombatSystem attack damage_percent independence ===
	if not _failed:
		await _check_combat_attack_damage_percent()

	# === 6. Game integration class damage pipeline ===
	if not _failed:
		await _check_game_integration_class_damage()

	if not _failed:
		print("character class checks passed")
		quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


# ======================================================================
# 1. prepare_character stores class and normalizes invalid
# ======================================================================
func _check_prepare_character_stores_class() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	# Valid classes pass through
	gm.prepare_character("TestName", {}, &"fighter")
	if gm.pending_character_class != &"fighter":
		_fail(
			"prepare_character(fighter): expected 'fighter', got '%s'" % gm.pending_character_class
		)
		return
	if gm.pending_character_name != "TestName":
		_fail(
			(
				"prepare_character: pending_character_name expected 'TestName', got '%s'"
				% gm.pending_character_name
			)
		)
		return

	gm.prepare_character("RangerTest", {}, &"ranger")
	if gm.pending_character_class != &"ranger":
		_fail("prepare_character(ranger): expected 'ranger', got '%s'" % gm.pending_character_class)
		return

	gm.prepare_character("WizardTest", {}, &"wizard")
	if gm.pending_character_class != &"wizard":
		_fail("prepare_character(wizard): expected 'wizard', got '%s'" % gm.pending_character_class)
		return

	# Invalid class normalizes to Fighter (DEFAULT_CHARACTER_CLASS)
	gm.prepare_character("InvalidTest", {}, &"barbarian")
	if gm.pending_character_class != &"fighter":
		_fail(
			(
				"prepare_character(barbarian): expected 'fighter' (default), got '%s'"
				% gm.pending_character_class
			)
		)
		return

	gm.prepare_character("EmptyTest", {}, &"")
	if gm.pending_character_class != &"fighter":
		_fail(
			(
				"prepare_character(''): expected 'fighter' (default), got '%s'"
				% gm.pending_character_class
			)
		)

	print("  prepare_character stores class and normalizes invalid -> Fighter")


# ======================================================================
# 2. get_character_class_damage_percent returns correct values
# ======================================================================
func _check_damage_percent_values() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	# Fighter: melee=150, ranged=100, magic=100
	_assert_damage_percent(gm, &"fighter", &"melee", 150, "Fighter melee")
	_assert_damage_percent(gm, &"fighter", &"ranged", 100, "Fighter ranged")
	_assert_damage_percent(gm, &"fighter", &"magic", 100, "Fighter magic")

	# Ranger: melee=50, ranged=150, magic=100
	_assert_damage_percent(gm, &"ranger", &"melee", 50, "Ranger melee")
	_assert_damage_percent(gm, &"ranger", &"ranged", 150, "Ranger ranged")
	_assert_damage_percent(gm, &"ranger", &"magic", 100, "Ranger magic")

	# Wizard: melee=60, ranged=60, magic=200
	_assert_damage_percent(gm, &"wizard", &"melee", 60, "Wizard melee")
	_assert_damage_percent(gm, &"wizard", &"ranged", 60, "Wizard ranged")
	_assert_damage_percent(gm, &"wizard", &"magic", 200, "Wizard magic")

	# Default (empty string) uses pending_character_class — test with fighter baseline
	gm.prepare_character("DefaultTest", {}, &"fighter")
	_assert_damage_percent(gm, &"", &"melee", 150, "Default (fighter pending) melee")
	_assert_damage_percent(gm, &"", &"ranged", 100, "Default (fighter pending) ranged")
	_assert_damage_percent(gm, &"", &"magic", 100, "Default (fighter pending) magic")

	gm.prepare_character("DefaultRanger", {}, &"ranger")
	_assert_damage_percent(gm, &"", &"melee", 50, "Default (ranger pending) melee")
	_assert_damage_percent(gm, &"", &"ranged", 150, "Default (ranger pending) ranged")
	_assert_damage_percent(gm, &"", &"magic", 100, "Default (ranger pending) magic")

	print("  damage_percent values correct for all class/type combos")


func _assert_damage_percent(
	gm: Node, char_class: StringName, damage_type: StringName, expected: int, label: String
) -> void:
	var actual: int = gm.get_character_class_damage_percent(damage_type, char_class)
	if actual != expected:
		_fail("%s: expected %d%%, got %d%%" % [label, expected, actual])


func _assert_damage_percent_at_level(
	gm: Node,
	char_class: StringName,
	damage_type: StringName,
	level: int,
	expected: int,
	label: String
) -> void:
	var actual: int = gm.get_character_class_damage_percent(damage_type, char_class, level)
	if actual != expected:
		_fail("%s: expected %d%%, got %d%% at level %d" % [label, expected, actual, level])


# ======================================================================
# 2b. Level-aware damage_percent scaling at 10/15/20
# ======================================================================
func _check_damage_percent_level_scaling() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	# Level 10
	_assert_damage_percent_at_level(gm, &"fighter", &"melee", 10, 160, "Fighter melee Lv10")
	_assert_damage_percent_at_level(gm, &"ranger", &"ranged", 10, 160, "Ranger ranged Lv10")

	# Level 15
	_assert_damage_percent_at_level(gm, &"fighter", &"melee", 15, 170, "Fighter melee Lv15")
	_assert_damage_percent_at_level(gm, &"ranger", &"melee", 15, 60, "Ranger melee Lv15")
	_assert_damage_percent_at_level(gm, &"ranger", &"ranged", 15, 170, "Ranger ranged Lv15")
	_assert_damage_percent_at_level(gm, &"wizard", &"magic", 15, 220, "Wizard magic Lv15")

	# Level 20
	_assert_damage_percent_at_level(gm, &"fighter", &"melee", 20, 180, "Fighter melee Lv20")
	_assert_damage_percent_at_level(gm, &"ranger", &"melee", 20, 70, "Ranger melee Lv20")
	_assert_damage_percent_at_level(gm, &"ranger", &"ranged", 20, 175, "Ranger ranged Lv20")
	_assert_damage_percent_at_level(gm, &"wizard", &"magic", 20, 240, "Wizard magic Lv20")
	_assert_damage_percent_at_level(gm, &"wizard", &"melee", 20, 70, "Wizard melee Lv20")
	_assert_damage_percent_at_level(gm, &"wizard", &"ranged", 20, 70, "Wizard ranged Lv20")

	print("  damage_percent level scaling correct at 10/15/20")


# ======================================================================
# 6. Game integration wires GameManager class modifiers into damage pipeline
# ======================================================================


func _check_game_integration_class_damage() -> void:
	seed(424242)

	var game_script: GDScript = load("res://scripts/game.gd")
	var actor_script: GDScript = _actor_script
	var stats_script: GDScript = _stats_script

	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	# --- _apply_typed_damage with wizard class at level 20 ---
	gm.prepare_character("WizardTest", {}, &"wizard")

	# Set up player with level 20 to exercise level-aware class scaling
	var player = actor_script.new()
	var player_stats = stats_script.new()
	player_stats.name = "StatsComponent"
	player_stats.level = 20
	player.add_child(player_stats)
	player.stats_component = player_stats

	var game = game_script.new()
	game._player = player

	var defender = actor_script.new()
	var def_stats = stats_script.new()
	def_stats.name = "StatsComponent"
	def_stats.max_hp = 100
	def_stats.current_hp = 100
	defender.add_child(def_stats)
	root.add_child(defender)
	await process_frame

	# 6a. Wizard magic at level 20 = 240% → 10 * 240/100 = 24
	var magic_dmg: int = game._apply_typed_damage(defender, 10, &"magic")
	if magic_dmg != 24:
		_fail("Wizard Lv20 _apply_typed_damage(magic, 10): expected 24, got %d" % magic_dmg)
		return

	# 6b. Wizard ranged at level 20 = 70% → 10 * 70/100 = 7
	def_stats.current_hp = 100
	var ranged_dmg: int = game._apply_typed_damage(defender, 10, &"ranged")
	if ranged_dmg != 7:
		_fail("Wizard Lv20 _apply_typed_damage(ranged, 10): expected 7, got %d" % ranged_dmg)
		return

	# --- _get_attacker_damage_percent with ranger class at level 20 ---
	gm.prepare_character("RangerTest", {}, &"ranger")
	player_stats.level = 20

	# 6c. Ranger player ranged at level 20 = 175%
	var player_pct: int = game._get_attacker_damage_percent(player, &"ranged")
	if player_pct != 175:
		_fail(
			(
				"Ranger Lv20 _get_attacker_damage_percent(player, ranged): expected 175, got %d"
				% player_pct
			)
		)
		return

	# 6d. Non-player attacker → always 100% regardless of level
	var other = actor_script.new()
	var other_pct: int = game._get_attacker_damage_percent(other, &"ranged")
	if other_pct != 100:
		_fail("_get_attacker_damage_percent(non-player, ranged): expected 100, got %d" % other_pct)
		return

	game.free()
	player.queue_free()
	other.queue_free()
	defender.queue_free()
	await process_frame
	print(
		"  Game integration correctly wires GameManager class modifiers into game damage pipeline"
	)


# ======================================================================
# 3+4. CharacterCreation class selector + Wizard selection stores &"wizard"
# ======================================================================
func _check_character_creation_class_and_begin() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	var scene: PackedScene = load("res://scenes/character_creation.tscn")
	var creation: Node = scene.instantiate()
	root.add_child(creation)
	await process_frame

	var selector = creation.class_selector

	# Verify 3 class items
	if selector.get_item_count() != 3:
		_fail("ClassSelector item count expected 3, got %d" % selector.get_item_count())
		creation.queue_free()
		return

	if selector.get_item_text(0) != "Fighter":
		_fail("ClassSelector[0] expected 'Fighter', got '%s'" % selector.get_item_text(0))
		creation.queue_free()
		return
	if selector.get_item_text(1) != "Ranger":
		_fail("ClassSelector[1] expected 'Ranger', got '%s'" % selector.get_item_text(1))
		creation.queue_free()
		return
	if selector.get_item_text(2) != "Wizard":
		_fail("ClassSelector[2] expected 'Wizard', got '%s'" % selector.get_item_text(2))
		creation.queue_free()
		return

	# Simulate selecting Wizard (index 2)
	creation._on_class_selected(2)
	var selected_id: StringName = creation._selected_class_id()
	if selected_id != &"wizard":
		_fail(
			"After selecting Wizard, _selected_class_id() expected 'wizard', got '%s'" % selected_id
		)

	# Set a valid name so _is_valid_assignment passes
	creation.name_input.text = "TestWizard"

	# Duplicate the _begin_run logic without the scene change (prepare_character
	# runs before change_scene_to_file, so we capture the same effect).
	var ability_scores: Dictionary = {}
	for index in range(creation.STAT_KEYS.size()):
		var roll_index: int = creation._selectors[index].get_selected_id()
		ability_scores[creation.STAT_KEYS[index]] = creation._rolls[roll_index]
	gm.prepare_character(creation.name_input.text, ability_scores, selected_id)

	if gm.pending_character_class != &"wizard":
		_fail(
			(
				"After Wizard selection + begin, pending_character_class expected 'wizard', got '%s'"
				% gm.pending_character_class
			)
		)
	if gm.pending_character_name != "TestWizard":
		_fail(
			(
				"After begin, pending_character_name expected 'TestWizard', got '%s'"
				% gm.pending_character_name
			)
		)
		return

	creation.queue_free()
	await process_frame
	print("  CharacterCreation ClassSelector has Fighter/Ranger/Wizard, Wizard begin stores wizard")


# ======================================================================
# 5. CombatSystem.attack respects attacker_damage_percent independently
# ======================================================================
func _check_combat_attack_damage_percent() -> void:
	seed(424242)
	var combat_script: GDScript = _combat_script
	var actor_script: GDScript = _actor_script
	var stats_script: GDScript = _stats_script

	if combat_script == null or actor_script == null or stats_script == null:
		_fail("Failed to load required script (CombatSystem, Actor, or StatsComponent)")
		return

	var attacker = actor_script.new()
	var attacker_stats = stats_script.new()
	attacker_stats.name = "StatsComponent"
	attacker_stats.strength = 10
	attacker_stats.dexterity = 10
	attacker_stats.constitution = 10
	attacker_stats.intelligence = 10
	attacker_stats.wisdom = 10
	attacker_stats.charisma = 10
	attacker_stats.max_hp = 100
	attacker_stats.current_hp = 100
	attacker_stats.base_armor_class = 10
	attacker_stats.base_attack_bonus = 20
	attacker_stats.base_damage_sides = 1
	attacker_stats.base_damage_bonus = 0
	attacker_stats.proficiency_bonus = 2
	attacker.add_child(attacker_stats)

	var defender = actor_script.new()
	var defender_stats = stats_script.new()
	defender_stats.name = "StatsComponent"
	defender_stats.strength = 10
	defender_stats.dexterity = 10
	defender_stats.constitution = 10
	defender_stats.intelligence = 10
	defender_stats.wisdom = 10
	defender_stats.charisma = 10
	defender_stats.max_hp = 100
	defender_stats.current_hp = 100
	defender_stats.base_armor_class = 10
	defender_stats.base_attack_bonus = 0
	defender_stats.base_damage_sides = 1
	defender_stats.base_damage_bonus = 0
	defender_stats.proficiency_bonus = 2
	defender.add_child(defender_stats)

	root.add_child(attacker)
	root.add_child(defender)
	await process_frame

	# Three attacks with same seed → same d20 roll and same raw_damage.
	# Reseed before each attack so all three get identical sequences.

	# r1: baseline (attacker=100, defender=100)
	seed(424242)
	var r1: Dictionary = combat_script.attack(attacker, defender, 100, 100)
	if not r1.hit:
		_fail("Baseline attack missed — test precondition failed")

	# r2: attacker_damage_percent = 200, damage_percent = 100
	defender_stats.current_hp = defender_stats.max_hp
	seed(424242)
	var r2: Dictionary = combat_script.attack(attacker, defender, 100, 200)
	if not r2.hit:
		_fail("Attacker-percent attack missed — test precondition failed")

	# r3: attacker_damage_percent = 100, damage_percent = 200
	defender_stats.current_hp = defender_stats.max_hp
	seed(424242)
	var r3: Dictionary = combat_script.attack(attacker, defender, 200, 100)
	if not r3.hit:
		_fail("Defender-percent attack missed — test precondition failed")

	# All three get the same raw_damage (same seed → same dice sequence)
	if r1.raw_damage != r2.raw_damage or r2.raw_damage != r3.raw_damage:
		_fail(
			(
				"Same seed produced different raw_damage: %d, %d, %d"
				% [r1.raw_damage, r2.raw_damage, r3.raw_damage]
			)
		)

	# ----- attacker_damage_percent independence -----
	# With damage_percent=100, attacker_scaled depends ONLY on attacker_damage_percent.
	var r1_expected_att_scaled: int = _compute_scaled(r1.raw_damage, 100)
	if r1.attacker_scaled_damage != r1_expected_att_scaled:
		_fail(
			(
				"r1: attacker_scaled %d ≠ _apply(100, raw=%d) = %d"
				% [r1.attacker_scaled_damage, r1.raw_damage, r1_expected_att_scaled]
			)
		)

	var r2_expected_att_scaled: int = _compute_scaled(r2.raw_damage, 200)
	if r2.attacker_scaled_damage != r2_expected_att_scaled:
		_fail(
			(
				"r2: attacker_scaled %d ≠ _apply(200, raw=%d) = %d"
				% [r2.attacker_scaled_damage, r2.raw_damage, r2_expected_att_scaled]
			)
		)

	var r3_expected_att_scaled: int = _compute_scaled(r3.raw_damage, 100)
	if r3.attacker_scaled_damage != r3_expected_att_scaled:
		_fail(
			(
				"r3: attacker_scaled %d ≠ _apply(100, raw=%d) = %d"
				% [r3.attacker_scaled_damage, r3.raw_damage, r3_expected_att_scaled]
			)
		)

	# ----- damage_percent independence -----
	# With attacker_damage_percent fixed, final damage scales with damage_percent.
	var r1_expected_damage: int = _compute_scaled(r1.attacker_scaled_damage, 100)
	if r1.damage != r1_expected_damage:
		_fail(
			(
				"r1: damage %d ≠ _apply(100, att_scaled=%d) = %d"
				% [r1.damage, r1.attacker_scaled_damage, r1_expected_damage]
			)
		)

	var r2_expected_damage: int = _compute_scaled(r2.attacker_scaled_damage, 100)
	if r2.damage != r2_expected_damage:
		_fail(
			(
				"r2: damage %d ≠ _apply(100, att_scaled=%d) = %d"
				% [r2.damage, r2.attacker_scaled_damage, r2_expected_damage]
			)
		)

	var r3_expected_damage: int = _compute_scaled(r3.attacker_scaled_damage, 200)
	if r3.damage != r3_expected_damage:
		_fail(
			(
				"r3: damage %d ≠ _apply(200, att_scaled=%d) = %d"
				% [r3.damage, r3.attacker_scaled_damage, r3_expected_damage]
			)
		)

	# Sanity: the two percent changes each affected damage differently.
	if r1.damage == r2.damage and r1.damage == r3.damage:
		_fail("Neither attacker_percent nor defender_percent changed damage — pipeline broken")

	attacker.queue_free()
	defender.queue_free()
	await process_frame
	print("  CombatSystem.attack applies attacker_damage_percent and damage_percent independently")


# ======================================================================
# Helpers
# ======================================================================
func _compute_scaled(raw_damage: int, percent: int) -> int:
	# Mirrors CombatSystem._apply_damage_percent exactly
	if percent <= 0:
		return 0
	if percent == 100:
		return raw_damage
	return max(1, int(round(raw_damage * percent / 100.0)))
