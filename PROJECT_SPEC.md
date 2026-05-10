# 考研知识图谱 - 项目架构文档

## 一、项目架构

### 文件清单与职责

| 文件 | 类型 | 职责 |
|------|------|------|
| `Global.gd` | GDScript (AutoLoad) | 全局单例，管理工作目录、学科CRUD、用户偏好持久化 |
| `SubjectSelector.gd` | GDScript | 学科选择界面逻辑：列表展示、新建/导入/导出/打开学科 |
| `SubjectSelector.tscn` | 场景文件 | 学科选择界面UI布局 |
| `SubjectEditor.gd` | GDScript | 编辑界面逻辑：3D/2D视图切换、数据管理器初始化、节点CRUD对话框 |
| `SubjectEditor.tscn` | 场景文件 | 编辑界面UI布局 |
| `SettingsPage.gd` | GDScript | 设置页面：语言切换等 |
| `project.godot` | 项目配置 | Godot引擎配置（自动加载、主场景、渲染器等） |
| `script/2dmm/DataManager.gd` | GDScript (RefCounted) | 数据管理：知识点CRUD、JSON读写、深度计算 |
| `script/2dmm/MindMap2D.gd` | GDScript (RefCounted) | 2D思维导图：XMind风格布局、贝塞尔曲线连线 |
| `script/2dmm/HistoryManager.gd` | GDScript (RefCounted) | 历史记录：撤销/重做操作 |
| `script/2dmm/ContextMenuManager.gd` | GDScript (RefCounted) | 右键菜单：节点菜单、空白菜单 |
| `script/2dmm/LayoutOptimizer.gd` | GDScript (RefCounted) | 布局优化器：垂直空间自动分配、防节点干涉 |
| `script/2dmm/EditNodeDialog.gd` | GDScript (ConfirmationDialog) | 编辑节点对话框 |
| `script/2dmm/KeyboardShortcutManager.gd` | GDScript | 快捷键管理：Ctrl+S/L/O 等 |
| `script/2dmm/DebugLogger.gd` | GDScript | 调试日志工具 |
| `script/2dmm/Main2D.gd` | GDScript | 2D视图主控制器 |
| `script/3dmm/KnowledgeMap.gd` | GDScript (Node3D) | 3D知识图谱：相机控制、节点交互、布局渲染 |
| `script/3dmm/LayoutManager.gd` | GDScript (RefCounted) | 布局算法：Fibonacci球面布局、多星系轨道分布 |
| `script/3dmm/PointManager.gd` | GDScript (RefCounted) | 3D节点渲染：球体、标签、连线 |
| `script/3dmm/DetailPopup.gd` | GDScript | 3D/2D详情弹窗 |
| `script/shared/DataManager3DAdapter.gd` | GDScript (RefCounted) | DataManager 3D适配器：桥接2dmm数据层与3dmm功能 |
| `script/2dtr/CognitiveMap2D.gd` | GDScript (RefCounted) | 2D认知地图：题目卡片网格、力导向布局、选中高亮连线 |
| `script/2dtr/CognitiveMapDataManager.gd` | GDScript (RefCounted) | 认知地图数据管理：problems/relations CRUD、JSON读写、知识点引用校验 |
| `script/2dtr/ProblemCanvas.gd` | GDScript (Control) | 题目独立关系画布：三行布局（前置/题目/用到）、右键添加关系 |
| `script/2dtr/ContextMenuManager.gd` | GDScript (RefCounted) | 认知地图右键菜单：新建题目、自动布局、添加关联知识点、添加关系线 |
| `script/2dtr/HistoryManager.gd` | GDScript (RefCounted) | 认知地图历史记录：撤销/重做 |
| `script/2dtr/DataManager.gd` | GDScript (RefCounted) | 认知地图辅助数据管理 |
| `script/2dtr/MindMap2D.gd` | GDScript (RefCounted) | 认知地图2D视图基础（从2dmm复制，适配认知地图） |
| `script/2dtr/EditNodeDialog.gd` | GDScript (ConfirmationDialog) | 认知地图节点编辑对话框 |
| `script/2dtr/DebugLogger.gd` | GDScript | 认知地图调试日志 |
| `script/2dtr/Main2D.gd` | GDScript | 认知地图独立主界面 |

### 场景切换流程

