class_name MapObjectVisualCatalog
extends Resource
## Explicit atlas mapping for items, containers, props, and traps.
##
## Gameplay supplies semantic visual IDs. Runtime lookup never scans directories
## or constructs resource paths.

# === Constants ===
const CELL_SIZE: Vector2i = Vector2i(16, 16)
const ATLAS_SIZE: Vector2i = Vector2i(448, 16)
const FALLBACK_COORDS: Vector2i = Vector2i(16, 0)
const ATLAS_COORDS: Dictionary = {
	# === Exact IDs (columns 0–27) ===
	&"item/potion": Vector2i(0, 0),
	&"item/elixir": Vector2i(1, 0),
	&"item/scroll": Vector2i(2, 0),
	&"item/sword": Vector2i(3, 0),
	&"item/axe": Vector2i(4, 0),
	&"item/dagger": Vector2i(5, 0),
	&"item/mace": Vector2i(6, 0),
	&"item/spear": Vector2i(7, 0),
	&"item/bow": Vector2i(8, 0),
	&"item/crossbow": Vector2i(9, 0),
	&"item/staff": Vector2i(10, 0),
	&"item/armor/light": Vector2i(11, 0),
	&"item/armor/heavy": Vector2i(12, 0),
	&"item/robe": Vector2i(13, 0),
	&"item/ring": Vector2i(14, 0),
	&"item/charm": Vector2i(15, 0),
	&"item/generic": FALLBACK_COORDS,
	&"prop/chest": Vector2i(17, 0),
	&"prop/boss_chest": Vector2i(18, 0),
	&"prop/vase": Vector2i(19, 0),
	&"prop/box": Vector2i(20, 0),
	&"prop/generic": Vector2i(21, 0),
	&"trap/damage": Vector2i(22, 0),
	&"trap/poison": Vector2i(23, 0),
	&"trap/teleport": Vector2i(24, 0),
	&"trap/alarm": Vector2i(25, 0),
	&"trap/stun": Vector2i(26, 0),
	&"trap/ambush": Vector2i(27, 0),
	# === Compatibility aliases ===
	&"item/consumable": Vector2i(0, 0),
	&"item/weapon": Vector2i(3, 0),
	&"item/armor": Vector2i(11, 0),
	&"item/accessory": Vector2i(14, 0),
	&"trap/generic": Vector2i(22, 0),
}

# === Exports ===
@export var catalog_version: int = 2
@export var object_atlas: Texture2D
@export var prototype: bool = false
@export var attribution: String = "Project-authored production object visual catalog."


# === Public Methods ===
func validate() -> String:
	if catalog_version != 2:
		return "Unsupported map object visual catalogue version"
	if object_atlas == null:
		return "Pixel object atlas is missing"
	if Vector2i(object_atlas.get_size()) != ATLAS_SIZE:
		return "Pixel object atlas must be exactly 448x16"
	if attribution.strip_edges().is_empty():
		return "Pixel object atlas attribution is missing"
	return ""


func get_atlas() -> Texture2D:
	return object_atlas


func region_for(visual_id: StringName) -> Rect2:
	var atlas_coords: Vector2i = ATLAS_COORDS.get(visual_id, FALLBACK_COORDS)
	return Rect2(Vector2(atlas_coords * CELL_SIZE), Vector2(CELL_SIZE))


func has_visual(visual_id: StringName) -> bool:
	return ATLAS_COORDS.has(visual_id)
