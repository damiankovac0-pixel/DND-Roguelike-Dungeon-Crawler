## Headless test for V12.1.0 class ability entries — 3 per class, locks, level-20 upgrades.
##
## Contracts:
##   1. _get_class_ability_entries() returns three entries per class: Lv1 unlocked,
##      Lv6/Lv12 locked at level 1 with unlock_level/disabled_reason; at level 20
##      all three are enabled and core ability charges_max = 2.
## Run:
##   /usr/local/bin/godot --headless --path . \
##      --script res://scripts/tests/test_v12_class_entries.gd
extends SceneTree

var _game_script: GDScript
var _actor_script: GDScript
var _stats_script: GDScript
var _inventory_script: GDScript
var _player_script: GDScript
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

	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	_check_fighter_entries(gm)
	if not _failed:
		_check_ranger_entries(gm)
	if not _failed:
		_check_wizard_entries(gm)

	if not _failed:
		print("V12.1.0 class ability entries check passed")
		quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


# ======================================================================
# Helpers
# ======================================================================


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


# ======================================================================
# Fighter entries — 3 entries, Lv1 locked/unlocked, Lv20 all enabled
# ======================================================================


func _check_fighter_entries(gm: Node) -> void:
	gm.prepare_character("FighterTest", {}, &"fighter")
	var game: Node = _game_script.new()
	game._player = _make_player(Vector2i(5, 5), _actor_script, 1)
	game._fighter_cleave_charges = 1
	game._fighter_second_wind_charges = 1
	game._fighter_whirlwind_charges = 1
	game._cleave_primed = false

	var ok: bool = true
	var entries: Array[Dictionary] = game._get_class_ability_entries()

	if entries.size() != 3:
		_fail("Fighter Lv1: expected 3 ability entries, got %d" % entries.size())
		ok = false

	if ok:
		var e0: Dictionary = entries[0]
		if e0.get("ability_id", &"") != &"fighter_cleave":
			_fail(
				(
					"Fighter[0]: ability_id expected 'fighter_cleave', got '%s'"
					% e0.get("ability_id", "")
				)
			)
			ok = false
		elif e0.get("name", "") != "Cleave":
			_fail("Fighter[0]: name expected 'Cleave', got '%s'" % e0.get("name", ""))
			ok = false
		elif e0.get("charges_current", -1) != 1:
			_fail(
				"Fighter[0] Lv1: charges_current expected 1, got %d" % e0.get("charges_current", -1)
			)
			ok = false
		elif e0.get("charges_max", -1) != 1:
			_fail("Fighter[0] Lv1: charges_max expected 1, got %d" % e0.get("charges_max", -1))
			ok = false
		elif e0.get("enabled", false) != true:
			_fail("Fighter[0] Lv1: enabled expected true (charges>0, not primed)")
			ok = false
		elif e0.get("active", true) != false:
			_fail("Fighter[0] Lv1: active expected false when not primed")
			ok = false
		elif e0.has("unlock_level"):
			_fail("Fighter[0] Lv1: should NOT have unlock_level (unlocked)")
			ok = false
		elif e0.has("disabled_reason"):
			_fail("Fighter[0] Lv1: should NOT have disabled_reason (unlocked)")
			ok = false

	if ok:
		var e1: Dictionary = entries[1]
		if e1.get("ability_id", &"") != &"fighter_second_wind":
			_fail(
				(
					"Fighter[1]: ability_id expected 'fighter_second_wind', got '%s'"
					% e1.get("ability_id", "")
				)
			)
			ok = false
		elif e1.get("name", "") != "Second Wind":
			_fail("Fighter[1]: name expected 'Second Wind', got '%s'" % e1.get("name", ""))
			ok = false
		elif e1.get("charges_current", -1) != 0:
			_fail(
				(
					"Fighter[1] Lv1: charges_current expected 0 (locked), got %d"
					% e1.get("charges_current", -1)
				)
			)
			ok = false
		elif e1.get("enabled", true) != false:
			_fail("Fighter[1] Lv1: enabled expected false (locked)")
			ok = false
		elif e1.get("unlock_level", 0) != 6:
			_fail("Fighter[1] Lv1: unlock_level expected 6, got %d" % e1.get("unlock_level", 0))
			ok = false
		elif e1.get("disabled_reason", "") != "Unlocks at level 6.":
			var got_dr: String = e1.get("disabled_reason", "")
			_fail(
				(
					"Fighter[1] Lv1: disabled_reason expected 'Unlocks at level 6.',"
					+ " got '%s'" % got_dr
				)
			)
			ok = false

	if ok:
		var e2: Dictionary = entries[2]
		if e2.get("ability_id", &"") != &"fighter_whirlwind":
			_fail(
				(
					"Fighter[2]: ability_id expected 'fighter_whirlwind', got '%s'"
					% e2.get("ability_id", "")
				)
			)
			ok = false
		elif e2.get("name", "") != "Whirlwind":
			_fail("Fighter[2]: name expected 'Whirlwind', got '%s'" % e2.get("name", ""))
			ok = false
		elif e2.get("charges_current", -1) != 0:
			_fail(
				(
					"Fighter[2] Lv1: charges_current expected 0 (locked), got %d"
					% e2.get("charges_current", -1)
				)
			)
			ok = false
		elif e2.get("enabled", true) != false:
			_fail("Fighter[2] Lv1: enabled expected false (locked)")
			ok = false
		elif e2.get("unlock_level", 0) != 12:
			_fail("Fighter[2] Lv1: unlock_level expected 12, got %d" % e2.get("unlock_level", 0))
			ok = false
		elif e2.get("disabled_reason", "") != "Unlocks at level 12.":
			var got_dr: String = e2.get("disabled_reason", "")
			_fail(
				(
					"Fighter[2] Lv1: disabled_reason expected 'Unlocks at level 12.',"
					+ " got '%s'" % got_dr
				)
			)
			ok = false

	# Level 20: Cleave charges_max=2, Second Wind + Whirlwind unlocked
	if ok:
		_free_test_node(game._player)
		game._player = _make_player(Vector2i(5, 5), _actor_script, 20)
		game._fighter_cleave_charges = 2
		entries = game._get_class_ability_entries()
		if entries.size() != 3:
			_fail("Fighter Lv20: expected 3 entries, got %d" % entries.size())
			ok = false

	if ok:
		var e0: Dictionary = entries[0]
		if e0.get("charges_max", -1) != 2:
			_fail("Fighter cleave Lv20: charges_max expected 2, got %d" % e0.get("charges_max", -1))
			ok = false
		elif e0.get("charges_current", -1) != 2:
			_fail(
				(
					"Fighter cleave Lv20: charges_current expected 2, got %d"
					% e0.get("charges_current", -1)
				)
			)
			ok = false

	if ok:
		var e1: Dictionary = entries[1]
		if e1.get("enabled", false) != true:
			_fail("Fighter Second Wind Lv20: enabled expected true")
			ok = false
		elif e1.has("unlock_level"):
			_fail("Fighter Second Wind Lv20: should NOT have unlock_level (unlocked)")
			ok = false
		elif e1.has("disabled_reason"):
			_fail("Fighter Second Wind Lv20: should NOT have disabled_reason (unlocked)")
			ok = false

	if ok:
		var e2: Dictionary = entries[2]
		if e2.get("enabled", false) != true:
			_fail("Fighter Whirlwind Lv20: enabled expected true")
			ok = false
		elif e2.has("unlock_level"):
			_fail("Fighter Whirlwind Lv20: should NOT have unlock_level (unlocked)")
			ok = false

	if not ok:
		_free_game(game)
		return

	_free_game(game)
	print(
		(
			"  Fighter entries correct (Lv1: Cleave unlocked, Second Wind/Whirlwind"
			+ " locked; Lv20: all enabled, Cleave 2 charges)"
		)
	)