```
启动 → SubjectSelector.tscn（主场景）
         │
         ├── 点击"设置" → SettingsPage.tscn（动态创建）
         │
         ├── 点击"打开学科" → SubjectEditor.tscn
         │                        │
         │                        ├── [3D导图] KnowledgeMap (Node3D)
         │                        │     ├── LayoutManager (布局)
         │                        │     ├── PointManager (渲染)
         │                        │     └── ContextMenuManager (菜单)
         │                        │
         │                        ├── [2D导图] MindMap2D (Node2D)
         │                        │     ├── LayoutOptimizer (布局优化)
         │                        │     ├── ContextMenuManager (菜单)
         │                        │     └── HistoryManager (历史)
         │                        │
         │                        ├── [2D认知] CognitiveMap2D (RefCounted)
         │                        │     ├── 题目卡片网格布局
         │                        │     ├── 力导向自动布局
         │                        │     ├── 选中高亮连线（灰色默认）
         │                        │     ├── 右键：新建题目/添加关联知识点/添加关系线/自动布局
         │                        │     └── 双击题目 → 编辑对话框 → 进入关系画布
         │                        │           └── ProblemCanvas (独立画布)
         │                        │                 ├── 三行布局：前置/题目/用到
         │                        │                 ├── 贝塞尔曲线连线
         │                        │                 └── 右键添加/删除关系
         │                        │
         │                        ├── DataManager (共享数据，2dmm层)
         │                        ├── CognitiveMapDataManager (认知地图数据，2dtr层)
         │                        └── DataManager3DAdapter (数据适配，shared层)
         │
         └── Global.gd (常驻内存，自动加载)
```

## 二、核心数据结构

### 学科JSON格式

每个学科对应工作目录下的一个 `.json` 文件：

```json
{
    "name": "高等数学",
    "nodes": [
        {
            "id": "gaoshu_001",
            "name": "极限",
            "description": "函数极限的定义与性质",
            "mastery": 0,
            "position": [0.0, 0.0, 0.0],
            "parent": ""
        },
        {
            "id": "gaoshu_002",
            "name": "导数",
            "description": "导数的定义与计算",
            "mastery": 1,
            "position": [2.0, 0.5, 1.0],
            "parent": "极限"
        }
    ]
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | String | 唯一标识符 |
| `name` | String | 知识点名称 |
| `description` | String | 详细描述 |
| `mastery` | int | 掌握程度：0=未学习, 1=学习中, 2=已掌握 |
| `position` | Array[float] | 3D坐标 [x, y, z] |
| `parent_id` | String | 父节点ID（空字符串表示根节点） |
| `galaxy_id` | int | 星系ID：0=主星系，>0=独立自由星系 |
| `relations` | Array[Object] | 关系列表：{target: String, type: String} |

### 用户偏好配置 (`user://preferences.cfg`)

```ini
[general]
workspace_dir="C:/Users/xxx/workspace"
recent_subjects=["高数", "线代", "概率论"]

[display]
language="zh"
```

## 三、已实现功能列表

### Global.gd - 全局管理
- [x] 工作目录的读取 / 设置 / 持久化
- [x] 获取工作目录下所有 .json 学科文件列表
- [x] 新建学科（创建含默认结构的 .json 文件）
- [x] 导入学科（复制外部 .json 到工作目录）
- [x] 导出学科（复制工作目录内 .json 到指定路径）
- [x] 最近打开记录（最多3条，自动去重）

### SubjectSelector - 学科选择界面
- [x] 顶部栏显示当前工作目录路径
- [x] "切换工作目录"按钮
- [x] ItemList 展示所有学科文件名
- [x] 新建/导入/导出学科功能
- [x] 双击列表项打开编辑界面
- [x] 底部"最近打开"列表
- [x] 设置按钮跳转设置页面

### SettingsPage - 设置页面
- [x] 语言切换（中文/英文）
- [x] 设置持久化存储

### SubjectEditor - 编辑界面
- [x] 顶部栏显示当前学科名称
- [x] 3D/2D视图切换按钮
- [x] 返回学科列表按钮
- [x] 共享 DataManager 实例

