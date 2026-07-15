class_name PixelEffectPool
extends Node2D
## Fixed-capacity particle pool for renderer-local pixel-map effects.
##
## Desktop uses GPUParticles2D. Web and headless runs use the matching
## CPUParticles2D fallback. Core draw-command effects remain authoritative for
## readability, so particle availability never changes gameplay or telegraphs.

# === Constants ===
const PARTICLE_TEXTURE: Texture2D = preload("res://assets/pixel_art/source/effects/particle.svg")
const EMBER_TEXTURE: Texture2D = preload("res://assets/pixel_art/source/effects/ember.svg")
const ARCANE_TEXTURE: Texture2D = preload("res://assets/pixel_art/source/effects/arcane.svg")
const POISON_TEXTURE: Texture2D = preload("res://assets/pixel_art/source/effects/poison.svg")
const FROST_TEXTURE: Texture2D = preload("res://assets/pixel_art/source/effects/frost.svg")
const POOL_SIZE: int = 12
const NORMAL_MIN_LIFETIME: float = 0.16
const REDUCED_LIFETIME_SCALE: float = 0.52
const REDUCED_ALPHA_CAP: float = 0.42
const RELEASE_MARGIN_SECONDS: float = 0.08
const EVENT_PROFILES: Dictionary = {
	&"projectile_trail":
	{"amount": 4, "lifetime": 0.18, "speed": 13.0, "gravity": 0.0, "scale": 0.55},
	&"cell_burst": {"amount": 10, "lifetime": 0.34, "speed": 27.0, "gravity": 30.0, "scale": 0.80},
	&"attack": {"amount": 3, "lifetime": 0.16, "speed": 12.0, "gravity": 0.0, "scale": 0.50},
	&"cast": {"amount": 7, "lifetime": 0.30, "speed": 21.0, "gravity": -8.0, "scale": 0.70},
	&"hurt": {"amount": 6, "lifetime": 0.24, "speed": 20.0, "gravity": 24.0, "scale": 0.65},
	&"death": {"amount": 12, "lifetime": 0.44, "speed": 28.0, "gravity": 34.0, "scale": 0.82},
	&"boss_spawn_intro":
	{"amount": 18, "lifetime": 0.58, "speed": 36.0, "gravity": -10.0, "scale": 0.95},
}

# === Private Variables ===
var _layout: RefCounted
var _state: RefCounted
var _emitters: Array[Node2D] = []
var _gpu_materials: Array[ParticleProcessMaterial] = []
var _active_slots: PackedByteArray = PackedByteArray()
var _remaining_seconds: PackedFloat32Array = PackedFloat32Array()
var _slot_generations: PackedInt64Array = PackedInt64Array()
var _slot_cells: Array[Vector2i] = []
var _alpha_gradient: Gradient
var _alpha_gradient_texture: GradientTexture1D
var _uses_cpu_particles: bool = false
var _reduced_vfx_enabled: bool = false
var _event_count: int = 0
var _reuse_count: int = 0
var _visibility_rejection_count: int = 0
var _generation: int = 0
var _last_event_type: StringName = &""
var _last_particle_amount: int = 0
var _last_lifetime: float = 0.0
var _last_effect_cell: Vector2i = Vector2i.ZERO
var _last_texture_id: StringName = &""


# === Lifecycle Methods ===
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)


func _process(delta: float) -> void:
	for index: int in range(_emitters.size()):
		if _active_slots[index] == 0:
			continue
		_remaining_seconds[index] -= delta
		if _remaining_seconds[index] <= 0.0:
			_release_slot(index)
	_update_processing_state()


# === Public Methods ===
func configure(layout: RefCounted, force_cpu_fallback: bool = false) -> Error:
	if layout == null:
		return ERR_INVALID_PARAMETER
	_layout = layout
	_uses_cpu_particles = (
		force_cpu_fallback or OS.has_feature("web") or DisplayServer.get_name() == "headless"
	)
	_initialize_fade_resources()
	_initialize_pool()
	return OK if _emitters.size() == POOL_SIZE else ERR_CANT_CREATE


func present(state: RefCounted) -> void:
	_state = state
	_prune_hidden_effects()


func set_reduced_vfx(enabled: bool) -> void:
	if _reduced_vfx_enabled == enabled:
		return
	_reduced_vfx_enabled = enabled
	if enabled:
		reset_transients()


