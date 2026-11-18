shader_type spatial;
// The stream in the woodland clearing (#607): deeper water down its middle, shallow
// edges, and pale ripples drifting downstream. UV.x runs along the stream (metres) and
// UV.y across it (-1 at one bank, 1 at the other). Every motion is a function of
// `stream_time`, the street's display clock, never TIME, so a paused capture is
// always the same frame. `moon` adds a faint cool sheen once the night is late.
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform float stream_time = 0.0;
uniform vec3 deep : source_color = vec3(0.24, 0.42, 0.45);
uniform vec3 shallow : source_color = vec3(0.42, 0.62, 0.58);
uniform vec3 ripple : source_color = vec3(0.86, 0.93, 0.9);
uniform float moon = 0.0;
uniform vec3 moon_color : source_color = vec3(0.5, 0.6, 0.78);

void fragment() {
	float across = abs(UV.y);
	float along = UV.x;
	float t = stream_time * 0.55;
	vec3 colour = mix(deep, shallow, smoothstep(0.3, 0.95, across));
	float wobble = sin(UV.y * 3.1 + along * 0.6) * 1.4;
	float a = sin((along - t) * 2.2 + wobble);
	float b = sin((along - t * 1.35) * 4.7 + UV.y * 6.0 + 1.7);
	float streak = smoothstep(0.78, 0.97, a * 0.62 + b * 0.38) * (1.0 - across * 0.55);
	float edge = smoothstep(0.82, 0.98, across) * (0.55 + 0.45 * sin(along * 3.3 - t * 2.0));
	colour = mix(colour, ripple, clamp(streak * 0.6 + edge * 0.45, 0.0, 1.0));
	colour += moon_color * moon * (0.06 + streak * 0.25);
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}
