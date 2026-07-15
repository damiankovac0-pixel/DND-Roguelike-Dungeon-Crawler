class_name MapObjectVisualCatalog
extends Resource
## Explicit atlas mapping for items, containers, props, and traps.
##
## Gameplay supplies semantic visual IDs. Runtime lookup never scans directories
## or constructs resource paths.

# === Constants ===
const CELL_SIZE: Vector2i = Vector2i(16, 16)
const ATLAS_SIZE: Vector2i = Vector2i(1664, 16)
const FALLBACK_COORDS: Vector2i = Vector2i(16, 0)
const ATLAS_COORDS: Dictionary = {
	# === Exact IDs (columns 0–27) ===
	&"item/potion": Vector2i(0, 0),
	&"item/elixir": Vector2i(1, 0),
	&"item/scroll": Vector2i(2, 0),
	&"item/sword": Vector2i(3, 0),
	&"item/axe": Vector2i(4, 0),
	&"item/dagger": Vector2i(5, 0),
	&"item/mace": Vector2i(6, 0),
	&"item/spear": Vector2i(7, 0),
	&"item/bow": Vector2i(8, 0),
	&"item/crossbow": Vector2i(9, 0),
	&"item/staff": Vector2i(10, 0),
	&"item/armor/light": Vector2i(11, 0),
	&"item/armor/heavy": Vector2i(12, 0),
	&"item/robe": Vector2i(13, 0),
	&"item/ring": Vector2i(14, 0),
	&"item/charm": Vector2i(15, 0),
	&"item/generic": FALLBACK_COORDS,
	&"prop/chest": Vector2i(17, 0),
	&"prop/boss_chest": Vector2i(18, 0),
	&"prop/vase": Vector2i(19, 0),
	&"prop/box": Vector2i(20, 0),
	&"prop/generic": Vector2i(21, 0),
	&"trap/damage": Vector2i(22, 0),
	&"trap/poison": Vector2i(23, 0),
	&"trap/teleport": Vector2i(24, 0),
	&"trap/alarm": Vector2i(25, 0),
	&"trap/stun": Vector2i(26, 0),
	&"trap/ambush": Vector2i(27, 0),
	# === Exact item/resource/<stem> IDs (columns 28–103) ===
	&"item/resource/ascendant_elixir": Vector2i(28, 0),
	&"item/resource/ascended_aegis": Vector2i(29, 0),
	&"item/resource/ascended_sword": Vector2i(30, 0),
	&"item/resource/amulet_of_guarding": Vector2i(31, 0),
	&"item/resource/battle_axe": Vector2i(32, 0),
	&"item/resource/bracers_of_power": Vector2i(33, 0),
	&"item/resource/chainmail": Vector2i(34, 0),
	&"item/resource/dagger": Vector2i(35, 0),
	&"item/resource/celestial_greatbow": Vector2i(36, 0),
	&"item/resource/crown_of_the_deep": Vector2i(37, 0),
	&"item/resource/dragonbone_blade": Vector2i(38, 0),
	&"item/resource/elixir_of_life": Vector2i(39, 0),
	&"item/resource/elixir_of_swiftness": Vector2i(40, 0),
	&"item/resource/elven_chain": Vector2i(41, 0),
	&"item/resource/flail": Vector2i(42, 0),
	&"item/resource/greater_health_potion": Vector2i(43, 0),
	&"item/resource/greatsword": Vector2i(44, 0),
	&"item/resource/half_plate": Vector2i(45, 0),
	&"item/resource/hand_crossbow": Vector2i(46, 0),
	&"item/resource/health_potion": Vector2i(47, 0),
	&"item/resource/heavy_crossbow": Vector2i(48, 0),
	&"item/resource/iron_axe": Vector2i(49, 0),
	&"item/resource/leather_armor": Vector2i(50, 0),
	&"item/resource/longbow": Vector2i(51, 0),
	&"item/resource/longsword": Vector2i(52, 0),
	&"item/resource/mace": Vector2i(53, 0),
	&"item/resource/mythril_plate": Vector2i(54, 0),
	&"item/resource/plate_armor": Vector2i(55, 0),
	&"item/resource/phoenix_elixir": Vector2i(56, 0),
	&"item/resource/potion_of_giant_strength": Vector2i(57, 0),
	&"item/resource/potion_of_haste": Vector2i(58, 0),
	&"item/resource/ring_of_accuracy": Vector2i(59, 0),
	&"item/resource/ring_of_power": Vector2i(60, 0),
	&"item/resource/ring_of_protection": Vector2i(61, 0),
	&"item/resource/scale_mail": Vector2i(62, 0),
	&"item/resource/scimitar": Vector2i(63, 0),
	&"item/resource/scroll_fire_bolt": Vector2i(64, 0),
	&"item/resource/scroll_lightning_bolt": Vector2i(65, 0),
	&"item/resource/scroll_fireball": Vector2i(66, 0),
	&"item/resource/scroll_magic_missile": Vector2i(67, 0),
	&"item/resource/scroll_shield": Vector2i(68, 0),
	&"item/resource/scroll_sleep": Vector2i(69, 0),
	&"item/resource/scroll_regeneration": Vector2i(70, 0),
	&"item/resource/shortbow": Vector2i(71, 0),
	&"item/resource/spear": Vector2i(72, 0),
	&"item/resource/splint_armor": Vector2i(73, 0),
	&"item/resource/stepstone_anklet": Vector2i(74, 0),
	&"item/resource/starfall_charm": Vector2i(75, 0),
	&"item/resource/studded_leather": Vector2i(76, 0),
	&"item/resource/superior_health_potion": Vector2i(77, 0),
	&"item/resource/tonic_of_regeneration": Vector2i(78, 0),
	&"item/resource/warhammer": Vector2i(79, 0),
	&"item/resource/voidglass_rapier": Vector2i(80, 0),
	&"item/resource/apprentice_staff": Vector2i(81, 0),
	&"item/resource/hunting_bow": Vector2i(82, 0),
	&"item/resource/training_sword": Vector2i(83, 0),
	&"item/resource/staff_ember": Vector2i(84, 0),
	&"item/resource/staff_stormglass": Vector2i(85, 0),
	&"item/resource/staff_void": Vector2i(86, 0),
	&"item/resource/staff_astral": Vector2i(87, 0),
	&"item/resource/staff_starfall": Vector2i(88, 0),
	&"item/resource/staff_ascendant": Vector2i(89, 0),
	&"item/resource/vanguard_blade": Vector2i(90, 0),
	&"item/resource/warlord_greatsword": Vector2i(91, 0),
	&"item/resource/eaglewood_bow": Vector2i(92, 0),
	&"item/resource/moonstring_longbow": Vector2i(93, 0),
	&"item/resource/warriors_ring": Vector2i(94, 0),
	&"item/resource/soldiers_plate": Vector2i(95, 0),
	&"item/resource/deft_gloves": Vector2i(96, 0),
	&"item/resource/scouts_cloak": Vector2i(97, 0),
	&"item/resource/mana_circlet": Vector2i(98, 0),
	&"item/resource/arcane_robes": Vector2i(99, 0),
	&"item/resource/guardian_mail": Vector2i(100, 0),
	&"item/resource/guardian_charm": Vector2i(101, 0),
	&"item/resource/siphon_rapier": Vector2i(102, 0),
	&"item/resource/siphon_ring": Vector2i(103, 0),
	# === Compatibility aliases ===
	&"item/consumable": Vector2i(0, 0),
	&"item/weapon": Vector2i(3, 0),
	&"item/armor": Vector2i(11, 0),
	&"item/accessory": Vector2i(14, 0),
	&"trap/generic": Vector2i(22, 0),
}