func play_event(event: Dictionary) -> bool:
	var event_type: StringName = StringName(event.get("type", &""))
	var profile_id: StringName = _profile_id_for_event(event)
	if not EVENT_PROFILES.has(profile_id):
		return false
	var effect_cell: Vector2i = _effect_cell_for_event(event)
	if not _effect_cell_visible(effect_cell):
		_visibility_rejection_count += 1
		return false
	var slot_index: int = _acquire_slot()
	var profile: Dictionary = EVENT_PROFILES[profile_id]
	var color: Color = _color_for_event(event, profile_id)
	_configure_slot(slot_index, effect_cell, profile, color, event, profile_id)
	_event_count += 1
	_last_event_type = event_type
	_last_effect_cell = effect_cell
	return true


func reset_transients() -> void:
	for index: int in range(_emitters.size()):
		_release_slot(index)
	_update_processing_state()


func clear() -> void:
	_state = null
	reset_transients()


func get_debug_snapshot() -> Dictionary:
	return {
		"configured": _emitters.size() == POOL_SIZE,
		"backend": &"cpu" if _uses_cpu_particles else &"gpu",
		"pool_size": _emitters.size(),
		"active_count": _active_count(),
		"event_count": _event_count,
		"reuse_count": _reuse_count,
		"visibility_rejection_count": _visibility_rejection_count,
		"reduced_vfx": _reduced_vfx_enabled,
		"last_event_type": _last_event_type,
		"last_particle_amount": _last_particle_amount,
		"last_lifetime": _last_lifetime,
		"last_effect_cell": _last_effect_cell,
		"last_texture_id": _last_texture_id,
		"child_count": get_child_count(),
	}


# === Private Methods ===
func _initialize_fade_resources() -> void:
	_alpha_gradient = Gradient.new()
	_alpha_gradient.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	_alpha_gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	_alpha_gradient_texture = GradientTexture1D.new()
	_alpha_gradient_texture.gradient = _alpha_gradient


func _initialize_pool() -> void:
	if not _emitters.is_empty():
		return
	_active_slots.resize(POOL_SIZE)
	_remaining_seconds.resize(POOL_SIZE)
	_slot_generations.resize(POOL_SIZE)
	for index: int in range(POOL_SIZE):
		var emitter: Node2D = (
			_create_cpu_emitter(index) if _uses_cpu_particles else _create_gpu_emitter(index)
		)
		add_child(emitter)
		_emitters.append(emitter)
		_slot_cells.append(Vector2i.ZERO)
		_release_slot(index)


func _create_cpu_emitter(index: int) -> CPUParticles2D:
	var emitter: CPUParticles2D = CPUParticles2D.new()
	emitter.name = "CpuEffect%02d" % index
	emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emitter.texture = PARTICLE_TEXTURE
	emitter.emitting = false
	emitter.one_shot = true
	emitter.local_coords = true
	emitter.explosiveness = 1.0
	emitter.randomness = 0.18
	emitter.fixed_fps = 30
	emitter.fract_delta = false
	emitter.use_fixed_seed = true
	emitter.color_ramp = _alpha_gradient
	return emitter


func _create_gpu_emitter(index: int) -> GPUParticles2D:
	var emitter: GPUParticles2D = GPUParticles2D.new()
	emitter.name = "GpuEffect%02d" % index
	emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emitter.texture = PARTICLE_TEXTURE
	emitter.emitting = false
	emitter.one_shot = true
	emitter.local_coords = true
	emitter.explosiveness = 1.0
	emitter.randomness = 0.18
	emitter.fixed_fps = 30
	emitter.fract_delta = false
	emitter.use_fixed_seed = true
	var process_material: ParticleProcessMaterial = ParticleProcessMaterial.new()
	process_material.color_ramp = _alpha_gradient_texture
	emitter.process_material = process_material
	_gpu_materials.append(process_material)
	return emitter


