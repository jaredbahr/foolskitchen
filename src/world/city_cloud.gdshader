shader_type spatial;
// Clouds drifting past below a rooftop (#614): chunky low-poly puffs, vertex-coloured
// (lit tops, shaded bellies), in one mesh. UV2.x is a puff's home along the street
// (local u) and UV2.y its speed; each drifts along u as a function of `cloud_time`
// (the street's display clock, never TIME), wraps round a `span` centred on `centre_u`
// and fades out near the ends, so a paused capture is always the same frame. `tint`
// follows the time of day (white by day, rosy at dusk, dim blue at night).
render_mode unshaded, cull_back, shadows_disabled, depth_prepass_alpha;

uniform float cloud_time = 0.0;
uniform float span = 180.0;
uniform float centre_u = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float opacity = 0.8;

varying float fade;

void vertex() {
	float home = UV2.x;
	float lo = centre_u - span * 0.5;
	float now = mod(home + UV2.y * cloud_time - lo, span) + lo;
	VERTEX.x += now - home;
	float edge = span * 0.12;
	fade = smoothstep(lo, lo + edge, now) * (1.0 - smoothstep(lo + span - edge, lo + span, now));
}

void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ALPHA = opacity * fade;
}
