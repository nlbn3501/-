## 认知视图操作历史管理器，支持撤销/重做功能，通过快照方式记录数据状态
extends RefCounted

var data_manager: RefCounted
var history_stack: Array = []
var redo_stack: Array = []
var max_history_size: int = 50

signal history_changed(can_undo: bool, can_redo: bool)

## 初始化历史管理器，绑定数据管理器
func _init(dm: RefCounted) -> void:
	data_manager = dm

## 记录一次操作，保存当前数据快照到历史栈
func record_operation(description: String) -> void:
	var snapshot: Array = data_manager.call("get_items_snapshot")
	history_stack.append({
		"description": description,
		"snapshot": snapshot,
	})
	redo_stack.clear()
	if history_stack.size() > max_history_size:
		history_stack.pop_front()
	history_changed.emit(can_undo(), can_redo())

## 撤销上一次操作，恢复到上一个快照状态
func undo() -> void:
	if history_stack.is_empty():
		return
	var command: Dictionary = history_stack.pop_back()
	var current_snapshot: Array = data_manager.call("get_items_snapshot")
	redo_stack.append({
		"description": command["description"],
		"snapshot": current_snapshot,
	})
	data_manager.call("restore_items_snapshot", command["snapshot"])
	history_changed.emit(can_undo(), can_redo())

## 重做上一次撤销的操作
func redo() -> void:
	if redo_stack.is_empty():
		return
	var command: Dictionary = redo_stack.pop_back()
	var current_snapshot: Array = data_manager.call("get_items_snapshot")
	history_stack.append({
		"description": command["description"],
		"snapshot": current_snapshot,
	})
	data_manager.call("restore_items_snapshot", command["snapshot"])
	history_changed.emit(can_undo(), can_redo())

## 是否可以撤销
func can_undo() -> bool:
	return not history_stack.is_empty()

## 是否可以重做
func can_redo() -> bool:
	return not redo_stack.is_empty()

## 清空所有历史记录
func clear_history() -> void:
	history_stack.clear()
	redo_stack.clear()
	history_changed.emit(false, false)

## 获取最近一次可撤销操作的描述
func get_undo_description() -> String:
	if history_stack.is_empty():
		return ""
	return history_stack.back().get("description", "")

## 获取最近一次可重做操作的描述
func get_redo_description() -> String:
	if redo_stack.is_empty():
		return ""
	return redo_stack.back().get("description", "")
