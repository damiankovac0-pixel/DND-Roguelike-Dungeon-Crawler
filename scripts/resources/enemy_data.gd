## Resource defining an enemy template: stats, floor gates, spawn weight, and damage affinities.
class_name EnemyData
extends Resource

# === Exports ===
@export var display_name: String = ""
@export var glyph: String = "g"
@export var color: Color = Color.WHITE
@export var max_hp: int = 8
@export var armor_class: int = 10
@export var attack_bonus: int = 2
@export var damage_sides: int = 4
@export var damage_bonus: int = 0
@export var xp_reward: int = 25
@export var min_floor: int = 1
@export var max_floor: int = 0
@export var spawn_weight: int = 10
@export var melee_damage_percent: int = 100
@export var ranged_damage_percent: int = 100
@export var magic_damage_percent: int = 100
@export var revive_chance_percent: int = 0
@export var revive_hp_percent: int = 0
@export var poison_chance_percent: int = 0
@export var poison_turns: int = 0
@export var poison_damage_sides: int = 4
@export var gold_bonus_chance_percent: int = 0
@export var gold_bonus_percent: int = 0
@export var ranged_attack_range: int = 0
@export var ranged_attack_interval: int = 0
@export var ranged_damage_sides: int = 0
@export var ranged_damage_bonus: int = 0
@export var ranged_damage_type: StringName = &"piercing"
@export var ranged_projectile_id: StringName = &""
@export var ai_preferred_range: int = 0
@export var summon_interval: int = 0
@export var summon_count: int = 0
@export var summon_max_active: int = 0
@export var summon_enemy_path: String = ""
@export var fireball_range: int = 0
@export var fireball_interval: int = 0
@export var fireball_damage_dice: int = 0
@export var fireball_damage_sides: int = 0
@export var fireball_damage_bonus: int = 0
@export var fireball_projectile_id: StringName = &""
@export var visual_id: StringName = &"actor/enemy/humanoid"

@export var is_boss: bool = false
@export var boss_id: StringName = &""
@export var boss_floor: int = 0
@export var boss_room_title: String = ""
@export var boss_reward_gold: int = 0
@export var boss_reward_chest_rarity: int = 0
@export var boss_phase_hp_percents: Array[int] = []
@export var boss_footprint_offsets: Array[Vector2i] = [Vector2i.ZERO]
@export var boss_visual_frames: Array[PackedStringArray] = []
@export var boss_visual_frame_seconds: float = 0.32
@export var boss_attacks: Array[Resource] = []
@export var boss_music_stream: AudioStream
@export var boss_climax_music_stream: AudioStream
@export var boss_strategy_hint: String = ""
@export var boss_guarded_damage_percent: int = 100
@export var boss_exposed_damage_percent: int = 100
@export var boss_exposed_turns: int = 0
@export var boss_retaliation_attack_id: StringName = &""
@export var boss_retaliation_hit_threshold: int = 0
