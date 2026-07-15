## Phase 3 regression coverage for animated pixel actors and boss footprints.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##     res://scripts/tests/test_pixel_actor_rendering.gd
extends SceneTree

const PRESENTATION_DIR: String = "res://scripts/ui/map_presentation/"
const VISUAL_CATALOG_DIR: String = "res://resources/visuals/catalogs/"
const GRID_LAYOUT_PATH: String = PRESENTATION_DIR + "map_grid_layout.gd"
const STATE_PATH: String = PRESENTATION_DIR + "map_presentation_state.gd"
const ACTOR_CATALOG_PATH: String = VISUAL_CATALOG_DIR + "actor_visual_catalog.tres"
const PIXEL_RENDERER_SCENE_PATH: String = "res://scenes/rendering/pixel_map_renderer.tscn"
const MAP_VIEW_PATH: String = "res://scripts/ui/map_view.gd"
const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const EXPECTED_ANIMATIONS: Array[StringName] = [
	&"idle", &"move", &"attack", &"cast", &"hurt", &"death"
]
const EXPECTED_PLAYER_ACTIONS: Array[StringName] = [
	&"attack_sword",
	&"attack_bow",
	&"attack_staff",
	&"use_scroll",
	&"drink_potion",
	&"fighter_cleave",
	&"fighter_second_wind",
	&"fighter_whirlwind",
	&"ranger_focus",
	&"ranger_volley",
	&"ranger_quickstep",
	&"arcane_spark",
	&"wizard_frost_nova",
	&"wizard_chain_lightning",
]


class FakeEnemyData:
	extends Resource

	var is_boss: bool = false
	var boss_id: StringName = &""

	var visual_id: StringName = &""


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
var _map_view_script: GDScript
var _renderer_scene: PackedScene
var _catalog: Resource
var _actors: Array[FakeActor] = []
var _player: FakeActor
var _enemy: FakeActor
var _shopkeeper: FakeActor
var _summon: FakeActor
var _boss: FakeActor
var _boss_cells: Array[Vector2i] = []
var _saved_player_class: StringName = &""
var _game_manager: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_dependencies()
	if _failed:
		return
	_create_actor_fixture()
	if _failed:
		_cleanup_actors()
		return
	_check_catalogue_animations()
	if _failed:
		_cleanup_actors()
		return
	var state: RefCounted = _build_state()
	_check_snapshot_contract(state)
	if _failed:
		_cleanup_actors()
		return
	await _check_renderer_lifecycle(state)
	await _check_map_view_event_bridge()
	_cleanup_actors()
	if _failed:
		return
	print("Pixel actor rendering checks passed")
	quit(0)


func _load_dependencies() -> void:
	_grid_script = load(GRID_LAYOUT_PATH)
	_state_script = load(STATE_PATH)
	_renderer_scene = load(PIXEL_RENDERER_SCENE_PATH)
	_map_view_script = load(MAP_VIEW_PATH)
	_catalog = load(ACTOR_CATALOG_PATH)
	_expect(
		_grid_script != null and _grid_script.can_instantiate(),
		"MapGridLayout failed to load",
	)
	_expect(
		_state_script != null and _state_script.can_instantiate(),
		"MapPresentationState failed to load",
	)
	_expect(_renderer_scene != null, "Pixel renderer scene failed to load")
	_expect(
		_map_view_script != null and _map_view_script.can_instantiate(),
		"MapView failed to load",
	)
	_expect(_catalog != null, "Actor visual catalogue failed to load")
	if _catalog != null:
		_expect_equal(str(_catalog.call(&"validate")), "", "Actor catalogue validation failed")


func _create_actor_fixture() -> void:
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_expect(false, "GameManager autoload missing")
		return
	_saved_player_class = _game_manager.pending_character_class
	_player = _new_actor(&"Player", "Hero", "@", Vector2i(2, 2), Color.WHITE)
	var enemy_visual_data: FakeEnemyData = FakeEnemyData.new()
	enemy_visual_data.visual_id = &"actor/enemy/brute"
	_enemy = _new_actor(&"Goblin", "Goblin", "g", Vector2i(3, 2), Color(0.4, 0.9, 0.4))
	_enemy.enemy_data = enemy_visual_data
	_shopkeeper = _new_actor(
		&"Shopkeeper", "Shopkeeper", "S", Vector2i(2, 4), Color(1.0, 0.82, 0.32)
	)
	_summon = _new_actor(
		&"SummonedWisp", "Summoned Wisp", "w", Vector2i(4, 4), Color(0.7, 0.5, 1.0)
	)
	_summon.set_meta(&"summoned_minion", true)
	_boss = _new_actor(&"Observer", "The Observer", "O", Vector2i(7, 5), Color(0.8, 0.5, 1.0))
	var boss_data: FakeEnemyData = FakeEnemyData.new()
	boss_data.is_boss = true
	boss_data.boss_id = &"observer"
	_boss.enemy_data = boss_data
	_boss_cells = [
		Vector2i(6, 4),
		Vector2i(7, 4),
		Vector2i(8, 4),
		Vector2i(6, 5),
		Vector2i(7, 5),
		Vector2i(8, 5),
	]
	_actors = [_player, _enemy, _shopkeeper, _summon, _boss]


