extends Node2D
## 游戏场景根。只做「场景层」的三件事：
##   1) 加载关卡并驱动 HUD（关卡名 / 步数 / 回溯点数量表）
##   2) 把触屏操作（滑动 + 虚拟方向键）翻译成移动指令
##   3) 通关弹窗与关卡进度记录
## 玩法规则一律在 GameManager，本文件不重复实现规则。

@export var level_index := 1
@export var force_touch_controls := false   # 桌面调试时可强制显示触屏按钮

const SWIPE_MIN := 44.0

const COLOR_TEXT := Color(0.93, 0.96, 1.0)
const COLOR_TEXT_DIM := Color(0.62, 0.70, 0.84)
const TEX_DIR := "res://assets/art/pixel/"

@onready var _level_label: Label = $HUD/LevelLabel
@onready var _steps_label: Label = $HUD/StepsLabel
@onready var _rewind_label: Label = $HUD/RewindLabel
@onready var _camera: Camera2D = $Camera2D

var _meter: RewindMeter
var _hint_label: Label
var _touch_root: Control
var _overlay: Control
var _overlay_title: Label
var _overlay_detail: Label
var _overlay_buttons: HBoxContainer
var _overlay_stars: StarStrip
var hint_stage := 0                 # 分层提示：0 关 / 1 文字方向 / 2 标出关键点
var _hint_panel: PanelContainer
var _hint_text: Label
var _ghost: Ghost                   # "过去的你"（仅当本关有历史最佳通关记录时才有）
var _preview_room := -1             # 回溯落点预览：当前标出的地图
var _preview_cell := Vector2i(-1, -1)
var _touch_start := Vector2.ZERO
var _touch_active := false


# 通关界面里那一排五角星（金 = 拿到，暗 = 没拿到）
class StarStrip:
	extends Control
	var count := 0
	func _init(n := 0) -> void:
		count = n
		custom_minimum_size = Vector2(76.0, 30.0)
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		for k in 3:
			var cx := 17.0 + k * 21.0
			var col := Color(1.0, 0.82, 0.28) if k < count else Color(1, 1, 1, 0.16)
			draw_polygon(LevelNode._star_pts(cx, 15.0, 10.0, 4.2), [col])
	func refresh(n: int) -> void:
		count = n
		queue_redraw()
var _touch_wanted := false
var _panel: RewindPanel
var _rewind_bar: Control
var _rewind_obj_btn: Button
var _rewind_dist_btns: Array = []
var _guide_label: Label
var _guide_steps: Array = []
var _guide_index := 0
var _room_label: Label
var _bottom_reserve := 108.0


func _ready() -> void:
	hint_stage = 0
	Music.play_level()
	GameManager.start_level(level_index)
	GameManager.completed.connect(_on_completed)
	_build_hud_extras()
	_build_rewind_bar()
	_build_guide()
	_build_hint_panel()
	_build_rewind_panel()
	_build_back_button()
	_build_touch_controls()
	_build_victory_overlay()
	_build_ghost()
	_fit_camera()
	get_viewport().size_changed.connect(_layout_touch_controls)
	get_viewport().size_changed.connect(_fit_camera)


# 让棋盘自动占满可用画面：横屏 / 竖屏 / 平板都不会太小或溢出。
# 底部还要放 HUD（提示 / 引导 / 距离回溯按钮条），所以先给它留出高度，再把棋盘整体上移。
func _fit_camera() -> void:
	var level := GameManager.get_node_or_null("Level") as LevelManager
	if level == null or _camera == null or level.width <= 0 or level.height <= 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var world_w := level.width * LevelManager.CELL
	var world_h := level.height * LevelManager.CELL
	var margin := 1.24
	var avail_h := maxf(120.0, vp.y - _bottom_reserve)
	var z := minf(vp.x / (world_w * margin), avail_h / (world_h * margin))
	z = clampf(z, 0.6, 3.2)
	_camera.zoom = Vector2(z, z)
	# 让棋盘在"扣掉底部 UI 之后"的那块区域里居中
	_camera.position = Vector2(0.0, _bottom_reserve * 0.5 / z)


# 底部 UI 需要多少高度：底部信息栏 + 距离回溯按钮条 + 新手引导
func _needed_bottom_reserve() -> float:
	var r := 108.0
	if _rewind_bar != null and _rewind_bar.visible:
		r += 62.0
	if _guide_label != null and _guide_label.visible:
		r += 58.0
	return r


