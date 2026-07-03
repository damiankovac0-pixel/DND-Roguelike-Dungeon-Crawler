@tool
class_name RarityShimmerEffect
extends RichTextEffect
## Custom BBCode effect for high-rarity item names.
##
## Uses color travel and tiny positional lift instead of opacity fades, so
## the text stays readable while still feeling enchanted.

var bbcode: String = "rarity_shimmer"


func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var base_color: Color = _color_param(char_fx.env, "base", char_fx.color)
	var accent_color: Color = _color_param(char_fx.env, "accent", Color.WHITE)
	var speed: float = _float_param(char_fx.env, "speed", 2.2)
	var spread: float = _float_param(char_fx.env, "spread", 0.55)
	var intensity: float = clampf(_float_param(char_fx.env, "intensity", 0.55), 0.0, 1.0)
	var lift: float = maxf(0.0, _float_param(char_fx.env, "lift", 0.0))
	var phase: float = char_fx.elapsed_time * speed * TAU + float(char_fx.relative_index) * spread
	var crest: float = pow((sin(phase) + 1.0) * 0.5, 3.0)
	var shimmer_amount: float = clampf(crest * intensity, 0.0, 1.0)

	char_fx.color = base_color.lerp(accent_color, shimmer_amount)
	if not char_fx.outline and lift > 0.0:
		var offset: Vector2 = char_fx.offset
		offset.y += sin(phase * 0.7) * lift
		char_fx.offset = offset
	return true


static func _color_param(env: Dictionary, key: String, fallback: Color) -> Color:
	var value: Variant = env.get(key, fallback)
	if value is Color:
		return value
	return fallback


static func _float_param(env: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = env.get(key, fallback)
	if value is float or value is int:
		return float(value)
	return fallback
