## V23.0.0 Projectile runtime combat integration tests.
##
## Contracts:
##   1. Staff shot via _resolve_ranged_attack creates ember_bolt trail and damages HP.
##   2. Physical bow shot with Hunter's Focus primed creates arrow trail and consumes focus.
##   3. Magic Missile creates at least 3 trails against visible targets.
##   4. Fireball area damage creates travel + area trails when enemies in radius.
##   5. Fireball returns false/no trail when no enemies are caught.
##   6. Enemy ranged attack creates ember_arrow trail and reduces player HP.
##   7. Enemy fireball creates fireball trail and reduces player HP.
##
## Run:
##   /usr/local/bin/godot --headless --path . --script \
##      res://scripts/tests/test_v23_projectile_runtime.gd
extends SceneTree

const ENEMY_DATA_PATH: String = "res://resources/enemies/goblin.tres"
const EMBER_ARCHER_PATH: String = "res://resources/enemies/ember_archer.tres"
const FLAME_ACOLYTE_PATH: String = "res://resources/enemies/flame_acolyte.tres"
const STAFF_EMBER_PATH: String = "res://resources/items/staff_ember.tres"
const HUNTING_BOW_PATH: String = "res://resources/items/hunting_bow.tres"
const SCROLL_MAGIC_MISSILE_PATH: String = "res://resources/items/scroll_magic_missile.tres"
const SCROLL_FIREBALL_PATH: String = "res://resources/items/scroll_fireball.tres"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(220000)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {}, game_manager.CLASS_WIZARD)
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	while game_manager.current_floor < 1:
		game._debug_descend_deeper()
		await process_frame

	# Clear the map area around the player for reliable placement
	var center: Vector2i = game._player.grid_position
	_prepare_open_area(game, game_manager, center)

	game.map_view.set_atmosphere_enabled(false)
	await process_frame

	# ---- 1. Wizard staff shot ----
	_check_staff_ranged_attack(game, game_manager, center)
	if _failed:
		return

	# ---- 2. Physical bow with Hunter's Focus ----
	_check_bow_hunter_focus(game, game_manager, center)
	if _failed:
		return

	# ---- 3. Magic Missile ----
	_check_magic_missile_trails(game, game_manager, center)
	if _failed:
		return

	# ---- 4. Fireball area damage ----
	_check_fireball_area_damage(game, game_manager, center)
	if _failed:
		return

	# ---- 5. Fireball no enemies ----
	_check_fireball_no_enemies(game, game_manager, center)
	if _failed:
		return

	# ---- 6. Enemy ranged attack ----
	_check_enemy_ranged(game, game_manager, center)
	if _failed:
		return

	# ---- 7. Enemy fireball ----
	_check_enemy_fireball(game, game_manager, center)
	if _failed:
		return

	game.queue_free()
	await process_frame
	print("V23 projectile runtime checks passed")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _prepare_open_area(game: Node, game_manager: Node, center: Vector2i) -> void:
	for enemy in game._enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	game._enemies.clear()
	game_manager.clear_enemies()

	for y_offset: int in range(-6, 7):
		for x_offset: int in range(-6, 7):
			var cell: Vector2i = center + Vector2i(x_offset, y_offset)
			if _is_inside_map(game_manager, cell):
				game_manager.map_data[cell.y][cell.x] = 0

	game._refresh_visibility()
	game._refresh_map()


func _is_inside_map(game_manager: Node, cell: Vector2i) -> bool:
	return (
		cell.y > 0
		and cell.y < game_manager.map_data.size() - 1
		and cell.x > 0
		and cell.x < game_manager.map_data[0].size() - 1
	)


func _spawn_enemy(game: Node, game_manager: Node, enemy_path: String, pos: Vector2i) -> Node:
	var enemy_data: Resource = load(enemy_path)
	if enemy_data == null:
		_fail("Failed to load enemy at %s" % enemy_path)
		return null
	var enemy: Node = game._spawn_enemy_instance(enemy_data, pos, game_manager.current_floor, false)
	game._refresh_visibility()
	return enemy


func _reset_trails(game: Node) -> void:
	if game.map_view != null and is_instance_valid(game.map_view):
		game.map_view._projectile_trails.clear()


