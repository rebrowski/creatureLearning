shader_type spatial;
// Gemeinsamer Shader aller Kreaturen. Farbe und Muster kommen aus Parametern,
// Körperteil-Infos aus den Vertex-Daten (siehe CreatureMeshBuilder).

render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 body_color : source_color = vec3(0.4, 0.6, 0.3);
// 0 = keins, 1 = Querstreifen, 2 = Flecken, 3 = Längsband
uniform int pattern_type = 0;
// Streifen/Flecken pro Meter
uniform float pattern_frequency = 4.0;
uniform float pattern_contrast = 0.5;

varying vec2 pattern_uv;
varying vec2 pattern_uv2;

void vertex() {
	pattern_uv = UV;
	pattern_uv2 = UV2;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float pattern_mask() {
	if (pattern_uv2.x < -500.0 || pattern_type == 0) {
		return 0.0;
	}
	if (pattern_type == 1) {
		float f = fract(pattern_uv.x * pattern_frequency);
		return smoothstep(0.55, 0.62, f) * (1.0 - smoothstep(0.88, 0.95, f));
	}
	if (pattern_type == 2) {
		vec2 cell_uv = pattern_uv * pattern_frequency * 1.2;
		vec2 cell = floor(cell_uv);
		vec2 offset = vec2(hash12(cell), hash12(cell + 17.0)) * 0.5 + 0.25;
		float d = length(fract(cell_uv) - offset);
		float present = step(0.35, hash12(cell + 5.0));
		return present * (1.0 - smoothstep(0.16, 0.22, d));
	}
	// Längsband etwas oberhalb der Mitte der Flanke
	float h = pattern_uv2.y;
	return 1.0 - smoothstep(0.18, 0.26, abs(h - 0.1));
}

void fragment() {
	vec3 base = COLOR.a > 0.5 ? body_color * COLOR.rgb : COLOR.rgb;
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 pattern_col = lum > 0.35 ? base * (1.0 - pattern_contrast * 0.75) : mix(base, vec3(1.0), pattern_contrast * 0.6);
	float m = COLOR.a > 0.5 ? pattern_mask() : 0.0;
	ALBEDO = mix(base, pattern_col, m);
	ROUGHNESS = COLOR.a > 0.5 ? 0.75 : 0.35;
}
