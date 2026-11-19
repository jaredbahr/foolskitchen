class_name GuestQuirkCatalogue
extends Resource
## Authored guest quirks and how often an ordinary guest has one. The caller
## passes the named `quirks` stream; this class never creates or seeds one.

## Chance that an eligible guest has a quirk at all.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.125
## Below this owner level no quirk is rolled and the stream is never asked for.
@export_range(1, 20, 1) var unlock_level: int = 3
@export var quirks: Array[GuestQuirk] = []


func is_valid() -> bool:
	if not is_finite(chance) or chance < 0.0 or chance > 1.0 or unlock_level < 1:
		return false
	var ids: Dictionary[StringName, bool] = {}
	for quirk: GuestQuirk in quirks:
		if quirk == null or not quirk.is_valid() or ids.has(quirk.id):
			return false
		ids[quirk.id] = true
	return true


func find_quirk(id: StringName) -> GuestQuirk:
	for quirk: GuestQuirk in quirks:
		if quirk != null and quirk.id == id:
			return quirk
	return null


## One chance draw, then (on a hit with at least one quirk suiting the type)
## one weighted pick. Returns null for no quirk.
func roll(random: RandomNumberGenerator, type_id: StringName) -> GuestQuirk:
	if random == null or not is_valid():
		return null
	if random.randf() >= chance:
		return null
	var eligible: Array[GuestQuirk] = []
	var total: float = 0.0
	for quirk: GuestQuirk in quirks:
		if quirk.suits(type_id):
			eligible.append(quirk)
			total += quirk.weight
	if eligible.is_empty():
		return null
	var ticket: float = random.randf() * total
	for quirk: GuestQuirk in eligible:
		ticket -= quirk.weight
		if ticket < 0.0:
			return quirk
	return eligible.back()
