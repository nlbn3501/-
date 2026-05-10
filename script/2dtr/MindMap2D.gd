extends RefCounted

const DEBUG_LOG := false

var _debug_logger: RefCounted

## 调试日志输出
func _log(p_msg: String) -> void:
	if DEBUG_LOG:
		var line: String = "[MindMap2D] " + p_msg
		print(line)
		if _debug_logger:
			_debug_logger.write(line)

var root_node: Node
var data_manager: RefCounted
var context_menu_manager: RefCounted
var history_manager: RefCounted

var node_controls: Dictionary = {}
var node_items: Dictionary = {}
var container: Control
var scroll_container: ScrollContainer
var _empty_hint: Label

var zoom_scale: float = 1.0
var min_zoom: float = 0.3
var max_zoom: float = 3.0
var zoom_speed: float = 0.05
var _zoom_throttle_ms: int = 80
var _zoom_pending: bool = false
var _last_zoom_time: int = 0

var node_size: Vector2 = Vector2(140, 55)

var selected_indices: Array = []
var _shown_indices: Array = []

var selected_index: int:
	get:
		return selected_indices[0] if not selected_indices.is_empty() else -1

var last_container_mouse_pos: Vector2 = Vector2(3600, 2700)

var is_dragging: bool = false
var drag_start_pos: Vector2
var drag_node_index: int
var drag_offset: Vector2

var is_placing_node: bool = false
var placing_node_index: int = -1
var _skip_next_click: bool = false
var _place_queue: Array = []

const MAP_WIDTH: float = 7200.0
const MAP_HEIGHT: float = 5400.0
const ROOT_CENTER_X: float = 3600.0
const ROOT_CENTER_Y: float = 2700.0

signal node_clicked(index: int)
signal node_double_clicked(index: int)
signal node_context_requested(index: int, position: Vector2)
signal request_create_node(parent_hint: int, extra: Variant)
signal request_edit_node(index: int)
signal request_screenshot()
signal data_changed()


func _init(dm: RefCounted, root: Node) -> void:
	data_manager = dm
	root_node = root

	var ContextMenuManagerScript := load("res://script/2dtr/ContextMenuManager.gd")
	if ContextMenuManagerScript:
		context_menu_manager = ContextMenuManagerScript.new(dm, root)
		context_menu_manager.menu_action.connect(_on_context_menu_action)


## 创建认知导图基础UI结构
func create_mind_map() -> void:
	_log("创建思维导图基础结构")

	scroll_container = ScrollContainer.new()
	scroll_container.name = "MindMapScroll"
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll_bg: StyleBoxFlat = StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0, 0, 0)
	scroll_container.add_theme_stylebox_override("panel", scroll_bg)

	container = Control.new()
	container.name = "MindMapContainer"
	container.position = Vector2.ZERO
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.clip_contents = false

	scroll_container.add_child(container)
	root_node.add_child(scroll_container)

	scroll_container.anchor_left = 0.0
	scroll_container.anchor_top = 0.0
	scroll_container.anchor_right = 1.0
	scroll_container.anchor_bottom = 1.0
	scroll_container.offset_left = 0
	scroll_container.offset_top = 0
	scroll_container.offset_right = 0
	scroll_container.offset_bottom = 0

	scroll_container.gui_input.connect(_on_scroll_gui_input)


## 构建认知导图相对布局
func build_mind_map_relative(auto_scroll: bool = true) -> void:
	_log("开始构建独立节点视图")

	_clear_all()

	var count: int = data_manager.call("get_count")
	if count == 0:
		_show_empty_state()
		return

	_hide_empty_state()

	_shown_indices.clear()
	for i in count:
		var item: Dictionary = data_manager.call("get_item", i)
		if item.get("visible_in_2dtr", false) == true:
			_shown_indices.append(i)

	var first_pos: Vector2 = Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)

	for i in count:
		var item: Dictionary = data_manager.call("get_item", i)
		var pos: Vector2 = Vector2(ROOT_CENTER_X + 800, ROOT_CENTER_Y)

		if item.has("pos2d"):
			var p2d: Variant = item.get("pos2d")
			if p2d is Array and p2d.size() >= 2:
				pos = Vector2(float(p2d[0]), float(p2d[1]))
		elif item.has("relative_offset"):
			var rel = item.get("relative_offset")
			if rel is Array and rel.size() >= 2:
				pos = Vector2(float(rel[0]), float(rel[1]))

		_create_node(i, item, pos)

		if _shown_indices.has(i) and (first_pos == Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)):
			first_pos = pos

	_update_container_size()

	if auto_scroll and scroll_container and is_instance_valid(scroll_container):
		call_deferred("_scroll_to_center", first_pos.x, first_pos.y)

	_log("构建完成，节点数量: %d, 可见: %d" % [node_controls.size(), _shown_indices.size()])


