class_name PixelTacticalLayer
extends Node2D
## Draws pixel-native tactical overlays and renderer-local transient effects.
##
## Hybrid uses this layer only for pixel projectiles, impacts, and boss spawn
## effects. Full Pixel additionally renders targeting, hazards, telegraphs,
## intents, secret-wall hints, arena treatment, and atmosphere without glyphs.

# === Constants ===
const CELL_BURST_DURATION: float = 0.55
const BOSS_SPAWN_DURATION: float = 0.90
const REDUCED_DURATION_SCALE: float = 0.58
const REDUCED_MAX_ALPHA: float = 0.20
const ATMOSPHERE_FRAME_SECONDS: float = 0.12
const REDUCED_ATMOSPHERE_FRAME_SECONDS: float = 0.36

# === Private Variables ===
var _layout: RefCounted
var _state: RefCounted
var _render_profile: StringName = &"hybrid"
var _reduced_vfx_enabled: bool = false
var _projectile_trails: Array[Dictionary] = []
var _cell_bursts: Array[Dictionary] = []
var _boss_spawn_effects: Array[Dictionary] = []
var _last_overlay_revision: int = -1
var _last_visibility_revision: int = -1
var _last_environment_revision: int = -1
var _event_count: int = 0
var _atmosphere_time: float = 0.0
var _atmosphere_draw_elapsed: float = 0.0
var _debug_counts: Dictionary = {}


# === Public Methods ===
func configure(layout: RefCounted) -> Error:
	_layout = layout
	if _layout == null:
		return ERR_INVALID_PARAMETER
	return OK


func set_render_profile(profile: StringName) -> void:
	if _render_profile == profile:
		return
	_render_profile = profile
	_update_debug_counts()
	_update_processing_state()
	queue_redraw()


func present(state: RefCounted, force_redraw: bool = false) -> void:
	_state = state
	if _state == null:
		_update_debug_counts()
		_update_processing_state()
		queue_redraw()
		return
	var overlay_revision: int = int(_state.get("overlay_revision"))
	var visibility_revision: int = int(_state.get("visibility_revision"))
	var environment_revision: int = int(_state.get("environment_revision"))
	if (
		force_redraw
		or overlay_revision != _last_overlay_revision
		or visibility_revision != _last_visibility_revision
		or environment_revision != _last_environment_revision
	):
		_update_debug_counts()
		queue_redraw()
	_last_overlay_revision = overlay_revision
	_last_visibility_revision = visibility_revision
	_last_environment_revision = environment_revision
	_update_processing_state()


func set_reduced_vfx(enabled: bool) -> void:
	if _reduced_vfx_enabled == enabled:
		return
	_reduced_vfx_enabled = enabled
	if enabled:
		_apply_reduced_vfx_to_active_effects()
	_update_processing_state()
	queue_redraw()


func play_event(event: Dictionary) -> void:
	match StringName(event.get("type", &"")):
		&"projectile_trail":
			_add_projectile_trail(_dictionary_or(event.get("payload", {})))
		&"cell_burst":
			_add_cell_burst(_dictionary_or(event.get("payload", {})))
		&"boss_spawn_intro":
			_add_boss_spawn_effect(_dictionary_or(event.get("payload", {})))
		&"clear_projectile_trails":
			_projectile_trails.clear()
			queue_redraw()
		&"clear_boss_spawn_effects":
			_boss_spawn_effects.clear()
			queue_redraw()
		_:
			return
	_event_count += 1
	_update_debug_counts()
	_update_processing_state()


func reset_transients() -> void:
	_projectile_trails.clear()
	_cell_bursts.clear()
	_boss_spawn_effects.clear()
	_update_debug_counts()
	_update_processing_state()
	queue_redraw()


func clear() -> void:
	_state = null
	reset_transients()
	_last_overlay_revision = -1
	_last_visibility_revision = -1
	_last_environment_revision = -1
	queue_redraw()


func get_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = _debug_counts.duplicate()
	snapshot["profile"] = _render_profile
	snapshot["native_tactical"] = _is_full_pixel()
	snapshot["projectile_count"] = _projectile_trails.size()
	snapshot["burst_count"] = _cell_bursts.size()
	snapshot["boss_spawn_count"] = _boss_spawn_effects.size()
	snapshot["event_count"] = _event_count
	snapshot["reduced_vfx"] = _reduced_vfx_enabled
	snapshot["projectile_cell_count"] = (
		_array_or(_projectile_trails[0].get("cells", [])).size()
		if not _projectile_trails.is_empty()
		else 0
	)
	snapshot["projectile_duration"] = (
		float(_projectile_trails[0].get("duration", 0.0))
		if not _projectile_trails.is_empty()
		else 0.0
	)
	snapshot["burst_duration"] = (
		float(_cell_bursts[0].get("duration", 0.0)) if not _cell_bursts.is_empty() else 0.0
	)
	return snapshot