func _sync_bottom_reserve() -> void:
	var want := _needed_bottom_reserve()
	if absf(want - _bottom_reserve) < 1.0:
		return
	_bottom_reserve = want
	_fit_camera()


func _process(_delta: float) -> void:
	_level_label.text = LevelManager.level_name(GameManager.current_level)
	_steps_label.text = "步数：%d" % GameManager.move_count
	_rewind_label.text = "回溯：%d / %d" % [GameManager.rewind_left, GameManager.rewind_budget]
	_update_rewind_preview()
	if _meter != null:
		_meter.set_points(GameManager.rewind_left, GameManager.rewind_budget)
	if _panel != null:
		_panel.refresh()
	if _touch_root != null:
		var show := _touch_wanted and not GameManager.rewind_mode
		var pad := _touch_root.get_node_or_null("DPad")
		if pad != null:
			pad.visible = show
		var rb := _touch_root.get_node_or_null("RewindButton")
		if rb != null:
			rb.visible = show
	if _hint_label != null:
		var hint: String = LevelManager.level_hint(GameManager.current_level)
		_hint_label.text = hint
		_hint_label.visible = hint != "" and not GameManager.rewind_mode
	_update_room_label()
	_update_rewind_bar()
	_update_guide()
	_sync_bottom_reserve()


# 多地图关卡：左上角显示"地图 2 / 3"，单地图关卡隐藏
func _update_room_label() -> void:
	if _room_label == null:
		return
	var lv := GameManager.get_node_or_null("Level") as LevelManager
	var rc: int = lv.room_count() if lv != null else 1
	_room_label.visible = rc > 1 and not GameManager.rewind_mode
	if rc > 1:
		_room_label.text = "地图 %d / %d" % [lv.current_room() + 1, rc]


# ---------------- 距离回溯按钮条（第二大关：地图下方） ----------------

# 只在"有回溯距离上限"的关卡出现：一颗对象按钮 + 一排 ↺N 格 按钮。
# 按一下就立刻把"当前选中的对象"送回 N 步之前，不用打开面板。
func _build_rewind_bar() -> void:
	_rewind_bar = Control.new()
	_rewind_bar.name = "RewindBar"
	_rewind_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_rewind_bar.offset_top = -172.0
	_rewind_bar.offset_bottom = -112.0
	_rewind_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_rewind_bar)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewind_bar.add_child(row)

	_rewind_obj_btn = _make_button("对象：玩家", Vector2(148.0, 50.0))
	_rewind_obj_btn.pressed.connect(_on_cycle_object)
	row.add_child(_rewind_obj_btn)

	for n in 3:
		var b := _make_button("↺ %d 格" % (n + 1), Vector2(112.0, 50.0), true)
		b.pressed.connect(_on_distance_button.bind(n + 1))
		row.add_child(b)
		_rewind_dist_btns.append(b)

	_rewind_bar.visible = false


func _on_distance_button(n: int) -> void:
	GameManager.try_span_rewind(n)


func _on_cycle_object() -> void:
	GameManager.cycle_object()


func _update_rewind_bar() -> void:
	if _rewind_bar == null:
		return
	var span: int = GameManager.rewind_span
	var should_show := span > 0 and not GameManager.is_completed() and not GameManager.rewind_mode
	if _rewind_bar.visible != should_show:
		_rewind_bar.visible = should_show
	if not should_show:
		return
	if _rewind_obj_btn != null:
		_rewind_obj_btn.text = "对象：%s" % GameManager.object_name(GameManager.selected_object_index())
	var maxd: int = GameManager.max_rewind_distance()
	for i in _rewind_dist_btns.size():
		var b: Button = _rewind_dist_btns[i]
		var n := i + 1
		b.visible = n <= span
		b.disabled = not (n <= maxd and GameManager.rewind_left > 0)


# ---------------- 新手引导（第一条教学关的分步提示） ----------------

func _build_guide() -> void:
	_guide_steps = LevelManager.level_guide(GameManager.current_level)
	_guide_index = 0
	_guide_label = Label.new()
	_guide_label.name = "GuideLabel"
	_guide_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_label.add_theme_font_size_override("font_size", 18)
	_guide_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.70))
	_guide_label.add_theme_color_override("font_outline_color", Color(0.07, 0.05, 0.02))
	_guide_label.add_theme_constant_override("outline_size", 6)
	_guide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_guide_label.visible = false
	$HUD.add_child(_guide_label)