## 滚动视图到中心位置
func _scroll_to_center(center_x: float, center_y: float) -> void:
	if not scroll_container or not is_instance_valid(scroll_container):
		return

	if root_node and is_instance_valid(root_node):
		await root_node.get_tree().process_frame
		await root_node.get_tree().process_frame

	var viewport_size = scroll_container.size
	var viewport_center = viewport_size / 2

	var scroll_x = center_x * zoom_scale - viewport_center.x
	var scroll_y = center_y * zoom_scale - viewport_center.y

	var max_scroll_x = max(0, container.custom_minimum_size.x - viewport_size.x)
	var max_scroll_y = max(0, container.custom_minimum_size.y - viewport_size.y)
	scroll_x = clamp(scroll_x, 0, max_scroll_x)
	scroll_y = clamp(scroll_y, 0, max_scroll_y)

	scroll_container.scroll_horizontal = scroll_x
	scroll_container.scroll_vertical = scroll_y

	_log("滚动到中心: 视口大小=%s, 节点中心=(%f, %f), 缩放=%.2f, 滚动位置=(%f, %f)" % [
		viewport_size, center_x, center_y, zoom_scale, scroll_x, scroll_y
	])


func _create_node(index: int, item: Dictionary, base_pos: Vector2) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Node_%d" % index

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(12 * zoom_scale))
	style.set_border_width_all(int(2 * zoom_scale))
	style.border_color = Color(1, 1, 1)
	style.bg_color = Color(0, 0, 0, 0)
	style.shadow_size = int(4 * zoom_scale)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)

	var scaled_size: Vector2 = node_size * zoom_scale
	panel.custom_minimum_size = scaled_size
	panel.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.name = "NodeLabel"
	label.text = str(item.get("name", "节点"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var font_size: int = int(16 * zoom_scale)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	panel.add_child(label)

	panel.position = base_pos * zoom_scale - scaled_size / 2

	panel.gui_input.connect(_on_node_gui_input.bind(index))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if is_placing_node:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	panel.mouse_entered.connect(_on_node_mouse_entered.bind(index))
	panel.mouse_exited.connect(_on_node_mouse_exited.bind(index))

	if is_selected(index):
		_update_node_style(index, true, false)
	else:
		_update_node_style(index, false, false)

	container.add_child(panel)
	node_controls[index] = panel
	node_items[index] = item

	if not _shown_indices.has(index):
		panel.visible = false


## 更新画布容器尺寸
func _update_container_size() -> void:
	var viewport_size := scroll_container.size if scroll_container and is_instance_valid(scroll_container) else Vector2(1152, 648)

	var new_size := Vector2(MAP_WIDTH, MAP_HEIGHT) * zoom_scale
	new_size.x = max(new_size.x, viewport_size.x)
	new_size.y = max(new_size.y, viewport_size.y)

	container.custom_minimum_size = new_size
	container.size = new_size

	if node_controls.is_empty():
		return

	var min_x := 999999.0
	var min_y := 999999.0
	var max_x := -999999.0
	var max_y := -999999.0

	for index in node_controls.keys():
		var panel: PanelContainer = node_controls[index]
		var left := panel.position.x
		var top := panel.position.y
		var right := panel.position.x + panel.custom_minimum_size.x
		var bottom := panel.position.y + panel.custom_minimum_size.y
		min_x = min(min_x, left)
		min_y = min(min_y, top)
		max_x = max(max_x, right)
		max_y = max(max_y, bottom)

	_log("容器大小更新: %s, 缩放=%.2f, 内容范围: (%.0f,%.0f)-(%.0f,%.0f)" % [str(new_size), zoom_scale, min_x, min_y, max_x, max_y])


func _clear_all() -> void:
	for key in node_controls.keys():
		var ctrl: Control = node_controls[key]
		if is_instance_valid(ctrl):
			container.remove_child(ctrl)
			ctrl.queue_free()
	node_controls.clear()
	node_items.clear()


## 显示空数据状态提示
func _show_empty_state() -> void:
	if _empty_hint != null:
		return

	_empty_hint = Label.new()
	_empty_hint.text = "右键点击此处新建知识点\n或按 Ctrl+N 快速创建节点"
	_empty_hint.add_theme_font_size_override("font_size", int(24 * zoom_scale))
	_empty_hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_hint.position = Vector2(ROOT_CENTER_X - 400, ROOT_CENTER_Y - 60) * zoom_scale
	_empty_hint.custom_minimum_size = Vector2(800, 120) * zoom_scale
	container.add_child(_empty_hint)


## 隐藏空数据状态提示
func _hide_empty_state() -> void:
	if _empty_hint != null and is_instance_valid(_empty_hint):
		_empty_hint.queue_free()
		_empty_hint = null


## 判断指定节点是否被选中
func is_selected(index: int) -> bool:
	return selected_indices.has(index)


## 选中指定节点，支持多选模式
func select_node(index: int, multi: bool = false) -> void:
	if multi:
		if selected_indices.has(index):
			selected_indices.erase(index)
			_update_node_style(index, false, false)
		else:
			selected_indices.append(index)
			_update_node_style(index, true, false)
	else:
		for si in selected_indices:
			if si != index and node_controls.has(si):
				_update_node_style(si, false, false)
		selected_indices.clear()
		if not selected_indices.has(index):
			selected_indices.append(index)
		_update_node_style(index, true, false)


## 取消所有节点的选中状态
func deselect_all() -> void:
	for si in selected_indices:
		if node_controls.has(si):
			_update_node_style(si, false, false)
	selected_indices.clear()


## 节点GUI输入事件处理
func _on_node_gui_input(event: InputEvent, index: int) -> void:
	if is_placing_node:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			node_double_clicked.emit(index)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			if Input.is_key_pressed(KEY_CTRL):
				_log("Ctrl+点击节点: %d, 当前选中=%s" % [index, str(selected_indices)])
				select_node(index, true)
				_log("Ctrl+点击后选中=%s" % str(selected_indices))
				node_clicked.emit(index)
				return

			is_dragging = true
			drag_node_index = index

			var panel: PanelContainer = node_controls[index]
			drag_start_pos = panel.position

			var container_mouse_pos = _screen_to_container(mb.global_position)
			drag_offset = container_mouse_pos - panel.position

			if selected_indices.size() > 1 and is_selected(index):
				select_node(index, false)
			elif not is_selected(index):
				select_node(index, false)

			node_clicked.emit(index)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if is_dragging:
				is_dragging = false

				var panel: PanelContainer = node_controls[drag_node_index]
				var drag_distance: float = (panel.position - drag_start_pos).length()

				if drag_distance > 20.0:
					var item: Dictionary = node_items[drag_node_index]
					if history_manager:
						history_manager.record_operation("移动节点: %s" % str(item.get("name", "")))
					update_node_position(drag_node_index)
					data_manager.call("save_data")
				else:
					node_controls[drag_node_index].position = drag_start_pos
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if context_menu_manager:
				if selected_indices.size() > 1 and is_selected(index):
					context_menu_manager.show_multi_selection_menu(mb.global_position, selected_indices)
				else:
					context_menu_manager.show_node_context_menu(index, mb.global_position, false)
			else:
				node_context_requested.emit(index, mb.global_position)
			return

	elif event is InputEventMouseMotion and is_dragging:
		var panel: PanelContainer = node_controls[drag_node_index]

		var container_mouse_pos = _screen_to_container(event.global_position)
		var new_pos: Vector2 = container_mouse_pos - drag_offset
		panel.position = new_pos


## 将屏幕坐标转换为画布容器内坐标
func _screen_to_container(global_pos: Vector2) -> Vector2:
	var viewport_pos: Vector2 = global_pos - scroll_container.get_global_position()
	return viewport_pos + Vector2(float(scroll_container.scroll_horizontal), float(scroll_container.scroll_vertical))


func update_node_position(node_index: int) -> void:
	if not node_controls.has(node_index):
		return
	var panel: PanelContainer = node_controls[node_index]
	var node_center = (panel.position + panel.size / 2) / zoom_scale

	var item: Dictionary = node_items[node_index]
	item["pos2d"] = [node_center.x, node_center.y]
	item["relative_offset"] = [node_center.x, node_center.y]


## 应用当前缩放比例到画布
func apply_canvas_zoom() -> void:
	_log("应用画布缩放: %.2f (重建视图)" % zoom_scale)
	rebuild()


## 缩放变更时更新所有节点位置和尺寸
func _apply_zoom_update(old_zoom: float) -> void:
	if node_controls.is_empty():
		return

	for index in node_controls.keys():
		var panel: PanelContainer = node_controls[index]
		if not is_instance_valid(panel):
			continue

		var old_center: Vector2 = panel.position + panel.custom_minimum_size / 2.0
		var base_pos: Vector2 = old_center / old_zoom

		var scaled_size: Vector2 = node_size * zoom_scale

		panel.custom_minimum_size = scaled_size
		panel.size = scaled_size
		panel.position = base_pos * zoom_scale - scaled_size / 2.0

		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.set_corner_radius_all(int(12 * zoom_scale))
		style.set_border_width_all(int(2 * zoom_scale))
		style.border_color = Color(1, 1, 1)
		style.bg_color = Color(0, 0, 0, 0)
		style.shadow_size = int(4 * zoom_scale)
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
		panel.add_theme_stylebox_override("panel", style)

		var label: Label = panel.get_node_or_null("NodeLabel")
		if label:
			label.add_theme_font_size_override("font_size", int(16 * zoom_scale))

		if is_selected(index):
			_update_node_style(index, true, false)
		else:
			_update_node_style(index, false, false)

	_update_container_size()

	_log("缩放属性更新: %.2f→%.2f, 节点数=%d" % [old_zoom, zoom_scale, node_controls.size()])


func zoom_in(mouse_global_pos: Vector2) -> void:
	var old_zoom = zoom_scale
	zoom_scale = min(max_zoom, zoom_scale + zoom_speed)
	if zoom_scale != old_zoom:
		_do_zoom(old_zoom, mouse_global_pos)
		if is_placing_node and node_controls.has(placing_node_index):
			_snap_placing_node_to_mouse()


## 缩小视图
func zoom_out(mouse_global_pos: Vector2) -> void:
	var old_zoom = zoom_scale
	zoom_scale = max(min_zoom, zoom_scale - zoom_speed)
	if zoom_scale != old_zoom:
		_do_zoom(old_zoom, mouse_global_pos)
		if is_placing_node and node_controls.has(placing_node_index):
			_snap_placing_node_to_mouse()



## 执行缩放操作，以鼠标位置为中心缩放
func _do_zoom(old_zoom: float, mouse_global_pos: Vector2) -> void:
	var mouse_viewport_pos: Vector2 = mouse_global_pos - scroll_container.get_global_position()

	var old_scroll: Vector2 = Vector2(float(scroll_container.scroll_horizontal), float(scroll_container.scroll_vertical))
	var local_point: Vector2 = (mouse_viewport_pos + old_scroll) / old_zoom

	_last_zoom_time = Time.get_ticks_msec()

	_apply_zoom_update(old_zoom)

	if not _zoom_pending:
		_zoom_pending = true
		root_node.get_tree().create_timer(0.2).timeout.connect(_on_zoom_throttle_timeout)

	var new_scroll_x: float = local_point.x * zoom_scale - mouse_viewport_pos.x
	var new_scroll_y: float = local_point.y * zoom_scale - mouse_viewport_pos.y

	var viewport_size: Vector2 = scroll_container.size
	var max_scroll_x = max(0, container.custom_minimum_size.x - viewport_size.x)
	var max_scroll_y = max(0, container.custom_minimum_size.y - viewport_size.y)
	new_scroll_x = clamp(new_scroll_x, 0, max_scroll_x)
	new_scroll_y = clamp(new_scroll_y, 0, max_scroll_y)

	scroll_container.scroll_horizontal = new_scroll_x
	scroll_container.scroll_vertical = new_scroll_y

	_log("缩放: %.2f→%.2f, 鼠标视口=(%.0f,%.0f), 本地点=(%.0f,%.0f), 新滚动=(%.0f,%.0f)" % [
		old_zoom, zoom_scale, mouse_viewport_pos.x, mouse_viewport_pos.y,
		local_point.x, local_point.y, new_scroll_x, new_scroll_y
	])


func _on_zoom_throttle_timeout() -> void:
	if _zoom_pending:
		var now: int = Time.get_ticks_msec()
		if now - _last_zoom_time >= 150:
			_zoom_pending = false
		else:
			root_node.get_tree().create_timer(0.1).timeout.connect(_on_zoom_throttle_timeout)


## 处理滚动事件
func handle_scroll(event: InputEvent) -> void:
	_on_scroll_gui_input(event)


## 滚动容器GUI输入事件处理
func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var container_mouse_pos = _screen_to_container(event.global_position)
		last_container_mouse_pos = container_mouse_pos / zoom_scale

		if is_placing_node and node_controls.has(placing_node_index):
			var panel: PanelContainer = node_controls[placing_node_index]
			panel.position = container_mouse_pos - panel.custom_minimum_size / 2

		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			scroll_container.scroll_horizontal -= event.relative.x
			scroll_container.scroll_vertical -= event.relative.y
			return

	if not event is InputEventMouseButton:
		return

	var mb: InputEventMouseButton = event as InputEventMouseButton

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		scroll_container.scroll_vertical = max(0, scroll_container.scroll_vertical - 50)
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		scroll_container.scroll_vertical = scroll_container.scroll_vertical + 50
		return

	if is_placing_node:
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_finalize_placing_node()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_placing_node()
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _skip_next_click:
			_skip_next_click = false
			return
		var container_mouse_pos = _screen_to_container(mb.global_position)
		var local_pos = container_mouse_pos / zoom_scale

		if context_menu_manager:
			context_menu_manager.show_empty_context_menu(mb.global_position, local_pos)
		return

	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if _skip_next_click:
			_skip_next_click = false
			return
		if not Input.is_key_pressed(KEY_CTRL):
			deselect_all()
		return


func _update_placing_node_position() -> void:
	if is_placing_node and node_controls.has(placing_node_index):
		_snap_placing_node_to_mouse()
		_apply_placing_node_style()


## 为正在放置的节点应用虚线边框样式
func _apply_placing_node_style() -> void:
	if is_placing_node and node_controls.has(placing_node_index):
		var panel = node_controls[placing_node_index]
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if style:
			var new_style = style.duplicate()
			new_style.border_color = Color(0, 1, 0.5)
			new_style.set_border_width_all(int(3 * zoom_scale))
			new_style.shadow_color = Color(0.0, 1.0, 0.5, 0.3)
			new_style.shadow_size = int(8 * zoom_scale)
			panel.add_theme_stylebox_override("panel", new_style)


## 完成当前节点放置，若队列中有待放置节点则继续下一个
func _finalize_placing_node() -> void:
	if not is_placing_node:
		return

	is_placing_node = false
	_skip_next_click = true

	if node_controls.has(placing_node_index):
		var panel: PanelContainer = node_controls[placing_node_index]
		var node_center = (panel.position + panel.size / 2) / zoom_scale

		var item: Dictionary = data_manager.call("get_item", placing_node_index)
		item["pos2d"] = [node_center.x, node_center.y]
		item["relative_offset"] = [node_center.x, node_center.y]
		item["visible_in_2dtr"] = true
		data_manager.call("save_data")

		_log("节点放置完成: %d, 位置=(%.0f, %.0f), 滚动=(%.0f, %.0f)" % [
			placing_node_index, node_center.x, node_center.y,
			float(scroll_container.scroll_horizontal), float(scroll_container.scroll_vertical)
		])
	else:
		_log("节点放置完成: %d (无控件)" % placing_node_index)
	placing_node_index = -1
	rebuild(false)

	if not _place_queue.is_empty():
		_place_next_from_queue()


## 取消当前节点放置，清空放置队列
func _cancel_placing_node() -> void:
	if not is_placing_node:
		return
	if node_controls.has(placing_node_index):
		node_controls[placing_node_index].visible = false
	_shown_indices.erase(placing_node_index)
	var item: Dictionary = data_manager.call("get_item", placing_node_index)
	item["visible_in_2dtr"] = false
	data_manager.call("save_data")
	is_placing_node = false
	placing_node_index = -1
	_place_queue.clear()
	rebuild(false)


## 从放置队列中取出下一个节点进入放置模式
## 从放置队列中放置下一个节点
func _place_next_from_queue() -> void:
	if _place_queue.is_empty():
		return
	var next_index: int = _place_queue.pop_front()
	if not node_controls.has(next_index):
		if not _place_queue.is_empty():
			_place_next_from_queue()
		return
	if not _shown_indices.has(next_index):
		_shown_indices.append(next_index)
	var item: Dictionary = data_manager.call("get_item", next_index)
	item["visible_in_2dtr"] = true
	data_manager.call("save_data")
	is_placing_node = true
	placing_node_index = next_index
	_skip_next_click = false
	node_controls[next_index].visible = true
	node_controls[next_index].mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap_placing_node_to_mouse()
	_apply_placing_node_style()
	select_node(next_index, false)


## 更新节点的视觉样式
func _update_node_style(index: int, is_selected_flag: bool, is_hovered: bool) -> void:
	if not node_controls.has(index):
		return

	var panel: PanelContainer = node_controls[index]
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	if not style:
		return

	var new_style: StyleBoxFlat = style.duplicate()
	if is_selected_flag:
		new_style.border_color = Color(0, 0.7, 1)
		new_style.set_border_width_all(int(3 * zoom_scale))
	elif is_hovered:
		new_style.border_color = Color(0, 0.5, 0.7)
		new_style.set_border_width_all(int(2 * zoom_scale))
	else:
		new_style.border_color = Color(1, 1, 1)
		new_style.set_border_width_all(int(2 * zoom_scale))

	panel.add_theme_stylebox_override("panel", new_style)


## 节点鼠标进入回调
func _on_node_mouse_entered(index: int) -> void:
	_update_node_style(index, is_selected(index), true)


func _on_node_mouse_exited(index: int) -> void:
	_update_node_style(index, is_selected(index), false)


## 重置视图到默认缩放和中心
func reset_view() -> void:
	zoom_scale = 1.0

	var viewport_size = scroll_container.size
	var viewport_center = viewport_size / 2

	var center_pos = Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)

	rebuild()

	var scroll_x = center_pos.x * zoom_scale - viewport_center.x
	var scroll_y = center_pos.y * zoom_scale - viewport_center.y

	scroll_x = max(0, scroll_x)
	scroll_y = max(0, scroll_y)

	scroll_container.scroll_horizontal = scroll_x
	scroll_container.scroll_vertical = scroll_y

	_log("重置视图: 视口大小=%s, 中心位置=%s, 滚动位置=(%f, %f)" % [viewport_size, center_pos, scroll_x, scroll_y])


## 重建认知导图视图
func rebuild(auto_scroll: bool = false) -> void:
	var saved_scroll_x: float = 0.0
	var saved_scroll_y: float = 0.0
	if scroll_container and is_instance_valid(scroll_container) and not auto_scroll:
		saved_scroll_x = float(scroll_container.scroll_horizontal)
		saved_scroll_y = float(scroll_container.scroll_vertical)
	build_mind_map_relative(auto_scroll)
	if not auto_scroll and scroll_container and is_instance_valid(scroll_container):
		scroll_container.scroll_horizontal = int(saved_scroll_x)
		scroll_container.scroll_vertical = int(saved_scroll_y)
	if is_placing_node and node_controls.has(placing_node_index):
		_update_placing_node_position()
	data_changed.emit()


func focus_on_node(index: int) -> void:
	if index < 0:
		deselect_all()
		return

	if not node_controls.has(index):
		return

	select_node(index, false)


## 滚动视图到指定节点位置
func scroll_to_node(index: int) -> void:
	if not node_controls.has(index):
		return

	var panel: PanelContainer = node_controls[index]
	var node_center: Vector2 = panel.position + panel.size / 2

	var viewport_size = scroll_container.size
	scroll_container.scroll_horizontal = int(node_center.x - viewport_size.x / 2)
	scroll_container.scroll_vertical = int(node_center.y - viewport_size.y / 2)


## 上下文菜单动作回调
func _on_context_menu_action(action: String, index: int, extra: Variant = null, mouse_pos: Vector2 = Vector2.ZERO) -> void:
	match action:
		"show_detail":
			node_double_clicked.emit(index)

		"focus_node":
			focus_on_node(index)
			scroll_to_node(index)

		"switch_view":
			_log("切换视图到节点: %d" % index)

		"set_mastery":
			if extra is int:
				var item: Dictionary = data_manager.call("get_item", index)
				if item is Dictionary:
					if history_manager:
						history_manager.record_operation("设置掌握度: %s" % str(item.get("name", "")))
					item["mastery"] = extra
					item["visible_in_2dtr"] = true
					data_manager.call("save_data")
					update_node_style(index, is_selected(index), false)

		"remove_from_view":
			_remove_node_from_view(index)

		"create_node":
			var local_pos: Vector2 = extra if extra is Vector2 else Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)
			create_node_at(local_pos)

		"add_node_show":
			_show_add_node_dialog()

		"refresh":
			data_manager.call("load_data")
			rebuild()

		"reset_view":
			reset_view()

		"screenshot":
			_log("截图请求")
			request_screenshot.emit()

		"batch_mastery":
			if extra is int:
				var mastery_val: int = extra
				if history_manager:
					history_manager.record_operation("批量设置掌握度: %d个节点" % selected_indices.size())
				for sel_idx in selected_indices:
					if data_manager.call("get_count") > sel_idx:
						var item: Dictionary = data_manager.call("get_item", sel_idx)
						item["mastery"] = mastery_val
				data_manager.call("save_data")
				rebuild()
				_log("批量设置掌握程度为: %d, 节点数: %d" % [mastery_val, selected_indices.size()])

		"batch_delete":
			var indices_to_delete: Array = selected_indices.duplicate()
			if indices_to_delete.is_empty():
				if extra is Array:
					indices_to_delete = extra
			if indices_to_delete.is_empty():
				return
			if history_manager:
				history_manager.record_operation("批量删除 %d个节点" % indices_to_delete.size())
			indices_to_delete.sort()
			indices_to_delete.reverse()
			for del_idx in indices_to_delete:
				if del_idx >= 0 and del_idx < data_manager.call("get_count"):
					data_manager.call("remove_item", del_idx)
			data_manager.call("save_data")
			deselect_all()
			rebuild()
			_log("批量删除节点: %d个" % indices_to_delete.size())


