## V31.0.0 difficulty state, persistence, pricing, and UI flow integration contract.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v31_difficulty_flow.gd
extends SceneTree

const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const CHARACTER_CREATION_SCENE_PATH: String = "res://scenes/character_creation.tscn"
const NORMAL_COLOR: Color = Color(0.6, 0.843137, 0.898039, 1.0)
const HARD_COLOR: Color = Color(1.0, 0.33, 0.47, 1.0)


class PriceItem:
	extends Resource

	var _price: int

	func _init(price: int) -> void:
		_price = price

	func get_price() -> int:
		return _price


var _failed: bool = false
var _game_manager: Node
var _history_file_existed: bool = false
var _history_file_bytes: PackedByteArray = PackedByteArray()

var _original_player: Node2D
var _original_enemies: Array[Node2D] = []
var _original_map_data: Array = []
var _original_map_width: int
var _original_map_height: int
var _original_current_floor: int
var _original_turn_count: int
var _original_is_player_turn: bool
var _original_has_active_run: bool
var _original_pending_character_name: String
var _original_pending_ability_scores: Dictionary = {}
var _original_pending_character_class: StringName
var _original_pending_difficulty: StringName
var _original_pending_debug_loadout: bool
var _original_character_history: Array = []
var _original_last_run_summary: Dictionary = {}


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_game_manager = root.get_node_or_null("/root/GameManager")
	_expect(_game_manager != null, "GameManager autoload is missing")
	if _game_manager == null:
		quit(1)
		return
	_backup_state()

	_check_unlock_and_normalization_contract()
	_check_history_migration_and_persistence()
	_check_summary_and_archive_difficulty()
	_check_hard_shop_rounding()
	_check_pending_selection_survives_context_clear()
	await _check_locked_modal_contract()
	await _check_unlocked_modal_contract()
	await _check_selection_route(_game_manager.DIFFICULTY_NORMAL)
	await _check_selection_route(_game_manager.DIFFICULTY_HARD)
	await _clear_current_test_scene()
	_restore_state()

	if _failed:
		quit(1)
		return
	print("V31 difficulty state, persistence, pricing, modal, and creation flow checks passed")
	quit(0)


func _backup_state() -> void:
	_original_player = _game_manager.player
	_original_enemies.assign(_game_manager.enemies)
	_original_map_data = _game_manager.map_data.duplicate(true)
	_original_map_width = _game_manager.map_width
	_original_map_height = _game_manager.map_height
	_original_current_floor = _game_manager.current_floor
	_original_turn_count = _game_manager.turn_count
	_original_is_player_turn = _game_manager.is_player_turn
	_original_has_active_run = _game_manager.has_active_run
	_original_pending_character_name = _game_manager.pending_character_name
	_original_pending_ability_scores = _game_manager.pending_ability_scores.duplicate(true)
	_original_pending_character_class = _game_manager.pending_character_class
	_original_pending_difficulty = _game_manager.pending_difficulty
	_original_pending_debug_loadout = _game_manager.pending_debug_loadout
	_original_character_history = _game_manager.character_history.duplicate(true)
	_original_last_run_summary = _game_manager.last_run_summary.duplicate(true)

	_history_file_existed = FileAccess.file_exists(_game_manager.HISTORY_PATH)
	if _history_file_existed:
		_history_file_bytes = FileAccess.get_file_as_bytes(_game_manager.HISTORY_PATH)


