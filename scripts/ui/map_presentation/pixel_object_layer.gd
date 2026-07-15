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
const BOB_AMPLITUDE: int = 1
const BOB_SPEED: float = 3.0
const ENCHANTMENT_PULSE_SPEED: float = 2.5
const ENCHANTMENT_OVERLAY_ALPHA: float = 0.28
const RARE_RARITY_THRESHOLD: int = 2
const ENCHANTMENT_RARITY_COLORS: Array[Color] = [
	Color("#8fb3ff"),
	Color("#d78fff"),
	Color("#ffb84d"),
	Color("#ff5fd7"),
	Color("#66fff0"),
]

# === Private Variables ===
var _layout: RefCounted
var _catalog: Resource
var _atlas: Texture2D
var _enchantment_overlay: Texture2D
var _state: RefCounted
var _objects: Array[Dictionary] = []
var _last_overlay_revision: int = -1
var _last_visibility_revision: int = -1
var _last_actor_revision: int = -1
var _item_count: int = 0
var _container_count: int = 0
var _trap_count: int = 0
var _reduced_vfx_enabled: bool = false
var _animation_time: float = 0.0
var _bob_item_count: int = 0
var _enchantment_overlay_count: int = 0


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
	_atlas = _catalog.call(&"get_atlas") as Texture2D
	_enchantment_overlay = _catalog.call(&"get_enchantment_overlay") as Texture2D
	if _atlas == null or _enchantment_overlay == null:
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
		_update_processing_state()
		queue_redraw()
	_last_overlay_revision = overlay_revision
	_last_visibility_revision = visibility_revision
	_last_actor_revision = actor_revision


func clear() -> void:
	_state = null
	_objects.clear()
	_reset_counts()
	_bob_item_count = 0
	_enchantment_overlay_count = 0
	_animation_time = 0.0
	_update_processing_state()
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
		"bob_item_count": _bob_item_count,
		"enchantment_overlay_count": _enchantment_overlay_count,
		"reduced_vfx_enabled": _reduced_vfx_enabled,
		"animation_active": is_processing(),
		"overlay_revision": _last_overlay_revision,
		"visibility_revision": _last_visibility_revision,
		"actor_revision": _last_actor_revision,
	}


func _draw() -> void:
	if _layout == null or _catalog == null or _atlas == null:
		return
	for object: Dictionary in _objects:
		var cell: Vector2i = object.get("cell", Vector2i.ZERO)
		var cell_rect: Rect2 = _layout.call(&"cell_rect", cell, 0.0)
		var color: Color = object.get("color", Color.WHITE)
		var category: StringName = object.get("category", &"")
		_draw_highlight(cell_rect.grow(-1.0), color, category, bool(object.get("marked", false)))
		# Apply item bob for visible dropped items
		var display_rect: Rect2 = cell_rect
		if not _reduced_vfx_enabled and bool(object.get("can_bob", false)):
			display_rect = Rect2(cell_rect.position + _item_bob_offset(cell), cell_rect.size)
		var visual_id: StringName = object.get("visual_id", &"prop/generic")
		var source_rect: Rect2 = _catalog.call(&"region_for", visual_id)
		var texture_color: Color = (
			Color.WHITE if bool(_catalog.call(&"has_visual", visual_id)) else color
		)
		if bool(object.get("triggered", false)):
			texture_color = Color(0.45, 0.45, 0.48, 1.0)
		draw_texture_rect_region(_atlas, display_rect, source_rect, texture_color)
		# Draw enchantment overlay for rare non-consumable items
		if bool(object.get("has_enchantment", false)):
			_draw_enchantment_overlay(display_rect, cell, object)


func _rebuild_objects() -> void:
	_objects.clear()
	_reset_counts()
	_bob_item_count = 0
	_enchantment_overlay_count = 0
	if _state == null or _layout == null:
		return
	var visible_cells: Dictionary = _state.get("visible_cells")
	var explored_cells: Dictionary = _state.get("explored_cells")
	var occupied_cells: Dictionary = _occupied_actor_cells()
	_append_items(_state.get("items"), visible_cells, occupied_cells)
	_append_containers(_state.get("containers"), visible_cells, occupied_cells)
	_append_traps(_state.get("trap_data"), explored_cells, occupied_cells)
	_update_processing_state()


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
		var entry: Dictionary = _object_entry(cell, payload, &"item")
		if bool(entry.get("can_bob", false)):
			_bob_item_count += 1
		if bool(entry.get("has_enchantment", false)):
			_enchantment_overlay_count += 1
		_objects.append(entry)
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
	var visual_id: StringName = payload.get("visual_id", &"prop/generic")
	var rarity: int = int(payload.get("rarity", 0))
	var is_item: bool = category == &"item"
	var can_bob: bool = is_item
	var has_enchantment: bool = (
		is_item and rarity >= RARE_RARITY_THRESHOLD and not _is_consumable_visual(visual_id)
	)
	return {
		"cell": cell,
		"visual_id": visual_id,
		"color": payload.get("color", Color.WHITE),
		"category": category,
		"marked": bool(payload.get("marked", false)),
		"triggered": bool(payload.get("triggered", false)),
		"rarity": rarity,
		"can_bob": can_bob,
		"has_enchantment": has_enchantment,
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


func set_reduced_vfx(enabled: bool) -> void:
	if _reduced_vfx_enabled == enabled:
		return
	_reduced_vfx_enabled = enabled
	if enabled:
		_animation_time = 0.0
	_update_processing_state()
	queue_redraw()


func _process(delta: float) -> void:
	_animation_time += delta
	queue_redraw()


func _update_processing_state() -> void:
	if _reduced_vfx_enabled:
		set_process(false)
		return
	set_process(_bob_item_count > 0 or _enchantment_overlay_count > 0)


func _item_bob_offset(cell: Vector2i) -> Vector2:
	var phase: float = (
		_animation_time * BOB_SPEED + float(_object_cell_hash(cell, 41) % 100) * 0.0628
	)
	var offset: float = roundf(sin(phase * TAU) * BOB_AMPLITUDE)
	return Vector2(0.0, offset)


func _draw_enchantment_overlay(display_rect: Rect2, cell: Vector2i, payload: Dictionary) -> void:
	if _enchantment_overlay == null:
		return
	var alpha: float = ENCHANTMENT_OVERLAY_ALPHA
	if not _reduced_vfx_enabled:
		var pulse: float = sin(
			(
				_animation_time * ENCHANTMENT_PULSE_SPEED
				+ float(_object_cell_hash(cell, 53) % 100) * 0.1
			)
		)
		alpha *= 0.6 + 0.4 * (pulse * 0.5 + 0.5)
	else:
		alpha *= 0.5
	var tint: Color = enchantment_color_for(int(payload.get("rarity", RARE_RARITY_THRESHOLD)))
	tint.a = alpha
	draw_texture_rect(_enchantment_overlay, display_rect, false, tint)


static func enchantment_color_for(rarity: int) -> Color:
	var color_index: int = clampi(
		rarity - RARE_RARITY_THRESHOLD,
		0,
		ENCHANTMENT_RARITY_COLORS.size() - 1,
	)
	return ENCHANTMENT_RARITY_COLORS[color_index]


static func _is_consumable_visual(visual_id: StringName) -> bool:
	var id_str: String = String(visual_id)
	return id_str.find("potion") >= 0 or id_str.find("scroll") >= 0 or id_str.find("elixir") >= 0


static func _object_cell_hash(cell: Vector2i, salt: int) -> int:
	return absi(cell.x * 73856093 + cell.y * 19349663 + salt * 83492791)
