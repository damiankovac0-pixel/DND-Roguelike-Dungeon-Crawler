## Headless test for V14.0.0 sensory feedback:
##   - SensoryFeedback script instantiation and audio disable
##   - Cue mapping for known and unknown message types
##   - get_cue_names() completeness for all required cues
##   - AudioStreamWAV properties (format, mix_rate, non-empty data)
##   - Visual feedback lifecycle (activate on trigger, expire after duration)
##   - Game scene integration (UI/SensoryFeedback node presence)
##
## Run:
##   /usr/local/bin/godot --headless --path .
##     --script res://scripts/tests/test_v14_sensory_feedback.gd
extends SceneTree
var _sensory_feedback_script: GDScript


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(424242)

	# Load the script and verify class_name
	_sensory_feedback_script = load("res://scripts/ui/sensory_feedback.gd")
	if _sensory_feedback_script == null:
		_fail("Could not load res://scripts/ui/sensory_feedback.gd")
	if _sensory_feedback_script.get_global_name() != &"SensoryFeedback":
		_fail(
			(
				"Expected class_name SensoryFeedback, got %s"
				% _sensory_feedback_script.get_global_name()
			)
		)

	# === 1. Cue mapping ===
	_check_cue_mapping()

	# === 2. Cue names ===
	_check_cue_names()

	# === 3. Audio stream ===
	_check_audio_stream()

	# === 4. Visual feedback ===
	await _check_visual_feedback()

	# === 5. Game scene integration ===
	await _check_game_scene_integration()

	await process_frame

	print("V14.0.0 sensory feedback tests passed")
	quit(0)


# ======================================================================
# 1. Cue mapping for message types
# ======================================================================
func _check_cue_mapping() -> void:
	var sf = _sensory_feedback_script.new()
	root.add_child(sf)
	sf.set_audio_enabled(false)

	# Known message types should map to non-empty cue names
	_assert_ne(
		sf.cue_for_message_type(&"combat_hit"),
		&"",
		"cue_for_message_type combat_hit should map to a non-empty cue"
	)
	_assert_ne(
		sf.cue_for_message_type(&"damage"),
		&"",
		"cue_for_message_type damage should map to a non-empty cue"
	)
	_assert_ne(
		sf.cue_for_message_type(&"magic"),
		&"",
		"cue_for_message_type magic should map to a non-empty cue"
	)
	_assert_ne(
		sf.cue_for_message_type(&"gold"),
		&"",
		"cue_for_message_type gold should map to a non-empty cue"
	)

	# Unknown message type should return empty StringName
	_assert_eq(
		sf.cue_for_message_type(&"unknown"),
		&"",
		"cue_for_message_type unknown should return empty StringName"
	)

	sf.queue_free()


# ======================================================================
# 2. Cue names completeness
# ======================================================================
func _check_cue_names() -> void:
	var sf = _sensory_feedback_script.new()
	root.add_child(sf)
	sf.set_audio_enabled(false)

	var cues: Array[StringName] = sf.get_cue_names()
	var required: Array[StringName] = [
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
	for cue: StringName in required:
		if not cue in cues:
			_fail("get_cue_names() missing required cue '%s'; found: %s" % [cue, str(cues)])

	if cues.is_empty():
		_fail("get_cue_names() returned empty array")

	sf.queue_free()


# ======================================================================
# 3. Audio stream properties
# ======================================================================
func _check_audio_stream() -> void:
	var sf = _sensory_feedback_script.new()
	root.add_child(sf)
	sf.set_audio_enabled(false)

	var stream: AudioStreamWAV = sf.get_cue_stream(&"combat_hit")
	if stream == null:
		_fail('get_cue_stream(&"combat_hit") returned null, expected AudioStreamWAV')

	if not stream is AudioStreamWAV:
		_fail("get_cue_stream returned %s, expected AudioStreamWAV" % stream.get_class())

	if stream.format != AudioStreamWAV.FORMAT_16_BITS:
		_fail(
			(
				"AudioStreamWAV format expected FORMAT_16_BITS (%d), got %d"
				% [AudioStreamWAV.FORMAT_16_BITS, stream.format]
			)
		)

	if stream.mix_rate != 22050:
		_fail("AudioStreamWAV mix_rate expected 22050, got %d" % stream.mix_rate)

	if stream.data.is_empty():
		_fail("AudioStreamWAV data is empty, expected procedural PCM samples")

	sf.queue_free()


# ======================================================================
# 4. Visual feedback lifecycle
# ======================================================================
func _check_visual_feedback() -> void:
	var sf = _sensory_feedback_script.new()
	root.add_child(sf)
	sf.set_audio_enabled(false)

	# Trigger a visual cue
	sf.trigger_cue(&"level")
	if not sf.has_active_visual_feedback():
		_fail('has_active_visual_feedback() should be true after trigger_cue(&"level")')

	# Simulate enough _process time to expire any reasonable visual duration.
	# Using cumulative 2.0 seconds which exceeds typical flash/vignette durations.
	sf._process(1.0)
	sf._process(1.0)

	if sf.has_active_visual_feedback():
		_fail("has_active_visual_feedback() should be false after 2.0s of _process")

	sf.queue_free()


# ======================================================================
# 5. Game scene integration
# ======================================================================
func _check_game_scene_integration() -> void:
	var gm: Node = root.get_node_or_null("/root/GameManager")
	if gm == null:
		_fail("GameManager autoload missing")
		return

	gm.prepare_character("debug", {})
	var game_scene: PackedScene = load("res://scenes/game.tscn")
	var game: Node = game_scene.instantiate()
	root.add_child(game)
	await process_frame

	var sf_node: Node = game.get_node_or_null("UI/SensoryFeedback")
	if sf_node == null:
		_fail("UI/SensoryFeedback node not found in game.tscn scene tree")
	else:
		print("  UI/SensoryFeedback found in game scene")

	# Cleanup
	gm.abandon_run()
	game.queue_free()
	await process_frame


# ======================================================================
# Assertion helpers
# ======================================================================
func _assert_eq(a, b, msg: String = "") -> void:
	if a != b:
		_fail("assert_eq failed: " + msg + " - expected '%s', got '%s'" % [str(b), str(a)])


func _assert_ne(a, b, msg: String = "") -> void:
	if a == b:
		_fail("assert_ne failed: " + msg + " - values are both '%s'" % [str(a)])


func _fail(message: String) -> void:
	printerr(message)
	quit(1)
