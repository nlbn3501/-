## 科目选择器主界面，提供工作区切换、科目列表浏览、新建/导入/导出/打开科目等功能
extends Control

@onready var _lbl_workspace: Label = $VBox/TopBar/LblWorkspace
@onready var _btn_switch_dir: Button = $VBox/TopBar/BtnSwitchDir
@onready var _btn_settings: Button = $VBox/TopBar/BtnSettings
@onready var _item_list: ItemList = $VBox/MainArea/ItemList
@onready var _btn_new: Button = $VBox/MainArea/BtnPanel/VBox/BtnNew
@onready var _btn_import: Button = $VBox/MainArea/BtnPanel/VBox/BtnImport
@onready var _btn_export: Button = $VBox/MainArea/BtnPanel/VBox/BtnExport
@onready var _btn_open: Button = $VBox/MainArea/BtnPanel/VBox/BtnOpen
@onready var _recent_list: ItemList = $VBox/BottomBar/RecentList

var _new_subject_dialog: ConfirmationDialog = null
var _new_subject_input: LineEdit = null
var _export_target_name: String = ""


## 节点就绪时连接按钮信号并刷新界面显示
func _ready() -> void:
	_btn_switch_dir.pressed.connect(_on_switch_dir_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_new.pressed.connect(_on_new_pressed)
	_btn_import.pressed.connect(_on_import_pressed)
	_btn_export.pressed.connect(_on_export_pressed)
	_btn_open.pressed.connect(_on_open_pressed)
	_item_list.item_activated.connect(_on_item_activated)
	_refresh_display()


## 刷新工作区路径、科目列表和最近打开列表的显示
func _refresh_display() -> void:
	var ws := Global.get_workspace_dir()
	if ws.is_empty():
		_lbl_workspace.text = "(workspace not set)"
	else:
		_lbl_workspace.text = ws
	_item_list.clear()
	var subjects := Global.get_subject_list()
	for fname in subjects:
		var display_name := fname.get_basename()
		_item_list.add_item(display_name)
	_recent_list.clear()
	for recent in Global.get_recent_subjects():
		_recent_list.add_item(recent)


## 检查工作区是否已设置，未设置时返回false并输出警告
func _check_workspace() -> bool:
	if Global.get_workspace_dir().is_empty():
		push_warning("please set workspace first")
		return false
	return true


## 获取当前在科目列表中选中的科目名称
func _get_selected_name() -> String:
	var selected := _item_list.get_selected_items()
	if selected.is_empty():
		return ""
	return _item_list.get_item_text(selected[0])


## 点击设置按钮时，加载设置页面并隐藏当前界面
func _on_settings_pressed() -> void:
	var settings_script := load("res://SettingsPage.gd") as GDScript
	var settings := Control.new()
	settings.set_script(settings_script)
	get_tree().root.add_child(settings)
	hide()
	settings.tree_exited.connect(_on_editor_closed)


## 点击切换目录按钮时，弹出文件夹选择对话框
func _on_switch_dir_pressed() -> void:
	DisplayServer.file_dialog_show(
		"Select Workspace",
		Global.get_workspace_dir(),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
		PackedStringArray([]),
		_on_dir_selected
	)


## 文件夹选择对话框回调，确认后设置工作区并刷新显示
func _on_dir_selected(ok: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if ok and !paths.is_empty():
		Global.set_workspace_dir(paths[0])
		_refresh_display()


## 点击新建按钮时，弹出新建科目对话框
func _on_new_pressed() -> void:
	if !_check_workspace():
		return
	_new_subject_dialog = ConfirmationDialog.new()
	_new_subject_dialog.title = "New Subject"
	_new_subject_input = LineEdit.new()
	_new_subject_input.placeholder_text = "Enter subject name"
	_new_subject_dialog.add_child(_new_subject_input)
	add_child(_new_subject_dialog)
	_new_subject_dialog.confirmed.connect(_on_new_confirmed)
	_new_subject_dialog.canceled.connect(_on_new_canceled)
	_new_subject_dialog.popup_centered(Vector2i(400, 150))
	_new_subject_input.grab_focus()
	_new_subject_input.text_submitted.connect(_on_new_text_submitted)


## 新建科目对话框确认回调，创建科目并刷新列表
func _on_new_confirmed() -> void:
	var name := _new_subject_input.text.strip_edges()
	if name.is_empty():
		return
	var err := Global.create_subject(name)
	if err == OK:
		_refresh_display()
	else:
		push_error("create subject failed, error: %d" % err)
	_cleanup_new_dialog()


## 新建科目对话框取消回调，清理对话框
func _on_new_canceled() -> void:
	_cleanup_new_dialog()


## 新建科目输入框回车提交时，触发确认操作
func _on_new_text_submitted(_text: String) -> void:
	_new_subject_dialog.confirmed.emit()


## 清理新建科目对话框及相关引用
func _cleanup_new_dialog() -> void:
	if is_instance_valid(_new_subject_dialog):
		_new_subject_dialog.queue_free()
	_new_subject_dialog = null
	_new_subject_input = null


## 点击导入按钮时，弹出文件选择对话框选择JSON文件
func _on_import_pressed() -> void:
	if !_check_workspace():
		return
	DisplayServer.file_dialog_show(
		"Import Subject",
		Global.get_workspace_dir(),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.json"]),
		_on_import_selected
	)


## 导入文件选择对话框回调，确认后执行导入并刷新列表
func _on_import_selected(ok: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if ok and !paths.is_empty():
		var err := Global.import_subject(paths[0])
		if err == OK:
			_refresh_display()
		else:
			push_error("import failed, error: %d" % err)


## 点击导出按钮时，弹出保存文件对话框导出选中的科目
func _on_export_pressed() -> void:
	if !_check_workspace():
		return
	var name := _get_selected_name()
	if name.is_empty():
		push_warning("please select a subject first")
		return
	_export_target_name = name
	DisplayServer.file_dialog_show(
		"Export Subject",
		Global.get_workspace_dir(),
		_export_target_name + ".json",
		false,
		DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
		PackedStringArray(["*.json"]),
		_on_export_selected
	)


## 导出文件选择对话框回调，确认后执行导出操作
func _on_export_selected(ok: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if ok and !paths.is_empty():
		var err := Global.export_subject(_export_target_name, paths[0])
		if err != OK:
			push_error("export failed, error: %d" % err)


## 点击打开按钮时，打开选中的科目编辑器
func _on_open_pressed() -> void:
	var name := _get_selected_name()
	if name.is_empty():
		push_warning("please select a subject first")
		return
	_open_editor(name)


## 双击科目列表项时，打开对应科目的编辑器
func _on_item_activated(index: int) -> void:
	_open_editor(_item_list.get_item_text(index))


## 打开科目编辑器，记录最近打开并隐藏选择器界面
func _open_editor(subject_name: String) -> void:
	Global.add_recent_subject(subject_name)
	var editor_script := load("res://SubjectEditor.gd") as GDScript
	var editor := Control.new()
	editor.set_script(editor_script)
	editor.subject_name = subject_name
	get_tree().root.add_child(editor)
	hide()
	editor.tree_exited.connect(_on_editor_closed)


## 编辑器关闭回调，重新显示选择器并刷新列表
func _on_editor_closed() -> void:
	show()
	_refresh_display()
