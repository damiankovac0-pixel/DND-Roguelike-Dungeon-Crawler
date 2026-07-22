## Static trap detection, triggering, and effect resolution (damage, poison, teleport, alarm).
class_name TrapSystem
extends RefCounted

const TrapDataScript = preload("res://scripts/resources/trap_data.gd")
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")


static func _d20_roll() -> int:
	return randi_range(1, 20)


static func detect_traps_around(
	pos: Vector2i,
	trap_data: Dictionary,
	revealed_traps: Dictionary,
	triggered_traps: Dictionary,
	perception_bonus: int,
	log_callback: Callable,
) -> void:
	var neighbors: Array[Vector2i] = [
		pos + Vector2i.UP,
		pos + Vector2i.DOWN,
		pos + Vector2i.LEFT,
		pos + Vector2i.RIGHT,
	]
	for neighbor: Vector2i in neighbors:
		if not trap_data.has(neighbor):
			continue
		if revealed_traps.has(neighbor) or triggered_traps.has(neighbor):
			continue
		var trap: Resource = trap_data[neighbor]
		if _d20_roll() + perception_bonus >= trap.detect_dc:
			revealed_traps[neighbor] = true
			log_callback.call(
				"You spot a %s nearby (%s). Step around it." % [trap.display_name, trap.glyph],
				&"warning"
			)


static func search_for_traps(
	player_pos: Vector2i,
	trap_data: Dictionary,
	revealed_traps: Dictionary,
	triggered_traps: Dictionary,
	visible_cells: Dictionary,
	perception_bonus: int,
) -> int:
	var found: int = 0
	for trap_cell: Vector2i in trap_data.keys():
		if revealed_traps.has(trap_cell) or triggered_traps.has(trap_cell):
			continue
		if trap_cell.distance_to(player_pos) > 3:
			continue
		if not visible_cells.has(trap_cell):
			continue
		var trap: Resource = trap_data[trap_cell]
		if _d20_roll() + perception_bonus >= trap.detect_dc:
			revealed_traps[trap_cell] = true
			found += 1
	return found


static func trigger_trap(
	trap_cell: Vector2i,
	trap_data: Dictionary,
	triggered_traps: Dictionary,
	player: Node2D,
	enemies: Array,
	map_data: Array,
	log_callback: Callable,
	refresh_callback: Callable,
	game_over_callback: Callable,
	special_callback: Callable,
	actor_blockers: Dictionary = {},
	damage_callback: Callable = Callable(),
) -> bool:
	if not trap_data.has(trap_cell):
		return true
	var trap: Resource = trap_data[trap_cell]
	triggered_traps[trap_cell] = true
	var stats: Node = player.stats_component
	match trap.effect:
		TrapDataScript.TrapEffect.DAMAGE, TrapDataScript.TrapEffect.POTSON:
			var damage: int = randi_range(trap.min_damage, trap.max_damage)
			damage = stats.apply_damage(damage)
			if damage_callback.is_valid():
				damage_callback.call(damage, str(trap.display_name), &"trap")
			if trap.effect == TrapDataScript.TrapEffect.DAMAGE:
				log_callback.call(
					"%s stabs you for %d damage!" % [trap.display_name, damage], &"damage"
				)
			else:
				log_callback.call(
					"A poison dart hits you for %d damage! The wound stings." % damage, &"damage"
				)
		TrapDataScript.TrapEffect.TELEPORT:
			var safe_cells: Array[Vector2i] = _get_safe_teleport_cells(
				trap_cell, trap_data, player, enemies, map_data, actor_blockers
			)
			if safe_cells.is_empty():
				log_callback.call(
					"The teleport trap fizzles — every destination is blocked.", &"neutral"
				)
			else:
				player.set_grid_position(safe_cells[randi_range(0, safe_cells.size() - 1)])
				log_callback.call("A shimmering glyph teleports you across the dungeon!", &"magic")
		TrapDataScript.TrapEffect.ALARM:
			var alerted: int = 0
			for enemy in enemies:
				if (
					enemy != null
					and enemy.is_alive()
					and enemy.grid_position.distance_to(player.grid_position) <= 15.0
				):
					alerted += 1
			log_callback.call(
				(
					"An alarm trap shrieks! %s"
					% ["Nearby enemies take notice." if alerted > 0 else "Nothing stirs."]
				),
				&"warning"
			)
		TrapDataScript.TrapEffect.STUN, TrapDataScript.TrapEffect.AMBUSH:
			special_callback.call(trap, trap_cell)
	var player_survived: bool = player.is_alive()
	if not player_survived:
		game_over_callback.call(false)
	else:
		refresh_callback.call()
	return player_survived


static func _get_safe_teleport_cells(
	trap_cell: Vector2i,
	trap_data: Dictionary,
	player: Node2D,
	enemies: Array,
	map_data: Array,
	actor_blockers: Dictionary
) -> Array[Vector2i]:
	var safe_cells: Array[Vector2i] = []
	if map_data.is_empty():
		return safe_cells
	var map_height: int = map_data.size()
	var map_width: int = map_data[0].size()
	var current_cell: Vector2i = player.grid_position
	for y: int in range(map_height):
		for x: int in range(map_width):
			var cell: Vector2i = Vector2i(x, y)
			if cell == current_cell or cell == trap_cell:
				continue
			if trap_data.has(cell):
				continue
			if actor_blockers.has(cell):
				continue
			if _is_living_enemy_at(cell, enemies):
				continue
			if not DungeonDataScript.is_walkable(map_data[cell.y][cell.x]):
				continue
			safe_cells.append(cell)
	return safe_cells


static func _is_living_enemy_at(cell: Vector2i, enemies: Array) -> bool:
	for enemy in enemies:
		if enemy == null or not enemy.is_alive():
			continue
		if enemy.grid_position == cell:
			return true
		var enemy_data: Resource = enemy.get("enemy_data") as Resource
		if enemy_data != null:
			var footprint_offsets: Array = enemy_data.get("boss_footprint_offsets")
			for offset: Vector2i in footprint_offsets:
				if enemy.grid_position + offset == cell:
					return true
	return false
