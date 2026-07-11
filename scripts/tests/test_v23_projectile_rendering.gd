## V23.0.0 Projectile rendering tests.
##
## Contracts:
##   1. play_projectile_trail creates one active trail with all stored cells.
##   2. has_active_projectile_trails() returns true immediately after play.
##   3. After duration expires, trail clears and has_active returns false.
##   4. Reduced VFX trims new and active trails to 2 cells, disables shimmer,
##      caps alpha, and shortens duration.
##   5. clear_projectile_trails() removes trails and stops processing when idle.
##   6. Boss hazard vfx_payload presentation state is accepted through set_boss_hazards.
##   7. Actor cell cache tracks alive actors and moved signals.
##
## Run:
##   /usr/local/bin/godot --headless --path . --script \
##      res://scripts/tests/test_v23_projectile_rendering.gd
extends SceneTree

const ProjectileSystemScript = preload("res://scripts/systems/projectile_system.gd")
const MapViewScript = preload("res://scripts/ui/map_view.gd")
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")


class TestActor:
	extends RefCounted

	signal moved(new_position: Vector2i)

	var grid_position: Vector2i
	var _alive: bool = true

	func _init(initial_position: Vector2i) -> void:
		grid_position = initial_position

	func is_alive() -> bool:
		return _alive

	func set_alive(alive: bool) -> void:
		_alive = alive

	func move_to(new_position: Vector2i) -> void:
		grid_position = new_position
		moved.emit(new_position)


var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_trail_play_and_lifecycle()
	if _failed:
		return
	_check_reduced_vfx_trims_cells()
	if _failed:
		return
	await _check_reduced_vfx_reduces_active_trail()
	if _failed:
		return
	_check_clear_projectile_trails()
	if _failed:
		return
	_check_boss_hazard_vfx_payload()
	if _failed:
		return
	await _check_actor_cell_cache_updates()
	if _failed:
		return

	print("V23 projectile rendering checks passed")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _make_map_view() -> Node:
	var map_view: Node = MapViewScript.new()
	root.add_child(map_view)
	map_view.set_atmosphere_enabled(false)
	(
		map_view
		. configure_map(
			[
				[
					DungeonDataScript.TileType.FLOOR,
					DungeonDataScript.TileType.FLOOR,
					DungeonDataScript.TileType.FLOOR,
					DungeonDataScript.TileType.FLOOR
				],
				[
					DungeonDataScript.TileType.FLOOR,
					DungeonDataScript.TileType.FLOOR,
					DungeonDataScript.TileType.FLOOR,
					DungeonDataScript.TileType.FLOOR
				],
			]
		)
	)
	(
		map_view
		. set_visibility(
			{
				Vector2i(0, 0): true,
				Vector2i(1, 0): true,
				Vector2i(2, 0): true,
				Vector2i(3, 0): true,
				Vector2i(0, 1): true,
				Vector2i(1, 1): true,
				Vector2i(2, 1): true,
				Vector2i(3, 1): true,
			},
			{
				Vector2i(0, 0): true,
				Vector2i(1, 0): true,
				Vector2i(2, 0): true,
				Vector2i(3, 0): true,
				Vector2i(0, 1): true,
				Vector2i(1, 1): true,
				Vector2i(2, 1): true,
				Vector2i(3, 1): true,
			}
		)
	)
	return map_view


func _check_trail_play_and_lifecycle() -> void:
	var map_view: Node = _make_map_view()
	await process_frame

	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")

	map_view.play_projectile_trail(cells, payload)
	await process_frame

	if not map_view.has_active_projectile_trails():
		_fail("has_active_projectile_trails() should be true after play_projectile_trail")
		map_view.queue_free()
		return

	var trail_count: int = map_view._projectile_trails.size()
	if trail_count != 1:
		_fail("Expected 1 active trail after play, got %d" % trail_count)
		map_view.queue_free()
		return

	var trail: Dictionary = map_view._projectile_trails[0]
	var stored_cells: Array = trail.get("cells", [])
	if stored_cells.size() != 3:
		_fail(
			(
				"Expected 3 stored cells in full mode, got %d (cells: %s)"
				% [stored_cells.size(), str(stored_cells)]
			)
		)
		map_view.queue_free()
		return

	# Advance time past the duration
	var duration: float = float(payload.get("duration_seconds", 0.22))
	map_view._process(duration + 0.1)

	if map_view.has_active_projectile_trails():
		_fail("Trail should have expired after duration %.3f" % duration)
		map_view.queue_free()
		return

	map_view.queue_free()
	await process_frame
	print("  trail play and lifecycle: 3 cells, aging, expiry")


