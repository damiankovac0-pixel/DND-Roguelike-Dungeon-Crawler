class_name ActorVisualCatalog
extends Resource
## Explicit sprite-sheet mapping for animated actor and boss views.
##
## Every visual ID resolves through fixed catalogue data. Runtime directory
## enumeration and filename construction are intentionally prohibited.

# === Constants ===
const ACTOR_FRAME_SIZE: Vector2i = Vector2i(16, 16)
const BOSS_FRAME_SIZE: Vector2i = Vector2i(80, 64)
const ACTOR_SHEET_SIZE: Vector2i = Vector2i(192, 816)
const BOSS_SHEET_SIZE: Vector2i = Vector2i(960, 320)
const ELITE_TINT: Color = Color(1.0, 0.84, 0.48)
const ACTOR_ROWS: Dictionary = {
	# New canonical visual IDs (actor/ namespace)
	&"actor/player/fighter": 0,
	&"actor/player/ranger": 1,
	&"actor/player/wizard": 2,
	&"actor/enemy/humanoid": 3,
	&"actor/enemy/brute": 4,
	&"actor/enemy/undead": 5,
	&"actor/enemy/beast": 6,
	&"actor/enemy/flyer": 7,
	&"actor/enemy/construct": 8,
	&"actor/enemy/caster": 9,
	&"actor/enemy/aquatic": 10,
	&"actor/enemy/aberration": 11,
	&"actor/shopkeeper": 12,
	&"actor/summon": 13,
	# Exact enemy visual IDs (rows 14-50, contract order)
	&"actor/enemy/bat": 14,
	&"actor/enemy/abyss_knight": 15,
	&"actor/enemy/ancient_dragon": 16,
	&"actor/enemy/cultist": 17,
	&"actor/enemy/goblin": 18,
	&"actor/enemy/kobold": 19,
	&"actor/enemy/lich": 20,
	&"actor/enemy/ogre_brute": 21,
	&"actor/enemy/orc": 22,
	&"actor/enemy/rat": 23,
	&"actor/enemy/skeleton": 24,
	&"actor/enemy/troll": 25,
	&"actor/enemy/wraith": 26,
	&"actor/enemy/zombie": 27,
	&"actor/enemy/stone_sentry": 28,
	&"actor/enemy/eye_acolyte": 29,
	&"actor/enemy/clockwork_spider": 30,
	&"actor/enemy/thorn_lasher": 31,
	&"actor/enemy/spore_servant": 32,
	&"actor/enemy/briar_witch": 33,
	&"actor/enemy/ash_revenant": 34,
	&"actor/enemy/ember_archer": 35,
	&"actor/enemy/flame_acolyte": 36,
	&"actor/enemy/drowned_knight": 37,
	&"actor/enemy/harpooner": 38,
	&"actor/enemy/abyssal_eel": 39,
	&"actor/enemy/tidecaller": 40,
	&"actor/enemy/mirror_duelist": 41,
	&"actor/enemy/prism_seer": 42,
	&"actor/enemy/shard_golem": 43,
	&"actor/enemy/glass_dragonling": 44,
	&"actor/enemy/void_herald": 45,
	&"actor/enemy/deep_maw": 46,
	&"actor/enemy/starved_godling": 47,
	&"actor/enemy/frost_guardian": 48,
	&"actor/enemy/warleader": 49,
	&"actor/enemy/shadow_weaver": 50,
	# Old semantic aliases
	&"actor/player": 0,
	&"actor/enemy": 3,
}
const KIND_FALLBACK_ROWS: Dictionary = {
	&"player": 0,
	&"enemy": 3,
	&"shopkeeper": 12,
	&"summon": 13,
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
const PLAYER_ACTION_SHEET_SIZE: Vector2i = Vector2i(448, 48)
const PLAYER_ACTION_COLUMNS: Dictionary = {
	&"attack_sword": [0, 1],
	&"attack_bow": [2, 3],
	&"attack_staff": [4, 5],
	&"use_scroll": [6, 7],
	&"drink_potion": [8, 9],
	&"fighter_cleave": [10, 11],
	&"fighter_second_wind": [12, 13],
	&"fighter_whirlwind": [14, 15],
	&"ranger_focus": [16, 17],
	&"ranger_volley": [18, 19],
	&"ranger_quickstep": [20, 21],
	&"arcane_spark": [22, 23],
	&"wizard_frost_nova": [24, 25],
	&"wizard_chain_lightning": [26, 27],
}
const PLAYER_ACTION_ROWS: Dictionary = {
	&"actor/player/fighter": 0,
	&"actor/player/ranger": 1,
	&"actor/player/wizard": 2,
	&"actor/player": 0,
}
const PLAYER_ACTION_ANIMATION_SPEEDS: Dictionary = {
	&"attack_sword": 10.0,
	&"attack_bow": 10.0,
	&"attack_staff": 10.0,
	&"use_scroll": 8.0,
	&"drink_potion": 8.0,
	&"fighter_cleave": 10.0,
	&"fighter_second_wind": 8.0,
	&"fighter_whirlwind": 10.0,
	&"ranger_focus": 8.0,
	&"ranger_volley": 10.0,
	&"ranger_quickstep": 10.0,
	&"arcane_spark": 10.0,
	&"wizard_frost_nova": 10.0,
	&"wizard_chain_lightning": 10.0,
}
const PLAYER_VISUAL_IDS: Array = [
	&"actor/player/fighter",
	&"actor/player/ranger",
	&"actor/player/wizard",
	&"actor/player",
]

# === Exports ===
@export var catalog_version: int = 2
@export var actor_sheet: Texture2D
@export var boss_sheet: Texture2D
@export var prototype: bool = false
@export var player_action_sheet: Texture2D
@export var attribution: String = "Project-authored production actor visual catalog."

# === Private Variables ===
var _frames_by_visual_id: Dictionary = {}


# === Public Methods ===
func validate() -> String:
	var validation_error: String = ""
	if catalog_version != 2:
		validation_error = "Unsupported actor visual catalogue version"
	elif actor_sheet == null:
		validation_error = "Pixel actor animation sheet is missing"
	elif boss_sheet == null:
		validation_error = "Pixel boss animation sheet is missing"
	elif player_action_sheet == null:
		validation_error = "Pixel player action sheet is missing"
	elif actor_sheet.get_size() != Vector2(ACTOR_SHEET_SIZE):
		validation_error = "Pixel actor animation sheet has the wrong dimensions"
	elif boss_sheet.get_size() != Vector2(BOSS_SHEET_SIZE):
		validation_error = "Pixel boss animation sheet has the wrong dimensions"
	elif player_action_sheet.get_size() != Vector2(PLAYER_ACTION_SHEET_SIZE):
		validation_error = "Pixel player action sheet has the wrong dimensions"
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
	if visual_id in PLAYER_VISUAL_IDS:
		_add_player_action_frames(frames, visual_id)
	_frames_by_visual_id[visual_id] = frames
	return frames


func tint_for(snapshot: Dictionary) -> Color:
	var visual_id: StringName = snapshot.get("visual_id", &"actor/enemy")
	if visual_id != &"" and ACTOR_ROWS.has(visual_id):
		var is_regular_elite: bool = (
			bool(snapshot.get("is_elite", false))
			and snapshot.get("kind", &"") == &"enemy"
			and not bool(snapshot.get("is_player", false))
			and not bool(snapshot.get("is_boss", false))
			and not bool(snapshot.get("is_summon", false))
		)
		return ELITE_TINT if is_regular_elite else Color.WHITE
	var boss_id: StringName = snapshot.get("boss_id", &"")
	if boss_id != &"" and BOSS_ROWS.has(boss_id):
		return Color.WHITE
	# Unknown visual — visible magenta fallback so missing assets are obvious
	return Color(1.0, 0.0, 1.0)


func frame_size_for(snapshot: Dictionary) -> Vector2i:
	return BOSS_FRAME_SIZE if bool(snapshot.get("is_boss", false)) else ACTOR_FRAME_SIZE


func clear_cache() -> void:
	_frames_by_visual_id.clear()


# === Private Methods ===
func _actor_row(snapshot: Dictionary) -> int:
	var visual_id: StringName = snapshot.get("visual_id", &"actor/enemy")
	if visual_id != &"" and ACTOR_ROWS.has(visual_id):
		return int(ACTOR_ROWS[visual_id])
	# Fall back to kind-based row
	var kind: StringName = snapshot.get("kind", &"enemy")
	return int(KIND_FALLBACK_ROWS.get(kind, ACTOR_ROWS[&"actor/enemy"]))


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


func _add_player_action_frames(frames: SpriteFrames, visual_id: StringName) -> void:
	var row: int = int(PLAYER_ACTION_ROWS.get(visual_id, 0))
	for animation_value: Variant in PLAYER_ACTION_COLUMNS.keys():
		var animation: StringName = StringName(animation_value)
		frames.add_animation(animation)
		frames.set_animation_loop(animation, false)
		frames.set_animation_speed(
			animation, float(PLAYER_ACTION_ANIMATION_SPEEDS.get(animation, 8.0))
		)
		var columns: Array = PLAYER_ACTION_COLUMNS[animation]
		for column_value: Variant in columns:
			var atlas_frame: AtlasTexture = AtlasTexture.new()
			atlas_frame.atlas = player_action_sheet
			atlas_frame.region = Rect2(
				Vector2(int(column_value) * ACTOR_FRAME_SIZE.x, row * ACTOR_FRAME_SIZE.y),
				Vector2(ACTOR_FRAME_SIZE),
			)
			frames.add_frame(animation, atlas_frame)
