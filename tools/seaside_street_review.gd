extends "res://src/world/main.gd"
## Unsaved street review fixture (#425): the seed-1 first morning with the seaside
## lot added as a second site and made the active one, so the view shows the
## seaside street (data/streets/seaside.tres). Nothing is saved or bought.
## Use: bash tools/screenshot.sh --scene=res://tools/seaside_street_review.tscn
##   --speed=0 --frames=60 [--quarter=N]. Set SEASIDE_STREET_REVIEW_HOME=1 to stay
## on the home site's starter street instead, for a side-by-side comparison.

const SEASIDE: StringName = &"seaside_cliff"


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if OS.get_environment("SEASIDE_STREET_REVIEW_HOME") == "1":
		return
	var lot: LotDef = _lot_def(SEASIDE)
	var sections: Dictionary = _new_site_sections(lot) if lot != null else {}
	if sections.is_empty() or not site_book.add_site(SEASIDE, SEASIDE, lot.display_name, Clock.sim.day, sections):
		push_error("Seaside street review could not add the seaside site")
		return
	if not switch_site(SEASIDE):
		push_error("Seaside street review could not switch to the seaside site: " + site_switch_refusal(SEASIDE))
		return
	# The street is the subject: take the panels off the picture.
	for panel: String in ["HUD", "Overlay", "Hints"]:
		var node: Node = get_node_or_null(panel)
		if node != null:
			node.set("visible", false)
	_close_up()
	if OS.get_environment("SEASIDE_STREET_PLAN") == "1":
		var summary: Array = []
		for entry: Dictionary in ($ShopView as ShopView).neighbourhood_dressing.furniture_plan():
			summary.append("%d@%.1f" % [entry["kind"], entry["u"]])
		print("PLAN ", " ".join(summary))
	print("SEASIDE_STREET_REVIEW ", JSON.stringify({"site": String(site_book.active_id),
		"street": String(($ShopView as ShopView).street_preset.id)}))


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
	var target: Vector3 = Vector3(origin.x, 0.0, origin.z) + normal * (float(frame["reserve_shift"]) + 2.6) + tangent * slide
	var rig: CameraRig = $CameraRig as CameraRig
	rig.frame_area(Vector2(target.x, target.z), Vector2(14.0, 14.0), float(zoom_text), true)


static func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	var parts: Array = value
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
