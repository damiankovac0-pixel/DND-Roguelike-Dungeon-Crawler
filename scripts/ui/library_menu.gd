## In-game codex: enemy lore, item stats, trap data, mechanics, version history, and run archive.
class_name LibraryMenu
extends Control

# === Constants ===
const RarityShimmerEffect = preload("res://scripts/ui/rarity_shimmer_effect.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const TrapDataScript = preload("res://scripts/resources/trap_data.gd")
const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")
const DamageTypeTextScript = preload("res://scripts/ui/damage_type_text.gd")
const LibraryVisualPreviewScript = preload("res://scripts/ui/library_visual_preview.gd")
const DIFFICULTY_NORMAL_COLOR: String = "#8fb3ff"
const DIFFICULTY_HARD_COLOR: String = "#ff5777"
const DIFFICULTY_NIGHTMARE_COLOR: String = "#c77dff"
const SHARDBEARER_NAMES: Dictionary = {
	&"observer": "Observer",
	&"seraphine": "Seraphine",
	&"vorrak": "Vorrak",
	&"kaelros": "Kaelros",
	&"nyxara": "Nyxara",
}
const ENEMY_NOTES: Dictionary = {
	"Rat": "Low HP early swarmer. Small poison chance can chip you for 3 turns.",
	"Bat": "Very low HP but high AC for floor 1. Annoying to hit, quick to kill once struck.",
	"Goblin": "Baseline early melee enemy with a chance to carry extra gold.",
	"Kobold": "Light skirmisher with better AC and accuracy than its HP suggests.",
	"Skeleton":
	(
		"Bone archer/guard. Fires short-range piercing shots every third action "
		+ "and tries to hold range 2."
	),
	"Stone Sentry": "Tower construct. High AC, partial melee resistance, and a magic weakness.",
	"Eye Acolyte": "Tower watcher. Keeps short range and fires weak magic bolts.",
	"Clockwork Spider": "Brass skitterer. Hard to shoot and carries a small poison bite.",
	"Zombie": "Low AC HP sponge. Has a 20% chance to stand back up once at 40% HP.",
	"Orc": "Mid-depth bruiser with steady accuracy and d8+3 melee damage.",
	"Cultist":
	"Kiting caster. Resists magic, fires magic bolts every third action, and prefers range 3.",
	"Wraith": "Evasive spirit. Resists melee damage but takes extra magic damage.",
	"Troll": "Heavy bruiser by stats. Large HP pool and 50% ranged resistance.",
	"Thorn Lasher": "Garden controller. Whips from range and backs up to keep distance.",
	"Spore Servant": "Fungal undead. Poisons on hit and sometimes rises again at low HP.",
	"Briar Witch": "Garden caster. Vulnerable to melee pressure but resists magic.",
	"Ogre Brute":
	"Large late bruiser. Big HP and d12+5 melee damage, but less armor than elite casters.",
	"Abyss Knight": "Armored deep melee elite with high AC, high accuracy, and heavy damage.",
	"Lich":
	(
		"Deep caster. Resists ranged damage, is vulnerable to magic, kites, "
		+ "and raises visible brittle melee skeletons."
	),
	"Ancient Dragon":
	"End-depth apex enemy. High AC/HP melee threat that hurls fireballs at range.",
	"Ash Revenant": "Cinder undead. Solid armor, heavy hits, and a chance to reform from ash.",
	"Ember Archer": "Cinder skirmisher. Keeps long range and fires burning shots.",
	"Flame Acolyte": "Cinder caster. Resists magic and throws smaller fireballs from range.",
	"Drowned Knight": "Sunken armored guard. Resists ranged pokes but is weak to magic.",
	"Harpooner": "Sunken ranged soldier. Holds mid-range and drags fights out with piercing shots.",
	"Abyssal Eel": "Fast Sunken predator. High AC and short magic bursts make it slippery.",
	"Tidecaller": "Sunken caster. Resists magic and attacks from long range.",
	"Mirror Duelist": "Glass melee elite. Resists weapons but cracks under magic.",
	"Prism Seer": "Glass caster. Resists magic but is fragile against weapons.",
	"Shard Golem": "Glass brute. Big HP and ranged resistance, but magic breaks it well.",
	"Glass Dragonling":
	"Rare Glass apex. Breathes fire but is less durable than the Ancient Dragon.",
	"Void Herald": "Endless special. Long-range void magic and elite late-game stats.",
	"Deep Maw": "Endless special. Massive melee threat with poison and a magic weakness.",
	"Starved Godling": "Endless apex rare. Extremely dangerous and intentionally low weight.",
}
const ITEM_TYPE_LORE: Dictionary = {
	ItemDataScript.ItemKind.CONSUMABLE:
	(
		"Consumed with H. Some act instantly; targeted scrolls open targeting mode "
		+ "and spend only after a visible in-range target or cell is confirmed."
	),
	ItemDataScript.ItemKind.WEAPON:
	(
		"Equipped weapons set melee or ranged attacks. Staffs are wizard-only"
		+ " ranged weapons that use WIS and deal magic damage. Some named weapons have unique effects."
	),
	ItemDataScript.ItemKind.ARMOR: "Equipped armor adds AC; rare armor may carry utility effects.",
	ItemDataScript.ItemKind.ACCESSORY:
	"Two accessory slots. Some add stats; others add cooldown utility like dashes.",
}
const VERSION_HISTORY: Array[String] = preload("res://scripts/version_history.gd").VERSION_HISTORY
const ENTRY_KIND_ENEMY: StringName = &"enemy"
const ENTRY_KIND_ITEM: StringName = &"item"
const ENTRY_KIND_TRAP: StringName = &"trap"
const COMPACT_LAYOUT_WIDTH: float = 760.0
const WIDE_SPLIT_OFFSET: int = 280
const COMPACT_SPLIT_OFFSET: int = 128
const WIDE_LIST_MINIMUM: Vector2 = Vector2(240, 0)
const WIDE_DETAIL_MINIMUM: Vector2 = Vector2(336, 0)
const COMPACT_LIST_MINIMUM: Vector2 = Vector2(0, 128)
const WIDE_PREVIEW_HEIGHT: float = 192.0
const COMPACT_PREVIEW_HEIGHT: float = 136.0
const WIDE_HORIZONTAL_MARGIN: int = 32
const WIDE_VERTICAL_MARGIN: int = 24
const COMPACT_MARGIN: int = 16
const WIDE_TITLE_SIZE: int = 28
const COMPACT_TITLE_SIZE: int = 20
const WIDE_BACK_WIDTH: float = 112.0
const COMPACT_BACK_WIDTH: float = 96.0

# === Private Variables ===
var _bestiary_buttons: Array[Button] = []
var _scribes_buttons: Array[Button] = []
var _dungeon_buttons: Array[Button] = []
var _selected_buttons: Dictionary = {}
var _reduced_vfx_enabled: bool = true
var _compact_layout: bool = false
var _layout_initialized: bool = false

# === Onready ===
@onready var margin: MarginContainer = $Margin
@onready var header: HBoxContainer = $Margin/VBox/Header
@onready var title_label: Label = $Margin/VBox/Header/Title
@onready var back_button: Button = $Margin/VBox/Header/BackButton
@onready var tabs: TabContainer = %Tabs
@onready var bestiary_split: SplitContainer = %Bestiary
@onready var scribes_split: SplitContainer = %Scribes
@onready var dungeon_split: SplitContainer = $"Margin/VBox/Tabs/Dungeon Notes"
@onready var bestiary_entries: VBoxContainer = %BestiaryEntries
@onready var scribes_entries: VBoxContainer = %ScribesEntries
@onready var dungeon_entries: VBoxContainer = %DungeonEntries
@onready var bestiary_details: RichTextLabel = %BestiaryDetails
@onready var scribes_details: RichTextLabel = %ScribesDetails
@onready var dungeon_details: RichTextLabel = %DungeonDetails
@onready var bestiary_preview: LibraryVisualPreviewScript = %BestiaryPreview
@onready var scribes_preview: LibraryVisualPreviewScript = %ScribesPreview
@onready var dungeon_preview: LibraryVisualPreviewScript = %DungeonPreview
@onready var info_text: RichTextLabel = %InfoText
@onready var archive_text: RichTextLabel = %ArchiveText
@onready var classes_text: RichTextLabel = %ClassesText


# === Lifecycle Methods ===
func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	tabs.tab_changed.connect(_on_tab_changed)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_reduced_vfx_enabled = SensoryFeedback.is_reduced_vfx_preferred()
	for rich_text: RichTextLabel in [
		bestiary_details,
		scribes_details,
		dungeon_details,
		classes_text,
		info_text,
		archive_text,
	]:
		rich_text.add_theme_constant_override("line_separation", 4)
		rich_text.bbcode_enabled = true
		rich_text.install_effect(RarityShimmerEffect.new())
	_build_resource_browsers()
	classes_text.text = _build_classes_text()
	info_text.text = _build_info_text()
	archive_text.text = _build_archive_text()
	_apply_responsive_layout()
	_update_back_focus_neighbor()
	back_button.grab_focus()


func _input(event: InputEvent) -> void:
	var viewport: Viewport = get_viewport()
	if _is_escape_key(event):
		_on_back_pressed()
		if viewport != null:
			viewport.set_input_as_handled()
	elif event.is_action_pressed(&"ui_left"):
		tabs.current_tab = wrapi(tabs.current_tab - 1, 0, tabs.get_tab_count())
		if viewport != null:
			viewport.set_input_as_handled()
	elif event.is_action_pressed(&"ui_right"):
		tabs.current_tab = wrapi(tabs.current_tab + 1, 0, tabs.get_tab_count())
		if viewport != null:
			viewport.set_input_as_handled()


# === Private Methods ===
func _build_resource_browsers() -> void:
	var enemies: Array[Resource] = _load_resources_with_paths(ResourcePaths.ENEMY_PATHS)
	enemies.sort_custom(_sort_enemy)
	_populate_entry_list(
		enemies,
		ResourcePaths.ENEMY_PATHS.size() - enemies.size(),
		ENTRY_KIND_ENEMY,
		bestiary_entries,
		_bestiary_buttons
	)

	var items: Array[Resource] = _load_resources_with_paths(ResourcePaths.ITEM_PATHS)
	items.sort_custom(_sort_item)
	_populate_entry_list(
		items,
		ResourcePaths.ITEM_PATHS.size() - items.size(),
		ENTRY_KIND_ITEM,
		scribes_entries,
		_scribes_buttons
	)

	var traps: Array[Resource] = _load_resources_with_paths(ResourcePaths.TRAP_PATHS)
	traps.sort_custom(_sort_trap)
	_populate_entry_list(
		traps,
		ResourcePaths.TRAP_PATHS.size() - traps.size(),
		ENTRY_KIND_TRAP,
		dungeon_entries,
		_dungeon_buttons
	)


func _populate_entry_list(
	resources: Array[Resource],
	failed_count: int,
	entry_kind: StringName,
	entry_container: VBoxContainer,
	buttons: Array[Button]
) -> void:
	for child: Node in entry_container.get_children():
		entry_container.remove_child(child)
		child.queue_free()
	buttons.clear()
	if resources.is_empty():
		_show_empty_browser(entry_kind, entry_container)
		return

	var button_group: ButtonGroup = ButtonGroup.new()
	for resource: Resource in resources:
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.button_group = button_group
		button.text = _entry_row_text(resource, entry_kind)
		button.tooltip_text = "%s — ASCII glyph '%s'" % [resource.display_name, resource.glyph]
		var select_callable: Callable = _select_entry.bind(resource, entry_kind, button)
		button.mouse_entered.connect(select_callable)
		button.pressed.connect(select_callable)
		button.focus_entered.connect(select_callable)
		entry_container.add_child(button)
		buttons.append(button)
	if failed_count > 0:
		var warning_label: Label = Label.new()
		warning_label.text = "%d record(s) could not be loaded." % failed_count
		warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry_container.add_child(warning_label)
	_wire_entry_focus(buttons)
	_select_entry(resources[0], entry_kind, buttons[0])


func _entry_row_text(resource: Resource, entry_kind: StringName) -> String:
	match entry_kind:
		ENTRY_KIND_ITEM:
			return (
				"%s  %s  · %s" % [resource.glyph, resource.display_name, resource.get_rarity_name()]
			)
		ENTRY_KIND_TRAP:
			return "%s  %s  · DC %d" % [resource.glyph, resource.display_name, resource.detect_dc]
	return "%s  %s" % [resource.glyph, resource.display_name]


func _select_entry(resource: Resource, entry_kind: StringName, source_button: Button) -> void:
	if resource == null or not is_instance_valid(source_button):
		return
	source_button.button_pressed = true
	_selected_buttons[entry_kind] = source_button
	match entry_kind:
		ENTRY_KIND_ENEMY:
			bestiary_details.text = _build_bestiary_selection_text(resource)
			bestiary_preview.show_enemy(resource)
			_reset_detail_scroll(bestiary_details)
		ENTRY_KIND_ITEM:
			scribes_details.text = _build_scribes_selection_text(resource)
			scribes_preview.show_item(resource)
			_reset_detail_scroll(scribes_details)
		ENTRY_KIND_TRAP:
			dungeon_details.text = _build_dungeon_selection_text(resource)
			dungeon_preview.show_trap(resource)
			_reset_detail_scroll(dungeon_details)


func _show_empty_browser(entry_kind: StringName, entry_container: VBoxContainer) -> void:
	var category: String = "library"
	match entry_kind:
		ENTRY_KIND_ENEMY:
			category = "bestiary"
		ENTRY_KIND_ITEM:
			category = "item"
		ENTRY_KIND_TRAP:
			category = "trap"
	var message: String = (
		"No %s records could be loaded. Use Back to return to the main menu." % category
	)
	var empty_label: Label = Label.new()
	empty_label.text = message
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry_container.add_child(empty_label)
	match entry_kind:
		ENTRY_KIND_ENEMY:
			bestiary_details.text = message
			bestiary_preview.show_empty(message)
		ENTRY_KIND_ITEM:
			scribes_details.text = message
			scribes_preview.show_empty(message)
		ENTRY_KIND_TRAP:
			dungeon_details.text = message
			dungeon_preview.show_empty(message)


func _wire_entry_focus(buttons: Array[Button]) -> void:
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		var previous: Control = back_button if index == 0 else buttons[index - 1]
		var next: Control = back_button if index == buttons.size() - 1 else buttons[index + 1]
		button.focus_neighbor_top = button.get_path_to(previous)
		button.focus_neighbor_bottom = button.get_path_to(next)
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(next)


func _reset_detail_scroll(details: RichTextLabel) -> void:
	var scroll: ScrollContainer = details.get_parent() as ScrollContainer
	if scroll != null:
		scroll.set_deferred(&"scroll_vertical", 0)


func _on_tab_changed(_tab_index: int) -> void:
	call_deferred(&"_focus_active_tab_entry")


func _focus_active_tab_entry() -> void:
	var entry_kind: StringName = _active_entry_kind()
	var buttons: Array[Button] = _buttons_for_kind(entry_kind)
	if buttons.is_empty():
		back_button.focus_neighbor_bottom = NodePath()
		back_button.grab_focus()
		return
	var target: Button = _selected_buttons.get(entry_kind) as Button
	if not is_instance_valid(target):
		target = buttons[0]
	back_button.focus_neighbor_bottom = back_button.get_path_to(target)
	target.grab_focus()


func _update_back_focus_neighbor() -> void:
	var entry_kind: StringName = _active_entry_kind()
	var buttons: Array[Button] = _buttons_for_kind(entry_kind)
	if buttons.is_empty():
		back_button.focus_neighbor_bottom = NodePath()
		return
	var target: Button = _selected_buttons.get(entry_kind) as Button
	if not is_instance_valid(target):
		target = buttons[0]
	back_button.focus_neighbor_bottom = back_button.get_path_to(target)


func _active_entry_kind() -> StringName:
	match tabs.get_tab_title(tabs.current_tab):
		"Bestiary":
			return ENTRY_KIND_ENEMY
		"Scribes":
			return ENTRY_KIND_ITEM
		"Dungeon Notes":
			return ENTRY_KIND_TRAP
	return &""


func _buttons_for_kind(entry_kind: StringName) -> Array[Button]:
	match entry_kind:
		ENTRY_KIND_ENEMY:
			return _bestiary_buttons
		ENTRY_KIND_ITEM:
			return _scribes_buttons
		ENTRY_KIND_TRAP:
			return _dungeon_buttons
	var empty: Array[Button] = []
	return empty


func _apply_responsive_layout() -> void:
	var compact: bool = get_window().size.x < COMPACT_LAYOUT_WIDTH
	if _layout_initialized and compact == _compact_layout:
		return
	_layout_initialized = true
	_compact_layout = compact
	var horizontal_margin: int = COMPACT_MARGIN if compact else WIDE_HORIZONTAL_MARGIN
	var vertical_margin: int = COMPACT_MARGIN if compact else WIDE_VERTICAL_MARGIN
	margin.add_theme_constant_override("margin_left", horizontal_margin)
	margin.add_theme_constant_override("margin_right", horizontal_margin)
	margin.add_theme_constant_override("margin_top", vertical_margin)
	margin.add_theme_constant_override("margin_bottom", vertical_margin)
	header.add_theme_constant_override("separation", 8 if compact else 16)
	title_label.add_theme_font_size_override(
		"font_size", COMPACT_TITLE_SIZE if compact else WIDE_TITLE_SIZE
	)
	back_button.custom_minimum_size.x = COMPACT_BACK_WIDTH if compact else WIDE_BACK_WIDTH
	_apply_split_layout(bestiary_split, bestiary_preview, compact)
	_apply_split_layout(scribes_split, scribes_preview, compact)
	_apply_split_layout(dungeon_split, dungeon_preview, compact)


func _apply_split_layout(
	split: SplitContainer, preview: LibraryVisualPreviewScript, compact: bool
) -> void:
	split.vertical = compact
	split.split_offset = COMPACT_SPLIT_OFFSET if compact else WIDE_SPLIT_OFFSET
	var list_panel: Control = split.get_child(0) as Control
	var detail_column: Control = split.get_child(1) as Control
	if list_panel != null:
		list_panel.custom_minimum_size = COMPACT_LIST_MINIMUM if compact else WIDE_LIST_MINIMUM
	if detail_column != null:
		detail_column.custom_minimum_size = Vector2.ZERO if compact else WIDE_DETAIL_MINIMUM
	preview.custom_minimum_size.y = (COMPACT_PREVIEW_HEIGHT if compact else WIDE_PREVIEW_HEIGHT)
	preview.set_compact_layout(compact)
	split.call_deferred(&"clamp_split_offset")


func _build_bestiary_selection_text(enemy: Resource) -> String:
	var lines: Array[String] = _bestiary_intro_lines()
	lines.append_array(_enemy_entry(enemy))
	return "\n".join(lines)


func _build_scribes_selection_text(item: Resource) -> String:
	var lines: Array[String] = _scribes_reference_lines()
	lines.append("[color=#f1c75b]KNOWN ITEMS — SELECTED[/color]")
	lines.append_array(_item_entry(item, not _reduced_vfx_enabled))
	return "\n".join(lines)


func _build_dungeon_selection_text(trap: Resource) -> String:
	var lines: Array[String] = _dungeon_heading_lines()
	lines.append_array(_dungeon_trap_intro_lines())
	lines.append(_trap_entry(trap))
	lines.append("")
	lines.append_array(_dungeon_map_and_biome_lines())
	lines.append_array(_dungeon_secret_room_lines())
	return "\n".join(lines)


func _build_bestiary_text() -> String:
	var enemies: Array[Resource] = _load_resources_with_paths(ResourcePaths.ENEMY_PATHS)
	enemies.sort_custom(_sort_enemy)
	var lines: Array[String] = _bestiary_intro_lines()
	for enemy: Resource in enemies:
		lines.append_array(_enemy_entry(enemy))
		lines.append("")
	return "\n".join(lines)


func _bestiary_intro_lines() -> Array[String]:
	return [
		"[font_size=24][color=#f1c75b]BESTIARY[/color][/font_size]",
		"",
		"Base monster data from enemy resources; Biomes shows where each roster can appear.",
		"Runtime depth scaling eases upward: slower HP growth,",
		"AC about every 8 floors, attack about every 7, and damage about every 8 after early floors.",
		DamageTypeTextScript.DAMAGE_TYPE_SUMMARY,
		"",
	]


func _build_scribes_text() -> String:
	var items: Array[Resource] = _load_resources_with_paths(ResourcePaths.ITEM_PATHS)
	items.sort_custom(_sort_item)
	var lines: Array[String] = _scribes_reference_lines()
	lines.append("[color=#f1c75b]KNOWN ITEMS[/color]")
	var current_kind: int = -1
	for item: Resource in items:
		if item.kind != current_kind:
			current_kind = item.kind
			lines.append("")
			lines.append(
				(
					"[font_size=20][color=#8fb3ff]%s[/color][/font_size]"
					% item.get_kind_name().to_upper()
				)
			)
		lines.append_array(_item_entry(item))
	return "\n".join(lines)


func _scribes_reference_lines() -> Array[String]:
	var lines: Array[String] = [
		"[font_size=24][color=#f1c75b]SCRIBES[/color][/font_size]",
		"",
		"Item data from item resources. Dungeon drops use floor gates, spawn weight,",
		(
			"and rarity weight. Shops use a boosted effective floor, depth rarity gates, "
			+ "and larger deep-floor stock."
		),
		"",
		"[color=#f1c75b]ITEM TYPES[/color]",
	]
	for item_kind: int in [
		ItemDataScript.ItemKind.CONSUMABLE,
		ItemDataScript.ItemKind.WEAPON,
		ItemDataScript.ItemKind.ARMOR,
		ItemDataScript.ItemKind.ACCESSORY,
	]:
		lines.append(
			(
				"- [color=#8fb3ff]%s[/color]: %s"
				% [_item_kind_name(item_kind), ITEM_TYPE_LORE[item_kind]]
			)
		)
	lines.append("")
	lines.append("[color=#f1c75b]RARITIES[/color]")
	for rarity_index: int in range(ItemDataScript.RARITY_NAMES.size()):
		lines.append(_rarity_entry(rarity_index))
	lines.append("")
	return lines


func _build_dungeon_scrolls_text() -> String:
	var traps: Array[Resource] = _load_resources_with_paths(ResourcePaths.TRAP_PATHS)
	traps.sort_custom(_sort_trap)
	var lines: Array[String] = _dungeon_heading_lines()
	lines.append_array(_dungeon_map_and_biome_lines())
	lines.append_array(_dungeon_trap_intro_lines())
	for trap: Resource in traps:
		lines.append(_trap_entry(trap))
	lines.append("")
	lines.append_array(_dungeon_secret_room_lines())
	return "\n".join(lines)


func _dungeon_heading_lines() -> Array[String]:
	return [
		"[font_size=24][color=#f1c75b]DUNGEON NOTES[/color][/font_size]",
		"",
		"Field guide to symbols, traps, secret rooms, and dungeon markings.",
		"",
	]


func _dungeon_map_and_biome_lines() -> Array[String]:
	return [
		"[color=#8fb3ff]MAP SYMBOLS[/color]",
		"- [color=#f2f2f2]@[/color] You.",
		"- [color=#777777]. ' ` , ~ * : ;[/color] Floor variants and biome decorations. Walkable.",
		(
			"- [color=#777777]# % & $ ^ ~ * ![/color] Stone, growth, ash, water, "
			+ "glass, and void wall variants. Block movement and sight."
		),
		"- [color=#b87532]+[/color] Closed door. Bump generated room doors to open.",
		"- [color=#9b7a45]/[/color] Open door. Walkable.",
		"- [color=#ffb838]G[/color] Boss gate. Seals a boss chamber. Opens when the boss is defeated.",
		"- [color=#ff3d2e]X[/color] Sealed boss gate. Impassable until room guardians are cleared.",
		(
			"- [color=#ffff66]>[/color] Stairs down. Floor 25 offers a final choice: "
			+ "leave victorious or delve forever."
		),
		"- [color=#ffd152]S[/color] Shopkeeper. Step into them to open the shop.",
		(
			"- Chests use item-rarity colors: gray Common, green Uncommon, blue Rare, "
			+ "purple Epic, gold Legendary, pink Mythic, and cyan Ascended."
		),
		"- [color=#8c7259]v/b[/color] Cracked vases and old boxes. Can hold rewards.",
		(
			"- [color=#b894ff]?[/color] Revealed weak wall. Attack, shoot, or blast it "
			+ "twice to open a secret room."
		),
		"- [color=#ff9f6e]^ v ! O ~ *[/color] Revealed traps. Step around them.",
		"- [color=#d8d8d8]![/color] Item on the ground.",
		"",
		"[color=#8fb3ff]BIOMES[/color]",
		(
			"- [color=#d0d0d6]The Tower[/color] (depths 1-5): pale marble halls under "
			+ "the gaze of The Observer. White, gray, and silver stone."
		),
		(
			"- [color=#d98a98]The Rotting Garden[/color] (depths 6-10): overgrown ruins where Seraphine, "
			+ "the Thorn Saint, blooms in decay. Green, gold, and sickly pink."
		),
		(
			"- [color=#e87230]The Cinder Wastes[/color] (depths 11-15): a scorched battlefield ruled by "
			+ "Vorrak, the Ashen Maw. Black, ember orange, and dark red."
		),
		(
			"- [color=#73b2d1]The Sunken Halls[/color] (depths 16-20): drowned chambers of Kaelros, the "
			+ "Drowned King. Deep blue, rusted bronze, and sea green."
		),
		(
			"- [color=#b380ff]The Glass Labyrinth[/color] (depths 21-25): a maze of mirrors haunted by "
			+ "Nyxara, the Mirror Witch. Purple, silver, and black."
		),
		(
			"- [color=#66fff0]Endless Deeps[/color] (depth 26+): infinite post-game descent "
			+ "drawing from all enemies plus rare Endless-only horrors."
		),
		"- Each biome ends in a sealed boss room on floors 5/10/15/20/25.",
		"",
	]


func _dungeon_trap_intro_lines() -> Array[String]:
	return [
		"[color=#8fb3ff]TRAPS[/color]",
		"Traps are hidden until detected. Moving near one rolls passive detection;",
		"Space searches visible traps within 3 tiles. WIS adds to detection.",
	]


func _dungeon_secret_room_lines() -> Array[String]:
	return [
		"[color=#8fb3ff]SECRET ROOMS[/color]",
		"- Secret rooms start sealed behind normal-looking wall tiles.",
		"- Search/listen can reveal nearby weak walls as '?'.",
		"- Breaking the weak wall turns it into floor and reveals the hidden passage.",
		"- Secret rooms have a high chance to contain a chest and clutter.",
	]


func _build_classes_text() -> String:
	var lines: Array[String] = [
		"[font_size=24][color=#f1c75b]CLASSES[/color][/font_size]",
		"",
		"Each class modifies your base damage, with level-aware scaling:",
		(
			"- [color=#f1c75b]Fighter[/color]: melee 150% (160% Lv10, 170% Lv15, 180% Lv20)."
			+ " Starts with a training sword."
		),
		(
			"- [color=#f1c75b]Ranger[/color]: melee 50% (60% Lv15, 70% Lv20),"
			+ " ranged 150% (160% Lv10, 170% Lv15, 175% Lv20)."
			+ " Starts with a hunting bow."
		),
		(
			"- [color=#f1c75b]Wizard[/color]: magic 200% (220% Lv15, 240% Lv20),"
			+ " melee/ranged 60% (70% Lv20)."
			+ " Starts with an apprentice staff (WIS-based ranged magic weapon)."
		),
		"",
		"[color=#8fb3ff]STAFFS[/color]",
		"- Staffs are wizard-only ranged weapons that use WIS for accuracy and damage.",
		"- They deal magic damage, benefiting from the Wizard's magic damage bonus.",
		"- Staffs have modest raw damage dice but scale strongly with Wizard's",
		"  passive magic multiplier, making them the Wizard's primary weapon.",
		"- A staff uses ranged weapon controls (F to fire) but targets the",
		"  magic resistance/weakness of enemies rather than ranged resistance.",
		"",
		"[color=#8fb3ff]CLASS GEAR[/color]",
		"- Some weapons, armor, and accessories are restricted to a specific class.",
		"- Class-restricted gear requires the matching class to equip, but can be",
		"  freely looted, carried, and sold by any class.",
		"- Class gear may grant a bonus to a specific damage type for matching classes.",
		"",
		"[color=#8fb3ff]CLASS ABILITIES[/color]",
		"",
		"Press [color=#f1c75b]Q[/color] to open the class ability menu while exploring a floor.",
		"Each class has three active abilities unlocked at levels 1, 6, and 12.",
		"Passive effects upgrade at levels 5, 10, 15, and 20.",
		"The Q menu shows all abilities; locked abilities appear grayed out",
		"with their unlock level and a reason. Core abilities gain a second",
		"charge at level 20.",
		"",
		"[color=#f1c75b]Fighter[/color]",
		"",
		"[color=#8fb3ff]Cleave[/color] (Lv1): Prime your next melee attack. When it lands,",
		"it splashes adjacent enemies for 50/60/75/100% at Lv1/10/15/20.",
		"1 charge per floor (2 at Lv20).",
		"",
		"[color=#8fb3ff]Second Wind[/color] (Lv6): Heal 20/25/30% at Lv6/15/20 and",
		"gain armor shield +2/+3/+4 for 3/4/5 turns. Consumes your action.",
		"1 charge per floor.",
		"",
		"[color=#8fb3ff]Whirlwind[/color] (Lv12): Melee attack all adjacent enemies once.",
		"Action consumed only if at least one enemy is hit.",
		"1 charge per floor.",
		"",
		"Passive — Extra strike: 12/18/24/30% chance at Lv5/10/15/20",
		"to make an additional melee strike on hit. The extra strike cannot",
		"trigger another extra strike (no recursion).",
		"",
		"[color=#f1c75b]Ranger[/color]",
		"",
		"[color=#8fb3ff]Hunter's Focus[/color] (Lv1): Accuracy +4/+5/+6 at Lv1/10/20",
		"and raw ranged multiplier 150/175/200% at Lv1/15/20.",
		"Consumed on hit or miss. 1 charge per floor.",
		"",
		"[color=#8fb3ff]Volley[/color] (Lv6): Requires a ranged weapon. Attack nearest",
		"visible enemies in weapon range. 2/3/4 targets at Lv6/15/20,",
		"each for 80/90/100% damage. Action consumed only with targets.",
		"1 charge per floor.",
		"",
		"[color=#8fb3ff]Quickstep[/color] (Lv12): Skips the next enemy phase,",
		"or the next 2 enemy phases at level 20. Consumes your action. 1 charge per floor.",
		"",
		"Passive — Ranged damage: base 150% scaling to",
		"160/170/180% at Lv10/15/20.",
		"",
		"[color=#f1c75b]Wizard[/color]",
		"",
		"[color=#8fb3ff]Arcane Spark[/color] (Lv1): Nearest visible enemy within range",
		"6/7/8 at Lv1/10/20 takes raw 1d4+max(0,WIS)+level/5 magic damage.",
		"Action consumed only with a target. 1 charge per floor.",
		"",
		"[color=#8fb3ff]Frost Nova[/color] (Lv6): Visible enemies within radius 2/3 at",
		"Lv6/15 take raw 1d4+max(0,WIS)+level/4 magic damage and sleep",
		"1/2 turns at Lv6/20. Action consumed only if at least one enemy",
		"is affected. 1 charge per floor.",
		"",
		"[color=#8fb3ff]Chain Lightning[/color] (Lv12): Nearest visible enemies in range",
		"7/8 at Lv12/20. 3/4 targets at Lv12/20, each for raw",
		"1d6+max(0,WIS)+level/2 magic damage. Action consumed only if",
		"at least one target exists. 1 charge per floor.",
		"",
		"Passive — Magic damage: base 200% scaling to 220/240% at Lv15/20.",
		"",
		"[color=#8fb3ff]DESIGN NOTE[/color]",
		"At level 20, each class has three active abilities and four passive",
		"upgrade tiers. The Q panel shows all abilities; locked ones appear",
		"grayed with their unlock level and disabled reason.",
		"",
	]
	return "\n".join(lines)


func _build_info_text() -> String:
	var lines: Array[String] = [
		"[font_size=24][color=#f1c75b]INFO[/color][/font_size]",
		"",
		GameManager.get_version_label() + ". Current dungeon rules.",
		"",
		"[color=#8fb3ff]LEVELS[/color]",
		"- XP to next level = current level × 100.",
		"- Levels 2-20 grant +1 ability score after the level up menu.",
		"- Ability scores cannot exceed 20.",
		"- After level 20, levels display as 20+1, 20+2, and so on with shifting colors.",
		"- Level 21+ gives normal HP growth only; proficiency and ability score gains stop at level 20.",
		"- HP gained each level = max(1, 5 + CON modifier).",
		"",
		"[color=#8fb3ff]ABILITY SCORES[/color]",
		"- STR: melee accuracy and melee damage.",
		"- DEX: armor class and ranged weapon accuracy.",
		"- CON: starting HP and HP gained per level. Raising CON can increase max HP.",
		(
			"- INT: direct healing consumables restore base HP + INT modifier + 10% of "
			+ "base healing per positive INT modifier."
		),
		"- INT: sight radius is 8, increases to 9 at INT 15, and 10 at INT 20.",
		(
			"- WIS: magic scroll damage adds double positive WIS modifier before "
			+ "magic resistance/vulnerability."
		),
		"- Damaging scrolls also gain +1 damage per 6 floors after their minimum floor.",
		"- CHA: shop buy price multiplier = clamp(1 - 0.05 × CHA modifier, 0.5, 1.5).",
		"- CHA: shop sell value multiplier = clamp(0.35 + 0.02 × CHA modifier, 0.25, 0.50).",
		"",
		"[color=#8fb3ff]COMBAT AND CONSUMABLES[/color]",
		(
			"- Classes modify player damage: Fighter +50% melee; Ranger -50% melee "
			+ "and +50% ranged; Wizard +100% magic and -40% melee/ranged."
		),
		"- Staffs are wizard-only ranged weapons: WIS accuracy, magic damage type.",
		"- Staffs use ranged weapon controls (F) but deal magic damage.",
		"- Melee accuracy and melee damage use STR.",
		"- Ranged weapon accuracy and damage use DEX.",
		(
			"- Fire, lightning, and other elemental spell flavor resolves through "
			+ "magic damage affinity."
		),
		(
			"- Scroll fire/bolt style attacks can miss; they roll with WIS and deal "
			+ "WIS/depth-scaled magic damage."
		),
		"- Magic Missile does not roll to hit and hits up to three visible enemies in range.",
		(
			"- Area scrolls target a visible in-range cell, preview radius, and damage "
			+ "every visible enemy in the radius."
		),
		"- Targeted consumables require a visible in-range target or cell; invalid confirmation does not spend the scroll.",
		"- Potions are not consumed at full HP.",
		"[color=#8fb3ff]SEARCHING[/color]",
		"- Space spends a turn searching for traps and listening for weak walls.",
		"- WIS improves trap detection and secret wall discovery.",
		"- Stun blocks movement and attacks for 3 actions; H consumables still work.",
		"- Ambush traps spawn three basic enemies a few tiles away.",
		"",
		"[color=#8fb3ff]VERSION HISTORY[/color]",
	]
	lines.append_array(VERSION_HISTORY)
	return "\n".join(lines)


func _build_archive_text() -> String:
	var entries: Array = GameManager.character_history
	var lines: Array[String] = [
		"[font_size=24][color=#f1c75b]ARCHIVE[/color][/font_size]",
		"",
		"Real completed runs only. Debug/test loadouts are ignored.",
		"Hard unlocks after an archived non-debug Normal victory.",
		"Nightmare unlocks after an archived non-debug Hard victory.",
		"Scores, shards, loadouts, and combat totals persist from V32 onward.",
	]
	if entries.is_empty():
		lines.append("[color=#92906f]No archived runs yet.[/color]")
		return "\n".join(lines)
	for index: int in range(entries.size()):
		lines.append(_archive_entry(entries[index], index + 1))
	return "\n".join(lines)


func _archive_entry(entry: Dictionary, archive_index: int) -> String:
	var delver_name: String = _clean_archive_name(str(entry.get("name", "Unknown")))
	var floor_number: int = int(entry.get("floor", 1))
	var level_value: int = int(entry.get("level", 1))
	var result: String = "Victory" if bool(entry.get("victory", false)) else "Fell"
	var result_color: String = "#7bd88f" if result == "Victory" else "#8b8fa3"
	var version_text: String = _archive_version(str(entry.get("version", "")))
	var class_id: StringName = StringName(
		str(entry.get("class", GameManager.DEFAULT_CHARACTER_CLASS))
	)
	var class_label: String = GameManager.get_character_class_label(class_id)
	var difficulty: StringName = StringName(
		str(entry.get("difficulty", GameManager.DEFAULT_DIFFICULTY))
	)
	var difficulty_label: String = GameManager.get_difficulty_label(difficulty)
	var difficulty_color: String
	match difficulty:
		GameManager.DIFFICULTY_HARD:
			difficulty_color = DIFFICULTY_HARD_COLOR
		GameManager.DIFFICULTY_NIGHTMARE:
			difficulty_color = DIFFICULTY_NIGHTMARE_COLOR
		_:
			difficulty_color = DIFFICULTY_NORMAL_COLOR
	var entry_text: String = (
		"[color=#47426b]%02d[/color]  [color=#fffbf0]%s[/color]  "
		+ "[color=#8fb3ff]%s[/color]  [color=%s]%s[/color]  "
		+ "[color=#7db8ff]F%d[/color]  [color=#d8d8d8]L%s[/color]  "
		+ "[color=%s]%s[/color]  [color=#f1c75b]%s[/color]"
	)
	var header: String = (
		entry_text
		% [
			archive_index,
			delver_name,
			class_label,
			difficulty_color,
			difficulty_label,
			floor_number,
			_format_level_bbcode(level_value),
			result_color,
			result,
			version_text,
		]
	)
	if not entry.has("score"):
		return header
	var score: int = int(entry.get("score", 0))
	var high_score: int = GameManager.get_high_score(difficulty)
	var record_label: String = (
		"  [color=#ffe077][b]HIGH SCORE[/b][/color]" if score > 0 and score == high_score else ""
	)
	var telemetry: String = (
		(
			"\n      [color=#ffe077]Score %s[/color]  "
			+ "[color=#a8a6b8]Turns %d  //  Kills %d  //  Shards %d/%d[/color]%s"
		)
		% [
			_format_archive_number(score),
			int(entry.get("turns", 0)),
			int(entry.get("enemy_kills", 0)),
			int(entry.get("shards_collected", 0)),
			GameManager.TOTAL_PORTAL_SHARDS,
			record_label,
		]
	)
	var boss_kills: Array = entry.get("boss_kills", [])
	if not boss_kills.is_empty():
		var bound_names: PackedStringArray = []
		for boss_entry: Variant in boss_kills:
			var boss_id: StringName
			var boss_name: String
			if boss_entry is Dictionary:
				boss_id = StringName(str(boss_entry.get("id", "")))
				boss_name = str(boss_entry.get("name", ""))
			else:
				boss_id = StringName(str(boss_entry))
			if boss_name.is_empty():
				boss_name = str(SHARDBEARER_NAMES.get(boss_id, str(boss_id).capitalize()))
			bound_names.append(boss_name)
		telemetry += ("\n      [color=#c77dff]Bound shards:[/color] %s" % ", ".join(bound_names))
	return header + telemetry


func _format_archive_number(value: int) -> String:
	var digits: String = str(max(0, value))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = ",%s%s" % [digits.right(3), grouped]
		digits = digits.left(digits.length() - 3)
	return digits + grouped


func _archive_version(version_value: String) -> String:
	if version_value.strip_edges().is_empty():
		return "version not recorded"
	return "v%s" % version_value.strip_edges()


func _format_level_bbcode(level_value: int) -> String:
	if level_value <= 20:
		return "%d" % level_value
	var colors: Array[String] = [
		"#d899ff",
		"#c77dff",
		"#9d7dff",
		"#7db8ff",
		"#66fff0",
		"#7bd88f",
		"#ffb84d",
		"#ff5fd7",
	]
	var prestige_level: int = level_value - 20
	return (
		"20[color=%s]+%d[/color]"
		% [
			colors[(prestige_level - 1) % colors.size()],
			prestige_level,
		]
	)


func _clean_archive_name(raw_name: String) -> String:
	var clean_name: String = raw_name.strip_edges().replace("[", "(").replace("]", ")")
	if clean_name.is_empty():
		clean_name = "Nameless"
	if clean_name.length() > 18:
		clean_name = clean_name.substr(0, 15) + "..."
	return clean_name


func _enemy_entry(enemy: Resource) -> Array[String]:
	var color: String = enemy.color.to_html(false)
	var lines: Array[String] = [
		(
			"[font_size=20][color=#%s]%s[/color][/font_size]  [color=#777777]'%s'[/color]"
			% [color, enemy.display_name, enemy.glyph]
		),
		(
			"Floors: %s    Spawn Weight: %d    XP: %d"
			% [_floor_range(enemy.min_floor, enemy.max_floor), enemy.spawn_weight, enemy.xp_reward]
		),
		(
			"Biomes: %s"
			% ", ".join(BiomeCatalogScript.biome_names_for_enemy_path(enemy.resource_path))
		),
		"Defense: AC %d, HP %d" % [enemy.armor_class, enemy.max_hp],
		(
			"Offense: attack %+d, damage 1d%d%+d"
			% [enemy.attack_bonus, enemy.damage_sides, enemy.damage_bonus]
		),
		DamageTypeTextScript.affinity_line(
			enemy.melee_damage_percent, enemy.ranged_damage_percent, enemy.magic_damage_percent
		),
		"Note: %s" % ENEMY_NOTES.get(enemy.display_name, _enemy_stat_note(enemy)),
	]
	if enemy.is_boss:
		lines.append("")
		lines.append("[color=#c77dff][b]SHARDBEARER // %s[/b][/color]" % enemy.boss_room_title)
		lines.append("[color=#d8d1df]%s[/color]" % enemy.boss_lore)
		lines.append("[color=#8dd6e8]Shard memory:[/color] %s" % enemy.boss_shard_lore)
		lines.append("[color=#ffe077]Tactic:[/color] %s" % enemy.boss_strategy_hint)
	if enemy.display_name == "Lich":
		lines.append_array(_lich_summon_entry(enemy))
	return lines


func _lich_summon_entry(lich: Resource) -> Array[String]:
	var summon_data: Resource = load(lich.summon_enemy_path)
	if summon_data == null:
		return ["Summon: missing resource %s" % lich.summon_enemy_path]
	var brittle_hp: int = max(4, int(ceil(summon_data.max_hp * 0.6)))
	var brittle_attack: int = max(1, summon_data.attack_bonus - 1)
	var brittle_damage_bonus: int = max(0, summon_data.damage_bonus - 1)
	return [
		(
			"  - [color=#%s]Brittle Skeleton[/color]  [color=#777777]'%s'[/color]"
			% [summon_data.color.to_html(false), summon_data.glyph]
		),
		(
			"  Summon: %d every %d Lich actions while visible    Max Active: %d    XP: 0"
			% [lich.summon_count, lich.summon_interval, lich.summon_max_active]
		),
		"  Defense: AC %d, HP %d" % [summon_data.armor_class, brittle_hp],
		(
			"  Offense: melee attack %+d, damage 1d%d%+d"
			% [brittle_attack, summon_data.damage_sides, brittle_damage_bonus]
		),
		"  Note: Summoned-only melee skeleton. No ranged attack, no kiting range, and no XP reward.",
	]


func _item_entry(item: Resource, animated_name: bool = true) -> Array[String]:
	var lines: Array[String] = [
		(
			"[font_size=18]%s[/font_size]  [color=#777788]%s %s[/color]"
			% [
				item.get_display_name_bbcode(animated_name),
				item.get_rarity_name(),
				item.get_kind_name(),
			]
		),
		(
			(
				"  [color=#8fb3ff]Floor[/color] %s   [color=#8fb3ff]Price[/color] %dg   "
				+ "[color=#8fb3ff]Weight[/color] %d"
			)
			% [_floor_range(item.min_floor, item.max_floor), item.get_price(), item.spawn_weight]
		),
		"  [color=#9999aa]Lore[/color]  %s" % item.description,
		"  [color=#9999aa]Stats[/color] %s" % _item_stats_line(item),
	]
	var class_notes: Array[String] = _scribe_class_notes(item)
	if not class_notes.is_empty():
		for note: String in class_notes:
			lines.append("  [color=#9999aa]Class[/color] %s" % note)
	lines.append("")
	return lines


func _item_stats_line(item: Resource) -> String:
	var stats: Array[String] = []
	if item.use_effect != ItemDataScript.ItemUse.NONE:
		stats.append(_item_use_name(item.use_effect))
	if item.range > 1:
		stats.append("range %d" % item.range)
	if item.healing_amount > 0:
		var heal_tag: String = " +INT" if item.use_effect == ItemDataScript.ItemUse.HEAL else ""
		stats.append("heals %d HP%s" % [item.healing_amount, heal_tag])
	if item.damage_sides > 0:
		var damage_tag: String = ""
		if item.kind == ItemDataScript.ItemKind.CONSUMABLE or item.is_staff:
			damage_tag = " +WIS"
		stats.append(
			(
				"damage %dd%d%+d%s"
				% [item.damage_dice, item.damage_sides, item.damage_bonus, damage_tag]
			)
		)
	if item.attack_bonus != 0:
		stats.append("attack %+d" % item.attack_bonus)
	elif item.damage_bonus != 0:
		stats.append("damage %+d" % item.damage_bonus)
	if item.armor_bonus != 0:
		stats.append("AC %+d" % item.armor_bonus)
	if item.effect_duration > 0:
		stats.append("duration %d" % item.effect_duration)
	if item.target_radius > 0:
		stats.append("radius %d" % item.target_radius)
	if item.special_effect != ItemDataScript.ItemSpecial.NONE:
		stats.append(_item_special_name(item))
	if stats.is_empty():
		stats.append("no direct combat stat")
	return ", ".join(stats)


func _scribe_class_notes(item: Resource) -> Array[String]:
	var notes: Array[String] = []
	if item.is_staff:
		notes.append("staff, WIS-based magic ranged")
	if item.kind == ItemDataScript.ItemKind.WEAPON and item.weapon_damage_type != &"":
		notes.append("damage type: %s" % item.weapon_damage_type)
	if item.required_class != &"":
		notes.append("requires: %s" % GameManager.get_character_class_label(item.required_class))
	if item.class_damage_percent_bonus != 0:
		var dmg_type: String = (
			String(item.class_damage_type) if item.class_damage_type != &"" else "all"
		)
		notes.append("class bonus: %+d%% %s" % [item.class_damage_percent_bonus, dmg_type])
	if item.set_id != &"":
		var set_name: String = (
			item.set_display_name if not item.set_display_name.is_empty() else String(item.set_id)
		)
		notes.append("set: %s (%d pieces)" % [set_name, max(2, item.set_required_count)])
		if item.set_damage_resist_percent > 0:
			notes.append("set bonus: -%d%% incoming damage" % item.set_damage_resist_percent)
		if item.set_proc_chance_percent > 0 and item.set_proc_heal_percent > 0:
			notes.append(
				(
					"set bonus: %d%% after-damage chance to heal %d%% max HP"
					% [item.set_proc_chance_percent, item.set_proc_heal_percent]
				)
			)
	return notes


func _item_use_name(item_use: int) -> String:
	var name: String = "none"
	match item_use:
		ItemDataScript.ItemUse.HEAL:
			name = "heal"
		ItemDataScript.ItemUse.RANGED_ATTACK:
			name = "ranged attack"
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			name = "magic missile"
		ItemDataScript.ItemUse.SHIELD:
			name = "shield"
		ItemDataScript.ItemUse.SLEEP:
			name = "sleep"
		ItemDataScript.ItemUse.HASTE:
			name = "haste"
		ItemDataScript.ItemUse.AREA_DAMAGE:
			name = "area damage"
		ItemDataScript.ItemUse.REGEN:
			name = "regen"
	return name


func _item_special_name(item: Resource) -> String:
	match item.special_effect:
		ItemDataScript.ItemSpecial.KILL_REGEN_PERCENT:
			return "kill regen %d%% max HP" % item.special_amount
		ItemDataScript.ItemSpecial.CURRENT_HP_DAMAGE_PERCENT:
			return "current HP hit +%d%%" % item.special_amount
		ItemDataScript.ItemSpecial.DASH_CHARGE:
			return "dash every %d actions" % item.special_cooldown
	return "special"


func _trap_entry(trap: Resource) -> String:
	return (
		"- [color=#%s]%s[/color] [color=#777788]'%s'[/color]: DC %d. %s %s"
		% [
			trap.color.to_html(false),
			trap.display_name,
			trap.glyph,
			trap.detect_dc,
			trap.description,
			_trap_effect_line(trap),
		]
	)


func _trap_effect_line(trap: Resource) -> String:
	var effect_text: String = "Unknown trap effect."
	match trap.effect:
		TrapDataScript.TrapEffect.DAMAGE:
			effect_text = "Deals %d-%d damage." % [trap.min_damage, trap.max_damage]
		TrapDataScript.TrapEffect.POTSON:
			effect_text = "Deals %d-%d poison dart damage." % [trap.min_damage, trap.max_damage]
		TrapDataScript.TrapEffect.TELEPORT:
			effect_text = "Teleports you to another walkable cell."
		TrapDataScript.TrapEffect.ALARM:
			effect_text = "Alerts nearby monsters."
		TrapDataScript.TrapEffect.STUN:
			effect_text = "Stuns you for 3 actions; H consumables remain usable."
		TrapDataScript.TrapEffect.AMBUSH:
			effect_text = "Summons 3 basic enemies a few tiles away."
	return effect_text


func _rarity_entry(rarity_index: int) -> String:
	var name: String = ItemDataScript.RARITY_NAMES[rarity_index]
	var color: String = ItemDataScript.RARITY_COLORS[rarity_index]
	var note: String = "weight 1"
	match rarity_index:
		ItemDataScript.ItemRarity.COMMON:
			note = "weight max(8, 60 - 5 × depth)"
		ItemDataScript.ItemRarity.UNCOMMON:
			note = "weight 22 + 3 × depth"
		ItemDataScript.ItemRarity.RARE:
			note = "weight max(0, 5 × depth - 6)"
		ItemDataScript.ItemRarity.EPIC:
			note = "weight max(0, 4 × depth - 16)"
		ItemDataScript.ItemRarity.LEGENDARY:
			note = "weight max(0, 3 × depth - 18)"
		ItemDataScript.ItemRarity.MYTHIC:
			note = "weight max(0, 2 × depth - 14)"
		ItemDataScript.ItemRarity.ASCENDED:
			note = "weight max(0, 2 × depth - 22)"
	return "- %s: %s" % [ItemDataScript.format_rarity_text(name, rarity_index), note]


func _load_resources_with_paths(paths: Array[String]) -> Array[Resource]:
	var resources: Array[Resource] = []
	for path: String in paths:
		var loaded: Resource = load(path)
		if loaded != null:
			resources.append(loaded)
	return resources


func _sort_enemy(left: Resource, right: Resource) -> bool:
	if left.min_floor == right.min_floor:
		return left.display_name < right.display_name
	return left.min_floor < right.min_floor


func _sort_item(left: Resource, right: Resource) -> bool:
	if left.kind != right.kind:
		return left.kind < right.kind
	if left.rarity != right.rarity:
		return left.rarity < right.rarity
	if left.min_floor != right.min_floor:
		return left.min_floor < right.min_floor
	return left.display_name < right.display_name


func _sort_trap(left: Resource, right: Resource) -> bool:
	if left.detect_dc == right.detect_dc:
		return left.display_name < right.display_name
	return left.detect_dc < right.detect_dc


func _enemy_stat_note(enemy: Resource) -> String:
	var tags: Array[String] = []
	if enemy.armor_class >= 14:
		tags.append("high AC")
	if enemy.max_hp >= 18:
		tags.append("large HP pool")
	if enemy.attack_bonus >= 5:
		tags.append("accurate")
	if enemy.damage_sides + enemy.damage_bonus >= 11:
		tags.append("high damage")
	if tags.is_empty():
		return "standard melee enemy"
	return ", ".join(tags)


func _floor_range(min_floor: int, max_floor: int) -> String:
	if max_floor > 0:
		return "floors %d-%d" % [min_floor, max_floor]
	return "floor %d+" % min_floor


func _item_kind_name(item_kind: int) -> String:
	var item: Resource = ItemDataScript.new()
	item.kind = item_kind
	return item.get_kind_name()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