# === Lifecycle Methods ===
func _process(delta: float) -> void:
	_atmosphere_time += delta
	var changed: bool = false
	changed = _advance_effects(_projectile_trails, delta, 0.22) or changed
	changed = _advance_effects(_cell_bursts, delta, CELL_BURST_DURATION) or changed
	changed = _advance_effects(_boss_spawn_effects, delta, BOSS_SPAWN_DURATION) or changed
	if _full_pixel_atmosphere_active():
		_atmosphere_draw_elapsed += delta
		var interval: float = (
			REDUCED_ATMOSPHERE_FRAME_SECONDS if _reduced_vfx_enabled else ATMOSPHERE_FRAME_SECONDS
		)
		if _atmosphere_draw_elapsed >= interval:
			_atmosphere_draw_elapsed = 0.0
			changed = true
	if changed:
		_update_debug_counts()
		queue_redraw()
	_update_processing_state()


func _draw() -> void:
	if _layout == null or _state == null:
		return
	if _is_full_pixel():
		_draw_atmosphere()
		_draw_boss_room()
		_draw_secret_walls()
		_draw_targeting()
		_draw_boss_hazards()
		_draw_boss_telegraphs()
		_draw_enemy_intents()
	_draw_projectile_trails()
	_draw_cell_bursts()
	_draw_boss_spawn_effects()


# === Private Methods ===
func _draw_atmosphere() -> void:
	if not _full_pixel_atmosphere_active():
		return
	var profile: Dictionary = _state.get("atmosphere_profile")
	var shimmer_color: Color = _color_or(
		profile.get("shimmer_color", Color.TRANSPARENT), Color.TRANSPARENT
	)
	var intensity: float = float(profile.get("ambient_intensity", 0.10))
	if _reduced_vfx_enabled:
		intensity *= 0.35
	var visible_cells: Dictionary = _state.get("visible_cells")
	var phase: int = int(floor(_atmosphere_time * float(profile.get("ambient_speed", 0.8))))
	for cell_value: Variant in visible_cells:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not _cell_in_view(cell) or _cell_hash(cell, 83 + phase) % 19 != 0:
			continue
		var rect: Rect2 = _cell_rect(cell, 0.0)
		var x_offset: float = float(2 + _cell_hash(cell, 97 + phase) % 12)
		var y_offset: float = float(2 + _cell_hash(cell, 109 + phase) % 12)
		var color: Color = shimmer_color
		color.a = clampf(maxf(color.a, intensity * 0.32), 0.0, 0.18)
		draw_rect(Rect2(rect.position + Vector2(x_offset, y_offset), Vector2(1, 1)), color)


func _draw_boss_room() -> void:
	var room_cells: Dictionary = _state.get("boss_room_cells")
	if room_cells.is_empty():
		return
	var locked: bool = bool(_state.get("boss_room_locked"))
	var tint: Color = _color_or(_state.get("boss_room_tint_color"), Color.TRANSPARENT)
	if tint.a <= 0.0:
		tint = Color(1.0, 0.18, 0.16, 0.10) if locked else Color(1.0, 0.72, 0.22, 0.06)
	var visible_cells: Dictionary = _state.get("visible_cells")
	var explored_cells: Dictionary = _state.get("explored_cells")
	for cell_value: Variant in room_cells:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not _cell_in_view(cell) or not (visible_cells.has(cell) or explored_cells.has(cell)):
			continue
		var rect: Rect2 = _cell_rect(cell, 1.0)
		draw_rect(rect, tint)
		if locked and _cell_hash(cell, 97) % 11 == 0:
			var motif_color: Color = Color(1.0, 0.72, 0.22, 0.34)
			draw_rect(Rect2(rect.get_center() - Vector2(1, 1), Vector2(2, 2)), motif_color)