# ======================================================================
# Ranger entries — 3 entries, Lv1 unlocked, Lv6/Lv12 locked at level 1
# ======================================================================


func _check_ranger_entries(gm: Node) -> void:
	gm.prepare_character("RangerTest", {}, &"ranger")
	var game: Node = _game_script.new()
	game._player = _make_player(Vector2i(5, 5), _actor_script, 1)
	game._ranger_focus_charges = 1
	game._ranger_volley_charges = 1
	game._ranger_quickstep_charges = 1
	game._hunter_focus_primed = false

	var ok: bool = true
	var entries: Array[Dictionary] = game._get_class_ability_entries()

	if entries.size() != 3:
		_fail("Ranger Lv1: expected 3 ability entries, got %d" % entries.size())
		ok = false

	if ok:
		var e0: Dictionary = entries[0]
		if e0.get("ability_id", &"") != &"ranger_focus":
			_fail(
				"Ranger[0]: ability_id expected 'ranger_focus', got '%s'" % e0.get("ability_id", "")
			)
			ok = false
		elif e0.get("name", "") != "Hunter's Focus":
			_fail("Ranger[0]: name expected 'Hunter\\'s Focus', got '%s'" % e0.get("name", ""))
			ok = false
		elif e0.get("charges_current", -1) != 1:
			_fail(
				"Ranger[0] Lv1: charges_current expected 1, got %d" % e0.get("charges_current", -1)
			)
			ok = false
		elif e0.get("charges_max", -1) != 1:
			_fail("Ranger[0] Lv1: charges_max expected 1, got %d" % e0.get("charges_max", -1))
			ok = false
		elif e0.has("unlock_level"):
			_fail("Ranger[0] Lv1: should NOT have unlock_level (unlocked)")
			ok = false

	if ok:
		var e1: Dictionary = entries[1]
		if e1.get("ability_id", &"") != &"ranger_volley":
			_fail(
				(
					"Ranger[1]: ability_id expected 'ranger_volley', got '%s'"
					% e1.get("ability_id", "")
				)
			)
			ok = false
		elif e1.get("name", "") != "Volley":
			_fail("Ranger[1]: name expected 'Volley', got '%s'" % e1.get("name", ""))
			ok = false
		elif e1.get("charges_current", -1) != 0:
			_fail(
				(
					"Ranger[1] Lv1: charges_current expected 0 (locked), got %d"
					% e1.get("charges_current", -1)
				)
			)
			ok = false
		elif e1.get("enabled", true) != false:
			_fail("Ranger[1] Lv1: enabled expected false (locked)")
			ok = false
		elif e1.get("unlock_level", 0) != 6:
			_fail("Ranger[1] Lv1: unlock_level expected 6, got %d" % e1.get("unlock_level", 0))
			ok = false
		elif e1.get("disabled_reason", "") != "Unlocks at level 6.":
			var got_dr: String = e1.get("disabled_reason", "")
			_fail(
				(
					"Ranger[1] Lv1: disabled_reason expected 'Unlocks at level 6.',"
					+ " got '%s'" % got_dr
				)
			)
			ok = false

	if ok:
		var e2: Dictionary = entries[2]
		if e2.get("ability_id", &"") != &"ranger_quickstep":
			_fail(
				(
					"Ranger[2]: ability_id expected 'ranger_quickstep', got '%s'"
					% e2.get("ability_id", "")
				)
			)
			ok = false
		elif e2.get("name", "") != "Quickstep":
			_fail("Ranger[2]: name expected 'Quickstep', got '%s'" % e2.get("name", ""))
			ok = false
		elif e2.get("charges_current", -1) != 0:
			_fail(
				(
					"Ranger[2] Lv1: charges_current expected 0 (locked), got %d"
					% e2.get("charges_current", -1)
				)
			)
			ok = false
		elif e2.get("unlock_level", 0) != 12:
			_fail("Ranger[2] Lv1: unlock_level expected 12, got %d" % e2.get("unlock_level", 0))
			ok = false
		elif e2.get("disabled_reason", "") != "Unlocks at level 12.":
			var got_dr: String = e2.get("disabled_reason", "")
			_fail(
				(
					"Ranger[2] Lv1: disabled_reason expected 'Unlocks at level 12.',"
					+ " got '%s'" % got_dr
				)
			)
			ok = false

	if not ok:
		_free_game(game)
		return

	_free_game(game)
	print("  Ranger entries correct (Lv1: Hunter's Focus unlocked;" + " Volley/Quickstep locked)")


