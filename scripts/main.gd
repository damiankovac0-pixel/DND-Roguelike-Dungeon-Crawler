extends Node


# === Lifecycle Methods ===
func _ready() -> void:
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")
