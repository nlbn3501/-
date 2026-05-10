# 超级拼装方案 - 3大核心功能整合

## 一、整体架构

```
启动 → SubjectSelector.tscn（主场景）
        │
        ├── Global.gd (AutoLoad，常驻内存)
        │     └── 工作目录管理、学科CRUD、用户偏好
        │
        └── 打开学科 → SubjectEditor.tscn（编辑界面）
                         │
                         ├── 顶部栏：学科名 + 3个Tab按钮 + 返回
                         │
                         ├── Tab页容器（3个视图，同一时刻只显示1个）
                         │     ├── Page3DMM  ← 3D思维导图
                         │     ├── Page2DMM  ← 2D思维导图
                         │     └── Page2DTR  ← 2D认知地图
                         │
                         ├── DataManager（共享单例，思维导图视图共用）
                         └── CognitiveMapDataManager（独立，认知地图专用）
```

## 二、最终文件清单

```
project_root/
├── project.godot                    ← AutoLoad: Global
├── Global.gd                        ← 全局单例
├── SubjectSelector.gd               ← 学科选择界面
├── SubjectSelector.tscn             ← 学科选择场景
├── SubjectEditor.gd                 ← 编辑界面（拼装入口）
├── SubjectEditor.tscn               ← 编辑界面场景
├── SettingsPage.gd                  ← 设置页面
├── icon.svg
│
└── script/
    ├── 2dmm/                       ← 2D思维导图模块
    │   ├── MindMap2D.gd            ← 2D思维导图主控制器
    │   ├── DataManager.gd          ← 思维导图数据管理（共享）
    │   ├── HistoryManager.gd       ← 撤销/重做（共享）
    │   ├── DetailPopup.gd          ← 详情弹窗（共享）
    │   ├── ContextMenuManager.gd   ← 右键菜单（2D思维导图）
    │   ├── DebugLogger.gd          ← 调试日志
    │   ├── EditNodeDialog.gd       ← 编辑节点对话框
    │   ├── KeyboardShortcutManager.gd ← 键盘快捷键
    │   ├── LayoutOptimizer.gd      ← 力布局优化
    │   └── Main2D.gd               ← 2D思维导图独立主界面
    │
    ├── 3dmm/                       ← 3D思维导图模块
    │   ├── KnowledgeMap.gd         ← 3D思维导图主控制器
    │   ├── PointManager.gd         ← 3D节点渲染
    │   ├── LayoutManager.gd        ← 3D布局算法
    │   └── DetailPopup.gd          ← 3D详情弹窗
    │
    ├── 2dtr/                       ← 2D认知地图模块
    │   ├── CognitiveMap2D.gd       ← 2D认知地图主控制器（含节点渲染+连线绘制+分组逻辑）
    │   ├── CognitiveMapDataManager.gd ← 认知地图数据管理（独立）
    │   ├── ContextMenuManager.gd   ← 右键菜单（认知地图）
    │   ├── Main2D.gd               ← 2D认知地图独立主界面
    │   └── ...（ForceLayout2D.gd、ProblemPanel.gd 待创建）
    │
    └── shared/                     ← 共享模块
        └── DataManager3DAdapter.gd ← 3D数据管理适配器
```

## 三、SubjectEditor.gd - 拼装核心

SubjectEditor 是3个视图的容器和协调者，负责：
1. 创建和持有共享的 DataManager 实例
2. 创建独立的 CognitiveMapDataManager 实例
3. 构建3个视图页面
4. Tab切换逻辑
5. 视图间信号路由

### 3.1 核心变量

```gdscript
extends Control

var subject_name: String = ""
var data_file_path: String = ""

var _data_manager: RefCounted                    # 思维导图数据
var _cognitive_map_data: RefCounted              # 认知地图数据
var _history_manager: RefCounted

var _knowledge_map: Node3D        # 3D思维导图
var _mindmap_2d: RefCounted       # 2D思维导图
var _cognitive_map_2d: RefCounted # 2D认知地图

var _current_tab: int = 0         # 0=3DMM, 1=2DMM, 2=2DTR

var _vp_container: SubViewportContainer  # 3D视图容器
var _sub_vp: SubViewport                 # 3D视口
var _page_2d_mm: Control                 # 2D思维导图页面
var _page_2d_tr: Control                 # 2D认知地图页面

var _tab_buttons: Array[Button] = []

const BAR_HEIGHT := 40
const TAB_NAMES = ["3D导图", "2D导图", "2D认知"]
```

### 3.2 _ready() 流程

