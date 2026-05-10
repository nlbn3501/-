extends RefCounted

const DEBUG_LOG := false

var _debug_logger: RefCounted

## 调试日志输出
func _log(p_msg: String) -> void:
	if DEBUG_LOG:
		var line: String = "[CognitiveMap2D] " + p_msg
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
var _shown_problem_indices: Array = []

const PROBLEM_INDEX_OFFSET: int = 100000

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

# 连线模式状态
var _is_connecting: bool = false
var _connect_from_index: int = -1
var _connect_type: String = ""
var _connect_line: Line2D = null

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
signal request_create_problem(position: Vector2)
signal request_add_related_knowledge(prob_index: int)
signal request_add_relation(prob_index: int)
signal request_open_problem(prob_index: int)
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


## 构建认知导图：题目卡片网格列表（知识节点仅在独立画布中显示）
func build_mind_map_relative(auto_scroll: bool = true) -> void:
	_log("开始构建题目卡片列表")

	_clear_all()

	var prob_count: int = data_manager.call("get_problem_count")
	if prob_count == 0:
		_show_empty_state()
		return

	_hide_empty_state()

	_shown_indices.clear()
	_shown_problem_indices.clear()
	_group_panels.clear()

	_build_groups()

	var cols: int = 5
	var card_w: float = 200.0
	var card_h: float = 60.0
	var gap_x: float = 20.0
	var gap_y: float = 20.0
	var grid_origin: Vector2 = Vector2(ROOT_CENTER_X - 400, ROOT_CENTER_Y - 300)

	var card_index: int = 0
	for pi in prob_count:
		var prob: Dictionary = data_manager.call("get_problem", pi)
		_shown_problem_indices.append(pi)

		var prob_id: String = str(prob.get("id", ""))
		var parent_group: String = data_manager.call("get_group_of_child", prob_id)
		if not parent_group.is_empty():
			continue

		var row: int = card_index / cols
		var col: int = card_index % cols
		var pos: Vector2 = Vector2(
			grid_origin.x + col * (card_w + gap_x),
			grid_origin.y + row * (card_h + gap_y)
		)

		_create_problem_card(pi, prob, pos, [])
		card_index += 1

	_update_container_size()
	_update_group_sizes()

	if auto_scroll and scroll_container and is_instance_valid(scroll_container):
		call_deferred("_scroll_to_center", grid_origin.x, grid_origin.y)

	_log("构建完成，题目: %d" % _shown_problem_indices.size())


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
	panel.z_index = 1

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


const DIFFICULTY_COLORS: Array[Color] = [
	Color(0.4, 0.8, 0.4),
	Color(0.6, 0.85, 0.4),
	Color(1.0, 0.85, 0.3),
	Color(1.0, 0.55, 0.2),
	Color(1.0, 0.25, 0.25),
]

## 题目卡片（网格布局，双击打开编辑对话框）
func _create_problem_card(prob_index: int, prob: Dictionary, base_pos: Vector2, _tags: Array) -> void:
	var virtual_idx: int = prob_index + PROBLEM_INDEX_OFFSET
	var card_w: float = 200.0
	var card_h: float = 60.0
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ProblemCard_%d" % prob_index
	panel.z_index = 1

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(10 * zoom_scale))
	style.set_border_width_all(int(2 * zoom_scale))
	style.border_color = Color(0.4, 0.6, 1.0)
	style.bg_color = Color(0.15, 0.17, 0.22, 0.95)
	style.shadow_size = int(4 * zoom_scale)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
	style.content_margin_left = 10.0 * zoom_scale
	style.content_margin_right = 10.0 * zoom_scale
	style.content_margin_top = 6.0 * zoom_scale
	style.content_margin_bottom = 6.0 * zoom_scale

	panel.custom_minimum_size = Vector2(card_w, card_h) * zoom_scale
	panel.add_theme_stylebox_override("panel", style)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(2 * zoom_scale))

	var title_label: Label = Label.new()
	title_label.text = str(prob.get("title", "题目"))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", int(14 * zoom_scale))
	title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	vbox.add_child(title_label)

	var info_row: HBoxContainer = HBoxContainer.new()
	info_row.add_theme_constant_override("separation", int(8 * zoom_scale))

	var difficulty: int = int(prob.get("difficulty", 0))
	var diff_label: Label = Label.new()
	diff_label.text = "★".repeat(clamp(difficulty, 0, 5))
	var diff_color: Color = DIFFICULTY_COLORS[clamp(difficulty - 1, 0, 4)] if difficulty > 0 else Color(0.5, 0.5, 0.5)
	diff_label.add_theme_font_size_override("font_size", int(11 * zoom_scale))
	diff_label.add_theme_color_override("font_color", diff_color)
	info_row.add_child(diff_label)

	var type_str: String = str(prob.get("type", ""))
	if not type_str.is_empty():
		var type_label: Label = Label.new()
		type_label.text = type_str
		type_label.add_theme_font_size_override("font_size", int(11 * zoom_scale))
		type_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		info_row.add_child(type_label)

	vbox.add_child(info_row)

	panel.add_child(vbox)
	panel.position = base_pos * zoom_scale

	panel.gui_input.connect(_on_card_gui_input.bind(prob_index))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	panel.mouse_entered.connect(func():
		if node_controls.has(virtual_idx):
			var s: StyleBoxFlat = node_controls[virtual_idx].get_theme_stylebox("panel").duplicate()
			s.border_color = Color(0.5, 0.7, 1.0)
			node_controls[virtual_idx].add_theme_stylebox_override("panel", s)
	)
	panel.mouse_exited.connect(func():
		if node_controls.has(virtual_idx):
			var s: StyleBoxFlat = node_controls[virtual_idx].get_theme_stylebox("panel").duplicate()
			s.border_color = Color(0.4, 0.6, 1.0)
			node_controls[virtual_idx].add_theme_stylebox_override("panel", s)
	)

	container.add_child(panel)
	node_controls[virtual_idx] = panel
	node_items[virtual_idx] = prob


