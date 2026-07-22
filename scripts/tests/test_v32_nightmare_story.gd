## V32 Nightmare unlock, encounter tuning, shardbearer lore, and prologue contracts.
##
## Run with:
##   godot --headless --path . --script res://scripts/tests/test_v32_nightmare_story.gd
extends SceneTree

const EnemyDataScript = preload("res://scripts/resources/enemy_data.gd")
const BossAttackDataScript = preload("res://scripts/resources/boss_attack_data.gd")
const EnemyScript = preload("res://scripts/entities/enemy.gd")
const ActorVisualCatalogScript = preload(
	"res://scripts/ui/map_presentation/actor_visual_catalog.gd"
)
const MapPresentationStateScript = preload(
	"res://scripts/ui/map_presentation/map_presentation_state.gd"
)
const BOSS_PATHS: Dictionary = {
	&"observer": "res://resources/enemies/the_observer.tres",
	&"seraphine": "res://resources/enemies/seraphine_thorn_saint.tres",
	&"vorrak": "res://resources/enemies/vorrak_ashen_maw.tres",
	&"kaelros": "res://resources/enemies/kaelros_drowned_king.tres",
	&"nyxara": "res://resources/enemies/nyxara_mirror_witch.tres",
}


class PriceItem:
	extends Resource

	var _price: int

	func _init(price: int) -> void:
		_price = price

	func get_price() -> int:
		return _price


var _failed: bool = false
var _game_manager: Node
var _difficulty_snapshot: StringName
var _history_snapshot: Array = []
var _floor_snapshot: int
var _name_snapshot: String
var _scores_snapshot: Dictionary = {}
var _class_snapshot: StringName
var _debug_snapshot: bool


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_game_manager = root.get_node_or_null("/root/GameManager")
	_expect(_game_manager != null, "GameManager autoload is missing")
	if _game_manager == null:
		quit(1)
		return
	_snapshot_game_manager()
	_check_unlock_chain()
	await _check_nightmare_menu()
	if _failed:
		_finish(null)
		return
	_game_manager.character_history = [_normal_victory(), _hard_victory()]
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NIGHTMARE)
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_WIZARD)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.sensory_feedback.set_audio_enabled(false, false, false)
	_expect(game._player != null, "Nightmare game fixture did not initialize its player")
	if not _failed:
		_check_nightmare_elite_chance(game)
	if not _failed:
		_check_nightmare_enemy_scaling(game)
	if not _failed:
		_check_nightmare_elite_identities(game)
	if not _failed:
		_check_nightmare_boss_escalation(game)
	if not _failed:
		_check_nightmare_economy(game)
	if not _failed:
		await _check_shard_story(game)
	if not _failed:
		await _check_prologue()
	await _finish(game)


func _snapshot_game_manager() -> void:
	_difficulty_snapshot = _game_manager.pending_difficulty
	_history_snapshot = _game_manager.character_history.duplicate(true)
	_floor_snapshot = _game_manager.current_floor
	_name_snapshot = _game_manager.pending_character_name
	_scores_snapshot = _game_manager.pending_ability_scores.duplicate(true)
	_class_snapshot = _game_manager.pending_character_class
	_debug_snapshot = _game_manager.pending_debug_loadout


func _finish(game: Node) -> void:
	if is_instance_valid(game):
		var sensory: Node = game.sensory_feedback
		for audio_player: AudioStreamPlayer in sensory._audio_players:
			audio_player.stop()
			audio_player.stream = null
		if is_instance_valid(sensory._ambience_player):
			sensory._ambience_player.stop()
			sensory._ambience_player.stream = null
		if is_instance_valid(sensory._music_player):
			sensory._music_player.stop()
			sensory._music_player.stream = null
		sensory._ambience_stream = null
		sensory._boss_music_stream = null
		sensory._boss_climax_stream = null
		sensory._cue_streams.clear()
		sensory._boss_attack_streams.clear()
		await process_frame
		game.queue_free()
		await process_frame
	_game_manager.abandon_run()
	_game_manager.pending_difficulty = _difficulty_snapshot
	_game_manager.character_history = _history_snapshot.duplicate(true)
	_game_manager.current_floor = _floor_snapshot
	_game_manager.pending_character_name = _name_snapshot
	_game_manager.pending_ability_scores = _scores_snapshot.duplicate(true)
	_game_manager.pending_character_class = _class_snapshot
	_game_manager.pending_debug_loadout = _debug_snapshot
	if _failed:
		quit(1)
		return
	print("V32 Nightmare tuning, shardbearer lore, and prologue contracts passed")
	quit(0)


