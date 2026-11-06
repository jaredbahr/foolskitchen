class_name InspectionTuning
extends Resource
## The surprise health inspector (#302), in data (data/balance/inspection.tres).
## When it may visit, how long it walks, what each finding costs and where the
## grade lines fall are all here; nothing about inspections is hard-coded.

## Shop (owner) level from which an inspector can visit.
@export var unlock_level: int = 3
## Visits are at least this many days apart (so at most one in any 7 days).
@export var min_gap_days: int = 7
## Chance, on each open day that may have a visit, drawn from the named
## "inspector" stream.
@export_range(0.0, 1.0, 0.01) var daily_chance: float = 0.15
## The inspector arrives somewhere in this share of the open hours.
@export_range(0.0, 1.0, 0.01) var arrival_from: float = 0.15
@export_range(0.0, 1.0, 0.01) var arrival_to: float = 0.55

## Ticks (10 a second) of walking the rooms before leaving: about a minute.
@export var visit_ticks: int = 600
## Ticks of looking about at each stop.
@export var look_ticks: int = 30
## Dining room stops on the round (the restroom, if any, is one more).
@export var dining_stops: int = 4
## The inspector leaves after this long whatever happens, so it can never
## stay in anybody's way.
@export var visit_cap_ticks: int = 1500

## Points a finding costs (more points is a worse shop).
@export var table_points: float = 2.0
@export var floor_spot_points: float = 1.0
@export var restroom_spot_points: float = 1.5
## Spoiled stock thrown out this morning: points per unit of currency lost,
## up to a cap so one big bin does not decide the grade alone.
@export var spoiled_points_per_cash: float = 0.25
@export var spoiled_points_cap: float = 6.0
## Dirty plates beyond this many are "piling up", then cost points each.
@export var dirty_plates_free: int = 3
@export var dirty_plate_points: float = 0.5

## A grade is A up to this many points, B up to the next line, then C.
@export var grade_a_max: float = 2.0
@export var grade_b_max: float = 7.0

## The grade card nudges arrivals for this many days after the visit.
@export var effect_days: int = 7
@export var factor_a: float = 1.05
@export var factor_b: float = 1.0
@export var factor_c: float = 0.9
## How many of the worst findings the evening report names.
@export var report_findings: int = 3


func is_valid() -> bool:
	for value: float in [daily_chance, arrival_from, arrival_to, table_points, floor_spot_points,
			restroom_spot_points, spoiled_points_per_cash, spoiled_points_cap, dirty_plate_points,
			grade_a_max, grade_b_max, factor_a, factor_b, factor_c]:
		if not is_finite(value) or value < 0.0:
			return false
	return unlock_level >= 1 and min_gap_days >= 1 and daily_chance <= 1.0 \
		and arrival_from <= arrival_to and arrival_to <= 1.0 and visit_ticks >= 1 \
		and look_ticks >= 1 and dining_stops >= 1 and visit_cap_ticks >= visit_ticks \
		and dirty_plates_free >= 0 and grade_a_max <= grade_b_max and effect_days >= 1 \
		and factor_a > 0.0 and factor_b > 0.0 and factor_c > 0.0 and report_findings >= 0


## The arrival factor a grade gives (1.0 for no grade).
func factor_for(grade: StringName) -> float:
	match grade:
		&"A":
			return factor_a
		&"B":
			return factor_b
		&"C":
			return factor_c
	return 1.0
