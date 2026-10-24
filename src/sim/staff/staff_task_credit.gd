class_name StaffTaskCredit
extends RefCounted
## Converts the board's one completed-task signal into staged employee XP.
## The session must connect this from task_completed exactly once per live board;
## TaskBoard.complete is the once-only barrier, not this stateless adapter.


static func credit_completed(task: SimTask, world: SimWorld, roster: StaffRoster) -> bool:
	if task == null or world == null or roster == null or task.state != SimTask.State.DONE:
		return false
	var claimant: SimAgent = world.agent(task.claimed_by)
	if not claimant is StaffAgent or claimant is OwnerAgent:
		return false
	var member_id: StringName = (claimant as StaffAgent).member_id
	return not member_id.is_empty() and roster.record_completed_task(member_id, task.kind)
