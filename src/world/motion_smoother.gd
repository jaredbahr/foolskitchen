class_name MotionSmoother
extends RefCounted
## Smooth motion between sim ticks (view only). The sim moves people in 10 Hz
## steps; drawn as they are, every pose is held for about three frames at
## 30 fps. This keeps, per person, the presented pose of the last two ticks
## and draws the blend between them at the clock's fraction of the way to the
## next tick (`alpha`, 0..1): the picture runs one tick (0.1 s at 1x) behind
## the sim and moves every frame. It never reads or writes sim state; ShopView
## feeds it the frames AgentPresentationController already makes.
##
## Not blended (a snap, drawn at once): a person who is new, hidden or shown
## again (the restroom), or who moved further than SNAP_DISTANCE in one tick
## (a teleport: the morning reset, a reload); a world tick that went backwards.
## Sitting down and standing up blend the walk into or out of the seat cell and
## switch the pose at the tick, so a seated figure never slides.

## Further than any walk, nudge or reach in one tick: a jump, not a step.
const SNAP_DISTANCE: float = 1.0


## What is blended for one person at one tick.
class Pose extends RefCounted:
	## Drawn floor point (sim position plus display offsets).
	var position: Vector3 = Vector3.ZERO
	## The sim's own floor point, without seat or separation offsets.
	var floor_position: Vector3 = Vector3.ZERO
	## Facing (PersonView rotation.y); `has_yaw` false while none is known yet.
	var yaw: float = 0.0
	var has_yaw: bool = false
	var moving: bool = false
	var seated: bool = false
	var bending: bool = false
	var hidden: bool = false
	var fade: float = 1.0
	var crate_slide: float = 0.0

	func copy() -> Pose:
		var out: Pose = Pose.new()
		out.position = position
		out.floor_position = floor_position
		out.yaw = yaw
		out.has_yaw = has_yaw
		out.moving = moving
		out.seated = seated
		out.bending = bending
		out.hidden = hidden
		out.fade = fade
		out.crate_slide = crate_slide
		return out


class Track extends RefCounted:
	var tick: int = 0
	var previous: Pose
	var current: Pose


var _tracks: Dictionary[int, Track] = {}


## The pose a frame presents (yaw from its facing, else the last one known).
static func pose_of(frame: AgentPresentationController.Frame, last: Pose = null) -> Pose:
	var pose: Pose = Pose.new()
	pose.position = frame.floor_position + frame.display_offset
	pose.floor_position = frame.floor_position
	var flat: Vector3 = Vector3(frame.facing_direction.x, 0.0, frame.facing_direction.z)
	if flat.length_squared() > 0.000001 and flat.is_finite():
		pose.yaw = atan2(-flat.x, -flat.z)
		pose.has_yaw = true
	elif last != null:
		pose.yaw = last.yaw
		pose.has_yaw = last.has_yaw
	pose.moving = frame.moving
	pose.seated = frame.seated
	pose.bending = frame.bending
	pose.hidden = frame.hidden
	pose.fade = frame.fade
	pose.crate_slide = frame.crate_slide
	return pose


## Records `frame`'s pose for person `id` at world tick `tick`. Called every
## drawn frame: the same tick again refreshes the newest pose (a change made
## between ticks, e.g. in the morning, shows at once); a later tick moves the
## newest pose to `previous`. Several ticks in one frame (2x/4x speed) keep the
## pose one tick back on the straight line between the two seen.
func observe(id: int, tick: int, frame: AgentPresentationController.Frame) -> void:
	var track: Track = _tracks.get(id) as Track
	var pose: Pose = pose_of(frame, track.current if track != null else null)
	if track == null or tick < track.tick:
		track = Track.new()
		track.tick = tick
		track.previous = pose
		track.current = pose
		_tracks[id] = track
		return
	if tick > track.tick:
		var ticks: int = tick - track.tick
		track.previous = track.current if ticks == 1 \
			else _between(track.current, pose, float(ticks - 1) / float(ticks))
		track.tick = tick
	track.current = pose
	if not continuous(track.previous, pose):
		track.previous = pose


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
	frame.fade = lerpf(a.fade, b.fade, t)
	frame.crate_slide = lerpf(a.crate_slide, b.crate_slide, t)
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


static func _between(a: Pose, b: Pose, t: float) -> Pose:
	var out: Pose = a.copy()
	out.position = a.position.lerp(b.position, t)
	out.floor_position = a.floor_position.lerp(b.floor_position, t)
	if a.has_yaw and b.has_yaw:
		out.yaw = lerp_angle(a.yaw, b.yaw, t)
	out.fade = lerpf(a.fade, b.fade, t)
	out.crate_slide = lerpf(a.crate_slide, b.crate_slide, t)
	return out
