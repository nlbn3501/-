## 2D思维导图数据管理器，负责知识节点数据的加载、保存、增删改查和备份恢复
extends RefCounted

const DEBUG_LOG := false
const MAX_BACKUPS: int = 10

var data_file: String
var items: Array = []
var backup_dir: String = ""

## 初始化数据管理器，设置文件路径并加载数据
func _init(file_path: String) -> void:
    data_file = file_path
    backup_dir = data_file.get_base_dir() + "/backups"
    load_data()

## 调试日志输出
func _log(p_msg: String) -> void:
    if DEBUG_LOG:
        print("[DataManager] " + p_msg)

## 从JSON文件加载节点数据到items数组
func load_data() -> void:
    _log("加载数据: %s" % data_file)
    
    if not FileAccess.file_exists(data_file):
        _log("数据文件不存在，创建新数据")
        items = []
        return
    
    var file = FileAccess.open(data_file, FileAccess.READ)
    if not file:
        _log("无法打开数据文件")
        return
    
    var json_string = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    var parse_result = json.parse(json_string)
    
    if parse_result == OK:
        var result = json.get_data()
        if result is Dictionary and result.has("nodes"):
            items = result["nodes"]
        elif result is Array:
            items = result
        else:
            items = []
        _migrate_legacy_fields()
        _log("数据加载成功，共 %d 项" % items.size())
    else:
        _log("JSON解析失败: %s" % json.get_error_message())

func _migrate_legacy_fields() -> void:
    var changed: bool = false
    for item in items:
        if item is Dictionary:
            if item.has("parent") and not item.has("parent_id"):
                item["parent_id"] = str(item["parent"]) if item["parent"] != null else ""
                item.erase("parent")
                changed = true
            if not item.has("id"):
                if item.has("name"):
                    item["id"] = str(item["name"]).replace(" ", "_").to_lower()
                else:
                    item["id"] = "node_%d" % randi_range(1000, 9999)
                changed = true
            if not item.has("pos2d") and item.has("position"):
                var pos = item["position"]
                if pos is Array and pos.size() >= 2:
                    item["pos2d"] = [3600.0 + float(pos[0]) * 200.0, 2700.0 + float(pos[1]) * 200.0]
                changed = true
    if changed:
        save_data()

## 将items数组保存为JSON文件
func save_data() -> void:
    _log("保存数据: %s, 共 %d 项" % [data_file, items.size()])
    
    var file = FileAccess.open(data_file, FileAccess.WRITE)
    if not file:
        _log("无法保存数据文件")
        return
    
    var data = {"nodes": items}
    var json_string = JSON.stringify(data, "\t")
    file.store_string(json_string)
    file.close()

## 获取数据项数量
func get_count() -> int:
    return items.size()

## 获取指定索引的数据项
func get_item(index: int) -> Dictionary:
    if index < 0 or index >= items.size():
        return {}
    return items[index]

## 添加一个数据项，返回新项的索引
func add_item(item: Dictionary) -> int:
    items.append(item)
    return items.size() - 1

## 移除指定索引的数据项
func remove_item(index: int) -> void:
    if index >= 0 and index < items.size():
        items.remove_at(index)

## 生成不重复的名称，若已存在则添加序号后缀
func generate_unique_name(base_name: String) -> String:
    var unique_name = base_name
    var counter = 1
    
    while find_by_name(unique_name) >= 0:
        unique_name = base_name + " (" + str(counter) + ")"
        counter += 1
    
    return unique_name

## 通过名称查找数据项索引
func find_by_name(name: String) -> int:
    for i in range(items.size()):
        if items[i].get("name", "") == name:
            return i
    return -1

## 基于时间戳和随机数生成唯一节点ID
func generate_unique_id(base_name: String) -> String:
    var timestamp = Time.get_unix_time_from_system()
    var random_num = randi_range(1000, 9999)
    return "node_" + str(timestamp) + "_" + str(random_num)

