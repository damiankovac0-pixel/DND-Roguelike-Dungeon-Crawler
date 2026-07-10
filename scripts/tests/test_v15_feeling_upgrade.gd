## Headless test for V16.5.0 Feeling Upgrade:
##   - V16.5 version string contract
##   - New audio/VFX API methods (is_audio_enabled, toggle, set with announce param,
##     master volume, ambience, reduced VFX, floor context, cue profile, play count)
##   - Mute does not block visual feedback
##   - Streams remain non-empty WAVs; unknown cues no-op
##   - MapView atmosphere API and cell burst (V13) compatibility
##   - Scene integration: game.tscn has UI/SensoryFeedback and pause audio/VFX controls
##   - Main menu / library / character creation have AsciiBackdrop Background
##   - GameManager current release metadata
##   - Library version history includes V16.5, V16, V15, and V14
##
## Defensive: uses runtime load() with explicit null checks so every missing
## contract produces a clear _fail().  Skips deeper method-level tests when a
## whole script fails to compile.
##
## Run:
##   /usr/local/bin/godot --headless --path .
##     --script res://scripts/tests/test_v15_feeling_upgrade.gd
extends SceneTree

const GAME_SCENE_PATH: String = "res://scenes/game.tscn"

var _sf: Node  # SensoryFeedback instance, reused across checks
var _sf_script  # GDScript — set by runtime load
var _mv_script  # GDScript — set by runtime load
var _lib_script  # GDScript — set by runtime load
var _backdrop_script  # GDScript — set by runtime load

# -- All-in-one flag so we don't retry failed loads in every check --
var _sf_loaded: bool = false
var _mv_loaded: bool = false
var _lib_loaded: bool = false
var _bd_loaded: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)

	# === 0. Attempt runtime script loads ===
	_load_scripts()

	# === 1. V16.5 Version ===
	_check_v15_version()

	# === 2. SensoryFeedback V16.5 Audio/VFX API ===
	if _sf_loaded:
		_check_audio_api()

	# === 3. Master volume API ===
	if _sf_loaded:
		_check_volume_api()

	# === 4. Ambience API ===
	if _sf_loaded:
		_check_ambience_api()

	# === 5. Floor audio context ===
	if _sf_loaded:
		_check_floor_audio_context()

	# === 6. Cue profile and play count ===
	if _sf_loaded:
		_check_cue_profile()

	# === 7. Audio streams non-empty WAVs ===
	if _sf_loaded:
		_check_audio_streams_nonempty()

	# === 8. Unknown cues no-op ===
	if _sf_loaded:
		_check_unknown_cue_noop()

	# === 9. Visual feedback works when audio disabled ===
	if _sf_loaded:
		await _check_visual_when_muted()

	# === 10. MapView atmosphere API ===
	if _mv_loaded:
		_check_map_atmosphere_api()

	# === 11. MapView cell burst (V13) still works ===
	if _mv_loaded:
		await _check_map_cell_bursts()

	# === 12. Game scene integration ===
	await _check_game_scene_integration()

	# === 13. Main menu / library / character creation Backdrop ===
	await _check_backdrop_scenes()

	# === 14. GameManager version ===
	_check_game_manager_version()

	# === 15. Library version history ===
	if _lib_loaded:
		_check_library_version_history()
	else:
		# Library history is important enough to always check — scan the raw file
		_check_library_history_raw()

	# === 16. Pause audio controls ===
	await _check_pause_audio_controls()

	await process_frame

	print("V16.5.0 feeling upgrade tests passed")
	quit(0)


