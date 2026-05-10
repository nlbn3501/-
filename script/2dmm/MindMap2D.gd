## 2D思维导图核心类，管理节点的创建、布局、交互、缩放、拖拽和连线绘制
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
var line_controls: Array = []
var container: Control
var scroll_container: ScrollContainer
var _empty_hint: Label

var _children_map: Dictionary = {}

var node_depths: Dictionary = {}
var _main_root_index: int = -1
var _node_is_center: Dictionary = {}

var zoom_scale: float = 1.0
var min_zoom: float = 0.3
var max_zoom: float = 3.0
var zoom_speed: float = 0.05
var _zoom_throttle_ms: int = 80
var _zoom_pending: bool = false
var _last_zoom_time: int = 0

var center_node_size: Vector2 = Vector2(180, 70)
var main_node_size: Vector2 = Vector2(140, 55)
var sub_node_size: Vector2 = Vector2(120, 45)
var leaf_node_size: Vector2 = Vector2(100, 40)

var horizontal_gap: float = 120.0
var vertical_spacing: float = 60.0

var selected_indices: Array = []

var selected_index: int:
	get:
		return selected_indices[0] if not selected_indices.is_empty() else -1

var last_container_mouse_pos: Vector2 = Vector2(3600, 2700)

var is_dragging: bool = false
var _lines_hidden: bool = false
var drag_start_pos: Vector2
var drag_node_index: int
var drag_parent_start: String
var drag_offset: Vector2
var drag_subtree_indices: Array = []
var drag_subtree_start_positions: Dictionary = {}

var drag_preview_line: Line2D
var snap_target_index: int = -1

var snap_distance: float = 100.0
var drag_dead_zone: float = 20.0

var _hover_timer: SceneTreeTimer = null
var _hover_node_index: int = -1
var _hover_delay: float = 0.8
var _hover_popup: Node = null

var is_placing_node: bool = false
var placing_node_index: int = -1
var _skip_next_click: bool = false

const MAP_WIDTH: float = 7200.0
const MAP_HEIGHT: float = 5400.0
const ROOT_CENTER_X: float = 3600.0
const ROOT_CENTER_Y: float = 2700.0

var branch_colors: Array[Color] = [
	Color(0.20, 0.60, 1.00),
	Color(1.00, 0.35, 0.35),
	Color(0.30, 0.85, 0.40),
	Color(1.00, 0.65, 0.10),
	Color(0.80, 0.30, 0.95),
	Color(0.05, 0.85, 0.85),
	Color(1.00, 0.45, 0.70),
	Color(0.95, 0.75, 0.20),
]

signal node_clicked(index: int)
signal node_double_clicked(index: int)
signal node_context_requested(index: int, position: Vector2)
signal request_create_node(parent_hint: int, extra: Variant)
signal request_edit_node(index: int)
signal request_rename_node(index: int)
signal request_hover_show(index: int)
signal request_screenshot()
signal data_changed()


## 初始化思维导图，绑定数据管理器和根节点，创建上下文菜单管理器
func _init(dm: RefCounted, root: Node) -> void:
	data_manager = dm
	root_node = root

	var ContextMenuManagerScript := load("res://script/2dmm/ContextMenuManager.gd")
	if ContextMenuManagerScript:
		context_menu_manager = ContextMenuManagerScript.new(dm, root)
		context_menu_manager.menu_action.connect(_on_context_menu_action)

	_migrate_root_position()


## 迁移旧版根节点位置到新的中心坐标，自动偏移所有节点
func _migrate_root_position() -> void:
	var count: int = data_manager.call("get_count")
	if count == 0:
		return

	var depths: Array = data_manager.call("compute_depths")
	var needs_migration: bool = false
	var old_center_x: float = 0.0
	var old_center_y: float = 0.0

	for i in count:
		if i < depths.size() and depths[i] == 0:
			var item: Dictionary = data_manager.call("get_item", i)
			var p2d = item.get("pos2d")
			if p2d is Array and p2d.size() >= 2:
				var px = float(p2d[0])
				var py = float(p2d[1])
				if abs(px - 1200.0) < 100.0 and abs(py - 900.0) < 100.0:
					needs_migration = true
					old_center_x = 1200.0
					old_center_y = 900.0
					break
				elif abs(px - 2666.0) < 100.0 and abs(py - 2000.0) < 100.0:
					needs_migration = true
					old_center_x = 2666.0
					old_center_y = 2000.0
					break

	if not needs_migration:
		return

	_log("检测到旧版根节点位置(%.0f,%.0f)，迁移到新位置(%.0f,%.0f)" % [old_center_x, old_center_y, ROOT_CENTER_X, ROOT_CENTER_Y])
	var offset_x: float = ROOT_CENTER_X - old_center_x
	var offset_y: float = ROOT_CENTER_Y - old_center_y

	for i in count:
		var item: Dictionary = data_manager.call("get_item", i)
		var p2d = item.get("pos2d")
		if p2d is Array and p2d.size() >= 2:
			item["pos2d"] = [float(p2d[0]) + offset_x, float(p2d[1]) + offset_y]
		var rel = item.get("relative_offset")
		if rel is Array and rel.size() >= 2:
			item["relative_offset"] = [float(rel[0]) + offset_x, float(rel[1]) + offset_y]

	data_manager.call("save_data")
	_log("位置迁移完成")


## 构建父子关系的子节点映射缓存
func _build_children_map() -> void:
	_children_map.clear()
	var count: int = data_manager.call("get_count")
	for i in count:
		var item: Dictionary = data_manager.call("get_item", i)
		var parent_id: String = str(item.get("parent_id", ""))
		if not parent_id.is_empty():
			if not _children_map.has(parent_id):
				_children_map[parent_id] = []
			_children_map[parent_id].append(i)


