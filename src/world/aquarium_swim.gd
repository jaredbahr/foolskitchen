class_name AquariumSwim
extends RefCounted
## Deterministic fish paths for a fish tank (#125). View only: no sim state,
## no global random draws and nothing saved. Each path is a closed loop round
## the tank, a wide ellipse with a gentle second harmonic, so a fish swims the
## length of the glass, turns at the end glass and comes back. A school of
## fish shares one loop, each a little behind and beside the one ahead.
## Positions are in the tank wrapper's space, in metres.

## One fish's loop. Times are display seconds.
class Swim:
	extends RefCounted
	var centre: Vector3 = Vector3.ZERO
	var radius: Vector2 = Vector2.ONE * 0.1
	var wobble: float = 0.0
	var wobble_phase: float = 0.0
	var angular_speed: float = 1.0
	var phase: float = 0.0
	var rise: float = 0.0
	var rise_rate: float = 0.3
	var rise_phase: float = 0.0
	var bob: float = 0.004
	var bob_rate: float = 4.0
	var lag: float = 0.0
	var offset: Vector3 = Vector3.ZERO
	var variant: int = 0
	var speed: float = 0.1

const MIN_FISH: int = 4
const MAX_FISH: int = 6
## Body speeds in metres a second, a calm tetra cruise.
const SPEED_RANGE: Vector2 = Vector2(0.07, 0.12)
## The fish's own size: half its length (nose to tail tip) and half its height.
## tools/build_aquarium.py measures them (aquarium.metrics.json).
const HALF_LENGTH: float = 0.058
const HALF_HEIGHT: float = 0.04
## A school member's furthest offset from the loop it shares.
const SCHOOL_SPREAD: float = 0.018
## Tail-wag yaw, a fast small swing so the fish read as swimming.
const WAG_ANGLE: float = 0.14
const WAG_RATE: float = 9.0
## Nose-to-nose gap between school members, in metres along their loop.
const SCHOOL_GAP: float = 0.13


## `seed_value` is the placed item's id, so each tank swims its own way and the
## same tank always swims the same way. `count` is clamped to 4-6.
static func plan(seed_value: int, count: int, box: AABB, variants: int) -> Array[Swim]:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = hash(seed_value) ^ 0x125
	var fish_count: int = clampi(count, MIN_FISH, MAX_FISH)
	var result: Array[Swim] = []
	# One school of two or three of a kind, the rest swimming alone.
	var school_size: int = random.randi_range(2, 3)
	var school_kind: int = random.randi_range(0, maxi(variants, 1) - 1)
	# Loops are spread out: alternate directions, evenly spaced starting
	# points and their own height bands, so the fish never parade in a line.
	var groups: int = fish_count - school_size + 1
	var school_path: Swim = _loop(random, box, SCHOOL_SPREAD, 0, groups)
	for member: int in school_size:
		var swim: Swim = _copy(school_path)
		swim.variant = school_kind
		swim.lag = SCHOOL_GAP * member / maxf(school_path.speed, 0.01)
		swim.offset = Vector3(0.0, random.randf_range(-1.0, 1.0), random.randf_range(-1.0, 1.0)) * SCHOOL_SPREAD
		if member == 0:
			swim.offset = Vector3.ZERO
		result.append(swim)
	var kind: int = school_kind
	while result.size() < fish_count:
		kind = (kind + 1 + random.randi_range(0, maxi(variants - 2, 0))) % maxi(variants, 1)
		var solo: Swim = _loop(random, box, 0.0, result.size() - school_size + 1, groups)
		solo.variant = kind
		result.append(solo)
	return result


## Where the fish is at `time`, inside `box` whenever the plan was made for it.
static func position(swim: Swim, time: float) -> Vector3:
	var t: float = time - swim.lag
	var angle: float = swim.phase + swim.angular_speed * t
	var x: float = swim.radius.x * sin(angle) + swim.wobble * sin(2.0 * angle + swim.wobble_phase)
	var z: float = swim.radius.y * cos(angle)
	var y: float = swim.rise * sin(swim.rise_rate * t + swim.rise_phase) + swim.bob * sin(swim.bob_rate * t)
	return swim.centre + Vector3(x, y, z) + swim.offset


