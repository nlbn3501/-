## 题目独立关系画布：左右布局（前置知识 / 题目 / 用到的知识点）
## 全功能版：缩放、平移、选中/多选、拖拽、双击编辑、上下文菜单、
## 连线模式、自动布局、历史记录、截图、空状态提示
extends Control

var prob_index: int = -1
var prob_data: Dictionary = {}
var cog_data: RefCounted = null
var data_manager: RefCounted = null
var history_manager: RefCounted = null

var _scroll: ScrollContainer = null
var _container: Control = null
var _lines: Array = []
var _knowledge_panels: Dictionary = {}  # rel_id -> PanelContainer
var _rel_data: Dictionary = {}          # rel_id -> {name, type, id}

# 缩放系统
var zoom_scale: float = 1.0
var min_zoom: float = 0.3
var max_zoom: float = 3.0
var zoom_speed: float = 0.05
var _zoom_pending: bool = false
var _last_zoom_time: int = 0

# 拖拽系统
var _is_dragging: bool = false
var _drag_rel_id: String = ""
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO

# 中键平移
var _is_panning: bool = false

# 选中系统
var selected_rel_ids: Array = []

# 连线模式
var _is_connecting: bool = false
var _connect_type: String = ""
var _connect_line: Line2D = null

# 放置模式
var is_placing_node: bool = false
var _placing_panel: PanelContainer = null
var _place_queue: Array = []
var _skip_next_click: bool = false

var _empty_hint: Label = null

signal request_back()
signal request_screenshot()

const BASE_CANVAS_W: float = 2400.0
const BASE_CANVAS_H: float = 1600.0
const CENTER_X: float = 1200.0
const CENTER_Y: float = 800.0
const NODE_SIZE: Vector2 = Vector2(140, 50)
const PROBLEM_SIZE: Vector2 = Vector2(210, 75)
const VERTICAL_SPACING: float = 60.0
const LEFT_OFFSET: float = 400.0
const RIGHT_OFFSET: float = 400.0

const RELATION_COLORS: Dictionary = {
	"用到": Color(0.3, 0.6, 1.0),
	"可替换": Color(1.0, 0.6, 0.2),
	"前置": Color(0.3, 0.85, 0.4),
	"延伸": Color(0.7, 0.4, 1.0),
	"自定义": Color(0.5, 0.5, 0.5),
}


func _init(p_prob_index: int, p_cog_data: RefCounted, p_data_manager: RefCounted) -> void:
	prob_index = p_prob_index
	cog_data = p_cog_data
	data_manager = p_data_manager
	prob_data = cog_data.call("get_problem", prob_index)


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
	_build_canvas()
	_center_on_problem.call_deferred()


func _process(_delta: float) -> void:
	if is_placing_node and _placing_panel and is_instance_valid(_placing_panel):
		var global_pos: Vector2 = get_viewport().get_mouse_position()
		var cp: Vector2 = _screen_to_container(global_pos)
		_placing_panel.position = cp - _placing_panel.custom_minimum_size / 2.0


# ==================== UI ====================

