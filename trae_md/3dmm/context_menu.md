# 3D思维导图 - 右键菜单

## 一、菜单类型

### 1.1 节点右键菜单

在节点上右键时弹出。聚焦标签根据节点状态动态变化。

| ID | 菜单项 | 触发动作 | 条件 |
|----|--------|----------|------|
| 1 | 查看详情: {name} | `show_detail` | 始终 |
| 2 | 聚焦节点 / 取消聚焦 | `focus_node` / `unfocus_node` | 普通节点→聚焦；已锁定的自由节点→取消聚焦 |
| 3 | 在2D视图中打开 | `switch_view` | 始终 |
| - | ---分隔线--- | - | - |
| 4 | 标记为已掌握 | `set_mastery(2)` | mastery < 2 |
| 5 | 标记为学习中 | `set_mastery(1)` | mastery < 1 |
| 6 | 标记为未学习 | `set_mastery(0)` | mastery > 0 |
| - | ---分隔线--- | - | - |
| 7 | 编辑节点 | `edit_node` | 始终 |
| 8 | 删除节点 | `delete_node` | 始终 |

> **聚焦规则**：只针对自由节点（galaxy_id > 0）生效。聚焦后相机锁定围绕该节点旋转，焦点不会因点击空白或旋转相机而消失。再次右键该节点显示"取消聚焦"。

### 1.2 空白右键菜单

在空白处右键时弹出。

| ID | 菜单项 | 触发动作 |
|----|--------|----------|
| 1 | 新建节点 | `create_node` |
| - | ---分隔线--- | - |
| 2 | 自动布局 | `auto_layout` |
| 3 | 刷新 (R) | `refresh` |
| 4 | 重置视图 | `reset_view` |
| 5 | 截图 | `screenshot` |
| 6 | 材质调试面板 | `toggle_settings` |

### 1.3 多选右键菜单

多选节点后右键弹出。

| ID | 菜单项 | 触发动作 |
|----|--------|----------|
| 0 | 批量操作 ({n}个节点) | 无（仅标题） |
| - | ---分隔线--- | - |
| 1 | 批量标记为已掌握 | `batch_mastery(2)` |
| 2 | 批量标记为学习中 | `batch_mastery(1)` |
| 3 | 批量标记为未学习 | `batch_mastery(0)` |
| - | ---分隔线--- | - |
| 4 | 批量删除 | `batch_delete` |

## 二、动作处理

所有菜单动作通过 `menu_action` 信号传递到 KnowledgeMap 处理：

```gdscript
func _on_context_menu_action(action: String, index: int, extra: Variant = null) -> void:
    match action:
        "show_detail"    → _show_detail_popup(index)
        "focus_node"     → _focus_on_point(index) + 高亮 + 锁定自由节点轨道
        "unfocus_node"   → 清除轨道锁定 + 清除聚焦目标
        "switch_view"    → 切换到2D视图
        "set_mastery"    → 更新mastery + 保存 + 刷新
        "edit_node"      → _show_node_dialog("edit", index)
        "delete_node"    → _delete_node(index)
        "create_node"    → _show_node_dialog("create", index, extra位置)
        "auto_layout"    → layout_manager.apply_layout() + rebuild
        "refresh"        → 清除聚焦 + 清除轨道锁定 + rebuild_all()
        "reset_view"     → 清除聚焦 + 清除轨道锁定 + 相机归位
        "screenshot"     → 保存PNG
        "toggle_settings"→ 切换材质面板
        "batch_mastery"  → 批量设置掌握度
        "batch_delete"   → 批量删除
```

## 三、菜单生命周期

1. 右键触发 → 创建 PopupMenu → 添加到场景树
2. 用户点击菜单项 → 发射 menu_action 信号 → 处理动作
3. 处理完成后 → `menu.queue_free()` 释放菜单

## 四、正确行为验证点

1. 菜单位置跟随鼠标
2. 菜单项根据当前状态动态显示/隐藏（如掌握度选项）
3. 菜单不会超出屏幕边界
4. 点击菜单外区域自动关闭
5. 菜单操作后数据正确保存
