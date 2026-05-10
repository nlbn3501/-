import os

path = os.path.join(r"C:\Users\spg\Desktop\mms_structure\project-260409", "Global.gd")

content = """\
extends Node

const PREFS_PATH = "user://preferences.cfg"
const MAX_RECENT = 3

var _workspace_dir: String = ""
var _recent_subjects: Array[String] = []


func _ready() -> void:
\t_load_preferences()


func _load_preferences() -> void:
\tvar config := ConfigFile.new()
\tvar err := config.load(PREFS_PATH)
\tif err != OK:
\t\tpush_warning("Global: \u65e0\u6cd5\u52a0\u8f7d\u504f\u597d\u8bbe\u7f6e\uff0c\u5c06\u4f7f\u7528\u9ed8\u8ba4\u503c")
\t\treturn
\t_workspace_dir = config.get_value("general", "workspace_dir", "")
\t_recent_subjects = config.get_value("general", "recent_subjects", [])


func _save_preferences() -> void:
\tvar config := ConfigFile.new()
\tconfig.set_value("general", "workspace_dir", _workspace_dir)
\tconfig.set_value("general", "recent_subjects", _recent_subjects)
\tvar err := config.save(PREFS_PATH)
\tif err != OK:
\t\tpush_error("Global: \u65e0\u6cd5\u4fdd\u5b58\u504f\u597d\u8bbe\u7f6e\uff0c\u9519\u8bef\u7801: %d" % err)


func get_workspace_dir() -> String:
\treturn _workspace_dir


func set_workspace_dir(path: String) -> void:
\t_workspace_dir = path
\t_save_preferences()


func get_subject_list() -> PackedStringArray:
\tif _workspace_dir.is_empty():
\t\treturn PackedStringArray()
\tvar result: PackedStringArray = []
\tvar dir := DirAccess.open(_workspace_dir)
\tif dir == null:
\t\tpush_error("Global: \u65e0\u6cd5\u6253\u5f00\u5de5\u4f5c\u76ee\u5f55: %s" % _workspace_dir)
\t\treturn result
\tdir.list_dir_begin()
\tvar file_name := dir.get_next()
\twhile file_name != "":
\t\tif !dir.current_is_dir() and file_name.ends_with(".json"):
\t\t\tresult.append(file_name)
\t\tfile_name = dir.get_next()
\tdir.list_dir_end()
\tresult.sort()
\treturn result


func create_subject(subject_name: String) -> int:
\tif _workspace_dir.is_empty():
\t\tpush_error("Global: \u672a\u8bbe\u7f6e\u5de5\u4f5c\u76ee\u5f55")
\t\treturn ERR_INVALID_PARAMETER
\tvar safe_name := subject_name.validate_filename() + ".json"
\tvar full_path := _workspace_dir.path_join(safe_name)
\tif FileAccess.file_exists(full_path):
\t\tpush_error("Global: \u5b66\u79d1\u6587\u4ef6\u5df2\u5b58\u5728: %s" % safe_name)
\t\treturn ERR_ALREADY_EXISTS
\tvar file := FileAccess.open(full_path, FileAccess.WRITE)
\tif file == null:
\t\tpush_error("Global: \u65e0\u6cd5\u521b\u5efa\u5b66\u79d1\u6587\u4ef6: %s" % safe_name)
\t\treturn ERR_FILE_CANT_WRITE
\tvar data := {"name": subject_name, "nodes": []}
\tfile.store_string(JSON.stringify(data, "\\t"))
\tfile.close()
\t_add_recent(subject_name)
\treturn OK


func import_subject(src_path: String) -> int:
\tif _workspace_dir.is_empty():
\t\tpush_error("Global: \u672a\u8bbe\u7f6e\u5de5\u4f5c\u76ee\u5f55")
\t\treturn ERR_INVALID_PARAMETER
\tif !FileAccess.file_exists(src_path):
\t\tpush_error("Global: \u6e90\u6587\u4ef6\u4e0d\u5b58\u5728: %s" % src_path)
\t\treturn ERR_FILE_NOT_FOUND
\tvar file_name := src_path.get_file()
\tvar dest_path := _workspace_dir.path_join(file_name)
\tif FileAccess.file_exists(dest_path):
\t\tpush_error("Global: \u76ee\u6807\u6587\u4ef6\u5df2\u5b58\u5728: %s" % file_name)
\t\treturn ERR_ALREADY_EXISTS
\tvar err := DirAccess.copy_absolute(src_path, dest_path)
\tif err != OK:
\t\tpush_error("Global: \u5bfc\u5165\u5931\u8d25\uff0c\u9519\u8bef\u7801: %d" % err)
\t\treturn err
\t_add_recent(file_name.get_basename())
\treturn OK


func export_subject(subject_name: String, dest_path: String) -> int:
\tif _workspace_dir.is_empty():
\t\tpush_error("Global: \u672a\u8bbe\u7f6e\u5de5\u4f5c\u76ee\u5f55")
\t\treturn ERR_INVALID_PARAMETER
\tvar src_file := subject_name + ".json"
\tvar src_path := _workspace_dir.path_join(src_file)
\tif !FileAccess.file_exists(src_path):
\t\tpush_error("Global: \u5b66\u79d1\u6587\u4ef6\u4e0d\u5b58\u5728: %s" % src_file)
\t\treturn ERR_FILE_NOT_FOUND
\tvar err := DirAccess.copy_absolute(src_path, dest_path)
\tif err != OK:
\t\tpush_error("Global: \u5bfc\u51fa\u5931\u8d25\uff0c\u9519\u8bef\u7801: %d" % err)
\t\treturn err
\treturn OK


func get_recent_subjects() -> Array[String]:
\treturn _recent_subjects.duplicate()


func add_recent_subject(subject_name: String) -> void:
\t_add_recent(subject_name)


func _add_recent(subject_name: String) -> void:
\t_recent_subjects.erase(subject_name)
\t_recent_subjects.insert(0, subject_name)
\tif _recent_subjects.size() > MAX_RECENT:
\t\t_recent_subjects.resize(MAX_RECENT)
\t_save_preferences()
"""

with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(content)

# Verify: check that all indentation uses tabs
with open(path, "rb") as f:
    data = f.read()
lines = data.split(b"\n")
bad_lines = []
for i, line in enumerate(lines):
    stripped = line.lstrip()
    if not stripped:
        continue
    indent = line[:len(line) - len(stripped)]
    if b" " in indent:
        bad_lines.append(i + 1)

if bad_lines:
    print(f"WARNING: Lines with space indentation: {bad_lines}")
else:
    print("OK: All indentation uses tabs only")
