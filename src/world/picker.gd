class_name Picker
extends RefCounted
## Pure picking helpers. Callers supply drawn positions and the camera's ray.

const PICK_RADIUS: float = 0.6


## Nearest drawn position on the XZ plane, or -1. Exact ties use the lowest id.
## Positions can retain their mesh height; vertical distance is ignored.
static func pick_agent(world_pos: Vector3, agents_positions: Dictionary) -> int:
	# Match the radius to Vector3 precision so Vector3(0.6, 0, 0) is inclusive.
	var radius: float = Vector3(PICK_RADIUS, 0.0, 0.0).x
	var radius_squared: float = radius * radius
	var nearest_id: int = -1
	var nearest_squared: float = INF
	for agent_id: int in agents_positions:
		var drawn_pos: Vector3 = agents_positions[agent_id]
		var dx: float = drawn_pos.x - world_pos.x
		var dz: float = drawn_pos.z - world_pos.z
		var distance_squared: float = dx * dx + dz * dz
		if distance_squared > radius_squared:
			continue
		if distance_squared < nearest_squared or (distance_squared == nearest_squared and agent_id < nearest_id):
			nearest_id = agent_id
			nearest_squared = distance_squared
	return nearest_id


## Intersects the forward ray with y = 0. Direction need not be normalized.
## A parallel ray or an intersection behind the origin has no floor hit.
static func floor_intersection(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	if ray_direction.y == 0.0:
		return null
	var distance: float = -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null
	var hit: Vector3 = ray_origin + ray_direction * distance
	hit.y = 0.0
	return hit
