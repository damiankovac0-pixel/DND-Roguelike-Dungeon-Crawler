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
) -> void:
	if not trap_data.has(trap_cell):
		return
	var trap: Resource = trap_data[trap_cell]
	triggered_traps[trap_cell] = true
	var stats: Node = player.stats_component
	match trap.effect:
		TrapDataScript.TrapEffect.DAMAGE, TrapDataScript.TrapEffect.POTSON:
			var damage: int = randi_range(trap.min_damage, trap.max_damage)
			stats.apply_damage(damage)
			if trap.effect == TrapDataScript.TrapEffect.DAMAGE:
				log_callback.call(
					"%s stabs you for %d damage!" % [trap.display_name, damage], &"damage"
				)
			else:
				log_callback.call(
					"A poison dart hits you for %d damage! The wound stings." % damage, &"damage"
				)
		TrapDataScript.TrapEffect.TELEPORT:
			var safe_cells: Array[Vector2i] = []
			for tc: Vector2i in trap_data.keys():
				if tc.distance_to(player.grid_position) > 5:
					safe_cells.append(tc)
			if safe_cells.is_empty() and not map_data.is_empty():
				var map_height: int = map_data.size()
				var map_width: int = map_data[0].size()
				for y: int in range(map_height):
					for x: int in range(map_width):
						var cell: Vector2i = Vector2i(x, y)
						if (
							player.grid_position != cell
							and DungeonDataScript.is_walkable(map_data[cell.y][cell.x])
						):
							safe_cells.append(cell)
			if safe_cells.is_empty():
				log_callback.call("The teleport trap fizzles — destination blocked.", &"neutral")
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
	if not player.is_alive():
		game_over_callback.call(false)
	else:
		refresh_callback.call()
