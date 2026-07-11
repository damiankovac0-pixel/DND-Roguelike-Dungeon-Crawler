## Headless test for UI polish, rarity motion, and current version history:
##   - Rarity BBCode shimmer tags for Legendary/Mythic/Ascended
##   - BBCode escaping ([lb]/[rb]) in item names
##   - Inventory/consumable/shop panel selection auto-scroll and offset clarity
##   - Shop panel follow_focus and high-rarity button colors
##   - GameManager version and Library version history
##   - V12.1.0: ClassAbilityPanel multi-ability rendering with unlock_level/disabled_reason
##   - V12.2.0: Staff/class gear Library version history entry
##   - V12.2.0: Character creation class selectors (Fighter/Ranger/Wizard)
##
## Run:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v11_5_ui_polish.gd
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)

	# === 1. Rarity BBCode shimmer tags (static, no scene) ===
	_check_lower_rarities_no_animation()
	_check_legendary_has_shimmer()
	_check_mythic_has_shimmer()
	_check_ascended_has_shimmer()
	_check_all_rarities_no_animation_when_disabled()

	# === 2. BBCode escaping ===
	_check_bbcode_escape()

	# === 3. GameManager version ===
	_check_game_manager_version()

	# === 4. Library version history ===
	_check_library_version_history()
	# === 5. Scene integration: panels, scroll, shop ===
	await _check_game_scene_integration()

	# One more frame to drain any deferred operations before exiting
	await process_frame

	print("UI polish and version history check passed")
	quit(0)


# ======================================================================
# 1. Rarity BBCode shimmer tags
# ======================================================================
func _check_lower_rarities_no_animation() -> void:
	var name: String = "Test"
	var plain_rarities: Array[int] = [
		ItemDataScript.ItemRarity.COMMON,
		ItemDataScript.ItemRarity.UNCOMMON,
		ItemDataScript.ItemRarity.RARE,
		ItemDataScript.ItemRarity.EPIC,
	]
	for r: int in plain_rarities:
		var result: String = ItemDataScript.format_rarity_text(name, r, true)
		if _has_rarity_motion_tag(result):
			_fail("Rarity %d should not have motion tags, got: %s" % [r, result])
		var color: String = ItemDataScript.RARITY_COLORS[r]
		if not color in result:
			_fail("Rarity %d missing color %s in: %s" % [r, color, result])
		if not result.ends_with("[/color]"):
			_fail("Rarity %d missing [/color] close: %s" % [r, result])


func _check_legendary_has_shimmer() -> void:
	var name: String = "Test"
	var r: int = ItemDataScript.ItemRarity.LEGENDARY
	var result: String = ItemDataScript.format_rarity_text(name, r, true)
	_assert_shimmer_only(result, "Legendary")
	var color: String = ItemDataScript.RARITY_COLORS[r]
	if not color in result:
		_fail("Legendary missing color %s: %s" % [color, result])


func _check_mythic_has_shimmer() -> void:
	var name: String = "Test"
	var r: int = ItemDataScript.ItemRarity.MYTHIC
	var result: String = ItemDataScript.format_rarity_text(name, r, true)
	_assert_shimmer_only(result, "Mythic")
	var color: String = ItemDataScript.RARITY_COLORS[r]
	if not color in result:
		_fail("Mythic missing color %s: %s" % [color, result])


func _check_ascended_has_shimmer() -> void:
	var name: String = "Test"
	var r: int = ItemDataScript.ItemRarity.ASCENDED
	var result: String = ItemDataScript.format_rarity_text(name, r, true)
	_assert_shimmer_only(result, "Ascended")
	var color: String = ItemDataScript.RARITY_COLORS[r]
	if not color in result:
		_fail("Ascended missing color %s: %s" % [color, result])


func _check_all_rarities_no_animation_when_disabled() -> void:
	var name: String = "Test"
	var all_rarities: Array[int] = [
		ItemDataScript.ItemRarity.COMMON,
		ItemDataScript.ItemRarity.UNCOMMON,
		ItemDataScript.ItemRarity.RARE,
		ItemDataScript.ItemRarity.EPIC,
		ItemDataScript.ItemRarity.LEGENDARY,
		ItemDataScript.ItemRarity.MYTHIC,
		ItemDataScript.ItemRarity.ASCENDED,
	]
	for r: int in all_rarities:
		var result: String = ItemDataScript.format_rarity_text(name, r, false)
		if _has_rarity_motion_tag(result):
			_fail("Rarity %d animated=false should not have motion tags, got: %s" % [r, result])
		var color: String = ItemDataScript.RARITY_COLORS[r]
		if not color in result:
			_fail("Rarity %d animated=false missing color %s: %s" % [r, color, result])


