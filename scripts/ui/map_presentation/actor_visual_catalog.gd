class_name ActorVisualCatalog
extends Resource
## Explicit sprite-sheet mapping for animated actor and boss views.
##
## Every visual ID resolves through fixed catalogue data. Runtime directory
## enumeration and filename construction are intentionally prohibited.

# === Constants ===
const ACTOR_FRAME_SIZE: Vector2i = Vector2i(16, 16)
const BOSS_FRAME_SIZE: Vector2i = Vector2i(80, 64)
const ACTOR_SHEET_SIZE: Vector2i = Vector2i(192, 64)
const BOSS_SHEET_SIZE: Vector2i = Vector2i(960, 320)
const ACTOR_ROWS: Dictionary = {
	&"player": 0,
	&"enemy": 1,
	&"shopkeeper": 2,
	&"summon": 3,
}
const BOSS_ROWS: Dictionary = {
	&"observer": 0,
	&"seraphine": 1,
	&"vorrak": 2,
	&"kaelros": 3,
	&"nyxara": 4,
}
const ANIMATION_COLUMNS: Dictionary = {
	&"idle": [0, 1],
	&"move": [2, 3],
	&"attack": [4, 5],
	&"cast": [6, 7],
	&"hurt": [8, 9],
	&"death": [10, 11],
}
const ANIMATION_SPEEDS: Dictionary = {
	&"idle": 3.0,
	&"move": 8.0,
	&"attack": 10.0,
	&"cast": 10.0,
	&"hurt": 12.0,
	&"death": 8.0,
}
const LOOPING_ANIMATIONS: Dictionary = {
	&"idle": true,
	&"move": true,
}

# === Exports ===
@export var catalog_version: int = 1
@export var actor_sheet: Texture2D
@export var boss_sheet: Texture2D
@export var prototype: bool = true
@export var attribution: String = "Project-authored deterministic Phase 3 prototype"

# === Private Variables ===
var _frames_by_visual_id: Dictionary = {}


# === Public Methods ===
func validate() -> String:
	var validation_error: String = ""
	if catalog_version != 1:
		validation_error = "Unsupported actor visual catalogue version"
	elif actor_sheet == null:
		validation_error = "Pixel actor animation sheet is missing"
	elif boss_sheet == null:
		validation_error = "Pixel boss animation sheet is missing"
	elif actor_sheet.get_size() != Vector2(ACTOR_SHEET_SIZE):
		validation_error = "Pixel actor animation sheet has the wrong dimensions"
	elif boss_sheet.get_size() != Vector2(BOSS_SHEET_SIZE):
		validation_error = "Pixel boss animation sheet has the wrong dimensions"
	elif attribution.strip_edges().is_empty():
		validation_error = "Pixel actor catalogue attribution is missing"
	return validation_error


func sprite_frames_for(snapshot: Dictionary) -> SpriteFrames:
	var visual_id: StringName = snapshot.get("visual_id", &"actor/enemy")
	if _frames_by_visual_id.has(visual_id):
		return _frames_by_visual_id[visual_id]
	var is_boss: bool = bool(snapshot.get("is_boss", false))
	var frame_size: Vector2i = BOSS_FRAME_SIZE if is_boss else ACTOR_FRAME_SIZE
	var texture: Texture2D = boss_sheet if is_boss else actor_sheet
	var row: int = _boss_row(snapshot) if is_boss else _actor_row(snapshot)
	var frames: SpriteFrames = _build_sprite_frames(texture, frame_size, row)
	_frames_by_visual_id[visual_id] = frames
	return frames


func tint_for(snapshot: Dictionary) -> Color:
	var kind: StringName = snapshot.get("kind", &"enemy")
	match kind:
		&"player":
			return Color(0.34, 0.94, 1.0)
		&"shopkeeper":
			return Color(1.0, 0.82, 0.32)
		&"summon":
			return Color(0.72, 0.58, 1.0)
	var color_value: Variant = snapshot.get("color", Color.WHITE)
	return color_value if color_value is Color else Color.WHITE


func frame_size_for(snapshot: Dictionary) -> Vector2i:
	return BOSS_FRAME_SIZE if bool(snapshot.get("is_boss", false)) else ACTOR_FRAME_SIZE


func clear_cache() -> void:
	_frames_by_visual_id.clear()


# === Private Methods ===
func _actor_row(snapshot: Dictionary) -> int:
	var kind: StringName = snapshot.get("kind", &"enemy")
	return int(ACTOR_ROWS.get(kind, ACTOR_ROWS[&"enemy"]))


func _boss_row(snapshot: Dictionary) -> int:
	var boss_id: StringName = snapshot.get("boss_id", &"observer")
	return int(BOSS_ROWS.get(boss_id, BOSS_ROWS[&"observer"]))


func _build_sprite_frames(texture: Texture2D, frame_size: Vector2i, row: int) -> SpriteFrames:
	var frames: SpriteFrames = SpriteFrames.new()
	frames.remove_animation(&"default")
	for animation_value: Variant in ANIMATION_COLUMNS.keys():
		var animation: StringName = StringName(animation_value)
		frames.add_animation(animation)
		frames.set_animation_loop(animation, bool(LOOPING_ANIMATIONS.get(animation, false)))
		frames.set_animation_speed(animation, float(ANIMATION_SPEEDS[animation]))
		var columns: Array = ANIMATION_COLUMNS[animation]
		for column_value: Variant in columns:
			var atlas_frame: AtlasTexture = AtlasTexture.new()
			atlas_frame.atlas = texture
			atlas_frame.region = Rect2(
				Vector2(int(column_value) * frame_size.x, row * frame_size.y),
				Vector2(frame_size),
			)
			frames.add_frame(animation, atlas_frame)
	return frames