## 题目卡片交互：双击打开编辑对话框，右键菜单，拖拽移动/放入组
func _on_card_gui_input(event: InputEvent, prob_index: int) -> void:
	var virtual_idx: int = prob_index + PROBLEM_INDEX_OFFSET

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			request_edit_node.emit(virtual_idx)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			is_dragging = true
			drag_node_index = virtual_idx
			var panel: PanelContainer = node_controls[virtual_idx]
			drag_start_pos = panel.position
			drag_offset = _screen_to_container(mb.global_position) - panel.position
			if not is_selected(virtual_idx):
				select_node(virtual_idx, false)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if is_dragging and drag_node_index == virtual_idx:
				is_dragging = false
				if not _drag_over_group.is_empty():
					var prob: Dictionary = data_manager.call("get_problem", prob_index)
					var prob_id: String = str(prob.get("id", ""))
					_drop_into_group(prob_id, _drag_over_group)
					_drag_over_group = ""
					return
				_drag_over_group = ""
				var panel: PanelContainer = node_controls[virtual_idx]
				var dist: float = (panel.position - drag_start_pos).length()
				if dist > 20.0:
					var item: Dictionary = node_items[virtual_idx]
					if history_manager:
						history_manager.record_operation("移动题目: %s" % str(item.get("title", "")))
					update_node_position(virtual_idx)
					data_manager.call("save_problems")
				else:
					panel.position = drag_start_pos
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if context_menu_manager:
				context_menu_manager.show_card_context_menu(prob_index, mb.global_position)
			return

	elif event is InputEventMouseMotion and is_dragging and drag_node_index == virtual_idx:
		var panel: PanelContainer = node_controls[virtual_idx]
		if is_instance_valid(panel):
			panel.position = _screen_to_container(event.global_position) - drag_offset
			_check_card_group_hover(event.global_position)


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


const RELATION_COLORS: Dictionary = {
	"用到": Color(0.3, 0.6, 1.0),
	"可替换": Color(1.0, 0.6, 0.2),
	"前置": Color(0.3, 0.85, 0.4),
	"延伸": Color(0.7, 0.4, 1.0),
	"自定义": Color(0.5, 0.5, 0.5),
}

const GROUP_COLORS: Array = [
	Color(0.2, 0.35, 0.55, 0.25),
	Color(0.35, 0.2, 0.5, 0.25),
	Color(0.2, 0.45, 0.3, 0.25),
	Color(0.5, 0.35, 0.15, 0.25),
	Color(0.45, 0.15, 0.3, 0.25),
	Color(0.15, 0.4, 0.45, 0.25),
]

var _relation_lines: Array = []
var _group_panels: Dictionary = {}
var _drag_over_group: String = ""


## 主画布只有题目卡片，无需绘制关系线（关系线在独立画布ProblemCanvas中）
func _draw_relation_lines() -> void:
	for line_node in _relation_lines:
		if is_instance_valid(line_node):
			line_node.queue_free()
	_relation_lines.clear()


func _clear_all() -> void:
	for key in node_controls.keys():
		var ctrl: Control = node_controls[key]
		if is_instance_valid(ctrl):
			var parent: Node = ctrl.get_parent()
			if parent and is_instance_valid(parent):
				parent.remove_child(ctrl)
			ctrl.queue_free()
	node_controls.clear()
	node_items.clear()
	for gid in _group_panels:
		var gp: Control = _group_panels[gid]
		if is_instance_valid(gp):
			var parent: Node = gp.get_parent()
			if parent and is_instance_valid(parent):
				parent.remove_child(gp)
			gp.queue_free()
	_group_panels.clear()


## ==================== 组容器 ====================

func _build_groups() -> void:
	var group_count: int = data_manager.call("get_group_count")
	for gi in group_count:
		var g: Dictionary = data_manager.call("get_group", gi)
		var gid: String = str(g.get("id", ""))
		var parent_id: String = str(g.get("parent_id", ""))
		if not parent_id.is_empty():
			continue
		_create_group_panel(g)

