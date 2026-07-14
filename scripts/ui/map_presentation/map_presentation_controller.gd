class_name MapPresentationController
extends RefCounted
## Owns requested and effective map-renderer modes behind the MapView facade.
##
## Phase 1 intentionally exposes only the existing ASCII renderer. Future
## renderers can extend capability resolution without changing gameplay calls.

# === Signals ===
signal mode_changed(requested_mode: StringName, effective_mode: StringName)

# === Constants ===
const MapRenderModeScript: GDScript = preload(
	"res://scripts/ui/map_presentation/map_render_mode.gd"
)

# === Private Variables ===
var _requested_mode: StringName = MapRenderModeScript.ASCII
var _effective_mode: StringName = MapRenderModeScript.ASCII


# === Public Methods ===
func set_requested_mode(value: Variant) -> void:
	var requested_mode: StringName = MapRenderModeScript.normalize(value)
	var effective_mode: StringName = _resolve_effective_mode(requested_mode)
	if requested_mode == _requested_mode and effective_mode == _effective_mode:
		return
	_requested_mode = requested_mode
	_effective_mode = effective_mode
	mode_changed.emit(_requested_mode, _effective_mode)


func get_requested_mode() -> StringName:
	return _requested_mode


func get_effective_mode() -> StringName:
	return _effective_mode


func is_requested_mode_available() -> bool:
	return _requested_mode == _effective_mode


# === Private Methods ===
func _resolve_effective_mode(_requested_mode_value: StringName) -> StringName:
	return MapRenderModeScript.ASCII
