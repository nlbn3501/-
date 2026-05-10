# 3D思维导图 - 布局与渲染

## 一、布局算法

### 1.1 多星系布局（Multi-Galaxy Layout）

将节点按 `galaxy_id` 分组，每个星系独立布局为同心球面：

```
galaxy_id=0（根星系）            galaxy_id=1（自由星系B）
  中心: 原点 (0,0,0)               中心: 自由节点B.position
  depth=0 → 原点                   depth=0 → 中心点（自由节点B）
  depth=1 → 半径 R1 球面           depth=1 → 半径 R1' 球面
  depth=2 → 半径 R2 球面           depth=2 → 半径 R2' 球面

galaxy_id=2（自由星系C）
  中心: 自由节点C.position
  depth=0 → 中心点（自由节点C）
  depth=1 → 半径 R1'' 球面
```

**布局流程**：

```gdscript
func apply_layout():
    var galaxy_groups = {}  # galaxy_id → [node_indices]
    
    for i in data_manager.get_count():
        var item = data_manager.get_item(i)
        var gid = item.get("galaxy_id", 0)
        galaxy_groups[gid].append(i)
    
    # 计算根星系最外层半径
    var max_root_radius = 0.0
    for gid, indices in galaxy_groups:
        if gid == 0:
            max_root_radius = _layout_galaxy(indices, Vector3.ZERO)
    
    # 布局自由星系：在根星系外层轨道上分布
    var free_galaxy_centers = _distribute_free_galaxies(
        galaxy_groups.keys().filter(func(k): return k > 0),
        max_root_radius + GALAXY_GAP
    )
    
    for gid in galaxy_groups.keys().filter(func(k): return k > 0):
        var center = free_galaxy_centers[gid]
        var indices = galaxy_groups[gid]
        _layout_galaxy(indices, center)
```

### 1.2 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `tree_base_radius` | 2.0 | 基础球面半径 |
| `tree_radius_increment` | 1.5 | 每层增加的半径 |
| `root_node_radius` | 0.8 | 星系根节点半径 |
| `depth_scale_factor` | 0.8 | 节点半径随深度的缩放因子 |
| `galaxy_gap` | 5.0 | 星系之间的最小间距 |
| `free_galaxy_orbit_radius` | 自适应 | 自由星系轨道球半径（见1.4） |

### 1.3 同心球面分布（星系内部）

每个星系内部使用 Fibonacci 球面采样算法：

```gdscript
func _layout_galaxy(indices: Array[int], center: Vector3) -> float:
    """返回该星系的最外层半径"""
    var depths = {}  # depth → [node_indices]
    for idx in indices:
        var d = data_manager.compute_depths()[idx]
        depths[d].append(idx)
    
    var max_radius = 0.0
    for depth, nodes_at_depth in depths:
        var radius = tree_base_radius + depth * tree_radius_increment
        # 自适应：如果节点过多，扩大半径
        while _needs_more_space(nodes_at_depth.size(), radius):
            radius += tree_radius_increment * 0.5
        # Fibonacci球面采样分布
        for j, idx in enumerate(nodes_at_depth):
            var pos = _fibonacci_sphere(j, nodes_at_depth.size(), radius)
            data_manager.set_item_position(idx, center + pos)
        max_radius = max(max_radius, radius)
    
    return max_radius
```

**自适应半径**：当某深度节点过多放不下时，自动扩大该深度的半径，确保节点不重叠。

### 1.4 自由星系轨道球

自由星系的「中心节点」放在**根星系最外层之外的一个轨道球**上：

```
自由星系轨道球自适应算法：

1. 确定根星系最外层半径 R_max_root
2. 自由星系轨道球半径 R_orbit = R_max_root + GALAXY_GAP
3. 如果自由星系过多导致轨道球上放不下，自动扩大 R_orbit
4. 多个自由星系在轨道球上使用 Fibonacci 球面采样分布（与星系内部同算法）
```

**视觉效果**：