func _restore_state() -> void:
	_game_manager.player = _original_player
	_game_manager.enemies.assign(_original_enemies)
	_game_manager.map_data = _original_map_data.duplicate(true)
	_game_manager.map_width = _original_map_width
	_game_manager.map_height = _original_map_height
	_game_manager.current_floor = _original_current_floor
	_game_manager.turn_count = _original_turn_count
	_game_manager.is_player_turn = _original_is_player_turn
	_game_manager.has_active_run = _original_has_active_run
	_game_manager.pending_character_name = _original_pending_character_name
	_game_manager.pending_ability_scores = _original_pending_ability_scores.duplicate(true)
	_game_manager.pending_character_class = _original_pending_character_class
	_game_manager.pending_difficulty = _original_pending_difficulty
	_game_manager.pending_debug_loadout = _original_pending_debug_loadout
	_game_manager.character_history = _original_character_history.duplicate(true)
	_game_manager.last_run_summary = _original_last_run_summary.duplicate(true)

	if _history_file_existed:
		var file: FileAccess = FileAccess.open(_game_manager.HISTORY_PATH, FileAccess.WRITE)
		if file == null:
			_fail("Could not restore the original character history file")
		else:
			file.store_buffer(_history_file_bytes)
	else:
		var absolute_path: String = ProjectSettings.globalize_path(_game_manager.HISTORY_PATH)
		if FileAccess.file_exists(_game_manager.HISTORY_PATH):
			var remove_error: Error = DirAccess.remove_absolute(absolute_path)
			if remove_error != OK:
				_fail("Could not remove the character history fixture")


func _check_unlock_and_normalization_contract() -> void:
	_expect_unlock([], false, "Hard unlocked without an archived victory")
	_expect_unlock(
		[{"name": "Normal Victor", "victory": true, "difficulty": "normal"}],
		true,
		"A strict Boolean non-debug Normal victory did not unlock Hard",
	)
	_expect_unlock(
		[{"name": "Legacy Victor", "victory": true}],
		true,
		"A legacy victory without difficulty did not migrate to Normal unlock authority",
	)
	_expect_unlock(
		[{"name": "Nightmare Victor", "victory": true, "difficulty": "nightmare"}],
		false,
		"A Nightmare victory incorrectly became Normal unlock authority",
	)
	_expect_unlock(
		[{"name": "Hard Victor", "victory": true, "difficulty": "hard"}],
		false,
		"A Hard victory incorrectly became Normal unlock authority",
	)
	_expect_unlock(
		[{"name": "Truthy Number", "victory": 1, "difficulty": "normal"}],
		false,
		"A numeric truthy victory incorrectly unlocked Hard",
	)
	_expect_unlock(
		[{"name": "Truthy String", "victory": "true", "difficulty": "normal"}],
		false,
		"A string truthy victory incorrectly unlocked Hard",
	)
	_expect_unlock(
		[{"name": "Defeated Hero", "victory": false, "difficulty": "normal"}],
		false,
		"A Normal defeat incorrectly unlocked Hard",
	)
	_expect_unlock(
		[
			{
				"name": "Flagged Fixture",
				"victory": true,
				"difficulty": "normal",
				"archived_debug": true,
			}
		],
		false,
		"An explicitly debug archive entry incorrectly unlocked Hard",
	)
	_expect_unlock(
		[{"name": "  DeBuG  ", "victory": true, "difficulty": "normal"}],
		false,
		"A case/whitespace debug-name archive entry incorrectly unlocked Hard",
	)
	_expect_unlock(
		[{"name": "Old Delver", "floor": 4, "level": 3}],
		false,
		"An incomplete real archive entry incorrectly unlocked Hard",
	)

	_game_manager.character_history = []
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_HARD
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_HARD)
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_NORMAL,
		"Locked Hard setter did not coerce to Normal",
	)
	_game_manager.set_pending_difficulty(&"  nightmare  ")
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_NORMAL,
		"Unknown pending difficulty did not normalize to Normal",
	)
	_expect_equal(
		_game_manager.get_difficulty_label(&"unknown"),
		"Normal",
		"Unknown difficulty label did not normalize to Normal",
	)


func _expect_unlock(history: Array, expected: bool, message: String) -> void:
	_game_manager.character_history = history.duplicate(true)
	_expect_equal(_game_manager.is_hard_mode_unlocked(), expected, message)