func _check_unlock_chain() -> void:
	_expect_equal(_game_manager.GAME_VERSION, "32.0.0", "V32 release metadata drifted")
	var version_history_script: GDScript = load("res://scripts/version_history.gd")
	var found_v32: bool = false
	for entry: String in version_history_script.VERSION_HISTORY:
		if entry.contains("V32.0.0"):
			found_v32 = true
			break
	_expect(found_v32, "Version history omitted the V32.0.0 release")
	_game_manager.character_history = []
	_expect(not _game_manager.is_hard_mode_unlocked(), "Hard unlocked without a Normal victory")
	_expect(
		not _game_manager.is_nightmare_mode_unlocked(),
		"Nightmare unlocked without a Hard victory",
	)
	_game_manager.character_history = [_normal_victory()]
	_expect(_game_manager.is_hard_mode_unlocked(), "Normal victory did not unlock Hard")
	_expect(
		not _game_manager.is_nightmare_mode_unlocked(),
		"Normal victory incorrectly unlocked Nightmare",
	)
	_game_manager.character_history = [_normal_victory(), _hard_victory()]
	_expect(_game_manager.is_nightmare_mode_unlocked(), "Hard victory did not unlock Nightmare")
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NIGHTMARE)
	_expect(_game_manager.is_nightmare_mode(), "Unlocked Nightmare selection was rejected")
	_expect(_game_manager.is_hard_mode(), "Nightmare did not inherit Hard-or-higher rules")
	_expect_equal(
		_game_manager.get_difficulty_label(_game_manager.DIFFICULTY_NIGHTMARE),
		"Nightmare",
		"Nightmare difficulty label drifted",
	)
	_game_manager.character_history = [
		_normal_victory(),
		{
			"name": "debug",
			"victory": true,
			"difficulty": "hard",
			"archived_debug": true,
		},
	]
	_expect(
		not _game_manager.is_nightmare_mode_unlocked(),
		"Debug Hard victory incorrectly unlocked Nightmare",
	)
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NIGHTMARE)
	_expect_equal(
		_game_manager.pending_difficulty,
		_game_manager.DIFFICULTY_NORMAL,
		"Locked Nightmare selection did not fail safely to Normal",
	)


func _check_nightmare_menu() -> void:
	_game_manager.character_history = [_normal_victory(), _hard_victory()]
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NIGHTMARE)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	var start_button: Button = menu.get_node("Center/VBox/StartButton")
	start_button.pressed.emit()
	await process_frame
	var modal_vbox: VBoxContainer = menu.get_node(
		"DifficultyModal/SafeMargin/Center/Panel/Margin/VBox"
	)
	var nightmare_button: Button = modal_vbox.get_node("NightmareButton")
	var status_label: Label = modal_vbox.get_node("StatusLabel")
	_expect(not nightmare_button.disabled, "Unlocked Nightmare option remained disabled")
	_expect_equal(
		nightmare_button.focus_mode,
		Control.FOCUS_ALL,
		"Unlocked Nightmare option was not keyboard/gamepad focusable",
	)
	_expect(
		nightmare_button.text.contains("Dungeon Hunts Back"),
		"Nightmare option did not communicate its encounter identity",
	)
	_expect(
		status_label.text.to_lower().contains("nightmare unlocked"),
		"Nightmare unlock status was not announced",
	)
	_expect_equal(
		root.gui_get_focus_owner(),
		nightmare_button,
		"Retained Nightmare selection was not focused",
	)
	menu.queue_free()
	await process_frame


