extends "res://src/world/main.gd"
## Explicit unsaved owner-Floor fixture; every person and task comes from normal
## paid seed-one service. No placement, money, XP, guest, route or RNG staging.

const SEARCH_TICKS: int = 12000
const SOURCE_FILES: Array[String] = ["res://tools/movement_review.gd", "res://tools/movement_review.tscn",
	"res://src/sim/agents/sim_agent.gd", "res://src/sim/movement_coordinator.gd",
	"res://src/world/agent_presentation_controller.gd", "res://src/world/motion_smoother.gd",
	"res://src/world/shop_view.gd", "res://src/world/main.gd", "res://tools/screenshot.gd",
	"res://data/balance/movement.tres", "res://data/layouts/tier1_deeper.tres"]
var _review_pair: Array[int] = []
var _review_state: Dictionary = {}
var _review_render: Dictionary = {}
var _review_frames: int = 0
var _review_ready: bool = false
var _review_out: String = ""


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_review_out = arg.trim_prefix("--out=")
	if _review_out.is_empty() or FileAccess.file_exists(_review_out.path_join("shot_0060.png")) \
			or FileAccess.file_exists(_review_out.path_join("shot_0060.json")) \
			or FileAccess.file_exists(_review_out.path_join("shot_0060.movement.json")):
		_review_fail("a fresh capture output is required")
		return
	super._ready()
	Clock.set_speed(0)
	var owner: OwnerAgent = sim.owner_agent() if sim != null else null
	if owner == null or not select_agent(owner.id) or not assign_owner_mode(&"floor"):
		_review_fail("the ordinary selected-owner Floor command failed")
		return
	clear_selection()
	if GameState.master_seed != 1 or Clock.sim.day != 1 or Clock.sim.phase != SimClock.Phase.MORNING \
			or not Clock.sim.start_service():
		_review_fail("the actual seed-one service did not open")
		return
	for _tick_index: int in SEARCH_TICKS:
		if Clock.sim.phase not in [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]:
			break
		run_ticks(1)
		if sim.served_today > 0 and int(Economy.ledger.day_totals(Clock.sim.day).get(Ledger.SALE, 0)) > 0:
			_review_pair = _passing_pair()
			if not _review_pair.is_empty():
				break
	if _review_pair.is_empty():
		print("MOVEMENT_REVIEW_SEARCH ", JSON.stringify({"seed": "1", "bound": SEARCH_TICKS,
			"tick": world.now, "phase": int(Clock.sim.phase), "served": sim.served_today,
			"result": "no natural opposing Staff/Owner pair in a two-cell aisle"}))
		_review_fail("bounded real service did not reach the declared passing condition")
		return
	Clock.set_speed(0)
	_review_state = _review_snapshot()
	_review_ready = true


func _process(delta: float) -> void:
	super._process(delta)
	if not _review_ready:
		return
	_review_frames += 1
	if not _unchanged():
		_review_fail("the paused service changed while drawing")
		return
	if _review_frames >= 25:
		RenderingServer.frame_post_draw.connect(_review_post_draw, CONNECT_ONE_SHOT)


## Distinct parallel lanes, opposite actual travel, adjacent across the aisle.
## This detects a naturally occurring moment; it never installs a route.
func _passing_pair() -> Array[int]:
	for first: SimAgent in world.agents:
		if not first is StaffAgent or first.move_progress <= 0.0:
			continue
		var a: Vector2i = first.next_cell() - first.cell
		if absi(a.x) + absi(a.y) != 1 or not _trace_valid(first):
			continue
		for second: SimAgent in world.agents:
			if second.id <= first.id or not second is StaffAgent \
					or second.move_progress <= 0.0 or second.next_cell() - second.cell != -a \
					or not _trace_valid(second):
				continue
			var gap: Vector2i = second.cell - first.cell
			var across: int = gap.x * -a.y + gap.y * a.x
			var along: int = gap.x * a.x + gap.y * a.y
			if absi(across) != 1 or absi(along) > 1:
				continue
			var lane: Vector2i = Vector2i(-a.y, a.x) * across
			var clear: bool = true
			# Cover the union of both travelled lane intervals, including the
			# bridge when the pair has just passed. Separate wall corridors are
			# not a shared aisle even if their people are safely far apart.
			for offset: int in range(mini(0, along - 1), maxi(1, along)):
				var start: Vector2i = first.cell + a * offset
				clear = clear and shared_aisle_open(world.grid, start, start + a, lane)
			if clear and _trace_clearance(first.movement_trace(), second.movement_trace()) \
					>= AgentPresentationController.MIN_STANDING_DISTANCE:
				return [first.id, second.id]
	return []