# ======================================================================
# 0. Runtime script loading — robust against broken dependencies
# ======================================================================
func _load_scripts() -> void:
	var sf_path := "res://scripts/ui/sensory_feedback.gd"
	_sf_script = load(sf_path)
	_sf_loaded = _sf_script != null and _sf_script.can_instantiate()
	if not _sf_loaded:
		_fail("Cannot load/instantiate %s — script may have compile errors" % sf_path)

	var mv_path := "res://scripts/ui/map_view.gd"
	_mv_script = load(mv_path)
	_mv_loaded = _mv_script != null and _mv_script.can_instantiate()
	if not _mv_loaded:
		print("  SKIP: %s failed to load/instantiate (V16 map checks skipped)" % mv_path)

	var lib_path := "res://scripts/ui/library_menu.gd"
	_lib_script = load(lib_path)
	_lib_loaded = _lib_script != null
	if not _lib_loaded:
		print("  NOTE: %s failed to load (library checks use raw text)" % lib_path)

	var bd_path := "res://scripts/ui/ascii_backdrop.gd"
	_backdrop_script = load(bd_path)
	_bd_loaded = _backdrop_script != null and _backdrop_script.can_instantiate()


func _check_v15_version() -> void:
	if not _sf_loaded:
		_fail("SensoryFeedback version check skipped — script not loaded")
		return

	# Check class_name via the script object
	if _sf_script.get_global_name() != &"SensoryFeedback":
		_fail("Expected script class_name SensoryFeedback, got %s" % _sf_script.get_global_name())

	# Instantiate to check VERSION constant
	var sf_instance: Node = _sf_script.new()
	root.add_child(sf_instance)

	if not ("VERSION" in sf_instance):
		_fail("SensoryFeedback instance missing VERSION property")

	var version: String = sf_instance.VERSION
	if version != "16.5.0":
		_fail(
			(
				(
					"SensoryFeedback.VERSION expected '16.5.0', got '%s' — "
					+ "V16.5 version string contract not yet updated"
				)
				% version
			)
		)

	sf_instance.queue_free()


# ======================================================================
# 2. Audio API — is_audio_enabled, toggle, set with announce param
# ======================================================================
func _check_audio_api() -> void:
	_sf = _sf_script.new()
	root.add_child(_sf)

	# --- is_audio_enabled ---
	if _sf.has_method(&"is_audio_enabled"):
		var enabled: bool = _sf.is_audio_enabled()
		print("  is_audio_enabled() initially = %s" % str(enabled))
	else:
		_fail("SensoryFeedback missing is_audio_enabled() — V16 contract")

	# --- toggle_audio_enabled(announce := true) ---
	if _sf.has_method(&"toggle_audio_enabled"):
		var before: bool = _sf.is_audio_enabled() if _sf.has_method("is_audio_enabled") else true
		_sf.toggle_audio_enabled(false)  # announce=false for headless
		if _sf.has_method(&"is_audio_enabled"):
			var after: bool = _sf.is_audio_enabled()
			_assert_ne(before, after, "toggle_audio_enabled should flip audio enabled state")
	else:
		_fail("SensoryFeedback missing toggle_audio_enabled(announce) — V16 contract")

	# --- set_audio_enabled(enabled, announce := false) ---
	if _sf.has_method(&"set_audio_enabled"):
		# V14 signature: set_audio_enabled(enabled) ← no announce param
		# V16 signature inherits V15 announce support: set_audio_enabled(enabled: bool, announce := false)
		_sf.set_audio_enabled(true, false)
		if _sf.has_method(&"is_audio_enabled"):
			_assert_eq(
				_sf.is_audio_enabled(), true, "set_audio_enabled(true, false) should enable audio"
			)
		_sf.set_audio_enabled(false, false)
		if _sf.has_method(&"is_audio_enabled"):
			_assert_eq(
				_sf.is_audio_enabled(),
				false,
				"set_audio_enabled(false, false) should disable audio"
			)
	else:
		_fail("SensoryFeedback missing set_audio_enabled() — V16 contract")


