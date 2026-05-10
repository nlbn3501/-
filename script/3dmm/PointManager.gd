## 3D知识点可视化管理器，管理球体节点、连线和关系线的创建、更新和交互
extends RefCounted

var point_nodes: Array[MeshInstance3D] = []
var point_bodies: Array[StaticBody3D] = []
var point_labels: Array[Label3D] = []
var line_instances: Array[MeshInstance3D] = []

var data_manager: RefCounted
var layout_manager: RefCounted
var root_node: Node3D
var _lines_container: Node3D

var global_sphere_scale: float = 1.0
var mat_unlearned_color: Color = Color(0.6, 0.6, 0.6)
var mat_learning_color: Color = Color(1.0, 0.7, 0.2)
var mat_learned_color: Color = Color(0.2, 0.85, 0.2)
var mat_roughness: float = 0.3
var mat_metallic: float = 0.0
var mat_emission_energy: float = 0.8
var mat_selected_color: Color = Color(1.0, 1.0, 0.3)
var mat_selected_emission_mult: float = 2.0

var line_tube_radius: float = 0.03
var line_radial_segments: int = 6
var line_length_segments: int = 12

signal points_rebuilt()


## 初始化点管理器，绑定数据管理器、布局管理器和根节点
func _init(manager: RefCounted, layout: RefCounted, root: Node3D) -> void:
	data_manager = manager
	layout_manager = layout
	root_node = root


## 确保连线容器节点存在
func _ensure_lines_container() -> void:
	if _lines_container != null and is_instance_valid(_lines_container):
		return
	_lines_container = Node3D.new()
	_lines_container.name = "LinesContainer"
	root_node.add_child(_lines_container)


## 构建所有知识点的3D球体可视化
func build_all_points() -> void:
	clear_all()
	_ensure_lines_container()

	var count: int = data_manager.get_count()
	var depths: Array = data_manager.compute_depths()
	for i in count:
		var item: Dictionary = data_manager.get_item(i)
		var pos: Vector3 = _resolve_position(item, i)
		_create_point_visual(i, item, pos, depths)

	build_all_lines()
	points_rebuilt.emit()


## 清除所有3D节点和连线
func clear_all() -> void:
	for child in root_node.get_children():
		if child is MeshInstance3D or child is Label3D or child is StaticBody3D:
			child.queue_free()
		elif child.name == "LinesContainer":
			for lc in child.get_children():
				lc.queue_free()
	point_nodes.clear()
	point_bodies.clear()
	point_labels.clear()
	line_instances.clear()


