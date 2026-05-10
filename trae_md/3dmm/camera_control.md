# 3D思维导图 - 相机控制

## 一、轨道相机模型

使用球坐标（theta, phi, radius）描述相机位置，相机始终注视目标点。

```
相机位置 = 目标点 + Vector3(
    radius * cos(phi) * sin(theta),
    radius * sin(phi),
    radius * cos(phi) * cos(theta)
)
```

### 1.1 参数范围

| 参数 | 范围 | 默认值 | 说明 |
|------|------|--------|------|
| `camera_target_radius` | 3.0 ~ 50.0 | 15.0 | 目标距离 |
| `camera_target_theta` | 无限制 | 0.0 | 水平角度（弧度） |
| `camera_target_phi` | -1.5 ~ 1.5 | 0.3 | 垂直角度（弧度） |
| `camera_smooth_speed` | > 0 | 12.0 | 插值速度 |

### 1.2 平滑插值

每帧在 `_process(delta)` 中执行：

```gdscript
camera_orbit_radius = lerp(camera_orbit_radius, camera_target_radius, smooth_speed * delta)
camera_orbit_theta = lerp(camera_orbit_theta, camera_target_theta, smooth_speed * delta)
camera_orbit_phi = lerp(camera_orbit_phi, camera_target_phi, smooth_speed * delta)
```

## 二、交互行为

### 2.1 旋转

| 触发 | 行为 |
|------|------|
| 空白处左键按下 | 开始旋转模式 `camera_is_rotating = true` |
| 鼠标移动（旋转中） | `theta -= delta.x * 0.005`, `phi += delta.y * 0.005`（clamp -1.5~1.5） |
| 左键释放 | 结束旋转模式 |
| 旋转开始时 | 清除聚焦目标 `_focus_target = Vector3.ZERO` |

### 2.2 缩放

| 触发 | 行为 |
|------|------|
| 滚轮上 | `radius = max(3.0, radius - 1.0)` |
| 滚轮下 | `radius = min(50.0, radius + 1.0)` |

### 2.3 聚焦

| 函数 | 行为 |
|------|------|
| `focus_on_node(index)` | 设置目标点为节点位置，radius=10 |
| `select_node(index)` | 清除旧选择，高亮新节点 |
| `focus_and_select_node(index)` | 聚焦 + 选中（组合操作） |
| `clear_all_selection()` | 取消所有高亮 |

### 2.4 自由节点轨道锁定（新增）

聚焦自由节点（galaxy_id > 0）时，相机锁定围绕该节点旋转，焦点**不会**因点击空白或旋转相机而消失。

| 变量 | 类型 | 说明 |
|------|------|------|
| `_orbiting_free_node_index` | int | 当前锁定的自由节点索引，-1表示无锁定 |

**行为规则**：
- 聚焦自由节点 → `_orbiting_free_node_index = index`，相机围绕该节点旋转
- 点击空白旋转相机 → 焦点不消失（`_orbiting_free_node_index >= 0` 时跳过清除）
- 右键已锁定的自由节点 → 菜单显示"取消聚焦"
- "取消聚焦" → 清除 `_orbiting_free_node_index` + 清除 `_focus_target`
- 聚焦非自由节点 → `_orbiting_free_node_index = -1`，行为与之前一致
- 刷新/重置视图 → 同时清除轨道锁定
- 锁定期间该节点保持高亮（`_clear_selection` 跳过轨道节点）

**特殊行为**：
- 自由星系聚焦后，相机以该自由节点位置为注视中心旋转，根星系和其他星系保持原位
- 聚焦一个自由星系内的子节点时，相机以该子节点位置为中心，但其所在星系的其他节点仍可见
- 从自由星系聚焦到根星系 → 相机平稳移动回原点区
- 从根星系聚焦到自由星系 → 相机移动到自由节点位置，该自由节点成为轨道中心

## 三、注视目标

- **默认状态**：注视根节点位置 `_get_root_node_position()`
- **聚焦自由星系节点**：注视该自由节点位置，相机围绕它旋转，焦点锁定不消失
- **手动旋转时**：有轨道锁定则不清除聚焦；无锁定则清除聚焦回到根节点

## 四、正确行为验证点

1. 首次加载时，相机对准根星系节点，radius=15
2. 聚焦自由星系节点后，相机平滑移动到该自由星系位置
3. 聚焦自由节点期间，点击空白旋转相机，焦点不消失
4. 右键已锁定的自由节点，菜单显示"取消聚焦"
5. 取消聚焦后恢复默认行为
6. 锁定期间该节点保持高亮不被清除
7. 缩放不会超出范围（3.0 ~ 50.0）
8. 聚焦不同星系时相机半径自适应调整