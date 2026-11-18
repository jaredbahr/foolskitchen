class_name WeatherLook
extends RefCounted
## How the day's weather shades the day's light: an overcast or rainy sky over the same
## clock-driven DayLight.Look (#208). Presentation only and a pure function of its inputs,
## so a paused capture always looks the same. Sunny returns the look untouched, so a
## sunny day is exactly the light it always was.
##
## Cloudy: a softer, dimmer, whiter sun with fainter shadows, a little more of the cool
## fill and a slightly cooler ambient under a pale grey sky. Rain: the same, further, under
## a low blue-grey sky; the cool fill and ambient keep it soft and readable rather than
## gloomy, and by night the shop's warm windows and the street's lamps do the rest.

## A neutral overcast white, and the cool grey-blue the rain's light leans to.
const OVERCAST: Color = Color(0.93, 0.94, 0.95)
const RAIN_COOL: Color = Color(0.82, 0.86, 0.94)
## The sky's grey for cloudy and for rain (top and horizon), by day; the evening's own
## sky colours still come through (the night stays as dark as it was).
const CLOUDY_SKY_TOP: Color = Color(0.29, 0.29, 0.3)
const CLOUDY_SKY_HORIZON: Color = Color(0.4, 0.39, 0.38)
const RAIN_SKY_TOP: Color = Color(0.22, 0.24, 0.27)
const RAIN_SKY_HORIZON: Color = Color(0.3, 0.32, 0.35)

## Per weather (SUNNY, CLOUDY, RAIN): how much of the sun reaches the ground, how far its
## colour goes toward the overcast white, the fill's and ambient's gain, how far the
## ambient cools and how far the sky goes grey.
const KEY_SHARE: Array[float] = [1.0, 0.78, 0.6]
const KEY_GREY: Array[float] = [0.0, 0.5, 0.65]
const FILL_GAIN: Array[float] = [1.0, 1.35, 1.6]
const AMBIENT_GAIN: Array[float] = [1.0, 1.1, 1.2]
const AMBIENT_COOL: Array[float] = [0.0, 0.16, 0.22]
const SKY_GREY: Array[float] = [0.0, 0.55, 0.8]
## The key light's shadow opacity: an overcast sun casts softer, fainter shadows.
const SHADOW_OPACITY: Array[float] = [1.0, 0.62, 0.4]
## The street's baked shadows (the blob and contact shadows painted on the ground) fade
## to this share of their strength.
const BAKED_SHADOW: Array[float] = [1.0, 0.6, 0.4]


static func _index(kind: int) -> int:
	return clampi(kind, WeatherState.Kind.SUNNY, WeatherState.Kind.RAIN)


## The light of `look` under the weather `kind`. Sunny returns `look` itself.
static func apply(look: DayLight.Look, kind: int) -> DayLight.Look:
	var index: int = _index(kind)
	if index == WeatherState.Kind.SUNNY or look == null:
		return look
	var rainy: bool = index == WeatherState.Kind.RAIN
	var result: DayLight.Look = DayLight.Look.new()
	# By night the moon is already faint: the overcast takes less of it, so a rainy night
	# stays as readable as a clear one and the lamps and windows carry it.
	var day_level: float = clampf(look.sky_horizon.get_luminance() / 0.32, 0.0, 1.0)
	var weight: float = lerpf(0.35, 1.0, day_level)
	var grey: Color = RAIN_COOL if rainy else OVERCAST
	result.key_color = look.key_color.lerp(grey * look.key_color.get_luminance() / maxf(grey.get_luminance(), 0.001), KEY_GREY[index])
	result.key_energy = look.key_energy * lerpf(1.0, KEY_SHARE[index], weight)
	# A high, diffuse sun: the light falls a little more steeply, so shadows stay short.
	result.key_pitch = lerpf(look.key_pitch, minf(look.key_pitch, -55.0), 0.5)
	result.fill_energy = look.fill_energy * FILL_GAIN[index]
	result.ambient_color = look.ambient_color.lerp(RAIN_COOL, AMBIENT_COOL[index] * weight)
	result.ambient_energy = look.ambient_energy * AMBIENT_GAIN[index]
	var top: Color = RAIN_SKY_TOP if rainy else CLOUDY_SKY_TOP
	var horizon: Color = RAIN_SKY_HORIZON if rainy else CLOUDY_SKY_HORIZON
	# The grey sky follows the day's own brightness, so dusk and night stay dark.
	result.sky_top = look.sky_top.lerp(top * day_level, SKY_GREY[index])
	result.sky_horizon = look.sky_horizon.lerp(horizon * day_level, SKY_GREY[index])
	result.sky_ground = look.sky_ground.lerp(look.sky_ground.lerp(horizon * day_level * 0.7, 0.6), SKY_GREY[index])
	result.glow = look.glow
	result.interior_energy = look.interior_energy
	return result


static func shadow_opacity(kind: int) -> float:
	return SHADOW_OPACITY[_index(kind)]


static func baked_shadow(kind: int) -> float:
	return BAKED_SHADOW[_index(kind)]


## Puts the weather's shadow softness on the rig's key light (sunny restores full shadows).
static func apply_shadows(rig: Node, kind: int) -> void:
	if rig == null:
		return
	var key: DirectionalLight3D = rig.get_node_or_null(^"KeyLight") as DirectionalLight3D
	if key != null:
		key.shadow_opacity = shadow_opacity(kind)