func _build_ui() -> void:
	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.custom_minimum_size = Vector2(0, 40)
	add_child(top_bar)

	var back_btn: Button = Button.new()
	back_btn.text = "< 返回"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(func(): request_back.emit())
	top_bar.add_child(back_btn)

	var title_label: Label = Label.new()
	title_label.text = str(prob_data.get("title", "题目"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(title_label)

	var difficulty: int = int(prob_data.get("difficulty", 1))
	var diff_label: Label = Label.new()
	diff_label.text = "★".repeat(clamp(difficulty, 1, 5))
	var diff_colors: Array[Color] = [
		Color(0.4, 0.8, 0.4), Color(0.6, 0.85, 0.4), Color(1.0, 0.85, 0.3),
		Color(1.0, 0.55, 0.2), Color(1.0, 0.25, 0.25),
	]
	diff_label.add_theme_color_override("font_color", diff_colors[clamp(difficulty - 1, 0, 4)])
	top_bar.add_child(diff_label)

	var type_label: Label = Label.new()
	type_label.text = str(prob_data.get("type", ""))
	type_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	top_bar.add_child(type_label)

	var zoom_in_btn: Button = Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.focus_mode = Control.FOCUS_NONE
	zoom_in_btn.pressed.connect(func(): _apply_button_zoom(min(max_zoom, zoom_scale + zoom_speed)))
	top_bar.add_child(zoom_in_btn)

	var zoom_out_btn: Button = Button.new()
	zoom_out_btn.text = "-"
	zoom_out_btn.focus_mode = Control.FOCUS_NONE
	zoom_out_btn.pressed.connect(func(): _apply_button_zoom(max(min_zoom, zoom_scale - zoom_speed)))
	top_bar.add_child(zoom_out_btn)

	var zoom_label: Label = Label.new()
	zoom_label.name = "ZoomLabel"
	zoom_label.text = "100%"
	zoom_label.custom_minimum_size = Vector2(50, 0)
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(zoom_label)

	_scroll = ScrollContainer.new()
	_scroll.name = "CanvasScroll"
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_top = 40
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll_bg: StyleBoxFlat = StyleBoxFlat.new()
	scroll_bg.bg_color = Color(0.06, 0.07, 0.1)
	_scroll.add_theme_stylebox_override("panel", scroll_bg)

	_container = Control.new()
	_container.name = "CanvasContainer"
	_container.custom_minimum_size = Vector2(BASE_CANVAS_W, BASE_CANVAS_H)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_container)

	add_child(_scroll)
	_scroll.gui_input.connect(_on_scroll_gui_input)


# ==================== 画布构建 ====================

func _build_canvas() -> void:
	_clear_canvas()

	var problem_id: String = str(prob_data.get("id", ""))
	var relations: Array = cog_data.call("get_relations_of_problem", problem_id)

	var used_targets: Array = []
	var prereq_targets: Array = []

	for rel in relations:
		var target_name: String = str(rel.get("target", ""))
		var rel_type: String = str(rel.get("type", "用到")).strip_edges()
		var rel_id: String = str(rel.get("id", ""))
		if target_name.is_empty():
			continue
		var dm_idx: int = data_manager.call("find_by_name", target_name)
		if dm_idx < 0:
			continue
		var entry: Dictionary = {"name": target_name, "type": rel_type, "id": rel_id}
		if rel.has("pos2d"):
			entry["pos2d"] = rel["pos2d"]
		_rel_data[rel_id] = entry
		if rel_type == "前置":
			prereq_targets.append(entry)
		else:
			used_targets.append(entry)

	var ns: Vector2 = NODE_SIZE * zoom_scale
	var ps: Vector2 = PROBLEM_SIZE * zoom_scale
	var cx: float = CENTER_X * zoom_scale
	var cy: float = CENTER_Y * zoom_scale

	# 中区：题目卡片
	var problem_panel: PanelContainer = _create_panel(
		str(prob_data.get("title", "题目")), ps,
		Color(0.15, 0.17, 0.22, 0.95), Color(0.4, 0.6, 1.0))
	problem_panel.position = Vector2(cx - ps.x / 2.0, cy - ps.y / 2.0)
	_container.add_child(problem_panel)

	# 左区：前置知识（右边缘→题目左边缘）
	var left_x: float = (CENTER_X - LEFT_OFFSET) * zoom_scale
	var left_total_h: float = prereq_targets.size() * ns.y + max(0, prereq_targets.size() - 1) * VERTICAL_SPACING * zoom_scale
	var left_y_start: float = cy - left_total_h / 2.0
	for i in prereq_targets.size():
		var t = prereq_targets[i]
		var panel: PanelContainer = _create_knowledge_panel(t["name"], t["type"], t["id"])
		var stored: Vector2 = _get_stored_pos(t["id"], zoom_scale)
		if stored != Vector2.ZERO:
			panel.position = stored - ns / 2.0
		else:
			panel.position = Vector2(left_x - ns.x / 2.0, left_y_start + i * (ns.y + VERTICAL_SPACING * zoom_scale))
		_container.add_child(panel)
		_knowledge_panels[t["id"]] = panel

	# 右区：用到/延伸（题目右边缘→知识节点左边缘）
	var right_x: float = (CENTER_X + RIGHT_OFFSET) * zoom_scale
	var right_total_h: float = used_targets.size() * ns.y + max(0, used_targets.size() - 1) * VERTICAL_SPACING * zoom_scale
	var right_y_start: float = cy - right_total_h / 2.0
	for i in used_targets.size():
		var t = used_targets[i]
		var panel: PanelContainer = _create_knowledge_panel(t["name"], t["type"], t["id"])
		var stored: Vector2 = _get_stored_pos(t["id"], zoom_scale)
		if stored != Vector2.ZERO:
			panel.position = stored - ns / 2.0
		else:
			panel.position = Vector2(right_x - ns.x / 2.0, right_y_start + i * (ns.y + VERTICAL_SPACING * zoom_scale))
		_container.add_child(panel)
		_knowledge_panels[t["id"]] = panel

	# 画连线（使用 panel.position 已经是缩放后的坐标）
	for t in prereq_targets:
		if _knowledge_panels.has(t["id"]):
			_draw_bezier_line(_knowledge_panels[t["id"]], problem_panel, t["type"], true)

	for t in used_targets:
		if _knowledge_panels.has(t["id"]):
			_draw_bezier_line(_knowledge_panels[t["id"]], problem_panel, t["type"], false)

	if relations.is_empty():
		_show_empty_state()
	else:
		_hide_empty_state()

	_update_container_size()
	_update_zoom_label()


func _clear_canvas() -> void:
	for line in _lines:
		if is_instance_valid(line):
			line.queue_free()
	_lines.clear()
	_knowledge_panels.clear()
	_rel_data.clear()
	if _container:
		for child in _container.get_children():
			_container.remove_child(child)
			child.queue_free()


func _update_container_size() -> void:
	var new_size: Vector2 = Vector2(BASE_CANVAS_W, BASE_CANVAS_H) * zoom_scale
	if _scroll and is_instance_valid(_scroll):
		var vp: Vector2 = _scroll.size
		new_size.x = max(new_size.x, vp.x)
		new_size.y = max(new_size.y, vp.y)
	_container.custom_minimum_size = new_size
	_container.size = new_size


# ==================== 面板创建 ====================

func _create_panel(text: String, size: Vector2, bg_color: Color, border_color: Color) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = size
	panel.z_index = 1

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(10 * zoom_scale))
	style.set_border_width_all(int(2 * zoom_scale))
	style.border_color = border_color
	style.bg_color = bg_color
	style.shadow_size = int(4 * zoom_scale)
	style.shadow_color = Color(0, 0, 0, 0.3)
	panel.add_theme_stylebox_override("panel", style)

	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", int(14 * zoom_scale))
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	panel.add_child(label)

	return panel


func _calculate_node_size(text: String) -> Vector2:
	var fixed_size: Vector2 = NODE_SIZE * zoom_scale
	var font_size: int = int(14 * zoom_scale)
	var font: Font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var padding: float = 40.0 * zoom_scale
	return Vector2(max(fixed_size.x, text_width + padding), fixed_size.y)


