## V16.5.0 Sensory Feedback — quieter procedural audio cues, ambience,
## remembered reduced-VFX mode, and calmer pause-menu controls.
##
## Place as `UI/SensoryFeedback` in `scenes/game.tscn`: full-rect, mouse-filter
## ignore, z_index below BiomeOverlay (z=80).  No external audio assets needed.
class_name SensoryFeedback
extends Control

# === Constants ===
const SAMPLE_RATE: int = 22050
const VERSION: String = "16.5.0"
const VERSION_LABEL: String = "V16.5.0 — Reduced VFX & Audio Polish"
const PLAYER_POOL_SIZE: int = 6
const MIN_VOLUME_DB: float = -60.0
const MAX_VOLUME_DB: float = 0.0
const DEFAULT_VOLUME: float = 0.42
const SETTINGS_PATH: String = "user://dungeon_delver_settings.cfg"
const SETTINGS_SECTION: String = "sensory"
const SETTING_REDUCED_VFX: String = "reduced_vfx"
const REDUCED_VFX_ALPHA_SCALE: float = 0.22
const REDUCED_VFX_MAX_ALPHA: float = 0.045
const REDUCED_VFX_DURATION_SCALE: float = 0.58
const REDUCED_VFX_MIN_DURATION: float = 0.08

# Cue name identifiers
const CUE_COMBAT_HIT: StringName = &"combat_hit"
const CUE_COMBAT_MISS: StringName = &"combat_miss"
const CUE_DAMAGE: StringName = &"damage"
const CUE_DEATH: StringName = &"death"
const CUE_LOOT: StringName = &"loot"
const CUE_GOLD: StringName = &"gold"
const CUE_HEAL: StringName = &"heal"
const CUE_WARNING: StringName = &"warning"
const CUE_FLOOR: StringName = &"floor"
const CUE_LEVEL: StringName = &"level"
const CUE_EQUIPMENT: StringName = &"equipment"
const CUE_MAGIC: StringName = &"magic"
const CUE_VICTORY: StringName = &"victory"
const CUE_BOSS_GATE: StringName = &"boss_gate"
const CUE_BOSS_SPAWN: StringName = &"boss_spawn"
const CUE_BOSS_TELEGRAPH: StringName = &"boss_telegraph"
const CUE_BOSS_PHASE: StringName = &"boss_phase"
const CUE_BOSS_DEFEAT: StringName = &"boss_defeat"

const ALL_CUES: Array[StringName] = [
	CUE_COMBAT_HIT,
	CUE_COMBAT_MISS,
	CUE_DAMAGE,
	CUE_DEATH,
	CUE_LOOT,
	CUE_GOLD,
	CUE_HEAL,
	CUE_WARNING,
	CUE_FLOOR,
	CUE_LEVEL,
	CUE_EQUIPMENT,
	CUE_MAGIC,
	CUE_VICTORY,
	CUE_BOSS_GATE,
	CUE_BOSS_SPAWN,
	CUE_BOSS_TELEGRAPH,
	CUE_BOSS_PHASE,
	CUE_BOSS_DEFEAT,
]

# Message type → cue name mapping (subset of cues driven by log messages).
const MESSAGE_TYPE_CUE_MAP: Dictionary = {
	&"combat_hit": CUE_COMBAT_HIT,
	&"combat_miss": CUE_COMBAT_MISS,
	&"damage": CUE_DAMAGE,
	&"death": CUE_DEATH,
	&"loot": CUE_LOOT,
	&"gold": CUE_GOLD,
	&"heal": CUE_HEAL,
	&"warning": CUE_WARNING,
	&"floor": CUE_FLOOR,
	&"level": CUE_LEVEL,
	&"equipment": CUE_EQUIPMENT,
	&"magic": CUE_MAGIC,
	&"boss_gate": CUE_BOSS_GATE,
	&"boss_story": CUE_BOSS_SPAWN,
	&"boss_telegraph": CUE_BOSS_TELEGRAPH,
	&"boss_phase": CUE_BOSS_PHASE,
	&"boss_defeat": CUE_BOSS_DEFEAT,
}

# Visual colour / duration profile per cue.
const CUE_VISUAL: Dictionary = {
	CUE_COMBAT_HIT: {"color": Color(1.0, 0.33, 0.47, 0.18), "duration": 0.25},
	CUE_COMBAT_MISS: {"color": Color(0.65, 0.65, 0.42, 0.10), "duration": 0.15},
	CUE_DAMAGE: {"color": Color(1.0, 0.20, 0.25, 0.22), "duration": 0.35},
	CUE_DEATH: {"color": Color(0.71, 0.23, 0.35, 0.40), "duration": 0.80},
	CUE_LOOT: {"color": Color(1.0, 0.88, 0.47, 0.14), "duration": 0.30},
	CUE_GOLD: {"color": Color(1.0, 0.72, 0.08, 0.16), "duration": 0.25},
	CUE_HEAL: {"color": Color(0.34, 0.69, 0.40, 0.14), "duration": 0.35},
	CUE_WARNING: {"color": Color(1.0, 0.54, 0.20, 0.18), "duration": 0.25},
	CUE_FLOOR: {"color": Color(0.60, 0.45, 0.93, 0.15), "duration": 0.50},
	CUE_LEVEL: {"color": Color(0.60, 0.84, 0.90, 0.16), "duration": 0.60},
	CUE_EQUIPMENT: {"color": Color(0.28, 0.63, 0.75, 0.10), "duration": 0.12},
	CUE_MAGIC: {"color": Color(0.70, 0.50, 1.0, 0.18), "duration": 0.35},
	CUE_VICTORY: {"color": Color(1.0, 0.82, 0.32, 0.25), "duration": 1.00},
	CUE_BOSS_GATE: {"color": Color(1.0, 0.54, 0.20, 0.22), "duration": 0.45},
	CUE_BOSS_SPAWN: {"color": Color(0.82, 0.20, 0.38, 0.24), "duration": 0.70},
	CUE_BOSS_TELEGRAPH: {"color": Color(1.0, 0.38, 0.14, 0.16), "duration": 0.20},
	CUE_BOSS_PHASE: {"color": Color(0.78, 0.48, 1.0, 0.22), "duration": 0.45},
	CUE_BOSS_DEFEAT: {"color": Color(1.0, 0.82, 0.32, 0.30), "duration": 1.10},
}