func _check_history_migration_and_persistence() -> void:
	var raw_history: Array = [
		{"name": "Old Delver", "floor": 4, "level": 3, "victory": true, "class": "mage"},
		{
			"name": "Patch Hero",
			"floor": 2,
			"level": 2,
			"victory": false,
			"class": "fighter",
			"difficulty": "nightmare",
		},
		{
			"name": "Hard Victor",
			"floor": 12,
			"level": 9,
			"victory": true,
			"class": "wizard",
			"difficulty": " HARD ",
		},
		{"name": " debug ", "victory": true, "difficulty": "normal"},
		{
			"name": "Flagged Fixture",
			"victory": true,
			"difficulty": "normal",
			"archived_debug": true,
		},
	]
	_write_history_fixture(raw_history)
	_game_manager.character_history = []
	_game_manager._load_character_history()

	_expect_equal(
		_game_manager.character_history.size(),
		3,
		"History migration deleted real entries or retained explicit debug entries",
	)
	var old_delver: Dictionary = _history_entry_named("Old Delver")
	var patch_hero: Dictionary = _history_entry_named("Patch Hero")
	var hard_victor: Dictionary = _history_entry_named("Hard Victor")
	_expect(
		not old_delver.is_empty(), "Old Delver was incorrectly treated as disposable fixture data"
	)
	_expect(
		not patch_hero.is_empty(), "Patch Hero was incorrectly treated as disposable fixture data"
	)
	_expect_equal(old_delver.get("class"), "wizard", "Legacy mage class did not migrate to wizard")
	_expect_equal(
		old_delver.get("difficulty"),
		"normal",
		"Missing archive difficulty did not migrate to Normal",
	)
	_expect_equal(
		patch_hero.get("difficulty"),
		"nightmare",
		"Nightmare archive difficulty did not survive migration",
	)
	_expect_equal(
		hard_victor.get("difficulty"),
		"hard",
		"Case/whitespace Hard archive difficulty did not normalize",
	)

	var persisted_file: FileAccess = FileAccess.open(_game_manager.HISTORY_PATH, FileAccess.READ)
	_expect(persisted_file != null, "Migrated character history was not persisted")
	if persisted_file != null:
		var persisted_history: Variant = JSON.parse_string(persisted_file.get_as_text())
		_expect(
			persisted_history is Array,
			"Persisted migrated character history is not a JSON array",
		)
		if persisted_history is Array:
			_expect_equal(
				persisted_history,
				_game_manager.character_history,
				"History migration changed memory but did not persist the changed content",
			)


func _write_history_fixture(history: Array) -> void:
	var file: FileAccess = FileAccess.open(_game_manager.HISTORY_PATH, FileAccess.WRITE)
	_expect(file != null, "Could not write character history fixture")
	if file != null:
		file.store_string(JSON.stringify(history))


func _history_entry_named(character_name: String) -> Dictionary:
	for entry: Variant in _game_manager.character_history:
		if entry is Dictionary and str(entry.get("name", "")) == character_name:
			return entry
	return {}


func _check_summary_and_archive_difficulty() -> void:
	_game_manager.character_history = [_normal_victory()]
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_HARD)
	_game_manager.reset_run()
	_game_manager.prepare_character("Hard Archivist", {}, _game_manager.CLASS_WIZARD)
	_game_manager.current_floor = 7
	_game_manager.end_run(true)
	_expect_equal(
		_game_manager.last_run_summary.get("difficulty"),
		"hard",
		"Hard last-run summary omitted or changed difficulty",
	)
	_expect_equal(
		(_game_manager.character_history[0] as Dictionary).get("difficulty"),
		"hard",
		"Hard archive record omitted or changed difficulty",
	)
	_game_manager.character_history = [_game_manager.character_history[0]]
	_expect(
		not _game_manager.is_hard_mode_unlocked(),
		"A newly archived Hard victory incorrectly became Normal unlock authority",
	)

	_game_manager.character_history = []
	_game_manager.set_pending_difficulty(&"unrecognized")
	_game_manager.reset_run()
	_game_manager.prepare_character("Normal Archivist", {}, _game_manager.CLASS_FIGHTER)
	_game_manager.current_floor = 2
	_game_manager.end_run(false)
	_expect_equal(
		_game_manager.last_run_summary.get("difficulty"),
		"normal",
		"Normalized Normal last-run summary omitted or changed difficulty",
	)
	_expect_equal(
		(_game_manager.character_history[0] as Dictionary).get("difficulty"),
		"normal",
		"Normalized Normal archive record omitted or changed difficulty",
	)