## 创建单个知识点的3D球体视觉节点
func _create_point_visual(index: int, item: Dictionary, pos: Vector3, depths: Array = []) -> void:
	var depth: int = 0
	if index < depths.size():
		depth = depths[index]
	elif depths.is_empty():
		var computed: Array = data_manager.compute_depths()
		if index < computed.size():
			depth = computed[index]
	var radius: float = layout_manager.call("radius_for_depth", depth) * global_sphere_scale

	var sphere: MeshInstance3D = MeshInstance3D.new()
	sphere.name = "KnowledgePoint_%d" % index
	var sphere_mesh: SphereMesh = SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	sphere.mesh = sphere_mesh
	sphere.position = pos
	sphere.material_override = _create_point_material_from_item(item)
	root_node.add_child(sphere)
	point_nodes.append(sphere)

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "KnowledgePointBody_%d" % index
	body.position = pos
	body.set_meta("point_index", index)
	root_node.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere_shape: SphereShape3D = SphereShape3D.new()
	sphere_shape.radius = radius * 1.05
	shape.shape = sphere_shape
	body.add_child(shape)
	point_bodies.append(body)

	var label: Label3D = Label3D.new()
	label.name = "KnowledgeLabel_%d" % index
	label.text = str(item.get("name", "未命名"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1, 1, 1, 0.9)
	label.position = pos + Vector3(0, radius + 0.4, 0)
	label.font_size = 64
	label.pixel_size = radius * 0.015
	label.outline_size = 4
	root_node.add_child(label)
	point_labels.append(label)


## 根据掌握程度创建材质
func _create_point_material(mastery: int) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	var base_color: Color
	if mastery >= 2:
		base_color = mat_learned_color
	elif mastery >= 1:
		base_color = mat_learning_color
	else:
		base_color = mat_unlearned_color
	mat.albedo_color = base_color
	mat.roughness = mat_roughness
	mat.emission_enabled = true
	mat.emission = base_color
	mat.emission_energy_multiplier = mat_emission_energy
	return mat


## 根据数据项创建材质
func _create_point_material_from_item(item: Dictionary) -> StandardMaterial3D:
	var mat: StandardMaterial3D = _create_point_material(int(item.get("mastery", 0)))
	if str(item.get("color", "")).to_lower() == "red":
		mat.albedo_color = Color(0.9, 0.25, 0.25)
		mat.emission = Color(0.9, 0.25, 0.25)
	return mat


## 更新单个知识点的视觉表现
func update_single_point(index: int) -> void:
	var count: int = data_manager.get_count()
	if index < 0 or index >= count:
		return
	if index >= point_nodes.size():
		return

	var item: Dictionary = data_manager.get_item(index)
	if not is_instance_valid(point_nodes[index]):
		return

	point_nodes[index].material_override = _create_point_material_from_item(item)

	var pos: Vector3 = _resolve_position(item, index)
	point_nodes[index].position = pos
	if index < point_bodies.size() and is_instance_valid(point_bodies[index]):
		point_bodies[index].position = pos

	if index < point_labels.size() and is_instance_valid(point_labels[index]):
		var depths: Array = data_manager.compute_depths()
		var radius: float = layout_manager.call("radius_for_depth", depths[index]) * global_sphere_scale
		point_labels[index].position = pos + Vector3(0, radius + 0.4, 0)
		point_labels[index].text = str(item.get("name", "未命名"))


## 解析节点的3D位置
func _resolve_position(item: Dictionary, index: int) -> Vector3:
	if item.has("position"):
		var pos: Variant = item.get("position")
		if pos is Array and pos.size() >= 3:
			return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return Vector3(float(index) * 1.4, 0.0, 0.0)


## 设置指定节点的3D位置并更新数据
func set_point_position(index: int, pos: Vector3) -> void:
	if index < 0 or index >= point_nodes.size():
		return
	point_nodes[index].position = pos
	if index < point_bodies.size() and is_instance_valid(point_bodies[index]):
		point_bodies[index].position = pos
	if index < point_labels.size() and is_instance_valid(point_labels[index]):
		var depths: Array = data_manager.compute_depths()
		var radius: float = layout_manager.call("radius_for_depth", depths[index]) * global_sphere_scale
		point_labels[index].position = pos + Vector3(0, radius + 0.4, 0)

	var item: Dictionary = data_manager.get_item(index)
	item["position"] = [pos.x, pos.y, pos.z]
	data_manager.set_item(index, item)


## 高亮或取消高亮指定节点
func highlight_point(index: int, enable: bool) -> void:
	if index < 0 or index >= point_nodes.size():
		return
	var count: int = data_manager.get_count()
	if index >= count:
		return
	var mat: StandardMaterial3D = point_nodes[index].material_override as StandardMaterial3D
	if mat:
		if enable:
			mat.emission = mat_selected_color
			mat.emission_energy_multiplier = mat_emission_energy * mat_selected_emission_mult
		else:
			var item: Dictionary = data_manager.get_item(index)
			var m: int = int(item.get("mastery", 0))
			var base_color: Color
			if m >= 2:
				base_color = mat_learned_color
			elif m >= 1:
				base_color = mat_learning_color
			else:
				base_color = mat_unlearned_color
			mat.emission = base_color
			mat.emission_energy_multiplier = mat_emission_energy


## 通过射线拾取鼠标位置下的知识点索引
func pick_point_index(mouse_pos: Vector2, camera: Camera3D) -> int:
	if camera == null:
		return -1
	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_end: Vector3 = origin + camera.project_ray_normal(mouse_pos) * 1000.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, ray_end)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result: Dictionary = root_node.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return -1
	var collider: Variant = result.get("collider")
	if collider is StaticBody3D and collider.has_meta("point_index"):
		return int(collider.get_meta("point_index"))
	return -1


## 获取指定节点的3D位置
func get_point_position(index: int) -> Vector3:
	if index >= 0 and index < point_nodes.size() and is_instance_valid(point_nodes[index]):
		return point_nodes[index].global_position
	return Vector3.ZERO


## 设置未学习节点颜色
func set_mat_unlearned_color(c: Color) -> void:
	mat_unlearned_color = c

## 设置学习中节点颜色
func set_mat_learning_color(c: Color) -> void:
	mat_learning_color = c

