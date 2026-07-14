## Phase 1 regression coverage for ASCII-safe map renderer mode preferences.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_map_render_mode.gd
extends SceneTree

const MAP_PRESENTATION_SCRIPT_DIR: String = "res://scripts/ui/map_presentation/"
const MODE_SCRIPT_PATH: String = MAP_PRESENTATION_SCRIPT_DIR + "map_render_mode.gd"
const CONTROLLER_SCRIPT_PATH: String = (
	MAP_PRESENTATION_SCRIPT_DIR + "map_presentation_controller.gd"
)
const MAP_VIEW_SCRIPT_PATH: String = "res://scripts/ui/map_view.gd"
const SENSORY_SCRIPT_PATH: String = "res://scripts/ui/sensory_feedback.gd"
const GAME_SCENE_PATH: String = "res://scenes/game.tscn"
const LEGACY_MAP_VIEW_METHODS: Array[StringName] = [
	&"configure_map",
	&"set_biome_theme",
	&"set_visibility",
	&"set_actors",
	&"set_items",
	&"set_containers",
	&"set_enemy_intents",
	&"set_targeting",
	&"set_traps",
	&"set_secret_walls",
	&"set_boss_room",
	&"set_boss_visuals",
	&"play_boss_spawn_intro",
	&"clear_boss_visuals",
	&"set_boss_telegraphs",
	&"set_boss_hazards",
	&"has_active_boss_visuals",
	&"play_cell_burst",
	&"has_active_cell_bursts",
	&"set_reduced_vfx_enabled",
	&"play_projectile_trail",
	&"has_active_projectile_trails",
	&"clear_projectile_trails",
	&"set_atmosphere_enabled",
	&"is_atmosphere_enabled",
	&"has_active_atmosphere_animation",
	&"get_atmosphere_profile",
]

var _failed: bool = false
var _mode_script: GDScript
var _controller_script: GDScript
var _map_view_script: GDScript
var _sensory_script: GDScript
var _settings_path: String = ""
var _settings_absolute_path: String = ""
var _settings_existed: bool = false
var _settings_backup: PackedByteArray = PackedByteArray()
var _settings_restored: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_scripts()
	if _failed:
		return
	_backup_settings()
	_check_mode_normalization()
	if _failed:
		return
	_check_ascii_only_controller()
	if _failed:
		return
	await _check_settings_compatibility()
	if _failed:
		return
	_check_map_view_compatibility()
	if _failed:
		return
	await _check_game_mode_sync()
	if _failed:
		return
	_restore_settings()
	print("Map renderer mode checks passed")
	quit(0)


func _load_scripts() -> void:
	_mode_script = load(MODE_SCRIPT_PATH)
	_controller_script = load(CONTROLLER_SCRIPT_PATH)
	_map_view_script = load(MAP_VIEW_SCRIPT_PATH)
	_sensory_script = load(SENSORY_SCRIPT_PATH)
	for script: GDScript in [_mode_script, _controller_script, _map_view_script, _sensory_script]:
		if script == null or not script.can_instantiate():
			_fail("Renderer mode dependency failed to load or instantiate")
			return


func _check_mode_normalization() -> void:
	_expect_normalized_mode(&"ascii", &"ascii", "ASCII StringName")
	_expect_normalized_mode("hybrid", &"hybrid", "Hybrid String")
	_expect_normalized_mode(&"pixel", &"pixel", "Pixel StringName")
	_expect_normalized_mode("full_pixel", &"ascii", "obsolete value")
	_expect_normalized_mode("PIXEL", &"ascii", "wrong-case value")
	_expect_normalized_mode(42, &"ascii", "wrong-type value")
	_expect_normalized_mode(null, &"ascii", "null value")
	if _failed:
		return
	if not bool(_mode_script.is_known(&"hybrid")):
		_fail("Hybrid should be a known requested renderer mode")
		return
	if bool(_mode_script.is_known("full_pixel")):
		_fail("full_pixel must not become a second persisted mode vocabulary")
		return
	print("  mode parser accepts only ascii, hybrid, and pixel")


func _expect_normalized_mode(value: Variant, expected: StringName, label: String) -> void:
	if _failed:
		return
	var actual: StringName = _mode_script.normalize(value)
	if actual != expected:
		_fail("%s normalized to %s instead of %s" % [label, actual, expected])