func _check_hard_shop_rounding() -> void:
	var item: PriceItem = PriceItem.new(19)
	var featured_item: PriceItem = PriceItem.new(13)
	var minimum_item: PriceItem = PriceItem.new(1)
	_game_manager.character_history = [_normal_victory()]
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NORMAL)
	var normal_buy: int = _game_manager._get_shop_buy_price(item, 10)
	var normal_sell: int = _game_manager._get_shop_sell_price(item, 10)
	var normal_featured_buy: int = _game_manager._get_shop_buy_price(featured_item, 15, 0)
	_expect_equal(normal_buy, 19, "Normal buy-price baseline changed")
	_expect_equal(normal_sell, 6, "Normal sell-price baseline changed")
	_expect_equal(normal_featured_buy, 10, "Normal featured-deal baseline changed")

	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_HARD)
	_expect(_game_manager.is_hard_mode(), "Unlocked Hard selection did not enter Hard mode")
	_expect_equal(
		_game_manager._get_shop_buy_price(item, 10),
		21,
		"Hard buy price was not ceil(final Normal price * 1.10)",
	)
	_expect_equal(
		_game_manager._get_shop_sell_price(item, 10),
		5,
		"Hard sell price was not floor(final Normal price * 0.90)",
	)
	_expect_equal(
		_game_manager._get_shop_buy_price(featured_item, 15, 0),
		11,
		"Hard buy multiplier was not applied after the final featured Normal price",
	)
	_expect_equal(
		_game_manager._get_shop_sell_price(minimum_item, 10),
		1,
		"Hard sell price dropped below the one-gold minimum",
	)


func _check_pending_selection_survives_context_clear() -> void:
	_game_manager.character_history = [_normal_victory()]
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_HARD)
	_game_manager.prepare_character("Prepared Hero", {}, _game_manager.CLASS_RANGER)
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_HARD,
		"Preparing a character reset the selected difficulty",
	)
	_game_manager.abandon_run()
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_HARD,
		"Back/retry-style abandon context clear reset difficulty",
	)
	_game_manager.clear_finished_run_context()
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_HARD,
		"Finished-run context clear reset difficulty",
	)


func _check_locked_modal_contract() -> void:
	_game_manager.character_history = []
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_HARD
	var menu: Control = await _instantiate_control_scene(MAIN_MENU_SCENE_PATH)
	if menu == null:
		return
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_NORMAL,
		"Main menu did not revalidate a stale locked Hard selection",
	)

	var start_button: Button = menu.get_node("Center/VBox/StartButton")
	var library_button: Button = menu.get_node("Center/VBox/LibraryButton")
	var quit_button: Button = menu.get_node("Center/VBox/QuitButton")
	var modal: Control = menu.get_node("DifficultyModal")
	var modal_vbox: VBoxContainer = menu.get_node(
		"DifficultyModal/SafeMargin/Center/Panel/Margin/VBox"
	)
	var title: Label = modal_vbox.get_node("Title")
	var normal_button: Button = modal_vbox.get_node("NormalButton")
	var hard_button: Button = modal_vbox.get_node("HardButton")
	var status_label: Label = modal_vbox.get_node("StatusLabel")
	var back_button: Button = modal_vbox.get_node("BackButton")

	_expect(not modal.visible, "Difficulty modal was visible before Start")
	start_button.pressed.emit()
	await process_frame
	_expect(modal.visible, "Start did not open the difficulty modal")
	_expect_equal(title.text, "CHOOSE YOUR DESCENT", "Difficulty modal title drifted")
	_expect(start_button.disabled, "Start remained active behind the modal")
	_expect(library_button.disabled, "Library remained active behind the modal")
	_expect(quit_button.disabled, "Quit remained active behind the modal")
	_expect(hard_button.is_visible_in_tree(), "Locked Hard option was hidden")
	_expect(hard_button.disabled, "Locked Hard option was enabled")
	_expect_equal(
		hard_button.focus_mode,
		Control.FOCUS_NONE,
		"Locked Hard option remained keyboard-focusable",
	)
	_expect(
		status_label.text.to_lower().contains("non-debug normal"),
		"Locked Hard copy did not explain the non-debug Normal victory requirement",
	)
	_expect_equal(
		root.gui_get_focus_owner(),
		normal_button,
		"Locked modal did not focus the available Normal choice",
	)
	_expect_focus_link(
		normal_button,
		&"focus_next",
		back_button,
		"Locked modal focus-next did not skip disabled Hard",
	)
	_expect_focus_link(
		back_button,
		&"focus_next",
		normal_button,
		"Locked modal focus loop did not return to Normal",
	)

	menu._unhandled_input(_action_event(&"ui_cancel"))
	await process_frame
	_expect(not modal.visible, "Cancel/Escape did not close the difficulty modal")
	_expect(not start_button.disabled, "Start stayed disabled after closing the modal")
	_expect_equal(
		root.gui_get_focus_owner(),
		start_button,
		"Closing the modal did not return focus to Start",
	)
	start_button.pressed.emit()
	await process_frame
	back_button.pressed.emit()
	await process_frame
	_expect(not modal.visible, "Difficulty Back did not close the modal")
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_NORMAL,
		"Difficulty Back changed the retained selection",
	)
	menu.queue_free()
	await process_frame


