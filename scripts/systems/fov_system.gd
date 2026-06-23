class_name FOVSystem
extends RefCounted

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")


# === Public Methods ===
static func calculate_visible_cells(origin: Vector2i, radius: int, map_data: Array) -> Dictionary:
	var visible_cells: Dictionary = {}
	for y: int in range(origin.y - radius, origin.y + radius + 1):
		for x: int in range(origin.x - radius, origin.x + radius + 1):
			var target: Vector2i = Vector2i(x, y)
			if origin.distance_to(target) > radius:
				continue
			if _has_line_of_sight(origin, target, map_data):
				visible_cells[target] = true
	return visible_cells


# === Private Methods ===
static func _has_line_of_sight(start: Vector2i, goal: Vector2i, map_data: Array) -> bool:
	var line: Array[Vector2i] = _bresenham_line(start, goal)
	for point: Vector2i in line:
		if point == start:
			continue
		if point.y < 0 or point.y >= map_data.size():
			return false
		if point.x < 0 or point.x >= map_data[0].size():
			return false
		if DungeonDataScript.is_opaque(map_data[point.y][point.x]) and point != goal:
			return false
	return true


static func _bresenham_line(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0: int = start.x
	var y0: int = start.y
	var x1: int = goal.x
	var y1: int = goal.y
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var error: int = dx + dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var twice_error: int = error * 2
		if twice_error >= dy:
			error += dy
			x0 += sx
		if twice_error <= dx:
			error += dx
			y0 += sy
	return points