func _draw_secret_walls() -> void:
	var walls: Dictionary = _state.get("secret_walls")
	var revealed: Dictionary = _state.get("revealed_secret_walls")
	var explored_cells: Dictionary = _state.get("explored_cells")
	var visible_cells: Dictionary = _state.get("visible_cells")
	var base_color: Color = _color_or(_state.get("secret_wall_hint_color"), Color.WHITE)
	for cell_value: Variant in revealed:
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not walls.has(cell) or not explored_cells.has(cell) or not _cell_in_view(cell):
			continue
		var color: Color = base_color if visible_cells.has(cell) else base_color.darkened(0.58)
		var rect: Rect2 = _cell_rect(cell, 2.0)
		var start: Vector2 = rect.position + Vector2(3, 0)
		var points: PackedVector2Array = PackedVector2Array(
			[start, start + Vector2(-2, 3), start + Vector2(1, 6), start + Vector2(-1, 9)]
		)
		draw_polyline(points, color, 1.0, false)


func _draw_targeting() -> void:
	var visible_cells: Dictionary = _state.get("visible_cells")
	var explored_cells: Dictionary = _state.get("explored_cells")
	for cell_value: Variant in _state.get("target_range_cells"):
		if (
			cell_value is Vector2i
			and _tactical_cell_visible(cell_value, visible_cells, explored_cells)
		):
			_draw_range_cell(cell_value)
	for cell_value: Variant in _state.get("target_area_cells"):
		if (
			cell_value is Vector2i
			and _tactical_cell_visible(cell_value, visible_cells, explored_cells)
		):
			_draw_area_cell(cell_value)
	if not bool(_state.get("targeting_active")):
		return
	var cursor: Vector2i = _state.get("target_cursor")
	if visible_cells.has(cursor) and _cell_in_view(cursor):
		_draw_cursor(cursor)


func _draw_range_cell(cell: Vector2i) -> void:
	var rect: Rect2 = _cell_rect(cell, 2.0)
	var color: Color = Color(0.82, 0.88, 0.32, 0.72)
	draw_rect(rect, Color(0.42, 0.45, 0.20, 0.07))
	draw_rect(Rect2(rect.get_center().round() - Vector2.ONE, Vector2(2, 2)), color)


func _draw_area_cell(cell: Vector2i) -> void:
	var rect: Rect2 = _cell_rect(cell, 2.0)
	var color: Color = Color(1.0, 0.52, 0.16, 0.88)
	draw_rect(rect, Color(1.0, 0.24, 0.08, 0.22))
	var center: Vector2 = rect.get_center().round()
	draw_line(center - Vector2(3, 0), center + Vector2(3, 0), color, 1.0, false)
	draw_line(center - Vector2(0, 3), center + Vector2(0, 3), color, 1.0, false)


func _draw_cursor(cell: Vector2i) -> void:
	var rect: Rect2 = _cell_rect(cell, 1.0)
	draw_rect(rect, Color(1.0, 0.72, 0.08, 0.12))
	_draw_rect_corners(rect, Color(1.0, 0.90, 0.22, 1.0), 5.0)


func _draw_boss_hazards() -> void:
	var visible_cells: Dictionary = _state.get("visible_cells")
	for cell_value: Variant in _state.get("boss_hazards"):
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not visible_cells.has(cell) or not _cell_in_view(cell):
			continue
		var payload_value: Variant = _state.get("boss_hazards")[cell]
		if payload_value is not Dictionary:
			continue
		var payload: Dictionary = payload_value
		var fill: Color = _color_or(payload.get("fill_color"), Color(0.0, 0.3, 1.0, 0.16))
		var border: Color = _color_or(payload.get("border_color"), Color(0.0, 0.5, 1.0, 0.62))
		var color: Color = _color_or(payload.get("color"), Color(0.6, 0.8, 1.0, 1.0))
		var rect: Rect2 = _cell_rect(cell, 1.0)
		draw_rect(rect, fill)
		draw_rect(rect, border, false, 1.0)
		var center: Vector2 = rect.get_center().round()
		for offset: float in [-3.0, 0.0, 3.0]:
			draw_line(center + Vector2(-4, offset), center + Vector2(4, offset), color, 1.0, false)


