class_name NeighbourhoodLife
extends RefCounted
## Small idle life on the street (#423), cheap, deterministic and driven only by the
## dressing's display clock: the shops' hanging signs sway, birds hop about the lawn
## beside the lot, and a few leaves drift off the planter trees. Like the rest of the
## neighbourhood it is view-only: no colliders, lights, sim agents, saves or random
## draws. Every motion is a closed-form function of (seconds, an integer hash), so a
## paused capture or a review time always shows the same frame, and nothing runs once
## the dressing stops processing.
##
## Nodes: one small mesh per swinging sign, one per bird with all the birds' contact
## shadows in a single MultiMesh, and one MultiMesh for all the leaves.

const BIRD_SIZE: float = 1.0
## Birds stand on the mown lawn, a hair above its flat plane.
const LAWN_Y: float = -0.033
const SHADOW_Y: float = -0.029
const LEAF_FLOOR: float = 0.02
const GAP: float = 0.7
## Where the lawn homes sit, behind the pavement (v is negative inside the block).
const HOME_V: Array[float] = [-1.7, -2.6, -1.1, -2.1]

var street: StreetSet
var frame: Transform3D = Transform3D.IDENTITY
var shift: float = 0.0
var paving_top: float = 0.055
## (u, v, height) of each planter tree's crown.
var crowns: Array[Vector3] = []
var signs: Array[Dictionary] = []
## The maximum lot's u extent and the extent of the neighbouring row: birds live outside both.
var lot_u: Vector2 = Vector2.ZERO
var row_u: Vector2 = Vector2.ZERO

var sign_nodes: Array[MeshInstance3D] = []
var bird_nodes: Array[MeshInstance3D] = []
var bird_shadows: MultiMeshInstance3D
var leaves: MultiMeshInstance3D
## The exact CPU copies of what was last sent to the MultiMeshes (a headless renderer cannot read them back).
var bird_shadow_transforms: Array[Transform3D] = []
var leaf_transforms: Array[Transform3D] = []
var _bird_spots: Array[Array] = []
var _sign_pivots: Array[Vector3] = []
var _material: StandardMaterial3D


func _r(a: int, b: int) -> float:
	return NeighbourhoodGround.hash01(a, b, street.seed_salt + 733)


# --- building ---------------------------------------------------------------

func build(parent: Node3D) -> void:
	if street == null:
		street = StreetSet.standard()
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 1.0
	_material.metallic_specular = 0.0
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_material.disable_receive_shadows = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_signs(parent)
	_build_birds(parent)
	_build_leaves(parent)


func _node(label: String, mesh: ArrayMesh) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _build_signs(parent: Node3D) -> void:
	for index: int in signs.size():
		var entry: Dictionary = signs[index]
		var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
		var main: Color = entry["main"]
		var accent: Color = entry["accent"]
		var length: float = NeighbourhoodBuildings.SIGN_LEN
		# Two short chains from the bracket and a framed blade board hanging below.
		for z: float in [0.07, length - 0.05]:
			pen.box(Vector3(-0.006, -0.08, z - 0.006), Vector3(0.006, 0.0, z + 0.006), street.metal)
		pen.box(Vector3(-0.022, -0.32, 0.04), Vector3(0.022, -0.075, length - 0.02), street.trim)
		pen.box(Vector3(-0.027, -0.305, 0.055), Vector3(0.027, -0.09, length - 0.035), main)
		pen.box(Vector3(-0.03, -0.235, 0.09), Vector3(0.03, -0.165, length - 0.075), accent)
		var node: MeshInstance3D = _node("Sign%d" % index, pen.soup.to_mesh())
		parent.add_child(node)
		sign_nodes.append(node)
		_sign_pivots.append(entry["pivot"])


func _bird_mesh(body: Color) -> ArrayMesh:
	var pen: NeighbourhoodBuildings.Pen = NeighbourhoodBuildings.Pen.new()
	var belly: Color = body.lightened(0.42)
	var wing: Color = body.darkened(0.2)
	var beak: Color = Color("e0a53a")
	pen.lump(Vector3(0.0, 0.1, 0.0), 0.08, 0.075, 0.11, 0.3, body.lightened(0.05), belly)
	pen.lump(Vector3(0.0, 0.17, 0.085), 0.055, 0.055, 0.055, 0.5, body.lightened(0.12), body.lightened(0.2))
	pen.box(Vector3(-0.014, 0.155, 0.128), Vector3(0.014, 0.172, 0.172), beak)
	for x: float in [-0.052, 0.052]:
		pen.box(Vector3(x - 0.012, 0.172, 0.12), Vector3(x + 0.012, 0.188, 0.134), Color("2b1f22"))
	for x: float in [-0.086, 0.074]:
		pen.box(Vector3(x, 0.095, -0.07), Vector3(x + 0.012, 0.145, 0.055), wing)
	pen.box(Vector3(-0.035, 0.1, -0.17), Vector3(0.035, 0.125, -0.09), wing.darkened(0.05))
	for x: float in [-0.03, 0.03]:
		pen.box(Vector3(x - 0.006, 0.0, -0.005), Vector3(x + 0.006, 0.05, 0.015), beak.darkened(0.25))
	return pen.soup.to_mesh()


