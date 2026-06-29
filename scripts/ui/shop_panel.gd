## Buy, sell, and reroll UI for the shopkeeper's stock.
class_name ShopPanel
extends PanelContainer

signal close_requested
signal purchase_requested(stock_index: int)
signal sell_requested(inventory_index: int)
signal reroll_requested

# === Constants ===
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const MODE_BUY: StringName = &"buy"
const MODE_SELL: StringName = &"sell"

# === Private Variables ===
var _player: Node
var _stock: Array = []
var _selected_index: int = 0
var _item_buttons: Array[Button] = []
var _item_list: VBoxContainer
var _mode: StringName = MODE_BUY
var _reroll_cost: int = 0

# === Onready ===
@onready var content_box: VBoxContainer = $Margin/VBox
@onready var close_button: Button = $Margin/VBox/Header/CloseButton
@onready var output: RichTextLabel = $Margin/VBox/Output
@onready var item_scroll: ScrollContainer = $Margin/VBox/ItemScroll
@onready var buy_tab_button: Button = $Margin/VBox/ModeTabs/BuyTabButton
@onready var sell_tab_button: Button = $Margin/VBox/ModeTabs/SellTabButton
@onready var reroll_button: Button = $Margin/VBox/ModeTabs/RerollButton


# === Lifecycle Methods ===
func _ready() -> void:
	output.bbcode_enabled = true
	output.custom_minimum_size = Vector2(700, 320)
	item_scroll.custom_minimum_size = Vector2(700, 224)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ensure_item_list()
	close_button.pressed.connect(_request_close)
	buy_tab_button.pressed.connect(_set_mode.bind(MODE_BUY))
	sell_tab_button.pressed.connect(_set_mode.bind(MODE_SELL))
	reroll_button.pressed.connect(_request_reroll)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _is_escape_key(event):
		_request_close()
		get_viewport().set_input_as_handled()
		return
	if _is_tab_key(event):
		_toggle_mode()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_up"):
		select_previous()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_down"):
		select_next()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		activate_selected()
		get_viewport().set_input_as_handled()


# === Public Methods ===
func refresh(player: Node, stock: Array, reroll_cost: int = 0) -> void:
	_player = player
	_stock = stock
	_reroll_cost = reroll_cost
	_clamp_selection()
	var gold: int = _get_player_gold()
	_ensure_item_list()
	_refresh_controls(gold)
	_rebuild_item_buttons(gold)
	_refresh_details(gold)


func select_previous() -> void:
	var active_items: Array = _get_active_items()
	if active_items.is_empty():
		return
	_selected_index = wrapi(_selected_index - 1, 0, active_items.size())
	_refresh_item_buttons(_get_player_gold())
	_refresh_details(_get_player_gold())
	_grab_selected_button_focus()


func select_next() -> void:
	var active_items: Array = _get_active_items()
	if active_items.is_empty():
		return
	_selected_index = wrapi(_selected_index + 1, 0, active_items.size())
	_refresh_item_buttons(_get_player_gold())
	_refresh_details(_get_player_gold())
	_grab_selected_button_focus()


func activate_selected() -> void:
	if _mode == MODE_SELL:
		sell_selected()
	else:
		buy_selected()


func buy_selected() -> void:
	if _stock.is_empty():
		return
	purchase_requested.emit(_selected_index)


func sell_selected() -> void:
	if _player == null or _player.inventory_component == null:
		return
	if _player.inventory_component.items.is_empty():
		return
	sell_requested.emit(_selected_index)


# === Private Methods ===
func _toggle_mode() -> void:
	_set_mode(MODE_SELL if _mode == MODE_BUY else MODE_BUY)


func _set_mode(mode: StringName) -> void:
	if _mode == mode:
		_refresh_controls(_get_player_gold())
		return
	_mode = mode
	_selected_index = 0
	refresh(_player, _stock, _reroll_cost)
	_grab_selected_button_focus()


func _request_reroll() -> void:
	if _mode != MODE_BUY:
		return
	reroll_requested.emit()


func _refresh_controls(gold: int) -> void:
	var is_buying: bool = _mode == MODE_BUY
	buy_tab_button.button_pressed = is_buying
	sell_tab_button.button_pressed = not is_buying
	buy_tab_button.text = "BUY"
	sell_tab_button.text = "SELL"
	buy_tab_button.add_theme_color_override(
		"font_color", Color.html("#f1c75b") if is_buying else Color.html("#777788")
	)
	sell_tab_button.add_theme_color_override(
		"font_color", Color.html("#f1c75b") if not is_buying else Color.html("#777788")
	)
	reroll_button.visible = is_buying
	reroll_button.text = "Reroll %dg" % _reroll_cost
	reroll_button.disabled = (not is_buying) or gold < _reroll_cost


