class_name HUD
extends Control

# === Onready ===
@onready var name_label: Label = $Margin/VBox/NameLabel
@onready var hp_label: Label = $Margin/VBox/HpLabel
@onready var floor_label: Label = $Margin/VBox/FloorLabel
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
	help_label.text = "WASD move     Space search/listen\nF fire         H consumables\nI inventory    C sheet\nEsc pause"


# === Public Methods ===
func bind_player(player: Node) -> void:
	name_label.text = player.display_name
	_update_floor(GameManager.current_floor)
	_update_hp(player.stats_component.current_hp, player.stats_component.max_hp)
	_update_xp(player.stats_component.xp, player.stats_component.xp_for_next_level())
	gold_label.text = "Gold %d" % player.stats_component.gold


# === Private Methods ===
func _update_floor(floor_number: int) -> void:
	floor_label.text = "Depth %d" % floor_number


func _update_hp(current_hp: int, max_hp: int) -> void:
	hp_label.text = "HP  %d / %d" % [current_hp, max_hp]


func _update_xp(current_xp: int, xp_to_next: int) -> void:
	var level_text: String = "1"
	if GameManager.player != null:
		level_text = GameManager.player.stats_component.get_level_bbcode()
	stats_label.text = "Level %s   XP %d / %d" % [level_text, current_xp, xp_to_next]
