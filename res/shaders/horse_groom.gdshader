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

uniform float dirt_level = 1.0;
uniform float mask_view = 0.0;
uniform vec3 dirt_color : source_color = vec3(0.54, 0.45, 0.33);
uniform vec3 sheen_color : source_color = vec3(0.95, 0.88, 0.68);
uniform float sheen_strength = 0.24;
uniform float dirt_strength = 0.40;

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
	vec4 mask = texture(groom_mask, UV);
	float groomable = mask.a;
	float clean = clamp(mask.r * groomable, 0.0, 1.0);
	float polish = clamp(mask.g * groomable, 0.0, 1.0);
	float loosen = clamp(mask.b * groomable, 0.0, 1.0);

	vec3 base = texture(coat_texture, UV).rgb;

	// Fine, dusty speckle rather than the large blotches a low-frequency
	// noise produced on the flank.  The base texture already carries the coat
	// pattern, so the dirt layer stays deliberately even.
	float clump = value_noise(UV * 96.0) * 0.55 + value_noise(UV * 240.0) * 0.45;
	float dirt = clamp(dirt_level * (1.0 - clean) * (0.62 + 0.38 * clump), 0.0, 1.0);
	dirt = smoothstep(0.02, 0.98, dirt);

	vec3 colour = mix(base, dirt_color, dirt * dirt_strength);

	// Currying does not remove dirt; it lifts and breaks it up so the dandy
	// brush can take it away.  The visual difference is deliberately subtle.
	float lifted = loosen * (1.0 - clean);
	colour = mix(colour, colour * 1.12 + vec3(0.035, 0.028, 0.018), lifted * 0.22 * clump);

	// Clean coat returns to its original colour with a gentle lift.
	colour = mix(colour, colour * vec3(1.06, 1.035, 1.01), clean * 0.65);

	// The material is unlit, so the polished sheen is a fresnel lift rather
	// than a lighting response.
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	colour += sheen_color * polish * fresnel * sheen_strength;

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
