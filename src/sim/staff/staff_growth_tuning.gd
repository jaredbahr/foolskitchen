class_name StaffGrowthTuning
extends Resource
## Authored XP per finished task and XP needed for each next skill level.
## Level timing must be checked with the manual balance probe before this
## feature is presented as complete.

const SKILLS: Array[StringName] = [&"cooking", &"service", &"cleaning"]

@export var task_skills: Dictionary[StringName, StringName] = {}
@export var task_xp: Dictionary[StringName, int] = {}
## Index 0 is the XP needed at skill 1 to reach skill 2, and so on.
@export var next_level_xp: PackedInt32Array = PackedInt32Array([70, 90, 110, 130])


func is_valid() -> bool:
	if next_level_xp.size() != 4 or task_skills.is_empty() or task_skills.size() != task_xp.size():
		return false
	for needed: int in next_level_xp:
		if needed <= 0 or needed > 1000000:
			return false
	for kind: StringName in task_skills:
		if not SKILLS.has(task_skills[kind]) or not task_xp.has(kind) \
				or task_xp[kind] <= 0 or task_xp[kind] > 1000:
			return false
	return true


func skill_for_task(kind: StringName) -> StringName:
	return task_skills.get(kind, &"")


func xp_for_task(kind: StringName) -> int:
	return task_xp.get(kind, 0)


func needed_for_next_level(level: int) -> int:
	return next_level_xp[level - 1] if level >= 1 and level < 5 and next_level_xp.size() == 4 else 0
