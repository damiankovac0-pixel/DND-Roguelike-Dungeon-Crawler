## Tile type enum, map dimensions, glyph/color tables, and walkable/opaque helpers.
extends Node
class_name DungeonData

enum TileType {
	FLOOR,
	WALL,
	DOOR,
	OPEN_DOOR,
	STAIRS_DOWN,
}

const TILE_COLORS: Dictionary = {
	TileType.FLOOR: Color(0.72, 0.70, 0.62),
	TileType.WALL: Color(0.42, 0.36, 0.50),
	TileType.DOOR: Color(0.82, 0.57, 0.30),
	TileType.OPEN_DOOR: Color(0.63, 0.52, 0.39),
	TileType.STAIRS_DOWN: Color(1.0, 0.88, 0.47),
}

const TILE_CHARS: Dictionary = {
	TileType.FLOOR: ".",
	TileType.WALL: "#",
	TileType.DOOR: "+",
	TileType.OPEN_DOOR: "/",
	TileType.STAIRS_DOWN: ">",
}

const CELL_SIZE: int = 20
const MAP_WIDTH: int = 48
const MAP_HEIGHT: int = 32


static func is_walkable(tile: TileType) -> bool:
	return tile == TileType.FLOOR or tile == TileType.OPEN_DOOR or tile == TileType.STAIRS_DOWN


static func is_opaque(tile: TileType) -> bool:
	return tile == TileType.WALL or tile == TileType.DOOR


static func create_tileset() -> TileSet:
	var num_tiles: int = TileType.size()
	var image: Image = Image.create(CELL_SIZE * num_tiles, CELL_SIZE, false, Image.FORMAT_RGBA8)
	for i in num_tiles:
		var color: Color = TILE_COLORS[i]
		for x in CELL_SIZE:
			for y in CELL_SIZE:
				image.set_pixel(i * CELL_SIZE + x, y, color)

	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var source: TileSetAtlasSource = TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(CELL_SIZE, CELL_SIZE)

	var tileset: TileSet = TileSet.new()
	tileset.tile_size = Vector2i(CELL_SIZE, CELL_SIZE)
	tileset.add_source(source, 0)

	for i in num_tiles:
		source.create_tile(Vector2i(i, 0))

	return tileset
