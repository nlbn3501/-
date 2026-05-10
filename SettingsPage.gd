## 设置页面，提供语言切换和截图目录配置
extends Control

var _lbl_title: Label
var _btn_back: Button
var _opt_language: OptionButton
var _section_general: Label
var _section_paths: Label
var _lbl_lang: Label
var _lbl_screenshot_dir: Label
var _btn_screenshot_dir: Button
var _lbl_screenshot_path: Label

const BAR_HEIGHT := 44
const ITEM_HEIGHT := 48


## 节点就绪时构建UI并适配窗口
func _ready() -> void:
	_build_ui()
	call_deferred("_fit_to_window")


## 构建设置页面的UI布局，包括语言选择和截图目录设置
func _build_ui() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(size.x, BAR_HEIGHT)
	add_child(top_bar)

	_lbl_title = Label.new()
	_lbl_title.name = "LblTitle"
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_lbl_title)

	_btn_back = Button.new()
	_btn_back.name = "BtnBack"
	top_bar.add_child(_btn_back)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.position = Vector2(0, BAR_HEIGHT)
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	_section_general = Label.new()
	_section_general.name = "SectionGeneral"
	_section_general.custom_minimum_size.y = 36
	vbox.add_child(_section_general)

	var lang_row := HBoxContainer.new()
	lang_row.name = "LangRow"
	lang_row.custom_minimum_size.y = ITEM_HEIGHT
	vbox.add_child(lang_row)

	_lbl_lang = Label.new()
	_lbl_lang.name = "LblLang"
	_lbl_lang.custom_minimum_size.x = 120
	_lbl_lang.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lang_row.add_child(_lbl_lang)

	_opt_language = OptionButton.new()
	_opt_language.name = "OptLanguage"
	_opt_language.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_language.add_item("中文", 0)
	_opt_language.add_item("English", 1)
	lang_row.add_child(_opt_language)

	var separator1 := HSeparator.new()
	vbox.add_child(separator1)

	_section_paths = Label.new()
	_section_paths.name = "SectionPaths"
	_section_paths.custom_minimum_size.y = 36
	vbox.add_child(_section_paths)

	var screenshot_row := HBoxContainer.new()
	screenshot_row.name = "ScreenshotRow"
	screenshot_row.custom_minimum_size.y = ITEM_HEIGHT
	vbox.add_child(screenshot_row)

	_lbl_screenshot_dir = Label.new()
	_lbl_screenshot_dir.name = "LblScreenshotDir"
	_lbl_screenshot_dir.custom_minimum_size.x = 120
	_lbl_screenshot_dir.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	screenshot_row.add_child(_lbl_screenshot_dir)

	var screenshot_vbox := VBoxContainer.new()
	screenshot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screenshot_row.add_child(screenshot_vbox)

	_lbl_screenshot_path = Label.new()
	_lbl_screenshot_path.name = "LblScreenshotPath"
	_lbl_screenshot_path.clip_text = true
	_lbl_screenshot_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screenshot_vbox.add_child(_lbl_screenshot_path)

	_btn_screenshot_dir = Button.new()
	_btn_screenshot_dir.name = "BtnScreenshotDir"
	_btn_screenshot_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screenshot_vbox.add_child(_btn_screenshot_dir)

	_btn_back.pressed.connect(_on_back_pressed)
	_opt_language.item_selected.connect(_on_language_selected)
	_btn_screenshot_dir.pressed.connect(_on_screenshot_dir_pressed)
	_refresh_language()


## 将设置页面各区域尺寸适配到窗口大小
func _fit_to_window() -> void:
	var vp_size := get_viewport_rect().size
	size = vp_size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top_bar: HBoxContainer = get_node_or_null("TopBar") as HBoxContainer
	if top_bar:
		top_bar.size = Vector2(vp_size.x, BAR_HEIGHT)
	var scroll: ScrollContainer = get_node_or_null("Scroll") as ScrollContainer
	if scroll:
		scroll.size = Vector2(vp_size.x, vp_size.y - BAR_HEIGHT)
		scroll.position = Vector2(0, BAR_HEIGHT)


## 根据当前语言设置刷新语言选项框的选中状态
func _refresh_language() -> void:
	var current := Global.get_locale()
	if current == "zh_CN":
		_opt_language.selected = 0
	elif current == "en":
		_opt_language.selected = 1
	else:
		_opt_language.selected = -1
	_update_labels()


## 更新所有界面标签的翻译文本
func _update_labels() -> void:
	_lbl_title.text = tr("设置")
	_btn_back.text = tr("返回")
	_section_general.text = tr("通用")
	_lbl_lang.text = tr("语言")
	_section_paths.text = tr("路径")
	_lbl_screenshot_dir.text = tr("截图目录")
	var ss_dir: String = Global.get_screenshot_dir()
	if ss_dir.is_empty():
		_lbl_screenshot_path.text = tr("(未设置，将使用工作区目录)")
	else:
		_lbl_screenshot_path.text = ss_dir
	_btn_screenshot_dir.text = tr("选择目录")


## 语言选择变更回调，切换应用语言并刷新标签
func _on_language_selected(index: int) -> void:
	match index:
		0:
			Global.set_locale("zh_CN")
		1:
			Global.set_locale("en")
	_update_labels()


## 点击截图目录按钮，弹出文件夹选择对话框
func _on_screenshot_dir_pressed() -> void:
	DisplayServer.file_dialog_show(
		tr("选择截图保存目录"),
		Global.get_screenshot_dir(),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
		PackedStringArray([]),
		_on_screenshot_dir_selected
	)


## 截图目录选择对话框回调，确认后更新路径并刷新标签
func _on_screenshot_dir_selected(ok: bool, paths: PackedStringArray, _filter_index: int) -> void:
	if ok and not paths.is_empty():
		Global.set_screenshot_dir(paths[0])
		_update_labels()


## 点击返回按钮，销毁设置页面
func _on_back_pressed() -> void:
	queue_free()
