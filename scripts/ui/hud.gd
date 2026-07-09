## Heads-up display: name, HP, floor depth, ability stats, gold, and help text.
class_name HUD
extends Control

# === Constants ===
const HP_SAFE_COLOR: Color = Color(0.92, 0.86, 0.74)
const HP_WOUNDED_COLOR: Color = Color(1.0, 0.72, 0.28)
const HP_DANGER_COLOR: Color = Color(1.0, 0.34, 0.47)
const HP_HEAL_FLASH_COLOR: Color = Color(0.48, 0.95, 0.56)
const GOLD_FLASH_COLOR: Color = Color(1.0, 0.82, 0.18)
const XP_FLASH_COLOR: Color = Color(0.55, 0.86, 1.0)
const LABEL_PULSE_SCALE: Vector2 = Vector2(1.08, 1.08)
const LABEL_PULSE_SECONDS: float = 0.24
const BOSS_HP_BAR_CELLS: int = 12
const BOSS_BANNER_HP_BAR_CELLS: int = 28

# === Private Variables ===
var _biome_name: String = "The Tower"
var _current_floor: int = 1
var _has_shopkeeper: bool = false
var _last_hp: int = -1
var _last_gold: int = -1
var _last_xp: int = -1
var _visible_enemy_intents: Dictionary = {}
var _boss_display_name: String = ""
var _boss_floor_active: bool = false
var _boss_locked: bool = false
var _boss_defeated: bool = false
var _last_boss_hp: int = -1
var _hp_tween: Tween
var _boss_hp_tween: Tween
var _gold_tween: Tween
var _xp_tween: Tween

# === Onready ===
@onready var name_label: Label = $Margin/VBox/NameLabel
@onready var hp_label: Label = $Margin/VBox/HpLabel
@onready var floor_label: Label = $Margin/VBox/FloorLabel
@onready var sep_boss_label: Label = $Margin/VBox/SepBoss
@onready var boss_name_label: Label = $Margin/VBox/BossNameLabel
@onready var boss_hp_label: Label = $Margin/VBox/BossHpLabel
@onready var boss_banner: PanelContainer = $BossBanner
@onready var boss_banner_title_label: Label = $BossBanner/Margin/VBox/TitleLabel
@onready var boss_banner_hp_label: Label = $BossBanner/Margin/VBox/HpLabel
@onready var stats_label: RichTextLabel = $Margin/VBox/StatsLabel
@onready var gold_label: Label = $Margin/VBox/GoldLabel
@onready var help_label: Label = $Margin/VBox/HelpLabel


# === Lifecycle Methods ===
func _ready() -> void:
	GameManager.player_damaged.connect(_update_hp)
	GameManager.xp_changed.connect(_update_xp)
	GameManager.floor_changed.connect(_update_floor)
	stats_label.bbcode_enabled = true
	stats_label.fit_content = true
	stats_label.scroll_active = false
	hide_boss_health()
	_update_goal_text()


# === Public Methods ===
func bind_player(player: Node) -> void:
	name_label.text = player.display_name
	_update_floor(GameManager.current_floor)
	_update_hp(player.stats_component.current_hp, player.stats_component.max_hp)
	_update_xp(player.stats_component.xp, player.stats_component.xp_for_next_level())
	_update_gold(player.stats_component.gold)


func set_biome_theme(theme: Dictionary) -> void:
	_biome_name = str(theme.get("name", "The Tower"))
	var label_color: Variant = theme.get("label_color", Color(0.6, 0.843, 0.898))
	if label_color is Color:
		floor_label.add_theme_color_override("font_color", label_color)
	_update_floor(GameManager.current_floor)


func set_floor_context(floor_number: int, has_shopkeeper: bool) -> void:
	_current_floor = floor_number
	_has_shopkeeper = has_shopkeeper
	_update_goal_text()


func set_visible_enemy_intents(enemy_intents: Dictionary) -> void:
	_visible_enemy_intents = enemy_intents
	_update_goal_text()


func set_boss_goal_state(display_name: String, active: bool, locked: bool, defeated: bool) -> void:
	_boss_display_name = display_name
	_boss_floor_active = active
	_boss_locked = locked
	_boss_defeated = defeated
	_update_goal_text()


func show_boss_health(
	display_name: String, current_hp: int, max_hp: int, accent_color: Color = Color(1.0, 0.72, 0.28)
) -> void:
	_boss_display_name = display_name
	_boss_floor_active = true
	sep_boss_label.visible = false
	boss_name_label.visible = false
	boss_hp_label.visible = false
	boss_name_label.text = display_name
	boss_banner.visible = true
	boss_banner_title_label.text = display_name.to_upper()
	boss_banner_title_label.add_theme_color_override("font_color", accent_color)
	_update_boss_hp(current_hp, max_hp)
	_update_goal_text()


func update_boss_health(current_hp: int, max_hp: int) -> void:
	_update_boss_hp(current_hp, max_hp)