func _step_done(key: String) -> bool:
	match key:
		"move":
			return GameManager.move_count > 0
		"push":
			return GameManager.push_count > 0
		"panel":
			return GameManager.panel_opens > 0
		"pick_box":
			return GameManager.panel_opens > 0 and GameManager.target_kind == GameManager.KIND_BOX
		"target_box":
			# 按钮模式下选中了箱子（不经过面板）
			return GameManager.target_kind == GameManager.KIND_BOX
		"rewind":
			return GameManager.rewinds_used > 0
		"win":
			return GameManager.is_completed()
	return false


func _update_guide() -> void:
	if _guide_label == null:
		return
	if _guide_steps.is_empty():
		_guide_label.visible = false
		return
	# 已完成的条件自动跳过；全部完成就不再显示
	while _guide_index < _guide_steps.size():
		var st: Dictionary = _guide_steps[_guide_index]
		if not _step_done(String(st.get("done", ""))):
			break
		_guide_index += 1
	if _guide_index >= _guide_steps.size():
		_guide_label.visible = false
		return
	var bar_on := _rewind_bar != null and _rewind_bar.visible
	_guide_label.offset_top = -226.0 if bar_on else -164.0
	_guide_label.offset_bottom = -182.0 if bar_on else -120.0
	_guide_label.visible = not GameManager.rewind_mode
	_guide_label.text = "▸ " + String(_guide_steps[_guide_index].get("tip", ""))


# ---------------- HUD ----------------

func _build_hud_extras() -> void:
	_level_label.add_theme_font_size_override("font_size", 22)
	_level_label.add_theme_color_override("font_color", COLOR_TEXT)
	_steps_label.add_theme_font_size_override("font_size", 18)
	_steps_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	_rewind_label.add_theme_font_size_override("font_size", 18)
	_rewind_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)

	_meter = RewindMeter.new()
	_meter.name = "RewindMeter"
	_meter.position = Vector2(96.0, 88.0)
	_meter.size = Vector2(260.0, 24.0)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_meter)

	# 新手提示（仅教学关显示，内容来自 LevelManager.level_hint）
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint_label.offset_top = -104.0
	_hint_label.offset_bottom = -60.0
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 17)
	_hint_label.add_theme_color_override("font_color", Color(0.87, 0.94, 1.0))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.12))
	_hint_label.add_theme_constant_override("outline_size", 6)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HUD.add_child(_hint_label)

	# 地图指示（多地图关卡才显示）：地图 2 / 3
	_room_label = Label.new()
	_room_label.name = "RoomLabel"
	_room_label.offset_left = 16.0
	_room_label.offset_top = 120.0
	_room_label.offset_right = 320.0
	_room_label.offset_bottom = 152.0
	_room_label.add_theme_font_size_override("font_size", 20)
	_room_label.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0))
	_room_label.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.12))
	_room_label.add_theme_constant_override("outline_size", 6)
	_room_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_room_label.visible = false
	$HUD.add_child(_room_label)


func _build_back_button() -> void:
	var btn := _make_button("‹ 关卡地图", Vector2(150.0, 44.0))
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-166.0, 12.0)
	btn.pressed.connect(_goto_menu)
	$HUD.add_child(btn)

	var re := _make_button("↺ 重开 (T)", Vector2(150.0, 44.0))
	re.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	re.position = Vector2(-332.0, 12.0)
	re.pressed.connect(_restart_current)
	$HUD.add_child(re)


# ---------------- 回溯落点预览 ----------------
# 回溯面板里选中某个历史位置时，在地图上直接画出"它会落到哪"。
# 目的是把"选错 → 重开"变成"先看清 → 再决定"，让思考替代试错。

func _update_rewind_preview() -> void:
	var level := GameManager.get_node_or_null("Level") as LevelManager
	if level == null:
		return
	if not GameManager.rewind_mode:
		if _preview_room >= 0:
			_preview_room = -1
			if hint_stage > 0:
				_apply_hint()          # 退出面板后把 H 提示还回去
			else:
				level.clear_hints()
		return
	var trail: TimeTrail = GameManager.trail_of_object(GameManager.selected_object_index())
	if trail == null or trail.past_count() <= 0:
		return
	var i: int = GameManager.node_index
	var c: Vector2i = trail.cell_at(i)
	var r: int = trail.room_at(i)
	if r == _preview_room and c == _preview_cell:
		return
	level.clear_hints()
	level.set_hint_cells(r, [c], Color(1.0, 0.58, 0.32, 0.95))
	_preview_room = r
	_preview_cell = c


