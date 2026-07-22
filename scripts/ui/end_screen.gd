## Shared victory/defeat results screen with deterministic run telemetry and boss progression.
class_name EndScreen
extends Control

# === Constants ===
const DIFFICULTY_NORMAL_COLOR: Color = Color("#8fb3ff")
const DIFFICULTY_HARD_COLOR: Color = Color("#ff5777")
const DIFFICULTY_NIGHTMARE_COLOR: Color = Color("#c77dff")
const SCORE_COLOR: Color = Color("#ffe077")
const COMPLETE_COLOR: Color = Color("#7ff5ff")
const MUTED_COLOR: Color = Color("#767487")
const MAX_PANEL_WIDTH: float = 1180.0
const COMPACT_LAYOUT_WIDTH: float = 760.0
const NARROW_LAYOUT_WIDTH: float = 480.0
const BOSS_REVEAL_STAGGER_SECONDS: float = 0.10
const BOSS_RESOURCE_PATHS: Array[String] = [
	"res://resources/enemies/the_observer.tres",
	"res://resources/enemies/seraphine_thorn_saint.tres",
	"res://resources/enemies/vorrak_ashen_maw.tres",
	"res://resources/enemies/kaelros_drowned_king.tres",
	"res://resources/enemies/nyxara_mirror_witch.tres",
]
const ACTOR_VISUAL_CATALOG: ActorVisualCatalog = preload(
	"res://resources/visuals/catalogs/actor_visual_catalog.tres"
)

# === Exports ===
@export var title_text: String = "Game Over"
@export_multiline var body_text: String = ""
@export var retry_scene: String = "res://scenes/character_creation.tscn"
@export var outcome_kicker: String = "RUN COMPLETE"
@export var retry_button_text: String = "Try Again"
@export var background_color: Color = Color(0.025, 0.012, 0.035, 1.0)
@export var accent_color: Color = Color(1.0, 0.34, 0.47, 1.0)

# === Private Variables ===
var _summary: Dictionary = {}
var _boss_cards: Array[Dictionary] = []
var _reduced_vfx: bool = true
var _entrance_tween: Tween

# === Onready ===
@onready var background: AsciiBackdrop = $Background
@onready var safe_margin: MarginContainer = $SafeMargin
@onready var results_panel: PanelContainer = $SafeMargin/Center/ResultsPanel
@onready var panel_margin: MarginContainer = results_panel.get_node("PanelMargin")
@onready var root_vbox: VBoxContainer = panel_margin.get_node("RootVBox")
@onready var header_grid: GridContainer = root_vbox.get_node("HeaderGrid")
@onready var outcome_vbox: VBoxContainer = header_grid.get_node("OutcomeVBox")
@onready var outcome_kicker_label: Label = outcome_vbox.get_node("OutcomeKicker")
@onready var title_label: Label = outcome_vbox.get_node("TitleLabel")
@onready var identity_label: Label = outcome_vbox.get_node("IdentityLabel")
@onready var difficulty_label: Label = outcome_vbox.get_node("DifficultyLabel")
@onready var score_vbox: VBoxContainer = header_grid.get_node("ScorePanel/ScoreMargin/ScoreVBox")
@onready var score_label: Label = score_vbox.get_node("ScoreLabel")
@onready var high_score_label: Label = score_vbox.get_node("HighScoreLabel")
@onready var results_scroll: ScrollContainer = root_vbox.get_node("ResultsScroll")
@onready var results_content: VBoxContainer = results_scroll.get_node("ResultsContent")
@onready var quick_stats_grid: GridContainer = results_content.get_node("QuickStatsGrid")
@onready var floor_value: Label = quick_stats_grid.get_node("FloorStat/StatMargin/StatVBox/Value")
@onready var turns_value: Label = quick_stats_grid.get_node("TurnsStat/StatMargin/StatVBox/Value")
@onready var kills_value: Label = quick_stats_grid.get_node("KillsStat/StatMargin/StatVBox/Value")
@onready var gold_value: Label = quick_stats_grid.get_node("GoldStat/StatMargin/StatVBox/Value")
@onready
var boss_vbox: VBoxContainer = results_content.get_node("BossProgressPanel/BossMargin/BossVBox")
@onready var boss_progress_label: Label = boss_vbox.get_node("BossHeadingRow/Progress")
@onready var boss_grid: GridContainer = boss_vbox.get_node("BossGrid")
@onready var detail_grid: GridContainer = results_content.get_node("DetailGrid")
@onready var fate_text: RichTextLabel = detail_grid.get_node("FatePanel/CardMargin/CardVBox/Text")
@onready
var progress_text: RichTextLabel = detail_grid.get_node("ProgressPanel/CardMargin/CardVBox/Text")
@onready
var damage_text: RichTextLabel = detail_grid.get_node("DamagePanel/CardMargin/CardVBox/Text")
@onready
var loadout_text: RichTextLabel = detail_grid.get_node("LoadoutPanel/CardMargin/CardVBox/Text")
@onready var narrative_label: Label = results_content.get_node("NarrativeLabel")
@onready var action_grid: GridContainer = root_vbox.get_node("ActionGrid")
@onready var retry_button: Button = action_grid.get_node("RetryButton")
@onready var quit_button: Button = action_grid.get_node("QuitButton")


