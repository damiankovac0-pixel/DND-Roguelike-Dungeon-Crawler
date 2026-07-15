## V23.0.0 Projectile resource ID and version metadata tests.
##
## Contracts:
##   1. All listed item paths have the correct projectile_id per Step 2.
##   2. All listed enemy paths have the correct projectile IDs per Step 2.
##   3. All boss non-summon attacks have non-empty projectile_id.
##   4. All boss summon attacks have empty projectile_id and hazard_vfx_id.
##   5. All boss hazard-producing attacks have non-empty hazard_vfx_id.
##   6. Every referenced projectile_id resolves to a known profile.
##   7. GameManager version, label, and Library version history are updated.
##
## Run:
##   /usr/local/bin/godot --headless --path . --script \
##      res://scripts/tests/test_v23_projectile_resources.gd
extends SceneTree

const ProjectileSystemScript = preload("res://scripts/systems/projectile_system.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")
const ResourcePathsScript = preload("res://scripts/resource_paths.gd")
const VersionHistoryScript = preload("res://scripts/version_history.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_item_projectile_ids()
	if _failed:
		return
	_check_enemy_ranged_projectile_ids()
	if _failed:
		return
	_check_boss_attack_projectile_ids()
	if _failed:
		return
	_check_boss_summon_empty_ids()
	if _failed:
		return
	_check_boss_hazard_vfx_ids()
	if _failed:
		return
	_check_projectile_profiles_known()
	if _failed:
		return
	_check_version_metadata()
	if _failed:
		return

	print("V23 projectile resource checks passed")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _load_resource(path: String) -> Resource:
	var res: Resource = load(path)
	if res == null:
		_fail("Failed to load resource: %s" % path)
	return res


func _check_item_projectile_ids() -> void:
	# Step 2 item projectile IDs
	var item_checks: Dictionary = {
		"res://resources/items/apprentice_staff.tres": &"arcane_bolt",
		"res://resources/items/staff_ember.tres": &"ember_bolt",
		"res://resources/items/staff_stormglass.tres": &"stormglass_bolt",
		"res://resources/items/staff_void.tres": &"void_bolt",
		"res://resources/items/staff_astral.tres": &"astral_star",
		"res://resources/items/staff_starfall.tres": &"starfall_star",
		"res://resources/items/staff_ascendant.tres": &"ascendant_star",
		"res://resources/items/hunting_bow.tres": &"arrow",
		"res://resources/items/shortbow.tres": &"arrow",
		"res://resources/items/longbow.tres": &"arrow",
		"res://resources/items/eaglewood_bow.tres": &"arrow",
		"res://resources/items/moonstring_longbow.tres": &"arrow",
		"res://resources/items/celestial_greatbow.tres": &"arrow",
		"res://resources/items/hand_crossbow.tres": &"crossbow_bolt",
		"res://resources/items/heavy_crossbow.tres": &"crossbow_bolt",
		"res://resources/items/scroll_fire_bolt.tres": &"fire_bolt",
		"res://resources/items/scroll_lightning_bolt.tres": &"lightning_bolt",
		"res://resources/items/scroll_magic_missile.tres": &"magic_missile",
		"res://resources/items/scroll_fireball.tres": &"fireball",
		"res://resources/items/scroll_sleep.tres": &"sleep_mote",
	}

	for path: String in item_checks:
		var item: Resource = _load_resource(path)
		if item == null:
			return
		var expected_id: StringName = item_checks[path]
		var actual_id: StringName = item.get("projectile_id") if "projectile_id" in item else &""
		if actual_id != expected_id:
			_fail(
				(
					'%s: projectile_id expected &"%s", got &"%s"'
					% [path.get_file(), expected_id, actual_id]
				)
			)
			return

	print("  item projectile_ids: %d items verified" % item_checks.size())


func _check_enemy_ranged_projectile_ids() -> void:
	# Step 2 enemy ranged projectile IDs
	var enemy_checks: Dictionary = {
		"res://resources/enemies/skeleton.tres":
		{"field": "ranged_projectile_id", "expected": &"arrow"},
		"res://resources/enemies/ember_archer.tres":
		{"field": "ranged_projectile_id", "expected": &"ember_arrow"},
		"res://resources/enemies/cultist.tres":
		{"field": "ranged_projectile_id", "expected": &"shadow_bolt"},
		"res://resources/enemies/eye_acolyte.tres":
		{"field": "ranged_projectile_id", "expected": &"shadow_bolt"},
		"res://resources/enemies/lich.tres":
		{"field": "ranged_projectile_id", "expected": &"shadow_bolt"},
		"res://resources/enemies/prism_seer.tres":
		{"field": "ranged_projectile_id", "expected": &"shadow_bolt"},
		"res://resources/enemies/shadow_weaver.tres":
		{"field": "ranged_projectile_id", "expected": &"shadow_bolt"},
		"res://resources/enemies/void_herald.tres":
		{"field": "ranged_projectile_id", "expected": &"shadow_bolt"},
		"res://resources/enemies/briar_witch.tres":
		{"field": "ranged_projectile_id", "expected": &"thorn_spike"},
		"res://resources/enemies/thorn_lasher.tres":
		{"field": "ranged_projectile_id", "expected": &"thorn_spike"},
		"res://resources/enemies/frost_guardian.tres":
		{"field": "ranged_projectile_id", "expected": &"frost_shard"},
		"res://resources/enemies/harpooner.tres":
		{"field": "ranged_projectile_id", "expected": &"harpoon"},
		"res://resources/enemies/abyssal_eel.tres":
		{"field": "ranged_projectile_id", "expected": &"tidal_bolt"},
		"res://resources/enemies/tidecaller.tres":
		{"field": "ranged_projectile_id", "expected": &"tidal_bolt"},
		# Fireball enemies
		"res://resources/enemies/ancient_dragon.tres":
		{"field": "fireball_projectile_id", "expected": &"fireball"},
		"res://resources/enemies/flame_acolyte.tres":
		{"field": "fireball_projectile_id", "expected": &"fireball"},
		"res://resources/enemies/glass_dragonling.tres":
		{"field": "fireball_projectile_id", "expected": &"fireball"},
		"res://resources/enemies/starved_godling.tres":
		{"field": "fireball_projectile_id", "expected": &"fireball"},
	}

	for path: String in enemy_checks:
		var enemy: Resource = _load_resource(path)
		if enemy == null:
			return
		var check: Dictionary = enemy_checks[path]
		var field: String = check["field"]
		var expected_id: StringName = check["expected"]
		var actual_id: StringName = enemy.get(field) if field in enemy else &""
		if actual_id != expected_id:
			_fail(
				(
					'%s: %s expected &"%s", got &"%s"'
					% [path.get_file(), field, expected_id, actual_id]
				)
			)
			return

	print("  enemy projectile_ids: %d enemies verified" % enemy_checks.size())


func _check_boss_attack_projectile_ids() -> void:
	# Boss non-summon attacks with projectile_id
	var boss_checks: Dictionary = {
		# The Observer
		"res://resources/enemies/the_observer.tres":
		[
			{"id": &"observer_gaze", "projectile_id": &"observer_gaze"},
			{"id": &"blink_pulse", "projectile_id": &"blink_pulse"},
		],
		# Seraphine Thorn Saint
		"res://resources/enemies/seraphine_thorn_saint.tres":
		[
			{"id": &"thorn_lance", "projectile_id": &"thorn_lance"},
			{"id": &"spore_burst", "projectile_id": &"spore_burst"},
		],
		# Vorrak Ashen Maw
		"res://resources/enemies/vorrak_ashen_maw.tres":
		[
			{"id": &"ash_breath", "projectile_id": &"ash_breath"},
			{"id": &"maw_quake", "projectile_id": &"maw_quake"},
		],
		# Kaelros Drowned King
		"res://resources/enemies/kaelros_drowned_king.tres":
		[
			{"id": &"undertow", "projectile_id": &"undertow"},
		],
		# Nyxara Mirror Witch
		"res://resources/enemies/nyxara_mirror_witch.tres":
		[
			{"id": &"mirror_ray", "projectile_id": &"mirror_ray"},
			{"id": &"prism_fracture", "projectile_id": &"prism_fracture"},
		],
	}

	for path: String in boss_checks:
		var boss: Resource = _load_resource(path)
		if boss == null:
			return
		if not "boss_attacks" in boss:
			_fail("%s missing boss_attacks" % path.get_file())
			return
		var attacks: Array = boss.boss_attacks
		var expected_attacks: Array = boss_checks[path]

		for expected: Dictionary in expected_attacks:
			var expected_id: StringName = expected["id"]
			var expected_projectile: StringName = expected["projectile_id"]
			var found: bool = false
			for attack: Resource in attacks:
				if attack.get("id") == expected_id:
					found = true
					var actual_projectile: StringName = (
						attack.get("projectile_id") if "projectile_id" in attack else &""
					)
					if actual_projectile != expected_projectile:
						_fail(
							(
								'%s attack %s: projectile_id expected &"%s", got &"%s"'
								% [
									path.get_file(),
									expected_id,
									expected_projectile,
									actual_projectile
								]
							)
						)
						return
					break
			if not found:
				_fail(
					(
						'%s: expected attack &"%s" not found in boss_attacks'
						% [path.get_file(), expected_id]
					)
				)
				return

	print("  boss attack projectile_ids: %d bosses verified" % boss_checks.size())


func _check_boss_summon_empty_ids() -> void:
	# Boss summon attacks must have empty projectile_id and hazard_vfx_id
	var boss_summon_checks: Dictionary = {
		"res://resources/enemies/seraphine_thorn_saint.tres": &"spore_bloom",
		"res://resources/enemies/kaelros_drowned_king.tres": &"drowned_retinue",
		"res://resources/enemies/nyxara_mirror_witch.tres": &"mirror_guard",
	}

	for path: String in boss_summon_checks:
		var boss: Resource = _load_resource(path)
		if boss == null:
			return
		var attacks: Array = boss.boss_attacks
		var expected_id: StringName = boss_summon_checks[path]
		var found: bool = false
		for attack: Resource in attacks:
			if attack.get("id") == expected_id:
				found = true
				# Summon attack should have empty projectile_id
				var proj_id: StringName = (
					attack.get("projectile_id") if "projectile_id" in attack else &""
				)
				if proj_id != &"":
					_fail(
						(
							'%s summon attack %s: projectile_id should be empty, got &"%s"'
							% [path.get_file(), expected_id, proj_id]
						)
					)
					return
				# Summon attack should have empty hazard_vfx_id
				var hazard_id: StringName = (
					attack.get("hazard_vfx_id") if "hazard_vfx_id" in attack else &""
				)
				if hazard_id != &"":
					_fail(
						(
							'%s summon attack %s: hazard_vfx_id should be empty, got &"%s"'
							% [path.get_file(), expected_id, hazard_id]
						)
					)
					return
				break
		if not found:
			# Spore_bloom may be missing if it wasn't defined; that's optional
			print("  (note: summon attack %s not found in %s)" % [expected_id, path.get_file()])

	# Additionally check The Observer has no summon attacks with non-empty IDs
	var observer: Resource = _load_resource("res://resources/enemies/the_observer.tres")
	if observer != null:
		for attack: Resource in observer.boss_attacks:
			var shape: StringName = attack.get("shape") if "shape" in attack else &""
			if shape == &"summon":
				_fail("The Observer should not have summon-shaped attacks")
				return

	print("  boss summon attacks: empty projectile/hazard IDs verified")


func _check_boss_hazard_vfx_ids() -> void:
	# Boss hazard-producing attacks
	var boss_hazard_checks: Dictionary = {
		"res://resources/enemies/the_observer.tres":
		[
			{"attack_id": &"blink_pulse", "hazard_vfx_id": &"blink_pulse_hazard"},
		],
		"res://resources/enemies/seraphine_thorn_saint.tres":
		[
			{"attack_id": &"spore_burst", "hazard_vfx_id": &"spore_hazard"},
		],
		"res://resources/enemies/vorrak_ashen_maw.tres":
		[
			{"attack_id": &"maw_quake", "hazard_vfx_id": &"molten_cracks"},
		],
		"res://resources/enemies/kaelros_drowned_king.tres":
		[
			{"attack_id": &"undertow", "hazard_vfx_id": &"undertow_hazard"},
		],
		"res://resources/enemies/nyxara_mirror_witch.tres":
		[
			{"attack_id": &"prism_fracture", "hazard_vfx_id": &"mirror_shards"},
		],
	}

	for path: String in boss_hazard_checks:
		var boss: Resource = _load_resource(path)
		if boss == null:
			return
		var attacks: Array = boss.boss_attacks
		var checks: Array = boss_hazard_checks[path]
		for check: Dictionary in checks:
			var attack_id: StringName = check["attack_id"]
			var expected_hazard_id: StringName = check["hazard_vfx_id"]
			var found: bool = false
			for attack: Resource in attacks:
				if attack.get("id") == attack_id:
					found = true
					var actual_hazard_id: StringName = (
						attack.get("hazard_vfx_id") if "hazard_vfx_id" in attack else &""
					)
					if actual_hazard_id != expected_hazard_id:
						_fail(
							(
								'%s attack %s: hazard_vfx_id expected &"%s", got &"%s"'
								% [path.get_file(), attack_id, expected_hazard_id, actual_hazard_id]
							)
						)
						return
					break
			if not found:
				_fail(
					(
						'%s: expected attack &"%s" not found for hazard check'
						% [path.get_file(), attack_id]
					)
				)
				return

	print("  boss hazard_vfx_ids: %d bosses verified" % boss_hazard_checks.size())


func _check_projectile_profiles_known() -> void:
	# Collect all referenced projectile IDs from items and enemies
	var referenced_ids: Array[StringName] = [
		# Items
		&"arcane_bolt",
		&"ember_bolt",
		&"stormglass_bolt",
		&"void_bolt",
		&"astral_star",
		&"starfall_star",
		&"ascendant_star",
		&"arrow",
		&"crossbow_bolt",
		&"fire_bolt",
		&"lightning_bolt",
		&"magic_missile",
		&"fireball",
		&"sleep_mote",
		# Enemy ranged
		&"ember_arrow",
		&"shadow_bolt",
		&"thorn_spike",
		&"frost_shard",
		&"harpoon",
		&"tidal_bolt",
		# Boss attacks
		&"observer_gaze",
		&"blink_pulse",
		&"thorn_lance",
		&"spore_burst",
		&"ash_breath",
		&"maw_quake",
		&"undertow",
		&"mirror_ray",
		&"prism_fracture",
		# Boss hazards
		&"blink_pulse_hazard",
		&"spore_hazard",
		&"molten_cracks",
		&"undertow_hazard",
		&"mirror_shards",
		# Class abilities
		&"arcane_spark",
		&"chain_lightning",
		&"frost_nova",
	]

	for pid: StringName in referenced_ids:
		var payload: Dictionary = ProjectileSystemScript.payload_for_id(pid)
		if payload.get("profile_id", &"") != pid:
			_fail(
				(
					'payload_for_id(&"%s") profile_id expected &"%s", got &"%s"'
					% [pid, pid, payload.get("profile_id", &"")]
				)
			)
			return
		if str(payload.get("glyph", "")).is_empty():
			_fail('payload_for_id(&"%s") has empty glyph' % pid)
			return

	print("  projectile profiles: %d known IDs verified" % referenced_ids.size())


func _check_version_metadata() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	if gm.GAME_VERSION != "30.0.0":
		_fail("GameManager.GAME_VERSION expected '30.0.0', got '%s'" % gm.GAME_VERSION)

	var version_label: String = gm.get_version_label()
	if not "30.0.0" in version_label:
		_fail("get_version_label() missing '30.0.0': " + version_label)
		return

	if not "2026-07-15" in version_label:
		_fail("get_version_label() missing '2026-07-15': " + version_label)
	# Standalone script tests cannot preload LibraryMenu because its UI script resolves the
	# GameManager autoload at scene compile time. Verify the static history wiring instead.
	var library_source: String = FileAccess.get_file_as_string("res://scripts/ui/library_menu.gd")
	var history_wiring: String = (
		"const VERSION_HISTORY: Array[String] = "
		+ 'preload("res://scripts/version_history.gd").VERSION_HISTORY'
	)
	if not library_source.contains(history_wiring):
		_fail("LibraryMenu should expose version_history.gd through VERSION_HISTORY")
		return

	# Version_history.gd keeps the current V30.0.0 and historical V23.3.0 entries.
	var history: Array = VersionHistoryScript.VERSION_HISTORY
	var found_v30_0_0: bool = false
	var found_v23_3_0: bool = false
	for entry: String in history:
		if "V30.0.0" in entry:
			found_v30_0_0 = true
		if "V23.3.0" in entry:
			found_v23_3_0 = true
	if not found_v30_0_0:
		_fail("version_history.gd should contain V30.0.0 entry")
		return
	if not found_v23_3_0:
		_fail("version_history.gd should retain V23.3.0 entry")
		return
	print("  version metadata: 30.0.0, 2026-07-15, V23.3.0+V30.0.0 in VERSION_HISTORY")