func _configure_slot(
	index: int,
	cell: Vector2i,
	profile: Dictionary,
	source_color: Color,
	event: Dictionary,
	profile_id: StringName
) -> void:
	var amount: int = int(profile.get("amount", 6))
	var lifetime: float = maxf(NORMAL_MIN_LIFETIME, float(profile.get("lifetime", 0.3)))
	var speed: float = float(profile.get("speed", 20.0))
	var gravity: float = float(profile.get("gravity", 20.0))
	var particle_scale: float = float(profile.get("scale", 0.7))
	var color: Color = source_color
	if _reduced_vfx_enabled:
		amount = mini(3, amount)
		lifetime = maxf(0.08, lifetime * REDUCED_LIFETIME_SCALE)
		speed *= 0.55
		gravity *= 0.55
		color.a = minf(color.a, REDUCED_ALPHA_CAP)
	# Select effect texture from event/payload identifiers; default neutral.
	var effect_texture: Texture2D = _select_texture_for_event(event, profile_id)
	var emitter: Node2D = _emitters[index]
	emitter.position = Vector2(_layout.call(&"cell_center_to_local", cell)).round()
	emitter.visible = true
	var seed_value: int = 1009 + _generation * 31 + index * 131
	if emitter is CPUParticles2D:
		_configure_cpu(
			emitter as CPUParticles2D,
			amount,
			lifetime,
			speed,
			gravity,
			particle_scale,
			color,
			effect_texture,
			seed_value
		)
	else:
		_configure_gpu(
			emitter as GPUParticles2D,
			index,
			amount,
			lifetime,
			speed,
			gravity,
			particle_scale,
			color,
			effect_texture,
			seed_value
		)
	_generation += 1
	_active_slots[index] = 1
	_remaining_seconds[index] = lifetime + RELEASE_MARGIN_SECONDS
	_slot_generations[index] = _generation
	_slot_cells[index] = cell
	_last_particle_amount = amount
	_last_lifetime = lifetime
	_update_processing_state()


func _configure_cpu(
	emitter: CPUParticles2D,
	amount: int,
	lifetime: float,
	speed: float,
	gravity: float,
	particle_scale: float,
	color: Color,
	effect_texture: Texture2D,
	seed_value: int,
) -> void:
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.direction = Vector2.UP
	emitter.spread = 180.0
	emitter.initial_velocity_min = speed * 0.62
	emitter.initial_velocity_max = speed
	emitter.gravity = Vector2(0.0, gravity)
	emitter.scale_amount_min = particle_scale * 0.72
	emitter.scale_amount_max = particle_scale
	emitter.color = color
	emitter.texture = effect_texture
	emitter.seed = seed_value
	emitter.emitting = true
	emitter.restart()


func _configure_gpu(
	emitter: GPUParticles2D,
	index: int,
	amount: int,
	lifetime: float,
	speed: float,
	gravity: float,
	particle_scale: float,
	color: Color,
	effect_texture: Texture2D,
	seed_value: int,
) -> void:
	var process_material: ParticleProcessMaterial = _gpu_materials[index]
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = speed * 0.62
	process_material.initial_velocity_max = speed
	process_material.gravity = Vector3(0.0, gravity, 0.0)
	process_material.scale_min = particle_scale * 0.72
	process_material.scale_max = particle_scale
	process_material.color = color
	emitter.texture = effect_texture
	emitter.amount = amount
	emitter.lifetime = lifetime
	emitter.seed = seed_value
	emitter.emitting = true
	emitter.restart()


func _profile_id_for_event(event: Dictionary) -> StringName:
	var event_type: StringName = StringName(event.get("type", &""))
	if event_type == &"actor_animation":
		return StringName(event.get("animation", &""))
	return event_type


func _effect_cell_for_event(event: Dictionary) -> Vector2i:
	var payload: Dictionary = _payload_for_event(event)
	var occupied_cells: Array = _array_or(payload.get("occupied_cells", []))
	for cell_value: Variant in occupied_cells:
		if cell_value is Vector2i and _effect_cell_visible(cell_value):
			return cell_value
	var trail_cells: Array = _array_or(payload.get("cells", []))
	for index: int in range(trail_cells.size() - 1, -1, -1):
		if trail_cells[index] is Vector2i:
			return trail_cells[index]
	var payload_cell: Variant = payload.get("cell")
	if payload_cell is Vector2i:
		return payload_cell
	var event_cell: Variant = event.get("cell")
	return event_cell if event_cell is Vector2i else Vector2i(-9999, -9999)


func _color_for_event(event: Dictionary, profile_id: StringName) -> Color:
	var payload: Dictionary = _payload_for_event(event)
	for key: StringName in [&"impact_color", &"color", &"rarity_color"]:
		var color_value: Variant = payload.get(key)
		if color_value is Color:
			return color_value
	match profile_id:
		&"attack":
			return Color(1.0, 0.82, 0.36, 0.86)
		&"cast":
			return Color(0.68, 0.48, 1.0, 0.90)
		&"hurt":
			return Color(1.0, 0.28, 0.34, 0.92)
		&"death":
			return Color(0.82, 0.20, 0.32, 0.92)
	return Color.WHITE


