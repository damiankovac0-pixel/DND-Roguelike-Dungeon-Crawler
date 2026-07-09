## Resource describing a delayed boss attack, telegraph shape, damage, and summons.
class_name BossAttackData
extends Resource

# === Exports ===
@export var id: StringName = &""
@export var intent: StringName = &"boss_attack"
@export var phase_min: int = 1
@export var cooldown: int = 2
@export var telegraph_turns: int = 1
@export var shape: StringName = &"single_player"
@export var range: int = 6
@export var radius: int = 1
@export var width: int = 1
@export var damage_dice: int = 1
@export var damage_sides: int = 6
@export var damage_bonus: int = 0
@export var damage_type: StringName = &"magic"
@export var summon_enemy_path: String = ""
@export var summon_count: int = 0
@export var warning_text: String = ""
@export var resolve_text: String = ""
@export var effect: StringName = &""
@export var effect_trigger: StringName = &"hit"
@export var effect_turns: int = 0
@export var effect_amount: int = 0
@export var telegraph_glyph: String = ""
@export var telegraph_color: Color = Color.TRANSPARENT
@export var telegraph_fill_color: Color = Color.TRANSPARENT
@export var telegraph_border_color: Color = Color.TRANSPARENT