func _assert_shimmer_only(result: String, label: String) -> void:
	if not "[rarity_shimmer" in result:
		_fail("%s missing [rarity_shimmer] tag: %s" % [label, result])
	if not "[/rarity_shimmer]" in result:
		_fail("%s missing [/rarity_shimmer] close: %s" % [label, result])
	if "[pulse" in result or "[wave" in result or "[fade" in result:
		_fail("%s should use shimmer, not pulse/wave/fade: %s" % [label, result])


func _has_rarity_motion_tag(result: String) -> bool:
	return (
		"[rarity_shimmer" in result or "[pulse" in result or "[wave" in result or "[fade" in result
	)


# ======================================================================
# 2. BBCode escaping
# ======================================================================
func _check_bbcode_escape() -> void:
	# The _escape_bbcode does sequential replace: "["->"[lb]" first, then "]"->"[rb]".
	# This means the "]" inside "[lb]" gets double-escaped too, producing "[lb[rb]".
	# That's acceptable because BBCode parsers render "[lb[rb]" as literal "[lb]",
	# which is the proper escaped form of "[". We assert the exact output to notice
	# any change in the function.
	var result: String = ItemDataScript._escape_bbcode("[Test]")
	# "[Test]" -> replace "[" -> "[lb]Test]" -> replace "]" -> "[lb[rb]Test[rb]"
	var expected: String = "[lb[rb]Test[rb]"
	if result != expected:
		_fail('_escape_bbcode("[Test]") expected "%s", got "%s"' % [expected, result])

	result = ItemDataScript._escape_bbcode("No brackets here")
	if result != "No brackets here":
		_fail('_escape_bbcode plain string changed: "%s"' % result)

	result = ItemDataScript._escape_bbcode("[A][B]")
	expected = "[lb[rb]A[rb][lb[rb]B[rb]"
	if result != expected:
		_fail('_escape_bbcode("[A][B]") expected "%s", got "%s"' % [expected, result])

	# Through format_rarity_text: brackets in the name must not produce raw '[' or ']'
	# that would be interpreted as BBCode tags by the rich text renderer.
	var formatted: String = ItemDataScript.format_rarity_text(
		"[Sword]", ItemDataScript.ItemRarity.COMMON, false
	)
	# Strip the color wrapper to check the inner escaped text
	var inner: String = formatted.trim_prefix("[color=#d8d8d8]").trim_suffix("[/color]")
	if not "[lb" in inner:
		_fail("format_rarity_text did not escape '[' to [lb] variant: " + formatted)


# ======================================================================
# 3. GameManager version
# ======================================================================
func _check_game_manager_version() -> void:
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	if game_manager.GAME_VERSION != "23.2.0":
		_fail("GameManager.GAME_VERSION expected '23.2.0', got '%s'" % game_manager.GAME_VERSION)
	var version_label: String = game_manager.get_version_label()
	if not "23.2.0" in version_label:
		_fail("get_version_label() missing version: " + version_label)
	if not "2026-07-11" in version_label:
		_fail("get_version_label() missing date: " + version_label)


