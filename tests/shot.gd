extends Node
## 临时工具：把某个场景跑起来、等若干帧稳定后截图存盘，然后退出。
## 仅用于开发期"看一眼 UI 长什么样"，不参与游戏正式运行。
##
## 用法（注意 -- 之后才是用户参数）：
##   Godot --path <项目> res://tests/shot.tscn -- <场景路径> <输出png> [走位串]
## 走位串：由 U/D/L/R 组成，会在截图前依次驱动 GameManager.try_move_player()，
##         便于截出"通关弹窗"之类的中间状态。

const DIRS := {
	"U": Vector2i(0, -1),
	"D": Vector2i(0, 1),
	"L": Vector2i(-1, 0),
	"R": Vector2i(1, 0),
}

var _target := "res://scenes/start_screen.tscn"
var _out := ""
var _moves := ""
var _frames := 0
var _game: Node
var _rewind_shot := false
var _settings_shot := false
var _hint_shot := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1:
		_target = args[0]
	if args.size() >= 2:
		_out = args[1]
	if args.size() >= 3:
		_moves = args[2]

	var packed: PackedScene = load(_target)
	if packed == null:
		print("[SHOT] 无法加载场景：", _target)
		get_tree().quit(1)
		return
	_game = packed.instantiate()
	# 第 4 个参数为 "touch" 时，强制显示触屏按钮（用于手机版截图验证）
	if args.size() >= 4 and args[3] == "touch":
		if _game.get("force_touch_controls") != null:
			_game.set("force_touch_controls", true)
	if args.size() >= 4 and args[3] == "rewind":
		_rewind_shot = true
	if args.size() >= 4 and args[3] == "settings":
		_settings_shot = true
	# 第 4 个参数为 "seedstars" 时，先往存档里种几条假纪录，用来验证星级/记录墙的显示
	if args.size() >= 4 and args[3] == "seedstars":
		Progress.record_run(15, 31, 1, [Vector3i(0, 3, 9)])
		Progress.record_run(20, 90, 3, [Vector3i(0, 2, 10)])
		print("[SHOT] 已种假纪录：第16关 3 星 / 第21关 1 星")
	if args.size() >= 4 and args[3] == "hint":
		_hint_shot = true
	if args.size() >= 4 and args[3] == "ghost":
		_seed_ghost(_target)
		print("[SHOT] 已种幽灵轨迹")
	add_child(_game)
	print("[SHOT] 场景已载入：", _target, " 走位=", _moves)


func _seed_ghost(target: String) -> void:
	# 从场景名 LevelN.tscn 推出关卡号，种一条会动的矩形回路（只为验证幽灵渲染，不代表真实解）
	Progress.clear_all()          # 先清干净，否则更早的短记录会挡住新的幽灵轨迹
	var idx := int(target.get_file().trim_suffix(".tscn").trim_prefix("Level")) - 1
	var path: Array = []
	var cx := 3
	var cy := 8
	var dirs: Array = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for round_ in 3:
		for d in dirs:
			for _s in 3:
				cx += d.x
				cy += d.y
				path.append(Vector3i(0, cx, cy))
	Progress.record_run(idx, 42, 2, path)


func _process(_delta: float) -> void:
	_frames += 1

	if _frames == 20 and _moves != "":
		var gm := get_node_or_null("/root/GameManager")
		if gm != null:
			for ch in _moves:
				var key := String(ch).to_upper()
				if DIRS.has(key):
					gm.try_move_player(DIRS[key])
			print("[SHOT] 已回放走位，步数=", gm.move_count, " 通关=", gm.is_completed())

	if _frames == 30 and _rewind_shot:
		var gm2 := get_node_or_null("/root/GameManager")
		if gm2 != null:
			gm2.toggle_rewind()
			gm2.select_object(1)
			gm2.select_node(maxi(0, gm2.trail_of_object(1).past_count() - 1))
			print("[SHOT] 回溯面板：对象=", gm2.object_name(1), " 节点=", gm2.node_index)

	if _frames == 30 and _settings_shot:
		if _game.has_method("_open_settings"):
			_game.call("_open_settings")
			print("[SHOT] 已打开设置面板")

	if _frames == 40 and _hint_shot:
		if _game.has_method("_cycle_hint"):
			_game.call("_cycle_hint")
			_game.call("_cycle_hint")
			print("[SHOT] 已按两次 H（分层提示第 2 层）")

	if _frames < 55:
		return

	var img := get_viewport().get_texture().get_image()
	var path := _out if _out != "" else "user://shot.png"
	var err := img.save_png(path)
	print("[SHOT] 保存 ", path, " 尺寸 ", img.get_width(), "x", img.get_height(), " err=", err)
	get_tree().quit(0 if err == OK else 1)