func _check_unlocked_modal_contract() -> void:
	_game_manager.character_history = [_normal_victory()]
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_HARD)
	var menu: Control = await _instantiate_control_scene(MAIN_MENU_SCENE_PATH)
	if menu == null:
		return
	var start_button: Button = menu.get_node("Center/VBox/StartButton")
	var modal_vbox: VBoxContainer = menu.get_node(
		"DifficultyModal/SafeMargin/Center/Panel/Margin/VBox"
	)
	var normal_button: Button = modal_vbox.get_node("NormalButton")
	var hard_button: Button = modal_vbox.get_node("HardButton")
	var back_button: Button = modal_vbox.get_node("BackButton")
	var status_label: Label = modal_vbox.get_node("StatusLabel")

	start_button.pressed.emit()
	await process_frame
	_expect(not hard_button.disabled, "Unlocked Hard option remained disabled")
	_expect_equal(
		hard_button.focus_mode,
		Control.FOCUS_ALL,
		"Unlocked Hard option was not keyboard/gamepad focusable",
	)
	var hard_font_color: Color = hard_button.get_theme_color(&"font_color")
	_expect(
		hard_font_color.r > hard_font_color.g and hard_font_color.r > hard_font_color.b,
		"Unlocked Hard option did not retain red danger styling",
	)
	_expect(
		status_label.text.to_lower().contains("hard unlocked"),
		"Unlocked Hard status did not announce the unlock",
	)
	_expect_equal(
		root.gui_get_focus_owner(),
		hard_button,
		"Retained unlocked Hard selection was not focused safely",
	)
	_expect_focus_link(
		normal_button, &"focus_next", hard_button, "Normal did not focus-next to Hard"
	)
	_expect_focus_link(hard_button, &"focus_next", back_button, "Hard did not focus-next to Back")
	_expect_focus_link(
		back_button, &"focus_next", normal_button, "Back did not close the focus loop"
	)
	_expect_focus_link(
		normal_button, &"focus_previous", back_button, "Normal focus-previous drifted"
	)
	_expect_focus_link(hard_button, &"focus_previous", normal_button, "Hard focus-previous drifted")
	_expect_focus_link(back_button, &"focus_previous", hard_button, "Back focus-previous drifted")
	menu.queue_free()
	await process_frame


