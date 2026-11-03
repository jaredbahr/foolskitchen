class_name DayLightTuning
extends Resource
## Key frames of the day's light (#208), by minute of the day (0..1440).
## Every array has one entry per key frame; DayLight blends between
## neighbours. Presentation only.

@export var minutes: PackedFloat32Array = PackedFloat32Array()
@export var key_color: PackedColorArray = PackedColorArray()
@export var key_energy: PackedFloat32Array = PackedFloat32Array()
## The key light's downward angle in degrees (negative is down). Its compass
## direction never changes, so light keeps coming from the upper left.
@export var key_pitch: PackedFloat32Array = PackedFloat32Array()
@export var fill_energy: PackedFloat32Array = PackedFloat32Array()
@export var ambient_color: PackedColorArray = PackedColorArray()
@export var ambient_energy: PackedFloat32Array = PackedFloat32Array()
@export var sky_top: PackedColorArray = PackedColorArray()
@export var sky_horizon: PackedColorArray = PackedColorArray()
@export var sky_ground: PackedColorArray = PackedColorArray()
## The shop's own warm lights over the floor (0 by day, rising at dusk).
@export var interior_energy: PackedFloat32Array = PackedFloat32Array()
@export var interior_color: Color = Color(1.0, 0.8, 0.58)
## Multiplies the glow of lit items (neon, string lights) and window pools.
@export var glow: PackedFloat32Array = PackedFloat32Array()
## Morning prep shows this many minutes before opening (never before 06:00).
@export var prep_lead_minutes: float = 60.0
## Last orders runs over this many minutes after closing time.
@export var last_orders_minutes: float = 60.0
## After closing the shop shows this late (capped just before midnight).
@export var closed_after_minutes: float = 150.0


func size() -> int:
	return minutes.size()


func is_valid() -> bool:
	var count: int = minutes.size()
	if count < 2:
		return false
	for array: Variant in [key_color, key_energy, key_pitch, fill_energy, ambient_color, ambient_energy,
			sky_top, sky_horizon, sky_ground, glow, interior_energy]:
		if (array as Variant).size() != count:
			return false
	for index: int in range(1, count):
		if minutes[index] <= minutes[index - 1]:
			return false
	return minutes[0] >= 0.0 and minutes[count - 1] <= 1440.0