## 从缓存获取指定父节点的子节点索引列表
func _get_children_cached(parent_index: int) -> Array:
	var item: Dictionary = data_manager.call("get_item", parent_index)
	var node_id: String = str(item.get("id", ""))
	return _children_map.get(node_id, [])


## 创建思维导图基础UI结构（滚动容器、画布容器、空状态提示）
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


## 构建相对布局的思维导图，以根节点为中心左右分布子树
func build_mind_map_relative(auto_scroll: bool = true, draw_lines: bool = true) -> void:
	_log("开始构建思维导图 - XMind风格")

	_clear_all()

	var count: int = data_manager.call("get_count")
	if count == 0:
		_show_empty_state()
		return

	_hide_empty_state()

	_build_children_map()

	var depths: Array = data_manager.call("compute_depths")
	var max_depth: int = _get_max_depth(depths)

	var all_root_indices: Array = []
	for i in count:
		var d: int = 0
		if i < depths.size():
			d = depths[i]
		if d == 0:
			all_root_indices.append(i)

	if all_root_indices.is_empty():
		_show_empty_state()
		return

	var main_root_index: int = -1
	var free_nodes: Array = []

	for ri in all_root_indices.size():
		var idx: int = all_root_indices[ri]
		var children: Array = _get_children_cached(idx)
		if main_root_index == -1 and not children.is_empty():
			main_root_index = idx
		elif main_root_index == -1:
			main_root_index = idx
		else:
			free_nodes.append(idx)

	if main_root_index == -1 and not all_root_indices.is_empty():
		main_root_index = all_root_indices[0]

	_main_root_index = main_root_index

	if main_root_index >= 0:
		var item: Dictionary = data_manager.call("get_item", main_root_index)
		if item.has("pos2d"):
			var p2d: Variant = item.get("pos2d")
			if p2d is Array and p2d.size() >= 2:
				var current_x = float(p2d[0])
				var current_y = float(p2d[1])
				if abs(current_x - ROOT_CENTER_X) > 4000 or abs(current_y - ROOT_CENTER_Y) > 4000:
					_log("根节点位置太远，重置到中心: (%.0f, %.0f) → (%.0f, %.0f)" % [current_x, current_y, ROOT_CENTER_X, ROOT_CENTER_Y])
					item["pos2d"] = [ROOT_CENTER_X, ROOT_CENTER_Y]
					item["relative_offset"] = [ROOT_CENTER_X, ROOT_CENTER_Y]
					data_manager.call("save_data")

	var main_center_x: float = ROOT_CENTER_X
	var main_center_y: float = ROOT_CENTER_Y

	if main_root_index >= 0:
		var item: Dictionary = data_manager.call("get_item", main_root_index)
		if item.has("pos2d"):
			var p2d: Variant = item.get("pos2d")
			if p2d is Array and p2d.size() >= 2:
				main_center_x = float(p2d[0])
				main_center_y = float(p2d[1])
				if main_center_x > 10000 or main_center_y > 8000:
					main_center_x = ROOT_CENTER_X
					main_center_y = ROOT_CENTER_Y
					item["pos2d"] = [main_center_x, main_center_y]
					data_manager.call("save_data")
		else:
			main_center_x = ROOT_CENTER_X
			main_center_y = ROOT_CENTER_Y
			item["pos2d"] = [main_center_x, main_center_y]
			if data_manager.has_method("save_data"):
				data_manager.call("save_data")

		_create_relative_node(main_root_index, item, Vector2(main_center_x, main_center_y), 0, true, 0)

		var direct_children: Array = _get_children_cached(main_root_index)
		if not direct_children.is_empty():
			var mid: int = (direct_children.size() + 1) / 2
			var right_children: Array = direct_children.slice(0, mid)
			var left_children: Array = direct_children.slice(mid, direct_children.size())

			var node_height = 50.0
			var base_spacing = 20.0
			var unit_height = max(node_height + base_spacing, vertical_spacing)

			_log("布局单位高度: %.1f, 缩放=%.2f" % [unit_height, zoom_scale])

			_place_child_group(right_children, main_root_index, main_center_x, main_center_y, 1, max_depth, 0, true, unit_height)
			_place_child_group(left_children, main_root_index, main_center_x, main_center_y, 1, max_depth, 0, false, unit_height)

	var root_subtree_bottom: float = main_center_y
	if main_root_index >= 0:
		var direct_children: Array = _get_children_cached(main_root_index)
		if not direct_children.is_empty():
			var right_total: float = 0.0
			var left_total: float = 0.0
			var mid: int = (direct_children.size() + 1) / 2
			for ci in range(mid):
				right_total += _get_subtree_height(direct_children[ci], 2, max_depth, vertical_spacing)
			for ci in range(mid, direct_children.size()):
				left_total += _get_subtree_height(direct_children[ci], 2, max_depth, vertical_spacing)
			var max_subtree: float = max(right_total, left_total)
			root_subtree_bottom = main_center_y + max_subtree / 2.0

	if not free_nodes.is_empty():
		var node_height = 50.0
		var base_spacing = 20.0
		var unit_height = max(node_height + base_spacing, vertical_spacing)

		var free_start_y: float = root_subtree_bottom + unit_height * 2.0

		for fi in free_nodes.size():
			var free_idx: int = free_nodes[fi]
			var item: Dictionary = data_manager.call("get_item", free_idx)

			var fx: float = ROOT_CENTER_X + 800.0
			var fy: float = free_start_y
			var has_saved_pos: bool = false

			if item.has("pos2d"):
				var p2d: Variant = item.get("pos2d")
				if p2d is Array and p2d.size() >= 2:
					fx = float(p2d[0])
					fy = float(p2d[1])
					has_saved_pos = true

			if not has_saved_pos and fy < root_subtree_bottom + unit_height:
				fy = root_subtree_bottom + unit_height

			var free_color_idx: int = (fi + 3) % branch_colors.size()
			_create_relative_node(free_idx, item, Vector2(fx, fy), 0, false, free_color_idx)

			var free_children: Array = _get_children_cached(free_idx)
			if not free_children.is_empty():
				_place_child_group(free_children, free_idx, fx, fy, 1, max_depth, free_color_idx, true, unit_height)

				var free_subtree_h: float = 0.0
				for rc in free_children:
					free_subtree_h += _get_subtree_height(rc, 2, max_depth, unit_height)
				free_start_y = fy + free_subtree_h / 2.0 + unit_height * 2.0
			else:
				free_start_y = fy + unit_height * 2.0

	if draw_lines:
		_draw_tree_lines(free_nodes)
	else:
		_clear_lines()

	_update_container_size()

	if auto_scroll and scroll_container and is_instance_valid(scroll_container):
		call_deferred("_scroll_to_root_center", main_center_x, main_center_y)

	_log("构建完成，节点数量: %d, 自由节点: %d" % [node_controls.size(), free_nodes.size()])