# === Lifecycle Methods ===
func _ready() -> void:
	_summary = _resolved_summary()
	_reduced_vfx = SensoryFeedback.is_reduced_vfx_preferred()
	background.color = background_color
	background.accent_color = accent_color
	background.treasure_color = accent_color.lerp(SCORE_COLOR, 0.45)
	background.motion_enabled = not _reduced_vfx
	retry_button.text = retry_button_text
	retry_button.pressed.connect(_on_retry_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_populate_header()
	_populate_quick_stats()
	_populate_details()
	_build_boss_progression()
	_apply_responsive_layout()
	_play_entrance()
	retry_button.call_deferred(&"grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		quit_button.grab_focus()
		get_viewport().set_input_as_handled()


# === Private Methods ===
func _resolved_summary() -> Dictionary:
	if not GameManager.last_run_summary.is_empty():
		return GameManager.last_run_summary
	return {
		"name": "Unknown Adventurer",
		"floor": GameManager.current_floor,
		"level": 1,
		"victory": false,
		"class": String(GameManager.DEFAULT_CHARACTER_CLASS),
		"difficulty": String(GameManager.pending_difficulty),
		"version": GameManager.GAME_VERSION,
	}


func _populate_header() -> void:
	var victory: bool = bool(_summary.get("victory", false))
	var character_name: String = str(_summary.get("name", "Unknown Adventurer"))
	var character_class: StringName = StringName(
		str(_summary.get("class", String(GameManager.DEFAULT_CHARACTER_CLASS)))
	)
	var difficulty: StringName = StringName(
		str(_summary.get("difficulty", String(GameManager.DEFAULT_DIFFICULTY)))
	)
	outcome_kicker_label.text = outcome_kicker
	outcome_kicker_label.add_theme_color_override(&"font_color", accent_color)
	title_label.text = title_text
	identity_label.text = (
		"%s  //  %s  //  LEVEL %d"
		% [
			character_name.to_upper(),
			GameManager.get_character_class_label(character_class).to_upper(),
			int(_summary.get("level", 1)),
		]
	)
	difficulty_label.text = (
		"DIFFICULTY: %s" % GameManager.get_difficulty_label(difficulty).to_upper()
	)
	difficulty_label.add_theme_color_override(&"font_color", _difficulty_color(difficulty))
	var score: int = int(_summary.get("score", 0))
	var high_score: int = int(_summary.get("high_score", score))
	score_label.text = _format_number(score) if _summary.has("score") else "—"
	if bool(_summary.get("is_new_high_score", false)):
		high_score_label.text = "NEW RECORD  //  HIGH %s" % _format_number(high_score)
		high_score_label.add_theme_color_override(&"font_color", SCORE_COLOR)
	else:
		high_score_label.text = "HIGH SCORE  //  %s" % _format_number(high_score)
		high_score_label.add_theme_color_override(&"font_color", MUTED_COLOR)
	if victory:
		narrative_label.text = (
			"The five shards join in your grasp. The breach closes—" + "and remembers your name."
		)
	elif int(_summary.get("floor", 1)) > 25 and int(_summary.get("shards_collected", 0)) >= 5:
		narrative_label.text = (
			"You won the right to leave, then carried the joined shards beyond the last stair. "
			+ "The Endless Deeps keep the rest of your story."
		)
	else:
		narrative_label.text = (
			body_text + " The shards you bound still mark how far one mortal pushed the dark."
		)


func _populate_quick_stats() -> void:
	floor_value.text = _metric_text("floor")
	turns_value.text = _metric_text("turns")
	var kills: int = int(_summary.get("enemy_kills", 0))
	kills_value.text = _format_number(kills) if _summary.has("enemy_kills") else "—"
	gold_value.text = _metric_text("final_gold")


func _populate_details() -> void:
	var victory: bool = bool(_summary.get("victory", false))
	var fate_lines: Array[String] = []
	if victory:
		fate_lines.append("[color=#7ff5ff]SURVIVED THE DUNGEON[/color]")
	else:
		var defeated_by: String = str(
			_summary.get("defeated_by", _summary.get("last_damage_source", "Unknown"))
		)
		if defeated_by.is_empty():
			defeated_by = "Unknown"
		fate_lines.append("[color=#ff5777]DEFEATED BY[/color]  %s" % defeated_by)
		var defeated_channel: String = str(
			_summary.get("defeated_by_channel", _summary.get("last_damage_channel", ""))
		)
		if not defeated_channel.is_empty():
			fate_lines.append("Final damage: %s" % defeated_channel.capitalize())
	fate_lines.append("HP remaining: %s / %s" % [_metric_text("final_hp"), _metric_text("max_hp")])
	fate_lines.append("Damage taken: %s" % _metric_text("damage_taken"))
	fate_text.text = "\n".join(fate_lines)

	var boss_kills: Array = _summary.get("boss_kills", [])
	var progress_lines: Array[String] = [
		"Deepest floor: %s" % _metric_text("floor"),
		"Turns taken: %s" % _metric_text("turns"),
		"Enemies slain: %s" % _metric_text("enemy_kills"),
		"Elites slain: %s" % _metric_text("elite_kills"),
		"Bosses / shards: %d / %d" % [boss_kills.size(), GameManager.TOTAL_PORTAL_SHARDS],
		"Items claimed: %s" % _metric_text("items_collected"),
		"Containers opened: %s" % _metric_text("containers_opened"),
	]
	var score_breakdown: Dictionary = _summary.get("score_breakdown", {})
	if not score_breakdown.is_empty():
		progress_lines.append("")
		progress_lines.append("[color=#ffe077]SCORE BREAKDOWN[/color]")
		var score_labels: Dictionary = {
			"progress": "Depth",
			"bosses": "Bosses",
			"combat": "Combat",
			"wealth": "Wealth",
			"pace": "Pace",
			"victory": "Victory",
			"endless": "Endless",
		}
		for score_key: String in score_labels:
			var score_value: int = int(score_breakdown.get(score_key, 0))
			if score_value > 0:
				progress_lines.append(
					"%s: +%s" % [score_labels[score_key], _format_number(score_value)]
				)
		(
			progress_lines
			. append(
				(
					"Subtotal %s  ×  %s%%"
					% [
						_format_number(int(score_breakdown.get("subtotal", 0))),
						int(score_breakdown.get("multiplier_percent", 100)),
					]
				)
			)
		)
	progress_text.text = "\n".join(progress_lines)
	damage_text.text = _build_damage_text()
	loadout_text.text = _build_loadout_text()


func _build_damage_text() -> String:
	var lines: Array[String] = [
		"Total dealt: %s" % _metric_text("damage_dealt"),
		"Biggest hit: %s" % _metric_text("biggest_hit"),
		"Total taken: %s" % _metric_text("damage_taken"),
	]
	var damage_by_channel: Dictionary = _summary.get("damage_by_channel", {})
	for channel: String in ["melee", "ranged", "magic"]:
		if damage_by_channel.has(channel):
			lines.append(
				"%s: %s" % [channel.capitalize(), _format_number(int(damage_by_channel[channel]))]
			)
	var incoming_sources: Dictionary = _summary.get("incoming_sources", {})
	var top_threat_name: String = ""
	var top_threat_damage: int = 0
	for threat_name: Variant in incoming_sources:
		var threat_damage: int = int(incoming_sources[threat_name])
		if threat_damage > top_threat_damage:
			top_threat_name = str(threat_name)
			top_threat_damage = threat_damage
	if top_threat_damage > 0:
		lines.append(
			"Top threat: %s  //  %s dmg" % [top_threat_name, _format_number(top_threat_damage)]
		)
	var raw_sources: Variant = _summary.get("damage_sources", [])
	var sources: Array = []
	if raw_sources is Array:
		sources = raw_sources
	elif raw_sources is Dictionary:
		sources.assign(raw_sources.values())
		sources.sort_custom(_damage_source_precedes)
	if not sources.is_empty():
		lines.append("")
		lines.append("[color=#ffe077]TOP SOURCES[/color]")
	for index: int in range(min(6, sources.size())):
		var source: Variant = sources[index]
		if not source is Dictionary:
			continue
		(
			lines
			. append(
				(
					"%s  //  %s dmg  //  %s uses"
					% [
						str(source.get("name", "Unknown")),
						_format_number(int(source.get("damage", 0))),
						_format_number(int(source.get("uses", 0))),
					]
				)
			)
		)
	if not _summary.has("damage_dealt"):
		lines.append("Legacy run — detailed combat telemetry unavailable.")
	return "\n".join(lines)


func _build_loadout_text() -> String:
	var loadout: Dictionary = _summary.get("loadout", {})
	var slot_labels: Dictionary = {
		"melee": "Melee",
		"ranged": "Ranged",
		"armor": "Armor",
		"accessory_1": "Accessory I",
		"accessory_2": "Accessory II",
	}
	var lines: Array[String] = []
	for slot_key: String in slot_labels:
		lines.append("%s: %s" % [slot_labels[slot_key], str(loadout.get(slot_key, "—"))])
	var inventory_items: Array = _summary.get("inventory", [])
	if not inventory_items.is_empty():
		lines.append("")
		lines.append("Carried: %d items" % inventory_items.size())
		lines.append(", ".join(PackedStringArray(inventory_items.slice(0, 6))))
	return "\n".join(lines)


func _build_boss_progression() -> void:
	var defeated_ids: Dictionary = _defeated_boss_ids()
	boss_progress_label.text = (
		"%d / %d SHARDS BOUND" % [defeated_ids.size(), GameManager.TOTAL_PORTAL_SHARDS]
	)
	for path: String in BOSS_RESOURCE_PATHS:
		var boss_data: Resource = load(path)
		if boss_data == null:
			continue
		var boss_id: StringName = boss_data.boss_id
		var defeated: bool = defeated_ids.has(boss_id)
		var card_data: Dictionary = _create_boss_card(boss_data, defeated)
		_boss_cards.append(card_data)
		boss_grid.add_child(card_data["card"])
	call_deferred(&"_play_boss_death_sequence")


func _create_boss_card(boss_data: Resource, defeated: bool) -> Dictionary:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override(&"panel", _boss_card_style(boss_data.color, defeated))
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 8)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_right", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	card.add_child(margin)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 5)
	margin.add_child(vbox)
	var stage: Control = Control.new()
	stage.custom_minimum_size = Vector2(0, 132)
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stage)
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	var snapshot: Dictionary = {
		"visual_id": boss_data.visual_id,
		"kind": &"enemy",
		"is_boss": true,
		"boss_id": boss_data.boss_id,
	}
	sprite.sprite_frames = ACTOR_VISUAL_CATALOG.sprite_frames_for(snapshot)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.animation = &"idle"
	sprite.frame = 0
	sprite.stop()
	sprite.modulate = Color.WHITE if defeated else Color(0.34, 0.34, 0.42, 0.72)
	stage.add_child(sprite)
	stage.resized.connect(_center_boss_sprite.bind(stage, sprite))
	var name_label: Label = Label.new()
	name_label.text = str(boss_data.display_name)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override(&"font_size", 14)
	name_label.add_theme_color_override(&"font_color", boss_data.color if defeated else MUTED_COLOR)
	vbox.add_child(name_label)
	var status_label: Label = Label.new()
	status_label.text = "SHARD BOUND" if defeated else "UNREACHED"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override(&"font_size", 12)
	status_label.add_theme_color_override(
		&"font_color", COMPLETE_COLOR if defeated else MUTED_COLOR
	)
	vbox.add_child(status_label)
	return {
		"card": card,
		"stage": stage,
		"sprite": sprite,
		"defeated": defeated,
	}


