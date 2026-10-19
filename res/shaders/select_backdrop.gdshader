shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 top_color : source_color = vec3(0.15, 0.22, 0.17);
uniform vec3 bottom_color : source_color = vec3(0.035, 0.052, 0.041);
uniform vec3 glow_color : source_color = vec3(0.62, 0.78, 0.52);
uniform float glow_strength = 0.16;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float t = clamp(local_pos.y / 10.0 + 0.5, 0.0, 1.0);
	vec3 base = mix(bottom_color, top_color, t);

	vec2 d = UV - vec2(0.5);
	float vignette = smoothstep(0.78, 0.18, length(d * vec2(1.15, 1.0)));
	base *= mix(0.55, 1.0, vignette);

	float glow = smoothstep(0.62, 0.0, distance(UV, vec2(0.56, 0.42)));
	base += glow_color * glow * glow_strength;

	ALBEDO = base;
}
