## 2D思维导图独立主界面，提供完整的节点管理、布局、快捷键和截图功能
extends Control

const DEBUG_LOG := false

var _debug_logger: RefCounted

## 调试日志输出
func _log(p_msg: String) -> void:
	if DEBUG_LOG:
		var line: String = "[Main2D] " + p_msg
		print(line)
		if _debug_logger:
			_debug_logger.write(line)

var data_manager: RefCounted
var mindmap_2d: RefCounted
var history_manager: RefCounted
var edit_dialog: ConfirmationDialog

## 节点就绪时初始化数据管理器、思维导图、历史管理器和UI
func _ready() -> void:
	var DebugLoggerScript := load("res://script/2dmm/DebugLogger.gd")
	if DebugLoggerScript:
		_debug_logger = DebugLoggerScript.new("res://debug_log.txt")
	_log("Main2D 开始初始化")

	custom_minimum_size = Vector2(1152, 648)
	anchor_right = 1.0
	anchor_bottom = 1.0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	set_focus_mode(Control.FOCUS_ALL)
	grab_focus()

	var main_bg: StyleBoxFlat = StyleBoxFlat.new()
	main_bg.bg_color = Color(0, 0, 0)
	add_theme_stylebox_override("panel", main_bg)

	var DataManagerScript := load("res://script/2dmm/DataManager.gd")
	if not DataManagerScript:
		_log("无法加载数据管理器脚本")
		return

	data_manager = DataManagerScript.new("res://data.json")
	_log("数据管理器创建完成，数据项数量: %d" % data_manager.call("get_count"))

	if data_manager.call("get_count") == 0:
		_log("没有数据，创建测试数据")
		_create_test_data()

	var MindMap2DScript := load("res://script/2dmm/MindMap2D.gd")
	if not MindMap2DScript:
		_log("无法加载思维导图脚本")
		return

	mindmap_2d = MindMap2DScript.new(data_manager, self)
	if _debug_logger:
		mindmap_2d._debug_logger = _debug_logger
	_log("思维导图创建完成")

	var HistoryManagerScript := load("res://script/2dmm/HistoryManager.gd")
	if HistoryManagerScript:
		history_manager = HistoryManagerScript.new(data_manager)
		history_manager.history_changed.connect(_on_history_changed)
		mindmap_2d.history_manager = history_manager
		_log("历史管理器创建完成")

	mindmap_2d.create_mind_map()
	_log("思维导图结构创建完成")

	await get_tree().process_frame
	_log("等待一个帧完成")

	mindmap_2d.build_mind_map_relative()
	_log("所有节点构建完成")

	mindmap_2d.node_clicked.connect(_on_node_clicked)
	mindmap_2d.node_double_clicked.connect(_on_node_double_clicked)
	mindmap_2d.node_context_requested.connect(_on_node_context_requested)
	mindmap_2d.request_create_node.connect(_on_request_create_node)
	mindmap_2d.request_edit_node.connect(_on_edit_selected_node)
	mindmap_2d.request_screenshot.connect(_on_screenshot)

	gui_input.connect(_on_gui_input)

	_log("Main2D 初始化完成")


## 全局输入处理，分发键盘快捷键
func _input(event: InputEvent) -> void:
	if not mindmap_2d:
		return

	if event is InputEventMouseButton and Input.is_key_pressed(KEY_CTRL):
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			mindmap_2d.zoom_in(mb.global_position)
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			mindmap_2d.zoom_out(mb.global_position)
			get_viewport().set_input_as_handled()
			return

	if mindmap_2d.is_placing_node:
		if event is InputEventMouseMotion:
			mindmap_2d._snap_placing_node_to_mouse()
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				mindmap_2d._finalize_placing_node()
				get_viewport().set_input_as_handled()
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				mindmap_2d._cancel_placing_node()
				get_viewport().set_input_as_handled()


