## Framed, catalog-backed pixel preview used by the Library browsers.
class_name LibraryVisualPreview
extends PanelContainer

# === Constants ===
const ACTOR_VISUAL_CATALOG: ActorVisualCatalog = preload(
	"res://resources/visuals/catalogs/actor_visual_catalog.tres"
)
const OBJECT_VISUAL_CATALOG: MapObjectVisualCatalog = preload(
	"res://resources/visuals/catalogs/map_object_visual_catalog.tres"
)
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const PixelObjectLayerScript = preload("res://scripts/ui/map_presentation/pixel_object_layer.gd")
const ITEM_RARE_THRESHOLD: int = ItemDataScript.ItemRarity.RARE
const PREVIEW_INSET: float = 16.0
const WIDE_STAGE_HEIGHT: float = 112.0
const COMPACT_STAGE_HEIGHT: float = 64.0
const STATIC_OVERLAY_ALPHA_MULTIPLIER: float = 0.5
const PULSE_MINIMUM_MULTIPLIER: float = 0.6
const PULSE_RANGE_MULTIPLIER: float = 0.4

# === Private Variables ===
var _animation_time: float = 0.0
var _base_sprite_position: Vector2 = Vector2.ZERO
var _current_frame_size: Vector2i = Vector2i(16, 16)
var _has_enchantment: bool = false
var _enchantment_tint: Color = Color.WHITE
var _reduced_vfx_enabled: bool = true

# === Onready ===
@onready var preview_stage: Control = $Margin/VBox/PreviewStage
@onready var actor_sprite: AnimatedSprite2D = $Margin/VBox/PreviewStage/ActorSprite
@onready var object_sprite: Sprite2D = $Margin/VBox/PreviewStage/ObjectSprite
@onready var enchantment_sprite: Sprite2D = $Margin/VBox/PreviewStage/EnchantmentSprite
@onready var alt_text: Label = $Margin/VBox/AltText
@onready var fallback_note: Label = $Margin/VBox/FallbackNote


# === Lifecycle Methods ===
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	object_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	enchantment_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_reduced_vfx_enabled = SensoryFeedback.is_reduced_vfx_preferred()
	preview_stage.resized.connect(_layout_sprite_nodes)
	set_process(false)
	show_empty("Choose an entry to inspect its catalog art.")


func _process(delta: float) -> void:
	_animation_time += delta
	_apply_object_motion()


# === Public Methods ===
func show_enemy(enemy: Resource) -> void:
	_reset_visuals()
	var snapshot: Dictionary = {
		"visual_id": enemy.visual_id,
		"kind": &"enemy",
		"is_boss": enemy.is_boss,
		"boss_id": enemy.boss_id,
	}
	var has_visual: bool = _actor_has_visual(snapshot)
	var frames: SpriteFrames = ACTOR_VISUAL_CATALOG.sprite_frames_for(snapshot)
	actor_sprite.sprite_frames = frames
	actor_sprite.modulate = ACTOR_VISUAL_CATALOG.tint_for(snapshot)
	actor_sprite.visible = frames != null
	_current_frame_size = ACTOR_VISUAL_CATALOG.frame_size_for(snapshot)
	if frames != null and frames.has_animation(&"idle"):
		actor_sprite.animation = &"idle"
		actor_sprite.frame = 0
		if _reduced_vfx_enabled:
			actor_sprite.stop()
		else:
			actor_sprite.play(&"idle")
	alt_text.text = _alt_text(enemy.display_name, enemy.glyph)
	if has_visual:
		fallback_note.text = ""
	else:
		fallback_note.text = (
			"Catalog fallback shown: no actor art is registered for '%s'." % enemy.visual_id
		)
	_layout_sprite_nodes()


func show_item(item: Resource) -> void:
	var enchanted: bool = (
		item.rarity >= ITEM_RARE_THRESHOLD and item.kind != ItemDataScript.ItemKind.CONSUMABLE
	)
	_show_object(item, enchanted)


func show_trap(trap: Resource) -> void:
	_show_object(trap, false)


func show_empty(message: String) -> void:
	_reset_visuals()
	alt_text.text = message
	fallback_note.text = "No pixel preview is available until a record is selected."


func is_reduced_vfx_enabled() -> bool:
	return _reduced_vfx_enabled


func set_compact_layout(compact: bool) -> void:
	if not is_node_ready():
		return
	preview_stage.custom_minimum_size.y = (COMPACT_STAGE_HEIGHT if compact else WIDE_STAGE_HEIGHT)
	_layout_sprite_nodes()


