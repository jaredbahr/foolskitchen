extends "res://src/world/main.gd"
## Unsaved street review fixture (#425): the seed-1 first morning with the seaside
## lot added as a second site and made the active one, so the view shows its
## street (the promenade, data/streets/promenade.tres, #596). Nothing is saved or bought.
## Use: bash tools/screenshot.sh --scene=res://tools/seaside_street_review.tscn
##   --speed=0 --frames=60 [--quarter=N]. Set SEASIDE_STREET_REVIEW_HOME=1 to stay
## on the home site's starter street instead, for a side-by-side comparison.
## SEASIDE_STREET_STAGE=day|dusk|night shows the street at that time of day (default
## day, the first morning): the clock is set for display only and never runs.
## SEASIDE_STREET_BEACH=<zoom> frames the beach behind the shop (#588) at that zoom
## (the default view is about 15; 22 shows the beach and sea well).
## SEASIDE_STREET_FOR_SALE=1 shows every terrace neighbour closed and for sale; a
## neighbour's id (surf_hire, beach_goods, ...) shows just that one (#596).
## SEASIDE_STREET_PRESET=<path> stands the lot on another street for the capture (for
## example res://data/streets/seaside.tres, the seaside road).
## SEASIDE_STREET_STANDS=stumps|cleared shows a woodland street's stands of trees
## (#607, data/streets/woodland.tres) felled to stumps or cleared; <state>:<id> (for
## example stumps:east) shows just that stand.
## SEASIDE_STREET_EXPANDED=1 grows the lot by its lease expansion first (#611), as
## buying it would but without the deposit, so a woodland's land stands show felled.
## SEASIDE_STREET_WALLS=up shows the shop's walls at full height (a woodland's log
## cabin, #611) instead of the cutaway.
## SEASIDE_STREET_LOT=<lot id> reviews another lot instead of the seaside cliff (for
## example skyscraper_rooftop, the city rooftop, #614; or town_fixer_upper, Old Mill Street's
## watermill on its country lane, #613).
## SEASIDE_STREET_PERGOLA=1 stands the two made rain-cover pergolas (#380,
## assets/made/pergola/) over kit tables and chairs in front of the shop, with a guest
## for scale (review only: nothing joins the sim or the save).
## SEASIDE_STREET_LIGHTHOUSE=<zoom> frames a cliff top's lighthouse across the bay (#380,
## data/streets/cliff.tres) at that zoom.
## SEASIDE_STREET_PAN=<u>,<v> zooms the player's view all the way out and pans it as far
## as the real pan limits allow along the street frame's tangent (u) and normal (v), for
## example 0,-1 to the end of a cliff top's or beach's pan out over the sea (#380).
## SEASIDE_STREET_PLOTS=mown|cleared shows a country street's land plots (#613,
## data/streets/country.tres) mown or cleared; <state>:<id> (for example mown:east)
## shows just that plot.
## SEASIDE_STREET_FRAMES=<n> times n frames after a 60-frame warm-up, with vsync off,
## and prints FRAME_TIME with the mean and median milliseconds (run --frames past 60+n).

const SEASIDE: StringName = &"seaside_cliff"
## The dusk stage's minute of the day: the sunset key frame (data/look/day_light.tres).
const DUSK_MINUTE: float = 1230.0
const WARM_UP_FRAMES: int = 60

