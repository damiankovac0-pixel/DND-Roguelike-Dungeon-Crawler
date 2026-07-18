## Deterministic V31 Hard presentation coverage for elite snapshots, atlas tinting,
## boss immunity labels, and contextual adaptive-shield sensory feedback.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##     res://scripts/tests/test_v31_hard_presentation.gd
extends SceneTree

const EnemyScript = preload("res://scripts/entities/enemy.gd")
const GAME_SCRIPT_PATH: String = "res://scripts/game.gd"
const MapPresentationStateScript = preload(
	"res://scripts/ui/map_presentation/map_presentation_state.gd"
)
const SensoryFeedbackScript = preload("res://scripts/ui/sensory_feedback.gd")
const ACTOR_CATALOG_PATH: String = "res://resources/visuals/catalogs/actor_visual_catalog.tres"
const REGULAR_ENEMY_PATH: String = "res://resources/enemies/goblin.tres"
const BOSS_PATHS: Dictionary = {
	&"observer": "res://resources/enemies/the_observer.tres",
	&"seraphine": "res://resources/enemies/seraphine_thorn_saint.tres",
	&"vorrak": "res://resources/enemies/vorrak_ashen_maw.tres",
	&"kaelros": "res://resources/enemies/kaelros_drowned_king.tres",
	&"nyxara": "res://resources/enemies/nyxara_mirror_witch.tres",
}
const EXPECTED_ELITE_TINT: Color = Color(1.0, 0.84, 0.48, 1.0)
const UNKNOWN_TINT: Color = Color(1.0, 0.0, 1.0, 1.0)


class AliveSummon:
	extends Node

	func is_alive() -> bool:
		return true


var _failures: Array[String] = []
var _game_manager: Node
var _saved_difficulty: StringName = &"normal"
var _saved_history: Array = []
var _game: Node
var _owned_nodes: Array[Node] = []
var _sensory: Control


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_game_manager = root.get_node_or_null("/root/GameManager")
	if _game_manager == null:
		_fail("GameManager autoload is missing")
		await _finish()
		return
	_saved_difficulty = _game_manager.pending_difficulty
	_saved_history = _game_manager.character_history.duplicate(true)
	var game_script: GDScript = load(GAME_SCRIPT_PATH)
	_expect(game_script != null and game_script.can_instantiate(), "Game script failed to load")
	if game_script == null or not game_script.can_instantiate():
		await _finish()
		return
	_game = game_script.new()

	_check_enemy_snapshot_contract()
	_check_actor_tints()
	_check_boss_immunity_labels()
	await _check_shield_sensory_feedback()
	await _finish()


func _check_enemy_snapshot_contract() -> void:
	var enemy: Node = EnemyScript.new()
	_owned_nodes.append(enemy)
	_expect_equal(enemy.is_elite, false, "Enemy should default to a non-elite")
	_expect_equal(typeof(enemy.is_elite), TYPE_BOOL, "Enemy elite state should remain boolean")
	_expect_equal(enemy.elite_behavior, &"", "Enemy should default to no elite behavior")
	_expect_equal(
		typeof(enemy.elite_behavior),
		TYPE_STRING_NAME,
		"Enemy elite behavior should remain a StringName",
	)

	var enemy_template: Resource = load(REGULAR_ENEMY_PATH)
	_expect(enemy_template != null, "Regular enemy fixture failed to load")
	if enemy_template == null:
		return
	var enemy_data: Resource = enemy_template.duplicate(true)
	enemy.initialize_from_data(enemy_data, Vector2i(4, 7))
	enemy.is_elite = true
	enemy.elite_behavior = &"hunter"
	_expect_equal(enemy.is_elite, true, "Enemy should retain its assigned elite state")
	_expect_equal(
		enemy.elite_behavior, &"hunter", "Enemy should retain its assigned elite behavior"
	)

	var state: RefCounted = MapPresentationStateScript.new()
	state.capture_actors([enemy])
	var snapshot: Dictionary = _snapshot_for(state.actors, enemy.get_instance_id())
	_expect(not snapshot.is_empty(), "MapPresentationState omitted the elite enemy")
	_expect_equal(snapshot.get("kind"), &"enemy", "Elite snapshot kind should stay enemy")
	_expect_equal(snapshot.get("is_elite"), true, "Elite state was lost in actor snapshot")
	_expect_equal(
		snapshot.get("visual_id"),
		enemy_data.visual_id,
		"Elite snapshot should retain the authored enemy visual",
	)

	var parity: Dictionary = state.get_parity_snapshot()
	var parity_actors: Array = parity.get("actors", [])
	var parity_snapshot: Dictionary = _snapshot_for(parity_actors, enemy.get_instance_id())
	_expect_equal(
		parity_snapshot.get("is_elite"),
		true,
		"Elite state was lost in the renderer-neutral parity snapshot",
	)

	enemy.is_elite = false
	_expect_equal(
		parity_snapshot.get("is_elite"),
		true,
		"Captured elite presentation state should not alias later actor mutation",
	)
	_expect_equal(
		enemy.elite_behavior,
		&"hunter",
		"Presentation capture should not mutate the actor's elite behavior",
	)


