# 2D思维导图 - 节点拖拽行为

## 一、拖拽模式概述

2D思维导图采用**XMind风格拖拽**，核心原则：
- **顺序不乱**：拖拽不会打乱同级节点的相对顺序
- **自动排开**：插入两个节点之间时，后续节点自动后移
- **自动补齐**：拖出节点后，空位自动被后续节点填补
- **子树整体拖拽**：当自由节点有子节点时，拖动该节点整体移动整个子树
- **吸附成子节点**：自由节点拖到其他节点附近时，可吸附成为其子节点
- **拖出成新星系**：树中节点可拖出成为自由星系，带整棵子树

## 二、节点分类

| 类型 | 说明 | 拖拽行为 |
|------|------|----------|
| 根节点 | 中心节点，depth=0，id="root" | 不可拖出（禁止变为自由节点） |
| 子节点 | 有父节点的节点 | 可拖拽，可吸附到其他节点，可拖出成新星系 |
| 自由节点 | 无父节点的非根节点 | 可拖拽，可吸附到其他节点，有子树时整体拖拽 |

## 三、拖拽实现细节

### 3.1 拖拽变量

| 变量 | 类型 | 说明 |
|------|------|------|
| `is_dragging` | bool | 是否正在拖拽 |
| `drag_start_pos` | Vector2 | 拖拽起始位置 |
| `drag_node_index` | int | 被拖拽节点的索引 |
| `drag_subtree_indices` | Array[int] | 被拖拽节点及其所有子节点索引（新增） |
| `drag_offset` | Vector2 | 鼠标与节点位置的偏移 |
| `snap_distance` | float | 吸附距离（100.0） |
| `drag_dead_zone` | float | 拖拽死区（20.0） |

### 3.2 子树索引收集

```gdscript
func _collect_subtree_indices(root_index: int) -> Array[int]:
    """递归收集 root_index 及其所有后代节点的索引"""
    var result = [root_index]
    var root_name = data_manager.get_item(root_index)["name"]
    for i in data_manager.get_count():
        var item = data_manager.get_item(i)
        if item.get("parent", "") == root_name:
            result += _collect_subtree_indices(i)
    return result
```

### 3.3 拖拽流程

**拖拽开始**（左键按下）：
1. 设置 `is_dragging = true`
2. 收集子树索引：`drag_subtree_indices = _collect_subtree_indices(node_index)`
3. 记录 `drag_start_pos` 为节点当前位置
4. 计算 `drag_offset = mb.position - panel.position`
5. 更新选中状态

**拖拽中**（鼠标移动）：
1. 计算目标位置：`target_pos = mouse_pos - drag_offset`
2. 应用吸附：`target_pos = _apply_snap(target_pos, drag_node_index)`
3. 更新所有子树节点的位置（整体平移）

```gdscript
# 整体平移子树
var delta = target_pos - panel.position
for idx in drag_subtree_indices:
    var sub_panel = node_controls.get(idx)
    if sub_panel:
        sub_panel.position += delta
```

**拖拽结束**（左键释放）：
1. 计算拖拽距离：`drag_distance = (panel.position - drag_start_pos).length()`
2. 如果距离 <= 死区：忽略，节点回到原位
3. 如果距离 > 死区：
   a. 检测吸附：检查是否可以吸附到附近节点
   b. 吸附成功 → 执行吸附逻辑
   c. 吸附失败 → 执行拖出/移动逻辑

### 3.4 吸附逻辑

```gdscript
func _apply_snap(target_pos: Vector2, current_index: int) -> Vector2:
    var snapped_pos: Vector2 = target_pos
    var min_distance: float = snap_distance
    var closest_node: int = -1

    for index in node_controls.keys():
        if index == current_index:
            continue
        var panel: PanelContainer = node_controls[index]
        var node_pos: Vector2 = panel.position + panel.size / 2.0
        var distance: float = target_pos.distance_to(node_pos)

        if distance < min_distance:
            min_distance = distance
            closest_node = index

    if closest_node >= 0:
        var closest_panel: PanelContainer = node_controls[closest_node]
        var closest_center: Vector2 = closest_panel.position + closest_panel.size / 2.0
        var direction: Vector2 = (target_pos - closest_center).normalized()
        var snap_pos: Vector2 = closest_center + direction * (horizontal_gap / 2)
        snapped_pos = snap_pos

    return snapped_pos
```

### 3.5 拖拽后数据更新

```gdscript
func _finish_drag() -> void:
    var panel = node_controls[drag_node_index]
    var drag_distance = (panel.position - drag_start_pos).length()
    
    if drag_distance <= drag_dead_zone:
        # 死区：恢复原位
        is_dragging = false
        return
    
    # 检测吸附
    var absorbed = _try_absorb(drag_node_index)
    
    if not absorbed:
        # 拖出/移动：更新所有子树节点的位置
        for idx in drag_subtree_indices:
            var sub_panel = node_controls.get(idx)
            if sub_panel:
                var item = data_manager.get_item(idx)
                item["pos2d"] = [sub_panel.position.x + sub_panel.size.x / 2.0, sub_panel.position.y + sub_panel.size.y / 2.0]
        
        # 若非自由节点则变为自由节点（新星系）
        var root_item = data_manager.get_item(drag_node_index)
        if root_item.get("parent", "") != "":
            root_item["parent"] = ""
            # 生成新的 galaxy_id
            var new_gid = _generate_new_galaxy_id()
            data_manager.move_subtree_to_new_galaxy(drag_node_index, new_gid)
    
    data_manager.save_data()
    rebuild()
    is_dragging = false
```