func _create_knowledge_panel(name: String, rel_type: String, rel_id: String) -> PanelContainer:
	var ns: Vector2 = _calculate_node_size(name)
	var line_color: Color = RELATION_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
	var panel: PanelContainer = _create_panel(name, ns, Color(0.12, 0.14, 0.18, 0.9), line_color)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	panel.gui_input.connect(_on_knowledge_gui_input.bind(rel_id, panel))
	panel.mouse_entered.connect(func():
		if not is_selected(rel_id):
			_update_panel_border(panel, rel_type, true))
	panel.mouse_exited.connect(func():
		if not is_selected(rel_id):
			_update_panel_border(panel, rel_type, false))

	if is_selected(rel_id):
		_update_panel_border(panel, rel_type, false)

	return panel


func _update_panel_border(panel: PanelContainer, rel_type: String, hovered: bool) -> void:
	var old_style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	if not old_style:
		return
	var s: StyleBoxFlat = old_style.duplicate()
	if is_selected_rel(panel):
		s.border_color = Color(0, 0.7, 1)
		s.set_border_width_all(int(3 * zoom_scale))
	elif hovered:
		s.border_color = Color(0.4, 0.7, 1.0)
		s.set_border_width_all(int(2 * zoom_scale))
	else:
		s.border_color = RELATION_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
		s.set_border_width_all(int(2 * zoom_scale))
	panel.add_theme_stylebox_override("panel", s)


func is_selected_rel(panel: PanelContainer) -> bool:
	for rid in selected_rel_ids:
		if _knowledge_panels.has(rid) and _knowledge_panels[rid] == panel:
			return true
	return false


func is_selected(rel_id: String) -> bool:
	return selected_rel_ids.has(rel_id)


func _get_stored_pos(rel_id: String, z: float) -> Vector2:
	if _rel_data.has(rel_id) and _rel_data[rel_id].has("pos2d"):
		var arr = _rel_data[rel_id]["pos2d"]
		if arr is Array and arr.size() >= 2:
			return Vector2(float(arr[0]) * z, float(arr[1]) * z)
	return Vector2.ZERO


func select_rel(rel_id: String, multi: bool = false) -> void:
	if multi:
		if selected_rel_ids.has(rel_id):
			selected_rel_ids.erase(rel_id)
		else:
			selected_rel_ids.append(rel_id)
	else:
		selected_rel_ids.clear()
		selected_rel_ids.append(rel_id)
	_refresh_all_styles()


func deselect_all() -> void:
	selected_rel_ids.clear()
	_refresh_all_styles()


func _refresh_all_styles() -> void:
	for rid in _knowledge_panels:
		var panel: PanelContainer = _knowledge_panels[rid]
		if is_instance_valid(panel):
			var rd: Dictionary = _rel_data.get(rid, {})
			_update_panel_border(panel, rd.get("type", "用到"), false)


# ==================== 知识节点交互 ====================

func _on_knowledge_gui_input(event: InputEvent, rel_id: String, panel: PanelContainer) -> void:
	if is_placing_node:
		return

	if _is_connecting:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_finish_relation_line(rel_id)
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			_edit_knowledge_node(rel_id)
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			if Input.is_key_pressed(KEY_CTRL):
				select_rel(rel_id, true)
				return
			select_rel(rel_id, false)
			_is_dragging = true
			_drag_rel_id = rel_id
			_drag_start_pos = panel.position
			_drag_offset = _screen_to_container(mb.global_position) - panel.position
			return

		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _is_dragging and _drag_rel_id == rel_id:
				_is_dragging = false
				var dist: float = (panel.position - _drag_start_pos).length()
				if dist > 20.0:
					var base_pos: Vector2 = panel.position / zoom_scale
					if _rel_data.has(rel_id):
						_rel_data[rel_id]["pos2d"] = [base_pos.x, base_pos.y]
					var problem_id: String = str(prob_data.get("id", ""))
					var relations: Array = cog_data.call("get_relations_of_problem", problem_id)
					for rel in relations:
						if str(rel.get("id", "")) == rel_id:
							rel["pos2d"] = [base_pos.x, base_pos.y]
							break
					cog_data.call("save_data")
					if history_manager:
						history_manager.call("record_operation", "移动知识节点")
				else:
					panel.position = _drag_start_pos
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_node_context_menu(rel_id, mb.global_position)
			return

	elif event is InputEventMouseMotion and _is_dragging and _drag_rel_id == rel_id:
		var cp: Vector2 = _screen_to_container(event.global_position)
		panel.position = cp - _drag_offset
		_redraw_lines()


# ==================== 2dmm风格贝塞尔连线 ====================

func _cubic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3


