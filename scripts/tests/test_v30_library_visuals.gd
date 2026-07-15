## V30.0.0 Library pixel-preview and held inventory navigation contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v30_library_visuals.gd
extends SceneTree

const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const LIBRARY_SCENE_PATH: String = "res://scenes/library.tscn"
const GAME_SCENE_PATH: String = "res://scenes/game.tscn"
const WIDE_VIEWPORT: Vector2i = Vector2i(1100, 800)
const COMPACT_VIEWPORT: Vector2i = Vector2i(700, 900)

var _failed: bool = false
var _original_viewport_size: Vector2i


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_original_viewport_size = root.size
	await _check_library_previews()
	if not _failed:
		await _check_inventory_hold_repeat()
	root.size = _original_viewport_size
	Input.action_release(&"ui_up")
	Input.action_release(&"ui_down")
	if _failed:
		quit(1)
		return
	print("V30 Library visuals and inventory repeat checks passed")
	quit(0)


func _check_library_previews() -> void:
	root.size = WIDE_VIEWPORT
	var library_scene: PackedScene = load(LIBRARY_SCENE_PATH)
	_expect(library_scene != null, "Library scene failed to load")
	if library_scene == null:
		return
	var library: Control = library_scene.instantiate() as Control
	root.add_child(library)
	await process_frame
	await process_frame
	_expect_equal(library.tabs.get_tab_count(), 6, "Library must retain all six tabs")
	_expect_equal(library._bestiary_buttons.size(), 42, "Bestiary must list every enemy resource")
	_expect_equal(library._scribes_buttons.size(), 76, "Scribes must list every item resource")
	_expect_equal(library._dungeon_buttons.size(), 6, "Dungeon Notes must list every trap resource")

	library._layout_initialized = false
	library._apply_responsive_layout()
	_expect(not library._compact_layout, "Wide Library viewport incorrectly entered compact mode")
	_expect(not library.bestiary_split.vertical, "Wide Bestiary split must be horizontal")
	_expect(not library.scribes_split.vertical, "Wide Scribes split must be horizontal")
	_expect(not library.dungeon_split.vertical, "Wide Dungeon Notes split must be horizontal")

	var bestiary_preview: Control = library.bestiary_preview
	bestiary_preview._reduced_vfx_enabled = false
	var first_enemy: Resource = load(ResourcePathsScript.ENEMY_PATHS[0])
	bestiary_preview.show_enemy(first_enemy)
	_expect(bestiary_preview.actor_sprite.visible, "Enemy preview sprite is hidden")
	_expect_equal(
		bestiary_preview.actor_sprite.animation,
		&"idle",
		"Enemy preview must use the authored idle animation",
	)
	_expect(bestiary_preview.actor_sprite.is_playing(), "Enemy preview idle animation did not play")
	_expect(
		bestiary_preview.alt_text.text.contains(first_enemy.display_name),
		"Enemy preview alt text omitted the display name",
	)

	var second_enemy_button: Button = library._bestiary_buttons[1]
	var first_alt_text: String = bestiary_preview.alt_text.text
	second_enemy_button.grab_focus()
	await process_frame
	_expect(second_enemy_button.button_pressed, "Keyboard focus did not select the enemy row")
	_expect(
		bestiary_preview.alt_text.text != first_alt_text,
		"Keyboard focus did not update the enemy preview",
	)
	var focused_button: Control = root.gui_get_focus_owner()
	var third_enemy_button: Button = library._bestiary_buttons[2]
	var second_alt_text: String = bestiary_preview.alt_text.text
	third_enemy_button.mouse_entered.emit()
	await process_frame
	_expect(third_enemy_button.button_pressed, "Mouse hover did not select the enemy row")
	_expect(
		bestiary_preview.alt_text.text != second_alt_text,
		"Mouse hover did not update the enemy preview",
	)
	_expect_equal(
		root.gui_get_focus_owner(),
		focused_button,
		"Mouse hover must not steal keyboard focus",
	)

	var enchanted_item: Resource = _find_enchanted_item()
	_expect(enchanted_item != null, "No rare equipment resource exists for preview testing")
	if enchanted_item != null:
		var item_button: Button = _button_containing(
			library._scribes_buttons, enchanted_item.display_name
		)
		_expect(item_button != null, "Rare equipment row is missing from Scribes")
		if item_button != null:
			library._reduced_vfx_enabled = false
			library.scribes_preview._reduced_vfx_enabled = false
			item_button.grab_focus()
			await process_frame
			_expect(library.scribes_preview.object_sprite.visible, "Item preview sprite is hidden")
			_expect_equal(
				library.scribes_preview.object_sprite.modulate,
				Color.WHITE,
				"Authored item preview art must retain its source palette",
			)
			_expect(
				library.scribes_preview.enchantment_sprite.visible,
				"Rare equipment preview is missing its enchantment overlay",
			)
			_expect(
				library.scribes_preview._enchantment_tint.is_equal_approx(
					Color.html(enchanted_item.get_rarity_color())
				),
				"Equipment enchantment tint must match its authored rarity colour",
			)
			_expect(
				library.scribes_preview.is_processing(),
				"Rare equipment preview did not enable its idle animation",
			)
			_expect(
				library.scribes_preview.alt_text.text.contains(enchanted_item.display_name),
				"Item preview alt text omitted the display name",
			)
			library.scribes_preview._reduced_vfx_enabled = true
			library.scribes_preview.show_item(enchanted_item)
			_expect(
				not library.scribes_preview.is_processing(),
				"Reduced VFX must stop Library item animation processing",
			)
			_expect(
				library.scribes_preview.enchantment_sprite.visible,
				"Reduced VFX must retain a static enchantment overlay",
			)
			_expect_equal(
				library.scribes_preview.object_sprite.position,
				library.scribes_preview.enchantment_sprite.position,
				"Static enchantment overlay must stay aligned to the item sprite",
			)

	var trap_button: Button = library._dungeon_buttons[1]
	trap_button.grab_focus()
	await process_frame
	_expect(trap_button.button_pressed, "Keyboard focus did not select the trap row")
	_expect(library.dungeon_preview.object_sprite.visible, "Trap preview sprite is hidden")
	_expect(
		not library.dungeon_preview.enchantment_sprite.visible,
		"Trap preview incorrectly received an equipment enchantment overlay",
	)

	root.size = COMPACT_VIEWPORT
	await process_frame
	library._layout_initialized = false
	library._apply_responsive_layout()
	_expect(library._compact_layout, "Narrow Library viewport did not enter compact mode")
	_expect(library.bestiary_split.vertical, "Compact Bestiary split must be vertical")
	_expect(library.scribes_split.vertical, "Compact Scribes split must be vertical")
	_expect(library.dungeon_split.vertical, "Compact Dungeon Notes split must be vertical")
	_expect_equal(
		library.bestiary_split.get_child(0).custom_minimum_size.x,
		0.0,
		"Compact browser list retained a desktop minimum width",
	)
	_expect_equal(
		library.bestiary_preview.preview_stage.custom_minimum_size.y,
		library.bestiary_preview.COMPACT_STAGE_HEIGHT,
		"Compact preview height drifted",
	)

	library.queue_free()
	await process_frame
	print("  Library previews respond to focus, hover, Reduced VFX, and compact layouts")