func _check_staff_ranged_attack(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)
	var staff: Resource = load(STAFF_EMBER_PATH)
	if staff == null:
		_fail("Staff Ember failed to load")
		return

	# Spawn a defender enemy for realistic combat
	var target_pos: Vector2i = center + Vector2i(3, 0)
	var target: Node = _spawn_enemy(game, game_manager, ENEMY_DATA_PATH, target_pos)
	if target == null:
		return

	# Set low AC to guarantee hit
	target.stats_component.base_armor_class = 1

	_reset_trails(game)
	var hp_before: int = target.stats_component.current_hp

	game._resolve_ranged_attack(staff, target, &"weapon")

	var trails: Array = game.map_view._projectile_trails
	if trails.is_empty():
		_fail("Staff shot should create a projectile trail")
		return

	var last_trail: Dictionary = trails[trails.size() - 1]
	var profile: StringName = last_trail.get("profile_id", &"")
	if profile != &"ember_bolt":
		_fail('Staff shot profile_id expected &"ember_bolt", got %s' % str(profile))
		return

	# Check that damage was dealt (WIS-based magic pipeline)
	if target.stats_component.current_hp >= hp_before:
		_fail("Staff shot should reduce target HP (WIS/magic pipeline)")
		return

	print("  staff ranged attack: ember_bolt trail + HP reduction")


func _check_bow_hunter_focus(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)
	var bow: Resource = load(HUNTING_BOW_PATH)
	if bow == null:
		_fail("Hunting Bow failed to load")
		return

	# Spawn a defender enemy for realistic combat
	var target_pos: Vector2i = center + Vector2i(3, 0)
	var target: Node = _spawn_enemy(game, game_manager, ENEMY_DATA_PATH, target_pos)
	if target == null:
		return

	# Set low AC to guarantee hit
	target.stats_component.base_armor_class = 1

	_reset_trails(game)

	# Prime Hunter's Focus
	game._hunter_focus_primed = true

	game._resolve_ranged_attack(bow, target, &"weapon")

	# Check that Hunter's Focus was consumed
	if game._hunter_focus_primed == true:
		_fail("Hunter's Focus should be consumed after ranged attack")
		return

	# Check projectile was created
	var trails: Array = game.map_view._projectile_trails
	if trails.is_empty():
		_fail("Bow shot should create a projectile trail")
		return

	var last_trail: Dictionary = trails[trails.size() - 1]
	var profile: StringName = last_trail.get("profile_id", &"")
	if profile != &"arrow":
		_fail('Bow shot profile_id expected &"arrow", got %s' % str(profile))
		return

	print("  bow Hunter's Focus: arrow trail + focus consumed")


func _check_magic_missile_trails(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)
	var missile: Resource = load(SCROLL_MAGIC_MISSILE_PATH)
	if missile == null:
		_fail("Scroll of Magic Missile failed to load")
		return

	# Spawn 3 enemies in range
	var positions: Array[Vector2i] = [
		center + Vector2i(2, 0),
		center + Vector2i(0, 2),
		center + Vector2i(3, 1),
	]
	var enemies: Array[Node] = []
	for pos: Vector2i in positions:
		var enemy: Node = _spawn_enemy(game, game_manager, ENEMY_DATA_PATH, pos)
		if enemy == null:
			_fail("Failed to spawn enemy for magic missile test")
			return
		enemies.append(enemy)

	game._refresh_visibility()

	# Verify all 3 are alive and visible
	for enemy in enemies:
		if not enemy.is_alive():
			_fail("Enemy died before magic missile test")
			return
		if not game._visible_cells.has(enemy.grid_position):
			_fail("Enemy at %s not visible for magic missile test" % str(enemy.grid_position))
			return

	_reset_trails(game)
	var resolved: bool = game._resolve_magic_missile(
		missile.duplicate(true), enemies[0].grid_position
	)

	if not resolved:
		_fail("Magic Missile should resolve against visible targets")
		return

	# Check that projectile trails were created for each missile
	var trails: Array = game.map_view._projectile_trails
	if trails.size() < 3:
		_fail("Magic Missile should create at least 3 projectile trails, got %d" % trails.size())
		return

	# Check that at least 3 trails have profile_id "magic_missile"
	var magic_missile_count: int = 0
	for trail: Dictionary in trails:
		if trail.get("profile_id", &"") == &"magic_missile":
			magic_missile_count += 1
	if magic_missile_count < 3:
		_fail("Expected at least 3 magic_missile trails, got %d" % magic_missile_count)
		return

	print("  magic missile: %d trails (%d magic_missile)" % [trails.size(), magic_missile_count])