### KnowledgeMap - 3D知识图谱
- [x] 相机控制：轨道相机（theta/phi/radius）、滚轮缩放、中键旋转
- [x] 相机平滑插值（lerp，smooth_speed=12）
- [x] 聚焦系统：`focus_on_node()` / `focus_and_select_node()` / `select_node()` / `clear_all_selection()`
- [x] 新建/编辑节点后自动聚焦+选中
- [x] 节点交互：左键选择/拖拽、右键菜单、双击详情
- [x] 空状态提示：无节点时显示引导文字
- [x] 新建节点对话框：名称/描述/X-Y-Z位置/掌握度/父节点选择
- [x] 编辑节点对话框：完整字段编辑（名称/描述/位置/掌握度/父节点）
- [x] 删除节点确认对话框
- [x] 快捷键：Ctrl+N 新建、Ctrl+Z 撤销、Ctrl+Y 重做、R 刷新、Delete 删除
- [x] 材质调试面板（右键→材质调试面板）：6种颜色+3种参数实时调节
- [x] 鼠标位置新建节点（过根节点垂直视线的平面射线检测）
- [x] 掌握度三态颜色：未学习(灰)、学习中(橙黄)、已掌握(绿)
- [x] 选中高亮色可配置（默认亮黄色，发光倍数2x）
- [x] 批量操作：多选删除、批量设置掌握度
- [x] **星系模式**：支持多根节点（galaxy_id），吸收/分离子节点
- [x] **Tab键快捷创建**：选中节点按Tab创建子节点，空节点按Tab创建自由节点
- [x] **关系连线**：Relation关系线渲染（橙色虚线）

### LayoutManager - 布局算法
- [x] Fibonacci 球面布局（同层节点在球面上均匀分布）
- [x] 多星系轨道分布（自由星系沿球面轨道排列）
- [x] 自适应半径（根据节点数量动态调整分布半径）
- [x] 树形层级缩放（root_node_radius + depth_scale_factor）

### PointManager - 3D节点渲染
- [x] 球体节点渲染（大小随深度缩放）
- [x] Label3D 标签（billboard、无深度测试）
- [x] 掌握度三态材质（未学习/学习中/已掌握）
- [x] 选中高亮材质（可配置颜色+发光倍数）
- [x] 曲线连线（TubeTrailMesh + Curve3D）
- [x] 材质参数对外暴露 setter：`set_mat_*` / `refresh_all_materials()`
- [x] 射线检测拾取 `pick_point_index()`

### MindMap2D - 2D思维导图
- [x] XMind风格布局：中心节点左右展开
- [x] 贝塞尔曲线连线
- [x] 掌握度颜色标识
- [x] 滚轮缩放、重置视图
- [x] 空状态提示
- [x] 右键菜单（节点菜单、空白菜单、多选菜单）
- [x] 垂直空间自动分配（防节点干涉）
- [x] 防抖动缩放（鼠标位置保持）
- [x] Ctrl+S 保存、Ctrl+L 加载、Ctrl+O 优化布局

### DataManager - 数据管理
- [x] JSON 文件读写
- [x] 知识点 CRUD 操作
- [x] 深度计算（树形结构）
- [x] 唯一ID/名称生成
- [x] 边关系收集
- [x] **星系模式**：galaxy_id 字段管理、多星系分离
- [x] 节点路径查询（get_node_path）
- [x] 快照与恢复（get_items_snapshot / restore_items_snapshot）
- [x] 数据备份与恢复（create_backup / restore_from_backup）

### HistoryManager - 历史记录
- [x] 撤销/重做栈管理
- [x] 支持操作类型：add、delete、edit、move
- [x] 最大历史记录限制（50条）

### ContextMenuManager - 右键菜单
- [x] 节点菜单：详情、定位、切换视图、掌握度（3态）、编辑、删除
- [x] 空白菜单：新建、刷新、重置、截图、材质调试面板
- [x] 多选菜单：批量掌握度、批量删除

### DetailPopup - 详情弹窗
- [x] 3D/2D通用详情弹窗（PanelContainer + CanvasLayer）
- [x] 显示节点完整信息：ID、名称、星系、父节点、掌握度、位置、路径
- [x] 操作按钮：聚焦、编辑、删除
- [x] 关系列表展示

### DataManager3DAdapter - 数据适配器
- [x] 桥接 DataManager 与 3dmm 专用方法
- [x] 星系相关：get_galaxy_nodes / get_all_galaxy_ids / get_galaxy_root_index
- [x] 节点操作：set_item_position / propagate_galaxy_id / cleanup_relations_for
- [x] 树形操作：absorb_subtree / detach_subtree / cleanup_empty_galaxies

