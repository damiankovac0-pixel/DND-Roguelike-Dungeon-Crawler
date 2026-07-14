class_name PixelActorView
extends Node2D
## Cosmetic animated view for one authoritative actor snapshot.
##
## Grid occupancy, visibility, life state, and outcomes arrive from shared
## presentation data. Tweens and animation playback never feed back into play.

# === Signals ===
signal death_finished(actor_id: int)

# === Constants ===
const DEFAULT_MOVE_SECONDS: float = 0.10
const ACTOR_FEEDBACK_SHADER: Shader = preload("res://assets/shaders/pixel_actor_feedback.gdshader")
const ATTACK_FEEDBACK_SECONDS: float = 0.12
const CAST_FEEDBACK_SECONDS: float = 0.18
const HURT_FEEDBACK_SECONDS: float = 0.15
const DEATH_FEEDBACK_SECONDS: float = 0.24
const BOSS_DEATH_FEEDBACK_SECONDS: float = 0.48
const BOSS_INTRO_FEEDBACK_SECONDS: float = 0.42
const ANIMATION_PRIORITY: Dictionary = {
	&"idle": 0,
	&"move": 1,
	&"attack": 2,
	&"cast": 2,
	&"hurt": 3,
	&"death": 4,
}

# === Public Variables ===
var actor_id: int = 0
var visual_id: StringName = &""

# === Private Variables ===
var _layout: RefCounted
var _snapshot: Dictionary = {}
var _cell: Vector2i = Vector2i.ZERO
var _footprint_cells: Array[Vector2i] = []
var _visible_footprint_cells: Array[Vector2i] = []
var _target_position: Vector2 = Vector2.ZERO
var _current_animation: StringName = &"idle"
var _move_tween: Tween
var _initialized: bool = false
var _was_visible: bool = false
var _is_boss: bool = false
var _death_pending: bool = false
var _reduced_vfx_enabled: bool = false
var _coalesced_event_count: int = 0
var _event_counts: Dictionary = {}
var _tint: Color = Color.WHITE
var _feedback_material: ShaderMaterial
var _feedback_tween: Tween
var _feedback_active: bool = false
var _death_animation_finished: bool = false
var _feedback_event_count: int = 0
var _boss_intro_count: int = 0

# === Onready ===
@onready var visual_root: Node2D = $VisualRoot
@onready var sprite: AnimatedSprite2D = $VisualRoot/AnimatedSprite2D


# === Lifecycle Methods ===
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.animation_finished.connect(_on_animation_finished)
	_feedback_material = ShaderMaterial.new()
	_feedback_material.shader = ACTOR_FEEDBACK_SHADER
	sprite.material = _feedback_material
	_reset_feedback_visuals()


func _draw() -> void:
	if not _is_boss or _layout == null:
		return
	for cell: Vector2i in _visible_footprint_cells:
		var cell_rect: Rect2 = _layout.call(&"cell_rect", cell)
		cell_rect.position -= position
		draw_rect(cell_rect.grow(-1.0), Color(_tint.r, _tint.g, _tint.b, 0.12))
		draw_rect(
			cell_rect.grow(-1.0),
			Color(_tint.r, _tint.g, _tint.b, 0.42),
			false,
			1.0,
		)


# === Public Methods ===
func initialize_view(
	snapshot: Dictionary,
	frames: SpriteFrames,
	tint: Color,
	layout: RefCounted,
	reduced_vfx_enabled: bool
) -> void:
	actor_id = int(snapshot.get("id", 0))
	visual_id = snapshot.get("visual_id", &"actor/enemy")
	_layout = layout
	_tint = tint
	_reduced_vfx_enabled = reduced_vfx_enabled
	sprite.sprite_frames = frames
	sprite.modulate = tint
	_reset_feedback_visuals()
	_play_animation(&"idle", true)