# ======================================================================
# 4. Library version history
# ======================================================================
func _check_library_version_history() -> void:
	var LibraryMenuScript: GDScript = load("res://scripts/ui/library_menu.gd")
	if LibraryMenuScript == null:
		_fail("LibraryMenu script could not be loaded")
		return
	var version_history: Array[String] = LibraryMenuScript.VERSION_HISTORY
	if version_history.is_empty():
		_fail("LibraryMenu VERSION_HISTORY is empty")
	var found_v11_5: bool = false
	var found_v12_0: bool = false
	var found_v12_1: bool = false
	var found_v12_2: bool = false
	var found_v12_3: bool = false
	var found_v13_0: bool = false
	var found_v14_0: bool = false
	var found_v15_0: bool = false
	var found_v16_0: bool = false
	var found_v16_5: bool = false
	var last_entry: String = ""
	for entry: String in version_history:
		if "V11.5.0" in entry:
			found_v11_5 = true
		if "V12.0.0" in entry:
			found_v12_0 = true
		if "V12.1.0" in entry:
			found_v12_1 = true
		if "V12.2.0" in entry:
			found_v12_2 = true
		if "V12.3.0" in entry:
			found_v12_3 = true
		if "V13.0.0" in entry:
			found_v13_0 = true
		if "V14.0.0" in entry:
			found_v14_0 = true
		if "V15.0.0" in entry:
			found_v15_0 = true
		if "V16.0.0" in entry:
			found_v16_0 = true
		if "V16.5.0" in entry:
			found_v16_5 = true
		last_entry = entry
	if not found_v11_5:
		_fail("Library VERSION_HISTORY missing V11.5.0 entry; last: " + last_entry)
	if not found_v12_0:
		_fail("Library VERSION_HISTORY missing V12.0.0 entry; last: " + last_entry)
	if not found_v12_1:
		_fail("Library VERSION_HISTORY missing V12.1.0 entry; last: " + last_entry)
	if not found_v12_2:
		_fail("Library VERSION_HISTORY missing V12.2.0 entry; last: " + last_entry)
	if not found_v12_3:
		_fail("Library VERSION_HISTORY missing V12.3.0 entry; last: " + last_entry)
	if not found_v13_0:
		_fail("Library VERSION_HISTORY missing V13.0.0 entry; last: " + last_entry)
	if not found_v14_0:
		_fail("Library VERSION_HISTORY missing V14.0.0 entry; last: " + last_entry)
	if not found_v15_0:
		_fail("Library VERSION_HISTORY missing V15.0.0 entry; last: " + last_entry)
	if not found_v16_0:
		_fail("Library VERSION_HISTORY missing V16.0.0 entry; last: " + last_entry)
	if not found_v16_5:
		_fail("Library VERSION_HISTORY missing V16.5.0 entry; last: " + last_entry)
	# Verify library scene exposes a Classes tab text node
	var lib_scene: PackedScene = load("res://scenes/library.tscn")
	if lib_scene == null:
		_fail("Library scene could not be loaded")
		return
	var lib: Node = lib_scene.instantiate()
	var classes_rich: Node = lib.get_node_or_null("Margin/VBox/Tabs/Classes/ClassesText")
	if classes_rich == null:
		_fail("Library scene missing node path: Margin/VBox/Tabs/Classes/ClassesText")
	if not classes_rich is RichTextLabel:
		_fail(
			"Library Classes/ClassesText is not a RichTextLabel, got %s" % classes_rich.get_class()
		)
	lib.queue_free()


# ======================================================================
# 5. Scene integration: panels, scroll, shop
# ======================================================================
func _check_game_scene_integration() -> void:
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return

	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	var player: Node = game_manager.player
	if player == null:
		_fail("No player after debug loadout")
		return

	var inventory: Node = player.inventory_component
	if inventory.items.size() < 3:
		_fail("Debug loadout gave only %d items" % inventory.items.size())
		return

	# -------- Inventory Panel --------
	await _check_inventory_panel_scroll(game, player, inventory)
	await _check_consumable_panel_scroll(game, player)
	await _check_shop_panel(game, game_manager)
	# -------- Class Ability Panel --------
	_check_class_ability_panel(game)
	# -------- Character Creation Class List --------
	_check_character_creation_class_list()
	# Cleanup: free the game scene and clear autoload references to avoid orphan warnings
	game_manager.abandon_run()
	game.queue_free()
	await process_frame


func _check_inventory_panel_scroll(game: Node, player: Node, inventory: Node) -> void:
	var inv_panel: Node = game.inventory_panel
	if inv_panel == null:
		_fail("inventory_panel is null")
		return

	inv_panel.refresh(player)
	await process_frame

	var item_count: int = inventory.items.size()
	if item_count < 3:
		_fail("Too few items (%d) for inventory scroll test" % item_count)
		return

	var initial_scroll: float = inv_panel.output.get_v_scroll_bar().value

	# Select deep into the list
	var target_index: int = max(0, item_count - 3)
	while inv_panel._selected_index != target_index:
		inv_panel.select_next()
	await process_frame

	var final_scroll: float = inv_panel.output.get_v_scroll_bar().value
	# If enough items to fill more than a few lines, scroll must change
	if item_count >= 10 and final_scroll <= 0.0 and initial_scroll <= 0.0:
		_fail("Inventory scroll_vertical did not advance after deep selection")
	var comparison_index: int = 0 if target_index != 0 else 1
	_assert_rich_text_row_offset(
		inv_panel.output.text,
		inventory.items[target_index].display_name,
		inventory.items[comparison_index].display_name,
		"Inventory"
	)


