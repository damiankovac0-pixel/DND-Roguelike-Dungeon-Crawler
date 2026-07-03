## Permanent test harness for V11 visual biome floor bands and glyph flavor.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_biome_themes.gd
##
## Verifies biome floor mapping, dungeon view theme assignment, HUD labeling,
## centered biome entry title text, and biome-specific glyph/decor keys.
extends SceneTree

const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_catalog_mapping()
	_check_theme_glyphs()
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	_check_game_theme(game, 1, "The Tower")
	for _index: int in range(5):
		game._debug_descend_deeper()
		await process_frame
	_check_game_theme(game, 6, "The Rotting Garden")
	game._generate_floor(26)
	await process_frame
	_check_game_theme(game, 26, "Endless Deeps")
	_check_map_tile_glyphs(game)
	print("biome theme check passed")
	quit(0)


func _check_catalog_mapping() -> void:
	_check_equal(BiomeCatalogScript.biome_index_for_floor(1), 1, "floor 1 biome")
	_check_equal(BiomeCatalogScript.biome_index_for_floor(5), 1, "floor 5 biome")
	_check_equal(BiomeCatalogScript.biome_index_for_floor(6), 2, "floor 6 biome")
	_check_equal(BiomeCatalogScript.biome_index_for_floor(25), 5, "floor 25 biome")
	_check_equal(BiomeCatalogScript.biome_index_for_floor(26), 6, "floor 26 biome")
	_check_equal(BiomeCatalogScript.biome_index_for_floor(99), 6, "floor 99 biome")
	var tower_theme: Dictionary = BiomeCatalogScript.theme_for_floor(1)
	var garden_theme: Dictionary = BiomeCatalogScript.theme_for_floor(6)
	_check_equal(tower_theme.get("name", ""), "The Tower", "tower biome name")
	_check_equal(garden_theme.get("name", ""), "The Rotting Garden", "rotting garden biome name")
	var tower_foreground: Dictionary = tower_theme.get("tile_foreground_colors", {})
	var garden_foreground: Dictionary = garden_theme.get("tile_foreground_colors", {})
	_check_equal(
		tower_foreground.get(DungeonDataScript.TileType.FLOOR),
		Color(0.68, 0.67, 0.70),
		"tower floor color stays silver-gray"
	)
	if (
		garden_foreground.get(DungeonDataScript.TileType.FLOOR)
		== tower_foreground.get(DungeonDataScript.TileType.FLOOR)
	):
		_fail("biome 2 floor color matches The Tower")


func _check_game_theme(game: Node, expected_floor: int, expected_name: String) -> void:
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing during theme check")
		return
	_check_equal(game_manager.current_floor, expected_floor, "current floor")
	var map_view: Node = game.get_node("MapView")
	var map_theme: Dictionary = map_view._biome_theme
	_check_equal(map_theme.get("name", ""), expected_name, "map biome theme")
	var title_label: Label = game.get_node("UI/BiomeOverlay/Center/Panel/Margin/VBox/TitleLabel")
	_check_equal(title_label.text, expected_name, "biome title text")
	var hud_floor_label: Label = game.get_node("UI/HUD/Margin/VBox/FloorLabel")
	if not hud_floor_label.text.contains(expected_name):
		_fail("HUD floor label missing %s: %s" % [expected_name, hud_floor_label.text])