## 通过节点ID查找数据项索引
func find_index_by_id(node_id: String) -> int:
    for i in range(items.size()):
        if items[i].get("id", "") == node_id:
            return i
    return -1

## 获取从根节点到指定节点的路径字符串
func get_node_path(index: int) -> String:
    var path: String = ""
    var current_index = index
    
    while current_index >= 0:
        var item = get_item(current_index)
        if item:
            if path.is_empty():
                path = item.get("name", "")
            else:
                path = item.get("name", "") + " > " + path
            
            if str(item.get("parent_id", "")):
                current_index = find_index_by_id(str(item.get("parent_id", "")))
            else:
                current_index = -1
        else:
            current_index = -1
    
    return path

## 计算所有节点的深度（到根的层级数），检测循环引用
func compute_depths() -> Array:
    var depths: Array = []
    var count: int = get_count()
    
    for i in count:
        var depth: int = 0
        var current_index = i
        var visited: Array = []
        
        while current_index >= 0:
            if visited.has(current_index):
                _log("循环引用检测: 节点 %d 存在循环依赖" % current_index)
                break
            
            visited.append(current_index)
            var item = get_item(current_index)
            if item and str(item.get("parent_id", "")):
                current_index = find_index_by_id(str(item.get("parent_id", "")))
                if current_index >= 0:
                    depth += 1
                else:
                    current_index = -1
        
        depths.append(depth)
    
    return depths

## 收集所有父子边关系
func collect_edges() -> Array:
    var edges: Array = []
    var count: int = get_count()
    
    for i in count:
        var item: Dictionary = get_item(i)
        var parent_id: String = str(item.get("parent_id", ""))
        
        if parent_id:
            edges.append({
                "from": find_index_by_id(parent_id),
                "to": i
            })
    
    return edges

## 设置指定索引的数据项
func set_item(index: int, item: Dictionary) -> void:
    if index >= 0 and index < items.size():
        items[index] = item

## 验证数据完整性，检查ID重复、缺失字段和循环引用
func validate_data() -> bool:
    var valid: bool = true
    var ids: Dictionary = {}
    
    for i in range(items.size()):
        var item: Dictionary = items[i]
        
        if not item.has("id"):
            _log("验证错误: 节点 %d 缺少 id 字段" % i)
            item["id"] = "node_%d" % i
            valid = false
        
        var node_id: String = str(item.get("id", ""))
        if ids.has(node_id):
            _log("验证错误: 节点 %d 的 id '%s' 与节点 %d 重复" % [i, node_id, ids[node_id]])
            item["id"] = "node_%d_%d" % [i, Time.get_ticks_msec()]
            valid = false
        ids[node_id] = i
        
        if not item.has("name"):
            _log("验证错误: 节点 %d 缺少 name 字段" % i)
            item["name"] = "Node %d" % i
            valid = false
        
        var parent_id: String = str(item.get("parent_id", ""))
        if not parent_id.is_empty() and find_index_by_id(parent_id) < 0:
            _log("验证错误: 节点 %d 的 parent_id '%s' 不存在" % [i, parent_id])
            item["parent_id"] = ""
            valid = false
        
        var current_index = i
        var visited: Array = []
        var has_cycle = false
        while current_index >= 0:
            if visited.has(current_index):
                _log("验证错误: 节点 %d 存在循环引用" % i)
                item["parent_id"] = ""
                valid = false
                has_cycle = true
                break
            visited.append(current_index)
            var current_item = get_item(current_index)
            if current_item and str(current_item.get("parent_id", "")):
                current_index = find_index_by_id(str(current_item.get("parent_id", "")))
            else:
                current_index = -1
        
        if has_cycle:
            continue
    
    return valid

