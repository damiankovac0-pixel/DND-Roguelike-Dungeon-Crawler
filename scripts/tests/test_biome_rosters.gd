## V11 biome roster spawn eligibility test.
##
## Verifies that _can_spawn_enemy respects biome rosters for floors 1-25,
## allows all enemies in Endless (floor 26+), bypasses max_floor in Endless so
## early-capped enemies can reappear, and still enforces min_floor in Endless.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_biome_rosters.gd
##
## Should fail on old floor-only spawn behavior (no biome roster gating)
## and pass after V11 implementation.
extends SceneTree

const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(123456)
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	gm.prepare_character("debug", {})
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame

	# ---- Catalog structural checks ----
	if not _failed:
		_check_catalog_rosters()

	# ---- Floor 1: Tower (biome 1) ----
	if not _failed:
		_check_floor_1_tower(game)

	# ---- Floor 6: Rotting Garden (biome 2) ----
	if not _failed:
		_check_floor_6_garden(game)

	# ---- Floor 11: Cinder Wastes (biome 3) ----
	if not _failed:
		_check_floor_11_cinder(game)

	# ---- Floor 16: Sunken Halls (biome 4) ----
	if not _failed:
		_check_floor_16_sunken(game)

	# ---- Floor 25: Glass Labyrinth (biome 5) ----
	if not _failed:
		_check_floor_25_glass(game)

	# ---- V20 boss resources are fixed encounters only ----
	if not _failed:
		_check_boss_resources_do_not_spawn_randomly(game)

	# ---- Floor 26: Endless Deeps start (biome 6) ----
	if not _failed:
		_check_endless_floor_26(game)

	# ---- Floor 30: Endless Deeps deep ----
	if not _failed:
		_check_endless_floor_30(game)

	if not _failed:
		print("biome roster check passed")
		quit(0)


# ---------------------------------------------------------------------------
# Catalog structural checks
# ---------------------------------------------------------------------------


func _check_catalog_rosters() -> void:
	if _failed:
		return

	# Every biome 1-5 has a non-empty roster
	for biome_index: int in range(1, 6):
		var roster: Array = BiomeCatalogScript.enemy_roster_for_biome_index(biome_index)
		if roster.is_empty():
			_fail("ENEMY_ROSTERS[%d] is empty" % biome_index)
			return

	# Biome 6 (Endless) roster may be empty; allowed for all is handled by
	# enemy_path_allowed_for_biome returning true for index 6.
	# Just verify the function returns true for any path.
	if not BiomeCatalogScript.enemy_path_allowed_for_biome("res://resources/enemies/rat.tres", 6):
		_fail("Endless should allow all enemies via enemy_path_allowed_for_biome")
		return

	# biomes_names_for_enemy_path includes Endless for every path
	var tower_enemy_names: Array[String] = BiomeCatalogScript.biome_names_for_enemy_path(
		"res://resources/enemies/rat.tres"
	)
	if not tower_enemy_names.has("Endless Deeps"):
		_fail("biome_names_for_enemy_path should always include Endless Deeps")
		return

	print("  catalog rosters: biomes 1-5 non-empty, Endless allows all")


# ---------------------------------------------------------------------------
# Floor 1 — Tower roster allows Rat/Goblin/Kobold/Bat; excludes Garden/Cinder
# ---------------------------------------------------------------------------


func _check_floor_1_tower(game: Node) -> void:
	if _failed:
		return

	# Allowed — Tower roster enemies present at floor 1
	_assert_can_spawn(
		game, "res://resources/enemies/rat.tres", 1, "Rat should spawn at floor 1 (Tower)"
	)
	_assert_can_spawn(
		game, "res://resources/enemies/goblin.tres", 1, "Goblin should spawn at floor 1 (Tower)"
	)
	_assert_can_spawn(
		game, "res://resources/enemies/kobold.tres", 1, "Kobold should spawn at floor 1 (Tower)"
	)
	_assert_can_spawn(
		game, "res://resources/enemies/bat.tres", 1, "Bat should spawn at floor 1 (Tower)"
	)

	# Denied — Garden enemies excluded by biome roster
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/thorn_lasher.tres",
		1,
		"Thorn Lasher should NOT spawn at floor 1 (Tower, not Garden)"
	)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/spore_servant.tres",
		1,
		"Spore Servant should NOT spawn at floor 1 (Tower, not Garden)"
	)

	# Denied — Cinder enemies excluded by biome roster
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/ash_revenant.tres",
		1,
		"Ash Revenant should NOT spawn at floor 1 (Tower, not Cinder)"
	)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/ember_archer.tres",
		1,
		"Ember Archer should NOT spawn at floor 1 (Tower, not Cinder)"
	)

	print("  floor 1 (Tower): Tower enemies allowed, Garden/Cinder excluded")


