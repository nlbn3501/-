path = r"C:\Users\spg\Desktop\mms_structure\project-260409\Global.gd"

content = """extends Node

const PREFS_PATH = "user://preferences.cfg"
const MAX_RECENT = 3

var _workspace_dir: String = ""
var _recent_subjects: Array[String] = []


func _ready() -> void:
	_load_preferences()


func _load_preferences() -> void:
	var config := ConfigFile.new()
	var err := config.load(PREFS_PATH)
	if err != OK:
		push_warning("Global: cannot load preferences")
		return
	_workspace_dir = config.get_value("general", "workspace_dir", "")
	_recent_subjects = config.get_value("general", "recent_subjects", [])


func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("general", "workspace_dir", _workspace_dir)
	config.set_value("general", "recent_subjects", _recent_subjects)
	var err := config.save(PREFS_PATH)
	if err != OK:
		push_error("Global: cannot save preferences, error: %d" % err)


func get_workspace_dir() -> String:
	return _workspace_dir


func set_workspace_dir(path: String) -> void:
	_workspace_dir = path
	_save_preferences()


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
		if !dir.current_is_dir() && file_name.ends_with(".json"):
			result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result


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
	file.store_string(JSON.stringify(data, "\\t"))
	file.close()
	_add_recent(subject_name)
	return OK


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


func get_recent_subjects() -> Array[String]:
	return _recent_subjects.duplicate()


func add_recent_subject(subject_name: String) -> void:
	_add_recent(subject_name)


func _add_recent(subject_name: String) -> void:
	_recent_subjects.erase(subject_name)
	_recent_subjects.insert(0, subject_name)
	if _recent_subjects.size() > MAX_RECENT:
		_recent_subjects.resize(MAX_RECENT)
	_save_preferences()
"""

# Write as UTF-8 without BOM, LF line endings
with open(path, "wb") as f:
    f.write(content.encode("utf-8"))

# Verify
with open(path, "rb") as f:
    data = f.read()

# Check for any space characters in leading indentation
lines = data.split(b"\n")
errors = []
for i, line in enumerate(lines):
    stripped = line.lstrip()
    if not stripped:
        continue
    indent = line[:len(line) - len(stripped)]
    if b" " in indent:
        errors.append(i + 1)

if errors:
    print(f"ERROR: Space indentation found on lines: {errors}")
else:
    print(f"OK: File written correctly ({len(data)} bytes, {len(lines)} lines)")
