class_name MishapText
extends RefCounted
## Player wording for mishaps and maintenance; never expose task/category IDs.


static func cleaning(kind: int) -> String:
	return "Sweep up a broken plate" if kind == CleanlinessState.MessKind.BROKEN_PLATE \
		else ("Mop up a spill" if kind == CleanlinessState.MessKind.SPILL else "Mop up a floor spot")


static func degrease(station_name: String) -> String:
	return "Degrease the %s" % station_name.to_lower()


static func daily(spills: int, broken: int, degreased: int) -> String:
	var text: String = "Mishaps: %d %s, %d broken %s; %d %s degreased" % [spills,
		"spill" if spills == 1 else "spills", broken, "plate" if broken == 1 else "plates",
		degreased, "station" if degreased == 1 else "stations"]
	return text + (". Paid replacement plates arrive tomorrow morning." if broken > 0 else ".")
