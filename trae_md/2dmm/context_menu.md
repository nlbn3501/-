# 2D思维导图 - 右键菜单

## 一、菜单类型

### 1.1 节点右键菜单

| ID | 菜单项 | 触发动作 | 条件 |
|----|--------|----------|------|
| 1 | 查看详情 | `show_detail` | 始终 |
| 2 | 聚焦节点 | `focus_node` | 始终 |
| - | ---分隔线--- | - | - |
| 3 | 创建子节点 | `create_child_node` | 始终 |
| 4 | 创建节点 | `create_node` | 始终 |
| - | ---分隔线--- | - | - |
| 5 | 编辑节点 | `edit_node` | 始终 |
| 6 | 设置掌握程度 → | `set_mastery` | 子菜单：未学习/学习中/已掌握 |
| - | ---分隔线--- | - | - |
| 7 | 删除节点 | `delete_node` | 始终 |
| 8 | 删除所有子节点 | `delete_all_non_root` | 始终 |
| - | ---分隔线--- | - | - |
| 9 | 刷新 | `refresh` | 始终 |
| 10 | 重置视图 | `reset_view` | 始终 |

### 1.2 空白右键菜单

| ID | 菜单项 | 触发动作 |
|----|--------|----------|
| 1 | 创建节点 | `create_node` |
| - | ---分隔线--- | - |
| 2 | 刷新 | `refresh` |
| 3 | 重置视图 | `reset_view` |
| - | ---分隔线--- | - |
| 4 | 截图 | `screenshot` |
| 5 | 一键删除所有非root节点 | `delete_all_non_root` |

**关键行为**：
- 空白处右键"创建节点"会直接在鼠标位置创建自由节点，无需对话框。
- "一键删除所有非root节点"会删除所有非root节点（自由节点和子节点），只保留root节点。

### 1.3 多选右键菜单

| ID | 菜单项 | 触发动作 |
|----|--------|----------|
| 1 | 批量标记为已掌握 | `batch_mastery(2)` |
| 2 | 批量标记为学习中 | `batch_mastery(1)` |
| 3 | 批量标记为未学习 | `batch_mastery(0)` |
| - | ---分隔线--- | - |
| 4 | 批量删除 | `batch_delete` |

## 二、动作处理

```gdscript
func _on_context_menu_action(action: String, index: int, extra: Variant = null, mouse_pos: Vector2 = Vector2.ZERO) -> void:
    match action:
        "show_detail"    → node_double_clicked.emit(index)
        "focus_node"     → focus_on_node(index)
                          scroll_to_node(index)
        "set_mastery_0"  → 设置mastery=0 + 保存 + rebuild
        "set_mastery_1"  → 设置mastery=1 + 保存 + rebuild
        "set_mastery_2"  → 设置mastery=2 + 保存 + rebuild
        "edit_node"      → 弹出编辑对话框
        "delete_node"    → 弹出删除确认
        "delete_all_non_root" → 删除所有非root节点
        "create_node"    → _create_node_directly(-1, local_pos)  # 创建自由节点
        "create_child_node" → _create_node_directly(index, mouse_pos)  # 创建子节点
        "refresh"        → load_data + rebuild
        "reset_view"     → reset_view()
        "screenshot"     → 截图功能
        "batch_mastery_0" → 批量设置掌握度=0
        "batch_mastery_1" → 批量设置掌握度=1
        "batch_mastery_2" → 批量设置掌握度=2
        "batch_delete"   → 批量删除
```

## 三、自由节点创建

### 3.1 空白处新建自由节点

当 `parent_index = -1` 时，创建的是自由节点：

```gdscript
func _create_node_directly(parent_index: int, mouse_pos: Vector2) -> void:
    var new_item: Dictionary = {
        "id": data_manager.call("generate_unique_id", "new_node"),
        "name": "New Node",
        "description": "",
        "position": [randf_range(-2.0, 2.0), randf_range(-2.0, 2.0), randf_range(-1.0, 1.0)],
        "mastery": 0,
    }

    # 转换坐标：mouse_pos是相对于scroll_container的坐标，需要加上滚动偏移
    var container_pos: Vector2 = mouse_pos
    if scroll_container and is_instance_valid(scroll_container):
        container_pos = mouse_pos + Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)

    if parent_index >= 0:
        # 有父节点，创建子节点
        var parent_item: Dictionary = data_manager.call("get_item", parent_index)
        new_item["parent_id"] = str(parent_item.get("id", ""))
        new_item["pos2d"] = [parent_pos.x + 220.0, parent_pos.y]
    else:
        # 无父节点，创建自由节点
        new_item["pos2d"] = [container_pos.x, container_pos.y]
        new_item["parent_id"] = ""

    var new_index: int = data_manager.call("add_item", new_item)
    data_manager.call("save_data")
    rebuild()
    focus_on_node(new_index)
```

### 3.2 坐标转换

右键菜单的 `extra` 参数是 `mb.position`（相对于 scroll_container 的坐标），需要加上滚动偏移量才能得到容器中的实际位置：

```gdscript
var container_pos: Vector2 = mouse_pos
if scroll_container and is_instance_valid(scroll_container):
    container_pos = mouse_pos + Vector2(scroll_container.scroll_horizontal, scroll_container.scroll_vertical)
```

## 四、一键删除所有非root节点

### 4.1 功能说明

该功能用于快速清理视图，删除所有非root节点（自由节点和子节点），只保留root节点。

### 4.2 实现方式

```gdscript
func _on_delete_all_non_root() -> void:
    var count: int = data_manager.call("get_count")
    var deleted_count: int = 0

    # 从后往前删除，避免索引混乱
    for i in range(count - 1, -1, -1):
        var item: Dictionary = data_manager.call("get_item", i)
        if item is Dictionary:
            # root节点的id是"root"，自由节点的parent_id为空字符串
            var node_id: String = str(item.get("id", ""))
            # 只保留id为"root"的节点（真正的root节点）
            if node_id != "root":
                data_manager.call("remove_item", i)
                deleted_count += 1

    # 保存数据
    data_manager.call("save_data")

    # 重建视图
    mindmap_2d.rebuild()

    _log("删除完成，共删除 %d 个非root节点" % deleted_count)
```

### 4.3 判断标准

- **root节点**：`id == "root"`
- **非root节点**：`id != "root"`（包括自由节点和子节点）

## 五、快捷键

| 快捷键 | 功能 | 实现方式 |
|--------|------|----------|
| R | 刷新视图 | `Input.is_action_just_pressed("refresh")` |
| Ctrl+N | 创建自由节点 | `Input.is_action_just_pressed("new_node")` |
| Tab | 直接创建子节点/自由节点 | `Input.is_action_just_pressed("new_child")` |
| Delete | 删除选中节点 | `Input.is_action_just_pressed("delete")` |
| Escape | 取消选择 | `Input.is_action_just_pressed("deselect")` |

**注意**：Tab 快捷键直接创建节点，不弹出对话框：
- 选中节点时：创建子节点
- 未选中时：创建自由节点

## 六、正确行为验证点

1. 菜单位置跟随鼠标
2. 掌握度选项通过子菜单展开（未学习/学习中/已掌握）
3. 编辑对话框预填当前值
4. 删除操作有确认步骤
5. 所有操作后数据正确保存
6. 空白处新建节点在鼠标位置创建
7. 新建的自由节点不显示连接线条
8. "一键删除所有非root节点"能正确删除所有非root节点（包括自由节点）
9. Tab 快捷键直接创建节点，不弹出对话框
10. Delete 快捷键删除选中节点
