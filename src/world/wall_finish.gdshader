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
// The shell's own wall boxes on a lot whose default finish is a pattern (log walls,
// #611): the pattern is laid from world position instead of UV (x along whichever
// horizontal axis the face runs, y up), so it lines up with the facings.
uniform bool world_space = false;

varying vec2 world_p;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 facing = abs(mat3(MODEL_MATRIX) * NORMAL);
	world_p = vec2(facing.x > facing.z ? world.z : world.x, world.y);
}

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

// 5: log wall: round logs 0.14 m high, laid flat-shaded like a low-poly log (a lit
// upper facet, the face, a shaded under facet), a thin chink line between them and
// a small step of tone from log to log.
vec3 logs(vec2 p, vec3 base, vec3 chink, float fw) {
	float course = 0.14;
	float row = floor(p.y / course);
	float t = fract(p.y / course);
	float tone = 0.95 + 0.08 * fract(sin(row * 12.9898) * 43758.5453);
	vec3 colour = base * tone;
	float fade = detail(course, fw);
	colour = mix(colour, base * tone * 1.1, step(0.66, t) * fade);
	colour = mix(colour, base * tone * 0.8, (1.0 - step(0.24, t)) * fade);
	float seam = min(t, 1.0 - t) * course;
	return mix(colour, chink, line_cover(seam, 0.006, fw) * fade);
}

// 6: a country mill's wall (#613): rubble stone to 0.78 m in courses of mixed
// heights, each stone its own tone with pale mortar round it; an oak sill beam;
// then upright timber boards (the accent) to the top, each with a lit edge.
vec3 mill(vec2 p, vec3 base, vec3 timber, float fw) {
	float stone_top = 0.78;
	float beam_top = 0.86;
	if (p.y < stone_top) {
		// Courses: three heights in turn, so the stone reads as laid by hand.
		float course = floor(p.y / 0.13);
		float lift = fract(p.y / 0.13);
		float tall = 0.13;
		float row_seed = fract(sin(course * 17.31) * 4375.85);
		float length = 0.17 + 0.13 * row_seed;
		float u = p.x / length + row_seed * 3.7;
		float stone = floor(u);
		float h = fract(sin(stone * 12.9898 + course * 78.233) * 43758.5453);
		// A short stone now and then: a vertical joint mid-stone.
		float f = fract(u);
		vec2 d = vec2(min(f, 1.0 - f) * length, min(lift, 1.0 - lift) * tall);
		if (h > 0.72) {
			d.x = min(d.x, abs(f - 0.5) * length);
		}
		vec3 tone = base * (0.86 + 0.2 * h);
		// The lit top edge and the shaded foot of each stone.
		tone *= lift > 0.78 ? 1.07 : (lift < 0.18 ? 0.9 : 1.0);
		float fade = detail(0.1, fw);
		vec3 mortar = min(base * 1.22, vec3(1.0));
		float cover = max(line_cover(d.x, 0.009, fw), line_cover(d.y, 0.009, fw));
		return mix(mix(base, tone, fade), mortar, cover * fade);
	}
	if (p.y < beam_top) {
		float t = (p.y - stone_top) / (beam_top - stone_top);
		vec3 beam = timber * (t > 0.7 ? 1.12 : (t < 0.25 ? 0.72 : 0.92));
		return beam;
	}
	// Boards 0.11 m wide, a lit left edge and a dark gap.
	float board = fract(p.x / 0.11);
	float fade = detail(0.11, fw);
	float n = floor(p.x / 0.11);
	vec3 colour = timber * (0.94 + 0.1 * fract(sin(n * 91.7) * 4375.85));
	colour = mix(colour, timber * 1.16, (1.0 - step(0.12, board)) * fade);
	return mix(colour, timber * 0.55, line_cover(min(board, 1.0 - board) * 0.11, 0.005, fw) * fade);
}

// 7: architectural concrete panels (#618): stack-bonded 0.5 x 0.7 m panels (two
// courses to the top of a wall), each a touch its own tone and paler than the main
// colour, with a dark recessed reveal (the accent) round it, a lit chamfer on its top
// and left edges and a shaded one on its bottom and right (light from the upper
// left), and four form-tie holes.
vec3 concrete(vec2 p, vec3 base, vec3 reveal, float fw) {
	vec2 size = vec2(0.5, 0.7);
	vec2 cell = floor(p / size);
	vec2 f = fract(p / size) * size;
	float h = fract(sin(cell.x * 12.9898 + cell.y * 78.233) * 43758.5453);
	// Cast concrete reads pale: the face sits a step above the main colour.
	vec3 colour = base * (1.26 + 0.06 * h);
	float fade = detail(0.1, fw);
	// The chamfers: 0.022 m bands just inside the reveal, lit on the left and top.
	float lit = max(1.0 - step(0.022, f.x), 1.0 - step(0.022, size.y - f.y));
	float shade = max(1.0 - step(0.022, size.x - f.x), 1.0 - step(0.022, f.y));
	colour = mix(colour, base * 1.42, lit * fade);
	colour = mix(colour, base * 1.06, shade * (1.0 - lit) * fade);
	// Four tie holes, 0.125 m in from the sides and 0.175 m from top and bottom.
	vec2 tie = vec2(f.x < size.x * 0.5 ? 0.125 : size.x - 0.125, f.y < size.y * 0.5 ? 0.175 : size.y - 0.175);
	float hole = length(f - tie);
	colour = mix(colour, reveal * 0.92, line_cover(hole, 0.011, fw) * detail(0.06, fw));
	vec2 d = min(f, size - f);
	float seam = max(line_cover(d.x, 0.007, fw), line_cover(d.y, 0.007, fw));
	return mix(colour, reveal * 0.85, seam * detail(0.05, fw));
}

// 8: whitewashed rubble (#380): lime wash over rough stone courses about 0.13 m
// high, each stone a touch its own tone with a lit top edge and soft, wash-filled
// joints, over a tarred plinth (the accent) to 0.16 m with a pale drip edge. Lime
// wash reads paler than paint: the face sits a step above the main colour.
vec3 whitewash(vec2 p, vec3 base, vec3 plinth, float fw) {
	float foot = 0.16;
	if (p.y < foot) {
		return mix(plinth, plinth * 1.3, 1.0 - step(0.018, foot - p.y));
	}
	float course = 0.13;
	float row = floor((p.y - foot) / course);
	float width = 0.24 + 0.1 * fract(sin(row * 17.1) * 913.7);
	float x = p.x / width + fract(sin(row * 41.3) * 4375.85);
	float h = fract(sin(floor(x) * 12.9898 + row * 78.233) * 43758.5453);
	vec3 colour = base * (1.12 + 0.05 * h);
	float fade = detail(0.1, fw);
	vec2 f = vec2(fract(x) * width, mod(p.y - foot, course));
	colour = mix(colour, base * 1.2, (1.0 - step(0.02, course - f.y)) * fade);
	vec2 d = min(f, vec2(width, course) - f);
	float joint = max(line_cover(d.x, 0.006, fw), line_cover(d.y, 0.006, fw));
	return mix(colour, base * 0.94, joint * fade * 0.8);
}

void fragment() {
	vec3 base = main_color.rgb;
	vec3 accent = accent_color.rgb;
	vec2 p = world_space ? world_p : UV;
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
	} else if (pattern == 5) {
		colour = logs(p, base, accent, fw);
	} else if (pattern == 6) {
		colour = mill(p, base, accent, fw);
	} else if (pattern == 7) {
		colour = concrete(p, base, accent, fw);
	} else if (pattern == 8) {
		colour = whitewash(p, base, accent, fw);
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
