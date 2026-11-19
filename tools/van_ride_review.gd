extends Control
## Van ride review fixture (#644): the ride over a plain backdrop, stopped at a
## chosen moment, or the morning site card with its "See the map" button. Run
## under a virtual display, for example
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
##     res://tools/van_ride_review.tscn -- --at=1.0 --out=screens/ride_mid.png
## Options: --at=<seconds into the ride> (0 start, 1 middle, 2.2 arrived with
## the line), --from=<neighbourhood id> --to=<neighbourhood id> (default
## old_town to skyline), --case=card (the morning card), --phone (a 390 x 844
## screen drawn 1:1), --out=<png>.

const FRAMES: int = 8

var _out: String = ""
var _at: float = 0.0
var _from: StringName = &"old_town"
var _to: StringName = &"skyline"
var _case: String = "ride"
var _frames: int = 0


func _ready() -> void:
	var phone: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--at="):
			_at = float(arg.trim_prefix("--at="))
		elif arg.begins_with("--from="):
			_from = StringName(arg.trim_prefix("--from="))
		elif arg.begins_with("--to="):
			_to = StringName(arg.trim_prefix("--to="))
		elif arg.begins_with("--case="):
			_case = arg.trim_prefix("--case=")
		elif arg == "--phone":
			phone = true
	if phone:
		get_window().content_scale_size = Vector2i(390, 844)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("4a5a50")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	if _case == "card":
		_card()
	else:
		_ride()


func _ride() -> void:
	var map: CityMapDef = CityMap.load_default()
	var lines: CommuteLines = CommuteLines.load_default()
	var line: String = lines.pick(12, _to, map.neighbourhood(_to).commute_line)
	var ride: VanRide = VanRide.new()
	add_child(ride)
	var panel: CityPanel = (load("res://src/ui/city_panel.tscn") as PackedScene).instantiate() as CityPanel
	ride.play(panel.map_texture, CityMap.van_path(map, _from, _to), line, 2.0)
	panel.free()
	# Late frames are fed in whole, so the picture is exactly that moment.
	ride.tick(_at)


func _card() -> void:
	var card: SiteCard = (load("res://src/ui/site_card.tscn") as PackedScene).instantiate() as SiteCard
	add_child(card)
	card.show()
	var home: SiteCard.Row = SiteCard.Row.new()
	home.id = &"home"
	home.name = "Fool's Kitchen"
	home.current = true
	home.takings = 412
	home.manager = "Ana"
	var mill: SiteCard.Row = SiteCard.Row.new()
	mill.id = &"mill"
	mill.name = "Old Mill Street"
	mill.managed = true
	mill.earnings = 84
	mill.manager = "Bea"
	card.map_available = true
	card.set_rows([home, mill] as Array[SiteCard.Row])


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == FRAMES and not _out.is_empty():
		get_viewport().get_texture().get_image().save_png(_out)
		print("VAN_RIDE_REVIEW saved %s size=%s" % [_out, get_viewport().get_visible_rect().size])
		get_tree().quit()
