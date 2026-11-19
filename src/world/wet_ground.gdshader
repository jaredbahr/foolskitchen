shader_type spatial;
// Rain on the neighbourhood's vertex-coloured meshes (ground, paths, roofs, decks, walls):
// lit exactly like their own per-vertex material, but darker where it is wet, with a
// faint glossy sheen of the sky's light streaked toward the viewer, as wet ground reflects.
// Flat, upward-facing surfaces soak the most; walls only darken a little, and grass and
// leaves (a colour whose green leads) only a touch. `wet` 0 is the dry colour exactly.
// Nothing moves: the sheen is a function of the world position, so a paused capture is
// always the same frame.
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

varying float up;
varying vec2 ground;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	ground = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
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
	// Wet things darken and grow a little richer.
	float grey = dot(colour, vec3(0.3, 0.5, 0.2));
	colour = mix(vec3(grey), colour, 1.0 + 0.18 * soak) * (1.0 - darken * soak);
	ALBEDO = max(colour, vec3(0.0));
	ROUGHNESS = 1.0;
	// The sheen: long soft streaks running toward the viewer, broken up along their length.
	vec2 across_dir = vec2(-view_dir.y, view_dir.x);
	float along = dot(ground, view_dir);
	float across = dot(ground, across_dir);
	float streak = 0.5 + 0.5 * sin(across * 2.3 + 1.7 * sin(along * 0.21 + across * 0.37));
	float breakup = 0.5 + 0.5 * sin(along * 0.45 + 2.1 * sin(across * 0.29));
	float gloss = flat_face * (1.0 - green) * wet;
	EMISSION = sheen_color * sheen * gloss * (0.35 + 0.65 * streak * breakup);
}
