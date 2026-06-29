## D&D 5e-style attack resolution: d20 + bonus vs AC, critical hits, and damage rolls.
class_name CombatSystem
extends RefCounted


# === Public Methods ===
static func attack(attacker: Node, defender: Node, damage_percent: int = 100) -> Dictionary:
	var roll_result: int = Dice.d20()
	var attack_total: int = roll_result + attacker.stats_component.get_attack_bonus()
	var target_ac: int = defender.stats_component.get_armor_class()
	var is_critical: bool = roll_result == 20
	var hit: bool = is_critical or attack_total >= target_ac
	var damage: int = 0
	var raw_damage: int = 0

	if hit:
		raw_damage = (
			Dice.roll(attacker.stats_component.get_damage_sides())
			+ attacker.stats_component.get_damage_bonus()
		)
		raw_damage = max(1, raw_damage)
		if is_critical:
			raw_damage += Dice.roll(attacker.stats_component.get_damage_sides())
		damage = _apply_damage_percent(raw_damage, damage_percent)
		if damage > 0:
			defender.stats_component.apply_damage(damage)

	return {
		"hit": hit,
		"critical": is_critical,
		"roll": roll_result,
		"total": attack_total,
		"damage": damage,
		"raw_damage": raw_damage,
		"defender_dead": not defender.is_alive(),
	}


static func _apply_damage_percent(raw_damage: int, damage_percent: int) -> int:
	if damage_percent <= 0:
		return 0
	if damage_percent == 100:
		return raw_damage
	return max(1, int(round(raw_damage * damage_percent / 100.0)))
