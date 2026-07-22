## V32 run telemetry, deterministic scoring, archive persistence, and results UI contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v32_run_finale.gd
extends SceneTree


class FakeStats:
	extends RefCounted

	var level: int = 1
	var max_hp: int = 10
	var current_hp: int = 10
	var gold: int = 0
	var xp: int = 0


class FakeItem:
	extends RefCounted

	var display_name: String = ""


class FakeInventory:
	extends RefCounted

	var items: Array = []
	var equipped_melee_weapon: Variant
	var equipped_ranged_weapon: Variant
	var equipped_armor: Variant
	var equipped_accessory_1: Variant
	var equipped_accessory_2: Variant


class FakePlayer:
	extends Node2D

	var display_name: String = ""
	var stats_component: FakeStats
	var inventory_component: FakeInventory


var _failed: bool = false
var _game_manager: Node
var _original_history: Array = []
var _original_summary: Dictionary = {}
var _original_pending_difficulty: StringName
var _history_existed: bool = false
var _history_bytes: PackedByteArray = PackedByteArray()


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_game_manager = root.get_node_or_null("/root/GameManager")
	_expect(_game_manager != null, "GameManager autoload is missing")
	if _game_manager == null:
		quit(1)
		return
	_backup_state()
	_check_score_formula()
	_check_run_summary_and_archive()
	_check_debug_run_filter()
	await _check_results_scenes()
	_restore_state()
	if _failed:
		quit(1)
		return
	print("V32 run telemetry, score, archive, and results contracts passed")
	quit(0)


func _backup_state() -> void:
	_original_history = _game_manager.character_history.duplicate(true)
	_original_summary = _game_manager.last_run_summary.duplicate(true)
	_original_pending_difficulty = _game_manager.pending_difficulty
	_history_existed = FileAccess.file_exists(_game_manager.HISTORY_PATH)
	if _history_existed:
		_history_bytes = FileAccess.get_file_as_bytes(_game_manager.HISTORY_PATH)


func _restore_state() -> void:
	_game_manager.abandon_run()
	_game_manager.character_history = _original_history.duplicate(true)
	_game_manager.last_run_summary = _original_summary.duplicate(true)
	_game_manager.pending_difficulty = _original_pending_difficulty
	if _history_existed:
		var file: FileAccess = FileAccess.open(_game_manager.HISTORY_PATH, FileAccess.WRITE)
		if file == null:
			_fail("Could not restore character history after V32 run test")
		else:
			file.store_buffer(_history_bytes)
	elif FileAccess.file_exists(_game_manager.HISTORY_PATH):
		var absolute_path: String = ProjectSettings.globalize_path(_game_manager.HISTORY_PATH)
		if DirAccess.remove_absolute(absolute_path) != OK:
			_fail("Could not remove V32 run-test history fixture")


func _check_score_formula() -> void:
	var metrics: Dictionary = {
		"floor": 30,
		"turns": 700,
		"enemy_kills": 80,
		"elite_kills": 9,
		"boss_kills":
		[
			{"id": "observer"},
			{"id": "seraphine"},
			{"id": "vorrak"},
			{"id": "kaelros"},
			{"id": "nyxara"},
		],
		"final_gold": 600,
		"victory": true,
	}
	var normal: Dictionary = _game_manager.calculate_run_score(
		metrics, _game_manager.DIFFICULTY_NORMAL
	)
	var hard: Dictionary = _game_manager.calculate_run_score(metrics, _game_manager.DIFFICULTY_HARD)
	var nightmare: Dictionary = _game_manager.calculate_run_score(
		metrics, _game_manager.DIFFICULTY_NIGHTMARE
	)
	_expect_score_sums(normal, "Normal")
	_expect_score_sums(hard, "Hard")
	_expect_score_sums(nightmare, "Nightmare")
	_expect(
		int(normal.get("victory", 0)) == _game_manager.SCORE_VICTORY_BONUS,
		"Victory score bonus drifted",
	)
	_expect(
		int(normal.get("endless", 0)) == 5 * _game_manager.SCORE_ENDLESS_FLOOR_BONUS,
		"Endless floor score did not begin after floor 25",
	)
	_expect(
		int(hard.get("total", 0)) > int(normal.get("total", 0)),
		"Hard score multiplier did not reward added risk",
	)
	_expect(
		int(nightmare.get("total", 0)) > int(hard.get("total", 0)),
		"Nightmare score multiplier did not exceed Hard",
	)
	var defeat_metrics: Dictionary = metrics.duplicate(true)
	defeat_metrics["victory"] = false
	var defeat: Dictionary = _game_manager.calculate_run_score(
		defeat_metrics, _game_manager.DIFFICULTY_NORMAL
	)
	_expect_equal(int(defeat.get("victory", -1)), 0, "Defeat received a victory bonus")
	_expect(
		int(defeat.get("total", 0)) < int(normal.get("total", 0)),
		"Victory did not outscore the same defeated run",
	)


