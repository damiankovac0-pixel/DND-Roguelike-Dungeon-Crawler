class_name MapGridLayout
extends RefCounted
## Renderer-local conversion between authoritative grid cells and local pixels.
##
## This layout never reads Actor.position or DungeonData.CELL_SIZE. Renderers
## choose their own cell size while consuming the same Vector2i game cells.

# === Private Variables ===
var _cell_size: Vector2i = Vector2i.ONE
var _origin: Vector2 = Vector2.ZERO
var _view_capacity: Vector2i = Vector2i.ONE
var _map_size: Vector2i = Vector2i.ZERO
var _focus_cell: Vector2i = Vector2i.ZERO
var _view_origin_cell: Vector2i = Vector2i.ZERO


# === Public Methods ===
func configure(cell_size: Vector2i, origin: Vector2, view_capacity: Vector2i) -> void:
	_cell_size = Vector2i(maxi(1, cell_size.x), maxi(1, cell_size.y))
	_origin = origin
	_view_capacity = Vector2i(maxi(1, view_capacity.x), maxi(1, view_capacity.y))
	_recalculate_view_origin()


func set_map_size(map_size: Vector2i) -> bool:
	var previous_origin: Vector2i = _view_origin_cell
	_map_size = Vector2i(maxi(0, map_size.x), maxi(0, map_size.y))
	_recalculate_view_origin()
	return previous_origin != _view_origin_cell


func set_focus_cell(focus_cell: Vector2i) -> bool:
	var previous_origin: Vector2i = _view_origin_cell
	_focus_cell = focus_cell
	_recalculate_view_origin()
	return previous_origin != _view_origin_cell


func get_cell_size() -> Vector2i:
	return _cell_size


func get_origin() -> Vector2:
	return _origin


func get_map_size() -> Vector2i:
	return _map_size


func get_view_capacity() -> Vector2i:
	return _view_capacity


func get_view_origin_cell() -> Vector2i:
	return _view_origin_cell


func get_view_rect() -> Rect2i:
	var visible_size: Vector2i = Vector2i(
		mini(_view_capacity.x, _map_size.x), mini(_view_capacity.y, _map_size.y)
	)
	return Rect2i(_view_origin_cell, visible_size)


func get_view_offset_pixels() -> Vector2:
	return -Vector2(_view_origin_cell.x * _cell_size.x, _view_origin_cell.y * _cell_size.y)


func cell_to_local(cell: Vector2i) -> Vector2:
	return (
		_origin + get_view_offset_pixels() + Vector2(cell.x * _cell_size.x, cell.y * _cell_size.y)
	)


func cell_center_to_local(cell: Vector2i) -> Vector2:
	return cell_to_local(cell) + Vector2(_cell_size) * 0.5


func cell_rect(cell: Vector2i, inset: float = 0.0) -> Rect2:
	var inset_vector: Vector2 = Vector2(inset, inset)
	var size: Vector2 = Vector2(_cell_size) - inset_vector * 2.0
	return Rect2(cell_to_local(cell) + inset_vector, size.max(Vector2.ZERO))


func local_to_cell(local_position: Vector2) -> Vector2i:
	var relative: Vector2 = local_position - _origin - get_view_offset_pixels()
	return Vector2i(
		int(floor(relative.x / float(_cell_size.x))), int(floor(relative.y / float(_cell_size.y)))
	)


func is_cell_in_view(cell: Vector2i) -> bool:
	return get_view_rect().has_point(cell)


# === Private Methods ===
func _recalculate_view_origin() -> void:
	if _map_size == Vector2i.ZERO:
		_view_origin_cell = Vector2i.ZERO
		return
	var maximum_origin: Vector2i = Vector2i(
		maxi(0, _map_size.x - _view_capacity.x), maxi(0, _map_size.y - _view_capacity.y)
	)
	var desired_origin: Vector2i = _focus_cell - _view_capacity / 2
	_view_origin_cell = Vector2i(
		clampi(desired_origin.x, 0, maximum_origin.x), clampi(desired_origin.y, 0, maximum_origin.y)
	)
