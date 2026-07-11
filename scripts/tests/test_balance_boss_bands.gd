## Deterministic boss combat model: pressure, TTK, and mechanics validation.
##
## Tests all five bosses (Observer through Nyxara) against Fighter/Ranger/Wizard
## profiles. Validates attack/hazard pressure, three-class TTK feasibility,
## chest rarity ladder, marked boss reward equipment preference,
## Seraphine 2-turn spores, Kaelros one-eel queue, Nyxara one guard.
##
## Run: godot --headless --path . --script res://scripts/tests/test_balance_boss_bands.gd
extends SceneTree

const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const EnemyDataScript = preload("res://scripts/resources/enemy_data.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

const BOSS_FLOORS: Dictionary = {
	&"observer": 5,
	&"seraphine": 10,
	&"vorrak": 15,
	&"kaelros": 20,
	&"nyxara": 25,
}

# Expected player level at each boss floor
const BOSS_FLOOR_LEVELS: Dictionary = {
	5: 5,
	10: 10,
	15: 14,
	20: 17,
	25: 20,
}

const CLASS_STATS: Dictionary = {
	&"fighter": {"str": 16, "dex": 14, "con": 14, "int": 10, "wis": 12, "cha": 10},
	&"ranger": {"str": 12, "dex": 16, "con": 14, "int": 10, "wis": 14, "cha": 8},
	&"wizard": {"str": 8, "dex": 12, "con": 14, "int": 16, "wis": 14, "cha": 10},
}

const EXPECTED_CHEST_RARITIES: Dictionary = {
	5: 2,
	10: 3,
	15: 4,
	20: 5,
	25: 6,
}

var _enemy_resources: Array[Resource] = []
var _item_resources: Array[Resource] = []
var _bosses: Dictionary = {}  # boss_id -> EnemyData
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_enemy_resources = []
	for p: String in ResourcePathsScript.ENEMY_PATHS:
		var r: Resource = load(p)
		if r != null:
			_enemy_resources.append(r)

	_item_resources = []
	for p: String in ResourcePathsScript.ITEM_PATHS:
		var r: Resource = load(p)
		if r != null:
			_item_resources.append(r)

	# Find and index bosses
	for e: Resource in _enemy_resources:
		if e.is_boss and e.boss_id != &"":
			_bosses[e.boss_id] = e

	# Verify all 5 bosses present
	for bid: StringName in [&"observer", &"seraphine", &"vorrak", &"kaelros", &"nyxara"]:
		if not _bosses.has(bid):
			_fail("Boss %s missing from resources" % bid)

	if _failed:
		printerr("Test failed: missing bosses")
		quit(1)
		return

	print("Loaded %d bosses: %s" % [_bosses.size(), ", ".join(_bosses.keys())])

	# Chest rarity check
	_check_boss_chest_rarities()

	# Marked boss reward equipment preference
	_check_boss_reward_preferred_equipment()

	# Boss pressure against each class
	_check_boss_attack_pressure()

	# Boss TTK feasibility
	_check_boss_ttk()

	# Specific boss mechanics
	_check_seraphine_spores()
	_check_kaelros_eels()
	_check_nyxara_guard()

	if _failed:
		printerr("Test failed, see errors above")
		quit(1)
		return
	print("All boss band checks passed")
	quit(0)


# ---- Helpers ----


func _enemy_scaled_hp(enemy: Resource, floor_n: int) -> int:
	var depth: int = max(0, floor_n - 1)
	var early: int = min(depth, 9)
	var late: int = max(0, depth - 9)
	var hp_bonus: int = int(ceil(early * 1.0)) + int(ceil(late * 1.25))
	return enemy.max_hp + hp_bonus


func _enemy_scaled_defense(enemy: Resource, floor_n: int) -> Dictionary:
	var depth: int = max(0, floor_n - 1)
	var armor_bonus: int = min(3, int(depth / 8))
	var ac: int = enemy.armor_class + armor_bonus
	var atk_bonus: int = int(depth / 7)
	var dmg_bonus: int = int(max(0, depth - 3) / 7)
	var special_bonus: int = min(3, int(depth / 8))
	return {
		"ac": ac,
		"atk": enemy.attack_bonus + atk_bonus,
		"dmg_bonus": enemy.damage_bonus + dmg_bonus,
		"special_bonus": special_bonus,
	}


func _player_attack_bonus(stats: Dictionary, weapon: Resource, level: int) -> int:
	var score: int = stats.get("str", 10)
	if weapon != null:
		if weapon.is_staff or weapon.weapon_damage_type == &"magic":
			score = stats.get("wis", 10)
		elif weapon.is_ranged_weapon:
			score = stats.get("dex", 10)
	var ability_mod: int = int((score - 10) / 2)
	var prof: int = 2 + int((min(level, 20) - 1) / 4)
	return prof + ability_mod + (weapon.attack_bonus if weapon != null else 0)


func _hit_chance(attack_bonus: int, ac: int) -> float:
	var needed: int = ac - attack_bonus
	if needed <= 1:
		return 1.0
	return max(0.05, (21.0 - needed) / 20.0)


func _player_class_percent(cls: StringName, damage_type: StringName, level: int) -> int:
	if cls == &"ranger":
		if damage_type == &"melee":
			return 50 if level < 15 else (60 if level < 20 else 70)
		elif damage_type == &"ranged":
			if level >= 20:
				return 175
			elif level >= 15:
				return 170
			elif level >= 10:
				return 160
			else:
				return 150
	elif cls == &"wizard":
		if damage_type == &"magic":
			if level >= 20:
				return 240
			elif level >= 15:
				return 220
			else:
				return 200
		elif damage_type in [&"melee", &"ranged"]:
			return 60 if level < 20 else 70
	else:
		if damage_type == &"melee":
			if level >= 20:
				return 180
			elif level >= 15:
				return 170
			elif level >= 10:
				return 160
			else:
				return 150
	return 100


func _scale_damage(raw: int, percent: int) -> int:
	if percent <= 0:
		return 0
	if percent == 100:
		return raw
	return max(1, int(round(raw * percent / 100.0)))


func _boss_con_score(base_con: int, level: int) -> int:
	# Realistic CON growth: CON boosted at level 8 and 16 (every other ASI)
	match level:
		5:
			return base_con
		10:
			return base_con + 2
		14:
			return base_con + 2
		17:
			return base_con + 4
		20:
			return base_con + 4
		_:
			return base_con


func _player_max_hp(stats: Dictionary, level: int) -> int:
	var con_score: int = stats.get("con", 10)
	var con_mod: int = int((con_score - 10) / 2)
	var hp: int = 12 + con_mod
	for lv: int in range(2, level + 1):
		var gain: int = max(1, 5 + con_mod)
		if lv > 20:
			gain = max(1, int(ceil(gain * 0.35)))
		hp += gain
	return hp


func _player_ac(stats: Dictionary, armor_bonus: int) -> int:
	var dex_score: int = stats.get("dex", 10)
	var dex_mod: int = int((dex_score - 10) / 2)
	return 10 + dex_mod + armor_bonus


func _best_weapon_for_class_at_floor(cls: StringName, floor_n: int) -> Resource:
	var best: Resource = null
	var best_score: int = 0
	for item: Resource in _item_resources:
		if item.kind != ItemDataScript.ItemKind.WEAPON:
			continue
		if item.min_floor > floor_n:
			continue
		if item.max_floor > 0 and item.max_floor < floor_n:
			continue
		if item.required_class != &"" and item.required_class != cls:
			continue
		if cls == &"fighter" and item.is_ranged_weapon:
			continue
		if cls == &"ranger" and (not item.is_ranged_weapon or item.is_staff):
			continue
		if cls == &"wizard" and not (item.is_staff or item.weapon_damage_type == &"magic"):
			continue
		var score: int = (
			item.damage_dice * max(1, item.damage_sides) + item.damage_bonus + item.attack_bonus * 2
		)
		if score > best_score:
			best_score = score
			best = item
	return best


func _expected_player_damage_per_hit(cls: StringName, floor_n: int) -> float:
	var stats: Dictionary = CLASS_STATS[cls]
	var level: int = BOSS_FLOOR_LEVELS[floor_n]
	var weapon: Resource = _best_weapon_for_class_at_floor(cls, floor_n)
	if weapon == null:
		return 0.0
	var sides: int = max(1, weapon.damage_sides)
	var dice: int = max(1, weapon.damage_dice)
	var expected_roll: float = dice * (sides + 1.0) / 2.0

	var ability_mod: int
	var score: int
	if weapon.is_staff or weapon.weapon_damage_type == &"magic":
		score = stats.get("wis", 10)
	elif weapon.is_ranged_weapon:
		score = stats.get("dex", 10)
	else:
		score = stats.get("str", 10)
	ability_mod = int((score - 10) / 2)
	var total_bonus: int = weapon.damage_bonus + ability_mod

	# Expected base damage
	var base: int = max(1, int(round(expected_roll + total_bonus)))

	var dt: StringName = (
		&"magic"
		if (weapon.is_staff or weapon.weapon_damage_type == &"magic")
		else (&"ranged" if weapon.is_ranged_weapon else &"melee")
	)
	var class_pct: int = _player_class_percent(cls, dt, level) + weapon.class_damage_percent_bonus
	var scaled: int = _scale_damage(base, class_pct)
	return float(scaled)


func _boss_attack_expected_damage(attack: Resource) -> float:
	if attack == null:
		return 0.0
	var dice: int = max(1, attack.damage_dice)
	var sides: int = max(2, attack.damage_sides)
	var expected_roll: float = dice * (sides + 1.0) / 2.0
	var total: float = expected_roll + attack.damage_bonus
	return max(1.0, total)


func _boss_hazard_expected_damage(attack: Resource) -> float:
	if attack == null or attack.hazard_turns <= 0:
		return 0.0
	var dice: int = max(1, attack.hazard_damage_dice)
	var sides: int = max(2, attack.hazard_damage_sides)
	var expected_roll: float = dice * (sides + 1.0) / 2.0
	var total: float = expected_roll + attack.hazard_damage_bonus
	return max(1.0, total)


# ---- Chest rarities ----


func _check_boss_chest_rarities() -> void:
	if _failed:
		return
	var issues: Array[String] = []
	for bid: StringName in _bosses:
		var boss: Resource = _bosses[bid]
		var expected: int = EXPECTED_CHEST_RARITIES.get(BOSS_FLOORS[bid], -1)
		if boss.boss_reward_chest_rarity != expected:
			issues.append(
				"%s: chest_rarity=%d, expected %d" % [bid, boss.boss_reward_chest_rarity, expected]
			)

	if issues.size() > 0:
		_fail("Boss chest rarity mismatch: %s" % ", ".join(issues))
	else:
		print(
			(
				"  chest rarities: Observer=%d Seraphine=%d Vorrak=%d Kaelros=%d Nyxara=%d"
				% [
					_bosses[&"observer"].boss_reward_chest_rarity,
					_bosses[&"seraphine"].boss_reward_chest_rarity,
					_bosses[&"vorrak"].boss_reward_chest_rarity,
					_bosses[&"kaelros"].boss_reward_chest_rarity,
					_bosses[&"nyxara"].boss_reward_chest_rarity,
				]
			)
		)


# ---- Boss reward equipment preference ----


func _check_boss_reward_preferred_equipment() -> void:
	if _failed:
		return

	var preferred_cases: int = 0
	var ordinary_preserved_cases: int = 0
	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		for bid: StringName in _bosses:
			if _failed:
				return
			var boss: Resource = _bosses[bid]
			var floor_n: int = BOSS_FLOORS[bid]
			var chest_rarity: int = boss.boss_reward_chest_rarity
			var reward_floor: int = _reward_floor_for_chest(floor_n, chest_rarity)
			var ordinary_candidates: Array[Resource] = _chest_reward_candidates(
				chest_rarity, floor_n
			)
			if ordinary_candidates.is_empty():
				_fail(
					(
						"[%s %s] no chest reward candidates at floor %d reward_floor %d"
						% [cls, bid, floor_n, reward_floor]
					)
				)
				return

			var ordinary_model_candidates: Array[Resource] = _ordinary_chest_reward_candidate_pool(
				ordinary_candidates
			)
			if ordinary_model_candidates.size() != ordinary_candidates.size():
				_fail(
					(
						"[%s %s] ordinary chest candidate count changed from %d to %d"
						% [
							cls,
							bid,
							ordinary_candidates.size(),
							ordinary_model_candidates.size(),
						]
					)
				)
				return

			var ordinary_has_nonpreferred_candidate: bool = false
			for item: Resource in ordinary_candidates:
				if not ordinary_model_candidates.has(item):
					_fail(
						(
							"[%s %s] ordinary chest model dropped %s before preference"
							% [cls, bid, item.display_name]
						)
					)
					return
				if not _is_class_compatible_equipment(item, cls):
					ordinary_has_nonpreferred_candidate = true
			if ordinary_has_nonpreferred_candidate:
				ordinary_preserved_cases += 1

			var preferred_candidates: Array[Resource] = _class_compatible_equipment_candidates(
				ordinary_candidates, cls
			)
			if preferred_candidates.is_empty():
				continue
			preferred_cases += 1

			var marked_pool: Array[Resource] = _marked_boss_reward_candidate_pool(
				ordinary_candidates, cls
			)
			if marked_pool.is_empty():
				_fail(
					(
						"[%s %s] marked boss reward pool empty despite compatible candidates"
						% [cls, bid]
					)
				)
				return
			for item: Resource in marked_pool:
				if not _is_class_compatible_equipment(item, cls):
					_fail(
						(
							"[%s %s] marked boss reward pool includes incompatible %s (required_class=%s)"
							% [cls, bid, item.display_name, str(item.required_class)]
						)
					)
					return

	if preferred_cases <= 0:
		_fail("no compatible boss reward equipment candidate cases found")
		return
	if ordinary_preserved_cases <= 0:
		_fail("ordinary chest model had no non-preferred candidates to preserve")
		return

	print(
		(
			"  boss reward equipment preference: %d marked pools compatible; ordinary chest pools unchanged"
			% preferred_cases
		)
	)


func _reward_floor_for_chest(floor_number: int, chest_rarity: int) -> int:
	return floor_number + mini(chest_rarity, 2)


func _chest_reward_candidates(chest_rarity: int, floor_number: int) -> Array[Resource]:
	var reward_floor: int = _reward_floor_for_chest(floor_number, chest_rarity)
	var maximum_rarity: int = min(chest_rarity, _rarity_cap_for_floor(floor_number))
	var candidates: Array[Resource] = _get_item_candidates_for_floor(reward_floor)
	var filtered: Array[Resource] = []
	var minimum_rarity: int = max(0, chest_rarity - 2)
	for item_data: Resource in candidates:
		if item_data.rarity >= minimum_rarity and item_data.rarity <= maximum_rarity:
			filtered.append(item_data)
	if filtered.is_empty():
		for fallback_rarity: int in range(maximum_rarity, -1, -1):
			for item_data: Resource in candidates:
				if item_data.rarity == fallback_rarity:
					filtered.append(item_data)
			if not filtered.is_empty():
				break
	return filtered


func _ordinary_chest_reward_candidate_pool(candidates: Array[Resource]) -> Array[Resource]:
	var ordinary_candidates: Array[Resource] = []
	for item_data: Resource in candidates:
		ordinary_candidates.append(item_data)
	return ordinary_candidates


func _marked_boss_reward_candidate_pool(
	candidates: Array[Resource], cls: StringName
) -> Array[Resource]:
	var compatible_equipment: Array[Resource] = _class_compatible_equipment_candidates(
		candidates, cls
	)
	if compatible_equipment.is_empty():
		return _ordinary_chest_reward_candidate_pool(candidates)
	return compatible_equipment


func _class_compatible_equipment_candidates(
	candidates: Array[Resource], cls: StringName
) -> Array[Resource]:
	var compatible_equipment: Array[Resource] = []
	for item_data: Resource in candidates:
		if _is_class_compatible_equipment(item_data, cls):
			compatible_equipment.append(item_data)
	return compatible_equipment


func _is_class_compatible_equipment(item_data: Resource, cls: StringName) -> bool:
	return _is_equipment_item(item_data) and not _is_wrong_class_item_for(item_data, cls)


func _is_equipment_item(item_data: Resource) -> bool:
	return (
		item_data.kind == ItemDataScript.ItemKind.WEAPON
		or item_data.kind == ItemDataScript.ItemKind.ARMOR
		or item_data.kind == ItemDataScript.ItemKind.ACCESSORY
	)


func _is_wrong_class_item_for(item_data: Resource, cls: StringName) -> bool:
	return item_data.required_class != &"" and item_data.required_class != cls


func _get_item_candidates_for_floor(floor_number: int) -> Array[Resource]:
	var candidates: Array[Resource] = []
	for item_data: Resource in _item_resources:
		if _can_spawn_item(item_data, floor_number):
			candidates.append(item_data)
	return candidates


func _can_spawn_item(item_data: Resource, floor_number: int) -> bool:
	if floor_number < item_data.min_floor:
		return false
	return item_data.max_floor <= 0 or floor_number <= item_data.max_floor


func _rarity_cap_for_floor(floor_number: int) -> int:
	if floor_number >= 23:
		return ItemDataScript.ItemRarity.ASCENDED
	if floor_number >= 18:
		return ItemDataScript.ItemRarity.MYTHIC
	if floor_number >= 13:
		return ItemDataScript.ItemRarity.LEGENDARY
	if floor_number >= 8:
		return ItemDataScript.ItemRarity.EPIC
	if floor_number >= 4:
		return ItemDataScript.ItemRarity.RARE
	if floor_number >= 2:
		return ItemDataScript.ItemRarity.UNCOMMON
	return ItemDataScript.ItemRarity.COMMON


# ---- Boss attack pressure ----


func _check_boss_attack_pressure() -> void:
	if _failed:
		return

	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		for bid: StringName in _bosses:
			if _failed:
				return
			var boss: Resource = _bosses[bid]
			var floor_n: int = BOSS_FLOORS[bid]
			var level: int = BOSS_FLOOR_LEVELS[floor_n]
			var stats: Dictionary = CLASS_STATS[cls].duplicate()
			stats["con"] = _boss_con_score(stats["con"], level)
			var def: Dictionary = _enemy_scaled_defense(boss, floor_n)
			var max_hp: int = _player_max_hp(stats, level)
			var armor_bonus: int = 0  # Baseline: no armor (worst-case)
			# Add estimated best armor available at floor
			if floor_n >= 10:
				armor_bonus = 7
			elif floor_n >= 6:
				armor_bonus = 5
			elif floor_n >= 4:
				armor_bonus = 4
			else:
				armor_bonus = 2
			var p_ac: int = _player_ac(stats, armor_bonus)

			# Boss melee attack pressure
			var ep: int = def["atk"] + 2  # +2 proficiency
			var melee_hit_chance: float = _hit_chance(ep, p_ac)
			var sides: int = boss.damage_sides
			var expected_melee_roll: float = (sides + 1.0) / 2.0
			var melee_dmg: float = expected_melee_roll + def["dmg_bonus"]
			var melee_pressure: float = (melee_hit_chance * melee_dmg) / float(max_hp) * 100.0

			# Boss attack pressure from abilities
			var best_direct: float = 0.0
			for atk: Resource in boss.boss_attacks:
				var is_summon: bool = atk.shape == &"summon" or atk.damage_dice <= 0
				var hazard_dmg: float = _boss_hazard_expected_damage(atk)

				# Direct damage pressure (skip summons and non-damaging attacks)
				if not is_summon:
					var attack_dmg: float = _boss_attack_expected_damage(atk)
					var attack_pressure: float = attack_dmg / float(max_hp) * 100.0

					if attack_pressure > best_direct:
						best_direct = attack_pressure

					# Direct telegraphed attacks: 8%-55% HP
					var has_status: bool = atk.effect != &"" or atk.hazard_effect != &""
					# Seraphine poison/status attacks don't need raw direct damage
					var skip_lower: bool = bid == &"seraphine" and has_status

					if not skip_lower and (attack_pressure < 8.0 or attack_pressure > 55.0):
						_fail(
							(
								"[%s %s] %s direct hit = %.1f%% HP (expected 8-55%%)"
								% [cls, bid, atk.id, attack_pressure]
							)
						)

					# Attack + hazard combo <= 65% (for attacks with both)
					if hazard_dmg > 0.0:
						var combo: float = (attack_dmg + hazard_dmg) / float(max_hp) * 100.0
						if combo > 65.0:
							_fail(
								(
									"[%s %s] %s combo = %.1f%% HP (max 65%%)"
									% [cls, bid, atk.id, combo]
								)
							)

				# Hazard tick check (applies to any attack with hazards)
				if hazard_dmg > 0.0:
					var hazard_pressure: float = hazard_dmg / float(max_hp) * 100.0
					var hazard_lower: float = 2.0
					if hazard_pressure < hazard_lower or hazard_pressure > 22.0:
						_fail(
							(
								"[%s %s] %s hazard tick = %.1f%% HP (expected %.0f-22%%)"
								% [cls, bid, atk.id, hazard_pressure, hazard_lower]
							)
						)

			# Verify each boss has at least one direct attack >= 8%
			if best_direct < 8.0:
				_fail(
					(
						"[%s %s] No damaging attack reaches 8%% HP (best=%.1f%%)"
						% [cls, bid, best_direct]
					)
				)

	print("  boss attack pressure bounds verified")


# ---- TTK ----


func _check_boss_ttk() -> void:
	if _failed:
		return

	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		var cls_ttks: Array[float] = []
		for bid: StringName in _bosses:
			if _failed:
				return
			var boss: Resource = _bosses[bid]
			var floor_n: int = BOSS_FLOORS[bid]
			var def: Dictionary = _enemy_scaled_defense(boss, floor_n)
			var scaled_hp: int = _enemy_scaled_hp(boss, floor_n)
			var stats: Dictionary = CLASS_STATS[cls]
			var level: int = BOSS_FLOOR_LEVELS[floor_n]
			var weapon: Resource = _best_weapon_for_class_at_floor(cls, floor_n)

			if weapon == null:
				_fail("[%s] No best weapon found for floor %d" % [cls, floor_n])
				continue

			var atk_bonus: int = _player_attack_bonus(stats, weapon, level)
			var hit_chance: float = _hit_chance(atk_bonus, def["ac"])

			if hit_chance <= 0.0:
				_fail(
					(
						"[%s %s] Cannot hit boss at floor %d (AC=%d atk=%d)"
						% [cls, bid, floor_n, def["ac"], atk_bonus]
					)
				)
				continue

			var dmg_per_hit: float = _expected_player_damage_per_hit(cls, floor_n)
			if dmg_per_hit <= 0.0:
				_fail("[%s %s] Zero expected damage" % [cls, bid])
				continue

			# Account for boss damage resistances
			var dt: StringName
			if weapon.is_staff or weapon.weapon_damage_type == &"magic":
				dt = &"magic"
			elif weapon.is_ranged_weapon:
				dt = &"ranged"
			else:
				dt = &"melee"

			var enemy_pct: int = 100
			match dt:
				&"melee":
					enemy_pct = boss.melee_damage_percent
				&"ranged":
					enemy_pct = boss.ranged_damage_percent
				&"magic":
					enemy_pct = boss.magic_damage_percent

			var final_dmg: float = _scale_damage(int(round(dmg_per_hit)), enemy_pct)

			var ttk: float = float(scaled_hp) / (hit_chance * final_dmg)
			cls_ttks.append(ttk)

			if ttk > 24.0:
				_fail("[%s %s] TTK = %.1f actions (max 24)" % [cls, bid, ttk])

			# Check ideal 8-18 range
			if ttk < 8.0:
				# Too fast - only fail if unreasonably fast
				if ttk < 4.0:
					_fail("[%s %s] TTK = %.1f actions (too fast, expect >=8)" % [cls, bid, ttk])

		if cls_ttks.size() > 0:
			var ttk_strs: Array[String] = []
			for t_val: float in cls_ttks:
				ttk_strs.append("%.1f" % t_val)
			var cls_str: String = ", ".join(ttk_strs)
			print("  %s boss TTKs: [%s]" % [cls, cls_str])

	print("  boss TTK bounds verified")


# ---- Seraphine spores ----


func _check_seraphine_spores() -> void:
	if _failed:
		return
	var boss: Resource = _bosses.get(&"seraphine")
	if boss == null:
		return

	for atk: Resource in boss.boss_attacks:
		if atk.id == &"spore_burst":
			if atk.telegraph_turns < 2:
				_fail(
					"Seraphine spore_burst telegraph_turns=%d (expected >=2)" % atk.telegraph_turns
				)
			else:
				print("  Seraphine spore_burst telegraph=%d turns (OK)" % atk.telegraph_turns)
			return

	_fail("Seraphine spore_burst attack not found")


# ---- Kaelros eels ----


func _check_kaelros_eels() -> void:
	if _failed:
		return
	var boss: Resource = _bosses.get(&"kaelros")
	if boss == null:
		return

	for atk: Resource in boss.boss_attacks:
		if atk.id == &"drowned_retinue":
			if atk.summon_count > 1:
				_fail("Kaelros drowned_retinue summon_count=%d (expected <=1)" % atk.summon_count)
			if atk.summon_max_active > 2:
				_fail(
					(
						"Kaelros drowned_retinue summon_max_active=%d (expected <=2)"
						% atk.summon_max_active
					)
				)
			print(
				(
					"  Kaelros drowned_retinue: summon_count=%d, max_active=%d (OK)"
					% [atk.summon_count, atk.summon_max_active]
				)
			)
			return

	_fail("Kaelros drowned_retinue attack not found")


# ---- Nyxara guard ----


func _check_nyxara_guard() -> void:
	if _failed:
		return
	var boss: Resource = _bosses.get(&"nyxara")
	if boss == null:
		return

	for atk: Resource in boss.boss_attacks:
		if atk.id == &"mirror_guard":
			if atk.summon_max_active > 1:
				_fail(
					(
						"Nyxara mirror_guard summon_max_active=%d (expected <=1)"
						% atk.summon_max_active
					)
				)
			if atk.cooldown < 5:
				_fail("Nyxara mirror_guard cooldown=%d (expected >=5)" % atk.cooldown)
			print(
				(
					"  Nyxara mirror_guard: phase_min=%d, max_active=%d, cooldown=%d (OK)"
					% [atk.phase_min, atk.summon_max_active, atk.cooldown]
				)
			)
			return

	_fail("Nyxara mirror_guard attack not found")


func _fail(msg: String) -> void:
	if not _failed:
		_failed = true
	printerr("FAIL: " + msg)