## 滚动视图到根节点中心位置
func _scroll_to_root_center(root_x: float, root_y: float) -> void:
	if not scroll_container or not is_instance_valid(scroll_container):
		return

	if root_node and is_instance_valid(root_node):
		await root_node.get_tree().process_frame

	var viewport_size = scroll_container.size
	var viewport_center = viewport_size / 2

	var scroll_x = root_x * zoom_scale - viewport_center.x
	var scroll_y = root_y * zoom_scale - viewport_center.y

	var max_scroll_x = max(0, container.custom_minimum_size.x - viewport_size.x)
	var max_scroll_y = max(0, container.custom_minimum_size.y - viewport_size.y)
	scroll_x = clamp(scroll_x, 0, max_scroll_x)
	scroll_y = clamp(scroll_y, 0, max_scroll_y)

	scroll_container.scroll_horizontal = scroll_x
	scroll_container.scroll_vertical = scroll_y

	_log("滚动到中心: 视口大小=%s, 节点中心=(%f, %f), 缩放=%.2f, 滚动位置=(%f, %f)" % [
		viewport_size, root_x, root_y, zoom_scale, scroll_x, scroll_y
	])


## 递归计算子树的总高度，用于垂直方向均匀分布
func _get_subtree_height(node_index: int, current_depth: int, max_depth: int, unit_height: float) -> float:
	var sub_children = _get_children_cached(node_index)
	if sub_children.is_empty():
		return unit_height
	if current_depth > max_depth:
		return unit_height * sub_children.size()
	var total_height: float = 0.0
	for child_idx in sub_children:
		total_height += _get_subtree_height(child_idx, current_depth + 1, max_depth, unit_height)
	return max(unit_height * sub_children.size(), total_height)


## 根据深度和是否为中心节点获取固定的节点尺寸
func _get_fixed_node_size(depth: int, is_center: bool) -> Vector2:
	if is_center:
		return center_node_size * zoom_scale
	elif depth <= 1:
		return main_node_size * zoom_scale
	else:
		return (sub_node_size if depth <= 2 else leaf_node_size) * zoom_scale


## 根据文本内容和深度计算节点宽度
func _calculate_node_width(text: String, depth: int, is_center: bool) -> float:
	var fixed_size: Vector2 = _get_fixed_node_size(depth, is_center)
	var font_size: int
	if is_center:
		font_size = int(20 * zoom_scale)
	else:
		font_size = int((16 if depth <= 1 else 14) * zoom_scale)
	var font: Font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var padding: float = 40.0 * zoom_scale
	return max(fixed_size.x, text_width + padding)


## 获取指定节点宽度的一半
func _get_node_half_width(index: int) -> float:
	if node_controls.has(index):
		return node_controls[index].custom_minimum_size.x / 2.0
	return 50.0 * zoom_scale

## 计算子节点相对于父节点的 X 偏移（父边缘 + gap + 子半宽）
func compute_child_x_offset(parent_index: int, child_name: String, child_depth: int, to_right: bool = true) -> float:
	var parent_half_w: float = _get_node_half_width(parent_index)
	var child_w: float = _calculate_node_width(child_name, child_depth, false)
	var direction: float = 1.0 if to_right else -1.0
	return direction * (parent_half_w + horizontal_gap + child_w / 2.0)

## 递归放置一组子节点，计算位置并创建节点控件
func _place_child_group(children: Array, parent_index: int, parent_pos_x: float, parent_pos_y: float, current_depth: int, max_depth: int, color_index: int, is_right_side: bool, vertical_spacing: float = 55.0) -> void:
	if children.is_empty() or current_depth > max_depth:
		return
	var direction: float = 1.0 if is_right_side else -1.0
	var parent_half_w: float = _get_node_half_width(parent_index)
	var subtree_heights: Array = []
	var child_half_widths: Array = []
	var total_height: float = 0.0
	for child_idx in children:
		var h: float = _get_subtree_height(child_idx, current_depth + 1, max_depth, vertical_spacing)
		subtree_heights.append(h)
		total_height += h
		var child_item: Dictionary = data_manager.call("get_item", child_idx)
		var child_w: float = _calculate_node_width(str(child_item.get("name", "")), current_depth, false)
		child_half_widths.append(child_w / 2.0)
	var current_y: float = parent_pos_y - total_height / 2.0
	for ci in children.size():
		var child_idx: int = children[ci]
		if node_controls.has(child_idx):
			current_y += subtree_heights[ci]
			continue
		var child_item: Dictionary = data_manager.call("get_item", child_idx)
		var node_y: float = current_y + subtree_heights[ci] / 2.0
		var node_x: float = parent_pos_x + direction * (parent_half_w + horizontal_gap + child_half_widths[ci])
		_create_relative_node(child_idx, child_item, Vector2(node_x, node_y), current_depth, false, color_index)
		var sub_children: Array = _get_children_cached(child_idx)
		_place_child_group(sub_children, child_idx, node_x, node_y, current_depth + 1, max_depth, color_index, is_right_side, vertical_spacing)
		current_y += subtree_heights[ci]


