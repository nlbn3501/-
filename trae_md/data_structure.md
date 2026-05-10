# 考研知识图谱 - 共享数据结构定义

## 一、数据目录结构

```
考研知识图谱/
└── data/
    ├── mindmap_nodes.json      # 思维导图节点（知识点树）
    └── cognitive_map/          # 认知地图独立数据
        ├── problems.json       # 所有题目
        ├── relations.json      # 所有关系（题目↔知识点）
        └── layout.json         # 画布布局状态
```

思维导图和认知地图的数据**完全分离**，认知地图通过 `relations.json` 中的 `target` 字段（知识点名称字符串）引用思维导图的节点。

---

## 二、思维导图数据结构（mindmap_nodes.json）

### 2.1 学科文件格式

每个学科对应 `data/` 目录下的一个 `.json` 文件。

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
            "parent": "",
            "galaxy_id": 0,
            "pos2d": [2000.0, 1500.0]
        }
    ]
}
```

### 2.2 节点字段定义

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | String | 是 | 唯一标识符，自动生成 |
| `name` | String | 是 | 知识点名称，唯一 |
| `description` | String | 否 | 详细描述 |
| `mastery` | int | 是 | 掌握程度：0=未学习, 1=学习中, 2=已掌握 |
| `position` | Array[float] | 是 | 3D坐标 [x, y, z]，3D视图使用 |
| `parent` | String | 否 | 父节点名称（空字符串表示根节点/自由节点） |
| `galaxy_id` | int | 是 | 所属星系ID：0=根星系，>=1为自由星系 |
| `pos2d` | Array[float] | 否 | 2D坐标 [x, y]，2D视图使用 |

> **注意**：`relations` 字段已从思维导图节点中移除，所有关系数据统一存储在认知地图的 `relations.json` 中。

### 2.3 Galaxy 星系规则

| 规则 | 说明 |
|------|------|
| `galaxy_id = 0` | 根星系，以原点(0,0,0)为中心的同心球面布局 |
| `galaxy_id >= 1` | 自由星系，以该星系根节点为中心的独立同心球面布局 |
| 新建节点 | 继承父节点的 `galaxy_id`；无父节点时创建新 `galaxy_id` |
| 吸附合并 | 节点被吸附到其他节点下时，其子树所有节点的 `galaxy_id` 更新为父节点所在的 `galaxy_id` |
| 拖出 | 节点从星系中拖出时，其子树所有节点获得新的唯一 `galaxy_id` |
| 销毁 | 自由星系内所有节点被删除后，该 `galaxy_id` 回收 |

### 2.4 depth 计算规则

`galaxy_id` 不影响 `compute_depths()` 算法——depth 永远是「相对该星系根节点的祖先链长度」：

| 节点 | galaxy_id | parent | depth | 说明 |
|------|-----------|--------|-------|------|
| root | 0 | "" | 0 | 根星系根节点 |
| 极限 | 0 | "root" | 1 | 根星系子节点 |
| 自由节点B | 1 | "" | 0 | 自由星系根节点 |
| B1 | 1 | "自由节点B" | 1 | 自由星系子节点 |

---

## 三、认知地图数据结构（cognitive_map/ 目录）

### 3.1 problems.json — 题目数据

**格式**：扁平数组，每道题一条记录。

```json
[
    {
        "id": "prob_001",
        "title": "求极限 sinx/x",
        "type": "计算题",
        "difficulty": 3,
        "source": "2024真题",
        "images": [
            "res://data/cognitive_map/images/prob_001_q.png",
            "res://data/cognitive_map/images/prob_001_s.png"
        ],
        "note": "核心是配凑成 sinx/x = 1 的形式"
    }
]
```

**字段定义**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | String | 是 | 唯一标识符，格式 `prob_{三位数}` 自动递增 |
| `title` | String | 是 | 题目标题，用于搜索和显示 |
| `type` | String | 是 | 题型分类：计算题 / 证明题 / 选择题 / 填空题 / 其他 |
| `difficulty` | int | 是 | 难度 1~5 星 |
| `source` | String | 否 | 来源，如"2024真题"、"张宇18讲"等 |
| `images` | Array[String] | 否 | 图片路径列表，纵向排列，一张一行 |
| `note` | String | 否 | 用户自定义注释 |

### 3.2 relations.json — 关系数据

**格式**：扁平数组，每条关系独立存储。

```json
[
    {
        "id": "rel_001",
        "problem_id": "prob_001",
        "target": "极限定义",
        "type": "用到",
        "label": "核心方法"
    }
]
```

**字段定义**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | String | 是 | 唯一标识符，格式 `rel_{三位数}` 自动递增 |
| `problem_id` | String | 是 | 关联的题目ID，引用 problems.json 中的 id |
| `target` | String | 是 | 知识点名称，引用 mindmap_nodes.json 中的 name |
| `type` | String | 是 | 关系类型（详见关系系统文档） |
| `label` | String | 否 | 自定义备注 |

**关系类型定义**（详见 `2dtr/relationship_system.md`）：

| 类型值 | 中文名 | 方向 | 说明 |
|--------|--------|------|------|
| `用到` | 用到 | 题目→知识点 | 这道题用到了该知识点（最常用） |
| `可替换` | 可替换 | 题目→知识点 | 该知识点可替换原方案 |
| `前置` | 前置知识 | 题目→知识点 | 解题前需要掌握的前置知识 |
| `延伸` | 延伸 | 题目→知识点 | 该题可延伸到的相关知识点 |
| `自定义` | 自定义 | 题目→知识点 | 用户自定义关系类型 |

### 3.3 layout.json — 画布布局状态

**格式**：一个 JSON 对象。

```json
{
    "zoom_level": 1.0,
    "scroll": {
        "h": 2000,
        "v": 1500
    },
    "node_positions": {
        "极限定义": {
            "pos": [1800.0, 1400.0],
            "pinned": true
        },
        "prob_001": {
            "pos": [2100.0, 1600.0],
            "pinned": false
        }
    },
    "expanded_groups": {
        "prob_001": false
    }
}
```

**字段定义**：

| 字段 | 类型 | 说明 |
|------|------|------|
| `zoom_level` | float | 当前缩放级别 |
| `scroll` | Object | 滚动位置 {h, v} |
| `node_positions` | Object | 所有手动调过位置的节点坐标，键为节点名称（知识点）或题目ID |
| `node_positions[].pos` | Array[float] | 2D坐标 [x, y] |
| `node_positions[].pinned` | bool | 是否固定（固定后不再参与力导向计算） |
| `expanded_groups` | Object | 合并的类题组是否展开状态，键为组内第一个题目ID |

> **说明**：
> - 只有被用户拖动过（pinned）的节点才记录位置。未被固定的节点每次打开由力导向重新布局。
> - 组节点的位置和 pinned 状态记录在 `node_positions` 中，键为组内第一个题目的 ID（与力导向中的代表键一致）。
> - `expanded_groups` 的键也是组内第一个题目的 ID，值为 `true`/`false` 表示展开/折叠。

---

## 四、数据读写规则

### 4.1 DataManager — 思维导图数据管理

共享的 DataManager 负责 `mindmap_nodes.json` 的读写，所有视图共用：

```
DataManager (单例)
    ├── load_data()                             ← 从JSON文件加载
    ├── save_data()                             ← 保存到JSON文件
    ├── get_item(index)                         ← 获取节点
    ├── add_item(item)                          ← 添加节点
    ├── remove_item(index)                      ← 删除节点
    ├── set_item(index, item)                   ← 更新节点
    ├── get_count()                             ← 节点数量
    ├── compute_depths()                        ← 计算深度
    ├── collect_edges()                         ← 收集父子边
    ├── find_index_by_name(name)                ← 通过名称查找节点索引
    ├── get_galaxy_nodes(galaxy_id)             ← 获取指定星系的所有节点索引
    ├── get_all_galaxy_ids()                    ← 获取所有星系ID列表
    ├── move_subtree_to_new_galaxy(root_index, new_galaxy_id)
    └── absorb_subtree(target_parent_index, subtree_root_index)
