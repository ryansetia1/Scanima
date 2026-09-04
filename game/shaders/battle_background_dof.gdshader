shader_type canvas_item;
render_mode unshaded;

uniform float far_blur_lod : hint_range(0.0, 3.0, 0.05) = 1.35;
uniform float near_blur_lod : hint_range(0.0, 3.0, 0.05) = 0.55;
uniform float saturation : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform float brightness : hint_range(0.5, 1.0, 0.01) = 0.92;
uniform sampler2D day_texture : source_color, filter_linear_mipmap;
uniform float daylight_blend : hint_range(0.0, 1.0) = 0.0;
// Team Battle tween ini; Duel dan background chapter membiarkannya di 1.0.
uniform float camera_zoom : hint_range(1.0, 1.08, 0.001) = 1.0;
uniform float camera_pivot_y : hint_range(0.0, 1.0, 0.001) = 0.91;

void fragment() {
	float near_mix = smoothstep(0.55, 0.98, UV.y);
	float blur_lod = mix(far_blur_lod, near_blur_lod, near_mix);
	vec2 camera_pivot = vec2(0.5, camera_pivot_y);
	vec2 camera_uv = (UV - camera_pivot) / camera_zoom + camera_pivot;
	vec4 night_color = textureLod(TEXTURE, camera_uv, blur_lod);
	vec4 day_color = textureLod(day_texture, camera_uv, blur_lod);
	vec4 color = mix(night_color, day_color, daylight_blend);
	float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(luminance), color.rgb, saturation) * brightness;
	COLOR = color;
}
