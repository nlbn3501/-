extends RefCounted

var data_manager: RefCounted
var root_node: Node

const MENU_ITEMS = [
    {"name": "show_detail", "label": "查看详情"},
    {"name": "focus_node", "label": "聚焦节点"},
    {"name": "separator", "label": ""},
    {"name": "set_mastery", "label": "设置掌握程度", "subitems": [
        {"name": "set_mastery_0", "label": "未学习"},
        {"name": "set_mastery_1", "label": "学习中"},
        {"name": "set_mastery_2", "label": "已掌握"}
    ]},
    {"name": "separator", "label": ""},
    {"name": "remove_from_view", "label": "从视图移除"},
    {"name": "separator", "label": ""},
    {"name": "auto_layout", "label": "自动布局"},
    {"name": "refresh", "label": "刷新"},
    {"name": "reset_view", "label": "重置视图"}
]

const PROBLEM_MENU_ITEMS = [
    {"name": "show_detail", "label": "编辑题目"},
    {"name": "separator", "label": ""},
    {"name": "add_related_knowledge", "label": "添加关联知识点"},
    {"name": "add_relation_line", "label": "添加关系线", "subitems": [
        {"name": "add_relation_line_用到", "label": "用到"},
        {"name": "add_relation_line_可替换", "label": "可替换"},
        {"name": "add_relation_line_前置", "label": "前置"},
        {"name": "add_relation_line_延伸", "label": "延伸"}
    ]},
    {"name": "separator", "label": ""},
    {"name": "delete_problem", "label": "删除题目"},
    {"name": "separator", "label": ""},
    {"name": "auto_layout", "label": "自动布局"},
    {"name": "refresh", "label": "刷新"},
    {"name": "reset_view", "label": "重置视图"}
]

## 题目卡片列表模式的右键菜单（无连线相关项）
const CARD_MENU_ITEMS = [
    {"name": "show_detail", "label": "编辑题目"},
    {"name": "open_canvas", "label": "打开关系画布"},
    {"name": "separator", "label": ""},
    {"name": "remove_from_group", "label": "从组中移出"},
    {"name": "delete_problem", "label": "删除题目"},
]

const EMPTY_MENU_ITEMS = [
    {"name": "create_problem", "label": "新建题目"},
    {"name": "create_group", "label": "创建组"},
    {"name": "separator", "label": ""},
    {"name": "auto_layout", "label": "自动布局"},
    {"name": "separator", "label": ""},
    {"name": "refresh", "label": "刷新"},
    {"name": "reset_view", "label": "重置视图"},
    {"name": "separator", "label": ""},
    {"name": "screenshot", "label": "截图"}
]

const MULTI_SELECT_MENU_ITEMS = [
    {"name": "batch_mastery_2", "label": "批量标记为已掌握"},
    {"name": "batch_mastery_1", "label": "批量标记为学习中"},
    {"name": "batch_mastery_0", "label": "批量标记为未学习"},
    {"name": "separator", "label": ""},
    {"name": "batch_delete", "label": "批量删除"}
]

signal menu_action(action: String, index: int, extra: Variant, mouse_pos: Vector2)

func _init(dm: RefCounted, root: Node) -> void:
    data_manager = dm
    root_node = root

func show_node_context_menu(node_index: int, mouse_pos: Vector2, is_empty: bool, focus_label: String = "聚焦节点", focus_action: String = "focus_node") -> void:
    var is_problem: bool = node_index >= 100000
    var items: Array = PROBLEM_MENU_ITEMS if is_problem else MENU_ITEMS
    var menu_name: String = "ProblemContextMenu" if is_problem else "NodeContextMenu"
    var menu: PopupMenu = PopupMenu.new()
    menu.name = menu_name

    for item in items:
        if item.name == "separator":
            menu.add_separator()
        elif item.has("subitems"):
            var submenu_name = "SubMenu_" + str(item.name)
            var submenu = PopupMenu.new()
            submenu.name = submenu_name
            for subitem in item.subitems:
                submenu.add_item(subitem.label)
                var sub_idx = submenu.get_item_count() - 1
                submenu.set_item_metadata(sub_idx, subitem.name)
            menu.add_child(submenu)
            menu.add_submenu_item(item.label, submenu_name)
            var menu_idx = menu.get_item_count() - 1
            menu.set_item_metadata(menu_idx, item.name)
            submenu.index_pressed.connect(_on_submenu_item_pressed.bind(node_index, mouse_pos, item.name))
        else:
            var display_label: String = item.label
            var action_name: String = item.name
            if item.name == "focus_node":
                display_label = focus_label
                action_name = focus_action
            menu.add_item(display_label)
            var menu_idx = menu.get_item_count() - 1
            menu.set_item_metadata(menu_idx, action_name)

    menu.index_pressed.connect(_on_menu_item_pressed.bind(node_index, mouse_pos))

    root_node.add_child(menu)
    menu.position = Vector2i(root_node.get_viewport().get_mouse_position())
    menu.popup()
    menu.grab_focus()
    menu.popup_hide.connect(func():
        if is_instance_valid(menu):
            menu.queue_free()
    )