# Per-cue audio profile: gain_db, min_interval (seconds between plays),
# duration (expected length in seconds), category label.
const CUE_PROFILES: Dictionary = {
	CUE_COMBAT_HIT: {"gain_db": -8.0, "min_interval": 0.22, "duration": 0.12, "category": "combat"},
	CUE_COMBAT_MISS:
	{"gain_db": -10.0, "min_interval": 0.15, "duration": 0.05, "category": "combat"},
	CUE_DAMAGE: {"gain_db": -7.0, "min_interval": 0.45, "duration": 0.30, "category": "damage"},
	CUE_DEATH: {"gain_db": -5.0, "min_interval": 2.50, "duration": 0.80, "category": "death"},
	CUE_LOOT: {"gain_db": -8.0, "min_interval": 0.65, "duration": 0.28, "category": "item"},
	CUE_GOLD: {"gain_db": -7.0, "min_interval": 0.45, "duration": 0.20, "category": "item"},
	CUE_HEAL: {"gain_db": -7.0, "min_interval": 0.65, "duration": 0.40, "category": "buff"},
	CUE_WARNING: {"gain_db": -12.0, "min_interval": 0.70, "duration": 0.15, "category": "warning"},
	CUE_FLOOR: {"gain_db": -9.0, "min_interval": 2.50, "duration": 0.60, "category": "progression"},
	CUE_LEVEL: {"gain_db": -7.0, "min_interval": 1.80, "duration": 0.80, "category": "progression"},
	CUE_EQUIPMENT: {"gain_db": -12.0, "min_interval": 0.30, "duration": 0.04, "category": "item"},
	CUE_MAGIC: {"gain_db": -9.0, "min_interval": 0.40, "duration": 0.35, "category": "magic"},
	CUE_VICTORY: {"gain_db": -5.0, "min_interval": 5.00, "duration": 1.00, "category": "victory"},
	CUE_BOSS_GATE: {"gain_db": -8.0, "min_interval": 0.65, "duration": 0.35, "category": "boss"},
	CUE_BOSS_SPAWN: {"gain_db": -6.0, "min_interval": 1.00, "duration": 0.65, "category": "boss"},
	CUE_BOSS_TELEGRAPH:
	{"gain_db": -12.0, "min_interval": 0.35, "duration": 0.16, "category": "boss"},
	CUE_BOSS_PHASE: {"gain_db": -7.0, "min_interval": 1.50, "duration": 0.42, "category": "boss"},
	CUE_BOSS_DEFEAT: {"gain_db": -5.0, "min_interval": 3.00, "duration": 1.00, "category": "boss"},
}

# === Exports ===
@export_range(0.0, 1.0) var default_master_volume: float = DEFAULT_VOLUME

# === Private Variables ===
var _cue_streams: Dictionary = {}  # StringName → AudioStreamWAV
var _audio_players: Array[AudioStreamPlayer] = []
var _audio_enabled: bool = true
var _next_player_index: int = 0
var _master_volume: float = 0.50
var _ambience_enabled: bool = true
var _ambience_player: AudioStreamPlayer
var _ambience_stream: AudioStreamWAV = null
var _ambience_profile: Dictionary = {}
var _music_player: AudioStreamPlayer
var _boss_music_stream: AudioStream
var _boss_climax_stream: AudioStream
var _boss_music_id: StringName = &""
var _boss_music_climax_active: bool = false
var _cue_last_play_time: Dictionary = {}  # StringName → float (time in seconds)
var _cue_play_count: Dictionary = {}  # StringName → int

var _visual_active: bool = false
var _visual_color: Color = Color.TRANSPARENT
var _visual_duration: float = 0.0
var _visual_elapsed: float = 0.0
var _reduced_vfx_enabled: bool = false

# === GameManager Access ===


## Returns the GameManager autoload node, or null if not available.
func _game_manager() -> Node:
	return get_node_or_null("/root/GameManager")


