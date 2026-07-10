## V23.0.0 Projectile rarity VFX tests.
##
## Contracts:
##   1. Loading hunting_bow.tres and celestial_greatbow.tres succeeds.
##   2. Both produce payloads with profile_id == &"arrow".
##   3. Common (rarity 0) payload has no shimmer, lower duration/alpha vs Ascended.
##   4. Ascended (rarity 6) payload has shimmer enabled, white accent, lift 0.55.
##   5. profile_id, glyph, trail_glyph, impact_glyph equal across rarities.
##   6. Scroll of Fireball (Epic) has profile_id fireball, no shimmer, style area.
##   7. apply_item_rarity_to_payload does not mutate input.
##
## Run:
##   /usr/local/bin/godot --headless --path . --script \
##      res://scripts/tests/test_v23_projectile_rarity_vfx.gd
extends SceneTree

const ProjectileSystemScript = preload("res://scripts/systems/projectile_system.gd")
const ItemDataScript = preload("res://scripts/resources/item_data.gd")

const HUNTING_BOW_PATH: String = "res://resources/items/hunting_bow.tres"
const CELESTIAL_GREATBOW_PATH: String = "res://resources/items/celestial_greatbow.tres"
const SCROLL_FIREBALL_PATH: String = "res://resources/items/scroll_fireball.tres"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_items_load()
	if _failed:
		return
	_check_common_vs_ascended_rarity()
	if _failed:
		return
	_check_ascended_specifics()
	if _failed:
		return
	_check_profile_glyphs_preserved()
	if _failed:
		return
	_check_scroll_fireball()
	if _failed:
		return
	_check_apply_rarity_no_mutate()
	if _failed:
		return

	print("V23 projectile rarity VFX checks passed")
	quit(0)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)


func _check_items_load() -> void:
	var bow: Resource = load(HUNTING_BOW_PATH)
	if bow == null:
		_fail("hunting_bow.tres failed to load")
		return
	var greatbow: Resource = load(CELESTIAL_GREATBOW_PATH)
	if greatbow == null:
		_fail("celestial_greatbow.tres failed to load")
		return
	var bow_rarity: int = int(bow.get("rarity")) if "rarity" in bow else -1
	var gb_rarity: int = int(greatbow.get("rarity")) if "rarity" in greatbow else -1
	print(
		(
			"  items loaded: Hunting Bow (rarity=%d), Celestial Greatbow (rarity=%d)"
			% [bow_rarity, gb_rarity]
		)
	)

	var bow_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		bow, &"weapon", &"ranged"
	)
	var gb_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		greatbow, &"weapon", &"ranged"
	)

	if bow_payload.get("profile_id", &"") != &"arrow":
		_fail(
			(
				'Hunting Bow payload profile_id expected &"arrow", got %s'
				% str(bow_payload.get("profile_id", &""))
			)
		)
		return
	if gb_payload.get("profile_id", &"") != &"arrow":
		_fail(
			(
				'Celestial Greatbow payload profile_id expected &"arrow", got %s'
				% str(gb_payload.get("profile_id", &""))
			)
		)
		return
	print("  both bows produce arrow profile")


func _check_common_vs_ascended_rarity() -> void:
	var bow: Resource = load(HUNTING_BOW_PATH)
	var greatbow: Resource = load(CELESTIAL_GREATBOW_PATH)

	var bow_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		bow, &"weapon", &"ranged"
	)
	var gb_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		greatbow, &"weapon", &"ranged"
	)

	if int(bow_payload.get("rarity", -1)) != ItemDataScript.ItemRarity.COMMON:
		_fail("Hunting Bow rarity expected COMMON (0), got %d" % bow_payload.get("rarity", -1))
		return
	if bow_payload.get("rarity_shimmer_enabled", true) != false:
		_fail("Hunting Bow shimmer should be disabled")
		return

	if int(gb_payload.get("rarity", -1)) != ItemDataScript.ItemRarity.ASCENDED:
		_fail(
			"Celestial Greatbow rarity expected ASCENDED (6), got %d" % gb_payload.get("rarity", -1)
		)
		return
	if gb_payload.get("rarity_shimmer_enabled", false) != true:
		_fail("Celestial Greatbow shimmer should be enabled")
		return

	# Ascended should have higher duration and trail/fill alpha scales
	var common_duration: float = float(bow_payload.get("duration_seconds", 0.0))
	var ascended_duration: float = float(gb_payload.get("duration_seconds", 0.0))
	if ascended_duration <= common_duration:
		_fail(
			(
				"Ascended duration (%.3f) should be > Common duration (%.3f)"
				% [ascended_duration, common_duration]
			)
		)
		return

	var common_trail_alpha: float = float(bow_payload.get("rarity_trail_alpha_scale", 0.0))
	var ascended_trail_alpha: float = float(gb_payload.get("rarity_trail_alpha_scale", 0.0))
	if ascended_trail_alpha <= common_trail_alpha:
		_fail(
			(
				"Ascended trail alpha scale (%.3f) should be > Common (%.3f)"
				% [ascended_trail_alpha, common_trail_alpha]
			)
		)
		return

	var common_fill_alpha: float = float(bow_payload.get("rarity_fill_alpha_scale", 0.0))
	var ascended_fill_alpha: float = float(gb_payload.get("rarity_fill_alpha_scale", 0.0))
	if ascended_fill_alpha <= common_fill_alpha:
		_fail(
			(
				"Ascended fill alpha scale (%.3f) should be > Common (%.3f)"
				% [ascended_fill_alpha, common_fill_alpha]
			)
		)
		return
	print("  Common vs Ascended rarity checks passed")