## Pure capture criterion, also exercised against the actual authored wall
## counterexample. Both lanes must connect along AND across this two-cell strip.
static func shared_aisle_open(grid: SimGrid, from_cell: Vector2i, to_cell: Vector2i,
		lane: Vector2i) -> bool:
	var direction: Vector2i = to_cell - from_cell
	if grid == null or absi(direction.x) + absi(direction.y) != 1 \
			or absi(lane.x) + absi(lane.y) != 1 or direction.x * lane.x + direction.y * lane.y != 0:
		return false
	for cell: Vector2i in [from_cell, to_cell, from_cell + lane, to_cell + lane]:
		if not grid.is_walkable(cell):
			return false
		for item: PlacedItem in grid.items():
			if item.seat_cells.has(cell):
				return false
	return grid.step_open(from_cell, to_cell) and grid.step_open(from_cell + lane, to_cell + lane) \
		and grid.step_open(from_cell, from_cell + lane) and grid.step_open(to_cell, to_cell + lane)


func _aisle_cell(cell: Vector2i) -> bool:
	if not world.grid.is_walkable(cell):
		return false
	for item: PlacedItem in world.grid.items():
		if item.seat_cells.has(cell):
			return false
	return true


func _trace_valid(agent: SimAgent) -> bool:
	var trace: Dictionary = agent.movement_trace()
	var points: Array = trace.get("points", [])
	var times: Array = trace.get("times", [])
	if points.size() < 2 or points.size() != times.size():
		return false
	var start: Vector3 = points[0]
	var finish: Vector3 = points[-1]
	if trace.get("tick") != world.now or trace.get("discontinuous") != false \
			or times[0] != 0.0 or times[-1] != 1.0 \
			or not finish.is_equal_approx(agent.movement_position()) \
			or start.is_equal_approx(finish):
		return false
	var claims: Dictionary = world.movement.snapshot()
	if claims["occupied"].get(agent.cell) != agent.id \
			or claims["next"].get(agent.next_cell()) != agent.id:
		return false
	var edge_held: bool = false
	for edge: Dictionary in claims["edges"]:
		if edge.get("id") == agent.id and edge.get("from") == agent.cell and edge.get("to") == agent.next_cell():
			edge_held = true
	if not edge_held:
		return false
	for index: int in points.size():
		var point: Vector3 = points[index]
		if not point.is_finite() or not is_finite(float(times[index])) \
				or float(times[index]) < 0.0 or float(times[index]) > 1.0 \
				or (index > 0 and float(times[index]) < float(times[index - 1])):
			return false
		if index == 0:
			continue
		var previous: Vector3 = points[index - 1]
		var from: Vector2i = GridMath.world_to_cell(previous)
		var to: Vector2i = GridMath.world_to_cell(point)
		var delta: Vector2i = to - from
		if absi(delta.x) > 1 or absi(delta.y) > 1 \
				or not _aisle_cell(from) or not _aisle_cell(to) or not world.grid.step_open(from, to):
			return false
		for cell: Vector2i in [from, to]:
			if claims["occupied"].get(cell) != agent.id and claims["next"].get(cell) != agent.id:
				return false
		if delta.x != 0 and delta.y != 0:
			for corner: Vector2i in [from + Vector2i(delta.x, 0), from + Vector2i(0, delta.y)]:
				if not _aisle_cell(corner) or claims["next"].get(corner) != agent.id:
					return false
	return true