```
                  自由星系轨道球（自适应半径）
                 ┌─────────────────────────┐
                 │   自由节点A (galaxy=1)   │
                 │      ├ A1 depth=1       │
                 │      └ A2 depth=1       │
                 │                         │
                 │   自由节点B (galaxy=2)   │
                 │      ├ B1 depth=1       │
                 │      └ B2 depth=1       │
                 └─────────────────────────┘
                           ↑
                 ┌─────────┴────────┐
                 │ 根星系同心球面     │
                 │ depth=0 root     │
                 │ depth=1 ○○○      │
                 │ depth=2 ○○○○     │
                 └──────────────────┘
```

### 1.5 吸附与合并后的布局

当自由星系 B 被吸附到根星系节点 A2 下：

1. B 的所有节点 `galaxy_id` → 0（合并到根星系）
2. B 的 `parent` → A2 的名称
3. B 中子节点的 `parent` 保持不变（仍指向 B）
4. 重新执行 `apply_layout()` → B 及其子节点自动按同心球面布局到根星系中

### 1.6 新文件行为

- 打开新文件时，只创建一个根节点（galaxy_id=0），位于原点
- 根节点默认名称为 "Root"，描述 "Root node of the mind map"
- 所有新添加节点默认作为根节点的子节点（galaxy_id=0）
- 根节点不可删除（删除时会自动重建）

### 1.7 自由节点处理

- 每个 galaxy_id > 0 的星系有一个根节点（parent=""）
- 自由星系根节点在自由轨道球上分布
- 该星系内子节点以根节点为中心进行同心球面布局

## 二、节点渲染

### 2.1 球体节点

- 使用 `MeshInstance3D` + `SphereMesh`
- 大小随深度缩放：`radius = root_radius * depth_scale_factor^depth`
- 根节点半径：0.8
- 深度缩放因子：0.8

### 2.2 标签

- 使用 `Label3D`
- Billboard模式（始终面向相机）
- 无深度测试（始终可见）
- 字体大小：根节点更大

### 2.3 掌握度材质

| 掌握度 | 颜色 | RGB |
|--------|------|-----|
| 0 未学习 | 灰色 | (0.6, 0.6, 0.6) |
| 1 学习中 | 橙黄色 | (1.0, 0.6, 0.1) |
| 2 已掌握 | 绿色 | (0.2, 0.85, 0.2) |

### 2.4 选中高亮

| 参数 | 默认值 |
|------|--------|
| 高亮颜色 | (1.0, 1.0, 0.3) 亮黄色 |
| 发光倍数 | 2.0 |

## 三、连线渲染

### 3.1 连线方式

使用 `TubeTrailMesh` + `Curve3D` 绘制3D曲线连线。

### 3.2 连线规则

- 只连接有父子关系的节点对
- 曲线从父节点中心到子节点中心
- 使用贝塞尔曲线平滑连接
- **跨星系节点不连线**（父子关系只存在于同一星系内）

### 3.3 连线更新

- 每帧在 `_process()` 中调用 `point_manager.update_link_lines()`
- 确保布局变化时连线实时更新

## 四、环境设置

| 设置 | 值 |
|------|-----|
| 背景色 | (0.05, 0.05, 0.07) 深色 |
| 环境光 | 禁用（使用方向光） |
| 辉光效果 | 开启，intensity=0.8, strength=0.6, bloom=0.5 |
| 辉光混合模式 | Additive |
| 辉光HDR阈值 | 0.8 |
| 辉光HDR缩放 | 0.5 |

## 五、交互限制

- **不支持节点拖拽**：节点位置由布局算法自动计算，用户不能手动拖拽
- **保留选择功能**：仍支持左键选择节点
- **保留相机控制**：旋转、缩放、聚焦功能不变
- **相机中心点**：聚焦到节点时以该节点为中心旋转；无聚焦时以根节点为中心

## 六、正确行为验证点

1. 根星系节点以原点为中心分布在同心球面上
2. 自由星系节点以各自根节点为中心分布在同心球面上
3. 自由星系根节点分布在根星系最外层的轨道球上
4. 吸附合并后，整个星系统一重新布局
5. 连线不穿过其他节点
6. 材质颜色与掌握度一致
7. 选中高亮效果明显可辨
8. 标签始终面向相机且可读
9. 新文件只创建一个根节点，位于原点
10. 根节点默认名称为英语 "Root"
11. 所有新节点默认作为根节点的子节点
12. 节点不能被拖拽移动