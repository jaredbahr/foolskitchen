class_name SoundDirector
extends Node
## Turns the running shop into sound (#117): a door bell as guests walk in, a
## coin sound as they pay, a chime for five-star reviews, a room tone that
## grows with the crowd, and a sizzle, fryer or coffee-machine loop while a
## station is being worked. It only listens to existing signals and reads
## view state; it never changes the simulation or draws random numbers.

const OPEN_PHASES: Array[SimClock.Phase] = [SimClock.Phase.OPEN, SimClock.Phase.LAST_ORDERS]
const ROOM_TONE: StringName = &"room_tone"
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


func bind(sim: RestaurantSim, view: ShopView) -> void:
	unbind()
	_sim = sim
	_view = view
	if _sim == null:
		return
	_sim.customer_arrived.connect(_on_customer_arrived)
	_sim.customer_paid.connect(_on_customer_paid)
	_sim.review_recorded.connect(_on_review_recorded)


func unbind() -> void:
	if _sim != null:
		if _sim.customer_arrived.is_connected(_on_customer_arrived):
			_sim.customer_arrived.disconnect(_on_customer_arrived)
		if _sim.customer_paid.is_connected(_on_customer_paid):
			_sim.customer_paid.disconnect(_on_customer_paid)
		if _sim.review_recorded.is_connected(_on_review_recorded):
			_sim.review_recorded.disconnect(_on_review_recorded)
	_sim = null
	_view = null
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
## its daytime or evening track during service and keeps playing while paused.
func refresh(light: float = 0.0) -> void:
	var serving: bool = _sim != null and OPEN_PHASES.has(Clock.sim.phase)
	if not display_only:
		Sounds.set_music_context(MusicTracks.service_context(serving, light))
	var running: bool = _sim != null and Clock.speed > 0 and OPEN_PHASES.has(Clock.sim.phase)
	var guests: int = 0
	if running and _sim.world != null:
		for agent: SimAgent in _sim.world.agents:
			if agent is CustomerAgent:
				guests += 1
	Sounds.set_loop_level(ROOM_TONE, float(guests) / float(Sounds.TUNING.room_tone_full_guests) if running else 0.0)
	_refresh_music(running, serving)
	# Read the view's current food layer: it is rebuilt when the world changes.
	var food: FoodPresentation = _view.food if _view != null else null
	for loop: StringName in FoodPresentation.STATION_LOOPS.values():
		var busy: int = int(food.busy_loops.get(loop, 0)) if running and food != null else 0
		Sounds.set_loop_level(loop, station_level(busy))


## The one counted jukebox plays its style while the shop is open; changing the
## style swaps the loop, and a closed, paused or jukebox-less shop is silent.
func _refresh_music(running: bool, serving: bool) -> void:
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
