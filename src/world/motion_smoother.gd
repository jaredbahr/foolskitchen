class_name MotionSmoother
extends RefCounted
## Smooth motion between sim ticks (view only). The sim moves people in 10 Hz
## steps; drawn as they are, every pose is held for about three frames at
## 30 fps. This keeps, per person, the presented pose of the last two ticks
## and draws the blend between them at the clock's fraction of the way to the
## next tick (`alpha`, 0..1): the picture runs one tick (0.1 s at 1x) behind
## the sim and follows its recorded edge centres, including turns completed
## within one tick. It never reads or writes sim state; ShopView
## feeds it the frames AgentPresentationController already makes.
##
## Not blended (a snap, drawn at once): a person who is new, hidden or shown
## again (the restroom), a discontinuous/stale/missing runtime trace, or a
## recorded segment longer than SNAP_DISTANCE (a teleport/reset); a world tick
## that went backwards. Legacy endpoint-only Frames retain the jump limit.
## Sitting down and standing up blend the walk into or out of the seat cell and
## switch the pose at the tick, so a seated figure never slides.

## Further than any walk, nudge or reach in one tick: a jump, not a step.
const SNAP_DISTANCE: float = 1.0


## What is blended for one person at one tick.
class Pose extends RefCounted:
	## Drawn floor point (sim position plus display offsets).
	var position: Vector3 = Vector3.ZERO
	## Floor point before seated/separation offsets (may include crate reach).
	var floor_position: Vector3 = Vector3.ZERO
	## Bare cell/path projection used by the actual movement trace.
	var sim_floor_position: Vector3 = Vector3.ZERO
	## Facing (PersonView rotation.y); `has_yaw` false while none is known yet.
	var yaw: float = 0.0
	var has_yaw: bool = false
	var moving: bool = false
	var seated: bool = false
	var seat_height: float = 0.0
	var seated_lean_degrees: float = 0.0
	var bending: bool = false
	var hidden: bool = false
	var fade: float = 1.0
	var crate_slide: float = 0.0
	## Where a sliding crate goes (AgentPresentationController.Frame).
	var crate_spot: Vector3 = Vector3.ZERO
	var crate_layer: int = 0

	func copy() -> Pose:
		var out: Pose = Pose.new()
		out.position = position
		out.floor_position = floor_position
		out.sim_floor_position = sim_floor_position
		out.yaw = yaw
		out.has_yaw = has_yaw
		out.moving = moving
		out.seated = seated
		out.seat_height = seat_height
		out.seated_lean_degrees = seated_lean_degrees
		out.bending = bending
		out.hidden = hidden
		out.fade = fade
		out.crate_slide = crate_slide
		out.crate_spot = crate_spot
		out.crate_layer = crate_layer
		return out


## Detached world-space movement points with actual within-tick timestamps.
class Travel extends RefCounted:
	var points: Array[Vector3] = []
	var times: Array[float] = []
	var motion_end_time: float = 0.0


class Track extends RefCounted:
	var tick: int = 0
	var previous: Pose
	var current: Pose
	var travel: Travel


var _tracks: Dictionary[int, Track] = {}


## The pose a frame presents (yaw from its facing, else the last one known).
static func pose_of(frame: AgentPresentationController.Frame, last: Pose = null) -> Pose:
	var pose: Pose = Pose.new()
	_fill(pose, frame, last)
	return pose


static func _fill(pose: Pose, frame: AgentPresentationController.Frame, last: Pose) -> void:
	pose.position = frame.floor_position + frame.display_offset
	pose.floor_position = frame.floor_position
	pose.sim_floor_position = frame.sim_floor_position
	var flat: Vector3 = Vector3(frame.facing_direction.x, 0.0, frame.facing_direction.z)
	if flat.length_squared() > 0.000001 and flat.is_finite():
		pose.yaw = atan2(-flat.x, -flat.z)
		pose.has_yaw = true
	elif last != null:
		pose.yaw = last.yaw
		pose.has_yaw = last.has_yaw
	pose.moving = frame.moving
	pose.seated = frame.seated
	pose.seat_height = frame.seat_height
	pose.seated_lean_degrees = frame.seated_lean_degrees
	pose.bending = frame.bending
	pose.hidden = frame.hidden
	pose.fade = frame.fade
	pose.crate_slide = frame.crate_slide
	pose.crate_spot = frame.crate_spot
	pose.crate_layer = frame.crate_layer