# === Exports ===
@export var catalog_version: int = 2
@export var object_atlas: Texture2D
@export var enchantment_overlay: Texture2D
@export var prototype: bool = false
@export var attribution: String = "Project-authored production object visual catalog."


# === Public Methods ===
func validate() -> String:
	if catalog_version != 2:
		return "Unsupported map object visual catalogue version"
	if object_atlas == null:
		return "Pixel object atlas is missing"
	if enchantment_overlay == null:
		return "Pixel enchantment overlay is missing"
	if Vector2i(object_atlas.get_size()) != ATLAS_SIZE:
		return "Pixel object atlas must be exactly 1664x16"
	if Vector2i(enchantment_overlay.get_size()) != Vector2i(16, 16):
		return "Pixel enchantment overlay must be exactly 16x16"
	if attribution.strip_edges().is_empty():
		return "Pixel object atlas attribution is missing"
	return ""


func get_atlas() -> Texture2D:
	return object_atlas


func get_enchantment_overlay() -> Texture2D:
	return enchantment_overlay


func region_for(visual_id: StringName) -> Rect2:
	var atlas_coords: Vector2i = ATLAS_COORDS.get(visual_id, FALLBACK_COORDS)
	return Rect2(Vector2(atlas_coords * CELL_SIZE), Vector2(CELL_SIZE))


func has_visual(visual_id: StringName) -> bool:
	return ATLAS_COORDS.has(visual_id)
