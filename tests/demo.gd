extends Node
## 宣传片录制脚本（开发期专用，不参与正式运行）。
##
## 用法：
##   Godot --path <项目> --write-movie <out.avi> --fixed-fps 30 \
##         --resolution 1920x1080 res://tests/demo.tscn
##
## 做的事：自动浏览选关界面 → 逐关按参考解「游玩」（含真实打开回溯面板、
## 换对象、翻历史节点、执行回溯的完整操作过程）→ 最后回到选关界面收尾。
## 关卡解法与 tests/solve_test.gd 的 SOLUTIONS 完全一致。

const DIRS := {
	"U": Vector2i(0, -1),
	"D": Vector2i(0, 1),
	"L": Vector2i(-1, 0),
	"R": Vector2i(1, 0),
}

# 参考解：字母 = 移动一格；P<i> = 玩家回溯到历史节点 i；B<k>:<i> = 第 k 个箱子回溯到节点 i
const SOLUTIONS := {
	0: ["U", "U", "L", "U", "R", "R"],
	1: ["D", "L", "L", "L", "B1:1", "L", "L", "P2", "L"],
	2: ["U", "U", "U", "B1:1", "U", "L", "L", "P1", "U", "U"],
	9: ["R", "R", "R", "B1:1", "R", "U", "U", "U", "U", "L", "L", "L", "L", "P1", "R"],
	15: ["U", "U", "U", "U", "L", "L", "R", "R", "R", "R", "R", "R", "R", "B0:0",
		"L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "R", "R", "R"],
	20: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0",
		"L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L",
		"R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R",
		"R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L",
		"L", "L", "L", "R", "R", "R", "R", "R"],
}

# 演示顺序（0 基关卡号）：教学三关 → 大关1 终局 → 大关2 借道 → 大关3 两次借道
const SHOW := [0, 1, 2, 9, 15, 20]

# 帧节奏（--fixed-fps 30）
const F_MOVE := 9          # 两步之间的间隔
const F_ENTER := 34        # 进入关卡后的就绪停顿
const F_SWITCH := 5        # 场景切换
const F_PANEL_OPEN := 20   # 面板展开
const F_PANEL_PICK := 15   # 换对象 / 翻历史
const F_APPLY := 18        # 执行回溯后的特效
const F_PANEL_EXIT := 22   # 面板收起
const F_CLEAR := 62        # 通关弹窗停留

var _cur: Node = null


func _ready() -> void:
	_run()


func _wait(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _mount(path: String, level_index: int = -1) -> void:
	if is_instance_valid(_cur):
		_cur.queue_free()
		_cur = null
		await _wait(F_SWITCH)
	var ps: PackedScene = load(path)
	if ps == null:
		print("[DEMO] 无法加载 ", path)
		return
	var inst: Node = ps.instantiate()
	get_tree().root.add_child(inst)
	_cur = inst
	await _wait(F_ENTER)


func _gm() -> Node:
	return get_node_or_null("/root/GameManager")


func _rewind(obj_index: int, node_i: int) -> void:
	var gm := _gm()
	if gm == null:
		return
	gm.toggle_rewind()
	await _wait(F_PANEL_OPEN)
	gm.select_object(obj_index)
	await _wait(F_PANEL_PICK)
	gm.select_node(node_i)
	await _wait(F_PANEL_PICK)
	gm.apply_rewind()
	await _wait(F_APPLY)
	await _wait(F_PANEL_EXIT)


func _step(act: String) -> void:
	var gm := _gm()
	if gm == null:
		return
	if act.length() == 1:
		gm.try_move_player(DIRS[act])
		await _wait(F_MOVE)
		return
	if act.begins_with("P"):
		await _rewind(0, int(act.substr(1)))
		return
	if act.begins_with("B"):
		var parts: PackedStringArray = act.substr(1).split(":")
		await _rewind(1 + int(parts[0]), int(parts[1]))


func _play(index: int) -> void:
	var acts: Array = SOLUTIONS.get(index, [])
	for a in acts:
		await _step(String(a))
	await _wait(F_CLEAR)


func _collect_level_nodes(n: Node, out: Array) -> void:
	if n is LevelNode:
		out.append(n)
	for c in n.get_children():
		_collect_level_nodes(c, out)


func _browse_levels() -> void:
	await _wait(24)
	var nodes: Array = []
	if is_instance_valid(_cur):
		_collect_level_nodes(_cur, nodes)
	nodes.sort_custom(func(a, b): return a.name < b.name)
	var picks: Array = [2, 1, 0, 4, 9, 14, 19, 24, 29]
	for p in picks:
		if p < nodes.size() and is_instance_valid(nodes[p]):
			nodes[p].grab_focus()
		await _wait(16)
	await _wait(30)


func _run() -> void:
	await _wait(3)
	# 片头：选关界面（像素树背景 + 数字格子 + 信息面板）
	await _mount("res://scenes/start_screen.tscn")
	await _browse_levels()
	# 逐关游玩
	for idx in SHOW:
		await _mount("res://scenes/Level%d.tscn" % (idx + 1), idx)
		await _play(idx)
	# 收尾：回到选关界面，展示已通关状态
	await _mount("res://scenes/start_screen.tscn")
	await _wait(150)
	print("[DEMO] 录制完成，共 ", Engine.get_frames_drawn(), " 帧")
	get_tree().quit(0)