# ---------------------------------------------------------------------------
# Floor 6 — Garden roster allows Thorn Lasher/Spore Servant; excludes Tower-only
# ---------------------------------------------------------------------------


func _check_floor_6_garden(game: Node) -> void:
	if _failed:
		return

	# Allowed — Garden roster enemies
	_assert_can_spawn(
		game,
		"res://resources/enemies/thorn_lasher.tres",
		6,
		"Thorn Lasher should spawn at floor 6 (Garden)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/spore_servant.tres",
		6,
		"Spore Servant should spawn at floor 6 (Garden)"
	)
	_assert_can_spawn(
		game, "res://resources/enemies/zombie.tres", 6, "Zombie should spawn at floor 6 (Garden)"
	)
	_assert_can_spawn(
		game, "res://resources/enemies/orc.tres", 6, "Orc should spawn at floor 6 (Garden)"
	)

	# V23.1.0: Frost Guardian added to Garden roster
	_assert_can_spawn(
		game,
		"res://resources/enemies/frost_guardian.tres",
		6,
		"Frost Guardian should spawn at floor 6 (Garden) — V23.1.0 roster addition"
	)

	# Denied — Tower-only enemies (rejected by roster even though min_floor/max_floor would allow some)
	# Goblin: min=1, max=7 — old floor-only would ALLOW at floor 6; new rejects (Tower roster, not Garden)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/goblin.tres",
		6,
		"Goblin should NOT spawn at floor 6 (Tower roster, not Garden) — fails on old floor-only behavior"
	)
	# Skeleton: min=2, max=9 — old floor-only would ALLOW; new rejects (Tower roster)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/skeleton.tres",
		6,
		"Skeleton should NOT spawn at floor 6 (Tower roster, not Garden) — fails on old floor-only behavior"
	)
	# Bat: max_floor=5 < 6 (also rejected by old, but check tower roster)
	_assert_cannot_spawn(
		game, "res://resources/enemies/bat.tres", 6, "Bat should NOT spawn at floor 6 (max_floor=5)"
	)

	# Denied — Cinder enemies (wrong roster)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/ash_revenant.tres",
		6,
		"Ash Revenant should NOT spawn at floor 6 (min_floor=11)"
	)

	print("  floor 6 (Garden): Garden enemies allowed, Tower-only/Cinder excluded")


# ---------------------------------------------------------------------------
# Floor 11 — Cinder roster allows Ash Revenant/Ember Archer; excludes Garden
# ---------------------------------------------------------------------------


func _check_floor_11_cinder(game: Node) -> void:
	if _failed:
		return

	# Allowed — Cinder roster enemies
	_assert_can_spawn(
		game,
		"res://resources/enemies/ash_revenant.tres",
		11,
		"Ash Revenant should spawn at floor 11 (Cinder)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/ember_archer.tres",
		11,
		"Ember Archer should spawn at floor 11 (Cinder)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/ogre_brute.tres",
		11,
		"Ogre Brute should spawn at floor 11 (Cinder)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/abyss_knight.tres",
		11,
		"Abyss Knight should spawn at floor 11 (Cinder)"
	)

	# V23.1.0: Warleader and Shadow Weaver added to Cinder roster
	_assert_can_spawn(
		game,
		"res://resources/enemies/warleader.tres",
		11,
		"Warleader should spawn at floor 11 (Cinder) — V23.1.0 roster addition"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/shadow_weaver.tres",
		14,
		"Shadow Weaver should spawn at floor 14 (Cinder) — V23.1.0 roster addition"
	)
	# Denied — Garden enemy that old floor-only would have allowed
	# Orc: min=3, max=16 — old would ALLOW at floor 11 (min<=11, max>=11); new rejects (Garden roster)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/orc.tres",
		11,
		"Orc should NOT spawn at floor 11 (Garden roster, not Cinder) — fails on old floor-only behavior"
	)
	# Troll: min=9, max=0 — old would ALLOW; new rejects (Garden roster)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/troll.tres",
		11,
		"Troll should NOT spawn at floor 11 (Garden roster, not Cinder) — fails on old floor-only behavior"
	)

	# Denied — Tower enemies (wrong roster, also max_floor too low)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/goblin.tres",
		11,
		"Goblin should NOT spawn at floor 11 (max_floor=7)"
	)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/rat.tres",
		11,
		"Rat should NOT spawn at floor 11 (max_floor=4)"
	)

	print("  floor 11 (Cinder): Cinder enemies allowed, Garden/Tower excluded")


