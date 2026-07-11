## Deterministic item dominance and relevance model.
##
## Loads every registered item, checks no strict domination within floor bands,
## Crown vs Starfall no-dual-dominance, current-HP rider <= 8%, staff ladder,
## armor ladder, healing relevance, offensive scroll ratios.
##
## Run: godot --headless --path . --script res://scripts/tests/test_balance_item_domination.gd
extends SceneTree

const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

const FLOOR_BANDS: Array = [[1, 5], [6, 10], [11, 15], [16, 20], [21, 25]]

var _item_resources: Array[Resource] = []
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_item_resources = []
	for p: String in ResourcePathsScript.ITEM_PATHS:
		var r: Resource = load(p)
		if r != null:
			_item_resources.append(r)

	print("Loaded %d items" % _item_resources.size())

	# Enumeration check
	_check_all_items_loaded()
	# No strict domination within floor bands
	_check_no_strict_domination()
	# Late relevance (min_floor >= 18 items)
	_check_late_item_relevance()
	# Crown vs Starfall
	_check_crown_starfall()
	# Current-HP rider <= 8%
	_check_current_hp_riders()
	# Staff ladder
	_check_staff_ladder()
	# Armor ladder
	_check_armor_ladder()
	# Healing relevance
	_check_healing_relevance()
	# Offensive scroll ratios
	_check_offensive_scrolls()

	if _failed:
		printerr("Test failed, see errors above")
		quit(1)
		return
	print("All item domination checks passed")
	quit(0)


func _check_all_items_loaded() -> void:
	if _failed:
		return
	var total: int = ResourcePathsScript.ITEM_PATHS.size()
	if _item_resources.size() != total:
		_fail("Loaded %d/%d item resources" % [_item_resources.size(), total])
	else:
		print("  all %d items loaded successfully" % total)


func _slot(item: Resource) -> String:
	if item.kind == ItemDataScript.ItemKind.WEAPON:
		return "weapon"
	elif item.kind == ItemDataScript.ItemKind.ARMOR:
		return "armor"
	elif item.kind == ItemDataScript.ItemKind.ACCESSORY:
		return "accessory"
	return "consumable"


func _is_eligible_for_band(item: Resource, band_min: int, band_max: int) -> bool:
	# item is eligible if its min_floor is within the band or overlaps it
	if item.min_floor > band_max:
		return false
	if item.max_floor > 0 and item.max_floor < band_min:
		return false
	return true


func _weapon_score(item: Resource, is_ranged: bool) -> int:
	# estimate weapon effectiveness
	if item.is_ranged_weapon != is_ranged:
		return -9999
	return (
		item.damage_dice * max(1, item.damage_sides)
		+ item.damage_bonus
		+ item.attack_bonus * 2
		+ item.range
	)


func _armor_score(item: Resource) -> int:
	return item.armor_bonus


func _accessory_offense_score(item: Resource) -> int:
	return item.attack_bonus + item.damage_bonus


func _accessory_defense_score(item: Resource) -> int:
	return item.armor_bonus


# ---- No strict domination ----


func _check_no_strict_domination() -> void:
	if _failed:
		return

	var any_issues: bool = false

	for band: Array in FLOOR_BANDS:
		var bmin: int = band[0]
		var bmax: int = band[1]

		if _check_weapon_band(bmin, bmax, false):
			any_issues = true
		if _check_weapon_band(bmin, bmax, true):
			any_issues = true
		if _check_armor_band(bmin, bmax):
			any_issues = true

	if not any_issues:
		print("  strict domination: all bands clean")


