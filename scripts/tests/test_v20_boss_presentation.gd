## V20.0.0 boss presentation and music contracts.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_presentation.gd
extends SceneTree

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const MapViewScript = preload("res://scripts/ui/map_view.gd")
const SensoryScript = preload("res://scripts/ui/sensory_feedback.gd")

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_map_view_boss_visuals()
	if not _failed:
		await _check_hud()
	if not _failed:
		await _check_music()
	if not _failed:
		_check_boss_cues()
	if not _failed:
		print("V20 boss presentation checks passed")
		quit(0)


func _check_map_view_boss_visuals() -> void:
	var map_view: Node = MapViewScript.new()
	root.add_child(map_view)
	map_view.set_atmosphere_enabled(false)
	map_view.configure_map([[DungeonDataScript.TileType.FLOOR, DungeonDataScript.TileType.FLOOR]])
	map_view.set_visibility(
		{Vector2i(0, 0): true, Vector2i(1, 0): true}, {Vector2i(0, 0): true, Vector2i(1, 0): true}
	)
	map_view.set_targeting(true, Vector2i(0, 0), {Vector2i(0, 0): true}, {})
	(
		map_view
		. set_boss_visuals(
			{
				Vector2i(0, 0):
				{
					"frames": [PackedStringArray(["AB"])],
					"frame_seconds": 0.1,
					"color": Color.WHITE,
					"occupied_cells": [Vector2i(0, 0), Vector2i(1, 0)],
					"phase": 1,
				}
			}
		)
	)
	_assert(
		map_view.has_active_boss_visuals() and map_view.is_processing(),
		"boss visuals should start processing"
	)
	_assert(
		map_view._actor_at(Vector2i(1, 0)) != null,
		"boss occupied cells should block item/container/trap drawing"
	)
	map_view.set_boss_telegraphs({Vector2i(1, 0): {"glyph": "!"}})
	_assert(map_view._targeting_active, "boss telegraphs should not clear targeting state")
	map_view._process(0.2)
	_assert(map_view._boss_frame_index > 0, "boss visual frame should advance")
	map_view.set_targeting(false, Vector2i.ZERO, {}, {})
	map_view.clear_boss_visuals()
	_assert(
		not map_view.has_active_boss_visuals() and not map_view.is_processing(),
		"clearing boss visuals should stop boss-only processing"
	)
	# Boss spawn intro lifecycle
	(
		map_view
		. play_boss_spawn_intro(
			Vector2i(0, 0),
			{
				"display_name": "Test Boss",
				"color": Color.WHITE,
				"occupied_cells": [Vector2i(0, 0), Vector2i(1, 0)],
			}
		)
	)
	_assert(map_view.is_processing(), "boss spawn intro should start processing")
	map_view._process(0.95)
	_assert(
		not map_view.is_processing(),
		"boss spawn intro should clear after duration and stop processing"
	)
	map_view.queue_free()


func _check_hud() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return
	gm.prepare_character("debug", {}, gm.CLASS_FIGHTER)
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game.hud.show_boss_health("The Observer", 36, 72)
	_assert(game.hud.boss_banner.visible, "boss banner should be visible")
	_assert(
		game.hud.boss_banner_hp_label.text == "[██████████████░░░░░░░░░░░░░░] 36 / 72",
		"boss banner HP label text was %s" % game.hud.boss_banner_hp_label.text
	)
	# Sidebar labels remain hidden
	_assert(not game.hud.boss_hp_label.visible, "sidebar boss HP should stay hidden")
	_assert(not game.hud.boss_name_label.visible, "sidebar boss name should stay hidden")
	_assert(not game.hud.sep_boss_label.visible, "sidebar boss separator should stay hidden")
	game.hud.hide_boss_health()
	_assert(not game.hud.boss_banner.visible, "boss banner should hide")


func _check_music() -> void:
	var sensory: Node = SensoryScript.new()
	root.add_child(sensory)
	await process_frame
	var stream: AudioStream = load("res://assets/audio/boss/8bit_action_boss_battle_bpm145.ogg")
	if stream == null:
		_fail("boss OGG stream failed to load")
	else:
		sensory.start_boss_music(&"observer", stream, null)
		_assert(sensory.is_boss_music_playing(), "boss music should play")
		_assert(sensory.get_boss_music_stream() != null, "boss music stream should be assigned")
		sensory.set_audio_enabled(false)
		_assert(
			not sensory.is_boss_music_playing(), "boss music should stop when audio is disabled"
		)
		sensory.stop_boss_music()


func _check_boss_cues() -> void:
	# Boss cue StringName constants exist and match expected values
	_assert(SensoryScript.CUE_BOSS_GATE == &"boss_gate", "CUE_BOSS_GATE missing")
	_assert(SensoryScript.CUE_BOSS_SPAWN == &"boss_spawn", "CUE_BOSS_SPAWN missing")
	_assert(SensoryScript.CUE_BOSS_TELEGRAPH == &"boss_telegraph", "CUE_BOSS_TELEGRAPH missing")
	_assert(SensoryScript.CUE_BOSS_PHASE == &"boss_phase", "CUE_BOSS_PHASE missing")
	_assert(SensoryScript.CUE_BOSS_DEFEAT == &"boss_defeat", "CUE_BOSS_DEFEAT missing")
	# Boss cues are registered in ALL_CUES
	var all_cues: Array = SensoryScript.ALL_CUES
	_assert(all_cues.has(&"boss_gate"), "boss_gate not in ALL_CUES")
	_assert(all_cues.has(&"boss_spawn"), "boss_spawn not in ALL_CUES")
	_assert(all_cues.has(&"boss_telegraph"), "boss_telegraph not in ALL_CUES")
	_assert(all_cues.has(&"boss_phase"), "boss_phase not in ALL_CUES")
	_assert(all_cues.has(&"boss_defeat"), "boss_defeat not in ALL_CUES")
	# Message-type→cue mapping includes boss entries
	var msg_map: Dictionary = SensoryScript.MESSAGE_TYPE_CUE_MAP
	_assert(msg_map.has(&"boss_gate"), "boss_gate message type not in cue map")
	_assert(msg_map.has(&"boss_story"), "boss_story message type not in cue map")
	_assert(msg_map.has(&"boss_telegraph"), "boss_telegraph message type not in cue map")
	_assert(msg_map.has(&"boss_phase"), "boss_phase message type not in cue map")
	_assert(msg_map.has(&"boss_defeat"), "boss_defeat message type not in cue map")


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
