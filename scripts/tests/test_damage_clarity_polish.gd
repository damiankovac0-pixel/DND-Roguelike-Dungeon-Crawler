## Focused damage-type clarity and UI polish regression test.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script
##   res://scripts/tests/test_damage_clarity_polish.gd
extends SceneTree

const DamageTypeTextScript = preload("res://scripts/ui/damage_type_text.gd")
const MapViewScript = preload("res://scripts/ui/map_view.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_damage_copy_helper()
	if not _failed:
		_check_library_bestiary_affinities()
	if not _failed:
		_check_overlay_layering()
	if not _failed:
		await _check_message_log_semantic_colors()
	if not _failed:
		_check_map_burst_lifecycle()
	if not _failed:
		_check_reduced_vfx_shortens_active_cell_bursts()
	if not _failed:
		print("damage clarity and polish checks passed")
		quit(0)


func _check_damage_copy_helper() -> void:
	var summary: String = DamageTypeTextScript.DAMAGE_TYPE_SUMMARY
	for damage_type: String in ["melee", "ranged", "magic"]:
		if damage_type not in summary:
			_fail("Damage summary missing %s: %s" % [damage_type, summary])
			return
	if summary.length() > 120:
		_fail("Damage summary should stay compact, length=%d" % summary.length())
		return
	var standard_line: String = DamageTypeTextScript.affinity_line(100, 100, 100)
	if "standard" not in standard_line:
		_fail("Standard affinity line should stay short and reassuring: %s" % standard_line)
		return
	var wraith_line: String = DamageTypeTextScript.affinity_line(75, 100, 150)
	if "resists melee (75%)" not in wraith_line:
		_fail("Affinity line missing melee resistance: %s" % wraith_line)
		return
	if "weak to magic (150%)" not in wraith_line:
		_fail("Affinity line missing magic weakness: %s" % wraith_line)
		return
	print("  damage copy helper: concise summary and affinity labels")


func _check_library_bestiary_affinities() -> void:
	var library_script: GDScript = load("res://scripts/ui/library_menu.gd")
	if library_script == null:
		_fail("LibraryMenu script failed to load")
		return
	var library: Control = library_script.new()
	var wraith: Resource = load("res://resources/enemies/wraith.tres")
	var entry: Array[String] = library._enemy_entry(wraith)
	var joined_entry: String = "\n".join(entry)
	if DamageTypeTextScript.DAMAGE_TYPE_SUMMARY not in library._build_bestiary_text():
		_fail("Bestiary intro missing compact damage type summary")
		library.free()
		return
	if "Affinities:" not in joined_entry:
		_fail("Wraith bestiary entry missing affinities: %s" % joined_entry)
		library.free()
		return
	if "resists melee (75%)" not in joined_entry or "weak to magic (150%)" not in joined_entry:
		_fail("Wraith bestiary affinities are incomplete: %s" % joined_entry)
		library.free()
		return
	library.free()
	print("  library bestiary: enemy affinities are explained in-entry")


func _check_overlay_layering() -> void:
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	var pause_panel: Control = game.get_node("UI/PausePanel")
	var biome_overlay: Control = game.get_node("UI/BiomeOverlay")
	if pause_panel.z_index <= biome_overlay.z_index:
		_fail(
			(
				"Pause panel z-index %d must exceed biome overlay z-index %d"
				% [pause_panel.z_index, biome_overlay.z_index]
			)
		)
		game.free()
		return
	game.free()
	print("  overlay layering: pause menu stays above biome introductions")


func _check_message_log_semantic_colors() -> void:
	var message_log_script: GDScript = load("res://scripts/ui/message_log.gd")
	if message_log_script == null:
		_fail("MessageLog script failed to load")
		return
	var message_log: PanelContainer = message_log_script.new()
	var output: RichTextLabel = RichTextLabel.new()
	output.name = "Output"
	message_log.add_child(output)
	root.add_child(message_log)
	await process_frame

	var neutral_color: String = str(message_log_script.TYPE_COLORS[&"neutral"])
	var semantic_types: Array[StringName] = [
		&"magic",
		&"boss_gate",
		&"boss_story",
		&"boss_telegraph",
		&"boss_phase",
	]
	for message_type: StringName in semantic_types:
		var color: String = str(message_log_script.TYPE_COLORS.get(message_type, ""))
		if color.is_empty():
			_fail("MessageLog missing semantic color for %s" % str(message_type))
			message_log.queue_free()
			return
		if color == neutral_color:
			_fail("MessageLog %s color should not fall back to neutral" % str(message_type))
			message_log.queue_free()
			return
		var message: String = "semantic %s" % str(message_type)
		message_log.add_message(message, message_type)
		var formatted: String = "[color=%s]%s[/color]" % [color, message]
		if formatted not in output.text:
			_fail(
				(
					"MessageLog %s should format with %s; output was %s"
					% [str(message_type), color, output.text]
				)
			)
			message_log.queue_free()
			return
		if not _colors_match_rgb(output.modulate, Color.html(color)):
			_fail("MessageLog %s pulse should use %s" % [str(message_type), color])
			message_log.queue_free()
			return

	message_log.queue_free()
	await process_frame
	print("  message log: magic and boss messages use semantic non-neutral colors")


func _check_map_burst_lifecycle() -> void:
	var map_view: Node2D = MapViewScript.new()
	map_view.play_cell_burst(Vector2i(3, 4), Color(1.0, 0.8, 0.2), "✦")
	if not map_view.has_active_cell_bursts():
		_fail("MapView burst should be active after play_cell_burst")
		map_view.free()
		return
	if not map_view.is_processing():
		_fail("MapView should process while a burst is active")
		map_view.free()
		return
	map_view._process(MapViewScript.CELL_BURST_DURATION + 0.01)
	if map_view.has_active_cell_bursts():
		_fail("MapView burst should expire after its duration")
		map_view.free()
		return
	if map_view.is_processing():
		_fail("MapView should stop processing after bursts expire")
		map_view.free()
		return
	map_view.free()
	print("  map polish: chest/container burst activates and expires cleanly")


func _check_reduced_vfx_shortens_active_cell_bursts() -> void:
	var map_view: Node2D = MapViewScript.new()
	map_view.play_cell_burst(Vector2i(2, 3), Color(1.0, 0.8, 0.2, 0.65), "✦")
	if map_view._cell_bursts.size() != 1:
		_fail("Reduced VFX: expected one active burst before toggle")
		map_view.free()
		return

	var active_burst: Dictionary = map_view._cell_bursts[0]
	var full_duration: float = float(active_burst.get("duration", 0.0))
	map_view.set_reduced_vfx_enabled(true)

	if not map_view.has_active_cell_bursts():
		_fail("Reduced VFX: active burst should remain active immediately after toggle")
		map_view.free()
		return
	var reduced_burst: Dictionary = map_view._cell_bursts[0]
	var reduced_duration: float = float(reduced_burst.get("duration", 0.0))
	if reduced_duration >= full_duration:
		_fail(
			(
				"Reduced VFX: active burst duration %.3f should be shorter than %.3f"
				% [reduced_duration, full_duration]
			)
		)
		map_view.free()
		return
	var reduced_color: Color = reduced_burst.get("color", Color.WHITE)
	if reduced_color.a > 0.081:
		_fail("Reduced VFX: active burst alpha %.4f should be <= 0.08" % reduced_color.a)
		map_view.free()
		return
	if not map_view.is_processing():
		_fail("Reduced VFX: active burst should keep MapView processing after toggle")
		map_view.free()
		return

	map_view._process(reduced_duration + 0.01)
	if map_view.has_active_cell_bursts():
		_fail("Reduced VFX: active burst should expire after shortened duration")
		map_view.free()
		return
	if map_view.is_processing():
		_fail("Reduced VFX: processing should stop after shortened burst expires")
		map_view.free()
		return
	map_view.free()
	print("  reduced VFX: active cell bursts cap alpha and use shortened lifecycle")


func _colors_match_rgb(left: Color, right: Color) -> bool:
	return (
		absf(left.r - right.r) <= 0.001
		and absf(left.g - right.g) <= 0.001
		and absf(left.b - right.b) <= 0.001
	)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