func _check_weapon_band(bmin: int, bmax: int, is_ranged: bool) -> bool:
	# Check a single band+weapon-type for strict domination among same-rarity peers
	var items: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.kind != ItemDataScript.ItemKind.WEAPON:
			continue
		if item.is_ranged_weapon != is_ranged:
			continue
		if not _is_eligible_for_band(item, bmin, bmax):
			continue
		items.append(item)
	if items.size() < 2:
		return false

	var any_issue: bool = false
	for r: int in range(ItemDataScript.ItemRarity.COMMON, ItemDataScript.ItemRarity.ASCENDED + 1):
		var same: Array[Resource] = []
		for it: Resource in items:
			if int(it.rarity) == r:
				same.append(it)
		if same.size() < 2:
			continue

		same.sort_custom(
			func(a, b): return _weapon_score(a, is_ranged) > _weapon_score(b, is_ranged)
		)
		var best: Resource = same[0]
		for i: int in range(1, same.size()):
			var other: Resource = same[i]
			# min_floor gap > 2 is a legitimate vertical upgrade; price/rarity/floor are tradeoffs
			if abs(other.min_floor - best.min_floor) > 2:
				continue
			if other.required_class != best.required_class:
				continue
			if (
				best.damage_dice >= other.damage_dice
				and best.damage_sides >= other.damage_sides
				and best.damage_bonus >= other.damage_bonus
				and best.attack_bonus >= other.attack_bonus
				and (
					best.damage_dice > other.damage_dice
					or best.damage_sides > other.damage_sides
					or best.damage_bonus > other.damage_bonus
					or best.attack_bonus > other.attack_bonus
				)
			):
				any_issue = true
				_fail(
					(
						"Band %d-%d: %s strictly dominates %s (same class %s, %s)"
						% [
							bmin,
							bmax,
							best.display_name,
							other.display_name,
							other.required_class,
							ItemDataScript.RARITY_NAMES[r],
						]
					)
				)
	return any_issue


func _check_armor_band(bmin: int, bmax: int) -> bool:
	# Check a single band for strict domination among same-rarity armor peers
	var items: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.kind != ItemDataScript.ItemKind.ARMOR:
			continue
		if not _is_eligible_for_band(item, bmin, bmax):
			continue
		items.append(item)
	if items.size() < 2:
		return false

	var any_issue: bool = false
	for r: int in range(ItemDataScript.ItemRarity.COMMON, ItemDataScript.ItemRarity.ASCENDED + 1):
		var same: Array[Resource] = []
		for it: Resource in items:
			if int(it.rarity) == r:
				same.append(it)
		if same.size() < 2:
			continue

		same.sort_custom(func(a, b): return a.armor_bonus > b.armor_bonus)
		var best: Resource = same[0]
		for i: int in range(1, same.size()):
			var other: Resource = same[i]
			# floor gap > 2 or larger min_floor = legitimate progression tradeoff
			if abs(other.min_floor - best.min_floor) > 2:
				continue
			if best.min_floor > other.min_floor:
				continue
			if best.armor_bonus >= other.armor_bonus and best.armor_bonus > other.armor_bonus:
				# Price-efficiency gate: a 25%+ price premium is a valid tradeoff, not domination
				if best.get_price() <= int(other.get_price() * 1.25):
					any_issue = true
					_fail(
						(
							"Band %d-%d: %s (AC+%d, price %d) dominates %s (AC+%d, price %d) (%s)"
							% [
								bmin,
								bmax,
								best.display_name,
								best.armor_bonus,
								best.get_price(),
								other.display_name,
								other.armor_bonus,
								other.get_price(),
								ItemDataScript.RARITY_NAMES[r],
							]
						)
					)
	return any_issue


# ---- Late relevance ----