### CognitiveMap2D - 2D认知地图（2dtr）
- [x] 题目卡片网格布局（2列自动换行）
- [x] 卡片显示：标题、难度星标、题型标签、关联知识点标签
- [x] 力导向自动布局（排斥力+向心力，知识节点多行对齐）
- [x] 关系连线（默认灰色半透明，选中高亮按类型着色）
- [x] 选中题目/知识节点时高亮所有相关连线
- [x] 右键菜单：新建题目、添加关联知识点（搜索+选类型）、添加关系线（子菜单4种类型）、自动布局、刷新、重置视图
- [x] 连线模式：选择关系类型后鼠标跟踪直线，点击目标知识节点完成关系创建
- [x] 关系覆盖：同一题目到同一知识点重复创建时覆盖旧关系
- [x] 删除关系（右键节点）
- [x] 快捷键：Ctrl+N新建题目、Delete删除、Escape取消连线

### CognitiveMapDataManager - 认知地图数据管理
- [x] 题目(problems) CRUD：加载/保存/新增/更新/删除
- [x] 关系(relations) CRUD：加载/保存/新增/删除/按题目查询/按知识点查询
- [x] 5种关系类型：用到、可替换、前置、延伸、自定义
- [x] 知识点改名时自动更新关系中的 target 引用
- [x] 知识点删除时自动清理引用该知识点的关系
- [x] 题目删除时自动清理关联关系

### ProblemCanvas - 题目独立关系画布
- [x] 三行布局：上区（用到/延伸的知识点）→ 中区（题目卡片）→ 下区（前置知识）
- [x] 贝塞尔曲线连线，颜色按关系类型区分
- [x] 右键空白 → 添加关联知识点（搜索+选类型）
- [x] 右键知识节点 → 删除关系
- [x] 返回按钮 → 销毁画布，回到认知地图主视图

### SubjectEditor - 编辑界面（含2dtr整合）
- [x] 三Tab切换：3D导图 / 2D导图 / 2D认知
- [x] 2D认知：新建题目对话框（两列布局：标题+题型，难度+来源）
- [x] 2D认知：编辑题目对话框（两列布局 + 图片管理 + "进入关系画布"按钮）
- [x] 2D认知：添加关联知识点（搜索+选关系类型+自动添加到视图）
- [x] 2D认知：数据同步（思维导图→认知地图，切换Tab时自动刷新）
- [x] 2D认知：Ctrl+N新建题目、Delete删除、Escape取消连线/取消选中

## 四、编码规范

### 命名约定
- **私有成员变量**：下划线前缀 `_data_manager`, `_knowledge_map`
- **私有方法**：下划线前缀 `_refresh_display()`, `_on_xxx_pressed()`
- **公开方法**：无前缀 `get_workspace_dir()`, `rebuild_all()`
- **信号回调**：`_on_节点名_事件()` 格式
- **信号名称**：蛇形命名 `point_clicked`, `nodes_changed`

### 文件组织
- 场景脚本放在项目根目录
- 工具类/管理器放在 `script/` 目录
- 脚本文件名使用 PascalCase

### API 使用规范
- 文件对话框：`DisplayServer.file_dialog_show()`
- 文件操作：`FileAccess` / `DirAccess`
- 配置读写：`ConfigFile`
- JSON 解析：内置 `JSON` 类
- 动态对话框：直接创建 `ConfirmationDialog`，在 `popup_centered()` 前连接信号

### 类型转换注意事项
- JSON 中的 `position` 是 `Array[float]`，使用时需转换为 `Vector3`
- `HistoryManager.push_move_action()` 参数类型为 `Vector3`，不是 `Array`

### UI 交互规范
- 所有弹窗使用代码动态创建
- 对话框信号连接在 `popup_centered()` 之前完成
- 避免使用 `call_deferred` 调用私有函数（`_`开头）

## 五、调试打印规范

在关键函数入口添加调试打印，格式如下：

```gdscript
func _do_create_node(node_name: String, description: String, parent_name: String) -> void:
    print("=== _do_create_node START ===")
    print("  node_name: %s" % node_name)
    # ... 函数逻辑
    print("=== _do_create_node END ===")
```

调试完成后可保留打印，便于后续问题排查。

## 六、选择/聚焦 API 规范

KnowledgeMap.gd 提供标准化的选择和聚焦函数，所有新建/编辑操作统一调用：

