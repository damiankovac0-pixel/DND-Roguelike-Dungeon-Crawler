## Drives the enemy phase by emitting signals around a callable action.
class_name TurnManager
extends Node

signal enemy_phase_started
signal enemy_phase_finished


# === Public Methods ===
func run_enemy_phase(enemy_actions: Callable) -> void:
	enemy_phase_started.emit()
	enemy_actions.call()
	enemy_phase_finished.emit()
