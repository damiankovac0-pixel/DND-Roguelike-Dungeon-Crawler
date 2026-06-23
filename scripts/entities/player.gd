class_name Player
extends "res://scripts/entities/actor.gd"


# === Lifecycle Methods ===
func _ready() -> void:
	super._ready()
	display_name = "Hero"
	glyph = "@"
	color = Color(0.95, 0.95, 0.95)


# === Public Methods ===
func initialize_from_rolls(ability_scores: Dictionary) -> void:
	if stats_component != null:
		stats_component.configure_player(ability_scores)