# === Private Methods ===
func _show_object(data: Resource, enchanted: bool) -> void:
	_reset_visuals()
	var visual_id: StringName = data.visual_id
	var atlas_texture: AtlasTexture = AtlasTexture.new()
	atlas_texture.atlas = OBJECT_VISUAL_CATALOG.get_atlas()
	atlas_texture.region = OBJECT_VISUAL_CATALOG.region_for(visual_id)
	object_sprite.texture = atlas_texture
	var has_authored_visual: bool = OBJECT_VISUAL_CATALOG.has_visual(visual_id)
	object_sprite.modulate = Color.WHITE if has_authored_visual else data.color
	object_sprite.visible = atlas_texture.atlas != null
	_current_frame_size = Vector2i(atlas_texture.region.size)
	_has_enchantment = enchanted
	_enchantment_tint = (
		PixelObjectLayerScript.enchantment_color_for(int(data.rarity)) if enchanted else Color.WHITE
	)
	var notes: Array[String] = []
	if not has_authored_visual:
		notes.append("Catalog fallback shown: no object art is registered for '%s'." % visual_id)
	if enchanted:
		var overlay_texture: Texture2D = OBJECT_VISUAL_CATALOG.get_enchantment_overlay()
		enchantment_sprite.texture = overlay_texture
		enchantment_sprite.visible = overlay_texture != null
		if overlay_texture == null:
			notes.append("Enchantment overlay unavailable; base catalog art is shown.")
	alt_text.text = _alt_text(data.display_name, data.glyph)
	fallback_note.text = " ".join(notes)
	_animation_time = 0.0
	set_process(_has_enchantment and not _reduced_vfx_enabled)
	_layout_sprite_nodes()
	_apply_object_motion()


func _reset_visuals() -> void:
	set_process(false)
	_animation_time = 0.0
	_has_enchantment = false
	_enchantment_tint = Color.WHITE
	actor_sprite.stop()
	actor_sprite.sprite_frames = null
	actor_sprite.visible = false
	actor_sprite.position = _base_sprite_position
	object_sprite.texture = null
	object_sprite.visible = false
	object_sprite.position = _base_sprite_position
	enchantment_sprite.texture = null
	enchantment_sprite.visible = false
	enchantment_sprite.position = _base_sprite_position
	enchantment_sprite.modulate = Color.WHITE


func _layout_sprite_nodes() -> void:
	if not is_node_ready():
		return
	var usable_size: Vector2 = Vector2(
		maxf(PREVIEW_INSET, preview_stage.size.x - PREVIEW_INSET),
		maxf(PREVIEW_INSET, preview_stage.size.y - PREVIEW_INSET)
	)
	var frame_width: float = maxf(1.0, float(_current_frame_size.x))
	var frame_height: float = maxf(1.0, float(_current_frame_size.y))
	var integer_scale: int = maxi(
		1, floori(minf(usable_size.x / frame_width, usable_size.y / frame_height))
	)
	var pixel_scale: Vector2 = Vector2.ONE * float(integer_scale)
	_base_sprite_position = (preview_stage.size * 0.5).floor()
	actor_sprite.scale = pixel_scale
	actor_sprite.position = _base_sprite_position
	object_sprite.scale = pixel_scale
	enchantment_sprite.scale = pixel_scale
	_apply_object_motion()


func _apply_object_motion() -> void:
	if not is_node_ready():
		return
	var bob_offset: float = 0.0
	var overlay_alpha: float = 1.0
	if _has_enchantment:
		if _reduced_vfx_enabled:
			overlay_alpha = (
				PixelObjectLayerScript.ENCHANTMENT_OVERLAY_ALPHA * STATIC_OVERLAY_ALPHA_MULTIPLIER
			)
		else:
			bob_offset = roundf(
				(
					sin(_animation_time * PixelObjectLayerScript.BOB_SPEED * TAU)
					* PixelObjectLayerScript.BOB_AMPLITUDE
				)
			)
			var pulse: float = sin(_animation_time * PixelObjectLayerScript.ENCHANTMENT_PULSE_SPEED)
			overlay_alpha = (
				PixelObjectLayerScript.ENCHANTMENT_OVERLAY_ALPHA
				* (PULSE_MINIMUM_MULTIPLIER + PULSE_RANGE_MULTIPLIER * (pulse * 0.5 + 0.5))
			)
	var display_position: Vector2 = _base_sprite_position + Vector2(0.0, bob_offset)
	object_sprite.position = display_position
	enchantment_sprite.position = display_position
	enchantment_sprite.modulate = Color(
		_enchantment_tint.r,
		_enchantment_tint.g,
		_enchantment_tint.b,
		overlay_alpha,
	)


func _actor_has_visual(snapshot: Dictionary) -> bool:
	return ACTOR_VISUAL_CATALOG.tint_for(snapshot) != Color(1.0, 0.0, 1.0, 1.0)


func _alt_text(display_name: String, glyph: String) -> String:
	return "Pixel preview: %s — ASCII glyph '%s'." % [display_name, glyph]