## 创建测试数据（开发调试用）
func _create_test_data() -> void:
	var root_item: Dictionary = {
		"id": "root",
		"name": "Root",
		"description": "根节点",
		"parent_id": "",
		"relative_offset": [3600.0, 2700.0],
		"pos2d": [3600.0, 2700.0],
		"mastery": 0,
	}
	data_manager.call("add_item", root_item)
	data_manager.call("save_data")


## GUI输入事件处理，处理鼠标滚轮缩放
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index in [4, 5]:
			if mindmap_2d:
				mindmap_2d.handle_scroll(event)
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed:
			if key_event.keycode == KEY_R:
				_log("R: 刷新视图")
				data_manager.call("load_data")
				mindmap_2d.rebuild()
			elif key_event.keycode == KEY_N and key_event.ctrl_pressed:
				_log("Ctrl+N: 创建浮动节点")
				var mouse_pos: Vector2 = mindmap_2d.get_mouse_container_pos()
				mindmap_2d.create_node_at(mouse_pos)
			elif key_event.keycode == KEY_TAB:
				_log("Tab: 创建子节点")
				_on_tab_create_node()
			elif key_event.keycode == KEY_DELETE:
				_log("Delete: 删除选中节点")
				_on_delete_selected()
			elif key_event.keycode == KEY_ESCAPE:
				if mindmap_2d.is_placing_node:
					mindmap_2d._cancel_placing_node()
				else:
					_log("Escape: 取消选择")
					mindmap_2d.focus_on_node(-1)
			elif key_event.keycode == KEY_Z and key_event.ctrl_pressed and not key_event.shift_pressed:
				_log("Ctrl+Z: 撤销")
				_on_undo()
			elif key_event.keycode == KEY_Y and key_event.ctrl_pressed:
				_log("Ctrl+Y: 重做")
				_on_redo()
			elif key_event.keycode == KEY_Z and key_event.ctrl_pressed and key_event.shift_pressed:
				_log("Ctrl+Shift+Z: 重做")
				_on_redo()
			elif key_event.keycode == KEY_F2:
				_log("F2: 编辑选中节点")
				_on_edit_selected_node()


## 节点单击回调
func _on_node_clicked(index: int) -> void:
	_log("节点被点击: %d" % index)


## 节点双击回调，显示详情弹窗
func _on_node_double_clicked(index: int) -> void:
	_log("节点被双击: %d" % index)
	_show_detail_popup(index)


## 节点右键菜单请求回调
func _on_node_context_requested(index: int, position: Vector2) -> void:
	_log("节点上下文请求: %d, 位置: %s" % [index, position])


## 请求创建节点，根据提示类型分发操作
func _on_request_create_node(parent_hint: int, extra: Variant = null) -> void:
	_log("创建节点请求: parent_hint=%d, extra=%s" % [parent_hint, extra])

	if parent_hint == -2:
		_on_delete_selected()
		return

	if parent_hint == -3:
		_on_delete_all_non_root()
		return

	var default_pos: Vector2 = Vector2(300, 0)
	if extra is Vector2:
		default_pos = extra

	_show_create_node_dialog(parent_hint, default_pos)