func _check_ascii_only_controller() -> void:
	var controller: RefCounted = _controller_script.new()
	_check_controller_defaults(controller)
	if _failed:
		return
	_check_controller_hybrid_request(controller)
	if _failed:
		return
	_check_controller_pixel_and_invalid_requests(controller)
	if _failed:
		return
	print("  controller preserves requests while ASCII remains the only renderer")


func _check_controller_defaults(controller: RefCounted) -> void:
	if StringName(controller.call(&"get_requested_mode")) != &"ascii":
		_fail("Map presentation controller should request ASCII by default")
		return
	if StringName(controller.call(&"get_effective_mode")) != &"ascii":
		_fail("Map presentation controller should render ASCII by default")


func _check_controller_hybrid_request(controller: RefCounted) -> void:
	controller.call(&"set_requested_mode", &"hybrid")
	if StringName(controller.call(&"get_requested_mode")) != &"hybrid":
		_fail("Controller should retain a normalized Hybrid request")
		return
	if StringName(controller.call(&"get_effective_mode")) != &"ascii":
		_fail("Unavailable Hybrid request must resolve to effective ASCII")
		return
	if bool(controller.call(&"is_requested_mode_available")):
		_fail("Hybrid must remain unavailable without a registered backend")


func _check_controller_pixel_and_invalid_requests(controller: RefCounted) -> void:
	controller.call(&"set_requested_mode", &"pixel")
	if StringName(controller.call(&"get_effective_mode")) != &"ascii":
		_fail("Unavailable Pixel request must resolve to effective ASCII")
		return
	controller.call(&"set_requested_mode", "invalid")
	if StringName(controller.call(&"get_requested_mode")) != &"ascii":
		_fail("Invalid request must normalize to requested ASCII")
		return
	if not bool(controller.call(&"is_requested_mode_available")):
		_fail("ASCII must always be available")


func _check_settings_compatibility() -> void:
	if not _write_sensory_only_settings():
		return
	await _check_missing_setting_and_persistence()
	if _failed:
		return
	await _check_stored_hybrid_setting()
	if _failed:
		return
	await _check_invalid_stored_setting()
	if _failed:
		return
	print("  renderer preference is backward-compatible with sensory settings")


func _write_sensory_only_settings() -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("sensory", "audio_enabled", false)
	config.set_value("sensory", "reduced_vfx", true)
	if config.save(_settings_path) == OK:
		return true
	_fail("Failed to prepare settings without a graphics section")
	return false


func _check_missing_setting_and_persistence() -> void:
	var sensory_feedback: Control = await _new_sensory_feedback()
	if sensory_feedback == null:
		return
	if StringName(sensory_feedback.call(&"get_map_render_mode")) != &"ascii":
		sensory_feedback.queue_free()
		_fail("Missing graphics setting should default to ASCII")
		return
	sensory_feedback.call(&"set_map_render_mode", &"hybrid", true)
	sensory_feedback.queue_free()
	await process_frame
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(_settings_path) != OK:
		_fail("Map renderer preference was not saved")
		return
	if bool(saved.get_value("sensory", "audio_enabled", true)):
		_fail("Saving renderer mode must preserve existing sensory settings")
		return
	var saved_mode: Variant = saved.get_value("graphics", "map_render_mode", "")
	if not (saved_mode is String):
		_fail("Renderer mode must persist as a plain string")
		return
	if saved_mode != "hybrid":
		_fail("Hybrid request was not stored under graphics/map_render_mode")


func _check_stored_hybrid_setting() -> void:
	var sensory_feedback: Control = await _new_sensory_feedback()
	if sensory_feedback == null:
		return
	if StringName(sensory_feedback.call(&"get_map_render_mode")) != &"hybrid":
		sensory_feedback.queue_free()
		_fail("Stored Hybrid request should load on a new settings owner")
		return
	sensory_feedback.queue_free()
	await process_frame


