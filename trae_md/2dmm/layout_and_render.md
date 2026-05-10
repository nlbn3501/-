# 2D思维导图 - 布局与渲染

## 一、布局算法

### 1.1 XMind风格布局

中心节点居中，子节点分左右两侧展开。

```
          左侧子树 ← [中心节点] → 右侧子树
```

**布局规则**：

1. 找到主根节点（depth=0且有子节点的节点）
2. 将根节点的直接子节点分为两组：
   - 前半部分放在右侧
   - 后半部分放在左侧
3. 递归展开每棵子树

### 1.2 子树高度自适应布局

**核心算法**：基于子树实际高度分配垂直空间，防止节点Y方向干涉。

```gdscript
func _get_subtree_height(node_index, current_depth, max_depth, unit_height) -> float:
    # 叶子节点高度 = unit_height
    # 有子节点 = 所有子树高度之和
    # 取 max(unit_height, 子树总高度) 确保最小间距
    if sub_children.is_empty():
        return unit_height
    var total_height = 0.0
    for child in sub_children:
        total_height += _get_subtree_height(child, ...)
    return max(unit_height, total_height)

func _place_child_group(children, ...):
    # 1. 计算每个子节点的子树高度
    # 2. 总高度 = 所有子树高度之和
    # 3. 从 parent_pos_y - total_height/2 开始放置
    # 4. 每个子节点居中在自己的子树空间内
    for ci in children.size():
        node_y = current_y + subtree_heights[ci] / 2.0
        current_y += subtree_heights[ci]
```

**优势**：
- 每个节点的垂直空间由其子树实际需要的高度决定
- 不会出现子树重叠的情况
- 叶子节点之间保持最小间距（unit_height）
- 自动适应任意深度的子树

### 1.3 布局参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `center_node_size` | Vector2(180, 70) | 中心节点尺寸 |
| `main_node_size` | Vector2(140, 55) | 主节点尺寸 |
| `sub_node_size` | Vector2(120, 45) | 子节点尺寸 |
| `leaf_node_size` | Vector2(100, 40) | 叶子节点尺寸 |
| `horizontal_gap` | 160.0 | 水平间距（地图坐标空间，不含缩放） |
| `unit_height` | max(50+20, 75.0) = 75.0 | 垂直单位高度（地图坐标空间，不含缩放） |
| `main_center_x` | 3600.0 | 中心节点X坐标 |
| `main_center_y` | 2700.0 | 中心节点Y坐标 |

**注意**：`horizontal_gap` 和 `unit_height` 都在地图坐标空间中计算，不包含缩放因子。渲染时统一通过 `panel.position = base_pos * zoom_scale` 应用缩放，避免双重缩放问题。

### 1.4 自由节点

无父节点的非根节点放置逻辑：
1. 如果自由节点有 `pos2d` 字段，使用该坐标
2. 否则使用默认位置（右侧区域）

自由节点默认位置：

| 参数 | 值 |
|------|-----|
| 起始X | 4400.0 (ROOT_CENTER_X + 800) |
| 起始Y | 2700.0 + index * 180.0 |
| Y间距 | 180.0 |

### 1.5 自由节点子树展示

当自由节点被吸附到树中（成为某节点的子节点）后，该节点及其原本的子节点按以下规则显示：

- 该节点以普通子节点的形式出现在树中，有贝塞尔曲线连接到父节点
- 其原本的子节点（子树）以它为父节点递归展开，按 XMind 左右布局正常显示
- 父节点与子树节点之间的连线与普通父子节点连线一致

**视觉示例**：

```
root
├── A1
│   └── B ← 被吸附到这里，带自己的子树
│       ├── B1
│       └── B2
├── A2
└── A3
```

### 1.6 位置迁移

自动检测旧版根节点坐标并迁移到新版7200×5400地图：

| 旧版中心 | 新版中心 |
|----------|----------|
| (1200, 900) | (3600, 2700) |
| (2666, 2000) | (3600, 2700) |

迁移时所有节点的 pos2d 和 relative_offset 都会相应偏移。

## 二、节点渲染

### 2.1 节点样式

使用 `PanelContainer` + `StyleBoxFlat`：