## Records `frame`'s pose for person `id` at world tick `tick`. Called every
## drawn frame: the same tick again refreshes the newest pose (a change made
## between ticks, e.g. in the morning, shows at once); a later tick moves the
## newest pose to `previous`. Runtime traces supply the actual latest tick's
## route when several ticks pass between frames. Hand-built legacy Frames
## retain their endpoint-only interpolation contract.
func observe(id: int, tick: int, frame: AgentPresentationController.Frame) -> void:
	var track: Track = _tracks.get(id) as Track
	if frame.movement_trace_expected:
		_observe_travel(id, tick, frame, track)
		return
	if track == null or tick < track.tick:
		var fresh: Pose = pose_of(frame)
		track = Track.new()
		track.tick = tick
		track.previous = fresh
		track.current = fresh
		_tracks[id] = track
		return
	if tick == track.tick and track.current != track.previous:
		# Same tick: refresh the newest pose in place, no new Pose (a new one is
		# made only on a new tick, or while previous and current are one object).
		_fill(track.current, frame, track.current)
	else:
		var pose: Pose = pose_of(frame, track.current)
		if tick > track.tick:
			var ticks: int = tick - track.tick
			track.previous = track.current if ticks == 1 \
				else _between(track.current, pose, float(ticks - 1) / float(ticks))
			track.tick = tick
		track.current = pose
	if not continuous(track.previous, track.current):
		track.previous = track.current


## Runtime movement must use the actual latest tick, even when rendering skipped
## earlier ticks. Missing, stale or discontinuous traces snap instead of drawing
## a guessed chord. Legacy hand-built Frames keep the endpoint-only test API.
func _observe_travel(id: int, tick: int, frame: AgentPresentationController.Frame, track: Track) -> void:
	var travel: Travel = _travel_of(frame, tick)
	if track == null or tick < track.tick or travel == null:
		var pose: Pose = pose_of(frame)
		if track == null:
			track = Track.new()
		track.tick = tick
		track.previous = pose
		track.current = pose
		track.travel = null
		_tracks[id] = track
		return
	if tick == track.tick:
		var was_hidden: bool = track.current.hidden
		_fill(track.current, frame, track.current)
		if was_hidden != track.current.hidden:
			track.previous = track.current
			track.travel = null
		return
	var latest: Pose = pose_of(frame, track.current)
	var visibility_changed: bool = track.current.hidden != latest.hidden
	var previous: Pose = track.current
	if tick - track.tick != 1:
		# The latest trace already starts at the preceding tick's actual point;
		# no interpolation across the several unseen ticks is needed.
		previous = latest.copy()
		previous.sim_floor_position = travel.points[0]
		previous.floor_position = travel.points[0]
		previous.position = travel.points[0] + latest.position - latest.sim_floor_position
		if latest.seated and travel.motion_end_time > 0.0:
			# The newest pose cannot describe the unseen start of an arrival.
			previous.seated = false
			previous.position = travel.points[0]
	elif not previous.sim_floor_position.is_equal_approx(travel.points[0]):
		# An out-of-tick reset or teleport is not a continuous walking segment.
		previous = latest
		travel = null
	if visibility_changed:
		previous = latest
		travel = null
	track.tick = tick
	track.previous = previous
	track.current = latest
	track.travel = travel


static func _travel_of(frame: AgentPresentationController.Frame, tick: int) -> Travel:
	var raw: Dictionary = frame.movement_trace
	if not raw.get("tick") is int or raw.get("tick") != tick or raw.get("discontinuous") != false:
		return null
	var points: Variant = raw.get("points")
	var times: Variant = raw.get("times")
	if not points is Array or not times is Array or points.size() < 2 or points.size() != times.size():
		return null
	var travel: Travel = Travel.new()
	for index: int in range(points.size()):
		if not points[index] is Vector3 or not (times[index] is float or times[index] is int):
			return null
		var point: Vector3 = points[index]
		var time: float = float(times[index])
		if not point.is_finite() or not is_finite(time) or time < 0.0 or time > 1.0:
			return null
		if index > 0:
			if time < travel.times[-1] or point.distance_to(travel.points[-1]) > SNAP_DISTANCE:
				return null
			if time == travel.times[-1] and not point.is_equal_approx(travel.points[-1]):
				return null
			if not point.is_equal_approx(travel.points[-1]):
				travel.motion_end_time = time
		travel.points.append(point)
		travel.times.append(time)
	if travel.times[0] != 0.0 or travel.times[-1] != 1.0 \
			or not travel.points[-1].is_equal_approx(frame.sim_floor_position):
		return null
	return travel


## Drops the blend for person `id`: what is drawn now is where the next tick
## blends from. ShopView calls it whenever it draws the newest state as it is
## (alpha 1: the clock not running this world, e.g. all morning), so a reset
## made then (staff back at their posts) is never slid across at opening.
func settle(id: int) -> void:
	var track: Track = _tracks.get(id) as Track
	if track != null:
		track.previous = track.current
		track.travel = null


## True when going from `a` to `b` in one tick may be blended.
static func continuous(a: Pose, b: Pose) -> bool:
	if a.hidden != b.hidden:
		return false
	var step: Vector3 = b.position - a.position
	step.y = 0.0
	return step.length() <= SNAP_DISTANCE and step.is_finite()