func apply_snapshot(
	snapshot: Dictionary,
	footprint_cells: Array[Vector2i],
	visible_cells: Dictionary,
	animate_move: bool
) -> void:
	var previous_cell: Vector2i = _cell
	var was_initialized: bool = _initialized
	_snapshot = snapshot
	_cell = snapshot.get("cell", Vector2i.ZERO)
	_is_boss = bool(snapshot.get("is_boss", false))
	_footprint_cells = footprint_cells.duplicate()
	if _footprint_cells.is_empty():
		_footprint_cells.append(_cell)
	_apply_facing(snapshot.get("facing", &"down"))
	_update_visible_footprint(visible_cells)
	_target_position = _calculate_target_position()
	var moved: bool = was_initialized and previous_cell != _cell
	var can_tween: bool = (
		moved
		and animate_move
		and not _reduced_vfx_enabled
		and _was_visible
		and not _visible_footprint_cells.is_empty()
	)
	if can_tween:
		_start_move_tween(_target_position)
	else:
		_stop_move_tween()
		position = _target_position.round()
	_initialized = true
	var alive: bool = bool(snapshot.get("alive", false))
	if alive:
		_death_pending = false
		visible = not _visible_footprint_cells.is_empty()
		_update_sprite_visibility()
	elif was_initialized and not _visible_footprint_cells.is_empty():
		visible = true
		_update_sprite_visibility(not _is_boss)
		play_cosmetic(&"death")
	else:
		visible = false
	_was_visible = visible
	queue_redraw()


func play_cosmetic(animation: StringName) -> void:
	if not ANIMATION_PRIORITY.has(animation) or sprite.sprite_frames == null:
		return
	if not sprite.sprite_frames.has_animation(animation):
		return
	if _current_animation == &"death":
		_coalesced_event_count += 1
		return
	if animation == _current_animation and sprite.is_playing():
		_coalesced_event_count += 1
		return
	var current_priority: int = int(ANIMATION_PRIORITY.get(_current_animation, 0))
	var requested_priority: int = int(ANIMATION_PRIORITY[animation])
	if requested_priority < current_priority and sprite.is_playing():
		_coalesced_event_count += 1
		return
	_event_counts[animation] = int(_event_counts.get(animation, 0)) + 1
	_death_pending = animation == &"death"
	if _death_pending:
		_death_animation_finished = false
	_play_animation(animation, true)
	_start_actor_feedback(animation)


func play_spawn_intro() -> void:
	if not _is_boss or not visible:
		return
	_boss_intro_count += 1
	_stop_feedback_tween()
	_reset_feedback_visuals()
	var duration: float = BOSS_INTRO_FEEDBACK_SECONDS
	var flash_amount: float = 0.72
	if _reduced_vfx_enabled:
		duration = 0.08
		flash_amount = 0.24
	else:
		visual_root.scale = Vector2(0.72, 0.72)
	_set_flash_color(Color(1.0, 0.74, 0.30, 1.0))
	_set_flash_amount(flash_amount)
	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.set_trans(Tween.TRANS_BACK)
	_feedback_tween.set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(visual_root, "scale", Vector2.ONE, duration)
	_feedback_tween.tween_method(_set_flash_amount, flash_amount, 0.0, duration)
	_feedback_active = true
	_feedback_tween.finished.connect(_on_feedback_finished)


func set_reduced_vfx(enabled: bool) -> void:
	_reduced_vfx_enabled = enabled
	if enabled and _move_tween != null and _move_tween.is_valid():
		_stop_move_tween()
		position = _target_position.round()
		if _current_animation == &"move":
			_play_animation(&"idle", true)
	if enabled:
		_stop_feedback_tween()
		_reset_feedback_visuals()
		if _death_pending and _death_animation_finished:
			death_finished.emit(actor_id)


func reset_transients() -> bool:
	_stop_move_tween()
	_stop_feedback_tween()
	_reset_feedback_visuals()
	position = _target_position.round()
	if _death_pending:
		visible = false
		return true
	_play_animation(&"idle", true)
	return false


func prepare_for_removal() -> void:
	_stop_move_tween()
	_stop_feedback_tween()