func _check_inventory_hold_repeat() -> void:
	root.size = WIDE_VIEWPORT
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	_expect(game_manager != null, "GameManager autoload is missing")
	if game_manager == null:
		return
	game_manager.prepare_character("debug", {}, game_manager.CLASS_FIGHTER)
	var game_scene: PackedScene = load(GAME_SCENE_PATH)
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	var panel: Control = game.inventory_panel
	var inventory: Node = game._player.inventory_component
	_expect(inventory.items.size() >= 12, "Debug inventory is too small for repeat testing")
	panel.visible = true
	panel._selected_index = 0
	panel.refresh(game._player)
	await process_frame

	Input.action_press(&"ui_down")
	panel._input(_action_event(&"ui_down", true))
	_expect_equal(panel._selected_index, 1, "Initial held-key press must move exactly one row")
	var initial_snapshot: Dictionary = panel.get_hold_debug_snapshot()
	_expect_equal(initial_snapshot.get("direction"), 1, "Down hold direction was not recorded")
	_expect_equal(
		initial_snapshot.get("interval"),
		panel.HOLD_START_INTERVAL,
		"Held-key repeat did not start at the configured interval",
	)
	panel._process(panel.HOLD_INITIAL_DELAY + 0.01)
	_expect_equal(panel._selected_index, 2, "Held-key initial delay did not produce one repeat")
	for _step_index: int in range(8):
		panel._process(1.0)
	var accelerated_snapshot: Dictionary = panel.get_hold_debug_snapshot()
	_expect(
		float(accelerated_snapshot.get("interval", 1.0)) < panel.HOLD_START_INTERVAL,
		"Held-key navigation interval did not accelerate",
	)
	_expect(
		float(accelerated_snapshot.get("interval", 0.0)) >= panel.HOLD_MIN_INTERVAL,
		"Held-key navigation accelerated below its minimum interval",
	)

	Input.action_release(&"ui_down")
	panel._input(_action_event(&"ui_down", false))
	_expect_equal(
		panel.get_hold_debug_snapshot().get("direction"),
		0,
		"Releasing the held key did not stop repeat navigation",
	)

	var before_opposite: int = panel._selected_index
	Input.action_press(&"ui_down")
	panel._input(_action_event(&"ui_down", true))
	Input.action_press(&"ui_up")
	panel._input(_action_event(&"ui_up", true))
	_expect_equal(
		panel._selected_index,
		before_opposite,
		"Opposite direction must step immediately and restart the repeat delay",
	)
	_expect_equal(
		panel.get_hold_debug_snapshot().get("direction"),
		-1,
		"Opposite direction did not replace the active hold direction",
	)
	Input.action_release(&"ui_down")
	Input.action_release(&"ui_up")
	panel._input(_action_event(&"ui_up", false))

	Input.action_press(&"ui_down")
	panel._input(_action_event(&"ui_down", true))
	var selected_before_close: int = panel._selected_index
	panel.visible = false
	await process_frame
	_expect_equal(
		panel.get_hold_debug_snapshot().get("direction"),
		0,
		"Closing inventory did not clear held-key state",
	)
	panel.visible = true
	panel.refresh(game._player)
	await process_frame
	_expect_equal(
		panel._selected_index,
		selected_before_close,
		"Reopening inventory unexpectedly changed the selected row",
	)
	Input.action_release(&"ui_down")

	game_manager.abandon_run()
	game.queue_free()
	await process_frame
	print("  inventory hold repeat accelerates, reverses, releases, and reopens deterministically")


func _find_enchanted_item() -> Resource:
	for path: String in ResourcePathsScript.ITEM_PATHS:
		var item: Resource = load(path)
		if (
			item != null
			and item.rarity >= ItemDataScript.ItemRarity.RARE
			and item.kind != ItemDataScript.ItemKind.CONSUMABLE
		):
			return item
	return null


func _button_containing(buttons: Array[Button], display_name: String) -> Button:
	for button: Button in buttons:
		if button.text.contains(display_name):
			return button
	return null


func _action_event(action: StringName, pressed: bool) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	return event


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