func _check_invalid_stored_setting() -> void:
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(_settings_path) != OK:
		_fail("Failed to reload settings before wrong-type check")
		return
	saved.set_value("graphics", "map_render_mode", 99)
	if saved.save(_settings_path) != OK:
		_fail("Failed to prepare wrong-type renderer preference")
		return
	var sensory_feedback: Control = await _new_sensory_feedback()
	if sensory_feedback == null:
		return
	if StringName(sensory_feedback.call(&"get_map_render_mode")) != &"ascii":
		sensory_feedback.queue_free()
		_fail("Wrong-type stored renderer preference must load as ASCII")
		return
	sensory_feedback.call(&"set_map_render_mode", "full_pixel", true)
	if StringName(sensory_feedback.call(&"get_map_render_mode")) != &"ascii":
		sensory_feedback.queue_free()
		_fail("Obsolete renderer value must normalize before persistence")
		return
	sensory_feedback.queue_free()
	await process_frame


func _check_map_view_compatibility() -> void:
	var map_view: Node2D = _map_view_script.new()
	for method: StringName in LEGACY_MAP_VIEW_METHODS:
		if not map_view.has_method(method):
			map_view.free()
			_fail("MapView lost legacy public method: %s" % method)
			return
	map_view.call(&"set_map_render_mode", &"hybrid")
	if StringName(map_view.call(&"get_requested_map_render_mode")) != &"hybrid":
		map_view.free()
		_fail("MapView facade did not retain requested Hybrid mode")
		return
	if StringName(map_view.call(&"get_effective_map_render_mode")) != &"ascii":
		map_view.free()
		_fail("MapView facade must keep rendering ASCII during Phase 1")
		return
	map_view.call(&"set_map_render_mode", &"pixel")
	if StringName(map_view.call(&"get_effective_map_render_mode")) != &"ascii":
		map_view.free()
		_fail("MapView facade must fall back from Pixel to ASCII during Phase 1")
		return
	map_view.free()
	print("  MapView preserves legacy calls and safely resolves unavailable backends")


func _check_game_mode_sync() -> void:
	if not _write_game_mode_settings():
		return
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing for renderer mode integration")
		return
	var game: Node = await _instantiate_game_for_mode_sync(game_manager)
	if game == null:
		return
	var initial_mode_valid: bool = _check_game_initial_mode(game)
	if initial_mode_valid:
		_check_game_runtime_mode(game)
	game_manager.call(&"abandon_run")
	game.queue_free()
	await process_frame
	if _failed:
		return
	print("  game startup and runtime preference changes sync into MapView")


func _write_game_mode_settings() -> bool:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("sensory", "audio_enabled", false)
	config.set_value("sensory", "reduced_vfx", true)
	config.set_value("graphics", "map_render_mode", "hybrid")
	if config.save(_settings_path) == OK:
		return true
	_fail("Failed to prepare game renderer preference")
	return false


func _instantiate_game_for_mode_sync(game_manager: Node) -> Node:
	game_manager.call(&"prepare_character", "debug", {})
	var game_scene: PackedScene = load(GAME_SCENE_PATH)
	if game_scene == null:
		_fail("Game scene failed to load for renderer mode integration")
		return null
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	return game


func _check_game_initial_mode(game: Node) -> bool:
	var map_view: Node = game.get("map_view")
	var sensory_feedback: Control = game.get("sensory_feedback")
	if map_view == null or sensory_feedback == null:
		_fail("Game did not expose MapView and SensoryFeedback after startup")
		return false
	if StringName(map_view.call(&"get_requested_map_render_mode")) != &"hybrid":
		_fail("Game did not sync stored Hybrid request into MapView")
		return false
	if StringName(map_view.call(&"get_effective_map_render_mode")) != &"hybrid":
		_fail("Game should activate the registered Hybrid prototype")
		return false
	if not _check_game_graphics_control(game):
		return false
	if not _check_game_hybrid_output(map_view):
		return false
	return true


