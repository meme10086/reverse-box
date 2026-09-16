extends Control
## 开始界面 = 关卡选择。
## 一屏 N 个方块，格子里是关卡编号（1~N），点哪个进哪关。
## 状态只靠颜色区分：已通关=绿框+对勾，推荐下一关=金框，其余=灰蓝框。
## 背景沿用像素大树，但不做任何装饰性动效（无粒子、无浮动、无连线）。

const TITLE_COLOR := Color(0.96, 0.98, 1.0)
const TITLE_OUTLINE := Color(0.10, 0.22, 0.42)
const SUBTITLE_COLOR := Color(0.76, 0.85, 0.97)
const INFO_COLOR := Color(0.93, 0.96, 1.0)
const HINT_COLOR := Color(0.66, 0.75, 0.88)

const TEX_DIR := "res://assets/art/pixel/"
const SETTINGS_PATH := "user://settings.cfg"

const COLS := 5              # 每行 5 个格子（10 关 = 2 行）
const GAP := 26.0            # 格子间距

var _node_layer: Control
var _title: Label
var _subtitle: Label
var _info: Label
var _hint: Label
var _settings_btn: Button
var _panel_style: StyleBoxFlat
var _settings_panel: CanvasLayer

var _nodes: Array = []       # Array[LevelNode]
var _selected := 0
var _bg: Texture2D

var _panel_h := 92.0
var _title_h := 88.0
var _area_top := 0.0
var _area_bottom := 0.0


func _ready() -> void:
	_apply_audio_setting()
	Music.play_menu()
	_build_ui()
	_build_nodes()
	_relayout()
	_update_info(_selected)
	resized.connect(_relayout)


# ---------------- 音频设置 ----------------

static func load_sfx_on() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return bool(cf.get_value("audio", "sfx", true))
	return true


