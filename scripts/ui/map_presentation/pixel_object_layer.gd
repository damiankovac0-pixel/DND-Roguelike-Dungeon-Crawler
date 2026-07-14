class_name PixelObjectLayer
extends Node2D
## Draws state-derived items, containers, props, and known traps below actors.
##
## The layer consumes semantic snapshots only. It never reads gameplay resources
## or decides whether an object exists, is revealed, or blocks movement.

# === Constants ===
const ITEM_FILL_ALPHA: float = 0.12
const ITEM_BORDER_ALPHA: float = 0.58
const PROP_FILL_ALPHA: float = 0.10
const PROP_BORDER_ALPHA: float = 0.48
const TRAP_FILL_ALPHA: float = 0.14
const TRAP_BORDER_ALPHA: float = 0.62

# === Private Variables ===
var _layout: RefCounted
var _catalog: Resource
var _atlas: Texture2D
var _state: RefCounted
var _objects: Array[Dictionary] = []
var _last_overlay_revision: int = -1
var _last_visibility_revision: int = -1
var _last_actor_revision: int = -1
var _item_count: int = 0
var _container_count: int = 0
var _trap_count: int = 0


# === Public Methods ===
func configure(layout: RefCounted, catalog: Resource) -> Error:
	_layout = layout
	_catalog = catalog
	if _layout == null or _catalog == null:
		return ERR_FILE_NOT_FOUND
	if not _catalog.has_method(&"validate") or not _catalog.has_method(&"get_atlas"):
		return ERR_INVALID_DATA
	var validation_error: String = str(_catalog.call(&"validate"))
	if not validation_error.is_empty():
		push_warning(validation_error)
		return ERR_FILE_NOT_FOUND
	_atlas = _catalog.call(&"get_atlas")
	if _atlas == null:
		return ERR_FILE_NOT_FOUND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return OK


func present(state: RefCounted, force_rebuild: bool = false) -> void:
	_state = state
	if _state == null:
		_objects.clear()
		_reset_counts()
		queue_redraw()
		return
	var overlay_revision: int = int(_state.get("overlay_revision"))
	var visibility_revision: int = int(_state.get("visibility_revision"))
	var actor_revision: int = int(_state.get("actor_revision"))
	if (
		force_rebuild
		or overlay_revision != _last_overlay_revision
		or visibility_revision != _last_visibility_revision
		or actor_revision != _last_actor_revision
	):
		_rebuild_objects()
		queue_redraw()
	_last_overlay_revision = overlay_revision
	_last_visibility_revision = visibility_revision
	_last_actor_revision = actor_revision


func clear() -> void:
	_state = null
	_objects.clear()
	_reset_counts()
	_last_overlay_revision = -1
	_last_visibility_revision = -1
	_last_actor_revision = -1
	queue_redraw()


func get_debug_snapshot() -> Dictionary:
	return {
		"object_count": _objects.size(),
		"item_count": _item_count,
		"container_count": _container_count,
		"trap_count": _trap_count,
		"overlay_revision": _last_overlay_revision,
		"visibility_revision": _last_visibility_revision,
		"actor_revision": _last_actor_revision,
	}


# === Lifecycle Methods ===
func _draw() -> void:
	if _layout == null or _catalog == null or _atlas == null:
		return
	for object: Dictionary in _objects:
		var cell: Vector2i = object.get("cell", Vector2i.ZERO)
		var cell_rect: Rect2 = _layout.call(&"cell_rect", cell, 0.0)
		var color: Color = object.get("color", Color.WHITE)
		var category: StringName = object.get("category", &"")
		_draw_highlight(cell_rect.grow(-1.0), color, category, bool(object.get("marked", false)))
		var visual_id: StringName = object.get("visual_id", &"prop/generic")
		var source_rect: Rect2 = _catalog.call(&"region_for", visual_id)
		var texture_color: Color = color
		texture_color.a = 1.0
		if bool(object.get("triggered", false)):
			texture_color = Color(0.45, 0.45, 0.48, 1.0)
		draw_texture_rect_region(_atlas, cell_rect, source_rect, texture_color)


