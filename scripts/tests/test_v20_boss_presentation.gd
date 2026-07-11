## V20.0.0 boss presentation and music contracts.
## Updated V20.1.0: hazards, StatusLabel, boss-specific cues, version history.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##   res://scripts/tests/test_v20_boss_presentation.gd
extends SceneTree

const DungeonDataScript = preload("res://scripts/dungeon/dungeon_data.gd")
const MapViewScript = preload("res://scripts/ui/map_view.gd")
const SensoryScript = preload("res://scripts/ui/sensory_feedback.gd")
const VersionHistoryScript = preload("res://scripts/version_history.gd")

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
		_check_sensory_boss_cues()
	if not _failed:
		_check_version_history()
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
	var projectile_cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
	map_view.play_projectile_trail(
		projectile_cells, {"profile_id": &"arrow", "duration_seconds": 0.2}
	)
	_assert(
		map_view.has_active_projectile_trails(), "projectile trail should coexist with telegraphs"
	)
	_assert(map_view._targeting_active, "projectile playback should not clear targeting state")
	_assert(
		not map_view._boss_telegraphs.is_empty(), "projectile playback should not clear telegraphs"
	)
	## Hazards: deep-duplicate on set, do not affect _actor_at, preserve existing state
	var hazard_payload: Dictionary = {
		Vector2i(1, 0):
		{
			"glyph": "≈",
			"color": Color.CYAN,
			"fill_color": Color(0, 0.3, 1, 0.2),
			"border_color": Color.CYAN,
		}
	}
	map_view.set_boss_hazards(hazard_payload)
	# Mutate original to prove deep copy
	hazard_payload[Vector2i(1, 0)]["glyph"] = "MUTATED"
	_assert(
		map_view._boss_hazards.get(Vector2i(1, 0), {}).get("glyph", "") == "≈",
		"set_boss_hazards should store a deep-duplicated payload"
	)
	_assert(
		map_view._actor_at(Vector2i(1, 0)) != null,
		"boss occupied cells should still block after hazards are set"
	)
	_assert(map_view._targeting_active, "hazards should not clear targeting state")
	_assert(not map_view._boss_telegraphs.is_empty(), "hazards should not clear boss telegraphs")
	_assert(
		map_view._boss_telegraphs.get(Vector2i(1, 0), {}).get("glyph", "") == "!",
		"hazards should not modify telegraph payload keys"
	)
	_assert(map_view.has_active_boss_visuals(), "hazards should not clear boss visuals")
	map_view._process(0.2)
	_assert(map_view._boss_frame_index > 0, "boss visual frame should advance")
	map_view.clear_projectile_trails()
	map_view.set_targeting(false, Vector2i.ZERO, {}, {})
	map_view.clear_boss_visuals()
	_assert(
		not map_view.has_active_boss_visuals() and not map_view.is_processing(),
		"clearing boss visuals should stop boss-only processing"
	)
	## Boss spawn intro lifecycle
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
	_assert(
		game.hud.boss_banner_status_label != null, "boss_banner_status_label should be non-null"
	)
	game.hud.set_boss_goal_state("The Observer", true, true, false, &"arena_reveal")
	_assert(
		game.hud.help_label.text.begins_with("Goal: prepare for The Observer"),
		"arena reveal should use prepare goal copy"
	)
	game.hud.hide_boss_health()
	_assert(
		game.hud.help_label.text.begins_with("Goal: prepare for The Observer"),
		"hiding boss HP should preserve arena lifecycle goal state"
	)
	game.hud.set_boss_goal_state("The Observer", true, true, false, &"active")
	_assert(
		game.hud.help_label.text.begins_with("Goal: defeat The Observer"),
		"active boss should use defeat goal copy"
	)
	game.hud.show_boss_health("The Observer", 36, 72)
	_assert(not game.hud.boss_banner.visible, "boss banner should remain hidden")
	_assert(game.hud.sep_boss_label.visible, "sidebar boss separator should be visible")
	_assert(game.hud.boss_name_label.visible, "sidebar boss name should be visible")
	_assert(game.hud.boss_hp_label.visible, "sidebar boss HP should be visible")
	_assert(
		game.hud.boss_name_label.text == "THE OBSERVER\nP1",
		"boss name label text was %s" % game.hud.boss_name_label.text
	)
	_assert(
		game.hud.boss_hp_label.text == "[██████░░░░░░] 36 / 72",
		"sidebar boss HP label text was %s" % game.hud.boss_hp_label.text
	)
	_assert(game.hud.boss_banner_hp_label.text == "", "boss banner HP should stay empty")
	_assert(game.hud.boss_banner_status_label.text == "", "boss banner status should stay empty")
	game.hud.update_boss_health(18, 72)
	_assert(
		game.hud.boss_hp_label.text == "[███░░░░░░░░░] 18 / 72",
		"sidebar boss HP update text was %s" % game.hud.boss_hp_label.text
	)
	game.hud.hide_boss_health()
	_assert(not game.hud.boss_banner.visible, "boss banner should hide")
	_assert(not game.hud.sep_boss_label.visible, "sidebar boss separator should hide")
	_assert(not game.hud.boss_name_label.visible, "sidebar boss name should hide")
	_assert(not game.hud.boss_hp_label.visible, "sidebar boss HP should hide")
	## Extended signature: phase, room_title, windup_label
	game.hud.show_boss_health(
		"The Observer", 36, 72, Color(1.0, 0.72, 0.28), 2, "The Unblinking Gate", "blink_pulse"
	)
	_assert(
		game.hud.boss_name_label.text.contains("P2"),
		"boss name label should contain P2, got %s" % game.hud.boss_name_label.text
	)
	_assert(
		game.hud.boss_name_label.text.contains("THE UNBLINKING GATE"),
		"boss name label should contain room title, got %s" % game.hud.boss_name_label.text
	)
	_assert(
		game.hud.boss_name_label.text.contains("WINDUP: BLINK_PULSE"),
		"boss name label should contain windup, got %s" % game.hud.boss_name_label.text
	)
	game.hud.hide_boss_health()
	_assert(game.hud.boss_name_label.text == "", "boss name label should be empty after hide")
	_assert(game.hud.boss_hp_label.text == "", "boss HP label should be empty after hide")
	_assert(
		game.hud.boss_name_label.scale == Vector2.ONE,
		"boss name label scale should be Vector2.ONE after hide"
	)
	_assert(
		game.hud.boss_name_label.modulate == Color.WHITE,
		"boss name label modulate should be WHITE after hide"
	)
	_assert(
		game.hud.boss_hp_label.scale == Vector2.ONE,
		"boss HP label scale should be Vector2.ONE after hide"
	)
	_assert(
		game.hud.boss_hp_label.modulate == Color.WHITE,
		"boss HP label modulate should be WHITE after hide"
	)
	_assert(
		game.hud.boss_banner_status_label.text == "",
		(
			"banner status label should be empty after hide, got %s"
			% game.hud.boss_banner_status_label.text
		)
	)
	_assert(
		game.hud.boss_banner_status_label.scale == Vector2.ONE,
		"status label scale should be Vector2.ONE after hide"
	)
	_assert(
		game.hud.boss_banner_status_label.modulate == Color.WHITE,
		"status label modulate should be WHITE after hide"
	)
	_assert(game.hud._last_boss_phase == -1, "_last_boss_phase should be -1 after hide")


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
	## Boss cue StringName constants exist and match expected values
	_assert(SensoryScript.CUE_BOSS_GATE == &"boss_gate", "CUE_BOSS_GATE missing")
	_assert(SensoryScript.CUE_BOSS_SPAWN == &"boss_spawn", "CUE_BOSS_SPAWN missing")
	_assert(SensoryScript.CUE_BOSS_TELEGRAPH == &"boss_telegraph", "CUE_BOSS_TELEGRAPH missing")
	_assert(SensoryScript.CUE_BOSS_PHASE == &"boss_phase", "CUE_BOSS_PHASE missing")
	_assert(SensoryScript.CUE_BOSS_DEFEAT == &"boss_defeat", "CUE_BOSS_DEFEAT missing")
	## Boss cues are registered in ALL_CUES
	var all_cues: Array = SensoryScript.ALL_CUES
	_assert(all_cues.has(&"boss_gate"), "boss_gate not in ALL_CUES")
	_assert(all_cues.has(&"boss_spawn"), "boss_spawn not in ALL_CUES")
	_assert(all_cues.has(&"boss_telegraph"), "boss_telegraph not in ALL_CUES")
	_assert(all_cues.has(&"boss_phase"), "boss_phase not in ALL_CUES")
	_assert(all_cues.has(&"boss_defeat"), "boss_defeat not in ALL_CUES")
	## Message-type→cue mapping includes boss entries
	var msg_map: Dictionary = SensoryScript.MESSAGE_TYPE_CUE_MAP
	_assert(msg_map.has(&"boss_gate"), "boss_gate message type not in cue map")
	_assert(msg_map.has(&"boss_story"), "boss_story message type not in cue map")
	_assert(msg_map.has(&"boss_telegraph"), "boss_telegraph message type not in cue map")
	_assert(msg_map.has(&"boss_phase"), "boss_phase message type not in cue map")
	_assert(msg_map.has(&"boss_defeat"), "boss_defeat message type not in cue map")


