## BFS next-step pathfinding for enemy AI toward a goal cell.
class_name Pathfinding
extends RefCounted

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")


# === Public Methods ===
static func find_next_step(
	start: Vector2i, goal: Vector2i, map_data: Array, blocked_cells: Dictionary
) -> Vector2i:
	if start == goal:
		return start

	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			break
		for direction: Vector2i in directions:
			var next: Vector2i = current + direction
			if came_from.has(next):
				continue
			if not _is_walkable(next, map_data):
				continue
			if blocked_cells.has(next) and next != goal:
				continue
			came_from[next] = current
			frontier.append(next)

	if not came_from.has(goal):
		return start

	var current_step: Vector2i = goal
	while came_from[current_step] != start:
		current_step = came_from[current_step]
	return current_step


# === Private Methods ===
static func _is_walkable(cell: Vector2i, map_data: Array) -> bool:
	if cell.y < 0 or cell.y >= map_data.size():
		return false
	if cell.x < 0 or cell.x >= map_data[0].size():
		return false
	return DungeonDataScript.is_walkable(map_data[cell.y][cell.x])
