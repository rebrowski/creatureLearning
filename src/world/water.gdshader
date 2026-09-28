shader_type spatial;
// Einfaches Wasser für Mobile: halbtransparent, leichte Wellen über die Normale.
render_mode blend_mix, cull_back, specular_schlick_ggx, depth_draw_opaque;

uniform vec3 shallow_color : source_color = vec3(0.25, 0.45, 0.45);
uniform vec3 deep_color : source_color = vec3(0.08, 0.2, 0.28);
uniform float alpha = 0.75;
uniform float flow_speed = 0.35;
// wird vom Wetter gesetzt (0..1): Regen macht das Wasser unruhiger
uniform float rain = 0.0;

varying float edge;

void vertex() {
	edge = UV.y;  // 0 = Mitte, 1 = Rand
}

void fragment() {
	vec2 p = UV2 * 0.6;
	float t = TIME * flow_speed;
	float w1 = sin(p.x * 3.1 + t * 2.0) * cos(p.y * 2.3 - t * 1.3);
	float w2 = sin((p.x + p.y) * 5.7 - t * 3.1) * (0.4 + rain);
	NORMAL_MAP = normalize(vec3(0.5 + 0.08 * w1 + 0.05 * w2, 0.5 + 0.08 * w2, 1.0));
	ALBEDO = mix(deep_color, shallow_color, smoothstep(0.2, 1.0, edge));
	ALPHA = alpha * (1.0 - smoothstep(0.85, 1.0, edge));
	ROUGHNESS = 0.08 + rain * 0.2;
	METALLIC = 0.0;
}
