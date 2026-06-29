## Resource defining a trap: effect type, damage, detection DC, and display glyph.
class_name TrapData
extends Resource

# === Enums ===
enum TrapEffect {
	DAMAGE,
	POTSON,
	TELEPORT,
	ALARM,
}

# === Exports ===
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var glyph: String = "∧"
@export var color: Color = Color(0.9, 0.4, 0.1)
@export var effect: TrapEffect = TrapEffect.DAMAGE
@export var min_damage: int = 2
@export var max_damage: int = 8
@export var detect_dc: int = 12
# Passive bonus to detection (higher = harder to spot)
@export var reveal_on_detect: bool = true
