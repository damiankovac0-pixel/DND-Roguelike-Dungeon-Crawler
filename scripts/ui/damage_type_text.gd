## Compact player-facing copy for damage types and enemy affinities.
class_name DamageTypeText
extends RefCounted

const DAMAGE_TYPE_SUMMARY: String = (
	"Damage types: melee is close combat, ranged is bows/crossbows, "
	+ "magic is staffs and scrolls."
)
const STANDARD_AFFINITY_TEXT: String = "Affinities: standard damage from melee, ranged, and magic."


static func affinity_line(melee_percent: int, ranged_percent: int, magic_percent: int) -> String:
	var notes: Array[String] = []
	_append_affinity_note(notes, "melee", melee_percent)
	_append_affinity_note(notes, "ranged", ranged_percent)
	_append_affinity_note(notes, "magic", magic_percent)
	if notes.is_empty():
		return STANDARD_AFFINITY_TEXT
	return "Affinities: %s." % "; ".join(notes)


static func _append_affinity_note(notes: Array[String], label: String, percent: int) -> void:
	if percent == 100:
		return
	if percent < 100:
		notes.append("resists %s (%d%%)" % [label, percent])
	else:
		notes.append("weak to %s (%d%%)" % [label, percent])