func _boss_card_style(identity_color: Color, defeated: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.025, 0.055, 0.92)
	style.border_color = identity_color if defeated else Color(0.22, 0.21, 0.28, 1.0)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _defeated_boss_ids() -> Dictionary:
	var valid_ids: Dictionary = {
		&"observer": true,
		&"seraphine": true,
		&"vorrak": true,
		&"kaelros": true,
		&"nyxara": true,
	}
	var defeated_ids: Dictionary = {}
	var boss_kills: Variant = _summary.get("boss_kills", [])
	if not boss_kills is Array:
		return defeated_ids
	for boss_entry: Variant in boss_kills:
		var boss_id: StringName
		if boss_entry is Dictionary:
			boss_id = StringName(str(boss_entry.get("id", "")))
		else:
			boss_id = StringName(str(boss_entry))
		if valid_ids.has(boss_id):
			defeated_ids[boss_id] = true
	return defeated_ids


func _play_boss_death_sequence() -> void:
	for card_data: Dictionary in _boss_cards:
		var stage: Control = card_data["stage"]
		var sprite: AnimatedSprite2D = card_data["sprite"]
		_center_boss_sprite(stage, sprite)
		if not bool(card_data["defeated"]):
			continue
		var stagger_seconds: float = (
			BOSS_REVEAL_STAGGER_SECONDS * 0.5 if _reduced_vfx else BOSS_REVEAL_STAGGER_SECONDS
		)
		await get_tree().create_timer(stagger_seconds).timeout
		sprite.speed_scale = 1.5 if _reduced_vfx else 1.0
		sprite.play(&"death")
		await sprite.animation_finished


