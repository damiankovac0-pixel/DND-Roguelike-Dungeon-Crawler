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
	var used_wall_glyphs: Dictionary = {}
	var passed := true
	for theme_index: int in range(BiomeCatalogScript.MAX_BIOME_INDEX):
		var theme: Dictionary = BiomeCatalogScript.THEMES[theme_index]
		var theme_name: String = theme.get("name", "unknown_%d" % theme_index)

		var floor_glyphs: Variant = theme.get("floor_glyphs")
		if not (floor_glyphs is Array) or floor_glyphs.is_empty():
			_fail("%s theme: floor_glyphs missing or empty" % theme_name)
			passed = false
			break

		if not _check_theme_wall_glyphs(theme_name, theme.get("wall_glyphs"), used_wall_glyphs):
			passed = false
			break
		if not _check_decoration_chance(theme, theme_name, "floor_decoration_chance_percent"):
			passed = false
			break
		if not _check_decoration_chance(theme, theme_name, "wall_decoration_chance_percent"):
			passed = false
			break

	if passed:
		print(
			(
				(
					"  theme glyphs: all %d themes have exactly three printable ASCII wall glyphs "
					+ "(pairwise disjoint), floor glyphs, and decoration chance keys"
				)
				% BiomeCatalogScript.MAX_BIOME_INDEX
			)
		)


func _check_theme_wall_glyphs(
	theme_name: String, wall_glyphs: Variant, used_wall_glyphs: Dictionary
) -> bool:
	var passed := true
	if not (wall_glyphs is Array):
		_fail("%s theme: wall_glyphs missing" % theme_name)
		passed = false
	elif wall_glyphs.size() != 3:
		_fail(
			"%s wall_glyphs must have exactly 3 glyphs, got %d" % [theme_name, wall_glyphs.size()]
		)
		passed = false
	else:
		for glyph_value: Variant in wall_glyphs:
			var glyph: String = str(glyph_value)
			if glyph.length() != 1:
				_fail("%s wall_glyphs contains multi-character entry '%s'" % [theme_name, glyph])
				passed = false
				break
			var code: int = glyph.unicode_at(0)
			if code < 32 or code > 126:
				_fail(
					(
						"%s wall_glyphs contains non-printable glyph '%s' (code %d)"
						% [theme_name, glyph, code]
					)
				)
				passed = false
				break
			if used_wall_glyphs.has(glyph):
				_fail(
					(
						"%s wall_glyphs glyph '%s' reused from %s"
						% [theme_name, glyph, used_wall_glyphs[glyph]]
					)
				)
				passed = false
				break
			used_wall_glyphs[glyph] = theme_name
	return passed


func _check_decoration_chance(theme: Dictionary, theme_name: String, key: String) -> bool:
	var passed := true
	if not theme.has(key):
		_fail("%s theme: %s missing" % [theme_name, key])
		passed = false
	elif not (theme.get(key) is int):
		_fail("%s theme: %s not integer" % [theme_name, key])
		passed = false
	elif theme.get(key) < 0:
		_fail("%s theme: %s negative" % [theme_name, key])
		passed = false
	return passed


