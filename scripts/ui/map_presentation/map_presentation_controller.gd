class_name MapPresentationController
extends RefCounted
## Selects a renderer behind MapView, caches the latest presentation state, and
## replays that state whenever a renderer becomes active.

# === Signals ===
signal mode_changed(requested_mode: StringName, effective_mode: StringName)

# === Constants ===
const MapRenderModeScript: GDScript = preload(
	"res://scripts/ui/map_presentation/map_render_mode.gd"
)

# === Private Variables ===
var _requested_mode: StringName = MapRenderModeScript.ASCII
var _effective_mode: StringName = MapRenderModeScript.ASCII
var _renderers: Dictionary = {}
var _layouts: Dictionary = {}
var _last_state: RefCounted
var _reduced_vfx_enabled: bool = false


# === Public Methods ===
func set_requested_mode(value: Variant) -> void:
	var requested_mode: StringName = MapRenderModeScript.normalize(value)
	_apply_mode(requested_mode)


func get_requested_mode() -> StringName:
	return _requested_mode


func get_effective_mode() -> StringName:
	return _effective_mode


func is_requested_mode_available() -> bool:
	return _requested_mode == MapRenderModeScript.ASCII or _renderer_is_available(_requested_mode)


func is_mode_available(mode_value: Variant) -> bool:
	if not MapRenderModeScript.is_known(mode_value):
		return false
	var mode: StringName = StringName(mode_value)
	return mode == MapRenderModeScript.ASCII or _renderer_is_available(mode)


func register_renderer(mode_value: Variant, renderer: Node, layout: RefCounted) -> bool:
	if not MapRenderModeScript.is_known(mode_value):
		return false
	var mode: StringName = StringName(mode_value)
	if mode == MapRenderModeScript.ASCII or not is_instance_valid(renderer) or layout == null:
		return false
	if not renderer.has_method(&"present") or not renderer.has_method(&"is_renderer_available"):
		return false
	if not bool(renderer.call(&"is_renderer_available")):
		return false
	_renderers[mode] = renderer
	_layouts[mode] = layout
	_set_renderer_visible(renderer, false)
	_set_renderer_reduced_vfx(renderer, _reduced_vfx_enabled)
	_apply_mode(_requested_mode, true)
	return true


func unregister_renderer(mode_value: Variant) -> void:
	var mode: StringName = MapRenderModeScript.normalize(mode_value)
	var renderer: Node = _renderer_for_mode(mode)
	if renderer != null:
		_reset_renderer_transients(renderer)
		_set_renderer_visible(renderer, false)
	_renderers.erase(mode)
	_layouts.erase(mode)
	_apply_mode(_requested_mode, true)


func present(state: RefCounted) -> void:
	_last_state = state
	var renderer: Node = _renderer_for_mode(_effective_mode)
	if renderer != null:
		renderer.call(&"present", state)


func play_event(event: Dictionary) -> void:
	var renderer: Node = _renderer_for_mode(_effective_mode)
	if renderer != null and renderer.has_method(&"play_event"):
		renderer.call(&"play_event", event)


func set_reduced_vfx(enabled: bool) -> void:
	_reduced_vfx_enabled = enabled
	var configured_renderers: Dictionary = {}
	for renderer_value: Variant in _renderers.values():
		if renderer_value is not Node or not is_instance_valid(renderer_value):
			continue
		var renderer: Node = renderer_value
		var renderer_id: int = renderer.get_instance_id()
		if configured_renderers.has(renderer_id):
			continue
		configured_renderers[renderer_id] = true
		_set_renderer_reduced_vfx(renderer, enabled)


func get_last_state() -> RefCounted:
	return _last_state


func get_active_layout() -> RefCounted:
	var layout: Variant = _layouts.get(_effective_mode)
	if layout is RefCounted:
		return layout
	return null


func get_debug_summary() -> Dictionary:
	return {
		"requested_mode": _requested_mode,
		"effective_mode": _effective_mode,
		"has_state": _last_state != null,
		"registered_modes": _renderers.keys(),
		"reduced_vfx": _reduced_vfx_enabled,
	}


# === Private Methods ===
func _apply_mode(requested_mode: StringName, force_replay: bool = false) -> void:
	var previous_requested: StringName = _requested_mode
	var previous_effective: StringName = _effective_mode
	var next_effective: StringName = _resolve_effective_mode(requested_mode)
	var mode_changed_value: bool = (
		requested_mode != previous_requested or next_effective != previous_effective
	)
	if not mode_changed_value and not force_replay:
		return
	var previous_renderer: Node = _renderer_for_mode(previous_effective)
	if previous_renderer != null and previous_effective != next_effective:
		_reset_renderer_transients(previous_renderer)
	for renderer_value: Variant in _renderers.values():
		if renderer_value is Node:
			_set_renderer_visible(renderer_value, false)
	_requested_mode = requested_mode
	_effective_mode = next_effective
	var active_renderer: Node = _renderer_for_mode(_effective_mode)
	if active_renderer != null:
		if active_renderer.has_method(&"set_render_profile"):
			active_renderer.call(&"set_render_profile", _effective_mode)
		_set_renderer_visible(active_renderer, true)
		if _last_state != null:
			active_renderer.call(&"present", _last_state)
	if mode_changed_value:
		mode_changed.emit(_requested_mode, _effective_mode)


func _resolve_effective_mode(requested_mode: StringName) -> StringName:
	if requested_mode != MapRenderModeScript.ASCII and _renderer_is_available(requested_mode):
		return requested_mode
	return MapRenderModeScript.ASCII


func _renderer_is_available(mode: StringName) -> bool:
	var renderer: Node = _renderer_for_mode(mode)
	return (
		renderer != null
		and renderer.has_method(&"is_renderer_available")
		and bool(renderer.call(&"is_renderer_available"))
	)


func _renderer_for_mode(mode: StringName) -> Node:
	var renderer: Variant = _renderers.get(mode)
	if renderer is Node and is_instance_valid(renderer):
		return renderer
	return null


func _reset_renderer_transients(renderer: Node) -> void:
	if renderer.has_method(&"reset_transients"):
		renderer.call(&"reset_transients")


func _set_renderer_reduced_vfx(renderer: Node, enabled: bool) -> void:
	if renderer.has_method(&"set_reduced_vfx"):
		renderer.call(&"set_reduced_vfx", enabled)


func _set_renderer_visible(renderer: Node, renderer_visible: bool) -> void:
	if renderer is CanvasItem:
		(renderer as CanvasItem).visible = renderer_visible
	if renderer.has_method(&"set_renderer_active"):
		renderer.call(&"set_renderer_active", renderer_visible)