## 绘制水平S形贝塞尔连线
## is_prereq=true: 知识节点在左，从知识节点右边缘→题目左边缘
## is_prereq=false: 知识节点在右，从题目右边缘→知识节点左边缘
func _draw_bezier_line(kp: PanelContainer, pp: PanelContainer, rel_type: String, is_prereq: bool) -> void:
	var line: Line2D = Line2D.new()
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.z_index = 5

	var highlighted: bool = false
	for rid in selected_rel_ids:
		if _knowledge_panels.has(rid) and _knowledge_panels[rid] == kp:
			highlighted = true
			break

	if highlighted:
		var lc: Color = RELATION_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
		lc.a = 1.0
		line.default_color = lc
		line.width = 3.0 * zoom_scale
	else:
		# 未选中：用该关系类型的颜色，半透明
		var lc: Color = RELATION_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
		lc.a = 0.6
		line.default_color = lc
		line.width = 1.8 * zoom_scale

	var start: Vector2
	var end: Vector2
	if is_prereq:
		# 左→中：知识节点右边缘中心 → 题目左边缘中心
		var kp_w: float = kp.custom_minimum_size.x if kp.size.x == 0 else kp.size.x
		var kp_h: float = kp.custom_minimum_size.y if kp.size.y == 0 else kp.size.y
		var pp_w: float = pp.custom_minimum_size.x if pp.size.x == 0 else pp.size.x
		var pp_h: float = pp.custom_minimum_size.y if pp.size.y == 0 else pp.size.y
		start = Vector2(kp.position.x + kp_w, kp.position.y + kp_h / 2.0)
		end = Vector2(pp.position.x, pp.position.y + pp_h / 2.0)
	else:
		# 中→右：题目右边缘中心 → 知识节点左边缘中心
		var kp_h: float = kp.custom_minimum_size.y if kp.size.y == 0 else kp.size.y
		var pp_w: float = pp.custom_minimum_size.x if pp.size.x == 0 else pp.size.x
		var pp_h: float = pp.custom_minimum_size.y if pp.size.y == 0 else pp.size.y
		start = Vector2(pp.position.x + pp_w, pp.position.y + pp_h / 2.0)
		end = Vector2(kp.position.x, kp.position.y + kp_h / 2.0)

	var control_offset: float = abs(end.x - start.x) * 0.5
	var dir: float = sign(end.x - start.x)
	if dir == 0.0:
		dir = 1.0
	var cp1: Vector2 = Vector2(start.x + control_offset * dir, start.y)
	var cp2: Vector2 = Vector2(end.x - control_offset * dir, end.y)

	var steps: int = 8
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		line.add_point(_cubic_bezier(start, cp1, cp2, end, t))

	_container.add_child(line)
	_lines.append(line)


## 重绘所有连线（拖拽时调用）
func _redraw_lines() -> void:
	for line in _lines:
		if is_instance_valid(line):
			line.queue_free()
	_lines.clear()

	var ps: Vector2 = PROBLEM_SIZE * zoom_scale
	var cx: float = CENTER_X * zoom_scale
	var cy: float = CENTER_Y * zoom_scale
	var pp_pos: Vector2 = Vector2(cx - ps.x / 2.0, cy - ps.y / 2.0)

	for rid in _rel_data:
		if not _knowledge_panels.has(rid):
			continue
		var rd: Dictionary = _rel_data[rid]
		var kp: PanelContainer = _knowledge_panels[rid]
		var kp_size: Vector2 = kp.custom_minimum_size if kp.size.x == 0 else kp.size
		var is_prereq: bool = (rd.get("type", "") == "前置")
		var rel_type: String = rd.get("type", "用到")

		var line: Line2D = Line2D.new()
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.z_index = 5

		var lc: Color = RELATION_COLORS.get(rel_type, Color(0.5, 0.5, 0.5))
		var is_sel: bool = selected_rel_ids.has(rid)
		lc.a = 1.0 if is_sel else 0.6
		line.default_color = lc
		line.width = (3.0 if is_sel else 1.8) * zoom_scale

		var start: Vector2
		var end: Vector2
		if is_prereq:
			start = Vector2(kp.position.x + kp_size.x, kp.position.y + kp_size.y / 2.0)
			end = Vector2(pp_pos.x, pp_pos.y + ps.y / 2.0)
		else:
			start = Vector2(pp_pos.x + ps.x, pp_pos.y + ps.y / 2.0)
			end = Vector2(kp.position.x, kp.position.y + kp_size.y / 2.0)

		var control_offset: float = abs(end.x - start.x) * 0.5
		var dir: float = sign(end.x - start.x)
		if dir == 0.0:
			dir = 1.0
		var cp1: Vector2 = Vector2(start.x + control_offset * dir, start.y)
		var cp2: Vector2 = Vector2(end.x - control_offset * dir, end.y)
		for i in range(9):
			var t: float = float(i) / 8.0
			line.add_point(_cubic_bezier(start, cp1, cp2, end, t))

		_container.add_child(line)
		_lines.append(line)


# ==================== 缩放系统 ====================

func _apply_button_zoom(new_zoom: float) -> void:
	var old: float = zoom_scale
	zoom_scale = new_zoom
	if zoom_scale == old:
		return
	_apply_zoom_update(old)
	var vp: Vector2 = _scroll.size
	var center_pt: Vector2 = Vector2(CENTER_X, CENTER_Y) * old
	var new_center_pt: Vector2 = center_pt / old * zoom_scale
	_scroll.scroll_horizontal = int(new_center_pt.x - vp.x / 2.0)
	_scroll.scroll_vertical = int(new_center_pt.y - vp.y / 2.0)


func zoom_in(mouse_global_pos: Vector2) -> void:
	var old: float = zoom_scale
	zoom_scale = min(max_zoom, zoom_scale + zoom_speed)
	if zoom_scale != old:
		_do_zoom(old, mouse_global_pos)


func zoom_out(mouse_global_pos: Vector2) -> void:
	var old: float = zoom_scale
	zoom_scale = max(min_zoom, zoom_scale - zoom_speed)
	if zoom_scale != old:
		_do_zoom(old, mouse_global_pos)