func _build_birds(parent: Node3D) -> void:
	var count: int = street.birds if not street.bird_colors.is_empty() else 0
	var homes: Array[Vector2] = []
	var gap_left: float = lot_u.x - GAP
	var gap_right: float = lot_u.y + GAP
	var homes_u: Array[float] = [gap_left, gap_right, row_u.x - 1.1, row_u.y + 1.1]
	for index: int in count:
		var slot: int = index % homes_u.size()
		var u: float = homes_u[slot]
		var z: float = shift + HOME_V[slot]
		var spread: float = 0.26 + 0.08 * _r(index, 4)
		homes.append(Vector2(u, z))
		_bird_spots.append([Vector2(u - spread, z - 0.12), Vector2(u + spread, z + 0.12 * (1.0 if _r(index, 5) < 0.5 else -1.0))])
		var tone: Color = street.bird_colors[index % street.bird_colors.size()]
		var node: MeshInstance3D = _node("Bird%d" % index, _bird_mesh(tone))
		node.scale = Vector3.ONE * BIRD_SIZE
		parent.add_child(node)
		bird_nodes.append(node)
	if count == 0:
		return
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var ring: Array[Vector2] = []
	for step: int in 8:
		var angle: float = TAU * float(step) / 8.0
		ring.append(Vector2(cos(angle) * 0.1, sin(angle) * 0.075))
	soup.star(Vector2.ZERO, ring, 0.0, NeighbourhoodFurniture.SHADOW_COLOUR)
	var flat: StandardMaterial3D = StandardMaterial3D.new()
	flat.vertex_color_use_as_albedo = true
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flat.disable_receive_shadows = true
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = soup.to_mesh()
	instances.instance_count = count
	bird_shadows = MultiMeshInstance3D.new()
	bird_shadows.name = "BirdShadows"
	bird_shadows.multimesh = instances
	bird_shadows.material_override = flat
	bird_shadows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bird_shadows)


func _build_leaves(parent: Node3D) -> void:
	var count: int = street.leaves if not crowns.is_empty() and not street.leaf_colors.is_empty() else 0
	if count == 0:
		return
	var soup: NeighbourhoodGround.Soup = NeighbourhoodGround.Soup.new()
	var a: Vector3 = Vector3(-0.055, 0.0, 0.0)
	var b: Vector3 = Vector3(0.0, 0.0, 0.04)
	var c: Vector3 = Vector3(0.055, 0.0, 0.0)
	var d: Vector3 = Vector3(0.0, 0.0, -0.04)
	soup.tri(a, b, c, Vector3.UP, Color.WHITE)
	soup.tri(a, c, d, Vector3.UP, Color.WHITE)
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = soup.to_mesh()
	instances.instance_count = count
	for index: int in count:
		instances.set_instance_color(index, street.leaf_colors[index % street.leaf_colors.size()])
	leaves = MultiMeshInstance3D.new()
	leaves.name = "Leaves"
	leaves.multimesh = instances
	leaves.material_override = _material
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(leaves)
	leaf_transforms.resize(count)


# --- motion -----------------------------------------------------------------

func apply(seconds: float) -> void:
	_apply_signs(seconds)
	_apply_birds(seconds)
	_apply_leaves(seconds)


func sign_angle(index: int, seconds: float) -> float:
	var amplitude: float = deg_to_rad(street.sign_sway_degrees) * (0.75 + 0.25 * _r(index, 1))
	var rate: float = 1.5 + 0.5 * _r(index, 2)
	var phase: float = _r(index, 3) * TAU
	return amplitude * (0.82 * sin(seconds * rate + phase) + 0.18 * sin(seconds * rate * 2.3 + phase * 2.0))


func _apply_signs(seconds: float) -> void:
	for index: int in sign_nodes.size():
		sign_nodes[index].transform = frame * Transform3D(Basis(Vector3.BACK, sign_angle(index, seconds)), _sign_pivots[index])