func _create_group_panel(g: Dictionary) -> void:
	var gid: String = str(g.get("id", ""))
	var gname: String = str(g.get("name", "组"))
	var pos2d: Array = g.get("pos2d", [3600.0, 2700.0])
	var gsize: Array = g.get("size", [400.0, 300.0])
	var color_idx: int = int(g.get("color_index", 0))
	var collapsed: bool = g.get("collapsed", false)
	var children: Array = g.get("children", [])

	var bg_color: Color = GROUP_COLORS[color_idx % GROUP_COLORS.size()]
	var border_color: Color = Color(bg_color.r + 0.15, bg_color.g + 0.15, bg_color.b + 0.15, 0.6)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "Group_%s" % gid
	panel.z_index = 0

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(12 * zoom_scale))
	style.set_border_width_all(int(2 * zoom_scale))
	style.border_color = border_color
	style.bg_color = bg_color
	style.content_margin_left = 8.0 * zoom_scale
	style.content_margin_right = 8.0 * zoom_scale
	style.content_margin_top = 30.0 * zoom_scale
	style.content_margin_bottom = 8.0 * zoom_scale

	var display_w: float = float(gsize[0]) * zoom_scale
	var display_h: float = float(gsize[1]) * zoom_scale if not collapsed else 40.0 * zoom_scale
	panel.custom_minimum_size = Vector2(display_w, display_h)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(float(pos2d[0]), float(pos2d[1])) * zoom_scale

	var title_bar: HBoxContainer = HBoxContainer.new()
	title_bar.name = "TitleBar"

	var collapse_btn: Button = Button.new()
	collapse_btn.text = "▼" if not collapsed else "▶"
	collapse_btn.flat = true
	collapse_btn.custom_minimum_size = Vector2(24 * zoom_scale, 24 * zoom_scale)
	collapse_btn.add_theme_font_size_override("font_size", int(12 * zoom_scale))
	title_bar.add_child(collapse_btn)

	var title_label: Label = Label.new()
	title_label.text = gname
	title_label.add_theme_font_size_override("font_size", int(14 * zoom_scale))
	title_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	title_bar.add_child(title_label)

	var content: VBoxContainer = VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(10 * zoom_scale))
	content.visible = not collapsed

	for child_id in children:
		if child_id.begins_with("grp_"):
			var child_gi: int = data_manager.call("find_group_by_id", child_id)
			if child_gi >= 0:
				var child_g: Dictionary = data_manager.call("get_group", child_gi)
				_create_group_panel(child_g)
				if _group_panels.has(child_id) and content.visible:
					var child_panel: PanelContainer = _group_panels[child_id]
					if is_instance_valid(child_panel):
						child_panel.get_parent().remove_child(child_panel)
						content.add_child(child_panel)
		else:
			for pi in data_manager.call("get_problem_count"):
				var prob: Dictionary = data_manager.call("get_problem", pi)
				if str(prob.get("id", "")) == child_id:
					var inner_pos: Vector2 = Vector2(0, 0)
					_create_problem_card_in_group(pi, prob, inner_pos, content)
					break

	var wrapper: VBoxContainer = VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", int(4 * zoom_scale))
	wrapper.add_child(title_bar)
	wrapper.add_child(content)
	panel.add_child(wrapper)

	collapse_btn.pressed.connect(func():
		var is_now_collapsed: bool = not content.visible
		g["collapsed"] = is_now_collapsed
		data_manager.call("save_groups")
		rebuild(false)
	)

	panel.gui_input.connect(_on_group_gui_input.bind(gid))

	container.add_child(panel)
	_group_panels[gid] = panel


func _create_problem_card_in_group(prob_index: int, prob: Dictionary, _base_pos: Vector2, parent: Control) -> void:
	var virtual_idx: int = prob_index + PROBLEM_INDEX_OFFSET
	var card_w: float = 180.0
	var card_h: float = 50.0
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ProblemCard_%d" % prob_index
	panel.z_index = 1

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(8 * zoom_scale))
	style.set_border_width_all(int(2 * zoom_scale))
	style.border_color = Color(0.4, 0.6, 1.0)
	style.bg_color = Color(0.15, 0.17, 0.22, 0.95)
	style.content_margin_left = 8.0 * zoom_scale
	style.content_margin_right = 8.0 * zoom_scale
	style.content_margin_top = 4.0 * zoom_scale
	style.content_margin_bottom = 4.0 * zoom_scale

	panel.custom_minimum_size = Vector2(card_w, card_h) * zoom_scale
	panel.add_theme_stylebox_override("panel", style)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(6 * zoom_scale))

	var title_label: Label = Label.new()
	title_label.text = str(prob.get("title", "题目"))
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.add_theme_font_size_override("font_size", int(13 * zoom_scale))
	title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(title_label)

	var type_str: String = str(prob.get("type", ""))
	if not type_str.is_empty():
		var type_label: Label = Label.new()
		type_label.text = type_str
		type_label.add_theme_font_size_override("font_size", int(10 * zoom_scale))
		type_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		hbox.add_child(type_label)

	panel.add_child(hbox)

	panel.gui_input.connect(_on_card_gui_input.bind(prob_index))
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	parent.add_child(panel)
	node_controls[virtual_idx] = panel
	node_items[virtual_idx] = prob


func _on_group_gui_input(event: InputEvent, group_id: String) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_group_context_menu(group_id, mb.global_position)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var panel: PanelContainer = _group_panels.get(group_id)
			if panel:
				is_dragging = true
				drag_node_index = -2
				drag_start_pos = panel.position
				drag_offset = _screen_to_container(mb.global_position) - panel.position
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if is_dragging and drag_node_index == -2:
				is_dragging = false
				var panel: PanelContainer = _group_panels.get(group_id)
				if panel:
					var dist: float = (panel.position - drag_start_pos).length()
					if dist > 20.0:
						var base_pos: Vector2 = panel.position / zoom_scale
						data_manager.call("set_group_prop", group_id, "pos2d", [base_pos.x, base_pos.y])
					else:
						panel.position = drag_start_pos
			return

	elif event is InputEventMouseMotion and is_dragging and drag_node_index == -2:
		var panel: PanelContainer = _group_panels.get(group_id)
		if panel:
			panel.position = _screen_to_container(event.global_position) - drag_offset
			_check_group_hover(event.global_position, group_id)


