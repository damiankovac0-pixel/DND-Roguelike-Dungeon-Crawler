class_name MainMenu
extends Control

# === Constants ===
const HISTORY_LIMIT: int = 5
const HISTORY_NAME_MAX: int = 18


# === Onready ===
@onready var start_button: Button = $Center/VBox/StartButton
@onready var library_button: Button = $Center/VBox/LibraryButton
@onready var quit_button: Button = $Center/VBox/QuitButton
@onready var history_output: RichTextLabel = $HistoryPanel/HistoryOutput


# === Lifecycle Methods ===
func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	library_button.pressed.connect(_on_library_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	history_output.bbcode_enabled = true
	_refresh_history()
	start_button.grab_focus()


# === Private Methods ===
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character_creation.tscn")


func _on_library_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/library.tscn")


func _on_quit_pressed() -> void:
	if OS.has_feature("web") and Engine.has_singleton(&"JavaScriptBridge"):
		var bridge: Object = Engine.get_singleton(&"JavaScriptBridge")
		bridge.call("eval", "window.close();", true)
		return
	get_tree().quit()


func _refresh_history() -> void:
	var entries: Array = GameManager.character_history
	var history_text: String = "[color=#47426b]-- RECENT DELVERS --[/color]"
	if entries.is_empty():
		history_text += "\n\n[color=#92906f]No delvers recorded.[/color]"
	else:
		var lines: Array[String] = []
		var entry_count: int = min(HISTORY_LIMIT, entries.size())
		for index: int in entry_count:
			lines.append(_format_history_entry(entries[index]))
		if entries.size() > HISTORY_LIMIT:
			lines.append(
				"[color=#47426b]+%d older runs in the archive[/color]"
				% (entries.size() - HISTORY_LIMIT)
			)
		history_text += "\n\n%s" % "\n".join(lines)
	history_output.clear()
	history_output.parse_bbcode(history_text)


func _format_history_entry(entry: Dictionary) -> String:
	var delver_name: String = _clean_history_name(str(entry.get("name", "Unknown")))
	var floor_number: int = int(entry.get("floor", 1))
	var level_value: int = int(entry.get("level", 1))
	var won: bool = bool(entry.get("victory", false))
	var result: String = "Victory" if won else "Fell"
	var result_color: String = "#7bd88f" if won else "#8b8fa3"
	return (
		"[color=#fffbf0]%s[/color]  [color=#7db8ff]F%d[/color]  [color=#d8d8d8]L%s[/color]  [color=%s]%s[/color]"
		% [delver_name, floor_number, _format_level_bbcode(level_value), result_color, result]
	)


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
	return "20[color=%s]+%d[/color]" % [
		colors[(prestige_level - 1) % colors.size()],
		prestige_level,
	]


func _clean_history_name(raw_name: String) -> String:
	var clean_name: String = raw_name.strip_edges().replace("[", "(").replace("]", ")")
	if clean_name.is_empty():
		clean_name = "Nameless"
	if clean_name.length() > HISTORY_NAME_MAX:
		clean_name = clean_name.substr(0, HISTORY_NAME_MAX - 3) + "..."
	return clean_name
