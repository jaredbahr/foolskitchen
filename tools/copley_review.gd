extends "res://src/world/main.gd"
## Unsaved review fixture for Chef Copley's art (#701): the seed-1 first morning with one of his
## pieces on screen, so the models and the RIVAL look can be checked by day and night.
## Use: COPLEY_VIEW=<view> bash tools/screenshot.sh --scene=res://tools/copley_review.tscn
##   --speed=0 --frames=60 --out=<dir>
## COPLEY_VIEW picks the piece:
##   truck_cliff, truck_mill, truck_rooftop, truck_cabin   the food truck at that lot (its name on the panel)
##   shop_home       the rival house across the starter street (Cool's Kitchen)
##   shop_boardwalk  the Boardwalk terrace's goods shop taken over (Beachfront Bored Walk);
##                   COPLEY_NEIGHBOUR=<id> takes another neighbour (surf_hire, arcade, ...)
##   trophy          Copley's Closing Sign hung on the home shop's wall
##   lineup          the three made models in the shop (a rough check of scale, not a review shot)
## COPLEY_STAGE=day|night (default day). COPLEY_ZOOM=<n> is the zoom multiplier on the game's own default
## view of that site (1, the default, is what a player sees; 3 is three times closer) and is centred on the piece.
## COPLEY_QUARTER=<0..3> turns the camera by quarter turns (the houses' street fronts face away from the default camera: use 2).
## Nothing is saved or bought; the weather is forced sunny.

const LOTS: Dictionary[String, StringName] = {
	"truck_cliff": &"seaside_cliff", "truck_mill": &"town_fixer_upper",
	"truck_rooftop": &"skyscraper_rooftop", "truck_cabin": &"woodland_cabin",
	"shop_boardwalk": &"beachfront_boardwalk",
}
const NAMES: Dictionary[String, String] = {
	"truck_cliff": "Seaside Riff", "truck_mill": "Old Mall Street", "truck_rooftop": "Skyline Rooftip",
	"truck_cabin": "Woodland Cabinet", "shop_boardwalk": "Beachfront Bored Walk", "shop_home": "Cool's Kitchen",
}
const TROPHY_ID: StringName = &"copley_sign"
## The home shop's back wall, inner face (anchor: cell x, cell y, side).
const TROPHY_FACE: Vector3i = Vector3i(8, 1, 0)
const NIGHT_MINUTE: float = 0.0

var _view: String = ""
var _zoom: float = 1.0
var _target: Vector3 = Vector3.ZERO
var _wait: int = 6


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	_view = OS.get_environment("COPLEY_VIEW")
	if _view.is_empty():
		_view = "shop_home"
	_zoom = float(OS.get_environment("COPLEY_ZOOM")) if not OS.get_environment("COPLEY_ZOOM").is_empty() else 1.0
	if LOTS.has(_view):
		var site: StringName = LOTS[_view]
		var lot: LotDef = _lot_def(site)
		var sections: Dictionary = _new_site_sections(lot) if lot != null else {}
		if sections.is_empty() or not site_book.add_site(site, site, lot.display_name, Clock.sim.day, sections):
			push_error("Copley review could not add the site %s" % site)
			return
		if not switch_site(site):
			push_error("Copley review could not switch to %s: %s" % [site, site_switch_refusal(site)])
			return
	_hide_panels()
	if not _force_sunny():
		return
	_stage(OS.get_environment("COPLEY_STAGE"))
	_wait = 8
	print("COPLEY_REVIEW ", _view)


func _dressing() -> NeighbourhoodDressing:
	return ($ShopView as ShopView).neighbourhood_dressing


func _hide_panels() -> void:
	for panel: String in ["HUD", "Overlay", "Hints"]:
		var node: Node = get_node_or_null(panel)
		if node != null:
			node.set("visible", false)


func _force_sunny() -> bool:
	if world == null or world.weather == null:
		push_error("Copley review found no weather to force")
		return false
	world.weather.kind = WeatherState.Kind.SUNNY
	refresh_presentation()
	return true


## Day keeps the morning; night is after close with the lamps up (display only: nothing ticks).
func _stage(stage: String) -> void:
	if stage != "night":
		return
	var clock: SimClock = world.clock
	clock.phase = SimClock.Phase.CLOSED
	clock.phase_tick = 0
	Clock.set_speed(0)
	refresh_presentation()


