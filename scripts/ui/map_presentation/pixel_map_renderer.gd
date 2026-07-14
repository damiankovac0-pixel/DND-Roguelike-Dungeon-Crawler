class_name PixelMapRenderer
extends Node2D
## Pixel-map backend for terrain, objects, actors, fog, and tactical effects.
##
## Gameplay remains authoritative elsewhere. This renderer consumes only
## semantic MapPresentationState snapshots and renderer-local visual events.

# === Constants ===
const TILE_SOURCE_ID: int = 0
const FLOOR_TILE_TYPE: int = 0
const ACTOR_VIEW_SCENE: PackedScene = preload("res://scenes/rendering/pixel_actor_view.tscn")

# === Exports ===
@export var catalog: Resource
@export var actor_catalog: Resource
@export var object_catalog: Resource

# === Private Variables ===
var _layout: RefCounted
var _state: RefCounted
var _available: bool = false
var _render_profile: StringName = &"hybrid"
var _reduced_vfx_enabled: bool = false
var _last_map_revision: int = -1
var _last_visibility_revision: int = -1
var _last_actor_revision: int = -1
var _last_overlay_revision: int = -1
var _last_environment_revision: int = -1
var _transient_reset_count: int = 0
var _actor_views: Dictionary = {}
var _retired_actor_ids: Dictionary = {}
var _actor_event_count: int = 0
var _playfield_rect: Rect2 = Rect2(Vector2(10, 10), Vector2(680, 590))
var _outer_background_color: Color = Color(0.0, 0.02, 0.035)
var _border_color: Color = Color(0.047, 0.059, 0.082)
var _border_frame_color: Color = Color(0.282, 0.259, 0.392)
var _background_color: Color = Color(0.025, 0.032, 0.047)

# === Onready ===
@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var structure_layer: TileMapLayer = $StructureLayer
@onready var object_layer: PixelObjectLayer = $ObjectLayer
@onready var actor_layer: Node2D = $ActorLayer
@onready var fog_layer: PixelFogLayer = $FogLayer
@onready var tactical_layer: PixelTacticalLayer = $TacticalLayer


# === Lifecycle Methods ===
func _ready() -> void:
	visible = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport_size), _outer_background_color)
	draw_rect(_playfield_rect.grow(6.0), _border_color)
	draw_rect(_playfield_rect.grow(2.0), _border_frame_color)
	draw_rect(_playfield_rect, _background_color)


# === Public Methods ===
func configure_style(
	playfield_rect: Rect2,
	outer_background_color: Color,
	map_border_color: Color,
	map_border_frame_color: Color,
	map_background_color: Color
) -> void:
	_playfield_rect = playfield_rect
	_outer_background_color = outer_background_color
	_border_color = map_border_color
	_border_frame_color = map_border_frame_color
	_background_color = map_background_color
	queue_redraw()


func initialize_renderer(layout: RefCounted) -> Error:
	_layout = layout
	var catalog_error: Error = _validate_catalogs()
	if catalog_error != OK:
		return catalog_error
	var tile_set_value: Variant = catalog.call(&"create_tile_set")
	if not (tile_set_value is TileSet):
		return ERR_CANT_CREATE
	ground_layer.tile_set = tile_set_value
	structure_layer.tile_set = tile_set_value
	fog_layer.configure(_layout)
	var layer_error: Error = object_layer.configure(_layout, object_catalog)
	if layer_error == OK:
		layer_error = tactical_layer.configure(_layout)
	if layer_error != OK:
		return layer_error
	tactical_layer.set_render_profile(_render_profile)
	tactical_layer.set_reduced_vfx(_reduced_vfx_enabled)
	_available = actor_layer != null and ACTOR_VIEW_SCENE != null
	return OK if _available else ERR_FILE_NOT_FOUND


func is_renderer_available() -> bool:
	return _available and _layout != null and is_instance_valid(ground_layer)