func _check_actor_tints() -> void:
	var catalog: Resource = load(ACTOR_CATALOG_PATH)
	_expect(catalog != null, "Actor visual catalog failed to load")
	if catalog == null:
		return
	_expect_equal(catalog.validate(), "", "Actor visual catalog should remain valid")

	var regular_elite: Dictionary = {
		"visual_id": &"actor/enemy/goblin",
		"kind": &"enemy",
		"is_elite": true,
		"is_player": false,
		"is_boss": false,
		"is_summon": false,
	}
	var elite_tint: Color = catalog.tint_for(regular_elite)
	_expect_equal(elite_tint, EXPECTED_ELITE_TINT, "Known regular elite tint drifted")
	_expect(
		elite_tint.g > 0.75 and elite_tint.g < 0.9 and elite_tint.b > 0.35 and elite_tint.b < 0.6,
		"Elite gold should remain restrained rather than becoming a saturated warning color",
	)

	var regular_enemy: Dictionary = regular_elite.duplicate(true)
	regular_enemy["is_elite"] = false
	_expect_equal(
		catalog.tint_for(regular_enemy), Color.WHITE, "Known non-elite tint should stay neutral"
	)
	_expect_equal(
		(
			catalog
			. tint_for(
				{
					"visual_id": &"boss/observer",
					"boss_id": &"observer",
					"kind": &"boss",
					"is_boss": true,
					"is_elite": true,
				}
			)
		),
		Color.WHITE,
		"Known boss should never receive the regular-elite tint",
	)
	_expect_equal(
		(
			catalog
			. tint_for(
				{
					"visual_id": &"actor/summon",
					"kind": &"summon",
					"is_summon": true,
					"is_elite": true,
				}
			)
		),
		Color.WHITE,
		"Known summon should never receive the regular-elite tint",
	)
	_expect_equal(
		(
			catalog
			. tint_for(
				{
					"visual_id": &"actor/player/fighter",
					"kind": &"player",
					"is_player": true,
					"is_elite": true,
				}
			)
		),
		Color.WHITE,
		"Known player should never receive the regular-elite tint",
	)
	_expect_equal(
		(
			catalog
			. tint_for(
				{
					"visual_id": &"actor/enemy/unmapped_elite",
					"kind": &"enemy",
					"is_elite": true,
				}
			)
		),
		UNKNOWN_TINT,
		"Unknown elite visual should retain the visible magenta fallback",
	)


