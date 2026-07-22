## Skippable, player-paced prologue between character creation and the dungeon.
class_name Prologue
extends Control

# === Constants ===
const GAME_SCENE_PATH: String = "res://scenes/game.tscn"
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const PAGE_FADE_SECONDS: float = 0.24
const COMPACT_LAYOUT_WIDTH: float = 700.0
const PAGE_DATA: Array[Dictionary] = [
	{
		"kicker": "LONG AGO // THE FIRST BREACH",
		"title": "THE DUNGEON OPENED ITS EYE",
		"body":
		(
			"Beneath a nameless kingdom, five keepers chained a living gate. "
			+ "Their seals held the dark below—until the dungeon learned to dream."
		),
		"sigil": "·  ◇  ◇  ◇  ◇  ◇  ·",
	},
	{
		"kicker": "THE FIVE // SHARDBEARERS",
		"title": "FIVE WARDENS. FIVE SHARDS.",
		"body":
		(
			"The Observer watches. The Thorn Saint roots. The Ashen Maw burns. "
			+ "The Drowned King drags. The Mirror Witch waits behind the final reflection."
		),
		"sigil": "O  ·  S  ·  V  ·  K  ·  N",
	},
	{
		"kicker": "YOUR OATH // THE DESCENT",
		"title": "BREAK EVERY SEAL",
		"body":
		(
			"Take the shard each warden guards. Carry all five to the last stair, "
			+ "and the breach can be sealed. Gold may arm you. Experience may harden you. "
			+ "Only the shards can open the way home."
		),
		"sigil": "[ 0 / 5 SHARDS BOUND ]",
	},
	{
		"kicker": "THE LAST STAIR // YOUR CHOICE",
		"title": "LEAVE—OR DELVE FOREVER",
		"body":
		(
			"Victory waits beyond the fifth shard. So does another path: carry their light "
			+ "into the Endless Deeps, where there is no final floor and no promise of return."
		),
		"sigil": "THE SHARDS CALL, SHARDBEARER",
	},
]

# === Private Variables ===
var _page_index: int = 0
var _transitioning: bool = false
var _entering_dungeon: bool = false
var _reduced_vfx: bool = true
var _page_tween: Tween

# === Onready ===
@onready var background: AsciiBackdrop = $Background
@onready var panel: PanelContainer = $SafeMargin/Center/Panel
@onready var panel_margin: MarginContainer = $SafeMargin/Center/Panel/PanelMargin
@onready var content: VBoxContainer = $SafeMargin/Center/Panel/PanelMargin/VBox/Content
@onready var kicker_label: Label = $SafeMargin/Center/Panel/PanelMargin/VBox/TopRow/Kicker
@onready var progress_label: Label = $SafeMargin/Center/Panel/PanelMargin/VBox/TopRow/Progress
@onready var sigil_label: Label = $SafeMargin/Center/Panel/PanelMargin/VBox/Content/Sigil
@onready var title_label: Label = $SafeMargin/Center/Panel/PanelMargin/VBox/Content/Title
@onready var body_label: Label = $SafeMargin/Center/Panel/PanelMargin/VBox/Content/Body
@onready var hint_label: Label = $SafeMargin/Center/Panel/PanelMargin/VBox/Hint
@onready var action_grid: GridContainer = $SafeMargin/Center/Panel/PanelMargin/VBox/Actions
@onready
var continue_button: Button = $SafeMargin/Center/Panel/PanelMargin/VBox/Actions/ContinueButton
@onready var skip_button: Button = $SafeMargin/Center/Panel/PanelMargin/VBox/Actions/SkipButton


# === Lifecycle Methods ===
func _ready() -> void:
	if (
		GameManager.pending_character_name.is_empty()
		or GameManager.pending_ability_scores.is_empty()
	):
		get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
		return
	_reduced_vfx = SensoryFeedback.is_reduced_vfx_preferred()
	background.motion_enabled = not _reduced_vfx
	continue_button.pressed.connect(_advance_page)
	skip_button.pressed.connect(_enter_dungeon)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_show_page(0, true)
	continue_button.call_deferred(&"grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_enter_dungeon()
		get_viewport().set_input_as_handled()


# === Private Methods ===
func _advance_page() -> void:
	if _transitioning or _entering_dungeon:
		return
	if _page_index >= PAGE_DATA.size() - 1:
		_enter_dungeon()
		return
	_show_page(_page_index + 1)


func _show_page(page_index: int, immediate: bool = false) -> void:
	_page_index = clampi(page_index, 0, PAGE_DATA.size() - 1)
	var page: Dictionary = PAGE_DATA[_page_index]
	kicker_label.text = str(page.get("kicker", "THE DESCENT"))
	progress_label.text = "%02d / %02d" % [_page_index + 1, PAGE_DATA.size()]
	sigil_label.text = str(page.get("sigil", "◇"))
	title_label.text = str(page.get("title", "SHARDBEARER"))
	body_label.text = str(page.get("body", ""))
	continue_button.text = "BEGIN DESCENT" if _page_index == PAGE_DATA.size() - 1 else "CONTINUE"
	hint_label.text = "ENTER advances  //  ESC skips"
	if is_instance_valid(_page_tween):
		_page_tween.kill()
	if immediate or _reduced_vfx:
		content.modulate = Color.WHITE
		content.position.y = 0.0
		_transitioning = false
		return
	_transitioning = true
	content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	content.position.y = 8.0
	_page_tween = create_tween().set_parallel(true)
	_page_tween.tween_property(content, "modulate", Color.WHITE, PAGE_FADE_SECONDS)
	(
		_page_tween
		. tween_property(content, "position:y", 0.0, PAGE_FADE_SECONDS)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_CUBIC)
	)
	_page_tween.finished.connect(_on_page_reveal_finished)


func _on_page_reveal_finished() -> void:
	_transitioning = false


func _enter_dungeon() -> void:
	if _entering_dungeon:
		return
	_entering_dungeon = true
	continue_button.disabled = true
	skip_button.disabled = true
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _apply_responsive_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = viewport_size.x < COMPACT_LAYOUT_WIDTH
	var horizontal_margin: int = 18 if compact else 42
	var vertical_margin: int = 20 if compact else 34
	panel_margin.add_theme_constant_override(&"margin_left", horizontal_margin)
	panel_margin.add_theme_constant_override(&"margin_right", horizontal_margin)
	panel_margin.add_theme_constant_override(&"margin_top", vertical_margin)
	panel_margin.add_theme_constant_override(&"margin_bottom", vertical_margin)
	panel.custom_minimum_size.x = min(820.0, max(300.0, viewport_size.x - 32.0))
	action_grid.columns = 1 if compact else 2
	title_label.add_theme_font_size_override(&"font_size", 23 if compact else 30)
	body_label.add_theme_font_size_override(&"font_size", 15 if compact else 18)