func _do_zoom(old_zoom: float, mouse_global_pos: Vector2) -> void:
	var mouse_vp: Vector2 = mouse_global_pos - _scroll.get_global_position()

	var old_scroll: Vector2 = Vector2(float(_scroll.scroll_horizontal), float(_scroll.scroll_vertical))
	var local_pt: Vector2 = (mouse_vp + old_scroll) / old_zoom

	_apply_zoom_update(old_zoom)

	_last_zoom_time = Time.get_ticks_msec()
	if not _zoom_pending:
		_zoom_pending = true
		get_tree().create_timer(0.2).timeout.connect(_on_zoom_throttle_timeout)

	var ns_x: float = local_pt.x * zoom_scale - mouse_vp.x
	var ns_y: float = local_pt.y * zoom_scale - mouse_vp.y
	var vp_size: Vector2 = _scroll.size
	var csize: Vector2 = _container.custom_minimum_size
	ns_x = clamp(ns_x, 0, max(0, csize.x - vp_size.x))
	ns_y = clamp(ns_y, 0, max(0, csize.y - vp_size.y))
	_scroll.scroll_horizontal = ns_x
	_scroll.scroll_vertical = ns_y


## 增量更新缩放：仅更新位置/尺寸/样式，不销毁重建（参考MindMap2D._apply_zoom_update）
func _apply_zoom_update(old_zoom: float) -> void:
	if _knowledge_panels.is_empty():
		_build_canvas()
		return

	var cx: float = CENTER_X * zoom_scale
	var cy: float = CENTER_Y * zoom_scale
	var ps: Vector2 = PROBLEM_SIZE * zoom_scale

	for child in _container.get_children():
		if child is PanelContainer and not _knowledge_panels.values().has(child):
			var pp: PanelContainer = child as PanelContainer
			pp.custom_minimum_size = ps
			pp.size = ps
			pp.position = Vector2(cx - ps.x / 2.0, cy - ps.y / 2.0)
			var s: StyleBoxFlat = pp.get_theme_stylebox("panel")
			if s:
				s.set_corner_radius_all(int(10 * zoom_scale))
				s.set_border_width_all(int(2 * zoom_scale))
				s.shadow_size = int(4 * zoom_scale)
			if pp.get_child_count() > 0 and pp.get_child(0) is Label:
				pp.get_child(0).add_theme_font_size_override("font_size", int(14 * zoom_scale))

	for rid in _knowledge_panels:
		var panel: PanelContainer = _knowledge_panels[rid]
		if not is_instance_valid(panel):
			continue

		var old_center: Vector2 = panel.position + panel.custom_minimum_size / 2.0
		var base_center: Vector2 = old_center / old_zoom
		var new_center: Vector2 = base_center * zoom_scale

		var name_str: String = _rel_data.get(rid, {}).get("name", "")
		var new_size: Vector2 = _calculate_node_size(name_str)
		panel.custom_minimum_size = new_size
		panel.size = new_size
		panel.position = new_center - new_size / 2.0

		var s: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if s:
			s.set_corner_radius_all(int(10 * zoom_scale))
			s.set_border_width_all(int(2 * zoom_scale))
			s.shadow_size = int(4 * zoom_scale)
		if panel.get_child_count() > 0 and panel.get_child(0) is Label:
			panel.get_child(0).add_theme_font_size_override("font_size", int(14 * zoom_scale))

	_update_panel_border_all()
	_redraw_lines()
	_update_container_size()
	_update_zoom_label()


func _update_panel_border_all() -> void:
	for rid in _knowledge_panels:
		var panel: PanelContainer = _knowledge_panels[rid]
		if not is_instance_valid(panel):
			continue
		var rd: Dictionary = _rel_data.get(rid, {})
		_update_panel_border(panel, rd.get("type", "用到"), false)


func _on_zoom_throttle_timeout() -> void:
	if _zoom_pending:
		var now: int = Time.get_ticks_msec()
		if now - _last_zoom_time >= 150:
			_zoom_pending = false
		else:
			get_tree().create_timer(0.1).timeout.connect(_on_zoom_throttle_timeout)


func reset_view() -> void:
	zoom_scale = 1.0
	_build_canvas()
	_center_on_problem()


func _center_on_problem() -> void:
	if not _scroll or not is_instance_valid(_scroll):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_redraw_lines()
	await get_tree().process_frame
	var vp: Vector2 = _scroll.size
	var cx: float = CENTER_X * zoom_scale
	var cy: float = CENTER_Y * zoom_scale
	var sx: float = cx - vp.x / 2.0
	var sy: float = cy - vp.y / 2.0
	var max_sx: float = max(0, _container.custom_minimum_size.x - vp.x)
	var max_sy: float = max(0, _container.custom_minimum_size.y - vp.y)
	_scroll.scroll_horizontal = int(clamp(sx, 0, max_sx))
	_scroll.scroll_vertical = int(clamp(sy, 0, max_sy))


func _update_zoom_label() -> void:
	var top_bar: HBoxContainer = get_node_or_null("TopBar") as HBoxContainer
	if top_bar:
		var lbl: Label = top_bar.get_node_or_null("ZoomLabel") as Label
		if lbl:
			lbl.text = "%d%%" % int(zoom_scale * 100)


func _screen_to_container(global_pos: Vector2) -> Vector2:
	var vp: Vector2 = global_pos - _scroll.get_global_position()
	return vp + Vector2(float(_scroll.scroll_horizontal), float(_scroll.scroll_vertical))


