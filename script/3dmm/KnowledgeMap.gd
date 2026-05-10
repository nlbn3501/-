## 3D知识导图核心类，管理3D空间中知识点的创建、布局、交互、选中和可视化
extends Node3D

var data_manager: RefCounted
var layout_manager: RefCounted
var point_manager: RefCounted
var history_manager: RefCounted
var context_menu_manager: RefCounted

var selected_index: int = -1
var selected_indices: Array[int] = []
var _empty_label: Label3D

var camera_orbit_radius: float = 15.0
var camera_orbit_theta: float = 0.0
var camera_orbit_phi: float = 0.3
var camera_target_radius: float = 15.0
var camera_target_theta: float = 0.0
var camera_target_phi: float = 0.3
var camera_orbit_speed: float = 0.005
var camera_zoom_speed: float = 1.0
var camera_smooth_speed: float = 12.0
var camera_is_rotating: bool = false
var camera_rotate_start: Vector2 = Vector2.ZERO
var camera_is_zooming: bool = false
var camera_zoom_start_y: float = 0.0
var camera_zoom_start_radius: float = 15.0
var _has_focus_target: bool = false
var _focus_target: Vector3 = Vector3.ZERO
var camera_root_index: int = 0
var _orbiting_free_node_index: int = -1

var mat_unlearned_color: Color = Color(0.6, 0.6, 0.6)
var mat_learning_color: Color = Color(1.0, 0.6, 0.1)
var mat_learned_color: Color = Color(0.2, 0.85, 0.2)
var mat_roughness: float = 0.3
var mat_metallic: float = 0.0
var mat_emission_energy: float = 0.8
var mat_selected_color: Color = Color(1.0, 1.0, 0.3)
var mat_selected_emission_mult: float = 2.0

var _settings_panel: PanelContainer

signal point_clicked(index: int)
signal point_double_clicked(index: int)
signal request_create_node(parent_hint: int)
signal nodes_changed()


## 初始化知识导图，绑定数据管理器
func _init(dm: RefCounted) -> void:
	data_manager = dm


## 节点就绪时初始化环境、管理器、信号和数据
func _ready() -> void:
	_setup_environment()
	_initialize_managers()
	_connect_signals()
	_load_and_build()


## 设置3D场景环境（世界环境、灯光、天空）
func _setup_environment() -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_strength = 0.6
	env.glow_bloom = 0.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.8
	env.glow_hdr_scale = 0.5
	world_env.environment = env
	add_child(world_env)


## 初始化布局管理器和点管理器
func _initialize_managers() -> void:
	layout_manager = load("res://script/3dmm/LayoutManager.gd").new(data_manager)
	point_manager = load("res://script/3dmm/PointManager.gd").new(data_manager, layout_manager, self)
	history_manager = load("res://script/2dmm/HistoryManager.gd").new(data_manager)
	context_menu_manager = load("res://script/2dmm/ContextMenuManager.gd").new(data_manager, self)


## 连接点管理器的交互信号
func _connect_signals() -> void:
	if context_menu_manager:
		context_menu_manager.menu_action.connect(_on_context_menu_action)


## 加载数据并构建3D视图
func _load_and_build() -> void:
	data_manager.load_data()
	if data_manager.get_count() == 0:
		_show_empty_state()
		return
	_hide_empty_state()
	layout_manager.apply_layout()
	point_manager.build_all_points()
	_find_root_node()
	_ensure_camera()


## 查找根节点并记录其索引
func _find_root_node() -> void:
	var depths: Array = data_manager.compute_depths()
	for i in depths.size():
		if depths[i] == 0:
			camera_root_index = i
			break


## 确保场景中存在摄像机
func _ensure_camera() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		camera = Camera3D.new()
		camera.name = "MainCamera"
		camera.current = true
		add_child(camera)
	var center: Vector3 = data_manager.get_points_center()
	_update_camera_position(camera, center)


## 更新摄像机位置到指定中心点
func _update_camera_position(camera: Camera3D, center: Vector3) -> void:
	camera_orbit_radius = camera_target_radius
	camera_orbit_theta = camera_target_theta
	camera_orbit_phi = camera_target_phi
	var x: float = camera_orbit_radius * cos(camera_orbit_phi) * sin(camera_orbit_theta)
	var y: float = camera_orbit_radius * sin(camera_orbit_phi)
	var z: float = camera_orbit_radius * cos(camera_orbit_phi) * cos(camera_orbit_theta)
	camera.position = center + Vector3(x, y, z)
	camera.look_at(center, Vector3.UP)


var _pending_focus_index: int = -1


## 外部请求聚焦到指定节点
func request_focus_on_node(index: int) -> void:
	_pending_focus_index = index


