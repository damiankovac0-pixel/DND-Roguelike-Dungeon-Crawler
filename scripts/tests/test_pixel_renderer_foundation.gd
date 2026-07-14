## Phase 2 regression coverage for grid layout, state replay, and pixel prototype.
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
	if _failed:
		return
	_check_grid_layout()
	if _failed:
		return
	_check_presentation_state()
	if _failed:
		return
	_check_controller_replay_and_fallback()
	if _failed:
		return
	await _check_pixel_renderer_scene()
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
	renderer.queue_free()
	await process_frame
	print("  TileMapLayer prototype renders terrain, visibility, and player deterministically")


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
