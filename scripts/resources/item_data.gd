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
@export var healing_amount: int = 0
@export var damage_dice: int = 1
@export var damage_sides: int = 0
@export var attack_bonus: int = 0
@export var damage_bonus: int = 0
@export var armor_bonus: int = 0


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
			rarity_multiplier = 10.0
		ItemRarity.ASCENDED:
			rarity_multiplier = 18.0
	return max(1, int(ceil(base_price * rarity_multiplier)))