## 绘制所有节点之间的贝塞尔曲线连线
func _draw_tree_lines(free_node_list: Array) -> void:
	_clear_lines()
	var all_edges: Array = data_manager.call("collect_edges")
	var valid_edges: Array = []
	for item in all_edges:
		var target_idx: int = int(item["to"])
		var source_idx: int = int(item["from"])
		if not free_node_list.has(target_idx):
			valid_edges.append(item)

	for ed in valid_edges:
		var src_idx: int = int(ed["from"])
		var dst_idx: int = int(ed["to"])
		if not node_controls.has(src_idx):
			continue
		if not node_controls.has(dst_idx):
			continue

		var src_panel: PanelContainer = node_controls[src_idx]
		var dst_panel: PanelContainer = node_controls[dst_idx]

		var line: Line2D = Line2D.new()
		line.name = "Line_%d_%d" % [src_idx, dst_idx]
		line.width = 1.8 * zoom_scale
		line.default_color = Color(1.0, 1.0, 1.0, 0.8)
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND

		var from_rect: Rect2 = Rect2(src_panel.position, src_panel.custom_minimum_size)
		var to_rect: Rect2 = Rect2(dst_panel.position, dst_panel.custom_minimum_size)

		var from_center: Vector2 = from_rect.get_center()
		var to_center: Vector2 = to_rect.get_center()

		var start_point: Vector2
		var end_point: Vector2

		if to_center.x > from_center.x:
			start_point = Vector2(from_rect.end.x, from_center.y)
			end_point = Vector2(to_rect.position.x, to_center.y)
		else:
			start_point = Vector2(from_rect.position.x, from_center.y)
			end_point = Vector2(to_rect.end.x, to_center.y)

		var distance: float = abs(end_point.x - start_point.x)
		var control_offset: float = distance * 0.5
		var dir: float = 1.0 if end_point.x > start_point.x else -1.0

		var cp1: Vector2 = Vector2(start_point.x + control_offset * dir, start_point.y)
		var cp2: Vector2 = Vector2(end_point.x - control_offset * dir, end_point.y)

		var steps: int = 8
		for step in range(steps + 1):
			var t: float = float(step) / float(steps)
			var point: Vector2 = _cubic_bezier(start_point, cp1, cp2, end_point, t)
			line.add_point(point)

		container.add_child(line)
		line_controls.append(line)

	for i in line_controls.size():
		container.move_child(line_controls[i], i)