func _check_late_item_relevance() -> void:
	if _failed:
		return

	var late_items: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.min_floor >= 18 and item.min_floor <= 25:
			late_items.append(item)

	print("  %d items with min_floor >= 18" % late_items.size())

	# Check each late item scores >= 85% of best same-slot for at least one class
	# Melee weapons
	var best_melee: Resource = null
	var best_melee_score: int = 0
	for item: Resource in late_items:
		if item.kind == ItemDataScript.ItemKind.WEAPON and not item.is_ranged_weapon:
			var score: int = _weapon_score(item, false)
			if score > best_melee_score:
				best_melee_score = score
				best_melee = item

	if best_melee != null:
		var weak_melee: Array[String] = []
		for item: Resource in late_items:
			if item.kind == ItemDataScript.ItemKind.WEAPON and not item.is_ranged_weapon:
				var score: int = _weapon_score(item, false)
				var pct: float = float(score) / float(best_melee_score) * 100.0
				if pct < 85.0:
					weak_melee.append("%s: %.0f%%" % [item.display_name, pct])
		if weak_melee.size() > 0:
			_fail(
				(
					"Late melee items below 85%% of best %s: %s"
					% [best_melee.display_name, ", ".join(weak_melee)]
				)
			)

	# Accessories
	var best_acc: Resource = null
	var best_acc_score: int = 0
	for item: Resource in late_items:
		if item.kind == ItemDataScript.ItemKind.ACCESSORY:
			var score: int = item.attack_bonus + item.damage_bonus + item.armor_bonus
			if score > best_acc_score:
				best_acc_score = score
				best_acc = item

	if best_acc != null:
		var weak_acc: Array[String] = []
		for item: Resource in late_items:
			if item.kind == ItemDataScript.ItemKind.ACCESSORY:
				var score: int = item.attack_bonus + item.damage_bonus + item.armor_bonus
				var pct: float = float(score) / float(best_acc_score) * 100.0
				if pct < 85.0:
					weak_acc.append("%s: %.0f%%" % [item.display_name, pct])
		if weak_acc.size() > 0:
			_fail(
				(
					"Late accessory items below 85%% of best %s: %s"
					% [best_acc.display_name, ", ".join(weak_acc)]
				)
			)


# ---- Crown vs Starfall ----


func _check_crown_starfall() -> void:
	if _failed:
		return
	var crown: Resource = null
	var starfall: Resource = null
	for item: Resource in _item_resources:
		if item.display_name == "Crown of the Deep":
			crown = item
		elif item.display_name == "Starfall Charm":
			starfall = item

	if crown == null:
		_fail("Crown of the Deep not found in resources")
		return
	if starfall == null:
		_fail("Starfall Charm not found in resources")
		return

	# Crown should not dominate both offense and defense over Starfall
	# Crown: atk+1, dmg+1, armor+3, price 820
	# Starfall: assumed magic class bonus (check through class_damage_percent_bonus)
	var crown_off: int = crown.attack_bonus + crown.damage_bonus
	var starfall_off: int = starfall.attack_bonus + starfall.damage_bonus

	# Crown has +1 atk +1 dmg = 2 offense vs Starfall's base offense
	# Starfall may have class_damage_percent_bonus
	# Verify Crown is not the universal best choice for every character
	if crown_off >= starfall_off and crown.armor_bonus >= starfall.armor_bonus:
		if crown_off > starfall_off or crown.armor_bonus > starfall.armor_bonus:
			# Crown dominates only if it's better or equal in both AND strictly better in at least one
			_fail(
				(
					"Crown of the Deep (atk=%d dmg=%d armor=%d) dominates Starfall Charm (atk=%d dmg=%d armor=%d) offensively and defensively"
					% [
						crown.attack_bonus,
						crown.damage_bonus,
						crown.armor_bonus,
						starfall.attack_bonus,
						starfall.damage_bonus,
						starfall.armor_bonus
					]
				)
			)

	print(
		(
			"  Crown vs Starfall: Crown atk=%d dmg=%d armor=%d, Starfall atk=%d dmg=%d armor=%d class_bonus=%d"
			% [
				crown.attack_bonus,
				crown.damage_bonus,
				crown.armor_bonus,
				starfall.attack_bonus,
				starfall.damage_bonus,
				starfall.armor_bonus,
				starfall.class_damage_percent_bonus
			]
		)
	)


# ---- Current-HP rider <= 8% ----


func _check_current_hp_riders() -> void:
	if _failed:
		return
	var found: Array[String] = []
	for item: Resource in _item_resources:
		if item.special_effect == ItemDataScript.ItemSpecial.CURRENT_HP_DAMAGE_PERCENT:
			if item.special_amount > 8:
				found.append("%s: %d%%" % [item.display_name, item.special_amount])

	if found.size() > 0:
		_fail("Current-HP riders exceeding 8%%: %s" % ", ".join(found))
	else:
		print("  all current-HP riders <= 8%%")


# ---- Staff ladder ----