func _check_group_hover(mouse_global: Vector2, exclude_id: String) -> void:
	var container_pos: Vector2 = _screen_to_container(mouse_global)
	var hovered: String = ""
	for gid in _group_panels:
		if gid == exclude_id:
			continue
		var gp: PanelContainer = _group_panels[gid]
		if not is_instance_valid(gp):
			continue
		var rect: Rect2 = Rect2(gp.position, gp.size)
		if rect.has_point(container_pos):
			hovered = gid
			break

	if _drag_over_group != hovered:
		if not _drag_over_group.is_empty() and _group_panels.has(_drag_over_group):
			var old_gp: PanelContainer = _group_panels[_drag_over_group]
			if is_instance_valid(old_gp):
				var s: StyleBoxFlat = old_gp.get_theme_stylebox("panel").duplicate()
				s.border_color = Color(s.bg_color.r + 0.15, s.bg_color.g + 0.15, s.bg_color.b + 0.15, 0.6)
				old_gp.add_theme_stylebox_override("panel", s)
		_drag_over_group = hovered
		if not hovered.is_empty() and _group_panels.has(hovered):
			var gp: PanelContainer = _group_panels[hovered]
			if is_instance_valid(gp):
				var s: StyleBoxFlat = gp.get_theme_stylebox("panel").duplicate()
				s.border_color = Color(0.3, 0.9, 0.5, 0.9)
				s.set_border_width_all(int(3 * zoom_scale))
				gp.add_theme_stylebox_override("panel", s)


func _show_group_context_menu(group_id: String, mouse_pos: Vector2) -> void:
	var menu: PopupMenu = PopupMenu.new()
	menu.add_item("重命名", 0)
	menu.add_item("删除组", 1)
	menu.add_item("更改颜色", 2)

	menu.index_pressed.connect(func(idx: int):
		match idx:
			0:
				_rename_group_dialog(group_id)
			1:
				data_manager.call("remove_group", group_id)
				rebuild()
			2:
				var gi: int = data_manager.call("find_group_by_id", group_id)
				if gi >= 0:
					var g: Dictionary = data_manager.call("get_group", gi)
					g["color_index"] = (int(g.get("color_index", 0)) + 1) % GROUP_COLORS.size()
					data_manager.call("save_groups")
					rebuild()
		menu.queue_free()
	)
	root_node.add_child(menu)
	menu.position = Vector2i(root_node.get_viewport().get_mouse_position())
	menu.popup()
	menu.grab_focus()
	menu.popup_hide.connect(func():
		if is_instance_valid(menu):
			menu.queue_free()
	)


func _rename_group_dialog(group_id: String) -> void:
	var gi: int = data_manager.call("find_group_by_id", group_id)
	if gi < 0:
		return
	var g: Dictionary = data_manager.call("get_group", gi)

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "重命名组"
	dialog.min_size = Vector2(300, 100)

	var vbox: VBoxContainer = VBoxContainer.new()
	var line_edit: LineEdit = LineEdit.new()
	line_edit.text = str(g.get("name", "组"))
	vbox.add_child(line_edit)
	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		g["name"] = line_edit.text.strip_edges()
		data_manager.call("save_groups")
		dialog.queue_free()
		rebuild()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	root_node.add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()


func _update_group_sizes() -> void:
	await root_node.get_tree().process_frame
	for gid in _group_panels:
		var gp: PanelContainer = _group_panels[gid]
		if not is_instance_valid(gp):
			continue
		var content: VBoxContainer = gp.get_node_or_null("Content") if gp.has_node("Content") else null
		if content and content.visible:
			var min_size: Vector2 = content.get_combined_minimum_size()
			var new_w: float = max(400.0 * zoom_scale, min_size.x + 24.0 * zoom_scale)
			var new_h: float = max(100.0 * zoom_scale, min_size.y + 46.0 * zoom_scale)
			gp.custom_minimum_size = Vector2(new_w, new_h)
			var gi: int = data_manager.call("find_group_by_id", gid)
			if gi >= 0:
				var g: Dictionary = data_manager.call("get_group", gi)
				g["size"] = [new_w / zoom_scale, new_h / zoom_scale]
				data_manager.call("save_groups")


func _drop_into_group(child_id: String, group_id: String) -> void:
	var old_group: String = data_manager.call("get_group_of_child", child_id)
	if not old_group.is_empty():
		data_manager.call("remove_child_from_group", old_group, child_id)
	data_manager.call("add_child_to_group", group_id, child_id)
	rebuild()


