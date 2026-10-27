extends RefCounted
## Driver for tools/concept_shots.gd (manual captures only).
var tree: SceneTree
var out: String

func _frames(n: int) -> void:
	for i: int in range(n):
		await tree.process_frame

func _save(name: String) -> void:
	await _frames(3)
	var image: Image = tree.root.get_viewport().get_texture().get_image()
	image.save_png(out.path_join(name))
	print("saved ", name)

func run(scene_tree: SceneTree) -> void:
	tree = scene_tree
	var args: PackedStringArray = OS.get_cmdline_user_args()
	out = args[0]
	var setup: String = args[1]
	var ticks: int = int(args[2])
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", int(args[3]) if args.size() > 3 else 1)
	tree.root.add_child(main)
	main.call("start")
	await _frames(5)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	if setup != "default":
		print("apply ", ProbeSetups.apply(setup, main))
		sim.start_day()
	await _frames(10)
	if args.has("catalogue"):
		main.call("set_build_active", true)
		var catalogue: BuildCatalogue = main.get_node("Overlay/BuildCatalogue") as BuildCatalogue
		catalogue.set_mode(BuildCatalogue.BUY)
		catalogue.set_category(&"bar_cafe")
		await _frames(200)
		await _save("%s_catalogue.png" % setup)
		return
	if args.has("menu"):
		main.call("set_menu_visible", true)
		await _frames(20)
		await _save("%s_menu_top.png" % setup)
		var scroll: ScrollContainer = main.get_node("Overlay/MenuPanel/Panel/Content/Scroll") as ScrollContainer
		scroll.scroll_vertical = 100000
		await _frames(10)
		await _save("%s_menu_drinks.png" % setup)
		main.call("set_menu_visible", false)
		return
	Clock.sim.start_service()
	main.call("run_ticks", ticks)
	await _frames(30)
	await _save("%s_full.png" % setup)
	var camera: CameraRig = main.get_node("CameraRig") as CameraRig
	camera.frame_area(Vector2(5.0, 3.6), Vector2(8, 8), 8.0, true)
	await _frames(30)
	await _save("%s_close.png" % setup)
	for q: int in range(1, 4):
		camera.rotate_quarter(1)
		await _frames(60)
		await _save("%s_close_q%d.png" % [setup, q])
