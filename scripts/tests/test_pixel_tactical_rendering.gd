## Phase 4 regression coverage for pixel objects, tactical overlays, and effects.
## Run with:
##   /usr/local/bin/godot --headless --path . --script
##   res://scripts/tests/test_pixel_tactical_rendering.gd
extends SceneTree

const PRESENTATION_DIR: String = "res://scripts/ui/map_presentation/"
const VISUAL_CATALOG_DIR: String = "res://resources/visuals/catalogs/"
const GRID_LAYOUT_PATH: String = PRESENTATION_DIR + "map_grid_layout.gd"
const STATE_PATH: String = PRESENTATION_DIR + "map_presentation_state.gd"
const OBJECT_CATALOG_PATH: String = VISUAL_CATALOG_DIR + "map_object_visual_catalog.tres"
const PIXEL_RENDERER_SCENE_PATH: String = "res://scenes/rendering/pixel_map_renderer.tscn"
const MAP_VIEW_PATH: String = "res://scripts/ui/map_view.gd"

var _failed: bool = false
var _layout_script: GDScript
var _state_script: GDScript
var _renderer_scene: PackedScene
var _object_catalog: Resource
var _actor: FakeActor


class FakeItem:
	extends Resource
	var kind: int = 0
	var rarity: int = 0
	var color: Color = Color.WHITE
	var visual_id: StringName = &""

	func _init(
		item_kind: int, item_rarity: int, item_color: Color, item_visual: StringName = &""
	) -> void:
		kind = item_kind
		rarity = item_rarity
		color = item_color
		visual_id = item_visual


class FakeTrap:
	extends Resource
	var effect: int = 0
	var color: Color = Color.WHITE
	var visual_id: StringName = &""

	func _init(trap_effect: int, trap_color: Color, trap_visual: StringName = &"") -> void:
		effect = trap_effect
		color = trap_color
		visual_id = trap_visual


class FakeActor:
	extends Node2D
	var display_name: String = "Test Enemy"
	var glyph: String = "e"
	var color: Color = Color(0.9, 0.25, 0.3)
	var grid_position: Vector2i = Vector2i(3, 2)
	var alive: bool = true

	func setup_actor() -> void:
		pass

	func is_alive() -> bool:
		return alive


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_load_dependencies()
	if _failed:
		quit(1)
		return
	_check_object_catalogue()
	var state: RefCounted = _build_state()
	_check_semantic_snapshots(state)
	await _check_renderer_objects_and_tactics(state)
	await _check_map_view_profile_bridge()
	_cleanup_actor()
	if _failed:
		quit(1)
		return
	print("Pixel tactical rendering checks passed")
	quit(0)


func _load_dependencies() -> void:
	_layout_script = load(GRID_LAYOUT_PATH) as GDScript
	_state_script = load(STATE_PATH) as GDScript
	_renderer_scene = load(PIXEL_RENDERER_SCENE_PATH) as PackedScene
	_object_catalog = load(OBJECT_CATALOG_PATH)
	_expect(_layout_script != null, "MapGridLayout failed to load")
	_expect(_state_script != null, "MapPresentationState failed to load")
	_expect(_renderer_scene != null, "Pixel renderer scene failed to load")
	_expect(_object_catalog != null, "Object visual catalogue failed to load")


