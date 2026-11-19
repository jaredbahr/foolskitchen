extends Control
## City map review fixture (#642): the city screen over a plain backdrop with an
## explicit, unsaved set of restaurants and lots, so every pin state shows. Run
## under a virtual display, for example
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tools/city_map_review.tscn -- --case=tier3 --out=screens/city_tier3.png
## Options: --case=tier3 (home here, the mill managed, the cliff closed and
## needing you, the Cabin and Rooftop locked, the boardwalk for sale: roadworks
## on the Skyline road), --case=tier5 (a second site renovating, one closed),
## --case=soon (Pinewood with no lot yet: a hoarding), --case=list
## (the plain list), --phone (a 390 x 844 screen drawn 1:1), --select=<id>.

const FRAMES: int = 8
const LOT_PATHS: Array[String] = ["town_fixer_upper", "beachfront_boardwalk", "seaside_cliff",
	"skyscraper_rooftop", "woodland_cabin"]

var _out: String = ""
var _case: String = "tier3"
var _select: StringName = &""
var _frames: int = 0


func _ready() -> void:
	var phone: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
		elif arg.begins_with("--select="):
			_select = StringName(arg.trim_prefix("--select="))
		elif arg == "--phone":
			phone = true
	if phone:
		get_window().content_scale_size = Vector2i(390, 844)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("4a5a50")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	add_child(panel)
	panel.set_city(_map(), _view())
	panel.show()
	if _case == "list":
		(panel.get_node("%ViewToggle") as Button).pressed.emit()
	if _select != &"":
		panel.pin_pressed_for_review(_select)


func _site(id: StringName, lot: StringName, name_: String, status: ChainSummary.Status) -> ChainSummary.Site:
	var site: ChainSummary.Site = ChainSummary.Site.new()
	site.id = id
	site.lot = lot
	site.name = name_
	site.status = status
	site.staffed = true
	site.stars = 4.2
	site.yesterday_takings = 184
	return site


func _view() -> CityPanel.View:
	var view: CityPanel.View = CityPanel.View.new()
	var home: ChainSummary.Site = _site(&"home", &"home", "Fool's Kitchen", ChainSummary.Status.HERE)
	var mill: ChainSummary.Site = _site(&"mill", &"town_fixer_upper", "Old Mill Street", ChainSummary.Status.MANAGED)
	mill.tonight = 84
	var cliff: ChainSummary.Site = _site(&"cliff", &"seaside_cliff", "Seaside Cliff", ChainSummary.Status.CLOSED)
	cliff.alerts = [ChainSummary.Alert.NO_MANAGER] as Array[ChainSummary.Alert]
	view.sites = [home, mill, cliff] as Array[ChainSummary.Site]
	view.career_tier = 3
	view.reputation = 3.8
	if _case == "tier5":
		var works: ChainSummary.Site = _site(&"works", &"woodland_cabin", "Woodland Cabin", ChainSummary.Status.RENOVATING)
		works.renovation_days = 3
		view.sites = [home, mill, cliff, works] as Array[ChainSummary.Site]
		view.career_tier = 5
		view.reputation = 4.6
	for name_: String in LOT_PATHS:
		var lot: LotDef = load("res://data/lots/%s.tres" % name_) as LotDef
		if lot != null:
			view.lots.append(lot)
	return view


func _map() -> CityMapDef:
	var map: CityMapDef = CityMap.load_default()
	if _case == "soon":
		# Pinewood as it was before the Cabin: no lot yet, so a hoarding.
		var pinewood: NeighbourhoodDef = map.neighbourhood(&"pinewood")
		pinewood.lots = [] as Array[StringName]
		pinewood.coming_soon = "A cabin in the woods"
	return map


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == FRAMES and not _out.is_empty():
		get_viewport().get_texture().get_image().save_png(_out)
		print("CITY_MAP_REVIEW saved %s size=%s" % [_out, get_viewport().get_visible_rect().size])
		get_tree().quit()
