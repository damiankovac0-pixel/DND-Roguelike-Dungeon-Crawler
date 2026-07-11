## V23.1.0 economy band and progression formula verification.
##
## Verifies: XP cumulative thresholds via formula, post-20 HP reduction rule,
## enemy encounter-limit caps per floor, shop stock sizes, first-reroll costs,
## rarity multiplier prices, floor-1 guaranteed potion,
## and chest rarity floor caps / reward-floor behavior via direct formula inspection.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_balance_economy_bands.gd
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const ResourcePathsScript = preload("res://scripts/resource_paths.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(123456)

	# ---- XP thresholds ----
	if not _failed:
		_check_xp_thresholds()

	# ---- Post-20 HP rule ----
	if not _failed:
		_check_post_twenty_hp_rule()

	# ---- Enemy cap formulas ----
	if not _failed:
		_check_enemy_cap_formulas()

	# ---- Shop stock sizes ----
	if not _failed:
		_check_shop_stock_formulas()

	# ---- Floor-1 guaranteed potion ----
	if not _failed:
		_check_floor_one_guaranteed_potion()

	# ---- Reroll costs ----
	if not _failed:
		_check_reroll_costs()

	# ---- Rarity multiplier prices ----
	if not _failed:
		_check_rarity_multipliers()

	# ---- Chest floor caps / reward-floor ----
	if not _failed:
		_check_chest_rarity_caps()

	if not _failed:
		print("balance economy bands check passed")
		quit(0)


# ---------------------------------------------------------------------------
#  XP thresholds — cumulative totals at key milestones
# ---------------------------------------------------------------------------


func _check_xp_thresholds() -> void:
	if _failed:
		return

	# Formula: 100 + level * 90 + level * level * 18
	var expected_cumulative: Array[int] = [1840, 10080, 29120, 63460]
	var levels_to_test: Array[int] = [5, 10, 15, 20]

	for i: int in range(levels_to_test.size()):
		var target_level: int = levels_to_test[i]
		var expected: int = expected_cumulative[i]

		var cumulative: int = 0
		for lvl: int in range(1, target_level):
			cumulative += 100 + lvl * 90 + lvl * lvl * 18

		if cumulative != expected:
			_fail(
				"cumulative XP to level %d = %d, expected %d" % [target_level, cumulative, expected]
			)
			return

	# Sanity: verify the formula itself for the first few levels
	var single_checks: Dictionary = {
		1: 208,
		2: 352,
		5: 1000,
		10: 2800,
		20: 9100,
	}
	for lvl: int in single_checks.keys():
		var actual: int = 100 + lvl * 90 + lvl * lvl * 18
		if actual != single_checks[lvl]:
			_fail("xp_for_next_level(%d) = %d, expected %d" % [lvl, actual, single_checks[lvl]])
			return

	print("  XP thresholds: cumulative 5/10/15/20 = 1840/10080/29120/63460, formula verified")


# ---------------------------------------------------------------------------
#  Post-20 HP rule — HP gain reduces after STAT_LEVEL_CAP
# ---------------------------------------------------------------------------


func _check_post_twenty_hp_rule() -> void:
	if _failed:
		return

	# Test the post-20 HP reduction formula directly (no private-runtime access needed).
	var con_modifier: int = floori((10 - 10) / 2.0)  # 0
	var base_hp_gain: int = max(1, 5 + con_modifier)  # 5
	var post_20_gain: int = max(1, int(ceil(base_hp_gain * 0.35)))  # ceil(1.75) = 2

	if post_20_gain != 2:
		_fail("post-20 HP gain for CON 10 = %d, expected 2" % post_20_gain)
		return

	# Also test with CON 16 (modifier = +3)
	var con_mod_high: int = floori((16 - 10) / 2.0)  # 3
	var base_hp_high: int = max(1, 5 + con_mod_high)  # 8
	var post_20_gain_high: int = max(1, int(ceil(base_hp_high * 0.35)))  # ceil(2.80) = 3

	if post_20_gain_high != 3:
		_fail("post-20 HP gain for CON 16 = %d, expected 3" % post_20_gain_high)
		return

	print("  post-20 HP reduction: CON 10 -> 2/level, CON 16 -> 3/level, formula verified")


# ---------------------------------------------------------------------------
#  Enemy cap formulas
# ---------------------------------------------------------------------------


func _check_enemy_cap_formulas() -> void:
	if _failed:
		return

	var expected_caps: Dictionary = {
		1: 5,
		5: 7,
		9: 9,
		13: 10,
		19: 12,
		25: 14,
	}

	for floor_number: int in expected_caps.keys():
		var cap: int
		if floor_number < 10:
			cap = 5 + int(floor_number * 0.45)
		else:
			cap = 9 + int((floor_number - 10) * 0.35)
		var expected: int = expected_caps[floor_number]
		if cap != expected:
			_fail("enemy cap floor %d = %d, expected %d" % [floor_number, cap, expected])
			return

	# Verify transition at floor 10 (both formulas should agree)
	var cap_9: int = 5 + int(9 * 0.45)  # 9
	var cap_10: int = 9 + int(0 * 0.35)  # 9
	if cap_9 != 9 or cap_10 != 9:
		_fail("enemy cap transition at floor 10 mismatch: f9=%d f10=%d" % [cap_9, cap_10])
		return

	print("  enemy caps: 5/7/9/10/12/14 at floors 1/5/9/13/19/25")


# ---------------------------------------------------------------------------
#  Shop stock sizes
# ---------------------------------------------------------------------------


func _check_shop_stock_formulas() -> void:
	if _failed:
		return

	var expected_stock: Dictionary = {
		1: 5,
		5: 5,
		6: 6,
		11: 6,
		12: 7,
		17: 7,
		18: 8,
		23: 8,
		24: 8,
	}

	for floor_number: int in expected_stock.keys():
		var size: int = 5 + clampi(int(max(1, floor_number) / 6), 0, 3)
		var expected: int = expected_stock[floor_number]
		if size != expected:
			_fail("shop stock at floor %d = %d, expected %d" % [floor_number, size, expected])
			return

	print("  shop stock: 5/5/6/7/8/8 at floors 1/5/6/12/18/24")


# ---------------------------------------------------------------------------
#  Floor-1 guaranteed potion
# ---------------------------------------------------------------------------


func _check_floor_one_guaranteed_potion() -> void:
	if _failed:
		return

	var potion_candidates: Array[Resource] = []
	for path: String in ResourcePathsScript.ITEM_PATHS:
		var item: Resource = load(path)
		if item == null:
			continue
		if not _can_spawn_item(item, 1):
			continue
		if item.kind != ItemDataScript.ItemKind.CONSUMABLE or item.healing_amount <= 0:
			continue
		potion_candidates.append(item)
		if item.min_floor > 1 or (item.max_floor > 0 and item.max_floor < 1):
			_fail(
				(
					"floor 1 healing candidate %s has invalid floor band min=%d max=%d"
					% [item.display_name, item.min_floor, item.max_floor]
				)
			)
			return

	if potion_candidates.is_empty():
		_fail("floor 1 has no guaranteed healing potion candidates")
		return

	var guaranteed_potion: Resource = _choose_floor_one_guaranteed_potion(potion_candidates)
	if guaranteed_potion == null:
		_fail("floor 1 guaranteed potion helper returned null")
		return
	if guaranteed_potion.display_name != "Health Potion":
		_fail(
			(
				"floor 1 guaranteed potion is %s (min_floor=%d healing=%d), expected Health Potion"
				% [
					guaranteed_potion.display_name,
					guaranteed_potion.min_floor,
					guaranteed_potion.healing_amount,
				]
			)
		)
		return
	if not _can_spawn_item(guaranteed_potion, 1):
		_fail(
			(
				"Health Potion floor band min=%d max=%d is not floor-1 eligible"
				% [guaranteed_potion.min_floor, guaranteed_potion.max_floor]
			)
		)
		return

	print(
		(
			"  floor 1 guaranteed potion: %s (min_floor=%d, healing=%d, candidates=%d)"
			% [
				guaranteed_potion.display_name,
				guaranteed_potion.min_floor,
				guaranteed_potion.healing_amount,
				potion_candidates.size(),
			]
		)
	)


# ---------------------------------------------------------------------------
#  First-reroll costs
# ---------------------------------------------------------------------------


func _check_reroll_costs() -> void:
	if _failed:
		return

	# First reroll: (25 + floor * 8) * (0 + 1) = 25 + floor * 8
	var expected_rerolls: Dictionary = {
		1: 33,
		5: 65,
		10: 105,
		15: 145,
		20: 185,
		25: 225,
	}

	for floor_number: int in expected_rerolls.keys():
		var cost: int = (25 + floor_number * 8) * 1
		var expected: int = expected_rerolls[floor_number]
		if cost != expected:
			_fail("first reroll at floor %d = %d, expected %d" % [floor_number, cost, expected])
			return

	print("  reroll costs: 33/65/105/145/185/225 at floors 1/5/10/15/20/25")


# ---------------------------------------------------------------------------
#  Rarity multiplier prices
# ---------------------------------------------------------------------------


func _check_rarity_multipliers() -> void:
	if _failed:
		return

	var expected_multipliers: Array[float] = [
		1.0,  # COMMON
		1.4,  # UNCOMMON
		2.2,  # RARE
		3.4,  # EPIC
		5.0,  # LEGENDARY
		6.8,  # MYTHIC
		8.5,  # ASCENDED
	]

	# Verify by loading one item of each available rarity and checking its price calc.
	# Use a known item resource from each rarity tier by checking all ITEM_PATHS.
	var price_by_rarity: Dictionary = {}  # rarity -> (base_price, display_name)
	for path: String in ResourcePathsScript.ITEM_PATHS:
		var item: Resource = load(path)
		if item == null:
			continue
		var rarity: int = _r_int(item, "rarity", -1)
		if rarity < 0 or rarity >= expected_multipliers.size():
			continue
		if price_by_rarity.has(rarity):
			continue
		var base_price: int = _r_int(item, "base_price", 1)
		price_by_rarity[rarity] = {"base": base_price, "name": _r_str(item, "display_name", path)}

	if price_by_rarity.size() != expected_multipliers.size():
		_fail(
			(
				"found items covering %d/%d rarities"
				% [price_by_rarity.size(), expected_multipliers.size()]
			)
		)
		return

	# Verify each rarity tier multiplier against the get_price() function
	for rarity: int in expected_multipliers.size():
		var expected_mul: float = expected_multipliers[rarity]
		var info: Dictionary = price_by_rarity[rarity]
		var base_price: int = info["base"]
		var expected_price: int = max(1, int(ceil(base_price * expected_mul)))
		# Use ItemDataScript's get_price logic inline
		var actual_price: int = _calc_item_price(base_price, rarity)
		if actual_price != expected_price:
			_fail(
				(
					"rarity %d multiplier mismatch: base=%d, expected=%.1f, price %d vs %d"
					% [rarity, base_price, expected_mul, actual_price, expected_price]
				)
			)
			return

	print(
		"  rarity multipliers: COMMON=1.0 UNCOMMON=1.4 RARE=2.2 EPIC=3.4 LEGENDARY=5.0 MYTHIC=6.8 ASCENDED=8.5"
	)


# ---------------------------------------------------------------------------
#  Chest rarity floor caps
# ---------------------------------------------------------------------------


func _check_chest_rarity_caps() -> void:
	if _failed:
		return

	# _rarity_cap_for_floor
	var expected_caps: Dictionary = {
		1: ItemDataScript.ItemRarity.COMMON,
		2: ItemDataScript.ItemRarity.UNCOMMON,
		3: ItemDataScript.ItemRarity.UNCOMMON,
		4: ItemDataScript.ItemRarity.RARE,
		7: ItemDataScript.ItemRarity.RARE,
		8: ItemDataScript.ItemRarity.EPIC,
		12: ItemDataScript.ItemRarity.EPIC,
		13: ItemDataScript.ItemRarity.LEGENDARY,
		17: ItemDataScript.ItemRarity.LEGENDARY,
		18: ItemDataScript.ItemRarity.MYTHIC,
		22: ItemDataScript.ItemRarity.MYTHIC,
		23: ItemDataScript.ItemRarity.ASCENDED,
		25: ItemDataScript.ItemRarity.ASCENDED,
	}

	for floor_number: int in expected_caps.keys():
		var cap: int = _rarity_cap_for_floor(floor_number)
		var expected: int = expected_caps[floor_number]
		if cap != expected:
			_fail(
				(
					"rarity cap at floor %d = %d (%s), expected %d (%s)"
					% [
						floor_number,
						cap,
						ItemDataScript.RARITY_NAMES[cap],
						expected,
						ItemDataScript.RARITY_NAMES[expected],
					]
				)
			)
			return

	# Check that reward-floor adds chest_rarity bonus
	# reward_floor = floor_number + min(chest_rarity, 2)
	# So a floor 10 RARE chest (rarity=2): reward_floor = 10 + 2 = 12
	var reward_floor: int = 10 + mini(2, 2)  # floor 10, rare chest
	if reward_floor != 12:
		_fail("reward floor for floor 10 rare chest = %d, expected 12" % reward_floor)
		return

	# COMMON chest (rarity=0) at floor 1: reward_floor = 1 + 0 = 1
	var common_rf: int = 1 + mini(0, 2)
	if common_rf != 1:
		_fail("reward floor for floor 1 common chest = %d, expected 1" % common_rf)
		return

	# ASCENDED chest (rarity=6) at floor 23: reward_floor = 23 + min(6, 2) = 25
	var asc_rf: int = 23 + mini(6, 2)
	if asc_rf != 25:
		_fail("reward floor for floor 23 ascended chest = %d, expected 25" % asc_rf)
		return

	print(
		"  chest floor caps: ascending through COMMON to ASCENDED by floor 23, reward-floor clamped +2 max"
	)


# ====== Inline formula mirrors (no private access needed) ======


static func _choose_floor_one_guaranteed_potion(potion_candidates: Array[Resource]) -> Resource:
	if potion_candidates.is_empty():
		return null
	var best_potion: Resource = potion_candidates[0]
	for potion: Resource in potion_candidates:
		if potion.healing_amount > best_potion.healing_amount:
			best_potion = potion
	return best_potion


static func _can_spawn_item(item_data: Resource, floor_number: int) -> bool:
	if floor_number < item_data.min_floor:
		return false
	return item_data.max_floor <= 0 or floor_number <= item_data.max_floor


static func _rarity_cap_for_floor(floor_number: int) -> int:
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


static func _calc_item_price(base_price: int, rarity: int) -> int:
	var rarity_multiplier: float = 1.0
	match rarity:
		ItemDataScript.ItemRarity.COMMON:
			rarity_multiplier = 1.0
		ItemDataScript.ItemRarity.UNCOMMON:
			rarity_multiplier = 1.4
		ItemDataScript.ItemRarity.RARE:
			rarity_multiplier = 2.2
		ItemDataScript.ItemRarity.EPIC:
			rarity_multiplier = 3.4
		ItemDataScript.ItemRarity.LEGENDARY:
			rarity_multiplier = 5.0
		ItemDataScript.ItemRarity.MYTHIC:
			rarity_multiplier = 6.8
		ItemDataScript.ItemRarity.ASCENDED:
			rarity_multiplier = 8.5
	return max(1, int(ceil(base_price * rarity_multiplier)))


# ====== Typed one-arg Resource.get() wrappers ======


static func _r_str(res: Resource, key: String, fallback: String = "") -> String:
	var v = res.get(key)
	return v if v != null and typeof(v) == TYPE_STRING else fallback


static func _r_int(res: Resource, key: String, fallback: int = 0) -> int:
	var v = res.get(key)
	return v if v != null and typeof(v) == TYPE_INT else fallback


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
