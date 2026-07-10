## V23.0.0 ProjectileSystem core unit tests.
##
## Contracts:
##   1. line_cells produces deterministic Bresenham lines including both endpoints.
##   2. Diagonal lines include both endpoints and correct size.
##   3. payload_for_id returns known profile payloads with non-empty glyphs.
##   4. Empty/unknown projectile_id falls back by damage type.
##   5. array_from_cell_keys sorts by y then x.
##
## Run:
##   /usr/local/bin/godot --headless --path . --script \
##      res://scripts/tests/test_v23_projectile_system.gd
extends SceneTree

const ProjectileSystemScript = preload("res://scripts/systems/projectile_system.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_line_cells_horizontal()
	if _failed:
		return
	_check_line_cells_diagonal()
	if _failed:
		return
	_check_payload_for_id_arrow()
	if _failed:
		return
	_check_payload_fallback_empty_id()
	if _failed:
		return
	_check_payload_fallback_unknown_id()
	if _failed:
		return
	_check_array_from_cell_keys()
	if _failed:
		return
	_check_fallback_by_damage_type()
	if _failed:
		return
	_check_ref_counted_payload_immutable()
	if _failed:
		return

	print("V23 projectile system checks passed")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _check_line_cells_horizontal() -> void:
	var cells: Array[Vector2i] = ProjectileSystemScript.line_cells(Vector2i(0, 0), Vector2i(3, 0))
	var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	if cells != expected:
		_fail("line_cells horizontal: got %s, expected %s" % [str(cells), str(expected)])


func _check_line_cells_diagonal() -> void:
	var cells: Array[Vector2i] = ProjectileSystemScript.line_cells(Vector2i(0, 0), Vector2i(3, 3))
	if cells.is_empty():
		_fail("line_cells diagonal returned empty")
		return
	if cells.front() != Vector2i(0, 0):
		_fail("line_cells diagonal should include start endpoint")
		return
	if cells.back() != Vector2i(3, 3):
		_fail("line_cells diagonal should include goal endpoint")
		return
	if cells.size() != 4:
		_fail(
			"line_cells diagonal size expected 4, got %d (cells: %s)" % [cells.size(), str(cells)]
		)


func _check_payload_for_id_arrow() -> void:
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")
	if payload.get("profile_id", &"") != &"arrow":
		_fail(
			(
				'payload_for_id(&"arrow") profile_id expected &"arrow", got %s'
				% str(payload.get("profile_id", &""))
			)
		)
		return
	var glyph: String = str(payload.get("glyph", ""))
	if glyph.is_empty():
		_fail('payload_for_id(&"arrow") glyph should be non-empty')
		return
	print("  arrow glyph: '%s'" % glyph)


func _check_payload_fallback_empty_id() -> void:
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"", &"fire")
	if payload.get("profile_id", &"") != &"fire_bolt":
		_fail(
			(
				'payload_for_id(&"", &"fire") profile_id expected &"fire_bolt", got %s'
				% str(payload.get("profile_id", &""))
			)
		)
		return
	print("  fire fallback: fire_bolt")


func _check_payload_fallback_unknown_id() -> void:
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"unknown_profile", &"fire")
	if payload.get("profile_id", &"") != &"fire_bolt":
		_fail(
			(
				'payload_for_id(&"unknown_profile", &"fire") expected &"fire_bolt", got %s'
				% str(payload.get("profile_id", &""))
			)
		)
		return
	print("  unknown ID fallback: fire_bolt")


func _check_array_from_cell_keys() -> void:
	var cells: Dictionary = {
		Vector2i(2, 2): true,
		Vector2i(1, 1): true,
		Vector2i(2, 1): true,
	}
	var sorted: Array[Vector2i] = ProjectileSystemScript.array_from_cell_keys(cells)
	var expected: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(2, 1),
		Vector2i(2, 2),
	]
	if sorted != expected:
		_fail("array_from_cell_keys: got %s, expected %s" % [str(sorted), str(expected)])
		return
	# Non-Vector2i keys should be ignored
	var mixed: Dictionary = {
		Vector2i(5, 5): true,
		"not_a_cell": true,
		42: true,
	}
	var sorted_mixed: Array[Vector2i] = ProjectileSystemScript.array_from_cell_keys(mixed)
	if sorted_mixed != [Vector2i(5, 5)]:
		_fail("array_from_cell_keys should filter non-Vector2i keys: got %s" % str(sorted_mixed))


func _check_fallback_by_damage_type() -> void:
	var checks: Array[Dictionary] = [
		{"damage_type": &"fire", "expected": &"fire_bolt"},
		{"damage_type": &"magic", "expected": &"arcane_bolt"},
		{"damage_type": &"ranged", "expected": &"arrow"},
		{"damage_type": &"piercing", "expected": &"arrow"},
		{"damage_type": &"cold", "expected": &"frost_shard"},
		{"damage_type": &"poison", "expected": &"thorn_spike"},
		{"damage_type": &"unknown", "expected": &"arcane_bolt"},
	]
	for entry: Dictionary in checks:
		var dt: StringName = entry["damage_type"]
		var expected: StringName = entry["expected"]
		var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"", dt)
		var profile: StringName = payload.get("profile_id", &"")
		if profile != expected:
			_fail(
				(
					'payload_for_id(&"", &"%s") profile_id expected &"%s", got &"%s"'
					% [dt, expected, profile]
				)
			)
			return
	print("  fallback damage type mappings correct")


func _check_ref_counted_payload_immutable() -> void:
	# Ensure payload_for_id returns a fresh duplicate, not a shared reference
	var first: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")
	var second: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")
	first["test_mutated"] = true
	if second.get("test_mutated", false):
		_fail("payload_for_id should return independent dictionary copies")
		return
	print("  payload immutability verified")
