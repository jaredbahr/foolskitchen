shader_type spatial;
// Rain splashing on paving, paths and roofs (WeatherView): each instance is a small flat
// quad on the ground where a thin ring opens and fades, over and over, each on its own
// beat (custom data: phase, rate). A function of `rain_time` (the street's display clock),
// so a paused capture is always the same frame.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform float rain_time = 0.0;
uniform vec4 tint : source_color = vec4(0.86, 0.9, 0.96, 0.5);

varying float age;

void vertex() {
	age = fract(INSTANCE_CUSTOM.x + rain_time * INSTANCE_CUSTOM.y);
}

void fragment() {
	float r = length(UV);
	float radius = 0.15 + 0.75 * age;
	float ring = 1.0 - smoothstep(0.0, 0.14, abs(r - radius));
	ALBEDO = tint.rgb;
	ALPHA = tint.a * ring * (1.0 - age) * step(r, 1.0);
}