```

### 4.2 CognitiveMapDataManager — 认知地图数据管理

认知地图使用独立的 `CognitiveMapDataManager` 管理 `cognitive_map/` 目录下的数据：

```
CognitiveMapDataManager (独立于 DataManager，但读取 mindmap_nodes.json 做引用校验)
    ├── load_all()                              ← 一次读取 problems.json + relations.json + layout.json
    ├── save_all()                              ← 一次保存所有认知地图数据
    │
    ├── get_all_problems()                      ← 获取所有题目
    ├── get_problem(problem_id)                 ← 获取单道题
    ├── add_problem(problem_data)               ← 新增题目
    ├── update_problem(problem_id, data)        ← 更新题目
    ├── remove_problem(problem_id)              ← 删除题目（同时清理关联关系）
    │
    ├── get_relations_of_problem(problem_id)    ← 获取某题的所有关系
    ├── get_problems_by_target(target_name)     ← 获取引用了某知识点的所有题目
    ├── add_relation(relation_data)             ← 新增关系
    ├── remove_relation(relation_id)            ← 删除关系
    ├── cleanup_relations_for_knowledge(name)   ← 思维导图删节点时清理引用
    ├── rename_knowledge_target(old_name, new_name) ← 思维导图改名时更新引用
    │
    ├── get_layout()                            ← 获取画布布局
    ├── save_layout(layout_data)                ← 保存画布布局
    │
    └── refresh()                               ← 切换到认知地图时调用：重新读取 mindmap_nodes.json
