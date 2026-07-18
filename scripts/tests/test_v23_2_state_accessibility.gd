## V23.2 state/accessibility regressions.
##
## Covers history filtering, run-summary cleanup, sensory preference persistence,
## reduced-motion backdrop behavior, and controller accessibility bindings.
extends SceneTree

const HISTORY_PATH: String = "user://character_history.json"
const SETTINGS_PATH: String = "user://dungeon_delver_settings.cfg"
const SENSORY_SCRIPT: GDScript = preload("res://scripts/ui/sensory_feedback.gd")
const BACKDROP_SCRIPT: GDScript = preload("res://scripts/ui/ascii_backdrop.gd")
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const EPSILON: float = 0.001
const REQUIRED_JOYPAD_ACTIONS: Array[StringName] = [
	&"ui_accept",
	&"ui_cancel",
	&"ui_up",
	&"ui_down",
	&"ui_left",
	&"ui_right",
	&"move_up",
	&"move_down",
	&"move_left",
	&"move_right",
	&"inventory",
	&"character_sheet",
	&"wait",
	&"use_potion",
	&"fire_ranged",
	&"class_ability",
]

var _failed: bool = false
var _cleanup_done: bool = false
var _history_backup_captured: bool = false
var _history_backup_exists: bool = false
var _history_backup_text: String = ""
var _settings_backup_captured: bool = false
var _settings_backup_exists: bool = false
var _settings_backup_text: String = ""
var _game_manager: Node = null
var _game_manager_backup: Dictionary = {}
var _owned_nodes: Array[Node] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(232002)
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload missing")
		return
	_capture_user_file_backups()
	if _failed:
		return
	_capture_game_manager_state(_game_manager)

	_check_history_migration_preserves_legitimate_entries(_game_manager)
	if _failed:
		return
	_check_last_run_summary_cleanup(_game_manager)
	if _failed:
		return
	await _check_all_sensory_preferences_persist()
	if _failed:
		return
	await _check_motion_disabled_backdrop_stops_processing()
	if _failed:
		return
	_check_required_actions_have_joypad_events()
	if _failed:
		return

	_cleanup()
	if _failed:
		return
	print("V23.2 state/accessibility checks passed")
	quit(0)