func _expect_score_sums(score: Dictionary, label: String) -> void:
	var subtotal: int = 0
	for key: StringName in [
		&"progress", &"bosses", &"combat", &"wealth", &"pace", &"victory", &"endless"
	]:
		subtotal += int(score.get(key, 0))
	_expect_equal(int(score.get("subtotal", -1)), subtotal, "%s score subtotal drifted" % label)
	var expected_total: int = roundi(subtotal * int(score.get("multiplier_percent", 0)) / 100.0)
	_expect_equal(int(score.get("total", -1)), expected_total, "%s score total drifted" % label)


func _check_run_summary_and_archive() -> void:
	_game_manager.character_history = []
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NORMAL)
	_game_manager.reset_run()
	_game_manager.prepare_character("Telemetry Hero", {}, _game_manager.CLASS_RANGER)
	var player: Node2D = _make_player()
	_game_manager.player = player
	_game_manager.start_floor(12)
	for _turn_index: int in range(5):
		_game_manager.advance_turn()
	_game_manager.record_player_action("Longsword", &"melee", &"weapon")
	_game_manager.record_damage_dealt(17, "Longsword", &"melee", &"weapon")
	_game_manager.record_player_action("Longsword", &"melee", &"weapon")
	_game_manager.record_damage_dealt(13, "Longsword", &"melee", &"weapon")
	_game_manager.record_player_action("Arcane Spark", &"magic", &"ability")
	_game_manager.record_damage_dealt(50, "Arcane Spark", &"magic", &"ability")
	_game_manager.record_damage_taken(11, "Ash Breath", &"fire")
	_game_manager.record_damage_taken(16, "Ash Breath", &"fire")
	_game_manager.record_enemy_defeated("Goblin")
	_game_manager.record_enemy_defeated("Elite Skeleton", &"", true)
	_game_manager.record_enemy_defeated("Brittle Skeleton", &"", false, true)
	_game_manager.record_enemy_defeated("The Observer", &"observer")
	_game_manager.record_item_collected()
	_game_manager.record_item_collected()
	_game_manager.record_container_opened()
	_game_manager.end_run(false)
	var summary: Dictionary = _game_manager.last_run_summary
	_expect_equal(summary.get("name"), "Telemetry Hero", "Run summary omitted character name")
	_expect_equal(int(summary.get("floor", 0)), 12, "Run summary omitted deepest floor")
	_expect_equal(int(summary.get("turns", 0)), 5, "Run summary turn total drifted")
	_expect_equal(int(summary.get("enemy_kills", 0)), 3, "Summoned minion polluted kill total")
	_expect_equal(int(summary.get("elite_kills", 0)), 1, "Elite kill total drifted")
	_expect_equal(int(summary.get("shards_collected", 0)), 1, "Boss shard was not tracked")
	var boss_kills: Array = summary.get("boss_kills", [])
	_expect_equal(boss_kills.size(), 1, "Boss kill identity was not retained")
	if not boss_kills.is_empty():
		_expect_equal((boss_kills[0] as Dictionary).get("id"), "observer", "Boss kill ID drifted")
	_expect_equal(int(summary.get("damage_dealt", 0)), 80, "Damage-dealt total drifted")
	_expect_equal(int(summary.get("damage_taken", 0)), 27, "Damage-taken total drifted")
	_expect_equal(summary.get("defeated_by"), "Ash Breath", "Killer source was not retained")
	_expect_equal(summary.get("defeated_by_channel"), "fire", "Killer damage channel drifted")
	var incoming_sources: Dictionary = summary.get("incoming_sources", {})
	_expect_equal(
		int(incoming_sources.get("Ash Breath", 0)),
		27,
		"Incoming damage-source aggregation was not retained",
	)
	var top_source: Dictionary = summary.get("most_damage_attack", {})
	_expect_equal(top_source.get("name"), "Arcane Spark", "Top damage source ranking drifted")
	_expect_equal(int(top_source.get("damage", 0)), 50, "Top damage source total drifted")
	var loadout: Dictionary = summary.get("loadout", {})
	_expect_equal(loadout.get("melee"), "Longsword", "Equipped melee weapon was not captured")
	_expect_equal(loadout.get("ranged"), "Hunting Bow", "Equipped ranged weapon was not captured")
	_expect_equal(loadout.get("armor"), "Leather Armor", "Equipped armor was not captured")
	_expect_equal(int(summary.get("final_gold", 0)), 321, "Final gold was not captured")
	_expect(int(summary.get("score", 0)) > 0, "Run summary did not calculate a score")
	_expect_equal(_game_manager.character_history.size(), 1, "Real run was not archived")
	var archive_entry: Dictionary = _game_manager.character_history[0]
	_expect_equal(archive_entry.get("score"), summary.get("score"), "Archive score drifted")
	_expect_equal(
		_game_manager.get_high_score(_game_manager.DIFFICULTY_NORMAL),
		summary.get("score"),
		"Difficulty high score did not persist",
	)
	player.free()


