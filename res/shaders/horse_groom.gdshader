shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Horse coat with a dynamic UV-space groom mask.
//   R = clean / dirt removed
//   G = polished / shine
//   B = curried / loosened
//   A = groomable surface (static, baked from the mesh)
//
// The imported horse material is unlit, so the shader keeps that look and
// fakes the soft sheen with a view-dependent fresnel instead of introducing
// a lit material that would change the established art direction.

uniform sampler2D coat_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D groom_mask : filter_linear, repeat_disable;
// Baked zone ids: 1 coat, 2 leg, 3 face, 4 hoof, 5 mane, 6 tail.  Used by the
// tool-change glow so a player can see exactly which parts a brush works on.
uniform sampler2D zone_map : filter_nearest, repeat_disable;

uniform float dirt_level = 1.0;
uniform float mask_view = 0.0;
uniform int highlight_mask = 0;
uniform float highlight_strength = 0.0;
// 1 = the tool only works on clean coat, so dirty areas glow fainter.
uniform float highlight_clean_soften = 0.0;
uniform vec3 highlight_color : source_color = vec3(0.55, 0.90, 1.0);
// 1 = sample the groom mask with the split TEXCOORD_1 set (separate left and
// right texels); 0 = fall back to TEXCOORD_0 for meshes without the split.
uniform float use_uv2 = 1.0;
uniform vec3 dirt_color : source_color = vec3(0.16, 0.13, 0.10);
uniform vec3 sheen_color : source_color = vec3(0.95, 0.88, 0.68);
uniform float sheen_strength = 0.50;
uniform float dirt_strength = 0.85;

varying vec3 world_normal;


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


void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec2 groom_uv = mix(UV, UV2, use_uv2);
	vec4 mask = texture(groom_mask, groom_uv);
	float groomable = mask.a;
	float clean = clamp(mask.r * groomable, 0.0, 1.0);
	float polish = clamp(mask.g * groomable, 0.0, 1.0);
	float loosen = clamp(mask.b * groomable, 0.0, 1.0);

	vec3 base = texture(coat_texture, UV).rgb;

	// Three octaves: a broad patchiness so the horse reads grubby at a glance,
	// then fine speckle for the dusty grain on top.
	float clump = value_noise(UV * 24.0) * 0.40 + value_noise(UV * 96.0) * 0.35 + value_noise(UV * 240.0) * 0.25;
	float dirt = clamp(dirt_level * (1.0 - clean) * (0.55 + 0.45 * clump), 0.0, 1.0);
	dirt = smoothstep(0.02, 0.98, dirt);

	// Dirt both tint and darken the coat so it is unmistakable against the
	// clean, slightly lifted coat underneath.
	vec3 colour = mix(base * (1.0 - 0.22 * dirt), dirt_color, dirt * dirt_strength);

	// Currying lifts and breaks up the dirt so the dandy brush can take it
	// away.  It reads as a damp, darkened coat so the first tool gives
	// immediate feedback even before any dirt is removed.
	float lifted = loosen * (1.0 - clean);
	colour = mix(colour, colour * vec3(0.72, 0.70, 0.66), lifted * 0.45);

	// Clean coat returns to its original colour with a clear lift.
	colour = mix(colour, colour * vec3(1.14, 1.09, 1.02), clean);

	// The material is unlit, so the polished sheen is a fresnel lift rather
	// than a lighting response.  A broader falloff lets the shine read across
	// the body instead of only on the silhouette.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	colour += sheen_color * polish * fresnel * sheen_strength;

	// Tool-change glow.  The zone map is a nearest-filtered id map, so a soft
	// tint can cover the whole brushable area without hiding the coat detail.
	float zone_id = floor(texture(zone_map, groom_uv).r * 255.0 + 0.5);
	bool zone_allowed = false;
	if (zone_id > 0.5 && zone_id < 6.5) {
		int zone = int(zone_id);
		zone_allowed = (highlight_mask & (1 << zone)) != 0;
	}
	if (highlight_strength > 0.001 && zone_allowed && mask_view < 0.5) {
		// Hoof texels have no groomable alpha, so they bypass that gate.
		float gate = zone_id > 3.5 ? 1.0 : groomable;
		// A polish-only brush lights its area, but fainter where the coat is
		// still dirty, so the player can see where it can actually work.
		float soften = mix(1.0, mix(0.35, 1.0, smoothstep(0.0, 0.6, clean)), highlight_clean_soften);
		float pulse = 0.78 + 0.22 * sin(TIME * 7.0);
		float glow = highlight_strength * pulse * gate * soften;
		float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.4);
		colour = mix(colour, highlight_color, glow * 0.12);
		colour += highlight_color * glow * (0.02 + rim * 0.16);
	}

	if (mask_view > 0.5) {
		vec3 overlay = vec3(0.07, 0.075, 0.065);
		if (groomable > 0.5) {
			overlay = vec3(0.34, 0.22, 0.12);
			overlay = mix(overlay, vec3(0.95, 0.60, 0.16), loosen);
			overlay = mix(overlay, vec3(0.24, 0.84, 0.40), clean);
			overlay = mix(overlay, vec3(1.0, 0.94, 0.62), polish);
		}
		// Mostly flat so the painted regions read at a glance; a little of
		// the coat shading keeps the horse's form from disappearing.
		colour = mix(overlay, colour, 0.10);
	}

	ALBEDO = colour;
}