func _draw_boss_telegraphs() -> void:
	var visible_cells: Dictionary = _state.get("visible_cells")
	for cell_value: Variant in _state.get("boss_telegraphs"):
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not visible_cells.has(cell) or not _cell_in_view(cell):
			continue
		var payload_value: Variant = _state.get("boss_telegraphs")[cell]
		if payload_value is not Dictionary:
			continue
		var payload: Dictionary = payload_value
		var fill: Color = _color_or(payload.get("fill_color"), Color(1.0, 0.16, 0.10, 0.24))
		var border: Color = _color_or(payload.get("border_color"), Color(1.0, 0.52, 0.18, 0.88))
		var color: Color = _color_or(payload.get("color"), Color(1.0, 0.64, 0.20, 1.0))
		var rect: Rect2 = _cell_rect(cell, 1.0)
		draw_rect(rect, fill)
		draw_rect(rect, border, false, 1.0)
		var center: Vector2 = rect.get_center().round()
		draw_line(center + Vector2(0, -4), center + Vector2(0, 2), color, 2.0, false)
		draw_rect(Rect2(center + Vector2(-1, 4), Vector2(2, 2)), color)


func _draw_enemy_intents() -> void:
	var visible_cells: Dictionary = _state.get("visible_cells")
	for cell_value: Variant in _state.get("enemy_intents"):
		if not (cell_value is Vector2i):
			continue
		var cell: Vector2i = cell_value
		if not visible_cells.has(cell) or not _cell_in_view(cell):
			continue
		var intent: StringName = StringName(_state.get("enemy_intents")[cell])
		_draw_intent_icon(cell, intent)


func _draw_intent_icon(cell: Vector2i, intent: StringName) -> void:
	var cell_rect: Rect2 = _cell_rect(cell, 0.0)
	var rect: Rect2 = Rect2(cell_rect.end - Vector2(7, 15), Vector2(6, 6))
	draw_rect(rect, Color(0.015, 0.02, 0.035, 0.88))
	var center: Vector2 = rect.get_center().round()
	var color: Color = Color(0.66, 0.62, 0.48)
	match intent:
		&"melee", &"boss_attack":
			color = Color(1.0, 0.20, 0.30)
			draw_line(center + Vector2(0, -2), center + Vector2(0, 1), color, 1.0, false)
			draw_rect(Rect2(center + Vector2(0, 2), Vector2(1, 1)), color)
		&"ranged":
			color = Color(1.0, 0.68, 0.22)
			draw_line(center + Vector2(-2, 0), center + Vector2(2, 0), color, 1.0, false)
			draw_line(center + Vector2(0, -2), center + Vector2(2, 0), color, 1.0, false)
			draw_line(center + Vector2(0, 2), center + Vector2(2, 0), color, 1.0, false)
		&"fireball":
			color = Color(0.88, 0.48, 1.0)
			_draw_diamond(center, 2.0, color)
		&"summon":
			color = Color(0.86, 0.82, 0.70)
			draw_line(center + Vector2(-2, 0), center + Vector2(2, 0), color, 1.0, false)
			draw_line(center + Vector2(0, -2), center + Vector2(0, 2), color, 1.0, false)
		&"sleeping":
			color = Color(0.48, 0.52, 0.58)
			draw_line(center + Vector2(-2, -2), center + Vector2(2, -2), color, 1.0, false)
			draw_line(center + Vector2(2, -2), center + Vector2(-2, 2), color, 1.0, false)
			draw_line(center + Vector2(-2, 2), center + Vector2(2, 2), color, 1.0, false)
		&"boss_windup":
			color = Color(1.0, 0.62, 0.18)
			draw_colored_polygon(
				PackedVector2Array(
					[center + Vector2(0, -2), center + Vector2(-2, 2), center + Vector2(2, 2)]
				),
				color,
			)
		_:
			color = Color(0.66, 0.62, 0.48)
			draw_rect(Rect2(center + Vector2(-2, -1), Vector2(5, 3)), color, false, 1.0)
			draw_rect(Rect2(center, Vector2(1, 1)), color)