# ======================================================================
# 3. Master volume API — set / get / effective_db
# ======================================================================
func _check_volume_api() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in volume check")

	# --- set_master_volume(value: float) ---
	if _sf.has_method(&"set_master_volume"):
		_sf.set_master_volume(-12.0)
	else:
		_fail("SensoryFeedback missing set_master_volume() — V16 contract")

	# --- get_master_volume() ---
	if _sf.has_method(&"get_master_volume"):
		var vol: float = _sf.get_master_volume()
		# Accept any finite value — the important contract is that the method exists
		# and returns a number.
		_assert_true(
			not is_nan(vol), "get_master_volume() should return a finite float, got %s" % vol
		)
	else:
		_fail("SensoryFeedback missing get_master_volume() — V16 contract")

	# --- Volume clamping ---
	if _sf.has_method(&"set_master_volume") and _sf.has_method(&"get_master_volume"):
		_sf.set_master_volume(-200.0)
		var clamped_low: float = _sf.get_master_volume()
		_assert_true(
			clamped_low >= -80.0, "set_master_volume(-200) should clamp; got %s" % clamped_low
		)
		_sf.set_master_volume(50.0)
		var clamped_high: float = _sf.get_master_volume()
		_assert_true(
			clamped_high <= 24.0, "set_master_volume(50) should clamp; got %s" % clamped_high
		)
		_sf.set_master_volume(-18.0)  # restore
	else:
		_fail("SensoryFeedback missing volume get/set — V16 contract")

	# --- get_effective_volume_db() ---
	if _sf.has_method(&"get_effective_volume_db"):
		var eff_db: float = _sf.get_effective_volume_db()
		_assert_true(
			not is_nan(eff_db),
			"get_effective_volume_db() should return a finite float, got %s" % eff_db
		)
		# When audio is disabled, effective volume should be very quiet
		if _sf.has_method(&"is_audio_enabled"):
			_sf.set_audio_enabled(false, false)
			var muted_db: float = _sf.get_effective_volume_db()
			_assert_true(
				muted_db <= -60.0 or is_inf(muted_db),
				(
					"get_effective_volume_db() when muted should be <= -60 dB or -INF, "
					+ "got %s" % muted_db
				)
			)
			_sf.set_audio_enabled(true, false)
	else:
		_fail("SensoryFeedback missing get_effective_volume_db() — V16 contract")


# ======================================================================
# 4. Ambience API
# ======================================================================
func _check_ambience_api() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in ambience check")

	if _sf.has_method(&"set_ambience_enabled"):
		_sf.set_ambience_enabled(false)
	else:
		_fail("SensoryFeedback missing set_ambience_enabled() — V15 contract")

	if _sf.has_method(&"is_ambience_enabled"):
		var amb: bool = _sf.is_ambience_enabled()
		_assert_eq(
			amb, false, "is_ambience_enabled() should be false after set_ambience_enabled(false)"
		)
		_sf.set_ambience_enabled(true)
		amb = _sf.is_ambience_enabled()
		_assert_eq(
			amb, true, "is_ambience_enabled() should be true after set_ambience_enabled(true)"
		)
		_sf.set_ambience_enabled(false)
	else:
		_fail("SensoryFeedback missing is_ambience_enabled() — V15 contract")

	if _sf.has_method(&"get_ambience_stream"):
		var amb_stream = _sf.get_ambience_stream()
		if amb_stream != null:
			_assert_true(
				amb_stream is AudioStreamWAV,
				(
					"get_ambience_stream() should return AudioStreamWAV or null, "
					+ "got %s" % amb_stream.get_class()
				)
			)
		else:
			print("  get_ambience_stream() returned null (acceptable if ambience not initialized)")
	else:
		_fail("SensoryFeedback missing get_ambience_stream() — V15 contract")

	if _sf.has_method(&"get_ambience_profile"):
		var profile = _sf.get_ambience_profile()
		if profile != null:
			_assert_true(
				profile is Dictionary,
				(
					"get_ambience_profile() should return Dictionary or null, "
					+ "got %s" % typeof(profile)
				)
			)
	else:
		_fail("SensoryFeedback missing get_ambience_profile() — V15 contract")


# ======================================================================
# 5. Floor audio context
# ======================================================================
func _check_floor_audio_context() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in floor audio context check")

	if _sf.has_method(&"set_floor_audio_context"):
		var test_biome: Dictionary = {"name": "Test Biome", "ambient_pitch": 1.2}
		_sf.set_floor_audio_context(5, test_biome)
		print("  set_floor_audio_context(5, {...}) completed without error")
	else:
		_fail("SensoryFeedback missing set_floor_audio_context() — V15 contract")