func _create_group_dialog(pos: Vector2) -> void:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "创建组"
	dialog.min_size = Vector2(300, 100)

	var vbox: VBoxContainer = VBoxContainer.new()
	var line_edit: LineEdit = LineEdit.new()
	line_edit.placeholder_text = "组名称"
	vbox.add_child(line_edit)
	dialog.add_child(vbox)

	dialog.confirmed.connect(func():
		var gname: String = line_edit.text.strip_edges()
		if gname.is_empty():
			gname = "新组"
		data_manager.call("add_group", gname, [pos.x, pos.y])
		dialog.queue_free()
		rebuild()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	root_node.add_child(dialog)
	dialog.popup_centered()
	line_edit.grab_focus()


func _check_card_group_hover(mouse_global: Vector2) -> void:
	var container_pos: Vector2 = _screen_to_container(mouse_global)
	var hovered: String = ""
	for gid in _group_panels:
		var gp: PanelContainer = _group_panels[gid]
		if not is_instance_valid(gp):
			continue
		var rect: Rect2 = Rect2(gp.position, gp.size)
		if rect.has_point(container_pos):
			hovered = gid
			break

	if _drag_over_group != hovered:
		if not _drag_over_group.is_empty() and _group_panels.has(_drag_over_group):
			var old_gp: PanelContainer = _group_panels[_drag_over_group]
			if is_instance_valid(old_gp):
				var s: StyleBoxFlat = old_gp.get_theme_stylebox("panel").duplicate()
				s.border_color = Color(s.bg_color.r + 0.15, s.bg_color.g + 0.15, s.bg_color.b + 0.15, 0.6)
				s.set_border_width_all(int(2 * zoom_scale))
				old_gp.add_theme_stylebox_override("panel", s)
		_drag_over_group = hovered
		if not hovered.is_empty() and _group_panels.has(hovered):
			var gp: PanelContainer = _group_panels[hovered]
			if is_instance_valid(gp):
				var s: StyleBoxFlat = gp.get_theme_stylebox("panel").duplicate()
				s.border_color = Color(0.3, 0.9, 0.5, 0.9)
				s.set_border_width_all(int(3 * zoom_scale))
				gp.add_theme_stylebox_override("panel", s)


## 显示空数据状态提示
func _show_empty_state() -> void:
	if _empty_hint != null:
		return

	_empty_hint = Label.new()
	_empty_hint.text = "右键点击此处新建题目\n或按 Ctrl+N 快速创建题目"
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
	_draw_relation_lines()


## 取消所有节点的选中状态
func deselect_all() -> void:
	for si in selected_indices:
		if node_controls.has(si):
			_update_node_style(si, false, false)
	selected_indices.clear()
	_draw_relation_lines()


## 节点GUI输入事件处理
func _on_node_gui_input(event: InputEvent, index: int) -> void:
	if is_placing_node:
		return

	# 连线模式：左键点击目标节点完成连线
	if _is_connecting and event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if index != _connect_from_index:
				_finish_relation_line(index)
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_relation_line()
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

				if not _drag_over_group.is_empty():
					var prob_idx: int = drag_node_index - PROBLEM_INDEX_OFFSET
					if prob_idx >= 0:
						var prob: Dictionary = data_manager.call("get_problem", prob_idx)
						var prob_id: String = str(prob.get("id", ""))
						_drop_into_group(prob_id, _drag_over_group)
					_drag_over_group = ""
					return
				_drag_over_group = ""

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

	elif event is InputEventMouseMotion and is_dragging and drag_node_index >= 0:
		var panel: PanelContainer = node_controls[drag_node_index]

		var container_mouse_pos = _screen_to_container(event.global_position)
		var new_pos: Vector2 = container_mouse_pos - drag_offset
		panel.position = new_pos
		_draw_relation_lines()
		_check_card_group_hover(event.global_position)


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


## 缩放变更时更新所有题目卡片位置和尺寸
func _apply_zoom_update(old_zoom: float) -> void:
	if node_controls.is_empty() and _group_panels.is_empty():
		return

	for index in node_controls.keys():
		var panel: PanelContainer = node_controls[index]
		if not is_instance_valid(panel):
			continue

		var is_in_group: bool = panel.get_parent() != container
		var card_w: float = 180.0 if is_in_group else 200.0
		var card_h: float = 50.0 if is_in_group else 60.0

		var old_center: Vector2 = panel.position + panel.custom_minimum_size / 2.0
		var base_pos: Vector2 = old_center / old_zoom
		var scaled_size: Vector2 = Vector2(card_w, card_h) * zoom_scale

		panel.custom_minimum_size = scaled_size
		panel.size = scaled_size
		panel.position = base_pos * zoom_scale - scaled_size / 2.0

		if is_in_group:
			var hbox_inner: HBoxContainer = panel.get_child(0) as HBoxContainer if panel.get_child_count() > 0 else null
			if hbox_inner:
				hbox_inner.add_theme_constant_override("separation", int(6 * zoom_scale))
				for child in hbox_inner.get_children():
					if child is Label:
						var fs: int = int(13 * zoom_scale) if child.size_flags_horizontal == Control.SIZE_EXPAND_FILL else int(10 * zoom_scale)
						child.add_theme_font_size_override("font_size", fs)

			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.set_corner_radius_all(int(8 * zoom_scale))
			style.set_border_width_all(int(2 * zoom_scale))
			style.border_color = Color(0.4, 0.6, 1.0)
			style.bg_color = Color(0.15, 0.17, 0.22, 0.95)
			style.content_margin_left = 8.0 * zoom_scale
			style.content_margin_right = 8.0 * zoom_scale
			style.content_margin_top = 4.0 * zoom_scale
			style.content_margin_bottom = 4.0 * zoom_scale
			panel.add_theme_stylebox_override("panel", style)
		else:
			var vbox_inner: VBoxContainer = panel.get_child(0) as VBoxContainer if panel.get_child_count() > 0 else null
			if vbox_inner:
				vbox_inner.add_theme_constant_override("separation", int(2 * zoom_scale))
				for child in vbox_inner.get_children():
					if child is Label:
						child.add_theme_font_size_override("font_size", int(14 * zoom_scale))
					elif child is HBoxContainer:
						for sub in child.get_children():
							if sub is Label:
								sub.add_theme_font_size_override("font_size", int(11 * zoom_scale))

			var style: StyleBoxFlat = StyleBoxFlat.new()
			style.set_corner_radius_all(int(10 * zoom_scale))
			style.set_border_width_all(int(2 * zoom_scale))
			style.border_color = Color(0.4, 0.6, 1.0)
			style.bg_color = Color(0.15, 0.17, 0.22, 0.95)
			style.shadow_size = int(4 * zoom_scale)
			style.shadow_color = Color(0.0, 0.0, 0.0, 0.3)
			style.content_margin_left = 10.0 * zoom_scale
			style.content_margin_right = 10.0 * zoom_scale
			style.content_margin_top = 6.0 * zoom_scale
			style.content_margin_bottom = 6.0 * zoom_scale
			panel.add_theme_stylebox_override("panel", style)

	for gid in _group_panels:
		var gp: PanelContainer = _group_panels[gid]
		if not is_instance_valid(gp):
			continue

		var old_center: Vector2 = gp.position + gp.custom_minimum_size / 2.0
		var base_pos: Vector2 = old_center / old_zoom

		var gi: int = data_manager.call("find_group_by_id", gid)
		if gi < 0:
			continue
		var g: Dictionary = data_manager.call("get_group", gi)
		var gsize: Array = g.get("size", [400.0, 300.0])
		var collapsed: bool = g.get("collapsed", false)
		var color_idx: int = int(g.get("color_index", 0))
		var bg_color: Color = GROUP_COLORS[color_idx % GROUP_COLORS.size()]
		var border_color: Color = Color(bg_color.r + 0.15, bg_color.g + 0.15, bg_color.b + 0.15, 0.6)

		var display_w: float = float(gsize[0]) * zoom_scale
		var display_h: float = float(gsize[1]) * zoom_scale if not collapsed else 40.0 * zoom_scale
		var new_size: Vector2 = Vector2(display_w, display_h)

		gp.custom_minimum_size = new_size
		gp.size = new_size
		gp.position = base_pos * zoom_scale - new_size / 2.0

		var style: StyleBoxFlat = gp.get_theme_stylebox("panel").duplicate()
		style.set_corner_radius_all(int(12 * zoom_scale))
		style.set_border_width_all(int(2 * zoom_scale))
		style.border_color = border_color
		style.content_margin_left = 8.0 * zoom_scale
		style.content_margin_right = 8.0 * zoom_scale
		style.content_margin_top = 30.0 * zoom_scale
		style.content_margin_bottom = 8.0 * zoom_scale
		gp.add_theme_stylebox_override("panel", style)

		var title_bar: HBoxContainer = gp.get_node_or_null("TitleBar") if gp.has_node("TitleBar") else null
		if title_bar:
			for child in title_bar.get_children():
				if child is Button:
					child.custom_minimum_size = Vector2(24 * zoom_scale, 24 * zoom_scale)
					child.add_theme_font_size_override("font_size", int(12 * zoom_scale))
				elif child is Label:
					child.add_theme_font_size_override("font_size", int(14 * zoom_scale))

	_update_container_size()


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

		if _is_connecting:
			_update_connect_line()

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
		if _is_connecting:
			_cancel_relation_line()
			return
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
			if index >= PROBLEM_INDEX_OFFSET:
				request_edit_node.emit(index)
			else:
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

		"remove_from_group":
			if index >= PROBLEM_INDEX_OFFSET:
				var prob_idx: int = index - PROBLEM_INDEX_OFFSET
				var prob: Dictionary = data_manager.call("get_problem", prob_idx)
				var prob_id: String = str(prob.get("id", ""))
				var old_group: String = data_manager.call("get_group_of_child", prob_id)
				if not old_group.is_empty():
					data_manager.call("remove_child_from_group", old_group, prob_id)
					rebuild()

		"create_problem":
			var local_pos: Vector2 = extra if extra is Vector2 else Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)
			request_create_problem.emit(local_pos)

		"create_group":
			var local_pos: Vector2 = extra if extra is Vector2 else Vector2(ROOT_CENTER_X, ROOT_CENTER_Y)
			_create_group_dialog(local_pos)

		"add_node_show":
			_show_add_node_dialog()

		"open_canvas":
			# 卡片模式：index 是纯 prob_index
			request_open_problem.emit(index)

		"delete_problem":
			if index >= PROBLEM_INDEX_OFFSET:
				var prob_idx: int = index - PROBLEM_INDEX_OFFSET
				data_manager.call("remove_relations_of_problem", data_manager.call("get_problem", prob_idx).get("id", ""))
				data_manager.call("remove_problem", prob_idx)
				rebuild()
			else:
				# 卡片模式：index 是纯 prob_index
				data_manager.call("remove_relations_of_problem", data_manager.call("get_problem", index).get("id", ""))
				data_manager.call("remove_problem", index)
				rebuild()

		"refresh":
			data_manager.call("load_data")
			data_manager.call("load_problems")
			data_manager.call("load_relations")
			rebuild()

		"reset_view":
			reset_view()

		"auto_layout":
			_run_force_layout()

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


