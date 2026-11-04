class_name DayLight
extends RefCounted
## The day's light as a pure function of the clock (#208): no state, no random
## draws, so a paused capture always looks the same. Presentation only.

## One moment's light.
class Look extends RefCounted:
	var key_color: Color = Color.WHITE
	var key_energy: float = 0.0
	var key_pitch: float = -55.0
	var fill_energy: float = 0.0
	var ambient_color: Color = Color.WHITE
	var ambient_energy: float = 0.0
	var sky_top: Color = Color.BLACK
	var sky_horizon: Color = Color.BLACK
	var sky_ground: Color = Color.BLACK
	var glow: float = 1.0
	var interior_energy: float = 0.0


## The minute of the day the shop shows for `clock`. Opening hours scale, so
## a short test day still runs from opening to closing. `fraction` is the
## view's progress towards the next tick (0..1) for smooth light.
static func minute_for(clock: SimClock, fraction: float, tuning: DayLightTuning) -> float:
	var open: float = float(clock.display_open_minute)
	var close: float = float(clock.display_close_minute)
	match clock.phase:
		SimClock.Phase.MORNING:
			return clampf(open - tuning.prep_lead_minutes, minf(360.0, open), open)
		SimClock.Phase.OPEN:
			var progress: float = clampf((float(clock.phase_tick) + clampf(fraction, 0.0, 1.0))
				/ float(maxi(clock.open_ticks, 1)), 0.0, 1.0)
			return lerpf(open, close, progress)
		SimClock.Phase.LAST_ORDERS:
			var progress: float = clampf((float(clock.phase_tick) + clampf(fraction, 0.0, 1.0))
				/ float(maxi(clock.last_orders_max_ticks, 1)), 0.0, 1.0)
			return minf(close + tuning.last_orders_minutes * progress, 1439.0)
		_:
			return minf(close + tuning.closed_after_minutes, 1439.0)


## The light at `minute`, blended smoothly between the two nearest key frames
## (held flat before the first and after the last).
static func sample(minute: float, tuning: DayLightTuning) -> Look:
	var count: int = tuning.size()
	var before: int = 0
	var after: int = 0
	var t: float = 0.0
	if minute >= tuning.minutes[count - 1]:
		before = count - 1
		after = count - 1
	elif minute > tuning.minutes[0]:
		for index: int in range(1, count):
			if minute <= tuning.minutes[index]:
				before = index - 1
				after = index
				t = (minute - tuning.minutes[before]) / (tuning.minutes[after] - tuning.minutes[before])
				break
	t = smoothstep(0.0, 1.0, t)
	var look: Look = Look.new()
	look.key_color = tuning.key_color[before].lerp(tuning.key_color[after], t)
	look.key_energy = lerpf(tuning.key_energy[before], tuning.key_energy[after], t)
	look.key_pitch = lerpf(tuning.key_pitch[before], tuning.key_pitch[after], t)
	look.fill_energy = lerpf(tuning.fill_energy[before], tuning.fill_energy[after], t)
	look.ambient_color = tuning.ambient_color[before].lerp(tuning.ambient_color[after], t)
	look.ambient_energy = lerpf(tuning.ambient_energy[before], tuning.ambient_energy[after], t)
	look.sky_top = tuning.sky_top[before].lerp(tuning.sky_top[after], t)
	look.sky_horizon = tuning.sky_horizon[before].lerp(tuning.sky_horizon[after], t)
	look.sky_ground = tuning.sky_ground[before].lerp(tuning.sky_ground[after], t)
	look.glow = lerpf(tuning.glow[before], tuning.glow[after], t)
	look.interior_energy = lerpf(tuning.interior_energy[before], tuning.interior_energy[after], t)
	return look
