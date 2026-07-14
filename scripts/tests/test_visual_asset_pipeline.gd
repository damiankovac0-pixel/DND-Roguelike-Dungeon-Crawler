## Regression coverage for explicit visual assets and generated Godot catalogues.
##
## Run with:
##   /usr/local/bin/godot --headless --path . --script \
##     res://scripts/tests/test_visual_asset_pipeline.gd
extends SceneTree

const MANIFEST_PATH: String = "res://assets/visual_assets.json"
const ATTRIBUTION_PATH: String = "res://assets/visual_asset_attribution.json"
const REQUIRED_CATEGORIES: Array[String] = ["terrain", "actor", "boss", "object", "effect"]
const REQUIRED_ANIMATIONS: Array[StringName] = [
	&"idle", &"move", &"attack", &"cast", &"hurt", &"death"
]

var _failed: bool = false
var _manifest: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_load_manifest()
	if _failed:
		return
	_check_explicit_assets()
	if _failed:
		return
	_check_generated_attribution()
	if _failed:
		return
	_check_generated_catalogues()
	if _failed:
		return
	print("Visual asset pipeline checks passed")
	quit(0)


func _load_manifest() -> void:
	_expect(FileAccess.file_exists(MANIFEST_PATH), "Visual asset manifest is missing")
	if _failed:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_expect(parsed is Dictionary, "Visual asset manifest must be valid JSON")
	if parsed is Dictionary:
		_manifest = parsed
	_expect_equal(int(_manifest.get("schema_version", 0)), 1, "Manifest schema drifted")
	_expect_equal(int(_manifest.get("catalog_version", 0)), 1, "Catalogue schema drifted")


func _check_explicit_assets() -> void:
	var asset_values: Variant = _manifest.get("assets", [])
	_expect(asset_values is Array, "Manifest assets must be an array")
	if asset_values is not Array:
		return
	var seen_ids: Dictionary = {}
	var seen_categories: Dictionary = {}
	var licenses: Dictionary = _dictionary_or_empty(_manifest.get("licenses", {}))
	for asset_value: Variant in asset_values:
		_expect(asset_value is Dictionary, "Every visual asset entry must be a dictionary")
		if asset_value is not Dictionary:
			continue
		var asset: Dictionary = asset_value
		var asset_id: String = str(asset.get("id", ""))
		var category: String = str(asset.get("category", ""))
		var source_path: String = str(asset.get("source_path", ""))
		var runtime_path: String = str(asset.get("runtime_path", ""))
		var license_id: String = str(asset.get("license_id", ""))
		_expect(not asset_id.is_empty(), "Visual asset ID is missing")
		_expect(not seen_ids.has(asset_id), "Visual asset IDs must be unique")
		seen_ids[asset_id] = true
		seen_categories[category] = true
		_expect(
			not source_path.begins_with("res://"),
			"%s source path must be repository-relative" % asset_id
		)
		_expect(
			not runtime_path.begins_with("res://"),
			"%s runtime path must be repository-relative" % asset_id
		)
		_expect(
			FileAccess.file_exists("res://" + source_path), "%s source file is missing" % asset_id
		)
		_expect(
			FileAccess.file_exists("res://" + runtime_path), "%s runtime file is missing" % asset_id
		)
		_expect(licenses.has(license_id), "%s has no declared licence" % asset_id)
		_expect(
			not str(asset.get("attribution", "")).is_empty(), "%s has no attribution" % asset_id
		)
		_check_asset_texture(asset)
	for category: String in REQUIRED_CATEGORIES:
		_expect(seen_categories.has(category), "Required visual category is missing: %s" % category)
	print("  manifest resolves explicit terrain, actor, boss, object, and effect resources")


func _check_asset_texture(asset: Dictionary) -> void:
	var asset_id: String = str(asset.get("id", ""))
	var runtime_path: String = "res://" + str(asset.get("runtime_path", ""))
	var texture: Resource = load(runtime_path)
	_expect(texture is Texture2D, "%s runtime file must import as Texture2D" % asset_id)
	if texture is not Texture2D:
		return
	var expected_size: Array = _array_or_empty(asset.get("expected_size", []))
	_expect_equal(expected_size.size(), 2, "%s expected size must have two components" % asset_id)
	if expected_size.size() != 2:
		return
	var expected: Vector2i = Vector2i(int(expected_size[0]), int(expected_size[1]))
	_expect_equal(
		Vector2i(texture.get_size()), expected, "%s imported texture dimensions drifted" % asset_id
	)