## 每帧更新摄像机轨道运动
func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	if _pending_focus_index >= 0:
		var idx: int = _pending_focus_index
		_pending_focus_index = -1
		_focus_on_point(idx)
		_clear_selection()
		selected_index = idx
		selected_indices = [idx]
		point_manager.highlight_point(idx, true)

	camera_orbit_radius = lerp(camera_orbit_radius, camera_target_radius, camera_smooth_speed * delta)
	camera_orbit_theta = lerp(camera_orbit_theta, camera_target_theta, camera_smooth_speed * delta)
	camera_orbit_phi = lerp(camera_orbit_phi, camera_target_phi, camera_smooth_speed * delta)

	var center: Vector3
	if _has_focus_target:
		center = _focus_target
	else:
		center = _get_root_node_position()
	var x: float = camera_orbit_radius * cos(camera_orbit_phi) * sin(camera_orbit_theta)
	var y: float = camera_orbit_radius * sin(camera_orbit_phi)
	var z: float = camera_orbit_radius * cos(camera_orbit_phi) * cos(camera_orbit_theta)
	camera.position = center + Vector3(x, y, z)
	camera.look_at(center, Vector3.UP)

	point_manager.update_link_lines()


## 全局输入处理，处理鼠标点击、拖拽和键盘快捷键
func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if not visible:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			_handle_double_click(mb.position)

		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.double_click:
			var idx: int = point_manager.pick_point_index(mb.position, get_viewport().get_camera_3d())
			if idx >= 0:
				if Input.is_key_pressed(KEY_CTRL):
					_toggle_select(idx, true)
				else:
					_toggle_select(idx, false)
			else:
				_clear_selection()
				camera_is_rotating = true
				camera_rotate_start = mb.position
				if _orbiting_free_node_index < 0:
					_has_focus_target = false
					_focus_target = Vector3.ZERO
				get_viewport().set_input_as_handled()

		elif mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			camera_is_rotating = false

		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed:
			camera_is_zooming = true
			camera_zoom_start_y = mb.position.y
			camera_zoom_start_radius = camera_target_radius
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and not mb.pressed:
			camera_is_zooming = false

		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_target_radius = max(3.0, camera_target_radius - camera_zoom_speed)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_target_radius = min(50.0, camera_target_radius + camera_zoom_speed)
			get_viewport().set_input_as_handled()

		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var idx: int = point_manager.pick_point_index(mb.position, get_viewport().get_camera_3d())
			var click_world: Vector3 = _mouse_to_plane(mb.position, 0.0)
			if idx >= 0:
				if selected_indices.size() > 1 and selected_indices.has(idx):
					context_menu_manager.show_multi_selection_menu(mb.global_position, selected_indices)
				else:
					var fl: String = "聚焦节点"
					var fa: String = "focus_node"
					if _is_free_node(idx) and _orbiting_free_node_index == idx:
						fl = "取消聚焦"
						fa = "unfocus_node"
					context_menu_manager.show_node_context_menu(idx, mb.global_position, false, fl, fa)
			else:
				var local_pos_2d := Vector2(click_world.x, click_world.z)
				context_menu_manager.show_empty_context_menu(mb.global_position, local_pos_2d)

	elif event is InputEventMouseMotion:
		if camera_is_zooming:
			var delta_y: float = event.position.y - camera_zoom_start_y
			camera_target_radius = clamp(camera_zoom_start_radius + delta_y * 0.05, 3.0, 50.0)
		elif camera_is_rotating:
			var delta: Vector2 = event.relative
			camera_target_theta -= delta.x * camera_orbit_speed
			camera_target_phi = clamp(camera_target_phi + delta.y * camera_orbit_speed, -1.5, 1.5)

	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				rebuild_all()
				get_viewport().set_input_as_handled()
			KEY_Z:
				if Input.is_key_pressed(KEY_CTRL):
					_perform_undo()
					get_viewport().set_input_as_handled()
			KEY_Y:
				if Input.is_key_pressed(KEY_CTRL):
					_perform_redo()
					get_viewport().set_input_as_handled()
			KEY_N:
				if Input.is_key_pressed(KEY_CTRL):
					var mouse_pos: Vector2 = get_viewport().get_mouse_position()
					var world_pos: Vector3 = _mouse_to_plane(mouse_pos, 0.0)
					_show_node_dialog("create", -1, world_pos)
					get_viewport().set_input_as_handled()
			KEY_DELETE:
				if selected_index >= 0:
					_delete_node(selected_index)
					selected_index = -1
				elif selected_indices.size() > 0:
					_batch_delete()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				_create_node_via_tab()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_clear_selection()


## 处理双击事件，选中并聚焦节点
func _handle_double_click(mouse_pos: Vector2) -> void:
	var idx: int = point_manager.pick_point_index(mouse_pos, get_viewport().get_camera_3d())
	if idx >= 0:
		selected_index = idx
		_show_detail_popup(idx)


