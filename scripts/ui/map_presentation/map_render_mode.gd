class_name MapRenderMode
extends RefCounted
## Canonical map-renderer mode values and strict preference normalization.
##
## Phase 1 recognizes future Hybrid and Pixel preferences while keeping ASCII
## as the only effective renderer.

# === Constants ===
const ASCII: StringName = &"ascii"
const HYBRID: StringName = &"hybrid"
const PIXEL: StringName = &"pixel"
const ALL: Array[StringName] = [ASCII, HYBRID, PIXEL]


# === Public Methods ===
static func normalize(value: Variant) -> StringName:
	if not (value is String or value is StringName):
		return ASCII
	var candidate: StringName = StringName(value)
	if candidate in ALL:
		return candidate
	return ASCII


static func is_known(value: Variant) -> bool:
	if not (value is String or value is StringName):
		return false
	return StringName(value) in ALL
