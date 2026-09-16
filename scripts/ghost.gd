class_name Ghost
extends Node2D
## "过去的你"：重玩一关时，把上一次通关的你**半透明地重演一遍**。
## 位置由存档里的行动轨迹（地图号, x, y）驱动，每一步往下一格缓动。
## 幽灵在你看不到的那张地图上时会先藏起来（Level 当前只画一张图）。
## 它只是"影子"，不参与任何玩法判定。

const TEX := "res://assets/art/pixel/player_front.png"
const DISP := 1.42

var _level: LevelManager
var _tex: Texture2D
var _timer: Timer

var path: Array = []            # Array[Vector3i]（地图号, x, y）
var _idx := 0
var interval := 0.36


func setup(level: LevelManager, path_: Array, step := 0.36) -> void:
	_level = level
	path = path_
	interval = step
	_tex = load(TEX)
	if _level == null or path.size() < 2:
		queue_free()
		return
	z_index = 60
	_move_to(0, true)
	_timer = Timer.new()
	_timer.wait_time = interval
	_timer.one_shot = false
	_timer.timeout.connect(_step)
	add_child(_timer)
	_timer.start()


func _step() -> void:
	_idx = (_idx + 1) % path.size()
	_move_to(_idx, false)


func _move_to(i: int, instant: bool) -> void:
	var c: Vector3i = path[i]
	var same_room: bool = (c.x == _level.current_room())
	visible = same_room
	if not same_room:
		return
	var target := _level.cell_to_world(Vector2i(c.y, c.z))
	if instant:
		position = target
	else:
		var tw := create_tween()
		tw.tween_property(self, "position", target, interval * 0.9)


func _draw() -> void:
	if _tex == null:
		return
	var s := LevelManager.CELL * DISP
	var rect := Rect2(Vector2(-s, -s) * 0.5 + Vector2(0.0, -s * 0.07), Vector2(s, s))
	# 半透明的人形 + 一圈淡淡的轮廓，和"现在的你"区分开
	draw_texture_rect(_tex, rect, false, Color(0.55, 0.86, 1.0, 0.40))
	draw_rect(rect.grow(-s * 0.16), Color(0.60, 0.90, 1.0, 0.55), false, 2.0)