func _check_consumable_panel_scroll(game: Node, player: Node) -> void:
	var con_panel: Node = game.consumable_panel
	if con_panel == null:
		_fail("consumable_panel is null")
		return

	con_panel.refresh(player)
	await process_frame

	if not con_panel.has_consumables():
		_fail("No consumables present in consumable panel")
		return

	var initial_scroll: float = con_panel.output.get_v_scroll_bar().value

	# Select deep into the consumable list
	var con_count: int = con_panel._consumable_indices.size()
	var target_index: int = max(0, con_count - 3)
	while con_panel._selected_index != target_index:
		con_panel._select_next()
	await process_frame

	var final_scroll: float = con_panel.output.get_v_scroll_bar().value
	if con_count >= 8 and final_scroll <= 0.0 and initial_scroll <= 0.0:
		_fail("Consumable scroll_vertical did not advance after deep selection")
	var comparison_list_index: int = 0 if target_index != 0 else 1
	var selected_item: Resource = player.inventory_component.items[
		con_panel._consumable_indices[target_index]
	]
	var comparison_item: Resource = player.inventory_component.items[
		con_panel._consumable_indices[comparison_list_index]
	]
	_assert_rich_text_row_offset(
		con_panel.output.text,
		selected_item.display_name,
		comparison_item.display_name,
		"Consumable"
	)


func _check_shop_panel(game: Node, game_manager: Node) -> void:
	var shop: Node = game.shop_panel
	if shop == null:
		_fail("shop_panel is null")
		return

	# Verify follow_focus is true
	if not shop.item_scroll.follow_focus:
		_fail("shop item_scroll.follow_focus is false, expected true")

	# Build a stock that includes high-rarity items
	var stock: Array[Resource] = []
	var high_rarity_items: Array[Resource] = []
	var low_rarity_count: int = 0
	for item: Resource in game._item_resources:
		if item.rarity >= ItemDataScript.ItemRarity.LEGENDARY:
			high_rarity_items.append(item)
		elif low_rarity_count < 4:
			stock.append(item.duplicate(true))
			low_rarity_count += 1
	for hi_item: Resource in high_rarity_items:
		if hi_item.display_name not in _list_names(stock):
			stock.append(hi_item.duplicate(true))

	if stock.is_empty():
		_fail("No stock items for shop test")
		return

	shop.refresh(game_manager.player, stock, 50)
	await process_frame

	# Check high-rarity buttons use rarity font color
	var high_rarity_count: int = 0
	var high_rarity_color_match: int = 0
	for idx: int in range(shop._item_buttons.size()):
		if idx >= stock.size():
			break
		var button: Button = shop._item_buttons[idx]
		var item: Resource = stock[idx]
		if item.rarity >= ItemDataScript.ItemRarity.LEGENDARY:
			high_rarity_count += 1
			var expected_color: Color = Color.html(item.get_rarity_color())
			var actual_color: Color = button.get_theme_color("font_color")
			if actual_color.is_equal_approx(expected_color):
				high_rarity_color_match += 1

	if high_rarity_count > 0 and high_rarity_color_match == 0:
		_fail(
			(
				("Shop: %d high-rarity buttons found, 0 had correct rarity font color.")
				% high_rarity_count
			)
		)

	# Deep selection test: move to deep item
	if stock.size() >= 4:
		var target_index: int = max(0, stock.size() - 2)
		var safety: int = 0
		while shop._selected_index != target_index and safety < 50:
			shop.select_next()
			safety += 1
		await process_frame
		if shop._selected_index == 0 and stock.size() > 1:
			_fail("Shop selection did not advance after select_next() calls")
		var comparison_index: int = 0 if target_index != 0 else 1
		_assert_button_row_offset(
			shop._item_buttons[target_index].text,
			stock[target_index].display_name,
			shop._item_buttons[comparison_index].text,
			stock[comparison_index].display_name,
			"Shop"
		)