func _check_nightmare_elite_chance(game: Node) -> void:
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	_expect_equal(game._elite_chance_for_floor(1), 22, "Nightmare floor 1 elite chance drifted")
	_expect_equal(game._elite_chance_for_floor(5), 24, "Nightmare floor 5 elite chance drifted")
	_expect_equal(game._elite_chance_for_floor(100), 38, "Nightmare elite chance cap drifted")
	var regular: Resource = _make_enemy_data("Nightmare Candidate")
	_expect(
		game._should_make_elite(regular, 1, true, 22),
		"Nightmare elites did not begin on floor 1",
	)
	_expect(
		not game._should_make_elite(regular, 1, true, 23),
		"Nightmare elite roll exceeded its floor band",
	)
	var forced_data: Resource = _make_enemy_data("Guaranteed Mutation")
	var forced_elite: Node = game._spawn_enemy_instance(
		forced_data, Vector2i(2, 1), 1, true, true, true
	)
	_expect(forced_elite.is_elite, "Guaranteed Nightmare encounter did not force one elite")
	_expect(
		str(forced_elite.elite_behavior).begins_with("nightmare_"),
		"Guaranteed Nightmare encounter used a Hard-mode elite identity",
	)
	_dispose_enemy(game, forced_elite)
	regular.is_boss = true
	_expect(not game._should_make_elite(regular, 30, true, 1), "Boss became a Nightmare elite")


func _check_nightmare_enemy_scaling(game: Node) -> void:
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	var template: Resource = _make_enemy_data("Nightmare Baseline")
	template.max_hp = 80
	template.armor_class = 10
	template.attack_bonus = 2
	template.damage_bonus = 3
	template.xp_reward = 100
	template.ranged_attack_range = 6
	template.ranged_attack_interval = 4
	template.ranged_damage_sides = 6
	template.ranged_damage_bonus = 2
	template.fireball_range = 5
	template.fireball_interval = 4
	template.fireball_damage_dice = 1
	template.fireball_damage_sides = 6
	template.fireball_damage_bonus = 1
	var enemy: Node = game._spawn_enemy_instance(template, Vector2i(2, 2), 11, true, false)
	_expect_equal(enemy.stats_component.max_hp, 117, "Nightmare ordinary HP scaling drifted")
	_expect_equal(
		enemy.stats_component.base_armor_class, 12, "Nightmare ordinary armor scaling drifted"
	)
	_expect_equal(
		enemy.stats_component.base_attack_bonus, 4, "Nightmare ordinary attack scaling drifted"
	)
	_expect_equal(
		enemy.stats_component.base_damage_bonus, 5, "Nightmare ordinary damage scaling drifted"
	)
	_expect_equal(enemy.stats_component.xp_reward, 130, "Nightmare ordinary XP baseline drifted")
	_expect_equal(
		enemy.enemy_data.ranged_damage_bonus, 4, "Nightmare ranged damage scaling drifted"
	)
	_expect_equal(enemy.enemy_data.fireball_damage_bonus, 3, "Nightmare spell scaling drifted")
	_expect_equal(
		enemy.stats_component.current_hp,
		enemy.stats_component.max_hp,
		"Nightmare spawn did not finish at full HP",
	)
	_dispose_enemy(game, enemy)


