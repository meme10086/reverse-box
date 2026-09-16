class_name RewindMeter
extends Control
## 回溯点数计量条：把「剩余点数 / 总点数」画成一排小圆点。
## 实心 = 还能用，空心 = 已花掉。纯显示，不含逻辑。

const DOT_R := 7.0
const GAP := 6.0

const COLOR_ON := Color(0.55, 0.82, 1.0)
const COLOR_ON_EDGE := Color(0.22, 0.42, 0.68)
const COLOR_OFF := Color(0.30, 0.34, 0.42, 0.85)

var _left := 0
var _total := 0


func set_points(left: int, total: int) -> void:
	if left == _left and total == _total:
		return
	_left = left
	_total = total
	if is_inside_tree():
		queue_redraw()


func _draw() -> void:
	var y := size.y * 0.5
	for i in _total:
		var c := Vector2(DOT_R + i * (DOT_R * 2.0 + GAP), y)
		if i < _left:
			draw_circle(c, DOT_R + 1.5, COLOR_ON_EDGE)
			draw_circle(c, DOT_R, COLOR_ON)
			draw_circle(c - Vector2(DOT_R * 0.3, DOT_R * 0.3), DOT_R * 0.32,
				Color(1.0, 1.0, 1.0, 0.55))
		else:
			draw_circle(c, DOT_R, Color(0.0, 0.0, 0.0, 0.0))
			draw_arc(c, DOT_R, 0.0, TAU, 20, COLOR_OFF, 2.0, true)