func _check_game_runtime_mode(game: Node) -> bool:
	var map_view: Node = game.get("map_view")
	var sensory_feedback: Control = game.get("sensory_feedback")
	sensory_feedback.call(&"set_map_render_mode", &"pixel", false)
	if StringName(map_view.call(&"get_requested_map_render_mode")) != &"pixel":
		_fail("Runtime renderer preference signal did not reach MapView")
		return false
	if StringName(map_view.call(&"get_effective_map_render_mode")) != &"ascii":
		_fail("Pixel must remain unavailable until its tactical overlays reach parity")
		return false
	var option: OptionButton = game.get("pause_map_renderer_option")
	option.item_selected.emit(1)
	if StringName(map_view.call(&"get_effective_map_render_mode")) != &"hybrid":
		_fail("Pause graphics control did not reactivate Hybrid")
		return false
	var saved: ConfigFile = ConfigFile.new()
	if saved.load(_settings_path) != OK:
		_fail("Pause graphics control did not persist its selection")
		return false
	if StringName(saved.get_value("graphics", "map_render_mode", &"ascii")) != &"hybrid":
		_fail("Pause graphics control persisted the wrong renderer mode")
		return false
	return true


func _check_game_graphics_control(game: Node) -> bool:
	var option: OptionButton = game.get("pause_map_renderer_option")
	if option == null or option.item_count != 3:
		_fail("Pause menu must expose the three canonical map mode labels")
		return false
	if option.selected != 1 or option.is_item_disabled(1):
		_fail(
			(
				"Hybrid graphics option mismatch: selected=%d disabled=%s available=%s"
				% [
					option.selected,
					option.is_item_disabled(1),
					game.get("map_view").call(&"is_map_render_mode_available", &"hybrid"),
				]
			)
		)
		return false
	if not option.is_item_disabled(2):
		_fail("Unavailable Full Pixel Map option should remain disabled")
		return false
	return true


func _check_game_hybrid_output(map_view: Node) -> bool:
	var pixel_renderer: Node = map_view.get_node_or_null("PixelMapRenderer")
	if pixel_renderer == null or not pixel_renderer.visible:
		_fail("Hybrid game startup did not expose the pixel backend")
		return false
	var debug: Dictionary = pixel_renderer.call(&"get_debug_snapshot")
	if int(debug.get("ground_cell_count", 0)) <= 0:
		_fail("Hybrid game startup did not render explored terrain")
		return false
	if not bool(debug.get("player_visible", false)):
		_fail("Hybrid game startup did not render the live player snapshot")
		return false
	if not _check_live_actor_views(pixel_renderer, debug):
		return false
	return true


func _check_live_actor_views(pixel_renderer: Node, debug: Dictionary) -> bool:
	var state: RefCounted = pixel_renderer.get("_state")
	if state == null:
		_fail("Hybrid game startup did not retain presentation state")
		return false
	var expected_actor_count: int = 0
	var kinds: Dictionary = {}
	for snapshot_value: Variant in state.get("actors"):
		if snapshot_value is not Dictionary or not bool(snapshot_value.get("alive", false)):
			continue
		expected_actor_count += 1
		kinds[snapshot_value.get("kind", &"")] = true
	if int(debug.get("actor_count", 0)) != expected_actor_count:
		_fail("Hybrid actor view count diverged from live authoritative snapshots")
		return false
	for required_kind: StringName in [&"player", &"shopkeeper", &"enemy"]:
		if not kinds.has(required_kind):
			_fail("Hybrid game startup missed actor kind: %s" % required_kind)
			return false
	return true


func _new_sensory_feedback() -> Control:
	var sensory_feedback: Control = _sensory_script.new()
	if sensory_feedback == null:
		_fail("SensoryFeedback instance creation failed")
		return null
	root.add_child(sensory_feedback)
	await process_frame
	return sensory_feedback


func _backup_settings() -> void:
	_settings_path = String(_sensory_script.SETTINGS_PATH)
	_settings_absolute_path = ProjectSettings.globalize_path(_settings_path)
	_settings_existed = FileAccess.file_exists(_settings_path)
	if _settings_existed:
		_settings_backup = FileAccess.get_file_as_bytes(_settings_path)


func _restore_settings() -> void:
	if _settings_restored or _settings_path.is_empty():
		return
	_settings_restored = true
	if _settings_existed:
		var restore: FileAccess = FileAccess.open(_settings_path, FileAccess.WRITE)
		if restore != null:
			restore.store_buffer(_settings_backup)
			restore.close()
	else:
		DirAccess.remove_absolute(_settings_absolute_path)


func _fail(message: String) -> void:
	_failed = true
	_restore_settings()
	printerr(message)
	quit(1)