func _check_nightmare_elite_identities(game: Node) -> void:
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	var behaviors: Dictionary = {}
	var brood_data: Resource = _make_enemy_data("Hive Keeper")
	brood_data.summon_interval = 4
	brood_data.summon_count = 1
	brood_data.summon_max_active = 2
	var brood: Node = _enemy_with_data(brood_data)
	game._apply_elite_identity(brood, brood_data)
	behaviors[brood.elite_behavior] = true
	_expect_equal(brood.elite_behavior, &"nightmare_broodcaller", "Summoner elite identity drifted")
	_expect_equal(brood_data.summon_count, 2, "Broodcaller did not add a summon")
	_expect_equal(brood_data.summon_max_active, 4, "Broodcaller active summon cap drifted")

	var fire_data: Resource = _make_enemy_data("Flame Keeper")
	fire_data.fireball_range = 5
	fire_data.fireball_interval = 4
	fire_data.fireball_damage_dice = 1
	var cataclysm: Node = _enemy_with_data(fire_data)
	game._apply_elite_identity(cataclysm, fire_data)
	behaviors[cataclysm.elite_behavior] = true
	_expect_equal(cataclysm.elite_behavior, &"nightmare_cataclysm", "Caster elite identity drifted")
	_expect_equal(fire_data.fireball_damage_dice, 2, "Cataclysm spell dice did not increase")
	_expect_equal(fire_data.fireball_range, 6, "Cataclysm spell range did not increase")

	var ranged_data: Resource = _make_enemy_data("Longbow Keeper")
	ranged_data.ranged_attack_range = 7
	ranged_data.ranged_attack_interval = 4
	ranged_data.ranged_damage_bonus = 2
	var deadeye: Node = _enemy_with_data(ranged_data)
	game._apply_elite_identity(deadeye, ranged_data)
	behaviors[deadeye.elite_behavior] = true
	_expect_equal(deadeye.elite_behavior, &"nightmare_deadeye", "Ranged elite identity drifted")
	_expect_equal(ranged_data.ranged_attack_interval, 1, "Deadeye cadence did not accelerate")
	_expect_equal(ranged_data.ranged_damage_bonus, 4, "Deadeye damage did not increase")

	var melee_data: Resource = _make_enemy_data("Crypt Keeper")
	var revenant: Node = _enemy_with_data(melee_data)
	game._apply_elite_identity(revenant, melee_data)
	behaviors[revenant.elite_behavior] = true
	_expect_equal(revenant.elite_behavior, &"nightmare_revenant", "Melee elite identity drifted")
	_expect(melee_data.revive_chance_percent >= 25, "Revenant lost its one-life return")
	_expect(melee_data.poison_turns >= 3, "Revenant poison had no duration")
	_expect_equal(behaviors.size(), 4, "Nightmare elite families were not mechanically distinct")

	var presentation_state: RefCounted = MapPresentationStateScript.new()
	presentation_state.capture_actors([deadeye])
	_expect_equal(presentation_state.actors.size(), 1, "Nightmare elite snapshot was not captured")
	var deadeye_snapshot: Dictionary = presentation_state.actors[0]
	_expect_equal(
		deadeye_snapshot.get("elite_behavior"),
		&"nightmare_deadeye",
		"Nightmare elite identity was dropped before Pixel rendering",
	)
	var visual_catalog: RefCounted = ActorVisualCatalogScript.new()
	var nightmare_tint: Color = visual_catalog.tint_for(deadeye_snapshot)
	_expect(
		nightmare_tint.is_equal_approx(Color(0.86, 0.46, 1.0, 1.0)),
		"Nightmare elite visuals did not use the violet identity tint",
	)
	for elite: Node in [brood, cataclysm, deadeye, revenant]:
		elite.free()