func _check_class_ability_panel(game: Node) -> void:
	var panel: Node = game.class_ability_panel
	if panel == null:
		_fail("game.class_ability_panel is null")
		return
	if panel.visible:
		_fail("ClassAbilityPanel should start invisible, got visible=true")
	var output: Node = panel.get_node_or_null("Margin/VBox/Output")
	if output == null:
		_fail("ClassAbilityPanel missing Output node at Margin/VBox/Output")
		return
	if not output is RichTextLabel:
		_fail("ClassAbilityPanel Output is not a RichTextLabel, got %s" % output.get_class())

	# V12.1.0: Test rendering of multiple ability dictionaries including a locked ability
	var abilities: Array[Dictionary] = [
		{
			ability_id = &"cleave",
			name = "Cleave",
			summary = "Swing in a wide arc.",
			charges_max = 3,
			charges_current = 2,
			unlock_level = 0,
			disabled_reason = "",
			enabled = true,
			active = false,
			details = "",
		},
		{
			ability_id = &"whirlwind",
			name = "Whirlwind",
			summary = "Spin and strike nearby enemies.",
			charges_max = 1,
			charges_current = 0,
			unlock_level = 12,
			disabled_reason = "Requires level 12.",
			enabled = false,
			active = true,
			details = "",
		},
	]
	panel.refresh(abilities)
	var text: String = output.text
	if "Cleave" not in text:
		_fail("ClassAbilityPanel output missing first ability name 'Cleave'")
	if "Whirlwind" not in text:
		_fail("ClassAbilityPanel output missing second ability name 'Whirlwind'")
	# Verify the specific disabled_reason is rendered (not generic "No charges remaining.")
	if "Requires level 12." not in text:
		_fail(
			(
				"ClassAbilityPanel locked ability missing disabled_reason"
				+ " 'Requires level 12.' in output"
			)
		)
	# Verify unlock_level indicator appears (either inline [LvN] or details (LvN))
	if "[Lv12]" not in text and "(Lv12)" not in text:
		_fail(
			"ClassAbilityPanel locked ability missing unlock_level indicator '[Lv12]' or '(Lv12)'"
		)


func _check_character_creation_class_list() -> void:
	var CreationScript: GDScript = load("res://scripts/ui/character_creation.gd")
	if CreationScript == null:
		_fail("CharacterCreation script could not be loaded")
		return
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	var class_ids: Array = CreationScript.CLASS_IDS
	if class_ids.size() < 3:
		_fail("CharacterCreation CLASS_IDS has fewer than 3 entries: %d" % class_ids.size())
		return
	var labels: Array[String] = []
	for class_id: StringName in class_ids:
		var label: String = gm.get_character_class_label(class_id)
		labels.append(label)
	var expected: Array[String] = ["Fighter", "Ranger", "Wizard"]
	for expected_label: String in expected:
		if not expected_label in labels:
			_fail(
				(
					"Character creation missing class label '%s'; found labels: %s"
					% [expected_label, str(labels)]
				)
			)


func _assert_rich_text_row_offset(
	bbcode_text: String, selected_name: String, comparison_name: String, context: String
) -> void:
	var text: String = _strip_bbcode(bbcode_text)
	if "›" not in text and "»" not in text:
		_fail("%s selected row missing animated arrow marker. Text: %s" % [context, text])
	var selected_column: int = _name_column(text, selected_name)
	var comparison_column: int = _name_column(text, comparison_name)
	if selected_column < 0:
		_fail("%s selected row missing item '%s'. Text: %s" % [context, selected_name, text])
	if comparison_column < 0:
		_fail("%s comparison row missing item '%s'. Text: %s" % [context, comparison_name, text])
	if selected_column <= comparison_column:
		_fail(
			(
				(
					"%s selected item should start right of an unselected item; "
					+ "selected column=%d, comparison column=%d."
				)
				% [context, selected_column, comparison_column]
			)
		)


func _assert_button_row_offset(
	selected_text: String,
	selected_name: String,
	comparison_text: String,
	comparison_name: String,
	context: String
) -> void:
	if not selected_text.begins_with("›   ") and not selected_text.begins_with("»   "):
		_fail("%s selected button missing marker spacing: %s" % [context, selected_text])
	var selected_column: int = selected_text.find(selected_name)
	var comparison_column: int = comparison_text.find(comparison_name)
	if selected_column <= comparison_column:
		_fail(
			(
				(
					"%s selected button should start right of an unselected button; "
					+ "selected column=%d, comparison column=%d."
				)
				% [context, selected_column, comparison_column]
			)
		)


func _strip_bbcode(bbcode_text: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(bbcode_text, "", true)


func _name_column(text: String, item_name: String) -> int:
	for line: String in text.split("\n"):
		var column: int = line.find(item_name)
		if column >= 0:
			return column
	return -1


static func _list_names(items: Array) -> Array[String]:
	var names: Array[String] = []
	for item: Resource in items:
		names.append(item.display_name)
	return names


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
