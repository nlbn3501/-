## 认知视图力导向布局优化器，使用斥力-引力模型自动排列节点，检测和解决节点重叠
extends RefCounted

var data_manager: RefCounted
var mindmap_2d: RefCounted
var node_positions: Dictionary = {}

var repulsion_strength: float = 5000.0
var attraction_strength: float = 0.01
var center_gravity: float = 0.005
var ideal_distance: float = 150.0
var max_iterations: int = 150
var convergence_threshold: float = 0.5

func _init(dm: RefCounted, mm_2d: RefCounted) -> void:
	data_manager = dm
	mindmap_2d = mm_2d

## 执行力导向布局优化
func optimize_layout() -> void:
	var node_controls: Dictionary = mindmap_2d.node_controls
	if node_controls.is_empty():
		return
	
	_collect_positions(node_controls)
	
	for iteration in max_iterations:
		var total_movement: float = _calculate_forces(node_controls)
		_apply_positions(node_controls)
		
		if total_movement < convergence_threshold:
			break
	
	_update_data_positions(node_controls)

func detect_node_conflicts() -> Array:
	var conflicts: Array = []
	var node_controls: Dictionary = mindmap_2d.node_controls
	var indices: Array = node_controls.keys()
	
	for i in range(indices.size()):
		for j in range(i + 1, indices.size()):
			var panel_a: PanelContainer = node_controls[indices[i]]
			var panel_b: PanelContainer = node_controls[indices[j]]
			
			if _rects_overlap(panel_a, panel_b):
				conflicts.append({
					"node_a": indices[i],
					"node_b": indices[j],
					"overlap": _calculate_overlap(panel_a, panel_b)
				})
	
	return conflicts

func resolve_conflicts(conflicts: Array) -> void:
	var node_controls: Dictionary = mindmap_2d.node_controls
	
	for conflict in conflicts:
		var index_a: int = conflict["node_a"]
		var index_b: int = conflict["node_b"]
		
		if not node_controls.has(index_a) or not node_controls.has(index_b):
			continue
		
		var panel_a: PanelContainer = node_controls[index_a]
		var panel_b: PanelContainer = node_controls[index_b]
		
		var center_a: Vector2 = panel_a.position + panel_a.size / 2.0
		var center_b: Vector2 = panel_b.position + panel_b.size / 2.0
		
		var direction: Vector2 = (center_b - center_a).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2(1, 0)
		
		var push_distance: float = conflict["overlap"] / 2.0 + 10.0
		panel_a.position -= direction * push_distance
		panel_b.position += direction * push_distance

## 将没有父节点且非root的自由节点排列到左侧区域
func arrange_free_nodes() -> void:
	var node_controls: Dictionary = mindmap_2d.node_controls
	var free_start_x: float = 400.0
	var free_start_y: float = 0.0
	var free_y_spacing: float = 180.0
	var free_index: int = 0
	
	for index in node_controls.keys():
		var item: Dictionary = data_manager.call("get_item", index)
		var parent_id: String = str(item.get("parent_id", ""))
		var node_id: String = str(item.get("id", ""))
		
		if parent_id == "" and node_id != "root":
			var panel: PanelContainer = node_controls[index]
			panel.position = Vector2(free_start_x, free_start_y + free_index * free_y_spacing)
			free_index += 1

## 收集所有节点的当前位置
func _collect_positions(node_controls: Dictionary) -> void:
	node_positions.clear()
	for index in node_controls.keys():
		var panel: PanelContainer = node_controls[index]
		node_positions[index] = {
			"x": panel.position.x + panel.size.x / 2.0,
			"y": panel.position.y + panel.size.y / 2.0,
			"vx": 0.0,
			"vy": 0.0
		}

## 计算所有节点的力
func _calculate_forces(node_controls: Dictionary) -> float:
	var total_movement: float = 0.0
	var indices: Array = node_positions.keys()
	
	for i in indices:
		var pos_a: Dictionary = node_positions[i]
		var fx: float = 0.0
		var fy: float = 0.0
		
		for j in indices:
			if i == j:
				continue
			var pos_b: Dictionary = node_positions[j]
			var dx: float = pos_a["x"] - pos_b["x"]
			var dy: float = pos_a["y"] - pos_b["y"]
			var dist_sq: float = dx * dx + dy * dy
			if dist_sq < 1.0:
				dist_sq = 1.0
			var dist: float = sqrt(dist_sq)
			
			var repulsion: float = repulsion_strength / dist_sq
			fx += (dx / dist) * repulsion
			fy += (dy / dist) * repulsion
		
		var item: Dictionary = data_manager.call("get_item", i)
		var parent_id: String = str(item.get("parent_id", ""))
		if parent_id != "":
			var parent_idx: int = mindmap_2d.find_node_index(parent_id)
			if parent_idx >= 0 and node_positions.has(parent_idx):
				var parent_pos: Dictionary = node_positions[parent_idx]
				var dx: float = parent_pos["x"] - pos_a["x"]
				var dy: float = parent_pos["y"] - pos_a["y"]
				fx += dx * attraction_strength
				fy += dy * attraction_strength
		
		var center_x: float = 3600.0 * mindmap_2d.zoom_scale
		var center_y: float = 2700.0 * mindmap_2d.zoom_scale
		fx -= (pos_a["x"] - center_x) * center_gravity
		fy -= (pos_a["y"] - center_y) * center_gravity
		
		pos_a["vx"] = (pos_a["vx"] + fx) * 0.9
		pos_a["vy"] = (pos_a["vy"] + fy) * 0.9
		
		total_movement += abs(pos_a["vx"]) + abs(pos_a["vy"])
	
	return total_movement

## 将速度应用到节点位置
func _apply_positions(node_controls: Dictionary) -> void:
	for index in node_positions.keys():
		var pos: Dictionary = node_positions[index]
		pos["x"] += pos["vx"]
		pos["y"] += pos["vy"]

## 将优化后的位置更新到节点控件和数据
func _update_data_positions(node_controls: Dictionary) -> void:
	for index in node_positions.keys():
		var pos: Dictionary = node_positions[index]
		if node_controls.has(index):
			var panel: PanelContainer = node_controls[index]
			panel.position = Vector2(pos["x"] - panel.size.x / 2.0, pos["y"] - panel.size.y / 2.0)

## 判断两个面板矩形是否重叠
func _rects_overlap(panel_a: PanelContainer, panel_b: PanelContainer) -> bool:
	var a_pos: Vector2 = panel_a.position
	var a_size: Vector2 = panel_a.size
	var b_pos: Vector2 = panel_b.position
	var b_size: Vector2 = panel_b.size
	
	return a_pos.x < b_pos.x + b_size.x and \
		a_pos.x + a_size.x > b_pos.x and \
		a_pos.y < b_pos.y + b_size.y and \
		a_pos.y + a_size.y > b_pos.y

## 计算两个面板的重叠面积
func _calculate_overlap(panel_a: PanelContainer, panel_b: PanelContainer) -> float:
	var a_pos: Vector2 = panel_a.position
	var a_size: Vector2 = panel_a.size
	var b_pos: Vector2 = panel_b.position
	var b_size: Vector2 = panel_b.size
	
	var overlap_x: float = min(a_pos.x + a_size.x, b_pos.x + b_size.x) - max(a_pos.x, b_pos.x)
	var overlap_y: float = min(a_pos.y + a_size.y, b_pos.y + b_size.y) - max(a_pos.y, b_pos.y)
	
	return overlap_x * overlap_y