## 显示新建节点对话框，包含名称、描述、掌握程度和父节点选择
func _show_create_node_dialog(parent_index_hint: int, mouse_pos: Vector2 = Vector2(300, 0)) -> void:
	_log("显示创建节点对话框: parent_hint=%d, pos=(%.0f, %.0f)" % [parent_index_hint, mouse_pos.x, mouse_pos.y])

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "新建知识点"
	dialog.min_size = Vector2(400, 350)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var name_row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = Label.new()
	name_label.text = "名称:"
	name_label.custom_minimum_size = Vector2(80, 0)
	var name_edit: LineEdit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "输入知识点名称"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(name_edit)
	vbox.add_child(name_row)

	var desc_row: HBoxContainer = HBoxContainer.new()
	var desc_label: Label = Label.new()
	desc_label.text = "描述:"
	desc_label.custom_minimum_size = Vector2(80, 0)
	var desc_edit: TextEdit = TextEdit.new()
	desc_edit.name = "DescEdit"
	desc_edit.placeholder_text = "输入描述信息"
	desc_edit.custom_minimum_size = Vector2(0, 80)
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.wrap_mode = 1
	desc_row.add_child(desc_label)
	desc_row.add_child(desc_edit)
	vbox.add_child(desc_row)

	var mastery_row: HBoxContainer = HBoxContainer.new()
	var mastery_label: Label = Label.new()
	mastery_label.text = "掌握程度:"
	mastery_label.custom_minimum_size = Vector2(80, 0)
	var mastery_opt: OptionButton = OptionButton.new()
	mastery_opt.name = "MasteryOpt"
	mastery_opt.add_item("未学习 (0)", 0)
	mastery_opt.add_item("学习中 (1)", 1)
	mastery_opt.add_item("已掌握 (2)", 2)
	mastery_opt.selected = 0
	mastery_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_row.add_child(mastery_label)
	mastery_row.add_child(mastery_opt)
	vbox.add_child(mastery_row)

	var parent_row: HBoxContainer = HBoxContainer.new()
	var parent_label: Label = Label.new()
	parent_label.text = "父节点:"
	parent_label.custom_minimum_size = Vector2(80, 0)
	var parent_opt: OptionButton = OptionButton.new()
	parent_opt.name = "ParentOpt"
	parent_opt.add_item("(无父节点/根节点)", -1)
	var count: int = data_manager.call("get_count")
	for i in count:
		var item: Dictionary = data_manager.call("get_item", i)
		var name_str: String = str(item.get("name", ""))
		parent_opt.add_item(name_str, i)
		if i == parent_index_hint:
			parent_opt.selected = parent_opt.item_count - 1
	parent_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_row.add_child(parent_label)
	parent_row.add_child(parent_opt)
	vbox.add_child(parent_row)

	dialog.add_child(vbox)
	add_child(dialog)

	var ref_name_edit: LineEdit = name_edit
	var ref_desc_edit: TextEdit = desc_edit
	var ref_mastery_opt: OptionButton = mastery_opt
	var ref_parent_opt: OptionButton = parent_opt

	dialog.confirmed.connect(func():
		_log("对话框确认")

		if not is_instance_valid(ref_name_edit):
			return
		if not is_instance_valid(ref_desc_edit):
			return
		if not is_instance_valid(ref_mastery_opt):
			return
		if not is_instance_valid(ref_parent_opt):
			return

		var new_name: String = ref_name_edit.text.strip_edges()
		if new_name.is_empty():
			new_name = "New Node"

		var unique_name: String = data_manager.call("generate_unique_name", new_name)

		var selected_parent_id: int = ref_parent_opt.get_selected_id()
		var parent_item_id: String = ""
		if selected_parent_id >= 0:
			var parent_item: Dictionary = data_manager.call("get_item", selected_parent_id)
			parent_item_id = str(parent_item.get("id", ""))

		var new_item: Dictionary = {
			"id": data_manager.call("generate_unique_id", unique_name),
			"name": unique_name,
			"description": ref_desc_edit.text.strip_edges(),
			"parent_id": parent_item_id,
			"relative_offset": [0.0, 0.0],
			"mastery": ref_mastery_opt.get_selected_id(),
		}

		if parent_item_id.is_empty():
			var container_pos: Vector2 = mindmap_2d.get_mouse_container_pos()
			new_item["relative_offset"] = [container_pos.x, container_pos.y]
			new_item["pos2d"] = [container_pos.x, container_pos.y]

		if history_manager:
			history_manager.record_operation("创建节点: %s" % unique_name)
		var new_index: int = data_manager.call("add_item", new_item)
		data_manager.call("save_data")
		mindmap_2d.rebuild()
		mindmap_2d.focus_on_node(new_index)
	)

	dialog.popup_centered()


