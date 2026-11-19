shader_type spatial;
// A rain puddle (WeatherView): a still sheet of water lying over the wet ground, mirroring
// the sky's light (so it reads on any paving, path or roof), its edge soft, with thin rings
// opening where the rain hits and, at night, the street's lamps shining in it. UV runs from
// 0 at the middle to 1 at the rim. Every motion is a function of `rain_time` (the street's
// display clock), so a paused capture is always the same frame.
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_mix;

uniform float rain_time = 0.0;
// The sky's light the water mirrors (it follows the time of day).
uniform vec3 sky : source_color = vec3(0.62, 0.68, 0.76);
uniform float opacity = 0.55;
// Up to six lamps (world x, z, strength): their light shines in the water.
uniform vec4 lights[6];
uniform vec3 light_color : source_color = vec3(1.0, 0.8, 0.46);
// Toward the camera on the ground (x, z): the reflections stretch along it.
uniform vec2 view_dir = vec2(-0.57, 0.82);

varying vec2 world_xz;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float r = length(UV);
	float body = 1.0 - smoothstep(0.7, 1.0, r);
	// The sky in the water: a soft band of brighter light across it.
	vec2 across_dir = vec2(-view_dir.y, view_dir.x);
	float toward = dot(world_xz, view_dir);
	float band = 0.5 + 0.5 * sin(toward * 2.1 + 0.6 * sin(dot(world_xz, across_dir) * 1.3));
	vec3 water = sky * (0.5 + 0.22 * band);
	// Rings where the drops land: in some small cells a ring opens on its own beat.
	vec2 cell = floor(world_xz / 0.3);
	float h = hash(cell);
	vec2 centre = (cell + 0.3 + 0.4 * vec2(h, hash(cell + 3.1))) * 0.3;
	float age = fract(rain_time * (0.7 + 0.5 * h) + h * 7.0);
	float d = length(world_xz - centre);
	float ring = (1.0 - smoothstep(0.004, 0.012, abs(d - 0.015 - 0.09 * age))) * (1.0 - age) * step(0.45, h);
	water = mix(water, sky * 1.05, ring * 0.55);
	// Lamplight in the water: a bright core stretched toward the viewer, broken by ripples.
	vec3 glow = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		vec4 l = lights[i];
		if (l.z <= 0.0) {
			continue;
		}
		vec2 off = world_xz - l.xy;
		float along = dot(off, view_dir);
		float side = dot(off, across_dir);
		float shine = exp(-side * side * 10.0 - max(along, -along * 4.0) * max(along, -along * 4.0) * 0.35);
		glow += light_color * l.z * shine * (0.75 + 0.25 * sin(along * 16.0 + rain_time * 2.5));
	}
	ALBEDO = water + glow;
	ALPHA = body * clamp(opacity + length(glow) * 0.5, 0.0, 1.0);
}
