class_name SoundDirector
extends Node
## Turns the running shop into sound (#117): a door bell as guests walk in, a
## coin sound as they pay, a chime for five-star reviews, a room tone that
## grows with the crowd, and a sizzle, fryer or coffee-machine loop while a
## station is being worked. The dining room (#366) adds table clinks that
## follow real events (a plate set down, a glass served, cutlery from eating
## tables, a table bussed, plates washed) and chatter layers that swell with
## the crowd. It only listens to existing signals and reads sim and view
## state; it never changes the simulation or draws from its random streams.
## Cutlery timing comes from its own seeded generator.

const OPEN_PHASES: Array[SimClock.Phase] = [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]
const ROOM_TONE: StringName = &"room_tone"
const AMBIENCE: AmbienceTuning = preload("res://data/audio/ambience.tres")
## The cutlery timer's own seed: a presentation stream, never the sim's.
const CUTLERY_SEED: int = 3660
## Longest frame counted toward the cutlery timer and chatter fades, so a
## hitch or a breakpoint doesn't fire a burst.
const MAX_FRAME_SECONDS: float = 0.25
## One station worked plays its loop at this level; each extra adds a little.
const ONE_STATION_LEVEL: float = 0.7
const EXTRA_STATION_LEVEL: float = 0.15

## The jukebox's music is a quiet bed under the room; its loop is the style's id.
const MUSIC_LEVEL: float = 1.0

## Set by a display-only Main (the title's backdrop): it must never drive the
## music, which belongs to the title screen there.
var display_only: bool = false

var _sim: RestaurantSim
var _view: ShopView
## The counted jukebox is looked up again only when the grid changes.
var _music_grid_version: int = -1
var _music_item_id: int = -1
var _music_loop: StringName = &""
var _content: ContentDB
## Chatter layers' current (faded) levels.
var _chatter: Dictionary[StringName, float] = {}
var _cutlery_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _cutlery_wait: float = INF
var _last_refresh_usec: int = -1
var _last_clean: int = -1
var _last_dirty: int = -1


func bind(sim: RestaurantSim, view: ShopView, content: ContentDB = null) -> void:
	unbind()
	_sim = sim
	_view = view
	_content = content
	_cutlery_rng.seed = CUTLERY_SEED
	_cutlery_wait = INF
	if _sim == null:
		return
	_sim.customer_arrived.connect(_on_customer_arrived)
	_sim.customer_paid.connect(_on_customer_paid)
	_sim.review_recorded.connect(_on_review_recorded)
	_sim.orders.order_delivered.connect(_on_order_delivered)
	if _sim.world != null:
		_sim.world.board.task_completed.connect(_on_task_completed)
	if _sim.kitchen != null:
		_sim.kitchen.plates_changed.connect(_on_plates_changed)


func unbind() -> void:
	if _sim != null:
		if _sim.customer_arrived.is_connected(_on_customer_arrived):
			_sim.customer_arrived.disconnect(_on_customer_arrived)
		if _sim.customer_paid.is_connected(_on_customer_paid):
			_sim.customer_paid.disconnect(_on_customer_paid)
		if _sim.review_recorded.is_connected(_on_review_recorded):
			_sim.review_recorded.disconnect(_on_review_recorded)
		if _sim.orders.order_delivered.is_connected(_on_order_delivered):
			_sim.orders.order_delivered.disconnect(_on_order_delivered)
		if _sim.world != null and _sim.world.board.task_completed.is_connected(_on_task_completed):
			_sim.world.board.task_completed.disconnect(_on_task_completed)
		if _sim.kitchen != null and _sim.kitchen.plates_changed.is_connected(_on_plates_changed):
			_sim.kitchen.plates_changed.disconnect(_on_plates_changed)
	_sim = null
	_view = null
	_content = null
	_chatter.clear()
	_last_refresh_usec = -1
	_last_clean = -1
	_last_dirty = -1
	_music_grid_version = -1
	_music_item_id = -1
	_music_loop = &""
	Sounds.stop_loops()
	if not display_only:
		Sounds.set_music_ducked(false)
		Sounds.set_music_context(&"")


