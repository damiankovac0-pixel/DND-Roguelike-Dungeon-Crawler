class_name MapVisualCatalog
extends Resource
## Explicit resources and atlas mapping for pixel-map terrain.
##
## Runtime lookup is catalogue-based; no directory enumeration or filename
## construction is used.

# === Constants ===
const DungeonDataScript: GDScript = preload("res://scripts/dungeon/dungeon_data.gd")
const TILE_SIZE: Vector2i = Vector2i(16, 16)
const ATLAS_SIZE: Vector2i = Vector2i(112, 16)
const TILE_SOURCE_ID: int = 0
const TILE_ATLAS_COORDS: Dictionary = {
	DungeonDataScript.TileType.FLOOR: Vector2i(0, 0),
	DungeonDataScript.TileType.WALL: Vector2i(1, 0),
	DungeonDataScript.TileType.DOOR: Vector2i(2, 0),
	DungeonDataScript.TileType.OPEN_DOOR: Vector2i(3, 0),
	DungeonDataScript.TileType.STAIRS_DOWN: Vector2i(4, 0),
	DungeonDataScript.TileType.BOSS_DOOR: Vector2i(5, 0),
	DungeonDataScript.TileType.SEALED_BOSS_DOOR: Vector2i(6, 0),
}

# === Exports ===
@export var catalog_version: int = 1
@export var tile_atlas: Texture2D
@export var prototype: bool = false
@export var attribution: String = "Project-authored production map visual catalog."


# === Public Methods ===
func validate() -> String:
	if catalog_version != 1:
		return "Unsupported map visual catalogue version"
	if tile_atlas == null:
		return "Pixel tile atlas is missing"
	if Vector2i(tile_atlas.get_size()) != ATLAS_SIZE:
		return "Pixel tile atlas must be exactly 112x16"
	if attribution.strip_edges().is_empty():
		return "Pixel tile atlas attribution is missing"
	return ""


func create_tile_set() -> TileSet:
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = TILE_SIZE
	var atlas_source: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas_source.texture = tile_atlas
	atlas_source.texture_region_size = TILE_SIZE
	for atlas_value: Variant in TILE_ATLAS_COORDS.values():
		if atlas_value is Vector2i:
			atlas_source.create_tile(atlas_value)
	tile_set.add_source(atlas_source, TILE_SOURCE_ID)
	return tile_set


func atlas_coords_for_tile(tile_type: int) -> Vector2i:
	var atlas_value: Variant = TILE_ATLAS_COORDS.get(
		tile_type, TILE_ATLAS_COORDS[DungeonDataScript.TileType.FLOOR]
	)
	return atlas_value if atlas_value is Vector2i else Vector2i.ZERO


func is_structure_tile(tile_type: int) -> bool:
	return tile_type != DungeonDataScript.TileType.FLOOR
