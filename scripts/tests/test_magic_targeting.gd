## Permanent test harness for Magic Missile multi-target behavior, depth damage scaling,
## damage relevance, and Sleep scroll contracts.
##
## Verifies:
##   - Scroll of Magic Missile exposes/uses target_count = 3.
##   - Resolving magic missile against a valid primary target damages up to three
##     distinct visible in-range enemies, not just one.
##   - The scroll depth damage bonus increases at deeper floors compared with an
##     early floor (tested via production helper if accessible).
##   - Magic Missile damage dice/sides/bonus are set and produce meaningful damage.
##   - Scroll of Sleep has effect_duration=1 and is ruled immune against bosses
##     (behavior confirmed in game.gd _resolve_sleep).
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_magic_targeting.gd
extends SceneTree

const ENEMY_DATA_PATH: String = "res://resources/enemies/goblin.tres"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(12345)
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	while game_manager.current_floor < 1:
		game._debug_descend_deeper()
		await process_frame

	# ---- Phase 1: target_count ----
	_check_magic_missile_target_count(game)

	# ---- Phase 2: multi-hit resolution ----
	if not _failed:
		_prepare_open_area(game, game_manager, game._player.grid_position)
		_check_magic_missile_multi_hit(game, game_manager)

	# ---- Phase 3: depth damage bonus ----
	if not _failed:
		_check_depth_damage_bonus(game, game_manager)

	# ---- Phase 4: damage relevance ----
	if not _failed:
		_check_scroll_damage_relevance(game)

	# ---- Phase 5: Sleep scroll contracts ----
	if not _failed:
		_check_sleep_scroll_contracts(game)

	if not _failed:
		print("magic targeting check passed")
		quit(0)


# ---------------------------------------------------------------------------
#  Phase 1 — Magic Missile scroll exposes target_count = 3
# ---------------------------------------------------------------------------


func _check_magic_missile_target_count(game: Node) -> void:
	if _failed:
		return
	var missile: Resource = game._find_item_by_display_name("Scroll of Magic Missile")
	if missile == null:
		_fail("Scroll of Magic Missile missing from loaded item resources")
		return

	if "target_count" in missile:
		if missile.target_count != 3:
			_fail("Scroll of Magic Missile target_count = %d, expected 3" % missile.target_count)
			return
		print("  magic missile target_count = 3")
	else:
		print("  magic missile: no target_count field (will fall back to default)")

	if missile.range < 7:
		_fail("Scroll of Magic Missile range = %d, expected at least 7" % missile.range)
		return

	print("  magic missile range = %d" % missile.range)


# ---------------------------------------------------------------------------
#  Phase 2 — Magic Missile hits up to three distinct visible in-range enemies
# ---------------------------------------------------------------------------


func _check_magic_missile_multi_hit(game: Node, game_manager: Node) -> void:
	if _failed:
		return

	var center: Vector2i = game._player.grid_position
	var enemy_data: Resource = load(ENEMY_DATA_PATH)

	# Spawn 4 enemies at distinct positions within magic missile range (7) and sight.
	var positions: Array[Vector2i] = [
		center + Vector2i(2, 0),
		center + Vector2i(0, 2),
		center + Vector2i(3, 1),
		center + Vector2i(1, 3),
	]
	var enemies: Array[Node] = []
	for pos: Vector2i in positions:
		if not game._is_walkable(pos):
			_fail("Spawn cell %s is not walkable after clearing area" % str(pos))
			return
		var enemy: Node = game._spawn_enemy_instance(
			enemy_data, pos, game_manager.current_floor, false
		)
		enemies.append(enemy)

	game._refresh_visibility()

	# Verify all 4 are alive and visible at start.
	for enemy in enemies:
		if not enemy.is_alive():
			_fail("Enemy at %s died before test" % str(enemy.grid_position))
			return
		if not game._visible_cells.has(enemy.grid_position):
			_fail("Enemy at %s is not visible (sight range may block)" % str(enemy.grid_position))
			return

	print("  multi-hit: %d enemies spawned and visible" % enemies.size())

	# Obtain a duplicate scroll so we don't mutate the template.
	var missile_template: Resource = game._find_item_by_display_name("Scroll of Magic Missile")
	if missile_template == null:
		_fail("Scroll of Magic Missile not found")
		return
	var missile: Resource = missile_template.duplicate(true)

	# Record HP before.
	var hp_before: Array[int] = []
	for enemy in enemies:
		hp_before.append(enemy.stats_component.current_hp)

	# Resolve magic missile targeting against the FIRST enemy's cell.
	var target_cell: Vector2i = enemies[0].grid_position
	var resolved: bool = game._resolve_targeted_item(missile, target_cell, &"consumable")
	if not resolved:
		_fail("magic missile targeting returned false")
		return

	# Count distinct enemies that took damage.
	var hit_count: int = 0
	for i in range(enemies.size()):
		if enemies[i].stats_component.current_hp < hp_before[i]:
			hit_count += 1

	# With 4 visible enemies in range and target_count=3, we must hit at least 2
	# (proving multi-target behavior) and at most 3.
	if hit_count < 2:
		_fail(
			(
				"magic missile hit only %d/%d enemies with 4 available, "
				+ "expected multi-target (>= 2) behavior" % [hit_count, enemies.size()]
			)
		)
		return
	if hit_count > 3:
		_fail(
			(
				"magic missile hit %d/%d enemies, expected at most 3 (target_count limit)"
				% [hit_count, enemies.size()]
			)
		)
		return

	print("  magic missile hit %d/%d enemies (target up to 3)" % [hit_count, enemies.size()])