func _check_history_migration_preserves_legitimate_entries(game_manager: Node) -> void:
	var raw_history: Array = [
		{
			"name": "Fresh Delver",
			"floor": 7,
			"level": 4,
			"victory": false,
			"version": "23.1.0",
			"class": "fighter",
			"difficulty": "hard",
		},
		{
			"name": "Long Debug Name",
			"floor": 12,
			"level": 8,
			"victory": true,
			"version": "23.1.0",
			"class": "ranger",
			"difficulty": "nightmare",
		},
		{"name": "Old Delver", "floor": 4, "level": 2, "victory": false},
		{
			"name": "Patch Hero",
			"floor": 9,
			"level": 3,
			"victory": true,
			"version": "23.1.0",
			"difficulty": "veteran",
		},
		{
			"name": "debug",
			"floor": 25,
			"level": 20,
			"victory": true,
			"version": "23.1.0",
			"class": "fighter",
			"difficulty": "normal",
		},
		{
			"name": "Archived Debug Hero",
			"floor": 25,
			"level": 20,
			"victory": true,
			"version": "23.1.0",
			"class": "fighter",
			"difficulty": "normal",
			"archived_debug": true,
		},
		{
			"name": "Mage Survivor",
			"floor": 8,
			"level": 5,
			"victory": false,
			"version": "20.0.0",
			"class": "mage",
			"difficulty": null,
		},
		{"name": "Nameless Actual", "floor": 2, "level": 1, "victory": false},
		"not a dictionary",
	]
	_write_required_user_file(HISTORY_PATH, JSON.stringify(raw_history))
	if _failed:
		return
	game_manager.character_history = []
	game_manager._load_character_history()

	var names: Array[String] = _history_names(game_manager.character_history)
	for legitimate_name: String in [
		"Fresh Delver",
		"Long Debug Name",
		"Old Delver",
		"Patch Hero",
		"Mage Survivor",
		"Nameless Actual",
	]:
		_assert_true(
			names.has(legitimate_name),
			"legitimate history entry should survive migration: %s" % legitimate_name
		)
		if _failed:
			return
	_assert_true(not names.has("debug"), "explicit debug-name history entry should be filtered")
	if _failed:
		return
	_assert_true(
		not names.has("Archived Debug Hero"), "history entry with archived_debug should be filtered"
	)
	if _failed:
		return

	var entries_by_name: Dictionary = _history_entries_by_name(game_manager.character_history)
	_assert_equal(
		str((entries_by_name["Fresh Delver"] as Dictionary).get("difficulty", "")),
		"hard",
		"valid Hard difficulty should survive migration"
	)
	if _failed:
		return
	for normal_name: String in [
		"Long Debug Name",
		"Old Delver",
		"Patch Hero",
		"Mage Survivor",
		"Nameless Actual",
	]:
		_assert_equal(
			str((entries_by_name[normal_name] as Dictionary).get("difficulty", "")),
			"normal",
			"missing or invalid difficulty should migrate to Normal: %s" % normal_name
		)
		if _failed:
			return
	_assert_equal(
		str((entries_by_name["Mage Survivor"] as Dictionary).get("class", "")),
		"wizard",
		"legacy mage class should migrate to wizard"
	)
	if _failed:
		return

	var saved_filtered: Variant = JSON.parse_string(_read_required_user_file(HISTORY_PATH))
	if _failed:
		return
	if not (saved_filtered is Array):
		_fail("filtered history file should save as a JSON array")
		return
	var saved_filtered_names: Array[String] = _history_names(saved_filtered)
	_assert_equal(
		saved_filtered_names.size(),
		names.size(),
		"saved filtered history should match in-memory history"
	)
	if _failed:
		return

	var additive_history: Array = [
		{
			"name": "Persisted Missing Difficulty",
			"floor": 3,
			"level": 2,
			"victory": false,
			"class": "fighter",
		},
		{
			"name": "Persisted Invalid Difficulty",
			"floor": 5,
			"level": 4,
			"victory": true,
			"class": "ranger",
			"difficulty": "nightmare",
		},
		{
			"name": "Persisted Mage",
			"floor": 7,
			"level": 5,
			"victory": false,
			"class": "mage",
			"difficulty": null,
		},
	]
	_write_required_user_file(HISTORY_PATH, JSON.stringify(additive_history))
	if _failed:
		return
	game_manager.character_history = []
	game_manager._load_character_history()
	_assert_equal(
		game_manager.character_history.size(),
		additive_history.size(),
		"content-only migration should not add or remove history entries"
	)
	if _failed:
		return

	var saved_additive: Variant = JSON.parse_string(_read_required_user_file(HISTORY_PATH))
	if _failed:
		return
	if not (saved_additive is Array):
		_fail("content-migrated history file should save as a JSON array")
		return
	_assert_equal(
		saved_additive.size(),
		additive_history.size(),
		"content-changing migration should persist without changing array size"
	)
	if _failed:
		return
	var saved_additive_entries: Dictionary = _history_entries_by_name(saved_additive)
	for migrated_name: String in [
		"Persisted Missing Difficulty",
		"Persisted Invalid Difficulty",
		"Persisted Mage",
	]:
		var migrated_entry: Dictionary = saved_additive_entries[migrated_name] as Dictionary
		_assert_true(
			migrated_entry.has("difficulty"),
			"persisted migration should add a difficulty field: %s" % migrated_name
		)
		if _failed:
			return
		_assert_equal(
			str(migrated_entry.get("difficulty", "")),
			"normal",
			"persisted missing or invalid difficulty should be Normal: %s" % migrated_name
		)
		if _failed:
			return
	_assert_equal(
		str((saved_additive_entries["Persisted Mage"] as Dictionary).get("class", "")),
		"wizard",
		"persisted content-only migration should retain mage-to-wizard conversion"
	)