func create_node_at(position: Vector2) -> void:
	var scroll_before: Vector2 = Vector2(
		float(scroll_container.scroll_horizontal),
		float(scroll_container.scroll_vertical)
	)
	_log("创建浮动节点前: 滚动=(%.0f, %.0f), 缩放=%.2f" % [scroll_before.x, scroll_before.y, zoom_scale])

	var new_item: Dictionary = {
		"id": data_manager.call("generate_unique_id", "new_node"),
		"name": "New Node",
		"description": "",
		"relative_offset": [position.x, position.y],
		"pos2d": [position.x, position.y],
		"parent_id": "",
		"mastery": 0,
		"source": "2dtr",
		"visible_in_2dtr": true,
	}

	if history_manager:
		history_manager.record_operation("创建节点: New Node")
	var new_index: int = data_manager.call("add_item", new_item)
	if not _shown_indices.has(new_index):
		_shown_indices.append(new_index)
	data_manager.call("save_data")

	is_placing_node = true
	placing_node_index = new_index
	_snap_log_counter = 0

	rebuild(false)

	var scroll_after_rebuild: Vector2 = Vector2(
		float(scroll_container.scroll_horizontal),
		float(scroll_container.scroll_vertical)
	)
	_log("创建浮动节点 rebuild后: 滚动=(%.0f, %.0f), 偏移=(%.0f, %.0f)" % [
		scroll_after_rebuild.x, scroll_after_rebuild.y,
		scroll_after_rebuild.x - scroll_before.x, scroll_after_rebuild.y - scroll_before.y
	])

	select_node(new_index, false)

	if node_controls.has(placing_node_index):
		_snap_placing_node_to_mouse()
		_apply_placing_node_style()

	var scroll_after_snap: Vector2 = Vector2(
		float(scroll_container.scroll_horizontal),
		float(scroll_container.scroll_vertical)
	)
	_log("创建浮动节点 snap后: 滚动=(%.0f, %.0f), 总偏移=(%.0f, %.0f), 节点=%d, 位置=(%.0f, %.0f)" % [
		scroll_after_snap.x, scroll_after_snap.y,
		scroll_after_snap.x - scroll_before.x, scroll_after_snap.y - scroll_before.y,
		new_index, position.x, position.y
	])


