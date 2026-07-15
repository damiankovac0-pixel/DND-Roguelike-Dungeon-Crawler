## Regression coverage for grid layout, state replay, and pixel rendering.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##     res://scripts/tests/test_pixel_renderer_foundation.gd
extends SceneTree

const PRESENTATION_DIR: String = "res://scripts/ui/map_presentation/"
const GRID_LAYOUT_PATH: String = PRESENTATION_DIR + "map_grid_layout.gd"
const STATE_PATH: String = PRESENTATION_DIR + "map_presentation_state.gd"
const CONTROLLER_PATH: String = PRESENTATION_DIR + "map_presentation_controller.gd"
const MAP_VIEW_PATH: String = "res://scripts/ui/map_view.gd"
const PIXEL_RENDERER_SCENE_PATH: String = "res://scenes/rendering/pixel_map_renderer.tscn"
const PREFERRED_SCALES: Array[int] = [3, 2, 1]


class FakeActor:
	extends Node2D

	var grid_position: Vector2i = Vector2i.ZERO
	var glyph: String = "@"
	var color: Color = Color.WHITE
	var alive: bool = true

	func is_alive() -> bool:
		return alive


class FakeRenderer:
	extends Node2D

	var available: bool = true
	var present_count: int = 0
	var reset_count: int = 0
	var profile: StringName = &""
	var last_state: RefCounted

	func is_renderer_available() -> bool:
		return available

	func set_render_profile(value: StringName) -> void:
		profile = value

	func present(state: RefCounted) -> void:
		last_state = state
		present_count += 1

	func reset_transients() -> void:
		reset_count += 1


var _failed: bool = false
var _grid_script: GDScript
var _state_script: GDScript
var _controller_script: GDScript
var _map_view_script: GDScript


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_dependencies()
	_check_grid_layout()
	_check_adaptive_grid_layout()
	_check_presentation_state()
	_check_controller_replay_and_fallback()
	if _failed:
		return
	await _check_pixel_renderer_scene()
	if _failed:
		return
	await _check_adaptive_pixel_renderer()
	if _failed:
		return
	await _check_map_view_switching()
	if _failed:
		return
	print("Pixel renderer foundation checks passed")
	quit(0)


func _load_dependencies() -> void:
	_grid_script = load(GRID_LAYOUT_PATH)
	_state_script = load(STATE_PATH)
	_controller_script = load(CONTROLLER_PATH)
	_map_view_script = load(MAP_VIEW_PATH)
	for script: GDScript in [_grid_script, _state_script, _controller_script, _map_view_script]:
		_expect(script != null and script.can_instantiate(), "Phase 2 script failed to load")
	var renderer_scene: Resource = load(PIXEL_RENDERER_SCENE_PATH)
	_expect(renderer_scene is PackedScene, "Pixel renderer scene failed to load")


func _check_grid_layout() -> void:
	var layout: RefCounted = _new_layout()
	layout.call(&"set_map_size", Vector2i(48, 32))
	layout.call(&"set_focus_cell", Vector2i(24, 16))
	_expect_equal(
		layout.call(&"get_cell_size"), Vector2i(16, 16), "Pixel layout must use 16x16 cells"
	)
	_expect_equal(
		layout.call(&"get_view_origin_cell"),
		Vector2i(4, 0),
		"Player focus should center the 41-column view"
	)
	_expect_equal(
		layout.call(&"cell_to_local", Vector2i(4, 0)),
		Vector2(20, 44),
		"First visible cell should begin at the map origin"
	)
	_expect_equal(
		layout.call(&"cell_to_local", Vector2i(5, 1)),
		Vector2(36, 60),
		"Cell conversion must advance by renderer-local 16-pixel steps"
	)
	_expect_equal(
		layout.call(&"local_to_cell", Vector2(36, 60)),
		Vector2i(5, 1),
		"Local-to-cell conversion should invert the renderer layout"
	)
	layout.call(&"set_focus_cell", Vector2i(47, 31))
	_expect_equal(
		layout.call(&"get_view_origin_cell"),
		Vector2i(7, 0),
		"View origin should clamp to the 48x32 map bounds"
	)
	_expect(
		bool(layout.call(&"is_cell_in_view", Vector2i(47, 31))),
		"Last map cell should remain inside the clamped view"
	)
	print("  grid layout isolates 16x16 rendering from gameplay world positions")