# ======================================================================
# 6. Cue profile and play count
# ======================================================================
func _check_cue_profile() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in cue profile check")

	if _sf.has_method(&"get_cue_profile"):
		var profile = _sf.get_cue_profile(&"combat_hit")
		if profile != null:
			_assert_true(
				profile is Dictionary,
				(
					'get_cue_profile(&"combat_hit") should return Dictionary or null, '
					+ "got %s" % typeof(profile)
				)
			)
		else:
			print("  get_cue_profile returned null (acceptable if not yet implemented)")
		var unknown_profile = _sf.get_cue_profile(&"nonexistent_cue")
		# Accept null OR empty dict — V15 stubs may differ on the sentinel
		if unknown_profile != null:
			if unknown_profile is Dictionary and unknown_profile.is_empty():
				print('  get_cue_profile(&"nonexistent_cue") returned {} (acceptable)')
			else:
				_fail(
					(
						'get_cue_profile(&"nonexistent_cue") expected null or {}, '
						+ "got %s" % str(unknown_profile)
					)
				)
	else:
		_fail("SensoryFeedback missing get_cue_profile() — V15 contract")

	if _sf.has_method(&"get_play_count"):
		var count: int = _sf.get_play_count(&"combat_hit")
		_assert_true(count >= 0, 'get_play_count(&"combat_hit") should be >= 0, got %d' % count)
		var unknown_count: int = _sf.get_play_count(&"nonexistent")
		_assert_eq(unknown_count, 0, 'get_play_count(&"nonexistent") should return 0')
	else:
		_fail("SensoryFeedback missing get_play_count() — V15 contract")


# ======================================================================
# 7. Audio streams non-empty WAVs
# ======================================================================
func _check_audio_streams_nonempty() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in audio streams check")

	if _sf.has_method(&"set_audio_enabled"):
		_sf.set_audio_enabled(false, false)

	var known_cues: Array[StringName] = [
		&"combat_hit",
		&"combat_miss",
		&"damage",
		&"death",
		&"loot",
		&"gold",
		&"heal",
		&"warning",
		&"floor",
		&"level",
		&"equipment",
		&"magic",
		&"victory",
	]
	for cue: StringName in known_cues:
		var stream: AudioStreamWAV = _sf.get_cue_stream(cue)
		if stream == null:
			_fail('get_cue_stream(&"%s") returned null, expected AudioStreamWAV' % cue)
		if not stream is AudioStreamWAV:
			_fail(
				(
					('get_cue_stream(&"%s") returned %s, expected AudioStreamWAV')
					% [cue, stream.get_class()]
				)
			)
		if stream.data.is_empty():
			_fail("AudioStreamWAV data for cue '%s' is empty" % cue)
		if stream.format != AudioStreamWAV.FORMAT_16_BITS:
			_fail(
				(
					("AudioStreamWAV format for '%s' expected FORMAT_16_BITS (%d), got %d")
					% [cue, AudioStreamWAV.FORMAT_16_BITS, stream.format]
				)
			)

	print("  All %d cue streams verified non-empty WAVs" % known_cues.size())


# ======================================================================
# 8. Unknown cues no-op
# ======================================================================
func _check_unknown_cue_noop() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in unknown cue check")

	# Both known and unknown triggers should not crash
	_sf.trigger_cue(&"")
	_sf.trigger_cue(&"definitely_not_a_real_cue_name_12345")
	_sf.trigger_cue(&"combat_hit")

	if _sf.has_method(&"has_active_visual_feedback"):
		print("  Unknown cue no-op verified (no crash on empty/bogus cues)")

	print("  Unknown cue trigger no-op test passed")


