## V15 procedural ASCII backdrop with mode/intensity controls and rich terminal visuals.
class_name AsciiBackdrop
extends ColorRect

# === Mode Enum ===
enum Mode {
	MAIN_MENU = 0,  ## Full effect: silhouettes, parallax, horizon, ambient streams
	AMBIENT = 1,  ## Moderate: horizon + reduced ambient, no silhouettes — good for readable overlays
	MINIMAL = 2,  ## Just ambient glyphs and subtle horizon — best for dense text panels
}

# === Constants ===
const AMBIENT_GLYPHS: Array[String] = [".", "·", "'", "`", ","]
const STREAM_GLYPHS: Array[String] = [".", ":", "*", "+", "x"]
const DUNGEON_SILHOUETTES: Array[String] = ["#", "▓", "▒", "░", "╬", "♣", "▲", "≈"]
const REDRAW_INTERVAL: float = 0.08
const MAX_DENSITY: float = 0.25
const MAX_ALPHA: float = 0.90

# === Exports ===
@export var mode: Mode = Mode.MAIN_MENU
@export_range(0.0, 1.0) var intensity: float = 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.0)
@export var motion_enabled: bool = true
@export var font: Font
@export var font_size: int = 15
@export var grid_step: Vector2 = Vector2(14, 18)
@export_range(0.0, 1.0) var glyph_density: float = 0.075
@export var ambient_color: Color = Color(0.28, 0.26, 0.39, 0.20)
@export var accent_color: Color = Color(0.6, 0.84, 0.9, 0.34)
@export var treasure_color: Color = Color(1.0, 0.72, 0.08, 0.34)
@export var silhouette_color: Color = Color(0.18, 0.14, 0.25, 0.06)
@export var parallax_speed: float = 1.0

# === Private Variables ===
var _elapsed: float = 0.0
var _redraw_accumulator: float = 0.0


# === Lifecycle Methods ===
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	var dt: float = delta if motion_enabled else 0.0
	_elapsed += dt
	_redraw_accumulator += delta
	if _redraw_accumulator >= REDRAW_INTERVAL:
		_redraw_accumulator = 0.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null:
		return
	var eff: float = intensity
	_draw_ambient_glyphs(draw_font, eff)
	_draw_depth_streams(draw_font, eff)
	_draw_soft_horizon(draw_font, eff)
	if mode == Mode.MAIN_MENU:
		_draw_dungeon_silhouettes(draw_font, eff)
		_draw_parallax_streams(draw_font, eff)


# === Private Drawing Methods ===
func _draw_ambient_glyphs(draw_font: Font, eff: float) -> void:
	if mode == Mode.MINIMAL:
		_draw_minimal_ambient(draw_font, eff)
		return
	var columns: int = int(ceil(size.x / grid_step.x))
	var rows: int = int(ceil(size.y / grid_step.y))
	var effective_density: float = minf(glyph_density * eff, MAX_DENSITY)
	var density_cutoff: int = int(effective_density * 1000.0)
	for y: int in range(rows):
		for x: int in range(columns):
			var drift: int = int(_elapsed * (0.7 + float((x * 17) % 9) * 0.08))
			var hash_value: int = _cell_hash(Vector2i(x, y + drift))
			if hash_value % 1000 >= density_cutoff:
				continue
			var glyph: String = AMBIENT_GLYPHS[hash_value % AMBIENT_GLYPHS.size()]
			var pulse: float = 0.55 + 0.25 * sin(_elapsed * 1.3 + float(hash_value % 31))
			var alpha: float = minf(ambient_color.a * clamp(pulse, 0.2, 0.9) * eff, MAX_ALPHA)
			var glyph_color: Color = Color(ambient_color.r, ambient_color.g, ambient_color.b, alpha)
			var point: Vector2 = Vector2(x * grid_step.x, (y + 1) * grid_step.y)
			draw_string(
				draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_color
			)