var _timed_frames: int = 0
var _frame_count: int = 0
var _last_usec: int = 0
var _frame_ms: Array[float] = []
## Frames left before SEASIDE_STREET_PAN pans (after the capture's own camera setup).
var _pan_wait: int = 20


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if OS.get_environment("SEASIDE_STREET_REVIEW_HOME") == "1":
		# The starter street takes the time of day too, for a day/dusk/night comparison.
		_set_stage(OS.get_environment("SEASIDE_STREET_STAGE"))
		return
	var site: StringName = SEASIDE
	if not OS.get_environment("SEASIDE_STREET_LOT").is_empty():
		site = StringName(OS.get_environment("SEASIDE_STREET_LOT"))
	var lot: LotDef = _lot_def(site)
	var street_override: String = OS.get_environment("SEASIDE_STREET_PRESET")
	if lot != null and not street_override.is_empty():
		# This process only: the review saves nothing, so the loaded lot may change.
		lot.street_preset = street_override
	var sections: Dictionary = _new_site_sections(lot) if lot != null else {}
	if sections.is_empty() or not site_book.add_site(site, site, lot.display_name, Clock.sim.day, sections):
		push_error("Seaside street review could not add the site %s" % site)
		return
	if not switch_site(site):
		push_error("Seaside street review could not switch to the site: " + site_switch_refusal(site))
		return
	# The street is the subject: take the panels off the picture.
	for panel: String in ["HUD", "Overlay", "Hints"]:
		var node: Node = get_node_or_null(panel)
		if node != null:
			node.set("visible", false)
	_show_for_sale(OS.get_environment("SEASIDE_STREET_FOR_SALE"))
	if OS.get_environment("SEASIDE_STREET_EXPANDED") == "1":
		_expand_lease()
	_show_stands(OS.get_environment("SEASIDE_STREET_STANDS"))
	_show_plots(OS.get_environment("SEASIDE_STREET_PLOTS"))
	if OS.get_environment("SEASIDE_STREET_PERGOLA") == "1":
		_show_pergolas()
	if OS.get_environment("SEASIDE_STREET_WALLS") == "up":
		_walls_up()
	_close_up()
	_frame_beach()
	_frame_lighthouse()
	_timed_frames = OS.get_environment("SEASIDE_STREET_FRAMES").to_int()
	if _timed_frames > 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not _set_stage(OS.get_environment("SEASIDE_STREET_STAGE")):
		return
	if OS.get_environment("SEASIDE_STREET_PLAN") == "1":
		var summary: Array = []
		for entry: Dictionary in ($ShopView as ShopView).neighbourhood_dressing.furniture_plan():
			summary.append("%d@%.1f" % [entry["kind"], entry["u"]])
		print("PLAN ", " ".join(summary))
	print("SEASIDE_STREET_REVIEW ", JSON.stringify({"site": String(site_book.active_id),
		"street": String(($ShopView as ShopView).street_preset.id), "minute": day_light_minute()}))


func _show_for_sale(which: String) -> void:
	if which.is_empty() or which == "0":
		return
	var dressing: NeighbourhoodDressing = ($ShopView as ShopView).neighbourhood_dressing
	for id: StringName in dressing.neighbour_ids():
		if which == "1" or which == String(id):
			dressing.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.FOR_SALE)


## After the first frames, which settle the view's wall mode.
func _walls_up() -> void:
	for frame: int in 3:
		await get_tree().process_frame
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.UP)


func _expand_lease() -> void:
	var layout: ShopLayout = _lease_for(_base_layout).layout_for(_base_layout, 2)
	if not shop_editor.grow_lot(layout):
		push_error("Seaside street review could not grow the lot")
		return
	lease_expanded = true
	($ShopView as ShopView).set_lot(shop_editor.footprint().lot)


func _show_stands(which: String) -> void:
	if which.is_empty():
		return
	var parts: PackedStringArray = which.split(":")
	var states: Dictionary[String, NeighbourhoodForest.StandState] = {"forest": NeighbourhoodForest.StandState.FOREST,
		"stumps": NeighbourhoodForest.StandState.STUMPS, "cleared": NeighbourhoodForest.StandState.CLEARED}
	if not states.has(parts[0]):
		push_error("Unknown SEASIDE_STREET_STANDS: " + which)
		return
	var dressing: NeighbourhoodDressing = ($ShopView as ShopView).neighbourhood_dressing
	for id: StringName in dressing.stand_ids():
		if parts.size() < 2 or parts[1] == String(id):
			dressing.set_stand_state(id, states[parts[0]])
	print("STANDS ", dressing.stand_ids())