# === Private Methods ===
func _rebuild_objects() -> void:
	_objects.clear()
	_reset_counts()
	if _state == null or _layout == null:
		return
	var visible_cells: Dictionary = _state.get("visible_cells")
	var explored_cells: Dictionary = _state.get("explored_cells")
	var occupied_cells: Dictionary = _occupied_actor_cells()
	_append_items(_state.get("items"), visible_cells, occupied_cells)
	_append_containers(_state.get("containers"), visible_cells, occupied_cells)
	_append_traps(_state.get("trap_data"), explored_cells, occupied_cells)


func _append_items(
	items: Dictionary, visible_cells: Dictionary, occupied_cells: Dictionary
) -> void:
	for cell_value: Variant in items:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not _cell_can_draw(cell) or not visible_cells.has(cell) or occupied_cells.has(cell):
			continue
		var payload_value: Variant = items[cell]
		if payload_value is not Dictionary:
			continue
		var payload: Dictionary = payload_value
		_objects.append(_object_entry(cell, payload, &"item"))
		_item_count += 1


func _append_containers(
	containers: Dictionary, visible_cells: Dictionary, occupied_cells: Dictionary
) -> void:
	for cell_value: Variant in containers:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not _cell_can_draw(cell) or not visible_cells.has(cell) or occupied_cells.has(cell):
			continue
		var payload_value: Variant = containers[cell]
		if payload_value is not Dictionary:
			continue
		var payload: Dictionary = payload_value
		_objects.append(_object_entry(cell, payload, &"container"))
		_container_count += 1


func _append_traps(
	traps: Dictionary, explored_cells: Dictionary, occupied_cells: Dictionary
) -> void:
	for cell_value: Variant in traps:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not _cell_can_draw(cell) or not explored_cells.has(cell) or occupied_cells.has(cell):
			continue
		var payload_value: Variant = traps[cell]
		if payload_value is not Dictionary:
			continue
		var payload: Dictionary = payload_value
		if not bool(payload.get("revealed", false)) and not bool(payload.get("triggered", false)):
			continue
		_objects.append(_object_entry(cell, payload, &"trap"))
		_trap_count += 1


func _object_entry(cell: Vector2i, payload: Dictionary, category: StringName) -> Dictionary:
	return {
		"cell": cell,
		"visual_id": payload.get("visual_id", &"prop/generic"),
		"color": payload.get("color", Color.WHITE),
		"category": category,
		"marked": bool(payload.get("marked", false)),
		"triggered": bool(payload.get("triggered", false)),
	}


func _occupied_actor_cells() -> Dictionary:
	var occupied_cells: Dictionary = {}
	for snapshot_value: Variant in _state.get("actors"):
		if snapshot_value is not Dictionary:
			continue
		var snapshot: Dictionary = snapshot_value
		if not bool(snapshot.get("alive", false)):
			continue
		var cell_value: Variant = snapshot.get("cell")
		if cell_value is Vector2i:
			occupied_cells[cell_value] = true
	for visual_value: Variant in _state.get("boss_visuals").values():
		if visual_value is not Dictionary:
			continue
		for cell_value: Variant in visual_value.get("occupied_cells", []):
			if cell_value is Vector2i:
				occupied_cells[cell_value] = true
	return occupied_cells


func _cell_can_draw(cell: Vector2i) -> bool:
	return bool(_layout.call(&"is_cell_in_view", cell))


func _draw_highlight(rect: Rect2, color: Color, category: StringName, marked: bool) -> void:
	var fill_alpha: float = PROP_FILL_ALPHA
	var border_alpha: float = PROP_BORDER_ALPHA
	if category == &"item":
		fill_alpha = ITEM_FILL_ALPHA
		border_alpha = ITEM_BORDER_ALPHA
	elif category == &"trap":
		fill_alpha = TRAP_FILL_ALPHA
		border_alpha = TRAP_BORDER_ALPHA
	draw_rect(rect, Color(color.r, color.g, color.b, fill_alpha))
	draw_rect(rect, Color(color.r, color.g, color.b, border_alpha), false, 1.0)
	if marked:
		draw_rect(rect.grow(-2.0), Color(1.0, 0.88, 0.42, 0.92), false, 1.0)


func _reset_counts() -> void:
	_item_count = 0
	_container_count = 0
	_trap_count = 0