var _snap_log_counter: int = 0

## 将正在放置的节点吸附到鼠标位置
func _snap_placing_node_to_mouse() -> void:
	if not is_placing_node or not node_controls.has(placing_node_index):
		return
	if not scroll_container or not is_instance_valid(scroll_container):
		return
	var global_pos: Vector2 = root_node.get_viewport().get_mouse_position()
	var container_mouse_pos = _screen_to_container(global_pos)
	var panel: PanelContainer = node_controls[placing_node_index]
	panel.position = container_mouse_pos - panel.custom_minimum_size / 2
	_snap_log_counter += 1
	if _snap_log_counter <= 5 or _snap_log_counter % 30 == 0:
		_log("snap[%d]: 鼠标全局=(%.0f,%.0f), 容器=(%.0f,%.0f), 面板=(%.0f,%.0f), 滚动=(%.0f,%.0f)" % [
			_snap_log_counter, global_pos.x, global_pos.y,
			container_mouse_pos.x, container_mouse_pos.y,
			panel.position.x, panel.position.y,
			float(scroll_container.scroll_horizontal), float(scroll_container.scroll_vertical)
		])


## 获取指定节点的画布位置
func get_node_position(index: int) -> Vector2:
	if node_controls.has(index):
		return node_controls[index].position / zoom_scale
	return Vector2.ZERO