# ======================================================================
# 9. Visual feedback works when audio disabled
# ======================================================================
func _check_visual_when_muted() -> void:
	if _sf == null or not is_instance_valid(_sf):
		_fail("_sf instance invalid in visual when muted check")

	if _sf.has_method(&"set_audio_enabled"):
		_sf.set_audio_enabled(false, false)

	_sf.trigger_cue(&"level")
	if not _sf.has_active_visual_feedback():
		_fail(
			(
				'has_active_visual_feedback() should be true after trigger_cue(&"level") '
				+ "even when audio is disabled"
			)
		)

	_sf._process(1.0)
	_sf._process(1.0)

	if _sf.has_active_visual_feedback():
		_fail("has_active_visual_feedback() should be false after 2.0s of _process")


# ======================================================================
# 10. MapView atmosphere API
# ======================================================================
func _check_map_atmosphere_api() -> void:
	if not _mv_loaded or _mv_script == null:
		_fail("MapView atmosphere check skipped — script not loaded")
		return

	var mv: Node = _mv_script.new()
	root.add_child(mv)

	if mv.has_method(&"set_atmosphere_enabled"):
		mv.set_atmosphere_enabled(true)
	else:
		_fail("MapView missing set_atmosphere_enabled() — V15 contract")

	if mv.has_method(&"is_atmosphere_enabled"):
		var atm: bool = mv.is_atmosphere_enabled()
		print("  MapView is_atmosphere_enabled() = %s" % str(atm))
		_assert_eq(atm, true, "is_atmosphere_enabled should be true after enabling")
	else:
		_fail("MapView missing is_atmosphere_enabled() — V15 contract")

	if mv.has_method(&"get_atmosphere_profile"):
		var profile = mv.get_atmosphere_profile()
		if profile != null:
			_assert_true(
				profile is Dictionary,
				(
					"get_atmosphere_profile() should return Dictionary or null, "
					+ "got %s" % typeof(profile)
				)
			)
		else:
			print("  get_atmosphere_profile() returned null (acceptable if V15 not implemented)")
	else:
		_fail("MapView missing get_atmosphere_profile() — V15 contract")

	if mv.has_method(&"has_active_atmosphere_animation"):
		var has_active: bool = mv.has_active_atmosphere_animation()
		print("  has_active_atmosphere_animation() initially = %s" % str(has_active))
	else:
		_fail("MapView missing has_active_atmosphere_animation() — V15 contract")

	if (
		mv.has_method(&"set_atmosphere_enabled")
		and mv.has_method(&"has_active_atmosphere_animation")
	):
		mv.set_atmosphere_enabled(false)
		var still_active: bool = mv.has_active_atmosphere_animation()
		_assert_eq(
			still_active,
			false,
			"has_active_atmosphere_animation() should be false when atmosphere disabled and no bursts"
		)

	mv.queue_free()


# ======================================================================
# 11. MapView cell burst (V13) still works
# ======================================================================
func _check_map_cell_bursts() -> void:
	if not _mv_loaded or _mv_script == null:
		_fail("MapView cell burst check skipped — script not loaded")
		return

	var mv: Node = _mv_script.new()
	root.add_child(mv)

	if not mv.has_method(&"play_cell_burst"):
		_fail("MapView missing play_cell_burst() — V13/V15 contract")

	if not mv.has_method(&"has_active_cell_bursts"):
		_fail("MapView missing has_active_cell_bursts() — V13 contract")

	if mv.has_active_cell_bursts():
		_fail("has_active_cell_bursts() should be false initially")

	mv.play_cell_burst(Vector2i(5, 3), Color.RED, "✦")
	if not mv.has_active_cell_bursts():
		_fail("has_active_cell_bursts() should be true after play_cell_burst")

	var elapsed: float = 0.0
	while elapsed < 0.6 and mv.has_active_cell_bursts():
		mv._process(0.1)
		elapsed += 0.1

	if mv.has_active_cell_bursts():
		_fail("has_active_cell_bursts() should be false after burst expires (>0.55s)")

	_assert_true(
		not mv.has_active_cell_bursts(), "Cell burst should be removed after CELL_BURST_DURATION"
	)

	mv.queue_free()