## 将鼠标屏幕坐标射线投射到指定Y高度的平面
func _mouse_to_plane(mouse_pos: Vector2, y: float) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var root_pos: Vector3 = _get_root_node_position()
	var cam_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var plane_d: float = -cam_forward.dot(root_pos)
	var plane: Plane = Plane(cam_forward, plane_d)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit is Vector3:
		return hit
	return root_pos


## 切换节点选中状态，支持Ctrl多选
func _toggle_select(index: int, ctrl_pressed: bool) -> void:
	if not ctrl_pressed:
		_clear_selection()
		selected_indices = [index]
		point_manager.highlight_point(index, true)
		selected_index = index
	else:
		if selected_indices.has(index):
			selected_indices.erase(index)
			point_manager.highlight_point(index, false)
			if selected_index == index:
				if selected_indices.size() > 0:
					selected_index = selected_indices[-1]
				else:
					selected_index = -1
		else:
			selected_indices.append(index)
			point_manager.highlight_point(index, true)
			selected_index = index


## 清除所有选中状态
func _clear_selection() -> void:
	for idx in selected_indices:
		if idx != _orbiting_free_node_index:
			point_manager.highlight_point(idx, false)
	selected_indices.clear()
	selected_index = -1


## 聚焦摄像机到指定知识点
func _focus_on_point(index: int) -> void:
	var pos: Vector3 = point_manager.get_point_position(index)
	_has_focus_target = true
	_focus_target = pos
	if _is_free_node(index):
		_orbiting_free_node_index = index
	else:
		_orbiting_free_node_index = -1
	var item: Dictionary = data_manager.get_item(index)
	var gid := int(item.get("galaxy_id", 0))
	var galaxy_nodes: Array = data_manager.get_galaxy_nodes(gid)
	var galaxy_radius: float = layout_manager.estimate_galaxy_radius(galaxy_nodes)
	camera_target_radius = max(galaxy_radius * 3.0, 8.0)
	camera_target_theta = atan2(pos.x, pos.z)
	camera_target_phi = 0.3


## 执行撤销操作
func _perform_undo() -> void:
	if not history_manager.can_undo():
		return
	history_manager.undo()
	data_manager.save_data()
	rebuild_all()


## 执行重做操作
func _perform_redo() -> void:
	if not history_manager.can_redo():
		return
	history_manager.redo()
	data_manager.save_data()
	rebuild_all()


## 批量删除选中的节点
func _batch_delete() -> void:
	if selected_indices.is_empty():
		return
	var selected: Array[int] = selected_indices.duplicate()
	selected.sort()
	var ids_to_delete: Dictionary = {}
	for idx in selected:
		var item: Dictionary = data_manager.get_item(idx)
		ids_to_delete[str(item.get("id", ""))] = true
	for idx in selected:
		var item: Dictionary = data_manager.get_item(idx)
		data_manager.cleanup_relations_for(str(item.get("name", "")))
	for id_key in ids_to_delete:
		var child_indices: Array = data_manager.get_children_of(str(id_key))
		for j in child_indices:
			var child: Dictionary = data_manager.get_item(j)
			child["parent_id"] = ""
			var new_gid: int = data_manager.next_available_galaxy_id()
			child["galaxy_id"] = new_gid
			data_manager.propagate_galaxy_id(j, new_gid)
			data_manager.set_item(j, child)
	for i in range(selected.size() - 1, -1, -1):
		var idx: int = selected[i]
		data_manager.remove_item(idx)
	history_manager.record_operation("批量删除")
	_clear_selection()
	data_manager.cleanup_empty_galaxies()
	data_manager.save_data()
	rebuild_all()


## 删除所有非根节点
func _delete_all_non_root() -> void:
	var count: int = data_manager.get_count()
	var deleted_count: int = 0
	for i in range(count - 1, -1, -1):
		var item: Dictionary = data_manager.get_item(i)
		if item.is_empty():
			continue
		var node_id: String = str(item.get("id", ""))
		if node_id != "root":
			data_manager.cleanup_relations_for(str(item.get("name", "")))
			data_manager.remove_item(i)
			deleted_count += 1
	if deleted_count > 0:
		data_manager.cleanup_empty_galaxies()
		_clear_selection()
		data_manager.save_data()
		rebuild_all()


## 显示空数据状态提示
func _show_empty_state() -> void:
	if _empty_label != null:
		return
	_empty_label = Label3D.new()
	_empty_label.name = "EmptyHint"
	_empty_label.text = "Right-click here to create first node"
	_empty_label.font_size = 80
	_empty_label.pixel_size = 0.02
	_empty_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_empty_label.outline_size = 6
	_empty_label.modulate = Color(0.4, 0.45, 0.55, 0.8)
	_empty_label.position = Vector3(0, 0, 0)
	add_child(_empty_label)


