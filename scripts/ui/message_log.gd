class_name MessageLog
extends PanelContainer

# === Constants ===
const MAX_MESSAGES: int = 6
const TYPE_COLORS: Dictionary = {
	&"neutral": "#d7d8dc",
	&"combat_hit": "#f07d67",
	&"combat_miss": "#9aa3ad",
	&"death": "#c9a45d",
	&"loot": "#f1c75b",
	&"gold": "#ffd866",
	&"heal": "#7bd88f",
	&"warning": "#ff9f6e",
	&"floor": "#8db7ff",
	&"level": "#d899ff",
	&"equipment": "#8fd3ff",
}

# === Private Variables ===
var _messages: Array[String] = []
var _last_message: String = ""
var _last_type: StringName = &"neutral"
var _repeat_count: int = 0

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
	output.text = "[color=#555566]-- MESSAGES --[/color]\n" + "\n".join(_messages)
	output.scroll_to_line(max(0, output.get_line_count() - 1))


# === Private Methods ===
func _format_message(message: String, message_type: StringName, repeat_count: int = 1) -> String:
	var color: String = TYPE_COLORS.get(message_type, TYPE_COLORS[&"neutral"])
	var suffix: String = " (x%d)" % repeat_count if repeat_count > 1 else ""
	return "[color=%s]%s%s[/color]" % [color, message, suffix]