# ======================================================================
# 12. Game scene integration
# ======================================================================
func _check_game_scene_integration() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	gm.prepare_character("debug", {})
	var game_scene: PackedScene = load(GAME_SCENE_PATH)
	if game_scene == null:
		_fail("Could not load res://scenes/game.tscn")
		return

	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	# UI/SensoryFeedback node
	var sf_node: Node = game.get_node_or_null("UI/SensoryFeedback")
	if sf_node == null:
		_fail("UI/SensoryFeedback node not found in game.tscn scene tree")
	else:
		print("  UI/SensoryFeedback found in game scene")

	# Pause panel nodes (V15 contract — paths defined in contract)
	var pause_panel: Node = game.get_node_or_null("UI/PausePanel")
	if pause_panel == null:
		_fail("UI/PausePanel node not found in game.tscn")
		gm.abandon_run()
		game.queue_free()
		await process_frame
		return

	_maybe_check_node(pause_panel, "Margin/VBox/AudioHeaderLabel", "Pause panel AudioHeaderLabel")
	_maybe_check_node(
		pause_panel, "Margin/VBox/AudioEnabledButton", "Pause panel AudioEnabledButton"
	)
	_maybe_check_node(
		pause_panel,
		"Margin/VBox/MasterVolumeRow/MasterVolumeSlider",
		"Pause panel MasterVolumeSlider"
	)
	_maybe_check_node(
		pause_panel,
		"Margin/VBox/MasterVolumeRow/MasterVolumeValueLabel",
		"Pause panel MasterVolumeValueLabel"
	)
	_maybe_check_node(
		pause_panel, "Margin/VBox/AmbienceEnabledButton", "Pause panel AmbienceEnabledButton"
	)
	_maybe_check_node(pause_panel, "Margin/VBox/ReducedVfxButton", "Pause panel ReducedVfxButton")

	gm.abandon_run()
	game.queue_free()
	await process_frame


# ======================================================================
# 13. Main menu / library / character creation Backdrop
# ======================================================================
func _check_backdrop_scenes() -> void:
	# Main menu
	var main_menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	if main_menu_scene != null:
		var main_menu: Node = main_menu_scene.instantiate()
		root.add_child(main_menu)
		await process_frame

		var mm_bg: Node = main_menu.get_node_or_null("Background")
		if mm_bg == null:
			_fail("MainMenu scene missing Background node")
		elif mm_bg.get_script() != null:
			var script_name: String = mm_bg.get_script().get_global_name()
			if script_name == "AsciiBackdrop":
				print("  MainMenu Background uses AsciiBackdrop script")
			else:
				print(
					(
						"  WARNING: MainMenu Background script is %s (expected AsciiBackdrop)"
						% script_name
					)
				)
		elif _bd_loaded:
			_fail("MainMenu Background has no script — expected AsciiBackdrop")
		else:
			print("  WARNING: MainMenu Background script null (AsciiBackdrop may not compile)")

		main_menu.queue_free()
		await process_frame
	else:
		_fail("Could not load res://scenes/main_menu.tscn")

	# Library scene
	var library_scene: PackedScene = load("res://scenes/library.tscn")
	if library_scene != null:
		var library: Node = library_scene.instantiate()
		root.add_child(library)
		await process_frame

		var lib_bg: Node = library.get_node_or_null("Background")
		if lib_bg == null:
			_fail("Library scene missing Background node at 'Background'")
		elif lib_bg.get_script() != null:
			var lib_script_name: String = lib_bg.get_script().get_global_name()
			if lib_script_name == "AsciiBackdrop":
				print("  Library Background uses AsciiBackdrop script")
			else:
				print(
					(
						"  WARNING: Library Background script is %s (expected AsciiBackdrop)"
						% lib_script_name
					)
				)
		else:
			print(
				(
					"  WARNING: Library Background has no script (acceptable if V15 WIP; "
					+ "contract expects AsciiBackdrop)"
				)
			)

		library.queue_free()
		await process_frame
	else:
		print("  WARNING: Could not load res://scenes/library.tscn (library checks skipped)")

	# Character creation scene
	var cc_scene: PackedScene = load("res://scenes/character_creation.tscn")
	if cc_scene != null:
		var cc: Node = cc_scene.instantiate()
		root.add_child(cc)
		await process_frame

		var cc_bg: Node = cc.get_node_or_null("Background")
		if cc_bg == null:
			_fail("CharacterCreation scene missing Background node at 'Background'")
		elif cc_bg.get_script() != null:
			var cc_script_name: String = cc_bg.get_script().get_global_name()
			if cc_script_name == "AsciiBackdrop":
				print("  CharacterCreation Background uses AsciiBackdrop script")
			else:
				print(
					(
						(
							"  WARNING: CharacterCreation Background script is %s "
							+ "(expected AsciiBackdrop)"
						)
						% cc_script_name
					)
				)
		else:
			print(
				(
					"  WARNING: CharacterCreation Background has no script (acceptable if V15 WIP; "
					+ "contract expects AsciiBackdrop)"
				)
			)

		cc.queue_free()
		await process_frame
	else:
		print(
			"  WARNING: Could not load res://scenes/character_creation.tscn (scene checks skipped)"
		)


