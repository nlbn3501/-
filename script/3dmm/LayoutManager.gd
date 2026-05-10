## 3D布局管理器，使用斐波那契球面分布算法将知识点按星系和深度分层排列在3D空间中
extends RefCounted

var tree_base_radius: float = 2.0
var tree_radius_increment: float = 1.5
var root_node_radius: float = 0.8
var depth_scale_factor: float = 0.8
var galaxy_gap: float = 5.0
var min_spacing: float = 1.5

var data_manager: RefCounted

signal layout_completed()


## 初始化布局管理器，绑定数据管理器
func _init(manager: RefCounted) -> void:
	data_manager = manager


## 应用布局，计算所有节点的3D位置
func apply_layout() -> void:
	if data_manager.get_count() == 0:
		return
	_apply_multi_galaxy_layout()
	layout_completed.emit()


## 多星系布局，将节点按galaxy_id分组后分别布局
func _apply_multi_galaxy_layout() -> void:
	var galaxy_groups: Dictionary = {}
	var all_ids: Array = data_manager.get_all_galaxy_ids()

	for gid in all_ids:
		galaxy_groups[gid] = data_manager.get_galaxy_nodes(gid)

	var max_root_radius := 0.0
	if galaxy_groups.has(0):
		max_root_radius = _layout_galaxy(galaxy_groups[0], Vector3.ZERO)

	var free_galaxy_ids: Array = []
	for gid in all_ids:
		if int(gid) > 0:
			free_galaxy_ids.append(int(gid))

	if free_galaxy_ids.size() > 0:
		var orbit_radius := max_root_radius + galaxy_gap
		var free_centers := _distribute_free_galaxies(free_galaxy_ids, orbit_radius)
		for gid in free_galaxy_ids:
			if free_centers.has(gid):
				var center: Vector3 = free_centers[gid]
				if galaxy_groups.has(gid):
					_layout_galaxy(galaxy_groups[gid], center)


## 对单个星系内的节点按深度分层布局
func _layout_galaxy(indices: Array, center: Vector3) -> float:
	if indices.is_empty():
		return 0.0

	var depths: Array = data_manager.compute_depths()
	var depth_nodes: Dictionary = {}

	for idx in indices:
		if idx < 0 or idx >= depths.size():
			continue
		var d: int = depths[idx]
		if not depth_nodes.has(d):
			depth_nodes[d] = []
		depth_nodes[d].append(idx)

	# 收集每个节点的 parent 信息（用于兄弟聚拢）
	var parent_id_map: Dictionary = {} # idx -> parent_id string
	for idx in indices:
		var item: Dictionary = data_manager.get_item(idx)
		parent_id_map[idx] = str(item.get("parent_id", ""))

	var max_radius := 0.0
	var depth_keys := depth_nodes.keys()
	depth_keys.sort()

	for d in depth_keys:
		var nodes_at_depth: Array = depth_nodes[d]
		if nodes_at_depth.is_empty():
			continue

		if d == 0:
			for idx in nodes_at_depth:
				data_manager.set_item_position(idx, center)
			max_radius = max(max_radius, 0.0)
		else:
			var base_radius: float = tree_base_radius + float(d) * tree_radius_increment
			var count: int = nodes_at_depth.size()
			var actual_radius: float = _adaptive_radius(count, base_radius)
			actual_radius = max(actual_radius, max_radius + tree_radius_increment * 0.5)

			var fib_positions: Array = []
			for i in count:
				fib_positions.append(center + _fibonacci_sphere(i, count, actual_radius))

			var assignment: Dictionary = _assign_by_parent_proximity(nodes_at_depth, fib_positions, center)

			for idx in assignment:
				data_manager.set_item_position(idx, assignment[idx])

			max_radius = max(max_radius, actual_radius)

	return max_radius


## 按父节点方位角将同层节点分配到斐波那契位置
func _assign_by_parent_proximity(nodes_at_depth: Array, fib_positions: Array, center: Vector3) -> Dictionary:
	var assignment: Dictionary = {}
	var available_indices: Array = []
	for i in fib_positions.size():
		available_indices.append(i)

	var children_by_parent: Dictionary = {}
	var parent_pos_map: Dictionary = {}
	for idx in nodes_at_depth:
		var item: Dictionary = data_manager.get_item(idx)
		var pid: String = str(item.get("parent_id", ""))
		if not children_by_parent.has(pid):
			children_by_parent[pid] = []
		children_by_parent[pid].append(idx)
		if not parent_pos_map.has(pid):
			if pid.is_empty():
				parent_pos_map[pid] = center
			else:
				var pidx: int = _find_index_by_id(pid)
				if pidx >= 0:
					var pitem: Dictionary = data_manager.get_item(pidx)
					var ppos = pitem.get("position", [0.0, 0.0, 0.0])
					parent_pos_map[pid] = Vector3(float(ppos[0]), float(ppos[1]), float(ppos[2]))
				else:
					parent_pos_map[pid] = center

	var parent_keys: Array = children_by_parent.keys()
	parent_keys.sort_custom(func(a, b): return children_by_parent[a].size() > children_by_parent[b].size())

	for pid in parent_keys:
		var children: Array = children_by_parent[pid]
		var ppos: Vector3 = parent_pos_map[pid]

		var sorted_available: Array = available_indices.duplicate()
		sorted_available.sort_custom(func(a, b): return fib_positions[a].distance_to(ppos) < fib_positions[b].distance_to(ppos))

		for child_idx in children:
			if sorted_available.is_empty():
				break
			var best_pos_idx: int = sorted_available.pop_front()
			assignment[child_idx] = fib_positions[best_pos_idx]
			available_indices.erase(best_pos_idx)
			for k in range(sorted_available.size() - 1, -1, -1):
				if sorted_available[k] == best_pos_idx:
					sorted_available.remove_at(k)
					break

	for idx in nodes_at_depth:
		if not assignment.has(idx):
			if not available_indices.is_empty():
				assignment[idx] = fib_positions[available_indices.pop_front()]

	return assignment