func hide_boss_health() -> void:
	sep_boss_label.visible = false
	boss_name_label.visible = false
	boss_hp_label.visible = false
	boss_banner.visible = false
	boss_banner.modulate = Color.WHITE
	boss_banner.scale = Vector2.ONE
	boss_banner_hp_label.text = ""
	boss_banner_title_label.text = ""
	boss_banner_title_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	_last_boss_hp = -1
	_update_goal_text()


# === Private Methods ===
func _update_boss_hp(current_hp: int, max_hp: int) -> void:
	boss_hp_label.text = _boss_hp_bar_text(current_hp, max_hp, BOSS_HP_BAR_CELLS)
	boss_banner_hp_label.text = _boss_hp_bar_text(current_hp, max_hp, BOSS_BANNER_HP_BAR_CELLS)
	var hp_color: Color = _hp_status_color(current_hp, max_hp)
	boss_hp_label.add_theme_color_override("font_color", hp_color)
	boss_banner_hp_label.add_theme_color_override("font_color", hp_color)
	if _last_boss_hp >= 0 and current_hp != _last_boss_hp:
		var flash_color: Color = (
			HP_HEAL_FLASH_COLOR if current_hp > _last_boss_hp else HP_DANGER_COLOR
		)
		_boss_hp_tween = _pulse_label(boss_banner_hp_label, _boss_hp_tween, flash_color)
	_last_boss_hp = current_hp


func _boss_hp_bar_text(current_hp: int, max_hp: int, bar_cells: int) -> String:
	var filled_cells: int = 0
	if max_hp > 0:
		filled_cells = clampi(
			int(round(float(current_hp) / float(max_hp) * bar_cells)), 0, bar_cells
		)
	var empty_cells: int = bar_cells - filled_cells
	var bar: String = "█".repeat(filled_cells) + "░".repeat(empty_cells)
	return "[%s] %d / %d" % [bar, current_hp, max_hp]


func _update_floor(floor_number: int) -> void:
	_current_floor = floor_number
	floor_label.text = "Depth %d // %s" % [floor_number, _biome_name]
	_update_goal_text()


func _update_hp(current_hp: int, max_hp: int) -> void:
	hp_label.text = "HP  %d / %d" % [current_hp, max_hp]
	hp_label.add_theme_color_override("font_color", _hp_status_color(current_hp, max_hp))
	if _last_hp >= 0 and current_hp != _last_hp:
		var flash_color: Color = HP_HEAL_FLASH_COLOR if current_hp > _last_hp else HP_DANGER_COLOR
		_hp_tween = _pulse_label(hp_label, _hp_tween, flash_color)
	_last_hp = current_hp


func _update_xp(current_xp: int, xp_to_next: int) -> void:
	var level_text: String = "1"
	if GameManager.player != null:
		level_text = GameManager.player.stats_component.get_level_bbcode()
	stats_label.text = "Level %s   XP %d / %d" % [level_text, current_xp, xp_to_next]
	if _last_xp >= 0 and current_xp != _last_xp:
		_xp_tween = _pulse_label(stats_label, _xp_tween, XP_FLASH_COLOR)
	_last_xp = current_xp


func _update_gold(gold: int) -> void:
	gold_label.text = "Gold %d" % gold
	if _last_gold >= 0 and gold != _last_gold:
		_gold_tween = _pulse_label(gold_label, _gold_tween, GOLD_FLASH_COLOR)
	_last_gold = gold


func _hp_status_color(current_hp: int, max_hp: int) -> Color:
	if max_hp <= 0:
		return HP_DANGER_COLOR
	var hp_ratio: float = float(current_hp) / float(max_hp)
	if hp_ratio <= 0.30:
		return HP_DANGER_COLOR
	if hp_ratio <= 0.55:
		return HP_WOUNDED_COLOR
	return HP_SAFE_COLOR


func _pulse_label(label: Control, active_tween: Tween, flash_color: Color) -> Tween:
	if active_tween != null and active_tween.is_valid():
		active_tween.kill()
	label.scale = LABEL_PULSE_SCALE
	label.modulate = flash_color
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, LABEL_PULSE_SECONDS)
	tween.parallel().tween_property(label, "modulate", Color.WHITE, LABEL_PULSE_SECONDS)
	return tween


func _update_goal_text() -> void:
	var goal_text: String = "Goal: find stairs"
	if _boss_floor_active:
		if _boss_defeated:
			goal_text = "Goal: claim chest or descend"
		elif _boss_locked:
			goal_text = "Goal: defeat %s" % _boss_display_name
		else:
			goal_text = "Goal: enter the boss gate"
	elif _current_floor >= 25:
		goal_text = "Goal: reach stairs for the final choice"
	elif _has_shopkeeper:
		goal_text = "Goal: shop or find stairs"
	var intent_text: String = ""
	if not _visible_enemy_intents.is_empty():
		intent_text = "Intent: ! melee  → ranged  * spell  + summon  ▲ windup  z asleep\n"
	help_label.text = (
		"%s\n" % goal_text
		+ intent_text
		+ "WASD move     Space search/listen\n"
		+ "F fire         H consumables\n"
		+ "I inventory    C sheet\n"
		+ "Q class skill  Esc pause/settings\n"
		+ "M mute"
	)