## Closest distance of the two actual piecewise timed paths, not endpoint-only.
func _trace_clearance(a: Dictionary, b: Dictionary) -> float:
	var times: Array[float] = []
	for trace: Dictionary in [a, b]:
		for time: float in trace["times"]:
			if not times.has(time):
				times.append(time)
	times.sort()
	var closest: float = INF
	for index: int in range(1, times.size()):
		var start: Vector3 = _trace_at(a, times[index - 1]) - _trace_at(b, times[index - 1])
		var finish: Vector3 = _trace_at(a, times[index]) - _trace_at(b, times[index])
		var change: Vector3 = finish - start
		var fraction: float = clampf(-start.dot(change) / change.length_squared(), 0.0, 1.0) \
			if change.length_squared() > 0.000000001 else 0.0
		closest = minf(closest, (start + change * fraction).length())
	return closest


func _trace_at(trace: Dictionary, time: float) -> Vector3:
	var points: Array = trace["points"]
	var times: Array = trace["times"]
	for index: int in range(1, times.size()):
		if time <= float(times[index]):
			var span: float = float(times[index]) - float(times[index - 1])
			var previous: Vector3 = points[index - 1]
			return previous.lerp(points[index],
				clampf((time - float(times[index - 1])) / span, 0.0, 1.0) if span > 0.0 else 1.0)
	return points[-1]


func _review_post_draw() -> void:
	if not _review_ready or _review_frames < 5:
		return
	var view: ShopView = $ShopView as ShopView
	var camera: Camera3D = get_viewport().get_camera_3d()
	var drawn: Dictionary[int, Vector3] = view.drawn_agent_positions()
	var viewport: Rect2 = get_viewport().get_visible_rect()
	var header: Control = $HUD/Top as Control
	if not _unchanged() or camera == null or viewport.size != Vector2(1600, 900) \
			or not header.is_visible_in_tree() or not viewport.encloses(header.get_global_rect()) \
			or is_menu_visible() or is_staff_visible() or is_stock_visible() or is_settings_visible() \
			or is_goals_visible() or _inspect_panel.visible or is_build_active() or _report.visible:
		_review_fail("the actual camera or native HUD is missing, clipped or obscured")
		return
	var claims: Dictionary = world.movement.snapshot()
	if claims["occupied"].size() != world.agents.size():
		_review_fail("active people and current-cell claims disagree")
		return
	for active: SimAgent in world.agents:
		if claims["occupied"].get(active.cell) != active.id:
			_review_fail("an active person has no unique actual cell claim")
			return
	var people: Array[Dictionary] = []
	var clearance: float = INF
	for id: int in _review_pair:
		var agent: SimAgent = world.agent(id)
		var person: PersonView = view.agent_nodes.get(id) as PersonView
		if agent == null or not _trace_valid(agent) or person == null or not person.is_visible_in_tree() \
				or not person.get_meta("person_ready", false) or person.get_meta("display_separation_blocked", false) \
				or not drawn.has(id):
			_review_fail("a passing actor is not a ready, visible native person")
			return
		var local: Vector3 = drawn[id]
		var foot: Vector3 = view.to_global(local)
		var head: Vector3 = person.to_global(person.head_anchor_position())
		for point: Vector3 in [foot, head]:
			var screen: Vector2 = camera.unproject_position(point)
			if not camera.is_position_in_frustum(point) or not viewport.has_point(screen) \
					or header.get_global_rect().has_point(screen):
				_review_fail("a passing person's actual feet or head is outside the unobscured image")
				return
		# Read actual drawn people, including seated guests, rather than copying
		# the coordinator's cell distance into a claim about rendered bodies.
		for other: int in drawn:
			var node: Node3D = view.agent_nodes.get(other) as Node3D
			if other != id and node != null and node.is_visible_in_tree():
				clearance = minf(clearance, local.distance_to(drawn[other]))
		if not _body_clear(local):
			_review_fail("a drawn passing body overlaps furniture, a seat or an internal edge")
			return
		people.append({"id": id, "role": String(agent.role), "clip": String(person.current_clip()),
			"model": String(person.model_name()), "cell": _wire(agent.cell),
			"next_cell": _wire(agent.next_cell()), "move_progress": agent.move_progress,
			"trace": _wire(agent.movement_trace()), "drawn_floor": _wire(local),
			"drawn_global": _wire(person.global_position), "head_global": _wire(head),
			"foot_screen": _wire(camera.unproject_position(foot)),
			"head_screen": _wire(camera.unproject_position(head)), "native_person": true})
	if clearance < AgentPresentationController.MIN_STANDING_DISTANCE:
		_review_fail("actual drawn person clearance is below the production standing distance")
		return
	_review_render = {"fixture": "unsaved Main seed1; owner assigned Floor through normal player command; normal paid stock and service",
		"source_tag": "issue263-natural-owner-floor-passing-v1", "seed": "1", "world_tick": world.now,
		"phase": int(Clock.sim.phase), "served": sim.served_today, "sales": Economy.ledger.day_totals(Clock.sim.day).get(Ledger.SALE, 0),
		"pair": people, "drawn_clearance_metres": clearance,
		"required_clearance_metres": AgentPresentationController.MIN_STANDING_DISTANCE,
		"timed_pair_clearance_metres": _trace_clearance(world.agent(_review_pair[0]).movement_trace(), world.agent(_review_pair[1]).movement_trace()),
		"claims": _wire(world.movement.snapshot()), "viewport": _wire(viewport.size),
		"header_rect": [header.global_position.x, header.global_position.y, header.size.x, header.size.y],
		"camera_position": _wire(camera.global_position), "camera_size": camera.size,
		"validation_timing": "frame_post_draw", "unchanged": true}
	# Same post-draw pattern as the existing curb capture: the canonical image
	# is saved first on frame60; earlier validation frames simply await it.
	if FileAccess.file_exists(_review_out.path_join("shot_0060.png")):
		_bind_saved_capture()


