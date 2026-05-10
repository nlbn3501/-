## 科目编辑器主界面，整合3D导图、2D导图和2D认知三个视图，管理知识点数据的增删改查
extends Control

var subject_name: String = ""
var data_file_path: String = ""

var _data_manager: RefCounted
var _knowledge_map: Node3D
var _mindmap_2d: RefCounted
var _cog_data: RefCounted
var _cog_map: RefCounted
var _cog_problem_panel: Node
var _problem_canvas: Control

var _lbl_subject: Label
var _tab_3d: Button
var _tab_2d: Button
var _tab_cog: Button
var _btn_back: Button
var _vp_container: SubViewportContainer
var _sub_vp: SubViewport
var _page_2d: Control
var _page_cog: Control
var _current_tab: int = 0

const BAR_HEIGHT := 36


## 节点就绪时初始化数据路径、构建UI和三个视图内容、连接信号
func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	focus_mode = Control.FOCUS_ALL
	_resolve_data_path()
	_build_ui()
	_init_data_manager()
	_build_3d_content()
	_build_2d_content()
	_build_cog_content()
	_connect_signals()
	_update_subject_label()
	_update_tab_visibility()
	call_deferred("_fit_to_window")


## 根据工作区目录和科目名解析数据文件的完整路径
func _resolve_data_path() -> void:
	var ws_dir: String = Global.get_workspace_dir()
	if ws_dir.is_empty() or subject_name.is_empty():
		data_file_path = ""
	else:
		data_file_path = ws_dir.path_join(subject_name + ".json")
	if not FileAccess.file_exists(data_file_path):
		push_warning("SubjectEditor: data file not found, will create empty: %s" % data_file_path)


## 构建顶部工具栏、3D视口容器、2D页面和认知页面的UI结构
func _build_ui() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.position = Vector2(0, 0)
	top_bar.focus_mode = Control.FOCUS_NONE
	add_child(top_bar)

	_lbl_subject = Label.new()
	_lbl_subject.name = "LblSubject"
	_lbl_subject.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_subject.clip_text = true
	_lbl_subject.text = "current subject"
	top_bar.add_child(_lbl_subject)

	_tab_3d = Button.new()
	_tab_3d.name = "Tab3D"
	_tab_3d.text = "3D导图"
	_tab_3d.toggle_mode = true
	_tab_3d.focus_mode = Control.FOCUS_NONE
	top_bar.add_child(_tab_3d)

	_tab_2d = Button.new()
	_tab_2d.name = "Tab2D"
	_tab_2d.text = "2D导图"
	_tab_2d.toggle_mode = true
	_tab_2d.focus_mode = Control.FOCUS_NONE
	top_bar.add_child(_tab_2d)

	_tab_cog = Button.new()
	_tab_cog.name = "TabCog"
	_tab_cog.text = "2D认知"
	_tab_cog.toggle_mode = true
	_tab_cog.focus_mode = Control.FOCUS_NONE
	top_bar.add_child(_tab_cog)

	_btn_back = Button.new()
	_btn_back.name = "BtnBack"
	_btn_back.text = "Back"
	_btn_back.focus_mode = Control.FOCUS_NONE
	top_bar.add_child(_btn_back)

	_vp_container = SubViewportContainer.new()
	_vp_container.name = "VpContainer"
	_vp_container.position = Vector2(0, BAR_HEIGHT)
	add_child(_vp_container)

	_sub_vp = SubViewport.new()
	_sub_vp.name = "SubViewport"
	_sub_vp.transparent_bg = false
	_sub_vp.disable_3d = false
	_vp_container.add_child(_sub_vp)

	_page_2d = Control.new()
	_page_2d.name = "Page2D"
	_page_2d.anchor_left = 0.0
	_page_2d.anchor_top = 0.0
	_page_2d.anchor_right = 1.0
	_page_2d.anchor_bottom = 1.0
	_page_2d.offset_left = 0
	_page_2d.offset_top = BAR_HEIGHT
	_page_2d.offset_right = 0
	_page_2d.offset_bottom = 0
	_page_2d.visible = false
	add_child(_page_2d)

	_page_cog = Control.new()
	_page_cog.name = "PageCog"
	_page_cog.anchor_left = 0.0
	_page_cog.anchor_top = 0.0
	_page_cog.anchor_right = 1.0
	_page_cog.anchor_bottom = 1.0
	_page_cog.offset_left = 0
	_page_cog.offset_top = BAR_HEIGHT
	_page_cog.offset_right = 0
	_page_cog.offset_bottom = 0
	_page_cog.visible = false
	add_child(_page_cog)


## 初始化2D导图的数据管理器
func _init_data_manager() -> void:
	_data_manager = load("res://script/2dmm/DataManager.gd").new(data_file_path)


## 构建3D知识导图视图，使用DataManager3DAdapter适配数据
func _build_3d_content() -> void:
	var KnowledgeMapScript := load("res://script/3dmm/KnowledgeMap.gd") as GDScript
	var dm_3d_adapter: RefCounted = load("res://script/shared/DataManager3DAdapter.gd").new(_data_manager)
	_knowledge_map = KnowledgeMapScript.new(dm_3d_adapter) as Node3D
	_knowledge_map.name = "KnowledgeMap"
	_sub_vp.add_child(_knowledge_map)


## 构建2D思维导图视图，包含工具栏和缩放/刷新按钮
func _build_2d_content() -> void:
	var MindMap2DScript := load("res://script/2dmm/MindMap2D.gd") as GDScript
	_mindmap_2d = MindMap2DScript.new(_data_manager, _page_2d)

	_mindmap_2d.create_mind_map()

	var HistoryManagerScript := load("res://script/2dmm/HistoryManager.gd") as GDScript
	var history_2d: RefCounted = HistoryManagerScript.new(_data_manager)
	_mindmap_2d.history_manager = history_2d

	_mindmap_2d.node_double_clicked.connect(func(index: int):
		_show_detail_popup_2d(index)
	)
	_mindmap_2d.request_create_node.connect(_on_request_create_node)
	_mindmap_2d.request_edit_node.connect(_on_request_edit_node)
	_mindmap_2d.request_rename_node.connect(_on_request_rename_node)
	_mindmap_2d.request_hover_show.connect(_on_request_hover_show)
	_mindmap_2d.request_screenshot.connect(_on_screenshot)
	_mindmap_2d.data_changed.connect(_on_2d_data_changed)

	_mindmap_2d.build_mind_map_relative()

	var toolbar := HBoxContainer.new()
	toolbar.name = "Toolbar2D"
	toolbar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toolbar.offset_bottom = 40.0
	toolbar.focus_mode = Control.FOCUS_NONE
	_page_2d.add_child(toolbar)

	var title_lbl := Label.new()
	title_lbl.text = "思维导图 - 2D视图"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title_lbl)

	var zoom_in_btn := Button.new()
	zoom_in_btn.text = "放大 (+)"
	zoom_in_btn.focus_mode = Control.FOCUS_NONE
	zoom_in_btn.pressed.connect(func():
		_mindmap_2d.zoom_in(_page_2d.get_global_mouse_position())
	)
	toolbar.add_child(zoom_in_btn)

	var zoom_out_btn := Button.new()
	zoom_out_btn.text = "缩小 (-)"
	zoom_out_btn.focus_mode = Control.FOCUS_NONE
	zoom_out_btn.pressed.connect(func():
		_mindmap_2d.zoom_out(_page_2d.get_global_mouse_position())
	)
	toolbar.add_child(zoom_out_btn)

	var reset_btn := Button.new()
	reset_btn.text = "重置视图"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(func(): _mindmap_2d.reset_view())
	toolbar.add_child(reset_btn)

	var refresh_btn := Button.new()
	refresh_btn.text = "刷新 (R)"
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(func(): _refresh_data())
	toolbar.add_child(refresh_btn)