func _check_adaptive_grid_layout() -> void:
	# === Standard playfield selects 2x ===
	var layout: RefCounted = _grid_script.new()
	layout.call(
		&"configure_adaptive",
		Vector2i(16, 16),
		Vector2(20, 44),
		Vector2(670, 556),
		PREFERRED_SCALES,
		Vector2i(19, 15),
		Vector2i(4, 3)
	)
	_expect_equal(
		layout.call(&"get_base_cell_size"),
		Vector2i(16, 16),
		"Adaptive layout must preserve base cell size"
	)
	_expect_equal(layout.call(&"get_scale"), 2, "Standard 670x556 playfield must select 2x")
	_expect_equal(
		layout.call(&"get_cell_size"),
		Vector2i(32, 32),
		"2x scale must produce 32x32 cells from 16px base"
	)
	_expect_equal(
		layout.call(&"get_view_capacity"),
		Vector2i(20, 17),
		"Capacity must be floor(available / cell_size)"
	)
	_expect_equal(
		layout.call(&"get_slack"),
		Vector2i(30, 12),
		"Slack must be available_pixels - capacity * cell_size"
	)
	_expect_equal(
		layout.call(&"get_edge_padding"), Vector2i(4, 3), "Edge padding must be (4,3) as configured"
	)
	# Origin offset by half slack
	_expect_equal(
		layout.call(&"get_origin"),
		Vector2(35, 50),
		"Origin must be base origin plus half-slack offset"
	)

	# === Large playfield selects 3x ===
	var large_layout: RefCounted = _grid_script.new()
	large_layout.call(
		&"configure_adaptive",
		Vector2i(16, 16),
		Vector2.ZERO,
		Vector2(1000, 800),
		PREFERRED_SCALES,
		Vector2i(19, 15),
		Vector2i(4, 3)
	)
	_expect_equal(large_layout.call(&"get_scale"), 3, "Large 1000x800 playfield must select 3x")
	_expect_equal(
		large_layout.call(&"get_cell_size"), Vector2i(48, 48), "3x must produce 48x48 cells"
	)

	# === Tiny playfield falls back to 1x ===
	var tiny_layout: RefCounted = _grid_script.new()
	tiny_layout.call(
		&"configure_adaptive",
		Vector2i(16, 16),
		Vector2.ZERO,
		Vector2(320, 256),
		PREFERRED_SCALES,
		Vector2i(19, 15),
		Vector2i(4, 3)
	)
	_expect_equal(
		tiny_layout.call(&"get_scale"),
		1,
		"320x256 playfield below minimum 2x capacity must fall back to 1x"
	)
	_expect_equal(
		tiny_layout.call(&"get_cell_size"), Vector2i(16, 16), "1x must keep native 16x16 cells"
	)

	# === Conversions round-trip at adaptive resolution ===
	var conv_layout: RefCounted = _grid_script.new()
	conv_layout.call(
		&"configure_adaptive",
		Vector2i(16, 16),
		Vector2(20, 44),
		Vector2(670, 556),
		PREFERRED_SCALES,
		Vector2i(19, 15),
		Vector2i(4, 3)
	)
	conv_layout.call(&"set_map_size", Vector2i(48, 32))
	conv_layout.call(&"set_focus_cell", Vector2i(24, 16))
	var test_cell: Vector2i = Vector2i(10, 8)
	var local_pos: Vector2 = conv_layout.call(&"cell_to_local", test_cell)
	_expect_equal(
		conv_layout.call(&"local_to_cell", local_pos),
		test_cell,
		"cell_to_local -> local_to_cell must round-trip at 2x"
	)
	_expect_equal(
		conv_layout.call(&"local_to_cell", local_pos + Vector2(15, 15)),
		test_cell,
		"local_to_cell must floor consistently within a 32x32 cell"
	)
	var edge_cell: Vector2i = Vector2i(0, 0)
	_expect_equal(
		conv_layout.call(&"local_to_cell", conv_layout.call(&"cell_to_local", edge_cell)),
		edge_cell,
		"Edge cell (0,0) must round-trip through conversion"
	)
	_expect_equal(
		conv_layout.call(
			&"local_to_cell", conv_layout.call(&"cell_to_local", test_cell) + Vector2(31, 31)
		),
		test_cell,
		"Cell interior offsets must still map to the same cell at 2x"
	)

	# === Small map centering with negative view origin ===
	var center_layout: RefCounted = _grid_script.new()
	center_layout.call(
		&"configure_adaptive",
		Vector2i(16, 16),
		Vector2.ZERO,
		Vector2(670, 556),
		PREFERRED_SCALES,
		Vector2i(19, 15),
		Vector2i(4, 3)
	)
	center_layout.call(&"set_map_size", Vector2i(5, 4))
	center_layout.call(&"set_focus_cell", Vector2i(2, 1))
	var center_origin: Vector2i = center_layout.call(&"get_view_origin_cell")
	_expect(
		center_origin.x < 0 and center_origin.y < 0,
		"Small map focus must produce negative view origin for centering: got %s" % [center_origin]
	)
	_expect(
		bool(center_layout.call(&"is_cell_in_view", Vector2i(0, 0))),
		"First map cell must remain in view with negative origin"
	)
	_expect(
		bool(center_layout.call(&"is_cell_in_view", Vector2i(4, 3))),
		"Last map cell must remain in view with negative origin"
	)

	# === Full-capacity view rect covers capacity regardless of map ===
	var view_rect: Rect2i = center_layout.call(&"get_view_rect")
	_expect_equal(
		view_rect.size,
		center_layout.call(&"get_view_capacity"),
		"View rect must always cover full capacity regardless of map size"
	)
	_expect(
		view_rect.position.x <= 0 and view_rect.position.y <= 0,
		"View rect position must be negative for centered small maps: got %s" % [view_rect.position]
	)

	# === Edge focus honors safe padding ===
	center_layout.call(&"set_map_size", Vector2i(40, 30))
	center_layout.call(&"set_focus_cell", Vector2i(0, 0))
	var edge_origin: Vector2i = center_layout.call(&"get_view_origin_cell")
	_expect(
		edge_origin.x >= -4 and edge_origin.y >= -3,
		"Edge focus at (0,0) must not exceed -edge_padding: got %s" % [edge_origin]
	)
	_expect(
		bool(center_layout.call(&"is_cell_in_view", Vector2i(0, 0))),
		"Map cell (0,0) must be in view at edge focus"
	)
	# Focus at opposite corner of a large map
	center_layout.call(&"set_focus_cell", Vector2i(39, 29))
	_expect(
		bool(center_layout.call(&"is_cell_in_view", Vector2i(39, 29))),
		"Last map cell must be in view at far corner focus"
	)
	var far_origin: Vector2i = center_layout.call(&"get_view_origin_cell")
	var far_end: Vector2i = far_origin + center_layout.call(&"get_view_capacity")
	_expect(
		far_end.x >= 40,
		(
			"View rect must reach map edge at far corner: origin=%s capacity=%s"
			% [far_origin, center_layout.call(&"get_view_capacity")]
		)
	)

	print("  adaptive grid layout selects zoom, centers small maps, and converts deterministically")


