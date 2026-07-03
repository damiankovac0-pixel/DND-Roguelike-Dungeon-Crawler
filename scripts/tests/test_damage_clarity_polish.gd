## Focused damage-type clarity and UI polish regression test.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script
##   res://scripts/tests/test_damage_clarity_polish.gd
extends SceneTree

const DamageTypeTextScript = preload("res://scripts/ui/damage_type_text.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_damage_copy_helper()
	if not _failed:
		_check_library_bestiary_affinities()
	if not _failed:
		_check_map_burst_lifecycle()
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


func _check_map_burst_lifecycle() -> void:
	var map_view_script: GDScript = load("res://scripts/ui/map_view.gd")
	if map_view_script == null:
		_fail("MapView script failed to load")
		return
	var map_view: Node2D = map_view_script.new()
	map_view.play_cell_burst(Vector2i(3, 4), Color(1.0, 0.8, 0.2), "✦")
	if not map_view.has_active_cell_bursts():
		_fail("MapView burst should be active after play_cell_burst")
		map_view.free()
		return
	if not map_view.is_processing():
		_fail("MapView should process while a burst is active")
		map_view.free()
		return
	map_view._process(map_view_script.CELL_BURST_DURATION + 0.01)
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


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
