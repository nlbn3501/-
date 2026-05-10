## 节点编辑对话框，提供名称、描述、掌握程度和父节点的编辑功能
extends ConfirmationDialog

signal node_edited(node_index: int, new_data: Dictionary)

var data_manager: RefCounted
var current_node_index: int = -1
var current_node_data: Dictionary = {}

var name_edit: LineEdit
var desc_edit: TextEdit
var mastery_opt: OptionButton
var parent_opt: OptionButton

## 初始化编辑对话框，构建表单UI并连接确认信号
func _init(dm: RefCounted) -> void:
	data_manager = dm
	title = "编辑节点"
	min_size = Vector2(450, 400)
	
	confirmed.connect(_on_confirmed)
	
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	
	var name_row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = Label.new()
	name_label.text = "名称:"
	name_label.custom_minimum_size = Vector2(80, 0)
	name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.placeholder_text = "输入知识点名称"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_t: String) -> void:
		confirmed.emit()
	)
	name_row.add_child(name_label)
	name_row.add_child(name_edit)
	vbox.add_child(name_row)
	
	var desc_row: HBoxContainer = HBoxContainer.new()
	var desc_label: Label = Label.new()
	desc_label.text = "描述:"
	desc_label.custom_minimum_size = Vector2(80, 0)
	desc_edit = TextEdit.new()
	desc_edit.name = "DescEdit"
	desc_edit.placeholder_text = "输入描述信息"
	desc_edit.custom_minimum_size = Vector2(0, 80)
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.wrap_mode = 1
	desc_row.add_child(desc_label)
	desc_row.add_child(desc_edit)
	vbox.add_child(desc_row)
	
	var mastery_row: HBoxContainer = HBoxContainer.new()
	var mastery_label: Label = Label.new()
	mastery_label.text = "掌握程度:"
	mastery_label.custom_minimum_size = Vector2(80, 0)
	mastery_opt = OptionButton.new()
	mastery_opt.name = "MasteryOpt"
	mastery_opt.add_item("未学习 (0)", 0)
	mastery_opt.add_item("学习中 (1)", 1)
	mastery_opt.add_item("已掌握 (2)", 2)
	mastery_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mastery_row.add_child(mastery_label)
	mastery_row.add_child(mastery_opt)
	vbox.add_child(mastery_row)
	
	var parent_row: HBoxContainer = HBoxContainer.new()
	var parent_label: Label = Label.new()
	parent_label.text = "父节点:"
	parent_label.custom_minimum_size = Vector2(80, 0)
	parent_opt = OptionButton.new()
	parent_opt.name = "ParentOpt"
	parent_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_row.add_child(parent_label)
	parent_row.add_child(parent_opt)
	vbox.add_child(parent_row)
	
	add_child(vbox)


## 打开编辑指定节点的对话框，填充当前数据
func edit_node(node_index: int) -> void:
	if node_index < 0 or node_index >= data_manager.call("get_count"):
		return
	
	current_node_index = node_index
	current_node_data = data_manager.call("get_item", node_index).duplicate(true)
	_populate_ui()
	popup_centered()


## 将当前节点数据填充到表单控件
func _populate_ui() -> void:
	name_edit.text = str(current_node_data.get("name", ""))
	desc_edit.text = str(current_node_data.get("description", ""))
	
	var mastery: int = int(current_node_data.get("mastery", 0))
	mastery_opt.selected = mastery
	
	parent_opt.clear()
	parent_opt.add_item("(无父节点/根节点)", -1)
	
	var current_parent_id: String = str(current_node_data.get("parent_id", ""))
	var count: int = data_manager.call("get_count")
	var select_index: int = 0
	
	for i in count:
		if i == current_node_index:
			continue
		var item: Dictionary = data_manager.call("get_item", i)
		var item_name: String = str(item.get("name", ""))
		var item_id: String = str(item.get("id", ""))
		parent_opt.add_item(item_name, i)
		if item_id == current_parent_id:
			select_index = parent_opt.item_count - 1
	
	parent_opt.selected = select_index


## 确认编辑，收集表单数据并发射节点编辑信号
func _on_confirmed() -> void:
	if current_node_index < 0:
		return
	
	var new_name: String = name_edit.text.strip_edges()
	if new_name.is_empty():
		new_name = "Node"
	
	var unique_name: String = data_manager.call("generate_unique_name", new_name)
	
	var selected_parent_id: int = parent_opt.get_selected_id()
	var parent_item_id: String = ""
	if selected_parent_id >= 0:
		var parent_item: Dictionary = data_manager.call("get_item", selected_parent_id)
		parent_item_id = str(parent_item.get("id", ""))
	
	var new_data: Dictionary = current_node_data.duplicate(true)
	new_data["name"] = unique_name
	new_data["description"] = desc_edit.text.strip_edges()
	new_data["mastery"] = mastery_opt.get_selected_id()
	new_data["parent_id"] = parent_item_id
	
	node_edited.emit(current_node_index, new_data)
