class_name GuestUrgencyTuning
extends Resource
## How strongly staff favour the guests closest to giving up (#307). A task's
## claim score is multiplied by 1 + weight x urgency, where urgency is the
## fraction (0..1) of the relevant patience the guest has already used. The
## multiplier only reorders work inside the job tier the player chose.

## Taking an order, delivering a meal or drink, and cooking a ticket.
@export_range(0.0, 8.0, 0.05) var guest_weight: float = 2.0
## Clearing a table while a party is waiting for one.
@export_range(0.0, 8.0, 0.05) var table_weight: float = 1.0


func is_valid() -> bool:
	return guest_weight >= 0.0 and table_weight >= 0.0