func _check_presentation_state() -> void:
	var state: RefCounted = _state_script.new()
	var map_data: Array = [[0, 1, 2], [3, 4, 5]]
	state.call(&"capture_map", map_data)
	state.set(&"visible_cells", {Vector2i(2, 1): true})
	state.set(&"explored_cells", {Vector2i(2, 1): true})
	state.call(&"mark_visibility_changed")
	var player: FakeActor = FakeActor.new()
	player.name = &"Player"
	player.grid_position = Vector2i(2, 1)
	state.call(&"capture_actors", [player])
	_expect_equal(state.get("map_size"), Vector2i(3, 2), "State should derive map dimensions")
	_expect_equal(state.get("focus_cell"), Vector2i(2, 1), "State should focus the player cell")
	_expect_equal(
		int(state.get("actor_revision")), 1, "Capturing actors should advance actor revision"
	)
	var player_snapshot: Dictionary = state.call(&"get_player_snapshot")
	_expect_equal(player_snapshot.get("cell"), Vector2i(2, 1), "Player snapshot cell drifted")
	_expect(
		int(state.get("revision")) >= 3,
		"Map, visibility, and actor changes should advance total revision"
	)
	player.free()
	print("  shared state captures map, visibility, and player cells without renderer math")


func _check_controller_replay_and_fallback() -> void:
	var controller: RefCounted = _controller_script.new()
	var layout: RefCounted = _new_layout()
	var renderer: FakeRenderer = FakeRenderer.new()
	var state: RefCounted = _state_script.new()
	state.call(&"capture_map", [[0]])
	_expect(
		bool(controller.call(&"register_renderer", &"hybrid", renderer, layout)),
		"Controller should register an available Hybrid renderer"
	)
	controller.call(&"present", state)
	controller.call(&"set_requested_mode", &"hybrid")
	_expect_equal(
		controller.call(&"get_effective_mode"),
		&"hybrid",
		"Registered Hybrid renderer should become effective"
	)
	_expect(renderer.visible, "Active Hybrid renderer should be visible")
	_expect_equal(renderer.profile, &"hybrid", "Renderer profile should match effective mode")
	_expect_equal(renderer.present_count, 1, "Activation should replay the cached state once")
	controller.call(&"set_requested_mode", &"hybrid")
	_expect_equal(
		renderer.present_count, 1, "Repeated mode request must not duplicate state replay"
	)
	state.call(&"mark_overlay_changed")
	controller.call(&"present", state)
	_expect_equal(renderer.present_count, 2, "New state should reach the active renderer")
	controller.call(&"set_requested_mode", &"pixel")
	_expect_equal(
		controller.call(&"get_effective_mode"),
		&"ascii",
		"Unregistered Pixel renderer must fall back to ASCII"
	)
	_expect(not renderer.visible, "Hybrid renderer should hide after fallback")
	_expect_equal(renderer.reset_count, 1, "Leaving Hybrid should clear its transients")
	controller.call(&"set_requested_mode", &"hybrid")
	_expect_equal(renderer.present_count, 3, "Returning to Hybrid should replay latest state")
	controller.call(&"unregister_renderer", &"hybrid")
	_expect_equal(
		controller.call(&"get_effective_mode"),
		&"ascii",
		"Removing the active backend should restore ASCII"
	)
	renderer.free()
	print("  controller replays state once and falls back cleanly to ASCII")