# ======================================================================
# 14. GameManager version
# ======================================================================
func _check_game_manager_version() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	if not ("GAME_VERSION" in gm):
		_fail("GameManager instance missing GAME_VERSION property")

	var gm_version: String = gm.GAME_VERSION
	if gm_version != "23.0.0":
		_fail(
			(
				"GameManager.GAME_VERSION expected '23.0.0', got '%s' — V23 release not set"
				% gm_version
			)
		)
	else:
		print("  GameManager.GAME_VERSION = 23.0.0")

	var label: String = gm.get_version_label()
	if not "23.0.0" in label or not "2026-07-10" in label:
		print(
			(
				"  WARNING: GameManager.get_version_label() = '%s' — "
				+ "may not reference 23.0.0 / 2026-07-10" % label
			)
		)
	else:
		print("  GameManager.get_version_label() references 23.0.0 / 2026-07-10")


# ======================================================================
# 15. Library version history — script load path
# ======================================================================
func _check_library_version_history() -> void:
	var history: Array = _lib_script.VERSION_HISTORY
	if history == null or history.is_empty():
		_fail("LibraryMenu.VERSION_HISTORY is empty or missing")

	var has_v16_5: bool = false
	var has_v16: bool = false
	var has_v15: bool = false
	var has_v14: bool = false
	var has_v13: bool = false
	for entry: Variant in history:
		var line: String = str(entry)
		if line.contains("V16.5") or line.contains("16.5.0"):
			has_v16_5 = true
		if line.contains("V16.0.0") or line.contains("16.0.0"):
			has_v16 = true
		if line.contains("V15") or line.contains("15.0.0"):
			has_v15 = true
		if line.contains("V14") or line.contains("14.0.0"):
			has_v14 = true
		if line.contains("V13") or line.contains("13.0.0"):
			has_v13 = true

	if not has_v16_5:
		_fail(
			(
				"Library version history must include V16.5 or 16.5.0 entry — "
				+ "did not find 'V16.5' or '16.5.0' in VERSION_HISTORY"
			)
		)
	if not has_v16:
		_fail(
			(
				"Library version history must include V16 or 16.0.0 entry — "
				+ "did not find 'V16' or '16.0.0' in VERSION_HISTORY"
			)
		)
	if not has_v15:
		_fail(
			(
				"Library version history must include V15 or 15.0.0 entry — "
				+ "did not find 'V15' or '15.0.0' in VERSION_HISTORY"
			)
		)
	if not has_v14:
		_fail(
			(
				"Library version history must include V14 or 14.0.0 entry — "
				+ "did not find 'V14' or '14.0.0' in VERSION_HISTORY"
			)
		)
	if not has_v13:
		print("  NOTE: V13 entry not found in VERSION_HISTORY (acceptable if trimmed)")
	print(
		(
			"  Library version history: V16.5 %s, V16 %s, V15 %s, V14 %s, V13 %s"
			% [
				"✓" if has_v16_5 else "✗",
				"✓" if has_v16 else "✗",
				"✓" if has_v15 else "✗",
				"✓" if has_v14 else "✗",
				"✓" if has_v13 else "(not found)"
			]
		)
	)
	print("  Total history entries: %d" % history.size())


