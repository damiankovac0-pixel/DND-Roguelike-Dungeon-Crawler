class_name MapPresentationState
extends RefCounted
## Mutable renderer-neutral snapshot assembled by the legacy MapView facade.
##
## Fields contain already-computed game cells and semantic presentation data.
## Renderers must not use this object to mutate gameplay state.

# === Constants ===
const ITEM_VISUAL_IDS: Array[StringName] = [
	&"item/consumable",
	&"item/weapon",
	&"item/armor",
	&"item/accessory",
]
const TRAP_VISUAL_IDS: Array[StringName] = [
	&"trap/damage",
	&"trap/poison",
	&"trap/teleport",
	&"trap/alarm",
	&"trap/stun",
	&"trap/ambush",
]

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

# === Private Variables ===
var _actor_cells_by_id: Dictionary = {}
var _actor_facing_by_id: Dictionary = {}


# === Public Methods ===
func capture_map(map: Array) -> void:
	map_data = map
	map_size = Vector2i(map[0].size(), map.size()) if not map.is_empty() else Vector2i.ZERO
	map_revision += 1
	_touch()


func capture_actors(actor_nodes: Array) -> void:
	actors.clear()
	focus_cell = Vector2i.ZERO
	var active_actor_ids: Dictionary = {}
	for actor: Variant in actor_nodes:
		var snapshot: Dictionary = _snapshot_actor(actor)
		if snapshot.is_empty():
			continue
		var actor_id: int = int(snapshot["id"])
		active_actor_ids[actor_id] = true
		actors.append(snapshot)
		if bool(snapshot["is_player"]):
			focus_cell = snapshot["cell"]
	_prune_actor_history(active_actor_ids)
	actor_revision += 1
	_touch()


func capture_items(item_nodes: Dictionary) -> void:
	items.clear()
	for cell_value: Variant in item_nodes:
		if not (cell_value is Vector2i):
			continue
		var item_value: Variant = item_nodes[cell_value]
		if not (item_value is Resource):
			continue
		var item: Resource = item_value
		var kind_index: int = int(item.get("kind"))
		var visual_id: StringName = &"item/generic"
		var item_visual: Variant = item.get("visual_id")
		if item_visual != null and str(item_visual) != "":
			visual_id = StringName(item_visual)
		elif kind_index >= 0 and kind_index < ITEM_VISUAL_IDS.size():
			visual_id = ITEM_VISUAL_IDS[kind_index]
		var color_value: Variant = item.get("color")
		items[cell_value] = {
			"visual_id": visual_id,
			"kind": kind_index,
			"rarity": int(item.get("rarity")),
			"color": color_value if color_value is Color else Color.WHITE,
		}
	overlay_revision += 1
	_touch()


func capture_containers(container_data: Dictionary) -> void:
	containers.clear()
	for cell_value: Variant in container_data:
		if not (cell_value is Vector2i):
			continue
		var payload_value: Variant = container_data[cell_value]
		if not (payload_value is Dictionary):
			continue
		var payload: Dictionary = payload_value
		var container_type: StringName = StringName(payload.get("type", &""))
		var visual_id: StringName = &"prop/generic"
		if container_type == &"chest":
			visual_id = (
				&"prop/boss_chest" if bool(payload.get("boss_reward", false)) else &"prop/chest"
			)
		elif container_type == &"clutter":
			visual_id = &"prop/vase" if str(payload.get("glyph", "")) == "v" else &"prop/box"
		var color_value: Variant = payload.get("color", Color.WHITE)
		containers[cell_value] = {
			"visual_id": visual_id,
			"type": container_type,
			"rarity": int(payload.get("rarity", 0)),
			"marked": bool(payload.get("marked", false)),
			"color": color_value if color_value is Color else Color.WHITE,
		}
	overlay_revision += 1
	_touch()