func _check_pixel_renderer_scene() -> void:
	var renderer_scene: PackedScene = load(PIXEL_RENDERER_SCENE_PATH)
	var renderer: Node2D = renderer_scene.instantiate()
	root.add_child(renderer)
	await process_frame
	var layout: RefCounted = _new_layout()
	var initialization_error: int = int(renderer.call(&"initialize_renderer", layout))
	_expect_equal(initialization_error, OK, "Prototype pixel renderer should initialize")
	if _failed:
		renderer.queue_free()
		return
	var state: RefCounted = _build_pixel_fixture_state()
	renderer.call(&"present", state)
	await process_frame
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect(bool(debug.get("available", false)), "Pixel renderer should report available")
	_expect_equal(
		debug.get("view_origin"), Vector2i(4, 0), "Pixel renderer should follow player focus"
	)
	_expect_equal(
		int(debug.get("ground_cell_count", 0)),
		41 * 32,
		"Pixel renderer should populate only the visible 41x32 camera window"
	)
	_expect_equal(
		int(debug.get("structure_cell_count", 0)),
		2,
		"Prototype fixture should render wall and door on the structure layer"
	)
	_expect(bool(debug.get("player_visible", false)), "Visible player sprite should render")
	_expect_equal(debug.get("player_cell"), Vector2i(24, 16), "Player sprite cell drifted")
	_expect_equal(
		debug.get("player_position"),
		layout.call(&"cell_center_to_local", Vector2i(24, 16)),
		"Player sprite should use the shared renderer-local layout"
	)
	var ground_count: int = int(debug.get("ground_cell_count", 0))
	renderer.call(&"present", state)
	await process_frame
	debug = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(debug.get("ground_cell_count", 0)),
		ground_count,
		"Replaying identical state must not duplicate TileMapLayer cells"
	)
	await _check_pixel_visibility_updates(renderer, state, ground_count)
	_check_pixel_terrain_update(renderer, state)
	_check_missing_catalog_fallback(renderer_scene, layout)
	_check_visual_catalog_contract(renderer)
	renderer.queue_free()
	await process_frame
	print("  TileMapLayer renders terrain, visibility, and player deterministically")