func _new_actor(
	node_name: StringName, display_name: String, glyph: String, cell: Vector2i, color: Color
) -> FakeActor:
	var actor: FakeActor = FakeActor.new()
	actor.name = node_name
	actor.setup_actor(display_name, glyph, color, cell)
	return actor


func _check_catalogue_animations() -> void:
	var snapshots: Array[Dictionary] = [
		{"visual_id": &"actor/player/fighter", "kind": &"player", "is_boss": false},
		{"visual_id": &"actor/enemy/humanoid", "kind": &"enemy", "is_boss": false},
		{"visual_id": &"actor/shopkeeper", "kind": &"shopkeeper", "is_boss": false},
		{"visual_id": &"actor/summon", "kind": &"summon", "is_boss": false},
		{
			"visual_id": &"boss/observer",
			"kind": &"boss",
			"is_boss": true,
			"boss_id": &"observer",
		},
	]
	for snapshot: Dictionary in snapshots:
		var frames: SpriteFrames = _catalog.call(&"sprite_frames_for", snapshot)
		_expect(frames != null, "Catalogue returned no SpriteFrames")
		for animation: StringName in EXPECTED_ANIMATIONS:
			_expect(frames.has_animation(animation), "Missing actor animation: %s" % animation)
			_expect_equal(
				frames.get_frame_count(animation),
				2,
				"Prototype animation should contain two deterministic frames",
			)
		_expect(frames.get_animation_loop(&"idle"), "Idle animation should loop")
		_expect(frames.get_animation_loop(&"move"), "Move animation should loop")
		_expect(not frames.get_animation_loop(&"death"), "Death animation must not loop")
		var first_frame: Texture2D = frames.get_frame_texture(&"idle", 0)
		_expect(first_frame is AtlasTexture, "Actor animation frame must use an atlas region")
		if first_frame is AtlasTexture:
			var expected_size: Vector2 = Vector2(80, 64) if snapshot["is_boss"] else Vector2(16, 16)
			_expect_equal(
				(first_frame as AtlasTexture).region.size,
				expected_size,
				"Actor atlas frame dimensions drifted",
			)
	_check_boss_catalog_rows()
	var player_snapshot: Dictionary = snapshots[0]
	var cached_frames: SpriteFrames = _catalog.call(&"sprite_frames_for", player_snapshot)
	_expect(
		cached_frames == _catalog.call(&"sprite_frames_for", player_snapshot),
		"Catalogue should reuse immutable SpriteFrames per visual ID",
	)
	print("  explicit catalogue provides cached idle/move/attack/cast/hurt/death frames")
	# Compatibility alias coverage
	for alias_id: StringName in [&"actor/player", &"actor/enemy"]:
		var alias_frames: SpriteFrames = _catalog.call(
			&"sprite_frames_for", {"visual_id": alias_id, "kind": &"enemy", "is_boss": false}
		)
		_expect(alias_frames != null, "Compatibility alias %s must return frames" % alias_id)
		for animation: StringName in EXPECTED_ANIMATIONS:
			_expect(
				alias_frames.has_animation(animation),
				"Alias %s missing animation: %s" % [alias_id, animation],
			)
		_expect(
			alias_frames.get_animation_loop(&"idle"),
			"Alias %s idle should loop" % alias_id,
		)
		var alias_frame: AtlasTexture = alias_frames.get_frame_texture(&"idle", 0) as AtlasTexture
		_expect(alias_frame != null, "Alias %s frame must use atlas region" % alias_id)
	_check_actor_catalog_rows()
	_check_player_action_animations()
	_check_actor_tint_colors()


