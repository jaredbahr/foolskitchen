shader_type spatial;
// Falling rain (WeatherView): every instance is one column of air, a thin quad turned to
// the camera and slanted with the wind, and one streak falls down it. The instance's custom
// data holds its phase and fall rate, so neighbouring streaks never fall in step. The fall
// is a function of `rain_time` (the street's display clock, never TIME), so a paused
// capture is always the same frame.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform float rain_time = 0.0;
// The streak's length as a share of its column.
uniform float streak = 0.14;
uniform vec4 tint : source_color = vec4(0.82, 0.87, 0.95, 0.42);

varying float head;

void vertex() {
	float fall = fract(INSTANCE_CUSTOM.x - rain_time * INSTANCE_CUSTOM.y);
	head = 1.0 - VERTEX.y;
	VERTEX.y = fall * (1.0 - streak) + VERTEX.y * streak;
}

void fragment() {
	ALBEDO = tint.rgb;
	// Brightest at the falling end, fading up the tail.
	ALPHA = tint.a * (0.3 + 0.7 * head);
}