```gdscript
func _ready() -> void:
    anchor_right = 1.0
    anchor_bottom = 1.0
    _resolve_data_path()
    _build_ui()              # 构建顶部栏 + 3个页面容器
    _init_data_manager()     # 创建共享DataManager + CognitiveMapDataManager
    _build_3d_mm()           # 构建3D思维导图
    _build_2d_mm()           # 构建2D思维导图
    _build_2d_tr()           # 构建2D认知地图
    _connect_signals()       # 连接所有信号
    _switch_tab(0)           # 默认显示3D思维导图
    call_deferred("_fit_to_window")
```

### 3.3 UI构建

```
┌──────────────────────────────────────────────────────┐
│ [学科名]  [3D导图] [2D导图] [2D认知]        [返回]   │ ← TopBar
├──────────────────────────────────────────────────────┤
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  VpContainer (3D视图)                           │  │ ← Tab0
│  │  └── SubViewport                                │  │
│  │       └── KnowledgeMap (3D思维导图)               │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  Page2DMM (2D思维导图)                          │  │ ← Tab1
│  │  └── MindMap2D                                  │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  Page2DTR (2D认知地图)                          │  │ ← Tab2
│  │  └── CognitiveMap2D + ProblemPanel (右侧面板)   │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### 3.4 Tab切换逻辑

```gdscript
func _switch_tab(tab_index: int) -> void:
    _current_tab = tab_index
    
    # 隐藏所有页面
    _vp_container.visible = false
    _page_2d_mm.visible = false
    _page_2d_tr.visible = false
    
    # 更新Tab按钮样式
    for i in _tab_buttons.size():
        _tab_buttons[i].button_pressed = (i == tab_index)
    
    # 显示对应页面
    match tab_index:
        0: # 3D思维导图
            _vp_container.visible = true
            _sub_vp.disable_3d = false
            if _knowledge_map:
                _knowledge_map.visible = true
        1: # 2D思维导图
            _page_2d_mm.visible = true
            if _mindmap_2d:
                _mindmap_2d.rebuild()
        2: # 2D认知地图
            _page_2d_tr.visible = true
            if _cognitive_map_2d:
                _cognitive_map_2d.rebuild()
                _cognitive_map_data.refresh()
```

## 四、数据管理方案

### 4.1 两个数据管理器

```gdscript
func _init_data_manager() -> void:
    # 思维导图数据（所有视图共用）
    _data_manager = load("res://script/2dmm/DataManager.gd").new(data_file_path)
    
    # 认知地图数据（独立目录）
    var cognitive_map_path = data_file_path.get_base_dir() + "/cognitive_map/"
    _cognitive_map_data = load("res://script/2dtr/CognitiveMapDataManager.gd").new(cognitive_map_path)
    
    _history_manager = load("res://script/2dmm/HistoryManager.gd").new(_data_manager)
```

### 4.2 数据传递

```gdscript
_knowledge_map = KnowledgeMapScript.new(_data_manager)
_mindmap_2d = MindMap2DScript.new(_data_manager)
_cognitive_map_2d = CognitiveMap2DScript.new(_data_manager, _cognitive_map_data)
```

### 4.3 数据同步规则

| 操作 | 触发视图 | 同步行为 |
|------|----------|----------|
| 新建/编辑/删除节点 | 思维导图 | DataManager.save_data() |
| 知识点改名 | 思维导图 | 保存后，切换到认知地图时 CognitiveMapDataManager.refresh() 自动更新关系中的 target 引用 |
| 删除知识点 | 思维导图 | 保存后，切换到认知地图时自动清理引用 |
| 新增/修改/删除题目 | 认知地图 | CognitiveMapDataManager.save_all() |
| 新增/修改/删除关系 | 认知地图 | CognitiveMapDataManager.save_all() |
| 拖动节点固定位置 | 认知地图 | CognitiveMapDataManager.save_layout() |
| 切换到认知地图 | Tab切换 | 调用 CognitiveMapDataManager.refresh() → 重新读取 mindmap_nodes.json |

## 五、信号路由

### 5.1 视图发出的信号

```gdscript
# 思维导图信号
signal node_clicked(index: int)
signal node_double_clicked(index: int)
signal node_context_requested(index: int, position: Vector2)
signal request_create_node(parent_hint: int)

# 认知地图信号
signal problem_created(problem_id: String)
signal relation_added(problem_id: String, target: String, type: String)
signal relation_removed(relation_id: String)
signal request_switch_to_mindmap(index: int)
```

### 5.2 SubjectEditor路由规则

```gdscript
func _connect_signals() -> void:
    # 3D思维导图
    _knowledge_map.point_double_clicked.connect(_show_detail_popup)
    _knowledge_map.request_create_node.connect(_on_request_create_node)
    
    # 2D思维导图
    _mindmap_2d.node_double_clicked.connect(_show_detail_popup)
    _mindmap_2d.request_create_node.connect(_on_request_create_node)
    
    # 2D认知地图
    _cognitive_map_2d.request_switch_to_mindmap.connect(func(idx):
        _switch_tab(1)
        _mindmap_2d.focus_on_node(idx)
    )