func _make_player() -> Node2D:
	var player: FakePlayer = FakePlayer.new()
	player.display_name = "Telemetry Hero"
	var stats: FakeStats = FakeStats.new()
	stats.level = 8
	stats.max_hp = 52
	stats.current_hp = 0
	stats.gold = 321
	stats.xp = 1440
	player.stats_component = stats
	var inventory: FakeInventory = FakeInventory.new()
	var sword: FakeItem = _make_item("Longsword")
	var bow: FakeItem = _make_item("Hunting Bow")
	var armor: FakeItem = _make_item("Leather Armor")
	var charm: FakeItem = _make_item("Ember Charm")
	inventory.items = [sword, bow, armor, charm]
	inventory.equipped_melee_weapon = sword
	inventory.equipped_ranged_weapon = bow
	inventory.equipped_armor = armor
	inventory.equipped_accessory_1 = charm
	player.inventory_component = inventory
	return player


func _make_item(display_name: String) -> FakeItem:
	var item: FakeItem = FakeItem.new()
	item.display_name = display_name
	return item


func _check_debug_run_filter() -> void:
	var archive_size: int = _game_manager.character_history.size()
	var ranked_high_score: int = _game_manager.get_high_score(_game_manager.DIFFICULTY_NORMAL)
	_game_manager.set_pending_difficulty(_game_manager.DIFFICULTY_NORMAL)
	_game_manager.reset_run()
	_game_manager.prepare_character("debug", {}, _game_manager.CLASS_FIGHTER)
	_game_manager.start_floor(25)
	_game_manager.end_run(true)
	_expect_equal(
		_game_manager.character_history.size(),
		archive_size,
		"Debug run polluted the persistent archive",
	)
	_expect(
		bool(_game_manager.last_run_summary.get("archived_debug", false)),
		"Debug result summary did not identify its non-archived status",
	)
	_expect_equal(
		int(_game_manager.last_run_summary.get("high_score", -1)),
		ranked_high_score,
		"Debug score was mislabeled as the ranked high score",
	)
	_expect_equal(
		_game_manager.get_high_score(_game_manager.DIFFICULTY_NORMAL),
		ranked_high_score,
		"Debug score changed the persisted ranked high score",
	)