## 构建2D认知导图视图，清理旧认知数据并从2D导图同步
func _build_cog_content() -> void:
	var ws_dir: String = data_file_path.get_base_dir()
	var cog_file: String = ws_dir.path_join(subject_name + "_cog.json")

	var CogDataManagerScript := load("res://script/2dtr/CognitiveMapDataManager.gd") as GDScript
	_cog_data = CogDataManagerScript.new(cog_file)

	var CognitiveMap2DScript := load("res://script/2dtr/CognitiveMap2D.gd") as GDScript
	_cog_map = CognitiveMap2DScript.new(_cog_data, _page_cog)

	_cog_map.create_mind_map()

	var HistoryManagerScript := load("res://script/2dtr/HistoryManager.gd") as GDScript
	var history_cog: RefCounted = HistoryManagerScript.new(_cog_data)
	_cog_map.history_manager = history_cog

	_cog_map.node_double_clicked.connect(func(index: int):
		_show_detail_popup_cog(index)
	)
	_cog_map.request_edit_node.connect(_on_request_edit_node)
	_cog_map.request_create_problem.connect(_on_cog_request_create_problem)
	_cog_map.request_add_related_knowledge.connect(_on_cog_add_related_knowledge)
	_cog_map.request_add_relation.connect(_on_cog_add_relation)

	_cog_map.build_mind_map_relative()

	_sync_cog_data_from_2dmm()


## 将2D导图的数据同步到认知导图，保留认知视图的位置和来源信息
func _sync_cog_data_from_2dmm() -> void:
	if not _cog_data or not _data_manager:
		return

	var existing_by_id: Dictionary = {}
	for i in _cog_data.get_count():
		var item: Dictionary = _cog_data.get_item(i)
		var nid: String = str(item.get("id", ""))
		if not nid.is_empty():
			existing_by_id[nid] = i

	var used_ids: Dictionary = {}

	for i in _data_manager.get_count():
		var src: Dictionary = _data_manager.get_item(i)
		var nid: String = str(src.get("id", ""))
		used_ids[nid] = true

		if existing_by_id.has(nid):
			var idx: int = existing_by_id[nid]
			var dst: Dictionary = _cog_data.get_item(idx)
			var saved_pos2d = dst.get("pos2d")
			var saved_rel = dst.get("relative_offset")
			var saved_source = dst.get("source", "2dmm")
			var saved_visible = dst.get("visible_in_2dtr", false)
			dst = src.duplicate(true)
			dst["source"] = saved_source
			dst["visible_in_2dtr"] = saved_visible
			if saved_pos2d != null:
				dst["pos2d"] = saved_pos2d
			if saved_rel != null:
				dst["relative_offset"] = saved_rel
			_cog_data.set_item(idx, dst)
		else:
			var new_item: Dictionary = src.duplicate(true)
			new_item["source"] = "2dmm"
			if not new_item.has("pos2d") or new_item["pos2d"] == null:
				new_item["pos2d"] = [3600.0 + randf_range(-200, 200), 2700.0 + randf_range(-200, 200)]
			if not new_item.has("relative_offset") or new_item["relative_offset"] == null:
				new_item["relative_offset"] = new_item["pos2d"]
			_cog_data.items.append(new_item)

	var to_remove: Array = []
	for i in range(_cog_data.get_count() - 1, -1, -1):
		var item: Dictionary = _cog_data.get_item(i)
		var nid: String = str(item.get("id", ""))
		var source: String = str(item.get("source", "2dmm"))
		if source == "2dmm" and not used_ids.has(nid):
			to_remove.append(i)
	for idx in to_remove:
		_cog_data.remove_item(idx)

	if not to_remove.is_empty() or _data_manager.get_count() > 0:
		_cog_data.save_data()


## 认知视图请求编辑节点的回调，转发到通用编辑逻辑
func _on_cog_request_edit(index: int) -> void:
	_on_request_edit_node(index)


## 确保指定目录存在，不存在则递归创建
func _ensure_dir_exists(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)


## 全局输入处理，根据当前标签页分发键盘和鼠标滚轮快捷键
func _input(event: InputEvent) -> void:
	if _current_tab == 1 and _mindmap_2d:
		if event is InputEventMouseButton and Input.is_key_pressed(KEY_CTRL):
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_mindmap_2d.zoom_in(mb.global_position)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_mindmap_2d.zoom_out(mb.global_position)
				get_viewport().set_input_as_handled()
				return

		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_TAB:
				var focus_owner: Control = get_viewport().gui_get_focus_owner()
				if focus_owner and (focus_owner is LineEdit or focus_owner is TextEdit):
					return
				get_viewport().set_input_as_handled()
				_on_tab_create_node_2d()
				return
			elif event.keycode == KEY_N and event.ctrl_pressed:
				var mouse_pos: Vector2 = _mindmap_2d.get_mouse_container_pos()
				_mindmap_2d.create_node_at(mouse_pos)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_DELETE:
				_delete_selected_2d()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_F2:
				_on_request_edit_node(_mindmap_2d.selected_index)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_R and not event.ctrl_pressed:
				_refresh_data()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ESCAPE:
				if _mindmap_2d.is_placing_node:
					_mindmap_2d._cancel_placing_node()
				else:
					_mindmap_2d.focus_on_node(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_Z and event.ctrl_pressed and not event.shift_pressed:
				_on_undo_2d()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_Y and event.ctrl_pressed:
				_on_redo_2d()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed:
				_on_redo_2d()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_S and event.ctrl_pressed:
				_data_manager.save_data()
				get_viewport().set_input_as_handled()
				return

	elif _current_tab == 2 and _cog_map:
		# ProblemCanvas 打开时，快捷键分发给画布
		if _problem_canvas and is_instance_valid(_problem_canvas):
			if event is InputEventMouseButton and Input.is_key_pressed(KEY_CTRL):
				var mb: InputEventMouseButton = event as InputEventMouseButton
				if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
					_problem_canvas.zoom_in(mb.global_position)
					get_viewport().set_input_as_handled()
					return
				elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
					_problem_canvas.zoom_out(mb.global_position)
					get_viewport().set_input_as_handled()
					return
			if event is InputEventKey and event.pressed:
				_problem_canvas.handle_key_input(event)
				return
		# 没有ProblemCanvas时，快捷键分发给认知地图
		if event is InputEventMouseButton and Input.is_key_pressed(KEY_CTRL):
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_cog_map.zoom_in(mb.global_position)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_cog_map.zoom_out(mb.global_position)
				get_viewport().set_input_as_handled()
				return

		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_N and event.ctrl_pressed:
				var mouse_pos: Vector2 = _cog_map.get_mouse_container_pos()
				_on_cog_request_create_problem(mouse_pos)
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_DELETE:
				_on_cog_delete_selected()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_ESCAPE:
				if _cog_map._is_connecting:
					_cog_map._cancel_relation_line()
				else:
					_cog_map.deselect_all()
				get_viewport().set_input_as_handled()
				return
			elif event.keycode == KEY_S and event.ctrl_pressed:
				if _cog_data:
					_cog_data.save_data()
				get_viewport().set_input_as_handled()
				return


## 每帧处理回调（当前无逻辑）
func _process(_delta: float) -> void:
	pass


## 按Tab键在2D视图中创建新节点，有选中节点时在其下方创建子节点
func _on_tab_create_node_2d() -> void:
	if not _mindmap_2d:
		return
	var sel_index: int = _mindmap_2d.selected_index
	if sel_index >= 0:
		var node_pos: Vector2 = _mindmap_2d.get_node_position(sel_index)
		var child_count: int = 0
		var count: int = _data_manager.get_count()
		for i in range(count):
			var item: Dictionary = _data_manager.get_item(i)
			if str(item.get("parent_id", "")) == str(_data_manager.get_item(sel_index).get("id", "")):
				child_count += 1
		var x_off: float = _mindmap_2d.compute_child_x_offset(sel_index, "New Node", 1)
		var new_pos: Vector2 = node_pos + Vector2(x_off, 50 * child_count)
		_create_node_directly_2d(sel_index, new_pos)
	else:
		var mouse_pos: Vector2 = _mindmap_2d.get_mouse_container_pos()
		_mindmap_2d.create_node_at(mouse_pos)
	grab_focus()


## 在2D视图中直接创建节点并保存数据，同步更新3D视图
func _create_node_directly_2d(parent_index: int, position: Vector2) -> void:
	var new_id: String = "node_" + str(Time.get_unix_time_from_system()) + "_" + str(randi_range(1000, 9999))
	var parent_id: String = ""
	var galaxy_id: int = 0
	if parent_index >= 0:
		var parent_node: Dictionary = _data_manager.get_item(parent_index)
		parent_id = str(parent_node.get("id", ""))
		galaxy_id = int(parent_node.get("galaxy_id", 0))
	else:
		var dm3d: RefCounted = load("res://script/shared/DataManager3DAdapter.gd").new(_data_manager)
		galaxy_id = dm3d.next_available_galaxy_id()
	var new_node: Dictionary = {
		"id": new_id,
		"name": "New Node",
		"description": "",
		"relative_offset": [position.x, position.y],
		"pos2d": [position.x, position.y],
		"parent_id": parent_id,
		"galaxy_id": galaxy_id,
		"mastery": 0,
		"relations": [],
	}
	var history_2d: RefCounted = _mindmap_2d.history_manager
	if history_2d:
		history_2d.record_operation("创建节点: New Node")
	_data_manager.add_item(new_node)
	_data_manager.save_data()
	_mindmap_2d.rebuild()
	var new_index: int = _data_manager.find_index_by_id(new_id)
	if new_index >= 0:
		_mindmap_2d.focus_on_node(new_index)
	if _knowledge_map:
		_knowledge_map.rebuild_all()


## 2D视图撤销操作
func _on_undo_2d() -> void:
	if not _mindmap_2d:
		return
	var history_2d: RefCounted = _mindmap_2d.history_manager
	if history_2d and history_2d.can_undo():
		history_2d.undo()
		_mindmap_2d.rebuild()


## 2D视图重做操作
func _on_redo_2d() -> void:
	if not _mindmap_2d:
		return
	var history_2d: RefCounted = _mindmap_2d.history_manager
	if history_2d and history_2d.can_redo():
		history_2d.redo()
		_mindmap_2d.rebuild()


## 2D数据变更回调，同步重建3D视图
func _on_2d_data_changed() -> void:
	if _knowledge_map:
		_knowledge_map.rebuild_all()


## 显示2D视图的节点重命名对话框
func _show_rename_dialog_2d(node_index: int) -> void:
	if node_index < 0 or node_index >= _data_manager.get_count():
		return
	var item: Dictionary = _data_manager.get_item(node_index)
	var old_name: String = str(item.get("name", ""))
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "重命名节点"
	dialog.min_size = Vector2(350, 120)
	var vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "输入新名称:"
	vbox.add_child(label)
	var name_edit := LineEdit.new()
	name_edit.text = old_name
	name_edit.select_all_on_focus = true
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_edit)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var new_name: String = name_edit.text.strip_edges()
		if new_name.is_empty():
			new_name = "New Node"
		if new_name != old_name:
			var unique_name: String = _data_manager.generate_unique_name(new_name)
			item["name"] = unique_name
			var history_2d: RefCounted = _mindmap_2d.history_manager
			if history_2d:
				history_2d.record_operation("重命名: %s → %s" % [old_name, unique_name])
			_data_manager.set_item(node_index, item)
			_data_manager.save_data()
			_mindmap_2d.rebuild()
			_mindmap_2d.focus_on_node(node_index)
			if _cog_data:
				_cog_data.call("rename_knowledge_target", old_name, unique_name)
	)
	name_edit.text_submitted.connect(func(_text: String):
		dialog.confirmed.emit()
	)
	dialog.popup_centered()
	name_edit.grab_focus()


