## Focused balance-pass contract tests.
##
## Verifies: Mythic/Ascended shop floor gates and price multipliers,
## Orc max-floor exclusion, current-floor healing potion at floor 10,
## final-floor enemy pool (Abyss Knight, Lich, Ancient Dragon),
## and enemy special-attack scaling that does NOT mutate template resources.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_balance_scaling.gd
extends SceneTree

const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const FINAL_FLOOR: int = 25
const SHOP_EFF_FACTOR: float = 0.25

var _gm: Node
var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


# _run only has one explicit return (GameManager missing guard).
# Phase blocks are wrapped in `if not _failed` so a check failure
# in any phase skips remaining phases without additional returns.
# Each check function also self-aborts if _failed is already set.
func _run() -> void:
	seed(123456)
	_gm = root.get_node_or_null("/root/GameManager")
	if _gm == null:
		_fail("GameManager autoload missing")
		return
	_gm.prepare_character("debug", {})
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame

	# ---- floor 10 ----
	while _gm.current_floor < 10:
		game._debug_descend_deeper()
		await process_frame
	if _gm.current_floor != 10:
		_fail("reached floor %d, expected 10" % _gm.current_floor)

	if not _failed:
		_check_floor10_shop_no_mythic_ascended(game)
		_check_floor10_healing_potion(game)

	# ---- floor 25 ----
	while _gm.current_floor < FINAL_FLOOR:
		game._debug_descend_deeper()
		await process_frame
	if _gm.current_floor != FINAL_FLOOR:
		_fail("reached floor %d, expected %d" % [_gm.current_floor, FINAL_FLOOR])

	if not _failed:
		_check_floor25_shop_candidates_all_mythic_ascended(game)
		_check_floor25_generated_stock_has_endgame_items(game)
		_check_final_floor_enemy_pool(game)
		_check_enemy_scaling_does_not_mutate_template(game)

	# ---- pricing (standalone) ----
	if not _failed:
		_check_mythic_ascended_pricing()

	if not _failed:
		print("balance scaling check passed")
		quit(0)


# ---------------------------------------------------------------------------
#  Floor 10 — shop candidates exclude Mythic/Ascended items
# ---------------------------------------------------------------------------


func _check_floor10_shop_no_mythic_ascended(game: Node) -> void:
	if _failed:
		return
	var eff: int = game._get_effective_shop_floor(10)
	var expected_eff: int = 10 + 1 + int(ceil(10 * SHOP_EFF_FACTOR))  # = 14
	if eff != expected_eff:
		_fail("floor 10 effective shop floor = %d, expected %d" % [eff, expected_eff])
		return

	var candidates: Array = game._get_shop_candidates_for_floor(10, eff)
	for item: Resource in candidates:
		if item.rarity >= ItemDataScript.ItemRarity.MYTHIC:
			_fail(
				(
					"floor 10 candidate %s is Mythic/Ascended (rarity=%d, min_floor=%d)"
					% [item.display_name, item.rarity, item.min_floor]
				)
			)
			return
	print("  floor 10 shop: %d candidates, no Mythic/Ascended items" % candidates.size())


# ---------------------------------------------------------------------------
#  Floor 10 — guaranteed healing potion uses current-floor items
# ---------------------------------------------------------------------------


func _check_floor10_healing_potion(game: Node) -> void:
	if _failed:
		return
	var eff: int = game._get_effective_shop_floor(10)
	# potion_floor = floor_number (10) since 10 > 4
	var potion: Resource = game._choose_guaranteed_shop_potion(10, eff)
	if potion == null:
		_fail("floor 10 has no guaranteed shop potion")
		return
	if potion.min_floor > 10:
		_fail(
			(
				(
					"floor 10 potion is %s (min_floor=%d);"
					+ " should be from floor-10-available pool"
				)
				% [potion.display_name, potion.min_floor]
			)
		)
		return
	# Must NOT be Ascendant Elixir (min_floor=20) or Phoenix Elixir (min_floor=15)
	if potion.display_name in ["Ascendant Elixir", "Phoenix Elixir"]:
		_fail(
			(
				("floor 10 potion is %s (min_floor=%d);" + " should be a floor-10-available potion")
				% [potion.display_name, potion.min_floor]
			)
		)
		return
	print(
		(
			"  floor 10 healing: %s (min_floor=%d, healing=%d)"
			% [potion.display_name, potion.min_floor, potion.healing_amount]
		)
	)