func _draw_projectile_trails() -> void:
	var explored_cells: Dictionary = _state.get("explored_cells")
	var visible_cells: Dictionary = _state.get("visible_cells")
	for trail: Dictionary in _projectile_trails:
		var cells: Array = _array_or(trail.get("cells", []))
		if cells.is_empty():
			continue
		var duration: float = maxf(0.05, float(trail.get("duration", 0.22)))
		var progress: float = clampf(float(trail.get("age", 0.0)) / duration, 0.0, 1.0)
		var fade: float = 1.0 - progress
		var respect_visibility: bool = bool(trail.get("respect_visibility", true))
		var previous_center: Vector2
		var has_previous: bool = false
		for index: int in range(cells.size()):
			var cell_value: Variant = cells[index]
			if not (cell_value is Vector2i):
				continue
			var cell: Vector2i = cell_value
			if (
				not explored_cells.has(cell)
				or (respect_visibility and not visible_cells.has(cell))
				or not _cell_in_view(cell)
			):
				continue
			var center: Vector2 = _cell_center(cell).round()
			var color: Color = _projectile_color(trail, index == cells.size() - 1, progress)
			color.a *= fade
			if has_previous:
				draw_line(previous_center, center, color, 2.0, false)
			if index == cells.size() - 1:
				_draw_diamond(center, 3.0, color)
			else:
				draw_rect(Rect2(center - Vector2(1, 1), Vector2(2, 2)), color)
			previous_center = center
			has_previous = true


func _draw_cell_bursts() -> void:
	var visible_cells: Dictionary = _state.get("visible_cells")
	var explored_cells: Dictionary = _state.get("explored_cells")
	for burst: Dictionary in _cell_bursts:
		var cell: Vector2i = burst.get("cell", Vector2i.ZERO)
		if not (visible_cells.has(cell) or explored_cells.has(cell)) or not _cell_in_view(cell):
			continue
		var duration: float = maxf(0.05, float(burst.get("duration", CELL_BURST_DURATION)))
		var progress: float = clampf(float(burst.get("age", 0.0)) / duration, 0.0, 1.0)
		var color: Color = _color_or(burst.get("color"), Color.WHITE)
		color.a *= 1.0 - progress
		var center: Vector2 = _cell_center(cell).round() - Vector2(0, roundf(progress * 6.0))
		_draw_diamond(center, maxf(1.0, 4.0 - progress * 2.0), color)
		var rect: Rect2 = _cell_rect(cell, 2.0)
		draw_rect(rect, Color(color.r, color.g, color.b, color.a * 0.18))


func _draw_boss_spawn_effects() -> void:
	var visible_cells: Dictionary = _state.get("visible_cells")
	for effect: Dictionary in _boss_spawn_effects:
		var duration: float = maxf(0.05, float(effect.get("duration", BOSS_SPAWN_DURATION)))
		var progress: float = clampf(float(effect.get("age", 0.0)) / duration, 0.0, 1.0)
		var pulse: float = sin(progress * PI)
		var color: Color = _color_or(effect.get("color"), Color(1.0, 0.72, 0.22, 1.0))
		for cell_value: Variant in _array_or(effect.get("occupied_cells", [])):
			if not (cell_value is Vector2i):
				continue
			var cell: Vector2i = cell_value
			if not visible_cells.has(cell) or not _cell_in_view(cell):
				continue
			var rect: Rect2 = _cell_rect(cell, 1.0)
			draw_rect(rect, Color(color.r, color.g, color.b, 0.08 + pulse * 0.22))
			_draw_rect_corners(rect, Color(color.r, color.g, color.b, 0.35 + pulse * 0.55), 4.0)


func _add_projectile_trail(payload: Dictionary) -> void:
	var trail: Dictionary = payload.duplicate(true)
	trail["age"] = 0.0
	trail["duration"] = maxf(0.05, float(trail.get("duration", 0.22)))
	if _reduced_vfx_enabled:
		_apply_reduced_vfx_to_trail(trail)
	_projectile_trails.append(trail)
	queue_redraw()


func _add_cell_burst(payload: Dictionary) -> void:
	var burst: Dictionary = payload.duplicate(true)
	burst["age"] = 0.0
	burst["duration"] = maxf(0.05, float(burst.get("duration", CELL_BURST_DURATION)))
	if _reduced_vfx_enabled:
		_apply_reduced_vfx_to_burst(burst)
	_cell_bursts.append(burst)
	queue_redraw()


func _add_boss_spawn_effect(payload: Dictionary) -> void:
	var effect: Dictionary = payload.duplicate(true)
	effect["age"] = 0.0
	effect["duration"] = maxf(0.05, float(effect.get("duration", BOSS_SPAWN_DURATION)))
	if effect.get("occupied_cells", []).is_empty():
		effect["occupied_cells"] = [effect.get("cell", Vector2i.ZERO)]
	if _reduced_vfx_enabled:
		effect["duration"] = maxf(0.08, float(effect["duration"]) * REDUCED_DURATION_SCALE)
		var color: Color = _color_or(effect.get("color"), Color.WHITE)
		effect["color"] = _cap_alpha(color, REDUCED_MAX_ALPHA)
	_boss_spawn_effects.append(effect)
	queue_redraw()