## 隐藏空数据状态提示
func _hide_empty_state() -> void:
	if _empty_label != null and is_instance_valid(_empty_label):
		_empty_label.queue_free()
		_empty_label = null


## 重建所有3D视图（点和连线）
func rebuild_all() -> void:
	var count: int = data_manager.get_count()
	if count == 0:
		_show_empty_state()
		return
	_hide_empty_state()
	layout_manager.apply_layout()
	point_manager.build_all_points()
	nodes_changed.emit()


## 显示节点创建/编辑对话框
func _show_node_dialog(mode: String, index: int = -1, default_pos: Vector3 = Vector3.ZERO) -> void:
	var is_create := mode == "create"
	var item: Dictionary = {}
	if not is_create:
		item = data_manager.get_item(index)
		if item.is_empty():
			return
	var dlg := ConfirmationDialog.new()
	dlg.title = "新建知识点" if is_create else "编辑知识点"
	dlg.min_size = Vector2i(460, 420)
	get_tree().root.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dlg.add_child(vbox)
	var name_input := LineEdit.new()
	name_input.placeholder_text = "名称 *"
	if not is_create:
		name_input.text = str(item.get("name", ""))
	vbox.add_child(name_input)
	var desc_input := TextEdit.new()
	desc_input.placeholder_text = "描述"
	desc_input.custom_minimum_size = Vector2(0, 70)
	if not is_create:
		desc_input.text = str(item.get("description", ""))
	vbox.add_child(desc_input)
	var pos_row := HBoxContainer.new()
	vbox.add_child(pos_row)
	var x_input := LineEdit.new()
	x_input.placeholder_text = "X"
	x_input.text = "%.2f" % default_pos.x if is_create else str(float(item.get("position", [0,0,0])[0]))
	pos_row.add_child(x_input)
	var y_input := LineEdit.new()
	y_input.placeholder_text = "Y"
	y_input.text = "%.2f" % default_pos.y if is_create else str(float(item.get("position", [0,0,0])[1]))
	pos_row.add_child(y_input)
	var z_input := LineEdit.new()
	z_input.placeholder_text = "Z"
	z_input.text = "%.2f" % default_pos.z if is_create else str(float(item.get("position", [0,0,0])[2]))
	pos_row.add_child(z_input)
	var opt_row := HBoxContainer.new()
	vbox.add_child(opt_row)
	var mastery_spin := SpinBox.new()
	mastery_spin.min_value = 0
	mastery_spin.max_value = 2
	mastery_spin.step = 1
	mastery_spin.value = int(item.get("mastery", 0)) if not is_create else 0
	opt_row.add_child(mastery_spin)
	var parent_opt := OptionButton.new()
	parent_opt.custom_minimum_size.x = 200
	parent_opt.add_item("(无 / 根节点)", -1)
	parent_opt.set_item_metadata(0, "")
	var pcount: int = data_manager.get_count()
	var opt_index: int = 1
	for i in pcount:
		if not is_create and i == index:
			continue
		var pitem: Dictionary = data_manager.get_item(i)
		var node_id: String = str(pitem.get("id", ""))
		parent_opt.add_item(str(pitem.get("name", "")), opt_index)
		parent_opt.set_item_metadata(opt_index, node_id)
		opt_index += 1
	if not is_create:
		var current_parent_id: String = str(item.get("parent_id", ""))
		if not current_parent_id.is_empty():
			for j in parent_opt.item_count:
				var meta: Variant = parent_opt.get_item_metadata(j)
				if meta is String and meta == current_parent_id:
					parent_opt.selected = j
					break
	elif index >= 0:
		var hint_item: Dictionary = data_manager.get_item(index)
		var hint_id := str(hint_item.get("id", ""))
		for j in parent_opt.item_count:
			var meta: Variant = parent_opt.get_item_metadata(j)
			if meta is String and meta == hint_id:
				parent_opt.selected = j
				break
	opt_row.add_child(parent_opt)
	var galaxy_label := Label.new()
	var current_galaxy := 0
	if is_create:
		if index >= 0:
			var hint_item: Dictionary = data_manager.get_item(index)
			current_galaxy = int(hint_item.get("galaxy_id", 0))
		else:
			current_galaxy = 0
		galaxy_label.text = "所属星系: %d" % current_galaxy
	else:
		current_galaxy = int(item.get("galaxy_id", 0))
		galaxy_label.text = "所属星系: %d" % current_galaxy
	galaxy_label.modulate = Color(0.7, 0.7, 0.7)
	vbox.add_child(galaxy_label)
	dlg.confirmed.connect(func():
		var node_name: String = name_input.text.strip_edges()
		if node_name.is_empty():
			return
		var desc_text: String = desc_input.text.strip_edges()
		var pos: Vector3 = Vector3(
			_parse_float(x_input.text, 0.0),
			_parse_float(y_input.text, 0.0),
			_parse_float(z_input.text, 0.0)
		)
		var mastery_val: int = int(mastery_spin.value)
		var selected_idx: int = parent_opt.selected
		var parent_id_val: String = ""
		if selected_idx >= 0 and selected_idx < parent_opt.item_count:
			var meta: Variant = parent_opt.get_item_metadata(selected_idx)
			if meta is String and not meta.is_empty():
				parent_id_val = meta
		if is_create:
			_do_create_node(node_name, desc_text, pos, mastery_val, parent_id_val)
		else:
			var old_item: Dictionary = item.duplicate(true)
			var old_parent_id := str(old_item.get("parent_id", ""))
			item["name"] = data_manager.generate_unique_name(node_name)
			item["description"] = desc_text
			item["position"] = [pos.x, pos.y, pos.z]
			item["mastery"] = mastery_val
			item["parent_id"] = parent_id_val
			if parent_id_val != old_parent_id:
				if parent_id_val.is_empty():
					item["galaxy_id"] = data_manager.next_available_galaxy_id()
				else:
					var pidx: int = data_manager.find_index_by_id(parent_id_val)
					if pidx >= 0:
						item["galaxy_id"] = int(data_manager.get_item(pidx).get("galaxy_id", 0))
				data_manager.propagate_galaxy_id(index, int(item["galaxy_id"]))
			data_manager.set_item(index, item)
			history_manager.record_operation("编辑节点: %s" % str(item.get("name", "")))
			data_manager.save_data()
			rebuild_all()
			request_focus_on_node(index)
		dlg.queue_free()
	)
	dlg.canceled.connect(func():
		dlg.queue_free()
	)
	dlg.popup_centered()
	name_input.grab_focus()