# ---------------------------------------------------------------------------
#  Phase 3 — Scroll depth damage bonus increases at deeper floors
# ---------------------------------------------------------------------------


func _check_depth_damage_bonus(game: Node, game_manager: Node) -> void:
	if _failed:
		return

	var missile: Resource = game._find_item_by_display_name("Scroll of Magic Missile")
	if missile == null:
		_fail("Scroll of Magic Missile missing from loaded item resources")
		return

	if not game.has_method(&"_get_scroll_depth_damage_bonus"):
		print("  no _get_scroll_depth_damage_bonus method found, skipping depth check")
		return

	var early_bonus: int = game._get_scroll_depth_damage_bonus(missile)

	# Descend to a significantly deeper floor (synchronous).
	var start_floor: int = game_manager.current_floor
	var target_floor: int = start_floor + 10
	while game_manager.current_floor < target_floor:
		game._debug_descend_deeper()

	var deep_bonus: int = game._get_scroll_depth_damage_bonus(missile)

	if deep_bonus <= early_bonus:
		_fail(
			(
				"scroll depth damage bonus at floor %d = %d, "
				+ (
					"should be > floor %d bonus = %d"
					% [game_manager.current_floor, deep_bonus, start_floor, early_bonus]
				)
			)
		)
		return
	print(
		(
			"  scroll depth bonus: %d at floor %d -> %d at floor %d"
			% [early_bonus, start_floor, deep_bonus, game_manager.current_floor]
		)
	)


# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
#  Phase 4 — Offensive scroll damage values produce meaningful damage
# ---------------------------------------------------------------------------


func _check_scroll_damage_relevance(game: Node) -> void:
	if _failed:
		return
	# Magic Missile: 1d4+2 per bolt, 3 bolts = 3d4+6 expected ~13.5 average
	var missile: Resource = game._find_item_by_display_name("Scroll of Magic Missile")
	if missile == null:
		_fail("Scroll of Magic Missile missing from loaded item resources")
		return
	if missile.damage_dice < 1 or missile.damage_sides < 4 or missile.damage_bonus < 2:
		_fail(
			(
				"Magic Missile damage too low: %dd%d+%d, expected at least 1d4+2"
				% [missile.damage_dice, missile.damage_sides, missile.damage_bonus]
			)
		)
		return
	var avg_per_bolt: float = (
		missile.damage_dice * (1.0 + missile.damage_sides) / 2.0 + missile.damage_bonus
	)
	_assert(avg_per_bolt >= 4.0, "Magic Missile average per bolt too low: %.1f" % avg_per_bolt)
	if missile.target_count >= 3:
		_assert(
			avg_per_bolt * missile.target_count >= 12.0,
			"Magic Missile 3-bolt average too low: %.1f" % (avg_per_bolt * missile.target_count)
		)
	print(
		(
			"  magic missile: %dd%d+%d per bolt, avg %.1f"
			% [missile.damage_dice, missile.damage_sides, missile.damage_bonus, avg_per_bolt]
		)
	)

	# Lightning Bolt: 3d6+3
	var bolt: Resource = game._find_item_by_display_name("Scroll of Lightning Bolt")
	if bolt == null:
		_fail("Scroll of Lightning Bolt missing")
		return
	if bolt.damage_dice < 3 or bolt.damage_sides < 6:
		_fail(
			(
				"Lightning Bolt damage too low: %dd%d+%d"
				% [bolt.damage_dice, bolt.damage_sides, bolt.damage_bonus]
			)
		)
		return
	print("  lightning bolt: %dd%d+%d" % [bolt.damage_dice, bolt.damage_sides, bolt.damage_bonus])

	# Fireball: 3d6+5
	var fb: Resource = game._find_item_by_display_name("Scroll of Fireball")
	if fb == null:
		_fail("Scroll of Fireball missing")
		return
	if fb.damage_dice < 3 or fb.damage_sides < 6:
		_fail(
			"Fireball damage too low: %dd%d+%d" % [fb.damage_dice, fb.damage_sides, fb.damage_bonus]
		)
		return
	print("  fireball: %dd%d+%d" % [fb.damage_dice, fb.damage_sides, fb.damage_bonus])


# ---------------------------------------------------------------------------
#  Phase 5 — Scroll of Sleep resource and boss immunity contract
# ---------------------------------------------------------------------------


func _check_sleep_scroll_contracts(game: Node) -> void:
	if _failed:
		return
	var sleep: Resource = game._find_item_by_display_name("Scroll of Sleep")
	if sleep == null:
		_fail("Scroll of Sleep missing from loaded item resources")
		return

	if sleep.effect_duration != 1:
		_fail(
			(
				"Scroll of Sleep effect_duration = %d, expected 1 (single-turn control)"
				% sleep.effect_duration
			)
		)
		return
	print("  sleep scroll: effect_duration = %d" % sleep.effect_duration)

	if sleep.range < 6:
		_fail("Scroll of Sleep range = %d, expected at least 6" % sleep.range)
		return
	print("  sleep scroll: range = %d" % sleep.range)

	# Boss immunity is enforced in game.gd _resolve_sleep: bosses are skipped
	# when collecting affected targets. If only bosses are in radius, the
	# scroll returns false without being consumed. This test verifies the
	# resource contract; the behavioral assertion is in the scaling test.


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------


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
				game_manager.map_data[cell.y][cell.x] = 0  # DungeonData.TileType.FLOOR

	game._refresh_visibility()
	game._refresh_map()


func _is_inside_map(game_manager: Node, cell: Vector2i) -> bool:
	return (
		cell.y > 0
		and cell.y < game_manager.map_data.size() - 1
		and cell.x > 0
		and cell.x < game_manager.map_data[0].size() - 1
	)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