func _center_boss_sprite(stage: Control, sprite: AnimatedSprite2D) -> void:
	sprite.position = (stage.size * 0.5).floor()


func _damage_source_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_damage: int = int(left.get("damage", 0))
	var right_damage: int = int(right.get("damage", 0))
	if left_damage != right_damage:
		return left_damage > right_damage
	return str(left.get("name", "")) < str(right.get("name", ""))


func _apply_responsive_layout() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var compact: bool = viewport_size.x < COMPACT_LAYOUT_WIDTH or viewport_size.y < 680.0
	var narrow: bool = viewport_size.x < NARROW_LAYOUT_WIDTH
	var short: bool = viewport_size.y < 500.0
	var stack_actions: bool = compact and not short
	var horizontal_margin: int = 8 if narrow else (16 if compact else 24)
	var vertical_margin: int = 8 if compact else 18
	safe_margin.add_theme_constant_override(&"margin_left", horizontal_margin)
	safe_margin.add_theme_constant_override(&"margin_right", horizontal_margin)
	safe_margin.add_theme_constant_override(&"margin_top", vertical_margin)
	safe_margin.add_theme_constant_override(&"margin_bottom", vertical_margin)
	var panel_side_margin: int = 6 if short else (10 if compact else 18)
	var panel_vertical_margin: int = 6 if short else (10 if compact else 16)
	panel_margin.add_theme_constant_override(&"margin_left", panel_side_margin)
	panel_margin.add_theme_constant_override(&"margin_right", panel_side_margin)
	panel_margin.add_theme_constant_override(&"margin_top", panel_vertical_margin)
	panel_margin.add_theme_constant_override(&"margin_bottom", panel_vertical_margin)
	root_vbox.add_theme_constant_override(&"separation", 6 if short else 12)
	var available_size: Vector2 = (
		viewport_size - Vector2(float(horizontal_margin * 2), float(vertical_margin * 2))
	)
	results_panel.custom_minimum_size = Vector2(
		min(MAX_PANEL_WIDTH, max(0.0, available_size.x)),
		max(0.0, available_size.y),
	)
	results_scroll.custom_minimum_size.y = 0.0 if compact else 300.0
	header_grid.columns = 2 if short else (1 if compact else 2)
	quick_stats_grid.columns = 1 if narrow else (2 if compact else 4)
	boss_grid.columns = 1 if narrow else (2 if compact else 5)
	detail_grid.columns = 1 if compact else 2
	action_grid.columns = 1 if stack_actions else 2
	title_label.add_theme_font_size_override(&"font_size", 18 if short else (22 if compact else 28))
	score_label.add_theme_font_size_override(&"font_size", 20 if short else (24 if compact else 30))
	for card_data: Dictionary in _boss_cards:
		var stage: Control = card_data["stage"]
		var sprite: AnimatedSprite2D = card_data["sprite"]
		stage.custom_minimum_size.y = 68.0 if compact else 132.0
		sprite.scale = Vector2.ONE if compact else Vector2(2.0, 2.0)
		_center_boss_sprite(stage, sprite)
	_wire_action_focus(stack_actions)


