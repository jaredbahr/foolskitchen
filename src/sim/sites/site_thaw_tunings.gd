class_name SiteThawTunings
extends RefCounted
## The balance data SiteThaw needs to decode and age a frozen site (FK-087).
## The session passes its own instances (main.gd may hold per-run copies);
## `authored()` loads the shipped files for tests and tools.

var thaw: SiteThawTuning
var demand: DemandTuning
var viral: ViralTuning
var rush: RushTuning
var booking: BookingTuning
var signature: SignatureTuning


func _init(demand_tuning: DemandTuning = null, viral_tuning: ViralTuning = null,
		rush_tuning: RushTuning = null, booking_tuning: BookingTuning = null,
		signature_tuning: SignatureTuning = null) -> void:
	demand = demand_tuning
	viral = viral_tuning
	rush = rush_tuning
	booking = booking_tuning
	signature = signature_tuning
	thaw = load("res://data/balance/site_thaw.tres") as SiteThawTuning


static func authored() -> SiteThawTunings:
	return SiteThawTunings.new(
		load("res://data/balance/demand.tres") as DemandTuning,
		load("res://data/balance/viral.tres") as ViralTuning,
		load("res://data/balance/rush_hour.tres") as RushTuning,
		load("res://data/balance/bookings.tres") as BookingTuning,
		load("res://data/balance/signature.tres") as SignatureTuning)


func is_valid() -> bool:
	return demand != null and demand.is_valid() and viral != null and viral.is_valid() \
		and rush != null and rush.is_valid() and booking != null and booking.is_valid() \
		and signature != null and signature.is_valid() \
		and thaw != null and thaw.is_valid()
