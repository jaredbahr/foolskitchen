shader_type spatial;
// The sea behind a seaside street (#588): flat, banded water in the shore's palette,
// the swash running up the wet sand with a foam edge, crests rolling in, a few
// glints, and at night the lights' shimmering reflections. UV carries the street's
// local (u, z); z falls toward the sea. Every motion is a function of `sea_time`,
// the street's display clock, never TIME, so a paused capture is always the same.
render_mode vertex_lighting, cull_disabled, specular_disabled;

uniform float sea_time = 0.0;
// Local z of the still waterline; the swash runs up to about 0.75 m past it.
uniform float shore_z = 0.0;
uniform float wet_width = 1.25;
uniform vec3 sand_wet : source_color = vec3(0.7, 0.62, 0.5);
uniform vec3 shallow : source_color = vec3(0.5, 0.78, 0.76);
uniform vec3 mid : source_color = vec3(0.32, 0.62, 0.7);
uniform vec3 deep : source_color = vec3(0.22, 0.45, 0.6);
uniform vec3 foam : source_color = vec3(0.96, 0.95, 0.9);
// Night glow: up to four lights (u, z, strength) shimmer on the water.
uniform vec4 lights[4];
uniform vec3 light_color : source_color = vec3(1.0, 0.82, 0.48);
// 0 by day; at sunset the crests and glints catch a warm light.
uniform float dusk = 0.0;
uniform vec3 dusk_color : source_color = vec3(1.0, 0.62, 0.38);
// 0 until the shop closes, 1 late at night: a faint cool moonlit sheen keeps the sea readable.
uniform float moon = 0.0;
uniform vec3 moon_color : source_color = vec3(0.45, 0.55, 0.75);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// How far the water reaches up the sand past the still line, in metres.
float swash(float u, float t) {
	float wave = 0.5 + 0.5 * sin(t * 0.62 + u * 0.11 + 0.7 * sin(u * 0.29));
	return 0.12 + 0.62 * wave * wave + 0.05 * sin(u * 1.7 + t * 0.4);
}

void fragment() {
	float u = UV.x;
	float d = shore_z - UV.y;
	float t = sea_time;
	float reach = swash(u, t);
	float past = d + reach;
	vec3 colour;
	vec3 glow = vec3(0.0);
	if (past < 0.0) {
		// Above the water's edge: the wet band, then dry sand (the beach mesh beneath).
		if (d < -wet_width - 0.12 * sin(u * 0.83) - 0.06 * sin(u * 2.3)) {
			discard;
		}
		colour = sand_wet;
		// The film the last wave left: a slightly darker sheen just above the edge.
		colour = mix(colour, sand_wet * 0.9, step(past, 0.0) * step(-0.18, past));
	} else {
		float band1 = 1.4 + 0.3 * sin(u * 0.37 + t * 0.21);
		float band2 = 5.0 + 0.8 * sin(u * 0.19 - t * 0.13 + 1.3);
		colour = d < band1 ? shallow : (d < band2 ? mid : deep);
		// Far water darkens a touch more toward the edge of the world.
		colour = mix(colour, deep * 0.9, smoothstep(14.0, 34.0, d));
		// The foam edge of the swash, and a fizzy second line just behind it.
		float edge = 1.0 - step(0.15 + 0.05 * sin(u * 2.3 + t) + 0.03 * sin(u * 5.1), past);
		float fizz_at = 0.42 + 0.1 * sin(u * 0.9 - t * 0.5);
		float fizz = step(fizz_at, past) * (1.0 - step(fizz_at + 0.07, past))
			* step(0.0, sin(u * 2.1 + 1.3 * sin(u * 0.7) + t * 0.3));
		// Crests rolling in from the deep, broken along their length.
		float wave = d * 1.7 + t * 1.25 + 0.6 * sin(u * 0.27);
		float roll = sin(wave);
		float k = floor(wave / 6.2832);
		float broken = step(0.55, sin(u * (0.7 + 0.25 * fract(k * 0.37)) + k * 2.4 + 0.8 * sin(u * 0.31)));
		float crest = step(0.986, roll) * broken * step(0.9, d) * (1.0 - smoothstep(5.0, 10.0, d));
		// Glints: short sparkling dashes on the open water.
		vec2 cell = floor(vec2(u * 0.9, d * 2.4));
		float h = hash(cell);
		float glint = step(0.975, h) * step(0.6, sin(t * 1.7 + h * 50.0)) * step(2.0, d);
		colour = mix(colour, foam, max(edge, fizz * 0.8));
		colour = mix(colour, foam, crest * 0.5);
		colour = mix(colour, mix(shallow, foam, 0.6), glint);
		// Sunset: the open water takes the warm sky, brightest far out, and the crests catch it.
		glow += dusk_color * dusk * (0.24 * smoothstep(1.0, 20.0, d) + crest * 0.3 + glint * 0.7 + edge * 0.15);
		glow += moon_color * moon * (0.05 + crest * 0.12 + glint * 0.35 + edge * 0.1);
		// Lights on the water: a soft pool and broken shimmering streaks.
		for (int i = 0; i < 4; i++) {
			vec4 l = lights[i];
			if (l.z <= 0.0) {
				continue;
			}
			vec2 off = vec2(u - l.x, UV.y - l.y);
			float pool = exp(-dot(off * vec2(0.7, 0.45), off * vec2(0.7, 0.45)));
			// Glittering little dashes, each flickering on its own beat.
			// Thin dashes along the shore, a few to each row of ripples.
			float row = off.y * 4.0 + 0.3 * sin(off.x * 1.7 + t * 0.8);
			vec2 bit = floor(vec2(off.x * 1.6 + 0.5 * floor(row), row));
			float hb = hash(bit + vec2(float(i) * 7.0, 3.0));
			float thin = step(0.6, fract(row));
			float dash = thin * step(0.3, hb) * step(-0.3, sin(t * 2.2 + hb * 40.0));
			glow += light_color * l.z * pool * (0.12 + 0.88 * dash);
		}
	}
	ALBEDO = colour;
	ROUGHNESS = 1.0;
	EMISSION = glow;
}
