shader_type canvas_item;
render_mode unshaded;

uniform float far_blur_lod : hint_range(0.0, 3.0, 0.05) = 1.35;
uniform float near_blur_lod : hint_range(0.0, 3.0, 0.05) = 0.55;
uniform float saturation : hint_range(0.0, 1.0, 0.01) = 0.88;
uniform float brightness : hint_range(0.5, 1.0, 0.01) = 0.92;

void fragment() {
	float near_mix = smoothstep(0.55, 0.98, UV.y);
	float blur_lod = mix(far_blur_lod, near_blur_lod, near_mix);
	vec4 color = textureLod(TEXTURE, UV, blur_lod);
	float luminance = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	color.rgb = mix(vec3(luminance), color.rgb, saturation) * brightness;
	COLOR = color;
}
