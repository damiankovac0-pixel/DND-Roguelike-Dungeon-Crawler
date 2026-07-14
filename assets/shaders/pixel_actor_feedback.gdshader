shader_type canvas_item;
render_mode unshaded;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float desaturate_amount : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_multiplier : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 pixel = texture(TEXTURE, UV) * COLOR;
	float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
	pixel.rgb = mix(pixel.rgb, vec3(luminance), desaturate_amount);
	pixel.rgb = mix(pixel.rgb, flash_color.rgb, flash_amount * pixel.a);
	pixel.a *= alpha_multiplier;
	COLOR = pixel;
}
