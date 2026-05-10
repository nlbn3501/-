## 键盘快捷键管理器，注册和处理思维导图操作的快捷键绑定
extends RefCounted

var data_manager: RefCounted
var mindmap_2d: RefCounted
var shortcuts: Dictionary = {}

signal shortcut_executed(action: String)

## 初始化快捷键管理器，绑定数据管理器和思维导图，并注册默认快捷键
func _init(dm: RefCounted, mm_2d: RefCounted) -> void:
	data_manager = dm
	mindmap_2d = mm_2d
	_initialize_shortcuts()

## 注册所有默认快捷键映射
func _initialize_shortcuts() -> void:
	shortcuts["undo"] = {"key": KEY_Z, "ctrl": true, "shift": false, "description": "撤销 (Ctrl+Z)"}
	shortcuts["redo"] = {"key": KEY_Y, "ctrl": true, "shift": false, "description": "重做 (Ctrl+Y)"}
	shortcuts["redo_alt"] = {"key": KEY_Z, "ctrl": true, "shift": true, "description": "重做 (Ctrl+Shift+Z)"}
	shortcuts["new_node"] = {"key": KEY_N, "ctrl": true, "shift": false, "description": "新建节点 (Ctrl+N)"}
	shortcuts["new_child"] = {"key": KEY_TAB, "ctrl": false, "shift": false, "description": "新建子节点 (Tab)"}
	shortcuts["delete"] = {"key": KEY_DELETE, "ctrl": false, "shift": false, "description": "删除选中 (Delete)"}
	shortcuts["edit"] = {"key": KEY_F2, "ctrl": false, "shift": false, "description": "编辑节点 (F2)"}
	shortcuts["refresh"] = {"key": KEY_R, "ctrl": false, "shift": false, "description": "刷新视图 (R)"}
	shortcuts["deselect"] = {"key": KEY_ESCAPE, "ctrl": false, "shift": false, "description": "取消选择 (Esc)"}
	shortcuts["focus_root"] = {"key": KEY_SPACE, "ctrl": false, "shift": false, "description": "聚焦根节点 (Space)"}
	shortcuts["save"] = {"key": KEY_S, "ctrl": true, "shift": false, "description": "保存数据 (Ctrl+S)"}
	shortcuts["load"] = {"key": KEY_L, "ctrl": true, "shift": false, "description": "加载数据 (Ctrl+L)"}
	shortcuts["optimize_layout"] = {"key": KEY_O, "ctrl": true, "shift": false, "description": "优化布局 (Ctrl+O)"}

## 注册一个自定义快捷键
func register_shortcut(action: String, key: int, ctrl: bool = false, shift: bool = false, description: String = "") -> void:
	if description.is_empty():
		description = action
	shortcuts[action] = {"key": key, "ctrl": ctrl, "shift": shift, "description": description}

## 移除一个已注册的快捷键
func unregister_shortcut(action: String) -> void:
	shortcuts.erase(action)

## 处理输入事件，匹配快捷键并发射对应信号，返回是否匹配成功
func handle_input(event: InputEvent) -> bool:
	if not event is InputEventKey:
		return false
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed:
		return false
	
	for action in shortcuts.keys():
		var shortcut: Dictionary = shortcuts[action]
		if key_event.keycode == shortcut["key"] and \
			key_event.ctrl_pressed == shortcut["ctrl"] and \
			key_event.shift_pressed == shortcut["shift"]:
			shortcut_executed.emit(action)
			return true
	
	return false

## 获取指定操作的快捷键描述
func get_shortcut_description(action: String) -> String:
	if shortcuts.has(action):
		return shortcuts[action].get("description", action)
	return action

## 获取所有快捷键的副本
func get_all_shortcuts() -> Dictionary:
	return shortcuts.duplicate()

## 获取所有快捷键的文本列表
func get_shortcuts_list() -> String:
	var lines: Array = []
	for action in shortcuts.keys():
		var shortcut: Dictionary = shortcuts[action]
		lines.append("%s: %s" % [shortcut.get("description", action), action])
	return "\n".join(lines)