func get_debug_snapshot() -> Dictionary:
	return {
		"actor_id": actor_id,
		"visual_id": visual_id,
		"kind": _snapshot.get("kind", &"enemy"),
		"cell": _cell,
		"alive": bool(_snapshot.get("alive", false)),
		"is_boss": _is_boss,
		"tint": _tint,
		"facing": _snapshot.get("facing", &"down"),
		"flip_h": sprite.flip_h,
		"footprint_cells": _footprint_cells.duplicate(),
		"visible_footprint_cells": _visible_footprint_cells.duplicate(),
		"visible": visible,
		"sprite_visible": sprite.visible,
		"position": position,
		"target_position": _target_position,
		"animation": _current_animation,
		"event_counts": _event_counts.duplicate(),
		"coalesced_event_count": _coalesced_event_count,
		"feedback_material": _feedback_material != null,
		"feedback_active": _feedback_active,
		"feedback_event_count": _feedback_event_count,
		"boss_intro_count": _boss_intro_count,
		"flash_amount": _shader_float(&"flash_amount"),
		"desaturate_amount": _shader_float(&"desaturate_amount"),
		"alpha_multiplier": _shader_float(&"alpha_multiplier"),
		"visual_position": visual_root.position,
		"visual_scale": visual_root.scale,
	}


# === Private Methods ===
func _start_actor_feedback(animation: StringName) -> void:
	_stop_feedback_tween()
	_reset_feedback_visuals()
	_feedback_event_count += 1
	var duration: float = ATTACK_FEEDBACK_SECONDS
	var flash_color: Color = Color(1.0, 0.82, 0.36, 1.0)
	var flash_amount: float = 0.38
	var start_position: Vector2 = _attack_feedback_offset()
	var start_scale: Vector2 = Vector2(1.08, 0.94)
	var end_scale: Vector2 = Vector2.ONE
	var end_desaturation: float = 0.0
	var end_alpha: float = 1.0
	match animation:
		&"cast":
			duration = CAST_FEEDBACK_SECONDS
			flash_color = Color(0.68, 0.48, 1.0, 1.0)
			flash_amount = 0.62
			start_position = Vector2.ZERO
			start_scale = Vector2(0.92, 0.92)
		&"hurt":
			duration = HURT_FEEDBACK_SECONDS
			flash_color = Color.WHITE
			flash_amount = 1.0
			var recoil_direction: float = -1.0 if actor_id % 2 == 0 else 1.0
			start_position = Vector2(2.0 * recoil_direction, 0.0)
			start_scale = Vector2(1.10, 0.90)
		&"death":
			duration = BOSS_DEATH_FEEDBACK_SECONDS if _is_boss else DEATH_FEEDBACK_SECONDS
			flash_color = Color(0.92, 0.24, 0.34, 1.0)
			flash_amount = 0.86
			start_position = Vector2.ZERO
			start_scale = Vector2.ONE
			end_scale = Vector2(0.82, 0.82)
			end_desaturation = 0.86
			end_alpha = 0.10
		_:
			pass
	if _reduced_vfx_enabled:
		duration = minf(duration * 0.52, 0.10)
		flash_amount *= 0.34
		start_position = Vector2.ZERO
		start_scale = Vector2.ONE
		if animation == &"death":
			end_scale = Vector2.ONE
			end_desaturation = 0.34
			end_alpha = 0.42
	visual_root.position = start_position.round()
	visual_root.scale = start_scale
	_set_flash_color(flash_color)
	_set_flash_amount(flash_amount)
	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.set_trans(Tween.TRANS_QUAD)
	_feedback_tween.set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(visual_root, "position", Vector2.ZERO, duration)
	_feedback_tween.tween_property(visual_root, "scale", end_scale, duration)
	_feedback_tween.tween_method(_set_flash_amount, flash_amount, 0.0, duration)
	_feedback_tween.tween_method(_set_desaturate_amount, 0.0, end_desaturation, duration)
	_feedback_tween.tween_method(_set_alpha_multiplier, 1.0, end_alpha, duration)
	_feedback_active = true
	_feedback_tween.finished.connect(_on_feedback_finished)


func _attack_feedback_offset() -> Vector2:
	match StringName(_snapshot.get("facing", &"down")):
		&"left":
			return Vector2(-2.0, 0.0)
		&"right":
			return Vector2(2.0, 0.0)
		&"up":
			return Vector2(0.0, -2.0)
	return Vector2(0.0, 2.0)


func _stop_feedback_tween() -> void:
	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = null
	_feedback_active = false


