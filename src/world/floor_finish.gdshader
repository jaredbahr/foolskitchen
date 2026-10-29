shader_type spatial;
render_mode cull_back;

// The shop floor (D25): one mesh, one material. A per-cell data texture picks
// each cell's pattern and colours; patterns are laid out in world space, so a
// floor type lines up across cells and rooms. Flat palette colours only, no
// textures (ART_STYLE section 3). Pattern numbers are FloorStyleDef.Pattern:
// a new floor look is a new number here plus its data file.
//
// Data texture (RGBA8, one texel per grid cell from map_origin):
//   R pattern, G base colour index, B accent colour index (0 = a darker shade
//   of the base colour), A threshold mask (1 west, 2 north, 4 east, 8 south:
//   the neighbour there is a different floor type).
// Colour index 0 is floor_color (the shop's own floor paint), 1.. are palette.

const int PALETTE_SIZE = 32;

// Warm placeholder palette; world-space spacing stays 0.5 m at every zoom.
uniform vec4 floor_color : source_color = vec4(0.58, 0.48, 0.34, 1.0);
uniform vec4 grid_color : source_color = vec4(0.28, 0.22, 0.15, 1.0);
uniform float cell_size : hint_range(0.1, 2.0) = 0.5;
uniform float line_width : hint_range(0.005, 0.1) = 0.012;
uniform bool grid_visible = true;
uniform sampler2D finish_map : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(0, 0);
// Zero: no map, every cell is the legacy planks in floor_color.
uniform ivec2 map_size = ivec2(0, 0);
uniform vec4 palette[PALETTE_SIZE] : source_color;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

// Coverage of a line of half width `half_width` at distance `d` (metres),
// antialiased over `fw` (metres per pixel).
float line_cover(float d, float half_width, float fw) {
	return 1.0 - smoothstep(half_width - fw * 0.5, half_width + fw * 0.5, d);
}

// Fine detail fades out when its period gets close to a few pixels, so far
// zoom shows the average colour instead of shimmer.
float detail(float period, float fw) {
	return clamp(period / max(fw, 0.00001) * 0.25 - 0.75, 0.0, 1.0);
}

vec3 colour_at(int index, vec3 fallback) {
	if (index <= 0) {
		return fallback;
	}
	return palette[clamp(index, 0, PALETTE_SIZE - 1)].rgb;
}

// 1: narrow planks, 0.125 m boards along x, staggered butt joints.
vec3 narrow_planks(vec2 p, vec3 base, vec3 seam, float fw) {
	float width = 0.125;
	float board_length = 0.75;
	float row = floor(p.y / width);
	float across = fract(p.y / width);
	float u = (p.x + hash12(vec2(row, 7.0)) * board_length) / board_length;
	float board = floor(u);
	float along = fract(u);
	float fade = detail(width, fw);
	vec3 colour = base * (1.0 + (hash12(vec2(row, board)) - 0.5) * 0.07 * fade);
	float d_long = min(across, 1.0 - across) * width;
	float d_butt = min(along, 1.0 - along) * board_length;
	float cover = max(line_cover(d_long, 0.005, fw), line_cover(d_butt, 0.004, fw));
	return mix(colour, seam, cover * fade);
}

// 2: herringbone, 4:1 boards 0.0625 m wide, turned 45 degrees so the
// zigzag runs along x.
vec3 herringbone(vec2 p, vec3 base, vec3 seam, float fw) {
	float width = 0.0625;
	float n = 4.0;
	vec2 q = vec2(p.x + p.y, p.y - p.x) * 0.70710678 / width;
	float row = floor(q.y);
	float u = mod(q.x - row, 2.0 * n);
	float along;
	float across;
	vec2 id;
	float turn;
	if (u < n) {
		along = u;
		across = fract(q.y);
		id = vec2(row, floor((q.x - row) / (2.0 * n)));
		turn = 0.0;
	} else {
		float column = floor(q.x);
		along = mod(q.y - (column - 2.0 * n + 1.0), 2.0 * n);
		across = fract(q.x);
		id = vec2(column + 101.0, floor((q.y - column + 2.0 * n - 1.0) / (2.0 * n)));
		turn = 1.0;
	}
	float fade = detail(width * 1.414, fw);
	float shade = 1.0 + ((hash12(id) - 0.5) * 0.08 + (turn - 0.5) * 0.04) * fade;
	vec3 colour = base * shade;
	float d_side = min(across, 1.0 - across) * width;
	float d_end = min(along, n - along) * width;
	float cover = max(line_cover(d_side, 0.003, fw), line_cover(d_end, 0.003, fw));
	return mix(colour, seam, cover * fade * 0.85);
}