## 创建当前数据的备份文件
func create_backup() -> bool:
    if not DirAccess.dir_exists_absolute(backup_dir):
        DirAccess.make_dir_recursive_absolute(backup_dir)
    
    var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
    var backup_path: String = backup_dir + "/data_backup_%s.json" % timestamp
    
    var file = FileAccess.open(backup_path, FileAccess.WRITE)
    if not file:
        _log("无法创建备份文件: %s" % backup_path)
        return false
    
    var data: Dictionary = {"nodes": items}
    file.store_string(JSON.stringify(data, "\t"))
    file.close()
    
    _log("备份创建成功: %s" % backup_path)
    _cleanup_old_backups()
    return true

## 从指定备份文件恢复数据
func restore_from_backup(backup_path: String) -> bool:
    if not FileAccess.file_exists(backup_path):
        _log("备份文件不存在: %s" % backup_path)
        return false
    
    var file = FileAccess.open(backup_path, FileAccess.READ)
    if not file:
        _log("无法打开备份文件: %s" % backup_path)
        return false
    
    var json_string: String = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    if json.parse(json_string) != OK:
        _log("备份文件解析失败: %s" % backup_path)
        return false
    
    var result = json.get_data()
    if result is Dictionary and result.has("nodes"):
        items = result["nodes"]
    elif result is Array:
        items = result
    else:
        _log("备份文件格式无效: %s" % backup_path)
        return false
    
    save_data()
    _log("从备份恢复成功: %s" % backup_path)
    return true

## 获取所有备份文件的路径列表
func get_backup_list() -> Array:
    var backups: Array = []
    
    if not DirAccess.dir_exists_absolute(backup_dir):
        return backups
    
    var dir = DirAccess.open(backup_dir)
    if not dir:
        return backups
    
    dir.list_dir_begin()
    var file_name = dir.get_next()
    while file_name != "":
        if file_name.begins_with("data_backup_") and file_name.ends_with(".json"):
            backups.append(backup_dir + "/" + file_name)
        file_name = dir.get_next()
    dir.list_dir_end()
    
    backups.sort()
    return backups

## 将数据导出到指定路径的JSON文件
func export_data(filepath: String) -> bool:
    var file = FileAccess.open(filepath, FileAccess.WRITE)
    if not file:
        _log("无法导出数据到: %s" % filepath)
        return false
    
    var data: Dictionary = {"nodes": items}
    file.store_string(JSON.stringify(data, "\t"))
    file.close()
    
    _log("数据导出成功: %s" % filepath)
    return true

## 从指定路径的JSON文件导入数据，导入前自动创建备份
func import_data(filepath: String) -> bool:
    if not FileAccess.file_exists(filepath):
        _log("导入文件不存在: %s" % filepath)
        return false
    
    var file = FileAccess.open(filepath, FileAccess.READ)
    if not file:
        _log("无法打开导入文件: %s" % filepath)
        return false
    
    var json_string: String = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    if json.parse(json_string) != OK:
        _log("导入文件解析失败: %s" % filepath)
        return false
    
    var result = json.get_data()
    var imported_items: Array = []
    if result is Dictionary and result.has("nodes"):
        imported_items = result["nodes"]
    elif result is Array:
        imported_items = result
    else:
        _log("导入文件格式无效: %s" % filepath)
        return false
    
    create_backup()
    items = imported_items
    save_data()
    
    _log("数据导入成功: %s, 共 %d 项" % [filepath, items.size()])
    return true

## 获取当前数据的深拷贝快照
func get_items_snapshot() -> Array:
    return items.duplicate(true)

## 从快照恢复数据并保存
func restore_items_snapshot(snapshot: Array) -> void:
    items = snapshot.duplicate(true)
    save_data()

## 清理超出最大备份数量的旧备份文件
func _cleanup_old_backups() -> void:
    var backups: Array = get_backup_list()
    while backups.size() > MAX_BACKUPS:
        var oldest: String = backups.pop_front()
        DirAccess.remove_absolute(oldest)
        _log("删除旧备份: %s" % oldest)