# ---------------- 幽灵回放（"过去的你"）----------------
# 本关只要有历史最佳通关记录，就把那一次的"你"半透明重演出来，和现在的你一起走。
# 幽灵只是个影子：半透明、不参与玩法、走到别的地图时先藏起来。

func _build_ghost() -> void:
	var level := GameManager.get_node_or_null("Level") as LevelManager
	if level == null:
		return
	var path: Array = Progress.ghost_path(GameManager.current_level)
	if path.size() < 2:
		print("[ReverseBox] 幽灵回放：本关没有历史轨迹（%d）" % path.size())
		return
	print("[ReverseBox] 幽灵回放：本关有 %d 步历史轨迹" % path.size())
	_ghost = Ghost.new()
	level.add_child(_ghost)
	_ghost.setup(level, path)


# ---------------- 分层提示（按 H）----------------
# 第一层：方向性文字（不给答案，只点破"要想通的是什么"）。
# 第二层：在地图上把关键点标出来（传送门 + 目标地砖）。
# 再按一次 H 关掉。它逼你想，但不会让你卡死退游戏。

func _build_hint_panel() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint_panel.anchor_left = 0.5
	_hint_panel.anchor_right = 0.5
	_hint_panel.offset_left = -330.0
	_hint_panel.offset_right = 330.0
	_hint_panel.offset_top = 10.0
	_hint_panel.visible = false
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.18, 0.94)
	sb.border_color = Color(0.45, 0.72, 0.62, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	_hint_panel.add_theme_stylebox_override("panel", sb)
	_hint_text = Label.new()
	_hint_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_text.add_theme_font_size_override("font_size", 17)
	_hint_text.add_theme_color_override("font_color", COLOR_TEXT)
	_hint_panel.add_child(_hint_text)
	$HUD.add_child(_hint_panel)


func _cycle_hint() -> void:
	hint_stage = (hint_stage + 1) % 3
	_apply_hint()


func _apply_hint() -> void:
	var level := GameManager.get_node_or_null("Level") as LevelManager
	if level == null:
		return
	if hint_stage == 0:
		level.clear_hints()
		_hint_panel.visible = false
		return

	var lvl: int = GameManager.current_level
	var hint: String = LevelManager.level_hint(lvl)
	if hint == "":
		# 没有定制提示的关：给一句"这关要想通什么"的通用方向
		if lvl >= 15:
			hint = "想通这一步：走廊只有一格宽，你绕不到箱子另一边 —— 把它推到尽头，再【回溯箱子】。"
		else:
			hint = "想通这一步：有些时候，正确的做法是把已经推出去的箱子【回溯】回它走过的某个位置。"

	if hint_stage == 1:
		level.clear_hints()
		_hint_text.text = hint + "\n—— 再按 H 在地图上标出关键点，Esc/H 关闭"
		_hint_panel.visible = true
	elif hint_stage == 2:
		# 标出所有地图上的传送门（青）与目标地砖（金）
		for r in level.room_count():
			var pcs: Array = level.portal_cells_in(r)
			if not pcs.is_empty():
				level.set_hint_cells(r, pcs, Color(0.45, 0.90, 1.00, 0.95))
			var gds: Array = level.rooms[r]["goals"]
			if not gds.is_empty():
				level.set_hint_cells(r, gds, Color(1.00, 0.85, 0.30, 0.95))
		_hint_text.text = "青色圈 = 传送门　·　金色点 = 目标地砖\n" + hint
		_hint_panel.visible = true


# 立即重开本关：不消耗回溯资源，清空所有对象轨迹（赛季研究关卡用）
func _restart_current() -> void:
	var layer := get_node_or_null("VictoryLayer") as CanvasLayer
	if layer != null:
		layer.visible = false
	GameManager.restart_level()
	_fit_camera()


func _build_rewind_panel() -> void:
	var cl := CanvasLayer.new()
	cl.name = "RewindUI"
	cl.layer = 110
	add_child(cl)
	_panel = RewindPanel.new()
	_panel.name = "RewindPanel"
	cl.add_child(_panel)


func _goto_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/start_screen.tscn")


# ---------------- 触屏操作（滑动 + 虚拟方向键） ----------------

func _build_touch_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TouchControls"
	layer.layer = 60
	add_child(layer)

	_touch_root = Control.new()
	_touch_root.name = "Root"
	_touch_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_touch_root)

	var pad := Control.new()
	pad.name = "DPad"
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_root.add_child(pad)

	var defs := [
		["▲", Vector2i(0, -1), Vector2(0.0, -1.0)],
		["▼", Vector2i(0, 1), Vector2(0.0, 1.0)],
		["◀", Vector2i(-1, 0), Vector2(-1.0, 0.0)],
		["▶", Vector2i(1, 0), Vector2(1.0, 0.0)],
	]
	for d in defs:
		var b := _make_button(d[0], Vector2(64.0, 64.0))
		b.name = "Dir_%s" % str(d[1])
		b.set_meta("dir", d[1])
		b.set_meta("offset", d[2])
		b.button_down.connect(_on_dir_button.bind(d[1]))
		pad.add_child(b)

	var rb := _make_button("回溯\nR", Vector2(88.0, 88.0), true)
	rb.name = "RewindButton"
	rb.button_down.connect(_on_rewind_button)
	_touch_root.add_child(rb)

	_touch_wanted = force_touch_controls or DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile")
	pad.visible = _touch_wanted
	rb.visible = _touch_wanted
	_layout_touch_controls()