## 四、吸附（自由节点→成为子节点）

### 4.1 吸附触发条件

自由节点被拖拽到另一个节点附近（距离 < snap_distance = 100px）时触发吸附检测。

### 4.2 吸附流程

```
自由节点B（带B1、B2）被拖到节点A2附近
    ↓
检测到吸附：A2 在吸附距离内
    ↓
执行吸附（直接吸附，无需二次确认）：
  1. B 的 parent = A2.name
  2. B 的所有子节点（B1、B2）的 galaxy_id = A2 的 galaxy_id
  3. B 及其子节点的 relations 字段保持不变
  4. B 的 depth 自动重新计算（通过 compute_depths()）
  5. B1、B2 的 depth 相应递增
    ↓
数据保存 + rebuild()
```

### 4.3 吸附后的 2D 视觉表现

```
吸附前：                         吸附后：
root                            root
├── A1                          ├── A1
├── A2                          │   └── B ← 成为子节点，带子树
├── A3                          │       ├── B1
                                │       └── B2
B (自由节点)                    ├── A2
├── B1                          ├── A3
└── B2
```

### 4.4 吸附实现

```gdscript
func _try_absorb(drag_node_index: int) -> bool:
    """尝试将 drag_node_index 吸附到最近的目标节点下。成功返回true。"""
    var drag_panel = node_controls[drag_node_index]
    var drag_center = drag_panel.position + drag_panel.size / 2.0
    
    var closest_index = -1
    var closest_dist = snap_distance
    
    for index in node_controls.keys():
        if index == drag_node_index:
            continue
        var panel = node_controls[index]
        var center = panel.position + panel.size / 2.0
        var dist = drag_center.distance_to(center)
        if dist < closest_dist:
            closest_dist = dist
            closest_index = index
    
    if closest_index < 0:
        return false  # 无吸附目标
    
    # 执行吸附
    var target_item = data_manager.get_item(closest_index)
    var target_name = target_item.get("name", "")
    var target_gid = target_item.get("galaxy_id", 0)
    
    # 将 drag_node 及其子树合并到目标星系
    data_manager.absorb_subtree(closest_index, drag_node_index)
    
    return true
```

### 4.5 吸附规则

| 规则 | 说明 |
|------|------|
| 根节点 | 不能将根节点吸附到其他节点下（id="root"） |
| 自由节点 | 可以被吸附到任意非根节点下 |
| 子节点 | 可以被吸附到其他非根节点下 |
| 子树 | 吸附时整棵子树一起移动，galaxy_id统一更新 |
| 关系 | 吸附后原 relations 字段保持不变 |

## 五、拖出（子节点→形成新星系）

### 5.1 拖出条件

树形结构中的任意节点（根节点除外）被拖拽远离其父节点且无吸附目标时，形成新自由星系。

### 5.2 拖出流程

```
节点A2（带子节点A2_1、A2_2）被拖离父节点
    ↓
距离超过死区 + 无吸附目标
    ↓
A2 成为新的自由节点：
  1. A2 的 parent 清空
  2. A2 获得新的 galaxy_id（当前最大 galaxy_id + 1）
  3. A2_1、A2_2 的 galaxy_id 更新为 A2 的 galaxy_id
  4. 所有子节点的 pos2d 更新为当前拖拽位置
  5. relations 字段保持不变
    ↓
数据保存 + rebuild()
```

### 5.3 拖出规则

| 规则 | 说明 |
|------|------|
| 根节点 id="root" | 不可拖出 |
| 无子节点的普通节点 | 拖出后仅自身成为自由节点，galaxy_id=新建 |
| 带子节点的节点 | 整个子树一起拖出，形成新的独立星系 |
| 拖回树中 | 再次吸附到树中可合并回原星系 |

## 六、关键行为说明

### 6.1 拖拽死区

拖拽距离小于20像素时，释放后节点回到原位，不会变为自由节点。这避免了因鼠标抖动导致的误操作。

### 6.2 子树整体移动

拖动自由节点时，其所有子节点跟随整体平移，内部相对位置不变。`rebuild()` 时子节点以该自由节点为父节点重新布局。

### 6.3 节点中心跟随鼠标

拖拽时，节点的中心点会跟随鼠标位置，而不是左上角跟随。这通过 `drag_offset = mb.position - panel.position` 实现。

### 6.4 自由节点与子树的连线

- 自由节点（parent=""）本身不显示连接到父节点的线条
- 自由节点与其子节点之间的连线正常显示
- 子树节点被拖出后，与父节点之间的连线消失

## 七、正确行为验证点

1. 拖拽不会导致节点丢失
2. 自由节点有子树时整体拖拽，子树内部关系不变
3. 拖拽后父子关系正确（自由节点无父子关系）
4. 拖拽后连线正确更新（自由节点不显示父连线，子树连线正常）
5. 拖拽后节点顺序正确
6. 拖拽距离小于死区时节点回到原位
7. 吸附后 galaxiy_id 正确更新为父节点所在星系
8. 拖出后 galaxy_id 正确分配新 ID
9. 吸附/拖出后 relations 字段保持不变
10. 根节点不可被吸附或拖出
11. 多次快速拖拽不会出错
12. 节点中心始终跟随鼠标