func _wire_action_focus(compact: bool) -> void:
	results_scroll.focus_mode = Control.FOCUS_ALL
	results_scroll.focus_next = results_scroll.get_path_to(retry_button)
	results_scroll.focus_previous = results_scroll.get_path_to(quit_button)
	results_scroll.focus_neighbor_top = results_scroll.get_path_to(quit_button)
	results_scroll.focus_neighbor_bottom = results_scroll.get_path_to(retry_button)
	retry_button.focus_next = retry_button.get_path_to(quit_button)
	retry_button.focus_previous = retry_button.get_path_to(results_scroll)
	quit_button.focus_next = quit_button.get_path_to(results_scroll)
	quit_button.focus_previous = quit_button.get_path_to(retry_button)
	var empty_path: NodePath = NodePath("")
	retry_button.focus_neighbor_left = empty_path
	retry_button.focus_neighbor_right = empty_path
	quit_button.focus_neighbor_left = empty_path
	quit_button.focus_neighbor_right = empty_path
	retry_button.focus_neighbor_top = retry_button.get_path_to(results_scroll)
	if compact:
		retry_button.focus_neighbor_bottom = retry_button.get_path_to(quit_button)
		quit_button.focus_neighbor_top = quit_button.get_path_to(retry_button)
		quit_button.focus_neighbor_bottom = quit_button.get_path_to(results_scroll)
	else:
		retry_button.focus_neighbor_bottom = retry_button.get_path_to(results_scroll)
		quit_button.focus_neighbor_top = quit_button.get_path_to(results_scroll)
		quit_button.focus_neighbor_bottom = quit_button.get_path_to(results_scroll)
		retry_button.focus_neighbor_left = retry_button.get_path_to(quit_button)
		retry_button.focus_neighbor_right = retry_button.get_path_to(quit_button)
		quit_button.focus_neighbor_left = quit_button.get_path_to(retry_button)
		quit_button.focus_neighbor_right = quit_button.get_path_to(retry_button)


