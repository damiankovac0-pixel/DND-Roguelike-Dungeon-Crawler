class_name MapVisualCatalog
extends Resource
## Explicit resources and atlas mapping for pixel-map terrain.
##
## Runtime lookup is catalogue-based; no directory enumeration or filename
## construction is used.

# === Constants ===
const DungeonDataScript: GDScript = preload("res://scripts/dungeon/dungeon_data.gd")
const TILE_SIZE: Vector2i = Vector2i(16, 16)
const ATLAS_SIZE: Vector2i = Vector2i(208, 96)
## Atlas grid: 13 columns × 6 rows, 16px cells.
##   Rows: 0=Tower, 1=Garden, 2=Cinder, 3=Sunken, 4=Glass, 5=Deeps
##   Columns: 0-3=floor_a..floor_d, 4-6=wall_a..wall_c,
##            7=door_closed, 8=door_open, 9=stairs_down,
##            10=boss_door, 11=boss_door_sealed,
##            12=wall_cracked
## Base coordinate for each tile type in row 0 (Tower). Variant
## selection adjusts the column for floors (0-3) and walls (4-6)
## using a deterministic cell hash.
const TILE_ATLAS_COORDS: Dictionary = {
	DungeonDataScript.TileType.FLOOR: Vector2i(0, 0),
	DungeonDataScript.TileType.WALL: Vector2i(4, 0),
	DungeonDataScript.TileType.DOOR: Vector2i(7, 0),
	DungeonDataScript.TileType.OPEN_DOOR: Vector2i(8, 0),
	DungeonDataScript.TileType.STAIRS_DOWN: Vector2i(9, 0),
	DungeonDataScript.TileType.BOSS_DOOR: Vector2i(10, 0),
	DungeonDataScript.TileType.SEALED_BOSS_DOOR: Vector2i(11, 0),
}
const FLOOR_VARIANT_SALT: int = 12347
const WALL_VARIANT_SALT: int = 67891
const CATALOG_VERSION: int = 2
const TILE_SOURCE_ID: int = 0
const ATLAS_COLUMNS: int = 13
const ATLAS_ROWS: int = 6
const WALL_CRACKED_COLUMN: int = 12

# === Exports ===
@export var catalog_version: int = CATALOG_VERSION
@export var tile_atlas: Texture2D
@export var prototype: bool = false
@export var attribution: String = "Project-authored production map visual catalog."


# === Public Methods ===
func validate() -> String:
	if catalog_version != CATALOG_VERSION:
		return "Unsupported map visual catalogue version"
	if tile_atlas == null:
		return "Pixel tile atlas is missing"
	if Vector2i(tile_atlas.get_size()) != ATLAS_SIZE:
		return "Pixel tile atlas must be exactly 208x96"
	if attribution.strip_edges().is_empty():
		return "Pixel tile atlas attribution is missing"
	return ""


func create_tile_set() -> TileSet:
	var tile_set: TileSet = TileSet.new()
	tile_set.tile_size = TILE_SIZE
	var atlas_source: TileSetAtlasSource = TileSetAtlasSource.new()
	atlas_source.texture = tile_atlas
	atlas_source.texture_region_size = TILE_SIZE
	for column: int in ATLAS_COLUMNS:
		for row: int in ATLAS_ROWS:
			atlas_source.create_tile(Vector2i(column, row))
	tile_set.add_source(atlas_source, TILE_SOURCE_ID)
	return tile_set


## Returns the atlas coordinate for the given tile type.
## When biome_row (0-based, clamped 0-5) and cell are provided, floors
## select a variant column (0-3) and walls select column 4-6 via
## deterministic cell hash. Structures use fixed columns 7-11.
## The one-argument fallback resolves to row 0 (Tower) with no variant.
func atlas_coords_for_tile(
	tile_type: int, biome_row: int = 0, cell: Vector2i = Vector2i.ZERO
) -> Vector2i:
	var base: Variant = TILE_ATLAS_COORDS.get(
		tile_type, TILE_ATLAS_COORDS[DungeonDataScript.TileType.FLOOR]
	)
	if not (base is Vector2i):
		return Vector2i.ZERO
	var row: int = clampi(biome_row, 0, ATLAS_ROWS - 1)
	if cell == Vector2i.ZERO:
		return Vector2i(base.x, row)
	if tile_type == DungeonDataScript.TileType.FLOOR:
		var variant: int = _cell_variant_hash(cell, FLOOR_VARIANT_SALT) % 4
		return Vector2i(variant, row)
	if tile_type == DungeonDataScript.TileType.WALL:
		var variant: int = _cell_variant_hash(cell, WALL_VARIANT_SALT) % 3
		return Vector2i(4 + variant, row)
	return Vector2i(base.x, row)


## Column is always 12 (WALL_CRACKED_COLUMN); row is clamped to valid range.
func atlas_coords_for_cracked_wall(biome_row: int) -> Vector2i:
	return Vector2i(WALL_CRACKED_COLUMN, clampi(biome_row, 0, ATLAS_ROWS - 1))


static func _cell_variant_hash(cell: Vector2i, salt: int) -> int:
	return absi(cell.x * 73856093 + cell.y * 19349663 + salt * 83492791)


func is_structure_tile(tile_type: int) -> bool:
	return tile_type != DungeonDataScript.TileType.FLOOR