func _advance_effects(effects: Array[Dictionary], delta: float, fallback_duration: float) -> bool:
	var changed: bool = false
	for index: int in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[index]
		effect["age"] = float(effect.get("age", 0.0)) + delta
		if float(effect["age"]) >= float(effect.get("duration", fallback_duration)):
			effects.remove_at(index)
		else:
			effects[index] = effect
		changed = true
	return changed


func _apply_reduced_vfx_to_active_effects() -> void:
	for trail: Dictionary in _projectile_trails:
		_apply_reduced_vfx_to_trail(trail)
	for burst: Dictionary in _cell_bursts:
		_apply_reduced_vfx_to_burst(burst)
	for effect: Dictionary in _boss_spawn_effects:
		effect["duration"] = maxf(
			0.08, float(effect.get("duration", 0.90)) * REDUCED_DURATION_SCALE
		)
		effect["color"] = _cap_alpha(_color_or(effect.get("color"), Color.WHITE), REDUCED_MAX_ALPHA)


func _apply_reduced_vfx_to_trail(trail: Dictionary) -> void:
	var cells: Array = _array_or(trail.get("cells", []))
	if cells.size() > 2:
		trail["cells"] = [cells.front(), cells.back()]
	trail["duration"] = maxf(0.08, float(trail.get("duration", 0.22)) * REDUCED_DURATION_SCALE)
	for key: String in ["color", "trail_color", "impact_color", "fill_color", "border_color"]:
		trail[key] = _cap_alpha(_color_or(trail.get(key), Color.WHITE), REDUCED_MAX_ALPHA)
	trail["rarity_shimmer_enabled"] = false


func _apply_reduced_vfx_to_burst(burst: Dictionary) -> void:
	burst["duration"] = maxf(
		0.08, float(burst.get("duration", CELL_BURST_DURATION)) * REDUCED_DURATION_SCALE
	)
	burst["color"] = _cap_alpha(_color_or(burst.get("color"), Color.WHITE), REDUCED_MAX_ALPHA)


func _update_debug_counts() -> void:
	_debug_counts = {
		"target_range_count": 0,
		"target_area_count": 0,
		"target_cursor_visible": false,
		"telegraph_count": 0,
		"hazard_count": 0,
		"intent_count": 0,
		"secret_wall_count": 0,
		"boss_room_count": 0,
	}
	if _state == null or _layout == null or not _is_full_pixel():
		return
	var visible_cells: Dictionary = _state.get("visible_cells")
	var explored_cells: Dictionary = _state.get("explored_cells")
	_debug_counts["target_range_count"] = _count_tactical_cells(
		_state.get("target_range_cells"), visible_cells, explored_cells
	)
	_debug_counts["target_area_count"] = _count_tactical_cells(
		_state.get("target_area_cells"), visible_cells, explored_cells
	)
	var cursor: Vector2i = _state.get("target_cursor")
	_debug_counts["target_cursor_visible"] = (
		bool(_state.get("targeting_active")) and visible_cells.has(cursor) and _cell_in_view(cursor)
	)
	_debug_counts["telegraph_count"] = _count_visible_cells(
		_state.get("boss_telegraphs"), visible_cells
	)
	_debug_counts["hazard_count"] = _count_visible_cells(_state.get("boss_hazards"), visible_cells)
	_debug_counts["intent_count"] = _count_visible_cells(_state.get("enemy_intents"), visible_cells)
	_debug_counts["boss_room_count"] = _count_explored_cells(
		_state.get("boss_room_cells"), visible_cells, explored_cells
	)
	var secret_cells: Dictionary = {}
	for cell_value: Variant in _state.get("revealed_secret_walls"):
		if cell_value is Vector2i and _state.get("secret_walls").has(cell_value):
			secret_cells[cell_value] = true
	_debug_counts["secret_wall_count"] = _count_explored_cells(
		secret_cells, visible_cells, explored_cells
	)


func _count_tactical_cells(
	cells: Dictionary, visible_cells: Dictionary, explored_cells: Dictionary
) -> int:
	var count: int = 0
	for cell_value: Variant in cells:
		if (
			cell_value is Vector2i
			and _tactical_cell_visible(cell_value, visible_cells, explored_cells)
		):
			count += 1
	return count


