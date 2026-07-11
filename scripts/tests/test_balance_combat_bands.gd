## Deterministic combat model: player hit/TTK/pressure vs every registered regular enemy.
##
## Model uses closed-form d20 hit chance, expected damage, and enemy action pressure.
## Player profiles: Fighter (STR), Ranger (DEX), Wizard (WIS+INT) at expected floor levels.
##
## Run: godot --headless --path . --script res://scripts/tests/test_balance_combat_bands.gd
extends SceneTree

const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const EnemyDataScript = preload("res://scripts/resources/enemy_data.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

const TEST_FLOORS: Array[int] = [1, 3, 5, 7, 10, 12, 15, 18, 20, 23, 25]

# Per-floor median TTK bands (non-inclusive upper bound in low floors)
const TTK_MEDIAN_BANDS: Dictionary = {
	1: [0.7, 2.2],
	3: [1.0, 3.0],
	5: [1.2, 3.5],
	7: [1.3, 4.0],
	10: [1.5, 4.0],
	12: [2.0, 5.0],
	15: [2.0, 5.0],
	18: [2.0, 5.5],
	20: [2.0, 5.5],
	23: [2.0, 6.0],
	25: [2.0, 6.0],
}

# Expected player level at each floor (from IntegratedBalancePlan target bands)
const FLOOR_LEVELS: Dictionary = {
	1: 1,
	3: 3,
	5: 5,
	7: 7,
	10: 9,
	12: 11,
	15: 13,
	18: 15,
	20: 16,
	23: 18,
	25: 19,
}

# Ability scores per class (standard allocation)
const CLASS_STATS: Dictionary = {
	&"fighter": {"str": 16, "dex": 14, "con": 14, "int": 10, "wis": 12, "cha": 10},
	&"ranger": {"str": 12, "dex": 16, "con": 14, "int": 10, "wis": 14, "cha": 8},
	&"wizard": {"str": 8, "dex": 12, "con": 14, "int": 16, "wis": 14, "cha": 10},
}

# Starter weapon per class
const STARTER_WEAPONS: Dictionary = {
	&"fighter": "res://resources/items/training_sword.tres",
	&"ranger": "res://resources/items/hunting_bow.tres",
	&"wizard": "res://resources/items/apprentice_staff.tres",
}

var _failed: bool = false
var _enemy_resources: Array[Resource] = []
var _item_resources: Array[Resource] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_enemy_resources = _load_resources(ResourcePathsScript.ENEMY_PATHS)
	_item_resources = _load_resources(ResourcePathsScript.ITEM_PATHS)

	# Non-boss regular enemies only
	var regular_enemies: Array[Resource] = []
	for e: Resource in _enemy_resources:
		if not e.is_boss:
			regular_enemies.append(e)

	print(
		(
			"Loaded %d regular enemies, %d total resources"
			% [regular_enemies.size(), _enemy_resources.size()]
		)
	)

	var player_equipment: Dictionary = _build_player_equipment()

	_check_regular_enemy_hit_chances(regular_enemies, player_equipment)
	_check_regular_enemy_ttk(regular_enemies, player_equipment)
	_check_regular_enemy_pressure(regular_enemies, player_equipment)

	for floor_idx: int in range(TEST_FLOORS.size()):
		var floor_n: int = TEST_FLOORS[floor_idx]
		var eligible: Array[Resource] = _eligible_regular_enemies(regular_enemies, floor_n)
		if eligible.is_empty():
			_fail("Floor %d has zero eligible regular enemies" % floor_n)

	if _failed:
		_print_fail_summary()
		return
	print("All combat band checks passed")
	quit(0)


func _load_resources(paths: Array[String]) -> Array[Resource]:
	var result: Array[Resource] = []
	for p: String in paths:
		var r: Resource = load(p)
		if r != null:
			result.append(r)
		else:
			_fail("Failed to load resource: %s" % p)
	return result


func _build_player_equipment() -> Dictionary:
	# Build lookup of best weapon/armor/accessory per floor per class
	var result: Dictionary = {}
	var fighters: Array[Resource] = []
	var rangers: Array[Resource] = []
	var wizards: Array[Resource] = []
	var armor_items: Array[Resource] = []
	var accessories: Array[Resource] = []
	var weapons: Dictionary = {}

	for item: Resource in _item_resources:
		if item.kind == ItemDataScript.ItemKind.WEAPON:
			var cls: StringName = item.required_class
			if (cls == &"fighter" or cls == &"") and not item.is_ranged_weapon:
				fighters.append(item)
			if (cls == &"ranger" or cls == &"") and item.is_ranged_weapon and not item.is_staff:
				rangers.append(item)
			if cls == &"wizard" and (item.is_staff or item.weapon_damage_type == &"magic"):
				wizards.append(item)
			weapons[item] = true
		elif item.kind == ItemDataScript.ItemKind.ARMOR:
			armor_items.append(item)
		elif item.kind == ItemDataScript.ItemKind.ACCESSORY:
			accessories.append(item)

	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		var cls_data: Dictionary = {}
		var cls_weapons: Array[Resource] = (
			fighters if cls == &"fighter" else (rangers if cls == &"ranger" else wizards)
		)
		for floor_n: int in TEST_FLOORS:
			var level: int = FLOOR_LEVELS[floor_n]
			var starter_path: String = STARTER_WEAPONS[cls]
			var starter: Resource = load(starter_path)

			# Best weapon available at this floor
			var best_weapon: Resource = starter
			var best_wscore: int = 0
			for w: Resource in cls_weapons:
				if w.min_floor > floor_n:
					continue
				if w.max_floor > 0 and w.max_floor < floor_n:
					continue
				var score: int = (
					w.damage_dice * max(1, w.damage_sides) + w.damage_bonus + w.attack_bonus * 2
				)
				if score > best_wscore:
					best_wscore = score
					best_weapon = w

			# Best armor
			var best_armor: Resource = null
			var best_ascore: int = 0
			for a: Resource in armor_items:
				if a.min_floor > floor_n:
					continue
				if a.max_floor > 0 and a.max_floor < floor_n:
					continue
				if a.armor_bonus > best_ascore:
					best_ascore = a.armor_bonus
					best_armor = a

			# Best offensive accessory (attack_bonus + damage_bonus)
			var best_acc: Resource = null
			var best_bscore: int = -99
			for ac: Resource in accessories:
				if ac.min_floor > floor_n:
					continue
				if ac.max_floor > 0 and ac.max_floor < floor_n:
					continue
				var score: int = ac.attack_bonus + ac.damage_bonus + ac.armor_bonus
				if score > best_bscore:
					best_bscore = score
					best_acc = ac

			cls_data[floor_n] = {
				"weapon": best_weapon,
				"armor": best_armor,
				"accessory": best_acc,
				"level": level,
			}
		result[cls] = cls_data
	return result


func _eligible_regular_enemies(enemies: Array[Resource], floor_n: int) -> Array[Resource]:
	var result: Array[Resource] = []
	for e: Resource in enemies:
		if e.is_boss:
			continue
		if e.min_floor > floor_n:
			continue
		if e.max_floor > 0 and e.max_floor < floor_n:
			continue
		result.append(e)
	return result


# ---- Player Attack Model ----


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


func _player_damage_sides(weapon: Resource) -> int:
	# max(4, weapon.damage_sides) for melee; for ranged it's weapon-specific via _roll_item_damage
	# For simplicity in the model, use weapon's damage_sides if set, else 4
	if weapon != null and weapon.damage_sides > 0:
		return weapon.damage_sides
	return 4


func _player_expected_base_damage(
	weapon: Resource, stats: Dictionary, is_ranged: bool, level: int, is_magic: bool
) -> int:
	# Expected value of raw damage before class/enemy scaling
	if weapon == null:
		return 0
	var sides: int = _player_damage_sides(weapon)
	var dice: int = max(1, weapon.damage_dice)
	var expected_roll: float = dice * (sides + 1) / 2.0

	var bonus: int = weapon.damage_bonus
	var score: int
	if is_magic:
		score = stats.get("wis", 10)
	elif is_ranged:
		score = stats.get("dex", 10)
	else:
		score = stats.get("str", 10)
	bonus += int((score - 10) / 2)

	return max(1, int(round(expected_roll + bonus)))


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
	else:  # fighter
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


func _hit_chance(attack_bonus: int, ac: int) -> float:
	# No natural-1 auto-miss: hit when roll + bonus >= AC, or roll=20.
	# If AC - atk <= 1, every roll hits (100%).
	# If AC - atk >= 21, only natural 20 hits (5%).
	var needed: int = ac - attack_bonus
	if needed <= 1:
		return 1.0
	return max(0.05, (21.0 - needed) / 20.0)


func _expected_damage_per_hit(
	weapon: Resource,
	stats: Dictionary,
	cls: StringName,
	level: int,
	enemy: Resource,
	is_ranged: bool,
	is_magic: bool
) -> float:
	var base: int = _player_expected_base_damage(weapon, stats, is_ranged, level, is_magic)
	var dt: StringName = &"magic" if is_magic else (&"ranged" if is_ranged else &"melee")
	var class_pct: int = _player_class_percent(cls, dt, level) + weapon.class_damage_percent_bonus
	var scaled: int = _scale_damage(base, class_pct)

	# Enemy damage resistance/weakness
	var enemy_pct: int = 100
	match dt:
		&"melee":
			enemy_pct = enemy.melee_damage_percent
		&"ranged":
			enemy_pct = enemy.ranged_damage_percent
		&"magic":
			enemy_pct = enemy.magic_damage_percent
	scaled = _scale_damage(scaled, enemy_pct)
	return float(scaled)


func _enemy_scaled_stats(enemy: Resource, floor_n: int) -> Dictionary:
	var depth: int = max(0, floor_n - 1)
	var early: int = min(depth, 9)
	var late: int = max(0, depth - 9)
	var hp_bonus: int = int(ceil(early * 1.0)) + int(ceil(late * 1.25))
	var armor_bonus: int = min(3, int(depth / 8))
	var atk_bonus: int = int(depth / 7)
	var dmg_bonus: int = int(max(0, depth - 3) / 7)
	var special_bonus: int = min(3, int(depth / 8))
	return {
		"hp": enemy.max_hp + hp_bonus,
		"ac": enemy.armor_class + armor_bonus,
		"atk": enemy.attack_bonus + atk_bonus,
		"dmg_sides": enemy.damage_sides,
		"dmg_bonus": enemy.damage_bonus + dmg_bonus,
		"special_bonus": special_bonus,
	}


func _enemy_attack_bonus(enemy: Resource, floor_n: int) -> int:
	# base_attack_bonus + 2 (proficiency) + scaling_attack_bonus
	var depth: int = max(0, floor_n - 1)
	var scaling: int = int(depth / 7)
	return enemy.attack_bonus + 2 + scaling


func _enemy_expected_damage(enemy: Resource, floor_n: int) -> float:
	var depth: int = max(0, floor_n - 1)
	var dmg_bonus: int = int(max(0, depth - 3) / 7)
	var total_dmg_bonus: int = enemy.damage_bonus + dmg_bonus
	var sides: int = enemy.damage_sides
	var expected_roll: float = (sides + 1.0) / 2.0
	return expected_roll + total_dmg_bonus


func _enemy_ranged_expected_damage(enemy: Resource, floor_n: int, special_bonus: int) -> float:
	if enemy.ranged_damage_sides <= 0:
		return 0.0
	var total_bonus: int = enemy.ranged_damage_bonus + special_bonus
	var sides: int = enemy.ranged_damage_sides
	var expected_roll: float = (sides + 1.0) / 2.0
	return expected_roll + total_bonus


func _enemy_fireball_expected_damage(enemy: Resource, floor_n: int, special_bonus: int) -> float:
	if enemy.fireball_damage_dice <= 0:
		return 0.0
	var total_bonus: int = enemy.fireball_damage_bonus + special_bonus
	var dice: int = max(1, enemy.fireball_damage_dice)
	var sides: int = max(2, enemy.fireball_damage_sides)
	var expected_roll: float = dice * (sides + 1.0) / 2.0
	return expected_roll + total_bonus


func _player_ac(stats: Dictionary, armor: Resource, accessory: Resource) -> int:
	var dex_score: int = stats.get("dex", 10)
	var dex_mod: int = int((dex_score - 10) / 2)
	var armor_bonus: int = 0
	if armor != null:
		armor_bonus += armor.armor_bonus
	if accessory != null:
		armor_bonus += accessory.armor_bonus
	return 10 + dex_mod + armor_bonus


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


# ---- Check: Hit Chance ----


func _check_regular_enemy_hit_chances(enemies: Array[Resource], equip: Dictionary) -> void:
	if _failed:
		return

	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		for floor_n: int in TEST_FLOORS:
			if _failed:
				return
			var eq: Dictionary = equip[cls][floor_n]
			var level: int = eq["level"]
			var weapon: Resource = eq["weapon"]
			var armor: Resource = eq["armor"]
			var accessory: Resource = eq["accessory"]
			var stats: Dictionary = CLASS_STATS[cls]
			var is_ranged: bool = weapon != null and weapon.is_ranged_weapon
			var is_magic: bool = (
				weapon != null and (weapon.is_staff or weapon.weapon_damage_type == &"magic")
			)
			var atk_bonus: int = _player_attack_bonus(stats, weapon, level)

			var eligible: Array[Resource] = _eligible_regular_enemies(enemies, floor_n)
			var misses: Array[String] = []
			for e: Resource in eligible:
				var e_stats: Dictionary = _enemy_scaled_stats(e, floor_n)
				var chance: float = _hit_chance(atk_bonus, e_stats["ac"])
				if chance < 0.45:
					misses.append(
						(
							"%s: hitChance=%.1f%% (AC=%d atk=%d)"
							% [e.display_name, chance * 100.0, e_stats["ac"], atk_bonus]
						)
					)

			if misses.size() > 0:
				_fail(
					(
						"[%s Floor %d] %d enemies below 45%% hit: %s"
						% [cls, floor_n, misses.size(), ", ".join(misses)]
					)
				)

	print("Hit chance checks passed for all classes and floors")


# ---- Check: TTK ----


func _check_regular_enemy_ttk(enemies: Array[Resource], equip: Dictionary) -> void:
	if _failed:
		return

	# Track per-floor how many classes have p90 <= 8
	var p90_ok: Dictionary = {}

	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		for floor_n: int in TEST_FLOORS:
			if _failed:
				return
			var eq: Dictionary = equip[cls][floor_n]
			var weapon: Resource = eq["weapon"]
			var level: int = eq["level"]
			var stats: Dictionary = CLASS_STATS[cls]
			var is_ranged: bool = weapon != null and weapon.is_ranged_weapon
			var is_magic: bool = (
				weapon != null and (weapon.is_staff or weapon.weapon_damage_type == &"magic")
			)

			var eligible: Array[Resource] = _eligible_regular_enemies(enemies, floor_n)
			var ttks: Array[float] = []
			for e: Resource in eligible:
				var e_stats: Dictionary = _enemy_scaled_stats(e, floor_n)
				var atk_bonus: int = _player_attack_bonus(stats, weapon, level)
				var hit_chance: float = _hit_chance(atk_bonus, e_stats["ac"])
				if hit_chance <= 0.0:
					ttks.append(99.9)
					continue
				var dmg: float = _expected_damage_per_hit(
					weapon, stats, cls, level, e, is_ranged, is_magic
				)
				if dmg <= 0.0:
					ttks.append(99.9)
					continue
				ttks.append(e_stats["hp"] / (hit_chance * dmg))

			if ttks.is_empty():
				continue

			ttks.sort()
			var median: float = ttks[ttks.size() / 2]
			var p90_idx: int = int(ceil(ttks.size() * 0.9)) - 1
			var p90: float = ttks[min(p90_idx, ttks.size() - 1)]

			var band: Array = TTK_MEDIAN_BANDS.get(floor_n, [1.0, 6.0])
			if median < band[0] or median > band[1]:
				_fail(
					(
						"[%s Floor %d] median TTK=%.2f (expected %.1f-%.1f)"
						% [cls, floor_n, median, band[0], band[1]]
					)
				)

			if p90 > 10.0:
				_fail("[%s Floor %d] 90th percentile TTK=%.2f (max 10.0)" % [cls, floor_n, p90])

			if not p90_ok.has(floor_n):
				p90_ok[floor_n] = 0
			if p90 <= 8.0:
				p90_ok[floor_n] += 1

			print(
				(
					"[%s Floor %d] median TTK=%.2f, p90=%.2f (%d enemies)"
					% [cls, floor_n, median, p90, ttks.size()]
				)
			)

	for floor_n: int in TEST_FLOORS:
		var ok: int = p90_ok.get(floor_n, 0)
		if ok < 2:
			_fail("Floor %d: only %d classes have p90 TTK <=8 (need >=2)" % [floor_n, ok])


# ---- Check: Enemy Pressure ----


func _check_regular_enemy_pressure(enemies: Array[Resource], equip: Dictionary) -> void:
	if _failed:
		return

	for cls: StringName in [&"fighter", &"ranger", &"wizard"]:
		for floor_n: int in TEST_FLOORS:
			if _failed:
				return
			var eq: Dictionary = equip[cls][floor_n]
			var stats: Dictionary = CLASS_STATS[cls]
			var level: int = eq["level"]
			var armor: Resource = eq["armor"]
			var accessory: Resource = eq["accessory"]
			var player_ac: int = _player_ac(stats, armor, accessory)
			var max_hp: int = _player_max_hp(stats, level)

			var eligible: Array[Resource] = _eligible_regular_enemies(enemies, floor_n)
			var pressures: Array[float] = []
			var special_pressures: Array[float] = []
			var bad_pressures: Array[String] = []

			for e: Resource in eligible:
				var ep: int = _enemy_attack_bonus(e, floor_n)
				var hit_chance: float = _hit_chance(ep, player_ac)
				var dmg: float = _enemy_expected_damage(e, floor_n)
				var pressure: float = (hit_chance * dmg) / float(max_hp) * 100.0
				pressures.append(pressure)

				# Special attacks (ranged/fireball unavoidable)
				var e_stats: Dictionary = _enemy_scaled_stats(e, floor_n)
				var special_bonus: int = e_stats["special_bonus"]
				var ranged_dmg: float = _enemy_ranged_expected_damage(e, floor_n, special_bonus)
				var fb_dmg: float = _enemy_fireball_expected_damage(e, floor_n, special_bonus)
				var special_max: float = 0.0
				if ranged_dmg > 0.0:
					special_max = max(special_max, ranged_dmg)
				if fb_dmg > 0.0:
					special_max = max(special_max, fb_dmg)
				if special_max > 0.0:
					var sp: float = special_max / float(max_hp) * 100.0
					special_pressures.append(sp)
					if sp > 35.0:
						bad_pressures.append("%s: special=%.1f%%HP" % [e.display_name, sp])

			if bad_pressures.size() > 0:
				_fail(
					(
						"[%s Floor %d] Special pressure >35%%: %s"
						% [cls, floor_n, ", ".join(bad_pressures)]
					)
				)

			# Early filler may be deliberately low-pressure; the median must rise with depth.
			if pressures.size() > 0:
				pressures.sort()
				var median_pressure: float = pressures[pressures.size() / 2]
				var high: float = pressures[pressures.size() - 1]
				var median_floor: float = 3.5 if floor_n <= 7 else (4.5 if floor_n <= 10 else 5.5)
				if median_pressure < median_floor:
					_fail(
						(
							"[%s Floor %d] Median enemy pressure = %.1f%% (min %.0f%%)"
							% [cls, floor_n, median_pressure, median_floor]
						)
					)
				if high > 35.0:
					_fail(
						(
							"[%s Floor %d] Max enemy pressure = %.1f%% (max 35%%)"
							% [cls, floor_n, high]
						)
					)

			# Two simultaneous enemies become more dangerous as the run progresses.
			if pressures.size() >= 2:
				pressures.sort()
				var top2: float = pressures[pressures.size() - 1] + pressures[pressures.size() - 2]
				var top2_floor: float = 10.0 if floor_n <= 7 else (13.0 if floor_n <= 10 else 18.0)
				if top2 < top2_floor or top2 > 65.0:
					_fail(
						(
							"[%s Floor %d] Top-two enemy pressure = %.1f%% (expected %.0f-65%%)"
							% [cls, floor_n, top2, top2_floor]
						)
					)

	print("Enemy pressure checks passed for all classes and floors")


func _fail(msg: String) -> void:
	if not _failed:
		_failed = true
	printerr("FAIL: " + msg)


func _print_fail_summary() -> void:
	printerr("Test failed, see errors above")
	quit(1)