// 3: checker, 0.25 m squares (two per cell side) in base and accent.
vec3 checker(vec2 p, vec3 base, vec3 second, float fw) {
	float size = 0.25;
	vec2 square = floor(p / size);
	float odd = mod(square.x + square.y, 2.0);
	vec2 f = fract(p / size);
	float d = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * size;
	float fade = detail(size, fw);
	vec3 colour = mix(base, second, mix(0.5, odd, fade));
	return mix(colour, mix(base, second, 0.5) * 0.85, line_cover(d, 0.0025, fw) * fade * 0.6);
}

// 4: small square tiles, 0.125 m, with grout lines.
vec3 small_tiles(vec2 p, vec3 base, vec3 grout, float fw) {
	float size = 0.125;
	vec2 tile = floor(p / size);
	vec2 f = fract(p / size);
	float fade = detail(size, fw);
	vec3 colour = base * (1.0 + (hash12(tile) - 0.5) * 0.05 * fade);
	vec2 d = min(f, 1.0 - f) * size;
	float cover = max(line_cover(d.x, 0.005, fw), line_cover(d.y, 0.005, fw));
	return mix(colour, grout, cover * fade);
}

// 5: regular hexagons, 0.125 m between opposite parallel edges.
// Two interleaved rectangular centre lattices; do not restart at cell edges.
vec3 hex_tiles(vec2 p, vec3 base, vec3 grout, float fw) {
	float size = 0.125;
	vec2 period = vec2(1.0, 1.73205081);
	vec2 a = mod(p / size + period * 0.5, period) - period * 0.5;
	vec2 b = mod(p / size, period) - period * 0.5;
	vec2 q = dot(a, a) < dot(b, b) ? a : b;
	vec2 normal = abs(q.x) > dot(abs(q), vec2(0.5, 0.8660254))
		? vec2(sign(q.x), 0.0) : sign(q) * vec2(0.5, 0.8660254);
	float d = (0.5 - dot(q, normal)) * size;
	float shade = dot(normal, vec2(1.0)) > 0.0 ? 0.65 : 0.82;
	return mix(base, grout * shade, line_cover(d, 0.003, fw) * detail(size, fw));
}

// 6: 0.25 m square pavers, each row offset by half a paver.
vec3 terracotta(vec2 p, vec3 base, vec3 joint, float fw) {
	float size = 0.25;
	float row = floor(p.y / size);
	vec2 f = fract(vec2(p.x / size + mod(row, 2.0) * 0.5, p.y / size));
	vec2 d = min(f, 1.0 - f) * size;
	float side = d.x < d.y ? f.x : f.y;
	float shade = side > 0.5 ? 0.65 : 0.82;
	return mix(base, joint * shade, line_cover(min(d.x, d.y), 0.005, fw) * detail(size, fw));
}

// Integer lattice hash shared with FloorThumbnail. Bounded operands keep
// all arithmetic within uint32 and give the CPU exactly the same samples.
float lattice_hash(ivec2 p) {
	uint n = (uint(p.x) & 65535u) * 251u + (uint(p.y) & 65535u) * 199u;
	n = (n ^ (n >> 7u)) * 109u;
	return float((n ^ (n >> 11u)) & 65535u) / 65535.0;
}

// 7: one small irregularly placed chip per 0.125 m lattice square.
vec3 terrazzo(vec2 p, vec3 base, vec3 accent, float fw) {
	float size = 0.125;
	ivec2 cell = ivec2(floor(p / size));
	float h = lattice_hash(cell);
	float j = lattice_hash(cell + ivec2(37, 91));
	vec2 centre = vec2(0.25 + h * 0.5, 0.25 + j * 0.5);
	float d = length((fract(p / size) - centre) * size);
	float radius = 0.015 + j * 0.0075;
	vec3 chip = accent * (h < 0.5 ? 1.0 : 0.8);
	// The smooth chip coverage handles pixel edges; fade the entire lattice
	// when cells approach a few pixels. Diameter-based fading hid all chips
	// even at the normal camera size. Fine detail still vanishes at far zoom.
	return mix(base, chip, line_cover(d, radius, fw) * detail(size, fw));
}