# === Lifecycle Methods ===
func _ready() -> void:
	# Full-rect anchors and mouse-filter ignore.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_preferences()

	# Start with visual processing off (event-gated only).
	set_process(false)

	# Build procedural audio streams.
	_initialize_cues()

	# Create a small pool of AudioStreamPlayer children.
	_initialize_audio_pool()

	# Create ambience player.
	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "AmbiencePlayer"
	_ambience_player.bus = &"Master"
	add_child(_ambience_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "BossMusicPlayer"
	_music_player.bus = &"Master"
	add_child(_music_player)
	_master_volume = clampf(default_master_volume, 0.0, 1.0)
	_update_player_volumes()

	# Initialize rate-limiting state.
	for cue: StringName in ALL_CUES:
		_cue_last_play_time[cue] = -INF
		_cue_play_count[cue] = 0

	# Connect GameManager signals if available.
	var gm: Node = _game_manager()
	if gm != null:
		if not gm.log_message_added.is_connected(_on_log_message):
			gm.log_message_added.connect(_on_log_message)
		if not gm.player_damaged.is_connected(_on_player_damaged):
			gm.player_damaged.connect(_on_player_damaged)
		if not gm.level_up.is_connected(_on_level_up):
			gm.level_up.connect(_on_level_up)
		if not gm.floor_changed.is_connected(_on_floor_changed):
			gm.floor_changed.connect(_on_floor_changed)
		if not gm.game_over_won.is_connected(_on_game_over_won):
			gm.game_over_won.connect(_on_game_over_won)


func _process(delta: float) -> void:
	_visual_elapsed += delta
	if _visual_elapsed >= _visual_duration:
		_visual_active = false
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if not _visual_active:
		return

	var progress: float = clampf(_visual_elapsed / _visual_duration, 0.0, 1.0)
	# Fade out over the last 30 % of the visual duration.
	var fade: float = 1.0
	if progress > 0.7:
		fade = 1.0 - (progress - 0.7) / 0.3

	if _reduced_vfx_enabled:
		_draw_reduced_visual(fade)
		return

	# --- Flash overlay ---
	var flash_color: Color = _visual_color
	flash_color.a *= fade
	draw_rect(Rect2(Vector2.ZERO, size), flash_color)

	# --- Sparse scanlines ---
	var scan_color: Color = Color(
		_visual_color.r * 1.4,
		_visual_color.g * 1.4,
		_visual_color.b * 1.4,
		_visual_color.a * 0.35 * fade
	)
	var scan_step: int = 5
	var y: float = 0.0
	while y < size.y:
		draw_rect(Rect2(0.0, y, size.x, 1.0), scan_color)
		y += scan_step

	# --- Inset border ring ---
	var border_inset: float = 4.0
	var border_color: Color = Color(
		_visual_color.r * 1.5,
		_visual_color.g * 1.5,
		_visual_color.b * 1.5,
		_visual_color.a * 0.60 * fade
	)
	var rect: Rect2 = Rect2(
		Vector2(border_inset, border_inset), size - Vector2(border_inset * 2.0, border_inset * 2.0)
	)
	draw_rect(rect, border_color, false, 2.0)
	# Corner accents on the border ring
	var corner_len: float = 12.0
	var corners: Array[Array] = [
		[
			Vector2(border_inset, border_inset),
			Vector2(border_inset + corner_len, border_inset),
			Vector2(border_inset, border_inset + corner_len)
		],
		[
			Vector2(size.x - border_inset, border_inset),
			Vector2(size.x - border_inset - corner_len, border_inset),
			Vector2(size.x - border_inset, border_inset + corner_len)
		],
		[
			Vector2(border_inset, size.y - border_inset),
			Vector2(border_inset + corner_len, size.y - border_inset),
			Vector2(border_inset, size.y - border_inset - corner_len)
		],
		[
			Vector2(size.x - border_inset, size.y - border_inset),
			Vector2(size.x - border_inset - corner_len, size.y - border_inset),
			Vector2(size.x - border_inset, size.y - border_inset - corner_len)
		],
	]
	for corner: Array in corners:
		draw_line(corner[0], corner[1], border_color, 1.5)
		draw_line(corner[0], corner[2], border_color, 1.5)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_M and event.pressed and not event.echo:
		toggle_audio_enabled(true)


# === Public Methods ===


## Returns the cue name that should play for the given message type string,
## or `&""` if no cue is mapped.
func cue_for_message_type(message_type: StringName) -> StringName:
	var cue: Variant = MESSAGE_TYPE_CUE_MAP.get(message_type, &"")
	if cue is StringName:
		return cue
	return &""


## Triggers the named sensory cue — plays audio and activates visual feedback.
## Safe to call with an unknown or empty cue name (no-op).
func trigger_cue(cue_name: StringName) -> void:
	if cue_name == &"":
		return

	# Audio playback
	if _audio_enabled:
		_play_cue(cue_name)

	# Visual feedback
	var visual_config: Variant = CUE_VISUAL.get(cue_name)
	if visual_config is Dictionary:
		_visual_color = visual_config.get("color", Color.TRANSPARENT)
		_visual_duration = visual_config.get("duration", 0.25)
		if _reduced_vfx_enabled:
			_visual_color.a = min(_visual_color.a * REDUCED_VFX_ALPHA_SCALE, REDUCED_VFX_MAX_ALPHA)
			_visual_duration = max(
				REDUCED_VFX_MIN_DURATION, _visual_duration * REDUCED_VFX_DURATION_SCALE
			)
		_visual_elapsed = 0.0
		_visual_active = true
		set_process(true)
		queue_redraw()


func play_boss_intro_cue(_boss_id: StringName) -> void:
	trigger_cue(CUE_BOSS_SPAWN)


func play_boss_phase_cue(_boss_id: StringName, _phase: int) -> void:
	trigger_cue(CUE_BOSS_PHASE)


func play_boss_defeat_cue(_boss_id: StringName) -> void:
	trigger_cue(CUE_BOSS_DEFEAT)


## Returns an array of all registered cue name StringNames.
func get_cue_names() -> Array[StringName]:
	return ALL_CUES.duplicate()


## Returns the AudioStreamWAV for a named cue, or `null` if unknown.
func get_cue_stream(cue_name: StringName) -> AudioStreamWAV:
	var stream: Variant = _cue_streams.get(cue_name)
	if stream is AudioStreamWAV:
		return stream
	return null


## Returns `true` while visual feedback from a triggered cue is still active.
func has_active_visual_feedback() -> bool:
	return _visual_active


## Enables or disables all audio playback, optionally announcing via log.
## Visual feedback is unaffected.
func set_audio_enabled(enabled: bool, announce: bool = false) -> void:
	_audio_enabled = enabled
	_update_player_volumes()
	_sync_ambience_player()
	if not _audio_enabled and is_instance_valid(_music_player):
		_music_player.stop()
	if announce:
		var status: String = "enabled" if _audio_enabled else "disabled"
		var gm: Node = _game_manager()
		if gm != null:
			gm.add_log_message("Audio cues %s" % status, &"neutral")


## Returns `true` if audio playback is currently enabled.
func is_audio_enabled() -> bool:
	return _audio_enabled


## Toggle audio on/off, optionally announcing via log.
func toggle_audio_enabled(announce: bool = true) -> void:
	set_audio_enabled(not _audio_enabled, announce)


## Sets master volume as a normalized value [0.0, 1.0] and updates all
## active audio players immediately.
func set_master_volume(value: float) -> void:
	_master_volume = clampf(value, 0.0, 1.0)
	_update_player_volumes()


## Returns the current master volume level, normalized [0.0, 1.0].
func get_master_volume() -> float:
	return _master_volume


## Returns the effective master volume in dB derived from the current
## normalized volume.
func get_effective_volume_db() -> float:
	if not _audio_enabled:
		return MIN_VOLUME_DB
	return _normalized_volume_to_db(_master_volume)


## Enables or disables the looping ambience audio.
func set_ambience_enabled(enabled: bool) -> void:
	_ambience_enabled = enabled
	_sync_ambience_player()


## Returns `true` if ambience playback is currently enabled.
func is_ambience_enabled() -> bool:
	return _ambience_enabled


## Enables or disables calmer event visuals and persists the setting by default.
func set_reduced_vfx_enabled(enabled: bool, persist: bool = true) -> void:
	_reduced_vfx_enabled = enabled
	if persist:
		_save_preferences()


## Returns `true` if reduced event visuals are enabled.
func is_reduced_vfx_enabled() -> bool:
	return _reduced_vfx_enabled


## Toggle reduced event visuals, optionally announcing via log.
func toggle_reduced_vfx_enabled(announce: bool = true) -> void:
	set_reduced_vfx_enabled(not _reduced_vfx_enabled)
	if announce:
		var status: String = "reduced" if _reduced_vfx_enabled else "full"
		var gm: Node = _game_manager()
		if gm != null:
			gm.add_log_message("Visual effects set to %s." % status, &"neutral")


## Updates the floor/biome ambience context, generating a new procedural
## ambient stream appropriate for the given floor and biome theme.
func set_floor_audio_context(floor_number: int, biome_theme: Dictionary) -> void:
	_ambience_stream = _build_ambience_stream(floor_number, biome_theme)
	_ambience_profile = {
		"floor": floor_number,
		"biome_name": biome_theme.get("name", "Unknown"),
		"biome_index": biome_theme.get("biome_index", 0),
	}
	if _ambience_player != null and _ambience_stream != null:
		_sync_ambience_player()


func start_boss_music(
	boss_id: StringName, base_stream: AudioStream, climax_stream: AudioStream = null
) -> void:
	if base_stream == null:
		stop_boss_music(0.0)
		return
	_boss_music_id = boss_id
	_boss_music_stream = base_stream
	_boss_climax_stream = climax_stream
	_boss_music_climax_active = false
	var stream_to_play: AudioStream = base_stream
	if boss_id == &"nyxara" and climax_stream != null:
		stream_to_play = climax_stream
		_boss_music_climax_active = true
	_apply_boss_music_stream(stream_to_play)


func update_boss_music_intensity(current_hp: int, max_hp: int) -> void:
	if _boss_music_id == &"" or _boss_climax_stream == null or _boss_music_climax_active:
		return
	if max_hp <= 0:
		return
	if float(current_hp) / float(max_hp) > 0.35:
		return
	_boss_music_climax_active = true
	_apply_boss_music_stream(_boss_climax_stream)


func stop_boss_music(_fade_seconds: float = 0.5) -> void:
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null
	_boss_music_stream = null
	_boss_climax_stream = null
	_boss_music_id = &""
	_boss_music_climax_active = false
	_update_player_volumes()
	_sync_ambience_player()


func is_boss_music_playing() -> bool:
	return is_instance_valid(_music_player) and _music_player.playing


func get_boss_music_stream() -> AudioStream:
	if not is_instance_valid(_music_player):
		return null
	return _music_player.stream


## Returns the profile Dictionary for a named cue, or `null` if unknown.
func get_cue_profile(cue_name: StringName) -> Dictionary:
	var profile: Variant = CUE_PROFILES.get(cue_name)
	if profile is Dictionary:
		return profile.duplicate()
	return {}


## Returns how many times a named cue has been played this session.
func get_play_count(cue_name: StringName) -> int:
	return _cue_play_count.get(cue_name, 0)


## Returns the current ambience AudioStreamWAV, or `null` if none set.
func get_ambience_stream() -> AudioStreamWAV:
	return _ambience_stream


## Returns the current ambience profile Dictionary with floor/biome context.
func get_ambience_profile() -> Dictionary:
	return _ambience_profile.duplicate()


func _apply_boss_music_stream(stream: AudioStream) -> void:
	if not is_instance_valid(_music_player):
		return
	var playback_stream: AudioStream = stream
	if stream != null:
		playback_stream = stream.duplicate()
	var ogg_stream: AudioStreamOggVorbis = playback_stream as AudioStreamOggVorbis
	if ogg_stream != null:
		ogg_stream.loop = true
	_music_player.stream = playback_stream
	_music_player.volume_db = get_effective_volume_db() - 8.0
	if _audio_enabled:
		_music_player.play()
	_update_player_volumes()
	_sync_ambience_player()


func _draw_reduced_visual(fade: float) -> void:
	var flash_color: Color = _visual_color
	flash_color.a = min(flash_color.a * fade, REDUCED_VFX_MAX_ALPHA)
	if flash_color.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), flash_color)
	var mark_color: Color = Color(
		_visual_color.r * 1.35,
		_visual_color.g * 1.35,
		_visual_color.b * 1.35,
		min(_visual_color.a * 2.2 * fade, 0.16)
	)
	var inset: float = 8.0
	var corner_len: float = 34.0
	draw_line(Vector2(inset, inset), Vector2(inset + corner_len, inset), mark_color, 1.2)
	draw_line(Vector2(inset, inset), Vector2(inset, inset + corner_len), mark_color, 1.2)
	draw_line(
		Vector2(size.x - inset, inset), Vector2(size.x - inset - corner_len, inset), mark_color, 1.2
	)
	draw_line(
		Vector2(size.x - inset, inset), Vector2(size.x - inset, inset + corner_len), mark_color, 1.2
	)