func _exit_tree() -> void:
	unbind()


## Sets the ambience loops from the current view; main calls it every frame
## with the shop's light (`DayLight.Look.interior_energy`). Everything is silent
## outside service hours and while the game is paused. The music instead picks
## its daytime or evening track during service, the evening report's track while
## the report is open, and keeps playing while paused.
## Chatter fades rather than cuts, so closing lets the room die away.
func refresh(light: float = 0.0, report_open: bool = false) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var delta: float = 0.0
	if _last_refresh_usec >= 0:
		delta = clampf(float(now_usec - _last_refresh_usec) / 1000000.0, 0.0, MAX_FRAME_SECONDS)
	_last_refresh_usec = now_usec
	var serving: bool = _sim != null and OPEN_PHASES.has(Clock.sim.phase)
	if not display_only:
		Sounds.set_music_context(MusicTracks.service_context(serving, light, report_open))
	var running: bool = _sim != null and Clock.speed > 0 and OPEN_PHASES.has(Clock.sim.phase)
	var guests: int = 0
	var staying: int = 0
	var eaters: Array[Vector2i] = []
	if running and _sim.world != null:
		for agent: SimAgent in _sim.world.agents:
			var customer: CustomerAgent = agent as CustomerAgent
			if customer == null:
				continue
			guests += 1
			if customer.state != CustomerAgent.State.LEAVING and customer.state != CustomerAgent.State.LEFT:
				staying += 1
			if customer.state == CustomerAgent.State.EATING:
				eaters.append(customer.cell)
	var ambient: bool = running and not display_only
	Sounds.set_loop_level(ROOM_TONE, float(guests) / float(AMBIENCE.room_tone_full_guests) if ambient else 0.0)
	var jukebox_playing: bool = _refresh_music(running, serving)
	_refresh_chatter(staying if ambient else 0, jukebox_playing, delta)
	if not ambient:
		eaters.clear()
	_refresh_cutlery(eaters, delta)
	# Read the view's current food layer: it is rebuilt when the world changes.
	var food: FoodPresentation = _view.food if _view != null else null
	for loop: StringName in FoodPresentation.STATION_LOOPS.values():
		var busy: int = int(food.busy_loops.get(loop, 0)) if running and food != null else 0
		Sounds.set_loop_level(loop, station_level(busy))


## The one counted jukebox plays its style while the shop is open; changing the
## style swaps the loop, and a closed, paused or jukebox-less shop is silent.
## Returns whether the jukebox is playing now.
func _refresh_music(running: bool, serving: bool) -> bool:
	var wanted: StringName = &""
	var jukebox_present: bool = false
	if serving and _sim != null and _sim.world != null:
		var grid: SimGrid = _sim.world.grid
		if grid.version != _music_grid_version:
			_music_grid_version = grid.version
			var counted: PlacedItem = Jukebox.counted_item(grid)
			_music_item_id = counted.id if counted != null else -1
		var placed: PlacedItem = grid.item(_music_item_id) if _music_item_id >= 0 else null
		if placed != null and not placed.removed:
			jukebox_present = true
			if running:
				wanted = Jukebox.loop_id(placed.def as ItemDef, placed.variant_id)
	if wanted != _music_loop:
		if not _music_loop.is_empty():
			Sounds.set_loop_level(_music_loop, 0.0)
		_music_loop = wanted
	if not _music_loop.is_empty():
		Sounds.set_loop_level(_music_loop, MUSIC_LEVEL)
	# The theme stays out of the way for the whole open shop, paused or not.
	if not display_only:
		Sounds.set_music_ducked(jukebox_present)
	return not _music_loop.is_empty()


## Crossfades the chatter layers toward the crowd's levels (`AmbienceMix`),
## quieter under a playing jukebox. Layers with no file yet stay silent.
func _refresh_chatter(crowd: int, jukebox_playing: bool, delta: float) -> void:
	var targets: Dictionary[StringName, float] = AmbienceMix.chatter_levels(crowd, AMBIENCE.chatter_anchors())
	var gain: float = AmbienceMix.chatter_gain(jukebox_playing, AMBIENCE.chatter_jukebox_duck_db)
	for layer: StringName in AmbienceTuning.CHATTER_LAYERS:
		var target: float = float(targets.get(layer, 0.0)) * gain
		var level: float = AmbienceMix.fade(float(_chatter.get(layer, 0.0)), target, delta, AMBIENCE.chatter_fade_seconds)
		_chatter[layer] = level
		Sounds.set_loop_level(layer, level)