func _check_pixel_visibility_updates(
	renderer: Node2D, state: RefCounted, original_ground_count: int
) -> void:
	var player_cell: Vector2i = Vector2i(24, 16)
	var visible_cells: Dictionary = Dictionary(state.get("visible_cells")).duplicate()
	visible_cells.erase(player_cell)
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)
	await process_frame
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect(
		not bool(debug.get("player_visible", true)),
		"Player sprite must obey shared visible-cell state",
	)
	visible_cells[player_cell] = true
	var explored_cells: Dictionary = Dictionary(state.get("explored_cells")).duplicate()
	explored_cells.erase(Vector2i(25, 16))
	state.set(&"visible_cells", visible_cells)
	state.set(&"explored_cells", explored_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)
	await process_frame
	debug = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(debug.get("ground_cell_count", 0)),
		original_ground_count - 1,
		"Unexplored cells must not leak terrain into the pixel renderer",
	)
	_expect_equal(
		int(debug.get("structure_cell_count", 0)),
		1,
		"Unexplored structure must be removed with its terrain cell",
	)
	explored_cells[Vector2i(25, 16)] = true
	state.set(&"explored_cells", explored_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)


func _check_pixel_terrain_update(renderer: Node2D, state: RefCounted) -> void:
	var map_data: Array = state.get("map_data")
	map_data[16][26] = 3
	state.call(&"capture_map", map_data)
	renderer.call(&"present", state)
	var structure_layer: TileMapLayer = renderer.get_node("StructureLayer")
	var catalog: Resource = renderer.get("catalog")
	_expect_equal(
		structure_layer.get_cell_atlas_coords(Vector2i(26, 16)),
		catalog.call(&"atlas_coords_for_tile", 3),
		"Door state changes must replace the structure atlas tile",
	)


func _check_missing_catalog_fallback(renderer_scene: PackedScene, layout: RefCounted) -> void:
	var missing_renderer: Node2D = renderer_scene.instantiate()
	missing_renderer.set("catalog", null)
	root.add_child(missing_renderer)
	var initialization_error: int = int(missing_renderer.call(&"initialize_renderer", layout))
	_expect(
		initialization_error != OK,
		"Renderer with a missing essential catalogue must reject activation"
	)
	_expect(
		not bool(missing_renderer.call(&"is_renderer_available")),
		"Missing catalogue renderer must remain unavailable"
	)
	missing_renderer.queue_free()


