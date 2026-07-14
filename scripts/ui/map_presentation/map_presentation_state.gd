class_name MapPresentationState
extends RefCounted
## Mutable renderer-neutral snapshot assembled by the legacy MapView facade.
##
## Fields contain already-computed game cells and semantic presentation data.
## Renderers must not use this object to mutate gameplay state.

# === Revision Counters ===
var revision: int = 0
var map_revision: int = 0
var visibility_revision: int = 0
var actor_revision: int = 0
var overlay_revision: int = 0
var environment_revision: int = 0

# === Map and Environment ===
var map_data: Array = []
var map_size: Vector2i = Vector2i.ZERO
var biome_theme: Dictionary = {}
var atmosphere_profile: Dictionary = {}
var atmosphere_enabled: bool = true
var reduced_vfx_enabled: bool = false

# === Visibility ===
var visible_cells: Dictionary = {}
var explored_cells: Dictionary = {}

# === Entities and Objects ===
var actors: Array[Dictionary] = []
var focus_cell: Vector2i = Vector2i.ZERO
var items: Dictionary = {}
var containers: Dictionary = {}
var trap_data: Dictionary = {}
var revealed_traps: Dictionary = {}
var triggered_traps: Dictionary = {}
var secret_walls: Dictionary = {}
var revealed_secret_walls: Dictionary = {}
var secret_wall_hint_color: Color = Color.WHITE

# === Tactical and Boss Presentation ===
var enemy_intents: Dictionary = {}
var targeting_active: bool = false
var target_cursor: Vector2i = Vector2i.ZERO
var target_range_cells: Dictionary = {}
var target_area_cells: Dictionary = {}
var boss_room_cells: Dictionary = {}
var boss_door_cells: Array[Vector2i] = []
var boss_room_locked: bool = false
var boss_room_tint_color: Color = Color.TRANSPARENT
var boss_visuals: Dictionary = {}
var boss_telegraphs: Dictionary = {}
var boss_hazards: Dictionary = {}


# === Public Methods ===
func capture_map(map: Array) -> void:
	map_data = map
	map_size = Vector2i(map[0].size(), map.size()) if not map.is_empty() else Vector2i.ZERO
	map_revision += 1
	_touch()


func capture_actors(actor_nodes: Array) -> void:
	actors.clear()
	focus_cell = Vector2i.ZERO
	for actor: Variant in actor_nodes:
		if actor == null or not is_instance_valid(actor):
			continue
		var cell_value: Variant = actor.get("grid_position")
		if not (cell_value is Vector2i):
			continue
		var alive: bool = true
		if actor.has_method(&"is_alive"):
			alive = bool(actor.call(&"is_alive"))
		var actor_name: StringName = actor.name if actor is Node else &""
		var color_value: Variant = actor.get("color")
		var snapshot: Dictionary = {
			"id": actor.get_instance_id(),
			"name": actor_name,
			"is_player": actor_name == &"Player",
			"cell": cell_value,
			"alive": alive,
			"glyph": str(actor.get("glyph")),
			"color": color_value if color_value is Color else Color.WHITE,
		}
		actors.append(snapshot)
		if bool(snapshot["is_player"]):
			focus_cell = cell_value
	actor_revision += 1
	_touch()


func mark_visibility_changed() -> void:
	visibility_revision += 1
	_touch()


func mark_overlay_changed() -> void:
	overlay_revision += 1
	_touch()


func mark_environment_changed() -> void:
	environment_revision += 1
	_touch()


func get_player_snapshot() -> Dictionary:
	for actor: Dictionary in actors:
		if bool(actor.get("is_player", false)):
			return actor
	return {}


func get_debug_summary() -> Dictionary:
	return {
		"revision": revision,
		"map_revision": map_revision,
		"visibility_revision": visibility_revision,
		"actor_revision": actor_revision,
		"overlay_revision": overlay_revision,
		"environment_revision": environment_revision,
		"map_size": map_size,
		"actor_count": actors.size(),
		"focus_cell": focus_cell,
	}


# === Private Methods ===
func _touch() -> void:
	revision += 1