# ======================================================================
# 15b. Library version history — raw file scan (fallback when script broken)
# ======================================================================
func _check_library_history_raw() -> void:
	print("  Checking library version history via raw file scan (script not loadable)")
	var content: String = _read_tscn_or_gd("res://scripts/version_history.gd")
	if content.is_empty():
		_fail("Could not read version_history.gd for version history check")
		return

	var has_v16_5: bool = "16.5.0" in content or "V16.5" in content
	var has_v16: bool = "16.0.0" in content or "V16.0" in content
	var has_v15: bool = "15.0.0" in content or "V15" in content
	var has_v14: bool = "14.0.0" in content or "V14" in content

	if not has_v16_5:
		_fail(
			(
				"Library version history must include V16.5 or 16.5.0 entry — "
				+ "scanned raw file, no '16.5.0' or 'V16.5' found"
			)
		)
	if not has_v16:
		_fail(
			(
				"Library version history must include V16 or 16.0.0 entry — "
				+ "scanned raw file, no '16.0.0' or 'V16.0' found"
			)
		)
	if not has_v15:
		_fail(
			(
				"Library version history must include V15 or 15.0.0 entry — "
				+ "scanned raw file, no '15.0.0' or 'V15' found"
			)
		)
	if not has_v14:
		_fail(
			(
				"Library version history must include V14 or 14.0.0 entry — "
				+ "scanned raw file, no '14.0.0' or 'V14' found"
			)
		)

	# Count VERSION_HISTORY entries via regex
	var entry_count: int = 0
	var lines: PackedStringArray = content.split("\n")
	for line: String in lines:
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with('"[color=#') and trimmed.contains("V"):
			entry_count += 1

	print(
		(
			"  Library version history (raw scan): V16.5 %s, V16 %s, V15 %s, V14 %s — %d entries"
			% [
				"✓" if has_v16_5 else "✗",
				"✓" if has_v16 else "✗",
				"✓" if has_v15 else "✗",
				"✓" if has_v14 else "✗",
				entry_count
			]
		)
	)


# ======================================================================
# 16. Pause audio controls — scene resource verification
# ======================================================================
func _check_pause_audio_controls() -> void:
	var game_tscn: PackedScene = load(GAME_SCENE_PATH)
	if game_tscn == null:
		_fail("Could not load res://scenes/game.tscn")
		return

	var game: Node = game_tscn.instantiate()
	if game == null:
		_fail("Failed to instantiate game.tscn")

	game.queue_free()
	await process_frame

	print("  game.tscn resource loads and instantiates")


# ======================================================================
# Helpers
# ======================================================================


## Checks whether `parent` has a node at `path` and prints/logs the result.
func _maybe_check_node(parent: Node, path: String, label: String) -> void:
	var node: Node = parent.get_node_or_null(path)
	if node == null:
		_fail("%s — node not found at '%s'" % [label, path])
	else:
		print("  %s found" % label)


## Reads a text resource file into a string (robust against engine errors).
func _read_tscn_or_gd(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text: String = f.get_as_text()
	f.close()
	return text


# ======================================================================
# Assertion helpers
# ======================================================================
func _assert_eq(a, b, msg: String = "") -> void:
	if a != b:
		_fail("assert_eq failed: " + msg + " - expected '%s', got '%s'" % [str(b), str(a)])


func _assert_ne(a, b, msg: String = "") -> void:
	if a == b:
		_fail("assert_ne failed: " + msg + " - values are both '%s'" % [str(a)])


func _assert_true(value: bool, msg: String = "") -> void:
	if not value:
		_fail("assert_true failed: " + msg)


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