func _check_reduced_vfx_trims_cells() -> void:
	var map_view: Node = _make_map_view()
	map_view.set_reduced_vfx_enabled(true)
	await process_frame

	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")
	var original_duration: float = 0.50
	payload["duration_seconds"] = original_duration
	payload["rarity_shimmer_enabled"] = true

	map_view.play_projectile_trail(cells, payload)
	await process_frame

	if not map_view.has_active_projectile_trails():
		_fail("Reduced VFX: should still create a trail")
		map_view.queue_free()
		return

	var trail: Dictionary = map_view._projectile_trails[0]
	var stored_cells: Array = trail.get("cells", [])
	if stored_cells.size() != 2:
		_fail(
			(
				"Reduced VFX: expected 2 cells (front+back) for 4-cell input, got %d (cells: %s)"
				% [stored_cells.size(), str(stored_cells)]
			)
		)
		map_view.queue_free()
		return

	# Verify first and last cell are preserved
	if stored_cells[0] != Vector2i(0, 0) or stored_cells[1] != Vector2i(3, 0):
		_fail("Reduced VFX: expected cells [0,0] and [3,0], got %s" % str(stored_cells))
		map_view.queue_free()
		return

	# Verify shimmer disabled, alphas capped, and duration shortened.
	if trail.get("rarity_shimmer_enabled", true) != false:
		_fail("Reduced VFX: shimmer should be disabled")
		map_view.queue_free()
		return
	var reduced_duration: float = float(trail.get("duration", 0.0))
	if reduced_duration >= original_duration:
		_fail(
			(
				"Reduced VFX: duration %.3f should be shorter than %.3f"
				% [reduced_duration, original_duration]
			)
		)
		map_view.queue_free()
		return
	if not _float_close(float(trail.get("duration_seconds", 0.0)), reduced_duration):
		_fail("Reduced VFX: duration_seconds should mirror reduced duration")
		map_view.queue_free()
		return
	if not _assert_trail_alpha_cap(trail, "Reduced VFX"):
		map_view.queue_free()
		return

	map_view.queue_free()
	await process_frame
	print("  reduced VFX: new trails trim, shimmer/alpha capped, duration shortened")


func _check_reduced_vfx_reduces_active_trail() -> void:
	var map_view: Node = _make_map_view()
	await process_frame

	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"arcane_bolt")
	payload["duration_seconds"] = 0.50
	payload["rarity_shimmer_enabled"] = true

	map_view.play_projectile_trail(cells, payload)
	await process_frame

	if not map_view.has_active_projectile_trails():
		_fail("Reduced VFX toggle: trail should exist before toggle")
		map_view.queue_free()
		return
	var full_trail: Dictionary = map_view._projectile_trails[0]
	var full_cells: Array = full_trail.get("cells", [])
	if full_cells.size() != 4:
		_fail("Reduced VFX toggle: expected 4 full cells before toggle, got %d" % full_cells.size())
		map_view.queue_free()
		return
	if not bool(full_trail.get("rarity_shimmer_enabled", false)):
		_fail("Reduced VFX toggle: test trail should start with shimmer enabled")
		map_view.queue_free()
		return
	var full_duration: float = float(full_trail.get("duration", 0.0))

	map_view.set_reduced_vfx_enabled(true)

	if not map_view.has_active_projectile_trails():
		_fail("Reduced VFX toggle: active trail should remain active immediately after toggle")
		map_view.queue_free()
		return
	if not map_view.is_processing():
		_fail("Reduced VFX toggle: active trail should keep MapView processing")
		map_view.queue_free()
		return
	var reduced_trail: Dictionary = map_view._projectile_trails[0]
	var reduced_cells: Array = reduced_trail.get("cells", [])
	if reduced_cells.size() != 2:
		_fail(
			"Reduced VFX toggle: active trail should trim to 2 cells, got %d" % reduced_cells.size()
		)
		map_view.queue_free()
		return
	if reduced_cells[0] != Vector2i(0, 0) or reduced_cells[1] != Vector2i(3, 0):
		_fail("Reduced VFX toggle: active trail should keep first and last cells")
		map_view.queue_free()
		return
	if reduced_trail.get("rarity_shimmer_enabled", true) != false:
		_fail("Reduced VFX toggle: active trail shimmer should be disabled immediately")
		map_view.queue_free()
		return
	var reduced_duration: float = float(reduced_trail.get("duration", 0.0))
	if reduced_duration >= full_duration:
		_fail(
			(
				"Reduced VFX toggle: active trail duration %.3f should be shorter than %.3f"
				% [reduced_duration, full_duration]
			)
		)
		map_view.queue_free()
		return
	if not _assert_trail_alpha_cap(reduced_trail, "Reduced VFX toggle"):
		map_view.queue_free()
		return

	map_view._process(reduced_duration + 0.01)
	if map_view.has_active_projectile_trails():
		_fail("Reduced VFX toggle: active trail should expire after shortened duration")
		map_view.queue_free()
		return
	if map_view.is_processing():
		_fail("Reduced VFX toggle: processing should stop after shortened trail expires")
		map_view.queue_free()
		return

	map_view.queue_free()
	await process_frame
	print("  reduced VFX: active trails immediately trim, cap alpha, and expire sooner")