func _check_nightmare_boss_escalation(game: Node) -> void:
	var boss_template: Resource = load(BOSS_PATHS[&"observer"])
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NORMAL
	var normal: Node = game._spawn_enemy_instance(boss_template, Vector2i(3, 3), 5, true, false)
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	var nightmare: Node = game._spawn_enemy_instance(boss_template, Vector2i(6, 3), 5, true, false)
	_expect_equal(
		nightmare.stats_component.max_hp,
		ceili(normal.stats_component.max_hp * game.NIGHTMARE_BOSS_HP_MULTIPLIER),
		"Nightmare boss HP multiplier drifted",
	)
	_expect_equal(
		nightmare.stats_component.base_armor_class,
		normal.stats_component.base_armor_class + 2,
		"Nightmare boss armor escalation drifted",
	)
	_expect_equal(
		nightmare.stats_component.base_attack_bonus,
		normal.stats_component.base_attack_bonus + 2,
		"Nightmare boss accuracy escalation drifted",
	)
	_expect_equal(
		game._scale_boss_special_damage(100, false),
		125,
		"Nightmare direct boss damage multiplier drifted",
	)
	_expect_equal(
		game._scale_boss_special_damage(100, true),
		120,
		"Nightmare boss hazard damage multiplier drifted",
	)
	var attack: Resource = BossAttackDataScript.new()
	attack.id = &"nightmare_cadence"
	attack.telegraph_turns = 3
	attack.cooldown = 4
	_expect_equal(
		game._boss_attack_effective_windup(attack), 1, "Nightmare telegraph did not tighten"
	)
	var production_escalations: int = 0
	for boss_path: String in BOSS_PATHS.values():
		var production_boss: Resource = load(boss_path)
		for production_attack: Resource in production_boss.boss_attacks:
			if production_attack.telegraph_turns < 3:
				continue
			_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NORMAL
			var normal_windup: int = game._boss_attack_effective_windup(production_attack)
			_game_manager.pending_difficulty = _game_manager.DIFFICULTY_HARD
			var hard_windup: int = game._boss_attack_effective_windup(production_attack)
			_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
			var nightmare_windup: int = game._boss_attack_effective_windup(production_attack)
			_expect_equal(
				[normal_windup, hard_windup, nightmare_windup],
				[3, 2, 1],
				"Production boss windup did not escalate across all three difficulties",
			)
			production_escalations += 1
	_expect(
		production_escalations >= BOSS_PATHS.size(),
		"Each Nightmare boss needs a production attack with an escalated windup",
	)
	var state: Dictionary = game._make_boss_state(nightmare)
	game._boss_states[nightmare] = state
	game._queue_boss_attack(nightmare, attack, {})
	state = game._boss_states[nightmare]
	var cooldowns: Dictionary = state.get("attack_cooldowns", {})
	_expect_equal(int(cooldowns.get(attack.id, 0)), 3, "Nightmare boss cooldown did not shorten")
	state = game._activate_hard_boss_shield(nightmare, state, &"magic", &"")
	_expect_equal(
		int(state.get("active_shield_turns", 0)),
		game.NIGHTMARE_ADAPTIVE_SHIELD_TURNS,
		"Nightmare adaptive shield duration drifted",
	)
	_dispose_enemy(game, normal)
	_dispose_enemy(game, nightmare)


func _check_nightmare_economy(game: Node) -> void:
	var item: PriceItem = PriceItem.new(19)
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NORMAL
	_expect_equal(_game_manager._get_shop_buy_price(item, 10), 19, "Normal buy baseline drifted")
	_expect_equal(_game_manager._get_shop_sell_price(item, 10), 6, "Normal sell baseline drifted")
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	_expect_equal(
		_game_manager._get_shop_buy_price(item, 10),
		24,
		"Nightmare shop markup did not apply after Normal pricing",
	)
	_expect_equal(
		_game_manager._get_shop_sell_price(item, 10),
		4,
		"Nightmare sell pressure drifted",
	)
	_game_manager.current_floor = 1
	game._shop_reroll_count = 0
	_expect_equal(game._get_shop_reroll_cost(), 45, "Nightmare reroll cost multiplier drifted")

	var reward_data: Resource = _make_enemy_data("Reward Foe")
	var reward_enemy: Node = game._spawn_enemy_instance(
		reward_data, Vector2i(8, 3), 1, false, false
	)
	seed(334455)
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NORMAL
	var normal_reward: int = game._roll_enemy_gold_reward(reward_enemy)
	seed(334455)
	_game_manager.pending_difficulty = _game_manager.DIFFICULTY_NIGHTMARE
	var nightmare_reward: int = game._roll_enemy_gold_reward(reward_enemy)
	_expect_equal(
		nightmare_reward,
		max(1, roundi(normal_reward * game.NIGHTMARE_ENEMY_GOLD_MULTIPLIER)),
		"Nightmare regular gold pressure drifted",
	)
	reward_enemy.is_elite = true
	seed(334455)
	var elite_reward: int = game._roll_enemy_gold_reward(reward_enemy)
	_expect_equal(
		elite_reward,
		max(
			1,
			roundi(
				(
					normal_reward
					* game.NIGHTMARE_ENEMY_GOLD_MULTIPLIER
					* game.NIGHTMARE_ELITE_GOLD_MULTIPLIER
				)
			)
		),
		"Nightmare elite bounty did not compensate its danger",
	)
	_dispose_enemy(game, reward_enemy)
	var items_before: int = int(_game_manager.run_stats.get("items_collected", 0))
	var inventory_before: int = game._player.inventory_component.items.size()
	game._open_chest_container({"rarity": 0, "display_name": "Telemetry Chest"})
	var inventory_added: int = game._player.inventory_component.items.size() - inventory_before
	_expect(inventory_added > 0, "Container telemetry fixture did not award an item")
	_expect_equal(
		int(_game_manager.run_stats.get("items_collected", 0)) - items_before,
		inventory_added,
		"Container reward items were omitted from run telemetry",
	)