func _play_entrance() -> void:
	if _reduced_vfx:
		results_panel.modulate = Color.WHITE
		results_panel.position.y = 0.0
		return
	results_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	results_panel.position.y = 10.0
	_entrance_tween = create_tween().set_parallel(true)
	_entrance_tween.tween_property(results_panel, "modulate", Color.WHITE, 0.34)
	(
		_entrance_tween
		. tween_property(results_panel, "position:y", 0.0, 0.34)
		. set_ease(Tween.EASE_OUT)
		. set_trans(Tween.TRANS_CUBIC)
	)


func _metric_text(key: String) -> String:
	return _format_number(int(_summary.get(key, 0))) if _summary.has(key) else "—"


func _difficulty_color(difficulty: StringName) -> Color:
	match difficulty:
		GameManager.DIFFICULTY_HARD:
			return DIFFICULTY_HARD_COLOR
		GameManager.DIFFICULTY_NIGHTMARE:
			return DIFFICULTY_NIGHTMARE_COLOR
		_:
			return DIFFICULTY_NORMAL_COLOR


func _format_number(value: int) -> String:
	var digits: String = str(abs(value))
	var grouped: String = ""
	while digits.length() > 3:
		grouped = ",%s%s" % [digits.right(3), grouped]
		digits = digits.left(digits.length() - 3)
	grouped = digits + grouped
	return "-%s" % grouped if value < 0 else grouped


func _on_retry_pressed() -> void:
	GameManager.clear_finished_run_context()
	get_tree().change_scene_to_file(retry_scene)


func _on_quit_pressed() -> void:
	GameManager.clear_finished_run_context()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