## 构造一个模拟的鼠标滚轮事件
func _make_wheel_event(button: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


## 连接标签页切换按钮和返回按钮的信号
func _connect_signals() -> void:
	_tab_3d.pressed.connect(func(): _switch_tab(0))
	_tab_2d.pressed.connect(func(): _switch_tab(1))
	_tab_cog.pressed.connect(func(): _switch_tab(2))
	_btn_back.pressed.connect(_on_back_pressed)
	if _knowledge_map:
		_knowledge_map.point_clicked.connect(_on_point_clicked)
		_knowledge_map.point_double_clicked.connect(_on_point_double_clicked)


## 切换到指定标签页（0=3D, 1=2D, 2=认知）
func _switch_tab(tab_index: int) -> void:
	_current_tab = tab_index
	_update_tab_visibility()


## 根据当前标签页更新各视图的可见性和按钮状态
func _update_tab_visibility() -> void:
	_tab_3d.button_pressed = (_current_tab == 0)
	_tab_2d.button_pressed = (_current_tab == 1)
	_tab_cog.button_pressed = (_current_tab == 2)

	_vp_container.visible = (_current_tab == 0)
	_page_2d.visible = (_current_tab == 1)
	_page_cog.visible = (_current_tab == 2)

	if _current_tab == 1 and _mindmap_2d:
		_mindmap_2d.rebuild()

	if _current_tab == 2 and _cog_map:
		_sync_cog_data_from_2dmm()
		_cog_map.rebuild(true)


## 更新顶部科目名称标签
func _update_subject_label() -> void:
	if not subject_name.is_empty():
		_lbl_subject.text = subject_name
	else:
		_lbl_subject.text = "unknown subject"


## 将编辑器各区域尺寸适配到窗口大小
func _fit_to_window() -> void:
	var vp_size := get_viewport_rect().size
	size = vp_size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view_size := Vector2(vp_size.x, vp_size.y - BAR_HEIGHT)
	if _vp_container:
		_vp_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_vp_container.set_offset(SIDE_TOP, BAR_HEIGHT)
	if _sub_vp:
		_sub_vp.size = view_size
	if _page_2d:
		_page_2d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_page_2d.set_offset(SIDE_TOP, BAR_HEIGHT)
	if _page_cog:
		_page_cog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_page_cog.set_offset(SIDE_TOP, BAR_HEIGHT)
	var top_bar: HBoxContainer = get_node_or_null("TopBar") as HBoxContainer
	if top_bar:
		top_bar.size = Vector2(vp_size.x, BAR_HEIGHT)


## 点击返回按钮，销毁编辑器返回选择器
func _on_back_pressed() -> void:
	queue_free()


## 3D视图中单击知识点的回调（当前无操作）
func _on_point_clicked(index: int) -> void:
	pass


## 3D视图中双击知识点，弹出详情窗口
func _on_point_double_clicked(index: int) -> void:
	_show_detail_popup_3d(index)


## 在3D视图中显示指定知识点的详情弹窗
func _show_detail_popup_3d(index: int) -> void:
	var item: Dictionary = _data_manager.get_item(index)
	if item.is_empty():
		return
	load("res://script/3dmm/DetailPopup.gd").show(item, _data_manager, _knowledge_map)


## 在2D视图中显示指定知识点的详情弹窗
func _show_detail_popup_2d(index: int) -> void:
	var item: Dictionary = _data_manager.get_item(index)
	if item.is_empty():
		return
	load("res://script/3dmm/DetailPopup.gd").show(item, _data_manager, _knowledge_map, false)


## 从文件重新加载数据并重建所有视图
func _refresh_data() -> void:
	_data_manager.load_data()
	if _knowledge_map:
		_knowledge_map.rebuild_all()
	if _mindmap_2d:
		_mindmap_2d.rebuild()


## 请求创建节点的统一入口，根据当前标签页分发到对应视图
func _on_request_create_node(parent_hint: int, extra: Variant = null) -> void:
	if _current_tab == 1 and _mindmap_2d:
		if parent_hint == -2:
			_delete_selected_2d()
		elif parent_hint == -3:
			_delete_all_non_root_2d()
		else:
			_show_create_node_dialog_2d(parent_hint, extra)
	elif _knowledge_map:
		if parent_hint == -2:
			if _knowledge_map.selected_index >= 0:
				_knowledge_map._delete_node(_knowledge_map.selected_index)
				if _mindmap_2d:
					_mindmap_2d.rebuild()
		elif parent_hint == -3:
			_knowledge_map._delete_all_non_root()
			if _mindmap_2d:
				_mindmap_2d.rebuild()
		else:
			_knowledge_map._show_node_dialog("create", parent_hint)


## 请求编辑节点的统一入口，根据当前标签页分发到对应视图
func _on_request_edit_node(index: int) -> void:
	if index >= 100000:
		var prob_index: int = index - 100000
		_on_cog_request_edit_problem(prob_index)
		return
	if _current_tab == 1 and _mindmap_2d:
		_show_edit_node_dialog_2d(index)
	elif _current_tab == 2 and _cog_map:
		_show_edit_node_dialog_cog(index)
	elif _knowledge_map:
		_knowledge_map._show_node_dialog("edit", index)


## 请求重命名节点，弹出重命名对话框
func _on_request_rename_node(index: int) -> void:
	if not _mindmap_2d:
		return
	if index < 0 or index >= _data_manager.get_count():
		return
	var item: Dictionary = _data_manager.get_item(index)
	var current_name: String = str(item.get("name", ""))

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "重命名节点"
	dialog.min_size = Vector2(350, 150)
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	var label: Label = Label.new()
	label.text = "名称:"
	var line_edit: LineEdit = LineEdit.new()
	line_edit.text = current_name
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit.select_all()
	hbox.add_child(label)
	hbox.add_child(line_edit)
	dialog.add_child(hbox)
	add_child(dialog)

	dialog.confirmed.connect(func():
		if not is_instance_valid(line_edit):
			return
		var new_name: String = line_edit.text.strip_edges()
		if new_name.is_empty():
			new_name = current_name
		if new_name != current_name:
			var history_2d: RefCounted = _mindmap_2d.history_manager
			if history_2d:
				history_2d.record_operation("重命名节点: %s → %s" % [current_name, new_name])
			item["name"] = new_name
			_data_manager.set_item(index, item)
			_data_manager.save_data()
			_mindmap_2d.rebuild()
			if _cog_data and current_name != new_name:
				_cog_data.call("rename_knowledge_target", current_name, new_name)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	line_edit.text_submitted.connect(func(_t: String) -> void:
		dialog.confirmed.emit()
	)
	dialog.popup_centered()
	line_edit.grab_focus()


## 悬停显示节点详情浮窗，包含名称、描述、掌握度和关系数
func _on_request_hover_show(index: int) -> void:
	if not _mindmap_2d:
		return
	if index < 0 or index >= _data_manager.get_count():
		return

	_mindmap_2d.close_hover_popup()

	var item: Dictionary = _data_manager.get_item(index)
	var name_str: String = str(item.get("name", "节点"))
	var desc: String = str(item.get("description", ""))
	var mastery: float = float(item.get("mastery", 0.0))
	var mastery_pct: int = int(mastery * 100)
	var relations: Array = item.get("relations", [])

	var panel: PanelContainer = PanelContainer.new()
	var zoom: float = _mindmap_2d.zoom_scale if _mindmap_2d else 1.0
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	style.border_color = Color(0.25, 0.35, 0.55, 0.8)
	style.set_border_width_all(int(1 * zoom))
	style.corner_radius_top_left = int(6 * zoom)
	style.corner_radius_top_right = int(6 * zoom)
	style.corner_radius_bottom_left = int(6 * zoom)
	style.corner_radius_bottom_right = int(6 * zoom)
	style.content_margin_left = 14.0 * zoom
	style.content_margin_right = 14.0 * zoom
	style.content_margin_top = 10.0 * zoom
	style.content_margin_bottom = 10.0 * zoom
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(6 * zoom))

	var title: Label = Label.new()
	title.text = name_str
	title.add_theme_font_size_override("font_size", int(15 * zoom))
	title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.95))
	vbox.add_child(title)

	var bar: HSeparator = HSeparator.new()
	bar.add_theme_constant_override("separation", 4)
	vbox.add_child(bar)

	if not desc.is_empty():
		var desc_label: Label = Label.new()
		desc_label.text = desc
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
		desc_label.custom_minimum_size.x = 260.0 * zoom
		vbox.add_child(desc_label)

	var mastery_label: Label = Label.new()
	mastery_label.text = "掌握度: %d%%" % mastery_pct
	mastery_label.add_theme_font_size_override("font_size", int(13 * zoom))
	mastery_label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.5))
	vbox.add_child(mastery_label)

	if not relations.is_empty():
		var rel_label: Label = Label.new()
		rel_label.text = "关系: %d 条" % relations.size()
		rel_label.add_theme_font_size_override("font_size", int(13 * zoom))
		rel_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.75))
		vbox.add_child(rel_label)

	panel.add_child(vbox)

	var ctrl: Control = _mindmap_2d.node_controls.get(index)
	if ctrl:
		var base_y: float = ctrl.position.y - 10.0 * zoom
		panel.position = Vector2(ctrl.position.x + ctrl.custom_minimum_size.x + 12.0 * zoom, base_y)
	else:
		panel.position = Vector2(400, 300)

	_mindmap_2d.container.add_child(panel)
	_mindmap_2d._hover_popup = panel