static func save_sfx_on(v: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("audio", "sfx", v)
	cf.save(SETTINGS_PATH)


static func load_music_on() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		return bool(cf.get_value("audio", "music", true))
	return true


static func save_music_on(v: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("audio", "music", v)
	cf.save(SETTINGS_PATH)


# 音效与音乐各管各的：早年这里是直接静掉 Master 总线，一关音效会把音乐也带走。
func _apply_audio_setting() -> void:
	GameManager.set_sfx_on(load_sfx_on())
	Music.set_music_on(load_music_on())


# ---------------- 构建 ----------------

func _build_ui() -> void:
	_title = _make_label(54, TITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_title.name = "Title"
	_title.text = "Reverse Box"
	_title.add_theme_color_override("font_outline_color", TITLE_OUTLINE)
	_title.add_theme_constant_override("outline_size", 9)
	add_child(_title)

	_subtitle = _make_label(19, SUBTITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.name = "Subtitle"
	_subtitle.text = "逆时推箱 · 时间回溯解谜"
	_subtitle.add_theme_color_override("font_outline_color", Color(0.05, 0.09, 0.16))
	_subtitle.add_theme_constant_override("outline_size", 6)
	add_child(_subtitle)

	_node_layer = Control.new()
	_node_layer.name = "NodeLayer"
	_node_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_node_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_node_layer)

	_info = _make_label(23, INFO_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_info.name = "InfoLabel"
	add_child(_info)

	_hint = _make_label(15, HINT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.name = "HintLabel"
	_hint.text = "点击数字进入关卡　·　WASD / 方向键移动　·　R 回溯 1 格"
	add_child(_hint)

	_settings_btn = Button.new()
	_settings_btn.name = "SettingsButton"
	_settings_btn.text = "设置"
	_settings_btn.custom_minimum_size = Vector2(84.0, 40.0)
	_settings_btn.focus_mode = Control.FOCUS_NONE
	_settings_btn.add_theme_font_size_override("font_size", 17)
	_settings_btn.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.18, 0.27, 0.88)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.48, 0.68, 0.92, 0.75)
	sb.set_border_width_all(2)
	_settings_btn.add_theme_stylebox_override("normal", sb)
	var hv := sb.duplicate() as StyleBoxFlat
	hv.bg_color = sb.bg_color.lightened(0.20)
	_settings_btn.add_theme_stylebox_override("hover", hv)
	_settings_btn.add_theme_stylebox_override("pressed", hv)
	_settings_btn.pressed.connect(_open_settings)
	add_child(_settings_btn)

	_panel_style = StyleBoxFlat.new()
	_panel_style.bg_color = Color(0.08, 0.11, 0.17, 0.88)
	_panel_style.set_corner_radius_all(8)
	_panel_style.border_color = Color(0.42, 0.60, 0.86, 0.60)
	_panel_style.set_border_width_all(2)


func _make_label(font_size: int, color: Color, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_nodes() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()

	var next_index := _next_level_index()
	for i in LevelManager.level_count():
		var node := LevelNode.new()
		node.name = "LevelNode_%d" % i
		node.configure(i, Progress.is_completed(i), i == next_index)
		node.level_focused.connect(_on_node_focused)
		node.pressed.connect(_on_node_pressed.bind(i))
		_node_layer.add_child(node)
		_nodes.append(node)


# 推荐下一关 = 第一个还没通关的关卡；全通关则指向最后一关
func _next_level_index() -> int:
	for i in LevelManager.level_count():
		if not Progress.is_completed(i):
			return i
	return maxi(0, LevelManager.level_count() - 1)


# ---------------- 布局（横竖屏统一的网格） ----------------

func _relayout() -> void:
	var vp := size
	if vp.x <= 4.0 or vp.y <= 4.0:
		return

	# —— 标题区 ——
	_title_h = clampf(vp.y * 0.135, 56.0, 86.0)
	_title.position = Vector2(0.0, _title_h * 0.18)
	_title.size = Vector2(vp.x, _title_h * 0.72)
	_subtitle.position = Vector2(0.0, _title_h * 0.94)
	_subtitle.size = Vector2(vp.x, 28.0)

	# —— 底部信息区 ——
	_panel_h = clampf(vp.y * 0.142, 78.0, 102.0)
	_info.position = Vector2(0.0, vp.y - _panel_h)
	_info.size = Vector2(vp.x, 34.0)
	_hint.position = Vector2(0.0, vp.y - _panel_h + 36.0)
	_hint.size = Vector2(vp.x, 24.0)

	# —— 设置按钮（右上角）——
	_settings_btn.size = Vector2(84.0, 40.0)
	_settings_btn.position = Vector2(vp.x - 100.0, 12.0)

	_node_layer.position = Vector2.ZERO

	# —— 关卡网格：每行 4 个，整体在标题与底部面板之间居中 ——
	_area_top = _title_h + 26.0
	_area_bottom = vp.y - _panel_h - 16.0

	var n := _nodes.size()
	if n == 0:
		return
	# 关卡变多以后每行多放一列，避免整块被压得太小
	var cols := 5
	if n > 24:
		cols = 6
	elif n > 20:
		cols = 6
	var rows := int(ceil(float(n) / float(cols)))
	var grid_w := cols * LevelNode.NODE_W + float(cols - 1) * GAP
	var grid_h := rows * LevelNode.NODE_H + float(rows - 1) * GAP

	# 空间不够时按比例缩小间距（保证在任何屏幕比例下都放得下）
	var avail_w := vp.x - 48.0
	var avail_h := _area_bottom - _area_top
	var sx := 1.0
	var sy := 1.0
	if grid_w > avail_w and grid_w > 0.0:
		sx = avail_w / grid_w
	if grid_h > avail_h and grid_h > 0.0:
		sy = avail_h / grid_h
	var k := clampf(minf(sx, sy), 0.45, 1.0)

	var cw := LevelNode.NODE_W * k
	var ch := LevelNode.NODE_H * k
	var gap := GAP * k
	var g_w := cols * cw + float(cols - 1) * gap
	var g_h := rows * ch + float(rows - 1) * gap
	var ox := (vp.x - g_w) * 0.5
	var oy := _area_top + (avail_h - g_h) * 0.5

	for i in n:
		var node: Control = _nodes[i]
		var r := i / cols
		var c := i % cols
		node.size = Vector2(cw, ch)
		node.position = Vector2(ox + float(c) * (cw + gap), oy + float(r) * (ch + gap))


# ---------------- 绘制（背景 + 信息面板） ----------------

func _draw() -> void:
	var vp := size
	if vp.x <= 4.0:
		return
	_draw_background_image(vp)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.04, 0.08, 0.34))
	_draw_info_panel(vp)


func _bg_tex() -> Texture2D:
	if _bg == null:
		_bg = load(TEX_DIR + "map_bg.png")
	return _bg


func _draw_background_image(vp: Vector2) -> void:
	var tex := _bg_tex()
	if tex == null:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.05, 0.07, 0.13))
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var k := maxf(vp.x / ts.x, vp.y / ts.y)   # cover
	var ds := ts * k
	draw_texture_rect(tex, Rect2((vp - ds) * 0.5, ds), false)