## One bird's pose: its ground position (u, z), height above the lawn, nose-down pitch and heading.
## It pecks, looks up, then (two cycles in three) hops to its other spot and turns back.
@warning_ignore("integer_division")
func bird_pose(index: int, seconds: float) -> Dictionary:
	var spots: Array = _bird_spots[index]
	var period: float = 2.8 + 1.6 * _r(index, 1)
	var progress: float = seconds / period + _r(index, 2)
	var cycle: int = int(floor(progress))
	var s: float = progress - float(cycle)
	var done: int = (cycle / 3) * 2 + mini(cycle % 3, 2)
	var moves: bool = cycle % 3 != 2
	var from: Vector2 = spots[done % 2]
	var to: Vector2 = spots[(done + 1) % 2]
	var move: float = clampf((s - 0.62) / 0.2, 0.0, 1.0) if moves else 0.0
	move = smoothstep(0.0, 1.0, move)
	var hop: float = sin(move * PI) * 0.12
	if not moves:
		hop = maxf(0.0, sin(clampf((s - 0.7) / 0.14, 0.0, 1.0) * PI)) * 0.04
	var pitch: float = 0.0
	if s < 0.54:
		pitch = 0.7 * maxf(0.0, sin(s / 0.54 * PI * 3.0))
	elif s < 0.62:
		pitch = -0.18
	elif moves:
		pitch = -0.12 * sin(move * PI)
	var before: int = maxi(cycle - 1, 0)
	var before_done: int = (before / 3) * 2 + mini(before % 3, 2)
	var before_from: Vector2 = spots[before_done % 2]
	var before_to: Vector2 = spots[(before_done + 1) % 2]
	var heading: float = lerp_angle(_heading(before_from, before_to), _heading(from, to), smoothstep(0.0, 0.14, s))
	var at: Vector2 = from.lerp(to, move)
	return {"u": at.x, "z": at.y, "hop": hop, "pitch": pitch, "heading": heading}


static func _heading(from: Vector2, to: Vector2) -> float:
	var direction: Vector2 = to - from
	return atan2(direction.x, direction.y)


func _apply_birds(seconds: float) -> void:
	bird_shadow_transforms.clear()
	for index: int in bird_nodes.size():
		var pose: Dictionary = bird_pose(index, seconds)
		var basis: Basis = Basis(Vector3.UP, pose["heading"]) * Basis(Vector3.RIGHT, pose["pitch"])
		var at: Vector3 = Vector3(pose["u"], LAWN_Y + float(pose["hop"]), pose["z"])
		bird_nodes[index].transform = frame * Transform3D(basis, at)
		var lift: float = float(pose["hop"])
		var shadow: Transform3D = frame * Transform3D(Basis(Vector3.UP, pose["heading"]).scaled(Vector3.ONE * (1.0 - minf(lift * 2.5, 0.4))),
			Vector3(pose["u"], SHADOW_Y, pose["z"]))
		bird_shadow_transforms.append(shadow)
		if bird_shadows != null:
			bird_shadows.multimesh.set_instance_transform(index, shadow)


## A leaf's whole fall is one function of the clock: it lifts off a crown, tumbles on a
## breeze along the pavement, settles and shrinks away, then the next leaf of its cycle starts.
func leaf_transform(index: int, seconds: float) -> Transform3D:
	var crown: Vector3 = crowns[index % crowns.size()]
	var duration: float = 6.0 + 3.0 * _r(index, 11)
	var progress: float = seconds / duration + _r(index, 12)
	var cycle: int = int(floor(progress))
	var s: float = progress - float(cycle)
	var salt: int = index * 131 + cycle
	var wind: float = 1.0 if _r(salt >> 2, 13) < 0.5 else -1.0
	var start: Vector3 = Vector3(crown.x + (_r(salt, 14) - 0.5) * 0.45, crown.z * (0.7 + 0.5 * _r(salt, 15)), crown.y + (_r(salt, 16) - 0.5) * 0.35)
	var reach: float = 0.8 + 0.7 * _r(salt, 17)
	var drift: float = wind * reach * s + sin(s * TAU * 1.5 + _r(salt, 18) * TAU) * 0.1
	var fall: float = pow(s, 0.85)
	var height: float = lerpf(start.y, LEAF_FLOOR, fall) + sin(s * TAU * 3.0 + _r(salt, 19) * TAU) * 0.03 * (1.0 - fall)
	var grow: float = smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.86, 1.0, s))
	var spin: float = s * TAU * (1.2 + _r(salt, 20))
	var tilt: float = sin(s * TAU * 3.0 + _r(salt, 21) * TAU) * 0.8 * (1.0 - 0.85 * s)
	var basis: Basis = (Basis(Vector3.UP, spin) * Basis(Vector3.RIGHT, tilt)).scaled(Vector3.ONE * maxf(grow, 0.0001))
	var local: Vector3 = Vector3(start.x + drift, paving_top + height, shift + start.z + (_r(salt, 22) - 0.5) * 0.5 * s)
	return frame * Transform3D(basis, local)


func _apply_leaves(seconds: float) -> void:
	if leaves == null:
		return
	for index: int in leaf_transforms.size():
		var placement: Transform3D = leaf_transform(index, seconds)
		leaf_transforms[index] = placement
		leaves.multimesh.set_instance_transform(index, placement)