func _check_boss_catalog_rows() -> void:
	var boss_ids: Array[StringName] = [&"observer", &"seraphine", &"vorrak", &"kaelros", &"nyxara"]
	for row: int in range(boss_ids.size()):
		var boss_id: StringName = boss_ids[row]
		var snapshot: Dictionary = {
			"visual_id": StringName("boss/%s" % boss_id),
			"kind": &"boss",
			"is_boss": true,
			"boss_id": boss_id,
		}
		var frames: SpriteFrames = _catalog.call(&"sprite_frames_for", snapshot)
		var frame: AtlasTexture = frames.get_frame_texture(&"idle", 0) as AtlasTexture
		_expect(frame != null, "Boss catalogue frame must be an AtlasTexture")
		if frame != null:
			_expect_equal(
				frame.region.position.y,
				float(row * 64),
				"Boss catalogue row mapping drifted for %s" % boss_id,
			)


func _check_actor_catalog_rows() -> void:
	var actor_ids: Array[Dictionary] = [
		{"id": &"actor/player/fighter", "row": 0},
		{"id": &"actor/player/ranger", "row": 1},
		{"id": &"actor/player/wizard", "row": 2},
		{"id": &"actor/enemy/humanoid", "row": 3},
		{"id": &"actor/enemy/brute", "row": 4},
		{"id": &"actor/enemy/undead", "row": 5},
		{"id": &"actor/enemy/beast", "row": 6},
		{"id": &"actor/enemy/flyer", "row": 7},
		{"id": &"actor/enemy/construct", "row": 8},
		{"id": &"actor/enemy/caster", "row": 9},
		{"id": &"actor/enemy/aquatic", "row": 10},
		{"id": &"actor/enemy/aberration", "row": 11},
		{"id": &"actor/shopkeeper", "row": 12},
		{"id": &"actor/summon", "row": 13},
	]
	var used_rows: Dictionary = {}
	for entry: Dictionary in actor_ids:
		var snapshot: Dictionary = {"visual_id": entry["id"], "kind": &"enemy", "is_boss": false}
		var frames: SpriteFrames = _catalog.call(&"sprite_frames_for", snapshot)
		var frame: AtlasTexture = frames.get_frame_texture(&"idle", 0) as AtlasTexture
		var expected_row: int = int(entry["row"])
		_expect(frame != null, "%s catalogue frame must be AtlasTexture" % entry["id"])
		if frame != null:
			_expect_equal(
				frame.region.position.y,
				float(expected_row * 16),
				"Actor catalogue row mapping drifted for %s" % entry["id"],
			)
		used_rows[expected_row] = entry["id"]
	var enemy_visual_ids: Dictionary = {}
	var boss_ids: Dictionary = {}
	for path: String in ResourcePathsScript.ENEMY_PATHS:
		var enemy_data: Resource = load(path)
		_expect(enemy_data != null, "Enemy resource failed to load: %s" % path)
		if enemy_data == null:
			continue
		if bool(enemy_data.get("is_boss")):
			var boss_id: StringName = enemy_data.get("boss_id")
			_expect(boss_id != &"", "Boss ID is empty: %s" % path)
			_expect(not boss_ids.has(boss_id), "Duplicate boss ID: %s" % boss_id)
			boss_ids[boss_id] = true
			continue
		var visual_id: StringName = enemy_data.get("visual_id")
		_expect(visual_id != &"", "Enemy visual ID is empty: %s" % path)
		_expect(not enemy_visual_ids.has(visual_id), "Duplicate enemy visual ID: %s" % visual_id)
		enemy_visual_ids[visual_id] = path
		var enemy_frames: SpriteFrames = (
			_catalog
			. call(
				&"sprite_frames_for",
				{"visual_id": visual_id, "kind": &"enemy", "is_boss": false},
			)
		)
		for animation: StringName in EXPECTED_ANIMATIONS:
			_expect(
				enemy_frames.has_animation(animation),
				"Enemy %s is missing animation %s" % [visual_id, animation],
			)
			_expect_equal(
				enemy_frames.get_frame_count(animation),
				2,
				"Enemy %s animation %s must have two authored frames" % [visual_id, animation],
			)
		var idle_frame: AtlasTexture = enemy_frames.get_frame_texture(&"idle", 0) as AtlasTexture
		_expect(idle_frame != null, "Enemy %s idle frame is not atlas-backed" % visual_id)
		if idle_frame != null:
			var row: int = int(idle_frame.region.position.y / 16.0)
			_expect(row >= 14 and row <= 50, "Enemy %s uses invalid row %d" % [visual_id, row])
			_expect(
				not used_rows.has(row),
				(
					"Enemy %s shares actor atlas row %d with %s"
					% [visual_id, row, used_rows.get(row, &"")]
				),
			)
			used_rows[row] = visual_id
		_expect_equal(
			(
				_catalog
				. call(
					&"tint_for",
					{"visual_id": visual_id, "kind": &"enemy", "is_boss": false},
				)
			),
			Color.WHITE,
			"Authored enemy %s must render without fallback tint" % visual_id,
		)
	_expect_equal(enemy_visual_ids.size(), 37, "All non-boss enemies need unique visuals")
	_expect_equal(boss_ids.size(), 5, "All boss resources need stable boss IDs")
	_expect_equal(used_rows.size(), 51, "Every actor visual must own one atlas row")
	print("  actor catalogue maps 37 unique enemies and 14 shared actors to distinct rows")