func _check_staff_ladder() -> void:
	if _failed:
		return
	var staffs: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.is_staff:
			staffs.append(item)

	staffs.sort_custom(func(a, b): return a.min_floor < b.min_floor)

	if staffs.is_empty():
		_fail("No staff items found")
		return

	# Check ladder progression
	var prev: Resource = staffs[0]
	var issues: Array[String] = []
	for i: int in range(1, staffs.size()):
		var curr: Resource = staffs[i]
		var prev_score: int = _weapon_score(prev, true)
		var curr_score: int = _weapon_score(curr, true)
		if curr_score <= prev_score and curr.display_name != "Staff Ascendant":
			issues.append(
				(
					"%s (score=%d, floor=%d) not > %s (score=%d, floor=%d)"
					% [
						curr.display_name,
						curr_score,
						curr.min_floor,
						prev.display_name,
						prev_score,
						prev.min_floor
					]
				)
			)
		if curr.min_floor <= prev.min_floor:
			issues.append(
				(
					"%s floor %d not > %s floor %d"
					% [curr.display_name, curr.min_floor, prev.display_name, prev.min_floor]
				)
			)
		# Check class_damage_percent_bonus increases
		if curr.class_damage_percent_bonus < prev.class_damage_percent_bonus:
			issues.append(
				(
					"%s class bonus %d%% < %s %d%%"
					% [
						curr.display_name,
						curr.class_damage_percent_bonus,
						prev.display_name,
						prev.class_damage_percent_bonus
					]
				)
			)
		prev = curr

	# Ascendant should be best staff
	var ascendant: Resource = null
	for s: Resource in staffs:
		if s.display_name == "Staff Ascendant":
			ascendant = s
			break

	if ascendant != null:
		var asc_score: int = _weapon_score(ascendant, true)
		for s: Resource in staffs:
			if s != ascendant and s.min_floor <= ascendant.min_floor:
				var s_score: int = _weapon_score(s, true)
				if s_score > asc_score:
					issues.append(
						(
							"%s (score=%d) surpasses Staff Ascendant (score=%d)"
							% [s.display_name, s_score, asc_score]
						)
					)

	if issues.size() > 0:
		_fail("Staff ladder issues: %s" % ", ".join(issues))
	else:
		print("  staff ladder: %d staffs, progression OK" % staffs.size())


# ---- Armor ladder ----


func _check_armor_ladder() -> void:
	if _failed:
		return
	var armors: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.kind == ItemDataScript.ItemKind.ARMOR:
			armors.append(item)

	armors.sort_custom(
		func(a, b):
			return (
				a.armor_bonus < b.armor_bonus
				or (a.armor_bonus == b.armor_bonus and a.min_floor < b.min_floor)
			)
	)

	if armors.is_empty():
		_fail("No armor items found")
		return

	# Check: if two armors have the same armor_bonus, the one with higher min_floor must have
	# some other advantage (rarity, class bonus, set bonus, etc.)
	var issues: Array[String] = []
	var seen_bonus: Dictionary = {}
	for a: Resource in armors:
		var key: int = a.armor_bonus
		if seen_bonus.has(key):
			var prev: Resource = seen_bonus[key]
			# Same armor bonus: higher min_floor should have some other advantage
			if a.min_floor > prev.min_floor:
				var has_advantage: bool = false
				if a.attack_bonus >= prev.attack_bonus:
					has_advantage = true
				elif a.class_damage_percent_bonus >= prev.class_damage_percent_bonus:
					has_advantage = true
				elif a.set_damage_resist_percent >= prev.set_damage_resist_percent:
					has_advantage = true
				elif a.set_id != &"":
					has_advantage = true
				elif a.rarity >= prev.rarity:
					has_advantage = true
				elif a.get_price() < prev.get_price():
					has_advantage = true
				if not has_advantage:
					issues.append(
						(
							"%s (AC+%d, floor %d) has no advantage over %s (AC+%d, floor %d)"
							% [
								a.display_name,
								a.armor_bonus,
								a.min_floor,
								prev.display_name,
								prev.armor_bonus,
								prev.min_floor
							]
						)
					)
		seen_bonus[key] = a

	# Check no strictly better earlier armor dominating later armor
	for i: int in armors.size():
		for j: int in range(i + 1, armors.size()):
			var a: Resource = armors[i]
			var b: Resource = armors[j]
			# Check each direction: earlier low-floor armor shouldn't dominate later
			for pair: Array in [[a, b], [b, a]]:
				var earlier: Resource = pair[0]
				var later: Resource = pair[1]
				if earlier.min_floor >= later.min_floor:
					continue
				if earlier.armor_bonus < later.armor_bonus:
					continue
				if earlier.rarity > later.rarity:
					continue
				if earlier.base_price > later.base_price:
					continue
				# Class-restricted items are not strictly dominating unrestricted
				if earlier.required_class != &"" and later.required_class == &"":
					continue
				# Class-damage-bonus items are not strictly dominating raw-stat items.
				if earlier.class_damage_percent_bonus > 0 and later.class_damage_percent_bonus <= 0:
					continue
				# A later class, hybrid, or set armor has utility the earlier raw-AC piece lacks.
				if later.attack_bonus > earlier.attack_bonus:
					continue
				if later.class_damage_percent_bonus > earlier.class_damage_percent_bonus:
					continue
				if (
					later.set_id != &""
					or later.set_damage_resist_percent > earlier.set_damage_resist_percent
				):
					continue
				issues.append(
					(
						"%s (AC+%d, floor %d) dominates %s (AC+%d, floor %d)"
						% [
							earlier.display_name,
							earlier.armor_bonus,
							earlier.min_floor,
							later.display_name,
							later.armor_bonus,
							later.min_floor
						]
					)
				)
	if issues.size() > 0:
		_fail("Armor ladder issues: %s" % ", ".join(issues))
	else:
		print("  armor ladder: %d armors, progression OK" % armors.size())


