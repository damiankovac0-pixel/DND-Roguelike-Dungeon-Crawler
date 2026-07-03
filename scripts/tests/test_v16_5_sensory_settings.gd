## Focused V16.5 regression coverage for remembered reduced VFX and calmer audio profiles.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v16_5_sensory_settings.gd
extends SceneTree

const SENSORY_SCRIPT_PATH: String = "res://scripts/ui/sensory_feedback.gd"
const GAME_SCENE_PATH: String = "res://scenes/game.tscn"

var _failed: bool = false
var _sf_script: GDScript


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_sf_script = load(SENSORY_SCRIPT_PATH)
	if _sf_script == null or not _sf_script.can_instantiate():
		_fail("SensoryFeedback script failed to load or instantiate")
		return

	await _reset_reduced_vfx_preference()
	if _failed:
		return
	await _check_reduced_vfx_persists()
	if _failed:
		return
	await _check_reduced_vfx_tones_down_flash()
	if _failed:
		return
	await _check_audio_profiles_are_quieter()
	if _failed:
		return
	await _check_pause_menu_exposes_reduced_vfx()
	if _failed:
		return
	await _reset_reduced_vfx_preference()
	if _failed:
		return

	print("V16.5 sensory settings checks passed")
	quit(0)


func _check_reduced_vfx_persists() -> void:
	var first: Control = _new_sensory_feedback()
	if first == null:
		return
	first.set_reduced_vfx_enabled(true, true)
	first.queue_free()
	await process_frame

	var second: Control = _new_sensory_feedback()
	if second == null:
		return
	if not second.is_reduced_vfx_enabled():
		_fail("Reduced VFX setting should persist for the next SensoryFeedback instance")
		second.queue_free()
		return
	second.queue_free()
	await process_frame
	print("  reduced VFX setting persists through user:// config")


func _check_reduced_vfx_tones_down_flash() -> void:
	var sf: Control = _new_sensory_feedback()
	if sf == null:
		return
	sf.set_audio_enabled(false, false)
	sf.set_reduced_vfx_enabled(true, false)
	sf.trigger_cue(sf.CUE_DAMAGE)
	if not sf.has_active_visual_feedback():
		_fail("Reduced VFX should still leave a visible feedback mark")
		sf.queue_free()
		return
	if sf._visual_color.a > sf.REDUCED_VFX_MAX_ALPHA + 0.001:
		_fail("Reduced VFX alpha too high: %s" % sf._visual_color.a)
		sf.queue_free()
		return
	var full_duration: float = sf.CUE_VISUAL[sf.CUE_DAMAGE]["duration"]
	if sf._visual_duration >= full_duration:
		_fail("Reduced VFX duration should be shorter than full VFX duration")
		sf.queue_free()
		return
	sf.queue_free()
	await process_frame
	print("  reduced VFX keeps a subtle mark without full-strength flash")


func _check_audio_profiles_are_quieter() -> void:
	var sf: Control = _new_sensory_feedback()
	if sf == null:
		return
	var hit_profile: Dictionary = sf.get_cue_profile(sf.CUE_COMBAT_HIT)
	var damage_profile: Dictionary = sf.get_cue_profile(sf.CUE_DAMAGE)
	var warning_profile: Dictionary = sf.get_cue_profile(sf.CUE_WARNING)
	if float(hit_profile.get("gain_db", 0.0)) > -8.0:
		_fail("combat hit gain should stay polished/quiet: %s" % hit_profile)
		sf.queue_free()
		return
	if float(damage_profile.get("min_interval", 0.0)) < 0.45:
		_fail("damage cue should be rate-limited more gently: %s" % damage_profile)
		sf.queue_free()
		return
	if float(warning_profile.get("gain_db", 0.0)) > -12.0:
		_fail("warning cue should stay quiet: %s" % warning_profile)
		sf.queue_free()
		return
	if sf.get_master_volume() > 0.43:
		_fail("default master volume should be calmer, got %s" % sf.get_master_volume())
		sf.queue_free()
		return
	sf.queue_free()
	await process_frame
	print("  audio profiles: lower gains, longer rate limits, calmer default volume")


func _check_pause_menu_exposes_reduced_vfx() -> void:
	var game_manager: Node = root.get_node_or_null("/root/GameManager")
	if game_manager == null:
		_fail("GameManager autoload missing")
		return
	game_manager.prepare_character("debug", {})
	var game_scene: PackedScene = load(GAME_SCENE_PATH)
	if game_scene == null:
		_fail("game scene failed to load")
		return
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame
	var reduced_button: Node = game.get_node_or_null("UI/PausePanel/Margin/VBox/ReducedVfxButton")
	if reduced_button == null:
		_fail("Pause panel missing Reduce VFX button")
		game.queue_free()
		return
	if not game.sensory_feedback.has_method(&"is_reduced_vfx_enabled"):
		_fail("SensoryFeedback missing reduced VFX getter for pause sync")
		game.queue_free()
		return
	game_manager.abandon_run()
	game.queue_free()
	await process_frame
	print("  pause menu exposes remembered Reduce VFX control")


func _reset_reduced_vfx_preference() -> void:
	var sf: Control = _new_sensory_feedback()
	if sf == null:
		return
	sf.set_reduced_vfx_enabled(false, true)
	sf.queue_free()
	await process_frame


func _new_sensory_feedback() -> Control:
	var sf: Control = _sf_script.new()
	if sf == null:
		_fail("SensoryFeedback instance creation failed")
		return null
	root.add_child(sf)
	return sf


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
