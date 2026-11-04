class_name MenuThemeText
extends RefCounted
## The menu's own tag shares, using VibeModel's known-tag and vote rules.
## This readout does not choose the restaurant's active room theme or effects.

const DEFAULT_TUNING: VibeTuning = preload("res://data/balance/vibe.tres")
const PREFIX: String = "Menu leans: "


static func summary(menu: Array[RecipeDef], tuning: VibeTuning = null) -> String:
	var rules: VibeTuning = tuning if tuning != null else DEFAULT_TUNING
	if rules == null or not rules.is_valid():
		return PREFIX + "No theme"
	var tally: Dictionary = tally_votes(menu, rules)
	var votes: Dictionary[StringName, float] = tally["votes"]
	var source_weight: float = tally["weight"]
	if source_weight <= 0.0:
		return PREFIX + rules.no_theme_label
	var parts: Array[String] = []
	# Pick the strongest remaining vote each pass. Ties keep theme_order, the
	# same authored tie order used by VibeModel.
	while true:
		var best: StringName = &""
		var best_vote: float = 0.0
		for theme: StringName in rules.theme_order:
			if votes[theme] > best_vote:
				best = theme
				best_vote = votes[theme]
		if best.is_empty():
			break
		parts.append("%s %d%%" % [rules.theme_labels[best], roundi(best_vote / source_weight * 100.0)])
		votes[best] = 0.0
	return PREFIX + ", ".join(parts)


## The menu's known-tag votes per theme and their total weight, exactly as the
## summary and the street sign count them. `rules` must be valid.
static func tally_votes(menu: Array[RecipeDef], rules: VibeTuning) -> Dictionary:
	var votes: Dictionary[StringName, float] = {}
	for theme: StringName in rules.theme_order:
		votes[theme] = 0.0
	var source_weight: float = 0.0
	for recipe: RecipeDef in menu:
		if recipe == null:
			continue
		var known_tags: Array[StringName] = []
		# VibeModel._known_tags visits authored order: duplicate and unknown tags
		# cannot add votes, while a dish with two known tags votes for both.
		for theme: StringName in rules.theme_order:
			if recipe.theme_tags.has(theme):
				known_tags.append(theme)
		if known_tags.is_empty() or rules.theme_menu_weight == 0.0:
			continue
		source_weight += rules.theme_menu_weight
		for theme: StringName in known_tags:
			votes[theme] += rules.theme_menu_weight
	return {"votes": votes, "weight": source_weight}


## The one theme with strictly the most votes, or empty on a tie or no votes.
static func leading_theme(menu: Array[RecipeDef], tuning: VibeTuning = null) -> StringName:
	var rules: VibeTuning = tuning if tuning != null else DEFAULT_TUNING
	if rules == null or not rules.is_valid():
		return &""
	var tally: Dictionary = tally_votes(menu, rules)
	var counts: Dictionary[StringName, float] = tally["votes"]
	var best: StringName = &""
	var best_vote: float = 0.0
	var tied: bool = false
	for theme: StringName in rules.theme_order:
		if counts[theme] > best_vote:
			best = theme
			best_vote = counts[theme]
			tied = false
		elif counts[theme] == best_vote and best_vote > 0.0:
			tied = true
	return &"" if tied else best
