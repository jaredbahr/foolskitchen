extends Node
## Global signal hub. Systems talk to each other through these signals,
## never through long node paths. Add signals here as systems need them,
## with a doc comment saying who emits it.

## Emitted by Clock when the day phase changes (see Clock.Phase).
signal day_phase_changed(day: int, phase: int)

## Emitted by Clock every sim tick, after the sim has advanced.
signal sim_ticked(tick: int)

## Emitted by Economy whenever cash changes. `reason` is a short tag like "sale" or "wages".
signal cash_changed(new_cash: int, delta: int, reason: StringName)

## Emitted for each accepted clock speed request, including keyboard shortcuts.
signal speed_changed(speed: int)

## Public service events forwarded by Main from the live restaurant.
signal dish_sold_out(display_name: String)
signal health_inspector_arrived()
signal guest_left_angry()

## Morning menu requests to accept or decline the one offered group booking.
signal booking_accept_requested()
signal booking_decline_requested()
