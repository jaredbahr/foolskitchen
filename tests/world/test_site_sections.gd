extends TestCase
## Every save section is either the owner's (shared by every site) or one
## site's (FK-087). A new section must pick a side in SiteSections.

const MAIN: PackedScene = preload("res://src/world/main.tscn")
var _main: Node
var _providers: Dictionary


func before_each() -> void:
	_providers = SaveSystem._providers.duplicate(true)
	Clock.set_speed(0)


func after_each() -> void:
	if is_instance_valid(_main):
		_main.get_parent().remove_child(_main)
		_main.free()
		_main = null
	SaveSystem._providers = _providers
	Clock.set_speed(0)
	Economy.reset(0)
	GameState.new_run(1)


func test_every_registered_section_is_global_or_per_site_and_never_both() -> void:
	_main = MAIN.instantiate()
	_main.set("use_saves", false)
	_main.set("new_game_seed_override", 1)
	(Engine.get_main_loop() as SceneTree).root.add_child(_main)
	_main.call("start")
	Clock.set_speed(0)
	var keys: PackedStringArray = SaveSystem.keys()
	assert_true(keys.has("pantry") and keys.has("economy"), "the session registers both money sections")
	for key: String in keys:
		assert_true(SiteSections.is_global(key) != SiteSections.is_per_site(key),
			"save section '%s' must be in exactly one SiteSections list" % key)
	for key: String in SiteSections.GLOBAL + SiteSections.PER_SITE:
		assert_true(keys.has(key), "SiteSections lists '%s', but nothing registers it" % key)
