extends TestCase
## The quirk badge over a guest (#661): drawn from the quirk's own `badge`
## texture, shown beside the mood dot and gone whenever the mood dot is.

const VIEW: PackedScene = preload("res://src/world/shop_view.tscn")
const QUIRKS: GuestQuirkCatalogue = preload("res://data/customers/quirks.tres")

var _view: ShopView
var _sim: RestaurantSim
var _world: SimWorld


func before_each() -> void:
	_world = SimWorld.new(SimGrid.new(Vector2i(8, 8)))
	_sim = RestaurantSim.new()
	_sim.world = _world
	_view = VIEW.instantiate() as ShopView


func after_each() -> void:
	_view.free()


func test_every_authored_quirk_has_its_own_badge() -> void:
	var seen: Array[Texture2D] = []
	for quirk: GuestQuirk in QUIRKS.quirks:
		assert_not_null(quirk.badge, "%s has a badge" % quirk.id)
		assert_false(seen.has(quirk.badge), "%s's badge is its own" % quirk.id)
		seen.append(quirk.badge)


func test_a_quirky_guest_shows_the_quirks_icon_and_a_plain_guest_shows_none() -> void:
	var plain: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	var quirky: Array[CustomerAgent] = []
	for quirk: GuestQuirk in QUIRKS.quirks:
		var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
		guest.quirk = quirk
		quirky.append(guest)
	await _show_world()
	var plain_badge: GuestQuirkBadge = _view.mood_nodes[plain.id].quirk_badge
	assert_false(plain_badge.visible, "no quirk, no badge")
	assert_null(plain_badge.texture)
	for guest: CustomerAgent in quirky:
		var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
		var badge: GuestQuirkBadge = icon.quirk_badge
		assert_eq(badge.get_parent(), icon, "the badge rides on the mood indicator")
		assert_true(badge.visible)
		assert_eq(badge.texture, guest.quirk.badge)
		assert_eq(badge.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
		assert_true(badge.no_depth_test)
		assert_true(badge.is_visible_in_tree())


func test_the_badge_sits_above_the_dot_without_covering_it() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	guest.quirk = QUIRKS.quirks[0]
	await _show_world()
	var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var badge: GuestQuirkBadge = icon.quirk_badge
	var dot_top: float = (icon.dot.mesh as SphereMesh).radius
	var badge_bottom: float = (badge.offset.y - badge.texture.get_height() / 2.0) * badge.pixel_size
	assert_true(badge_bottom >= dot_top, "the badge starts above the dot's top edge")


func test_a_new_quirk_gets_a_badge_by_data_alone() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	var fresh: GuestQuirk = QUIRKS.quirks[0].duplicate() as GuestQuirk
	fresh.id = &"fresh_quirk"
	fresh.badge = QUIRKS.quirks[1].badge
	guest.quirk = fresh
	await _show_world()
	assert_eq(_view.mood_nodes[guest.id].quirk_badge.texture, QUIRKS.quirks[1].badge)
	fresh.badge = null
	var other: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	other.quirk = fresh
	_view.show_world(_world)
	assert_false(_view.mood_nodes[other.id].quirk_badge.visible, "a quirk without a picture shows no badge")


func test_the_badge_follows_the_mood_dot_and_makes_no_new_nodes_per_frame() -> void:
	var guest: CustomerAgent = _guest(CustomerAgent.State.WAITING_FOOD)
	guest.quirk = QUIRKS.quirks[1]
	await _show_world()
	var icon: GuestMoodIndicator = _view.mood_nodes[guest.id]
	var badge: GuestQuirkBadge = icon.quirk_badge
	var children: int = icon.get_child_count()
	for _frame: int in range(3):
		_view._process(0.1)
	assert_eq(_view.mood_nodes[guest.id], icon)
	assert_eq(icon.get_child_count(), children)
	assert_true(badge.is_visible_in_tree())
	icon.hide()
	assert_false(badge.is_visible_in_tree(), "hiding the dot hides the badge")
	icon.show()
	# The guest leaves the waiting states: the dot goes, and the badge with it.
	guest.state = CustomerAgent.State.EATING
	_view._process(0.1)
	assert_false(_view.mood_nodes.has(guest.id))
	assert_false(is_instance_valid(badge) and badge.is_inside_tree(), "the badge is gone with the dot")


func _show_world() -> void:
	if not _view.is_inside_tree():
		var tree: SceneTree = Engine.get_main_loop() as SceneTree
		await tree.process_frame
		tree.root.add_child(_view)
	assert_true(_view.is_inside_tree(), "native rigs require actual scene-tree entry")
	_view.set_process(false)
	_view.show_world(_world)


func _guest(state: CustomerAgent.State) -> CustomerAgent:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 5151
	var guest: CustomerAgent = CustomerAgent.new(_sim, random)
	guest.state = state
	guest.queue_patience = 100
	guest.food_patience = 100
	guest.order = Order.new()
	guest.order.recipe_id = &"tomato_soup"
	var index: int = _world.all_agents().size()
	guest.cell = Vector2i(1 + index % 4, 1 + floori(float(index) / 4.0))
	_world.add_agent(guest)
	return guest
