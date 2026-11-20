extends TestCase
## The rival's food truck on the four real lots with no shopfronts (#701): its slot stands clear of
## everything that lot's street builds (the lot, the door's approach, the porch, paths, land plots and
## stands of trees), as the street's own builder judges it, also once the lease has grown.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
const LOTS: Array[StringName] = [&"seaside_cliff", &"town_fixer_upper", &"skyscraper_rooftop", &"woodland_cabin"]

var _main: Node3D


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()


func test_each_lots_truck_slot_is_clear() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	_main = MAIN.instantiate() as Node3D
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	tree.root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	for id: StringName in LOTS:
		var lot: LotDef = _main.call("_lot_def", id) as LotDef
		var sections: Dictionary = _main.call("_new_site_sections", lot)
		var book: SiteBook = _main.get("site_book") as SiteBook
		assert_true(book.add_site(id, id, lot.display_name, Clock.sim.day, sections), String(id))
		assert_true(_main.call("switch_site", id), String(id))
		for frame: int in 4:
			await tree.process_frame
		var dressing: NeighbourhoodDressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
		assert_true(dressing.set_rival_truck("Copley's"), "%s: room for a truck" % id)
		assert_eq(dressing.rival_truck_blocked_by(), "", "%s: the truck's spot is clear" % id)
		# Grow the lease where the lot can grow, and the truck must still stand clear.
		var base: ShopLayout = _main.get("_base_layout") as ShopLayout
		var editor: ShopEditor = _main.get("shop_editor") as ShopEditor
		var lease: Variant = _main.call("_lease_for", base)
		if lease != null:
			var grown: ShopLayout = lease.layout_for(base, 2)
			if grown != null and editor.grow_lot(grown):
				_main.set("lease_expanded", true)
				(_main.get_node("ShopView") as ShopView).set_lot(editor.footprint().lot)
				for frame: int in 2:
					await tree.process_frame
				dressing = (_main.get_node("ShopView") as ShopView).neighbourhood_dressing
				assert_not_null(dressing.rival_truck(), "%s: the truck stays when the lease grows" % id)
				assert_eq(dressing.rival_truck_blocked_by(), "", "%s: clear on the grown lease too" % id)
		dressing.clear_rival_truck()