## 设置已掌握节点颜色
func set_mat_learned_color(c: Color) -> void:
	mat_learned_color = c

## 设置材质粗糙度
func set_mat_roughness(v: float) -> void:
	mat_roughness = v

## 设置材质金属度
func set_mat_metallic(v: float) -> void:
	mat_metallic = v

## 设置材质发光强度
func set_mat_emission_energy(v: float) -> void:
	mat_emission_energy = v

## 设置选中节点颜色
func set_mat_selected_color(c: Color) -> void:
	mat_selected_color = c

## 设置选中节点发光倍数
func set_mat_selected_emission_mult(v: float) -> void:
	mat_selected_emission_mult = v

## 刷新所有节点的材质
func refresh_all_materials() -> void:
	var count: int = data_manager.get_count()
	for i in range(min(count, point_nodes.size())):
		if not is_instance_valid(point_nodes[i]):
			continue
		var item: Dictionary = data_manager.get_item(i)
		point_nodes[i].material_override = _create_point_material_from_item(item)


## 构建所有父子关系的管状连线
func build_all_lines() -> void:
	_ensure_lines_container()
	for child in _lines_container.get_children():
		child.queue_free()
	line_instances.clear()

	var edges: Array = data_manager.collect_edges()
	var line_mat := _create_line_material()

	for edge in edges:
		var from_idx: int = int(edge.get("from", -1))
		var to_idx: int = int(edge.get("to", -1))
		if from_idx < 0 or to_idx < 0:
			continue
		if from_idx >= point_nodes.size() or to_idx >= point_nodes.size():
			continue

		var from_item: Dictionary = data_manager.get_item(from_idx)
		var to_item: Dictionary = data_manager.get_item(to_idx)
		var from_gid := int(from_item.get("galaxy_id", 0))
		var to_gid := int(to_item.get("galaxy_id", 0))
		if from_gid != to_gid:
			continue

		var p1: Vector3 = _resolve_position(from_item, from_idx)
		var p2: Vector3 = _resolve_position(to_item, to_idx)

		var mesh: Mesh = _create_straight_tube_mesh(p1, p2)
		if mesh == null:
			continue

		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "EdgeLine_%d_%d" % [from_idx, to_idx]
		mi.mesh = mesh
		mi.material_override = line_mat
		_lines_container.add_child(mi)
		line_instances.append(mi)

	build_relation_lines()


## 构建关系连线（虚线管状）
func build_relation_lines() -> void:
	var relations: Array = data_manager.collect_relations()
	if relations.is_empty():
		return

	var rel_mat := _create_relation_material()

	for rel in relations:
		var from_idx: int = int(rel.get("from", -1))
		var to_idx: int = int(rel.get("to", -1))
		if from_idx < 0 or to_idx < 0:
			continue
		if from_idx >= point_nodes.size() or to_idx >= point_nodes.size():
			continue

		var from_item: Dictionary = data_manager.get_item(from_idx)
		var to_item: Dictionary = data_manager.get_item(to_idx)
		var p1: Vector3 = _resolve_position(from_item, from_idx)
		var p2: Vector3 = _resolve_position(to_item, to_idx)

		var mesh: Mesh = _create_dashed_tube_mesh(p1, p2)
		if mesh == null:
			continue

		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = "RelationLine_%d_%d" % [from_idx, to_idx]
		mi.mesh = mesh
		mi.material_override = rel_mat
		_lines_container.add_child(mi)
		line_instances.append(mi)


func _create_relation_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.5, 0.2, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.3, 0.1)
	mat.emission_energy_multiplier = 0.4
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## 创建虚线管状网格
func _create_dashed_tube_mesh(p1: Vector3, p2: Vector3) -> Mesh:
	var dir := p2 - p1
	var total_length: float = dir.length()
	if total_length < 0.01:
		return null

	var dash_length: float = 0.3
	var gap_length: float = 0.2
	var segment_length: float = dash_length + gap_length
	var num_segments: int = int(total_length / segment_length)
	if num_segments < 1:
		num_segments = 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for s in num_segments:
		var start_t: float = float(s) * segment_length / total_length
		var end_t: float = min(start_t + dash_length / total_length, 1.0)

		var seg_start: Vector3 = p1 + dir * start_t
		var seg_end: Vector3 = p1 + dir * end_t

		var points := PackedVector3Array()
		var steps: int = max(line_length_segments / 2, 2)
		for i in steps + 1:
			var t: float = float(i) / float(steps)
			points.append(seg_start.lerp(seg_end, t))

		var seg_mesh: Mesh = _build_tube_along_points(points)
		if seg_mesh == null:
			continue

		var arrays: Array = seg_mesh.surface_get_arrays(0)
		if arrays.is_empty() or arrays.size() <= Mesh.ARRAY_INDEX:
			continue

		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue

		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var offset: int = st.get_vertex_count()

		for v in verts:
			st.add_vertex(v)

		if indices.is_empty():
			for i in range(0, verts.size(), 3):
				if i + 2 < verts.size():
					st.add_index(offset + i)
					st.add_index(offset + i + 1)
					st.add_index(offset + i + 2)
		else:
			for idx in indices:
				st.add_index(offset + int(idx))

	st.generate_normals()
	return st.commit()