func _history_entries_by_name(history: Array) -> Dictionary:
	var entries_by_name: Dictionary = {}
	for entry: Variant in history:
		if entry is Dictionary:
			entries_by_name[str(entry.get("name", ""))] = entry
	return entries_by_name


func _check_last_run_summary_cleanup(game_manager: Node) -> void:
	game_manager.prepare_character(
		"Summary Hero",
		{"str": 15, "dex": 14, "con": 13, "int": 12, "wis": 10, "cha": 8},
		game_manager.CLASS_RANGER
	)
	game_manager.reset_run()
	game_manager.current_floor = 6
	game_manager.end_run(false)
	_assert_true(
		not game_manager.last_run_summary.is_empty(), "end_run should expose a last run summary"
	)
	if _failed:
		return
	_assert_equal(
		str(game_manager.last_run_summary.get("name", "")),
		"Summary Hero",
		"last run summary should describe the completed run before cleanup"
	)
	if _failed:
		return
	game_manager.clear_finished_run_context()
	_assert_true(
		game_manager.last_run_summary.is_empty(),
		"clear_finished_run_context should remove stale last_run_summary data"
	)
	if _failed:
		return
	game_manager.last_run_summary = {"stale": true}
	game_manager.abandon_run()
	_assert_true(
		game_manager.last_run_summary.is_empty(),
		"abandon_run should clear stale last_run_summary data"
	)
	if _failed:
		return
	game_manager.last_run_summary = {"stale": true}
	game_manager.reset_run()
	_assert_true(
		game_manager.last_run_summary.is_empty(),
		"reset_run should clear stale last_run_summary data"
	)


func _check_all_sensory_preferences_persist() -> void:
	var first: Control = _new_sensory_feedback()
	if first == null:
		return
	first.set_audio_enabled(false, false, true)
	first.set_master_volume(0.27, true)
	first.set_ambience_enabled(false, true)
	first.set_reduced_vfx_enabled(true, true)
	first.queue_free()
	_owned_nodes.erase(first)
	await process_frame

	var second: Control = _new_sensory_feedback()
	if second == null:
		return
	_assert_true(
		not second.is_audio_enabled(), "audio_enabled preference should persist as disabled"
	)
	if _failed:
		return
	_assert_float_equal(second.get_master_volume(), 0.27, "master_volume preference should persist")
	if _failed:
		return
	_assert_true(
		not second.is_ambience_enabled(), "ambience_enabled preference should persist as disabled"
	)
	if _failed:
		return
	_assert_true(
		second.is_reduced_vfx_enabled(), "reduced_vfx preference should persist as enabled"
	)
	if _failed:
		return

	second.set_audio_enabled(true, false, true)
	second.set_master_volume(0.91, true)
	second.set_ambience_enabled(true, true)
	second.set_reduced_vfx_enabled(false, true)
	second.queue_free()
	_owned_nodes.erase(second)
	await process_frame

	var third: Control = _new_sensory_feedback()
	if third == null:
		return
	_assert_true(third.is_audio_enabled(), "audio_enabled preference should persist as enabled")
	if _failed:
		return
	_assert_float_equal(
		third.get_master_volume(), 0.91, "updated master_volume preference should persist"
	)
	if _failed:
		return
	_assert_true(
		third.is_ambience_enabled(), "ambience_enabled preference should persist as enabled"
	)
	if _failed:
		return
	_assert_true(
		not third.is_reduced_vfx_enabled(), "reduced_vfx preference should persist as disabled"
	)
	third.queue_free()
	_owned_nodes.erase(third)
	await process_frame