| 属性 | 值 |
|------|-----|
| 圆角 | 12px（中心节点18px），随缩放变化 |
| 边框宽度 | 2px（选中3px），随缩放变化 |
| 边框颜色 | 白色 (1, 1, 1) |
| 填充颜色 | 透明 (0, 0, 0, 0) |
| 阴影大小 | 4px（已禁用），随缩放变化 |
| 阴影颜色 | (0, 0, 0, 0.3) |

### 2.2 节点样式状态

| 状态 | 边框颜色 | 边框宽度 |
|------|---------|---------|
| 正常 | 白色 (1, 1, 1) | 2px |
| 悬停 | 淡蓝色 (0, 0.5, 0.7) | 2px |
| 选中 | 蓝色 (0, 0.7, 1) | 3px |
| 吸附目标 | 绿色 (0, 1, 0) | 3px |
| 放置模式 | 绿色 (0, 1, 0.5) | 3px + 绿色阴影 |

### 2.3 节点尺寸（按深度）

| 深度 | 尺寸 | 字号 |
|------|------|------|
| 0（中心） | 180×70 | 20 |
| 1（主节点） | 140×55 | 16 |
| 2（子节点） | 120×45 | 14 |
| 3+（叶子） | 100×40 | 13 |

所有尺寸和字号随 `zoom_scale` 缩放。

### 2.4 文字样式

- 颜色：白色 (1, 1, 1)
- 水平对齐：居中
- 垂直对齐：居中

## 三、连线渲染

### 3.1 贝塞尔曲线

使用 `Line2D` 绘制三次贝塞尔曲线：

```
起点 = 父节点右边缘中心（或左边缘，取决于方向）
终点 = 子节点左边缘中心（或右边缘）
控制点1 = (起点.x + offset, 起点.y)
控制点2 = (终点.x - offset, 终点.y)
offset = 距离 × 0.5
```

### 3.2 连线参数

| 参数 | 值 |
|------|------|
| 线宽 | 2.5 * zoom_scale |
| 颜色 | (1.0, 1.0, 1.0, 0.8) 白色半透明 |
| 采样步数 | 24 |

### 3.3 自由节点连线处理

**关键逻辑**：自由节点不显示任何连接线条。

在 `_draw_tree_lines` 函数中，通过检查边的两端节点是否都在 `free_node_list` 中来过滤：

```gdscript
for item in all_edges:
    var target_idx = int(item["to"])
    var source_idx = int(item["from"])
    if not free_node_list.has(target_idx) and not free_node_list.has(source_idx):
        valid_edges.append(item)
```

这确保了：
- 拖拽后的节点（变为自由节点）不会显示到其原父节点的连线
- 自由节点之间的连线也不会显示

### 3.4 拖拽预览线

拖拽节点时显示预览连线：
- 从被拖拽节点中心到吸附目标节点中心
- 颜色：半透明蓝色 (0, 0.7, 1, 0.5)
- 宽度：2.0 * zoom_scale
- z_index：100（始终在最上层）

### 3.5 连线层级

连线添加到容器后，移到最底层（`move_child(line, 0)`），确保节点在连线上方。

## 四、背景样式

### 4.1 背景颜色

| 元素 | 颜色 |
|------|-----|
| 主Control | 黑色 (0, 0, 0) |
| ScrollContainer | 黑色 (0, 0, 0) |
| Container | 黑色 (0, 0, 0) |

## 五、缩放与滚动

### 5.1 缩放

| 参数 | 值 |
|------|------|
| 初始缩放 | 1.0 |
| 最小缩放 | 0.3 |
| 最大缩放 | 3.0 |
| 缩放步长 | 0.05 |

缩放通过 `_apply_zoom_update()` 增量更新节点属性实现，**不销毁不重建**。

### 5.2 缩放双路径设计

缩放和数据变更走两条完全不同的路径：

| 场景 | 调用路径 | 说明 |
|------|----------|------|
| 缩放（Ctrl+滚轮） | `_do_zoom()` → `_apply_zoom_update()` | 只更新属性，不销毁不创建 |
| 数据变更（增删节点、拖拽、编辑） | `rebuild()` → `build_mind_map_relative()` → `_clear_all()` + 全量重建 | 销毁所有控件后重新创建 |

### 5.3 缩放增量更新流程

