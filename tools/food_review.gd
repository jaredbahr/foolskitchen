extends Node3D
## Deterministic, real service capture. No tickets, stock, staffing, traits or
## chance values are forced. The same tool can run on main for a paired image.

var main: Node
var fixture: Dictionary = {}
var _frames: int = 0


func _ready() -> void:
	main = (load("res://src/world/main.tscn") as PackedScene).instantiate()
	main.set("use_saves", false)
	main.set("new_game_seed_override", 99)
	add_child(main)
	var clock: Node = get_node("/root/Clock")
	clock.call("set_speed", 0)
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var view: ShopView = main.get_node("ShopView") as ShopView
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	rig.edge_pan_enabled = false
	if not sim.world.clock.start_service():
		push_error("Food review could not open the seeded shop")
		return
	_checkpoint(false)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 30:
		_checkpoint(true)


func _checkpoint(stove: bool) -> void:
	var sim: RestaurantSim = main.get("sim") as RestaurantSim
	var view: ShopView = main.get_node("ShopView") as ShopView
	var found: bool = false
	for tick: int in range(5500):
		main.call("run_ticks", 1)
		view._process(0.0)
		if _busy(sim, stove):
			found = true
			break
	fixture = {"seed": 99, "world_tick": sim.world.now, "real_service": true,
		"checkpoint": "stove" if stove else "busy",
		"busy_checkpoint_found": found, "served": sim.served_today,
		"ready_orders": sim.orders.orders_in_state(Order.State.READY).size(),
		"dirty_tables": sim.kitchen.dirty_tables.size()}
	if not found:
		push_error("Seeded food review did not reach its checkpoint")
		return
	if "food" in view:
		var food: Node = view.get("food") as Node
		var stages: Dictionary[StringName, int] = {}
		var dishes: Array[Dictionary] = []
		for dish: Node3D in food.get("pool"):
			if not dish.visible:
				continue
			var stage: StringName = dish.get("stage")
			stages[stage] = stages.get(stage, 0) + 1
			dishes.append({"order": dish.get("order_id"), "recipe": dish.get("recipe_id"),
				"stage": stage, "parent": str(dish.get_parent().name),
				"position": [dish.position.x, dish.position.y, dish.position.z]})
		fixture["visible_stages"] = stages
		fixture["dishes"] = dishes
		var emitting: Array[int] = []
		var steam: Dictionary = food.get("steam")
		for item_id: int in steam:
			if (steam[item_id] as CPUParticles3D).emitting:
				emitting.append(item_id)
		fixture["emitting_stations"] = emitting
	print("FOOD REVIEW: ", JSON.stringify(fixture))


func _busy(sim: RestaurantSim, stove: bool) -> bool:
	if not stove and (sim.orders.orders_in_state(Order.State.READY).is_empty() or sim.kitchen.dirty_tables.is_empty()):
		return false
	var eating: bool = false
	var working: bool = false
	for agent: SimAgent in sim.world.agents:
		if agent is CustomerAgent and (agent as CustomerAgent).state == CustomerAgent.State.EATING:
			eating = true
		if agent is StaffAgent:
			var staff: StaffAgent = agent as StaffAgent
			var station: PlacedItem = sim.world.grid.item(staff._held_item_id)
			working = working or (station != null and (station.def as ItemDef).id in [&"stove", &"fryer"]
				and staff.task != null and staff.task.kind == &"cook"
				and AgentPresentationController.frame_for(staff, sim.world).working)
	return eating and (working or not stove)