```

## 六、ContextMenuManager 扩展

### 6.1 认知地图菜单项

| 菜单 | 新增项 | 动作 |
|------|--------|------|
| 认知地图空白菜单 | 新建题目 | `create_problem` |
| 认知地图空白菜单 | 连线（选择关系类型后点知识点） | `start_connect` |
| 认知地图空白菜单 | 搜索知识点（拉取到画布） | `search_knowledge` |
| 认知地图空白菜单 | 刷新布局 | `refresh_layout` |
| 认知地图题目节点菜单 | 编辑题目 | `edit_problem` |
| 认知地图题目节点菜单 | 管理关系 | `manage_relations` |
| 认知地图题目节点菜单 | 在思维导图中查看 | `switch_to_mindmap` |
| 认知地图知识点菜单 | 在思维导图中查看 | `switch_to_mindmap` |
| 认知地图连线菜单 | 修改关系类型 | `edit_relation` |
| 认知地图连线菜单 | 删除关系 | `delete_relation` |

### 6.2 构造函数扩展

```gdscript
func _init(dm: RefCounted, parent: Node, view_type: String = "mindmap_3d") -> void:
    data_manager = dm
    parent_node = parent
    _view_type = view_type  # "mindmap_3d", "mindmap_2d", "cogmap_2d"
```

根据 `_view_type` 决定菜单内容。

## 七、拼装步骤

### 第1步：准备共享模块

1. 确保 `DataManager.gd` 已具备必要API
2. 新建 `CognitiveMapDataManager.gd`（参考 data_structure.md 中的API定义）
3. 确保 `HistoryManager.gd` 支持关系操作的撤销/重做
4. 确保 `DetailPopup.gd` 支持显示题目信息

### 第2步：3个核心功能独立调试

在各自独立项目中完成开发和测试：

| 项目 | 核心文件 | 测试重点 |
|------|----------|----------|
| 3dmm 独立项目 | KnowledgeMap.gd, PointManager.gd | 相机、星系布局、对话框 |
| 2dmm 独立项目 | MindMap2D.gd | XMind拖拽、布局、吸附/拖出 |
| 2dtr 独立项目 | CognitiveMap2D.gd, ForceLayout2D.gd, ProblemPanel.gd | 力导向布局、题目CRUD、连线、分组合并 |

### 第3步：统一接口

确保3个视图模块有一致的对外接口：

```gdscript
# 每个视图必须实现的接口
func rebuild() -> void                          # 重新渲染
func focus_on_node(index: int) -> void          # 聚焦节点
func get_selected_index() -> int                 # 获取选中节点
func handle_refresh() -> void                    # 刷新数据
```

### 第4步：创建SubjectEditor

1. 新建 SubjectEditor.gd，实现3.2节的 _ready() 流程
2. 构建3个页面容器
3. 将3个视图模块的代码复制到 `script/2dmm/`、`script/3dmm/`、`script/2dtr/` 子目录
4. 连接信号路由

### 第5步：集成测试

1. 测试Tab切换：3个视图正确显示/隐藏
2. 测试数据同步：思维导图修改后，认知地图正确更新
3. 测试关系编辑：认知地图添加关系后，保存正确
4. 测试撤销/重做：跨视图撤销正确
5. 测试详情弹窗：3个视图双击都能弹出详情

### 第6步：优化完善

1. 统一视觉风格
2. 添加过渡动画
3. 性能优化（大数据量时）
4. 快捷键全局统一

## 八、关键注意事项

### 8.1 3D视图独占

3D思维导图独占 SubViewport，切换到2D视图时隐藏3D视图容器。

### 8.2 2D视图延迟构建

2D视图在不可见时构建可能导致尺寸为0的问题。解决方案：
- 切换到2D视图时调用 `rebuild()`
- 或使用 `call_deferred()` 延迟构建

### 8.3 数据管理器安全

- DataManager 和 CognitiveMapDataManager 各自独立保存，互不干扰
- CognitiveMapDataManager 读取 mindmap_nodes.json 为只读，不修改

### 8.4 HistoryManager共享

3个视图共享一个 HistoryManager，撤销/重做跨视图生效：
- 在思维导图中新建节点 → 切换到认知地图 → Ctrl+Z → 节点被撤销
- 需要在撤销后 rebuild 当前视图

## 九、project.godot 配置

```ini
[application]
config/name="考研知识图谱"
run/main_scene="res://SubjectSelector.tscn"
config/features=PackedStringArray("4.6", "Forward Plus")

[autoload]
Global="*res://Global.gd"

[rendering]
rendering_device/driver.windows="d3d12"
```