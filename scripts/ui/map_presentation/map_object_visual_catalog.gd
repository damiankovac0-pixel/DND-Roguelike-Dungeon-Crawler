class_name MapObjectVisualCatalog
extends Resource
## Explicit atlas mapping for items, containers, props, and traps.
##
## Gameplay supplies semantic visual IDs. Runtime lookup never scans directories
## or constructs resource paths.

# === Constants ===
const CELL_SIZE: Vector2i = Vector2i(16, 16)
const ATLAS_SIZE: Vector2i = Vector2i(256, 16)
const FALLBACK_COORDS: Vector2i = Vector2i(15, 0)
const ATLAS_COORDS: Dictionary = {
	&"item/consumable": Vector2i(0, 0),
	&"item/weapon": Vector2i(1, 0),
	&"item/armor": Vector2i(2, 0),
	&"item/accessory": Vector2i(3, 0),
	&"item/generic": Vector2i(4, 0),
	&"prop/chest": Vector2i(5, 0),
	&"prop/boss_chest": Vector2i(6, 0),
	&"prop/vase": Vector2i(7, 0),
	&"prop/box": Vector2i(8, 0),
	&"trap/damage": Vector2i(9, 0),
	&"trap/poison": Vector2i(10, 0),
	&"trap/teleport": Vector2i(11, 0),
	&"trap/alarm": Vector2i(12, 0),
	&"trap/stun": Vector2i(13, 0),
	&"trap/ambush": Vector2i(14, 0),
	&"prop/generic": FALLBACK_COORDS,
	&"trap/generic": FALLBACK_COORDS,
}

# === Exports ===
@export var object_atlas: Texture2D
@export var prototype: bool = true
@export var attribution: String = "Project-authored deterministic Phase 4 prototype"


# === Public Methods ===
func validate() -> String:
	if object_atlas == null:
		return "Pixel object atlas is missing"
	if Vector2i(object_atlas.get_size()) != ATLAS_SIZE:
		return "Pixel object atlas must be exactly 256x16"
	return ""


func get_atlas() -> Texture2D:
	return object_atlas


func region_for(visual_id: StringName) -> Rect2:
	var atlas_coords: Vector2i = ATLAS_COORDS.get(visual_id, FALLBACK_COORDS)
	return Rect2(Vector2(atlas_coords * CELL_SIZE), Vector2(CELL_SIZE))


func has_visual(visual_id: StringName) -> bool:
	return ATLAS_COORDS.has(visual_id)