## 解析浮点数字符串，失败时返回默认值
func _parse_float(text: String, default_val: float) -> float:
	var t: String = text.strip_edges()
	if t.is_empty():
		return default_val
	return t.to_float()


## 执行创建节点操作，添加到数据管理器并重建视图
func _do_create_node(node_name: String, description: String, pos: Vector3, mastery: int, parent_id: String) -> void:
	var unique_name: String = data_manager.generate_unique_name(node_name)
	var unique_id: String = data_manager.generate_unique_id(unique_name.to_lower().replace(" ", "_"))
	var galaxy_id := 0
	if not parent_id.is_empty():
		var pidx: int = data_manager.find_index_by_id(parent_id)
		if pidx >= 0:
			galaxy_id = int(data_manager.get_item(pidx).get("galaxy_id", 0))
	var item: Dictionary = {
		"id": unique_id,
		"name": unique_name,
		"description": description,
		"mastery": mastery,
		"position": [pos.x, pos.y, pos.z],
		"parent_id": parent_id,
		"galaxy_id": galaxy_id,
		"relations": []
	}
	var new_index: int = data_manager.add_item(item)
	if data_manager.get_count() == 1:
		camera_target_theta = 0.0
		camera_target_phi = 0.3
		camera_target_radius = 15.0
	history_manager.record_operation("创建节点: %s" % unique_name)
	data_manager.save_data()
	rebuild_all()
	request_focus_on_node(new_index)


## 判断指定节点是否为自由节点（无父节点且非root）
func _is_free_node(index: int) -> bool:
	var item: Dictionary = data_manager.get_item(index)
	if item.is_empty():
		return false
	var node_id: String = str(item.get("id", ""))
	if node_id == "root":
		return false
	var pid: String = str(item.get("parent_id", ""))
	return pid.is_empty()


## 通过Tab键在选中节点下创建子节点
func _create_node_via_tab() -> void:
	if selected_index >= 0:
		_create_child_node(selected_index)
	else:
		_create_free_node_via_tab()