# ---------------------------------------------------------------------------
# Floor 16 — Sunken roster allows Drowned Knight/Harpooner; excludes Cinder-only
# ---------------------------------------------------------------------------


func _check_floor_16_sunken(game: Node) -> void:
	if _failed:
		return

	# Allowed — Sunken roster enemies
	_assert_can_spawn(
		game,
		"res://resources/enemies/drowned_knight.tres",
		16,
		"Drowned Knight should spawn at floor 16 (Sunken)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/harpooner.tres",
		16,
		"Harpooner should spawn at floor 16 (Sunken)"
	)

	# V23.1.0: Shadow Weaver added to Sunken roster
	_assert_can_spawn(
		game,
		"res://resources/enemies/shadow_weaver.tres",
		16,
		"Shadow Weaver should spawn at floor 16 (Sunken) — V23.1.0 roster addition"
	)
	# Denied — Cinder-only enemies that old floor-only would have allowed
	# Abyss Knight: min=11, max=0 — old would ALLOW at floor 16; new rejects (Cinder roster, not Sunken)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/abyss_knight.tres",
		16,
		"Abyss Knight should NOT spawn at floor 16 (Cinder roster, not Sunken) — fails on old floor-only behavior"
	)
	# Lich: min=12, max=0 — old would ALLOW; new rejects (Cinder roster)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/lich.tres",
		16,
		"Lich should NOT spawn at floor 16 (Cinder roster, not Sunken) — fails on old floor-only behavior"
	)

	# Denied — Cinder enemies with max_floor cap
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/ash_revenant.tres",
		16,
		"Ash Revenant should NOT spawn at floor 16 (max_floor=15)"
	)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/ember_archer.tres",
		16,
		"Ember Archer should NOT spawn at floor 16 (max_floor=15)"
	)

	print("  floor 16 (Sunken): Sunken enemies allowed, Cinder-only excluded")


# ---------------------------------------------------------------------------
# Floor 25 — Glass roster includes Abyss Knight/Lich/Dragon + Glass exclusives;
#             excludes Orc and other non-Glass enemies
# ---------------------------------------------------------------------------


func _check_floor_25_glass(game: Node) -> void:
	if _failed:
		return

	# Allowed — Glass roster core enemies
	_assert_can_spawn(
		game,
		"res://resources/enemies/abyss_knight.tres",
		25,
		"Abyss Knight should spawn at floor 25 (Glass)"
	)
	_assert_can_spawn(
		game, "res://resources/enemies/lich.tres", 25, "Lich should spawn at floor 25 (Glass)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/ancient_dragon.tres",
		25,
		"Ancient Dragon should spawn at floor 25 (Glass)"
	)

	# Allowed — Glass-exclusive enemies
	_assert_can_spawn(
		game,
		"res://resources/enemies/mirror_duelist.tres",
		25,
		"Mirror Duelist should spawn at floor 25 (Glass)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/prism_seer.tres",
		25,
		"Prism Seer should spawn at floor 25 (Glass)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/shard_golem.tres",
		25,
		"Shard Golem should spawn at floor 25 (Glass)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/glass_dragonling.tres",
		25,
		"Glass Dragonling should spawn at floor 25 (Glass)"
	)

	# Denied — Orc (max_floor=16, also wrong roster) — old floor-only would reject via max_floor too
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/orc.tres",
		25,
		"Orc should NOT spawn at floor 25 (max_floor=16)"
	)
	# Denied — Garden enemy that old floor-only would have allowed
	# Wraith: min=7, max=0 — old would ALLOW at floor 25; new rejects (Garden roster)
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/wraith.tres",
		25,
		"Wraith should NOT spawn at floor 25 (Garden roster, not Glass) — fails on old floor-only behavior"
	)
	# Denied — Tower enemy
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/goblin.tres",
		25,
		"Goblin should NOT spawn at floor 25 (max_floor=7)"
	)
	print("  floor 25 (Glass): Glass enemies allowed, Orc/Wraith/Garden excluded")


# ---------------------------------------------------------------------------
# Floor 26 — Endless Deeps: early-capped enemies reappear, Endless specials
#            by min_floor, Starved Godling waits until floor 30
# ---------------------------------------------------------------------------


