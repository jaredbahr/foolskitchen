shader_type spatial;
// Rain on the neighbourhood's vertex-coloured meshes (ground, paths, roofs, decks, walls):
// lit exactly like their own per-vertex material, but darker where it is wet, with a
// faint glossy sheen of the sky's light streaked toward the viewer, as wet ground reflects.
// Flat, upward-facing surfaces soak the most; walls only darken a little, and grass and
// leaves (a colour whose green leads) only a touch. `wet` 0 is the dry colour exactly.
// Light, warm colours (sand) keep their gold: they darken less and grow richer.
// With SWAY (foliage: trees, bushes, hedges, grass, reeds) the vertices whose colour alpha is
// under 1 lean and stir in the wind, more the higher they stand above the ground, so trunks
// and stems stay planted. The sheen and the sway are functions of the world position and
// `sway_time` (the street's display clock), so a paused capture is always the same frame.
render_mode vertex_lighting, specular_disabled, shadows_disabled;

uniform float wet = 0.0;
// A plain-coloured mesh (road, paving, kerbs) gives its colour here instead of per vertex.
uniform vec3 base_color : source_color = vec3(0.6);
// How much darker a soaked flat surface gets, and how much of that grass keeps.
uniform float darken = 0.27;
uniform float grass_share = 0.3;
// The sky's light the wet sheen reflects (follows the time of day), and how strong it is.
uniform vec3 sheen_color : source_color = vec3(0.6, 0.66, 0.75);
uniform float sheen = 0.11;
// The camera's forward direction on the ground (x, z): reflections streak along it.
uniform vec2 view_dir = vec2(0.57, -0.82);

// The scenery's own specular share (its StandardMaterial3D's metallic_specular).
uniform float specular_share = 0.5;
#ifdef SWAY
uniform float sway_time = 0.0;
// How far a crown leans at full sway (metres), and how much the wind comes in gusts.
uniform float sway_reach = 0.02;
uniform float gust = 0.2;
uniform vec2 wind = vec2(0.8, 0.6);
#endif

varying float up;
varying vec2 ground;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground = world.xz;
#ifdef SWAY
	float free = 1.0 - COLOR.a;
	if (free > 0.0) {
		// Planted at the ground, freer the higher it stands.
		float height = smoothstep(-0.04, 0.32, world.y) * (0.45 + 0.55 * clamp(world.y, 0.0, 2.6));
		float along = dot(world.xz, wind);
		float t = sway_time;
		// Gusts roll across the place; under them each plant stirs on its own beat.
		float envelope = 1.0 - gust + gust * (0.5 + 0.5 * sin(along * 0.13 - t * 0.55));
		float stir = 0.35 + 0.65 * sin(t * 1.6 + along * 0.5 + world.z * 0.23);
		float lean = sway_reach * free * height * envelope * stir;
		vec3 push = vec3(wind.x * lean, -abs(lean) * 0.2, wind.y * lean);
		VERTEX += transpose(mat3(MODEL_MATRIX)) * push;
	}
#endif
}

void fragment() {
#ifdef FLAT_COLOUR
	vec3 colour = base_color;
#else
	vec3 colour = COLOR.rgb;
#endif
	float green = clamp((colour.g - max(colour.r, colour.b)) * 7.0, 0.0, 1.0);
	float flat_face = smoothstep(0.55, 0.92, up);
	float soak = wet * mix(0.3, 1.0, flat_face) * mix(1.0, grass_share, green);
	// Wet things darken and grow a little richer; pale warm sand to a deeper gold, not brown.
	float grey = dot(colour, vec3(0.3, 0.5, 0.2));
	float sandy = clamp((colour.r - colour.b) * 3.0, 0.0, 1.0) * smoothstep(0.45, 0.7, grey) * (1.0 - green);
	colour = mix(vec3(grey), colour, 1.0 + (0.18 + 0.6 * sandy) * soak) * (1.0 - darken * (1.0 - 0.75 * sandy) * soak);
	ALBEDO = max(colour, vec3(0.0));
	ROUGHNESS = 1.0;
	SPECULAR = specular_share;
	// The sheen: long soft streaks running toward the viewer, broken up along their length.
	vec2 across_dir = vec2(-view_dir.y, view_dir.x);
	float along = dot(ground, view_dir);
	float across = dot(ground, across_dir);
	float streak = 0.5 + 0.5 * sin(across * 2.3 + 1.7 * sin(along * 0.21 + across * 0.37));
	float breakup = 0.5 + 0.5 * sin(along * 0.45 + 2.1 * sin(across * 0.29));
	float gloss = flat_face * (1.0 - green) * wet;
	EMISSION = sheen_color * sheen * gloss * (0.35 + 0.65 * streak * breakup);
}