func _load_preferences() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: int = config.load(SETTINGS_PATH)
	if error != OK:
		return
	_reduced_vfx_enabled = bool(
		config.get_value(SETTINGS_SECTION, SETTING_REDUCED_VFX, _reduced_vfx_enabled)
	)


func _save_preferences() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTING_REDUCED_VFX, _reduced_vfx_enabled)
	config.save(SETTINGS_PATH)


# === Private Audio Methods ===


func _initialize_cues() -> void:
	_cue_streams[CUE_COMBAT_HIT] = _generate_cue_stream(_build_combat_hit)
	_cue_streams[CUE_COMBAT_MISS] = _generate_cue_stream(_build_combat_miss)
	_cue_streams[CUE_DAMAGE] = _generate_cue_stream(_build_damage)
	_cue_streams[CUE_DEATH] = _generate_cue_stream(_build_death)
	_cue_streams[CUE_LOOT] = _generate_cue_stream(_build_loot)
	_cue_streams[CUE_GOLD] = _generate_cue_stream(_build_gold)
	_cue_streams[CUE_HEAL] = _generate_cue_stream(_build_heal)
	_cue_streams[CUE_WARNING] = _generate_cue_stream(_build_warning)
	_cue_streams[CUE_FLOOR] = _generate_cue_stream(_build_floor)
	_cue_streams[CUE_LEVEL] = _generate_cue_stream(_build_level)
	_cue_streams[CUE_EQUIPMENT] = _generate_cue_stream(_build_equipment)
	_cue_streams[CUE_MAGIC] = _generate_cue_stream(_build_magic)
	_cue_streams[CUE_VICTORY] = _generate_cue_stream(_build_victory)


