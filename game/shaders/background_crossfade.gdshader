shader_type canvas_item;
render_mode unshaded;

uniform sampler2D day_texture : source_color, filter_linear_mipmap;
uniform float daylight_blend : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 night_color = texture(TEXTURE, UV);
	vec4 day_color = texture(day_texture, UV);
	COLOR = mix(night_color, day_color, daylight_blend);
}