# ==================== 滚动/平移/缩放输入 ====================

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		# Ctrl+滚轮缩放
		if Input.is_key_pressed(KEY_CTRL):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				zoom_in(mb.global_position)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				zoom_out(mb.global_position)
				get_viewport().set_input_as_handled()
				return

		# 中键平移
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				get_viewport().set_input_as_handled()
			else:
				_is_panning = false
			return

		# 普通滚轮
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll.scroll_vertical = max(0, _scroll.scroll_vertical - 50)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll.scroll_vertical += 50
			return

		# 放置模式
		if is_placing_node:
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_finalize_placing()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				_cancel_placing()
			return

		# 右键空白
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _is_connecting:
				_cancel_relation_line()
			else:
				_show_empty_context_menu(mb.global_position)
			return

		# 左键空白
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _skip_next_click:
				_skip_next_click = false
				return
			if _is_connecting:
				_cancel_relation_line()
				return
			if not Input.is_key_pressed(KEY_CTRL):
				deselect_all()
			return

	if event is InputEventMouseMotion:
		if _is_panning:
			_scroll.scroll_horizontal -= int(event.relative.x)
			_scroll.scroll_vertical -= int(event.relative.y)
			return
		if _is_connecting and _connect_line:
			var cp: Vector2 = _screen_to_container(get_viewport().get_mouse_position())
			var ps: Vector2 = PROBLEM_SIZE * zoom_scale
			var cx: float = CENTER_X * zoom_scale
			var cy: float = CENTER_Y * zoom_scale
			_connect_line.set_point_position(0, Vector2(cx + ps.x / 2.0, cy))
			_connect_line.set_point_position(1, cp)


# ==================== 节点放置 ====================

func _start_placing_from_queue() -> void:
	if _place_queue.is_empty():
		return
	var next_name: String = _place_queue.pop_front()
	is_placing_node = true
	_skip_next_click = false

	var ns: Vector2 = NODE_SIZE * zoom_scale
	_placing_panel = _create_panel(next_name, ns, Color(0.12, 0.14, 0.18, 0.7), Color(0, 1, 0.5))
	_placing_panel.z_index = 100
	var s: StyleBoxFlat = _placing_panel.get_theme_stylebox("panel").duplicate()
	s.border_color = Color(0, 1, 0.5)
	s.set_border_width_all(int(3 * zoom_scale))
	s.shadow_color = Color(0.0, 1.0, 0.5, 0.3)
	s.shadow_size = int(8 * zoom_scale)
	_placing_panel.add_theme_stylebox_override("panel", s)
	_container.add_child(_placing_panel)


func _finalize_placing() -> void:
	if not is_placing_node:
		return
	is_placing_node = false
	_skip_next_click = true

	if _placing_panel and is_instance_valid(_placing_panel):
		var problem_id: String = str(prob_data.get("id", ""))
		cog_data.call("add_relation", problem_id, _placing_panel.get_child(0).text, "用到")
		var cog_idx: int = cog_data.call("find_by_name", _placing_panel.get_child(0).text)
		if cog_idx >= 0:
			var cog_item: Dictionary = cog_data.call("get_item", cog_idx)
			cog_item["visible_in_2dtr"] = true
			cog_data.call("save_data")
		_placing_panel.queue_free()
		_placing_panel = null

	_build_canvas()

	if not _place_queue.is_empty():
		_start_placing_from_queue.call_deferred()


func _cancel_placing() -> void:
	if not is_placing_node:
		return
	is_placing_node = false
	if _placing_panel and is_instance_valid(_placing_panel):
		_placing_panel.queue_free()
		_placing_panel = null
	_place_queue.clear()


# ==================== 上下文菜单 ====================

func _show_node_context_menu(rel_id: String, mouse_pos: Vector2) -> void:
	var menu: PopupMenu = PopupMenu.new()
	menu.name = "NodeContextMenu"

	menu.add_item("查看详情")
	menu.set_item_metadata(0, "show_detail")
	menu.add_separator()

	var submenu: PopupMenu = PopupMenu.new()
	submenu.name = "MasterySub"
	submenu.add_item("未学习")
	submenu.set_item_metadata(0, 0)
	submenu.add_item("学习中")
	submenu.set_item_metadata(1, 1)
	submenu.add_item("已掌握")
	submenu.set_item_metadata(2, 2)
	submenu.index_pressed.connect(func(idx: int):
		var m: int = submenu.get_item_metadata(idx)
		var tn: String = _rel_data.get(rel_id, {}).get("name", "")
		var di: int = data_manager.call("find_by_name", tn)
		if di >= 0:
			var item: Dictionary = data_manager.call("get_item", di)
			item["mastery"] = m
			data_manager.call("save_data")
		if history_manager:
			history_manager.call("record_operation", "设置掌握度")
		menu.queue_free()
		_build_canvas()
	)
	menu.add_child(submenu)
	menu.add_submenu_item("设置掌握度", "MasterySub")

	menu.add_separator()
	menu.add_item("删除关系")
	menu.set_item_metadata(menu.get_item_count() - 1, "delete_relation")
	menu.add_separator()
	menu.add_item("自动布局")
	menu.set_item_metadata(menu.get_item_count() - 1, "auto_layout")
	menu.add_item("重置视图")
	menu.set_item_metadata(menu.get_item_count() - 1, "reset_view")
	menu.add_item("截图")
	menu.set_item_metadata(menu.get_item_count() - 1, "screenshot")

	menu.index_pressed.connect(func(idx: int):
		var action: String = menu.get_item_metadata(idx)
		match action:
			"show_detail":
				_edit_knowledge_node(rel_id)
			"delete_relation":
				_delete_relation(rel_id)
			"auto_layout":
				_run_auto_layout()
			"reset_view":
				reset_view()
			"screenshot":
				request_screenshot.emit()
		menu.queue_free()
	)

	add_child(menu)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()
	menu.grab_focus()
	menu.popup_hide.connect(func():
		if is_instance_valid(menu):
			menu.queue_free()
	)