func set_renderer_active(active: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func set_render_profile(profile: StringName) -> void:
	_render_profile = profile
	if is_instance_valid(tactical_layer):
		tactical_layer.set_render_profile(profile)


func present(state: RefCounted) -> void:
	if not is_renderer_available():
		return
	_state = state
	var view_changed: bool = bool(_layout.call(&"set_map_size", state.get("map_size")))
	view_changed = bool(_layout.call(&"set_focus_cell", state.get("focus_cell"))) or view_changed
	_update_layer_positions()
	var map_revision: int = int(state.get("map_revision"))
	var visibility_revision: int = int(state.get("visibility_revision"))
	var actor_revision: int = int(state.get("actor_revision"))
	var overlay_revision: int = int(state.get("overlay_revision"))
	var environment_revision: int = int(state.get("environment_revision"))
	if (
		view_changed
		or map_revision != _last_map_revision
		or visibility_revision != _last_visibility_revision
	):
		_rebuild_tiles()
	if (
		view_changed
		or actor_revision != _last_actor_revision
		or visibility_revision != _last_visibility_revision
		or overlay_revision != _last_overlay_revision
	):
		var animate_actor_moves: bool = not view_changed and actor_revision != _last_actor_revision
		_sync_actor_views(animate_actor_moves)
	object_layer.present(state, view_changed)
	fog_layer.present(state, view_changed)
	tactical_layer.present(state, view_changed)
	if environment_revision != _last_environment_revision:
		queue_redraw()
	_last_map_revision = map_revision
	_last_visibility_revision = visibility_revision
	_last_actor_revision = actor_revision
	_last_overlay_revision = overlay_revision
	_last_environment_revision = environment_revision


func set_reduced_vfx(enabled: bool) -> void:
	_reduced_vfx_enabled = enabled
	for view_value: Variant in _actor_views.values():
		if view_value is PixelActorView:
			(view_value as PixelActorView).set_reduced_vfx(enabled)
	tactical_layer.set_reduced_vfx(enabled)


func reset_transients() -> void:
	_transient_reset_count += 1
	for actor_id_value: Variant in _actor_views.keys():
		var actor_id: int = int(actor_id_value)
		var view: PixelActorView = _actor_views.get(actor_id)
		if view != null and view.reset_transients():
			_retired_actor_ids[actor_id] = true
			_remove_actor_view(actor_id)

	tactical_layer.reset_transients()


func shutdown_renderer() -> void:
	ground_layer.clear()
	structure_layer.clear()
	object_layer.clear()
	_clear_actor_views()
	_retired_actor_ids.clear()
	tactical_layer.clear()
	visible = false
	_state = null


func play_event(event: Dictionary) -> void:
	if event.get("type", &"") != &"actor_animation":
		tactical_layer.play_event(event)
		return
	var view: PixelActorView = _actor_view_for_event(event)
	if view == null:
		return
	var animation: StringName = event.get("animation", &"idle")
	view.play_cosmetic(animation)
	_actor_event_count += 1


func get_debug_snapshot() -> Dictionary:
	var view_origin: Vector2i = (
		_layout.call(&"get_view_origin_cell") if _layout != null else Vector2i.ZERO
	)
	var actor_debug: Dictionary = _actor_debug_snapshots()
	var player_debug: Dictionary = _player_debug_snapshot(actor_debug)
	var object_debug: Dictionary = object_layer.get_debug_snapshot()
	var tactical_debug: Dictionary = tactical_layer.get_debug_snapshot()
	return {
		"available": is_renderer_available(),
		"profile": _render_profile,
		"ground_cell_count": ground_layer.get_used_cells().size(),
		"structure_cell_count": structure_layer.get_used_cells().size(),
		"player_visible": bool(player_debug.get("visible", false)),
		"player_cell": player_debug.get("cell", Vector2i.ZERO),
		"player_position": player_debug.get("position", Vector2.ZERO),
		"view_origin": view_origin,
		"map_revision": _last_map_revision,
		"visibility_revision": _last_visibility_revision,
		"actor_revision": _last_actor_revision,
		"overlay_revision": _last_overlay_revision,
		"actor_count": _actor_views.size(),
		"visible_actor_count": _visible_actor_count(actor_debug),
		"boss_actor_count": _boss_actor_count(actor_debug),
		"retired_actor_count": _retired_actor_ids.size(),
		"actor_event_count": _actor_event_count,
		"actor_views": actor_debug,
		"objects": object_debug,
		"tactical": tactical_debug,
		"reduced_vfx": _reduced_vfx_enabled,
		"transient_reset_count": _transient_reset_count,
	}


# === Private Methods ===
func _validate_catalogs() -> Error:
	if catalog == null or not catalog.has_method(&"validate"):
		return ERR_FILE_NOT_FOUND
	var map_catalog_error: String = str(catalog.call(&"validate"))
	if not map_catalog_error.is_empty():
		push_warning(map_catalog_error)
		return ERR_FILE_NOT_FOUND
	if actor_catalog == null or not actor_catalog.has_method(&"validate"):
		return ERR_FILE_NOT_FOUND
	var actor_catalog_error: String = str(actor_catalog.call(&"validate"))
	if not actor_catalog_error.is_empty():
		push_warning(actor_catalog_error)
		return ERR_FILE_NOT_FOUND
	return OK


func _update_layer_positions() -> void:
	var layer_position: Vector2 = _layout.call(&"get_origin")
	layer_position += _layout.call(&"get_view_offset_pixels")
	ground_layer.position = layer_position.round()
	structure_layer.position = layer_position.round()


func _rebuild_tiles() -> void:
	ground_layer.clear()
	structure_layer.clear()
	var map_data: Array = _state.get("map_data")
	var explored_cells: Dictionary = _state.get("explored_cells")
	var view_rect: Rect2i = _layout.call(&"get_view_rect")
	var floor_coords: Vector2i = catalog.call(&"atlas_coords_for_tile", FLOOR_TILE_TYPE)
	for y: int in range(view_rect.position.y, view_rect.end.y):
		if y < 0 or y >= map_data.size():
			continue
		for x: int in range(view_rect.position.x, view_rect.end.x):
			if x < 0 or x >= map_data[y].size():
				continue
			var cell: Vector2i = Vector2i(x, y)
			if not explored_cells.has(cell):
				continue
			var tile_type: int = int(map_data[y][x])
			ground_layer.set_cell(cell, TILE_SOURCE_ID, floor_coords)
			if bool(catalog.call(&"is_structure_tile", tile_type)):
				var structure_coords: Vector2i = catalog.call(&"atlas_coords_for_tile", tile_type)
				structure_layer.set_cell(cell, TILE_SOURCE_ID, structure_coords)


func _sync_actor_views(animate_moves: bool) -> void:
	var actor_snapshots: Array = _state.get("actors")
	var visible_cells: Dictionary = _state.get("visible_cells")
	var active_actor_ids: Dictionary = {}
	for snapshot_value: Variant in actor_snapshots:
		if snapshot_value is not Dictionary:
			continue
		var snapshot: Dictionary = snapshot_value
		var actor_id: int = int(snapshot.get("id", 0))
		if actor_id <= 0:
			continue
		active_actor_ids[actor_id] = true
		var alive: bool = bool(snapshot.get("alive", false))
		var view: PixelActorView = _actor_views.get(actor_id)
		if not alive:
			_sync_dead_actor_view(actor_id, snapshot, view, visible_cells)
			continue
		if _retired_actor_ids.has(actor_id):
			_retired_actor_ids.erase(actor_id)
		if view != null and not bool(view.get_debug_snapshot().get("alive", false)):
			_remove_actor_view(actor_id)
			view = null
		if view == null:
			view = _create_actor_view(snapshot)
		if view == null:
			continue
		(
			view
			. apply_snapshot(
				snapshot,
				_footprint_for_actor(snapshot),
				visible_cells,
				animate_moves,
			)
		)
	for actor_id_value: Variant in _actor_views.keys():
		var actor_id: int = int(actor_id_value)
		if not active_actor_ids.has(actor_id):
			_remove_actor_view(actor_id)
	for actor_id_value: Variant in _retired_actor_ids.keys():
		if not active_actor_ids.has(actor_id_value):
			_retired_actor_ids.erase(actor_id_value)


func _create_actor_view(snapshot: Dictionary) -> PixelActorView:
	var view: PixelActorView = ACTOR_VIEW_SCENE.instantiate() as PixelActorView
	if view == null:
		return null
	actor_layer.add_child(view)
	var frames: SpriteFrames = actor_catalog.call(&"sprite_frames_for", snapshot)
	var tint: Color = actor_catalog.call(&"tint_for", snapshot)
	view.initialize_view(snapshot, frames, tint, _layout, _reduced_vfx_enabled)
	view.death_finished.connect(_on_actor_death_finished.bind(view))
	var actor_id: int = int(snapshot.get("id", 0))
	_actor_views[actor_id] = view
	return view


func _sync_dead_actor_view(
	actor_id: int, snapshot: Dictionary, view: PixelActorView, visible_cells: Dictionary
) -> void:
	if view == null:
		_retired_actor_ids[actor_id] = true
		return
	var footprint: Array[Vector2i] = _footprint_for_actor(snapshot)
	if bool(snapshot.get("is_boss", false)) and footprint.size() <= 1:
		var previous_footprint: Array[Vector2i] = _vector2i_array(
			view.get_debug_snapshot().get("footprint_cells", [])
		)
		if previous_footprint.size() > 1:
			footprint = previous_footprint
	view.apply_snapshot(snapshot, footprint, visible_cells, false)
	var dead_debug: Dictionary = view.get_debug_snapshot()
	if not bool(dead_debug.get("visible", false)) and dead_debug.get("animation") != &"death":
		_retired_actor_ids[actor_id] = true
		_remove_actor_view(actor_id)


func _footprint_for_actor(snapshot: Dictionary) -> Array[Vector2i]:
	var fallback: Array[Vector2i] = _vector2i_array(snapshot.get("occupied_cells", []))
	if fallback.is_empty():
		fallback.append(snapshot.get("cell", Vector2i.ZERO))
	if not bool(snapshot.get("is_boss", false)):
		return fallback
	var boss_visuals: Dictionary = _state.get("boss_visuals")
	var anchor_cell: Vector2i = snapshot.get("cell", Vector2i.ZERO)
	if boss_visuals.has(anchor_cell):
		var direct_payload: Dictionary = boss_visuals.get(anchor_cell, {})
		var direct_cells: Array[Vector2i] = _vector2i_array(
			direct_payload.get("occupied_cells", [])
		)
		if not direct_cells.is_empty():
			return direct_cells
	for previous_anchor_value: Variant in boss_visuals.keys():
		if previous_anchor_value is not Vector2i:
			continue
		var payload: Dictionary = boss_visuals.get(previous_anchor_value, {})
		var previous_cells: Array[Vector2i] = _vector2i_array(payload.get("occupied_cells", []))
		if previous_cells.is_empty():
			continue
		var translated_cells: Array[Vector2i] = []
		var offset: Vector2i = anchor_cell - Vector2i(previous_anchor_value)
		for cell: Vector2i in previous_cells:
			translated_cells.append(cell + offset)
		return translated_cells
	return fallback


func _vector2i_array(value: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if value is not Array:
		return cells
	for cell_value: Variant in value:
		if cell_value is Vector2i:
			cells.append(cell_value)
	return cells


func _actor_view_for_event(event: Dictionary) -> PixelActorView:
	var actor_id: int = int(event.get("actor_id", 0))
	var direct_view: PixelActorView = _actor_views.get(actor_id)
	if direct_view != null:
		return direct_view
	var event_cell: Vector2i = event.get("cell", Vector2i(-9999, -9999))
	for view_value: Variant in _actor_views.values():
		if view_value is not PixelActorView:
			continue
		var view: PixelActorView = view_value
		var debug: Dictionary = view.get_debug_snapshot()
		if debug.get("cell", Vector2i(-9998, -9998)) == event_cell:
			return view
	return null


func _actor_debug_snapshots() -> Dictionary:
	var snapshots: Dictionary = {}
	for actor_id_value: Variant in _actor_views.keys():
		var view: PixelActorView = _actor_views.get(actor_id_value)
		if view != null:
			snapshots[int(actor_id_value)] = view.get_debug_snapshot()
	return snapshots


func _player_debug_snapshot(actor_debug: Dictionary) -> Dictionary:
	for debug_value: Variant in actor_debug.values():
		if debug_value is Dictionary and debug_value.get("kind", &"") == &"player":
			return debug_value
	return {}


func _visible_actor_count(actor_debug: Dictionary) -> int:
	var count: int = 0
	for debug_value: Variant in actor_debug.values():
		if debug_value is Dictionary and bool(debug_value.get("visible", false)):
			count += 1
	return count


func _boss_actor_count(actor_debug: Dictionary) -> int:
	var count: int = 0
	for debug_value: Variant in actor_debug.values():
		if debug_value is Dictionary and bool(debug_value.get("is_boss", false)):
			count += 1
	return count


func _remove_actor_view(actor_id: int) -> void:
	var view: PixelActorView = _actor_views.get(actor_id)
	if view == null:
		return
	view.prepare_for_removal()
	_actor_views.erase(actor_id)
	view.queue_free()


func _clear_actor_views() -> void:
	for actor_id_value: Variant in _actor_views.keys():
		_remove_actor_view(int(actor_id_value))


func _on_actor_death_finished(actor_id: int, source_view: PixelActorView) -> void:
	if _actor_views.get(actor_id) != source_view:
		return
	_retired_actor_ids[actor_id] = true
	_remove_actor_view(actor_id)
