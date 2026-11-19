shader_type spatial;
// A street lamp's light on wet ground at night (WeatherView): a long soft warm streak from
// under the lamp toward the viewer, as a wet street mirrors a lamp, broken into ripples.
// UV.x runs across the streak (-1..1) and UV.y along it (0 under the lamp, 1 nearest the
// viewer). Drawn additively; `level` is how lit the lamps are (0 by day).
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;

uniform float level = 0.0;
uniform float rain_time = 0.0;
uniform vec3 light_color : source_color = vec3(1.0, 0.78, 0.44);

void fragment() {
	float across = abs(UV.x);
	float along = UV.y;
	float core = exp(-across * across * 6.0) * (1.0 - smoothstep(0.1, 1.0, along)) * smoothstep(0.0, 0.1, along);
	// Broken a little by the rain's ripples: soft, uneven bands drifting along the streak.
	float ripple = 0.82 + 0.18 * sin(along * 17.0 - rain_time * 1.7 + 2.0 * sin(along * 5.3 + UV.x * 2.0));
	ALBEDO = light_color * core * ripple * level * 0.95;
}