func _layout_touch_controls() -> void:
	if _touch_root == null:
		return
	var vp := get_viewport().get_visible_rect().size

	var pad := _touch_root.get_node_or_null("DPad") as Control
	if pad != null:
		var step := 68.0
		var origin := Vector2(104.0, vp.y - 104.0)
		pad.position = Vector2.ZERO
		pad.size = vp
		for child in pad.get_children():
			var b := child as Control
			if b == null:
				continue
			var off: Vector2 = b.get_meta("offset")
			b.size = Vector2(64.0, 64.0)
			b.position = origin + off * step - b.size * 0.5

	var rb := _touch_root.get_node_or_null("RewindButton") as Control
	if rb != null:
		rb.size = Vector2(88.0, 88.0)
		rb.position = Vector2(vp.x - 140.0, vp.y - 148.0)


func _on_dir_button(dir: Vector2i) -> void:
	GameManager.try_move_player(dir)


func _on_rewind_button() -> void:
	GameManager.toggle_rewind()


# 触屏滑动：按住拖动，每越过一个阈值就走一格（连续拖动可连续走）
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_touch_start = t.position
			_touch_active = true
		else:
			_touch_active = false
		return

	if event is InputEventScreenDrag and _touch_active:
		var d := (event as InputEventScreenDrag)
		var delta := d.position - _touch_start
		if delta.length() < SWIPE_MIN:
			return
		if absf(delta.x) > absf(delta.y):
			GameManager.try_move_player(Vector2i(signi(roundi(delta.x)), 0))
		else:
			GameManager.try_move_player(Vector2i(0, signi(roundi(delta.y))))
		_touch_start = d.position
		return

	# 键盘：回溯模式里 Esc 先退出回溯；T / Backspace 立即重开本关；H 分层提示
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_ESCAPE:
			if GameManager.rewind_mode:
				GameManager.toggle_rewind()
			else:
				_goto_menu()
		elif k == KEY_T or k == KEY_BACKSPACE:
			_restart_current()
		elif k == KEY_H:
			_cycle_hint()


# ---------------- 通关弹窗 ----------------

func _build_victory_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VictoryLayer"
	layer.layer = 120
	layer.visible = false
	add_child(layer)

	_overlay = Control.new()
	_overlay.name = "Victory"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.09, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.12, 0.19, 0.98)
	sb.set_corner_radius_all(4)
	sb.border_color = Color(0.45, 0.78, 0.60, 0.95)
	sb.set_border_width_all(4)
	sb.content_margin_left = 44.0
	sb.content_margin_right = 44.0
	sb.content_margin_top = 30.0
	sb.content_margin_bottom = 30.0
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# 通关对勾徽章（像素贴图）
	var badge := TextureRect.new()
	badge.texture = load(TEX_DIR + "badge_clear.png")
	badge.custom_minimum_size = Vector2(96.0, 96.0)
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(badge)

	_overlay_title = Label.new()
	_overlay_title.text = "关卡完成！"
	_overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_title.add_theme_font_size_override("font_size", 40)
	_overlay_title.add_theme_color_override("font_color", Color(0.78, 0.98, 0.84))
	vbox.add_child(_overlay_title)

	_overlay_stars = StarStrip.new()
	vbox.add_child(_overlay_stars)

	_overlay_detail = Label.new()
	_overlay_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_detail.add_theme_font_size_override("font_size", 20)
	_overlay_detail.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(_overlay_detail)

	_overlay_buttons = HBoxContainer.new()
	_overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_buttons.add_theme_constant_override("separation", 14)
	vbox.add_child(_overlay_buttons)

	layer.visible = false