func _check_map_tile_glyphs(game: Node) -> void:
	var map_view: Node = game.get_node("MapView")
	if map_view == null:
		_fail("MapView missing from game scene")
	else:
		var test_cell: Vector2i = Vector2i(5, 3)
		var wall_cell: Vector2i = Vector2i(5, 3)
		var passed := true

		# 1) With current Endless theme, floor glyph belongs to Endless set
		var endless_theme: Dictionary = map_view._biome_theme
		var endless_floor_glyph: String = map_view._tile_glyph(
			test_cell, DungeonDataScript.TileType.FLOOR, false
		)
		var endless_wall_glyph: String = map_view._tile_glyph(
			wall_cell, DungeonDataScript.TileType.WALL, false
		)

		var endless_floor_set: Array = endless_theme.get("floor_glyphs", [])
		var endless_floor_dec_set: Array = endless_theme.get("floor_decoration_glyphs", [])
		passed = _check_tile_glyph_membership(
			"Endless floor",
			endless_floor_glyph,
			"floor_glyphs",
			endless_floor_set,
			"floor_decoration_glyphs",
			endless_floor_dec_set
		)

		if passed:
			var endless_wall_set: Array = endless_theme.get("wall_glyphs", [])
			var endless_wall_dec_set: Array = endless_theme.get("wall_decoration_glyphs", [])
			passed = _check_tile_glyph_membership(
				"Endless wall",
				endless_wall_glyph,
				"wall_glyphs",
				endless_wall_set,
				"wall_decoration_glyphs",
				endless_wall_dec_set
			)

		# 2) Switch to Tower theme — glyph for same cell should come from Tower set
		var tower_theme: Dictionary = {}
		if passed:
			tower_theme = BiomeCatalogScript.theme_for_floor(1)
			map_view.set_biome_theme(tower_theme)
			var tower_floor_glyph: String = map_view._tile_glyph(
				test_cell, DungeonDataScript.TileType.FLOOR, false
			)
			var tower_floor_set: Array = tower_theme.get("floor_glyphs", [])
			var tower_floor_dec_set: Array = tower_theme.get("floor_decoration_glyphs", [])
			passed = _check_tile_glyph_membership(
				"Tower floor",
				tower_floor_glyph,
				"floor_glyphs",
				tower_floor_set,
				"floor_decoration_glyphs",
				tower_floor_dec_set
			)

		if passed:
			# 3) Each biome's wall glyph sample belongs to its own set
			for biome_theme: Dictionary in BiomeCatalogScript.THEMES:
				map_view.set_biome_theme(biome_theme)
				if not _check_biome_wall_tile_glyph(map_view, wall_cell, biome_theme):
					passed = false
					break

		if passed:
			# 4) Tower fallback — a theme lacking wall_glyphs returns Tower glyphs at runtime
			var tower_wall_set: Array = tower_theme.get("wall_glyphs", [])
			passed = _check_tower_fallback_wall_glyph(map_view, wall_cell, tower_wall_set)

		if passed:
			print(
				(
					"  tile glyph: MapView returns biome-specific wall glyphs for all six biomes; "
					+ "Tower fallback works at runtime"
				)
			)


func _check_tile_glyph_membership(
	label: String,
	glyph: String,
	primary_key: String,
	primary_set: Array,
	decoration_key: String,
	decoration_set: Array
) -> bool:
	var passed := true
	if not (primary_set.has(glyph) or decoration_set.has(glyph)):
		_fail(
			(
				"%s glyph '%s' not in %s %s or %s %s"
				% [
					label,
					glyph,
					primary_key,
					str(primary_set),
					decoration_key,
					str(decoration_set),
				]
			)
		)
		passed = false
	return passed


func _check_biome_wall_tile_glyph(
	map_view: Node, wall_cell: Vector2i, biome_theme: Dictionary
) -> bool:
	var biome_wall_glyph: String = map_view._tile_glyph(
		wall_cell, DungeonDataScript.TileType.WALL, false
	)
	var biome_name: String = biome_theme.get("name", "unknown")
	var biome_wall_set: Array = biome_theme.get("wall_glyphs", [])
	var biome_wall_dec_set: Array = biome_theme.get("wall_decoration_glyphs", [])
	return _check_tile_glyph_membership(
		"%s wall" % biome_name,
		biome_wall_glyph,
		"wall_glyphs",
		biome_wall_set,
		"wall_decoration_glyphs",
		biome_wall_dec_set
	)


func _check_tower_fallback_wall_glyph(
	map_view: Node, wall_cell: Vector2i, tower_wall_set: Array
) -> bool:
	var fallback_theme: Dictionary = {"name": "Wall-less Test"}
	map_view.set_biome_theme(fallback_theme)
	var fallback_glyph: String = map_view._tile_glyph(
		wall_cell, DungeonDataScript.TileType.WALL, false
	)
	var passed := true
	if not tower_wall_set.has(fallback_glyph):
		_fail(
			"fallback wall glyph '%s' not in Tower set %s" % [fallback_glyph, str(tower_wall_set)]
		)
		passed = false
	return passed


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s got %s, expected %s" % [label, str(actual), str(expected)])


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
