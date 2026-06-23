class_name Enemy
extends "res://scripts/entities/actor.gd"

# === Public Variables ===
var enemy_data: Resource


# === Public Methods ===
func initialize_from_data(data: Resource, start_position: Vector2i) -> void:
	enemy_data = data
	setup_actor(data.display_name, data.glyph, data.color, start_position)
	if stats_component != null:
		stats_component.configure_enemy(data)
