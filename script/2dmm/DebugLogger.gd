## 调试日志记录器，将带时间戳的日志输出到控制台和文件
extends RefCounted

var _log_file: FileAccess
var _log_path: String

## 初始化日志文件路径，可选追加模式或覆盖模式
func _init(path: String = "res://debug_log.txt", append: bool = false) -> void:
	_log_path = path
	if not append:
		if FileAccess.file_exists(_log_path):
			DirAccess.remove_absolute(_log_path)
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE_READ)
	if _log_file:
		_log_file.seek_end()
		write("=== DebugLogger 初始化 ===")

## 写入一条带时间戳的日志消息到控制台和文件
func write(msg: String) -> void:
	var timestamp: String = Time.get_datetime_string_from_system()
	var line: String = "[%s] %s" % [timestamp, msg]
	print(line)
	if _log_file:
		_log_file.seek_end()
		_log_file.store_line(line)
		_log_file.flush()

## 关闭日志文件句柄
func close() -> void:
	if _log_file:
		_log_file.close()
		_log_file = null

## 读取日志文件的全部内容，读取后重新以读写模式打开文件
func get_log_content() -> String:
	close()
	if not FileAccess.file_exists(_log_path):
		return ""
	var file = FileAccess.open(_log_path, FileAccess.READ)
	if not file:
		return ""
	var content = file.get_as_text()
	file.close()
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE_READ)
	if _log_file:
		_log_file.seek_end()
	return content