## 在指定父节点下创建子节点
func _create_child_node(parent_index: int) -> void:
	var parent_item: Dictionary = data_manager.get_item(parent_index)
	if parent_item.is_empty():
		return
	var parent_id: String = str(parent_item.get("id", ""))
	var parent_pos: Vector3 = point_manager.get_point_position(parent_index)
	var parent_galaxy := int(parent_item.get("galaxy_id", 0))
	var child_count: int = 0
	var total: int = data_manager.get_count()
	for i in total:
		var this_item: Dictionary = data_manager.get_item(i)
		if str(this_item.get("parent_id", "")) == parent_id:
			child_count += 1
	var create_pos: Vector3 = parent_pos + Vector3(2.0 + child_count * 0.5, 0.5 * child_count, child_count * 0.3)
	var unique_name: String = data_manager.generate_unique_name("New Node")
	var unique_id: String = data_manager.generate_unique_id(unique_name.to_lower().replace(" ", "_"))
	var item: Dictionary = {
		"id": unique_id,
		"name": unique_name,
		"description": "",
		"mastery": 0,
		"position": [create_pos.x, create_pos.y, create_pos.z],
		"parent_id": parent_id,
		"galaxy_id": parent_galaxy,
		"relations": []
	}
	var new_index: int = data_manager.add_item(item)
	if data_manager.get_count() == 1:
		camera_target_theta = 0.0
		camera_target_phi = 0.3
		camera_target_radius = 15.0
	history_manager.record_operation("创建子节点: %s" % unique_name)
	data_manager.save_data()
	rebuild_all()
	request_focus_on_node(new_index)


## 通过Tab键创建自由节点
func _create_free_node_via_tab() -> void:
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var create_pos: Vector3 = _mouse_to_plane(mouse_pos, 0.0)
	var unique_name: String = data_manager.generate_unique_name("New Node")
	var unique_id: String = data_manager.generate_unique_id(unique_name.to_lower().replace(" ", "_"))
	var new_galaxy: int = data_manager.next_available_galaxy_id()
	var item: Dictionary = {
		"id": unique_id,
		"name": unique_name,
		"description": "",
		"mastery": 0,
		"position": [create_pos.x, create_pos.y, create_pos.z],
		"parent_id": "",
		"galaxy_id": new_galaxy,
		"relations": []
	}
	var new_index: int = data_manager.add_item(item)
	if data_manager.get_count() == 1:
		camera_target_theta = 0.0
		camera_target_phi = 0.3
		camera_target_radius = 15.0
	history_manager.record_operation("创建自由节点: %s" % unique_name)
	data_manager.save_data()
	rebuild_all()
	request_focus_on_node(new_index)


## 显示指定节点的详情弹窗
func _show_detail_popup(index: int) -> void:
	var item: Dictionary = data_manager.get_item(index)
	if item.is_empty():
		return
	load("res://script/3dmm/DetailPopup.gd").show(item, data_manager, self)


## 上下文菜单动作回调，分发各种操作
func _on_context_menu_action(action: String, index: int, extra: Variant = null, mouse_pos: Variant = null) -> void:
	match action:
		"show_detail":
			_show_detail_popup(index)
		"focus_node":
			_focus_on_point(index)
			selected_index = index
			selected_indices = [index]
			point_manager.highlight_point(index, true)
		"unfocus_node":
			_orbiting_free_node_index = -1
			_has_focus_target = false
			_focus_target = Vector3.ZERO
		"set_mastery":
			if extra is int:
				var item: Dictionary = data_manager.get_item(index)
				if not item.is_empty():
					item["mastery"] = extra
					data_manager.set_item(index, item)
					data_manager.save_data()
					point_manager.update_single_point(index)
					point_manager.build_all_lines()
		"edit_node":
			_show_node_dialog("edit", index)
		"delete_node":
			_delete_node(index)
		"create_node":
			var create_pos: Vector3 = Vector3.ZERO
			if extra is Vector3:
				create_pos = extra
			elif extra is Vector2:
				create_pos = Vector3(extra.x, 0.0, extra.y)
			_show_node_dialog("create", index if index >= 0 else -1, create_pos)
		"auto_layout":
			layout_manager.apply_layout()
			point_manager.build_all_points()
			data_manager.save_data()
		"refresh":
			_has_focus_target = false
			_focus_target = Vector3.ZERO
			_orbiting_free_node_index = -1
			rebuild_all()
		"reset_view":
			_has_focus_target = false
			_focus_target = Vector3.ZERO
			_orbiting_free_node_index = -1
			camera_target_radius = 15.0
			camera_target_theta = 0.0
			camera_target_phi = 0.3
		"screenshot":
			_take_screenshot()
		"toggle_settings":
			_toggle_settings_panel()
		"delete_all_non_root":
			_delete_all_non_root()
		"batch_mastery":
			_batch_set_mastery(extra as int if extra is int else 1)
		"batch_delete":
			_batch_delete()
		"absorb_to_root":
			_absorb_to_root(index)
		"detach_as_galaxy":
			_detach_as_galaxy(index)


## 将节点吸收到根节点的星系中
func _absorb_to_root(index: int) -> void:
	if index < 0 or index >= data_manager.get_count():
		return
	var item: Dictionary = data_manager.get_item(index)
	if item.is_empty():
		return
	var root_idx: int = data_manager.find_index_by_id("root")
	if root_idx < 0:
		return
	var old_item: Dictionary = item.duplicate(true)
	data_manager.absorb_subtree(root_idx, index)
	history_manager.record_operation("吸收到根星系: %s" % str(item.get("name", "")))
	data_manager.save_data()
	rebuild_all()
	request_focus_on_node(index)