## Puts the piece on screen once the street has built.
func _show_piece() -> void:
	var dressing: NeighbourhoodDressing = _dressing()
	match _view:
		"shop_home":
			if not dressing.set_neighbour_state(StreetSet.RIVAL_ID, NeighbourhoodDressing.NeighbourState.RIVAL, NAMES[_view]):
				push_error("Copley review: the starter street has no rival house")
				return
			_target = dressing.neighbour(StreetSet.RIVAL_ID).global_position
		"shop_boardwalk":
			var id: StringName = StringName(OS.get_environment("COPLEY_NEIGHBOUR")) if not OS.get_environment("COPLEY_NEIGHBOUR").is_empty() else &"beach_goods"
			if not dressing.set_neighbour_state(id, NeighbourhoodDressing.NeighbourState.RIVAL, NAMES[_view]):
				push_error("Copley review: no neighbour %s" % id)
				return
			_target = dressing.neighbour(id).global_position
		"trophy":
			if not shop_hang(TROPHY_ID, TROPHY_FACE):
				push_error("Copley review could not hang the trophy: " + shop_editor.last_check.why)
				return
			_target = GridMath.cell_to_world(WallFaces.cell(TROPHY_FACE)) + Vector3(0.0, 0.7, 0.0)
		"lineup":
			_lineup()
		_:
			if not dressing.set_rival_truck(NAMES.get(_view, "Copley's")):
				push_error("Copley review: no room for a truck at %s" % _view)
				return
			_target = dressing.rival_truck().global_position
	if OS.get_environment("COPLEY_GRID") == "1":
		_grid_markers(dressing)
	_frame_piece()
	print("COPLEY_TARGET ", _view, " ", _target)


## Centres the view on the piece at the game's default zoom divided by COPLEY_ZOOM. A truck at zoom 1 keeps the
## game's own framing of the lot (it is parked in view of the door); a shop or the trophy is panned to.
func _frame_piece() -> void:
	var rig: CameraRig = $CameraRig as CameraRig
	var base: float = rig.initial_zoom
	rig.minimum_zoom = 1.0
	# Review only: a player's pan stops at the world's edge, which would shrink a view of the far side of the road.
	rig.set_world_bounds(Rect2())
	var quarter: int = int(OS.get_environment("COPLEY_QUARTER")) if not OS.get_environment("COPLEY_QUARTER").is_empty() else 0
	rig.initial_yaw_degrees = 45.0 + 90.0 * float(quarter)
	if _view.begins_with("truck") and is_equal_approx(_zoom, 1.0) and quarter == 0:
		return
	rig.frame_area(Vector2(_target.x, _target.z), Vector2(60.0, 60.0), base / _zoom, true)


## COPLEY_GRID=1: little numbered posts on a street-local grid (u,z), to choose a truck slot.
func _grid_markers(dressing: NeighbourhoodDressing) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "GridMarkers"
	add_child(holder)
	var frame: Transform3D = dressing.local_frame()
	var door_u: float = 0.0
	for u: float in range(-8, 13, 2):
		for z: float in [1.0, 2.0, 3.0, 4.0]:
			var label: Label3D = Label3D.new()
			label.text = "%d,%d" % [int(u), int(z)]
			label.font_size = 24
			label.pixel_size = 0.012
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.modulate = Color(1, 0, 0)
			label.position = frame * Vector3(u + door_u, 0.2, z)
			holder.add_child(label)


func _lineup() -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "CopleyLineup"
	add_child(holder)
	var origin: Vector3 = GridMath.cell_to_world(Vector2i(8, 8))
	var truck: Node3D = NeighbourhoodRival.truck("Cool's Kitchen")
	truck.position = origin
	holder.add_child(truck)
	var sign: Node3D = NeighbourhoodRival.sign_node("Cool's Kitchen", 1.4)
	sign.position = origin + Vector3(-1.9, 0.5, 0.0)
	holder.add_child(sign)
	var trophy: Node3D = NeighbourhoodRival.closing_sign()
	trophy.position = origin + Vector3(1.9, 0.5, 0.0)
	holder.add_child(trophy)
	_target = origin


func _process(delta: float) -> void:
	super._process(delta)
	if _wait > 0:
		_wait -= 1
		if _wait == 0:
			_show_piece()
