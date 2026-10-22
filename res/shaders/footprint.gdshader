shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// Footprints are drawn as one small ground quad per hoof/foot landing and the
// trail node ring-buffers those quads in a single MultiMesh.
//
// The alpha-blended print is a dark, low-opacity stain: the ground texture stays
// visible through it, so a print reads as pressed-down earth on grass, dirt,
// path or sand rather than a flat brown decal.  Multiply blending would have
// been the natural choice, but this project's Compatibility renderer draws
// nothing at all with `blend_mul` (verified in artifacts/_dbg_fp_*.png), so the
// effect is built from ALPHA instead.
//
// No textures are involved.  The hoof wall, sole, heel gap and the boot's sole
// and tread bars are analytic, so the print stays crisp at any distance and
// costs one draw call for the whole trail.
//
// Per-instance data comes from the MultiMesh (use_custom_data = true):
//   INSTANCE_CUSTOM.x = birth time (seconds, same clock as `now`)
//   INSTANCE_CUSTOM.y = strength (0..1)
//   INSTANCE_CUSTOM.z = kind (0 = hoof, 1 = boot)
//   INSTANCE_CUSTOM.w = random seed (0..1)
// INSTANCE_CUSTOM is only readable in the vertex stage, so it is forwarded to
// the fragment stage through a varying.

uniform vec4 tint : source_color = vec4(0.20, 0.16, 0.12, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0) = 0.50;
uniform float lifetime = 40.0;
uniform float now = 0.0;

varying vec4 print_data;

// Signed distance to an ellipse: negative inside, zero on the rim.
float ellipse_sd(vec2 p, vec2 radius) {
	return length(p / radius) - 1.0;
}

void vertex() {
	print_data = INSTANCE_CUSTOM;
}

void fragment() {
	// Quad UV in -1..1, with +y pointing along the print's length (the toe).
	vec2 q = (UV - 0.5) * 2.0;

	float age = clamp((now - print_data.x) / max(lifetime, 0.001), 0.0, 1.0);
	float life = 1.0 - age;
	float strength = print_data.y;
	float seed = print_data.w;
	float is_boot = step(0.5, print_data.z);

	// --- hoof: a thick wall, a softer sole inside it, an open heel ----------
	float hoof_outer = ellipse_sd(q, vec2(0.88, 0.94));
	float hoof_inner = ellipse_sd(q - vec2(0.0, 0.12), vec2(0.58, 0.64));
	float hoof_wall = smoothstep(0.10, -0.05, hoof_outer) * smoothstep(-0.03, 0.12, hoof_inner);
	float hoof_sole = smoothstep(0.02, -0.30, hoof_outer) * 0.42;
	// The heel is open and the frog splits it, so the print reads as a hoof
	// rather than a round dent.
	float heel_open = smoothstep(-0.30, -0.92, q.y);
	float frog = 1.0 - 0.45 * smoothstep(0.22, 0.02, abs(q.x)) * smoothstep(0.10, -0.55, q.y);
	float hoof_mask = max(hoof_wall * (1.0 - 0.80 * heel_open), hoof_sole * frog);

	// --- boot: a sole outline, wider toe, heel block, tread bars ------------
	vec2 boot_q = q * vec2(0.94, 1.0);
	float boot_edge = ellipse_sd(boot_q + vec2(0.0, 0.04), vec2(0.70, 0.95));
	float boot_shape = smoothstep(0.14, -0.10, boot_edge);
	// The toe is broader than the heel, so pinch the rear of the outline.
	boot_shape *= mix(0.62, 1.0, smoothstep(-0.95, 0.25, q.y));
	float bands = abs(sin((q.y + 0.08 + seed * 0.12) * 13.0));
	float tread = mix(0.66, 1.0, smoothstep(0.25, 0.85, bands));
	float heel_block = smoothstep(-0.45, -0.85, q.y) * smoothstep(0.75, 0.95, abs(q.x));
	float boot_mask = boot_shape * tread * (1.0 + 0.25 * heel_block);

	float mask = mix(hoof_mask, boot_mask, is_boot);
	float alpha = clamp(mask * life * strength * tint_strength, 0.0, 1.0);
	// Per-print variation keeps a trail from looking rubber-stamped.
	alpha *= 0.90 + 0.10 * seed;

	ALBEDO = tint.rgb;
	ALPHA = alpha;
}
