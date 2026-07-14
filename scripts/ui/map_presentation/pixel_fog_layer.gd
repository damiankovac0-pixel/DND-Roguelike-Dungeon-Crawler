class_name PixelFogLayer
extends Node2D
## Draws unexplored and explored-but-hidden cells from shared visibility state.

# === Constants ===
const UNEXPLORED_COLOR: Color = Color(0.008, 0.012, 0.022, 1.0)
const EXPLORED_DIM_COLOR: Color = Color(0.02, 0.025, 0.045, 0.62)

# === Private Variables ===
var _layout: RefCounted
var _state: RefCounted
var _last_visibility_revision: int = -1


# === Public Methods ===
func configure(layout: RefCounted) -> void:
	_layout = layout
	queue_redraw()


func present(state: RefCounted, force_redraw: bool = false) -> void:
	_state = state
	var visibility_revision: int = int(state.get("visibility_revision"))
	if force_redraw or visibility_revision != _last_visibility_revision:
		_last_visibility_revision = visibility_revision
		queue_redraw()


func get_last_visibility_revision() -> int:
	return _last_visibility_revision


# === Lifecycle Methods ===
func _draw() -> void:
	if _layout == null or _state == null:
		return
	var explored_cells: Dictionary = _state.get("explored_cells")
	var visible_cells: Dictionary = _state.get("visible_cells")
	var view_rect: Rect2i = _layout.call(&"get_view_rect")
	for y: int in range(view_rect.position.y, view_rect.end.y):
		for x: int in range(view_rect.position.x, view_rect.end.x):
			var cell: Vector2i = Vector2i(x, y)
			var cell_rect: Rect2 = _layout.call(&"cell_rect", cell)
			if not explored_cells.has(cell):
				draw_rect(cell_rect, UNEXPLORED_COLOR)
			elif not visible_cells.has(cell):
				draw_rect(cell_rect, EXPLORED_DIM_COLOR)