## 删除2D视图中选中的节点，同步更新3D和认知数据
func _delete_selected_2d() -> void:
	if not _mindmap_2d:
		return
	var selected: Array = _mindmap_2d.selected_indices.duplicate()
	if selected.is_empty():
		return
	var history_2d: RefCounted = _mindmap_2d.history_manager
	if history_2d:
		history_2d.record_operation("删除节点")
	var deleted_names: Array = []
	selected.sort()
	selected.reverse()
	for idx in selected:
		if idx < _data_manager.get_count():
			var item: Dictionary = _data_manager.get_item(idx)
			var name: String = str(item.get("name", ""))
			if not name.is_empty():
				deleted_names.append(name)
			_data_manager.remove_item(idx)
	_data_manager.save_data()
	_mindmap_2d.deselect_all()
	_mindmap_2d.rebuild()
	if _knowledge_map:
		_knowledge_map.rebuild_all()
	if _cog_data:
		for name in deleted_names:
			_cog_data.call("cleanup_relations_for_knowledge", name)
			_cog_data.call("cleanup_relations_for_target", name)
		_sync_cog_data_from_2dmm()
		if _cog_map:
			_cog_map.rebuild()


## 删除2D视图中所有非root节点并重置root位置
func _delete_all_non_root_2d() -> void:
	if not _mindmap_2d:
		return
	var history_2d: RefCounted = _mindmap_2d.history_manager
	if history_2d:
		history_2d.record_operation("删除所有非root节点")
	var deleted_names: Array = []
	var count: int = _data_manager.get_count()
	for i in range(count - 1, -1, -1):
		var item: Dictionary = _data_manager.get_item(i)
		if str(item.get("id", "")) != "root":
			var name: String = str(item.get("name", ""))
			if not name.is_empty():
				deleted_names.append(name)
			_data_manager.remove_item(i)
	var root_idx: int = _data_manager.find_index_by_id("root")
	if root_idx >= 0:
		var root_item: Dictionary = _data_manager.get_item(root_idx)
		root_item["pos2d"] = [3600.0, 2700.0]
		root_item["relative_offset"] = [3600.0, 2700.0]
		_data_manager.set_item(root_idx, root_item)
	_data_manager.save_data()
	_mindmap_2d.deselect_all()
	_mindmap_2d.rebuild()
	if _knowledge_map:
		_knowledge_map.rebuild_all()
	if _cog_data:
		for name in deleted_names:
			_cog_data.call("cleanup_relations_for_knowledge", name)
			_cog_data.call("cleanup_relations_for_target", name)
		_sync_cog_data_from_2dmm()
		if _cog_map:
			_cog_map.rebuild()