## Selects an effect texture based on event/payload identifiers.
## Selector precedence:
## 1. payload.element     — most specific semantic field
## 2. payload.effect_type — effect subtype
## 3. payload.trap_type   — trap-specific field
## 4. payload.animation   — animation name (may contain element keywords)
## 5. payload.profile_id  — semantic projectile or hazard profile
## 6. profile_id          — event type fallback (e.g., "cast" → arcane)
## 7. default             — neutral particle.svg
## Unknown or missing identifiers default to neutral.
func _select_texture_for_event(event: Dictionary, profile_id: StringName) -> Texture2D:
	var payload: Dictionary = _payload_for_event(event)
	for key: StringName in [&"element", &"effect_type", &"trap_type", &"animation", &"profile_id"]:
		var value: StringName = StringName(payload.get(key, &""))
		if value != &"":
			var tex: Texture2D = _texture_from_identifier(value)
			if tex != null:
				_last_texture_id = value
				return tex
	# Fallback to profile_id (event type)
	var profile_tex: Texture2D = _texture_from_identifier(profile_id)
	if profile_tex != null:
		_last_texture_id = profile_id
		return profile_tex
	_last_texture_id = &"neutral"
	return PARTICLE_TEXTURE


static func _texture_from_identifier(id: StringName) -> Texture2D:
	match id:
		&"fire", &"flame", &"ember", &"effect/ember":
			return EMBER_TEXTURE
		&"ember_bolt", &"fire_bolt", &"fireball", &"ember_arrow":
			return EMBER_TEXTURE
		&"starfall_star", &"ash_breath", &"maw_quake", &"molten_cracks":
			return EMBER_TEXTURE
		&"magic", &"arcane", &"shadow", &"void", &"cast", &"effect/arcane":
			return ARCANE_TEXTURE
		&"arcane_bolt", &"stormglass_bolt", &"void_bolt", &"astral_star":
			return ARCANE_TEXTURE
		&"ascendant_star", &"lightning_bolt", &"magic_missile", &"sleep_mote":
			return ARCANE_TEXTURE
		&"shadow_bolt", &"observer_gaze", &"blink_pulse", &"mirror_ray":
			return ARCANE_TEXTURE
		&"prism_fracture", &"arcane_spark", &"chain_lightning":
			return ARCANE_TEXTURE
		&"blink_pulse_hazard", &"mirror_shards":
			return ARCANE_TEXTURE
		&"poison", &"acid", &"effect/poison":
			return POISON_TEXTURE
		&"thorn_spike", &"thorn_lance", &"spore_burst", &"spore_hazard":
			return POISON_TEXTURE
		&"frost", &"ice", &"cold", &"effect/frost":
			return FROST_TEXTURE
		&"frost_shard", &"tidal_bolt", &"undertow", &"frost_nova":
			return FROST_TEXTURE
		&"undertow_hazard":
			return FROST_TEXTURE
		_:
			return null


func _payload_for_event(event: Dictionary) -> Dictionary:
	var payload: Variant = event.get("payload", event)
	return payload if payload is Dictionary else event


func _effect_cell_visible(cell: Vector2i) -> bool:
	if _layout == null or _state == null:
		return false
	var visible_cells: Dictionary = _state.get("visible_cells")
	return visible_cells.has(cell) and bool(_layout.call(&"is_cell_in_view", cell))


func _acquire_slot() -> int:
	for index: int in range(_emitters.size()):
		if _active_slots[index] == 0:
			return index
	var oldest_index: int = 0
	var oldest_generation: int = _slot_generations[0]
	for index: int in range(1, _slot_generations.size()):
		if _slot_generations[index] < oldest_generation:
			oldest_generation = _slot_generations[index]
			oldest_index = index
	_reuse_count += 1
	_release_slot(oldest_index)
	return oldest_index


func _release_slot(index: int) -> void:
	if index < 0 or index >= _emitters.size():
		return
	var emitter: Node2D = _emitters[index]
	if emitter is CPUParticles2D:
		(emitter as CPUParticles2D).emitting = false
	elif emitter is GPUParticles2D:
		(emitter as GPUParticles2D).emitting = false
	emitter.visible = false
	_active_slots[index] = 0
	_remaining_seconds[index] = 0.0


func _prune_hidden_effects() -> void:
	if _state == null:
		reset_transients()
		return
	for index: int in range(_emitters.size()):
		if _active_slots[index] != 0 and not _effect_cell_visible(_slot_cells[index]):
			_release_slot(index)
	_update_processing_state()


func _active_count() -> int:
	var count: int = 0
	for active_value: int in _active_slots:
		if active_value != 0:
			count += 1
	return count


func _update_processing_state() -> void:
	set_process(_active_count() > 0)


func _array_or(value: Variant) -> Array:
	return value if value is Array else []