func _draw_info_panel(vp: Vector2) -> void:
	var rect := Rect2(vp.x * 0.14, vp.y - _panel_h + 6.0, vp.x * 0.72, _panel_h - 22.0)
	draw_style_box(_panel_style, rect)


# ---------------- 交互 ----------------

func _on_node_focused(index: int) -> void:
	_selected = index
	_update_info(index)
	for i in _nodes.size():
		var node: LevelNode = _nodes[i]
		node.selected = (i == index)
		node.queue_redraw()


func _on_node_pressed(index: int) -> void:
	_selected = index
	_update_info(index)
	GameManager.start_level(index)
	get_tree().change_scene_to_file("res://scenes/Level%d.tscn" % (index + 1))


func _update_info(index: int) -> void:
	var state := "已通关 ✓" if Progress.is_completed(index) else "未通关"
	_info.text = "%s　·　回溯次数 %d　·　%s" % [
		LevelManager.level_name(index),
		LevelManager.level_rewind_budget(index),
		state]


# ---------------- 设置面板 ----------------

func _open_settings() -> void:
	if is_instance_valid(_settings_panel):
		return

	# 放在独立 CanvasLayer 上（和游戏场景里的回溯面板、通关弹窗一致），
	# 否则弹窗会和关卡信息文字挤在同一层，被后面的文字盖住。
	_settings_panel = CanvasLayer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.layer = 100
	add_child(_settings_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.08, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_panel.add_child(center)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.14, 0.21, 0.98)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(0.48, 0.68, 0.92, 0.85)
	sb.set_border_width_all(3)
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 26.0
	sb.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	vbox.add_child(title)

	var sfx := Button.new()
	sfx.text = "音效：%s" % ("开" if load_sfx_on() else "关")
	sfx.custom_minimum_size = Vector2(220.0, 52.0)
	sfx.focus_mode = Control.FOCUS_NONE
	sfx.add_theme_font_size_override("font_size", 20)
	sfx.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	sfx.add_theme_stylebox_override("normal", _button_style(Color(0.18, 0.30, 0.42, 0.95)))
	sfx.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.40, 0.55, 0.95)))
	sfx.add_theme_stylebox_override("pressed", _button_style(Color(0.24, 0.40, 0.55, 0.95)))
	sfx.pressed.connect(func():
		var v := not load_sfx_on()
		save_sfx_on(v)
		_apply_audio_setting()
		sfx.text = "音效：%s" % ("开" if v else "关"))
	vbox.add_child(sfx)

	var music := Button.new()
	music.text = "音乐：%s" % ("开" if load_music_on() else "关")
	music.custom_minimum_size = Vector2(220.0, 52.0)
	music.focus_mode = Control.FOCUS_NONE
	music.add_theme_font_size_override("font_size", 20)
	music.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	music.add_theme_stylebox_override("normal", _button_style(Color(0.18, 0.30, 0.42, 0.95)))
	music.add_theme_stylebox_override("hover", _button_style(Color(0.24, 0.40, 0.55, 0.95)))
	music.add_theme_stylebox_override("pressed", _button_style(Color(0.24, 0.40, 0.55, 0.95)))
	music.pressed.connect(func():
		var v := not load_music_on()
		save_music_on(v)
		Music.set_music_on(v)
		music.text = "音乐：%s" % ("开" if v else "关"))
	vbox.add_child(music)

	# 音乐署名：CC BY 4.0 要求署名可被找到，放在设置面板里最稳。
	var credit := Label.new()
	credit.custom_minimum_size = Vector2(220.0, 0.0)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.text = "音乐：Kevin MacLeod (incompetech.com)\nLicensed under CC BY 4.0"
	credit.add_theme_font_size_override("font_size", 11)
	credit.add_theme_color_override("font_color", Color(0.62, 0.72, 0.86))
	vbox.add_child(credit)

	var close := Button.new()
	close.text = "返回"
	close.custom_minimum_size = Vector2(220.0, 52.0)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	close.add_theme_stylebox_override("normal", _button_style(Color(0.22, 0.36, 0.30, 0.95)))
	close.add_theme_stylebox_override("hover", _button_style(Color(0.28, 0.46, 0.38, 0.95)))
	close.add_theme_stylebox_override("pressed", _button_style(Color(0.28, 0.46, 0.38, 0.95)))
	close.pressed.connect(_close_settings)
	vbox.add_child(close)


func _button_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.52, 0.72, 0.92, 0.85)
	sb.set_border_width_all(2)
	return sb


func _close_settings() -> void:
	if is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null
