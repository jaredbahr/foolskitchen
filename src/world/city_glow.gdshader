shader_type spatial;
// Points of light over a rooftop's city (#614): the terrace bulbs, the red aircraft
// lights on the tallest masts, the street lights far below and the cars on those
// streets. Like forest_glow.gdshader, each sprite is one quad with all four corners at
// its centre, spread to face the camera here; UV is the corner, UV2.x the size and
// UV2.y the seed, and COLOR.rgb the sprite's own tint. `mode` 1 blinks (aircraft
// lights: a slow on-off beat per light); `mode` 2 drives (COLOR.a picks the street's
// axis and direction: below 0.25 is +u, 0.5 -u, 0.75 +z, above that -z, and each car
// runs `span` metres and wraps). All motion is a function of `glow_time`, the street's
// display clock, never TIME, so a paused capture is always the same frame. `level`
// fades them in from dusk; lights deep below the roof are dimmed by the haze.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, skip_vertex_transform, shadows_disabled;

uniform float glow_time = 0.0;
uniform float level = 0.0;
uniform int mode = 0;
uniform float speed = 6.0;
uniform float span = 200.0;
uniform float street_depth = 46.0;

varying float lit;
varying vec3 tint;

void vertex() {
	vec3 centre = VERTEX;
	float seed = UV2.y;
	lit = 1.0;
	tint = COLOR.rgb;
	if (mode == 1) {
		float beat = fract(glow_time / 2.4 + fract(seed * 0.37));
		lit = smoothstep(0.0, 0.06, beat) * (1.0 - smoothstep(0.42, 0.5, beat));
	} else if (mode == 2) {
		vec3 axis = COLOR.a < 0.25 ? vec3(1.0, 0.0, 0.0) : COLOR.a < 0.5 ? vec3(-1.0, 0.0, 0.0)
			: COLOR.a < 0.75 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 0.0, -1.0);
		float pace = speed * (0.75 + 0.5 * fract(seed * 0.71));
		float run = mod(glow_time * pace + fract(seed * 0.13) * span, span) - span * 0.5;
		centre += axis * run;
		lit = 1.0 - smoothstep(span * 0.42, span * 0.5, abs(run));
	}
	lit *= mix(1.0, 0.55, clamp(-centre.y / street_depth, 0.0, 1.0));
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
	ALBEDO = mix(tint, vec3(1.0, 0.97, 0.9), core * 0.6);
	ALPHA = clamp((halo * 0.75 + core) * level * lit, 0.0, 1.0);
}