func _check_player_action_animations() -> void:
	var action_sheet: Texture2D = _catalog.get("player_action_sheet")
	_expect(action_sheet != null, "Player action sheet is missing")
	var class_rows: Dictionary = {
		&"actor/player/fighter": 0,
		&"actor/player/ranger": 1,
		&"actor/player/wizard": 2,
	}
	for visual_id: StringName in class_rows:
		var row: int = int(class_rows[visual_id])
		var frames: SpriteFrames = (
			_catalog
			. call(
				&"sprite_frames_for",
				{"visual_id": visual_id, "kind": &"player", "is_boss": false},
			)
		)
		for action_index: int in range(EXPECTED_PLAYER_ACTIONS.size()):
			var action_id: StringName = EXPECTED_PLAYER_ACTIONS[action_index]
			_expect(
				frames.has_animation(action_id),
				"Player %s is missing action animation %s" % [visual_id, action_id],
			)
			_expect_equal(
				frames.get_frame_count(action_id),
				2,
				"Player action %s must have two authored frames" % action_id,
			)
			_expect(
				not frames.get_animation_loop(action_id),
				"Player action %s must complete before returning to idle" % action_id,
			)
			for frame_index: int in range(2):
				var frame: AtlasTexture = (
					frames.get_frame_texture(action_id, frame_index) as AtlasTexture
				)
				_expect(frame != null, "Player action %s frame is not atlas-backed" % action_id)
				if frame != null:
					_expect(frame.atlas == action_sheet, "Player action frame uses the wrong sheet")
					_expect_equal(
						frame.region.position,
						Vector2((action_index * 2 + frame_index) * 16, row * 16),
						(
							"Player %s action %s mapped to the wrong class frame"
							% [visual_id, action_id]
						),
					)
	print("  three player classes expose distinct weapon, consumable, and skill frames")


func _check_actor_tint_colors() -> void:
	var known_ids: Array[StringName] = [
		&"actor/player/fighter",
		&"actor/player/ranger",
		&"actor/player/wizard",
		&"actor/enemy/humanoid",
		&"actor/enemy/brute",
		&"actor/enemy/undead",
		&"actor/enemy/beast",
		&"actor/enemy/flyer",
		&"actor/enemy/construct",
		&"actor/enemy/caster",
		&"actor/enemy/aquatic",
		&"actor/enemy/aberration",
		&"actor/shopkeeper",
		&"actor/summon",
	]
	for visual_id: StringName in known_ids:
		var tint: Color = _catalog.call(
			&"tint_for", {"visual_id": visual_id, "kind": &"enemy", "is_boss": false}
		)
		_expect_equal(
			tint,
			Color.WHITE,
			"Authored visual %s must return Color.WHITE tint" % visual_id,
		)
	# Compatibility alias tint checks
	for alias_id: StringName in [&"actor/player", &"actor/enemy"]:
		var alias_tint: Color = _catalog.call(
			&"tint_for", {"visual_id": alias_id, "kind": &"enemy", "is_boss": false}
		)
		_expect_equal(
			alias_tint,
			Color.WHITE,
			"Compatibility alias %s must return Color.WHITE tint" % alias_id,
		)
	# Unknown visual must return visible safe fallback (magenta)
	var unknown_tint: Color = _catalog.call(
		&"tint_for", {"visual_id": &"actor/unknown", "kind": &"enemy", "is_boss": false}
	)
	_expect(
		unknown_tint != Color.WHITE,
		"Unknown visual must not return Color.WHITE — should use safe fallback",
	)
	_expect_equal(
		unknown_tint,
		Color(1.0, 0.0, 1.0),
		"Unknown visual tint must be visible magenta fallback",
	)
	print(
		"  actor tint colours: known authored IDs return WHITE, unknown uses visible magenta fallback"
	)


