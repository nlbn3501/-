## 全局自动加载单例，管理工作区路径、最近打开科目、语言偏好和截图目录等应用级配置
extends Node

const PREFS_PATH = "user://preferences.cfg"
const MAX_RECENT = 3

var _workspace_dir: String = ""
var _recent_subjects: Array[String] = []
var _locale: String = "zh_CN"
var _screenshot_dir: String = ""


## 节点就绪时自动加载持久化的偏好设置
func _ready() -> void:
	_load_preferences()


## 从配置文件加载工作区路径、最近科目、语言和截图目录等偏好设置
func _load_preferences() -> void:
	var config := ConfigFile.new()
	var err := config.load(PREFS_PATH)
	if err != OK:
		push_warning("Global: cannot load preferences")
		return
	_workspace_dir = config.get_value("general", "workspace_dir", "")
	_recent_subjects = config.get_value("general", "recent_subjects", [])
	_locale = config.get_value("general", "locale", "zh_CN")
	_screenshot_dir = config.get_value("general", "screenshot_dir", "")


## 将当前偏好设置持久化保存到配置文件
func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "workspace_dir", _workspace_dir)
	config.set_value("general", "recent_subjects", _recent_subjects)
	config.set_value("general", "locale", _locale)
	config.set_value("general", "screenshot_dir", _screenshot_dir)
	var err := config.save(PREFS_PATH)
	if err != OK:
		push_error("Global: cannot save preferences, error: %d" % err)


## 获取当前工作区目录路径
func get_workspace_dir() -> String:
	return _workspace_dir


## 设置工作区目录路径并持久化保存
func set_workspace_dir(path: String) -> void:
	_workspace_dir = path
	_save_preferences()


## 扫描工作区目录，返回所有科目JSON文件名的有序列表
func get_subject_list() -> PackedStringArray:
	if _workspace_dir.is_empty():
		return PackedStringArray()
	var result: PackedStringArray = []
	var dir := DirAccess.open(_workspace_dir)
	if dir == null:
		push_error("Global: cannot open workspace: %s" % _workspace_dir)
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if !dir.current_is_dir() && file_name.ends_with(".json") && !file_name.ends_with("_cog.json") && file_name != "problems.json" && file_name != "relations.json":
			result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


## 在工作区中创建新科目文件，返回操作结果错误码
func create_subject(subject_name: String) -> int:
	if _workspace_dir.is_empty():
		push_error("Global: workspace not set")
		return ERR_INVALID_PARAMETER
	var safe_name := subject_name.validate_filename() + ".json"
	var full_path := _workspace_dir.path_join(safe_name)
	if FileAccess.file_exists(full_path):
		push_error("Global: subject already exists: %s" % safe_name)
		return ERR_ALREADY_EXISTS
	var file := FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		push_error("Global: cannot create subject file: %s" % safe_name)
		return ERR_FILE_CANT_WRITE
	var data := {"name": subject_name, "nodes": []}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_add_recent(subject_name)
	return OK


## 从外部路径导入科目文件到工作区，返回操作结果错误码
func import_subject(src_path: String) -> int:
	if _workspace_dir.is_empty():
		push_error("Global: workspace not set")
		return ERR_INVALID_PARAMETER
	if !FileAccess.file_exists(src_path):
		push_error("Global: source file not found: %s" % src_path)
		return ERR_FILE_NOT_FOUND
	var file_name := src_path.get_file()
	var dest_path := _workspace_dir.path_join(file_name)
	if FileAccess.file_exists(dest_path):
		push_error("Global: target file exists: %s" % file_name)
		return ERR_ALREADY_EXISTS
	var err := DirAccess.copy_absolute(src_path, dest_path)
	if err != OK:
		push_error("Global: import failed, error: %d" % err)
		return err
	_add_recent(file_name.get_basename())
	return OK


## 将指定科目文件导出到目标路径，返回操作结果错误码
func export_subject(subject_name: String, dest_path: String) -> int:
	if _workspace_dir.is_empty():
		push_error("Global: workspace not set")
		return ERR_INVALID_PARAMETER
	var src_file := subject_name + ".json"
	var src_path := _workspace_dir.path_join(src_file)
	if !FileAccess.file_exists(src_path):
		push_error("Global: subject file not found: %s" % src_file)
		return ERR_FILE_NOT_FOUND
	var err := DirAccess.copy_absolute(src_path, dest_path)
	if err != OK:
		push_error("Global: export failed, error: %d" % err)
		return err
	return OK


## 获取最近打开的科目列表副本
func get_recent_subjects() -> Array[String]:
	return _recent_subjects.duplicate()


## 将指定科目添加到最近打开列表
func add_recent_subject(subject_name: String) -> void:
	_add_recent(subject_name)


## 内部方法：将科目名插入最近列表头部，超限时裁剪并保存
func _add_recent(subject_name: String) -> void:
	_recent_subjects.erase(subject_name)
	_recent_subjects.insert(0, subject_name)
	if _recent_subjects.size() > MAX_RECENT:
		_recent_subjects.resize(MAX_RECENT)
	_save_preferences()


## 获取当前界面语言设置
func get_locale() -> String:
	return _locale


## 设置界面语言并立即应用到翻译服务器
func set_locale(locale: String) -> void:
	_locale = locale
	_save_preferences()
	TranslationServer.set_locale(_locale)


## 获取截图保存目录，未设置时回退到工作区目录
func get_screenshot_dir() -> String:
	if _screenshot_dir.is_empty():
		return _workspace_dir
	return _screenshot_dir


## 设置截图保存目录并持久化保存
func set_screenshot_dir(path: String) -> void:
	_screenshot_dir = path
	_save_preferences()