## Now and then a cutlery clink from one of the tables where guests are
## eating; more eaters clink more often, up to the tuned cap.
func _refresh_cutlery(eaters: Array[Vector2i], delta: float) -> void:
	var rate: float = AmbienceMix.cutlery_rate(eaters.size(), AMBIENCE.cutlery_per_eater, AMBIENCE.cutlery_max_rate)
	if rate <= 0.0:
		_cutlery_wait = INF
		return
	if is_inf(_cutlery_wait):
		_cutlery_wait = AmbienceMix.next_gap(_cutlery_rng, rate)
	_cutlery_wait -= delta
	if _cutlery_wait > 0.0:
		return
	_cutlery_wait = AmbienceMix.next_gap(_cutlery_rng, rate)
	var cell: Vector2i = eaters[_cutlery_rng.randi_range(0, eaters.size() - 1)]
	_clink(&"cutlery", cell)


## Clinks follow events only while the shop is open and running, never on the
## title's backdrop.
func _clinks_live() -> bool:
	return not display_only and _sim != null and Clock.speed > 0 and OPEN_PHASES.has(Clock.sim.phase)


func _clink(kind: StringName, cell: Vector2i) -> void:
	if cell == SimGrid.NO_CELL:
		Sounds.play_clink(kind)
		return
	var position: Vector3 = GridMath.cell_to_world(cell)
	if _view != null and _view.is_inside_tree():
		position = _view.global_transform * position
	Sounds.play_clink(kind, position, true)


func _item_cell(item_id: int) -> Vector2i:
	if _sim == null or _sim.world == null:
		return SimGrid.NO_CELL
	var placed: PlacedItem = _sim.world.grid.item(item_id)
	return placed.origin if placed != null else SimGrid.NO_CELL


func _on_order_delivered(order: Order) -> void:
	if not _clinks_live():
		return
	var recipe: RecipeDef = _content.recipe(order.recipe_id) if _content != null else null
	var drink: bool = recipe != null and recipe.is_drink()
	var cell: Vector2i = order.seat_cell if order.seat_cell != SimGrid.NO_CELL else _item_cell(order.table_item_id)
	_clink(&"glass" if drink else &"plate", cell)


func _on_task_completed(task: SimTask) -> void:
	if task.kind != &"bus_table" or not _clinks_live():
		return
	_clink(&"dish_stack", _item_cell(int(task.payload.get("table_item_id", 0))))


## A plate washed: fewer dirty and more clean than last time.
func _on_plates_changed(clean: int, _total: int, dirty: int, _in_use: int) -> void:
	var washed: bool = _last_dirty >= 0 and dirty < _last_dirty and clean > _last_clean
	_last_clean = clean
	_last_dirty = dirty
	if not washed or not _clinks_live():
		return
	var cell: Vector2i = SimGrid.NO_CELL
	for agent: SimAgent in _sim.world.agents:
		var staff: StaffAgent = agent as StaffAgent
		if staff != null and staff.task != null and staff.task.kind == &"wash":
			cell = staff.cell
			break
	_clink(&"sink", cell)


static func station_level(busy: int) -> float:
	if busy <= 0:
		return 0.0
	return minf(ONE_STATION_LEVEL + EXTRA_STATION_LEVEL * float(busy - 1), 1.0)


func _on_customer_arrived(_customer: CustomerAgent) -> void:
	Sounds.play(&"door_bell")


func _on_customer_paid(_customer: CustomerAgent, _order: Order, _amount: int) -> void:
	Sounds.play(&"cash")


func _on_review_recorded(row: Dictionary) -> void:
	if int(row.get("stars", 0)) == 5:
		Sounds.play(&"star_chime")