func _check_object_catalogue() -> void:
	_expect_equal(str(_object_catalog.call(&"validate")), "", "Object catalogue validation failed")
	var atlas: Texture2D = _object_catalog.call(&"get_atlas")
	_expect(atlas != null, "Object catalogue returned no atlas")
	if atlas != null:
		_expect_equal(
			Vector2i(atlas.get_size()), Vector2i(448, 16), "Object atlas dimensions drifted"
		)
	var expected_columns: Dictionary = {
		&"item/potion": 0,
		&"item/elixir": 1,
		&"item/scroll": 2,
		&"item/sword": 3,
		&"item/axe": 4,
		&"item/dagger": 5,
		&"item/mace": 6,
		&"item/spear": 7,
		&"item/bow": 8,
		&"item/crossbow": 9,
		&"item/staff": 10,
		&"item/armor/light": 11,
		&"item/armor/heavy": 12,
		&"item/robe": 13,
		&"item/ring": 14,
		&"item/charm": 15,
		&"item/generic": 16,
		&"prop/chest": 17,
		&"prop/boss_chest": 18,
		&"prop/vase": 19,
		&"prop/box": 20,
		&"prop/generic": 21,
		&"trap/damage": 22,
		&"trap/poison": 23,
		&"trap/teleport": 24,
		&"trap/alarm": 25,
		&"trap/stun": 26,
		&"trap/ambush": 27,
	}
	for visual_id: StringName in expected_columns:
		var region: Rect2 = _object_catalog.call(&"region_for", visual_id)
		_expect_equal(
			region.position, Vector2(expected_columns[visual_id] * 16, 0), "Atlas mapping drifted"
		)
		_expect_equal(region.size, Vector2(16, 16), "Object region must remain 16x16")
	var alias_checks: Dictionary = {
		&"item/consumable": 0,
		&"item/weapon": 3,
		&"item/armor": 11,
		&"item/accessory": 14,
		&"item/generic": 16,
	}
	for visual_id: StringName in alias_checks:
		var region: Rect2 = _object_catalog.call(&"region_for", visual_id)
		_expect_equal(
			region.position, Vector2(alias_checks[visual_id] * 16, 0), "Alias mapping drifted"
		)
	var fallback: Rect2 = _object_catalog.call(&"region_for", &"missing/visual")
	_expect_equal(
		fallback.position, Vector2(256, 0), "Unknown object IDs need safe fallback at column 16"
	)
	print("  explicit object catalogue maps deterministic 16x16 atlas regions")


func _build_state() -> RefCounted:
	var state: RefCounted = _state_script.new()
	var map_data: Array = []
	var explored_cells: Dictionary = {}
	var visible_cells: Dictionary = {}
	for y: int in range(10):
		var row: Array[int] = []
		for x: int in range(12):
			row.append(0)
			var cell: Vector2i = Vector2i(x, y)
			explored_cells[cell] = true
			if x <= 7 and y <= 6:
				visible_cells[cell] = true
		map_data.append(row)
	state.call(&"capture_map", map_data)
	state.set(&"explored_cells", explored_cells)
	visible_cells.erase(Vector2i(6, 2))
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	_actor = FakeActor.new()
	_actor.name = &"Enemy"
	state.call(&"capture_actors", [_actor])
	(
		state
		. call(
			&"capture_items",
			{
				Vector2i(2, 2): FakeItem.new(1, 2, Color(0.4, 0.7, 1.0), &"item/sword"),
				Vector2i(3, 2): FakeItem.new(2, 1, Color(0.7, 0.8, 0.9), &"item/armor/heavy"),
				Vector2i(9, 8): FakeItem.new(0, 0, Color(0.4, 1.0, 0.5), &"item/potion"),
			},
		)
	)
	(
		state
		. call(
			&"capture_containers",
			{
				Vector2i(4, 2):
				{
					"type": &"chest",
					"rarity": 3,
					"boss_reward": false,
					"marked": false,
					"color": Color(0.8, 0.45, 1.0),
				},
				Vector2i(9, 7):
				{
					"type": &"clutter",
					"glyph": "v",
					"color": Color(0.6, 0.4, 0.25),
				},
			},
		)
	)
	var traps: Dictionary = {
		Vector2i(5, 2): FakeTrap.new(0, Color(1.0, 0.35, 0.2), &"trap/damage"),
		Vector2i(6, 2): FakeTrap.new(1, Color(0.4, 1.0, 0.45), &"trap/poison"),
		Vector2i(7, 2): FakeTrap.new(2, Color(0.6, 0.4, 1.0), &"trap/teleport"),
	}
	(
		state
		. call(
			&"capture_traps",
			traps,
			{Vector2i(5, 2): true},
			{Vector2i(6, 2): true},
		)
	)
	(
		state
		. call(
			&"capture_secret_walls",
			{Vector2i(1, 4): {"hp": 2}},
			{Vector2i(1, 4): true},
			Color(0.72, 0.58, 1.0),
		)
	)
	state.set(&"targeting_active", true)
	state.set(&"target_cursor", Vector2i(4, 3))
	state.set(&"target_range_cells", {Vector2i(2, 3): true, Vector2i(9, 8): true})
	state.set(&"target_area_cells", {Vector2i(4, 3): true})
	state.set(&"boss_room_cells", {Vector2i(5, 5): true, Vector2i(6, 5): true})
	state.set(&"boss_room_locked", true)
	(
		state
		. set(
			&"boss_telegraphs",
			{
				Vector2i(5, 3): {"color": Color.ORANGE_RED},
				Vector2i(9, 8): {"color": Color.ORANGE_RED},
			},
		)
	)
	(
		state
		. set(
			&"boss_hazards",
			{Vector2i(5, 4): {"color": Color.CORNFLOWER_BLUE}},
		)
	)
	state.set(&"enemy_intents", {Vector2i(3, 2): &"melee"})
	state.set(&"atmosphere_enabled", false)
	state.call(&"mark_overlay_changed")
	state.call(&"mark_environment_changed")
	return state


func _check_semantic_snapshots(state: RefCounted) -> void:
	var items: Dictionary = state.get("items")
	_expect(items[Vector2i(2, 2)] is Dictionary, "Item state must be semantic data")
	_expect_equal(items[Vector2i(2, 2)].get("visual_id"), &"item/sword", "Sword visual ID drifted")
	_expect_equal(
		items[Vector2i(3, 2)].get("visual_id"), &"item/armor/heavy", "Heavy armor visual ID drifted"
	)
	_expect_equal(
		items[Vector2i(9, 8)].get("visual_id"), &"item/potion", "Potion visual ID drifted"
	)
	var containers: Dictionary = state.get("containers")
	_expect_equal(
		containers[Vector2i(4, 2)].get("visual_id"), &"prop/chest", "Chest visual ID drifted"
	)
	_expect_equal(
		containers[Vector2i(9, 7)].get("visual_id"), &"prop/vase", "Clutter visual ID drifted"
	)
	var traps: Dictionary = state.get("trap_data")
	_expect_equal(traps[Vector2i(5, 2)].get("visual_id"), &"trap/damage", "Trap visual ID drifted")
	_expect(bool(traps[Vector2i(6, 2)].get("triggered")), "Triggered trap state was lost")
	_expect_equal(
		traps[Vector2i(7, 2)].get("visual_id"), &"trap/teleport", "Teleport trap visual ID drifted"
	)
	print("  shared state converts gameplay resources into semantic object snapshots")


func _check_renderer_objects_and_tactics(state: RefCounted) -> void:
	var renderer: Node2D = _renderer_scene.instantiate() as Node2D
	root.add_child(renderer)
	await process_frame
	var layout: RefCounted = _layout_script.new()
	layout.call(&"configure", Vector2i(16, 16), Vector2(20, 44), Vector2i(12, 10))
	var initialization_error: int = int(renderer.call(&"initialize_renderer", layout))
	_expect_equal(initialization_error, OK, "Pixel renderer failed to initialize")
	renderer.call(&"present", state)
	await process_frame
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	var objects: Dictionary = debug.get("objects", {})
	_expect_equal(int(objects.get("item_count", 0)), 1, "Visible uncovered item count drifted")
	_expect_equal(int(objects.get("container_count", 0)), 1, "Visible container count drifted")
	_expect_equal(int(objects.get("trap_count", 0)), 2, "Known trap count drifted")
	var tactical: Dictionary = debug.get("tactical", {})
	_expect(
		not bool(tactical.get("native_tactical", true)),
		"Hybrid must retain ASCII tactical overlays"
	)
	_expect_equal(int(tactical.get("telegraph_count", -1)), 0, "Hybrid rendered native telegraphs")
	var actor_count: int = int(debug.get("actor_count", 0))
	renderer.call(&"set_render_profile", &"pixel")
	renderer.call(&"present", state)
	await process_frame
	debug = renderer.call(&"get_debug_snapshot")
	tactical = debug.get("tactical", {})
	_expect(
		bool(tactical.get("native_tactical", false)), "Full Pixel tactical profile did not activate"
	)
	_expect_equal(int(tactical.get("target_range_count", 0)), 1, "Target range visibility drifted")
	_expect_equal(int(tactical.get("target_area_count", 0)), 1, "Target area visibility drifted")
	_expect(bool(tactical.get("target_cursor_visible", false)), "Pixel target cursor disappeared")
	_expect_equal(int(tactical.get("telegraph_count", 0)), 1, "Telegraph visibility drifted")
	_expect_equal(int(tactical.get("hazard_count", 0)), 1, "Hazard visibility drifted")
	_expect_equal(int(tactical.get("intent_count", 0)), 1, "Enemy intent visibility drifted")
	_expect_equal(int(tactical.get("secret_wall_count", 0)), 1, "Secret-wall hint drifted")
	_expect_equal(
		int(debug.get("actor_count", 0)), actor_count, "Profile switching duplicated actors"
	)
	_check_pixel_transients(renderer)
	await create_timer(0.65).timeout
	tactical = renderer.call(&"get_debug_snapshot").get("tactical", {})
	_expect_equal(int(tactical.get("projectile_count", -1)), 0, "Projectile effect did not expire")
	_expect_equal(int(tactical.get("burst_count", -1)), 0, "Cell burst did not expire")
	_expect_equal(int(tactical.get("boss_spawn_count", -1)), 0, "Boss spawn effect did not expire")
	await _check_missing_object_catalogue(layout)
	renderer.call(&"shutdown_renderer")
	renderer.queue_free()
	await process_frame
	print("  renderer gates objects by FOV and switches to pixel-native tactical overlays")


func _check_pixel_transients(renderer: Node2D) -> void:
	renderer.call(&"set_reduced_vfx", true)
	(
		renderer
		. call(
			&"play_event",
			{
				"type": &"projectile_trail",
				"payload":
				{
					"cells": [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)],
					"duration": 0.30,
					"color": Color.CYAN,
					"trail_color": Color(0.3, 0.8, 1.0, 0.7),
					"impact_color": Color.WHITE,
					"respect_visibility": true,
				},
			},
		)
	)
	(
		renderer
		. call(
			&"play_event",
			{
				"type": &"cell_burst",
				"payload": {"cell": Vector2i(4, 3), "duration": 0.40, "color": Color.ORANGE},
			},
		)
	)
	(
		renderer
		. call(
			&"play_event",
			{
				"type": &"boss_spawn_intro",
				"payload":
				{
					"cell": Vector2i(5, 5),
					"occupied_cells": [Vector2i(5, 5), Vector2i(6, 5)],
					"duration": 0.90,
					"color": Color.GOLD,
				},
			},
		)
	)
	var tactical: Dictionary = renderer.call(&"get_debug_snapshot").get("tactical", {})
	_expect_equal(int(tactical.get("projectile_count", 0)), 1, "Pixel projectile event was lost")
	_expect_equal(int(tactical.get("burst_count", 0)), 1, "Pixel cell burst event was lost")
	_expect_equal(int(tactical.get("boss_spawn_count", 0)), 1, "Pixel boss spawn event was lost")
	_expect_equal(
		int(tactical.get("projectile_cell_count", 0)), 2, "Reduced VFX should trim trail cells"
	)
	_expect(
		float(tactical.get("projectile_duration", 1.0)) < 0.30,
		"Reduced projectile duration was not applied"
	)
	_expect(
		float(tactical.get("burst_duration", 1.0)) < 0.40, "Reduced burst duration was not applied"
	)
	var event_count: int = int(tactical.get("event_count", 0))
	var state: RefCounted = renderer.get("_state")
	renderer.call(&"present", state)
	tactical = renderer.call(&"get_debug_snapshot").get("tactical", {})
	_expect_equal(
		int(tactical.get("event_count", 0)), event_count, "State replay duplicated effects"
	)