func _check_shard_story(game: Node) -> void:
	for boss_id: StringName in BOSS_PATHS:
		var boss_data: Resource = load(BOSS_PATHS[boss_id])
		_expect(boss_data != null, "Shardbearer resource failed to load: %s" % boss_id)
		if boss_data == null:
			continue
		_expect(not boss_data.boss_lore.strip_edges().is_empty(), "%s has no boss lore" % boss_id)
		_expect(
			not boss_data.boss_shard_lore.strip_edges().is_empty(),
			"%s has no shard memory" % boss_id,
		)
	_game_manager.reset_run()
	_game_manager.record_enemy_defeated("The Observer", &"observer")
	await process_frame
	_expect_equal(_game_manager.get_collected_shard_count(), 1, "Boss kill did not bind a shard")
	_expect_equal(game.hud.shards_label.text, "Shards 1 / 5", "HUD did not expose shard progress")
	game._show_shard_claim(&"observer")
	await process_frame
	_expect(game.biome_overlay.visible, "Shard claim did not open its reward moment")
	_expect(
		game.biome_title_label.text.contains("FIRST SHARD CLAIMED"),
		"Shard claim title did not communicate portal progress",
	)
	game._hide_biome_overlay()


func _check_prologue() -> void:
	var prologue: Control = load("res://scenes/prologue.tscn").instantiate()
	root.add_child(prologue)
	await process_frame
	var prologue_script: GDScript = prologue.get_script()
	var pages: Array = prologue_script.get_script_constant_map().get("PAGE_DATA", [])
	_expect_equal(pages.size(), 4, "Prologue did not pace its four-part objective")
	var title_label: Label = prologue.get_node(
		"SafeMargin/Center/Panel/PanelMargin/VBox/Content/Title"
	)
	var body_label: Label = prologue.get_node(
		"SafeMargin/Center/Panel/PanelMargin/VBox/Content/Body"
	)
	_expect(title_label.text.contains("DUNGEON"), "Prologue opening did not establish the breach")
	prologue.call(&"_show_page", 1)
	_expect(title_label.text.contains("FIVE WARDENS"), "Prologue did not name the five guardians")
	_expect(body_label.text.contains("Observer"), "Prologue omitted Shardbearer identities")
	prologue.call(&"_show_page", 2)
	_expect(body_label.text.contains("all five"), "Prologue did not explain portal progression")
	prologue.call(&"_show_page", 3)
	var next_button: Button = prologue.get_node(
		"SafeMargin/Center/Panel/PanelMargin/VBox/Actions/ContinueButton"
	)
	_expect_equal(next_button.text, "BEGIN DESCENT", "Prologue finale call-to-action drifted")
	prologue.queue_free()
	await process_frame


func _make_enemy_data(display_name: String) -> Resource:
	var data: Resource = EnemyDataScript.new()
	data.display_name = display_name
	data.max_hp = 10
	data.armor_class = 10
	data.attack_bonus = 2
	data.damage_sides = 4
	data.damage_bonus = 1
	data.xp_reward = 20
	return data


func _enemy_with_data(data: Resource) -> Node:
	var enemy: Node = EnemyScript.new()
	enemy.enemy_data = data
	return enemy


func _dispose_enemy(game: Node, enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	game._enemies.erase(enemy)
	_game_manager.remove_enemy(enemy)
	game._boss_states.erase(enemy)
	enemy.free()


func _normal_victory() -> Dictionary:
	return {
		"name": "Normal Victor",
		"victory": true,
		"difficulty": "normal",
		"class": "fighter",
		"floor": 25,
	}


func _hard_victory() -> Dictionary:
	return {
		"name": "Hard Victor",
		"victory": true,
		"difficulty": "hard",
		"class": "ranger",
		"floor": 25,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_fail("%s: got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_failed = true
	push_error(message)