| 函数 | 参数 | 返回 | 功能 |
|------|------|------|------|
| `focus_on_node(index)` | int 节点索引 | void | 设置相机注视目标为该节点位置，拉近到 radius=10 |
| `select_node(index)` | int 节点索引 | void | 清除旧选择，高亮指定节点，更新 selected_index/selected_indices |
| `clear_all_selection()` | 无 | void | 取消所有节点高亮，清空 selected_index 和 selected_indices |
| `focus_and_select_node(index)` | int 节点索引 | void | **组合操作**：聚焦 + 选中（新建/编辑后调用此函数） |

### 调用约定
- `_do_create_node()` 结尾 → `focus_and_select_node(new_index)`
- 编辑确认回调 → `focus_and_select_node(index)`
- 用户手动旋转相机 → 自动清除 `_focus_target`
- 刷新/重置视图 → 自动清除 `_focus_target`

### 材质系统参数（KnowledgeMap ↔ PointManager 双向同步）

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `mat_unlearned_color` | Color | (0.6, 0.6, 0.6) 灰 | mastery=0 颜色 |
| `mat_learning_color` | Color | (1.0, 0.6, 0.1) 橙黄 | mastery=1 颜色 |
| `mat_learned_color` | Color | (0.2, 0.85, 0.2) 绿 | mastery=2 颜色 |
| `mat_selected_color` | Color | (1.0, 1.0, 0.3) 亮黄 | 选中高亮色 |
| `mat_roughness` | float | 0.3 | 粗糙度 |
| `mat_metallic` | float | 0.0 | 金属度 |
| `mat_emission_energy` | float | 0.8 | 发光强度 |
| `mat_selected_emission_mult` | float | 2.0 | 选中发光倍数 |

## 七、待实现功能

### 优化项
- [x] 编辑节点功能（完整字段）
- [x] 批量操作完善
- [ ] 搜索/过滤功能
- [ ] 导出图片功能完善

### 2dtr 认知地图 — 待实现
- [x] 题目卡片网格布局
- [x] 5种关系类型（用到/可替换/前置/延伸/自定义）
- [x] 力导向布局（基础版）
- [x] 关系连线颜色编码
- [x] 选中高亮连线
- [x] 题目独立关系画布（ProblemCanvas）
- [ ] 连线箭头（三角形，8px）
- [ ] 连线线型（虚线/点线）
- [ ] Pinning 系统（拖拽固定，双击解除）
- [ ] 题目分组合并（相同关系集合自动合并为组）
- [ ] 顶部筛选栏（搜索/章节/题型/难度/来源）
- [ ] 缩放三级渲染（概览/中等/详细）
- [ ] 关系标签悬停显示
- [ ] layout.json 持久化
- [ ] 知识点节点路径面包屑显示
- [ ] 知识点关联题数角标
- [ ] 题目卡片按题型区分色调

### 目录结构
```
script/
├── 2dmm/                 # 2D思维导图模块
│   ├── DataManager.gd
│   ├── MindMap2D.gd
│   ├── HistoryManager.gd
│   ├── ContextMenuManager.gd
│   ├── LayoutOptimizer.gd
│   ├── EditNodeDialog.gd
│   ├── KeyboardShortcutManager.gd
│   ├── DebugLogger.gd
│   └── Main2D.gd
├── 3dmm/                 # 3D知识图谱模块
│   ├── KnowledgeMap.gd
│   ├── LayoutManager.gd
│   ├── PointManager.gd
│   └── DetailPopup.gd
├── 2dtr/                 # 2D认知地图模块
│   ├── CognitiveMap2D.gd          # 主控制器：卡片网格、力导向、连线
│   ├── CognitiveMapDataManager.gd # 数据管理：problems/relations CRUD
│   ├── ProblemCanvas.gd           # 题目独立关系画布
│   ├── ContextMenuManager.gd      # 认知地图右键菜单
│   ├── HistoryManager.gd          # 认知地图历史记录
│   ├── DataManager.gd             # 辅助数据管理
│   ├── MindMap2D.gd               # 2D视图基础
│   ├── EditNodeDialog.gd          # 节点编辑对话框
│   ├── DebugLogger.gd             # 调试日志
│   └── Main2D.gd                  # 独立主界面
└── shared/               # 共享组件
    └── DataManager3DAdapter.gd  # 数据层适配器
```