func _show_plots(which: String) -> void:
	if which.is_empty():
		return
	var parts: PackedStringArray = which.split(":")
	var states: Dictionary[String, NeighbourhoodCountry.PlotState] = {"grown": NeighbourhoodCountry.PlotState.GROWN,
		"mown": NeighbourhoodCountry.PlotState.MOWN, "cleared": NeighbourhoodCountry.PlotState.CLEARED}
	if not states.has(parts[0]):
		push_error("Unknown SEASIDE_STREET_PLOTS: " + which)
		return
	var dressing: NeighbourhoodDressing = ($ShopView as ShopView).neighbourhood_dressing
	for id: StringName in dressing.plot_ids():
		if parts.size() < 2 or parts[1] == String(id):
			dressing.set_plot_state(id, states[parts[0]])
	print("PLOTS ", dressing.plot_ids())


## The pergolas (#380) side by side in front of the shop, each over a table and chairs.
func _show_pergolas() -> void:
	var dressing: NeighbourhoodDressing = ($ShopView as ShopView).neighbourhood_dressing
	var frame: Transform3D = dressing.local_frame()
	var cliff: NeighbourhoodCliff = dressing.cliff()
	var door_u: float = cliff.door.get_center().x if cliff != null else 0.0
	var z: float = float(dressing.capture_state()["frame"]["reserve_shift"]) + 1.9
	var holder: Node3D = Node3D.new()
	holder.name = "PergolaReview"
	add_child(holder)
	var scale: float = ArtScale.FURNITURE_SCALE
	for index: int in 2:
		var at: Vector3 = frame * Vector3(door_u + 2.6 + 2.45 * float(index), 0.0, z)
		var cover: Node3D = (load("res://assets/made/pergola/%s.glb" % ["pergola_timber", "pergola_awning"][index]) as PackedScene).instantiate() as Node3D
		holder.add_child(cover)
		cover.transform = Transform3D(frame.basis.scaled(Vector3.ONE * scale), at)
		_centred(holder, "res://assets/kenney/furniture/table.glb", at, frame.basis)
		for side: float in [-1.0, 1.0]:
			var seat: Vector3 = at + frame.basis * Vector3(side * 0.62, 0.0, 0.0)
			_centred(holder, "res://assets/kenney/furniture/chair.glb", seat, frame.basis * Basis(Vector3.UP, side * PI * 0.5))
	var guest: PersonView = (load("res://assets/people/person.tscn") as PackedScene).instantiate() as PersonView
	guest.role = &"guest"
	guest.guest_id = 4
	holder.add_child(guest)
	guest.transform = Transform3D(frame.basis, frame * Vector3(door_u + 1.15, 0.0, z + 0.3))


