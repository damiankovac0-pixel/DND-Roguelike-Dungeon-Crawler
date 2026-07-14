## Phase 5 regression coverage for pooled particles, actor feedback, and lighting.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##     res://scripts/tests/test_pixel_vfx_polish.gd
extends SceneTree

const PRESENTATION_DIR: String = "res://scripts/ui/map_presentation/"
const VISUAL_CATALOG_DIR: String = "res://resources/visuals/catalogs/"
const GRID_LAYOUT_PATH: String = PRESENTATION_DIR + "map_grid_layout.gd"
const STATE_PATH: String = PRESENTATION_DIR + "map_presentation_state.gd"
const EFFECT_POOL_PATH: String = PRESENTATION_DIR + "pixel_effect_pool.gd"
const ACTOR_VIEW_SCENE_PATH: String = "res://scenes/rendering/pixel_actor_view.tscn"
const ACTOR_CATALOG_PATH: String = VISUAL_CATALOG_DIR + "prototype_actor_visual_catalog.tres"
const PIXEL_RENDERER_SCENE_PATH: String = "res://scenes/rendering/pixel_map_renderer.tscn"


class FakeEnemyData:
	extends Resource

	var is_boss: bool = false
	var boss_id: StringName = &""


class FakeActor:
	extends Node2D

	var display_name: String = "Actor"
	var grid_position: Vector2i = Vector2i.ZERO
	var glyph: String = "a"
	var color: Color = Color.WHITE
	var alive: bool = true
	var enemy_data: Resource

	func setup_actor(
		actor_name: String, actor_glyph: String, actor_color: Color, start_position: Vector2i
	) -> void:
		display_name = actor_name
		glyph = actor_glyph
		color = actor_color
		grid_position = start_position

	func initialize_from_data(data: Resource, start_position: Vector2i) -> void:
		enemy_data = data
		grid_position = start_position

	func is_alive() -> bool:
		return alive


var _failed: bool = false
var _grid_script: GDScript
var _state_script: GDScript
var _effect_pool_script: GDScript
var _actor_view_scene: PackedScene
var _actor_catalog: Resource
var _renderer_scene: PackedScene
var _player: FakeActor
var _boss: FakeActor


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_dependencies()
	if _failed:
		return
	_create_actor_fixture()
	var layout: RefCounted = _new_layout()
	var player_state: RefCounted = _new_state([_player])
	await _check_fixed_effect_pool(layout, player_state)
	if _failed:
		_cleanup_actors()
		return
	await _check_actor_shader_feedback(layout, player_state.get("visible_cells"))
	if _failed:
		_cleanup_actors()
		return
	await _check_renderer_effect_profiles(layout, player_state)
	_cleanup_actors()
	if _failed:
		return
	print("Pixel VFX polish checks passed")
	quit(0)


func _load_dependencies() -> void:
	_grid_script = load(GRID_LAYOUT_PATH)
	_state_script = load(STATE_PATH)
	_effect_pool_script = load(EFFECT_POOL_PATH)
	_actor_view_scene = load(ACTOR_VIEW_SCENE_PATH)
	_actor_catalog = load(ACTOR_CATALOG_PATH)
	_renderer_scene = load(PIXEL_RENDERER_SCENE_PATH)
	_expect(_grid_script != null and _grid_script.can_instantiate(), "Grid layout failed to load")
	_expect(_state_script != null and _state_script.can_instantiate(), "State failed to load")
	_expect(
		_effect_pool_script != null and _effect_pool_script.can_instantiate(),
		"Effect pool failed to load",
	)
	_expect(_actor_view_scene != null, "Actor view scene failed to load")
	_expect(_actor_catalog != null, "Actor visual catalogue failed to load")
	_expect(_renderer_scene != null, "Pixel renderer scene failed to load")


func _create_actor_fixture() -> void:
	_player = FakeActor.new()
	_player.name = &"Player"
	_player.setup_actor("Hero", "@", Color(0.35, 0.95, 1.0), Vector2i(4, 4))
	_boss = FakeActor.new()
	_boss.name = &"Observer"
	_boss.setup_actor("The Observer", "O", Color(0.76, 0.48, 1.0), Vector2i(7, 5))
	var boss_data: FakeEnemyData = FakeEnemyData.new()
	boss_data.is_boss = true
	boss_data.boss_id = &"observer"
	_boss.enemy_data = boss_data


