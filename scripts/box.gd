class_name Box
extends Node2D
## 单个箱子。只负责「我在哪一格、滑到哪一格、有没有归位」。
## 不决定能不能推；能否推由 GameManager.try_move_player() 裁决。
## 移动为插值滑动（move_toward），gliding 为真表示动画尚未结束。
## 显示：像素贴图（常态木箱 / 归位态绿箱），素材在 assets/art/pixel/。

const SPEED := 480.0
const DISP := 1.06              # 显示尺寸 = LevelManager.CELL * DISP
const TEX_DIR := "res://assets/art/pixel/"

var cell := Vector2i.ZERO
var room := 0                 # 所在地图（单地图关卡恒为 0）
var color := 0                # 箱子颜色（0 = 无色；1/2/3 = 甲乙丙）
var on_goal := false
var _target := Vector2.ZERO
var _tex: Texture2D
var _tex_goal: Texture2D
var _loaded := false


func _ready() -> void:
	_load_textures()


func _apply_color_tint() -> void:
	# 彩色箱子：贴图上色 + 一圈同色描边。
	# 只靠 modulate 会"乘"在木箱贴图上，紫色会变成暗红 —— 所以描边才是主要的颜色标识。
	match color:
		1:
			modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.72, 0.45, 1.00), 0.55)   # 紫
		2:
			modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.00, 0.78, 0.20), 0.55)   # 橙黄
		3:
			modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.35, 0.95, 0.50), 0.55)   # 绿
		_:
			modulate = Color(1, 1, 1)
	if is_inside_tree():
		queue_redraw()


# 这个箱子的"标识色"（描边与顶上圆点用它，不参与贴图乘法）
func color_value() -> Color:
	match color:
		1:
			return Color(0.72, 0.45, 1.00)
		2:
			return Color(1.00, 0.78, 0.20)
		3:
			return Color(0.35, 0.95, 0.50)
		_:
			return Color(1, 1, 1)


func _load_textures() -> void:
	if _loaded:
		return
	_loaded = true
	_tex = load(TEX_DIR + "box.png")
	_tex_goal = load(TEX_DIR + "box_on_goal.png")


func init(start_cell: Vector2i, world_pos: Vector2, start_on_goal: bool,
		start_room := 0, start_color := 0) -> void:
	cell = start_cell
	room = start_room
	color = start_color
	on_goal = start_on_goal
	_apply_color_tint()
	_target = world_pos
	position = world_pos
	if is_inside_tree():
		queue_redraw()


func move_to(new_cell: Vector2i, world_pos: Vector2, new_on_goal: bool) -> void:
	cell = new_cell
	_target = world_pos
	on_goal = new_on_goal
	if is_inside_tree():
		queue_redraw()


# 时间回溯回放：瞬间归位（不走滑动动画），并恢复归位状态
func snap_to(new_cell: Vector2i, world_pos: Vector2, new_on_goal: bool) -> void:
	cell = new_cell
	_target = world_pos
	position = world_pos
	on_goal = new_on_goal
	if is_inside_tree():
		queue_redraw()


func gliding() -> bool:
	return position.distance_to(_target) > 0.5


func _process(delta: float) -> void:
	if not gliding():
		return
	position = position.move_toward(_target, SPEED * delta)
	if not gliding():
		position = _target


func _draw() -> void:
	if not _loaded:
		_load_textures()
	var tex: Texture2D = _tex_goal if on_goal else _tex
	if tex == null:
		return
	var s := LevelManager.CELL * DISP
	var rect := Rect2(Vector2(-s, -s) * 0.5, Vector2(s, s))
	draw_texture_rect(tex, rect, false)
	# 彩色箱子：加一圈同色描边 + 顶上圆点，颜色一眼可辨
	if color != 0:
		var col := color_value()
		draw_rect(rect.grow(-s * 0.10), col, false, 4.0)
		draw_circle(Vector2(0.0, -s * 0.32), s * 0.085, col)