## 显示节点详情弹窗
func _show_detail_popup(index: int) -> void:
	if index < 0 or index >= data_manager.call("get_count"):
		return

	var item: Dictionary = data_manager.call("get_item", index)
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "节点详情: %s" % str(item.get("name", ""))
	dialog.min_size = Vector2(450, 400)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var info_labels: Array = [
		"名称: %s" % str(item.get("name", "")),
		"ID: %s" % str(item.get("id", "")),
		"描述: %s" % str(item.get("description", "")),
		"父节点ID: %s" % str(item.get("parent_id", "")),
		"掌握程度: %s" % ["未学习", "学习中", "已掌握"][int(item.get("mastery", 0))],
		"相对偏移: %s" % str(item.get("relative_offset", [])),
		"路径: %s" % data_manager.call("get_node_path", index),
	]

	for label_text in info_labels:
		var lbl: Label = Label.new()
		lbl.text = label_text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(lbl)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()


## 删除选中的节点
func _on_delete_selected() -> void:
	var selected: Array = mindmap_2d.selected_indices.duplicate()
	if selected.is_empty():
		_log("没有选中节点")
		return

	if selected.size() == 1:
		var sel_index: int = selected[0]
		var item: Dictionary = data_manager.call("get_item", sel_index)
		var node_name: String = str(item.get("name", ""))

		var dialog: ConfirmationDialog = ConfirmationDialog.new()
		dialog.title = "确认删除"
		dialog.dialog_text = "确定要删除节点 \"%s\" 吗？" % node_name
		add_child(dialog)

		dialog.confirmed.connect(func():
			if history_manager:
				history_manager.record_operation("删除节点: %s" % node_name)
			data_manager.call("remove_item", sel_index)
			data_manager.call("save_data")
			mindmap_2d.deselect_all()
			mindmap_2d.rebuild()
			_log("节点已删除: %s" % node_name)
		)

		dialog.popup_centered()
	else:
		var dialog: ConfirmationDialog = ConfirmationDialog.new()
		dialog.title = "确认删除"
		dialog.dialog_text = "确定要删除 %d 个节点吗？" % selected.size()
		add_child(dialog)

		dialog.confirmed.connect(func():
			if history_manager:
				history_manager.record_operation("批量删除 %d 个节点" % selected.size())
			selected.sort()
			selected.reverse()
			for idx in selected:
				if idx < data_manager.call("get_count"):
					data_manager.call("remove_item", idx)
			data_manager.call("save_data")
			mindmap_2d.deselect_all()
			mindmap_2d.rebuild()
			_log("已删除 %d 个节点" % selected.size())
		)

		dialog.popup_centered()


## 取消所有节点选中
func _on_deselect() -> void:
	if not mindmap_2d.selected_indices.is_empty():
		mindmap_2d.focus_on_node(-1)
		_log("已取消选择")


## 删除所有非根节点
func _on_delete_all_non_root() -> void:
	_log("一键删除所有非root节点")
	if history_manager:
		history_manager.record_operation("删除所有非root节点")
	var count: int = data_manager.call("get_count")
	var deleted_count: int = 0

	for i in range(count - 1, -1, -1):
		var item: Dictionary = data_manager.call("get_item", i)
		if item is Dictionary:
			var node_id: String = str(item.get("id", ""))
			if node_id != "root":
				data_manager.call("remove_item", i)
				deleted_count += 1

	data_manager.call("save_data")
	mindmap_2d.deselect_all()
	mindmap_2d.rebuild()
	_log("删除完成，共删除 %d 个非root节点" % deleted_count)