func _check_clear_projectile_trails() -> void:
	var map_view: Node = _make_map_view()
	await process_frame

	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var payload: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")

	map_view.play_projectile_trail(cells, payload)
	await process_frame

	if not map_view.has_active_projectile_trails():
		_fail("Trail should exist before clear")
		map_view.queue_free()
		return

	map_view.clear_projectile_trails()
	await process_frame

	if map_view.has_active_projectile_trails():
		_fail("Trail should be gone after clear_projectile_trails")
		map_view.queue_free()
		return

	# No other animations active -> processing should stop
	if map_view.is_processing():
		_fail("Processing should stop when no trails/animations/atmosphere active")
		map_view.queue_free()
		return

	map_view.queue_free()
	await process_frame
	print("  clear_projectile_trails: trails removed, processing stopped")


func _check_boss_hazard_vfx_payload() -> void:
	var map_view: Node = _make_map_view()
	await process_frame

	# Simulate a boss hazard payload with vfx_payload
	var vfx: Dictionary = ProjectileSystemScript.payload_for_id(&"blink_pulse_hazard")
	var hazard_payload: Dictionary = {
		Vector2i(0, 0):
		{
			"glyph": "⊙",
			"color": Color(0.82, 0.95, 1.0, 1.0),
			"fill_color": Color(0.18, 0.46, 1.0, 0.12),
			"border_color": Color(0.72, 0.90, 1.0, 0.30),
			"vfx_payload": vfx,
		}
	}
	map_view.set_boss_hazards(hazard_payload)
	await process_frame

	var stored_hazards: Dictionary = map_view._boss_hazards
	if stored_hazards.is_empty():
		_fail("set_boss_hazards should store hazards")
		map_view.queue_free()
		return

	var stored_vfx: Dictionary = stored_hazards.get(Vector2i(0, 0), {}).get("vfx_payload", {})
	if stored_vfx.is_empty():
		_fail("Boss hazard should store vfx_payload")
		map_view.queue_free()
		return

	if stored_vfx.get("profile_id", &"") != &"blink_pulse_hazard":
		_fail(
			(
				'vfx_payload profile_id expected &"blink_pulse_hazard", got %s'
				% str(stored_vfx.get("profile_id", &""))
			)
		)
		map_view.queue_free()
		return

	if str(stored_vfx.get("glyph", "")).is_empty():
		_fail("vfx_payload glyph should be non-empty")
		map_view.queue_free()
		return

	# Verify deep-duplicate: mutating the original should not affect stored
	vfx["profile_id"] = &"mutated"
	var post_mutate: StringName = (
		map_view._boss_hazards.get(Vector2i(0, 0), {}).get("vfx_payload", {}).get("profile_id", &"")
	)
	if post_mutate == &"mutated":
		_fail("set_boss_hazards should deep-duplicate vfx_payload")
		map_view.queue_free()
		return

	map_view.queue_free()
	await process_frame
	print("  boss hazard vfx_payload accepted and deep-duplicated")


func _check_actor_cell_cache_updates() -> void:
	var map_view: Node = _make_map_view()
	await process_frame

	var actor: TestActor = TestActor.new(Vector2i(1, 0))
	map_view.set_actors([actor])
	if map_view._actor_at(Vector2i(1, 0)) != actor:
		_fail("Actor cache should contain alive actor at initial cell")
		map_view.queue_free()
		return

	actor.move_to(Vector2i(2, 0))
	if map_view._actor_cells.has(Vector2i(1, 0)):
		_fail("Actor cache should erase the old cell after moved signal")
		map_view.queue_free()
		return
	if map_view._actor_at(Vector2i(1, 0)) != null:
		_fail("Actor lookup should clear the old cell after moved signal")
		map_view.queue_free()
		return
	if map_view._actor_at(Vector2i(2, 0)) != actor:
		_fail("Actor cache should move actor to new cell after moved signal")
		map_view.queue_free()
		return

	actor.set_alive(false)
	map_view.set_actors([actor])
	if map_view._actor_cells.has(Vector2i(2, 0)):
		_fail("Actor cache should erase dead actors when rebuilt")
		map_view.queue_free()
		return
	if map_view._actor_at(Vector2i(2, 0)) != null:
		_fail("Actor lookup should omit dead actors when rebuilt")
		map_view.queue_free()
		return
	actor.move_to(Vector2i(3, 0))
	if map_view._actor_cells.has(Vector2i(3, 0)):
		_fail("Actor lookup should not repopulate dead actors from moved signal")
		map_view.queue_free()
		return
	if map_view._actor_at(Vector2i(3, 0)) != null:
		_fail("Actor lookup should not repopulate dead actors from moved signal")
		map_view.queue_free()
		return

	map_view.queue_free()
	await process_frame
	print("  actor cache: alive, moved, and dead actors update cached cells")


func _assert_trail_alpha_cap(trail: Dictionary, prefix: String) -> bool:
	var alpha_fields: Array[String] = [
		"color", "trail_color", "impact_color", "fill_color", "border_color"
	]
	for field: String in alpha_fields:
		var color: Color = trail.get(field, Color.WHITE)
		if color.a > 0.081:
			_fail("%s: %s alpha %.4f should be <= 0.08" % [prefix, field, color.a])
			return false
	return true


func _float_close(left: float, right: float) -> bool:
	return absf(left - right) <= 0.0001