func _build_state() -> RefCounted:
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
	state.call(&"capture_actors", _actors)
	(
		state
		. set(
			&"boss_visuals",
			{
				_boss.grid_position:
				{
					"display_name": _boss.display_name,
					"occupied_cells": _boss_cells.duplicate(),
					"phase": 1,
				}
			},
		)
	)
	state.call(&"mark_overlay_changed")
	return state


func _check_snapshot_contract(state: RefCounted) -> void:
	var snapshots: Array = state.get("actors")
	_expect_equal(snapshots.size(), 5, "State should contain every actor category")
	var by_id: Dictionary = _snapshots_by_id(snapshots)
	_expect_equal(by_id.size(), 5, "Actor snapshot IDs must be unique for the session")
	_expect_equal(by_id[_player.get_instance_id()]["kind"], &"player", "Player kind drifted")
	_expect_equal(by_id[_enemy.get_instance_id()]["kind"], &"enemy", "Enemy kind drifted")
	_expect_equal(
		by_id[_shopkeeper.get_instance_id()]["kind"],
		&"shopkeeper",
		"Shopkeeper kind drifted",
	)
	_expect_equal(by_id[_summon.get_instance_id()]["kind"], &"summon", "Summon kind drifted")
	_expect_equal(by_id[_boss.get_instance_id()]["kind"], &"boss", "Boss kind drifted")
	_expect_equal(
		by_id[_boss.get_instance_id()]["visual_id"],
		&"boss/observer",
		"Boss visual ID must remain semantic and explicit",
	)
	_enemy.grid_position = Vector2i(4, 2)
	state.call(&"capture_actors", _actors)
	by_id = _snapshots_by_id(state.get("actors"))
	_expect_equal(
		by_id[_enemy.get_instance_id()]["facing"],
		&"right",
		"Actor facing should follow renderer-neutral grid movement",
	)
	_enemy.grid_position = Vector2i(3, 2)
	state.call(&"capture_actors", _actors)
	by_id = _snapshots_by_id(state.get("actors"))
	_expect_equal(
		by_id[_enemy.get_instance_id()]["facing"],
		&"left",
		"Actor facing should preserve the latest horizontal direction",
	)
	print("  state snapshots classify actors and preserve stable IDs and facing")
	if _game_manager != null:
		var saved_class: StringName = _game_manager.pending_character_class
		for player_class: StringName in [&"fighter", &"ranger", &"wizard"]:
			_game_manager.pending_character_class = player_class
			state.call(&"capture_actors", _actors)
			by_id = _snapshots_by_id(state.get("actors"))
			_expect_equal(
				by_id[_player.get_instance_id()]["visual_id"],
				StringName("actor/player/%s" % player_class),
				(
					"Player class %s must produce actor/player/%s visual_id"
					% [player_class, player_class]
				),
			)
		_game_manager.pending_character_class = saved_class
		state.call(&"capture_actors", _actors)
	# Enemy resource visual_id coverage
	by_id = _snapshots_by_id(state.get("actors"))
	var enemy_visual_id: StringName = by_id[_enemy.get_instance_id()]["visual_id"]
	_expect_equal(
		enemy_visual_id,
		&"actor/enemy/brute",
		"Enemy with enemy_data.visual_id must use the explicit resource-driven value",
	)


func _check_renderer_lifecycle(state: RefCounted) -> void:
	var renderer: Node2D = _renderer_scene.instantiate()
	root.add_child(renderer)
	await process_frame
	var layout: RefCounted = _grid_script.new()
	layout.call(&"configure", Vector2i(16, 16), Vector2(20, 44), Vector2i(12, 10))
	_expect_equal(
		int(renderer.call(&"initialize_renderer", layout)),
		OK,
		"Pixel renderer should initialize with its actor catalogue",
	)
	renderer.call(&"present", state)
	await process_frame
	_check_initial_views(renderer, layout)
	_check_boss_visibility_mask(renderer, state)
	_check_hidden_actor(renderer, state)
	await _check_actor_movement(renderer, state, layout)
	_check_events_and_reset(renderer, state)
	await _check_death_and_revival(renderer, state)
	_check_actor_removal(renderer, state)
	_check_missing_actor_catalogue(layout)
	renderer.call(&"shutdown_renderer")
	renderer.queue_free()
	await process_frame
	await process_frame
	print("  renderer synchronizes actor lifecycle, movement, events, and boss footprints")