## A kit model, centred on `at` (kit models stand on a back corner), at the furniture scale.
func _centred(holder: Node3D, path: String, at: Vector3, basis: Basis) -> void:
	var model: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(model)
	var box: AABB = AABB()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var part: AABB = (model.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		box = part if box.size == Vector3.ZERO else box.merge(part)
	var middle: Vector3 = Vector3(box.get_center().x, 0.0, box.get_center().z) * ArtScale.FURNITURE_SCALE
	model.transform = Transform3D(basis.scaled(Vector3.ONE * ArtScale.FURNITURE_SCALE), at - basis * middle)


## Sets the clock's phase for display only (dusk mid-evening service, night after
## close); nothing ticks, as the review runs at speed 0. Day leaves the morning.
func _set_stage(stage: String) -> bool:
	var clock: SimClock = world.clock
	match stage:
		"", "day":
			return true
		"dusk":
			clock.phase = SimClock.Phase.OPEN
			clock.phase_tick = roundi((DUSK_MINUTE - clock.display_open_minute)
				/ float(clock.display_close_minute - clock.display_open_minute) * clock.open_ticks)
		"night":
			clock.phase = SimClock.Phase.CLOSED
			clock.phase_tick = 0
		_:
			push_error("Unknown SEASIDE_STREET_STAGE: " + stage)
			return false
	Clock.set_speed(0)
	refresh_presentation()
	return true


## SEASIDE_STREET_ZOOM=<metres> frames the pavement in close-up (about 9 reads props
## well); SEASIDE_STREET_U=<metres> slides the view along the street.
func _close_up() -> void:
	var zoom_text: String = OS.get_environment("SEASIDE_STREET_ZOOM")
	if zoom_text.is_empty():
		return
	var frame: Dictionary = $ShopView.neighbourhood_dressing.capture_state().get("frame", {})
	if not frame.has("origin"):
		push_error("Seaside street review found no street frame")
		return
	var origin: Vector3 = _vector(frame["origin"])
	var normal: Vector3 = _vector(frame["normal"])
	var tangent: Vector3 = _vector(frame["tangent"])
	var slide: float = float(OS.get_environment("SEASIDE_STREET_U"))
	# SEASIDE_STREET_V=<metres> moves the close-up out past the street (a woodland glade, #607).
	var out: float = 2.6 if OS.get_environment("SEASIDE_STREET_V").is_empty() else float(OS.get_environment("SEASIDE_STREET_V"))
	var target: Vector3 = Vector3(origin.x, 0.0, origin.z) + normal * (float(frame["reserve_shift"]) + out) + tangent * slide
	var rig: CameraRig = $CameraRig as CameraRig
	rig.frame_area(Vector2(target.x, target.z), Vector2(14.0, 14.0), float(zoom_text), true)


func _frame_beach() -> void:
	var zoom_text: String = OS.get_environment("SEASIDE_STREET_BEACH")
	var shore: NeighbourhoodShore = $ShopView.neighbourhood_dressing.shore()
	if zoom_text.is_empty() or shore == null:
		return
	var frame: Transform3D = $ShopView.neighbourhood_dressing.local_frame()
	var target: Vector3 = frame * Vector3(shore.path_u, 0.0, shore.lane_v - 2.0)
	($CameraRig as CameraRig).frame_area(Vector2(target.x, target.z), Vector2(14.0, 14.0), float(zoom_text), true)


func _frame_lighthouse() -> void:
	var zoom_text: String = OS.get_environment("SEASIDE_STREET_LIGHTHOUSE")
	var cliff: NeighbourhoodCliff = $ShopView.neighbourhood_dressing.cliff()
	if zoom_text.is_empty() or cliff == null:
		return
	var target: Vector3 = $ShopView.neighbourhood_dressing.local_frame() * Vector3(cliff.lighthouse.x, 0.0, cliff.lighthouse.y + 2.0)
	($CameraRig as CameraRig).frame_area(Vector2(target.x, target.z), Vector2(14.0, 14.0), float(zoom_text), true)


func _pan_to_limit() -> void:
	var text: String = OS.get_environment("SEASIDE_STREET_PAN")
	if text.is_empty():
		return
	var parts: PackedStringArray = text.split(",")
	var frame: Dictionary = $ShopView.neighbourhood_dressing.capture_state().get("frame", {})
	if parts.size() != 2 or not frame.has("normal"):
		push_error("SEASIDE_STREET_PAN needs <u>,<v> and a street frame")
		return
	var push: Vector3 = _vector(frame["tangent"]) * float(parts[0]) + _vector(frame["normal"]) * float(parts[1])
	var rig: CameraRig = $CameraRig as CameraRig
	rig.zoom_steps(1000.0)
	# Far past any limit: the rig's own clamp stops it where a player's pan would.
	rig.position += push * 1000.0
	rig.step_view(0.001, Vector2.ZERO)
	print("SEASIDE_STREET_PAN ", rig.position)


static func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	var parts: Array = value
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


@warning_ignore("integer_division")
func _process(delta: float) -> void:
	super._process(delta)
	if _pan_wait > 0:
		_pan_wait -= 1
		if _pan_wait == 0:
			_pan_to_limit()
	if _timed_frames <= 0 or _frame_ms.size() >= _timed_frames:
		return
	_frame_count += 1
	var now: int = Time.get_ticks_usec()
	if _frame_count > WARM_UP_FRAMES:
		_frame_ms.append(float(now - _last_usec) / 1000.0)
		if _frame_ms.size() == _timed_frames:
			var sorted: Array[float] = _frame_ms.duplicate()
			sorted.sort()
			var total: float = 0.0
			for value: float in _frame_ms:
				total += value
			print("FRAME_TIME ", JSON.stringify({"frames": _timed_frames, "mean_ms": snappedf(total / float(_timed_frames), 0.01),
				"median_ms": snappedf(sorted[_timed_frames / 2], 0.01)}))
	_last_usec = now
