extends "res://src/world/main.gd"
## Explicit, unsaved review of the disguised food critic (#303). Capture with
##   bash tools/screenshot.sh --out=screens/critic --scene=res://tools/critic_review.tscn --frames=12,90 --speed=0
## Frame 12 is the critic at a table with the notebook in hand and the Inspect
## panel listing their tells; frame 90 is the evening report with the critic's
## verdict. The shop, the critic's disguise, their tells and the weighted
## review all go through the real code; only the seated pose and the cooked
## quality are staged here. Nothing is saved and no service tick is run.

const FRAMES_BEFORE_REPORT: int = 40

var _frame: int = 0
var _ready_fixture: bool = false
var _guest: CustomerAgent
var _tick: int = 0


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 303
	super._ready()
	Clock.set_speed(0)
	var table: PlacedItem = _middle_table()
	if table == null or table.seat_cells.is_empty():
		_fail("requires the original middle table")
		return
	var seat: Vector2i = table.seat_cells[0]
	var tuning: CriticTuning = CRITIC.duplicate() as CriticTuning
	tuning.daily_chance = 1.0
	sim.critic.tuning = tuning
	sim.set_customer_level(2)
	if not Clock.sim.start_service():
		_fail("could not enter service")
		return
	# Real draws from the critic's stream, from the first seed whose draw shows
	# the notebook and the dearest order (so the capture shows both a prop and
	# a line that only exists after ordering).
	for candidate: int in range(303, 400):
		var probe: FoodCritic = FoodCritic.new(tuning)
		var stream: RandomNumberGenerator = RandomNumberGenerator.new()
		stream.seed = candidate
		probe.plan_day(Clock.sim.day, 2, func() -> RandomNumberGenerator: return stream)
		if probe.has_tell(FoodCritic.NOTEBOOK) and probe.has_tell(FoodCritic.PRICIEST):
			_stream = RandomNumberGenerator.new()
			_stream.seed = candidate
			break
	sim.critic_rng_provider = func() -> RandomNumberGenerator: return _staged_stream()
	sim.critic.plan_day(Clock.sim.day, 2, sim.critic_rng_provider)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 303001
	_guest = sim.add_customer(world.grid.entries()[0], random, customer_type_catalogue.find_type(&"regular"))
	if _guest == null or not _guest.disguise_as_critic(sim.critic.tells, sim.critic.tuning) \
			or not table.reserve(seat, _guest.id):
		_fail("the critic could not be seated")
		return
	_guest.table_item_id = table.id
	_guest.seat_cell = seat
	_guest.cell = seat
	_guest.path.clear()
	_guest.state = CustomerAgent.State.EATING
	var recipe: RecipeDef = sim.menu[0]
	var priciest: RecipeDef = recipe
	for choice: RecipeDef in sim.menu:
		if sim.price_of(choice) > sim.price_of(priciest):
			priciest = choice
	_guest.order = Order.new()
	_guest.order.recipe_id = priciest.id
	_guest.order.price = sim.price_of(priciest)
	_guest.order.quality = 0.9
	_guest.order.state = Order.State.DELIVERED
	var rig: CameraRig = $CameraRig
	var focus: Vector3 = GridMath.cell_to_world(seat)
	rig.minimum_zoom = 3.0
	rig.edge_pan_enabled = false
	rig.frame_area(Vector2(focus.x - 0.4, focus.z + 0.4), Vector2(2.4, 2.4), 2.4, true)
	($ShopView as ShopView)._process(0.0)
	if not select_agent(_guest.id):
		_fail("could not open the production inspector")
		return
	_tick = world.now
	_ready_fixture = true


func _staged_stream() -> RandomNumberGenerator:
	if _stream == null:
		_stream = RandomNumberGenerator.new()
		_stream.seed = 303
	return _stream


var _stream: RandomNumberGenerator


func _middle_table() -> PlacedItem:
	var tables: Array[PlacedItem] = []
	for it: PlacedItem in world.grid.items():
		if not it.seat_cells.is_empty():
			tables.append(it)
	if tables.size() != 3:
		return null
	tables.sort_custom(func(a: PlacedItem, b: PlacedItem) -> bool: return a.origin.x < b.origin.x)
	return tables[1]


func _process(_delta: float) -> void:
	if not _ready_fixture:
		return
	_frame += 1
	if _frame == 10:
		_assert_inspector()
	elif _frame == FRAMES_BEFORE_REPORT:
		# The real departure: the paid critic leaves and the weighted review lands.
		_guest.paid = true
		_guest.state = CustomerAgent.State.LEFT
		sim.record_departure(_guest)
		_inspect_panel.clear()
		shown_report = build_report(Clock.sim.day)
		_report.call(&"show_report", shown_report)
	elif _frame == 70:
		var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
		scroll.ensure_control_visible(_report.get("critic_summary") as Label)
	elif _frame == 80:
		_assert_report()


func _assert_inspector() -> void:
	var details: Label = _inspect_panel.get_node("%Details") as Label
	var person: PersonView = ($ShopView as ShopView).agent_nodes.get(_guest.id) as PersonView
	var book: Node3D = person.get_node_or_null("Notebook") as Node3D if person != null else null
	if book == null or not book.visible or not _inspect_panel.is_visible_in_tree() \
			or not details.text.contains("Scribbling in a little notebook") \
			or details.text.to_lower().contains("critic"):
		_fail("notebook or plain tell lines are missing")
		return
	print("CRITIC_REVIEW ", JSON.stringify({"stage": "inspector", "tells": sim.critic.tells,
		"inspector": details.text, "world_tick": world.now, "use_saves": use_saves}))


func _assert_report() -> void:
	var heading: Label = _report.get("critic_heading") as Label
	var summary: Label = _report.get("critic_summary") as Label
	var scroll: ScrollContainer = _report.get_node("Panel/Column/Scroll") as ScrollContainer
	if shown_report == null or not _report.is_visible_in_tree() or summary == null \
			or not summary.is_visible_in_tree() or shown_report.critic_lines.size() != 3 \
			or heading.text != "A food critic visited today" or not summary.text.contains("(5 stars)") \
			or not scroll.get_global_rect().grow(1.0).encloses(heading.get_global_rect()) \
			or not scroll.get_global_rect().grow(1.0).encloses(summary.get_global_rect()):
		_fail("the report line is missing or outside the scroll view")
		return
	print("CRITIC_REVIEW ", JSON.stringify({"stage": "report", "lines": shown_report.critic_lines,
		"reputation_before": shown_report.reputation_before, "reputation_after": shown_report.reputation_after,
		"world_tick": world.now, "use_saves": use_saves}))


func _fail(reason: String) -> void:
	_ready_fixture = false
	push_error("Critic review: " + reason)