```gdscript
func _apply_zoom_update(old_zoom: float) -> void:
    for index in node_controls.keys():
        var panel = node_controls[index]
        # 反推 base_pos（unscaled 中心点）
        var old_center = panel.position + panel.custom_minimum_size / 2.0
        var base_pos = old_center / old_zoom
        # 更新尺寸和位置
        panel.custom_minimum_size = node_size * zoom_scale
        panel.size = node_size * zoom_scale
        panel.position = base_pos * zoom_scale - node_size / 2.0
        # 创建新 StyleBoxFlat（不修改旧实例，避免不触发重绘）
        var style = StyleBoxFlat.new()
        style.set_corner_radius_all(...)
        style.set_border_width_all(...)
        panel.add_theme_stylebox_override("panel", style)
        # 更新 Label font_size
        label.add_theme_font_size_override("font_size", font_size)
    _apply_zoom_to_lines()
    _update_container_size()
```

**关键设计**：
- **反推 base_pos**：`base_pos = (panel.position + panel.size / 2) / old_zoom`，不需要额外存储 unscaled 位置
- **创建新 StyleBoxFlat**：每次缩放创建全新的 StyleBoxFlat 并 `add_theme_stylebox_override`，和 `_create_relative_node` 方式一致，避免直接修改 `get_theme_stylebox()` 返回的共享引用导致不触发重绘
- **显式设置 panel.size**：`custom_minimum_size` 只设最小值，必须同时设 `panel.size` 确保缩小时框不会保持旧的较大尺寸
- **信号只连一次**：`gui_input`、`mouse_entered`、`mouse_exited` 在 `_create_relative_node` 时连接，缩放时不重连

### 5.4 缩放连线更新

```gdscript
func _apply_zoom_to_lines() -> void:
    # 池化 Line2D：多了的 queue_free，少了的 new，已有的 clear_points + add_point
    var all_edges = data_manager.collect_edges()
    var valid_edges = 过滤出两端节点都存在的边
    # 差值调整 line_controls 数组大小
    for i in range(needed_count, existing_count):
        line_controls[i].queue_free()
    for i in range(existing_count, needed_count):
        line_controls.append(Line2D.new())
    # 复用已有 Line2D，只重新计算贝塞尔点
    for i in needed_count:
        line_controls[i].clear_points()
        # 重新算贝塞尔点，add_point
```

### 5.5 缩放节流

| 参数 | 值 | 说明 |
|------|-----|------|
| `_zoom_throttle_ms` | 80ms | 已废弃，不再使用节流判断 |
| `_on_zoom_throttle_timeout` | 150ms | 缩放停止后补一次连线确认更新 |

缩放时 `_apply_zoom_update()` 即时执行（无节流），`_on_zoom_throttle_timeout` 仅在缩放停止后补一次 `_apply_zoom_to_lines()` 确保最终状态一致。

### 5.6 缩放坐标保持

缩放时鼠标所指的地图坐标点保持不变：

```gdscript
func _do_zoom(old_zoom, mouse_global_pos):
    var mouse_viewport_pos = mouse_global_pos - scroll_container.get_global_position()
    var local_point = (mouse_viewport_pos + old_scroll) / old_zoom
    _apply_zoom_update(old_zoom)
    var new_scroll_x = local_point.x * zoom_scale - mouse_viewport_pos.x
    var new_scroll_y = local_point.y * zoom_scale - mouse_viewport_pos.y
```

### 5.7 元数据存储

缩放增量更新需要读取节点的 depth 和 is_center 信息，这些在 `build_mind_map_relative` 时填充：

| 变量 | 类型 | 填充时机 | 用途 |
|------|------|----------|------|
| `node_depths` | Dictionary | `_create_relative_node()` | 记录每个节点的 depth |
| `_node_is_center` | Dictionary | `_create_relative_node()` | 记录每个节点是否为中心节点 |
| `_main_root_index` | int | `build_mind_map_relative()` | 记录主根节点索引 |

这些字典在 `_clear_all()` 时一并清空。

### 5.8 滚动

使用 `ScrollContainer` 包裹容器：
- 容器最小尺寸：7200×5400 * zoom_scale
- 初始滚动位置：中心节点附近

### 5.3 重置视图

```gdscript
func reset_view():
    zoom_scale = 1.0
    rebuild()
    scroll_to_root_center()
```

## 六、空状态

当没有节点时显示提示文字：