func _check_ascended_specifics() -> void:
	var greatbow: Resource = load(CELESTIAL_GREATBOW_PATH)
	var payload: Dictionary = ProjectileSystemScript.payload_from_item(
		greatbow, &"weapon", &"ranged"
	)

	if int(payload.get("rarity", -1)) != ItemDataScript.ItemRarity.ASCENDED:
		_fail("Expected ASCENDED rarity")
		return

	var expected_color: Color = Color.html(
		ItemDataScript.RARITY_COLORS[ItemDataScript.ItemRarity.ASCENDED]
	)
	var got_color: Color = payload.get("rarity_color", Color.BLACK)
	if got_color != expected_color:
		_fail("rarity_color expected %s, got %s" % [str(expected_color), str(got_color)])
		return

	if payload.get("rarity_shimmer_enabled", false) != true:
		_fail("Ascended shimmer should be enabled")
		return

	var accent: Color = payload.get("rarity_accent_color", Color.BLACK)
	if accent != Color.WHITE:
		_fail("Ascended rarity_accent_color expected WHITE, got %s" % str(accent))
		return

	var shimmer_lift: float = float(payload.get("rarity_shimmer_lift", 0.0))
	if abs(shimmer_lift - 0.55) > 0.001:
		_fail("Ascended rarity_shimmer_lift expected 0.55, got %.3f" % shimmer_lift)
		return
	print("  Ascended specifics verified")


func _check_profile_glyphs_preserved() -> void:
	var bow: Resource = load(HUNTING_BOW_PATH)
	var greatbow: Resource = load(CELESTIAL_GREATBOW_PATH)

	var bow_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		bow, &"weapon", &"ranged"
	)
	var gb_payload: Dictionary = ProjectileSystemScript.payload_from_item(
		greatbow, &"weapon", &"ranged"
	)

	var fields_to_check: Array[String] = ["profile_id", "glyph", "trail_glyph", "impact_glyph"]
	for field: String in fields_to_check:
		var common_val = bow_payload.get(field, null)
		var ascended_val = gb_payload.get(field, null)
		if common_val == null or ascended_val == null:
			_fail("Field '%s' missing from payload" % field)
			return
		if common_val != ascended_val:
			_fail(
				(
					"Field '%s' differs: Common=%s Ascended=%s (should be equal)"
					% [field, str(common_val), str(ascended_val)]
				)
			)
			return
	print("  profile glyphs preserved across rarities")


func _check_scroll_fireball() -> void:
	var fireball: Resource = load(SCROLL_FIREBALL_PATH)
	if fireball == null:
		_fail("scroll_fireball.tres failed to load")
		return

	var payload: Dictionary = ProjectileSystemScript.payload_from_item(
		fireball, &"consumable", &"fire"
	)
	if payload.get("profile_id", &"") != &"fireball":
		_fail(
			(
				'Scroll of Fireball profile_id expected &"fireball", got %s'
				% str(payload.get("profile_id", &""))
			)
		)
		return
	if int(payload.get("rarity", -1)) != ItemDataScript.ItemRarity.EPIC:
		_fail("Scroll of Fireball rarity expected EPIC (3), got %d" % payload.get("rarity", -1))
		return
	if payload.get("rarity_shimmer_enabled", true) != false:
		_fail("Scroll of Fireball (Epic) should not have shimmer")
		return
	if payload.get("style", &"") != &"area":
		_fail('Scroll of Fireball style expected &"area", got %s' % str(payload.get("style", &"")))
		return
	if payload.get("rarity_tint_strength", 0.0) != 0.46:
		_fail(
			(
				"Scroll of Fireball (Epic) rarity_tint_strength expected 0.46, got %.3f"
				% payload.get("rarity_tint_strength", 0.0)
			)
		)
		return
	print("  scroll of fireball (Epic) verified")


func _check_apply_rarity_no_mutate() -> void:
	var base_payload: Dictionary = ProjectileSystemScript.payload_for_id(&"arrow")
	var original_profile: StringName = base_payload.get("profile_id", &"")
	var original_duration: float = float(base_payload.get("duration_seconds", 0.0))

	ProjectileSystemScript.apply_item_rarity_to_payload(
		base_payload, ItemDataScript.ItemRarity.ASCENDED
	)

	if base_payload.get("profile_id", &"") != original_profile:
		_fail("apply_item_rarity_to_payload mutated profile_id")
		return
	if float(base_payload.get("duration_seconds", 0.0)) != original_duration:
		_fail(
			(
				"apply_item_rarity_to_payload mutated duration_seconds (was %.3f, now %.3f)"
				% [original_duration, base_payload.get("duration_seconds", 0.0)]
			)
		)
		return
	if base_payload.get("rarity", -1) != 0:
		_fail("apply_item_rarity_to_payload mutated base payload rarity")
		return
	print("  apply_item_rarity_to_payload does not mutate input")
