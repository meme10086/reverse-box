class_name RewindPanel
extends Control
## 时间回溯面板：选对象 → 选它的历史位置 → 执行。
##
## 只负责界面与输入转译，规则判定全部在 GameManager（节点是否可用、资源够不够）。
## 目标：玩家一眼就能看出「我现在正在回溯谁」「它会回到哪一格」。

const COL_BG := Color(0.07, 0.10, 0.17, 0.96)
const COL_EDGE := Color(0.42, 0.62, 0.92, 0.9)
const COL_TEXT := Color(0.93, 0.96, 1.0)
const COL_DIM := Color(0.62, 0.70, 0.84)
const COL_OK := Color(0.55, 0.90, 0.66)
const COL_BAD := Color(0.95, 0.62, 0.55)
const COL_SEL := Color(0.35, 0.62, 1.0)

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _obj_row: HBoxContainer
var _prev_btn: Button
var _next_btn: Button
var _node_label: Label
var _status: Label
var _apply_btn: Button
var _cancel_btn: Button

var _built := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _build() -> void:
	if _built:
		return
	_built = true

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.04, 0.08, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BG
	sb.set_corner_radius_all(6)
	sb.border_color = COL_EDGE
	sb.set_border_width_all(3)
	sb.content_margin_left = 30.0
	sb.content_margin_right = 30.0
	sb.content_margin_top = 22.0
	sb.content_margin_bottom = 22.0
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)

	_title = Label.new()
	_title.text = "时间回溯"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", COL_TEXT)
	v.add_child(_title)

	var sub := Label.new()
	sub.text = "只改变你选中的那个对象，其它对象留在原地"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", COL_DIM)
	v.add_child(sub)

	_obj_row = HBoxContainer.new()
	_obj_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_obj_row.add_theme_constant_override("separation", 10)
	v.add_child(_obj_row)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	v.add_child(nav)

	_prev_btn = _mk_button("◀ 更早", Vector2(120.0, 46.0))
	_prev_btn.pressed.connect(func(): GameManager.move_node(-1))
	nav.add_child(_prev_btn)

	_node_label = Label.new()
	_node_label.custom_minimum_size = Vector2(300.0, 46.0)
	_node_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_node_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_node_label.add_theme_font_size_override("font_size", 19)
	_node_label.add_theme_color_override("font_color", COL_TEXT)
	nav.add_child(_node_label)

	_next_btn = _mk_button("更近 ▶", Vector2(120.0, 46.0))
	_next_btn.pressed.connect(func(): GameManager.move_node(1))
	nav.add_child(_next_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", COL_DIM)
	v.add_child(_status)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)

	_apply_btn = _mk_button("执行回溯", Vector2(180.0, 52.0), true)
	_apply_btn.pressed.connect(func(): GameManager.apply_rewind())
	row.add_child(_apply_btn)

	_cancel_btn = _mk_button("取消 (R)", Vector2(140.0, 52.0))
	_cancel_btn.pressed.connect(func(): GameManager.toggle_rewind())
	row.add_child(_cancel_btn)


func _mk_button(text: String, sz: Vector2, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", COL_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.24, 0.38, 0.95) if not primary else Color(0.22, 0.42, 0.72, 0.98)
	sb.set_corner_radius_all(4)
	sb.border_color = COL_SEL if primary else Color(0.35, 0.45, 0.62)
	sb.set_border_width_all(3)
	return b


# 每帧由 game.gd 调用
func refresh() -> void:
	if not _built:
		return
	var active: bool = GameManager.rewind_mode
	visible = active
	if not active:
		return

	_sync_object_buttons()

	var obj := GameManager.selected_object_index()
	var trail := GameManager.trail_of_object(obj)
	var total: int = trail.size()
	var cur := GameManager.node_index
	var back: int = maxi(0, total - 1 - cur)

	_title.text = "时间回溯 · %s" % GameManager.object_name(obj)
	_node_label.text = "回到 %d 步前（第 %d / %d 个过去位置）" % [back, cur + 1, maxi(1, total - 1)]

	var valid: bool = GameManager.node_valid(cur)
	if total <= 1:
		_node_label.text = "没有可回的位置"
		_status.text = "这个对象还没有过去可回"
		_status.add_theme_color_override("font_color", COL_BAD)
	elif valid:
		_status.text = "✔ 可以回到这里"
		_status.add_theme_color_override("font_color", COL_OK)
	else:
		_status.text = "✘ 这一格现在被占着（墙 / 别的对象），换一个位置"
		_status.add_theme_color_override("font_color", COL_BAD)

	_apply_btn.disabled = not GameManager.can_apply()
	_apply_btn.text = "执行回溯（剩 %d）" % GameManager.rewind_left
	_prev_btn.disabled = cur - 1 < 0
	_next_btn.disabled = cur + 1 > total - 1


func _sync_object_buttons() -> void:
	var want := GameManager.object_count()
	while _obj_row.get_child_count() > want:
		var last := _obj_row.get_child(want)
		_obj_row.remove_child(last)
		last.queue_free()
	while _obj_row.get_child_count() < want:
		var idx := _obj_row.get_child_count()
		var b := _mk_button("对象", Vector2(120.0, 46.0))
		b.name = "Obj%d" % idx
		b.pressed.connect(func(): GameManager.select_object(idx))
		_obj_row.add_child(b)

	var sel := GameManager.selected_object_index()
	for i in want:
		var b := _obj_row.get_child(i) as Button
		var t := GameManager.trail_of_object(i)
		var past: int = t.past_count()
		b.text = "%s（%d）" % [GameManager.object_name(i), past]
		b.disabled = past <= 0 and i != sel
		b.add_theme_color_override("font_color", COL_TEXT)
		var sb := StyleBoxFlat.new()
		var on := i == sel
		sb.bg_color = Color(0.24, 0.46, 0.78, 0.98) if on else Color(0.14, 0.20, 0.32, 0.95)
		sb.set_corner_radius_all(4)
		sb.border_color = COL_SEL if on else Color(0.32, 0.40, 0.55)
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("disabled", sb)
