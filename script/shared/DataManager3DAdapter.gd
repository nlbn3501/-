## 数据管理器3D适配器，将2D数据管理器的接口适配为3D知识导图所需的接口格式
extends RefCounted

var _base_dm: RefCounted

## 初始化3D适配器，绑定2D数据管理器
func _init(base_dm: RefCounted) -> void:
	_base_dm = base_dm

## 获取数据项数量
func get_count() -> int:
	return _base_dm.get_count()

## 获取指定索引的数据项
func get_item(index: int) -> Dictionary:
	return _base_dm.get_item(index)

## 设置指定索引的数据项
func set_item(index: int, item: Dictionary) -> void:
	_base_dm.set_item(index, item)

## 添加一个数据项
func add_item(item: Dictionary) -> int:
	return _base_dm.add_item(item)

## 移除指定索引的数据项
func remove_item(index: int) -> void:
	_base_dm.remove_item(index)

## 保存数据到文件
func save_data() -> void:
	_base_dm.save_data()

## 从文件加载数据
func load_data() -> void:
	_base_dm.load_data()

## 生成不重复的名称
func generate_unique_name(base_name: String) -> String:
	return _base_dm.generate_unique_name(base_name)

## 生成唯一节点ID
func generate_unique_id(base_name: String) -> String:
	return _base_dm.generate_unique_id(base_name)

## 通过节点ID查找数据项索引
func find_index_by_id(node_id: String) -> int:
	return _base_dm.find_index_by_id(node_id)

## 计算所有节点的深度
func compute_depths() -> Array:
	return _base_dm.compute_depths()

## 获取当前数据的深拷贝快照
func get_items_snapshot() -> Array:
	return _base_dm.get_items_snapshot()

## 从快照恢复数据
func restore_items_snapshot(snapshot: Array) -> void:
	_base_dm.restore_items_snapshot(snapshot)

## 收集所有父子边关系
func collect_edges() -> Array:
	var edges: Array = []
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		var parent_id: String = str(item.get("parent_id", ""))
		if parent_id:
			edges.append({
				"from": find_index_by_id(parent_id),
				"to": i
			})
	return edges

## 收集所有关系数据
func collect_relations() -> Array:
	var relations: Array = []
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		var item_relations: Array = item.get("relations", [])
		for rel in item_relations:
			relations.append({
				"from_index": i,
				"from_name": str(item.get("name", "")),
				"to_name": str(rel.get("target", "")),
				"type": str(rel.get("type", "")),
			})
	return relations

## 计算所有知识点的3D中心位置
func get_points_center() -> Vector3:
	var count: int = get_count()
	if count == 0:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var valid_count := 0
	for i in count:
		var item: Dictionary = get_item(i)
		var pos3d: Array = item.get("pos3d", [0.0, 0.0, 0.0])
		if pos3d.size() >= 3:
			sum += Vector3(float(pos3d[0]), float(pos3d[1]), float(pos3d[2]))
			valid_count += 1
	if valid_count > 0:
		return sum / valid_count
	return Vector3.ZERO

## 获取指定星系ID的所有节点索引
func get_galaxy_nodes(galaxy_id: int) -> Array:
	var nodes: Array = []
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		if int(item.get("galaxy_id", 0)) == galaxy_id:
			nodes.append(i)
	return nodes

## 获取指定父节点的子节点索引列表
func get_children_of(parent_id: String) -> Array:
	var children: Array = []
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		if str(item.get("parent_id", "")) == parent_id:
			children.append(i)
	return children

## 获取下一个可用的星系ID
func next_available_galaxy_id() -> int:
	var max_gid: int = 0
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		var gid: int = int(item.get("galaxy_id", 0))
		if gid > max_gid:
			max_gid = gid
	return max_gid + 1

## 递归传播星系ID到子树所有节点
func propagate_galaxy_id(index: int, galaxy_id: int) -> void:
	var item: Dictionary = get_item(index)
	item["galaxy_id"] = galaxy_id
	set_item(index, item)
	var children: Array = get_children_of(str(item.get("id", "")))
	for child_idx in children:
		propagate_galaxy_id(child_idx, galaxy_id)

## 清理指定节点名称的所有关系引用
func cleanup_relations_for(node_name: String) -> void:
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		var relations: Array = item.get("relations", [])
		var new_relations: Array = []
		for rel in relations:
			if str(rel.get("target", "")) != node_name:
				new_relations.append(rel)
		if new_relations.size() != relations.size():
			item["relations"] = new_relations
			set_item(i, item)

## 清理空星系（无节点的星系）
func cleanup_empty_galaxies() -> void:
	pass

## 将子树吸收到目标节点所在的星系
func absorb_subtree(root_idx: int, target_idx: int) -> void:
	var root_item: Dictionary = get_item(root_idx)
	var target_item: Dictionary = get_item(target_idx)
	var root_galaxy_id: int = int(root_item.get("galaxy_id", 0))
	target_item["galaxy_id"] = root_galaxy_id
	target_item["parent_id"] = str(root_item.get("id", ""))
	set_item(target_idx, target_item)
	propagate_galaxy_id(target_idx, root_galaxy_id)

## 将子树从当前星系分离为独立星系
func detach_subtree(index: int) -> void:
	var item: Dictionary = get_item(index)
	var new_galaxy_id: int = next_available_galaxy_id()
	item["galaxy_id"] = new_galaxy_id
	item["parent_id"] = ""
	set_item(index, item)
	propagate_galaxy_id(index, new_galaxy_id)

## 获取所有已使用的星系ID列表
func get_all_galaxy_ids() -> Array:
	var ids: Array = []
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		var gid: int = int(item.get("galaxy_id", 0))
		if not ids.has(gid):
			ids.append(gid)
	return ids

## 设置指定节点的3D位置
func set_item_position(index: int, pos: Vector3) -> void:
	var item: Dictionary = get_item(index)
	item["position"] = [pos.x, pos.y, pos.z]
	set_item(index, item)

## 获取指定星系的根节点索引
func get_galaxy_root_index(galaxy_id: int) -> int:
	var count: int = get_count()
	for i in count:
		var item: Dictionary = get_item(i)
		if int(item.get("galaxy_id", 0)) == galaxy_id:
			var parent_id: String = str(item.get("parent_id", ""))
			if parent_id.is_empty() or str(item.get("id", "")) == "root":
				return i
			var parent_idx: int = find_index_by_id(parent_id)
			if parent_idx < 0:
				return i
			var parent_item: Dictionary = get_item(parent_idx)
			if int(parent_item.get("galaxy_id", 0)) != galaxy_id:
				return i
	return -1

## 获取从根节点到指定节点的路径字符串
func get_node_path(index: int) -> String:
	return _base_dm.get_node_path(index)