func capture_traps(traps: Dictionary, revealed: Dictionary, triggered: Dictionary) -> void:
	trap_data.clear()
	for cell_value: Variant in traps:
		if not (cell_value is Vector2i):
			continue
		var trap_value: Variant = traps[cell_value]
		if not (trap_value is Resource):
			continue
		var trap: Resource = trap_value
		var effect_index: int = int(trap.get("effect"))
		var visual_id: StringName = &"trap/generic"
		var trap_visual: Variant = trap.get("visual_id")
		if trap_visual != null and str(trap_visual) != "":
			visual_id = StringName(trap_visual)
		elif effect_index >= 0 and effect_index < TRAP_VISUAL_IDS.size():
			visual_id = TRAP_VISUAL_IDS[effect_index]
		var color_value: Variant = trap.get("color")
		trap_data[cell_value] = {
			"visual_id": visual_id,
			"effect": effect_index,
			"revealed": revealed.has(cell_value),
			"triggered": triggered.has(cell_value),
			"color": color_value if color_value is Color else Color.WHITE,
		}
	revealed_traps = revealed.duplicate()
	triggered_traps = triggered.duplicate()
	overlay_revision += 1
	_touch()


func capture_secret_walls(walls: Dictionary, revealed: Dictionary, hint_color: Color) -> void:
	secret_walls = walls.duplicate()
	revealed_secret_walls = revealed.duplicate()
	secret_wall_hint_color = hint_color
	overlay_revision += 1
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


func get_parity_snapshot() -> Dictionary:
	return {
		"map_data": map_data.duplicate(true),
		"map_size": map_size,
		"biome_theme": biome_theme.duplicate(true),
		"atmosphere_profile": atmosphere_profile.duplicate(true),
		"atmosphere_enabled": atmosphere_enabled,
		"reduced_vfx_enabled": reduced_vfx_enabled,
		"visible_cells": visible_cells.duplicate(true),
		"explored_cells": explored_cells.duplicate(true),
		"actors": actors.duplicate(true),
		"focus_cell": focus_cell,
		"items": items.duplicate(true),
		"containers": containers.duplicate(true),
		"trap_data": trap_data.duplicate(true),
		"revealed_traps": revealed_traps.duplicate(true),
		"triggered_traps": triggered_traps.duplicate(true),
		"secret_walls": secret_walls.duplicate(true),
		"revealed_secret_walls": revealed_secret_walls.duplicate(true),
		"secret_wall_hint_color": secret_wall_hint_color,
		"enemy_intents": enemy_intents.duplicate(true),
		"targeting_active": targeting_active,
		"target_cursor": target_cursor,
		"target_range_cells": target_range_cells.duplicate(true),
		"target_area_cells": target_area_cells.duplicate(true),
		"boss_room_cells": boss_room_cells.duplicate(true),
		"boss_door_cells": boss_door_cells.duplicate(),
		"boss_room_locked": boss_room_locked,
		"boss_room_tint_color": boss_room_tint_color,
		"boss_visuals": boss_visuals.duplicate(true),
		"boss_telegraphs": boss_telegraphs.duplicate(true),
		"boss_hazards": boss_hazards.duplicate(true),
	}


# === Private Methods ===
func _snapshot_actor(actor: Variant) -> Dictionary:
	if actor == null or not is_instance_valid(actor):
		return {}
	var cell_value: Variant = actor.get("grid_position")
	if not (cell_value is Vector2i):
		return {}
	var actor_id: int = actor.get_instance_id()
	var alive: bool = true
	if actor.has_method(&"is_alive"):
		alive = bool(actor.call(&"is_alive"))
	var actor_name: StringName = actor.name if actor is Node else &""
	var display_name: String = str(actor_name)
	if actor.has_method(&"setup_actor"):
		display_name = str(actor.get("display_name"))
	var enemy_data: Resource
	if actor.has_method(&"initialize_from_data"):
		enemy_data = actor.get("enemy_data")
	var is_player: bool = actor_name == &"Player"
	var is_boss: bool = enemy_data != null and bool(enemy_data.get("is_boss"))
	var is_summon: bool = actor.has_meta(&"summoned_minion")
	var kind: StringName = _actor_kind(is_player, is_boss, is_summon, actor_name)
	var boss_id: StringName = StringName(enemy_data.get("boss_id")) if is_boss else StringName()
	var color_value: Variant = actor.get("color")
	var is_elite: bool = _actor_is_elite(actor)
	return {
		"id": actor_id,
		"name": actor_name,
		"display_name": display_name,
		"kind": kind,
		"visual_id": _visual_id_for(is_player, kind, enemy_data, boss_id),
		"is_player": is_player,
		"is_boss": is_boss,
		"is_summon": is_summon,
		"is_elite": is_elite,
		"boss_id": boss_id,
		"cell": cell_value,
		"occupied_cells": [cell_value],
		"facing": _update_actor_facing(actor_id, cell_value),
		"alive": alive,
		"glyph": str(actor.get("glyph")),
		"color": color_value if color_value is Color else Color.WHITE,
	}


