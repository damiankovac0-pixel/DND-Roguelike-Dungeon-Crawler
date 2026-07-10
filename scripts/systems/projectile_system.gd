## Presentation-only projectile profile and grid trail helpers.
class_name ProjectileSystem
extends RefCounted

# === Constants ===
const ItemDataScript = preload("res://scripts/resources/item_data.gd")


# === Public Methods ===
static func line_cells(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0: int = start.x
	var y0: int = start.y
	var x1: int = goal.x
	var y1: int = goal.y
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var error: int = dx + dy

	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var twice_error: int = error * 2
		if twice_error >= dy:
			error += dy
			x0 += sx
		if twice_error <= dx:
			error += dx
			y0 += sy
	return points


static func array_from_cell_keys(cells: Dictionary) -> Array[Vector2i]:
	var sorted_cells: Array[Vector2i] = []
	for key in cells.keys():
		if key is Vector2i:
			sorted_cells.append(key)
	sorted_cells.sort_custom(
		func(left: Vector2i, right: Vector2i) -> bool:
			if left.y == right.y:
				return left.x < right.x
			return left.y < right.y
	)
	return sorted_cells


static func payload_for_id(
	projectile_id: StringName,
	fallback_damage_type: StringName = &"",
	fallback_color: Color = Color.WHITE
) -> Dictionary:
	var payload: Dictionary = _payload_for_profile(projectile_id)
	var used_fallback: bool = false
	if payload.is_empty():
		var fallback_id: StringName = _profile_id_for_fallback(fallback_damage_type)
		payload = _payload_for_profile(fallback_id)
		used_fallback = true
	if payload.is_empty():
		payload = _payload_for_profile(&"arcane_bolt")
		used_fallback = true
	if used_fallback and fallback_color != Color.WHITE:
		_apply_fallback_color(payload, fallback_color)
	return payload.duplicate(true)


static func payload_from_item(
	item: Resource, source: StringName, damage_type: StringName
) -> Dictionary:
	if item == null:
		return payload_for_id(&"", damage_type)
	var projectile_id: StringName = _resource_string_name(item, "projectile_id")
	if projectile_id == &"":
		projectile_id = _item_fallback_projectile_id(item, source, damage_type)
	var rarity_value: int = ItemDataScript.ItemRarity.COMMON
	if "rarity" in item:
		rarity_value = int(item.get("rarity"))
	return apply_item_rarity_to_payload(payload_for_id(projectile_id, damage_type), rarity_value)


static func payload_from_enemy_ranged(enemy_data: Resource) -> Dictionary:
	if enemy_data == null:
		return payload_for_id(&"", &"ranged")
	var projectile_id: StringName = _resource_string_name(enemy_data, "ranged_projectile_id")
	var damage_type: StringName = _resource_string_name(enemy_data, "ranged_damage_type", &"ranged")
	if projectile_id != &"":
		return payload_for_id(projectile_id, damage_type)
	return payload_for_id(&"", damage_type)


static func payload_from_enemy_fireball(enemy_data: Resource) -> Dictionary:
	if enemy_data == null:
		return payload_for_id(&"fireball", &"fire", Color(1.0, 0.38, 0.12))
	var projectile_id: StringName = _resource_string_name(enemy_data, "fireball_projectile_id")
	var fallback_color: Color = _color_or_default(enemy_data.get("color"), Color(1.0, 0.38, 0.12))
	if projectile_id != &"":
		return payload_for_id(projectile_id, &"fire", fallback_color)
	return payload_for_id(&"fireball", &"fire", fallback_color)


static func payload_from_boss_attack(attack: Resource) -> Dictionary:
	if attack == null:
		return payload_for_id(&"", &"magic", Color.WHITE)
	var projectile_id: StringName = _resource_string_name(attack, "projectile_id")
	if projectile_id == &"":
		projectile_id = _resource_string_name(attack, "id")
	var damage_type: StringName = _resource_string_name(attack, "damage_type", &"magic")
	var fallback_color: Color = _color_or_default(attack.get("telegraph_color"), Color.WHITE)
	return payload_for_id(projectile_id, damage_type, fallback_color)


static func payload_from_boss_hazard(attack: Resource) -> Dictionary:
	if attack == null:
		return payload_for_id(&"", &"magic", Color.WHITE)
	var projectile_id: StringName = _resource_string_name(attack, "hazard_vfx_id")
	if projectile_id == &"":
		projectile_id = _resource_string_name(attack, "projectile_id")
	if projectile_id == &"":
		projectile_id = _resource_string_name(attack, "id")
	var damage_type: StringName = _resource_string_name(attack, "hazard_damage_type", &"magic")
	var fallback_color: Color = _color_or_default(attack.get("telegraph_color"), Color.WHITE)
	return payload_for_id(projectile_id, damage_type, fallback_color)


static func apply_item_rarity_to_payload(payload: Dictionary, rarity_value: int) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	var rarity_vfx: Dictionary = rarity_vfx_for(rarity_value)
	var rarity_color: Color = rarity_vfx.get(
		"rarity_color", Color.html(ItemDataScript.RARITY_COLORS[0])
	)
	var tint_strength: float = float(rarity_vfx.get("rarity_tint_strength", 0.0))
	var trail_alpha_scale: float = float(rarity_vfx.get("rarity_trail_alpha_scale", 1.0))
	var fill_alpha_scale: float = float(rarity_vfx.get("rarity_fill_alpha_scale", 1.0))

	for key: String in ["color", "trail_color", "impact_color", "fill_color", "border_color"]:
		var color: Color = result.get(key, Color.WHITE)
		result[key] = _tint_rgb_preserving_alpha(color, rarity_color, tint_strength)

	result["trail_color"] = _scale_alpha(result.get("trail_color", Color.WHITE), trail_alpha_scale)
	result["impact_color"] = _scale_alpha(
		result.get("impact_color", Color.WHITE), trail_alpha_scale
	)
	result["fill_color"] = _scale_alpha(
		result.get("fill_color", Color.TRANSPARENT), fill_alpha_scale
	)
	result["border_color"] = _scale_alpha(
		result.get("border_color", Color.TRANSPARENT), fill_alpha_scale
	)
	result["duration_seconds"] = max(
		0.05,
		(
			float(result.get("duration_seconds", 0.22))
			* float(rarity_vfx.get("rarity_duration_scale", 1.0))
		)
	)

	for key: String in rarity_vfx.keys():
		result[key] = rarity_vfx[key]
	return result


static func rarity_vfx_for(rarity_value: int) -> Dictionary:
	var safe_rarity: int = clampi(
		rarity_value, ItemDataScript.ItemRarity.COMMON, ItemDataScript.RARITY_COLORS.size() - 1
	)
	var rarity_color: Color = Color.html(ItemDataScript.RARITY_COLORS[safe_rarity])
	var result: Dictionary = {
		"rarity": safe_rarity,
		"rarity_name": ItemDataScript.RARITY_NAMES[safe_rarity],
		"rarity_color": rarity_color,
		"rarity_tint_strength": 0.0,
		"rarity_duration_scale": 1.0,
		"rarity_trail_alpha_scale": 1.0,
		"rarity_fill_alpha_scale": 1.0,
		"rarity_shimmer_enabled": false,
		"rarity_accent_color": rarity_color,
		"rarity_shimmer_speed": 0.0,
		"rarity_shimmer_spread": 0.0,
		"rarity_shimmer_intensity": 0.0,
		"rarity_shimmer_lift": 0.0,
	}
	match safe_rarity:
		ItemDataScript.ItemRarity.UNCOMMON:
			result["rarity_tint_strength"] = 0.18
			result["rarity_duration_scale"] = 1.03
			result["rarity_trail_alpha_scale"] = 1.05
			result["rarity_fill_alpha_scale"] = 1.05
		ItemDataScript.ItemRarity.RARE:
			result["rarity_tint_strength"] = 0.32
			result["rarity_duration_scale"] = 1.06
			result["rarity_trail_alpha_scale"] = 1.10
			result["rarity_fill_alpha_scale"] = 1.10
		ItemDataScript.ItemRarity.EPIC:
			result["rarity_tint_strength"] = 0.46
			result["rarity_duration_scale"] = 1.09
			result["rarity_trail_alpha_scale"] = 1.16
			result["rarity_fill_alpha_scale"] = 1.16
		ItemDataScript.ItemRarity.LEGENDARY:
			result["rarity_tint_strength"] = 0.60
			result["rarity_duration_scale"] = 1.12
			result["rarity_trail_alpha_scale"] = 1.24
			result["rarity_fill_alpha_scale"] = 1.20
			result["rarity_shimmer_enabled"] = true
			result["rarity_accent_color"] = Color.html("#fff1a0")
			result["rarity_shimmer_speed"] = 2.05
			result["rarity_shimmer_spread"] = 0.48
			result["rarity_shimmer_intensity"] = 0.58
		ItemDataScript.ItemRarity.MYTHIC:
			result["rarity_tint_strength"] = 0.72
			result["rarity_duration_scale"] = 1.15
			result["rarity_trail_alpha_scale"] = 1.32
			result["rarity_fill_alpha_scale"] = 1.26
			result["rarity_shimmer_enabled"] = true
			result["rarity_accent_color"] = Color.html("#ffd6ff")
			result["rarity_shimmer_speed"] = 2.45
			result["rarity_shimmer_spread"] = 0.62
			result["rarity_shimmer_intensity"] = 0.62
			result["rarity_shimmer_lift"] = 0.35
		ItemDataScript.ItemRarity.ASCENDED:
			result["rarity_tint_strength"] = 0.85
			result["rarity_duration_scale"] = 1.18
			result["rarity_trail_alpha_scale"] = 1.40
			result["rarity_fill_alpha_scale"] = 1.32
			result["rarity_shimmer_enabled"] = true
			result["rarity_accent_color"] = Color.WHITE
			result["rarity_shimmer_speed"] = 2.25
			result["rarity_shimmer_spread"] = 0.58
			result["rarity_shimmer_intensity"] = 0.70
			result["rarity_shimmer_lift"] = 0.55
	return result


# === Private Methods ===
static func _profile_id_for_fallback(fallback_damage_type: StringName) -> StringName:
	match fallback_damage_type:
		&"fire":
			return &"fire_bolt"
		&"magic":
			return &"arcane_bolt"
		&"ranged", &"piercing":
			return &"arrow"
		&"cold":
			return &"frost_shard"
		&"poison":
			return &"thorn_spike"
	return &"arcane_bolt"


static func _tint_rgb_preserving_alpha(color: Color, tint: Color, strength: float) -> Color:
	return Color(color.r, color.g, color.b, color.a).lerp(
		Color(tint.r, tint.g, tint.b, color.a), clampf(strength, 0.0, 1.0)
	)


static func _scale_alpha(color: Color, scale: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(color.a * scale, 0.0, 1.0))


static func _color_or_default(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return fallback


static func _payload_for_profile(profile_id: StringName) -> Dictionary:
	match profile_id:
		&"arrow":
			return _base_payload(
				&"arrow",
				&"bolt",
				"›",
				"·",
				"›",
				Color(0.58, 0.82, 1.0, 1.0),
				Color(0.58, 0.82, 1.0, 0.42),
				Color(0.58, 0.82, 1.0, 0.10),
				Color.TRANSPARENT,
				0.20
			)
		&"crossbow_bolt":
			return _base_payload(
				&"crossbow_bolt",
				&"bolt",
				"»",
				"·",
				"›",
				Color(0.78, 0.86, 0.92, 1.0),
				Color(0.78, 0.86, 0.92, 0.42),
				Color(0.78, 0.86, 0.92, 0.10),
				Color.TRANSPARENT,
				0.20
			)
		&"arcane_bolt":
			return _base_payload(
				&"arcane_bolt",
				&"bolt",
				"✦",
				"·",
				"✦",
				Color(0.68, 0.48, 1.0, 1.0),
				Color(0.68, 0.48, 1.0, 0.46),
				Color(0.68, 0.48, 1.0, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"ember_bolt":
			return _base_payload(
				&"ember_bolt",
				&"bolt",
				"*",
				"·",
				"✹",
				Color(1.0, 0.38, 0.12, 1.0),
				Color(1.0, 0.42, 0.12, 0.48),
				Color(1.0, 0.18, 0.02, 0.14),
				Color.TRANSPARENT,
				0.23
			)
		&"stormglass_bolt":
			return _base_payload(
				&"stormglass_bolt",
				&"beam",
				"~",
				"~",
				"✦",
				Color(0.45, 0.86, 1.0, 1.0),
				Color(0.45, 0.86, 1.0, 0.46),
				Color(0.10, 0.42, 1.0, 0.12),
				Color.TRANSPARENT,
				0.20
			)
		&"void_bolt":
			return _base_payload(
				&"void_bolt",
				&"bolt",
				"◇",
				"·",
				"◆",
				Color(0.78, 0.46, 1.0, 1.0),
				Color(0.78, 0.46, 1.0, 0.46),
				Color(0.36, 0.08, 0.62, 0.14),
				Color.TRANSPARENT,
				0.24
			)
		&"astral_star":
			return _base_payload(
				&"astral_star",
				&"bolt",
				"✧",
				"·",
				"✧",
				Color(0.76, 0.86, 1.0, 1.0),
				Color(0.76, 0.86, 1.0, 0.46),
				Color(0.30, 0.42, 0.92, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"starfall_star":
			return _base_payload(
				&"starfall_star",
				&"bolt",
				"✹",
				"·",
				"✹",
				Color(1.0, 0.78, 0.34, 1.0),
				Color(1.0, 0.78, 0.34, 0.48),
				Color(1.0, 0.54, 0.14, 0.14),
				Color.TRANSPARENT,
				0.25
			)
		&"ascendant_star":
			return _base_payload(
				&"ascendant_star",
				&"beam",
				"✷",
				"✧",
				"✷",
				Color(0.66, 1.0, 0.94, 1.0),
				Color(0.66, 1.0, 0.94, 0.50),
				Color(0.16, 0.80, 0.76, 0.14),
				Color.TRANSPARENT,
				0.24
			)
		&"fire_bolt":
			return _base_payload(
				&"fire_bolt",
				&"bolt",
				"*",
				"·",
				"✹",
				Color(1.0, 0.30, 0.08, 1.0),
				Color(1.0, 0.36, 0.08, 0.48),
				Color(1.0, 0.16, 0.02, 0.14),
				Color.TRANSPARENT,
				0.22
			)
		&"lightning_bolt":
			return _base_payload(
				&"lightning_bolt",
				&"beam",
				"~",
				"~",
				"✦",
				Color(1.0, 0.90, 0.28, 1.0),
				Color(0.58, 0.90, 1.0, 0.48),
				Color(0.28, 0.48, 1.0, 0.12),
				Color.TRANSPARENT,
				0.18
			)
		&"magic_missile":
			return _base_payload(
				&"magic_missile",
				&"bolt",
				"✦",
				"·",
				"✦",
				Color(0.65, 0.85, 1.0, 1.0),
				Color(0.65, 0.85, 1.0, 0.44),
				Color(0.18, 0.42, 1.0, 0.12),
				Color.TRANSPARENT,
				0.20
			)
		&"fireball":
			return _base_payload(
				&"fireball",
				&"area",
				"●",
				"*",
				"✹",
				Color(1.0, 0.22, 0.08, 1.0),
				Color(1.0, 0.32, 0.08, 0.46),
				Color(1.0, 0.16, 0.02, 0.18),
				Color(1.0, 0.52, 0.12, 0.40),
				0.26
			)
		&"sleep_mote":
			return _base_payload(
				&"sleep_mote",
				&"area",
				"☾",
				"·",
				"z",
				Color(0.58, 0.70, 1.0, 1.0),
				Color(0.58, 0.70, 1.0, 0.42),
				Color(0.20, 0.24, 0.62, 0.12),
				Color.TRANSPARENT,
				0.24
			)
		&"frost_shard":
			return _base_payload(
				&"frost_shard",
				&"bolt",
				"•",
				"·",
				"✦",
				Color(0.52, 0.86, 1.0, 1.0),
				Color(0.52, 0.86, 1.0, 0.42),
				Color(0.12, 0.46, 0.78, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"thorn_spike":
			return _base_payload(
				&"thorn_spike",
				&"bolt",
				"^",
				"·",
				"╋",
				Color(0.78, 1.0, 0.44, 1.0),
				Color(0.78, 1.0, 0.44, 0.42),
				Color(0.18, 0.50, 0.16, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"harpoon":
			return _base_payload(
				&"harpoon",
				&"bolt",
				"➤",
				"·",
				"›",
				Color(0.56, 0.78, 0.88, 1.0),
				Color(0.56, 0.78, 0.88, 0.42),
				Color(0.08, 0.28, 0.44, 0.10),
				Color.TRANSPARENT,
				0.22
			)
		&"shadow_bolt":
			return _base_payload(
				&"shadow_bolt",
				&"bolt",
				"◆",
				"·",
				"◆",
				Color(0.70, 0.48, 1.0, 1.0),
				Color(0.70, 0.48, 1.0, 0.42),
				Color(0.24, 0.08, 0.42, 0.12),
				Color.TRANSPARENT,
				0.23
			)
		&"ember_arrow":
			return _base_payload(
				&"ember_arrow",
				&"bolt",
				"›",
				"*",
				"✹",
				Color(1.0, 0.46, 0.16, 1.0),
				Color(1.0, 0.46, 0.16, 0.44),
				Color(1.0, 0.18, 0.02, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"tidal_bolt":
			return _base_payload(
				&"tidal_bolt",
				&"bolt",
				"≈",
				"·",
				"≈",
				Color(0.42, 0.82, 1.0, 1.0),
				Color(0.42, 0.82, 1.0, 0.44),
				Color(0.05, 0.30, 0.54, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"observer_gaze":
			return _base_payload(
				&"observer_gaze",
				&"beam",
				"⊙",
				"·",
				"⊙",
				Color(0.74, 0.92, 1.0, 1.0),
				Color(0.74, 0.92, 1.0, 0.48),
				Color(0.12, 0.36, 0.78, 0.18),
				Color(0.54, 0.84, 1.0, 0.42),
				0.28
			)
		&"blink_pulse":
			return _base_payload(
				&"blink_pulse",
				&"area",
				"◉",
				"·",
				"◉",
				Color(0.82, 0.95, 1.0, 1.0),
				Color(0.82, 0.95, 1.0, 0.42),
				Color(0.18, 0.46, 1.0, 0.16),
				Color(0.72, 0.90, 1.0, 0.42),
				0.28
			)
		&"thorn_lance":
			return _base_payload(
				&"thorn_lance",
				&"beam",
				"╋",
				"^",
				"╋",
				Color(0.90, 1.0, 0.48, 1.0),
				Color(0.90, 1.0, 0.48, 0.44),
				Color(0.18, 0.54, 0.16, 0.16),
				Color(0.76, 1.0, 0.36, 0.40),
				0.26
			)
		&"spore_burst":
			return _base_payload(
				&"spore_burst",
				&"area",
				"✹",
				"·",
				"✹",
				Color(0.76, 1.0, 0.52, 1.0),
				Color(0.76, 1.0, 0.52, 0.42),
				Color(0.22, 0.60, 0.18, 0.18),
				Color(0.90, 0.58, 0.82, 0.42),
				0.28
			)
		&"ash_breath":
			return _base_payload(
				&"ash_breath",
				&"area",
				"※",
				"*",
				"※",
				Color(1.0, 0.52, 0.16, 1.0),
				Color(1.0, 0.52, 0.16, 0.46),
				Color(1.0, 0.16, 0.02, 0.20),
				Color(1.0, 0.72, 0.24, 0.44),
				0.30
			)
		&"maw_quake":
			return _base_payload(
				&"maw_quake",
				&"area",
				"▴",
				"·",
				"▴",
				Color(1.0, 0.66, 0.24, 1.0),
				Color(1.0, 0.66, 0.24, 0.42),
				Color(0.90, 0.12, 0.02, 0.18),
				Color(1.0, 0.46, 0.12, 0.42),
				0.30
			)
		&"undertow":
			return _base_payload(
				&"undertow",
				&"area",
				"≈",
				"≈",
				"≈",
				Color(0.48, 0.88, 1.0, 1.0),
				Color(0.48, 0.88, 1.0, 0.44),
				Color(0.05, 0.32, 0.58, 0.18),
				Color(0.38, 0.82, 1.0, 0.42),
				0.30
			)
		&"mirror_ray":
			return _base_payload(
				&"mirror_ray",
				&"beam",
				"◇",
				"·",
				"◆",
				Color(1.0, 0.82, 1.0, 1.0),
				Color(1.0, 0.82, 1.0, 0.46),
				Color(0.42, 0.10, 0.68, 0.18),
				Color(0.96, 0.64, 1.0, 0.42),
				0.28
			)
		&"prism_fracture":
			return _base_payload(
				&"prism_fracture",
				&"area",
				"◆",
				"◇",
				"◆",
				Color(1.0, 0.76, 1.0, 1.0),
				Color(1.0, 0.76, 1.0, 0.44),
				Color(0.50, 0.14, 0.72, 0.18),
				Color(1.0, 0.58, 1.0, 0.42),
				0.28
			)
		&"arcane_spark":
			return _base_payload(
				&"arcane_spark",
				&"bolt",
				"✦",
				"·",
				"✦",
				Color(0.78, 0.58, 1.0, 1.0),
				Color(0.78, 0.58, 1.0, 0.44),
				Color(0.30, 0.12, 0.74, 0.12),
				Color.TRANSPARENT,
				0.20
			)
		&"chain_lightning":
			return _base_payload(
				&"chain_lightning",
				&"chain",
				"~",
				"~",
				"✦",
				Color(0.72, 0.92, 1.0, 1.0),
				Color(0.72, 0.92, 1.0, 0.44),
				Color(0.20, 0.48, 1.0, 0.12),
				Color.TRANSPARENT,
				0.22
			)
		&"frost_nova":
			return _base_payload(
				&"frost_nova",
				&"nova",
				"❄",
				"·",
				"❄",
				Color(0.62, 0.90, 1.0, 1.0),
				Color(0.62, 0.90, 1.0, 0.42),
				Color(0.12, 0.46, 0.82, 0.14),
				Color.TRANSPARENT,
				0.26
			)
		&"blink_pulse_hazard":
			return _base_payload(
				&"blink_pulse_hazard",
				&"hazard",
				"⊙",
				"·",
				"⊙",
				Color(0.82, 0.95, 1.0, 1.0),
				Color(0.82, 0.95, 1.0, 0.34),
				Color(0.18, 0.46, 1.0, 0.12),
				Color(0.72, 0.90, 1.0, 0.30),
				0.22
			)
		&"spore_hazard":
			return _base_payload(
				&"spore_hazard",
				&"hazard",
				"✹",
				"·",
				"✹",
				Color(0.76, 1.0, 0.52, 1.0),
				Color(0.76, 1.0, 0.52, 0.34),
				Color(0.22, 0.60, 0.18, 0.14),
				Color(0.90, 0.58, 0.82, 0.30),
				0.22
			)
		&"molten_cracks":
			return _base_payload(
				&"molten_cracks",
				&"hazard",
				"▴",
				"*",
				"▴",
				Color(1.0, 0.66, 0.24, 1.0),
				Color(1.0, 0.46, 0.12, 0.34),
				Color(0.90, 0.12, 0.02, 0.14),
				Color(1.0, 0.46, 0.12, 0.30),
				0.22
			)
		&"undertow_hazard":
			return _base_payload(
				&"undertow_hazard",
				&"hazard",
				"≈",
				"≈",
				"≈",
				Color(0.48, 0.88, 1.0, 1.0),
				Color(0.48, 0.88, 1.0, 0.34),
				Color(0.05, 0.32, 0.58, 0.14),
				Color(0.38, 0.82, 1.0, 0.30),
				0.22
			)
		&"mirror_shards":
			return _base_payload(
				&"mirror_shards",
				&"hazard",
				"◆",
				"◇",
				"◆",
				Color(1.0, 0.76, 1.0, 1.0),
				Color(1.0, 0.76, 1.0, 0.34),
				Color(0.50, 0.14, 0.72, 0.14),
				Color(1.0, 0.58, 1.0, 0.30),
				0.22
			)
	return {}


static func _base_payload(
	profile_id: StringName,
	style: StringName,
	glyph: String,
	trail_glyph: String,
	impact_glyph: String,
	color: Color,
	trail_color: Color,
	fill_color: Color,
	border_color: Color,
	duration_seconds: float
) -> Dictionary:
	var payload: Dictionary = {
		"profile_id": profile_id,
		"style": style,
		"glyph": glyph,
		"trail_glyph": trail_glyph,
		"impact_glyph": impact_glyph,
		"color": color,
		"trail_color": trail_color,
		"impact_color": color,
		"fill_color": fill_color,
		"border_color": border_color,
		"duration_seconds": duration_seconds,
		"respect_visibility": true,
	}
	for key: String in rarity_vfx_for(ItemDataScript.ItemRarity.COMMON).keys():
		payload[key] = rarity_vfx_for(ItemDataScript.ItemRarity.COMMON)[key]
	return payload


static func _resource_string_name(
	resource: Resource, property_name: String, fallback: StringName = &""
) -> StringName:
	if resource == null or not (property_name in resource):
		return fallback
	var value: Variant = resource.get(property_name)
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return fallback


static func _item_fallback_projectile_id(
	item: Resource, source: StringName, damage_type: StringName
) -> StringName:
	var is_staff: bool = bool(item.get("is_staff")) if "is_staff" in item else false
	var use_effect: int = (
		int(item.get("use_effect")) if "use_effect" in item else ItemDataScript.ItemUse.NONE
	)
	var weapon_damage_type: StringName = _resource_string_name(item, "weapon_damage_type", &"")
	if is_staff:
		return &"arcane_bolt"
	match use_effect:
		ItemDataScript.ItemUse.MAGIC_MISSILE:
			return &"magic_missile"
		ItemDataScript.ItemUse.AREA_DAMAGE:
			return &"fireball"
		ItemDataScript.ItemUse.SLEEP:
			return &"sleep_mote"
	if (
		source == &"weapon"
		and (weapon_damage_type == &"ranged" or weapon_damage_type == &"piercing")
	):
		return &"arrow"
	if weapon_damage_type != &"" and weapon_damage_type != &"melee":
		return _profile_id_for_fallback(weapon_damage_type)
	return _profile_id_for_fallback(damage_type)


static func _apply_fallback_color(payload: Dictionary, fallback_color: Color) -> void:
	for key: String in ["color", "trail_color", "impact_color", "fill_color", "border_color"]:
		var color: Color = payload.get(key, Color.WHITE)
		payload[key] = Color(fallback_color.r, fallback_color.g, fallback_color.b, color.a)