## 将节点从根星系分离为独立星系
func _detach_as_galaxy(index: int) -> void:
	if index < 0 or index >= data_manager.get_count():
		return
	var item: Dictionary = data_manager.get_item(index)
	if item.is_empty():
		return
	var node_id: String = str(item.get("id", ""))
	if node_id == "root":
		return
	var old_item: Dictionary = item.duplicate(true)
	data_manager.detach_subtree(index)
	history_manager.record_operation("分离为独立星系: %s" % str(item.get("name", "")))
	data_manager.save_data()
	rebuild_all()
	request_focus_on_node(index)


## 批量设置选中节点的掌握程度
func _batch_set_mastery(target_mastery: int) -> void:
	if selected_indices.is_empty():
		return
	for idx in selected_indices:
		var item: Dictionary = data_manager.get_item(idx)
		item["mastery"] = target_mastery
		item["color"] = ""
		data_manager.set_item(idx, item)
		point_manager.update_single_point(idx)
	history_manager.record_operation("批量设置掌握度")
	_clear_selection()
	data_manager.save_data()


## 删除指定节点及其子树
func _delete_node(index: int) -> void:
	if index < 0 or index >= data_manager.get_count():
		return
	var item: Dictionary = data_manager.get_item(index)
	var confirm_dlg := ConfirmationDialog.new()
	confirm_dlg.title = "确认删除"
	confirm_dlg.dialog_text = "确定要删除 \"%s\" 吗？\n其子节点将成为自由节点。" % str(item.get("name", ""))
	get_tree().root.add_child(confirm_dlg)
	confirm_dlg.confirmed.connect(func():
		var deleted_id: String = str(item.get("id", ""))
		history_manager.record_operation("删除节点: %s" % str(item.get("name", "")))
		data_manager.remove_item(index)
		var dcount: int = data_manager.get_count()
		for i in dcount:
			var child: Dictionary = data_manager.get_item(i)
			if str(child.get("parent_id", "")) == deleted_id:
				child["parent_id"] = ""
				var new_gid: int = data_manager.next_available_galaxy_id()
				child["galaxy_id"] = new_gid
				data_manager.propagate_galaxy_id(i, new_gid)
				data_manager.set_item(i, child)
		data_manager.cleanup_relations_for(str(item.get("name", "")))
		data_manager.cleanup_empty_galaxies()
		data_manager.save_data()
		rebuild_all()
		confirm_dlg.queue_free()
	)
	confirm_dlg.canceled.connect(func():
		confirm_dlg.queue_free()
	)
	confirm_dlg.popup_centered()


## 切换设置面板的显示
func _toggle_settings_panel() -> void:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		_settings_panel.visible = not _settings_panel.visible
		return
	_create_settings_panel()