## Changes `frame` (made for the newest tick) into what is drawn at `alpha`
## (0 the previous tick's pose .. 1 the newest). At 1 the frame is unchanged.
func blend(id: int, alpha: float, frame: AgentPresentationController.Frame) -> void:
	var track: Track = _tracks.get(id) as Track
	if track == null or alpha >= 1.0 or track.previous == track.current:
		return
	var t: float = clampf(alpha, 0.0, 1.0)
	if track.travel != null:
		_blend_travel(track, t, frame)
		return
	var a: Pose = track.previous
	var b: Pose = track.current
	var from: Vector3 = a.position
	var to: Vector3 = b.position
	if a.seated != b.seated:
		# Into or out of a seat: the walk ends (or starts) on the seat cell, and
		# the person stands until the tick they are seated (or after it).
		from = a.floor_position if a.seated else a.position
		to = b.floor_position if b.seated else b.position
		if b.seated:
			frame.seated = false
			frame.seat_height = 0.0
			frame.seated_lean_degrees = 0.0
			frame.moving = not from.is_equal_approx(to)
	frame.floor_position = from.lerp(to, t)
	frame.display_offset = Vector3.ZERO
	if a.has_yaw or b.has_yaw:
		var yaw: float = lerp_angle(a.yaw, b.yaw, t) if a.has_yaw and b.has_yaw else (b.yaw if b.has_yaw else a.yaw)
		frame.facing_direction = Vector3(-sin(yaw), 0.0, -cos(yaw))
	# Still walking the last bit into a stop (not into a bend for a crate).
	if a.moving and not frame.moving and not frame.seated and not b.bending \
			and not from.is_equal_approx(to):
		frame.moving = true
	_blend_properties(a, b, t, frame)


func _blend_travel(track: Track, t: float, frame: AgentPresentationController.Frame) -> void:
	var travel: Travel = track.travel
	var index: int = 0
	while index < travel.times.size() - 2 and t > travel.times[index + 1]:
		index += 1
	var duration: float = travel.times[index + 1] - travel.times[index]
	var fraction: float = clampf((t - travel.times[index]) / duration, 0.0, 1.0) if duration > 0.0 else 1.0
	var point: Vector3 = travel.points[index].lerp(travel.points[index + 1], fraction)
	var direction: Vector3 = travel.points[index + 1] - travel.points[index]
	var a: Pose = track.previous
	var b: Pose = track.current
	var start_offset: Vector3 = a.position - a.sim_floor_position
	var end_offset: Vector3 = b.position - b.sim_floor_position
	if b.seated and travel.motion_end_time > 0.0:
		# Seat only at the actual arrival time, including a terminal hold. A
		# skipped rendering tick must never slide the final seated pose in.
		if t < travel.motion_end_time:
			frame.seated = false
			frame.seat_height = 0.0
			frame.seated_lean_degrees = 0.0
			start_offset = Vector3.ZERO if a.seated else start_offset
			end_offset = Vector3.ZERO
		else:
			frame.seated = true
			frame.seat_height = b.seat_height
			frame.seated_lean_degrees = b.seated_lean_degrees
			start_offset = end_offset
	elif a.seated != b.seated:
		if a.seated:
			start_offset = Vector3.ZERO
		if b.seated:
			end_offset = Vector3.ZERO
			frame.seated = false
			frame.seat_height = 0.0
			frame.seated_lean_degrees = 0.0
	frame.sim_floor_position = point
	frame.floor_position = point
	frame.display_offset = start_offset.lerp(end_offset, t)
	frame.moving = direction.length_squared() > 0.000001 and not frame.seated
	if frame.moving:
		frame.facing_direction = direction
	_blend_properties(a, b, t, frame)


static func _blend_properties(a: Pose, b: Pose, t: float, frame: AgentPresentationController.Frame) -> void:
	frame.fade = lerpf(a.fade, b.fade, t)
	frame.crate_slide = lerpf(a.crate_slide, b.crate_slide, t)
	if b.crate_slide <= 0.0 and a.crate_slide > 0.0:
		# The slide ends this tick (the crate is in the hands): the newest frame
		# has no spot, so it finishes towards the one it slid from.
		frame.crate_spot = a.crate_spot
		frame.crate_layer = a.crate_layer
	frame.clip = PersonPresentation.clip_for_state(frame.moving, frame.seated, frame.carrying, frame.working,
		frame.bending)


## Drops the people no longer present (`alive` ids).
func retain(alive: Dictionary[int, bool]) -> void:
	for id: int in _tracks.keys():
		if not alive.has(id):
			_tracks.erase(id)


func clear() -> void:
	_tracks.clear()


func has_track(id: int) -> bool:
	return _tracks.has(id)


## True while person `id` has a previous pose to blend from.
func blending(id: int) -> bool:
	var track: Track = _tracks.get(id) as Track
	return track != null and track.previous != track.current


static func _between(a: Pose, b: Pose, t: float) -> Pose:
	var out: Pose = a.copy()
	out.position = a.position.lerp(b.position, t)
	out.floor_position = a.floor_position.lerp(b.floor_position, t)
	out.sim_floor_position = a.sim_floor_position.lerp(b.sim_floor_position, t)
	if a.has_yaw and b.has_yaw:
		out.yaw = lerp_angle(a.yaw, b.yaw, t)
	out.fade = lerpf(a.fade, b.fade, t)
	out.crate_slide = lerpf(a.crate_slide, b.crate_slide, t)
	return out
