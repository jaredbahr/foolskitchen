shader_type spatial;
render_mode cull_back;

// Warm placeholder palette; world-space spacing stays 0.5 m at every zoom.
uniform vec4 floor_color : source_color = vec4(0.58, 0.48, 0.34, 1.0);
uniform vec4 grid_color : source_color = vec4(0.28, 0.22, 0.15, 1.0);
uniform float cell_size : hint_range(0.1, 2.0) = 0.5;
uniform float line_width : hint_range(0.005, 0.1) = 0.012;
uniform bool grid_visible = true;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid_position = world_position.xz / cell_size;
	vec2 line_distance = abs(fract(grid_position + 0.5) - 0.5) * cell_size;
	vec2 antialias = max(fwidth(world_position.xz), vec2(0.0001));
	vec2 lines = 1.0 - smoothstep(vec2(line_width), vec2(line_width) + antialias, line_distance);
	float coverage = grid_visible ? max(lines.x, lines.y) : 0.0;
	// A quiet world-space plank variation remains multiplicative with the
	// authored floor swatch, so paint keeps control of the underlying colour.
	float plank_band = mod(floor(world_position.z / 0.5), 2.0);
	float plank_seam = 1.0 - smoothstep(0.0, 0.012, abs(fract(world_position.z / 0.5) - 0.5));
	float plank_shade = 1.0 - plank_band * 0.018 - plank_seam * 0.025;
	vec3 patterned_floor = floor_color.rgb * plank_shade;
	ALBEDO = mix(patterned_floor, grid_color.rgb, coverage);
	ROUGHNESS = 0.95;
}
