class_name InspectionText
extends RefCounted
## Every player-facing word about health inspections (rule 11: no ids in the UI).

const HEADING: String = "Health inspection"
const CLEAN: String = "The inspector found nothing to mark down"


## "Health inspection: grade B".
static func grade_line(grade: StringName) -> String:
	return "%s: grade %s" % [HEADING, String(grade)]


## "Last inspection: B, day 12" for the hygiene overview.
static func last_line(grade: StringName, day: int) -> String:
	return "Last inspection: %s, day %d" % [String(grade), day]


const NONE_YET: String = "Last inspection: none yet"


## One plain sentence for a finding row ({kind, count}).
static func finding(row: Dictionary) -> String:
	var count: int = int(row.get("count", 0))
	match StringName(row.get("kind", &"")):
		InspectionModel.TABLES:
			return "A dirty table was left uncleared" if count == 1 \
				else "%d dirty tables were left uncleared" % count
		InspectionModel.FLOOR:
			return "There was a spill on the dining room floor" if count == 1 \
				else "There were %d spills and messes on the floor" % count
		InspectionModel.RESTROOM:
			return "The restroom needed cleaning"
		InspectionModel.STOCK:
			return "Food had gone off in the stock room"
		InspectionModel.DISHES:
			return "Dirty dishes were piling up"
	return ""


## The evening report's lines: the grade, then the worst findings.
static func report_lines(result: Dictionary, tuning: InspectionTuning) -> Array[String]:
	var lines: Array[String] = []
	if result.is_empty():
		return lines
	lines.append(grade_line(StringName(result["grade"])))
	var findings: Array = result.get("findings", [])
	if findings.is_empty():
		lines.append(CLEAN)
		return lines
	for index: int in mini(findings.size(), tuning.report_findings):
		lines.append(finding(findings[index]))
	return lines