## 在2D视图中显示新建知识点对话框，包含名称、描述、掌握度和父节点选择
func _show_create_node_dialog_2d(parent_hint: int, extra: Variant = null) -> void:
	var default_pos: Vector2 = Vector2(3600, 2700)
	if extra is Vector2:
		default_pos = extra
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
	var item_count: int = _data_manager.get_count()
	for i in item_count:
		var item: Dictionary = _data_manager.get_item(i)
		var item_name: String = str(item.get("name", ""))
		parent_opt.add_item(item_name, i)
		if i == parent_hint:
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
		if not is_instance_valid(ref_name_edit):
			return
		var new_name: String = ref_name_edit.text.strip_edges()
		if new_name.is_empty():
			new_name = "New Node"
		var unique_name: String = _data_manager.generate_unique_name(new_name)
		var selected_parent_id: int = ref_parent_opt.get_selected_id()
		var parent_item_id: String = ""
		if selected_parent_id >= 0:
			var parent_item: Dictionary = _data_manager.get_item(selected_parent_id)
			parent_item_id = str(parent_item.get("id", ""))
		var new_item: Dictionary = {
			"id": _data_manager.generate_unique_id(unique_name),
			"name": unique_name,
			"description": ref_desc_edit.text.strip_edges(),
			"parent_id": parent_item_id,
			"relative_offset": [0.0, 0.0],
			"mastery": ref_mastery_opt.get_selected_id(),
		}
		if parent_item_id.is_empty():
			var container_pos: Vector2 = _mindmap_2d.get_mouse_container_pos()
			new_item["relative_offset"] = [container_pos.x, container_pos.y]
			new_item["pos2d"] = [container_pos.x, container_pos.y]
		var history_2d: RefCounted = _mindmap_2d.history_manager
		if history_2d:
			history_2d.record_operation("创建节点: %s" % unique_name)
		var new_index: int = _data_manager.add_item(new_item)
		_data_manager.save_data()
		_mindmap_2d.rebuild()
		_mindmap_2d.focus_on_node(new_index)
	)
	name_edit.text_submitted.connect(func(_t: String) -> void:
		dialog.confirmed.emit()
	)
	dialog.popup_centered()
	name_edit.grab_focus()


## 在2D视图中显示编辑节点对话框，使用EditNodeDialog组件
func _show_edit_node_dialog_2d(node_index: int) -> void:
	if node_index < 0 or node_index >= _data_manager.get_count():
		return
	var EditDialogScript := load("res://script/2dmm/EditNodeDialog.gd")
	if not EditDialogScript:
		return
	var edit_dialog: ConfirmationDialog = EditDialogScript.new(_data_manager)
	edit_dialog.node_edited.connect(func(edited_index: int, new_data: Dictionary):
		if edited_index < 0 or edited_index >= _data_manager.get_count():
			return
		var old_item: Dictionary = _data_manager.get_item(edited_index)
		var old_name: String = str(old_item.get("name", ""))
		var new_name: String = str(new_data.get("name", ""))
		var history_2d: RefCounted = _mindmap_2d.history_manager
		if history_2d:
			history_2d.record_operation("编辑节点: %s" % new_name)
		_data_manager.set_item(edited_index, new_data)
		_data_manager.save_data()
		_mindmap_2d.rebuild()
		_mindmap_2d.focus_on_node(edited_index)
		if _cog_data and old_name != new_name and not old_name.is_empty():
			_cog_data.call("rename_knowledge_target", old_name, new_name)
	)
	add_child(edit_dialog)
	edit_dialog.edit_node(node_index)


## 截图回调，根据当前标签页截取2D视图或3D视图的截图
func _on_screenshot() -> void:
	var ss_dir: String = Global.get_screenshot_dir()
	if ss_dir.is_empty():
		ss_dir = "user://"
	if _current_tab == 1:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var timestamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
		var filename: String = "%s_screenshot_2dmm_%s.png" % [subject_name, timestamp]
		var save_path: String = ss_dir.path_join(filename)
		image.save_png(save_path)
	elif _knowledge_map:
		_knowledge_map._take_screenshot()


## 认知视图节点双击回调，显示详情弹窗
func _on_cog_node_double_clicked(key: String, _node_type: String) -> void:
	_show_detail_popup_cog(int(key))


## 认知视图请求创建题目回调
func _on_cog_request_create_problem(position: Vector2) -> void:
	_show_create_problem_dialog(position)

## 直接创建题目
func _create_problem_directly(position: Vector2) -> void:
	if not _cog_data:
		return
	var new_problem: Dictionary = {
		"title": "新题目",
		"type": "其他",
		"difficulty": 1,
		"source": "",
		"images": [],
		"note": "",
		"pos2d": [position.x, position.y],
	}
	_cog_data.add_problem(new_problem)
	if _cog_map:
		_cog_map.rebuild()