# ======================================================================
# Wizard entries — 3 entries, Lv1 unlocked, Lv6/Lv12 locked at level 1
# ======================================================================


func _check_wizard_entries(gm: Node) -> void:
	gm.prepare_character("WizardTest", {}, &"wizard")
	var game: Node = _game_script.new()
	game._player = _make_player(Vector2i(5, 5), _actor_script, 1)
	game._wizard_spark_charges = 1
	game._wizard_frost_nova_charges = 1
	game._wizard_chain_lightning_charges = 1

	var ok: bool = true
	var entries: Array[Dictionary] = game._get_class_ability_entries()

	if entries.size() != 3:
		_fail("Wizard Lv1: expected 3 ability entries, got %d" % entries.size())
		ok = false

	if ok:
		var e0: Dictionary = entries[0]
		if e0.get("ability_id", &"") != &"arcane_spark":
			_fail(
				"Wizard[0]: ability_id expected 'arcane_spark', got '%s'" % e0.get("ability_id", "")
			)
			ok = false
		elif e0.get("name", "") != "Arcane Spark":
			_fail("Wizard[0]: name expected 'Arcane Spark', got '%s'" % e0.get("name", ""))
			ok = false
		elif e0.get("charges_current", -1) != 1:
			_fail(
				"Wizard[0] Lv1: charges_current expected 1, got %d" % e0.get("charges_current", -1)
			)
			ok = false
		elif e0.get("charges_max", -1) != 1:
			_fail("Wizard[0] Lv1: charges_max expected 1, got %d" % e0.get("charges_max", -1))
			ok = false
		elif e0.has("unlock_level"):
			_fail("Wizard[0] Lv1: should NOT have unlock_level (unlocked)")
			ok = false

	if ok:
		var e1: Dictionary = entries[1]
		if e1.get("ability_id", &"") != &"wizard_frost_nova":
			_fail(
				(
					"Wizard[1]: ability_id expected 'wizard_frost_nova', got '%s'"
					% e1.get("ability_id", "")
				)
			)
			ok = false
		elif e1.get("name", "") != "Frost Nova":
			_fail("Wizard[1]: name expected 'Frost Nova', got '%s'" % e1.get("name", ""))
			ok = false
		elif e1.get("charges_current", -1) != 0:
			_fail(
				(
					"Wizard[1] Lv1: charges_current expected 0 (locked), got %d"
					% e1.get("charges_current", -1)
				)
			)
			ok = false
		elif e1.get("unlock_level", 0) != 6:
			_fail("Wizard[1] Lv1: unlock_level expected 6, got %d" % e1.get("unlock_level", 0))
			ok = false
		elif e1.get("disabled_reason", "") != "Unlocks at level 6.":
			var got_dr: String = e1.get("disabled_reason", "")
			_fail(
				(
					"Wizard[1] Lv1: disabled_reason expected 'Unlocks at level 6.',"
					+ " got '%s'" % got_dr
				)
			)
			ok = false

	if ok:
		var e2: Dictionary = entries[2]
		if e2.get("ability_id", &"") != &"wizard_chain_lightning":
			_fail(
				(
					"Wizard[2]: ability_id expected 'wizard_chain_lightning', got '%s'"
					% e2.get("ability_id", "")
				)
			)
			ok = false
		elif e2.get("name", "") != "Chain Lightning":
			_fail("Wizard[2]: name expected 'Chain Lightning', got '%s'" % e2.get("name", ""))
			ok = false
		elif e2.get("charges_current", -1) != 0:
			_fail(
				(
					"Wizard[2] Lv1: charges_current expected 0 (locked), got %d"
					% e2.get("charges_current", -1)
				)
			)
			ok = false
		elif e2.get("unlock_level", 0) != 12:
			_fail("Wizard[2] Lv1: unlock_level expected 12, got %d" % e2.get("unlock_level", 0))
			ok = false
		elif e2.get("disabled_reason", "") != "Unlocks at level 12.":
			var got_dr: String = e2.get("disabled_reason", "")
			_fail(
				(
					"Wizard[2] Lv1: disabled_reason expected 'Unlocks at level 12.',"
					+ " got '%s'" % got_dr
				)
			)
			ok = false

	if not ok:
		_free_game(game)
		return

	_free_game(game)
	print(
		(
			"  Wizard entries correct (Lv1: Arcane Spark unlocked;"
			+ " Frost Nova/Chain Lightning locked)"
		)
	)