func _check_initial_views(renderer: Node2D, layout: RefCounted) -> void:
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(int(debug.get("actor_count", 0)), 5, "Renderer should create one view per actor")
	_expect_equal(
		int(debug.get("visible_actor_count", 0)), 5, "All fixture actors should begin visible"
	)
	_expect_equal(int(debug.get("boss_actor_count", 0)), 1, "Renderer should identify one boss")
	var actor_views: Dictionary = debug.get("actor_views", {})
	var boss_debug: Dictionary = actor_views.get(_boss.get_instance_id(), {})
	_expect_equal(
		boss_debug.get("footprint_cells"),
		_boss_cells,
		"Boss view must consume authoritative occupied cells exactly",
	)
	var expected_boss_center: Vector2 = (
		Vector2(layout.call(&"cell_to_local", Vector2i(6, 4))) + Vector2(24, 16)
	)
	_expect_equal(
		boss_debug.get("target_position"),
		expected_boss_center,
		"Boss sprite anchor should center over its authoritative footprint bounds",
	)


func _check_boss_visibility_mask(renderer: Node2D, state: RefCounted) -> void:
	var visible_cells: Dictionary = Dictionary(state.get("visible_cells")).duplicate()
	visible_cells.erase(_boss_cells[0])
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)
	var boss_debug: Dictionary = _actor_debug(renderer, _boss)
	_expect(bool(boss_debug.get("visible", false)), "Visible boss footprint should remain marked")
	_expect(
		not bool(boss_debug.get("sprite_visible", true)),
		"Oversized boss sprite must not leak across a hidden footprint cell",
	)
	visible_cells[_boss_cells[0]] = true
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)
	boss_debug = _actor_debug(renderer, _boss)
	_expect(
		bool(boss_debug.get("sprite_visible", false)), "Fully visible boss should show its sprite"
	)


func _check_hidden_actor(renderer: Node2D, state: RefCounted) -> void:
	var visible_cells: Dictionary = Dictionary(state.get("visible_cells")).duplicate()
	visible_cells.erase(_enemy.grid_position)
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)
	var enemy_debug: Dictionary = _actor_debug(renderer, _enemy)
	_expect(not bool(enemy_debug.get("visible", true)), "Hidden enemy view must be invisible")
	_expect_equal(
		int(renderer.call(&"get_debug_snapshot").get("actor_count", 0)),
		5,
		"Visibility changes must not duplicate or remove actor views",
	)
	visible_cells[_enemy.grid_position] = true
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)


func _check_actor_movement(renderer: Node2D, state: RefCounted, layout: RefCounted) -> void:
	_enemy.grid_position = Vector2i(4, 2)
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	var enemy_debug: Dictionary = _actor_debug(renderer, _enemy)
	_expect_equal(enemy_debug.get("cell"), Vector2i(4, 2), "Enemy view cell did not update")
	_expect_equal(enemy_debug.get("animation"), &"move", "Grid movement should play move")
	_expect_equal(enemy_debug.get("facing"), &"right", "Moved enemy facing drifted")
	_expect(not bool(enemy_debug.get("flip_h", true)), "Right-facing enemy should not flip")
	await create_timer(0.16).timeout
	enemy_debug = _actor_debug(renderer, _enemy)
	_expect_equal(
		enemy_debug.get("position"),
		layout.call(&"cell_center_to_local", Vector2i(4, 2)),
		"Movement tween should finish at the authoritative cell center",
	)
	_expect_equal(enemy_debug.get("animation"), &"idle", "Movement should return to idle")
	renderer.call(&"set_reduced_vfx", true)
	_player.grid_position = Vector2i(3, 2)
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	var player_debug: Dictionary = _actor_debug(renderer, _player)
	_expect_equal(
		player_debug.get("position"),
		layout.call(&"cell_center_to_local", Vector2i(3, 2)),
		"Reduced VFX should snap movement without changing gameplay cells",
	)
	_expect_equal(player_debug.get("animation"), &"idle", "Reduced VFX should skip move loop")
	renderer.call(&"set_reduced_vfx", false)


