class_name CombatSystem
extends RefCounted


# === Public Methods ===
static func attack(attacker: Node, defender: Node) -> Dictionary:
	var roll_result: int = Dice.d20()
	var attack_total: int = roll_result + attacker.stats_component.get_attack_bonus()
	var target_ac: int = defender.stats_component.get_armor_class()
	var is_critical: bool = roll_result == 20
	var hit: bool = is_critical or attack_total >= target_ac
	var damage: int = 0

	if hit:
		damage = (
			Dice.roll(attacker.stats_component.get_damage_sides())
			+ attacker.stats_component.get_damage_bonus()
		)
		damage = max(1, damage)
		if is_critical:
			damage += Dice.roll(attacker.stats_component.get_damage_sides())
		defender.stats_component.apply_damage(damage)

	return {
		"hit": hit,
		"critical": is_critical,
		"roll": roll_result,
		"total": attack_total,
		"damage": damage,
		"defender_dead": not defender.is_alive(),
	}