func _check_visual_catalog_contract(renderer: Node2D) -> void:
	var catalog: Resource = renderer.get("catalog")
	_expect(catalog != null, "Catalog must be set on pixel renderer")

	# Terrain atlas includes twelve base columns plus dedicated cracked walls.
	var tile_atlas: Texture2D = catalog.get("tile_atlas")
	var atlas_size: Vector2i = (
		Vector2i(tile_atlas.get_size()) if tile_atlas != null else Vector2i.ZERO
	)
	_expect_equal(atlas_size, Vector2i(208, 96), "Terrain atlas must be exactly 208x96")

	# Catalog version and validate return no errors
	_expect_equal(int(catalog.get("catalog_version")), 2, "Catalog version must be 2")
	var validation: String = str(catalog.call(&"validate"))
	_expect_equal(validation, "", "validate() must return empty string for valid catalog")

	var cell_a: Vector2i = Vector2i(10, 10)
	var cell_b: Vector2i = Vector2i(15, 20)

	# Deterministic same-cell variants
	var floor_a1: Vector2i = catalog.call(&"atlas_coords_for_tile", 0, 0, cell_a)
	var floor_a2: Vector2i = catalog.call(&"atlas_coords_for_tile", 0, 0, cell_a)
	_expect_equal(floor_a1, floor_a2, "Same cell + biome must produce same floor variant")

	var wall_a1: Vector2i = catalog.call(&"atlas_coords_for_tile", 1, 0, cell_a)
	var wall_a2: Vector2i = catalog.call(&"atlas_coords_for_tile", 1, 0, cell_a)
	_expect_equal(wall_a1, wall_a2, "Same cell + biome must produce same wall variant")

	# Biome row separation: row 0 vs row 5
	var row0_floor: Vector2i = catalog.call(&"atlas_coords_for_tile", 0, 0, cell_b)
	var row5_floor: Vector2i = catalog.call(&"atlas_coords_for_tile", 0, 5, cell_b)
	_expect(
		row0_floor.y == 0 and row5_floor.y == 5,
		(
			"Floor coords must use biome rows: row0 got y=%d, row5 got y=%d"
			% [row0_floor.y, row5_floor.y]
		)
	)

	var row0_wall: Vector2i = catalog.call(&"atlas_coords_for_tile", 1, 0, cell_b)
	var row5_wall: Vector2i = catalog.call(&"atlas_coords_for_tile", 1, 5, cell_b)
	_expect(
		row0_wall.y == 0 and row5_wall.y == 5,
		"Wall coords must use biome rows: row0 got y=%d, row5 got y=%d" % [row0_wall.y, row5_wall.y]
	)

	# Floor columns must be in 0-3 across multiple cells
	for test_x in range(10):
		for test_y in range(10):
			var test_cell: Vector2i = Vector2i(test_x * 3 + 1, test_y * 5 + 2)
			var fc: Vector2i = catalog.call(&"atlas_coords_for_tile", 0, 0, test_cell)
			_expect(
				fc.x >= 0 and fc.x <= 3,
				"Floor variant column must be in [0,3]: at %s got %d" % [test_cell, fc.x]
			)
			_expect_equal(fc.y, 0, "Floor row must stay at biome row 0")

	# Wall columns must be in 4-6 across multiple cells
	for test_x in range(10):
		var test_cell: Vector2i = Vector2i(test_x * 7 + 3, test_x * 11 + 5)
		var wc: Vector2i = catalog.call(&"atlas_coords_for_tile", 1, 0, test_cell)
		_expect(
			wc.x >= 4 and wc.x <= 6,
			"Wall variant column must be in [4,6]: at %s got %d" % [test_cell, wc.x]
		)
		_expect_equal(wc.y, 0, "Wall row must match biome row 0")

	# Structure columns 7-11 are fixed regardless of cell
	_expect_equal(
		catalog.call(&"atlas_coords_for_tile", 2, 0, cell_a),
		Vector2i(7, 0),
		"DOOR must map to fixed column 7"
	)
	_expect_equal(
		catalog.call(&"atlas_coords_for_tile", 3, 0, cell_a),
		Vector2i(8, 0),
		"OPEN_DOOR must map to fixed column 8"
	)
	_expect_equal(
		catalog.call(&"atlas_coords_for_tile", 4, 0, cell_a),
		Vector2i(9, 0),
		"STAIRS_DOWN must map to fixed column 9"
	)
	_expect_equal(
		catalog.call(&"atlas_coords_for_tile", 5, 0, cell_a),
		Vector2i(10, 0),
		"BOSS_DOOR must map to fixed column 10"
	)
	_expect_equal(
		catalog.call(&"atlas_coords_for_tile", 6, 0, cell_a),
		Vector2i(11, 0),
		"SEALED_BOSS_DOOR must map to fixed column 11"
	)
	for biome_row: int in range(6):
		_expect_equal(
			catalog.call(&"atlas_coords_for_cracked_wall", biome_row),
			Vector2i(12, biome_row),
			"Cracked wall must use the dedicated biome-specific atlas cell",
		)
	_expect_equal(
		catalog.call(&"atlas_coords_for_cracked_wall", -1),
		Vector2i(12, 0),
		"Cracked wall rows must clamp below the atlas",
	)
	_expect_equal(
		catalog.call(&"atlas_coords_for_cracked_wall", 99),
		Vector2i(12, 5),
		"Cracked wall rows must clamp above the atlas",
	)

	# One-argument Tower fallback (no cell -> row 0 Tower, no variant)
	var tower_floor: Vector2i = catalog.call(&"atlas_coords_for_tile", 0)
	_expect_equal(
		tower_floor, Vector2i(0, 0), "One-arg FLOOR fallback must be Tower row 0 column 0"
	)
	var tower_wall: Vector2i = catalog.call(&"atlas_coords_for_tile", 1)
	_expect_equal(tower_wall, Vector2i(4, 0), "One-arg WALL fallback must be Tower row 0 column 4")
	var tower_door: Vector2i = catalog.call(&"atlas_coords_for_tile", 2)
	_expect_equal(tower_door, Vector2i(7, 0), "One-arg DOOR fallback must be Tower row 0 column 7")

	# Base tile coordinates stay in columns 0-11 of the 13x6 atlas.
	for tile_type in [0, 1, 2, 3, 4, 5, 6]:
		for biome in [0, 2, 4]:
			for cell in [cell_a, cell_b]:
				var coords: Vector2i = catalog.call(
					&"atlas_coords_for_tile", tile_type, biome, cell
				)
				_expect(
					coords.x >= 0 and coords.x <= 11 and coords.y >= 0 and coords.y <= 5,
					(
						"Base atlas coords must remain within columns 0-11: "
						+ "type=%d biome=%d cell=%s got %s" % [tile_type, biome, cell, coords]
					)
				)

	print(
		(
			"  visual catalog upholds atlas size, versioning, deterministic variants, "
			+ "biome rows, floor/wall/structure columns, and bounded coords"
		)
	)