func _check_boss_immunity_labels() -> void:
	var bosses: Dictionary = {}
	for boss_id: StringName in BOSS_PATHS:
		var boss: Node = _new_boss(boss_id)
		if boss != null:
			bosses[boss_id] = boss
	if bosses.size() != BOSS_PATHS.size():
		return

	var observer: Node = bosses[&"observer"]
	var observer_state: Dictionary = _game._make_boss_state(observer)
	var seraphine: Node = bosses[&"seraphine"]
	var seraphine_state: Dictionary = _game._make_boss_state(seraphine)
	seraphine_state["active_shield_channel"] = &"ranged"
	seraphine_state["active_shield_turns"] = 2

	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NORMAL
	var normal_observer_label: String = _game._boss_strategy_label(
		observer, observer_state, observer.enemy_data
	)
	_expect_equal(
		normal_observer_label,
		"EYE WATCHING // EVADE TO EXPOSE",
		"Normal Observer strategy label should remain unchanged",
	)
	var normal_adaptive_label: String = _game._boss_strategy_label(
		seraphine, seraphine_state, seraphine.enemy_data
	)
	_expect(
		not normal_adaptive_label.contains("IMMUNE"),
		"Normal boss labels should ignore dormant Hard shield state",
	)

	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_HARD
	var observer_label: String = _game._boss_strategy_label(
		observer, observer_state, observer.enemy_data
	)
	_expect(observer_label.contains("EYE WATCHING"), "Observer label lost its counterplay hint")
	_expect(
		observer_label.contains("RANGED IMMUNE"),
		"Closed-eye Observer label should expose its fixed ranged immunity",
	)
	observer_state["exposed_turns"] = 1
	var open_eye_label: String = _game._boss_strategy_label(
		observer, observer_state, observer.enemy_data
	)
	_expect(
		not open_eye_label.contains("IMMUNE"),
		"Open-eye Observer label should remove the fixed immunity",
	)

	_assert_adaptive_label(seraphine, seraphine_state, "BRIARS 3/3", "RANGED IMMUNE 2")
	var vorrak: Node = bosses[&"vorrak"]
	var vorrak_state: Dictionary = _game._make_boss_state(vorrak)
	vorrak_state["active_shield_channel"] = &"melee"
	vorrak_state["active_shield_turns"] = 1
	_assert_adaptive_label(vorrak, vorrak_state, "HEAT 0/3", "MELEE IMMUNE 1")
	var nyxara: Node = bosses[&"nyxara"]
	var nyxara_state: Dictionary = _game._make_boss_state(nyxara)
	nyxara_state["active_shield_channel"] = &"magic"
	nyxara_state["active_shield_turns"] = 2
	_assert_adaptive_label(nyxara, nyxara_state, "TRUE ANGLE N", "MAGIC IMMUNE 2")

	var kaelros: Node = bosses[&"kaelros"]
	var retainer: Node = AliveSummon.new()
	_owned_nodes.append(retainer)
	retainer.set_meta(&"summoned_minion", true)
	retainer.set_meta(&"summoner_id", kaelros.get_instance_id())
	_game._enemies.append(retainer)
	var kaelros_state: Dictionary = _game._make_boss_state(kaelros)
	var guarded_label: String = _game._boss_strategy_label(
		kaelros, kaelros_state, kaelros.enemy_data
	)
	_expect(
		guarded_label.contains("CROWN GUARDED // RETINUE 1"),
		"Kaelros label should name the live-retinue shield condition",
	)
	_expect(
		guarded_label.contains("MAGIC IMMUNE"),
		"Kaelros label should expose fixed magic immunity while a retainer lives",
	)
	_game._enemies.erase(retainer)
	var unguarded_label: String = _game._boss_strategy_label(
		kaelros, kaelros_state, kaelros.enemy_data
	)
	_expect_equal(
		unguarded_label,
		"TIDE UNBOUND",
		"Kaelros label should clear fixed immunity when the last retainer is gone",
	)