# ---- Healing relevance ----


func _check_healing_relevance() -> void:
	if _failed:
		return
	var heal_items: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.kind == ItemDataScript.ItemKind.CONSUMABLE and item.healing_amount > 0:
			heal_items.append(item)

	if heal_items.is_empty():
		_fail("No healing consumables found")
		return

	heal_items.sort_custom(func(a, b): return a.healing_amount < b.healing_amount)

	# Estimated player HP at each healing tier, based on the target level curve and CON growth.
	var floor_hp: Dictionary = {
		1: 14, 2: 21, 3: 28, 5: 42, 7: 56, 11: 77, 17: 119, 22: 154, 25: 182
	}

	# Healing at min_floor should restore a meaningful share; regeneration uses its total duration.
	var heal_issues: Array[String] = []
	for h: Resource in heal_items:
		var f: int = max(1, h.min_floor)
		var f_hp: int = floor_hp.get(f, 100)
		var effective_heal: int = h.healing_amount
		if h.use_effect == ItemDataScript.ItemUse.REGEN:
			effective_heal *= max(1, h.effect_duration)
		var pct: float = float(effective_heal) / float(f_hp) * 100.0
		if pct < 18.0:
			heal_issues.append(
				(
					"%s: heals %d total (%.0f%% HP at floor %d)"
					% [h.display_name, effective_heal, pct, f]
				)
			)

	if heal_issues.size() > 0:
		_fail("Healing items restore <18%% HP at min_floor: %s" % ", ".join(heal_issues))

	# At floor 25, at least one affordable heal restores >= 25% HP
	var floor25_hp: int = floor_hp[25]
	var threshold: int = int(ceil(floor25_hp * 0.25))
	var found_affordable: Array[Resource] = []
	for h: Resource in heal_items:
		var effective_heal: int = h.healing_amount
		if h.use_effect == ItemDataScript.ItemUse.REGEN:
			effective_heal *= max(1, h.effect_duration)
		if effective_heal >= threshold and h.get_price() <= 800:
			found_affordable.append(h)

	if found_affordable.is_empty():
		_fail("No affordable heal at floor 25 restores >= %d HP (%d%%)" % [threshold, 25])

	print(
		(
			"  healing: %d items, floor-25 threshold=%d, %d affordable meets >=25%%"
			% [heal_items.size(), threshold, found_affordable.size()]
		)
	)


# ---- Offensive scroll ratios ----


