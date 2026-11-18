shader_type spatial;
// The country lane's far crop fields: lit like the rest of the country (vertex colour,
// per-vertex light, no specular), with crop texture drawn in the fragment so it stays
// as fine as the near wheat's grain at any zoom: small flecks of ears and stalks and
// faint, wavy, broken drill rows a few percent darker. Vertex alpha says what a vertex
// is: 1 is plain ground (pasture, left as it is); below that it codes the crop's style
// (0 grain, 1 ploughed, 2 young green) and its rows' direction. Everything comes from
// the mesh's own coordinates, so a paused capture is always the same frame.
render_mode vertex_lighting, cull_disabled, shadows_disabled, specular_disabled;

varying vec2 ground;

void vertex() {
	ground = VERTEX.xz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// How much of a pattern of `period` metres survives at this pixel's footprint.
float detail(float period, float fw) {
	return clamp(period / max(fw, 0.00001) * 0.5 - 0.5, 0.0, 1.0);
}

// A layer of round flecks, one in about `density` of the cells of `size` metres, each
// at its own place in its cell: 1 inside a fleck, softened over the pixel's footprint.
float flecks(vec2 p, float size, float radius, float density, float salt, float fw) {
	vec2 cell = floor(p / size);
	if (hash(cell + salt) > density) {
		return 0.0;
	}
	vec2 centre = (cell + 0.2 + 0.6 * vec2(hash(cell + salt + 7.1), hash(cell + salt + 3.7))) * size;
	return 1.0 - smoothstep(radius - fw, radius + fw, length(p - centre));
}

void fragment() {
	vec3 colour = COLOR.rgb;
	if (COLOR.a < 0.9) {
		float code = floor(COLOR.a * 8.0);
		float style = floor(code * 0.5);
		bool along = mod(code, 2.0) > 0.5;
		vec2 p = ground;
		vec2 q = along ? p : p.yx;
		float fw = max(max(fwidth(p.x), fwidth(p.y)), 0.0001);
		// Drill rows: soft, a little wavy, fading in and out along their length.
		float spacing = style == 1.0 ? 0.3 : 0.22;
		float wobble = 0.05 * sin(q.y * 0.83 + q.x * 0.31) + 0.025 * sin(q.y * 2.1 + 1.7);
		float across = (q.x + wobble) / spacing;
		float row = 0.5 + 0.5 * sin(across * 6.2831853);
		float broken = 0.5 + 0.5 * sin(q.y * 0.55 + floor(across) * 2.39);
		float depth = style == 1.0 ? 0.045 : 0.03;
		colour *= 1.0 - depth * row * (0.4 + 0.6 * broken) * detail(spacing, fw);
		// Flecks: pale ears (or clods) catching the light and darker gaps between stalks.
		float fade = detail(0.05, fw);
		float light = flecks(p, 0.075, 0.022, 0.45, 1.3, fw);
		float dark = flecks(p + vec2(0.035, 0.02), 0.075, 0.02, 0.4, 9.1, fw);
		// Grain ears go pale toward straw; clods and young leaves lift less.
		float lift = style == 1.0 ? 0.1 : (style == 2.0 ? 0.14 : 0.32);
		float sink = style == 1.0 ? 0.12 : 0.07;
		colour = mix(colour, mix(colour, vec3(1.0, 0.95, 0.78), lift), light * fade);
		colour = mix(colour, colour * (1.0 - sink), dark * (1.0 - light) * fade);
	}
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}