| 属性 | 值 |
|------|-----|
| 文字 | "右键点击此处新建知识点\n或按 Ctrl+N 快速创建节点" |
| 字号 | 24 * zoom_scale |
| 颜色 | (0.5, 0.55, 0.65) |
| 位置 | (ROOT_CENTER_X - 400, ROOT_CENTER_Y - 60) * zoom_scale |
| 尺寸 | 800×120 * zoom_scale |

## 七、节点放置模式

新建自由节点后进入放置模式：

1. 节点跟随鼠标移动（`_snap_placing_node_to_mouse()`）
2. 节点显示绿色边框和阴影（`_apply_placing_node_style()`）
3. 左键点击确认放置（`_finalize_placing_node()`）
4. 右键点击取消放置并删除节点（`_cancel_placing_node()`）
5. 放置后自动保存坐标到 pos2d 和 relative_offset
6. 缩放时放置中的节点自动跟随鼠标更新位置

## 八、正确行为验证点

1. 背景为纯黑色
2. 节点为白色边框，透明填充、白色文字
3. 鼠标悬停节点时边框变为淡蓝色
4. 点击选中节点时边框变为蓝色
5. 点击空白处取消选中
6. 中心节点始终在容器中央
7. 左右两侧子树不重叠（子树高度自适应）
8. 贝塞尔曲线平滑不交叉
9. 缩放后节点和连线比例正确
10. 缩放时字体清晰不模糊（重算 font_size，非位图缩放）
11. 缩放时框大小正确跟随缩放（不出现框变大的问题）
12. 缩放时不销毁不重建节点（信号保持有效）
13. 滚动范围覆盖所有节点
14. 自由节点不与树形节点重叠
15. 自由节点不显示连接线条
16. Tab键在选中节点时新增子节点
17. Tab键在空白处新增自由节点
18. 缩放时鼠标所指位置不变
19. 放置模式下节点跟随鼠标
20. 拖拽时显示预览连线
21. 吸附目标节点显示绿色边框

## 九、快捷键支持

### 9.1 Input Map 配置

| 动作名 | 按键 | 功能 |
|--------|------|------|
| `refresh` | R | 刷新视图 |
| `new_node` | Ctrl+N | 创建自由节点 |
| `new_child` | Tab | 创建子节点/自由节点 |
| `undo` | Ctrl+Z | 撤销操作 |
| `redo` | Ctrl+Y | 重做操作 |
| `redo_alt` | Ctrl+Shift+Z | 重做操作（备选） |
| `delete` | Delete | 删除选中节点 |
| `deselect` | Escape | 取消选择 |
| `edit` | F2 | 编辑选中节点 |
| `save` | Ctrl+S | 保存数据 |
| `load` | Ctrl+L | 加载数据 |
| `optimize_layout` | Ctrl+O | 优化布局 |
| `focus_root` | Space | 聚焦根节点 |
| `zoom_in` | Ctrl+滚轮上 | 放大视图 |
| `zoom_out` | Ctrl+滚轮下 | 缩小视图 |

### 9.2 实现方式

快捷键在 Main2D.gd 的 `_on_gui_input()` 中直接检测：

```gdscript
if key_event.keycode == KEY_TAB:
    _on_tab_create_node()
elif key_event.keycode == KEY_DELETE:
    _on_delete_selected()
elif key_event.keycode == KEY_Z and key_event.ctrl_pressed:
    _on_undo()
```

同时也通过 KeyboardShortcutManager.gd 提供可扩展的快捷键注册系统。

## 十、拖拽功能

### 10.1 实现方式

使用 Godot 事件系统实现节点拖拽：

| 事件 | 处理逻辑 |
|------|----------|
| `MOUSE_BUTTON_LEFT` (按下) | 开始拖拽，记录偏移量，创建预览线 |
| `MOUSE_MOTION` | 实时更新节点位置，检测吸附目标，更新预览线 |
| `MOUSE_BUTTON_LEFT` (释放) | 结束拖拽，判断死区，执行吸附或拖出 |

### 10.2 坐标系统

- **开始拖拽**：记录鼠标与节点的全局坐标偏移
- **拖拽移动**：使用 `_screen_to_container()` 转换坐标，设置节点位置
- **结束拖拽**：将节点坐标转换为地图坐标并保存到 pos2d/relative_offset

### 10.3 特性

- 支持平滑拖拽
- 拖拽结束后自动更新节点数据
- 拖拽预览线实时显示
- 吸附目标自动高亮
- 死区内释放不改变节点关系
- Ctrl+点击支持多选