func _check_sensory_boss_cues() -> void:
	var sf: Node = SensoryScript.new()
	root.add_child(sf)
	sf.set_reduced_vfx_enabled(false, false)
	## Observer and Vorrak boss intro cues should use boss-specific colors
	sf.play_boss_intro_cue(&"observer")
	var obs_color: Color = sf._visual_color
	_assert(sf._visual_active, "observer cue should activate visual feedback")
	sf.play_boss_intro_cue(&"vorrak")
	var vor_color: Color = sf._visual_color
	_assert(
		obs_color != vor_color,
		(
			"observer and vorrak boss cues should produce different colors (got obs=%s vor=%s)"
			% [obs_color, vor_color]
		)
	)
	## Both cues preserve the cue-profile alpha before reduced-VFX scaling
	var spawn_alpha: float = (
		SensoryScript.CUE_VISUAL[SensoryScript.CUE_BOSS_SPAWN].get("color", Color.TRANSPARENT).a
	)
	_assert(
		abs(obs_color.a - spawn_alpha) < 0.001,
		(
			"observer cue should preserve fallback alpha (expected %.3f, got %.3f)"
			% [spawn_alpha, obs_color.a]
		)
	)
	_assert(
		abs(vor_color.a - spawn_alpha) < 0.001,
		(
			"vorrak cue should preserve fallback alpha (expected %.3f, got %.3f)"
			% [spawn_alpha, vor_color.a]
		)
	)
	## Reduced VFX: enable non-persistently, trigger Nyxara cue, assert capped alpha, restore
	sf.set_reduced_vfx_enabled(true, false)
	sf.play_boss_defeat_cue(&"nyxara")
	_assert(
		sf._visual_color.a <= sf.REDUCED_VFX_MAX_ALPHA + 0.0001,
		(
			"reduced VFX should cap cue alpha (got %.6f, max %.4f, epsilon 0.0001)"
			% [sf._visual_color.a, sf.REDUCED_VFX_MAX_ALPHA]
		)
	)
	sf.set_reduced_vfx_enabled(false, false)


func _check_version_history() -> void:
	var v20_1_entries: Array[String] = []
	for entry: String in VersionHistoryScript.VERSION_HISTORY:
		if entry.contains("V20.1.0"):
			v20_1_entries.append(entry)
	_assert(
		v20_1_entries.size() == 1,
		"VERSION_HISTORY should contain exactly one V20.1.0 entry (found %d)" % v20_1_entries.size()
	)
	_assert(
		v20_1_entries[0].contains("Boss identity pass"),
		"V20.1.0 entry should mention Boss identity pass"
	)


func _assert(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
