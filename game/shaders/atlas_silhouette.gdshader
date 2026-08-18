shader_type canvas_item;

uniform vec4 silhouette_color : source_color = vec4(0.20, 0.30, 0.44, 1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(silhouette_color.rgb, source.a * silhouette_color.a);
}
