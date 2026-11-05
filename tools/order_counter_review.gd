extends "res://src/world/main.gd"
## Explicit, unsaved display fixture for #293, not a balance claim. The probe's
## real coffee_counter shop (the order counter continuing the bar) is opened,
## and drink guests walk in from the street door at a steady pace until a real
## queue stands in front of the till: one guest ordering, others lined up on
## the cells behind, a takeaway waiting at the pickup cell. Nothing is staged:
## the guests, orders and servers are the ordinary sim.
## Capture with tools/screenshot.sh --scene=res://tools/order_counter_review.tscn
## --speed=0 --frames=90.

const SEEDS: Array[int] = [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
const ARRIVAL_GAP: int = 20
const MAX_TICKS: int = 1200


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 1
	skip_owner_picker = true
	super._ready()
	if sim == null or not ProbeSetups.apply("coffee_counter", self):
		push_error("Order counter review could not build its café")
		return
	if not Clock.sim.start_service():
		push_error("Order counter review could not open service")
		return
	sim.spawner._remaining = 1000000
	var entries: Array[Vector2i] = world.grid.entries()
	var arrivals: int = 0
	var line: int = 0
	var ordering: int = 0
	for tick: int in MAX_TICKS:
		if tick % ARRIVAL_GAP == 0 and arrivals < SEEDS.size():
			var random: RandomNumberGenerator = RandomNumberGenerator.new()
			random.seed = SEEDS[arrivals]
			var guest: CustomerAgent = sim.add_visitor(entries[arrivals % entries.size()], random, null, RecipeDef.COFFEE)
			guest.food_patience = 4000
			arrivals += 1
		sim.advance()
		EventBus.sim_ticked.emit(Clock.sim.tick)
		line = 0
		ordering = 0
		for guest: CustomerAgent in sim.customers():
			if guest.counter_visit and guest.state == CustomerAgent.State.QUEUED:
				line += 1
			elif guest.counter_visit and guest.counter_stage == CustomerAgent.Counter.AT_COUNTER:
				ordering += 1
		if line == 3 and ordering >= 1 and arrivals >= 5:
			break
	Clock.set_speed(0)
	refresh_presentation()
	($ShopView as ShopView).set_wall_mode(ShopView.WallMode.DOWN)
	_frame_queue()
	var cells: Array[String] = []
	for guest: CustomerAgent in sim.customers():
		cells.append("%d:%s:%s" % [guest.id, CustomerAgent.State.keys()[guest.state], guest.cell])
	print("ORDER_COUNTER_REVIEW ", JSON.stringify({"ticks": sim.world.now, "in_line": line, "ordering": ordering,
		"takeaways_waiting": _takeaways_waiting(), "customers": sim.customers().size(), "cells": cells}))


func _takeaways_waiting() -> int:
	var count: int = 0
	for guest: CustomerAgent in sim.customers():
		if guest.takeaway and guest.state == CustomerAgent.State.WAITING_FOOD:
			count += 1
	return count


## The counter and the cells its line uses, from a three-quarter view.
func _frame_queue() -> void:
	var rig: CameraRig = $CameraRig as CameraRig
	var world_cell: Vector3 = GridMath.cell_to_world(Vector2i(12, 10))
	rig.minimum_zoom = 4.0
	rig.initial_yaw_degrees = 135.0
	rig.frame_area(Vector2(world_cell.x, world_cell.z), Vector2(8.0, 8.0), 6.2, true)
	rig.set_process(false)