func _check_generated_attribution() -> void:
	_expect(FileAccess.file_exists(ATTRIBUTION_PATH), "Generated visual attribution is missing")
	if _failed:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ATTRIBUTION_PATH))
	_expect(parsed is Dictionary, "Generated visual attribution must be valid JSON")
	if parsed is not Dictionary:
		return
	var attribution: Dictionary = parsed
	var records: Array = _array_or_empty(attribution.get("assets", []))
	var manifest_assets: Array = _array_or_empty(_manifest.get("assets", []))
	_expect_equal(
		records.size(), manifest_assets.size(), "Attribution must cover every visual asset"
	)
	var attributed_ids: Dictionary = {}
	for record_value: Variant in records:
		_expect(record_value is Dictionary, "Attribution records must be dictionaries")
		if record_value is not Dictionary:
			continue
		var record: Dictionary = record_value
		var asset_id: String = str(record.get("id", ""))
		var digest: String = str(record.get("sha256", ""))
		attributed_ids[asset_id] = true
		_expect(
			digest.length() == 64 and _is_lowercase_hex(digest),
			"%s attribution hash is invalid" % asset_id
		)
		_expect(
			str(record.get("runtime_path", "")).begins_with("res://"),
			"%s runtime attribution path is invalid" % asset_id
		)
	for asset_value: Variant in manifest_assets:
		if asset_value is Dictionary:
			_expect(
				attributed_ids.has(str(asset_value.get("id", ""))),
				"Visual asset attribution is incomplete"
			)
	print("  generated attribution covers every source with deterministic content hashes")


func _check_generated_catalogues() -> void:
	var catalogue_values: Array = _array_or_empty(_manifest.get("catalogs", []))
	_expect(not catalogue_values.is_empty(), "Manifest must generate at least one Godot catalogue")
	var actor_catalogue: Resource
	for catalogue_value: Variant in catalogue_values:
		_expect(catalogue_value is Dictionary, "Catalogue definitions must be dictionaries")
		if catalogue_value is not Dictionary:
			continue
		var catalogue_definition: Dictionary = catalogue_value
		var catalogue_path: String = "res://" + str(catalogue_definition.get("path", ""))
		var catalogue: Resource = load(catalogue_path)
		_expect(catalogue != null, "Generated catalogue failed to load: %s" % catalogue_path)
		if catalogue == null:
			continue
		_expect(catalogue.has_method(&"validate"), "Generated catalogue must expose validate()")
		_expect_equal(
			int(catalogue.get("catalog_version")), 1, "Generated catalogue version drifted"
		)
		_expect_equal(str(catalogue.call(&"validate")), "", "Generated catalogue validation failed")
		var invalid_catalogue: Resource = catalogue.duplicate()
		invalid_catalogue.set("catalog_version", 2)
		_expect(
			not str(invalid_catalogue.call(&"validate")).is_empty(),
			"Unsupported catalogue versions must fail safely"
		)
		if str(catalogue_definition.get("id", "")) == "actors":
			actor_catalogue = catalogue
	_check_animation_contract(actor_catalogue)
	print("  generated catalogues load, validate dimensions, and reject schema drift")


func _check_animation_contract(actor_catalogue: Resource) -> void:
	_expect(actor_catalogue != null, "Generated actor catalogue is missing")
	if actor_catalogue == null:
		return
	var frames: SpriteFrames = actor_catalogue.call(
		&"sprite_frames_for", {"visual_id": &"actor/player", "kind": &"player", "is_boss": false}
	)
	_expect(frames != null, "Actor catalogue failed to build SpriteFrames")
	if frames == null:
		return
	for animation: StringName in REQUIRED_ANIMATIONS:
		_expect(frames.has_animation(animation), "Actor animation is missing: %s" % animation)
		_expect_equal(
			frames.get_frame_count(animation),
			2,
			"Actor animation frame count drifted: %s" % animation
		)


func _array_or_empty(value: Variant) -> Array:
	return value if value is Array else []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _is_lowercase_hex(value: String) -> bool:
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_fail(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected and not _failed:
		_fail("%s: got %s, expected %s" % [message, actual, expected])


func _fail(message: String) -> void:
	_failed = true
	printerr(message)
	quit(1)