func _check_shield_sensory_feedback() -> void:
	_sensory = SensoryFeedbackScript.new()
	root.add_child(_sensory)
	await process_frame
	_sensory.set_reduced_vfx_enabled(false, false)
	_sensory.set_audio_enabled(false, false, false)
	var initial_cache_size: int = _sensory._boss_attack_streams.size()
	var muted_key: StringName = &"seraphine|briar_rebuke|shield"
	_sensory.play_boss_attack_cue(&"seraphine", &"briar_rebuke", &"shield")
	_expect_equal(
		_sensory._boss_attack_streams.size(),
		initial_cache_size,
		"Muted shield cue should not allocate a contextual stream",
	)
	_expect(
		not _sensory._boss_attack_streams.has(muted_key),
		"Muted shield cue should leave its lazy cache key absent",
	)
	_expect(
		_sensory.has_active_visual_feedback(),
		"Muted shield cue should retain user-readable visual feedback",
	)
	var expected_seraphine_visual: Color = Color(0.82, 1.0, 0.42, _sensory._visual_color.a)
	_expect(
		_sensory._visual_color.is_equal_approx(expected_seraphine_visual),
		"Shield visual should remain contextual to Seraphine",
	)

	_sensory.set_audio_enabled(true, false, false)
	var telegraph_cue: StringName = _sensory.CUE_BOSS_TELEGRAPH
	var profile: Dictionary = _sensory.CUE_PROFILES.get(telegraph_cue, {})
	var min_interval: float = float(profile.get("min_interval", 0.0))
	_expect(min_interval > 0.0, "Boss shield cue should retain telegraph rate limiting")
	_make_cue_eligible(telegraph_cue, min_interval)
	_sensory.play_boss_attack_cue(&"seraphine", &"briar_rebuke", &"shield")
	var seraphine_stream: AudioStreamWAV = (
		_sensory._boss_attack_streams.get(muted_key) as AudioStreamWAV
	)
	_expect(seraphine_stream != null, "Enabled shield cue should lazily cache its stream")
	if seraphine_stream != null:
		_expect(not seraphine_stream.data.is_empty(), "Shield cue stream should contain PCM data")

	var vorrak_key: StringName = &"vorrak|maw_snap|shield"
	_make_cue_eligible(telegraph_cue, min_interval)
	_sensory.play_boss_attack_cue(&"vorrak", &"maw_snap", &"shield")
	var vorrak_stream: AudioStreamWAV = (
		_sensory._boss_attack_streams.get(vorrak_key) as AudioStreamWAV
	)
	_expect(vorrak_stream != null, "Second boss shield cue should own a contextual cache entry")
	if seraphine_stream != null and vorrak_stream != null:
		_expect(
			seraphine_stream.data != vorrak_stream.data,
			"Different bosses should not collapse to one generic shield sound",
		)
	var expected_vorrak_visual: Color = Color(1.0, 0.38, 0.12, _sensory._visual_color.a)
	_expect(
		_sensory._visual_color.is_equal_approx(expected_vorrak_visual),
		"Shield visual should remain contextual to Vorrak",
	)


func _new_boss(boss_id: StringName) -> Node:
	var path: String = str(BOSS_PATHS.get(boss_id, ""))
	var template: Resource = load(path)
	_expect(template != null, "Boss fixture failed to load: %s" % boss_id)
	if template == null:
		return null
	var boss: Node = EnemyScript.new()
	boss.name = StringName("Test_%s" % boss_id)
	boss.initialize_from_data(template.duplicate(true), Vector2i(8, 8))
	_owned_nodes.append(boss)
	return boss


func _assert_adaptive_label(
	boss: Node, state: Dictionary, base_fragment: String, immunity_fragment: String
) -> void:
	var label: String = _game._boss_strategy_label(boss, state, boss.enemy_data)
	_expect(
		label.contains(base_fragment),
		"%s label lost base strategy context: %s" % [boss.enemy_data.boss_id, label],
	)
	_expect(
		label.contains(immunity_fragment),
		"%s label omitted active shield channel or turns: %s" % [boss.enemy_data.boss_id, label],
	)


func _make_cue_eligible(cue_name: StringName, min_interval: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_sensory._cue_last_play_time[cue_name] = now - min_interval - 1.0


func _snapshot_for(snapshots: Array, instance_id: int) -> Dictionary:
	for snapshot_value: Variant in snapshots:
		if snapshot_value is Dictionary:
			var snapshot: Dictionary = snapshot_value
			if int(snapshot.get("id", 0)) == instance_id:
				return snapshot
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("FAIL: %s" % message)


func _finish() -> void:
	if _game_manager != null:
		_game_manager.pending_difficulty = _saved_difficulty
		_game_manager.character_history = _saved_history.duplicate(true)
	if is_instance_valid(_game):
		_game._enemies.clear()
		_game.free()
	for node: Node in _owned_nodes:
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()
	if is_instance_valid(_sensory):
		_sensory.queue_free()
		await process_frame
	if _failures.is_empty():
		print("V31 Hard presentation checks passed")
		quit(0)
	else:
		printerr("V31 Hard presentation checks failed: %d" % _failures.size())
		quit(1)
