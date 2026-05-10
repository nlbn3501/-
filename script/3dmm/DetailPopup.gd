## 节点详情弹窗，显示知识点的完整信息并提供聚焦、编辑和删除操作
extends RefCounted

## 静态方法：显示节点详情弹窗，包含ID、名称、父节点、掌握度、位置、路径和描述
static func show(item: Dictionary, data_manager: RefCounted, host_node: Node, is_3d: bool = true) -> void:
	var popup := PanelContainer.new()
	popup.name = "DetailPopup"
	var tree: SceneTree = host_node.get_tree() if host_node else Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var layer: CanvasLayer = tree.root.get_node_or_null("DetailCanvasLayer")
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "DetailCanvasLayer"
		tree.root.add_child(layer)
	layer.add_child(popup)

	popup.custom_minimum_size = Vector2(420, 0)
	popup.anchor_left = 0.5
	popup.anchor_right = 0.5
	popup.anchor_top = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -210
	popup.offset_right = 210
	popup.offset_top = -200
	popup.offset_bottom = 200

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup.add_child(vbox)

	var title_bar := HBoxContainer.new()
	vbox.add_child(title_bar)
	var title := Label.new()
	title.text = str(item.get("name", "未命名"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func():
		popup.queue_free()
	)
	title_bar.add_child(close_btn)

	vbox.add_child(HSeparator.new())

	var info_grid := GridContainer.new()
	info_grid.columns = 2
	info_grid.add_theme_constant_override("h_separation", 10)
	info_grid.add_theme_constant_override("v_separation", 5)
	vbox.add_child(info_grid)

	_add_info_row(info_grid, "ID:", str(item.get("id", "")))
	_add_info_row(info_grid, "名称:", str(item.get("name", "")))

	var parent_id: String = str(item.get("parent_id", ""))
	if not parent_id.is_empty():
		var pidx: int = data_manager.call("find_index_by_id", parent_id)
		if pidx >= 0:
			var parent_item: Dictionary = data_manager.call("get_item", pidx)
			_add_info_row(info_grid, "父节点:", str(parent_item.get("name", "")))
		else:
			_add_info_row(info_grid, "父节点:", parent_id)
	else:
		_add_info_row(info_grid, "父节点:", "(无/自由节点)")

	var mastery: int = int(item.get("mastery", 0))
	var mastery_text: String
	match mastery:
		0:
			mastery_text = "未学习"
		1:
			mastery_text = "学习中"
		_:
			mastery_text = "已掌握"
	_add_info_row(info_grid, "掌握度:", mastery_text)

	var pos2d = item.get("pos2d", item.get("relative_offset", [0.0, 0.0]))
	if pos2d is Array and pos2d.size() >= 2:
		_add_info_row(info_grid, "位置:", "(%.1f, %.1f)" % [float(pos2d[0]), float(pos2d[1])])

	var path_text: String = ""
	if data_manager.has_method("get_node_path"):
		var self_idx: int = data_manager.call("find_index_by_id", str(item.get("id", "")))
		path_text = data_manager.call("get_node_path", self_idx)
	if path_text.is_empty():
		path_text = str(item.get("name", ""))
	_add_info_row(info_grid, "路径:", path_text)

	var child_count: int = 0
	var count: int = data_manager.call("get_count")
	var item_id: String = str(item.get("id", ""))
	for i in count:
		var child_item: Dictionary = data_manager.call("get_item", i)
		if str(child_item.get("parent_id", "")) == item_id:
			child_count += 1
	_add_info_row(info_grid, "子节点数:", str(child_count))

	vbox.add_child(HSeparator.new())

	var desc_label := Label.new()
	desc_label.text = "描述:"
	vbox.add_child(desc_label)
	var desc_text := RichTextLabel.new()
	desc_text.bbcode_enabled = true
	desc_text.fit_content = true
	desc_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var desc_content: String = str(item.get("description", ""))
	if desc_content.is_empty():
		desc_content = "(无描述)"
	desc_text.text = desc_content
	vbox.add_child(desc_text)

	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(action_row)

	var is_3d_mode := is_3d
	var is_readonly: bool = not is_3d and host_node == null

	var focus_btn := Button.new()
	focus_btn.text = "聚焦"
	focus_btn.pressed.connect(func():
		var idx: int = data_manager.call("find_index_by_id", str(item.get("id", "")))
		if idx >= 0 and is_3d_mode:
			if host_node and host_node.has_method("request_focus_on_node"):
				host_node.request_focus_on_node(idx)
		popup.queue_free()
	)
	action_row.add_child(focus_btn)

	if not is_readonly:
		var edit_btn := Button.new()
		edit_btn.text = "编辑"
		edit_btn.pressed.connect(func():
			var idx: int = data_manager.call("find_index_by_id", str(item.get("id", "")))
			if idx >= 0 and is_3d_mode:
				if host_node and host_node.has_method("_show_node_dialog"):
					host_node._show_node_dialog("edit", idx)
			popup.queue_free()
		)
		action_row.add_child(edit_btn)

		var delete_btn := Button.new()
		delete_btn.text = "删除"
		delete_btn.pressed.connect(func():
			var idx: int = data_manager.call("find_index_by_id", str(item.get("id", "")))
			if idx >= 0 and is_3d_mode:
				if host_node and host_node.has_method("_delete_node"):
					host_node._delete_node(idx)
			popup.queue_free()
		)
		action_row.add_child(delete_btn)


## 向信息网格添加一行键值对
static func _add_info_row(grid: GridContainer, label_text: String, value_text: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.7, 0.7, 0.7)
	grid.add_child(label)
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 14)
	grid.add_child(value)
