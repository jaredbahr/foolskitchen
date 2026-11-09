class_name ViralReviewText
extends RefCounted
## Plain words shared by the morning, demand breakdown and evening report.


static func evening(dish_name: String) -> String:
	var food: String = dish_name.strip_edges()
	if food.is_empty():
		food = "food"
	return "A guest's post about your %s is going viral! Expect more guests for a few days." % food


static func morning(factor: float) -> String:
	return "A guest's post is still bringing people in. " + demand_line(factor) \
		if factor > 1.0 else ""


static func demand_line(factor: float) -> String:
	if not is_finite(factor) or factor < 1.0:
		return ""
	return "Trending online: +%.0f%%" % roundf((factor - 1.0) * 100.0)