func _new_layout() -> RefCounted:
	var layout: RefCounted = _grid_script.new()
	layout.call(&"configure", Vector2i(16, 16), Vector2(20, 44), Vector2i(41, 34))
	layout.call(&"set_map_size", Vector2i(12, 10))
	layout.call(&"set_focus_cell", _player.grid_position)
	return layout


func _new_state(actors: Array) -> RefCounted:
	var state: RefCounted = _state_script.new()
	var map_data: Array = []
	var visible_cells: Dictionary = {}
	for y: int in range(10):
		var row: Array[int] = []
		for x: int in range(12):
			row.append(0)
			visible_cells[Vector2i(x, y)] = true
		map_data.append(row)
	state.call(&"capture_map", map_data)
	state.set(&"visible_cells", visible_cells)
	state.set(&"explored_cells", visible_cells.duplicate())
	state.call(&"mark_visibility_changed")
	state.call(&"capture_actors", actors)
	(
		state
		. set(
			&"atmosphere_profile",
			{
				"void_color": Color(0.03, 0.04, 0.08, 1.0),
				"shimmer_color": Color(0.3, 0.5, 1.0, 0.06),
			},
		)
	)
	state.set(&"atmosphere_enabled", true)
	state.call(&"mark_environment_changed")
	return state


func _check_fixed_effect_pool(layout: RefCounted, state: RefCounted) -> void:
	var pool: Node2D = _effect_pool_script.new()
	root.add_child(pool)
	await process_frame
	_expect_equal(
		int(pool.call(&"configure", layout, true)), OK, "CPU effect pool failed to configure"
	)
	pool.call(&"present", state)
	var initial: Dictionary = pool.call(&"get_debug_snapshot")
	_expect_equal(initial.get("backend"), &"cpu", "Headless fallback should use CPU particles")
	_expect_equal(int(initial.get("pool_size", 0)), 12, "Effect pool size drifted")
	_expect_equal(int(initial.get("child_count", 0)), 12, "Effect pool was not preallocated")
	for index: int in range(20):
		var accepted: bool = bool(
			(
				pool
				. call(
					&"play_event",
					{
						"type": &"cell_burst",
						"payload":
						{
							"cell": Vector2i(5, 5),
							"color": Color(1.0, 0.34, 0.47, 0.92),
						},
					},
				)
			)
		)
		_expect(accepted, "Visible pooled effect %d was rejected" % index)
	var saturated: Dictionary = pool.call(&"get_debug_snapshot")
	_expect_equal(int(saturated.get("active_count", 0)), 12, "Pool exceeded fixed capacity")
	_expect_equal(int(saturated.get("reuse_count", 0)), 8, "Oldest-slot reuse count drifted")
	_expect_equal(int(saturated.get("child_count", 0)), 12, "Events allocated extra nodes")
	var hidden_accepted: bool = bool(
		(
			pool
			. call(
				&"play_event",
				{"type": &"cell_burst", "payload": {"cell": Vector2i(99, 99)}},
			)
		)
	)
	_expect(not hidden_accepted, "Off-view particle effect bypassed visibility gating")
	pool.call(&"set_reduced_vfx", true)
	_expect_equal(
		int(pool.call(&"get_debug_snapshot").get("active_count", -1)),
		0,
		"Enabling Reduced VFX should clear active particles",
	)
	(
		pool
		. call(
			&"play_event",
			{
				"type": &"cell_burst",
				"payload": {"cell": Vector2i(5, 5), "color": Color.WHITE},
			},
		)
	)
	var reduced: Dictionary = pool.call(&"get_debug_snapshot")
	_expect_equal(int(reduced.get("last_particle_amount", 0)), 3, "Reduced VFX amount drifted")
	_expect(
		float(reduced.get("last_lifetime", 1.0)) < 0.34,
		"Reduced VFX should shorten particle lifetime",
	)
	await create_timer(0.36).timeout
	_expect_equal(
		int(pool.call(&"get_debug_snapshot").get("active_count", -1)),
		0,
		"Completed particle slots were not released",
	)
	pool.queue_free()
	await process_frame
	print("  fixed particle pool caps nodes and uses the Web-safe CPU fallback")


