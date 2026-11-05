extends "res://src/world/main.gd"
## Explicit unsaved capture of the street A-frame sign (#292): the sign bought
## through the ordinary hang request on the pavement beside the door, with its
## live restaurant name and today's special, and the real owner at the door for
## scale. Run: bash tools/screenshot.sh --scene=res://tools/a_frame_review.tscn
## --speed=0 --frames=60. Fixture cash and level are synthetic (disclosed in the
## printed line); nothing is saved and no service runs.

const NAME: String = "Little Lantern"
const SIGN_ID: StringName = &"a_frame_sign"
const CAPTURE_FRAME: int = 60

var _sign_anchor: Vector3i = WallFaces.NO_FACE
var _sign_ready: bool = false
var _frames: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	Clock.set_speed(0)
	Economy.add_cash(2000, Ledger.OTHER)
	shop_editor.set_owner_level(2)
	_sign_anchor = _beside_door(2)
	if not shop_hang(SIGN_ID, _sign_anchor):
		push_error("A-frame review: the sign was refused: " + shop_editor.last_check.why)
		return
	if not menu_set_restaurant_name(NAME):
		push_error("A-frame review: the rename was refused")
		return
	var owner: OwnerAgent = sim.owner_agent()
	if owner != null and not world.grid.entries().is_empty():
		var entry: Vector2i = world.grid.entries()[0]
		world.reset_agent_position(owner, entry)
	_sign_ready = true


func _process(delta: float) -> void:
	super._process(delta)
	if not _sign_ready:
		return
	_frames += 1
	if _frames == 10:
		_focus()
	elif _frames == CAPTURE_FRAME:
		_report_sign()


func _focus() -> void:
	var view: ShopView = get_node("ShopView") as ShopView
	view.set_wall_mode(ShopView.WallMode.UP)
	var rig: CameraRig = get_node("CameraRig") as CameraRig
	rig.set_process(false)
	var camera: Camera3D = get_node("CameraRig/Camera3D") as Camera3D
	var into: Vector2i = -WallRules.street_side(world.grid)
	var along: Vector2i = WallFaces.DIRS[posmod(WallFaces.DIRS.find(into) + 1, 4)]
	var outward: Vector3 = Vector3(-into.x, 0.0, -into.y)
	var right: Vector3 = Vector3(along.x, 0.0, along.y)
	var target: Vector3 = view.wall_finish_view.item_nodes[_sign_anchor].global_position - right * 0.45 + Vector3.UP * 0.35
	camera.global_position = target + outward * 7.0 + right * 2.0 + Vector3.UP * 2.8
	camera.look_at(target)
	camera.size = 3.2


func _report_sign() -> void:
	var view: ShopView = get_node("ShopView") as ShopView
	var visual: ItemVisual = view.wall_finish_view.item_nodes.get(_sign_anchor) as ItemVisual
	var mount: Node = visual.prop.get_node(^"BoardMount/Art/Board/WallMount") if visual != null else null
	var title: Label3D = mount.get_node(^"MenuText") as Label3D if mount != null else null
	var special: Label3D = mount.get_node(^"SpecialText") as Label3D if mount != null else null
	var ok: bool = title != null and title.text == NAME and special != null and special.visible \
		and special.text.begins_with(StreetSignText.SPECIAL_PREFIX) and visual.is_visible_in_tree()
	if not ok:
		push_error("A-frame review: the sign does not show its name and special")
	print("A_FRAME_REVIEW ", JSON.stringify({"fixture": "Unsaved seed1 morning; synthetic cash and level 2; sign bought through shop_hang; no service",
		"name": title.text if title != null else "", "special": special.text if special != null else "",
		"curb_appeal_score": curb_appeal_score, "curb_appeal_factor": curb_appeal_factor, "ok": ok}))
	_sign_ready = false


## The pavement cell beside the street door (offset -1 or 2 along the front).
func _beside_door(offset: int) -> Vector3i:
	var doors: Array[Vector2i] = ExteriorSupport.door_cells(world.grid)
	var into: Vector2i = -WallRules.street_side(world.grid)
	var direction: int = WallFaces.DIRS.find(into)
	var along: Vector2i = WallFaces.DIRS[posmod(direction + 1, 4)]
	var first: Vector2i = doors[0]
	for cell: Vector2i in doors:
		if cell.x * along.x + cell.y * along.y < first.x * along.x + first.y * along.y:
			first = cell
	return ExteriorSupport.key_for(WallFaces.make(first + along * offset - into, direction),
		ExteriorSupport.Band.GROUND)