# ---------------------------------------------------------------------------
#  Floor 25 — all Mythic/Ascended items must be candidate-eligible
# ---------------------------------------------------------------------------


func _check_floor25_shop_candidates_all_mythic_ascended(game: Node) -> void:
	if _failed:
		return
	var eff: int = game._get_effective_shop_floor(FINAL_FLOOR)
	var expected_eff: int = FINAL_FLOOR + 1 + int(ceil(FINAL_FLOOR * SHOP_EFF_FACTOR))  # = 33
	if eff != expected_eff:
		_fail("floor %d effective shop floor = %d, expected %d" % [FINAL_FLOOR, eff, expected_eff])
		return

	var candidates: Array = game._get_shop_candidates_for_floor(FINAL_FLOOR, eff)

	var expected_total: int = 0
	for item: Resource in game._item_resources:
		if item.rarity >= ItemDataScript.ItemRarity.MYTHIC:
			expected_total += 1

	var found: int = 0
	var missing: Array[String] = []
	for item: Resource in game._item_resources:
		if item.rarity >= ItemDataScript.ItemRarity.MYTHIC:
			if candidates.has(item):
				found += 1
			else:
				missing.append(item.display_name)

	if found < expected_total:
		_fail(
			(
				"floor %d candidates include %d/%d Mythic/Ascended items; missing: %s"
				% [FINAL_FLOOR, found, expected_total, ", ".join(missing)]
			)
		)
		return
	print(
		(
			"  floor %d shop: %d candidates, all %d Mythic/Ascended items present"
			% [FINAL_FLOOR, candidates.size(), found]
		)
	)


# ---------------------------------------------------------------------------
#  Floor 25 — generated stock sample contains endgame items
# ---------------------------------------------------------------------------


func _check_floor25_generated_stock_has_endgame_items(game: Node) -> void:
	if _failed:
		return
	var stock: Array = game._generate_shop_stock(FINAL_FLOOR)
	var endgame_count: int = 0
	for item: Resource in stock:
		if item.rarity >= ItemDataScript.ItemRarity.MYTHIC:
			endgame_count += 1

	if endgame_count == 0:
		_fail("floor %d generated stock has no Mythic/Ascended items (seed=123456)" % FINAL_FLOOR)
		return
	print(
		(
			"  floor %d stock: %d items, %d endgame (Mythic/Ascended)"
			% [FINAL_FLOOR, stock.size(), endgame_count]
		)
	)


# ---------------------------------------------------------------------------
#  Final-floor enemy pool — excludes Orc; includes Abyss Knight, Lich, Dragon
# ---------------------------------------------------------------------------


func _check_final_floor_enemy_pool(game: Node) -> void:
	if _failed:
		return
	var orc_excluded: bool = true
	var abyss_ok: bool = false
	var lich_ok: bool = false
	var dragon_ok: bool = false

	for enemy_data: Resource in game._enemy_resources:
		var can_spawn: bool = game._can_spawn_enemy(enemy_data, FINAL_FLOOR)
		match enemy_data.display_name:
			"Orc":
				orc_excluded = not can_spawn
			"Abyss Knight":
				abyss_ok = can_spawn
			"Lich":
				lich_ok = can_spawn
			"Ancient Dragon":
				dragon_ok = can_spawn

	if not orc_excluded:
		_fail("Orc can spawn at floor %d, but max_floor=16" % FINAL_FLOOR)
		return
	if not abyss_ok:
		_fail("Abyss Knight cannot spawn at floor %d" % FINAL_FLOOR)
		return
	if not lich_ok:
		_fail("Lich cannot spawn at floor %d" % FINAL_FLOOR)
		return
	if not dragon_ok:
		_fail("Ancient Dragon cannot spawn at floor %d" % FINAL_FLOOR)
		return
	print("  final-floor enemy pool: Orc excluded, Abyss Knight/Lich/Ancient Dragon included")


