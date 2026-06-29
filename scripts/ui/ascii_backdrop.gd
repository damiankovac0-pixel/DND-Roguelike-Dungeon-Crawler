class_name AsciiBackdrop
extends ColorRect

# === Constants ===
const AMBIENT_GLYPHS: Array[String] = [".", "·", "'", "`", ":", "*", "+"]
const ROOM_PATTERNS: Array[Dictionary] = [
	{"origin": Vector2(64, 74), "width": 18, "height": 8, "label": "VAULT"},
	{"origin": Vector2(66, 502), "width": 22, "height": 9, "label": "CRYPT"},
	{"origin": Vector2(612, 596), "width": 15, "height": 6, "label": "STAIRS"},
]

# === Exports ===
@export var font: Font
@export var font_size: int = 15
@export var grid_step: Vector2 = Vector2(14, 18)
@export_range(0.0, 1.0) var glyph_density: float = 0.075
@export var ambient_color: Color = Color(0.28, 0.26, 0.39, 0.20)
@export var accent_color: Color = Color(0.6, 0.84, 0.9, 0.34)
@export var treasure_color: Color = Color(1.0, 0.72, 0.08, 0.42)


# === Lifecycle Methods ===
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	var draw_font: Font = font if font != null else ThemeDB.fallback_font
	if draw_font == null:
		return
	_draw_ambient_glyphs(draw_font)
	_draw_room_overlays(draw_font)
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


func _draw_room_overlays(draw_font: Font) -> void:
	for pattern: Dictionary in ROOM_PATTERNS:
		_draw_ascii_room(
			draw_font,
			pattern["origin"],
			pattern["width"],
			pattern["height"],
			pattern["label"]
		)


func _draw_ascii_room(
	draw_font: Font, origin: Vector2, width_chars: int, height_chars: int, label: String
) -> void:
	var top_bottom: String = "+" + _repeat_char("-", max(0, width_chars - 2)) + "+"
	var middle: String = "|" + _repeat_char(".", max(0, width_chars - 2)) + "|"
	for row: int in range(height_chars):
		var row_text: String = top_bottom if row == 0 or row == height_chars - 1 else middle
		var row_color: Color = accent_color if row == 0 or row == height_chars - 1 else ambient_color
		draw_string(
			draw_font,
			origin + Vector2(0, float(row + 1) * grid_step.y),
			row_text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			row_color
		)
	draw_string(
		draw_font,
		origin + Vector2(grid_step.x * 2.0, grid_step.y * 3.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		treasure_color
	)


func _draw_corner_runes(draw_font: Font) -> void:
	var runes: Array[Dictionary] = [
		{"point": Vector2(24, 32), "text": "HP  AC  XP"},
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
			Color(accent_color.r, accent_color.g, accent_color.b, 0.26)
		)


func _repeat_char(glyph: String, count: int) -> String:
	var result: String = ""
	for _index: int in range(count):
		result += glyph
	return result


func _cell_hash(cell: Vector2i) -> int:
	var value: int = cell.x * 73856093 ^ cell.y * 19349663 ^ 83492791
	return abs(value)