func _check_actor_shader_feedback(layout: RefCounted, visible_cells: Dictionary) -> void:
	var player_view: Node2D = _actor_view_scene.instantiate()
	root.add_child(player_view)
	await process_frame
	var player_snapshot: Dictionary = {
		"id": 1001,
		"visual_id": &"actor/player",
		"kind": &"player",
		"cell": _player.grid_position,
		"facing": &"right",
		"alive": true,
		"is_boss": false,
	}
	var player_frames: SpriteFrames = _actor_catalog.call(&"sprite_frames_for", player_snapshot)
	player_view.call(&"initialize_view", player_snapshot, player_frames, Color.WHITE, layout, false)
	var player_cells: Array[Vector2i] = [_player.grid_position]
	(
		player_view
		. call(
			&"apply_snapshot",
			player_snapshot,
			player_cells,
			visible_cells,
			false,
		)
	)
	player_view.call(&"play_cosmetic", &"hurt")
	var hurt_debug: Dictionary = player_view.call(&"get_debug_snapshot")
	_expect(bool(hurt_debug.get("feedback_material", false)), "Actor shader material was missing")
	_expect(bool(hurt_debug.get("feedback_active", false)), "Hurt feedback did not activate")
	_expect(
		float(hurt_debug.get("flash_amount", 0.0)) > 0.9,
		"Hurt feedback did not start with a readable flash",
	)
	_expect(
		hurt_debug.get("visual_position", Vector2.ZERO) != Vector2.ZERO,
		"Normal hurt feedback should include renderer-local recoil",
	)
	await create_timer(0.20).timeout
	player_view.call(&"reset_transients")
	player_view.call(&"set_reduced_vfx", true)
	player_view.call(&"play_cosmetic", &"hurt")
	var reduced_debug: Dictionary = player_view.call(&"get_debug_snapshot")
	_expect_equal(
		reduced_debug.get("visual_position"),
		Vector2.ZERO,
		"Reduced VFX should remove actor recoil",
	)
	_expect(
		float(reduced_debug.get("flash_amount", 1.0)) <= 0.35,
		"Reduced VFX should cap actor flash intensity",
	)
	player_view.queue_free()
	await process_frame

	var boss_view: Node2D = _actor_view_scene.instantiate()
	root.add_child(boss_view)
	await process_frame
	var boss_cells: Array[Vector2i] = _boss_cells()
	var boss_snapshot: Dictionary = {
		"id": 2002,
		"visual_id": &"boss/observer",
		"kind": &"boss",
		"cell": _boss.grid_position,
		"facing": &"left",
		"alive": true,
		"is_boss": true,
	}
	var boss_frames: SpriteFrames = _actor_catalog.call(&"sprite_frames_for", boss_snapshot)
	(
		boss_view
		. call(
			&"initialize_view",
			boss_snapshot,
			boss_frames,
			Color(0.76, 0.48, 1.0),
			layout,
			false,
		)
	)
	boss_view.call(&"apply_snapshot", boss_snapshot, boss_cells, visible_cells, false)
	boss_view.call(&"play_spawn_intro")
	var intro_debug: Dictionary = boss_view.call(&"get_debug_snapshot")
	_expect_equal(int(intro_debug.get("boss_intro_count", 0)), 1, "Boss intro was not played")
	_expect(
		intro_debug.get("visual_scale", Vector2.ONE) != Vector2.ONE,
		"Boss intro should animate the visual root",
	)
	var death_events: Array[int] = []
	boss_view.connect(&"death_finished", func(actor_id: int) -> void: death_events.append(actor_id))
	boss_view.call(&"play_cosmetic", &"death")
	await create_timer(0.30).timeout
	_expect(death_events.is_empty(), "Boss death feedback ended before its authored sequence")
	await create_timer(0.24).timeout
	_expect_equal(death_events, [2002], "Boss death completion signal drifted")
	boss_view.queue_free()
	await process_frame
	print("  actor shader feedback adds hit flash, recoil, and extended boss death timing")


