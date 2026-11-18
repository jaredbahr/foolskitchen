shader_type spatial;
// The country lane's standing wheat (#619): lit like the rest of the country (vertex
// colour, per-vertex light, no specular), with a slight sway. Vertex alpha says what
// may move: 1 stands still (the earth, the stalks' feet), 0 sways in full; how far it
// sways also grows with height. Gentle waves roll across the field with a faint paler
// sheen on their crests. Every motion is a function of `sway_time`, the street's
// display clock, never TIME, so a paused capture is always the same frame.
render_mode vertex_lighting, cull_disabled, shadows_disabled, specular_disabled;

uniform float sway_time = 0.0;
// Where the wind blows (street-local x, z) and how far the ears lean (metres).
uniform vec2 wind = vec2(0.94, 0.34);
uniform float reach = 0.035;
uniform float base_y = -0.047;

varying float sheen;

void vertex() {
	float free = (1.0 - COLOR.a) * clamp((VERTEX.y - base_y) / 0.45, 0.0, 1.4);
	float along = dot(VERTEX.xz, wind);
	float across = dot(VERTEX.xz, vec2(-wind.y, wind.x));
	float t = sway_time;
	// A slow gust envelope and a quicker ripple under it.
	float gust = 0.55 + 0.45 * sin(along * 0.21 - t * 0.37 + sin(across * 0.13) * 1.7);
	float wave = sin(along * 0.85 - t * 1.25 + sin(across * 0.4) * 0.8);
	float lean = (0.35 + 0.65 * gust) * (0.6 * wave + 0.4) * reach * free;
	VERTEX.xz += wind * lean;
	VERTEX.y -= abs(lean) * 0.35;
	sheen = clamp(wave * gust, 0.0, 1.0) * free;
}

void fragment() {
	ALBEDO = COLOR.rgb * (1.0 + 0.07 * sheen);
	ROUGHNESS = 1.0;
}