func _check_theme_glyphs() -> void:
	# Every theme must have non-empty floor/wall glyph arrays and decoration chance keys
	for theme_index: int in range(BiomeCatalogScript.MAX_BIOME_INDEX):
		var theme: Dictionary = BiomeCatalogScript.THEMES[theme_index]
		var theme_name: String = theme.get("name", "unknown_%d" % theme_index)

		var floor_glyphs: Variant = theme.get("floor_glyphs")
		if not (floor_glyphs is Array) or floor_glyphs.is_empty():
			_fail("%s theme: floor_glyphs missing or empty" % theme_name)
			return

		var wall_glyphs: Variant = theme.get("wall_glyphs")
		if not (wall_glyphs is Array) or wall_glyphs.is_empty():
			_fail("%s theme: wall_glyphs missing or empty" % theme_name)
			return

		if not theme.has("floor_decoration_chance_percent"):
			_fail("%s theme: floor_decoration_chance_percent missing" % theme_name)
			return
		if not (theme.get("floor_decoration_chance_percent") is int):
			_fail("%s theme: floor_decoration_chance_percent not integer" % theme_name)
			return
		if theme.get("floor_decoration_chance_percent") < 0:
			_fail("%s theme: floor_decoration_chance_percent negative" % theme_name)
			return

		if not theme.has("wall_decoration_chance_percent"):
			_fail("%s theme: wall_decoration_chance_percent missing" % theme_name)
			return
		if not (theme.get("wall_decoration_chance_percent") is int):
			_fail("%s theme: wall_decoration_chance_percent not integer" % theme_name)
			return
		if theme.get("wall_decoration_chance_percent") < 0:
			_fail("%s theme: wall_decoration_chance_percent negative" % theme_name)
			return

	print("  theme glyphs: all %d themes have non-empty floor/wall glyphs and decoration chance keys" % BiomeCatalogScript.MAX_BIOME_INDEX)


func _check_map_tile_glyphs(game: Node) -> void:
	var map_view: Node = game.get_node("MapView")
	if map_view == null:
		_fail("MapView missing from game scene")
		return

	var test_cell: Vector2i = Vector2i(5, 3)
	var wall_cell: Vector2i = Vector2i(5, 3)

	# 1) With current Endless theme, floor glyph belongs to Endless set
	var endless_theme: Dictionary = map_view._biome_theme
	var endless_floor_glyph: String = map_view._tile_glyph(test_cell, DungeonDataScript.TileType.FLOOR, false)
	var endless_wall_glyph: String = map_view._tile_glyph(wall_cell, DungeonDataScript.TileType.WALL, false)

	var endless_floor_set: Array = endless_theme.get("floor_glyphs", [])
	var endless_floor_dec_set: Array = endless_theme.get("floor_decoration_glyphs", [])
	var endless_wall_set: Array = endless_theme.get("wall_glyphs", [])
	var endless_wall_dec_set: Array = endless_theme.get("wall_decoration_glyphs", [])

	var floor_ok: bool = (
		endless_floor_set.has(endless_floor_glyph)
		or endless_floor_dec_set.has(endless_floor_glyph)
	)
	if not floor_ok:
		_fail(
			(
				"Endless floor glyph '%s' not in floor_glyphs %s or floor_decoration_glyphs %s"
				% [endless_floor_glyph, str(endless_floor_set), str(endless_floor_dec_set)]
			)
		)
		return

	var wall_ok: bool = (
		endless_wall_set.has(endless_wall_glyph)
		or endless_wall_dec_set.has(endless_wall_glyph)
	)
	if not wall_ok:
		_fail(
			(
				"Endless wall glyph '%s' not in wall_glyphs %s or wall_decoration_glyphs %s"
				% [endless_wall_glyph, str(endless_wall_set), str(endless_wall_dec_set)]
			)
		)
		return

	# 2) Switch to Tower theme — glyph for same cell should come from Tower set
	var tower_theme: Dictionary = BiomeCatalogScript.theme_for_floor(1)
	map_view.set_biome_theme(tower_theme)
	var tower_floor_glyph: String = map_view._tile_glyph(test_cell, DungeonDataScript.TileType.FLOOR, false)
	var tower_floor_set: Array = tower_theme.get("floor_glyphs", [])
	var tower_floor_dec_set: Array = tower_theme.get("floor_decoration_glyphs", [])

	var tower_floor_ok: bool = (
		tower_floor_set.has(tower_floor_glyph)
		or tower_floor_dec_set.has(tower_floor_glyph)
	)
	if not tower_floor_ok:
		_fail(
			(
				"Tower floor glyph '%s' not in floor_glyphs %s or floor_decoration_glyphs %s"
				% [tower_floor_glyph, str(tower_floor_set), str(tower_floor_dec_set)]
			)
		)
		return

	print("  tile glyph: MapView returns biome-specific glyphs for Endless and Tower themes")


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s got %s, expected %s" % [label, str(actual), str(expected)])


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
