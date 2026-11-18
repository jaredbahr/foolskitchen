shader_type spatial;
// Little points of warm light in the woodland clearing (#607): the string lights' and
// lanterns' bulbs, and the fireflies. Each sprite is one quad whose four corners all
// sit at its centre; the vertex stage spreads them to face the camera, so one mesh
// holds every light and each always faces the view. UV is the corner (0..1), UV2.x
// the sprite's size and UV2.y its seed. Fireflies (`drift` 1) wander and blink as a
// function of `glow_time`, the street's display clock, never TIME, so a paused
// capture is always the same frame. `level` fades them all in from dusk.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled;

uniform float glow_time = 0.0;
uniform float level = 0.0;
uniform float drift = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.82, 0.46);

varying float lit;

void vertex() {
	vec3 centre = VERTEX;
	float seed = UV2.y;
	lit = 1.0;
	if (drift > 0.5) {
		float t = glow_time * 0.32 + seed * 17.0;
		centre += vec3(sin(t * 0.9 + seed * 3.1) * 0.55 + sin(t * 0.37 + seed) * 0.35,
			sin(t * 1.3 + seed * 5.0) * 0.16,
			cos(t * 0.7 + seed * 2.3) * 0.55 + cos(t * 0.29 + seed * 4.0) * 0.3);
		float blink = sin(glow_time * (0.9 + fract(seed * 7.3) * 0.8) + seed * 11.0);
		lit = smoothstep(-0.1, 0.8, blink);
	}
	vec4 view = MODELVIEW_MATRIX * vec4(centre, 1.0);
	view.xy += (UV - 0.5) * UV2.x;
	VERTEX = view.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float halo = 1.0 - smoothstep(0.0, 1.0, d);
	halo *= halo;
	float core = 1.0 - smoothstep(0.0, 0.28, d);
	ALBEDO = mix(tint, vec3(1.0, 0.97, 0.85), core);
	ALPHA = clamp((halo * 0.75 + core) * level * lit, 0.0, 1.0);
}