func _actor_kind(
	is_player: bool, is_boss: bool, is_summon: bool, actor_name: StringName
) -> StringName:
	if is_player:
		return &"player"
	if is_boss:
		return &"boss"
	if actor_name == &"Shopkeeper":
		return &"shopkeeper"
	if is_summon:
		return &"summon"
	return &"enemy"


func _actor_is_elite(actor: Variant) -> bool:
	var enemy_actor: Enemy = actor as Enemy
	return enemy_actor != null and enemy_actor.is_elite


func _get_player_class() -> StringName:
	var main_loop: MainLoop = Engine.get_main_loop()
	var tree: SceneTree = main_loop as SceneTree
	if tree == null or tree.root == null:
		return &"fighter"
	var gm: Node = tree.root.get_node_or_null(^"GameManager")
	if gm == null:
		return &"fighter"
	var raw: Variant = gm.get("pending_character_class")
	if raw == null:
		return &"fighter"
	var cls: StringName = StringName(raw)
	if cls == &"fighter" or cls == &"ranger" or cls == &"wizard":
		return cls
	return &"fighter"


func _visual_id_for(
	is_player: bool, kind: StringName, enemy_data: Resource, boss_id: StringName
) -> StringName:
	var visual_id: StringName
	if is_player:
		var player_class: StringName = _get_player_class()
		visual_id = StringName("actor/player/%s" % player_class)
	elif kind == &"boss":
		var enemy_visual: Variant = enemy_data.get("visual_id") if enemy_data != null else null
		if enemy_visual != null and str(enemy_visual) != "":
			visual_id = StringName(enemy_visual)
		elif boss_id != StringName():
			visual_id = StringName("boss/%s" % boss_id)
		else:
			visual_id = &"boss/unknown"
	elif kind == &"shopkeeper":
		visual_id = &"actor/shopkeeper"
	elif kind == &"summon":
		var summon_visual: Variant = enemy_data.get("visual_id") if enemy_data != null else null
		if summon_visual != null and str(summon_visual) != "":
			visual_id = StringName(summon_visual)
		else:
			visual_id = &"actor/summon"
	else:
		# Normal enemy — prefer resource visual_id, fall back to humanoid
		var enemy_visual: Variant = enemy_data.get("visual_id") if enemy_data != null else null
		if enemy_visual != null and str(enemy_visual) != "":
			visual_id = StringName(enemy_visual)
		else:
			visual_id = &"actor/enemy/humanoid"
	return visual_id


func _update_actor_facing(actor_id: int, cell: Vector2i) -> StringName:
	var facing: StringName = _actor_facing_by_id.get(actor_id, &"down")
	var previous_cell: Vector2i = _actor_cells_by_id.get(actor_id, cell)
	var delta: Vector2i = cell - previous_cell
	if delta.x < 0:
		facing = &"left"
	elif delta.x > 0:
		facing = &"right"
	elif delta.y < 0:
		facing = &"up"
	elif delta.y > 0:
		facing = &"down"
	_actor_cells_by_id[actor_id] = cell
	_actor_facing_by_id[actor_id] = facing
	return facing


func _prune_actor_history(active_actor_ids: Dictionary) -> void:
	for actor_id: Variant in _actor_cells_by_id.keys():
		if active_actor_ids.has(actor_id):
			continue
		_actor_cells_by_id.erase(actor_id)
		_actor_facing_by_id.erase(actor_id)


func _touch() -> void:
	revision += 1