func _check_events_and_reset(renderer: Node2D, state: RefCounted) -> void:
	var attack_event: Dictionary = {
		"type": &"actor_animation",
		"actor_id": _enemy.get_instance_id(),
		"cell": _enemy.grid_position,
		"animation": &"attack",
	}
	renderer.call(&"play_event", attack_event)
	renderer.call(&"play_event", attack_event)
	var enemy_debug: Dictionary = _actor_debug(renderer, _enemy)
	_expect_equal(enemy_debug.get("animation"), &"attack", "Attack event should play immediately")
	_expect_equal(
		int(enemy_debug.get("coalesced_event_count", 0)),
		1,
		"Repeated animation events should coalesce",
	)
	(
		renderer
		. call(
			&"play_event",
			{
				"type": &"actor_animation",
				"actor_id": _enemy.get_instance_id(),
				"animation": &"hurt",
			},
		)
	)
	enemy_debug = _actor_debug(renderer, _enemy)
	_expect_equal(enemy_debug.get("animation"), &"hurt", "Hurt should interrupt attack")
	var event_count: int = int(renderer.call(&"get_debug_snapshot").get("actor_event_count", 0))
	renderer.call(&"present", state)
	_expect_equal(
		int(renderer.call(&"get_debug_snapshot").get("actor_event_count", 0)),
		event_count,
		"State replay must not replay one-shot actor events",
	)
	renderer.call(&"reset_transients")
	enemy_debug = _actor_debug(renderer, _enemy)
	_expect_equal(enemy_debug.get("animation"), &"idle", "Transient reset should restore idle")
	for action_id: StringName in EXPECTED_PLAYER_ACTIONS:
		(
			renderer
			. call(
				&"play_event",
				{
					"type": &"actor_animation",
					"actor_id": _player.get_instance_id(),
					"cell": _player.grid_position,
					"animation": action_id,
				},
			)
		)
		var player_debug: Dictionary = _actor_debug(renderer, _player)
		_expect_equal(
			player_debug.get("animation"),
			action_id,
			"Renderer did not dispatch authored player action %s" % action_id,
		)
	renderer.call(&"reset_transients")
	var player_debug: Dictionary = _actor_debug(renderer, _player)
	_expect_equal(
		player_debug.get("animation"),
		&"idle",
		"Player action reset should restore idle",
	)


func _check_death_and_revival(renderer: Node2D, state: RefCounted) -> void:
	_enemy.alive = false
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	var enemy_debug: Dictionary = _actor_debug(renderer, _enemy)
	_expect_equal(enemy_debug.get("animation"), &"death", "Dead actor should play death once")
	await create_timer(0.32).timeout
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(int(debug.get("actor_count", 0)), 4, "Finished death view should be retired")
	_expect_equal(
		int(debug.get("retired_actor_count", 0)), 1, "Dead actor ID should prevent recreation"
	)
	_enemy.alive = true
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	debug = renderer.call(&"get_debug_snapshot")
	_expect_equal(int(debug.get("actor_count", 0)), 5, "Revived actor should recreate its view")
	_expect_equal(int(debug.get("retired_actor_count", 0)), 0, "Revival should clear retirement")
	_expect_equal(_actor_debug(renderer, _enemy).get("animation"), &"idle", "Revival should idle")
	_check_boss_death_footprint(renderer, state)
	_check_hidden_death_retirement(renderer, state)


func _check_boss_death_footprint(renderer: Node2D, state: RefCounted) -> void:
	state.set(&"boss_visuals", {})
	state.call(&"mark_overlay_changed")
	_boss.alive = false
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	var boss_debug: Dictionary = _actor_debug(renderer, _boss)
	_expect_equal(
		boss_debug.get("footprint_cells"),
		_boss_cells,
		"Boss death must retain the last authoritative footprint",
	)
	_boss.alive = true
	(
		state
		. set(
			&"boss_visuals",
			{
				_boss.grid_position:
				{
					"display_name": _boss.display_name,
					"occupied_cells": _boss_cells.duplicate(),
					"phase": 1,
				}
			},
		)
	)
	state.call(&"mark_overlay_changed")
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)


func _check_hidden_death_retirement(renderer: Node2D, state: RefCounted) -> void:
	var visible_cells: Dictionary = Dictionary(state.get("visible_cells")).duplicate()
	visible_cells.erase(_enemy.grid_position)
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	renderer.call(&"present", state)
	_enemy.alive = false
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(debug.get("actor_count", 0)),
		4,
		"Hidden dead actor should retire without waiting for an invisible animation",
	)
	_expect_equal(
		int(debug.get("retired_actor_count", 0)),
		1,
		"Hidden dead actor ID should remain retired",
	)
	_enemy.alive = true
	visible_cells[_enemy.grid_position] = true
	state.set(&"visible_cells", visible_cells)
	state.call(&"mark_visibility_changed")
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)