func _check_motion_disabled_backdrop_stops_processing() -> void:
	var backdrop: Control = BACKDROP_SCRIPT.new()
	if backdrop == null:
		_fail("AsciiBackdrop instance creation failed")
		return
	backdrop.motion_enabled = false
	root.add_child(backdrop)
	_owned_nodes.append(backdrop)
	await process_frame
	_assert_true(
		not backdrop.is_processing(), "motion-disabled AsciiBackdrop should not process frames"
	)
	if _failed:
		return
	var elapsed_before: float = float(backdrop._elapsed)
	await process_frame
	await process_frame
	_assert_float_equal(
		float(backdrop._elapsed),
		elapsed_before,
		"motion-disabled AsciiBackdrop elapsed time should stay stopped"
	)
	if _failed:
		return
	backdrop.motion_enabled = true
	await process_frame
	_assert_true(backdrop.is_processing(), "re-enabled AsciiBackdrop should process again")
	if _failed:
		return
	backdrop.motion_enabled = false
	_assert_true(
		not backdrop.is_processing(),
		"disabling motion at runtime should stop AsciiBackdrop processing"
	)
	if _failed:
		return
	backdrop.queue_free()
	_owned_nodes.erase(backdrop)
	await process_frame

	var preference_writer: Control = _new_sensory_feedback()
	if preference_writer == null:
		return
	preference_writer.set_reduced_vfx_enabled(true, true)
	preference_writer.queue_free()
	_owned_nodes.erase(preference_writer)
	await process_frame

	var main_menu_scene: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	if main_menu_scene == null:
		_fail("main menu scene failed to load")
		return
	var main_menu: Control = main_menu_scene.instantiate() as Control
	if main_menu == null:
		_fail("main menu scene did not instantiate as Control")
		return
	root.add_child(main_menu)
	_owned_nodes.append(main_menu)
	await process_frame
	var background: Control = main_menu.get_node_or_null("Background") as Control
	if background == null:
		_fail("main menu missing Background control")
		return
	_assert_true(
		bool(background.get("motion_enabled")) == false,
		"reduced VFX preference should disable main-menu backdrop motion"
	)
	if _failed:
		return
	_assert_true(
		not background.is_processing(), "preference-disabled main-menu backdrop should be stopped"
	)
	main_menu.queue_free()
	_owned_nodes.erase(main_menu)
	await process_frame


func _check_required_actions_have_joypad_events() -> void:
	for action: StringName in REQUIRED_JOYPAD_ACTIONS:
		if not InputMap.has_action(action):
			_fail("required input action missing: %s" % String(action))
			return
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		var has_joypad_event: bool = false
		for event: InputEvent in events:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_joypad_event = true
				break
		if not has_joypad_event:
			_fail("required input action lacks a joypad binding: %s" % String(action))
			return


func _new_sensory_feedback() -> Control:
	var sensory_feedback: Control = SENSORY_SCRIPT.new()
	if sensory_feedback == null:
		_fail("SensoryFeedback instance creation failed")
		return null
	root.add_child(sensory_feedback)
	_owned_nodes.append(sensory_feedback)
	return sensory_feedback


func _history_names(history: Array) -> Array[String]:
	var names: Array[String] = []
	for entry: Variant in history:
		if entry is Dictionary:
			names.append(str(entry.get("name", "")))
	return names


func _capture_user_file_backups() -> void:
	_history_backup_exists = FileAccess.file_exists(HISTORY_PATH)
	if _history_backup_exists:
		_history_backup_text = _read_required_user_file(HISTORY_PATH)
		if _failed:
			return
	_history_backup_captured = true

	_settings_backup_exists = FileAccess.file_exists(SETTINGS_PATH)
	if _settings_backup_exists:
		_settings_backup_text = _read_required_user_file(SETTINGS_PATH)
		if _failed:
			return
	_settings_backup_captured = true