func _initialize_audio_pool() -> void:
	for index: int in range(PLAYER_POOL_SIZE):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "AudioPlayer_%d" % index
		player.bus = &"Master"
		player.volume_db = _normalized_volume_to_db(_master_volume)
		add_child(player)
		_audio_players.append(player)


## Plays a cue stream if rate limiting permits, applying per-cue gain.
func _play_cue(cue_name: StringName) -> void:
	var profile: Variant = CUE_PROFILES.get(cue_name)
	if profile is not Dictionary:
		return
	var min_interval: float = profile.get("min_interval", 0.0)
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _cue_last_play_time.get(cue_name, -INF) < min_interval:
		return
	_cue_last_play_time[cue_name] = now
	_cue_play_count[cue_name] = _cue_play_count.get(cue_name, 0) + 1

	var stream: Variant = _cue_streams.get(cue_name)
	if stream is AudioStreamWAV:
		var pool_size: int = _audio_players.size()
		if pool_size == 0:
			return
		var player: AudioStreamPlayer = _audio_players[_next_player_index]
		_next_player_index = (_next_player_index + 1) % pool_size
		player.stream = stream
		var gain_db: float = profile.get("gain_db", 0.0)
		player.volume_db = get_effective_volume_db() + gain_db
		player.play()


## Updates all active audio player volumes from the current master volume.
func _update_player_volumes() -> void:
	var effective_db: float = get_effective_volume_db()
	for player: AudioStreamPlayer in _audio_players:
		if is_instance_valid(player):
			player.volume_db = effective_db
	if is_instance_valid(_ambience_player):
		var ambience_db: float = effective_db
		if is_instance_valid(_music_player) and _music_player.playing:
			ambience_db -= 12.0
		_ambience_player.volume_db = ambience_db if _ambience_enabled else MIN_VOLUME_DB
	if is_instance_valid(_music_player):
		_music_player.volume_db = effective_db - 8.0 if _audio_enabled else MIN_VOLUME_DB