func _draw_minimal_ambient(draw_font: Font, eff: float) -> void:
	## Sparse, dim ambient for text-heavy panels.
	var columns: int = int(ceil(size.x / grid_step.x))
	var rows: int = int(ceil(size.y / grid_step.y))
	var density_cutoff: int = int(glyph_density * 0.4 * eff * 1000.0)
	for y: int in range(rows):
		for x: int in range(columns):
			var drift: int = int(_elapsed * 0.3)
			var hash_value: int = _cell_hash(Vector2i(x, y + drift))
			if hash_value % 1000 >= density_cutoff:
				continue
			var glyph: String = AMBIENT_GLYPHS[hash_value % AMBIENT_GLYPHS.size()]
			var alpha: float = minf(ambient_color.a * 0.5 * eff, 0.12)
			var glyph_color: Color = Color(ambient_color.r, ambient_color.g, ambient_color.b, alpha)
			var point: Vector2 = Vector2(x * grid_step.x, (y + 1) * grid_step.y)
			draw_string(
				draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_color
			)


func _draw_depth_streams(draw_font: Font, eff: float) -> void:
	if mode == Mode.MINIMAL:
		return
	var lanes: Array[float] = [0.08, 0.18, 0.31, 0.69, 0.82, 0.93]
	var lane_count: int = lanes.size()
	if mode == Mode.AMBIENT:
		lane_count = 3  # fewer streams for readability
	for lane_index: int in range(lane_count):
		var lane_x: float = size.x * lanes[lane_index]
		var speed: float = (18.0 + float(lane_index % 3) * 8.0) * parallax_speed
		var base_y: float = (
			fposmod(_elapsed * speed + float(lane_index * 97), size.y + 160.0) - 80.0
		)
		for step: int in range(9):
			var point_y: float = fposmod(base_y + float(step * 82), size.y + 120.0) - 40.0
			var hash_value: int = _cell_hash(Vector2i(lane_index, step + int(_elapsed)))
			var glyph: String = STREAM_GLYPHS[hash_value % STREAM_GLYPHS.size()]
			var point_x: float = lane_x + sin(_elapsed * 0.9 + float(step)) * 22.0
			var fade: float = 0.18 + 0.18 * sin(_elapsed * 1.7 + float(step + lane_index))
			var stream_color: Color = accent_color.lerp(treasure_color, float(step % 3) * 0.22)
			stream_color.a = clamp(fade * eff, 0.06, 0.34)
			draw_string(
				draw_font,
				Vector2(point_x, point_y),
				glyph,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				stream_color
			)


func _draw_soft_horizon(draw_font: Font, eff: float) -> void:
	if mode == Mode.MINIMAL:
		# Even in minimal, keep one faint ring for atmosphere
		var center: Vector2 = size * 0.5
		var faint_ring_color: Color = Color(
			accent_color.r, accent_color.g, accent_color.b, 0.015 * eff
		)
		_draw_ring(center, 140.0, faint_ring_color)
		return
	var center: Vector2 = size * 0.5
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * 0.9)
	var ring_count: int = 3 if mode == Mode.MAIN_MENU else 2
	for ring_index: int in range(ring_count):
		var radius: float = 118.0 + float(ring_index) * 46.0 + pulse * 10.0
		var ring_color: Color = accent_color.lerp(treasure_color, float(ring_index) * 0.18)
		ring_color.a = (0.025 + float(ring_count - 1 - ring_index) * 0.012) * eff
		_draw_ring(center, radius, ring_color)
	if mode == Mode.MAIN_MENU:
		var runes: Array[String] = ["·", "+", "*", ":", "."]
		var rune_count: int = 14 if eff < 0.5 else 18
		for index: int in range(rune_count):
			var angle: float = _elapsed * 0.22 + float(index) * TAU / float(rune_count)
			var radius: float = 190.0 + 18.0 * sin(_elapsed * 0.7 + float(index))
			var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
			var rune_color: Color = Color(
				accent_color.r, accent_color.g, accent_color.b, 0.10 * eff
			)
			draw_string(
				draw_font,
				point,
				runes[index % runes.size()],
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				rune_color
			)