func _check_selection_route(difficulty: StringName) -> void:
	await _clear_current_test_scene()
	if difficulty == _game_manager.DIFFICULTY_HARD:
		_game_manager.character_history = [_normal_victory()]
	else:
		_game_manager.character_history = []
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NORMAL)

	var menu_scene: PackedScene = load(MAIN_MENU_SCENE_PATH)
	_expect(menu_scene != null, "Main menu scene failed to load for routing")
	if menu_scene == null:
		return
	var menu: Control = menu_scene.instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var start_button: Button = menu.get_node("Center/VBox/StartButton")
	var modal_vbox: VBoxContainer = menu.get_node(
		"DifficultyModal/SafeMargin/Center/Panel/Margin/VBox"
	)
	var choice_button: Button = (
		modal_vbox.get_node("HardButton")
		if difficulty == _game_manager.DIFFICULTY_HARD
		else modal_vbox.get_node("NormalButton")
	)
	start_button.pressed.emit()
	await process_frame
	choice_button.pressed.emit()
	await process_frame
	await process_frame

	var creation: Node = current_scene
	var difficulty_name: String = (
		"Hard" if difficulty == _game_manager.DIFFICULTY_HARD else "Normal"
	)
	_expect(creation != null, "%s selection did not create a destination scene" % difficulty_name)
	if creation == null:
		return
	_expect_equal(
		creation.scene_file_path,
		CHARACTER_CREATION_SCENE_PATH,
		"%s selection did not route to character creation" % difficulty_name,
	)
	_expect_equal(
		_game_manager.pending_difficulty,
		difficulty,
		"%s selection did not update GameManager before routing" % difficulty_name,
	)
	var difficulty_label: Label = (
		creation.get_node_or_null("Center/Panel/Margin/VBox/DifficultyLabel") as Label
	)
	_expect(difficulty_label != null, "Character creation difficulty confirmation is missing")
	if difficulty_label != null:
		_expect_equal(
			difficulty_label.text,
			"Difficulty: %s" % difficulty_name.to_upper(),
			"Character creation %s confirmation text drifted" % difficulty_name,
		)
		var expected_color: Color = (
			HARD_COLOR if difficulty == _game_manager.DIFFICULTY_HARD else NORMAL_COLOR
		)
		_expect(
			difficulty_label.get_theme_color(&"font_color").is_equal_approx(expected_color),
			"Character creation %s confirmation color drifted" % difficulty_name,
		)

	var back_button: Button = (
		creation.get_node_or_null("Center/Panel/Margin/VBox/Buttons/BackButton") as Button
	)
	_expect(back_button != null, "Character creation Back button is missing")
	if back_button != null:
		back_button.pressed.emit()
		await process_frame
		await process_frame
		_expect(
			current_scene != null and current_scene.scene_file_path == MAIN_MENU_SCENE_PATH,
			"Character creation Back did not route to the main menu",
		)
		_expect_equal(
			_game_manager.pending_difficulty,
			difficulty,
			"Character creation Back did not preserve %s selection" % difficulty_name,
		)


func _instantiate_control_scene(path: String) -> Control:
	var packed_scene: PackedScene = load(path)
	_expect(packed_scene != null, "Scene failed to load: %s" % path)
	if packed_scene == null:
		return null
	var scene: Control = packed_scene.instantiate() as Control
	_expect(scene != null, "Scene root is not a Control: %s" % path)
	if scene == null:
		return null
	root.add_child(scene)
	await process_frame
	return scene


func _clear_current_test_scene() -> void:
	var scene: Node = current_scene
	if scene != null and is_instance_valid(scene):
		if scene.is_inside_tree():
			scene.queue_free()
		current_scene = null
	await process_frame


func _normal_victory() -> Dictionary:
	return {
		"name": "Normal Victor",
		"floor": 10,
		"level": 8,
		"victory": true,
		"class": "fighter",
		"difficulty": "normal",
	}


func _action_event(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	event.strength = 1.0
	return event


func _expect_focus_link(
	source: Control, property_name: StringName, target: Control, message: String
) -> void:
	var focus_path: NodePath = source.get(property_name)
	_expect(not focus_path.is_empty(), "%s: focus path is empty" % message)
	if focus_path.is_empty():
		return
	_expect_equal(source.get_node_or_null(focus_path), target, message)


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
