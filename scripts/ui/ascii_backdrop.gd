class_name AsciiBackdrop
extends ColorRect

# === Constants ===
const AMBIENT_GLYPHS: Array[String] = [".", "·", "'", "`"]
const CENTER_FRAME_ALPHA: float = 0.075
const INNER_FRAME_ALPHA: float = 0.055

# === Exports ===
@export var font: Font
@export var font_size: int = 15
@export var grid_step: Vector2 = Vector2(14, 18)
@export_range(0.0, 1.0) var glyph_density: float = 0.045
@export var ambient_color: Color = Color(0.28, 0.26, 0.39, 0.14)
@export var accent_color: Color = Color(0.6, 0.84, 0.9, 0.24)
@export var treasure_color: Color = Color(1.0, 0.72, 0.08, 0.34)


# === Lifecycle Methods ===
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null:
		return
	_draw_ambient_glyphs(draw_font)
	_draw_centered_depth_marker(draw_font)
	_draw_corner_runes(draw_font)


# === Private Methods ===
func _draw_ambient_glyphs(draw_font: Font) -> void:
	var columns: int = int(ceil(size.x / grid_step.x))
	var rows: int = int(ceil(size.y / grid_step.y))
	var density_cutoff: int = int(glyph_density * 1000.0)
	for y: int in range(rows):
		for x: int in range(columns):
			var hash_value: int = _cell_hash(Vector2i(x, y))
			if hash_value % 1000 >= density_cutoff:
				continue
			var glyph: String = AMBIENT_GLYPHS[hash_value % AMBIENT_GLYPHS.size()]
			var alpha: float = ambient_color.a * (0.45 + float(hash_value % 55) / 100.0)
			var glyph_color: Color = Color(ambient_color.r, ambient_color.g, ambient_color.b, alpha)
			var point: Vector2 = Vector2(x * grid_step.x, (y + 1) * grid_step.y)
			draw_string(draw_font, point, glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glyph_color)


func _draw_centered_depth_marker(draw_font: Font) -> void:
	var frame_size: Vector2 = Vector2(min(size.x * 0.44, 520.0), min(size.y * 0.32, 240.0))
	var frame_position: Vector2 = (size - frame_size) * 0.5
	var outer_color: Color = Color(accent_color.r, accent_color.g, accent_color.b, CENTER_FRAME_ALPHA)
	var inner_color: Color = Color(treasure_color.r, treasure_color.g, treasure_color.b, INNER_FRAME_ALPHA)
	draw_rect(Rect2(frame_position, frame_size), outer_color, false, 1.0)
	draw_rect(Rect2(frame_position + Vector2(10.0, 10.0), frame_size - Vector2(20.0, 20.0)), inner_color, false, 1.0)
	var marker: String = "· · ·"
	var marker_size: Vector2 = draw_font.get_string_size(marker, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(
		draw_font,
		Vector2((size.x - marker_size.x) * 0.5, frame_position.y + grid_step.y * 1.5),
		marker,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outer_color
	)
	draw_string(
		draw_font,
		Vector2((size.x - marker_size.x) * 0.5, frame_position.y + frame_size.y - grid_step.y),
		marker,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		outer_color
	)


func _draw_corner_runes(draw_font: Font) -> void:
	var runes: Array[Dictionary] = [
		{"point": Vector2(size.x - 176.0, size.y - 34.0), "text": "FOV  LOOT  EXIT"},
	]
	for rune: Dictionary in runes:
		draw_string(
			draw_font,
			rune["point"],
			rune["text"],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(accent_color.r, accent_color.g, accent_color.b, 0.18)
		)


func _repeat_char(glyph: String, count: int) -> String:
	var result: String = ""
	for _index: int in range(count):
		result += glyph
	return result


func _cell_hash(cell: Vector2i) -> int:
	var value: int = cell.x * 73856093 ^ cell.y * 19349663 ^ 83492791
	return abs(value)