## 显示创建题目对话框
func _show_create_problem_dialog(position: Vector2) -> void:
	if not _cog_data:
		return
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "新建题目"
	dialog.min_size = Vector2(400, 350)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var TYPE_STRINGS: Array = ["计算题", "证明题", "选择题", "填空题", "其他"]

	# 第一行：标题 + 题型（两列）
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)

	var title_col: HBoxContainer = HBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label: Label = Label.new()
	title_label.text = "标题:"
	title_label.custom_minimum_size = Vector2(50, 0)
	var title_edit: LineEdit = LineEdit.new()
	title_edit.placeholder_text = "输入题目标题"
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_child(title_label)
	title_col.add_child(title_edit)
	row1.add_child(title_col)

	var type_col: HBoxContainer = HBoxContainer.new()
	type_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var type_label: Label = Label.new()
	type_label.text = "题型:"
	type_label.custom_minimum_size = Vector2(50, 0)
	var type_opt: OptionButton = OptionButton.new()
	for i in TYPE_STRINGS.size():
		type_opt.add_item(TYPE_STRINGS[i], i)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_col.add_child(type_label)
	type_col.add_child(type_opt)
	row1.add_child(type_col)
	vbox.add_child(row1)

	# 第二行：难度 + 来源（两列）
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)

	var diff_col: HBoxContainer = HBoxContainer.new()
	diff_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var diff_label: Label = Label.new()
	diff_label.text = "难度:"
	diff_label.custom_minimum_size = Vector2(50, 0)
	var diff_opt: OptionButton = OptionButton.new()
	for i in range(1, 6):
		diff_opt.add_item("★".repeat(i), i - 1)
	diff_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_col.add_child(diff_label)
	diff_col.add_child(diff_opt)
	row2.add_child(diff_col)

	var source_col: HBoxContainer = HBoxContainer.new()
	source_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var source_label: Label = Label.new()
	source_label.text = "来源:"
	source_label.custom_minimum_size = Vector2(50, 0)
	var source_edit: LineEdit = LineEdit.new()
	source_edit.placeholder_text = "如 2024真题、张宇18讲"
	source_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_col.add_child(source_label)
	source_col.add_child(source_edit)
	row2.add_child(source_col)
	vbox.add_child(row2)

	# 注释（全宽）
	var note_row: HBoxContainer = HBoxContainer.new()
	var note_label: Label = Label.new()
	note_label.text = "注释:"
	note_label.custom_minimum_size = Vector2(50, 0)
	var note_edit: TextEdit = TextEdit.new()
	note_edit.placeholder_text = "可选注释"
	note_edit.custom_minimum_size = Vector2(0, 60)
	note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	note_row.add_child(note_label)
	note_row.add_child(note_edit)
	vbox.add_child(note_row)

	dialog.add_child(vbox)
	add_child(dialog)

	dialog.confirmed.connect(func():
		var title_text: String = title_edit.text.strip_edges()
		if title_text.is_empty():
			title_text = "新题目"
		var new_problem: Dictionary = {
			"title": title_text,
			"type": TYPE_STRINGS[type_opt.selected],
			"difficulty": diff_opt.selected + 1,
			"source": source_edit.text.strip_edges(),
			"images": [],
			"note": note_edit.text.strip_edges(),
			"pos2d": [position.x, position.y],
		}
		_cog_data.add_problem(new_problem)
		if _cog_map:
			_cog_map.rebuild()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	title_edit.grab_focus()


## 认知视图请求编辑题目
func _on_cog_request_edit_problem(prob_index: int) -> void:
	if not _cog_data:
		return
	var prob: Dictionary = _cog_data.call("get_problem", prob_index)
	if prob.is_empty():
		return
	var problem_id: String = str(prob.get("id", ""))

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "编辑题目"
	dialog.min_size = Vector2(620, 520)
	var scroll_vbox: ScrollContainer = ScrollContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var TYPE_STRINGS: Array = ["计算题", "证明题", "选择题", "填空题", "其他"]

	# 第一行：标题 + 题型（两列）
	var row1: HBoxContainer = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)

	var title_col: HBoxContainer = HBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_label: Label = Label.new()
	title_label.text = "标题:"
	title_label.custom_minimum_size = Vector2(50, 0)
	var title_edit: LineEdit = LineEdit.new()
	title_edit.text = str(prob.get("title", ""))
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_child(title_label)
	title_col.add_child(title_edit)
	row1.add_child(title_col)

	var type_col: HBoxContainer = HBoxContainer.new()
	type_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var type_label: Label = Label.new()
	type_label.text = "题型:"
	type_label.custom_minimum_size = Vector2(50, 0)
	var type_opt: OptionButton = OptionButton.new()
	for i in TYPE_STRINGS.size():
		type_opt.add_item(TYPE_STRINGS[i], i)
	var current_type: String = str(prob.get("type", "其他"))
	var type_idx: int = TYPE_STRINGS.find(current_type)
	if type_idx >= 0:
		type_opt.selected = type_idx
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_col.add_child(type_label)
	type_col.add_child(type_opt)
	row1.add_child(type_col)
	vbox.add_child(row1)

	# 第二行：难度 + 来源（两列）
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)

	var diff_col: HBoxContainer = HBoxContainer.new()
	diff_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var diff_label: Label = Label.new()
	diff_label.text = "难度:"
	diff_label.custom_minimum_size = Vector2(50, 0)
	var diff_opt: OptionButton = OptionButton.new()
	for i in range(1, 6):
		diff_opt.add_item("★".repeat(i), i - 1)
	diff_opt.selected = clamp(int(prob.get("difficulty", 1)) - 1, 0, 4)
	diff_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_col.add_child(diff_label)
	diff_col.add_child(diff_opt)
	row2.add_child(diff_col)

	var source_col: HBoxContainer = HBoxContainer.new()
	source_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var source_label: Label = Label.new()
	source_label.text = "来源:"
	source_label.custom_minimum_size = Vector2(50, 0)
	var source_edit: LineEdit = LineEdit.new()
	source_edit.text = str(prob.get("source", ""))
	source_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_col.add_child(source_label)
	source_col.add_child(source_edit)
	row2.add_child(source_col)
	vbox.add_child(row2)

	# 注释（全宽）
	var note_row: HBoxContainer = HBoxContainer.new()
	var note_label: Label = Label.new()
	note_label.text = "注释:"
	note_label.custom_minimum_size = Vector2(50, 0)
	var note_edit: TextEdit = TextEdit.new()
	note_edit.text = str(prob.get("note", ""))
	note_edit.custom_minimum_size = Vector2(0, 60)
	note_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	note_row.add_child(note_label)
	note_row.add_child(note_edit)
	vbox.add_child(note_row)

	# 进入关系画布按钮
	var canvas_sep: HSeparator = HSeparator.new()
	vbox.add_child(canvas_sep)

	var canvas_btn: Button = Button.new()
	canvas_btn.text = "进入关系画布"
	canvas_btn.custom_minimum_size = Vector2(0, 36)
	canvas_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_btn.pressed.connect(func():
		dialog.queue_free()
		_open_problem_canvas(prob_index)
	)
	vbox.add_child(canvas_btn)

	var img_sep: HSeparator = HSeparator.new()
	vbox.add_child(img_sep)

	var img_list: VBoxContainer = VBoxContainer.new()
	img_list.name = "ImageList"
	img_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	img_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(img_list)

	var current_images: Array = []
	var raw_images: Variant = prob.get("images")
	if raw_images is Array:
		current_images = raw_images.duplicate(true)

	for img_path in current_images:
		_add_image_row(img_list, str(img_path), current_images)

	var drop_panel: PanelContainer = PanelContainer.new()
	drop_panel.name = "DropPanel"
	drop_panel.custom_minimum_size = Vector2(0, 60)
	drop_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var drop_style: StyleBoxFlat = StyleBoxFlat.new()
	drop_style.bg_color = Color(0.2, 0.22, 0.28, 0.6)
	drop_style.set_border_width_all(2)
	drop_style.border_color = Color(0.4, 0.5, 0.7, 0.5)
	drop_style.set_corner_radius_all(6)
	drop_style.set_content_margin_all(8)
	drop_panel.add_theme_stylebox_override("panel", drop_style)
	var drop_label: Label = Label.new()
	drop_label.text = "拖拽图片到此处 / 点击选择"
	drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drop_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_panel.add_child(drop_label)
	vbox.add_child(drop_panel)

	drop_panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_image_file_dialog(dialog, problem_id, current_images, img_list)
	)

	var _on_files_dropped: Callable = func(files: PackedStringArray):
		for f in files:
			var ext: String = f.get_extension().to_lower()
			if ext != "png" and ext != "jpg" and ext != "jpeg" and ext != "bmp":
				continue
			var res_path: String = _copy_image_to_project(f, problem_id)
			if not res_path.is_empty():
				current_images.append(res_path)
				_add_image_row(img_list, res_path, current_images)
	get_viewport().files_dropped.connect(_on_files_dropped)
	dialog.tree_exiting.connect(func():
		if get_viewport().files_dropped.is_connected(_on_files_dropped):
			get_viewport().files_dropped.disconnect(_on_files_dropped)
	)

	scroll_vbox.add_child(vbox)
	scroll_vbox.add_theme_constant_override("margin_right", 12)
	dialog.add_child(scroll_vbox)
	add_child(dialog)

	dialog.confirmed.connect(func():
		var new_data: Dictionary = prob.duplicate()
		var title_text: String = title_edit.text.strip_edges()
		if title_text.is_empty():
			title_text = prob.get("title", "题目")
		new_data["title"] = title_text
		new_data["type"] = TYPE_STRINGS[type_opt.selected]
		new_data["difficulty"] = diff_opt.selected + 1
		new_data["source"] = source_edit.text.strip_edges()
		new_data["note"] = note_edit.text.strip_edges()
		new_data["images"] = current_images.duplicate(true)
		_cog_data.call("set_problem", prob_index, new_data)
		if _cog_map:
			_cog_map.rebuild()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()


## 打开题目的独立关系画布
func _open_problem_canvas(prob_index: int) -> void:
	if not _cog_data or not _data_manager:
		return
	var ProblemCanvasScript := load("res://script/2dtr/ProblemCanvas.gd") as GDScript
	var canvas: Control = ProblemCanvasScript.new(prob_index, _cog_data, _data_manager)
	canvas.name = "ProblemCanvas"
	_problem_canvas = canvas

	var HistoryManagerScript := load("res://script/2dtr/HistoryManager.gd") as GDScript
	canvas.history_manager = HistoryManagerScript.new(_cog_data)

	canvas.request_back.connect(func():
		_problem_canvas = null
		if is_instance_valid(canvas):
			_page_cog.remove_child(canvas)
			canvas.queue_free()
		if _cog_map and _cog_map.scroll_container:
			_cog_map.scroll_container.visible = true
			_cog_map.rebuild()
	)
	canvas.request_screenshot.connect(_on_screenshot)
	# 隐藏认知地图，显示画布
	if _cog_map and _cog_map.scroll_container:
		_cog_map.scroll_container.visible = false
	_page_cog.add_child(canvas)


func _add_image_row(img_list: VBoxContainer, img_path: String, images_array: Array) -> void:
	var abs_path: String = _resolve_image_path(img_path)
	var img: Image = Image.load_from_file(abs_path)
	if not img:
		push_warning("加载图片失败: %s" % abs_path)
		return

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var row: VBoxContainer = VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var max_h: float = 500.0

	var panel_bg: PanelContainer = PanelContainer.new()
	panel_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg_style: StyleBoxFlat = StyleBoxFlat.new()
	bg_style.bg_color = Color(0, 0, 0, 0)
	bg_style.set_corner_radius_all(4)
	panel_bg.add_theme_stylebox_override("panel", bg_style)

	var thumb: TextureRect = TextureRect.new()
	thumb.texture = tex
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.custom_minimum_size = Vector2(0, min(tex.get_height(), max_h))
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_STOP
	thumb.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.double_click:
			_show_image_fullscreen(abs_path)
	)
	panel_bg.add_child(thumb)

	row.add_child(panel_bg)

	var del_btn: Button = Button.new()
	del_btn.text = "删除"
	del_btn.custom_minimum_size = Vector2(80, 28)
	del_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	del_btn.pressed.connect(func():
		images_array.erase(img_path)
		row.queue_free()
	)
	row.add_child(del_btn)
	img_list.add_child(row)


