extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for #294, not a service or balance claim.
## A fresh seed-1 morning shop at level 3 with a jukebox bought through the real
## Buy command beside a wall, then selected so the real Inspect panel shows its
## music-style choice; the style is picked with that panel's own button. Capture
## with tools/screenshot.sh --scene=res://tools/jukebox_review.tscn --speed=0
## --frames=12,40 (frame 12: the picker; frame 40: a close view without the
## selection outline, to judge the model and its shadow).

const STYLE: StringName = &"jukebox_cafe_jazz"
## The jukebox goes on the north wall, in the clear stretch beside the tables.
const WALL_COLUMN: int = 11

var _review_frame: int = 0
var _item: PlacedItem


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	super._ready()
	if sim == null:
		push_error("Jukebox review needs a fresh shop")
		return
	Economy.add_cash(500, Ledger.OTHER)
	shop_editor.set_owner_level(3)
	var cell: Vector2i = _free_wall_cell()
	if cell == SimGrid.NO_CELL or not shop_buy(&"jukebox", cell, 2):
		push_error("Jukebox review could not place its jukebox: " + shop_editor.last_check.why)
		return
	var placed: PlacedItem = world.grid.item(shop_editor.last_item_id)
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.CUTAWAY)
	_inspect_panel.show_item(placed.id)
	var button: Button = _inspect_panel.get_node_or_null("Panel/Rows/MusicStyleRow/MusicStyleButtons/" + String(STYLE)) as Button
	if button == null:
		push_error("Jukebox review inspector has no music-style button")
		return
	button.pressed.emit()
	Clock.set_speed(0)
	refresh_presentation()
	_item = placed
	_frame(placed, 3.4)
	print("JUKEBOX_REVIEW ", JSON.stringify({"cell": [cell.x, cell.y], "style": String(placed.variant_id),
		"vibe_theme": vibe_result.theme_label, "vibe_score": vibe_result.score, "use_saves": use_saves}))


func _process(delta: float) -> void:
	super._process(delta)
	_review_frame += 1
	if _review_frame == 25:
		clear_selection()
		_frame(_item, 2.4)


## The first empty dining floor cell touching a wall on its far (north) side.
func _free_wall_cell() -> Vector2i:
	var best: Vector2i = SimGrid.NO_CELL
	for cell: Vector2i in world.grid.cells():
		if world.grid.terrain(cell) != SimGrid.Terrain.FLOOR or world.grid.room(cell) != SimGrid.Room.DINING \
				or world.grid.item_at(cell) != null or not world.grid.edge_blocked(cell, cell + Vector2i.UP):
			continue
		if best == SimGrid.NO_CELL or absi(cell.x - WALL_COLUMN) < absi(best.x - WALL_COLUMN) \
				or (cell.x == best.x and cell.y < best.y):
			best = cell
	return best


func _frame(placed: PlacedItem, zoom: float) -> void:
	var rig: CameraRig = $CameraRig as CameraRig
	var world_cell: Vector3 = GridMath.cell_to_world(placed.origin)
	var centre: Vector2 = Vector2(world_cell.x, world_cell.z)
	rig.minimum_zoom = zoom
	rig.initial_yaw_degrees = 45.0
	rig.frame_area(centre, Vector2(6.0, 6.0), zoom, true)
	rig.set_process(false)
