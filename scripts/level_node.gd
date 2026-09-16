class_name LevelNode
extends BaseButton
## 关卡格子：一个方形按钮 + 中间的大号关卡编号（1、2、3…），点一下直接进那一关。
## 状态只保留三种视觉反馈：未通关（冷色）/ 已通关（绿色 + 对勾）/ 推荐下一关（金色边框）。
## 朴素直接，不做任何装饰性动效。

signal level_focused(index: int)

const NODE_W := 104.0
const NODE_H := 104.0

const C_BG := Color(0.13, 0.18, 0.27, 0.94)
const C_BG_CLEARED := Color(0.14, 0.32, 0.24, 0.94)
const C_BG_HOVER := Color(0.20, 0.28, 0.40, 0.96)
const C_BORDER := Color(0.38, 0.50, 0.68, 0.90)
const C_BORDER_CLEARED := Color(0.42, 0.86, 0.58, 0.95)
const C_BORDER_NEXT := Color(0.98, 0.84, 0.32, 1.0)
const C_TEXT := Color(0.95, 0.97, 1.0)
const C_TEXT_CLEARED := Color(0.90, 1.0, 0.92)

# 大关色条：顶部的细色带用来一眼区分"这是第几大关"
const CHAPTER_STRIP := {
	0: Color(0.42, 0.62, 0.95),   # 大关 1：独立回溯
	1: Color(0.72, 0.55, 1.00),   # 大关 2：回溯距离受限
	2: Color(1.00, 0.72, 0.30),   # 大关 3：多地图 + 颜色
}

var level_index := 0
var selected := false
var cleared := false
var is_next := false
var star_count := 0
var best_steps := 0

var _hover := false


# 一颗五角星的顶点（外径 R、内径 r）
static func _star_pts(cx: float, cy: float, R: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI / 2.0 + i * PI / 5.0
		var rad: float = R if i % 2 == 0 else r
		pts.append(Vector2(cx + cos(ang) * rad, cy + sin(ang) * rad))
	return pts


func _ready() -> void:
	custom_minimum_size = Vector2(NODE_W, NODE_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_emit_focus)
	pressed.connect(_emit_focus)


func configure(index: int, cleared_state: bool, next_flag: bool) -> void:
	level_index = index
	cleared = cleared_state
	is_next = next_flag
	star_count = Progress.stars(index)
	best_steps = Progress.best_steps(index)
	var rooms: int = LevelManager.level_room_count(index)
	var span: int = LevelManager.level_rewind_span(index)
	var extra := ""
	if rooms > 1:
		extra += "　地图 %d 张" % rooms
	if span > 0:
		extra += "　只能回 %d 格" % span
	var star_txt := "★★★" if star_count >= 3 else ("★★☆" if star_count == 2 else ("★☆☆" if star_count == 1 else "☆☆☆"))
	var best_txt := "　最佳 %d 步" % best_steps if best_steps > 0 else ""
	tooltip_text = "%s（回溯点数 %d）%s\n%s%s" % [
		LevelManager.level_name(index), LevelManager.level_rewind_budget(index),
		extra, star_txt, best_txt]
	queue_redraw()


func _on_hover(v: bool) -> void:
	_hover = v
	if v:
		_emit_focus()
	queue_redraw()


func _emit_focus() -> void:
	level_focused.emit(level_index)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)

	# 底色
	var bg := C_BG_CLEARED if cleared else C_BG
	if _hover or selected:
		bg = C_BG_HOVER if not cleared else C_BG_CLEARED.lightened(0.10)
	draw_rect(r, bg)

	# 顶部大关色条
	var chap := level_index / 10
	if CHAPTER_STRIP.has(chap):
		draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(size.x, 5.0)), CHAPTER_STRIP[chap])

	# 边框：已通关=绿，推荐下一关=金，其余=冷灰蓝
	var border := C_BORDER_CLEARED if cleared else C_BORDER
	var bw := 3.0
	if is_next:
		border = C_BORDER_NEXT
		bw = 5.0
	elif selected:
		bw = 4.0
	draw_rect(r, border, false, bw)

	# 关卡编号（正中）
	var font := get_theme_default_font()
	if font != null:
		var fs := 48
		var txt := str(level_index + 1)
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := Vector2((size.x - tw.x) * 0.5, size.y * 0.5 + fs * 0.35)
		draw_string(font, pos + Vector2(1.0, 1.0), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.03, 0.05, 0.09, 0.75))
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			C_TEXT_CLEARED if cleared else C_TEXT)

	# 已通关：右下角小对勾
	if cleared:
		var p := Vector2(size.x - 20.0, size.y - 18.0)
		draw_circle(p, 11.0, Color(0.18, 0.56, 0.31))
		draw_polyline(PackedVector2Array([
			p + Vector2(-5.5, 0.0),
			p + Vector2(-1.5, 4.0),
			p + Vector2(6.0, -4.5),
		]), Color(0.94, 1.0, 0.95), 3.0, true)

	# 星级：左下角一排小五角星（金 = 拿到，暗 = 没拿到）
	for k in 3:
		var cx := 14.0 + k * 17.0
		var col := Color(1.0, 0.82, 0.28) if k < star_count else Color(1, 1, 1, 0.16)
		draw_polygon(_star_pts(cx, size.y - 16.0, 7.5, 3.2), [col])
		if k < star_count:
			draw_polyline(_star_pts(cx, size.y - 16.0, 7.5, 3.2),
				Color(0.55, 0.38, 0.06), 1.0, true)