func _draw_dungeon_silhouettes(draw_font: Font, eff: float) -> void:
	## Faint dungeon-wall traces on the left/right edges for atmosphere.
	var columns: int = int(ceil(size.x / grid_step.x))
	var rows: int = int(ceil(size.y / grid_step.y))
	var silhouette_density: int = int(8.0 * eff)
	var silhouette_lanes: Array[int] = [0, 1, columns - 2, columns - 1]
	for lane_x: int in silhouette_lanes:
		if lane_x < 0 or lane_x >= columns:
			continue
		for anchor_y: int in range(0, rows, 4):
			var hash_value: int = _cell_hash(Vector2i(lane_x * 7, anchor_y * 13))
			if hash_value % 1000 > silhouette_density * 80:
				continue
			for segment: int in range(3):
				var seg_y: int = anchor_y + segment
				if seg_y >= rows:
					break
				var glyph: String = DUNGEON_SILHOUETTES[
					(hash_value + segment) % DUNGEON_SILHOUETTES.size()
				]
				var seg_alpha: float = (
					silhouette_color.a * eff * (0.4 + 0.3 * sin(_elapsed * 0.5 + float(seg_y)))
				)
				seg_alpha = minf(seg_alpha, 0.12)
				var seg_color: Color = Color(
					silhouette_color.r, silhouette_color.g, silhouette_color.b, seg_alpha
				)
				var point: Vector2 = Vector2(lane_x * grid_step.x, (seg_y + 1) * grid_step.y)
				draw_string(
					draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, seg_color
				)
	# Top/bottom border traces
	var edge_lanes: Array[int] = [0, rows - 1]
	for lane_y: int in edge_lanes:
		for lane_x: int in range(0, columns, 3):
			var hash_value: int = _cell_hash(Vector2i(lane_x * 31, lane_y * 17))
			if hash_value % 1000 > silhouette_density * 60:
				continue
			var glyph: String = DUNGEON_SILHOUETTES[(hash_value >> 3) % DUNGEON_SILHOUETTES.size()]
			var edge_alpha: float = silhouette_color.a * eff * 0.6
			edge_alpha = minf(edge_alpha, 0.08)
			var edge_color: Color = Color(
				silhouette_color.r, silhouette_color.g, silhouette_color.b, edge_alpha
			)
			var point: Vector2 = Vector2(lane_x * grid_step.x, (lane_y + 1) * grid_step.y)
			draw_string(
				draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, edge_color
			)


func _draw_parallax_streams(draw_font: Font, eff: float) -> void:
	## Slow, wide streams at different depths for parallax depth effect.
	var parallax_lanes: Array[Dictionary] = [
		{"x": 0.05, "speed": 5.0, "count": 3},
		{"x": 0.50, "speed": 7.0, "count": 4},
		{"x": 0.95, "speed": 6.0, "count": 3},
		{"x": 0.25, "speed": 4.0, "count": 2},
		{"x": 0.75, "speed": 8.0, "count": 2},
	]
	for lane: Dictionary in parallax_lanes:
		var lane_x: float = size.x * lane["x"]
		var speed: float = lane["speed"] * parallax_speed
		var count: int = lane["count"]
		for step: int in range(count):
			var offset: float = float(step * 143) * 0.3
			var base_y: float = fposmod(_elapsed * speed + offset, size.y + 80.0) - 40.0
			var hash_value: int = _cell_hash(Vector2i(int(lane_x * 10), step + int(_elapsed * 0.3)))
			var glyph: String = STREAM_GLYPHS[(hash_value >> 2) % STREAM_GLYPHS.size()]
			var point_x: float = lane_x + sin(_elapsed * 0.35 + float(step)) * 30.0
			var fade: float = 0.06 + 0.06 * sin(_elapsed * 0.8 + float(step + int(lane_x)))
			var stream_color: Color = Color(
				accent_color.r, accent_color.g, accent_color.b, clamp(fade * eff, 0.02, 0.18)
			)
			draw_string(
				draw_font,
				Vector2(point_x, base_y),
				glyph,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				font_size,
				stream_color
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