func _check_actor_removal(renderer: Node2D, state: RefCounted) -> void:
	_actors.erase(_shopkeeper)
	state.call(&"capture_actors", _actors)
	renderer.call(&"present", state)
	_expect_equal(
		int(renderer.call(&"get_debug_snapshot").get("actor_count", 0)),
		4,
		"Missing actor snapshot should remove exactly one view",
	)


func _check_missing_actor_catalogue(layout: RefCounted) -> void:
	var missing_renderer: Node2D = _renderer_scene.instantiate()
	missing_renderer.set("actor_catalog", null)
	root.add_child(missing_renderer)
	_expect(
		int(missing_renderer.call(&"initialize_renderer", layout)) != OK,
		"Missing essential actor catalogue must reject Hybrid activation",
	)
	_expect(
		not bool(missing_renderer.call(&"is_renderer_available")),
		"Missing actor catalogue renderer must remain unavailable",
	)
	missing_renderer.queue_free()


func _check_map_view_event_bridge() -> void:
	var map_view: Node2D = _map_view_script.new()
	root.add_child(map_view)
	await process_frame
	var map_data: Array = []
	var visible_cells: Dictionary = {}
	for y: int in range(10):
		var row: Array[int] = []
		for x: int in range(12):
			row.append(0)
			visible_cells[Vector2i(x, y)] = true
		map_data.append(row)
	map_view.call(&"configure_map", map_data)
	map_view.call(&"set_visibility", visible_cells, visible_cells)
	map_view.call(&"set_actors", [_enemy])
	map_view.call(&"set_enemy_intents", {_enemy.grid_position: &"melee"})
	(
		map_view
		. call(
			&"set_boss_telegraphs",
			{Vector2i(6, 5): {"glyph": "!", "color": Color.RED}},
		)
	)
	map_view.call(&"set_map_render_mode", &"hybrid")
	await process_frame
	var renderer: Node = map_view.get_node_or_null("PixelMapRenderer")
	_expect(renderer != null and renderer.visible, "MapView should activate pixel actor backend")
	if renderer == null:
		map_view.queue_free()
		return
	var state: RefCounted = renderer.get("_state")
	_expect_equal(
		Dictionary(state.get("enemy_intents")).get(_enemy.grid_position),
		&"melee",
		"Hybrid must retain shared ASCII enemy-intent semantics",
	)
	_expect(
		Dictionary(state.get("boss_telegraphs")).has(Vector2i(6, 5)),
		"Hybrid must retain shared ASCII boss-telegraph geometry",
	)
	var before_events: int = int(renderer.call(&"get_debug_snapshot").get("actor_event_count", 0))
	map_view.call(&"play_actor_event", _enemy, &"attack")
	var after_event: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(after_event.get("actor_event_count", 0)),
		before_events + 1,
		"MapView should forward one-shot actor events to the active backend",
	)
	map_view.call(&"set_map_render_mode", &"ascii")
	map_view.call(&"set_map_render_mode", &"hybrid")
	var after_replay: Dictionary = renderer.call(&"get_debug_snapshot")
	_expect_equal(
		int(after_replay.get("actor_event_count", 0)),
		before_events + 1,
		"Renderer switching must replay state without replaying cosmetic events",
	)
	_expect_equal(
		int(after_replay.get("actor_count", 0)),
		1,
		"Renderer switching must not duplicate actor views",
	)
	map_view.queue_free()
	await process_frame
	print("  MapView preserves ASCII tactical data and does not replay cosmetic events")


func _snapshots_by_id(snapshots: Array) -> Dictionary:
	var by_id: Dictionary = {}
	for snapshot_value: Variant in snapshots:
		if snapshot_value is Dictionary:
			by_id[int(snapshot_value.get("id", 0))] = snapshot_value
	return by_id


func _actor_debug(renderer: Node2D, actor: FakeActor) -> Dictionary:
	var debug: Dictionary = renderer.call(&"get_debug_snapshot")
	var actor_views: Dictionary = debug.get("actor_views", {})
	return actor_views.get(actor.get_instance_id(), {})


func _cleanup_actors() -> void:
	var actor_values: Array = [_player, _enemy, _shopkeeper, _summon, _boss]
	for actor_value: Variant in actor_values:
		if actor_value != null and is_instance_valid(actor_value):
			actor_value.free()
	_actors.clear()
	if _game_manager != null:
		_game_manager.pending_character_class = _saved_player_class


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