## 显示指定节点（滚动到可视区域）
func _show_node(index: int) -> void:
	if not _shown_indices.has(index):
		_shown_indices.append(index)
	if node_controls.has(index) and is_instance_valid(node_controls[index]):
		node_controls[index].visible = true


## 从视图中移除指定节点（不删除数据，仅隐藏）
func _remove_node_from_view(index: int) -> void:
	_shown_indices.erase(index)
	var item: Dictionary = data_manager.call("get_item", index)
	item["visible_in_2dtr"] = false
	data_manager.call("save_data")
	if is_selected(index):
		selected_indices.erase(index)
	rebuild(false)


## 显示添加节点对话框（搜索已有节点 + 输入名称创建新节点，确认后跟在鼠标上放置）
## 显示添加节点对话框
func _show_add_node_dialog() -> void:
	var count: int = data_manager.call("get_count")

	var all_nodes: Array = []
	for i in count:
		var item: Dictionary = data_manager.call("get_item", i)
		all_nodes.append({"index": i, "name": str(item.get("name", "节点")), "desc": str(item.get("description", ""))})

	var selected_real: Dictionary = {}
	var _updating: bool = false

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "添加节点"
	dialog.min_size = Vector2(460, 560)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var search_label: Label = Label.new()
	search_label.text = "搜索已有节点（可多选）:"
	vbox.add_child(search_label)

	var search_box: LineEdit = LineEdit.new()
	search_box.placeholder_text = "输入关键词搜索..."
	search_box.clear_button_enabled = true
	vbox.add_child(search_box)

	var item_list: ItemList = ItemList.new()
	item_list.name = "NodeList"
	item_list.select_mode = ItemList.SELECT_MULTI
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.custom_minimum_size = Vector2(420, 240)
	vbox.add_child(item_list)

	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	var create_label: Label = Label.new()
	create_label.text = "或输入名称创建新节点:"
	vbox.add_child(create_label)

	var name_edit: LineEdit = LineEdit.new()
	name_edit.placeholder_text = "新节点名称..."
	name_edit.clear_button_enabled = true
	vbox.add_child(name_edit)

	var indices_map: Array = []

	var refresh_list := func(filter: String) -> void:
		if not is_instance_valid(item_list):
			return
		_updating = true
		item_list.clear()
		indices_map.clear()
		var lower_filter: String = filter.to_lower()
		for node_data in all_nodes:
			var n_name: String = node_data["name"]
			var n_desc: String = node_data["desc"]
			var real_idx: int = node_data["index"]
			if not lower_filter.is_empty():
				if not n_name.to_lower().contains(lower_filter) and not n_desc.to_lower().contains(lower_filter):
					continue
			var display: String = n_name
			if selected_real.has(real_idx):
				display += " [已选]"
			item_list.add_item(display)
			indices_map.append(real_idx)
			if selected_real.has(real_idx):
				item_list.select(item_list.get_item_count() - 1)
		_updating = false

	refresh_list.call("")

	search_box.text_changed.connect(func(new_text: String) -> void:
		refresh_list.call(new_text)
	)

	item_list.multi_selected.connect(func(list_idx: int, selected: bool) -> void:
		if _updating:
			return
		if list_idx >= 0 and list_idx < indices_map.size():
			var real_idx: int = indices_map[list_idx]
			if selected:
				selected_real[real_idx] = true
			else:
				selected_real.erase(real_idx)
			refresh_list.call(search_box.text)
	)

	item_list.item_clicked.connect(func(list_idx: int, _at_pos: Vector2, mb_index: int) -> void:
		if mb_index != MOUSE_BUTTON_RIGHT:
			return
		if _updating:
			return
		if list_idx >= 0 and list_idx < indices_map.size():
			var real_idx: int = indices_map[list_idx]
			selected_real.erase(real_idx)
			refresh_list.call(search_box.text)
	)

	name_edit.text_submitted.connect(func(_t: String) -> void:
		dialog.confirmed.emit()
	)

	dialog.add_child(vbox)
	root_node.add_child(dialog)

	dialog.confirmed.connect(func():
		_place_queue.clear()

		var new_name: String = name_edit.text.strip_edges()
		if not new_name.is_empty():
			var new_pos: Vector2 = last_container_mouse_pos
			var new_item: Dictionary = {
				"id": data_manager.call("generate_unique_id", "new_node"),
				"name": new_name,
				"description": "",
				"relative_offset": [new_pos.x, new_pos.y],
				"pos2d": [new_pos.x, new_pos.y],
				"parent_id": "",
				"mastery": 0,
				"source": "2dtr",
				"visible_in_2dtr": true,
			}
			if history_manager:
				history_manager.record_operation("创建节点: %s" % new_name)
			var new_index: int = data_manager.call("add_item", new_item)
			data_manager.call("save_data")
			_place_queue.append(new_index)

		for idx in selected_real.keys():
			if not _place_queue.has(idx):
				_place_queue.append(idx)

		dialog.queue_free()

		if not _place_queue.is_empty():
			rebuild(false)
			_place_next_from_queue.call_deferred()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)

	dialog.popup_centered()
	search_box.grab_focus()


## 获取鼠标在画布容器中的位置
func get_mouse_container_pos() -> Vector2:
	return last_container_mouse_pos


## 公开接口：更新节点样式
func update_node_style(index: int, is_selected_flag: bool, is_hovered: bool) -> void:
	_update_node_style(index, is_selected_flag, is_hovered)