func update_link_lines() -> void:
	if _lines_container == null or not is_instance_valid(_lines_container):
		return
	if line_instances.is_empty():
		return
	var needs_update := false
	for mi in line_instances:
		if mi == null or not is_instance_valid(mi):
			needs_update = true
			break
	if needs_update:
		build_all_lines()
		return
	var edges: Array = data_manager.collect_edges()
	if edges.size() != line_instances.size() - data_manager.collect_relations().size():
		build_all_lines()
		return


## 创建连线材质
func _create_line_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.6, 0.8, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.4, 0.6)
	mat.emission_energy_multiplier = 0.5
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## 创建曲线管状网格
func _create_curved_tube_mesh(p1: Vector3, p2: Vector3) -> Mesh:
	var curve := Curve3D.new()
	var dir := p2 - p1
	var perp := dir.cross(Vector3.UP)
	if perp.length() < 0.001:
		perp = dir.cross(Vector3.RIGHT)
	if perp.length() < 0.001:
		perp = Vector3.FORWARD
	perp = perp.normalized() * dir.length() * 0.1

	curve.add_point(p1, Vector3.ZERO, perp)
	curve.add_point(p2, -perp, Vector3.ZERO)

	var baked_points := curve.get_baked_points()
	if baked_points.size() < 2:
		return _create_straight_tube_mesh(p1, p2)

	return _build_tube_along_points(baked_points)


## 创建直线管状网格
func _create_straight_tube_mesh(p1: Vector3, p2: Vector3) -> Mesh:
	var points := PackedVector3Array()
	var steps: int = max(line_length_segments, 2)
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		points.append(p1.lerp(p2, t))
	return _build_tube_along_points(points)


## 沿路径点构建管状网格
func _build_tube_along_points(points: PackedVector3Array) -> Mesh:
	if points.size() < 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		return st.commit()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rings: Array = []
	var prev_up := Vector3.UP
	var prev_right := Vector3.RIGHT
	for i in points.size():
		var pos: Vector3 = points[i]
		var tangent: Vector3
		if i < points.size() - 1:
			tangent = (points[i + 1] - pos).normalized()
		elif i > 0:
			tangent = (pos - points[i - 1]).normalized()
		else:
			tangent = Vector3.FORWARD

		if i == 0:
			var up := Vector3.UP
			if abs(tangent.dot(up)) > 0.99:
				up = Vector3.RIGHT
			prev_right = tangent.cross(up).normalized()
			prev_up = prev_right.cross(tangent).normalized()
		else:
			prev_up = (prev_up - prev_up.dot(tangent) * tangent).normalized()
			if prev_up.length() < 0.001:
				prev_up = Vector3.RIGHT
				prev_up = (prev_up - prev_up.dot(tangent) * tangent).normalized()
			prev_right = tangent.cross(prev_up).normalized()
			prev_up = prev_right.cross(tangent).normalized()

		var ring: Array = []
		for j in line_radial_segments:
			var angle := 2.0 * PI * float(j) / float(line_radial_segments)
			ring.append(pos + prev_right * cos(angle) * line_tube_radius + prev_up * sin(angle) * line_tube_radius)
		rings.append(ring)

	for i in range(rings.size() - 1):
		for j in line_radial_segments:
			var j_next := (j + 1) % line_radial_segments
			st.add_vertex(rings[i][j])
			st.add_vertex(rings[i][j_next])
			st.add_vertex(rings[i + 1][j])

			st.add_vertex(rings[i][j_next])
			st.add_vertex(rings[i + 1][j_next])
			st.add_vertex(rings[i + 1][j])

	st.generate_normals()
	return st.commit()