## Applies the current audio/ambience state to the ambience player.
func _sync_ambience_player() -> void:
	if not is_instance_valid(_ambience_player):
		return
	var ambience_db: float = get_effective_volume_db()
	if is_instance_valid(_music_player) and _music_player.playing:
		ambience_db -= 12.0
	_ambience_player.volume_db = ambience_db if _ambience_enabled else MIN_VOLUME_DB
	if not _audio_enabled or not _ambience_enabled or _ambience_stream == null:
		_ambience_player.stop()
		return
	_ambience_player.stream = _ambience_stream
	if not _ambience_player.playing:
		_ambience_player.play()


## Maps a normalized volume [0.0, 1.0] to a logarithmic dB value.
static func _normalized_volume_to_db(normalized: float) -> float:
	var clamped: float = clampf(normalized, 0.0, 1.0)
	if clamped <= 0.0:
		return MIN_VOLUME_DB
	var curved: float = sqrt(clamped)
	return lerpf(MIN_VOLUME_DB, MAX_VOLUME_DB, curved)


# --- PCM synthesis helpers ---


## Synthesises a single-frequency sine wave segment and returns it as sample
## values in [-1.0, 1.0].
static func _sine_samples(freq: float, duration: float, start_phase: float = 0.0) -> Array[float]:
	var count: int = maxi(1, ceili(duration * SAMPLE_RATE))
	var result: Array[float] = []
	result.resize(count)
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		result[i] = sin(start_phase + t * freq * TAU)
	return result


## Sums multiple sample arrays into one, scaling each by its weight.
static func _mix(sources: Array[Array], weights: Array[float]) -> Array[float]:
	var max_len: int = 0
	for src: Array in sources:
		if src.size() > max_len:
			max_len = src.size()
	var result: Array[float] = []
	result.resize(max_len)
	for src_i: int in range(sources.size()):
		var src: Array = sources[src_i]
		var w: float = weights[src_i] if src_i < weights.size() else 1.0
		for i: int in range(src.size()):
			result[i] += float(src[i]) * w
	return result


## Applies a simple exponential decay envelope (fast attack, then release).
static func _envelope(
	samples: Array[float], attack_seconds: float = 0.005, release_start: float = 0.7
) -> Array[float]:
	var attack_samples: int = ceili(attack_seconds * SAMPLE_RATE)
	var release_sample: int = floori(release_start * float(samples.size()))
	for i: int in range(samples.size()):
		var env: float = 1.0
		if i < attack_samples and attack_samples > 0:
			env = float(i) / float(attack_samples)
		if i >= release_sample:
			var t: float = float(i - release_sample) / float(samples.size() - release_sample)
			env *= 1.0 - t
		samples[i] *= env
	return samples


## Applies a frequency sweep from `freq_start` to `freq_end` over the sample
## array, rewriting its phase.
static func _apply_sweep(samples: Array[float], freq_start: float, freq_end: float) -> void:
	var count: int = samples.size()
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var frac: float = float(i) / float(count - 1) if count > 1 else 0.0
		var freq: float = freq_start + (freq_end - freq_start) * frac
		samples[i] = sin(t * freq * TAU)


## Builds a square-wave approximation from the individual sine partials.
static func _square_samples(freq: float, duration: float, partials: int = 3) -> Array[float]:
	var base: Array[float] = []
	var count: int = maxi(1, ceili(duration * SAMPLE_RATE))
	base.resize(count)
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var v: float = 0.0
		for k: int in range(1, partials * 2 + 1, 2):
			v += sin(t * freq * TAU * float(k)) / float(k)
		base[i] = v
	return base


## Noise burst — white noise through a simple band-limited approximation.
static func _noise_samples(duration: float) -> Array[float]:
	var count: int = maxi(1, ceili(duration * SAMPLE_RATE))
	var result: Array[float] = []
	result.resize(count)
	for i: int in range(count):
		result[i] = randf() * 2.0 - 1.0
	return result


## Converts float samples in [-1.0, 1.0] to a 16-bit mono PCM PackedByteArray.
static func _samples_to_pcm(samples: Array[float]) -> PackedByteArray:
	var count: int = samples.size()
	var data: PackedByteArray = []
	data.resize(count * 2)
	for i: int in range(count):
		var val: int = clampi(int(samples[i] * 32767.0), -32768, 32767)
		var idx: int = i * 2
		data[idx] = val & 0xFF
		data[idx + 1] = (val >> 8) & 0xFF
	return data