func _show_image_fullscreen(abs_path: String) -> void:
	var img: Image = Image.load_from_file(abs_path)
	if not img:
		return
	var tex: ImageTexture = ImageTexture.create_from_image(img)

	var img_w: float = tex.get_width()
	var img_h: float = tex.get_height()

	var scr: Vector2i = DisplayServer.window_get_size()
	var chrome_w: int = 40
	var chrome_h: int = 100
	var max_content_w: float = float(scr.x) - chrome_w
	var max_content_h: float = float(scr.y) - chrome_h

	var display_w: float = img_w
	var display_h: float = img_h
	var ratio: float = img_w / img_h
	if display_w > max_content_w:
		display_w = max_content_w
		display_h = display_w / ratio
	if display_h > max_content_h:
		display_h = max_content_h
		display_w = display_h * ratio

	var final_w: int = int(display_w) + chrome_w
	var final_h: int = int(display_h) + chrome_h

	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.exclusive = false
	dialog.title = "图片预览"
	dialog.min_size = Vector2(int(display_w), int(display_h))
	dialog.size = Vector2i(final_w, final_h)

	var tex_holder: TextureRect = TextureRect.new()
	tex_holder.texture = tex
	tex_holder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tex_holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_holder.custom_minimum_size = Vector2(int(display_w), int(display_h))
	tex_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tex_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(tex_holder)

	add_child(dialog)
	dialog.popup_centered()


func _open_image_file_dialog(parent: Window, problem_id: String, current_images: Array, img_list: VBoxContainer) -> void:
	var file_dialog: FileDialog = FileDialog.new()
	file_dialog.title = "选择图片"
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.jpg ; JPEG Images", "*.jpeg ; JPEG Images", "*.bmp ; BMP Images"])
	file_dialog.exclusive = false
	parent.add_child(file_dialog)
	file_dialog.files_selected.connect(func(paths: PackedStringArray):
		print("[图片] 选择了 %d 个文件" % paths.size())
		for p in paths:
			print("[图片] 处理: %s" % p)
			var res_path: String = _copy_image_to_project(p, problem_id)
			print("[图片] 结果: %s" % res_path)
			if not res_path.is_empty():
				current_images.append(res_path)
				_add_image_row(img_list, res_path, current_images)
				print("[图片] 添加成功，当前共 %d 张" % current_images.size())
			else:
				print("[图片] 复制失败，路径为空")
		file_dialog.queue_free()
	)
	file_dialog.canceled.connect(func():
		print("[图片] 用户取消")
		file_dialog.queue_free()
	)
	file_dialog.popup_centered(Vector2i(800, 600))


func _resolve_image_path(img_path: String) -> String:
	if img_path.begins_with("res://"):
		var stripped: String = img_path.substr(6)
		if stripped.length() >= 3 and stripped[1] == ':' and (stripped[2] == '/' or stripped[2] == '\\'):
			return stripped
		return ProjectSettings.globalize_path(img_path)
	return img_path


func _copy_image_to_project(source_path: String, problem_id: String) -> String:
	if not _cog_data:
		push_warning("复制图片失败: _cog_data 为空")
		return ""
	var cog_file: String = str(_cog_data.get("data_file"))
	if cog_file.is_empty() or cog_file == "<null>":
		push_warning("复制图片失败: data_file 为空，返回原始路径")
		return source_path
	var cog_dir: String = cog_file.get_base_dir()
	var img_dir: String = cog_dir.path_join("images")
	var img_dir_abs: String = img_dir
	if img_dir.begins_with("res://"):
		img_dir_abs = ProjectSettings.globalize_path(img_dir)
	if not DirAccess.dir_exists_absolute(img_dir_abs):
		DirAccess.make_dir_recursive_absolute(img_dir_abs)
	var file_name: String = source_path.get_file()
	var dest_file_name: String = problem_id + "_" + file_name
	var dest_abs: String = img_dir_abs.path_join(dest_file_name)
	var source_abs: String = source_path
	if source_path.begins_with("res://"):
		source_abs = ProjectSettings.globalize_path(source_path)
	if source_abs == dest_abs:
		return source_path
	var err: int = DirAccess.copy_absolute(source_abs, dest_abs)
	if err != OK:
		push_warning("复制图片失败: %s -> %s (err=%d)" % [source_abs, dest_abs, err])
		return source_path
	if cog_file.begins_with("res://"):
		return img_dir.path_join(dest_file_name)
	return img_dir_abs.path_join(dest_file_name)


