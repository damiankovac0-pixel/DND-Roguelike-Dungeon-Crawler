## V23.1.0 resource model registry and schema validation.
##
## Verifies every ResourcePaths ENEMY_PATHS / ITEM_PATHS entry loads with
## correct type, non-boss enemies with min_floor<=25 are eligible on at least
## one intended floor via BiomeCatalog, each floor 1-25 has >=4 regular eligible
## enemies, bosses are excluded from random rosters, and exact anchor counts
## for class gear, staff ladder, consumable items, and boss resources.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_balance_resource_model.gd
extends SceneTree

const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const BiomeCatalogScript = preload("res://scripts/biome_catalog.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

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

	# ---- resource loading & schema ----
	if not _failed:
		_check_enemy_paths_load()
	if not _failed:
		_check_item_paths_load()

	# ---- enemy roster eligibility ----
	if not _failed:
		_check_non_boss_enemies_eligible_on_enemy_path()
	if not _failed:
		_check_every_floor_has_enough_enemies()

	# ---- boss exclusion ----
	if not _failed:
		_check_boss_resources_do_not_spawn_randomly(game)

	# ---- exact anchor counts ----
	if not _failed:
		_check_anchor_counts()

	if not _failed:
		print("balance resource model check passed")
		quit(0)


# ---------------------------------------------------------------------------
#  Enemy path loading & schema
# ---------------------------------------------------------------------------


func _check_enemy_paths_load() -> void:
	if _failed:
		return
	for path: String in ResourcePathsScript.ENEMY_PATHS:
		var enemy: Resource = load(path)
		if enemy == null:
			_fail("ENEMY_PATHS could not load: %s" % path)
			return
		if not enemy is Resource:
			_fail("%s loaded but is not a Resource" % path)
			return
		# Every enemy resource must have display_name and valid min_floor
		if _r_str(enemy, "display_name") == "":
			_fail("%s missing display_name" % path)
			return
		if not typeof(_r_int(enemy, "min_floor", -1)) == TYPE_INT:
			_fail("%s missing min_floor" % path)
			return
	print(
		(
			"  ENEMY_PATHS: %d resources loaded with valid schema"
			% ResourcePathsScript.ENEMY_PATHS.size()
		)
	)


func _check_item_paths_load() -> void:
	if _failed:
		return
	for path: String in ResourcePathsScript.ITEM_PATHS:
		var item: Resource = load(path)
		if item == null:
			_fail("ITEM_PATHS could not load: %s" % path)
			return
		if not item is Resource:
			_fail("%s loaded but is not a Resource" % path)
			return
		if _r_str(item, "display_name") == "":
			_fail("%s missing display_name" % path)
			return
		if not typeof(_r_int(item, "kind", -1)) == TYPE_INT:
			_fail("%s missing kind" % path)
			return
	print(
		(
			"  ITEM_PATHS: %d resources loaded with valid schema"
			% ResourcePathsScript.ITEM_PATHS.size()
		)
	)


# ---------------------------------------------------------------------------
#  Non-boss enemy eligibility via BiomeCatalog
# ---------------------------------------------------------------------------


func _check_non_boss_enemies_eligible_on_enemy_path() -> void:
	if _failed:
		return
	var missed: Array[String] = []
	for path: String in ResourcePathsScript.ENEMY_PATHS:
		var enemy: Resource = load(path)
		if enemy == null:
			continue
		if _r_bool(enemy, "is_boss"):
			continue
		var min_floor: int = _r_int(enemy, "min_floor", 1)
		if min_floor > 25:
			continue
		# Must be eligible on at least one biome's roster via BiomeCatalog
		var found_biome: bool = false
		for biome_index: int in range(1, 6):
			if BiomeCatalogScript.enemy_path_allowed_for_biome(path, biome_index):
				found_biome = true
				break
		if not found_biome:
			missed.append(_r_str(enemy, "display_name", path))
	if not missed.is_empty():
		_fail("Enemies not eligible on any biome 1-5 roster: %s" % ", ".join(missed))
		return
	print("  all non-boss enemies (min_floor<=25) are eligible on at least one biome roster")


# ---------------------------------------------------------------------------
#  Floor coverage — every floor 1-25 has >= 4 regular eligible enemies
# ---------------------------------------------------------------------------


func _check_every_floor_has_enough_enemies() -> void:
	if _failed:
		return
	var eligible_enemies: Dictionary = _build_eligible_enemies()
	var low_floors: Array[String] = []
	for floor_number: int in range(1, 26):
		var count: int = 0
		for key: String in eligible_enemies.keys():
			var data: EnemyMeta = eligible_enemies[key]
			if (
				data.min_floor <= floor_number
				and (data.max_floor <= 0 or floor_number <= data.max_floor)
			):
				count += 1
		if count < 4:
			low_floors.append("floor %d (%d)" % [floor_number, count])
	if not low_floors.is_empty():
		_fail("Floors with fewer than 4 eligible enemies: %s" % ", ".join(low_floors))
		return
	print("  every floor 1-25 has >= 4 regular eligible enemies")


# ---------------------------------------------------------------------------
#  Boss exclusion from random rosters
# ---------------------------------------------------------------------------


func _check_boss_resources_do_not_spawn_randomly(game: Node) -> void:
	if _failed:
		return
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
		if not _r_bool(boss_data, "is_boss"):
			_fail("%s should be marked is_boss" % _r_str(boss_data, "display_name", boss_path))
			return
		if game._can_spawn_enemy(boss_data, _r_int(boss_data, "boss_floor", 1)):
			_fail(
				(
					"%s should not spawn through random enemy rosters"
					% _r_str(boss_data, "display_name", boss_path)
				)
			)
			return
		if game._can_spawn_enemy(boss_data, 26):
			_fail(
				(
					"%s should not spawn randomly in Endless"
					% _r_str(boss_data, "display_name", boss_path)
				)
			)
			return
	print("  boss resources: 5 filtered from random rosters and Endless")


# ---------------------------------------------------------------------------
#  Anchor counts
# ---------------------------------------------------------------------------


func _check_anchor_counts() -> void:
	if _failed:
		return

	var enemy_total: int = ResourcePathsScript.ENEMY_PATHS.size()
	var item_total: int = ResourcePathsScript.ITEM_PATHS.size()

	# Load and classify
	var boss_count: int = 0
	var non_boss_enemies: int = 0
	var consumable_count: int = 0
	var staff_count: int = 0
	var class_gear_count: int = 0

	for path: String in ResourcePathsScript.ENEMY_PATHS:
		var e: Resource = load(path)
		if e == null:
			continue
		if _r_bool(e, "is_boss"):
			boss_count += 1
		else:
			non_boss_enemies += 1

	for path: String in ResourcePathsScript.ITEM_PATHS:
		var item: Resource = load(path)
		if item == null:
			continue
		var kind: int = _r_int(item, "kind", -1)
		if kind == ItemDataScript.ItemKind.CONSUMABLE:
			consumable_count += 1
		var is_staff: bool = _r_bool(item, "is_staff")
		if is_staff:
			staff_count += 1
		# Class gear items have a required_class set
		var req_class: StringName = _r_sname(item, "required_class")
		if req_class != &"":
			class_gear_count += 1

	# Anchor: enemy total should be 42 (including 5 bosses)
	if enemy_total != 42:
		_fail("ENEMY_PATHS size %d, expected 42" % enemy_total)
		return
	if boss_count != 5:
		_fail("boss count %d, expected 5" % boss_count)
		return
	if non_boss_enemies != 37:
		_fail("non-boss enemy count %d, expected 37" % non_boss_enemies)
		return

	# Anchor: item total + class counts
	if item_total != 76:
		_fail("ITEM_PATHS size %d, expected 76" % item_total)
		return
	if consumable_count != 17:
		_fail("consumable count %d, expected 17" % consumable_count)
		return
	if staff_count != 7:
		_fail("staff item count %d, expected 7" % staff_count)
		return
	if class_gear_count != 20:
		_fail("class-required-gear count %d, expected 20" % class_gear_count)
		return

	print(
		(
			"  anchors: enemies=%d (%d boss, %d standard), items=%d (consumable=%d, staff=%d, class_gear=%d)"
			% [
				enemy_total,
				boss_count,
				non_boss_enemies,
				item_total,
				consumable_count,
				staff_count,
				class_gear_count
			]
		)
	)


# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

## Typed one-arg Resource.get() wrappers (Godot 4 get() accepts only one arg).


class EnemyMeta:
	var path: String
	var display_name: String
	var min_floor: int
	var max_floor: int
	var is_boss: bool

	func _init(p: String, d: String, minf: int, maxf: int, boss: bool) -> void:
		path = p
		display_name = d
		min_floor = minf
		max_floor = maxf
		is_boss = boss


static func _r_str(res: Resource, key: String, fallback: String = "") -> String:
	var v = res.get(key)
	return v if v != null and typeof(v) == TYPE_STRING else fallback


static func _r_int(res: Resource, key: String, fallback: int = 0) -> int:
	var v = res.get(key)
	return v if v != null and typeof(v) == TYPE_INT else fallback


static func _r_bool(res: Resource, key: String, fallback: bool = false) -> bool:
	var v = res.get(key)
	return v if v != null and typeof(v) == TYPE_BOOL else fallback


static func _r_sname(res: Resource, key: String, fallback: StringName = &"") -> StringName:
	var v = res.get(key)
	return v if v != null and typeof(v) == TYPE_STRING_NAME else fallback


func _build_eligible_enemies() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ResourcePathsScript.ENEMY_PATHS:
		var enemy: Resource = load(path)
		if enemy == null:
			continue
		if _r_bool(enemy, "is_boss"):
			continue
		var meta: EnemyMeta = EnemyMeta.new(
			path,
			_r_str(enemy, "display_name"),
			_r_int(enemy, "min_floor", 1),
			_r_int(enemy, "max_floor"),
			false
		)
		result[path] = meta
	return result


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
