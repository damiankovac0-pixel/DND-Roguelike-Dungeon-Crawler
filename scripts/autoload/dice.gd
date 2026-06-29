## Autoload singleton for dice rolling: d20, NdS, 4d6-drop-lowest, and ability modifiers.
extends Node


# === Lifecycle Methods ===
func _ready() -> void:
	randomize()


# === Public Methods ===
func d20() -> int:
	return randi_range(1, 20)


func roll(sides: int) -> int:
	return randi_range(1, sides)


func roll_dice(count: int, sides: int) -> Array[int]:
	var results: Array[int] = []
	for i in range(count):
		results.append(roll(sides))
	return results


func roll_4d6_drop_lowest() -> int:
	var rolls: Array[int] = [roll(6), roll(6), roll(6), roll(6)]
	rolls.sort()
	rolls.reverse()
	return rolls[0] + rolls[1] + rolls[2]


func roll_ability_scores() -> Dictionary:
	var scores: Dictionary = {}
	for stat in ["str", "dex", "con", "int", "wis", "cha"]:
		scores[stat] = roll_4d6_drop_lowest()
	return scores


func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)
