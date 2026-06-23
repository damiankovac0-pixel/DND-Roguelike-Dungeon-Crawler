class_name Actor
extends Node2D

signal moved(new_position: Vector2i)
signal died(actor)

# === Constants ===
const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const CELL_SIZE: int = DungeonDataScript.CELL_SIZE

# === Public Variables ===
var display_name: String = "Actor"
var glyph: String = "@"
var color: Color = Color.WHITE
var grid_position: Vector2i = Vector2i.ZERO
var blocks_movement: bool = true
var stats_component: Node
var inventory_component: Node


# === Lifecycle Methods ===
func _ready() -> void:
	stats_component = get_node_or_null("StatsComponent")
	inventory_component = get_node_or_null("InventoryComponent")
	if stats_component != null and inventory_component != null:
		stats_component.inventory_component = inventory_component
	if stats_component != null:
		stats_component.died.connect(_on_stats_died)
	_sync_world_position()


# === Public Methods ===
func setup_actor(
	actor_name: String, actor_glyph: String, actor_color: Color, start_position: Vector2i
) -> void:
	display_name = actor_name
	glyph = actor_glyph
	color = actor_color
	grid_position = start_position
	_sync_world_position()


func set_grid_position(new_position: Vector2i) -> void:
	grid_position = new_position
	_sync_world_position()
	moved.emit(grid_position)


func is_alive() -> bool:
	return stats_component != null and stats_component.current_hp > 0


# === Private Methods ===
func _sync_world_position() -> void:
	position = Vector2(grid_position.x * CELL_SIZE, grid_position.y * CELL_SIZE)


func _on_stats_died() -> void:
	died.emit(self)