func _on_completed() -> void:
	Progress.mark_completed(GameManager.current_level)
	_show_victory()


func _show_victory() -> void:
	var layer := get_node_or_null("VictoryLayer") as CanvasLayer
	if layer == null:
		return

	var lvl: int = GameManager.current_level
	var stars: int = Progress.stars(lvl)
	if _overlay_stars != null:
		_overlay_stars.refresh(stars)
	match stars:
		3:
			_overlay_title.text = "三星达成！"
			_overlay_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.40))
		_:
			_overlay_title.text = "关卡完成！"
			_overlay_title.add_theme_color_override("font_color", Color(0.78, 0.98, 0.84))

	# 本次刷新了哪些纪录（步数 / 回溯 / 首次）
	var brk: Dictionary = GameManager.last_break
	var notes: Array = []
	if brk.get("first", false):
		notes.append("首次通关")
	if brk.get("steps", false):
		notes.append("刷新最短步数")
	if brk.get("rewinds", false):
		notes.append("刷新最少回溯")
	var extra := ""
	if not notes.is_empty():
		extra = "\n" + " · ".join(notes)
	_overlay_detail.text = "步数 %d（目标 %d）　·　回溯 %d 次（目标 %d 次）%s" % [
		GameManager.move_count, LevelManager.level_par_steps(lvl),
		GameManager.rewinds_used, GameManager.par_rewinds, extra]

	for c in _overlay_buttons.get_children():
		_overlay_buttons.remove_child(c)
		c.queue_free()

	var again := _make_button("再玩一次", Vector2(150.0, 52.0), true)
	again.pressed.connect(_restart_level)
	_overlay_buttons.add_child(again)

	if GameManager.current_level + 1 < LevelManager.level_count():
		var nxt := _make_button("下一关 ▶", Vector2(160.0, 52.0), true)
		nxt.pressed.connect(func(): _goto_level(GameManager.current_level + 1))
		_overlay_buttons.add_child(nxt)

	var menu := _make_button("返回地图", Vector2(150.0, 52.0))
	menu.pressed.connect(_goto_menu)
	_overlay_buttons.add_child(menu)

	layer.visible = true


# 简单评级：不用回溯点数为 S，用掉 ≤3 点为 A，其余普通
# 评级看「回溯用量」：达到设计最优 = S，多 1 次 = A，多 2 次 = B，再多 = C
func _last_grade() -> String:
	var used: int = GameManager.rewinds_used
	var par: int = GameManager.par_rewinds
	if used <= par:
		return "S"
	if used <= par + 1:
		return "A"
	if used <= par + 2:
		return "B"
	return "C"


func _restart_level() -> void:
	var layer := get_node_or_null("VictoryLayer") as CanvasLayer
	if layer != null:
		layer.visible = false
	GameManager.start_level(GameManager.current_level)
	_fit_camera()


func _goto_level(index: int) -> void:
	GameManager.start_level(index)
	get_tree().change_scene_to_file("res://scenes/Level%d.tscn" % (index + 1))


# ---------------- 小工具 ----------------

func _make_button(text: String, sz: Vector2, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = sz
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(clampf(sz.y * 0.42, 16.0, 24.0)))
	b.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	b.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.14))
	b.add_theme_constant_override("outline_size", 5)
	b.add_theme_stylebox_override("normal", _btn_sb(false, primary))
	b.add_theme_stylebox_override("hover", _btn_sb(true, primary))
	b.add_theme_stylebox_override("pressed", _btn_sb(true, primary))
	b.add_theme_stylebox_override("focus", _btn_sb(false, primary))
	return b


# 像素风按钮样式：方角 + 粗描边。
# 不用贴图做九宫格——按钮实际尺寸远小于贴图，9-slice 会把像素装饰拉伸糊掉。
func _btn_sb(pressed: bool, primary: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if primary:
		sb.bg_color = Color(0.10, 0.30, 0.24, 0.97) if pressed else Color(0.14, 0.40, 0.32, 0.97)
		sb.border_color = Color(0.45, 0.92, 0.62, 0.95)
	else:
		sb.bg_color = Color(0.11, 0.20, 0.32, 0.97) if pressed else Color(0.15, 0.26, 0.40, 0.97)
		sb.border_color = Color(0.42, 0.72, 0.95, 0.90)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(3)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb
