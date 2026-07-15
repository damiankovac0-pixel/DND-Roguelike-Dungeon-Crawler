## Phase 7 release gates for renderer parity, visual differentiation, lifecycle, and load.
extends SceneTree

const MAP_VIEW_SCRIPT: GDScript = preload("res://scripts/ui/map_view.gd")
const VIEWPORT_SIZE: Vector2i = Vector2i(720, 610)
const MODE_SWITCH_CYCLES: int = 120
const DENSE_ACTOR_COUNT: int = 64
const DENSE_TURN_UPDATES: int = 60
const MAX_DENSE_UPDATE_MSEC: float = 5000.0
const MAX_NODE_GROWTH: int = 4
const MAX_STATIC_MEMORY_GROWTH_BYTES: int = 16 * 1024 * 1024
const REQUIRE_VISUAL_CAPTURE_ARG: String = "--require-visual-capture"

var _failed: bool = false
var _viewport: SubViewport
var _map_view: Node2D
var _base_actors: Array[FakeActor] = []
var _baseline_snapshot: Dictionary = {}


class FakeEnemyData:
	extends Resource

	var is_boss: bool = false
	var boss_id: StringName = &""

	func _init(boss: bool = false, id: StringName = &"") -> void:
		is_boss = boss
		boss_id = id


class FakeActor:
	extends Node2D

	signal moved(new_position: Vector2i)

	var grid_position: Vector2i = Vector2i.ZERO
	var glyph: String = "e"
	var color: Color = Color.WHITE
	var alive: bool = true
	var display_name: String = "Actor"
	var enemy_data: Resource

	func _init(
		actor_name: StringName = &"Enemy",
		cell: Vector2i = Vector2i.ZERO,
		actor_glyph: String = "e",
		actor_color: Color = Color.WHITE,
		data: Resource = null
	) -> void:
		name = actor_name
		grid_position = cell
		glyph = actor_glyph
		color = actor_color
		display_name = str(actor_name)
		enemy_data = data

	func is_alive() -> bool:
		return alive

	func setup_actor(_display_name: String, _glyph: String, _color: Color) -> void:
		pass

	func initialize_from_data(_data: Resource) -> void:
		pass

	func move_to(cell: Vector2i) -> void:
		grid_position = cell
		moved.emit(cell)


class FakeItem:
	extends Resource

	var kind: int = 0
	var rarity: int = 0
	var glyph: String = "!"
	var color: Color = Color.WHITE

	func _init(type: int, item_rarity: int, item_color: Color) -> void:
		kind = type
		rarity = item_rarity
		color = item_color


class FakeTrap:
	extends Resource

	var effect: int = 0
	var glyph: String = "^"
	var color: Color = Color.WHITE

	func _init(type: int, trap_color: Color) -> void:
		effect = type
		color = trap_color


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Phase 7 pixel renderer release gates ===")
	await _create_fixture()
	if _failed:
		await _cleanup()
		quit(1)
		return
	await _check_default_and_mode_parity()
	await _check_fixed_scene_visual_captures()
	await _check_mode_switch_lifecycle_stress()
	await _check_dense_actor_performance()
	await _check_viewport_resize_stability()
	await _cleanup()
	if _failed:
		quit(1)
		return
	print("Phase 7 pixel renderer release gates passed")
	quit(0)


func _create_fixture() -> void:
	_viewport = SubViewport.new()
	_viewport.name = &"ReleaseGateViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_map_view = MAP_VIEW_SCRIPT.new() as Node2D
	_expect(_map_view != null, "MapView failed to instantiate")
	if _map_view == null:
		return
	_viewport.add_child(_map_view)
	await process_frame
	await process_frame
	_configure_map_fixture()
	await process_frame
	await process_frame
	_baseline_snapshot = _shared_snapshot()
	_expect(not _baseline_snapshot.is_empty(), "Shared parity snapshot was empty")


func _configure_map_fixture() -> void:
	var map_data: Array = []
	var explored_cells: Dictionary = {}
	var visible_cells: Dictionary = {}
	for y: int in range(32):
		var row: Array[int] = []
		for x: int in range(48):
			var tile_type: int = 0
			if x == 0 or x == 47 or y == 0 or y == 31:
				tile_type = 1
			elif y == 8 and x >= 10 and x <= 38:
				tile_type = 1
			row.append(tile_type)
			var cell: Vector2i = Vector2i(x, y)
			explored_cells[cell] = true
			if x >= 3 and x <= 44:
				visible_cells[cell] = true
		map_data.append(row)
	map_data[8][18] = 2
	map_data[8][19] = 3
	map_data[8][30] = 5
	map_data[8][31] = 6
	map_data[20][36] = 4
	_map_view.call(&"configure_map", map_data)
	_map_view.call(&"set_visibility", visible_cells, explored_cells)
	_map_view.call(&"set_atmosphere_enabled", false)

	var player: FakeActor = FakeActor.new(&"Player", Vector2i(24, 15), "@", Color(0.40, 0.95, 1.0))
	var enemy: FakeActor = FakeActor.new(&"Enemy", Vector2i(27, 15), "g", Color(0.95, 0.45, 0.30))
	var boss: FakeActor = FakeActor.new(
		&"Boss", Vector2i(33, 14), "O", Color(0.88, 0.30, 1.0), FakeEnemyData.new(true, &"observer")
	)
	_base_actors.assign([player, enemy, boss])
	_map_view.call(&"set_actors", _base_actors)
	(
		_map_view
		. call(
			&"set_items",
			{
				Vector2i(23, 17): FakeItem.new(0, 2, Color(0.35, 1.0, 0.55)),
				Vector2i(46, 24): FakeItem.new(1, 4, Color(0.92, 0.55, 1.0)),
			}
		)
	)
	(
		_map_view
		. call(
			&"set_containers",
			{
				Vector2i(25, 18):
				{
					"type": &"chest",
					"rarity": 3,
					"boss_reward": false,
					"marked": false,
					"color": Color(0.90, 0.62, 0.22),
				},
				Vector2i(29, 18):
				{
					"type": &"clutter",
					"glyph": "v",
					"color": Color(0.55, 0.38, 0.24),
				},
			}
		)
	)
	(
		_map_view
		. call(
			&"set_traps",
			{
				Vector2i(26, 17): FakeTrap.new(0, Color(1.0, 0.30, 0.20)),
				Vector2i(28, 17): FakeTrap.new(1, Color(0.35, 1.0, 0.45)),
			},
			{Vector2i(26, 17): true},
			{Vector2i(28, 17): true}
		)
	)
	_map_view.call(
		&"set_secret_walls",
		{Vector2i(16, 8): {"hp": 2}},
		{Vector2i(16, 8): true},
		Color(0.72, 0.58, 1.0)
	)
	(
		_map_view
		. call(
			&"set_targeting",
			true,
			Vector2i(28, 15),
			{
				Vector2i(25, 15): true,
				Vector2i(26, 15): true,
				Vector2i(27, 15): true,
				Vector2i(28, 15): true,
			},
			{Vector2i(28, 15): true, Vector2i(28, 16): true}
		)
	)
	_map_view.call(&"set_enemy_intents", {Vector2i(27, 15): &"melee"})
	var boss_room_cells: Dictionary = {}
	for y: int in range(12, 19):
		for x: int in range(31, 39):
			boss_room_cells[Vector2i(x, y)] = true
	_map_view.call(
		&"set_boss_room",
		boss_room_cells,
		[Vector2i(30, 15), Vector2i(30, 16)],
		true,
		Color(0.28, 0.08, 0.36, 0.16)
	)
	(
		_map_view
		. call(
			&"set_boss_visuals",
			{
				Vector2i(33, 14):
				{
					"boss_id": &"observer",
					"occupied_cells":
					[
						Vector2i(33, 14),
						Vector2i(34, 14),
						Vector2i(33, 15),
						Vector2i(34, 15),
					],
					"frames": [["O", "O"], ["O", "O"]],
					"color": Color(0.88, 0.30, 1.0),
				}
			}
		)
	)
	(
		_map_view
		. call(
			&"set_boss_telegraphs",
			{
				Vector2i(29, 15): {"glyph": "!", "color": Color.ORANGE_RED},
				Vector2i(30, 15): {"glyph": "!", "color": Color.ORANGE_RED},
			}
		)
	)
	_map_view.call(
		&"set_boss_hazards", {Vector2i(32, 17): {"glyph": "~", "color": Color.CORNFLOWER_BLUE}}
	)


func _check_default_and_mode_parity() -> void:
	_expect_equal(
		StringName(_map_view.call(&"get_requested_map_render_mode")),
		&"ascii",
		"ASCII must remain the requested default",
	)
	_expect_equal(
		StringName(_map_view.call(&"get_effective_map_render_mode")),
		&"ascii",
		"ASCII must remain the effective default",
	)
	_assert_shared_parity("default ASCII")

	_map_view.call(&"set_map_render_mode", &"hybrid")
	await process_frame
	var hybrid: Dictionary = _debug_snapshot()
	_assert_shared_parity("Hybrid")
	_expect_equal(hybrid.get("effective_mode"), &"hybrid", "Hybrid mode did not activate")
	var hybrid_pixel: Dictionary = hybrid.get("pixel", {})
	_expect_equal(hybrid_pixel.get("profile"), &"hybrid", "Hybrid renderer profile drifted")
	_expect_equal(int(hybrid_pixel.get("actor_count", 0)), 3, "Hybrid actor count drifted")
	_expect(bool(hybrid_pixel.get("visible", false)), "Hybrid pixel base stayed hidden")
	_expect(
		bool(hybrid.get("ascii", {}).get("tactical_active", false)),
		"Hybrid ASCII tactics disappeared",
	)

	_map_view.call(&"set_map_render_mode", &"pixel")
	await process_frame
	var pixel: Dictionary = _debug_snapshot()
	_assert_shared_parity("Full Pixel")
	_expect_equal(pixel.get("effective_mode"), &"pixel", "Full Pixel mode did not activate")
	var pixel_backend: Dictionary = pixel.get("pixel", {})
	_expect_equal(pixel_backend.get("profile"), &"pixel", "Full Pixel profile drifted")
	_expect_equal(int(pixel_backend.get("actor_count", 0)), 3, "Full Pixel actor count drifted")
	_expect(
		not bool(pixel.get("ascii", {}).get("tactical_active", true)),
		"Full Pixel left ASCII tactics visible",
	)
	var tactical: Dictionary = pixel_backend.get("tactical", {})
	_expect(bool(tactical.get("native_tactical", false)), "Full Pixel tactics are not pixel-native")
	_expect(int(tactical.get("telegraph_count", 0)) > 0, "Boss telegraphs did not reach Full Pixel")
	_expect(int(tactical.get("target_range_count", 0)) > 0, "Target range did not reach Full Pixel")
	_expect(int(tactical.get("intent_count", 0)) > 0, "Enemy intents did not reach Full Pixel")
	print("  ASCII, Hybrid, and Full Pixel consume one semantic state snapshot")


func _check_fixed_scene_visual_captures() -> void:
	if not _is_visual_capture_supported():
		_expect(
			not OS.get_cmdline_user_args().has(REQUIRE_VISUAL_CAPTURE_ARG),
			"Visual capture was required, but the headless display uses dummy textures",
		)
		print("  fixed scene capture deferred: headless display uses dummy textures")
		return
	var ascii_image: Image = await _capture_mode(&"ascii")
	var hybrid_image: Image = await _capture_mode(&"hybrid")
	var pixel_image: Image = await _capture_mode(&"pixel")
	_expect_equal(ascii_image.get_size(), VIEWPORT_SIZE, "ASCII capture dimensions drifted")
	_expect_equal(hybrid_image.get_size(), VIEWPORT_SIZE, "Hybrid capture dimensions drifted")
	_expect_equal(pixel_image.get_size(), VIEWPORT_SIZE, "Full Pixel capture dimensions drifted")
	var ascii_hybrid_difference: int = _sampled_difference_count(ascii_image, hybrid_image)
	var hybrid_pixel_difference: int = _sampled_difference_count(hybrid_image, pixel_image)
	_expect(
		ascii_hybrid_difference >= 300,
		"Fixed-scene ASCII and Hybrid captures were not visually distinct",
	)
	_expect(
		hybrid_pixel_difference >= 12,
		"Fixed-scene Hybrid and Full Pixel tactical captures were not visually distinct",
	)
	_assert_shared_parity("fixed-scene captures")
	print(
		(
			"  fixed scene captures differ as expected (ASCII/Hybrid=%d, Hybrid/Pixel=%d samples)"
			% [ascii_hybrid_difference, hybrid_pixel_difference]
		)
	)


func _check_mode_switch_lifecycle_stress() -> void:
	_map_view.call(&"set_map_render_mode", &"hybrid")
	await process_frame
	var initial_debug: Dictionary = _debug_snapshot().get("pixel", {})
	var initial_renderer_children: int = int(initial_debug.get("renderer_child_count", 0))
	var initial_effect_children: int = int(initial_debug.get("effects", {}).get("child_count", 0))
	var initial_node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var initial_static_memory: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var max_actor_children: int = int(initial_debug.get("actor_layer_child_count", 0))
	var outbound_path: Array[Vector2i] = [Vector2i(24, 15), Vector2i(25, 15), Vector2i(26, 15)]
	var inbound_path: Array[Vector2i] = [Vector2i(27, 15), Vector2i(28, 15), Vector2i(29, 15)]
	for cycle: int in range(MODE_SWITCH_CYCLES):
		_map_view.call(&"set_map_render_mode", &"hybrid")
		_map_view.call(&"set_reduced_vfx_enabled", cycle % 4 == 0)
		var transient_actor: FakeActor = (
			FakeActor
			. new(
				StringName("Transient%03d" % cycle),
				Vector2i(8 + cycle % 20, 22 + cycle % 3),
				"s",
				Color(0.55, 0.82, 1.0),
			)
		)
		var actors_with_transient: Array = _base_actors.duplicate()
		actors_with_transient.append(transient_actor)
		_map_view.call(&"set_actors", actors_with_transient)
		(
			_map_view
			. call(
				&"play_projectile_trail",
				outbound_path,
				{
					"style": &"bolt",
					"duration_seconds": 0.18,
					"color": Color(0.45, 0.82, 1.0),
				},
			)
		)
		_map_view.call(&"play_cell_burst", Vector2i(26, 15), Color(1.0, 0.55, 0.20), "*")
		_map_view.call(&"set_map_render_mode", &"pixel")
		(
			_map_view
			. call(
				&"play_projectile_trail",
				inbound_path,
				{"style": &"orb", "duration_seconds": 0.16, "color": Color(0.9, 0.4, 1.0)},
			)
		)
		_map_view.call(&"play_cell_burst", Vector2i(29, 15), Color(0.9, 0.4, 1.0), "+")
		_map_view.call(&"set_actors", _base_actors)
		_map_view.call(&"set_map_render_mode", &"ascii")
		transient_actor.free()
		await process_frame
		var cycle_pixel: Dictionary = _debug_snapshot().get("pixel", {})
		max_actor_children = maxi(
			max_actor_children, int(cycle_pixel.get("actor_layer_child_count", 0))
		)
		_expect_equal(
			int(cycle_pixel.get("renderer_child_count", 0)),
			initial_renderer_children,
			"Renderer child count grew during mode switching",
		)
		_expect_equal(
			int(cycle_pixel.get("effects", {}).get("child_count", 0)),
			initial_effect_children,
			"Fixed effect pool allocated extra children",
		)
	await process_frame
	await process_frame
	_map_view.call(&"set_reduced_vfx_enabled", false)
	_map_view.call(&"set_map_render_mode", &"pixel")
	await process_frame
	var final_pixel: Dictionary = _debug_snapshot().get("pixel", {})
	_expect_equal(int(final_pixel.get("actor_count", 0)), 3, "Mode stress duplicated actor views")
	_expect_equal(
		int(final_pixel.get("actor_layer_child_count", 0)),
		3,
		"Mode stress leaked actor-view children",
	)
	_expect(max_actor_children <= 3, "Queued actor views accumulated across stress frames")
	_expect(
		int(final_pixel.get("actor_view_create_count", 0)) >= MODE_SWITCH_CYCLES + 3,
		"Mode stress did not exercise actor-view creation",
	)
	_expect(
		int(final_pixel.get("actor_view_remove_count", 0)) >= MODE_SWITCH_CYCLES,
		"Mode stress did not exercise actor-view removal",
	)
	_expect(
		int(final_pixel.get("transient_reset_count", 0)) >= MODE_SWITCH_CYCLES * 2,
		"Renderer transitions did not reset transient effects",
	)
	var effects: Dictionary = final_pixel.get("effects", {})
	_expect_equal(int(effects.get("active_count", -1)), 0, "Mode stress left particles active")
	_expect_equal(
		int(effects.get("pool_size", 0)),
		initial_effect_children,
		"Mode stress changed fixed particle capacity",
	)
	var final_node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_expect(
		final_node_count <= initial_node_count + MAX_NODE_GROWTH,
		"Mode stress leaked nodes: %d -> %d" % [initial_node_count, final_node_count],
	)
	var final_static_memory: int = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var static_memory_growth: int = final_static_memory - initial_static_memory
	_expect(
		static_memory_growth <= MAX_STATIC_MEMORY_GROWTH_BYTES,
		(
			"Mode stress retained %.2f MiB of static memory"
			% (float(static_memory_growth) / float(1024 * 1024))
		),
	)
	_assert_shared_parity("mode-switch stress")
	print(
		(
			"  %d live mode-switch cycles kept 3 actor views, %d effect nodes, and %.2f MiB memory growth"
			% [
				MODE_SWITCH_CYCLES,
				initial_effect_children,
				float(static_memory_growth) / float(1024 * 1024),
			]
		)
	)


func _check_dense_actor_performance() -> void:
	var dense_actors: Array[FakeActor] = []
	for index: int in range(DENSE_ACTOR_COUNT):
		var actor_name: StringName = &"Player" if index == 0 else StringName("Load%02d" % index)
		var cell: Vector2i = (
			Vector2i(24, 15) if index == 0 else Vector2i(6 + index % 32, 2 + (index / 32) * 5)
		)
		var glyph: String = "@" if index == 0 else "e"
		dense_actors.append(FakeActor.new(actor_name, cell, glyph, Color(0.72, 0.82, 0.92)))
	_map_view.call(&"set_map_render_mode", &"pixel")
	_map_view.call(&"set_actors", dense_actors)
	await process_frame
	await process_frame
	var before: Dictionary = _debug_snapshot().get("pixel", {})
	_expect_equal(
		int(before.get("actor_count", 0)), DENSE_ACTOR_COUNT, "Dense actor fixture did not render"
	)
	var tile_rebuilds_before: int = int(before.get("tile_rebuild_count", 0))
	var actor_syncs_before: int = int(before.get("actor_sync_count", 0))
	var started_usec: int = Time.get_ticks_usec()
	for turn: int in range(DENSE_TURN_UPDATES):
		for index: int in range(1, dense_actors.size()):
			var actor: FakeActor = dense_actors[index]
			actor.grid_position = Vector2i(6 + (index + turn) % 32, 2 + (index / 32) * 5)
		_map_view.call(&"set_actors", dense_actors)
	var elapsed_msec: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	await process_frame
	await process_frame
	var after: Dictionary = _debug_snapshot().get("pixel", {})
	_expect_equal(
		int(after.get("actor_count", 0)), DENSE_ACTOR_COUNT, "Dense updates duplicated actor views"
	)
	_expect_equal(
		int(after.get("actor_layer_child_count", 0)),
		DENSE_ACTOR_COUNT,
		"Dense updates leaked actor children",
	)
	_expect_equal(
		int(after.get("tile_rebuild_count", 0)),
		tile_rebuilds_before,
		"Actor-only updates rebuilt static tile layers",
	)
	_expect(
		int(after.get("actor_sync_count", 0)) - actor_syncs_before >= DENSE_TURN_UPDATES,
		"Dense turn updates did not reach the actor renderer",
	)
	_expect(
		elapsed_msec <= MAX_DENSE_UPDATE_MSEC,
		(
			"Dense actor updates exceeded %.0f ms release ceiling: %.2f ms"
			% [MAX_DENSE_UPDATE_MSEC, elapsed_msec]
		),
	)
	_map_view.call(&"set_actors", _base_actors)
	for actor: FakeActor in dense_actors:
		actor.free()
	await process_frame
	await process_frame
	_expect_equal(
		int(_debug_snapshot().get("pixel", {}).get("actor_count", 0)),
		3,
		"Dense fixture did not restore the baseline actor set",
	)
	_assert_shared_parity("dense actor restore")
	print(
		(
			"  %d actors x %d turn updates completed in %.2f ms without static tile rebuilds"
			% [DENSE_ACTOR_COUNT, DENSE_TURN_UPDATES, elapsed_msec]
		)
	)


func _check_viewport_resize_stability() -> void:
	var sizes: Array[Vector2i] = [
		Vector2i(720, 610),
		Vector2i(1180, 760),
		Vector2i(800, 600),
		Vector2i(1600, 900),
		Vector2i(960, 540),
	]
	_map_view.call(&"set_map_render_mode", &"pixel")
	var expected_origin: Vector2i = _debug_snapshot().get("pixel", {}).get(
		"view_origin", Vector2i(-1, -1)
	)
	for viewport_size: Vector2i in sizes:
		_viewport.size = viewport_size
		await process_frame
		if _is_visual_capture_supported():
			RenderingServer.force_draw()
			await process_frame
			var image: Image = _viewport.get_texture().get_image()
			_expect_equal(
				image.get_size(), viewport_size, "Viewport resize capture dimensions drifted"
			)
		else:
			_expect_equal(_viewport.size, viewport_size, "Headless viewport dimensions drifted")
		var pixel: Dictionary = _debug_snapshot().get("pixel", {})
		_expect_equal(int(pixel.get("actor_count", 0)), 3, "Viewport resize lost actor views")
		_expect_equal(
			pixel.get("view_origin"),
			expected_origin,
			"Browser resize changed gameplay-cell framing"
		)
		_assert_shared_parity("viewport %dx%d" % [viewport_size.x, viewport_size.y])
	_viewport.size = VIEWPORT_SIZE
	_map_view.call(&"set_map_render_mode", &"ascii")
	await process_frame
	var ascii_debug: Dictionary = _debug_snapshot()
	var ascii_pixel: Dictionary = ascii_debug.get("pixel", {})
	_expect(
		not bool(ascii_pixel.get("visible", true)), "ASCII did not hide pixel base after resize"
	)
	_expect_equal(
		int(ascii_pixel.get("process_mode", -1)),
		Node.PROCESS_MODE_DISABLED,
		"ASCII did not disable pixel processing after resize",
	)
	_expect(
		bool(ascii_debug.get("ascii", {}).get("tactical_active", false)),
		"ASCII tactical rendering was not restored after resize",
	)
	print("  five viewport sizes preserved framing, actors, parity, and ASCII restoration")


func _is_visual_capture_supported() -> bool:
	return DisplayServer.get_name() != "headless"


func _capture_mode(mode: StringName) -> Image:
	_map_view.call(&"set_map_render_mode", mode)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	return _viewport.get_texture().get_image()


func _sampled_difference_count(left: Image, right: Image) -> int:
	var sample_width: int = 180
	var sample_height: int = 152
	var left_sample: Image = left.duplicate()
	var right_sample: Image = right.duplicate()
	left_sample.resize(sample_width, sample_height, Image.INTERPOLATE_NEAREST)
	right_sample.resize(sample_width, sample_height, Image.INTERPOLATE_NEAREST)
	var left_data: PackedByteArray = left_sample.get_data()
	var right_data: PackedByteArray = right_sample.get_data()
	var difference_count: int = 0
	var byte_count: int = mini(left_data.size(), right_data.size())
	for index: int in range(0, byte_count, 4):
		var channel_difference: int = 0
		for channel: int in range(3):
			channel_difference += absi(
				int(left_data[index + channel]) - int(right_data[index + channel])
			)
		if channel_difference >= 24:
			difference_count += 1
	return difference_count


func _shared_snapshot() -> Dictionary:
	return _debug_snapshot().get("shared", {})


func _debug_snapshot() -> Dictionary:
	if _map_view == null or not _map_view.has_method(&"get_presentation_debug_snapshot"):
		return {}
	return _map_view.call(&"get_presentation_debug_snapshot")


func _assert_shared_parity(context: String) -> void:
	_expect_equal(
		_shared_snapshot(),
		_baseline_snapshot,
		"Renderer activity mutated shared semantic state during %s" % context,
	)


func _cleanup() -> void:
	if _map_view != null and is_instance_valid(_map_view):
		_map_view.call(&"set_actors", [])
		_map_view.queue_free()
	await process_frame
	await process_frame
	for actor: FakeActor in _base_actors:
		if is_instance_valid(actor):
			actor.free()
	_base_actors.clear()
	if _viewport != null and is_instance_valid(_viewport):
		_viewport.queue_free()
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition or _failed:
		return
	_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected or _failed:
		return
	_fail("%s: got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