func _clamp_selection() -> void:
	var active_items: Array = _get_active_items()
	if active_items.is_empty():
		_selected_index = 0
	else:
		_selected_index = clampi(_selected_index, 0, active_items.size() - 1)


func _get_active_items() -> Array:
	if _mode == MODE_SELL:
		if _player == null or _player.inventory_component == null:
			return []
		return _player.inventory_component.items
	return _stock


func _ensure_item_list() -> void:
	if _item_list != null:
		return
	_item_list = VBoxContainer.new()
	_item_list.name = "ItemList"
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 4)
	item_scroll.add_child(_item_list)


func _rebuild_item_buttons(gold: int) -> void:
	for button: Button in _item_buttons:
		if is_instance_valid(button):
			_item_list.remove_child(button)
			button.queue_free()
	_item_buttons.clear()

	var active_items: Array = _get_active_items()
	for index: int in range(active_items.size()):
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(0, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_entered.connect(_select_index.bind(index))
		button.pressed.connect(_on_item_button_pressed.bind(index))
		_item_list.add_child(button)
		_item_buttons.append(button)
	_refresh_item_buttons(gold)


func _refresh_item_buttons(gold: int) -> void:
	var active_items: Array = _get_active_items()
	for index: int in range(_item_buttons.size()):
		var item: Resource = active_items[index]
		var marker: String = ">" if index == _selected_index else " "
		var price_text: String = ""
		var suffix: String = ""
		if _mode == MODE_SELL:
			price_text = "%dg" % _get_item_sell_price(item)
			if _player != null and _player.inventory_component.is_equipped(item):
				suffix = " [equipped]"
		else:
			var price: int = _get_item_price_for_player(item)
			var missing_gold: int = max(0, price - gold)
			var afford_text: String = "" if missing_gold == 0 else " (need %dg)" % missing_gold
			price_text = "%dg" % price
			suffix = afford_text
		_item_buttons[index].text = "%s %s - %s%s" % [marker, item.display_name, price_text, suffix]
		_item_buttons[index].tooltip_text = (
			"%s\n%s" % [item.description, ", ".join(_item_effect_tags(item))]
		)
		var button_color: String = "#f2f2f2" if index == _selected_index else "#c7c3d6"
		_item_buttons[index].add_theme_color_override("font_color", Color.html(button_color))


func _refresh_details(gold: int) -> void:
	var mode_label: String = "SELL" if _mode == MODE_SELL else "BUY"
	var help: String = (
		"Tab buy/sell   Up/Down select   Enter/click %s   Esc closes"
		% ("sells" if _mode == MODE_SELL else "buys")
	)
	var lines: Array[String] = [
		"[font_size=22][color=#f1c75b]SHOP - %s[/color][/font_size]" % mode_label,
		"[color=#555566]%s[/color]" % help,
		"",
		"[color=#ffd866]Gold: %d[/color]" % gold,
	]
	if _player != null and _player.stats_component != null:
		var cha_mod: int = Dice.modifier(_player.stats_component.charisma)
		if cha_mod != 0:
			var price_pct: int = max(50, 100 - 5 * cha_mod)
			var sell_pct: int = int(clampf(0.35 + 0.02 * cha_mod, 0.25, 0.50) * 100.0)
			lines.append(
				(
					"[color=#9999aa]CHA: buys cost %d%% base, sells pay %d%% value.[/color]"
					% [price_pct, sell_pct]
				)
			)
	lines.append("")
	lines.append("[color=#555566]──────────────────────────────────[/color]")
	lines.append_array(_get_selected_item_details())
	output.text = "\n".join(lines)


func _get_selected_item_details() -> Array[String]:
	var active_items: Array = _get_active_items()
	if active_items.is_empty():
		if _mode == MODE_SELL:
			return ["You have nothing to sell."]
		return ["Sold out. Come back after the next restock."]
	var item: Resource = active_items[_selected_index]
	var value_line: String = ""
	if _mode == MODE_SELL:
		value_line = (
			"%s %s  sell %dg (value %dg)"
			% [
				item.get_rarity_name(),
				item.get_kind_name(),
				_get_item_sell_price(item),
				item.get_price()
			]
		)
	else:
		value_line = (
			"%s %s  %dg (base %dg)"
			% [
				item.get_rarity_name(),
				item.get_kind_name(),
				_get_item_price_for_player(item),
				item.get_price()
			]
		)
	var lines: Array[String] = [
		_colored_item_name(item),
		value_line,
		item.description,
		"",
	]
	match item.kind:
		ItemDataScript.ItemKind.WEAPON:
			_append_weapon_shop_details(lines, item)
		ItemDataScript.ItemKind.ARMOR:
			_append_armor_shop_details(lines, item)
		ItemDataScript.ItemKind.ACCESSORY:
			_append_accessory_shop_details(lines, item)
		ItemDataScript.ItemKind.CONSUMABLE:
			_append_consumable_details(lines, item)
	var special_line: String = _special_detail(item)
	if not special_line.is_empty():
		lines.append(special_line)
	return lines


func _append_weapon_shop_details(lines: Array[String], item: Resource) -> void:
	lines.append(
		(
			"Weapon: d%d%+d damage, %+d accuracy"
			% [item.damage_sides, item.damage_bonus, item.attack_bonus]
		)
	)
	if item.is_ranged_weapon:
		lines.append("Range: %d" % item.range)
	if _player != null and _player.inventory_component != null:
		var inv: Node = _player.inventory_component
		var current_weapon: Resource = (
			inv.get_equipped_ranged_weapon()
			if item.is_ranged_weapon
			else inv.get_preferred_melee_weapon()
		)
		var cur_accuracy: int = 0 if current_weapon == null else current_weapon.attack_bonus
		var cur_dmg_sides: int = 4 if current_weapon == null else current_weapon.damage_sides
		var cur_dmg_bonus: int = 0 if current_weapon == null else current_weapon.damage_bonus
		var role: String = "ranged" if item.is_ranged_weapon else "melee"
		lines.append(
			(
				"Current %s: d%d%+d damage, %+d accuracy"
				% [role, cur_dmg_sides, cur_dmg_bonus, cur_accuracy]
			)
		)
		(
			lines
			. append(
				(
					"Change: damage die %+d, damage %+d, accuracy %+d"
					% [
						item.damage_sides - cur_dmg_sides,
						item.damage_bonus - cur_dmg_bonus,
						item.attack_bonus - cur_accuracy,
					]
				)
			)
		)


func _append_armor_shop_details(lines: Array[String], item: Resource) -> void:
	lines.append("Armor: %+d AC" % item.armor_bonus)
	if _player != null and _player.inventory_component != null and _player.stats_component != null:
		var inv: Node = _player.inventory_component
		var stats: Node = _player.stats_component
		var current_armor: Resource = inv.equipped_armor
		var cur_armor_bonus: int = 0 if current_armor == null else current_armor.armor_bonus
		var cur_ac: int = stats.get_armor_class()
		var preview_ac: int = cur_ac - cur_armor_bonus + item.armor_bonus
		lines.append(
			"Current AC: %d  With item: %d  Change: %+d" % [cur_ac, preview_ac, preview_ac - cur_ac]
		)


func _append_accessory_shop_details(lines: Array[String], item: Resource) -> void:
	lines.append(
		(
			"Accessory: %+d accuracy, %+d damage, %+d AC"
			% [item.attack_bonus, item.damage_bonus, item.armor_bonus]
		)
	)
	if _player != null and _player.inventory_component != null:
		var inv: Node = _player.inventory_component
		var acc1: Resource = inv.equipped_accessory_1
		var acc2: Resource = inv.equipped_accessory_2
		var equipped: Array[Resource] = []
		if acc1 != null:
			equipped.append(acc1)
		if acc2 != null:
			equipped.append(acc2)
		if equipped.is_empty():
			lines.append("Current: no accessories equipped.")
		else:
			lines.append("Equipped accessories:")
			for acc: Resource in equipped:
				lines.append(
					(
						"  %s: %+d acc, %+d dmg, %+d AC"
						% [acc.display_name, acc.attack_bonus, acc.damage_bonus, acc.armor_bonus]
					)
				)
		var total_accuracy: int = (
			(acc1.attack_bonus if acc1 != null else 0) + (acc2.attack_bonus if acc2 != null else 0)
		)
		var total_dmg: int = (
			(acc1.damage_bonus if acc1 != null else 0) + (acc2.damage_bonus if acc2 != null else 0)
		)
		var total_ac: int = (
			(acc1.armor_bonus if acc1 != null else 0) + (acc2.armor_bonus if acc2 != null else 0)
		)
		lines.append(
			(
				"Change: accuracy %+d, damage %+d, AC %+d"
				% [
					item.attack_bonus - total_accuracy,
					item.damage_bonus - total_dmg,
					item.armor_bonus - total_ac
				]
			)
		)


func _append_consumable_details(lines: Array[String], item: Resource) -> void:
	match item.use_effect:
		ItemDataScript.ItemUse.HEAL:
			(
				lines
				. append(
					(
						"Consumable: restores %d HP + INT modifier + 10%% base per positive INT modifier"
						% item.healing_amount
					)
				)
			)
		ItemDataScript.ItemUse.SHIELD:
			lines.append(
				"Consumable: %+d AC for %d turns" % [item.armor_bonus, item.effect_duration]
			)
		ItemDataScript.ItemUse.HASTE:
			lines.append("Consumable: skips %d enemy phase" % item.effect_duration)
		ItemDataScript.ItemUse.REGEN:
			lines.append(
				(
					"Consumable: restores %d HP for %d turns"
					% [item.healing_amount, item.effect_duration]
				)
			)
		ItemDataScript.ItemUse.RANGED_ATTACK:
			(
				lines
				. append(
					(
						"Targeted: range %d, WIS accuracy, magic damage %dd%d%+d plus double positive WIS modifier"
						% [item.range, item.damage_dice, item.damage_sides, item.damage_bonus]
					)
				)
			)
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			(
				lines
				. append(
					(
						"Targeted: range %d, cannot miss, force damage %dd%d%+d plus double positive WIS modifier"
						% [item.range, item.damage_dice, item.damage_sides, item.damage_bonus]
					)
				)
			)
		ItemDataScript.ItemUse.SLEEP:
			lines.append(
				(
					"Targeted: range %d, highlighted radius %d, sleeps enemies %d turns"
					% [item.range, item.target_radius, item.effect_duration]
				)
			)
		ItemDataScript.ItemUse.AREA_DAMAGE:
			var area_text: String = (
				(
					"Targeted: range %d, highlighted radius %d, hits every visible enemy "
					+ "for %dd%d%+d plus double positive WIS modifier"
				)
				% [
					item.range,
					item.target_radius,
					item.damage_dice,
					item.damage_sides,
					item.damage_bonus,
				]
			)
			lines.append(area_text)
		_:
			lines.append("Consumable: no effect")


func _item_effect_tags(item: Resource) -> Array[String]:
	var tags: Array[String] = []
	if item.range > 1:
		tags.append("range %d" % item.range)
	if item.target_radius > 0:
		tags.append("radius %d" % item.target_radius)
	if item.healing_amount > 0:
		tags.append("heals %d HP +INT scaling" % item.healing_amount)
	if item.damage_sides > 0:
		var stat_bonus_tag: String = (
			" +WISx2" if item.kind == ItemDataScript.ItemKind.CONSUMABLE else ""
		)
		(
			tags
			. append(
				(
					"damage %dd%d%+d%s"
					% [
						item.damage_dice,
						item.damage_sides,
						item.damage_bonus,
						stat_bonus_tag,
					]
				)
			)
		)
	if item.armor_bonus != 0:
		tags.append("AC %+d" % item.armor_bonus)
	if item.special_effect != ItemDataScript.ItemSpecial.NONE:
		tags.append(_special_detail(item))
	if tags.is_empty():
		tags.append(item.get_kind_name())
	return tags


func _special_detail(item: Resource) -> String:
	match item.special_effect:
		ItemDataScript.ItemSpecial.KILL_REGEN_PERCENT:
			return "kill regen %d%% max HP" % item.special_amount
		ItemDataScript.ItemSpecial.CURRENT_HP_DAMAGE_PERCENT:
			return "ranged hit +%d%% current HP" % item.special_amount
		ItemDataScript.ItemSpecial.DASH_CHARGE:
			return "dash every %d actions" % item.special_cooldown
	return ""


func _select_index(index: int) -> void:
	var active_items: Array = _get_active_items()
	if index < 0 or index >= active_items.size() or index == _selected_index:
		return
	_selected_index = index
	var gold: int = _get_player_gold()
	_refresh_item_buttons(gold)
	_refresh_details(gold)


func _on_item_button_pressed(index: int) -> void:
	_select_index(index)
	activate_selected()


func _grab_selected_button_focus() -> void:
	if _selected_index < 0 or _selected_index >= _item_buttons.size():
		return
	_item_buttons[_selected_index].grab_focus()


func _get_player_gold() -> int:
	if _player != null and _player.stats_component != null:
		return _player.stats_component.gold
	return 0


func _request_close() -> void:
	close_requested.emit()


func _colored_item_name(item: Resource) -> String:
	return "[color=%s]%s[/color]" % [item.get_rarity_color(), item.display_name]


func _is_escape_key(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_cancel"):
		return true
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and (key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE)
	)


func _is_tab_key(event: InputEvent) -> bool:
	var key_event: InputEventKey = event as InputEventKey
	return (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and key_event.keycode == KEY_TAB
	)


func _get_item_price_for_player(item: Resource) -> int:
	var base_price: int = item.get_price()
	if _player == null or _player.stats_component == null:
		return base_price
	var cha_mod: int = Dice.modifier(_player.stats_component.charisma)
	var multiplier: float = clampf(1.0 - 0.05 * cha_mod, 0.5, 1.5)
	return max(1, ceili(base_price * multiplier))


func _get_item_sell_price(item: Resource) -> int:
	if _player == null or _player.stats_component == null:
		return max(1, floori(item.get_price() * 0.35))
	var cha_mod: int = Dice.modifier(_player.stats_component.charisma)
	var multiplier: float = clampf(0.35 + 0.02 * cha_mod, 0.25, 0.50)
	return max(1, floori(item.get_price() * multiplier))