func _check_adaptive_pixel_renderer() -> void:
	var renderer_scene: PackedScene = load(PIXEL_RENDERER_SCENE_PATH)
	var renderer: Node2D = renderer_scene.instantiate()
	root.add_child(renderer)
	await process_frame
	var layout: RefCounted = _new_adaptive_layout()
	var initialization_error: int = int(renderer.call(&"initialize_renderer", layout))
	_expect_equal(initialization_error, OK, "Pixel renderer should initialize with adaptive layout")
	if _failed:
		renderer.queue_free()
		return
	var state: RefCounted = _build_pixel_fixture_state()
	renderer.call(&"present", state)
	await process_frame
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect(bool(debug.get("available", false)), "Adaptive pixel renderer should report available")

	# New debug fields mirror layout properties
	_expect_equal(
		debug.get("base_cell_size"),
		Vector2i(16, 16),
		"Debug must expose base cell size from adaptive layout"
	)
	_expect_equal(debug.get("scale"), 2, "Debug must expose integer zoom from adaptive layout")
	_expect_equal(
		debug.get("slack"), Vector2i(30, 12), "Debug must expose slack from adaptive layout"
	)
	_expect_equal(
		debug.get("edge_padding"),
		Vector2i(4, 3),
		"Debug must expose edge padding from adaptive layout"
	)
	_expect_equal(
		debug.get("cell_size"), Vector2i(32, 32), "Debug must expose cell size from adaptive layout"
	)
	_expect_equal(
		debug.get("origin"), Vector2(35, 50), "Debug must expose origin from adaptive layout"
	)
	_expect_equal(
		debug.get("capacity"), Vector2i(20, 17), "Debug must expose capacity from adaptive layout"
	)

	# Tile layers scale by the integer zoom
	_expect_equal(
		renderer.get_node("GroundLayer").scale,
		Vector2(2, 2),
		"Ground TileMapLayer must scale by integer zoom"
	)
	_expect_equal(
		renderer.get_node("StructureLayer").scale,
		Vector2(2, 2),
		"Structure TileMapLayer must scale by integer zoom"
	)

	# Vector layers remain unscaled
	for layer_name: StringName in [
		&"ObjectLayer",
		&"ActorLayer",
		&"FogLayer",
		&"TacticalLayer",
		&"LightingLayer",
		&"EffectPool"
	]:
		var layer: Node = renderer.get_node(NodePath(String(layer_name)))
		_expect_equal(
			layer.scale, Vector2.ONE, "%s must remain unscaled under adaptive layout" % [layer_name]
		)

	# Actor positions remain cell-centered via layout
	_expect_equal(
		debug.get("player_cell"),
		Vector2i(24, 16),
		"Player cell must be preserved under adaptive layout"
	)
	_expect_equal(
		debug.get("player_position"),
		layout.call(&"cell_center_to_local", Vector2i(24, 16)),
		"Player position under adaptive layout must match cell_center_to_local"
	)

	# Transform ownership: tile layers carry layout origin + view offset,
	# vector layers remain at ZERO before shake is applied.
	var layer_dict: Dictionary = debug.get("layers", {})
	var expected_tile_pos: Vector2 = (
		(layout.call(&"get_origin") + layout.call(&"get_view_offset_pixels")).round()
	)
	_expect_equal(
		layer_dict.get("GroundLayer", {}).get("position"),
		expected_tile_pos,
		"GroundLayer position must include layout origin and view offset"
	)
	_expect_equal(
		layer_dict.get("StructureLayer", {}).get("position"),
		expected_tile_pos,
		"StructureLayer position must include layout origin and view offset"
	)
	for layer_name: StringName in [
		&"ObjectLayer",
		&"ActorLayer",
		&"FogLayer",
		&"TacticalLayer",
		&"LightingLayer",
		&"EffectPool"
	]:
		_expect_equal(
			layer_dict.get(String(layer_name), {}).get("position"),
			Vector2.ZERO,
			"%s position must be ZERO before shake" % [layer_name]
		)

	renderer.queue_free()
	await process_frame
	print(
		"  adaptive pixel renderer scales tiles, leaves vectors unscaled, exposes layout in debug"
	)


