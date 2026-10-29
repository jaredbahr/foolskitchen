shader_type spatial;
render_mode cull_back;

// Wall finishes (D26): a thin facing on a wall face, one material per look.
// Flat palette colours only, no textures (ART_STYLE section 3); the light
// comes from the scene, lit like the plain walls (roughness 0.9). Pattern
// numbers are WallStyleDef.Pattern: a new look is a new number here plus its
// data file (and WallThumbnail). UV is laid in world metres: x along the wall
// line, y up from the floor, so patterns line up from face to face.
// UV2 is the face's own 0..1 square, for the preview's outline.

uniform int pattern = 0;
uniform vec4 main_color : source_color = vec4(0.9, 0.84, 0.72, 1.0);
// Already resolved on the CPU: grout, mortar, stripes, or the paint above
// the panelling.
uniform vec4 accent_color : source_color = vec4(0.65, 0.6, 0.5, 1.0);
// A proposal (the Wall finish tool's drag, the paint hover): a thin outline.
uniform bool preview = false;
uniform vec4 preview_color : source_color = vec4(0.42, 0.67, 0.48, 1.0);

// Coverage of a line of half width `half_width` at distance `d` (metres),
// antialiased over `fw` (metres per pixel).
float line_cover(float d, float half_width, float fw) {
	return 1.0 - smoothstep(half_width - fw * 0.5, half_width + fw * 0.5, d);
}

// Fine detail fades when its period nears a few pixels (no shimmer far out).
float detail(float period, float fw) {
	return clamp(period / max(fw, 0.00001) * 0.5 - 0.5, 0.0, 1.0);
}

// 1: painted wood panelling to 0.46 m: boards 0.1 m wide with grooves, a
// skirting and a cap rail in shades of the main colour; accent paint above.
vec3 wainscot(vec2 p, vec3 base, vec3 above, float fw) {
	float top = 0.46;
	if (p.y > top) {
		return above;
	}
	float fade = detail(0.1, fw);
	vec3 colour = base;
	float board = fract(p.x / 0.1);
	float groove = min(board, 1.0 - board) * 0.1;
	colour = mix(colour, base * 0.78, line_cover(groove, 0.004, fw) * fade);
	if (p.y < 0.06) {
		colour = base * 0.88;
	}
	if (p.y > top - 0.045) {
		colour = base * 0.92;
		colour = mix(colour, base * 1.08, line_cover(abs(p.y - (top - 0.008)), 0.006, fw));
	}
	colour = mix(colour, base * 0.7, line_cover(abs(p.y - (top - 0.045)), 0.003, fw) * fade);
	return colour;
}

// 2: vertical stripes, a 0.12 m repeat: 0.07 main, 0.05 accent.
vec3 stripes(vec2 p, vec3 base, vec3 second, float fw) {
	float period = 0.12;
	float u = fract(p.x / period) * period;
	float band = smoothstep(0.07 - fw * 0.5, 0.07 + fw * 0.5, u) * (1.0 - smoothstep(period - fw * 0.5, period, u));
	return mix(mix(base, second, 0.4), mix(base, second, band), detail(period, fw));
}

// Running bond of `size` blocks with joints of half width `joint`.
vec3 bond(vec2 p, vec2 size, float joint, vec3 base, vec3 seam, float fw) {
	float row = floor(p.y / size.y);
	float u = p.x / size.x + mod(row, 2.0) * 0.5;
	vec2 f = vec2(fract(u), fract(p.y / size.y));
	vec2 d = min(f, 1.0 - f) * size;
	float cover = max(line_cover(d.x, joint, fw), line_cover(d.y, joint, fw));
	return mix(base, seam, cover * detail(size.y, fw));
}

void fragment() {
	vec3 base = main_color.rgb;
	vec3 accent = accent_color.rgb;
	vec2 p = UV;
	float fw = max(max(fwidth(p.x), fwidth(p.y)), 0.0001);
	vec3 colour = base;
	if (pattern == 1) {
		colour = wainscot(p, base, accent, fw);
	} else if (pattern == 2) {
		colour = stripes(p, base, accent, fw);
	} else if (pattern == 3) {
		// 3: subway tiles 0.15 x 0.075 m with thin grout.
		colour = bond(p, vec2(0.15, 0.075), 0.005, base, accent, fw);
	} else if (pattern == 4) {
		// 4: brick, 0.22 x 0.075 m with mortar joints.
		colour = bond(p + vec2(0.0, 0.02), vec2(0.22, 0.075), 0.007, base, accent, fw);
	}
	if (preview) {
		vec2 q = UV2;
		vec2 fq = max(vec2(fwidth(q.x), fwidth(q.y)), vec2(0.0001));
		vec2 edge = min(q, 1.0 - q) / fq;
		float rim = 1.0 - smoothstep(1.5, 3.0, min(edge.x, edge.y));
		colour = mix(colour, preview_color.rgb, rim);
	}
	ALBEDO = colour;
	ROUGHNESS = 0.9;
}