func _show_empty_context_menu(mouse_pos: Vector2) -> void:
	var menu: PopupMenu = PopupMenu.new()
	menu.name = "EmptyContextMenu"

	menu.add_item("添加关联知识点")
	menu.set_item_metadata(0, "add_knowledge")
	menu.add_separator()

	var submenu: PopupMenu = PopupMenu.new()
	submenu.name = "RelTypeSub"
	var types: Array = ["用到", "可替换", "前置", "延伸"]
	for i in types.size():
		submenu.add_item(types[i])
		submenu.set_item_metadata(i, types[i])
	submenu.index_pressed.connect(func(idx: int):
		_start_relation_line(submenu.get_item_metadata(idx))
		menu.queue_free()
	)
	menu.add_child(submenu)
	menu.add_submenu_item("添加关系线", "RelTypeSub")

	menu.add_separator()
	menu.add_item("自动布局")
	menu.set_item_metadata(menu.get_item_count() - 1, "auto_layout")
	menu.add_item("重置视图")
	menu.set_item_metadata(menu.get_item_count() - 1, "reset_view")
	menu.add_item("截图")
	menu.set_item_metadata(menu.get_item_count() - 1, "screenshot")

	menu.index_pressed.connect(func(idx: int):
		var action: String = menu.get_item_metadata(idx)
		match action:
			"add_knowledge":
				_show_add_knowledge_dialog()
			"auto_layout":
				_run_auto_layout()
			"reset_view":
				reset_view()
			"screenshot":
				request_screenshot.emit()
		menu.queue_free()
	)

	add_child(menu)
	menu.position = Vector2i(get_viewport().get_mouse_position())
	menu.popup()
	menu.grab_focus()
	menu.popup_hide.connect(func():
		if is_instance_valid(menu):
			menu.queue_free()
	)


# ==================== 连线模式 ====================

func _start_relation_line(rel_type: String) -> void:
	_is_connecting = true
	_connect_type = rel_type

	_connect_line = Line2D.new()
	_connect_line.name = "ConnectLine"
	_connect_line.width = 3.0 * zoom_scale
	_connect_line.default_color = RELATION_COLORS.get(rel_type, Color(1, 1, 1))
	_connect_line.add_point(Vector2.ZERO)
	_connect_line.add_point(Vector2.ZERO)
	_connect_line.z_index = 100
	_container.add_child(_connect_line)


func _cancel_relation_line() -> void:
	_is_connecting = false
	_connect_type = ""
	if _connect_line and is_instance_valid(_connect_line):
		_connect_line.queue_free()
		_connect_line = null


func _finish_relation_line(target_rel_id: String) -> void:
	if not _is_connecting:
		return

	var target_name: String = _rel_data.get(target_rel_id, {}).get("name", "")
	var problem_id: String = str(prob_data.get("id", ""))

	var existing: Array = cog_data.call("get_relations_of_problem", problem_id)
	for rel in existing:
		if str(rel.get("target", "")) == target_name and str(rel.get("type", "")) == _connect_type:
			_cancel_relation_line()
			return

	cog_data.call("add_relation", problem_id, target_name, _connect_type)
	_cancel_relation_line()
	if history_manager:
		history_manager.call("record_operation", "添加关系线: %s" % target_name)
	_build_canvas()


# ==================== 自动布局 ====================

func _run_auto_layout() -> void:
	var problem_id: String = str(prob_data.get("id", ""))
	var relations: Array = cog_data.call("get_relations_of_problem", problem_id)

	var ns: Vector2 = NODE_SIZE * zoom_scale
	var cx: float = CENTER_X * zoom_scale
	var cy: float = CENTER_Y * zoom_scale
	var left_x: float = (CENTER_X - LEFT_OFFSET) * zoom_scale
	var right_x: float = (CENTER_X + RIGHT_OFFSET) * zoom_scale

	var prereq_list: Array = []
	var used_list: Array = []
	for rel in relations:
		var rid: String = str(rel.get("id", ""))
		var rtype: String = str(rel.get("type", "用到")).strip_edges()
		if rtype == "前置":
			prereq_list.append(rid)
		else:
			used_list.append(rid)

	# 左区居中
	var lh: float = prereq_list.size() * ns.y + max(0, prereq_list.size() - 1) * VERTICAL_SPACING * zoom_scale
	var ly: float = cy - lh / 2.0
	for i in prereq_list.size():
		if _knowledge_panels.has(prereq_list[i]) and is_instance_valid(_knowledge_panels[prereq_list[i]]):
			_knowledge_panels[prereq_list[i]].position = Vector2(left_x - ns.x / 2.0, ly + i * (ns.y + VERTICAL_SPACING * zoom_scale))

	# 右区居中
	var rh: float = used_list.size() * ns.y + max(0, used_list.size() - 1) * VERTICAL_SPACING * zoom_scale
	var ry: float = cy - rh / 2.0
	for i in used_list.size():
		if _knowledge_panels.has(used_list[i]) and is_instance_valid(_knowledge_panels[used_list[i]]):
			_knowledge_panels[used_list[i]].position = Vector2(right_x - ns.x / 2.0, ry + i * (ns.y + VERTICAL_SPACING * zoom_scale))

	_redraw_lines()


# ==================== 历史记录 ====================

func undo() -> void:
	if history_manager and history_manager.call("can_undo"):
		history_manager.call("undo")
		_build_canvas()


func redo() -> void:
	if history_manager and history_manager.call("can_redo"):
		history_manager.call("redo")
		_build_canvas()


# ==================== 空状态 ====================