## Tab键创建子节点
func _on_tab_create_node() -> void:
	var sel_index: int = mindmap_2d.selected_index
	if sel_index >= 0:
		var node_pos: Vector2 = mindmap_2d.get_node_position(sel_index)

		var child_count: int = 0
		var count: int = data_manager.call("get_count")
		for i in range(count):
			var item: Dictionary = data_manager.call("get_item", i)
			if str(item.get("parent_id", "")) == str(data_manager.call("get_item", sel_index).get("id", "")):
				child_count += 1

		var new_pos: Vector2 = node_pos + Vector2(220, 50 * child_count)
		_create_node_directly(sel_index, new_pos)
	else:
		var mouse_pos: Vector2 = mindmap_2d.get_mouse_container_pos()
		mindmap_2d.create_node_at(mouse_pos)


## 直接创建节点并保存数据
func _create_node_directly(parent_index: int, position: Vector2) -> void:
	var new_id: String = "node_" + str(Time.get_unix_time_from_system()) + "_" + str(randi_range(1000, 9999))

	var parent_id: String = ""
	if parent_index >= 0:
		var parent_node: Dictionary = data_manager.call("get_item", parent_index)
		parent_id = str(parent_node.get("id", ""))

	var node_position = position

	var new_node: Dictionary = {
		"id": new_id,
		"name": "New Node",
		"description": "",
		"relative_offset": [node_position.x, node_position.y],
		"pos2d": [node_position.x, node_position.y],
		"parent_id": parent_id,
		"mastery": 0,
	}

	if history_manager:
		history_manager.record_operation("创建节点: New Node")
	data_manager.call("add_item", new_node)
	data_manager.call("save_data")
	mindmap_2d.rebuild()

	var new_index: int = data_manager.call("find_index_by_id", new_id)
	if new_index >= 0:
		mindmap_2d.focus_on_node(new_index)

	_log("直接创建节点: 父节点=%d, 位置=(%f, %f)" % [parent_index, node_position.x, node_position.y])


## 撤销操作
func _on_undo() -> void:
	if history_manager and history_manager.can_undo():
		history_manager.undo()
		mindmap_2d.rebuild()
		_log("撤销操作: %s" % history_manager.get_undo_description())
	else:
		_log("没有可撤销的操作")


## 重做操作
func _on_redo() -> void:
	if history_manager and history_manager.can_redo():
		history_manager.redo()
		mindmap_2d.rebuild()
		_log("重做操作: %s" % history_manager.get_redo_description())
	else:
		_log("没有可重做的操作")


## 历史状态变更回调
func _on_history_changed(can_undo: bool, can_redo: bool) -> void:
	_log("历史状态更新: 可撤销=%s, 可重做=%s" % [can_undo, can_redo])


## 编辑选中的节点
func _on_edit_selected_node() -> void:
	var sel_index: int = mindmap_2d.selected_index
	if sel_index < 0:
		_log("没有选中节点")
		return
	_show_edit_node_dialog(sel_index)


## 显示编辑节点对话框
func _show_edit_node_dialog(node_index: int) -> void:
	if edit_dialog and is_instance_valid(edit_dialog):
		edit_dialog.queue_free()

	var EditDialogScript := load("res://script/2dmm/EditNodeDialog.gd")
	if not EditDialogScript:
		_log("无法加载编辑对话框脚本")
		return

	edit_dialog = EditDialogScript.new(data_manager)
	edit_dialog.node_edited.connect(_on_node_edited)
	add_child(edit_dialog)
	edit_dialog.edit_node(node_index)


## 节点编辑完成回调，更新数据并重建视图
func _on_node_edited(node_index: int, new_data: Dictionary) -> void:
	if node_index < 0 or node_index >= data_manager.call("get_count"):
		return

	if history_manager:
		history_manager.record_operation("编辑节点: %s" % str(new_data.get("name", "")))
	data_manager.call("set_item", node_index, new_data)
	data_manager.call("save_data")

	mindmap_2d.rebuild()
	mindmap_2d.focus_on_node(node_index)
	_log("节点编辑完成: %d" % node_index)


## 截图回调，保存当前视口为PNG文件
func _on_screenshot() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var timestamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var save_path: String = "user://screenshot_2dmm_%s.png" % timestamp
	image.save_png(save_path)
	_log("截图已保存: %s" % save_path)