func _check_results_scenes() -> void:
	var summary: Dictionary = {
		"name": "Finale Hero",
		"class": "wizard",
		"difficulty": "nightmare",
		"victory": true,
		"floor": 31,
		"level": 20,
		"turns": 812,
		"final_hp": 4,
		"max_hp": 70,
		"final_gold": 999,
		"final_xp": 4400,
		"enemy_kills": 102,
		"elite_kills": 16,
		"boss_kills":
		[
			{"id": "observer", "name": "The Observer", "floor": 5},
			{"id": "seraphine", "name": "Seraphine, the Thorn Saint", "floor": 10},
			{"id": "vorrak", "name": "Vorrak, the Ashen Maw", "floor": 15},
			{"id": "kaelros", "name": "Kaelros, the Drowned King", "floor": 20},
			{"id": "nyxara", "name": "Nyxara, the Mirror Witch", "floor": 25},
		],
		"shards_collected": 5,
		"damage_dealt": 1800,
		"damage_taken": 410,
		"biggest_hit": 74,
		"damage_by_channel": {"melee": 520, "magic": 1280},
		"incoming_sources": {"Drowned Knight": 221, "Ash Breath": 189},
		"items_collected": 28,
		"containers_opened": 19,
		"defeated_by": "",
		"defeated_by_channel": "",
		"most_damage_attack": {"name": "Arcane Spark", "damage": 710, "uses": 22},
		"damage_sources":
		{
			"ability|magic|Arcane Spark":
			{
				"name": "Arcane Spark",
				"channel": &"magic",
				"category": &"ability",
				"damage": 710,
				"uses": 22
			},
			"weapon|melee|Longsword":
			{
				"name": "Longsword",
				"channel": &"melee",
				"category": &"weapon",
				"damage": 520,
				"uses": 31
			},
		},
		"loadout": {"melee": "Longsword", "ranged": "Hunting Bow", "armor": "Plate Armor"},
		"inventory": ["Longsword", "Hunting Bow", "Plate Armor", "Mirror Key"],
		"score": 54321,
		"score_breakdown":
		{
			"bosses": 12500,
			"progress": 31000,
			"combat": 14940,
			"wealth": 3838,
			"pace": 224,
			"victory": 12000,
			"endless": 2700,
			"subtotal": 56282,
			"multiplier_percent": 135,
			"total": 75981,
		},
		"previous_high_score": 50000,
		"high_score": 54321,
		"is_new_high_score": true,
	}
	_game_manager.last_run_summary = summary
	for scene_path: String in ["res://scenes/game_over.tscn", "res://scenes/victory.tscn"]:
		var packed: PackedScene = load(scene_path)
		_expect(packed != null, "Results scene failed to load: %s" % scene_path)
		if packed == null:
			continue
		var screen: Control = packed.instantiate() as Control
		root.add_child(screen)
		await process_frame
		var root_vbox: VBoxContainer = screen.get_node(
			"SafeMargin/Center/ResultsPanel/PanelMargin/RootVBox"
		)
		var score_label: Label = root_vbox.get_node(
			"HeaderGrid/ScorePanel/ScoreMargin/ScoreVBox/ScoreLabel"
		)
		_expect(score_label.text.contains("54,321"), "Results screen omitted formatted score")
		var results_scroll: ScrollContainer = root_vbox.get_node("ResultsScroll")
		var retry_button: Button = root_vbox.get_node("ActionGrid/RetryButton")
		_expect_equal(
			results_scroll.focus_mode,
			Control.FOCUS_ALL,
			"Results scroller is not keyboard focusable",
		)
		_expect_equal(
			results_scroll.focus_next,
			results_scroll.get_path_to(retry_button),
			"Results scroller does not return focus to actions",
		)
		var results_content: VBoxContainer = root_vbox.get_node("ResultsScroll/ResultsContent")
		var boss_grid: GridContainer = results_content.get_node(
			"BossProgressPanel/BossMargin/BossVBox/BossGrid"
		)
		_expect_equal(
			boss_grid.get_child_count(), 5, "Results screen did not build five boss cards"
		)
		var fate_text: RichTextLabel = results_content.get_node(
			"DetailGrid/FatePanel/CardMargin/CardVBox/Text"
		)
		_expect(fate_text.text.contains("SURVIVED"), "Victory results did not render final fate")
		var damage_text: RichTextLabel = results_content.get_node(
			"DetailGrid/DamagePanel/CardMargin/CardVBox/Text"
		)
		_expect(damage_text.text.contains("Arcane Spark"), "Results screen omitted damage source")
		_expect(
			damage_text.text.contains("Drowned Knight"),
			"Results screen omitted top incoming threat",
		)
		screen.queue_free()
		await process_frame
	var compact_viewport: SubViewport = SubViewport.new()
	compact_viewport.size = Vector2i(640, 400)
	root.add_child(compact_viewport)
	var compact_screen: Control = load("res://scenes/victory.tscn").instantiate()
	compact_viewport.add_child(compact_screen)
	for _frame: int in range(3):
		await process_frame
	var compact_panel: PanelContainer = compact_screen.get_node("SafeMargin/Center/ResultsPanel")
	var compact_scroll: ScrollContainer = compact_panel.get_node(
		"PanelMargin/RootVBox/ResultsScroll"
	)
	var compact_actions: GridContainer = compact_panel.get_node("PanelMargin/RootVBox/ActionGrid")
	_expect(
		compact_panel.size.y <= compact_viewport.size.y,
		(
			"Compact results panel exceeded viewport: %.1f > %d"
			% [compact_panel.size.y, compact_viewport.size.y]
		),
	)
	_expect_equal(
		compact_scroll.custom_minimum_size.y,
		0.0,
		"Compact results scroller retained its desktop minimum height",
	)
	_expect(
		compact_actions.get_global_rect().end.y <= compact_viewport.size.y,
		(
			"Compact results actions clipped at %.1f > %d"
			% [compact_actions.get_global_rect().end.y, compact_viewport.size.y]
		),
	)
	compact_viewport.queue_free()
	await process_frame


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
