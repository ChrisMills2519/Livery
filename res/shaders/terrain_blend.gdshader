shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Blends four tiled ground surfaces through a hand-painted control map so the
// yard, path, training ground and arena grow into the grass instead of sitting
// on it as rectangles.
//
// The control map is sampled in world space and is linear data:
//   R = stable-yard dirt, G = path, B = training sand, A = arena sand.
// Grass is the remainder.  Detail textures keep their own tiling scale, so the
// blend does not sacrifice texel density.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D path_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D control_map : filter_linear_mipmap, repeat_disable;

uniform vec2 control_center = vec2(10.0, -5.0);
uniform vec2 control_size = vec2(128.0, 128.0);

uniform float grass_tile = 15.0;
uniform float dirt_tile = 2.1;
uniform float path_tile = 5.0;
uniform float sand_tile = 2.5;

uniform float blend_sharpness = 1.35;
uniform float normal_strength = 0.85;
uniform float macro_strength = 0.10;

uniform vec4 grass_tint : source_color = vec4(0.85, 0.95, 0.80, 1.0);
uniform vec4 dirt_tint : source_color = vec4(0.92, 0.80, 0.68, 1.0);
uniform vec4 path_tint : source_color = vec4(0.95, 0.90, 0.80, 1.0);
uniform vec4 sand_tint : source_color = vec4(0.89, 0.85, 0.76, 1.0);

varying vec3 world_pos;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


// VRAM-compressed normal maps (RGTC/ETC2) keep only the red and green
// channels, so the blue channel has to be rebuilt here instead of sampled.
vec3 sample_normal(sampler2D tex, vec2 uv) {
	vec2 xy = texture(tex, uv).rg * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 p = world_pos.xz;

	vec2 control_uv = (p - control_center) / control_size + 0.5;
	vec4 weights = texture(control_map, control_uv);
	// repeat_disable clamps at the border; the rest of the 200 m plane is
	// grass, so explicitly drop the painted layers outside the map.
	if (control_uv.x < 0.0 || control_uv.x > 1.0 || control_uv.y < 0.0 || control_uv.y > 1.0) {
		weights = vec4(0.0);
	}
	weights = pow(max(weights, vec4(0.0)), vec4(blend_sharpness));

	float painted = weights.r + weights.g + weights.b + weights.a;
	float grass_weight = max(0.0, 1.0 - painted);
	float total = max(painted + grass_weight, 1e-4);
	weights *= 1.0 / total;
	grass_weight *= 1.0 / total;

	// Low-frequency tint variation hides the repeat in the large dirt and sand
	// areas without another texture fetch.
	float macro = value_noise(p * 0.07) * 0.6 + value_noise(p * 0.23) * 0.4;
	macro = mix(1.0 - macro_strength, 1.0 + macro_strength, macro);

	vec3 grass = texture(grass_albedo, p / grass_tile).rgb * grass_tint.rgb;
	vec3 dirt = texture(dirt_albedo, p / dirt_tile).rgb * dirt_tint.rgb;
	vec3 path = texture(path_albedo, p / path_tile).rgb * path_tint.rgb;
	vec3 sand = texture(sand_albedo, p / sand_tile).rgb * sand_tint.rgb;

	vec3 albedo = grass * grass_weight
		+ dirt * weights.r
		+ path * weights.g
		+ sand * (weights.b + weights.a);
	ALBEDO = albedo * macro;
	ROUGHNESS = 0.96;
	SPECULAR = 0.18;
	METALLIC = 0.0;

	vec3 n_grass = sample_normal(grass_normal, p / grass_tile);
	vec3 n_dirt = sample_normal(dirt_normal, p / dirt_tile);
	vec3 n_path = sample_normal(path_normal, p / path_tile);
	vec3 n_sand = sample_normal(sand_normal, p / sand_tile);
	vec3 n = n_grass * grass_weight
		+ n_dirt * weights.r
		+ n_path * weights.g
		+ n_sand * (weights.b + weights.a);
	n.xy *= normal_strength;
	n = normalize(n);

	// NORMAL, TANGENT and BINORMAL are in view space here; combine them
	// explicitly instead of relying on the engine's normal-map conventions.
	NORMAL = normalize(TANGENT * n.x + BINORMAL * n.y + NORMAL * n.z);
}