```

### 4.3 视图间数据同步

| 操作 | 触发视图 | 同步行为 |
|------|----------|----------|
| 新建/编辑/删除知识点 | 思维导图 | DataManager.save_data() |
| 知识点改名 | 思维导图 | 保存后，切换到认知地图时自动刷新，更新关系中的 target 引用 |
| 删除知识点 | 思维导图 | 保存后，切换到认知地图时自动刷新，清理引用该知识点的所有关系 |
| 新增/修改/删除题目 | 认知地图 | CognitiveMapDataManager.save_all() |
| 新增/修改/删除关系 | 认知地图 | CognitiveMapDataManager.save_all() |
| 拖动节点固定位置 | 认知地图 | CognitiveMapDataManager.save_layout() |
| 切换到认知地图 | Tab切换 | 自动调用 CognitiveMapDataManager.refresh() → 重新读取 mindmap_nodes.json |

**核心原则**：任何修改操作后立即保存，切换视图时目标视图从文件重新加载。

### 4.4 refresh() 时序

`CognitiveMapDataManager.refresh()` 的执行顺序：

```
refresh():
  1. _load_mindmap_nodes()     ← 重新读取最新的 mindmap_nodes.json
  2. _validate_relations()     ← 基于最新 mindmap 节点列表，清理无效的 relations 引用
  3. load_all()                ← 重新加载 problems.json + relations.json + layout.json
```

> **安全保证**：思维导图在切换 Tab 时会先执行 `DataManager.save_data()`，确保 mindmap_nodes.json 是最新状态。因此 `_validate_relations()` 不会误删有效关系。

---

## 五、用户偏好配置

存储路径：`user://preferences.cfg`

```ini
[general]
workspace_dir="C:/Users/xxx/workspace"
recent_subjects=["高数", "线代", "概率论"]

[display]
locale="zh_CN"
```

---

## 六、编码规范

### 命名约定

| 类型 | 规范 | 示例 |
|------|------|------|
| 私有成员变量 | 下划线前缀 | `_data_manager`, `_cognitive_map_data` |
| 私有方法 | 下划线前缀 | `_refresh_display()`, `_on_xxx_pressed()` |
| 公开方法 | 无前缀 | `get_workspace_dir()`, `rebuild_all()` |
| 信号回调 | `_on_节点名_事件()` | `_on_btn_new_pressed()` |
| 信号名称 | 蛇形命名 | `point_clicked`, `nodes_changed` |

### 文件组织

| 位置 | 内容 |
|------|------|
| 项目根目录 | 场景脚本（Global.gd, SubjectEditor.gd等） |
| `script/2dmm/` | 2D思维导图模块（MindMap2D.gd, DataManager.gd, HistoryManager.gd等） |
| `script/3dmm/` | 3D思维导图模块（KnowledgeMap.gd, PointManager.gd, LayoutManager.gd等） |
| `script/2dtr/` | 2D认知地图模块（CognitiveMap2D.gd, CognitiveMapDataManager.gd等） |
| `script/shared/` | 共享模块（DataManager3DAdapter.gd） |
| `scenes/` | 子场景文件 |

### 类型转换注意

- JSON中 `position` 是 `Array[float]`，使用时需转换为 `Vector3`
- JSON中 `pos2d` 是 `Array[float]`，使用时需转换为 `Vector2`
- JSON中 `galaxy_id` 是 int 类型，直接使用