# ---------------------------------------------------------------------------
#  Enemy special-attack scaling does NOT mutate the shared template resource
# ---------------------------------------------------------------------------


func _check_enemy_scaling_does_not_mutate_template(game: Node) -> void:
	if _failed:
		return
	var lich_src: Resource = load("res://resources/enemies/lich.tres")
	var dragon_src: Resource = load("res://resources/enemies/ancient_dragon.tres")

	var base_lich_ranged: int = lich_src.ranged_damage_bonus
	var base_dragon_fireball: int = dragon_src.fireball_damage_bonus

	# Spawn at two different floors; scaling adds floor(depth_bonus / 6).
	# Floor 10 depth=9  -> special bonus = 1
	# Floor 25 depth=24 -> special bonus = 4
	var e_low: Node = game._spawn_enemy_instance(lich_src, Vector2i(0, 0), 10, true)
	var e_high: Node = game._spawn_enemy_instance(lich_src, Vector2i(0, 0), FINAL_FLOOR, true)

	var low_bonus: int = e_low.enemy_data.ranged_damage_bonus
	var high_bonus: int = e_high.enemy_data.ranged_damage_bonus

	if high_bonus <= low_bonus:
		_fail(
			(
				("Lich floor %d (ranged_bonus=%d) should be > floor 10 (ranged_bonus=%d)")
				% [FINAL_FLOOR, high_bonus, low_bonus]
			)
		)
		return

	if lich_src.ranged_damage_bonus != base_lich_ranged:
		_fail(
			(
				("Lich template mutated: original ranged_bonus=%d, after test=%d")
				% [base_lich_ranged, lich_src.ranged_damage_bonus]
			)
		)
		return

	# Dragon - fireball scaling
	var d_low: Node = game._spawn_enemy_instance(dragon_src, Vector2i(0, 0), 10, true)
	var d_high: Node = game._spawn_enemy_instance(dragon_src, Vector2i(0, 0), FINAL_FLOOR, true)

	var d_low_fb: int = d_low.enemy_data.fireball_damage_bonus
	var d_high_fb: int = d_high.enemy_data.fireball_damage_bonus

	if d_high_fb <= d_low_fb:
		_fail(
			(
				("Dragon floor %d (fireball_bonus=%d) should be > floor 10 (fireball_bonus=%d)")
				% [FINAL_FLOOR, d_high_fb, d_low_fb]
			)
		)
		return

	if dragon_src.fireball_damage_bonus != base_dragon_fireball:
		_fail(
			(
				("Dragon template mutated: original fireball_bonus=%d, after test=%d")
				% [base_dragon_fireball, dragon_src.fireball_damage_bonus]
			)
		)
		return

	print(
		(
			"  enemy scaling: Lich ranged %d->%d, Dragon fireball %d->%d, templates unchanged"
			% [low_bonus, high_bonus, d_low_fb, d_high_fb]
		)
	)


# ---------------------------------------------------------------------------
#  Mythic/Ascended get_price() reflects current multipliers
# ---------------------------------------------------------------------------


func _check_mythic_ascended_pricing() -> void:
	if _failed:
		return
	# MYTHIC    multiplier = 8.0     -> ceil(base * 8.0)
	# ASCENDED  multiplier = 12.0    -> ceil(base * 12.0)
	var expected: Dictionary = {
		"res://resources/items/starfall_charm.tres": 3600,
		"res://resources/items/voidglass_rapier.tres": 4160,
		"res://resources/items/phoenix_elixir.tres": 3040,
		"res://resources/items/ascended_aegis.tres": 9120,
		"res://resources/items/ascended_sword.tres": 9360,
		"res://resources/items/celestial_greatbow.tres": 8640,
		"res://resources/items/crown_of_the_deep.tres": 10800,
		"res://resources/items/ascendant_elixir.tres": 7680,
	}

	for path: String in expected:
		var item: Resource = load(path)
		var got: int = item.get_price()
		if got != expected[path]:
			_fail(
				(
					("%s get_price() = %d, expected %d" + " (base_price=%d, rarity=%d)")
					% [path, got, expected[path], item.base_price, item.rarity]
				)
			)
			return
	print("  item pricing: %d Mythic/Ascended items match multipliers" % expected.size())


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