func _check_missing_object_catalogue(layout: RefCounted) -> void:
	var renderer: Node2D = _renderer_scene.instantiate() as Node2D
	renderer.set("object_catalog", null)
	root.add_child(renderer)
	await process_frame
	var initialization_error: int = int(renderer.call(&"initialize_renderer", layout))
	_expect(initialization_error != OK, "Missing object catalogue must reject pixel activation")
	_expect(
		not bool(renderer.call(&"is_renderer_available")), "Incomplete renderer remained available"
	)
	renderer.queue_free()
	await process_frame


func _check_map_view_profile_bridge() -> void:
	var map_view_script: GDScript = load(MAP_VIEW_PATH) as GDScript
	_expect(map_view_script != null and map_view_script.can_instantiate(), "MapView failed to load")
	if map_view_script == null or not map_view_script.can_instantiate():
		return
	var map_view: Node2D = map_view_script.new()
	root.add_child(map_view)
	await process_frame
	var map_data: Array = []
	var cells: Dictionary = {}
	for y: int in range(6):
		var row: Array[int] = []
		for x: int in range(8):
			row.append(0)
			cells[Vector2i(x, y)] = true
		map_data.append(row)
	map_view.call(&"configure_map", map_data)
	map_view.call(&"set_visibility", cells, cells.duplicate())
	_expect(
		bool(map_view.call(&"is_map_render_mode_available", &"pixel")),
		"Full Pixel mode unavailable"
	)
	map_view.call(&"set_map_render_mode", &"pixel")
	_expect_equal(
		map_view.call(&"get_effective_map_render_mode"), &"pixel", "Full Pixel did not activate"
	)
	var projectile_cells: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	(
		map_view
		. call(
			&"play_projectile_trail",
			projectile_cells,
			{"duration_seconds": 0.3},
		)
	)
	map_view.call(&"play_cell_burst", Vector2i(3, 1), Color.CYAN)
	var renderer: Node = map_view.get_node_or_null("PixelMapRenderer")
	_expect(
		renderer.process_mode != Node.PROCESS_MODE_DISABLED,
		"Active pixel renderer should process animations and effects",
	)
	var tactical: Dictionary = renderer.call(&"get_debug_snapshot").get("tactical", {})
	_expect_equal(
		int(tactical.get("projectile_count", 0)), 1, "MapView did not forward projectile event"
	)
	_expect_equal(int(tactical.get("burst_count", 0)), 1, "MapView did not forward burst event")
	_expect(
		not map_view.is_processing(),
		"Legacy ASCII effects should not process behind pixel profiles"
	)
	map_view.call(&"set_map_render_mode", &"hybrid")
	_expect_equal(
		map_view.call(&"get_effective_map_render_mode"), &"hybrid", "Hybrid did not reactivate"
	)
	tactical = renderer.call(&"get_debug_snapshot").get("tactical", {})
	_expect_equal(int(tactical.get("projectile_count", -1)), 0, "Profile switch kept stale effects")
	map_view.call(&"set_map_render_mode", &"ascii")
	_expect_equal(
		map_view.call(&"get_effective_map_render_mode"), &"ascii", "ASCII did not restore"
	)
	_expect_equal(
		renderer.process_mode,
		Node.PROCESS_MODE_DISABLED,
		"Inactive pixel renderer should stop renderer-local processing",
	)
	map_view.queue_free()
	await process_frame
	print("  MapView forwards effects and switches ASCII, Hybrid, and Full Pixel safely")


func _cleanup_actor() -> void:
	if is_instance_valid(_actor):
		_actor.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_fail("%s: got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