func _check_fireball_area_damage(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)
	var fireball: Resource = load(SCROLL_FIREBALL_PATH)
	if fireball == null:
		_fail("Scroll of Fireball failed to load")
		return

	# Spawn enemies within radius 1 of a target cell
	var blast_center: Vector2i = center + Vector2i(3, 0)
	var positions: Array[Vector2i] = [
		blast_center,
		blast_center + Vector2i(1, 0),
	]
	var enemies: Array[Node] = []
	for pos: Vector2i in positions:
		var enemy: Node = _spawn_enemy(game, game_manager, ENEMY_DATA_PATH, pos)
		if enemy == null:
			_fail("Failed to spawn enemy for fireball test")
			return
		enemies.append(enemy)

	game._refresh_visibility()
	_reset_trails(game)

	var resolved: bool = game._resolve_targeted_item(
		fireball.duplicate(true), blast_center, &"consumable"
	)

	if not resolved:
		_fail("Fireball should resolve when enemies are in radius")
		return

	var trails: Array = game.map_view._projectile_trails
	if trails.size() < 2:
		_fail("Fireball should create at least 2 trails (travel + area), got %d" % trails.size())
		return

	print("  fireball area damage: %d trails created, resolved=%s" % [trails.size(), resolved])


func _check_fireball_no_enemies(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)

	# Clear existing enemies from area
	_prepare_open_area(game, game_manager, center)

	var fireball: Resource = load(SCROLL_FIREBALL_PATH)
	if fireball == null:
		_fail("Scroll of Fireball failed to load")
		return

	var far_cell: Vector2i = center + Vector2i(6, 0)
	_reset_trails(game)

	var resolved: bool = game._resolve_targeted_item(
		fireball.duplicate(true), far_cell, &"consumable"
	)

	if resolved:
		_fail("Fireball should return false when no enemies in radius")
		return

	var new_trails: int = game.map_view._projectile_trails.size()
	if new_trails != 0:
		_fail("Fireball with no enemies should create 0 trails, got %d" % new_trails)
		return

	print("  fireball no enemies: returned false, 0 trails")


func _check_enemy_ranged(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)
	_prepare_open_area(game, game_manager, center)

	var enemy: Node = _spawn_enemy(game, game_manager, EMBER_ARCHER_PATH, center + Vector2i(5, 0))
	if enemy == null:
		return

	game._refresh_visibility()
	_reset_trails(game)

	var hp_before: int = game._player.stats_component.current_hp

	game._resolve_enemy_ranged_attack(enemy)

	var trails: Array = game.map_view._projectile_trails
	if trails.is_empty():
		_fail("Enemy ranged attack should create a projectile trail")
		return

	var last_trail: Dictionary = trails[trails.size() - 1]
	var profile: StringName = last_trail.get("profile_id", &"")
	if profile != &"ember_arrow":
		_fail('Ember Archer projectile expected &"ember_arrow", got %s' % str(profile))
		return

	if game._player.stats_component.current_hp >= hp_before:
		_fail("Enemy ranged attack should reduce player HP")
		return

	print("  enemy ranged: ember_arrow trail + player HP reduction")


func _check_enemy_fireball(game: Node, game_manager: Node, center: Vector2i) -> void:
	seed(220000)
	_prepare_open_area(game, game_manager, center)

	var enemy: Node = _spawn_enemy(game, game_manager, FLAME_ACOLYTE_PATH, center + Vector2i(5, 0))
	if enemy == null:
		return

	game._refresh_visibility()
	_reset_trails(game)

	var hp_before: int = game._player.stats_component.current_hp

	game._resolve_enemy_fireball(enemy)

	var trails: Array = game.map_view._projectile_trails
	if trails.is_empty():
		_fail("Enemy fireball should create a projectile trail")
		return

	var last_trail: Dictionary = trails[trails.size() - 1]
	var profile: StringName = last_trail.get("profile_id", &"")
	if profile != &"fireball":
		_fail('Flame Acolyte fireball expected &"fireball", got %s' % str(profile))
		return

	if game._player.stats_component.current_hp >= hp_before:
		_fail("Enemy fireball should reduce player HP")
		return

	print("  enemy fireball: fireball trail + player HP reduction")
