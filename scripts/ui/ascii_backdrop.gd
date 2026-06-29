class_name AsciiBackdrop
extends ColorRect

# === Constants ===
const AMBIENT_GLYPHS: Array[String] = [".", "·", "'", "`", ","]
const STREAM_GLYPHS: Array[String] = [".", ":", "*", "+", "x"]
const REDRAW_INTERVAL: float = 0.08

# === Exports ===
@export var font: Font
@export var font_size: int = 15
@export var grid_step: Vector2 = Vector2(14, 18)
@export_range(0.0, 1.0) var glyph_density: float = 0.075
@export var ambient_color: Color = Color(0.28, 0.26, 0.39, 0.20)
@export var accent_color: Color = Color(0.6, 0.84, 0.9, 0.34)
@export var treasure_color: Color = Color(1.0, 0.72, 0.08, 0.34)

# === Private Variables ===
var _elapsed: float = 0.0
var _redraw_accumulator: float = 0.0


# === Lifecycle Methods ===
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL:
		_redraw_accumulator = 0.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null:
		return
	_draw_ambient_glyphs(draw_font)
	_draw_depth_streams(draw_font)
	_draw_soft_horizon(draw_font)


# === Private Methods ===
func _draw_ambient_glyphs(draw_font: Font) -> void:
	var columns: int = int(ceil(size.x / grid_step.x))
	var rows: int = int(ceil(size.y / grid_step.y))
	var density_cutoff: int = int(glyph_density * 1000.0)
	for y: int in range(rows):
		for x: int in range(columns):
			var drift: int = int(_elapsed * (0.7 + float((x * 17) % 9) * 0.08))
			var hash_value: int = _cell_hash(Vector2i(x, y + drift))
			if hash_value % 1000 >= density_cutoff:
				continue
			var glyph: String = AMBIENT_GLYPHS[hash_value % AMBIENT_GLYPHS.size()]
			var pulse: float = 0.55 + 0.25 * sin(_elapsed * 1.3 + float(hash_value % 31))
			var alpha: float = ambient_color.a * clamp(pulse, 0.2, 0.9)
			var glyph_color: Color = Color(ambient_color.r, ambient_color.g, ambient_color.b, alpha)
			var point: Vector2 = Vector2(x * grid_step.x, (y + 1) * grid_step.y)
			draw_string(draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_color)


func _draw_depth_streams(draw_font: Font) -> void:
	var lanes: Array[float] = [0.08, 0.18, 0.31, 0.69, 0.82, 0.93]
	for lane_index: int in range(lanes.size()):
		var lane_x: float = size.x * lanes[lane_index]
		var speed: float = 18.0 + float(lane_index % 3) * 8.0
		var base_y: float = fposmod(_elapsed * speed + float(lane_index * 97), size.y + 160.0) - 80.0
		for step: int in range(9):
			var point_y: float = fposmod(base_y + float(step * 82), size.y + 120.0) - 40.0
			var hash_value: int = _cell_hash(Vector2i(lane_index, step + int(_elapsed)))
			var glyph: String = STREAM_GLYPHS[hash_value % STREAM_GLYPHS.size()]
			var point_x: float = lane_x + sin(_elapsed * 0.9 + float(step)) * 22.0
			var fade: float = 0.18 + 0.18 * sin(_elapsed * 1.7 + float(step + lane_index))
			var stream_color: Color = accent_color.lerp(treasure_color, float(step % 3) * 0.22)
			stream_color.a = clamp(fade, 0.06, 0.34)
			draw_string(
				draw_font,
				Vector2(point_x, point_y),
				glyph,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				stream_color
			)


func _draw_soft_horizon(draw_font: Font) -> void:
	var center: Vector2 = size * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * 0.9)
	for ring_index: int in range(3):
		var radius: float = 118.0 + float(ring_index) * 46.0 + pulse * 10.0
		var ring_color: Color = accent_color.lerp(treasure_color, float(ring_index) * 0.18)
		ring_color.a = 0.025 + float(2 - ring_index) * 0.012
		_draw_ring(center, radius, ring_color)
	var runes: Array[String] = ["·", "+", "*", ":", "."]
	for index: int in range(18):
		var angle: float = _elapsed * 0.22 + float(index) * TAU / 18.0
		var radius: float = 190.0 + 18.0 * sin(_elapsed * 0.7 + float(index))
		var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		var rune_color: Color = Color(accent_color.r, accent_color.g, accent_color.b, 0.10)
		draw_string(
			draw_font,
			point,
			runes[index % runes.size()],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			rune_color
		)


func _draw_ring(center: Vector2, radius: float, ring_color: Color) -> void:
	var previous_point: Vector2 = center + Vector2(radius, 0.0)
	for segment: int in range(1, 97):
		var angle: float = float(segment) * TAU / 96.0
		var next_point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(previous_point, next_point, ring_color, 1.0)
		previous_point = next_point


func _cell_hash(cell: Vector2i) -> int:
	var value: int = cell.x * 73856093 ^ cell.y * 19349663 ^ 83492791
	return abs(value)