## 创建3D视图设置面板，包含材质和显示参数调节
func _create_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.name = "MaterialSettingsPanel"
	var ui_layer: CanvasLayer = get_tree().root.get_node_or_null("*CanvasLayer*")
	if ui_layer == null:
		ui_layer = CanvasLayer.new()
		get_tree().root.add_child(ui_layer)
	ui_layer.add_child(_settings_panel)
	_settings_panel.custom_minimum_size = Vector2(300, 0)
	_settings_panel.anchor_left = 1.0
	_settings_panel.anchor_right = 1.0
	_settings_panel.offset_left = -320.0
	_settings_panel.offset_right = -10.0
	_settings_panel.offset_top = 50.0
	_settings_panel.offset_bottom = -10.0
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_panel.add_child(vbox)
	var title := Label.new()
	title.text = "【材质调试】"
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	var uc_row := HBoxContainer.new()
	vbox.add_child(uc_row)
	var uc_label := Label.new()
	uc_label.text = "未学习颜色"
	uc_row.add_child(uc_label)
	var uc_btn := ColorPickerButton.new()
	uc_btn.color = mat_unlearned_color
	uc_btn.custom_minimum_size.x = 80
	uc_btn.color_changed.connect(func(c: Color):
		mat_unlearned_color = c
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	uc_row.add_child(uc_btn)
	var lc_row := HBoxContainer.new()
	vbox.add_child(lc_row)
	var lc_label := Label.new()
	lc_label.text = "学习中颜色"
	lc_row.add_child(lc_label)
	var lc_btn := ColorPickerButton.new()
	lc_btn.color = mat_learning_color
	lc_btn.custom_minimum_size.x = 80
	lc_btn.color_changed.connect(func(c: Color):
		mat_learning_color = c
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	lc_row.add_child(lc_btn)
	var lrn_row := HBoxContainer.new()
	vbox.add_child(lrn_row)
	var lrn_label := Label.new()
	lrn_label.text = "已掌握颜色"
	lrn_row.add_child(lrn_label)
	var lrn_btn := ColorPickerButton.new()
	lrn_btn.color = mat_learned_color
	lrn_btn.custom_minimum_size.x = 80
	lrn_btn.color_changed.connect(func(c: Color):
		mat_learned_color = c
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	lrn_row.add_child(lrn_btn)
	vbox.add_child(HSeparator.new())
	var rough_row := HBoxContainer.new()
	vbox.add_child(rough_row)
	var rough_lbl := Label.new()
	rough_lbl.text = "粗糙度"
	rough_row.add_child(rough_lbl)
	var rough_spin := SpinBox.new()
	rough_spin.min_value = 0.0
	rough_spin.max_value = 1.0
	rough_spin.step = 0.05
	rough_spin.value = mat_roughness
	rough_spin.value_changed.connect(func(v: float):
		mat_roughness = v
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	rough_row.add_child(rough_spin)
	var metal_row := HBoxContainer.new()
	vbox.add_child(metal_row)
	var metal_lbl := Label.new()
	metal_lbl.text = "金属度"
	metal_row.add_child(metal_lbl)
	var metal_spin := SpinBox.new()
	metal_spin.min_value = 0.0
	metal_spin.max_value = 1.0
	metal_spin.step = 0.05
	metal_spin.value = mat_metallic
	metal_spin.value_changed.connect(func(v: float):
		mat_metallic = v
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	metal_row.add_child(metal_spin)
	var emit_row := HBoxContainer.new()
	vbox.add_child(emit_row)
	var emit_lbl := Label.new()
	emit_lbl.text = "发光强度"
	emit_row.add_child(emit_lbl)
	var emit_spin := SpinBox.new()
	emit_spin.min_value = 0.0
	emit_spin.max_value = 5.0
	emit_spin.step = 0.1
	emit_spin.value = mat_emission_energy
	emit_spin.value_changed.connect(func(v: float):
		mat_emission_energy = v
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	emit_row.add_child(emit_spin)
	vbox.add_child(HSeparator.new())
	var sel_row := HBoxContainer.new()
	vbox.add_child(sel_row)
	var sel_lbl := Label.new()
	sel_lbl.text = "选中高亮色"
	sel_row.add_child(sel_lbl)
	var sel_btn := ColorPickerButton.new()
	sel_btn.color = mat_selected_color
	sel_btn.custom_minimum_size.x = 80
	sel_btn.color_changed.connect(func(c: Color):
		mat_selected_color = c
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	sel_row.add_child(sel_btn)
	var sel_em_row := HBoxContainer.new()
	vbox.add_child(sel_em_row)
	var sel_em_lbl := Label.new()
	sel_em_lbl.text = "选中发光倍数"
	sel_em_row.add_child(sel_em_lbl)
	var sel_em_spin := SpinBox.new()
	sel_em_spin.min_value = 1.0
	sel_em_spin.max_value = 5.0
	sel_em_spin.step = 0.1
	sel_em_spin.value = mat_selected_emission_mult
	sel_em_spin.value_changed.connect(func(v: float):
		mat_selected_emission_mult = v
		_sync_materials_to_point_manager()
		_refresh_all_point_materials()
	)
	sel_em_row.add_child(sel_em_spin)


## 将设置面板的材质参数同步到点管理器
func _sync_materials_to_point_manager() -> void:
	point_manager.set_mat_unlearned_color(mat_unlearned_color)
	point_manager.set_mat_learning_color(mat_learning_color)
	point_manager.set_mat_learned_color(mat_learned_color)
	point_manager.set_mat_roughness(mat_roughness)
	point_manager.set_mat_metallic(mat_metallic)
	point_manager.set_mat_emission_energy(mat_emission_energy)
	point_manager.set_mat_selected_color(mat_selected_color)
	point_manager.set_mat_selected_emission_mult(mat_selected_emission_mult)


## 刷新所有点的材质
func _refresh_all_point_materials() -> void:
	point_manager.refresh_all_materials()


## 截取3D视口截图并保存为PNG
func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var timestamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var save_path: String = "user://screenshot_%s.png" % timestamp
	image.save_png(save_path)
	print("Screenshot saved to: %s" % save_path)


## 计算所有知识点的中心位置
func get_points_center() -> Vector3:
	return data_manager.get_points_center()


## 获取根节点的3D位置
func _get_root_node_position() -> Vector3:
	for i in data_manager.get_count():
		var item = data_manager.get_item(i)
		if str(item.get("id", "")) == "root":
			var pos = item.get("position", [0.0, 0.0, 0.0])
			return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return Vector3.ZERO
