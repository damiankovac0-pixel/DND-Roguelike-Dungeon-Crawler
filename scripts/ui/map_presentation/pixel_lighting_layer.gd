class_name PixelLightingLayer
extends Node2D
## Cosmetic cell-aligned light falloff for the pixel-map base.
##
## This layer consumes the authoritative visible-cell set but never expands or
## contracts it. It only darkens the outer edge of cells already visible.

# === Constants ===
const INNER_LIGHT_RADIUS: int = 2
const OUTER_LIGHT_RADIUS: int = 8
const MAX_EDGE_ALPHA: float = 0.13

# === Private Variables ===
var _layout: RefCounted
var _state: RefCounted
var _last_visibility_revision: int = -1
var _last_environment_revision: int = -1
var _last_focus_cell: Vector2i = Vector2i(-9999, -9999)
var _lit_cell_count: int = 0


# === Public Methods ===
func configure(layout: RefCounted) -> Error:
	_layout = layout
	return OK if _layout != null else ERR_INVALID_PARAMETER


func present(state: RefCounted, force_redraw: bool = false) -> void:
	_state = state
	if _state == null:
		_lit_cell_count = 0
		queue_redraw()
		return
	var visibility_revision: int = int(_state.get("visibility_revision"))
	var environment_revision: int = int(_state.get("environment_revision"))
	var focus_cell: Vector2i = _state.get("focus_cell")
	if (
		force_redraw
		or visibility_revision != _last_visibility_revision
		or environment_revision != _last_environment_revision
		or focus_cell != _last_focus_cell
	):
		_update_lit_cell_count()
		queue_redraw()
	_last_visibility_revision = visibility_revision
	_last_environment_revision = environment_revision
	_last_focus_cell = focus_cell


func clear() -> void:
	_state = null
	_lit_cell_count = 0
	_last_visibility_revision = -1
	_last_environment_revision = -1
	_last_focus_cell = Vector2i(-9999, -9999)
	queue_redraw()


func get_debug_snapshot() -> Dictionary:
	return {
		"enabled": _lighting_enabled(),
		"lit_cell_count": _lit_cell_count,
		"inner_radius": INNER_LIGHT_RADIUS,
		"outer_radius": OUTER_LIGHT_RADIUS,
		"max_edge_alpha": MAX_EDGE_ALPHA,
	}


# === Lifecycle Methods ===
func _draw() -> void:
	if not _lighting_enabled():
		return
	var focus_cell: Vector2i = _state.get("focus_cell")
	var visible_cells: Dictionary = _state.get("visible_cells")
	var atmosphere_profile: Dictionary = _state.get("atmosphere_profile")
	var void_color: Color = _color_or(
		atmosphere_profile.get("void_color", Color(0.02, 0.03, 0.05, 1.0)),
		Color(0.02, 0.03, 0.05, 1.0),
	)
	for cell_value: Variant in visible_cells:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not bool(_layout.call(&"is_cell_in_view", cell)):
			continue
		var distance: int = _chebyshev_distance(cell, focus_cell)
		if distance <= INNER_LIGHT_RADIUS:
			continue
		var falloff: float = clampf(
			float(distance - INNER_LIGHT_RADIUS) / float(OUTER_LIGHT_RADIUS - INNER_LIGHT_RADIUS),
			0.0,
			1.0,
		)
		var shade: Color = Color(void_color.r, void_color.g, void_color.b, falloff * MAX_EDGE_ALPHA)
		var rect: Rect2 = _layout.call(&"cell_rect", cell)
		draw_rect(rect, shade)


# === Private Methods ===
func _lighting_enabled() -> bool:
	return (
		_layout != null
		and _state != null
		and bool(_state.get("atmosphere_enabled"))
		and not _state.get("visible_cells").is_empty()
	)


func _update_lit_cell_count() -> void:
	_lit_cell_count = 0
	if not _lighting_enabled():
		return
	var focus_cell: Vector2i = _state.get("focus_cell")
	for cell_value: Variant in _state.get("visible_cells"):
		if (
			cell_value is Vector2i
			and bool(_layout.call(&"is_cell_in_view", cell_value))
			and _chebyshev_distance(cell_value, focus_cell) > INNER_LIGHT_RADIUS
		):
			_lit_cell_count += 1


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _color_or(value: Variant, fallback: Color) -> Color:
	return value if value is Color else fallback