// 8: metre-wide slabs; faint fine-lattice mottling, thin accent joints.
vec3 concrete(vec2 p, vec3 base, vec3 joint, float fw) {
	vec2 f = fract(p);
	vec2 d = min(f, 1.0 - f);
	float shade = 1.0 + (lattice_hash(ivec2(floor(p / 0.125))) - 0.5) * 0.035 * detail(0.125, fw);
	return mix(base * shade, joint, line_cover(min(d.x, d.y), 0.002, fw) * detail(1.0, fw));
}

// 9: no joints; a quiet alternating warp/weft in the selected colours.
vec3 carpet(vec2 p, vec3 base, vec3 accent, float fw) {
	vec2 f = fract(p / 0.025);
	float weave = (step(0.5, f.x) + step(0.5, f.y)) * 0.5;
	return mix(base, accent, weave * 0.06 * detail(0.025, fw));
}

void fragment() {
	vec2 grid_position = world_position.xz / cell_size;
	vec2 line_distance = abs(fract(grid_position + 0.5) - 0.5) * cell_size;
	vec2 antialias = max(fwidth(world_position.xz), vec2(0.0001));
	vec2 lines = 1.0 - smoothstep(vec2(line_width), vec2(line_width) + antialias, line_distance);
	float coverage = grid_visible ? max(lines.x, lines.y) : 0.0;
	ivec4 finish = ivec4(0);
	ivec2 cell = ivec2(floor(grid_position)) - map_origin;
	if (cell.x >= 0 && cell.y >= 0 && cell.x < map_size.x && cell.y < map_size.y) {
		finish = ivec4(round(texelFetch(finish_map, cell, 0) * 255.0));
	}
	vec3 base = colour_at(finish.g, floor_color.rgb);
	vec3 accent = finish.b > 0 ? colour_at(finish.b, base) : base * 0.72;
	float fw = max(antialias.x, antialias.y);
	vec3 patterned_floor;
	if (finish.r == 1) {
		patterned_floor = narrow_planks(world_position.xz, base, accent, fw);
	} else if (finish.r == 2) {
		patterned_floor = herringbone(world_position.xz, base, accent, fw);
	} else if (finish.r == 3) {
		patterned_floor = checker(world_position.xz, base, finish.b > 0 ? accent : base * 0.55, fw);
	} else if (finish.r == 4) {
		patterned_floor = small_tiles(world_position.xz, base, accent, fw);
	} else if (finish.r == 5) {
		patterned_floor = hex_tiles(world_position.xz, base, accent, fw);
	} else if (finish.r == 6) {
		patterned_floor = terracotta(world_position.xz, base, accent, fw);
	} else if (finish.r == 7) {
		patterned_floor = terrazzo(world_position.xz, base, accent, fw);
	} else if (finish.r == 8) {
		patterned_floor = concrete(world_position.xz, base, accent, fw);
	} else if (finish.r == 9) {
		patterned_floor = carpet(world_position.xz, base, accent, fw);
	} else {
		// 0: the original wide planks, unchanged. A quiet world-space plank
		// variation remains multiplicative with the authored floor swatch, so
		// paint keeps control of the underlying colour.
		float plank_band = mod(floor(world_position.z / 0.5), 2.0);
		float plank_seam = 1.0 - smoothstep(0.0, 0.012, abs(fract(world_position.z / 0.5) - 0.5));
		float plank_shade = 1.0 - plank_band * 0.018 - plank_seam * 0.025;
		patterned_floor = base * plank_shade;
	}
	if (finish.a > 0) {
		// A thin darker threshold where the floor type changes; each side draws half.
		vec2 local = fract(grid_position) * cell_size;
		float edge = 1.0e3;
		edge = (finish.a & 1) != 0 ? min(edge, local.x) : edge;
		edge = (finish.a & 2) != 0 ? min(edge, local.y) : edge;
		edge = (finish.a & 4) != 0 ? min(edge, cell_size - local.x) : edge;
		edge = (finish.a & 8) != 0 ? min(edge, cell_size - local.y) : edge;
		patterned_floor = mix(patterned_floor, patterned_floor * 0.55, line_cover(edge, 0.007, fw));
	}
	ALBEDO = mix(patterned_floor, grid_color.rgb, coverage);
	ROUGHNESS = 0.95;
}
