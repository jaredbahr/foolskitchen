extends TestCase

const REVIEW: Script = preload("res://tools/restroom_review.gd")


func test_review_fixture_uses_real_commands_and_keeps_two_toilets_reachable() -> void:
	var main: Node = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 1)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(main)
	Clock.set_speed(0)
	assert_eq(REVIEW.prepare(main, tree.root), "")
	var editor: ShopEditor = main.get("shop_editor") as ShopEditor
	assert_eq(editor.decor.item(Vector3i(1, 7, 3)).def_id, &"wall_hand_dryer")
	assert_eq(RoomRules.restroom_toilets((main.get("world") as SimWorld).grid).size(), 2)
	REVIEW.focus(main, false)
	var camera: Camera3D = main.get_node("CameraRig/Camera3D") as Camera3D
	assert_eq((main.get_node("ShopView") as ShopView).wall_mode, ShopView.WallMode.UP)
	assert_true(camera.global_position.y > 20.0, "overview clears the unchanged kitchen wall and stall divider")
	assert_true(camera.global_position.x > 3.0, "eastward component reveals the mirror frame")
	REVIEW.focus(main, true)
	assert_almost_eq(camera.global_position.z, 3.5, 0.001, "due-east close view avoids the foreground kitchen wall")
	main.free()
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)
