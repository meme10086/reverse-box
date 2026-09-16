class_name Player
extends Node2D
## 玩家。负责两件事：把键盘输入翻译成方向、把「我想往这走」交给 GameManager 裁决。
## 走不走得动、箱子推不推得动，全部由 GameManager 决定，本类不含规则判断。
## 显示：像素贴图（四方向 + 8 帧走路 + 4 帧推箱），素材在 assets/art/pixel/。

const SPEED := 480.0
const DISP := 1.42              # 显示尺寸 = LevelManager.CELL * DISP
const TEX_DIR := "res://assets/art/pixel/"
const WALK_FPS := 11.0
const PUSH_TIME := 0.30

var cell := Vector2i.ZERO
var room := 0                 # 所在地图（单地图关卡恒为 0）

var _target := Vector2.ZERO
var _game_manager: Node
var _dir := Vector2i(0, 1)       # 朝向：默认朝下（正面）
var _walk_t := 0.0               # 走路动画计时
var _push_t := 0.0               # 推箱动作剩余时间
var _flip := false               # 本次绘制是否水平翻转（侧视帧朝左时用）
var _tex_dirs := {}
var _tex_walk: Array = []
var _tex_push: Array = []
var _loaded := false


func _ready() -> void:
	_load_textures()
	_game_manager = get_node_or_null("/root/GameManager")


func _load_textures() -> void:
	if _loaded:
		return
	_loaded = true
	_tex_dirs["front"] = load(TEX_DIR + "player_front.png")
	_tex_dirs["back"] = load(TEX_DIR + "player_back.png")
	_tex_dirs["left"] = load(TEX_DIR + "player_left.png")
	_tex_dirs["right"] = load(TEX_DIR + "player_right.png")
	for i in 8:
		_tex_walk.append(load(TEX_DIR + "player_walk_%d.png" % (i + 1)))
	for i in 4:
		_tex_push.append(load(TEX_DIR + "player_push_%d.png" % (i + 1)))


func init(start_cell: Vector2i, world_pos: Vector2) -> void:
	cell = start_cell
	_target = world_pos
	position = world_pos
	if is_inside_tree():
		queue_redraw()


# 移动。pushed=true 表示这一次是「推着箱子走」，会播放推箱动作。
func move_to(new_cell: Vector2i, world_pos: Vector2, pushed := false) -> void:
	var d := new_cell - cell
	if d != Vector2i.ZERO:
		_dir = d
	cell = new_cell
	_target = world_pos
	if pushed:
		_push_t = PUSH_TIME
	if is_inside_tree():
		queue_redraw()


# 时间回溯回放：瞬间归位（不走滑动动画）
func snap_to(new_cell: Vector2i, world_pos: Vector2) -> void:
	cell = new_cell
	_target = world_pos
	position = world_pos
	_push_t = 0.0
	if is_inside_tree():
		queue_redraw()


func gliding() -> bool:
	return position.distance_to(_target) > 0.5


func _process(delta: float) -> void:
	if _push_t > 0.0:
		_push_t = maxf(0.0, _push_t - delta)

	if gliding():
		position = position.move_toward(_target, SPEED * delta)
		if not gliding():
			position = _target
		_walk_t += delta
		queue_redraw()
		return

	if _game_manager == null:
		return

	var dir := _read_dir()
	if dir != Vector2i.ZERO:
		_game_manager.try_move_player(dir)


func _read_dir() -> Vector2i:
	# 只取按下那一帧，避免长按连发
	if Input.is_action_just_pressed("move_up"):
		return Vector2i(0, -1)
	if Input.is_action_just_pressed("move_down"):
		return Vector2i(0, 1)
	if Input.is_action_just_pressed("move_left"):
		return Vector2i(-1, 0)
	if Input.is_action_just_pressed("move_right"):
		return Vector2i(1, 0)
	return Vector2i.ZERO


# 选贴图。同时更新 _flip（侧视帧朝左时翻转）。
func _pick_texture() -> Texture2D:
	_flip = false

	# 1) 推箱中
	if _push_t > 0.0 and not _tex_push.is_empty():
		var k := 1.0 - _push_t / PUSH_TIME
		var idx := clampi(int(k * float(_tex_push.size())), 0, _tex_push.size() - 1)
		_flip = _dir.x < 0
		return _tex_push[idx]

	# 2) 水平移动 -> 侧视走路帧（只有朝右的，朝左翻转）
	if gliding() and _dir.x != 0 and not _tex_walk.is_empty():
		var idx2 := int(_walk_t * WALK_FPS) % _tex_walk.size()
		_flip = _dir.x < 0
		return _tex_walk[idx2]

	# 3) 静止 / 垂直移动 -> 按朝向用四方向站立帧
	if _dir.y < 0:
		return _tex_dirs.get("back", null)
	if _dir.y > 0:
		return _tex_dirs.get("front", null)
	if _dir.x > 0:
		return _tex_dirs.get("right", null)
	if _dir.x < 0:
		return _tex_dirs.get("left", null)
	return _tex_dirs.get("front", null)


func _draw() -> void:
	var tex: Texture2D = _pick_texture()
	if tex == null:
		return
	var s := LevelManager.CELL * DISP
	var rect := Rect2(Vector2(-s, -s) * 0.5 + Vector2(0.0, -s * 0.07), Vector2(s, s))
	if _flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1.0, 1.0))
	draw_texture_rect(tex, rect, false)
	if _flip:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