## Peak-normalizes samples so the maximum absolute value reaches ~0.99,
## preserving the waveform shape while maximising loudness before PCM.
static func _peak_normalize(samples: Array[float]) -> Array[float]:
	var peak: float = 0.0
	for v: float in samples:
		var abs_v: float = absf(v)
		if abs_v > peak:
			peak = abs_v
	if peak < 0.0001:
		return samples
	var scale: float = 0.99 / peak
	for i: int in range(samples.size()):
		samples[i] *= scale
	return samples


## Builds an AudioStreamWAV from float samples.
static func _pcm_to_stream(samples: Array[float]) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.stereo = false
	stream.mix_rate = SAMPLE_RATE
	stream.data = _samples_to_pcm(samples)
	return stream


## Helper: calls a build callback that returns float samples, peak-normalizes,
## then wraps into an AudioStreamWAV.
static func _generate_cue_stream(build_callback: Callable) -> AudioStreamWAV:
	var samples: Array[float] = build_callback.call()
	_peak_normalize(samples)
	var stream: AudioStreamWAV = _pcm_to_stream(samples)
	return stream


# --- Cue synthesisers ---


static func _build_combat_hit() -> Array[float]:
	# Low blip: short 120 Hz sine with gentle decay.
	var s: Array[float] = _sine_samples(120.0, 0.12)
	return _envelope(s, 0.005, 0.55)


static func _build_combat_miss() -> Array[float]:
	# Quick tick: high 600 Hz sine, very short.
	var s: Array[float] = _sine_samples(600.0, 0.05)
	return _envelope(s, 0.003, 0.35)


static func _build_damage() -> Array[float]:
	# Low thud: 110 Hz sine with downward sweep, moderate length.
	var s: Array[float] = _sine_samples(110.0, 0.30)
	_apply_sweep(s, 120.0, 85.0)
	return _envelope(s, 0.008, 0.70)


static func _build_death() -> Array[float]:
	# Descending: square approximation sliding from 250→70 Hz, 0.8 s.
	var s: Array[float] = _square_samples(250.0, 0.80, 2)
	_apply_sweep(s, 250.0, 70.0)
	return _envelope(s, 0.015, 0.80)


static func _build_loot() -> Array[float]:
	# Chime: 880 Hz + 1320 Hz bell-like.
	var s1: Array[float] = _sine_samples(880.0, 0.28)
	var s2: Array[float] = _sine_samples(1320.0, 0.28)
	var mixed: Array[float] = _mix([s1, s2], [0.5, 0.3])
	return _envelope(mixed, 0.005, 0.65)


static func _build_gold() -> Array[float]:
	# Higher chime: 1100 Hz + 1650 Hz.
	var s1: Array[float] = _sine_samples(1100.0, 0.20)
	var s2: Array[float] = _sine_samples(1650.0, 0.20)
	var mixed: Array[float] = _mix([s1, s2], [0.4, 0.4])
	return _envelope(mixed, 0.005, 0.55)


static func _build_heal() -> Array[float]:
	# Rising: 280 → 550 Hz sine, 0.4 s.
	var s: Array[float] = _sine_samples(280.0, 0.40)
	_apply_sweep(s, 280.0, 550.0)
	return _envelope(s, 0.008, 0.70)


static func _build_warning() -> Array[float]:
	# Soft buzz: sine at 300 Hz, 0.12 s, gentle.
	var s: Array[float] = _sine_samples(300.0, 0.12)
	return _envelope(s, 0.005, 0.45)


static func _build_floor() -> Array[float]:
	# Rising with two harmonics: 200→450 Hz + 400→900 Hz, 0.6 s.
	var s1: Array[float] = _sine_samples(200.0, 0.60)
	_apply_sweep(s1, 200.0, 450.0)
	var s2: Array[float] = _sine_samples(400.0, 0.60)
	_apply_sweep(s2, 400.0, 900.0)
	var mixed: Array[float] = _mix([s1, s2], [0.5, 0.25])
	return _envelope(mixed, 0.010, 0.70)


static func _build_level() -> Array[float]:
	# Fuller rising: 300→700 Hz with three harmonics, 0.8 s.
	var s1: Array[float] = _sine_samples(300.0, 0.80)
	_apply_sweep(s1, 300.0, 700.0)
	var s2: Array[float] = _sine_samples(600.0, 0.80)
	_apply_sweep(s2, 600.0, 1400.0)
	var s3: Array[float] = _sine_samples(900.0, 0.80)
	_apply_sweep(s3, 900.0, 2100.0)
	var mixed: Array[float] = _mix([s1, s2, s3], [0.4, 0.25, 0.12])
	return _envelope(mixed, 0.010, 0.75)


static func _build_equipment() -> Array[float]:
	# Soft click: very short filtered noise burst.
	var s: Array[float] = _noise_samples(0.035)
	return _envelope(s, 0.002, 0.25)


static func _build_magic() -> Array[float]:
	# Gentle shimmer: layered high sines with subtle amplitude wobble.
	var s1: Array[float] = _sine_samples(1100.0, 0.30)
	var s2: Array[float] = _sine_samples(1650.0, 0.30)
	var s3: Array[float] = _sine_samples(2200.0, 0.30)
	var mixed: Array[float] = _mix([s1, s2, s3], [0.3, 0.2, 0.12])
	# Amplitude wobble for shimmer effect
	var count: int = mixed.size()
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var wobble: float = 0.75 + 0.25 * sin(t * 10.0 * TAU)
		mixed[i] *= wobble
	return _envelope(mixed, 0.008, 0.70)