## 创建单个节点的UI控件（面板、标签、颜色条）
func _create_relative_node(index: int, item: Dictionary, base_pos: Vector2, depth: int, is_center: bool, color_index: int) -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Node_%d" % index

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(12 * zoom_scale))
	style.set_border_width_all(int(2 * zoom_scale))
	style.border_color = Color(1, 1, 1)
	style.bg_color = Color(0, 0, 0, 0)
	style.shadow_size = int(4 * zoom_scale)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)

	var node_size: Vector2
	if is_center:
		style.set_corner_radius_all(int(18 * zoom_scale))
		var auto_w: float = _calculate_node_width(str(item.get("name", "")), 0, true)
		node_size = Vector2(auto_w, center_node_size.y * zoom_scale)
	elif depth <= 1:
		var auto_w: float = _calculate_node_width(str(item.get("name", "")), 1, false)
		node_size = Vector2(auto_w, main_node_size.y * zoom_scale)
	else:
		var base_h: float = (sub_node_size.y if depth <= 2 else leaf_node_size.y) * zoom_scale
		var auto_w: float = _calculate_node_width(str(item.get("name", "")), depth, false)
		node_size = Vector2(auto_w, base_h)

	panel.custom_minimum_size = node_size
	panel.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.name = "NodeLabel"
	label.text = str(item.get("name", "节点"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	var font_size: int
	if is_center:
		font_size = int(20 * zoom_scale)
	else:
		font_size = int((16 if depth <= 1 else 14) * zoom_scale)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	panel.add_child(label)

	panel.position = base_pos * zoom_scale - node_size / 2

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
	node_depths[index] = depth
	_node_is_center[index] = is_center


## 三次贝塞尔曲线插值计算
func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3


## 递归收集指定节点的所有子树索引
func _collect_subtree_indices(root_index: int) -> Array:
	var result: Array = [root_index]
	var queue: Array = [root_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		var sub_children: Array = _get_children_cached(current)
		for child_idx in sub_children:
			if not result.has(child_idx):
				result.append(child_idx)
				queue.append(child_idx)
	return result


## 获取深度数组中的最大深度值
func _get_max_depth(depths: Array) -> int:
	var max_d: int = 0
	for d in depths:
		if d > max_d:
			max_d = d
	return max_d


## 更新画布容器尺寸以适配所有节点
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


## 清除所有节点控件和连线
func _clear_all() -> void:
	for key in node_controls.keys():
		var ctrl: Control = node_controls[key]
		if is_instance_valid(ctrl):
			container.remove_child(ctrl)
			ctrl.queue_free()
	node_controls.clear()
	node_items.clear()
	node_depths.clear()
	_node_is_center.clear()
	_main_root_index = -1
	_children_map.clear()

	_clear_lines()


## 清除所有连线控件
func _clear_lines() -> void:
	for line in line_controls:
		if is_instance_valid(line):
			container.remove_child(line)
			line.queue_free()
	line_controls.clear()


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


## 节点GUI输入事件处理，处理点击、双击、右键菜单和拖拽
func _on_node_gui_input(event: InputEvent, index: int) -> void:
	if is_placing_node:
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			request_rename_node.emit(index)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			if Input.is_key_pressed(KEY_CTRL):
				_log("Ctrl+点击节点: %d, 当前选中=%s" % [index, str(selected_indices)])
				select_node(index, true)
				_log("Ctrl+点击后选中=%s" % str(selected_indices))
				node_clicked.emit(index)
				return

			var item_data: Dictionary = node_items[index]
			if str(item_data.get("id", "")) == "root":
				select_node(index, false)
				node_clicked.emit(index)
				return

			is_dragging = true
			drag_node_index = index
			drag_parent_start = node_items[index].get("parent_id", "")

			var panel: PanelContainer = node_controls[index]
			drag_start_pos = panel.position

			var container_mouse_pos = _screen_to_container(mb.global_position)
			drag_offset = container_mouse_pos - panel.position

			drag_subtree_indices = _collect_subtree_indices(index)
			drag_subtree_start_positions.clear()
			for sub_idx in drag_subtree_indices:
				if node_controls.has(sub_idx):
					drag_subtree_start_positions[sub_idx] = node_controls[sub_idx].position

			_create_drag_preview(index)

			if selected_indices.size() > 1 and is_selected(index):
				select_node(index, false)
			elif not is_selected(index):
				select_node(index, false)

			node_clicked.emit(index)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if is_dragging:
				is_dragging = false
				_lines_hidden = false

				var panel: PanelContainer = node_controls[drag_node_index]
				var drag_distance: float = (panel.position - drag_start_pos).length()

				_hide_drag_preview()

				if drag_distance > drag_dead_zone:
					if snap_target_index >= 0 and node_controls.has(snap_target_index):
						var snap_item: Dictionary = data_manager.call("get_item", snap_target_index)
						var item: Dictionary = node_items[drag_node_index]
						if history_manager:
							history_manager.record_operation("移动节点: %s" % str(item.get("name", "")))
						item["parent_id"] = str(snap_item.get("id", ""))
						var snap_galaxy: int = int(snap_item.get("galaxy_id", 0))
						item["galaxy_id"] = snap_galaxy
						for sub_idx in drag_subtree_indices:
							if sub_idx != drag_node_index:
								var sub_item: Dictionary = data_manager.call("get_item", sub_idx)
								sub_item["galaxy_id"] = snap_galaxy
						_log("节点吸附到: %d" % snap_target_index)
					else:
						var item: Dictionary = node_items[drag_node_index]
						if history_manager:
							history_manager.record_operation("移动节点: %s" % str(item.get("name", "")))
						item["parent_id"] = ""
						var max_gid: int = 0
						for i in data_manager.call("get_count"):
							var ex_item: Dictionary = data_manager.call("get_item", i)
							var g: int = int(ex_item.get("galaxy_id", 0))
							if g > max_gid:
								max_gid = g
						var new_galaxy: int = max_gid + 1
						item["galaxy_id"] = new_galaxy
						for sub_idx in drag_subtree_indices:
							if sub_idx != drag_node_index:
								var sub_item: Dictionary = data_manager.call("get_item", sub_idx)
								sub_item["galaxy_id"] = new_galaxy

					for sub_idx in drag_subtree_indices:
						if node_controls.has(sub_idx):
							update_node_relative_position(sub_idx)
					data_manager.call("save_data")
					rebuild()
				else:
					for sub_idx in drag_subtree_indices:
						if node_controls.has(sub_idx) and drag_subtree_start_positions.has(sub_idx):
							node_controls[sub_idx].position = drag_subtree_start_positions[sub_idx]
					for line in line_controls:
						if is_instance_valid(line):
							line.visible = true

				drag_subtree_indices.clear()
				drag_subtree_start_positions.clear()
				snap_target_index = -1
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
		if not _lines_hidden:
			_lines_hidden = true
			for line in line_controls:
				if is_instance_valid(line):
					line.visible = false

		var panel: PanelContainer = node_controls[drag_node_index]

		var container_mouse_pos = _screen_to_container(event.global_position)
		var new_pos: Vector2 = container_mouse_pos - drag_offset
		var delta: Vector2 = new_pos - panel.position
		panel.position = new_pos

		for sub_idx in drag_subtree_indices:
			if sub_idx == drag_node_index:
				continue
			if node_controls.has(sub_idx) and drag_subtree_start_positions.has(sub_idx):
				var sub_panel: PanelContainer = node_controls[sub_idx]
				var orig_offset: Vector2 = drag_subtree_start_positions[sub_idx] - drag_start_pos
				sub_panel.position = panel.position + orig_offset

		_update_drag_preview(panel)

		var closest_index: int = _find_closest_node(panel.position + panel.size / 2, drag_node_index)
		if closest_index >= 0:
			snap_target_index = closest_index
			_show_snap_preview(closest_index, panel)
		else:
			snap_target_index = -1
			_hide_snap_preview()


## 将屏幕坐标转换为画布容器内坐标
func _screen_to_container(global_pos: Vector2) -> Vector2:
	var viewport_pos: Vector2 = global_pos - scroll_container.get_global_position()
	return viewport_pos + Vector2(float(scroll_container.scroll_horizontal), float(scroll_container.scroll_vertical))


## 更新节点的相对位置数据并保存
func update_node_relative_position(node_index: int) -> void:
	if not node_controls.has(node_index):
		return
	var panel: PanelContainer = node_controls[node_index]
	var item: Dictionary = node_items[node_index]

	var node_center = (panel.position + panel.size / 2) / zoom_scale

	if item.get("parent_id", "") != "":
		var parent_index = find_node_index(item.get("parent_id", ""))
		if parent_index >= 0 and node_controls.has(parent_index):
			var parent_panel: PanelContainer = node_controls[parent_index]
			var parent_center = (parent_panel.position + parent_panel.size / 2) / zoom_scale

			item["relative_offset"] = [
				node_center.x - parent_center.x,
				node_center.y - parent_center.y
			]
	else:
		item["relative_offset"] = [node_center.x, node_center.y]
		item["pos2d"] = [node_center.x, node_center.y]


## 通过节点ID查找节点索引
func find_node_index(node_id: String) -> int:
	for i in data_manager.call("get_count"):
		var item: Dictionary = data_manager.call("get_item", i)
		if str(item.get("id", "")) == node_id:
			return i
	return -1


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

		var depth: int = node_depths.get(index, 1)
		var is_center: bool = _node_is_center.get(index, false)

		var label: Label = panel.get_node_or_null("NodeLabel")
		var text_name: String = label.text if label else ""
		var auto_w: float = _calculate_node_width(text_name, depth, is_center)
		var fixed_h: float
		if is_center:
			fixed_h = center_node_size.y * zoom_scale
		elif depth <= 1:
			fixed_h = main_node_size.y * zoom_scale
		else:
			fixed_h = (sub_node_size.y if depth <= 2 else leaf_node_size.y) * zoom_scale
		var node_size: Vector2 = Vector2(auto_w, fixed_h)

		panel.custom_minimum_size = node_size
		panel.size = node_size
		panel.position = base_pos * zoom_scale - node_size / 2.0

		var style: StyleBoxFlat = StyleBoxFlat.new()
		if is_center:
			style.set_corner_radius_all(int(18 * zoom_scale))
		else:
			style.set_corner_radius_all(int(12 * zoom_scale))
		style.set_border_width_all(int(2 * zoom_scale))
		style.border_color = Color(1, 1, 1)
		style.bg_color = Color(0, 0, 0, 0)
		style.shadow_size = int(4 * zoom_scale)
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
		panel.add_theme_stylebox_override("panel", style)

		if label:
			var font_size: int
			if is_center:
				font_size = int(20 * zoom_scale)
			else:
				font_size = int((16 if depth <= 1 else 14) * zoom_scale)
			label.add_theme_font_size_override("font_size", font_size)

		if is_selected(index):
			_update_node_style(index, true, false)
		else:
			_update_node_style(index, false, false)

	_apply_zoom_to_lines()
	_update_container_size()

	_log("缩放属性更新: %.2f→%.2f, 节点数=%d" % [old_zoom, zoom_scale, node_controls.size()])


## 更新所有连线的缩放
func _apply_zoom_to_lines() -> void:
	var all_edges: Array = data_manager.call("collect_edges")
	var valid_edges: Array = []
	for item in all_edges:
		var target_idx: int = int(item["to"])
		var source_idx: int = int(item["from"])
		if node_controls.has(source_idx) and node_controls.has(target_idx):
			valid_edges.append(item)

	var needed_count: int = valid_edges.size()
	var existing_count: int = line_controls.size()

	for i in range(needed_count, existing_count):
		if is_instance_valid(line_controls[i]):
			line_controls[i].queue_free()
	line_controls.resize(needed_count)

	var new_line_count: int = 0
	for i in range(existing_count, needed_count):
		var line: Line2D = Line2D.new()
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.default_color = Color(1.0, 1.0, 1.0, 0.8)
		container.add_child(line)
		line_controls[i] = line
		new_line_count += 1

	if new_line_count > 0:
		var first_line_idx: int = container.get_child_count() - new_line_count
		for i in new_line_count:
			container.move_child(line_controls[existing_count + i], i)

	for i in needed_count:
		var ed: Dictionary = valid_edges[i]
		var src_idx: int = int(ed["from"])
		var dst_idx: int = int(ed["to"])
		var src_panel: PanelContainer = node_controls[src_idx]
		var dst_panel: PanelContainer = node_controls[dst_idx]
		var line: Line2D = line_controls[i]

		line.name = "Line_%d_%d" % [src_idx, dst_idx]
		line.width = 1.8 * zoom_scale

		var from_rect: Rect2 = Rect2(src_panel.position, src_panel.custom_minimum_size)
		var to_rect: Rect2 = Rect2(dst_panel.position, dst_panel.custom_minimum_size)
		var from_center: Vector2 = from_rect.get_center()
		var to_center: Vector2 = to_rect.get_center()

		var start_point: Vector2
		var end_point: Vector2

		if to_center.x > from_center.x:
			start_point = Vector2(from_rect.end.x, from_center.y)
			end_point = Vector2(to_rect.position.x, to_center.y)
		else:
			start_point = Vector2(from_rect.position.x, from_center.y)
			end_point = Vector2(to_rect.end.x, to_center.y)

		var distance: float = abs(end_point.x - start_point.x)
		var control_offset: float = distance * 0.5
		var dir: float = 1.0 if end_point.x > start_point.x else -1.0

		var cp1: Vector2 = Vector2(start_point.x + control_offset * dir, start_point.y)
		var cp2: Vector2 = Vector2(end_point.x - control_offset * dir, end_point.y)

		line.clear_points()
		var steps: int = 8
		for step in range(steps + 1):
			var t: float = float(step) / float(steps)
			var point: Vector2 = _cubic_bezier(start_point, cp1, cp2, end_point, t)
			line.add_point(point)


## 放大视图
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


## 缩放节流超时回调，执行待处理的缩放
func _on_zoom_throttle_timeout() -> void:
	if _zoom_pending:
		var now: int = Time.get_ticks_msec()
		if now - _last_zoom_time >= 150:
			_zoom_pending = false
			_apply_zoom_to_lines()
		else:
			root_node.get_tree().create_timer(0.1).timeout.connect(_on_zoom_throttle_timeout)


## 处理滚动事件（委托给滚动容器输入处理）
func handle_scroll(event: InputEvent) -> void:
	_on_scroll_gui_input(event)


## 滚动容器GUI输入事件处理，处理缩放和节点放置
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


## 更新正在放置的节点的位置跟随鼠标
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


## 完成节点放置，保存位置数据并重建视图
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
		data_manager.call("save_data")

		_log("节点放置完成: %d, 位置=(%.0f, %.0f), 滚动=(%.0f, %.0f)" % [
			placing_node_index, node_center.x, node_center.y,
			float(scroll_container.scroll_horizontal), float(scroll_container.scroll_vertical)
		])
	else:
		_log("节点放置完成: %d (无控件)" % placing_node_index)
	placing_node_index = -1
	rebuild(false)


## 取消节点放置，移除临时节点
func _cancel_placing_node() -> void:
	if not is_placing_node:
		return

	is_placing_node = false
	_skip_next_click = true

	if placing_node_index >= 0:
		data_manager.call("remove_item", placing_node_index)
		data_manager.call("save_data")
	placing_node_index = -1
	rebuild(false)
	_log("取消节点放置")


## 更新节点的视觉样式（选中/悬停状态）
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


## 节点鼠标进入回调，启动悬停计时器
func _on_node_mouse_entered(index: int) -> void:
	_update_node_style(index, is_selected(index), true)
	_start_hover_timer(index)


## 节点鼠标退出回调，取消悬停计时器
func _on_node_mouse_exited(index: int) -> void:
	_update_node_style(index, is_selected(index), false)
	_cancel_hover_timer()
	close_hover_popup()


## 启动悬停延迟计时器
func _start_hover_timer(index: int) -> void:
	_cancel_hover_timer()
	_hover_node_index = index
	_hover_timer = root_node.get_tree().create_timer(_hover_delay)
	_hover_timer.timeout.connect(_on_hover_timeout.bind(index))


## 取消悬停计时器
func _cancel_hover_timer() -> void:
	if _hover_timer and _hover_timer.timeout.is_connected(_on_hover_timeout):
		_hover_timer.timeout.disconnect(_on_hover_timeout)
	_hover_timer = null
	_hover_node_index = -1


## 悬停超时回调，发射悬停显示信号
func _on_hover_timeout(index: int) -> void:
	if _hover_node_index == index and node_controls.has(index):
		request_hover_show.emit(index)
	_hover_timer = null
	_hover_node_index = -1


## 关闭悬停弹窗
func close_hover_popup() -> void:
	if _hover_popup and is_instance_valid(_hover_popup):
		_hover_popup.queue_free()
	_hover_popup = null


## 获取所有根节点索引列表
func _get_all_root_indices() -> Array:
	var all_root_indices: Array = []
	var count: int = data_manager.call("get_count")
	var depths: Array = data_manager.call("compute_depths")

	for i in count:
		var d: int = 0
		if i < depths.size():
			d = depths[i]
		if d == 0:
			all_root_indices.append(i)

	return all_root_indices


## 重置视图到默认缩放和根节点中心
func reset_view() -> void:
	zoom_scale = 1.0

	var viewport_size = scroll_container.size
	var viewport_center = viewport_size / 2

	var root_position = Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)
	var main_root_index = -1
	var all_root_indices = _get_all_root_indices()
	if not all_root_indices.is_empty():
		main_root_index = all_root_indices[0]
		var item = data_manager.call("get_item", main_root_index)
		if item.has("pos2d"):
			var p2d = item.get("pos2d")
			if p2d is Array and p2d.size() >= 2:
				root_position = Vector2(float(p2d[0]), float(p2d[1]))

	rebuild()

	var scroll_x = root_position.x * zoom_scale - viewport_center.x
	var scroll_y = root_position.y * zoom_scale - viewport_center.y

	scroll_x = max(0, scroll_x)
	scroll_y = max(0, scroll_y)

	scroll_container.scroll_horizontal = scroll_x
	scroll_container.scroll_vertical = scroll_y

	_log("重置视图: 视口大小=%s, 根节点位置=%s, 滚动位置=(%f, %f)" % [viewport_size, root_position, scroll_x, scroll_y])


## 重建思维导图视图
func rebuild(auto_scroll: bool = false, draw_lines: bool = true) -> void:
	var saved_scroll_x: float = 0.0
	var saved_scroll_y: float = 0.0
	if scroll_container and is_instance_valid(scroll_container) and not auto_scroll:
		saved_scroll_x = float(scroll_container.scroll_horizontal)
		saved_scroll_y = float(scroll_container.scroll_vertical)
	build_mind_map_relative(auto_scroll, draw_lines)
	if not auto_scroll and scroll_container and is_instance_valid(scroll_container):
		scroll_container.scroll_horizontal = int(saved_scroll_x)
		scroll_container.scroll_vertical = int(saved_scroll_y)
	if is_placing_node and node_controls.has(placing_node_index):
		_update_placing_node_position()
	data_changed.emit()


## 聚焦到指定节点（-1表示根节点）
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


## 上下文菜单动作回调，分发创建、编辑、删除、掌握度等操作
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
					data_manager.call("save_data")
					update_node_style(index, is_selected(index), false)

		"edit_node":
			_log("编辑节点: %d" % index)
			request_edit_node.emit(index)

		"delete_node":
			request_create_node.emit(-2)

		"delete_all_non_root":
			request_create_node.emit(-3)

		"create_node":
			var local_pos: Vector2 = extra if extra is Vector2 else Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)
			create_node_at(local_pos)

		"create_child_node":
			var node_pos: Vector2 = get_node_position(index)
			var x_off: float = compute_child_x_offset(index, "New Node", 1)
			var new_pos: Vector2 = node_pos + Vector2(x_off, 0)
			request_create_node.emit(index, new_pos)

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


## 在指定位置创建新节点，进入放置模式
func create_node_at(position: Vector2) -> void:
	var scroll_before: Vector2 = Vector2(
		float(scroll_container.scroll_horizontal),
		float(scroll_container.scroll_vertical)
	)
	_log("创建浮动节点前: 滚动=(%.0f, %.0f), 缩放=%.2f" % [scroll_before.x, scroll_before.y, zoom_scale])

	var max_galaxy_id: int = 0
	var count: int = data_manager.call("get_count")
	for i in count:
		var existing_item: Dictionary = data_manager.call("get_item", i)
		var gid: int = int(existing_item.get("galaxy_id", 0))
		if gid > max_galaxy_id:
			max_galaxy_id = gid

	var new_item: Dictionary = {
		"id": data_manager.call("generate_unique_id", "new_node"),
		"name": "New Node",
		"description": "",
		"relative_offset": [position.x, position.y],
		"pos2d": [position.x, position.y],
		"parent_id": "",
		"galaxy_id": max_galaxy_id + 1,
		"mastery": 0,
	}

	if history_manager:
		history_manager.record_operation("创建节点: New Node")
	var new_index: int = data_manager.call("add_item", new_item)
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


## 获取鼠标在画布容器中的位置
func get_mouse_container_pos() -> Vector2:
	return last_container_mouse_pos


## 公开接口：更新节点样式
func update_node_style(index: int, is_selected_flag: bool, is_hovered: bool) -> void:
	_update_node_style(index, is_selected_flag, is_hovered)


## 查找距离指定位置最近的节点，排除指定索引
func _find_closest_node(pos: Vector2, exclude_index: int) -> int:
	var closest_index: int = -1
	var min_distance: float = snap_distance * zoom_scale

	for index in node_controls.keys():
		if index == exclude_index:
			continue
		if drag_subtree_indices.has(index):
			continue
		var panel: PanelContainer = node_controls[index]
		var node_pos: Vector2 = panel.position + panel.size / 2.0
		var distance: float = pos.distance_to(node_pos)

		if distance < min_distance:
			min_distance = distance
			closest_index = index

	return closest_index


## 创建拖拽预览线
func _create_drag_preview(index: int) -> void:
	var panel: PanelContainer = node_controls[index]
	panel.modulate = Color(1, 1, 1, 0.7)

	if not drag_preview_line:
		drag_preview_line = Line2D.new()
		drag_preview_line.name = "DragPreviewLine"
		drag_preview_line.width = 1.5 * zoom_scale
		drag_preview_line.default_color = Color(0, 0.7, 1, 0.5)
		drag_preview_line.z_index = 100
		container.add_child(drag_preview_line)


## 更新拖拽预览线的终点位置
func _update_drag_preview(panel: PanelContainer) -> void:
	if drag_preview_line and is_instance_valid(drag_preview_line):
		drag_preview_line.clear_points()
		drag_preview_line.add_point(panel.position + panel.size / 2.0)


## 显示吸附目标预览效果
func _show_snap_preview(target_index: int, drag_panel: PanelContainer) -> void:
	if not node_controls.has(target_index):
		return

	var target_panel: PanelContainer = node_controls[target_index]
	var style: StyleBoxFlat = target_panel.get_theme_stylebox("panel")
	if style:
		var new_style = style.duplicate()
		new_style.border_color = Color(0, 1, 0)
		new_style.set_border_width_all(int(3 * zoom_scale))
		target_panel.add_theme_stylebox_override("panel", new_style)

	if drag_preview_line and is_instance_valid(drag_preview_line):
		drag_preview_line.clear_points()
		var from_pos: Vector2 = target_panel.position + target_panel.size / 2.0
		var to_pos: Vector2 = drag_panel.position + drag_panel.size / 2.0
		drag_preview_line.add_point(from_pos)
		drag_preview_line.add_point(to_pos)


## 隐藏吸附目标预览效果
func _hide_snap_preview() -> void:
	for index in node_controls.keys():
		if is_selected(index):
			_update_node_style(index, true, false)
		else:
			_update_node_style(index, false, false)


## 隐藏拖拽预览线
func _hide_drag_preview() -> void:
	if drag_preview_line and is_instance_valid(drag_preview_line):
		drag_preview_line.queue_free()
		drag_preview_line = null

	if node_controls.has(drag_node_index):
		var panel: PanelContainer = node_controls[drag_node_index]
		panel.modulate = Color(1, 1, 1, 1)

	_hide_snap_preview()