func _check_renderer_effect_profiles(layout: RefCounted, state: RefCounted) -> void:
	var renderer: Node2D = _renderer_scene.instantiate()
	root.add_child(renderer)
	await process_frame
	_expect_equal(
		int(renderer.call(&"initialize_renderer", layout)),
		OK,
		"Pixel renderer failed to initialize with effect layers",
	)
	renderer.call(&"set_render_profile", &"pixel")
	renderer.call(&"present", state)
	var initial: Dictionary = renderer.call(&"get_debug_snapshot")
	var expected_backend: StringName = (
		&"cpu" if OS.has_feature("web") or DisplayServer.get_name() == "headless" else &"gpu"
	)
	_expect_equal(
		initial.get("effects", {}).get("backend"),
		expected_backend,
		"Renderer selected the wrong platform particle backend",
	)
	_expect(
		int(initial.get("lighting", {}).get("lit_cell_count", 0)) > 0,
		"Simulated lighting did not shade visible outer cells",
	)
	var intro_event: Dictionary = {
		"type": &"boss_spawn_intro",
		"payload":
		{
			"cell": _boss.grid_position,
			"occupied_cells": _boss_cells(),
			"color": _boss.color,
		},
	}
	renderer.call(&"play_event", intro_event)
	var pending: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(pending.get("pending_boss_intro_count", 0)),
		1,
		"Pre-snapshot boss intro was not retained",
	)
	_expect(
		bool(pending.get("shake_active", false)), "Full Pixel boss intro should shake map layers"
	)
	_expect_equal(
		int(pending.get("effects", {}).get("active_count", 0)),
		1,
		"Boss intro did not acquire a particle slot",
	)
	state.call(&"capture_actors", [_player, _boss])
	(
		state
		. set(
			&"boss_visuals",
			{
				_boss.grid_position:
				{
					"occupied_cells": _boss_cells(),
					"color": _boss.color,
				}
			},
		)
	)
	state.call(&"mark_overlay_changed")
	renderer.call(&"present", state)
	await process_frame
	var replayed: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(replayed.get("pending_boss_intro_count", -1)),
		0,
		"Boss intro was not consumed after snapshot replay",
	)
	var boss_debug: Dictionary = replayed.get("actor_views", {}).get(_boss.get_instance_id(), {})
	_expect_equal(
		int(boss_debug.get("boss_intro_count", 0)),
		1,
		"Spawned boss view did not receive its retained intro",
	)
	renderer.call(&"set_render_profile", &"hybrid")
	(
		renderer
		. call(
			&"play_event",
			{
				"type": &"actor_animation",
				"actor_id": _player.get_instance_id(),
				"cell": _player.grid_position,
				"animation": &"hurt",
			},
		)
	)
	var hybrid: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect(not bool(hybrid.get("shake_active", true)), "Hybrid must keep ASCII overlays aligned")
	_expect(
		int(hybrid.get("effects", {}).get("event_count", 0)) >= 2,
		"Hybrid actor event did not retain additive pixel effects",
	)
	renderer.call(&"set_render_profile", &"pixel")
	renderer.call(&"set_reduced_vfx", true)
	renderer.call(&"play_event", intro_event)
	var reduced: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect(not bool(reduced.get("shake_active", true)), "Reduced VFX must suppress map shake")
	_expect_equal(
		int(reduced.get("effects", {}).get("last_particle_amount", 0)),
		3,
		"Renderer did not propagate Reduced VFX to particles",
	)
	renderer.call(&"reset_transients")
	var reset: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(reset.get("effects", {}).get("active_count", -1)),
		0,
		"Renderer reset left active particle slots",
	)
	_expect(not bool(reset.get("shake_active", true)), "Renderer reset left map shake active")
	renderer.call(&"set_renderer_active", false)
	_expect_equal(
		renderer.process_mode,
		Node.PROCESS_MODE_DISABLED,
		"Inactive renderer should suspend all VFX processing",
	)
	renderer.queue_free()
	await process_frame
	print("  renderer profiles retain boss intros and isolate shake from Hybrid and Reduced VFX")


func _boss_cells() -> Array[Vector2i]:
	return [
		Vector2i(6, 4),
		Vector2i(7, 4),
		Vector2i(8, 4),
		Vector2i(6, 5),
		Vector2i(7, 5),
		Vector2i(8, 5),
	]


func _cleanup_actors() -> void:
	if is_instance_valid(_player):
		_player.free()
	if is_instance_valid(_boss):
		_boss.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_fail("%s: got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	push_error(message)
	quit(1)