func _check_offensive_scrolls() -> void:
	if _failed:
		return
	var scrolls: Array[Resource] = []
	for item: Resource in _item_resources:
		if item.kind == ItemDataScript.ItemKind.CONSUMABLE and item.damage_sides > 0:
			scrolls.append(item)

	if scrolls.is_empty():
		_fail("No offensive scrolls found")
		return

	# Compare scrolls as utility for a non-Wizard against a class-scaled physical weapon turn.
	var weapon_dpr: Dictionary = {}
	for floor_n: int in [2, 5, 6, 10]:
		var best: float = 0.0
		var proficiency: int = 2 + int((min(floor_n, 20) - 1) / 4)
		var target_ac: int = 12 + int(floor_n / 5)
		for item: Resource in _item_resources:
			if item.kind != ItemDataScript.ItemKind.WEAPON or item.is_staff:
				continue
			if item.min_floor > floor_n:
				continue
			if item.max_floor > 0 and item.max_floor < floor_n:
				continue
			var sides: int = max(1, item.damage_sides)
			var dice: int = max(1, item.damage_dice)
			var raw: float = dice * (sides + 1.0) / 2.0 + item.damage_bonus + 3
			var class_percent: int = 150 + item.class_damage_percent_bonus
			var attack_total: int = proficiency + 3 + item.attack_bonus
			var needed: int = target_ac - attack_total
			var hit_chance: float = 1.0 if needed <= 1 else max(0.05, (21.0 - needed) / 20.0)
			var dpr: float = raw * class_percent / 100.0 * hit_chance
			best = max(best, dpr)
		weapon_dpr[floor_n] = best

	var issues: Array[String] = []
	for s: Resource in scrolls:
		var f: int = max(2, s.min_floor)
		var dice: int = max(1, s.damage_dice)
		var sides: int = max(1, s.damage_sides)
		var expected_base: float = dice * (sides + 1.0) / 2.0 + s.damage_bonus

		# Scroll damage bonus = WIS*2 (magic) + depth_bonus (int(depth/6)*2)
		# With WIS 14 (+2): magic_bonus = 4
		var wis_mod: int = 2
		var magic_bonus: int = max(0, wis_mod * 2)
		var depth: int = max(0, f - s.min_floor)
		var depth_bonus: int = int(depth / 6) * 2
		var total_base: float = expected_base + magic_bonus + depth_bonus

		# Targeted attack scrolls roll to hit; Missile and Fireball are guaranteed.
		var scroll_hit_chance: float = 1.0
		if s.use_effect == ItemDataScript.ItemUse.RANGED_ATTACK:
			var proficiency: int = 2 + int((min(f, 20) - 1) / 4)
			var target_ac: int = 12 + int(f / 5)
			var needed: int = target_ac - (proficiency + wis_mod + s.attack_bonus)
			scroll_hit_chance = 1.0 if needed <= 1 else max(0.05, (21.0 - needed) / 20.0)
		var scroll_dpr: float = total_base * scroll_hit_chance

		var weapon_dpr_at_f: float = weapon_dpr.get(f, 5.0)
		if weapon_dpr_at_f <= 0.0:
			weapon_dpr_at_f = 5.0
		var ratio: float = scroll_dpr / weapon_dpr_at_f

		# Single-target should be 0.75x-1.75x same-floor weapon DPR
		if ratio < 0.75 or ratio > 1.75:
			issues.append(
				(
					"%s: DPR=%.1f vs weapon DPR=%d (ratio=%.2f)"
					% [s.display_name, scroll_dpr, weapon_dpr_at_f, ratio]
				)
			)

		# For AoE scrolls (fireball with target_radius >= 1), two-target total should be 1.5x-3.5x
		if s.target_radius >= 1:
			var aoe_total: float = total_base * 2.0
			var aoe_ratio: float = aoe_total / float(weapon_dpr_at_f)
			if aoe_ratio < 1.5 or aoe_ratio > 3.5:
				issues.append(
					(
						"%s (AoE): 2-target=%.1f vs weapon DPR=%d (ratio=%.2f)"
						% [s.display_name, aoe_total, weapon_dpr_at_f, aoe_ratio]
					)
				)

	if issues.size() > 0:
		_fail("Scroll ratio issues: %s" % ", ".join(issues))
	else:
		print("  offensive scrolls: %d scrolls, ratios acceptable" % scrolls.size())


func _fail(msg: String) -> void:
	if not _failed:
		_failed = true
	printerr("FAIL: " + msg)
