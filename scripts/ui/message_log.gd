## Color-coded scrolling log of combat, loot, floor, and system messages.
class_name MessageLog
extends PanelContainer

# === Constants ===
const MAX_MESSAGES: int = 7
const TYPE_COLORS: Dictionary = {
	&"neutral": "#fff9e4",
	&"combat_hit": "#ff5777",
	&"combat_miss": "#a6a66a",
	&"death": "#b53b59",
	&"loot": "#ffe077",
	&"gold": "#ffb915",
	&"heal": "#57b067",
	&"warning": "#ff8a32",
	&"floor": "#9972ee",
	&"level": "#99d7e5",
	&"equipment": "#47a0bf",
	&"magic": "#d7b7ff",
	&"boss_gate": "#ffcf5a",
	&"boss_story": "#ff9fdf",
	&"boss_telegraph": "#ff6b35",
	&"boss_phase": "#7ff5ff",
	&"shard": "#c77dff",
}
const LOG_PULSE_SCALE: Vector2 = Vector2(1.015, 1.015)
const LOG_PULSE_SECONDS: float = 0.18

# === Private Variables ===
var _messages: Array[String] = []
var _last_message: String = ""
var _last_type: StringName = &"neutral"
var _repeat_count: int = 0
var _message_tween: Tween

# === Onready ===
@onready var output: RichTextLabel = $Output


# === Lifecycle Methods ===
func _ready() -> void:
	output.bbcode_enabled = true
	GameManager.log_message_added.connect(add_message)


# === Public Methods ===
func add_message(message: String, message_type: StringName = &"neutral") -> void:
	if message == _last_message and message_type == _last_type and not _messages.is_empty():
		_repeat_count += 1
		_messages[_messages.size() - 1] = _format_message(message, message_type, _repeat_count)
	else:
		_last_message = message
		_last_type = message_type
		_repeat_count = 1
		_messages.append(_format_message(message, message_type))

	while _messages.size() > MAX_MESSAGES:
		_messages.pop_front()
	output.text = "[color=#8178b5]MESSAGES[/color]\n" + "\n".join(_messages)
	output.scroll_to_line(max(0, output.get_line_count() - 1))
	_pulse_output(message_type)


# === Private Methods ===
func _format_message(message: String, message_type: StringName, repeat_count: int = 1) -> String:
	var color: String = TYPE_COLORS.get(message_type, TYPE_COLORS[&"neutral"])
	var suffix: String = " (x%d)" % repeat_count if repeat_count > 1 else ""
	return "[color=%s]%s%s[/color]" % [color, message, suffix]


func _pulse_output(message_type: StringName) -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	var color: Color = Color.html(TYPE_COLORS.get(message_type, TYPE_COLORS[&"neutral"]))
	output.scale = LOG_PULSE_SCALE
	output.modulate = Color(color.r, color.g, color.b, 1.0)
	_message_tween = create_tween()
	_message_tween.set_trans(Tween.TRANS_QUART)
	_message_tween.set_ease(Tween.EASE_OUT)
	_message_tween.tween_property(output, "scale", Vector2.ONE, LOG_PULSE_SECONDS)
	_message_tween.parallel().tween_property(output, "modulate", Color.WHITE, LOG_PULSE_SECONDS)