## 添加关联知识点（从2dmm全量选择，选中后自动显示并创建关系，默认"用到"）
func _on_cog_add_related_knowledge(prob_index: int) -> void:
	if not _cog_data or not _data_manager:
		return
	var prob: Dictionary = _cog_data.call("get_problem", prob_index)
	if prob.is_empty():
		return
	var problem_id: String = str(prob.get("id", ""))

	var existing_targets: Array = []
	for rel in _cog_data.call("get_relations_of_problem", problem_id):
		existing_targets.append(str(rel.get("target", "")))

	var RELATION_TYPES: Array = ["用到", "可替换", "前置", "延伸"]

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "添加关联知识点"
	dialog.min_size = Vector2(400, 450)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# 关系类型选择
	var type_row: HBoxContainer = HBoxContainer.new()
	var type_label: Label = Label.new()
	type_label.text = "关系类型:"
	type_label.custom_minimum_size = Vector2(70, 0)
	var type_opt: OptionButton = OptionButton.new()
	for t in RELATION_TYPES:
		type_opt.add_item(t)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_label)
	type_row.add_child(type_opt)
	vbox.add_child(type_row)

	# 搜索框
	var search_edit: LineEdit = LineEdit.new()
	search_edit.placeholder_text = "搜索知识点..."
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(search_edit)

	# 知识点列表
	var item_list: ItemList = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.select_mode = ItemList.SELECT_MULTI

	var all_names: Array = []
	for i in _data_manager.get_count():
		var item: Dictionary = _data_manager.get_item(i)
		var n: String = str(item.get("name", ""))
		if not n.is_empty():
			all_names.append(n)
			var idx: int = item_list.add_item(n)
			if n in existing_targets:
				item_list.set_item_disabled(idx, true)

	vbox.add_child(item_list)
	dialog.add_child(vbox)
	add_child(dialog)

	search_edit.text_changed.connect(func(text: String):
		item_list.clear()
		var filter: String = text.to_lower()
		for n in all_names:
			if filter.is_empty() or filter in n.to_lower():
				var idx: int = item_list.add_item(n)
				if n in existing_targets:
					item_list.set_item_disabled(idx, true)
	)

	dialog.confirmed.connect(func():
		var rel_type: String = RELATION_TYPES[type_opt.selected]
		var selected: Array = item_list.get_selected_items()
		for si in selected:
			var target_name: String = item_list.get_item_text(si)
			if target_name in existing_targets:
				continue
			_cog_data.call("add_relation", problem_id, target_name, rel_type)
			var cog_idx: int = _cog_data.call("find_by_name", target_name)
			if cog_idx >= 0:
				var cog_item: Dictionary = _cog_data.call("get_item", cog_idx)
				cog_item["visible_in_2dtr"] = true
				_cog_data.call("save_data")
		if _cog_map:
			_cog_map.rebuild()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	search_edit.grab_focus()


## 添加关系（选知识点+选类型）
func _on_cog_add_relation(prob_index: int) -> void:
	if not _cog_data or not _data_manager:
		return
	var prob: Dictionary = _cog_data.call("get_problem", prob_index)
	if prob.is_empty():
		return
	var problem_id: String = str(prob.get("id", ""))

	var existing_targets: Array = []
	for rel in _cog_data.call("get_relations_of_problem", problem_id):
		existing_targets.append(str(rel.get("target", "")))

	var RELATION_TYPES: Array = ["用到", "可替换", "前置", "延伸", "自定义"]

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "添加关系"
	dialog.min_size = Vector2(400, 350)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var type_row: HBoxContainer = HBoxContainer.new()
	var type_label: Label = Label.new()
	type_label.text = "关系类型:"
	type_label.custom_minimum_size = Vector2(70, 0)
	var type_opt: OptionButton = OptionButton.new()
	for t in RELATION_TYPES:
		type_opt.add_item(t)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_label)
	type_row.add_child(type_opt)
	vbox.add_child(type_row)

	var label_row: HBoxContainer = HBoxContainer.new()
	var label_label: Label = Label.new()
	label_label.text = "备注:"
	label_label.custom_minimum_size = Vector2(70, 0)
	var label_edit: LineEdit = LineEdit.new()
	label_edit.placeholder_text = "可选备注"
	label_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_row.add_child(label_label)
	label_row.add_child(label_edit)
	vbox.add_child(label_row)

	var search_edit: LineEdit = LineEdit.new()
	search_edit.placeholder_text = "搜索知识点..."
	vbox.add_child(search_edit)

	var item_list: ItemList = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.select_mode = ItemList.SELECT_MULTI

	var all_names: Array = []
	for i in _data_manager.get_count():
		var item: Dictionary = _data_manager.get_item(i)
		var n: String = str(item.get("name", ""))
		if not n.is_empty():
			all_names.append(n)
			var idx: int = item_list.add_item(n)
			if n in existing_targets:
				item_list.set_item_disabled(idx, true)

	vbox.add_child(item_list)
	dialog.add_child(vbox)
	add_child(dialog)

	search_edit.text_changed.connect(func(text: String):
		item_list.clear()
		var filter: String = text.to_lower()
		for n in all_names:
			if filter.is_empty() or filter in n.to_lower():
				var idx: int = item_list.add_item(n)
				if n in existing_targets:
					item_list.set_item_disabled(idx, true)
	)

	dialog.confirmed.connect(func():
		var selected: Array = item_list.get_selected_items()
		var rel_type: String = RELATION_TYPES[type_opt.selected]
		var rel_label: String = label_edit.text.strip_edges()
		for si in selected:
			var target_name: String = item_list.get_item_text(si)
			if target_name in existing_targets:
				continue
			_cog_data.call("add_relation", problem_id, target_name, rel_type, rel_label)
			var cog_idx: int = _cog_data.call("find_by_name", target_name)
			if cog_idx >= 0:
				var cog_item: Dictionary = _cog_data.call("get_item", cog_idx)
				cog_item["visible_in_2dtr"] = true
				_cog_data.call("save_data")
		if _cog_map:
			_cog_map.rebuild()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	search_edit.grab_focus()


## 认知视图请求管理关系回调（预留接口）
func _on_cog_request_manage_relations(_problem_id: String) -> void:
	pass


## 认知视图请求搜索知识点回调（预留接口）
func _on_cog_request_search_knowledge() -> void:
	pass


## 刷新认知视图布局
func _on_cog_refresh_layout() -> void:
	if _cog_map:
		_cog_map.rebuild()


## 重置认知视图到默认位置
func _on_cog_reset_view() -> void:
	if _cog_map:
		_cog_map.reset_view()


## 保存认知视图所有数据
func _on_cog_save_all() -> void:
	if _cog_data:
		_cog_data.save_data()


## 取消认知视图中所有节点的选中状态
func _on_cog_deselect() -> void:
	if _cog_map:
		_cog_map.deselect_all()


## 在认知视图中通过Tab键创建新题目
func _on_cog_tab_create() -> void:
	if not _cog_map:
		return
	var mouse_pos: Vector2 = _cog_map.get_mouse_container_pos()
	_on_cog_request_create_problem(mouse_pos)


## 删除认知视图中选中的节点
func _on_cog_delete_selected() -> void:
	if not _cog_map:
		return
	_delete_selected_cog()


## 认知题目保存后重建视图
func _on_cog_problem_saved(_problem_id: String, _data: Dictionary) -> void:
	if _cog_map:
		_cog_map.rebuild()


## 认知关系移除后重建视图
func _on_cog_relation_removed(_relation_id: String) -> void:
	if _cog_map:
		_cog_map.rebuild()


## 认知关系类型变更后重建视图
func _on_cog_relation_type_changed(_relation_id: String, _new_type: String) -> void:
	if _cog_map:
		_cog_map.rebuild()


## 显示知识点关联题目列表的弹窗
func _show_knowledge_problem_list(kname: String, problems: Array) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "关联题目 - %s" % kname
	dialog.min_size = Vector2(400, 300)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	for p in problems:
		var row: HBoxContainer = HBoxContainer.new()
		var title: Label = Label.new()
		title.text = str(p.get("title", ""))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var diff: Label = Label.new()
		diff.text = "★".repeat(int(p.get("difficulty", 0)))
		row.add_child(diff)
		var ptype: Label = Label.new()
		ptype.text = str(p.get("type", ""))
		row.add_child(ptype)
		vbox.add_child(row)
	dialog.add_child(vbox)
	add_child(dialog)
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.popup_centered()


## 在认知视图中显示指定知识点的详情弹窗
func _show_detail_popup_cog(index: int) -> void:
	if not _cog_data:
		return
	var item: Dictionary = _cog_data.get_item(index)
	if item.is_empty():
		return
	load("res://script/3dmm/DetailPopup.gd").show(item, _cog_data, null, false)


## 删除认知视图中选中的节点并保存
func _delete_selected_cog() -> void:
	if not _cog_map or not _cog_data:
		return
	var selected: Array = _cog_map.selected_indices.duplicate()
	if selected.is_empty():
		return
	var history_cog: RefCounted = _cog_map.history_manager
	if history_cog:
		history_cog.record_operation("删除节点")
	selected.sort()
	selected.reverse()
	for idx in selected:
		if idx < _cog_data.get_count():
			_cog_data.remove_item(idx)
	_cog_data.save_data()
	_cog_map.deselect_all()
	_cog_map.rebuild()


## 删除认知视图中所有节点
func _delete_all_non_root_cog() -> void:
	if not _cog_map or not _cog_data:
		return
	var history_cog: RefCounted = _cog_map.history_manager
	if history_cog:
		history_cog.record_operation("删除所有节点")
	_cog_data.items.clear()
	_cog_data.save_data()
	_cog_map.deselect_all()
	_cog_map.rebuild()


## 在认知视图中显示编辑节点对话框
func _show_edit_node_dialog_cog(node_index: int) -> void:
	if not _cog_data or node_index < 0 or node_index >= _cog_data.get_count():
		return
	var item: Dictionary = _cog_data.get_item(node_index)
	var old_name: String = str(item.get("name", ""))

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "编辑知识点"
	dialog.min_size = Vector2(420, 300)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var name_row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = Label.new()
	name_label.text = "名称:"
	name_label.custom_minimum_size = Vector2(80, 0)
	var name_edit: LineEdit = LineEdit.new()
	name_edit.text = old_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(name_edit)
	vbox.add_child(name_row)

	var desc_row: HBoxContainer = HBoxContainer.new()
	var desc_label: Label = Label.new()
	desc_label.text = "描述:"
	desc_label.custom_minimum_size = Vector2(80, 0)
	var desc_edit: TextEdit = TextEdit.new()
	desc_edit.text = str(item.get("description", ""))
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
	mastery_opt.add_item("未学习", 0)
	mastery_opt.add_item("学习中", 1)
	mastery_opt.add_item("已掌握", 2)
	mastery_opt.selected = int(item.get("mastery", 0))
	mastery_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_row.add_child(mastery_label)
	mastery_row.add_child(mastery_opt)
	vbox.add_child(mastery_row)

	dialog.add_child(vbox)
	add_child(dialog)

	dialog.confirmed.connect(func():
		var new_name: String = name_edit.text.strip_edges()
		if new_name.is_empty():
			new_name = old_name
		item["name"] = new_name
		item["description"] = desc_edit.text.strip_edges()
		item["mastery"] = mastery_opt.get_selected_id()
		_cog_data.set_item(node_index, item)
		_cog_data.save_data()

		if new_name != old_name:
			var dm_idx: int = _data_manager.find_by_name(old_name)
			if dm_idx >= 0:
				var dm_item: Dictionary = _data_manager.get_item(dm_idx)
				dm_item["name"] = new_name
				dm_item["description"] = desc_edit.text.strip_edges()
				dm_item["mastery"] = mastery_opt.get_selected_id()
				_data_manager.set_item(dm_idx, dm_item)
				_data_manager.save_data()
				_cog_data.call("rename_relation_target", old_name, new_name)
				if _mindmap_2d:
					_mindmap_2d.rebuild()
				if _knowledge_map:
					_knowledge_map.rebuild_all()

		if _cog_map:
			_cog_map.rebuild()
			_cog_map.focus_on_node(node_index)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	name_edit.grab_focus()