func _body_clear(point: Vector3) -> bool:
	# Conservative square around the actual drawn body, including every crossed
	# interior edge. This checks the native position, not a sim-derived pose.
	var radius: float = AgentPresentationController.MIN_STANDING_DISTANCE / 2.0
	var low: Vector2i = GridMath.world_to_cell(point - Vector3(radius, 0.0, radius))
	var high: Vector2i = GridMath.world_to_cell(point + Vector3(radius, 0.0, radius))
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			if not _aisle_cell(cell):
				return false
			if x < high.x and not world.grid.step_open(cell, cell + Vector2i.RIGHT):
				return false
			if y < high.y and not world.grid.step_open(cell, cell + Vector2i.DOWN):
				return false
	return true


func _review_snapshot() -> Dictionary:
	var state: Dictionary = BalanceProbe._control_snapshot(self, sim)
	var actors: Array[Dictionary] = []
	for agent: SimAgent in world.agents:
		var actor: Dictionary = {"id": agent.id, "cell": agent.cell, "next": agent.next_cell(),
			"progress": agent.move_progress, "path": agent.path.duplicate(), "path_index": agent.path_index,
			"trace": agent.movement_trace()}
		if agent is StaffAgent:
			var staff: StaffAgent = agent as StaffAgent
			actor["task"] = staff.task.id if staff.task != null else -1
			actor["step"] = staff.step_index
		actors.append(actor)
	state["actors"] = actors
	state["claims"] = world.movement.snapshot()
	state["shop"] = shop_editor.to_dict()
	state["arrival_countdown"] = sim.spawner.get("_remaining")
	return state