## 显示指定节点（设visible标记后rebuild，仅当节点尚未显示时）
func _show_node(index: int) -> void:
	if _shown_indices.has(index):
		return
	var item: Dictionary = data_manager.call("get_item", index)
	item["visible_in_2dtr"] = true
	data_manager.call("save_data")
	rebuild(false)


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
	dialog.title = "添加知识点到视图"
	dialog.min_size = Vector2(460, 460)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var search_label: Label = Label.new()
	search_label.text = "搜索知识点（可多选）:"
	vbox.add_child(search_label)

	var search_box: LineEdit = LineEdit.new()
	search_box.placeholder_text = "输入关键词搜索..."
	search_box.clear_button_enabled = true
	vbox.add_child(search_box)

	var item_list: ItemList = ItemList.new()
	item_list.name = "NodeList"
	item_list.select_mode = ItemList.SELECT_MULTI
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.custom_minimum_size = Vector2(420, 300)
	vbox.add_child(item_list)

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

	dialog.add_child(vbox)
	root_node.add_child(dialog)

	dialog.confirmed.connect(func():
		_place_queue.clear()

		for idx in selected_real.keys():
			if not _place_queue.has(idx):
				var sel_item: Dictionary = data_manager.call("get_item", idx)
				sel_item["visible_in_2dtr"] = true
				_place_queue.append(idx)
		data_manager.call("save_data")

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


## 力导向自动布局：基于节点间斥力和连线弹簧力迭代计算最终位置
func _run_force_layout() -> void:
	if node_controls.is_empty():
		return

	# 分离题目节点和知识节点
	var problem_keys: Array = []
	var knowledge_keys: Array = []

	for key in node_controls.keys():
		if not is_instance_valid(node_controls[key]):
			continue
		if key >= PROBLEM_INDEX_OFFSET:
			problem_keys.append(key)
		else:
			knowledge_keys.append(key)

	if problem_keys.is_empty() and knowledge_keys.is_empty():
		return

	# 收集连线关系
	var edges: Array = []
	var all_relations: Array = data_manager.call("get_all_relations")
	var relation_count: Dictionary = {}  # 每个知识节点的关系数

	for rel in all_relations:
		var problem_id: String = str(rel.get("problem_id", ""))
		var target_name: String = str(rel.get("target", ""))
		var prob_idx: int = -1
		for pi in _shown_problem_indices:
			var p: Dictionary = data_manager.call("get_problem", pi)
			if str(p.get("id", "")) == problem_id:
				prob_idx = pi
				break
		if prob_idx < 0:
			continue
		var prob_virtual: int = prob_idx + PROBLEM_INDEX_OFFSET
		var target_idx: int = data_manager.call("find_by_name", target_name)
		if target_idx < 0:
			continue
		edges.append([prob_virtual, target_idx])
		if not relation_count.has(target_idx):
			relation_count[target_idx] = 0
		relation_count[target_idx] += 1

	var canvas_w: float = MAP_WIDTH
	var canvas_h: float = MAP_HEIGHT
	var positions: Dictionary = {}

	# 题目节点均匀分布在底部一行
	var problem_row_y: float = canvas_h - 150.0
	var problem_spacing: float = 200.0
	var problems_start_x: float = (canvas_w - problem_spacing * (problem_keys.size() - 1)) / 2.0

	for i in problem_keys.size():
		positions[problem_keys[i]] = Vector2(problems_start_x + i * problem_spacing, problem_row_y)

	# 知识节点按关系数排序，关系多的排前面
	knowledge_keys.sort_custom(func(a, b):
		return relation_count.get(a, 0) > relation_count.get(b, 0)
	)

	# 计算每个知识节点的X中心（引用它的题目X的平均值）
	var knowledge_center_x: Dictionary = {}
	for ek in knowledge_keys:
		knowledge_center_x[ek] = []

	for edge in edges:
		if positions.has(edge[0]) and knowledge_center_x.has(edge[1]):
			knowledge_center_x[edge[1]].append(positions[edge[0]].x)

	for ek in knowledge_keys:
		if knowledge_center_x[ek].size() > 0:
			var avg: float = 0.0
			for x in knowledge_center_x[ek]:
				avg += x
			knowledge_center_x[ek] = avg / knowledge_center_x[ek].size()
		else:
			knowledge_center_x[ek] = canvas_w / 2.0

	# 多行网格布局：每行最多6个，行间间距，每行水平对齐
	var nodes_per_row: int = 6
	var row_spacing: float = 120.0
	var node_spacing: float = 160.0
	var top_margin: float = 120.0

	for i in knowledge_keys.size():
		var row: int = i / nodes_per_row
		var col: int = i % nodes_per_row
		var nodes_in_row: int = min(nodes_per_row, knowledge_keys.size() - row * nodes_per_row)
		
		# 每行居中
		var row_width: float = node_spacing * (nodes_in_row - 1)
		var row_start_x: float = (canvas_w - row_width) / 2.0
		
		# 奇数行偏移，形成交错布局
		var offset_x: float = 0.0
		if row % 2 == 1:
			offset_x = node_spacing * 0.5
		
		var x: float = row_start_x + col * node_spacing + offset_x
		var y: float = top_margin + row * row_spacing
		
		# 微调：向引用中心靠拢
		var center_pull: float = 0.15
		x = x * (1.0 - center_pull) + knowledge_center_x[knowledge_keys[i]] * center_pull
		
		positions[knowledge_keys[i]] = Vector2(x, y)

	# 应用结果到面板
	for key in node_controls.keys():
		if not positions.has(key):
			continue
		var panel: PanelContainer = node_controls[key]
		if not is_instance_valid(panel):
			continue
		var new_center: Vector2 = positions[key]
		panel.position = new_center * zoom_scale - panel.size / 2.0

		if key >= PROBLEM_INDEX_OFFSET:
			var prob_idx: int = key - PROBLEM_INDEX_OFFSET
			var prob: Dictionary = data_manager.call("get_problem", prob_idx)
			if not prob.is_empty():
				prob["pos2d"] = [new_center.x, new_center.y]
				data_manager.call("save_problems")
		else:
			var item: Dictionary = data_manager.call("get_item", key)
			if not item.is_empty():
				item["pos2d"] = [new_center.x, new_center.y]
				data_manager.call("save_data")

	_update_container_size()
	_draw_relation_lines()
	_log("自动布局完成: %d 题目, %d 知识点" % [problem_keys.size(), knowledge_keys.size()])


## ==================== 连线模式 ====================

const CONNECT_LINE_COLOR: Dictionary = {
	"用到": Color(0.3, 0.6, 1.0),
	"可替换": Color(1.0, 0.6, 0.2),
	"前置": Color(0.3, 0.85, 0.4),
	"延伸": Color(0.7, 0.4, 1.0),
}

## 进入连线模式：从指定题目节点开始，跟踪鼠标绘制临时连线
func _start_relation_line(from_index: int, rel_type: String) -> void:
	_is_connecting = true
	_connect_from_index = from_index
	_connect_type = rel_type

	_connect_line = Line2D.new()
	_connect_line.name = "ConnectLine"
	_connect_line.width = 3.0 * zoom_scale
	_connect_line.default_color = CONNECT_LINE_COLOR.get(rel_type, Color(1, 1, 1))
	_connect_line.add_point(Vector2.ZERO)
	_connect_line.add_point(Vector2.ZERO)
	_connect_line.z_index = 100
	container.add_child(_connect_line)

	_log("连线模式开始: 从题目 %d, 类型=%s" % [from_index, rel_type])


## 每帧更新临时连线的鼠标端位置
func _update_connect_line() -> void:
	if not _is_connecting or not _connect_line:
		return
	if not node_controls.has(_connect_from_index):
		_cancel_relation_line()
		return

	var from_panel: PanelContainer = node_controls[_connect_from_index]
	var from_center: Vector2 = from_panel.position + from_panel.size / 2.0

	var global_pos: Vector2 = root_node.get_viewport().get_mouse_position()
	var container_mouse_pos = _screen_to_container(global_pos)

	_connect_line.set_point_position(0, from_center)
	_connect_line.set_point_position(1, container_mouse_pos)


## 点击目标节点完成连线，创建关系并自动添加知识点到视图
func _finish_relation_line(target_index: int) -> void:
	if not _is_connecting:
		return

	var from_virtual: int = _connect_from_index
	var prob_real_index: int = from_virtual - PROBLEM_INDEX_OFFSET
	var prob: Dictionary = data_manager.call("get_problem", prob_real_index)
	if prob.is_empty():
		_cancel_relation_line()
		return
	var problem_id: String = str(prob.get("id", ""))

	var target_item: Dictionary = data_manager.call("get_item", target_index)
	var target_name: String = str(target_item.get("name", ""))
	if target_name.is_empty():
		_cancel_relation_line()
		return

	# 创建关系（覆盖：如果同题目同目标已有关系，先删除旧关系）
	var existing_rels: Array = data_manager.call("get_relations_of_problem", problem_id)
	for rel in existing_rels:
		if str(rel.get("target", "")) == target_name:
			data_manager.call("remove_relation", str(rel.get("id", "")))
	data_manager.call("add_relation", problem_id, target_name, _connect_type)

	# 自动添加知识点到视图
	target_item["visible_in_2dtr"] = true
	data_manager.call("save_data")

	# 清理连线模式状态
	_is_connecting = false
	_connect_from_index = -1
	_connect_type = ""
	if _connect_line and is_instance_valid(_connect_line):
		_connect_line.queue_free()
		_connect_line = null

	# 刷新视图
	rebuild()
	_log("关系创建完成: %s → %s, 类型=%s" % [problem_id, target_name, _connect_type])


## 取消连线模式
func _cancel_relation_line() -> void:
	_is_connecting = false
	_connect_from_index = -1
	_connect_type = ""
	if _connect_line and is_instance_valid(_connect_line):
		_connect_line.queue_free()
		_connect_line = null
	_log("连线模式取消")
