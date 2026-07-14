class_name PixelMapRenderer
extends Node2D
## Minimal 16x16 pixel-map backend for terrain, fog, and the player.
##
## Gameplay remains authoritative elsewhere. This renderer consumes only a
## MapPresentationState and a renderer-local MapGridLayout.

# === Constants ===
const TILE_SOURCE_ID: int = 0
const FLOOR_TILE_TYPE: int = 0

# === Exports ===
@export var catalog: Resource

# === Private Variables ===
var _layout: RefCounted
var _state: RefCounted
var _available: bool = false
var _render_profile: StringName = &"hybrid"
var _reduced_vfx_enabled: bool = false
var _last_map_revision: int = -1
var _last_visibility_revision: int = -1
var _last_actor_revision: int = -1
var _last_environment_revision: int = -1
var _transient_reset_count: int = 0
var _player_cell: Vector2i = Vector2i.ZERO
var _playfield_rect: Rect2 = Rect2(Vector2(10, 10), Vector2(680, 590))
var _outer_background_color: Color = Color(0.0, 0.02, 0.035)
var _border_color: Color = Color(0.047, 0.059, 0.082)
var _border_frame_color: Color = Color(0.282, 0.259, 0.392)
var _background_color: Color = Color(0.025, 0.032, 0.047)

# === Onready ===
@onready var ground_layer: TileMapLayer = $GroundLayer
@onready var structure_layer: TileMapLayer = $StructureLayer
@onready var player_sprite: Sprite2D = $PlayerSprite
@onready var fog_layer: PixelFogLayer = $FogLayer


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
	if catalog == null or not catalog.has_method(&"validate"):
		return ERR_FILE_NOT_FOUND
	var validation_error: String = str(catalog.call(&"validate"))
	if not validation_error.is_empty():
		push_warning(validation_error)
		return ERR_FILE_NOT_FOUND
	var tile_set_value: Variant = catalog.call(&"create_tile_set")
	if not (tile_set_value is TileSet):
		return ERR_CANT_CREATE
	ground_layer.tile_set = tile_set_value
	structure_layer.tile_set = tile_set_value
	var player_texture_value: Variant = catalog.call(&"player_or_fallback_texture")
	if player_texture_value is Texture2D:
		player_sprite.texture = player_texture_value
	fog_layer.configure(_layout)
	_available = player_sprite.texture != null
	return OK if _available else ERR_FILE_NOT_FOUND


func is_renderer_available() -> bool:
	return _available and _layout != null and is_instance_valid(ground_layer)


func set_render_profile(profile: StringName) -> void:
	_render_profile = profile


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
	):
		_update_player()
	fog_layer.present(state, view_changed)
	if environment_revision != _last_environment_revision:
		queue_redraw()
	_last_map_revision = map_revision
	_last_visibility_revision = visibility_revision
	_last_actor_revision = actor_revision
	_last_environment_revision = environment_revision


func set_reduced_vfx(enabled: bool) -> void:
	_reduced_vfx_enabled = enabled


func reset_transients() -> void:
	_transient_reset_count += 1


func shutdown_renderer() -> void:
	ground_layer.clear()
	structure_layer.clear()
	player_sprite.visible = false
	visible = false
	_state = null


func get_debug_snapshot() -> Dictionary:
	var view_origin: Vector2i = (
		_layout.call(&"get_view_origin_cell") if _layout != null else Vector2i.ZERO
	)
	return {
		"available": is_renderer_available(),
		"profile": _render_profile,
		"ground_cell_count": ground_layer.get_used_cells().size(),
		"structure_cell_count": structure_layer.get_used_cells().size(),
		"player_visible": player_sprite.visible,
		"player_cell": _player_cell,
		"player_position": player_sprite.position,
		"view_origin": view_origin,
		"map_revision": _last_map_revision,
		"visibility_revision": _last_visibility_revision,
		"actor_revision": _last_actor_revision,
		"reduced_vfx": _reduced_vfx_enabled,
		"transient_reset_count": _transient_reset_count,
	}


# === Private Methods ===
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


func _update_player() -> void:
	player_sprite.visible = false
	var player_snapshot: Dictionary = _state.call(&"get_player_snapshot")
	if player_snapshot.is_empty() or not bool(player_snapshot.get("alive", false)):
		return
	var cell: Vector2i = player_snapshot.get("cell", Vector2i.ZERO)
	var visible_cells: Dictionary = _state.get("visible_cells")
	if not visible_cells.has(cell) or not bool(_layout.call(&"is_cell_in_view", cell)):
		return
	_player_cell = cell
	player_sprite.position = Vector2(_layout.call(&"cell_center_to_local", cell)).round()
	player_sprite.visible = true