func _unchanged() -> bool:
	return not use_saves and Clock.speed == 0 and GameState.master_seed == 1 \
		and sim.owner_agent().current_mode() == &"floor" \
		and _review_state == _review_snapshot()


func _bind_saved_capture() -> void:
	var png: String = _review_out.path_join("shot_0060.png")
	var sidecar: String = png.get_basename() + ".json"
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(sidecar))
	if _review_render.is_empty() or not raw is Dictionary:
		_review_fail("the canonical frame60 capture or native proof is missing")
		return
	var metadata: Dictionary = raw
	# JSON numbers are floats; nested Dictionary equality preserves numeric types.
	if metadata.get("scene") != "res://tools/movement_review.tscn" or metadata.get("frame") != 60 \
			or metadata.get("width") != 1600 or metadata.get("height") != 900 \
			or metadata.get("world_tick") != _review_render["world_tick"] \
			or metadata.get("master_seed") != "1" or metadata.get("new_game_seed_override") != "1" \
			or metadata.get("engine_errors") != 0 or metadata.get("day_phase") != _review_render["phase"] \
			or metadata.get("capture_parameters") != {"open": false, "fast_ticks_per_frame": 0.0, "speed": 0.0} \
			or metadata.get("capture_timing") != "frame_post_draw" \
			or metadata.get("image_file") != "shot_0060.png" \
			or FileAccess.get_sha256(png).length() != 64 \
			or metadata.get("image_sha256") != FileAccess.get_sha256(png):
		_review_fail("canonical PNG identity differs from the measured paused service")
		return
	for person: Dictionary in _review_render["pair"]:
		var matched: bool = false
		for actor: Dictionary in metadata.get("people", {}).get("actors", []):
			if actor.get("id") == person["id"]:
				matched = _same_point(actor.get("drawn_position", {}).get("world"), person["drawn_global"])
		if not matched:
			_review_fail("canonical people evidence differs from the actual drawn passing actors")
			return
	var sources: Dictionary = {}
	for source: String in SOURCE_FILES:
		sources[source] = FileAccess.get_sha256(source)
		if String(sources[source]).length() != 64:
			_review_fail("a fixture or geometry source could not be hashed")
			return
	_review_render.merge({"image_file": png.get_file(), "image_sha256": metadata["image_sha256"],
		"canonical_sidecar_sha256": FileAccess.get_sha256(sidecar), "scene": metadata["scene"],
		"frame": metadata["frame"], "width": metadata["width"], "height": metadata["height"],
		"engine_errors": metadata["engine_errors"], "source_sha256": sources})
	var file: FileAccess = FileAccess.open(png.get_basename() + ".movement.json", FileAccess.WRITE)
	if file == null:
		_review_fail("cannot write the image-bound movement proof")
		return
	file.store_string(JSON.stringify(_review_render, "\t") + "\n")
	var result: Error = file.get_error()
	file.close()
	if result != OK:
		_review_fail("cannot save the image-bound movement proof")
		return
	print("MOVEMENT_REVIEW ", JSON.stringify(_review_render))
	_review_ready = false


func _same_point(value: Variant, expected: Array) -> bool:
	# The canonical JSON writer rounds floating point values. Compare its
	# measured positions within one micrometre, rather than requiring an
	# accidental bitwise equality after that serialization.
	if not value is Array or value.size() != 3:
		return false
	for index: int in 3:
		if not is_finite(float(value[index])) or absf(float(value[index]) - float(expected[index])) > 0.000001:
			return false
	return true


func _wire(value: Variant) -> Variant:
	if value is Vector2i or value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Array:
		var array_rows: Array = []
		for entry: Variant in value:
			array_rows.append(_wire(entry))
		return array_rows
	if value is Dictionary:
		var dictionary_rows: Dictionary = {}
		for key: Variant in value:
			dictionary_rows[str(key)] = _wire(value[key])
		return dictionary_rows
	return value


func _review_fail(reason: String) -> void:
	_review_ready = false
	push_error("Movement review: " + reason)