func _count_visible_cells(cells: Dictionary, visible_cells: Dictionary) -> int:
	var count: int = 0
	for cell_value: Variant in cells:
		if cell_value is Vector2i and visible_cells.has(cell_value) and _cell_in_view(cell_value):
			count += 1
	return count


func _count_explored_cells(
	cells: Dictionary, visible_cells: Dictionary, explored_cells: Dictionary
) -> int:
	var count: int = 0
	for cell_value: Variant in cells:
		if (
			cell_value is Vector2i
			and (visible_cells.has(cell_value) or explored_cells.has(cell_value))
			and _cell_in_view(cell_value)
		):
			count += 1
	return count


func _update_processing_state() -> void:
	set_process(
		(
			not _projectile_trails.is_empty()
			or not _cell_bursts.is_empty()
			or not _boss_spawn_effects.is_empty()
			or _full_pixel_atmosphere_active()
		)
	)


func _full_pixel_atmosphere_active() -> bool:
	return (
		_is_full_pixel()
		and _state != null
		and bool(_state.get("atmosphere_enabled"))
		and not Dictionary(_state.get("atmosphere_profile")).is_empty()
	)


func _is_full_pixel() -> bool:
	return _render_profile == &"pixel"


func _tactical_cell_visible(
	cell: Vector2i, visible_cells: Dictionary, explored_cells: Dictionary
) -> bool:
	return visible_cells.has(cell) and explored_cells.has(cell) and _cell_in_view(cell)


func _cell_in_view(cell: Vector2i) -> bool:
	return _layout != null and bool(_layout.call(&"is_cell_in_view", cell))


func _cell_rect(cell: Vector2i, inset: float) -> Rect2:
	return _layout.call(&"cell_rect", cell, inset)


func _cell_center(cell: Vector2i) -> Vector2:
	return _layout.call(&"cell_center_to_local", cell)


func _draw_rect_corners(rect: Rect2, color: Color, length: float) -> void:
	var top_left: Vector2 = rect.position
	var top_right: Vector2 = Vector2(rect.end.x - 1.0, rect.position.y)
	var bottom_left: Vector2 = Vector2(rect.position.x, rect.end.y - 1.0)
	var bottom_right: Vector2 = rect.end - Vector2.ONE
	for points: PackedVector2Array in [
		PackedVector2Array(
			[top_left + Vector2(length, 0), top_left, top_left + Vector2(0, length)]
		),
		PackedVector2Array(
			[top_right - Vector2(length, 0), top_right, top_right + Vector2(0, length)]
		),
		PackedVector2Array(
			[bottom_left + Vector2(0, -length), bottom_left, bottom_left + Vector2(length, 0)]
		),
		PackedVector2Array(
			[bottom_right + Vector2(0, -length), bottom_right, bottom_right - Vector2(length, 0)]
		),
	]:
		draw_polyline(points, color, 1.0, false)


func _draw_diamond(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				center + Vector2(0, -radius),
				center + Vector2(radius, 0),
				center + Vector2(0, radius),
				center + Vector2(-radius, 0),
			]
		),
		color,
	)


func _projectile_color(trail: Dictionary, impact: bool, progress: float) -> Color:
	var key: String = "impact_color" if impact and progress > 0.55 else "color"
	if not impact:
		key = "trail_color"
	var color: Color = _color_or(trail.get(key), Color.WHITE)
	if bool(trail.get("rarity_shimmer_enabled", false)):
		var accent: Color = _color_or(trail.get("rarity_accent_color"), color)
		var phase: float = sin(
			float(trail.get("age", 0.0)) * TAU * float(trail.get("rarity_shimmer_speed", 0.0))
		)
		var amount: float = clampf(
			(phase * 0.5 + 0.5) * float(trail.get("rarity_shimmer_intensity", 0.0)),
			0.0,
			1.0,
		)
		color = color.lerp(Color(accent.r, accent.g, accent.b, color.a), amount)
	return color


func _cap_alpha(color: Color, maximum: float) -> Color:
	return Color(color.r, color.g, color.b, minf(color.a, maximum))


func _color_or(value: Variant, fallback: Color) -> Color:
	return value if value is Color else fallback


func _dictionary_or(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _array_or(value: Variant) -> Array:
	return value if value is Array else []


func _cell_hash(cell: Vector2i, salt: int) -> int:
	return absi(cell.x * 73856093 + cell.y * 19349663 + salt * 83492791)