func _show_empty_state() -> void:
	if _empty_hint:
		return
	_empty_hint = Label.new()
	_empty_hint.text = "右键空白处添加关联知识点\n或使用菜单添加关系线"
	_empty_hint.add_theme_font_size_override("font_size", int(20 * zoom_scale))
	_empty_hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cx: float = CENTER_X * zoom_scale
	var cy: float = CENTER_Y * zoom_scale
	_empty_hint.position = Vector2(cx - 200 * zoom_scale, cy + 80 * zoom_scale)
	_empty_hint.custom_minimum_size = Vector2(400, 60) * zoom_scale
	_container.add_child(_empty_hint)


func _hide_empty_state() -> void:
	if _empty_hint and is_instance_valid(_empty_hint):
		_empty_hint.queue_free()
		_empty_hint = null


# ==================== 添加关联知识点对话框 ====================

func _show_add_knowledge_dialog() -> void:
	if not data_manager or not cog_data:
		return
	var problem_id: String = str(prob_data.get("id", ""))
	var existing: Array = []
	for rel in cog_data.call("get_relations_of_problem", problem_id):
		existing.append(str(rel.get("target", "")))

	var REL_TYPES: Array = ["用到", "可替换", "前置", "延伸"]

	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "添加关联知识点"
	dialog.min_size = Vector2(400, 450)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var type_row: HBoxContainer = HBoxContainer.new()
	var type_label: Label = Label.new()
	type_label.text = "关系类型:"
	type_label.custom_minimum_size = Vector2(70, 0)
	var type_opt: OptionButton = OptionButton.new()
	for t in REL_TYPES:
		type_opt.add_item(t)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_label)
	type_row.add_child(type_opt)
	vbox.add_child(type_row)

	var search_edit: LineEdit = LineEdit.new()
	search_edit.placeholder_text = "搜索知识点..."
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(search_edit)

	var show_existing_check: CheckBox = CheckBox.new()
	show_existing_check.text = "显示已关联知识点"
	show_existing_check.button_pressed = false
	vbox.add_child(show_existing_check)

	var item_list: ItemList = ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_list.select_mode = ItemList.SELECT_MULTI

	var all_names: Array = []
	for i in data_manager.call("get_count"):
		var item: Dictionary = data_manager.call("get_item", i)
		var n: String = str(item.get("name", ""))
		if not n.is_empty():
			all_names.append(n)

	var refresh_list: Callable = func(_text: String = "") -> void:
		item_list.clear()
		var filter: String = search_edit.text.to_lower()
		var show_ex: bool = show_existing_check.button_pressed
		for n in all_names:
			if not show_ex and n in existing:
				continue
			if filter.is_empty() or filter in n.to_lower():
				var idx: int = item_list.add_item(n)
				if n in existing:
					item_list.set_item_disabled(idx, true)

	vbox.add_child(item_list)
	dialog.add_child(vbox)
	add_child(dialog)

	search_edit.text_changed.connect(refresh_list)
	show_existing_check.toggled.connect(func(_pressed: bool): refresh_list.call())
	refresh_list.call()

	dialog.confirmed.connect(func():
		var rel_type: String = REL_TYPES[type_opt.selected]
		var selected: Array = item_list.get_selected_items()
		for si in selected:
			var target_name: String = item_list.get_item_text(si)
			if target_name in existing:
				continue
			cog_data.call("add_relation", problem_id, target_name, rel_type)
			var cog_idx: int = cog_data.call("find_by_name", target_name)
			if cog_idx >= 0:
				var cog_item: Dictionary = cog_data.call("get_item", cog_idx)
				cog_item["visible_in_2dtr"] = true
				cog_data.call("save_data")
			if history_manager:
				history_manager.call("record_operation", "添加关系: %s" % target_name)
		_build_canvas()
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup_centered()
	search_edit.grab_focus()


# ==================== 编辑/删除 ====================

func _edit_knowledge_node(rel_id: String) -> void:
	var target_name: String = _rel_data.get(rel_id, {}).get("name", "")
	if target_name.is_empty():
		return
	var dm_idx: int = data_manager.call("find_by_name", target_name)
	if dm_idx < 0:
		return

	var EditDialogScript := load("res://script/2dmm/EditNodeDialog.gd")
	if not EditDialogScript:
		return
	var edit_dialog: ConfirmationDialog = EditDialogScript.new(data_manager)
	edit_dialog.node_edited.connect(func(edited_index: int, new_data: Dictionary):
		data_manager.call("set_item", edited_index, new_data)
		data_manager.call("save_data")
		_build_canvas()
		if history_manager:
			history_manager.call("record_operation", "编辑节点: %s" % str(new_data.get("name", "")))
	)
	add_child(edit_dialog)
	edit_dialog.edit_node(dm_idx)


func _delete_relation(rel_id: String) -> void:
	cog_data.call("remove_relation", rel_id)
	if history_manager:
		history_manager.call("record_operation", "删除关系")
	_build_canvas()


# ==================== 快捷键分发 ====================

func handle_key_input(event: InputEventKey) -> void:
	if event.keycode == KEY_Z and event.ctrl_pressed and not event.shift_pressed:
		undo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Y and event.ctrl_pressed:
		redo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed:
		redo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_DELETE:
		for rid in selected_rel_ids.duplicate():
			_delete_relation(rid)
		deselect_all()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if _is_connecting:
			_cancel_relation_line()
		elif is_placing_node:
			_cancel_placing()
		else:
			deselect_all()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_N and event.ctrl_pressed:
		_show_add_knowledge_dialog()
		get_viewport().set_input_as_handled()


func handle_scroll(event: InputEvent) -> void:
	_on_scroll_gui_input(event)


func take_screenshot() -> void:
	request_screenshot.emit()