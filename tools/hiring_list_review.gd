extends "res://src/world/main.gd"
## Open the Staff panel, scroll to hiring, and show its native sort options.


func _ready() -> void:
	use_saves = false
	new_game_seed_override = 373
	super._ready()
	Clock.set_speed(0)
	for _frame: int in range(3):
		await get_tree().process_frame
	var staff_button: Button = $HUD/Top/Row/Staff
	_click(staff_button.get_global_rect().get_center())
	for _frame: int in range(3):
		await get_tree().process_frame
	var panel: StaffPanel = $Overlay/StaffPanel
	if not panel.visible:
		push_error("The native Staff button did not open the Staff panel")
		return
	var scroll: ScrollContainer = panel.get_node("Panel/Content/Scroll") as ScrollContainer
	var heading: Label = scroll.get_node("List/CandidateTitle") as Label
	scroll.scroll_vertical += roundi(heading.get_global_rect().position.y - scroll.get_global_rect().position.y)
	for _frame: int in range(2):
		await get_tree().process_frame
	var role: OptionButton = panel.get_node("%HiringRole") as OptionButton
	var sorter: OptionButton = panel.get_node("%HiringSort") as OptionButton
	_click(sorter.get_global_rect().get_center())
	await get_tree().process_frame
	var popup: PopupMenu = sorter.get_popup()
	if not popup.visible:
		push_error("The native hiring sort popup did not open")
		return
	var skills: Array[int] = []
	var names: Array[String] = []
	var pool: Array[StaffMember] = staff_roster.candidates()
	for row: Node in panel.get_node("%Candidates").get_children():
		for member: StaffMember in pool:
			if panel.row_for(member.id) == row and (row as Control).visible:
				skills.append(member.skill)
				names.append(member.display_name)
				break
	var sorted: Array[int] = skills.duplicate()
	sorted.sort()
	sorted.reverse()
	if sorter.get_selected_id() != StaffPanel.HiringSort.SKILL \
			or skills.size() != pool.size() or skills != sorted:
		push_error("The visible candidate rows do not match the default skill order")
		return
	var sort_options: Array[String] = []
	for index: int in sorter.item_count:
		sort_options.append(sorter.get_item_text(index))
	print("HIRING_LIST_REVIEW ", JSON.stringify({"seed": 373, "use_saves": use_saves,
		"role": role.get_item_text(role.selected), "sort": sorter.get_item_text(sorter.selected),
		"candidates": names, "skills": skills, "sort_menu_open": popup.visible,
		"sort_options": sort_options, "fixture": "native Staff click and native sort popup"}))


func _click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		get_viewport().push_input(event, true)