func _check_map_view_switching() -> void:
	var map_view: Node2D = _map_view_script.new()
	root.add_child(map_view)
	await process_frame
	map_view.call(&"configure_map", [[0, 0], [0, 0]])
	var visible_cells: Dictionary = {
		Vector2i(0, 0): true,
		Vector2i(1, 0): true,
		Vector2i(0, 1): true,
		Vector2i(1, 1): true,
	}
	map_view.call(&"set_visibility", visible_cells, visible_cells)
	map_view.call(&"play_cell_burst", Vector2i.ZERO, Color.WHITE)
	var trail_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ONE]
	map_view.call(&"play_projectile_trail", trail_cells)
	map_view.call(&"set_map_render_mode", &"hybrid")
	_expect_equal(
		map_view.call(&"get_effective_map_render_mode"),
		&"hybrid",
		"MapView should activate its registered Hybrid renderer"
	)
	_expect(
		not bool(map_view.call(&"has_active_cell_bursts")),
		"Renderer switching should clear ASCII cell-burst transients"
	)
	_expect(
		not bool(map_view.call(&"has_active_projectile_trails")),
		"Renderer switching should clear ASCII projectile transients"
	)
	var pixel_renderer: Node = map_view.get_node_or_null("PixelMapRenderer")
	_expect(
		pixel_renderer != null and pixel_renderer.visible, "Hybrid pixel child should be visible"
	)
	map_view.call(&"set_map_render_mode", &"pixel")
	_expect_equal(
		map_view.call(&"get_effective_map_render_mode"),
		&"pixel",
		"Full Pixel mode should activate after tactical parity"
	)
	var pixel_debug: Dictionary = pixel_renderer.call(&"get_debug_snapshot")
	_expect_equal(pixel_debug.get("profile"), &"pixel", "Pixel renderer profile did not switch")
	_expect(
		bool(pixel_debug.get("tactical", {}).get("native_tactical", false)),
		"Full Pixel profile should own tactical overlays",
	)
	map_view.call(&"set_map_render_mode", &"ascii")
	_expect_equal(
		map_view.call(&"get_effective_map_render_mode"), &"ascii", "ASCII mode should restore"
	)
	_expect(pixel_renderer != null and not pixel_renderer.visible, "ASCII should hide pixel child")
	map_view.queue_free()
	await process_frame
	print("  MapView switches by state replay and clears renderer-local transients")


func _new_layout() -> RefCounted:
	var layout: RefCounted = _grid_script.new()
	layout.call(&"configure", Vector2i(16, 16), Vector2(20, 44), Vector2i(41, 34))
	return layout


func _new_adaptive_layout() -> RefCounted:
	var layout: RefCounted = _grid_script.new()
	layout.call(
		&"configure_adaptive",
		Vector2i(16, 16),
		Vector2(20, 44),
		Vector2(670, 556),
		PREFERRED_SCALES,
		Vector2i(19, 15),
		Vector2i(4, 3)
	)
	return layout


func _build_pixel_fixture_state() -> RefCounted:
	var state: RefCounted = _state_script.new()
	var map_data: Array = []
	var explored_cells: Dictionary = {}
	var visible_cells: Dictionary = {}
	for y: int in range(32):
		var row: Array[int] = []
		for x: int in range(48):
			row.append(0)
			var cell: Vector2i = Vector2i(x, y)
			explored_cells[cell] = true
			visible_cells[cell] = true
		map_data.append(row)
	map_data[16][25] = 1
	map_data[16][26] = 2
	state.call(&"capture_map", map_data)
	state.set(&"explored_cells", explored_cells)
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	var player: FakeActor = FakeActor.new()
	player.name = &"Player"
	player.grid_position = Vector2i(24, 16)
	state.call(&"capture_actors", [player])
	player.free()
	return state


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected and not _failed:
		_fail("%s: got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
