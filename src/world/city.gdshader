shader_type spatial;
// The city round a rooftop site (#614): every building, the tower the shop stands on,
// other roofs' clutter and the streets far below, as flat vertex-coloured boxes. Two
// things are drawn here instead of in geometry, so the whole city stays a handful of
// cheap meshes:
// - Windows: a grid on every wall face, in the street frame's local space (the mesh is
//   authored there). UV.x is the building's seed, UV.y its window style (0 none,
//   1 punched windows, 2 a glass curtain wall, 3 ribbon windows). By day they are
//   glass; at night some rooms are lit, warm or cool, chosen by an integer hash of the
//   building, floor and room, and swapped now and then on `city_time` (the street's
//   display clock, never TIME), so a paused capture always shows the same frame.
//   Small windows far off fade to their average so nothing shimmers.
// - Haze: the deeper below the roof and the farther from the shop, the more a
//   surface fades into the haze colour (day, dusk, night), so the street at the bottom
//   and the far skyline melt away and the eye stays on the roof. At night the bottom of
//   the canyons glows warm with the street lights.
render_mode vertex_lighting, shadows_disabled, specular_disabled, cull_back;

// Where the evening is: 0 by day, 0.5 at the golden dusk, 1 by night (the haze runs
// day, dusk, night along it).
uniform float level = 0.0;
// How lit the windows are (0..1; below 0 they follow `level`), and the share of the
// night's lit rooms that are on (a scattering at dusk, all of them by night).
uniform float window_level = -1.0;
uniform float window_share = 1.0;
uniform float late = 0.0;
uniform float city_time = 0.0;
uniform float street_depth = 46.0;
uniform vec2 centre = vec2(0.0);
uniform vec3 haze_day : source_color = vec3(0.8, 0.86, 0.92);
uniform vec3 haze_dusk : source_color = vec3(0.92, 0.74, 0.64);
uniform vec3 haze_night : source_color = vec3(0.1, 0.13, 0.24);
uniform vec3 window_day : source_color = vec3(0.36, 0.45, 0.55);
uniform vec3 window_dark : source_color = vec3(0.08, 0.1, 0.14);
uniform vec3 window_warm : source_color = vec3(1.0, 0.78, 0.42);
uniform vec3 window_cool : source_color = vec3(0.8, 0.88, 1.0);
uniform float window_energy = 1.1;
// At night the streets' lights warm the bottom of the canyons.
uniform vec3 street_glow : source_color = vec3(1.0, 0.7, 0.36);
// Weather (0 fair, about 0.4 cloudy, 1 rain): the haze thickens toward a grey murk, most
// over the deep streets and the far skyline. 0 draws exactly the fair city.
uniform float murk = 0.0;
uniform vec3 murk_day : source_color = vec3(0.62, 0.66, 0.7);

varying vec3 local_pos;
varying vec3 local_nrm;
varying vec2 info;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	local_pos = VERTEX;
	local_nrm = NORMAL;
	info = UV;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float style = floor(info.y + 0.5);
	float glow = 0.0;
	vec3 glow_colour = window_warm;
	// How much the glass mirrors the sunset sky: most at the golden dusk, none by day or night.
	float sunset = 1.0 - clamp(abs(level - 0.5) * 2.0, 0.0, 1.0);
	float mirror = 0.0;
	if (style > 0.5 && abs(local_nrm.y) < 0.5) {
		float along = abs(local_nrm.x) > 0.5 ? local_pos.z : local_pos.x;
		float storey = style > 2.5 ? 1.15 : 1.4;
		float column = style > 1.5 ? 0.62 : 0.8;
		vec2 grid = vec2(along / column, local_pos.y / storey);
		vec2 cell = floor(grid);
		vec2 f = fract(grid);
		vec2 lo = vec2(0.22, 0.3);
		vec2 hi = vec2(0.78, 0.82);
		if (style > 2.5) {
			lo = vec2(-1.0, 0.34);
			hi = vec2(2.0, 0.86);
		} else if (style > 1.5) {
			lo = vec2(0.06, 0.1);
			hi = vec2(0.94, 0.94);
		}
		vec2 w = max(fwidth(grid), vec2(0.0001));
		float mx = smoothstep(lo.x - w.x, lo.x + w.x, f.x) * (1.0 - smoothstep(hi.x - w.x, hi.x + w.x, f.x));
		float my = smoothstep(lo.y - w.y, lo.y + w.y, f.y) * (1.0 - smoothstep(hi.y - w.y, hi.y + w.y, f.y));
		float coverage = clamp(hi.x - lo.x, 0.0, 1.0) * (hi.y - lo.y);
		float blur = smoothstep(0.3, 0.7, max(w.x, w.y));
		float mask = mix(mx * my, coverage, blur);
		// Rooms are a few windows wide; each changes now and then, on its own beat.
		float seed = info.x * 997.0;
		float width = style > 1.5 && style < 2.5 ? 1.0 + floor(fract(seed * 0.37) * 2.0) : 2.0 + floor(fract(seed * 0.37) * 3.0);
		float room = floor(cell.x / width);
		float beat = floor(city_time / 53.0 + hash(vec3(room, cell.y, seed)));
		float pick = hash(vec3(room * 1.7 + 3.1, cell.y * 0.9 + seed, beat * 7.3 + 1.0));
		float share = mix(0.3, 0.17, late) * (0.6 + 0.8 * fract(seed * 0.61)) * window_share;
		float on = mix(step(pick, share), share, blur);
		// Offices burn cool white, homes warm; a few rooms the other way.
		float cool = step(0.6, fract(seed * 0.173)) * step(1.5, style) * step(style, 2.5);
		float swap = step(0.82, hash(vec3(room + 9.0, cell.y, seed + 2.0)));
		glow_colour = mix(window_warm, window_cool, abs(cool - swap));
		vec3 day_glass = window_day * (0.88 + 0.24 * f.y);
		// Glass stays glass through the dusk (it takes the warm low sun) and darkens with the night.
		vec3 pane = mix(day_glass, window_dark, smoothstep(0.3, 1.0, level));
		base = mix(base, pane, mask);
		glow = mask * on * (window_level < 0.0 ? level : window_level);
		mirror = mask * (1.0 - on) * sunset * (0.75 + 0.25 * f.y);
	}
	float depth = clamp(-local_pos.y / street_depth, 0.0, 1.0);
	float far = smoothstep(30.0, 115.0, length(local_pos.xz - centre));
	float haze = 1.0 - (1.0 - pow(depth, 1.15) * 0.9) * (1.0 - far * 0.75);
	// A little night air over everything, so the city's roofs go blue, not brown.
	haze = max(haze, 0.45 * smoothstep(0.5, 1.0, level));
	haze = mix(haze, 1.0, murk * (0.12 + 0.5 * max(pow(depth, 0.8), far)));
	vec3 tint = level < 0.5 ? mix(haze_day, haze_dusk, level * 2.0) : mix(haze_dusk, haze_night, level * 2.0 - 1.0);
	tint = mix(tint, murk_day * (0.25 + 0.75 * (1.0 - smoothstep(0.4, 1.0, level))) * mix(vec3(1.0), tint * 1.4, 0.35), murk * 0.7);
	tint = mix(tint, street_glow * 0.55, smoothstep(0.5, 1.0, level) * depth * depth * 0.6);
	ALBEDO = base * (1.0 - haze);
	ROUGHNESS = 1.0;
	EMISSION = tint * haze + glow_colour * glow * window_energy * (1.0 - haze * 0.55) + haze_dusk * mirror * 0.32 * (1.0 - haze);
}