func _capture_game_manager_state(game_manager: Node) -> void:
	_game_manager_backup = {
		"character_history": game_manager.character_history.duplicate(true),
		"last_run_summary": game_manager.last_run_summary.duplicate(true),
		"player": game_manager.player,
		"enemies": game_manager.enemies.duplicate(),
		"map_data": game_manager.map_data.duplicate(true),
		"map_width": game_manager.map_width,
		"map_height": game_manager.map_height,
		"current_floor": game_manager.current_floor,
		"turn_count": game_manager.turn_count,
		"is_player_turn": game_manager.is_player_turn,
		"has_active_run": game_manager.has_active_run,
		"pending_character_name": game_manager.pending_character_name,
		"pending_ability_scores": game_manager.pending_ability_scores.duplicate(true),
		"pending_character_class": game_manager.pending_character_class,
		"pending_debug_loadout": game_manager.pending_debug_loadout,
	}


func _restore_game_manager_state() -> void:
	if _game_manager == null or _game_manager_backup.is_empty():
		return
	_game_manager.character_history = _game_manager_backup["character_history"].duplicate(true)
	_game_manager.last_run_summary = _game_manager_backup["last_run_summary"].duplicate(true)
	_game_manager.player = _game_manager_backup["player"]
	_game_manager.enemies = _game_manager_backup["enemies"].duplicate()
	_game_manager.map_data = _game_manager_backup["map_data"].duplicate(true)
	_game_manager.map_width = int(_game_manager_backup["map_width"])
	_game_manager.map_height = int(_game_manager_backup["map_height"])
	_game_manager.current_floor = int(_game_manager_backup["current_floor"])
	_game_manager.turn_count = int(_game_manager_backup["turn_count"])
	_game_manager.is_player_turn = bool(_game_manager_backup["is_player_turn"])
	_game_manager.has_active_run = bool(_game_manager_backup["has_active_run"])
	_game_manager.pending_character_name = str(_game_manager_backup["pending_character_name"])
	_game_manager.pending_ability_scores = _game_manager_backup["pending_ability_scores"].duplicate(
		true
	)
	_game_manager.pending_character_class = StringName(
		str(_game_manager_backup["pending_character_class"])
	)
	_game_manager.pending_debug_loadout = bool(_game_manager_backup["pending_debug_loadout"])


func _read_required_user_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("failed to read user file: %s" % path)
		return ""
	return file.get_as_text()


func _write_required_user_file(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("failed to write isolated user file: %s" % path)
		return
	file.store_string(text)


func _restore_user_file(path: String, existed: bool, text: String) -> void:
	if existed:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("failed to restore user file: %s" % path)
			_failed = true
			return
		file.store_string(text)
		return
	if not FileAccess.file_exists(path):
		return
	var directory: DirAccess = DirAccess.open(path.get_base_dir())
	if directory == null:
		push_error("failed to open user directory for cleanup: %s" % path.get_base_dir())
		_failed = true
		return
	var error: int = directory.remove(path.get_file())
	if error != OK:
		push_error("failed to remove isolated user file %s: %d" % [path, error])
		_failed = true


func _cleanup() -> void:
	if _cleanup_done:
		return
	_cleanup_done = true
	for node: Node in _owned_nodes.duplicate():
		if is_instance_valid(node):
			node.queue_free()
	_owned_nodes.clear()
	_restore_game_manager_state()
	if _history_backup_captured:
		_restore_user_file(HISTORY_PATH, _history_backup_exists, _history_backup_text)
	if _settings_backup_captured:
		_restore_user_file(SETTINGS_PATH, _settings_backup_exists, _settings_backup_text)


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _assert_float_equal(actual: float, expected: float, message: String) -> void:
	if absf(actual - expected) <= EPSILON:
		return
	_fail("%s (expected %.3f, got %.3f)" % [message, expected, actual])


func _fail(message: String) -> void:
	if _failed:
		return
	_failed = true
	printerr(message)
	_cleanup()
	quit(1)