func _check_endless_floor_26(game: Node) -> void:
	if _failed:
		return

	# Allowed — early-capped Tower enemies (max_floor ignored in Endless)
	# Rat: min=1, max_floor=4 — old floor-only would REJECT (4 < 26); new ALLOWS (Endless bypasses max_floor)
	_assert_can_spawn(
		game,
		"res://resources/enemies/rat.tres",
		26,
		"Rat should spawn at floor 26 (Endless bypasses max_floor) — fails on old floor-only behavior"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/goblin.tres",
		26,
		"Goblin should spawn at floor 26 (Endless bypasses max_floor)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/kobold.tres",
		26,
		"Kobold should spawn at floor 26 (Endless bypasses max_floor)"
	)
	_assert_can_spawn(
		game,
		"res://resources/enemies/skeleton.tres",
		26,
		"Skeleton should spawn at floor 26 (Endless bypasses max_floor)"
	)

	# Allowed — Void Herald at min_floor
	_assert_can_spawn(
		game,
		"res://resources/enemies/void_herald.tres",
		26,
		"Void Herald should spawn at floor 26 (Endless, min_floor=26)"
	)
	# Denied — Deep Maw starts at floor 27
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/deep_maw.tres",
		26,
		"Deep Maw should NOT spawn at floor 26 (min_floor=27)"
	)

	# Denied — Starved Godling requires floor 30
	_assert_cannot_spawn(
		game,
		"res://resources/enemies/starved_godling.tres",
		26,
		"Starved Godling should NOT spawn at floor 26 (min_floor=30)"
	)

	# Allowed — Cinder/Garden enemies also appear in Endless (no roster restrictions)
	_assert_can_spawn(
		game,
		"res://resources/enemies/ash_revenant.tres",
		26,
		"Ash Revenant should spawn at floor 26 (Endless, no roster limit, max_floor=15 bypassed)"
	)

	print("  floor 26 (Endless): early-capped enemies allowed, min_floor enforced, roster bypassed")


# ---------------------------------------------------------------------------
# Floor 30 — deep Endless: Starved Godling finally appears
# ---------------------------------------------------------------------------


func _check_endless_floor_30(game: Node) -> void:
	if _failed:
		return

	# Allowed — Starved Godling at min_floor
	_assert_can_spawn(
		game,
		"res://resources/enemies/starved_godling.tres",
		30,
		"Starved Godling should spawn at floor 30 (min_floor=30)"
	)

	# Allowed — early capped enemies still appear
	_assert_can_spawn(
		game, "res://resources/enemies/rat.tres", 30, "Rat should spawn at floor 30 (Endless)"
	)

	# Endless specials
	_assert_can_spawn(
		game,
		"res://resources/enemies/void_herald.tres",
		30,
		"Void Herald should spawn at floor 30 (Endless)"
	)

	print("  floor 30 (Endless): Starved Godling allowed, early enemies still present")


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------


func _assert_can_spawn(game: Node, enemy_path: String, floor_number: int, label: String) -> void:
	if _failed:
		return
	var enemy: Resource = load(enemy_path)
	if enemy == null:
		_fail("%s: could not load %s" % [label, enemy_path])
		return
	if not game._can_spawn_enemy(enemy, floor_number):
		_fail("%s: _can_spawn_enemy returned false" % label)


func _assert_cannot_spawn(game: Node, enemy_path: String, floor_number: int, label: String) -> void:
	if _failed:
		return
	var enemy: Resource = load(enemy_path)
	if enemy == null:
		_fail("%s: could not load %s" % [label, enemy_path])
		return
	if game._can_spawn_enemy(enemy, floor_number):
		_fail("%s: _can_spawn_enemy returned true" % label)


func _check_boss_resources_do_not_spawn_randomly(game: Node) -> void:
	var boss_paths: Array[String] = [
		"res://resources/enemies/the_observer.tres",
		"res://resources/enemies/seraphine_thorn_saint.tres",
		"res://resources/enemies/vorrak_ashen_maw.tres",
		"res://resources/enemies/kaelros_drowned_king.tres",
		"res://resources/enemies/nyxara_mirror_witch.tres",
	]
	for boss_path: String in boss_paths:
		var boss_data: Resource = load(boss_path)
		if boss_data == null:
			_fail("could not load boss resource %s" % boss_path)
			return
		if not boss_data.is_boss:
			_fail("%s should be marked is_boss" % boss_data.display_name)
			return
		if game._can_spawn_enemy(boss_data, boss_data.boss_floor):
			_fail("%s should not spawn through random enemy rosters" % boss_data.display_name)
			return
		if game._can_spawn_enemy(boss_data, 26):
			_fail("%s should not spawn randomly in Endless" % boss_data.display_name)
			return
	print("  V20 bosses: fixed encounter resources filtered from random rosters")


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