## The direction it swims (the path's tangent), never zero.
static func heading(swim: Swim, time: float) -> Vector3:
	var t: float = time - swim.lag
	var angle: float = swim.phase + swim.angular_speed * t
	var w: float = swim.angular_speed
	var dx: float = w * (swim.radius.x * cos(angle) + 2.0 * swim.wobble * cos(2.0 * angle + swim.wobble_phase))
	var dz: float = -w * swim.radius.y * sin(angle)
	var dy: float = swim.rise * swim.rise_rate * cos(swim.rise_rate * t + swim.rise_phase)
	var result: Vector3 = Vector3(dx, dy, dz)
	return result.normalized() if result.length() > 0.00001 else Vector3.FORWARD


## The fish's transform: nose (-Z) along its heading, level but for a slight
## pitch on climbs, with a small tail-wag yaw.
static func pose(swim: Swim, time: float) -> Transform3D:
	var at: Vector3 = position(swim, time)
	var ahead: Vector3 = heading(swim, time)
	var flat: Vector3 = Vector3(ahead.x, 0.0, ahead.z)
	var yaw: float = atan2(-flat.x, -flat.z) if flat.length() > 0.00001 else 0.0
	yaw += WAG_ANGLE * sin(WAG_RATE * (time - swim.lag) + swim.phase * 3.0)
	var pitch: float = clampf(asin(clampf(ahead.y, -1.0, 1.0)), -0.35, 0.35)
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(basis, at)


## A fresh loop that keeps a whole fish (and a school's spread) in the box.
static func _loop(random: RandomNumberGenerator, box: AABB, spread: float, group: int, groups: int) -> Swim:
	var swim: Swim = Swim.new()
	var half: Vector3 = box.size * 0.5
	var room_x: float = maxf(0.0, half.x - HALF_LENGTH - spread)
	var room_z: float = maxf(0.0, half.z - HALF_LENGTH - spread)
	var room_y: float = maxf(0.0, half.y - HALF_HEIGHT - spread)
	# Long, flat loops: most of the length, part of the depth.
	var reach_x: float = room_x * random.randf_range(0.55, 1.0)
	swim.wobble = reach_x * random.randf_range(0.0, 0.15)
	swim.radius.x = reach_x - swim.wobble
	swim.radius.y = room_z * random.randf_range(0.45, 1.0)
	var slack_x: float = room_x - reach_x
	var slack_z: float = room_z - swim.radius.y
	swim.wobble_phase = random.randf_range(0.0, TAU)
	swim.bob = minf(0.004, room_y * 0.3)
	# Each group keeps to its own height band, drifting a little within it.
	var band: float = (2.0 * room_y) / maxf(1.0, float(groups))
	swim.rise = minf(band * 0.5, maxf(0.0, room_y - swim.bob)) * random.randf_range(0.3, 0.9)
	var band_centre: float = -room_y + band * (float(group) + 0.5)
	var limit_y: float = maxf(0.0, room_y - swim.rise - swim.bob)
	var centre_y: float = clampf(band_centre, -limit_y, limit_y)
	swim.centre = box.get_center() + Vector3(random.randf_range(-slack_x, slack_x),
		centre_y, random.randf_range(-slack_z, slack_z))
	var loop_length: float = TAU * sqrt((swim.radius.x * swim.radius.x + swim.radius.y * swim.radius.y) * 0.5)
	var speed: float = random.randf_range(SPEED_RANGE.x, SPEED_RANGE.y)
	swim.speed = speed
	swim.angular_speed = TAU * speed / maxf(loop_length, 0.01)
	if group % 2 == 1:
		swim.angular_speed = -swim.angular_speed
	swim.phase = TAU * float(group) / maxf(1.0, float(groups)) + random.randf_range(-0.4, 0.4)
	swim.rise_rate = random.randf_range(0.2, 0.45)
	swim.rise_phase = random.randf_range(0.0, TAU)
	swim.bob_rate = random.randf_range(3.0, 5.0)
	return swim


static func _copy(source: Swim) -> Swim:
	var swim: Swim = Swim.new()
	swim.centre = source.centre
	swim.radius = source.radius
	swim.wobble = source.wobble
	swim.wobble_phase = source.wobble_phase
	swim.angular_speed = source.angular_speed
	swim.phase = source.phase
	swim.rise = source.rise
	swim.rise_rate = source.rise_rate
	swim.rise_phase = source.rise_phase
	swim.bob = source.bob
	swim.bob_rate = source.bob_rate
	swim.speed = source.speed
	return swim
