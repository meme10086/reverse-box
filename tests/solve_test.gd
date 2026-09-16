extends SceneTree
## 逻辑自检（无渲染、无输入模拟）：
##   godot --headless --path <project> -s res://tests/solve_test.gd
##
## 覆盖「对象独立回溯」版玩法：
##   M  关卡元数据（矩形 / 边框全墙 / 1 玩家 / 箱数=目标数 / 回溯次数 ≥ 最优）
##   S  全部 10 关端到端求解（含玩家/箱子回溯操作，解由 Python 参考模拟器验证）
##   N  传统推箱子规则负向：撞墙不可走、连箱不可推、非法移动不计步
##   A  玩家独立回溯：玩家回到过去，箱子原地不动
##   B  箱子独立回溯：箱子回到过去，玩家原地不动
##   C  双对象回溯：互不串扰
##   D  历史限制：只能回到自己真实走过的位置（越界 / 当前 / 被占用都不可选）
##   E  回溯后仍可正常移动、推箱、通关
##   F  即时重开：位置复位 + 轨迹清空 + 资源恢复
##   I  输入映射：WASD/方向键 + R + 确认键
## 退出码：0 = 全部通过；1 = 存在失败。

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)

# 每关解：字母 = 移动；P<i> = 玩家回溯到历史节点 i；B<k>:<i> = 第 k 个箱子回溯到节点 i
const SOLUTIONS := {
	0: ["U", "U", "L", "U", "R", "R"],
	1: ["D", "L", "L", "L", "B1:1", "L", "L", "P2", "L"],
	2: ["U", "U", "U", "B1:1", "U", "L", "L", "P1", "U", "U"],
	3: ["R", "R", "R", "B1:0", "R", "U", "U", "P1", "R", "R"],
	4: ["L", "D", "L", "D", "R", "R", "B0:1", "R", "R", "R", "B1:0", "L", "L"],
	5: ["D", "D", "L", "L", "B1:0", "R", "L", "L", "L", "L", "B0:0", "R", "R"],
	6: ["R", "R", "D", "D", "D", "B0:0", "D", "L", "L", "L", "L", "L", "P3", "D"],
	7: ["R", "R", "R", "B1:1", "R", "U", "U", "U", "U", "L", "L", "L", "L", "B0:0", "R"],
	8: ["D", "D", "L", "L", "L", "L", "L", "B1:0", "L", "U", "U", "U", "R", "P5", "L"],
	9: ["R", "R", "R", "B1:1", "R", "U", "U", "U", "U", "L", "L", "L", "L", "P1", "R"],
	10: ["L", "L", "L", "L", "L", "U", "U", "B1:3"],
	11: ["R", "R", "B0:0", "L", "L", "R", "R", "R", "R"],
	12: ["L", "U", "U", "U", "B1:1", "U", "R", "R", "R", "R"],
	13: ["D", "R", "R", "R", "L", "D", "D", "R", "R", "R", "B1:0", "L"],
	14: ["L", "D", "L", "D", "R", "R", "B0:1", "R", "R", "R", "B1:0", "L", "L"],
	15: ["U", "U", "U", "U", "L", "L", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "R", "R", "R"],
	16: ["U", "U", "U", "U", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R"],
	17: ["U", "U", "U", "U", "U", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R"],
	18: ["U", "U", "U", "U", "U", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R"],
	19: ["U", "U", "U", "U", "U", "U", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	20: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R"],
	21: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R"],
	22: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R"],
	23: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	24: ["D", "L", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	25: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	26: ["D", "L", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	27: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	28: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
	29: ["D", "L", "U", "R", "U", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B0:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "U", "L", "L", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "D", "D", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "B1:0", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "D", "L", "L", "U", "L", "L", "L", "L", "L", "L", "L", "L", "L", "L", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R", "R"],
}

var _failures := 0


func _initialize() -> void:
	var code := _run()
	print("[RB-TEST] ===== 退出码：", code, " =====")
	quit(code)


func _run() -> int:
	print("[RB-TEST] ===== ReverseBox(独立回溯) 逻辑自检开始 =====")
	_part_meta()
	_part_solve_all()
	_part_negative()
	_part_a_player_rewind()
	_part_b_box_rewind()
	_part_c_both()
	_part_d_limits()
	_part_e_after_rewind()
	_part_f_restart()
	_part_g_span()
	_part_input()
	if _failures == 0:
		print("[RB-TEST] PASS 全部通过")
	else:
		print("[RB-TEST] FAIL 共 ", _failures, " 处失败")
	return 1 if _failures > 0 else 0


# ---------------- 工具 ----------------

func _new_gm(index: int):
	var gm = load("res://scripts/game_manager.gd").new()
	gm.record_runs = false      # 测试不写真实存档
	gm.start_level(index)
	return gm


func _dir(ch: String) -> Vector2i:
	match ch:
		"U": return UP
		"D": return DOWN
		"L": return LEFT
		"R": return RIGHT
	return Vector2i.ZERO


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("[RB-TEST] PASS ", name)
	else:
		_failures += 1
		print("[RB-TEST] FAIL ", name, "  ", detail)


func _do(gm, act: String) -> bool:
	if act.length() == 1:
		return gm.try_move_player(_dir(act))
	if act.begins_with("P"):
		if not gm.rewind_mode:
			gm.toggle_rewind()
		gm.select_object(0)
		gm.select_node(int(act.substr(1)))
		return gm.apply_rewind()
	if act.begins_with("B"):
		var parts := act.substr(1).split(":")
		if not gm.rewind_mode:
			gm.toggle_rewind()
		gm.select_object(1 + int(parts[0]))
		gm.select_node(int(parts[1]))
		return gm.apply_rewind()
	return false


func _play(gm, acts: Array) -> void:
	for a in acts:
		_do(gm, a)


func _box_cells(gm) -> Array:
	return gm.box_cells()


# ---------------- M 关卡元数据 ----------------

func _part_meta() -> void:
	var n: int = LevelManager.level_count()
	_check("M1 关卡数量 ≥ 10", n >= 10, "实际 %d" % n)
	var ok_width := true
	var ok_border := true
	var ok_player := true
	var ok_boxgoal := true
	var ok_par := true
	var ok_room_same := true
	for i in n:
		var data: Dictionary = LevelManager.LEVELS[i]
		var rooms: Array = data["rooms"] if data.has("rooms") else [data["layout"]]
		var box_total := 0
		var goal_total := 0
		var player_total := 0
		var w0 := -1
		var h0 := -1
		for room in rooms:
			var rows: Array = room
			var w: int = 0
			for r in rows:
				w = maxi(w, String(r).length())
			for r in rows:
				if String(r).length() != w:
					ok_width = false
			for x in w:
				if rows[0][x] != "#" or rows[rows.size() - 1][x] != "#":
					ok_border = false
			for r in rows:
				if r[0] != "#" or r[r.length() - 1] != "#":
					ok_border = false
			if w0 < 0:
				w0 = w
				h0 = rows.size()
			elif w != w0 or rows.size() != h0:
				ok_room_same = false
			for r in rows:
				for x in String(r).length():
					match r[x]:
						"@": player_total += 1
						"$", "&": box_total += 1
						"*", "&": goal_total += 1
						"a", "b", "c": box_total += 1
						"1", "2", "3": goal_total += 1
		if player_total != 1:
			ok_player = false
			print("     关卡 ", i, " 玩家数 = ", player_total)
		if box_total != goal_total:
			ok_boxgoal = false
			print("     关卡 ", i, " 箱 ", box_total, " 目标 ", goal_total)
		if LevelManager.level_rewind_budget(i) < LevelManager.level_par_rewinds(i):
			ok_par = false
	_check("M2 每关每行等宽", ok_width)
	_check("M3 每关边框全为墙", ok_border)
	_check("M4 每关恰好 1 个玩家", ok_player)
	_check("M5 每关箱子数 = 目标点数", ok_boxgoal)
	_check("M6 回溯次数 ≥ 设计最优", ok_par)
	_check("M7 多地图关卡各图尺寸一致", ok_room_same)


# ---------------- S 端到端求解 ----------------

func _part_solve_all() -> void:
	for i in SOLUTIONS.keys():
		var gm = _new_gm(i)
		var acts: Array = SOLUTIONS[i]
		_play(gm, acts)
		var used: int = gm.rewinds_used
		var expect: int = 0
		for a in acts:
			if a.length() > 1:
				expect += 1
		_check("S%d 第 %d 关通关（回溯 %d 次）" % [i + 1, i + 1, used],
			gm.is_completed() and used == expect,
			"完成=%s 回溯=%d/%d" % [str(gm.is_completed()), used, expect])


# ---------------- N 传统推箱子规则负向 ----------------

func _part_negative() -> void:
	# 第 2 关：玩家 (1,3)，左边 (0,3) 是墙
	var gm = _new_gm(1)
	var mc0: int = gm.move_count
	_check("N1 撞墙不可走且不计步",
		not gm.try_move_player(LEFT) and gm.move_count == mc0)

	# 第 1 关：玩家 (2,5)，箱子 (2,4)，目标 (4,2)
	var g1 = _new_gm(0)
	_check("N2 向上推箱成功，步数 +1", g1.try_move_player(UP) and g1.move_count == 1)
	_check("N3 连续推箱：箱子被推到 (2,2)",
		g1.try_move_player(UP) and g1.box_cells()[0] == Vector2i(2, 2))

	# 箱子顶到走廊尽头的墙：推不动，且玩家自己也不动、不计步
	var g2 = _new_gm(1)
	_play(g2, ["R", "R", "R", "R", "R", "R"])   # 走廊箱子被推到尽头 (8,3)
	var mc2: int = g2.move_count
	var p2: Vector2i = g2.player_cell()
	_check("N4 箱子后面是墙 → 推不动", not g2.try_move_player(RIGHT))
	_check("N5 推不动时玩家也不动、不计步",
		g2.move_count == mc2 and g2.player_cell() == p2)

	# 回溯模式中不能移动
	var g3 = _new_gm(1)
	_play(g3, ["R", "R", "R"])
	g3.toggle_rewind()
	var mv: int = g3.move_count
	_check("N6 回溯模式中移动被禁用",
		not g3.try_move_player(LEFT) and g3.move_count == mv)
	g3.toggle_rewind()


# ---------------- A 玩家独立回溯 ----------------

# 从参考解里自动找出"能单独回溯玩家"的场景：
# 前缀全是不含回溯的走位，最后执行第一次玩家回溯。
func _probe_player_rewind() -> Array:
	# 按参考解原样回放到"第一个玩家回溯"之前，再单独执行它。
	# 前缀里可以有箱子回溯（下标必须与参考解一致，所以不能跳步）。
	for idx in range(1, LevelManager.level_count()):
		var acts: Array = SOLUTIONS[idx]
		for k in range(acts.size()):
			var a := String(acts[k])
			if not a.begins_with("P"):
				continue
			var gm = _new_gm(idx)
			for j in range(k):
				_do(gm, String(acts[j]))
			var used_before: int = gm.rewinds_used
			var boxes_before := _box_cells(gm)
			var pcell_before: Vector2i = gm.player_cell()
			if _do(gm, a):
				return [gm, a, boxes_before, pcell_before, idx, used_before]
	return []


func _part_a_player_rewind() -> void:
	var probe := _probe_player_rewind()
	_check("A0 参考解里存在「只回溯玩家」的场景", probe.size() > 0)
	if probe.is_empty():
		return
	var gm = probe[0]
	var boxes_before: Array = probe[2]
	var pcell_before: Vector2i = probe[3]
	_check("A1 玩家回溯成功（第 %d 关 %s）" % [probe[4] + 1, probe[1]], true)
	_check("A2 玩家回到历史位置", gm.player_cell() != pcell_before,
		"回溯后 %s" % str(gm.player_cell()))
	_check("A3 玩家回溯时箱子完全不动", _box_cells(gm) == boxes_before,
		"前 %s / 后 %s" % [str(boxes_before), str(_box_cells(gm))])
	_check("A4 玩家回溯正好多扣 1 次资源",
		gm.rewinds_used == int(probe[5]) + 1,
		"前缀已用 %d，现在 %d" % [int(probe[5]), gm.rewinds_used])


# ---------------- B 箱子独立回溯 ----------------

func _part_b_box_rewind() -> void:
	var probe := []
	for idx in range(1, LevelManager.level_count()):
		var acts: Array = SOLUTIONS[idx]
		for k in range(acts.size()):
			var a := String(acts[k])
			if not a.begins_with("B"):
				continue
			var gm = _new_gm(idx)
			var clean := true
			for j in range(k):
				var s := String(acts[j])
				if s.begins_with("P") or s.begins_with("B"):
					clean = false
					break
				_do(gm, s)
			if not clean or gm.rewinds_used != 0:
				continue
			var pcell: Vector2i = gm.player_cell()
			var boxes_before := _box_cells(gm)
			var trail_before: int = gm.trail_of_object(1).size()
			if _do(gm, a):
				probe = [gm, a, pcell, boxes_before, trail_before, idx]
			break
		if not probe.is_empty():
			break
	_check("B0 参考解里存在「只回溯箱子」的场景", probe.size() > 0)
	if probe.is_empty():
		return
	var gm2 = probe[0]
	_check("B1 箱子回溯成功（第 %d 关 %s）" % [probe[5] + 1, probe[1]], true)
	_check("B2 箱子位置确实改变", _box_cells(gm2) != probe[3],
		"前 %s / 后 %s" % [str(probe[3]), str(_box_cells(gm2))])
	_check("B3 箱子回溯时玩家不动", gm2.player_cell() == probe[2],
		"前 %s / 后 %s" % [str(probe[2]), str(gm2.player_cell())])
	_check("B4 轨迹互相独立：被推动过的箱子有历史，另一个仍是 1",
		gm2.trail_of_object(1).size() > 1 or gm2.trail_of_object(2).size() > 1)


# ---------------- C 双对象回溯 ----------------

func _part_c_both() -> void:
	# 找一个"两次回溯"的关卡，按参考解依次执行两次回溯，验证互不串扰
	var pick := -1
	for idx in range(1, LevelManager.level_count()):
		var n := 0
		for a in SOLUTIONS[idx]:
			if String(a).begins_with("P") or String(a).begins_with("B"):
				n += 1
		if n >= 2:
			pick = idx
			break
	_check("C0 存在需要两次回溯的关卡", pick >= 0)
	if pick < 0:
		return
	var gm = _new_gm(pick)
	var p_after := Vector2i.ZERO
	var first_done := false
	var box_before_p: Array = []
	for a in SOLUTIONS[pick]:
		var s := String(a)
		if s.begins_with("B"):
			_check("C1 第一次回溯（箱子 %s）成功" % s, _do(gm, s))
			p_after = gm.player_cell()
			first_done = true
		elif s.begins_with("P"):
			box_before_p = _box_cells(gm)
			_check("C2 第二次回溯（玩家 %s）成功" % s, _do(gm, s))
			break
		else:
			_do(gm, s)
	_check("C3 两次回溯后资源正好扣 2", gm.rewinds_used == 2, "实际 %d" % gm.rewinds_used)
	if first_done:
		_check("C4 玩家回溯不影响箱子：回溯前后箱子数组没变",
			_box_cells(gm) == box_before_p,
			"前 %s / 后 %s" % [str(box_before_p), str(_box_cells(gm))])
	_check("C5 玩家位置确实被改变", gm.player_cell() != p_after,
		"前 %s / 后 %s" % [str(p_after), str(gm.player_cell())])


# ---------------- D 历史限制 ----------------

func _moves_only(idx: int, count: int) -> Array:
	var out: Array = []
	for a in SOLUTIONS[idx]:
		if out.size() >= count:
			break
		if not String(a).begins_with("P") and not String(a).begins_with("B"):
			out.append(a)
	return out


func _part_d_limits() -> void:
	# 用第 2 关参考解的前 4 个走位把玩家走开，再检查历史节点的可选性
	var gm = _new_gm(1)
	_play(gm, _moves_only(1, 4))
	gm.toggle_rewind()
	gm.select_object(0)
	var t: int = gm.trail_of_object(0).size()
	_check("D1 越界节点不可选", not gm.node_valid_by_index(0, t + 5))
	_check("D2 「当前」节点不可选（必须是严格过去）", not gm.node_valid_by_index(0, t - 1))
	_check("D3 起点（真实走过）可选", gm.node_valid_by_index(0, 0))
	# 找一个"玩家走过、现在空着"的格子 —— 它必须是可回溯的
	var past_free := Vector2i(-1, -1)
	var past_idx := -1
	var level = gm.get_node_or_null("Level")
	for i in range(t - 1):
		var c: Vector2i = gm.trail_of_object(0).cell_at(i)
		if c != gm.player_cell() and level.get_box_at(c) == null:
			past_free = c
			past_idx = i
	_check("D4 玩家轨迹里有走过的空闲格子", past_idx >= 0, "找到 %s" % str(past_free))
	_check("D5 该格空闲 → 可以回溯过去", past_idx >= 0 and gm.node_valid_by_index(0, past_idx))
	gm.toggle_rewind()

	# 箱子回溯到「玩家此刻站的格子」必须被拒绝（否则两者会重叠）
	var g3 = _new_gm(1)
	_play(g3, ["D", "L"])                 # 玩家推箱子一格，自己站上箱子原来的格子
	g3.toggle_rewind()
	g3.select_object(2)
	g3.select_node(0)
	_check("D9 箱子回溯到玩家所在格：节点被判为不可用", not g3.node_valid_by_index(2, 0))
	_check("D10 箱子回溯到玩家所在格：执行被拒绝", not g3.apply_rewind())
	_check("D11 玩家与箱子没有重叠",
		g3.player_cell() != g3.box_cells()[1],
		"玩家 %s / 箱子 %s" % [str(g3.player_cell()), str(g3.box_cells()[1])])
	g3.toggle_rewind()
	# 玩家走开（顺手把箱子也再推一格）后，同一个历史节点就合法了
	_play(g3, ["L"])
	g3.toggle_rewind()
	g3.select_object(2)
	g3.select_node(0)
	_check("D12 玩家让开后，箱子可以回到那一格",
		g3.node_valid_by_index(2, 0) and g3.apply_rewind())
	g3.toggle_rewind()
	_check("D8 不能回到自己从未走过的格子",
		not g3.trail_of_object(0).cells.has(Vector2i(5, 1)))


# ---------------- E 回溯后仍可正常游玩并通关 ----------------

func _part_e_after_rewind() -> void:
	# 第 2 关：执行完参考解里所有回溯动作后，剩下的走位仍应能正常走完并通关
	var gm = _new_gm(1)
	var acts: Array = SOLUTIONS[1]
	var rewind_done := 0
	for a in acts:
		if String(a).begins_with("P") or String(a).begins_with("B"):
			rewind_done += 1
	_check("E0 第 2 关参考解含两次回溯", rewind_done == 2)
	var tail: Array = []
	var seen_rewind := 0
	for a in acts:
		var s := String(a)
		if s.begins_with("P") or s.begins_with("B"):
			seen_rewind += 1
			_do(gm, s)
		elif seen_rewind >= 2:
			tail.append(s)
		else:
			_do(gm, s)
	_check("E1 回溯后未通关", not gm.is_completed())
	var mc_before: int = gm.move_count
	if tail.size() > 0:
		_do(gm, String(tail[0]))
	_check("E2 回溯后仍可正常走位", gm.move_count > mc_before)
	for i in range(1, tail.size()):
		_do(gm, String(tail[i]))
	_check("E3 回溯后仍可通关", gm.is_completed())


# ---------------- G 距离上限（第二大关） ----------------

func _part_g_span() -> void:
	# rewind_span = 1 时：只能回到 1 步之前，更远的历史节点必须不可选
	var gm = _new_gm(1)
	_play(gm, _moves_only(1, 4))          # 走 4 步 → 玩家轨迹 5 个节点
	gm.rewind_span = 1
	gm.toggle_rewind()
	gm.select_object(0)
	var t: int = gm.trail_of_object(0).size()
	_check("G1 距离上限内（1 步前）可选", gm.node_valid_by_index(0, t - 2))
	_check("G2 超出距离上限（2 步前）不可选", not gm.node_valid_by_index(0, t - 3))
	gm.toggle_rewind()

	# 按钮式回溯：超上限拒绝、上限内成功、且只扣 1 次
	var gm2 = _new_gm(1)
	_play(gm2, _moves_only(1, 4))
	gm2.rewind_span = 2
	_check("G3 超过上限 try_span_rewind(3) 被拒绝", not gm2.try_span_rewind(3))
	_check("G4 try_span_rewind(2) 成功", gm2.try_span_rewind(2))
	_check("G5 距离回溯消耗 1 次", gm2.rewinds_used == 1)
	_check("G6 距离回溯后玩家确实换了位置", gm2.player_cell() != Vector2i(4, 4),
		"玩家现在 %s" % str(gm2.player_cell()))

	# 没有上限（第一大关）时，远距离节点仍然可选
	var gm3 = _new_gm(1)
	_play(gm3, _moves_only(1, 4))
	_check("G7 不限距离时可回到起点", gm3.node_valid_by_index(0, 0))


# ---------------- F 即时重开 ----------------

func _part_f_restart() -> void:
	var gm = _new_gm(2)
	_play(gm, ["R", "R", "R"])
	var p0: Vector2i = gm.trail_of_object(0).cell_at(0)
	gm.restart_level()
	_check("F1 玩家回到起点", gm.player_cell() == p0)
	_check("F2 所有轨迹清空（只剩起点）",
		gm.trail_of_object(0).size() == 1 and gm.trail_of_object(1).size() == 1)
	_check("F3 回溯资源恢复",
		gm.rewinds_used == 0 and gm.rewind_left == gm.rewind_budget)
	_check("F4 步数归零", gm.move_count == 0)
	_check("F5 重开后不再处于回溯模式", not gm.rewind_mode)


# ---------------- I 输入映射 ----------------

func _part_input() -> void:
	var gm = load("res://scripts/game_manager.gd").new()
	get_root().add_child(gm)
	gm._register_input_actions()   # 无头脚本里 _ready 时机不保证，显式注册一次
	var need := ["move_up", "move_down", "move_left", "move_right", "rewind", "rw_confirm"]
	var ok := true
	for a in need:
		if not InputMap.has_action(a):
			ok = false
			print("     缺少动作 ", a)
	_check("I1 移动 / 回溯 / 确认动作都已注册", ok)
	gm.queue_free()