## 题目卡片列表模式的右键菜单（编辑、打开画布、删除）
func show_card_context_menu(prob_index: int, mouse_pos: Vector2) -> void:
    var menu: PopupMenu = PopupMenu.new()
    menu.name = "CardContextMenu"

    for item in CARD_MENU_ITEMS:
        if item.name == "separator":
            menu.add_separator()
        else:
            menu.add_item(item.label)
            var menu_idx = menu.get_item_count() - 1
            menu.set_item_metadata(menu_idx, item.name)

    menu.index_pressed.connect(func(idx: int):
        var action_name: String = menu.get_item_metadata(idx)
        if action_name:
            menu_action.emit(action_name, prob_index, null, Vector2.ZERO)
        menu.queue_free()
    )

    root_node.add_child(menu)
    menu.position = Vector2i(root_node.get_viewport().get_mouse_position())
    menu.popup()
    menu.grab_focus()
    menu.popup_hide.connect(func():
        if is_instance_valid(menu):
            menu.queue_free()
    )

func show_empty_context_menu(mouse_pos: Vector2, local_pos: Vector2) -> void:
    var menu: PopupMenu = PopupMenu.new()
    menu.name = "EmptyContextMenu"

    for item in EMPTY_MENU_ITEMS:
        if item.name == "separator":
            menu.add_separator()
        else:
            menu.add_item(item.label)
            var menu_idx = menu.get_item_count() - 1
            menu.set_item_metadata(menu_idx, item.name)

    menu.index_pressed.connect(_on_empty_menu_item_pressed.bind(local_pos))

    root_node.add_child(menu)
    menu.position = Vector2i(root_node.get_viewport().get_mouse_position())
    menu.popup()
    menu.grab_focus()
    menu.popup_hide.connect(func():
        if is_instance_valid(menu):
            menu.queue_free()
    )

func show_multi_selection_menu(mouse_pos: Vector2, selected_indices: Array) -> void:
    var menu: PopupMenu = PopupMenu.new()
    menu.name = "MultiSelectContextMenu"

    menu.add_item("批量操作 (%d个节点)" % selected_indices.size())
    menu.set_item_disabled(0, true)
    menu.add_separator()

    for item in MULTI_SELECT_MENU_ITEMS:
        if item.name == "separator":
            menu.add_separator()
        else:
            menu.add_item(item.label)
            var menu_idx = menu.get_item_count() - 1
            menu.set_item_metadata(menu_idx, item.name)

    menu.index_pressed.connect(_on_multi_select_menu_item_pressed.bind(selected_indices))

    root_node.add_child(menu)
    menu.position = Vector2i(root_node.get_viewport().get_mouse_position())
    menu.popup()
    menu.grab_focus()
    menu.popup_hide.connect(func():
        if is_instance_valid(menu):
            menu.queue_free()
    )

func _on_menu_item_pressed(index: int, node_index: int, mouse_pos: Vector2) -> void:
    var is_problem: bool = node_index >= 100000
    var menu_name: String = "ProblemContextMenu" if is_problem else "NodeContextMenu"
    var menu = root_node.get_node(menu_name) if root_node.has_node(menu_name) else null
    if menu:
        var action_name = menu.get_item_metadata(index)
        if action_name and action_name != "set_mastery":
            menu_action.emit(action_name, node_index, null, Vector2.ZERO)
        menu.queue_free()

func _on_submenu_item_pressed(index: int, node_index: int, mouse_pos: Vector2, parent_action: String) -> void:
    var is_problem: bool = node_index >= 100000
    var menu_name: String = "ProblemContextMenu" if is_problem else "NodeContextMenu"
    var submenu: PopupMenu = null
    if root_node.has_node(menu_name):
        for child in root_node.get_node(menu_name).get_children():
            if child is PopupMenu:
                submenu = child
                break
    if submenu:
        var sub_action = submenu.get_item_metadata(index)
        if sub_action:
            if sub_action.begins_with("set_mastery_"):
                var mastery = int(sub_action.get_slice("_", 2))
                menu_action.emit("set_mastery", node_index, mastery, Vector2.ZERO)
            elif sub_action.begins_with("add_relation_line_"):
                var rel_type: String = sub_action.substr(18)
                menu_action.emit("start_relation_line", node_index, rel_type, Vector2.ZERO)
        var menu = root_node.get_node(menu_name) if root_node.has_node(menu_name) else null
        if menu:
            menu.queue_free()

func _on_empty_menu_item_pressed(index: int, local_pos: Vector2) -> void:
    var menu = root_node.get_node("EmptyContextMenu") if root_node.has_node("EmptyContextMenu") else null
    if menu:
        var action_name = menu.get_item_metadata(index)
        if action_name:
            menu_action.emit(action_name, -1, local_pos, Vector2.ZERO)
        menu.queue_free()

func _on_multi_select_menu_item_pressed(index: int, selected_indices: Array) -> void:
    var menu = root_node.get_node("MultiSelectContextMenu") if root_node.has_node("MultiSelectContextMenu") else null
    if menu:
        var action_name = menu.get_item_metadata(index)
        if action_name:
            if action_name.begins_with("batch_mastery_"):
                var mastery = int(action_name.get_slice("_", 2))
                menu_action.emit("batch_mastery", -1, mastery, Vector2.ZERO)
            elif action_name == "batch_delete":
                menu_action.emit("batch_delete", -1, selected_indices, Vector2.ZERO)
        menu.queue_free()