static func _build_victory() -> Array[float]:
	# Sweeping fanfare: 250→600 Hz with rich harmonics, 1.0 s.
	var s1: Array[float] = _sine_samples(250.0, 1.00)
	_apply_sweep(s1, 250.0, 600.0)
	var s2: Array[float] = _sine_samples(500.0, 1.00)
	_apply_sweep(s2, 500.0, 1200.0)
	var s3: Array[float] = _sine_samples(750.0, 1.00)
	_apply_sweep(s3, 750.0, 1800.0)
	var mixed: Array[float] = _mix([s1, s2, s3], [0.4, 0.3, 0.12])
	return _envelope(mixed, 0.015, 0.80)


# --- Ambience synthesiser ---


## Builds a quiet, sparse procedural ambience stream appropriate for the
## given floor number and biome theme.  Returns a looping AudioStreamWAV of
## moderate length (~4 seconds) with low, sparse content.
static func _build_ambience_stream(floor_number: int, biome_theme: Dictionary) -> AudioStreamWAV:
	var biome_name: String = str(biome_theme.get("name", "The Tower"))
	var duration: float = 4.0
	var count: int = ceili(duration * SAMPLE_RATE)
	var buf: Array[float] = []
	buf.resize(count)
	var seed_base: int = floor_number * 100 + biome_name.hash()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.set_seed(seed_base)

	# Determine ambient character from biome name.
	var has_wind: bool = true
	var has_drip: bool = false
	var has_rumble: bool = false
	var has_hum: bool = false
	var name_lower: String = biome_name.to_lower()
	if name_lower.find("cave") != -1 or name_lower.find("cavern") != -1:
		has_drip = true
		has_hum = true
	elif (
		name_lower.find("tower") != -1
		or name_lower.find("keep") != -1
		or name_lower.find("fortress") != -1
		or name_lower.find("castle") != -1
	):
		has_hum = true
	elif (
		name_lower.find("forest") != -1
		or name_lower.find("grove") != -1
		or name_lower.find("thicket") != -1
	):
		has_drip = true
		has_rumble = false
	elif (
		name_lower.find("crypt") != -1
		or name_lower.find("tomb") != -1
		or name_lower.find("catacomb") != -1
	):
		has_hum = true
		has_drip = true
	elif (
		name_lower.find("forge") != -1
		or name_lower.find("foundry") != -1
		or name_lower.find("lava") != -1
	):
		has_rumble = true
		has_wind = false
	elif (
		name_lower.find("sanctum") != -1
		or name_lower.find("library") != -1
		or name_lower.find("archive") != -1
	):
		has_hum = true
		has_wind = false

	# Synthesise ambient samples — sparse, quiet, subtle.
	for i: int in range(count):
		var t: float = float(i) / SAMPLE_RATE
		var sample: float = 0.0

		# Wind: very low frequency filtered noise envelope.
		if has_wind:
			var wind_env: float = 0.5 + 0.5 * sin(t * 0.8 * TAU + float(seed_base) * 0.01)
			var wind_noise: float = rng.randf() * 2.0 - 1.0
			sample += wind_noise * 0.015 * wind_env

		# Drip: occasional high-pitched tick.
		if has_drip:
			var drip_phase: float = fmod(t, 1.5 + sin(float(seed_base)) * 0.5)
			if drip_phase < 0.025:
				var drip_pos: float = drip_phase / 0.025
				sample += sin(drip_pos * TAU * 1800.0) * 0.02 * (1.0 - drip_pos)

		# Hum: low sustained drone.
		if has_hum:
			var hum_freq: float = 55.0 + fmod(float(seed_base) * 0.01, 15.0)
			sample += sin(t * hum_freq * TAU) * 0.008
			sample += sin(t * hum_freq * 2.0 * TAU) * 0.004

		# Rumble: very low occasional pulses.
		if has_rumble:
			var rumble_phase: float = fmod(t, 2.0 + fmod(float(seed_base), 1.0))
			if rumble_phase < 0.15:
				var rumble_pos: float = rumble_phase / 0.15
				var rumble_env: float = sin(rumble_pos * PI)
				var rumble_noise: float = rng.randf() * 2.0 - 1.0
				sample += rumble_noise * 0.02 * rumble_env

		buf[i] = clampf(sample, -1.0, 1.0)

	# Normalize gently, then make very quiet for background.
	_peak_normalize(buf)
	for i: int in range(count):
		buf[i] *= 0.012

	var stream: AudioStreamWAV = _pcm_to_stream(buf)
	stream.set_loop_mode(AudioStreamWAV.LOOP_FORWARD)
	stream.set_loop_begin(0)
	stream.set_loop_end(count)
	return stream


func _on_log_message(_message: String, message_type: StringName) -> void:
	var cue: StringName = cue_for_message_type(message_type)
	if cue != &"":
		trigger_cue(cue)


func _on_player_damaged(_new_hp: int, _max_hp: int) -> void:
	trigger_cue(CUE_DAMAGE)


func _on_level_up(_new_level: int) -> void:
	trigger_cue(CUE_LEVEL)


func _on_floor_changed(_new_floor: int) -> void:
	trigger_cue(CUE_FLOOR)


func _on_game_over_won(victory: bool) -> void:
	trigger_cue(CUE_VICTORY if victory else CUE_DEATH)