## 按父节点方位角排序节点索引
func _sort_by_parent_azimuth(indices: Array, depths: Array, center: Vector3) -> Array:
	# 对同层节点按父节点方位角排序，使兄弟节点在 Fibonacci 球面上相邻
	var sorted_pairs: Array = [] # [azimuth, idx]
	for idx in indices:
		var item: Dictionary = data_manager.get_item(idx)
		var pid: String = str(item.get("parent_id", ""))
		var azimuth: float = 0.0
		if not pid.is_empty():
			var pidx: int = _find_index_by_id(pid)
			if pidx >= 0:
				var pitem: Dictionary = data_manager.get_item(pidx)
				var ppos_arr = pitem.get("position", [0.0, 0.0, 0.0])
				var ppos := Vector3(float(ppos_arr[0]), float(ppos_arr[1]), float(ppos_arr[2]))
				var rel: Vector3 = ppos - center
				azimuth = atan2(rel.z, rel.x)
		sorted_pairs.append([azimuth, idx])

	sorted_pairs.sort_custom(func(a, b): return a[0] < b[0])

	var result: Array = []
	for pair in sorted_pairs:
		result.append(pair[1])
	return result


## 斐波那契球面均匀分布算法，返回第index个点在球面上的位置
func _fibonacci_sphere(index: int, total: int, radius: float) -> Vector3:
	if total <= 0:
		return Vector3.ZERO
	if total == 1:
		return Vector3(0.0, radius, 0.0)

	var golden_ratio := (1.0 + sqrt(5.0)) / 2.0
	var phi := acos(1.0 - 2.0 * (float(index) + 0.5) / float(total))
	var theta := 2.0 * PI * float(index) / golden_ratio

	var x: float = radius * sin(phi) * cos(theta)
	var y: float = radius * cos(phi)
	var z: float = radius * sin(phi) * sin(theta)

	return Vector3(x, y, z)


## 根据节点数量自适应调整球面半径
func _adaptive_radius(node_count: int, base_radius: float) -> float:
	var radius: float = base_radius
	while _needs_more_space(node_count, radius):
		radius += tree_radius_increment * 0.5
	return radius


## 判断当前半径是否需要扩展以容纳所有节点
func _needs_more_space(node_count: int, radius: float) -> bool:
	var sphere_area: float = 4.0 * PI * radius * radius
	var node_area: float = min_spacing * min_spacing
	var needed_area: float = float(node_count) * node_area
	return needed_area > sphere_area


## 将自由星系均匀分布在轨道上
func _distribute_free_galaxies(free_galaxy_ids: Array, base_orbit_radius: float) -> Dictionary:
	var centers: Dictionary = {}
	var count: int = free_galaxy_ids.size()
	if count == 0:
		return centers

	var orbit_radius: float = base_orbit_radius

	var max_free_size := 0
	for gid in free_galaxy_ids:
		var nodes: Array = data_manager.get_galaxy_nodes(gid)
		max_free_size = max(max_free_size, nodes.size())

	while _needs_more_space(count, orbit_radius * 0.5):
		orbit_radius += galaxy_gap * 0.5

	for i in count:
		var gid: int = free_galaxy_ids[i]
		centers[gid] = _fibonacci_sphere(i, count, orbit_radius)

	return centers


## 获取指定深度的球面半径
func radius_for_depth(depth: int) -> float:
	return root_node_radius * pow(depth_scale_factor, float(min(depth, 3)))


## 估算指定星系节点的布局半径
func estimate_galaxy_radius(galaxy_node_indices: Array) -> float:
	if galaxy_node_indices.is_empty():
		return 3.0

	var center := Vector3.ZERO
	for idx in galaxy_node_indices:
		var item: Dictionary = data_manager.get_item(idx)
		var pos = item.get("position", [0.0, 0.0, 0.0])
		center += Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	center /= float(galaxy_node_indices.size())

	var max_dist := 0.0
	for idx in galaxy_node_indices:
		var item: Dictionary = data_manager.get_item(idx)
		var pos = item.get("position", [0.0, 0.0, 0.0])
		var node_pos := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var dist := center.distance_to(node_pos)
		if dist > max_dist:
			max_dist = dist

	return max(max_dist, 3.0)

## 通过节点ID查找数据项索引
func _find_index_by_id(node_id: String) -> int:
	for i in data_manager.get_count():
		var item: Dictionary = data_manager.get_item(i)
		if str(item.get("id", "")) == node_id:
			return i
	return -1