func _reset_feedback_visuals() -> void:
	if not is_instance_valid(visual_root):
		return
	visual_root.position = Vector2.ZERO
	visual_root.scale = Vector2.ONE
	_set_flash_amount(0.0)
	_set_desaturate_amount(0.0)
	_set_alpha_multiplier(1.0)


func _set_flash_color(color: Color) -> void:
	if _feedback_material != null:
		_feedback_material.set_shader_parameter(&"flash_color", color)


func _set_flash_amount(amount: float) -> void:
	if _feedback_material != null:
		_feedback_material.set_shader_parameter(&"flash_amount", amount)


func _set_desaturate_amount(amount: float) -> void:
	if _feedback_material != null:
		_feedback_material.set_shader_parameter(&"desaturate_amount", amount)


func _set_alpha_multiplier(amount: float) -> void:
	if _feedback_material != null:
		_feedback_material.set_shader_parameter(&"alpha_multiplier", amount)


func _shader_float(parameter: StringName) -> float:
	if _feedback_material == null:
		return 0.0
	return float(_feedback_material.get_shader_parameter(parameter))


func _update_visible_footprint(visible_cells: Dictionary) -> void:
	_visible_footprint_cells.clear()
	for cell: Vector2i in _footprint_cells:
		if visible_cells.has(cell) and bool(_layout.call(&"is_cell_in_view", cell)):
			_visible_footprint_cells.append(cell)


func _calculate_target_position() -> Vector2:
	if not _is_boss:
		return _layout.call(&"cell_center_to_local", _cell)
	var min_cell: Vector2i = _footprint_cells[0]
	var max_cell: Vector2i = _footprint_cells[0]
	for cell: Vector2i in _footprint_cells:
		min_cell.x = min(min_cell.x, cell.x)
		min_cell.y = min(min_cell.y, cell.y)
		max_cell.x = max(max_cell.x, cell.x)
		max_cell.y = max(max_cell.y, cell.y)
	var top_left: Vector2 = _layout.call(&"cell_to_local", min_cell)
	var cell_size: Vector2 = Vector2(_layout.call(&"get_cell_size"))
	var footprint_size: Vector2 = Vector2(max_cell - min_cell + Vector2i.ONE) * cell_size
	return top_left + footprint_size * 0.5


func _update_sprite_visibility(force_visible: bool = false) -> void:
	if force_visible:
		sprite.visible = true
		return
	if not _is_boss:
		sprite.visible = not _visible_footprint_cells.is_empty()
		return
	sprite.visible = (
		not _footprint_cells.is_empty()
		and _visible_footprint_cells.size() == _footprint_cells.size()
	)


func _apply_facing(facing_value: Variant) -> void:
	var facing: StringName = StringName(facing_value)
	if facing == &"left":
		sprite.flip_h = true
	elif facing == &"right":
		sprite.flip_h = false


func _start_move_tween(target: Vector2) -> void:
	_stop_move_tween()
	if int(ANIMATION_PRIORITY.get(_current_animation, 0)) <= 1:
		_play_animation(&"move", true)
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_QUAD)
	_move_tween.set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "position", target.round(), DEFAULT_MOVE_SECONDS)
	_move_tween.finished.connect(_on_move_finished)


func _stop_move_tween() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = null


func _play_animation(animation: StringName, restart: bool) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(animation):
		return
	_current_animation = animation
	sprite.play(animation)
	if restart:
		sprite.frame = 0
		sprite.frame_progress = 0.0


func _on_move_finished() -> void:
	_move_tween = null
	position = _target_position.round()
	if _current_animation == &"move":
		_play_animation(&"idle", true)


func _on_feedback_finished() -> void:
	_feedback_tween = null
	_feedback_active = false
	if _death_pending:
		if _death_animation_finished:
			death_finished.emit(actor_id)
		return
	_reset_feedback_visuals()


func _on_animation_finished() -> void:
	if _current_animation == &"death":
		_death_animation_finished = true
		if not _feedback_active:
			death_finished.emit(actor_id)
	elif _current_animation != &"idle" and _current_animation != &"move":
		_play_animation(&"idle", true)
