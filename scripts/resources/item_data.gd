## Resource defining an item: kind, rarity, price, stats, use effects, and special abilities.
class_name ItemData
extends Resource

# === Enums ===
enum ItemKind {
	CONSUMABLE,
	WEAPON,
	ARMOR,
	ACCESSORY,
}

enum ItemRarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	MYTHIC,
	ASCENDED,
}

enum ItemUse {
	NONE,
	HEAL,
	RANGED_ATTACK,
	MAGIC_MISSILE,
	SHIELD,
	SLEEP,
	HASTE,
	AREA_DAMAGE,
	REGEN,
}

enum ItemSpecial {
	NONE,
	KILL_REGEN_PERCENT,
	CURRENT_HP_DAMAGE_PERCENT,
	DASH_CHARGE,
}

# === Constants ===
const RARITY_NAMES: Array[String] = [
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Ascended",
]
const RARITY_COLORS: Array[String] = [
	"#d8d8d8",
	"#7bd88f",
	"#8fb3ff",
	"#d78fff",
	"#ffb84d",
	"#ff5fd7",
	"#66fff0",
]

# === Exports ===
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var glyph: String = "!"
@export var color: Color = Color.WHITE
@export var kind: ItemKind = ItemKind.CONSUMABLE
@export var rarity: ItemRarity = ItemRarity.COMMON
@export var base_price: int = 5
@export var spawn_weight: int = 10
@export var min_floor: int = 1
@export var max_floor: int = 0
@export var is_ranged_weapon: bool = false
@export var range: int = 1
@export var use_effect: ItemUse = ItemUse.NONE
@export var effect_duration: int = 0
@export var target_radius: int = 0
@export var target_count: int = 1
@export var healing_amount: int = 0
@export var damage_dice: int = 1
@export var damage_sides: int = 0
@export var attack_bonus: int = 0
@export var damage_bonus: int = 0
@export var armor_bonus: int = 0
@export var special_effect: ItemSpecial = ItemSpecial.NONE
@export var special_amount: int = 0
@export var special_cooldown: int = 0
@export var required_class: StringName = &""
@export var is_staff: bool = false
@export var projectile_id: StringName = &""
@export var weapon_damage_type: StringName = &"melee"
@export var class_damage_type: StringName = &""
@export var class_damage_percent_bonus: int = 0
@export var set_id: StringName = &""
@export var set_display_name: String = ""
@export var set_required_count: int = 2
@export var set_damage_resist_percent: int = 0
@export var set_proc_chance_percent: int = 0
@export var set_proc_heal_percent: int = 0


# === Public Methods ===
func get_kind_name() -> String:
	match kind:
		ItemKind.CONSUMABLE:
			return "Consumable"
		ItemKind.WEAPON:
			return "Weapon"
		ItemKind.ARMOR:
			return "Armor"
		ItemKind.ACCESSORY:
			return "Accessory"
	return "Item"


func get_rarity_name() -> String:
	if rarity >= 0 and rarity < RARITY_NAMES.size():
		return RARITY_NAMES[rarity]
	return RARITY_NAMES[ItemRarity.COMMON]


func get_rarity_color() -> String:
	if rarity >= 0 and rarity < RARITY_COLORS.size():
		return RARITY_COLORS[rarity]
	return RARITY_COLORS[ItemRarity.COMMON]


func get_display_name_bbcode(animated: bool = true) -> String:
	return format_rarity_text(display_name, rarity, animated)


static func format_rarity_text(text: String, rarity_value: int, animated: bool = true) -> String:
	var safe_rarity: int = clampi(rarity_value, ItemRarity.COMMON, RARITY_COLORS.size() - 1)
	var color: String = RARITY_COLORS[safe_rarity]
	var colored_text: String = "[color=%s]%s[/color]" % [color, _escape_bbcode(text)]
	if not animated:
		return colored_text
	match safe_rarity:
		ItemRarity.LEGENDARY:
			return _rarity_shimmer_text(colored_text, color, "#fff1a0", 2.05, 0.48, 0.58, 0.0)
		ItemRarity.MYTHIC:
			return _rarity_shimmer_text(colored_text, color, "#ffd6ff", 2.45, 0.62, 0.62, 0.35)
		ItemRarity.ASCENDED:
			return _rarity_shimmer_text(colored_text, color, "#ffffff", 2.25, 0.58, 0.70, 0.55)
	return colored_text


static func _rarity_shimmer_text(
	colored_text: String,
	base_color: String,
	accent_color: String,
	speed: float,
	spread: float,
	intensity: float,
	lift: float
) -> String:
	return (
		(
			"[rarity_shimmer base=%s accent=%s speed=%.2f spread=%.2f intensity=%.2f lift=%.2f]"
			+ "%s[/rarity_shimmer]"
		)
		% [base_color, accent_color, speed, spread, intensity, lift, colored_text]
	)


static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func get_price() -> int:
	var rarity_multiplier: float = 1.0
	match rarity:
		ItemRarity.COMMON:
			rarity_multiplier = 1.0
		ItemRarity.UNCOMMON:
			rarity_multiplier = 1.5
		ItemRarity.RARE:
			rarity_multiplier = 2.5
		ItemRarity.EPIC:
			rarity_multiplier = 4.0
		ItemRarity.LEGENDARY:
			rarity_multiplier = 6.0
		ItemRarity.MYTHIC:
			rarity_multiplier = 8.0
		ItemRarity.ASCENDED:
			rarity_multiplier = 12.0
	return max(1, int(ceil(base_price * rarity_multiplier)))
