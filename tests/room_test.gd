extends SceneTree
## 多地图 / 传送门 / 颜色匹配 专项自检（大关 3 的引擎基础）。
##   godot --headless --path <project> -s res://tests/room_test.gd
##
## 覆盖：
##   R1 关卡能解析出 2 张地图、2 对传送门
##   R2 箱子被推过传送门 → 出现在另一张地图的对应门里，玩家留在原地
##   R3 玩家走进传送门 → 切换地图、落在对应门里
##   R4 颜色判定：同色箱子压同色地砖才算到位；异色不算
##   R5 端到端：按参考解打完这关（跨图搬运 + 颜色匹配）
## 退出码：0 = 全部通过；1 = 存在失败。

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)

# 两张 7x6 地图：左图把紫箱推进 A 门，玩家走 B 门过去，再把箱子推上紫地砖
const TEST_LEVEL := {
	"name": "测试 · 双图",
	"rewind_budget": 2,
	"par_rewinds": 0,
	"rooms": [
		[
			"#######",
			"#.....#",
			"#.....#",
			"#B..aA#",
			"#.@...#",
			"#######",
		],
		[
			"#######",
			"#.....#",
			"#.....#",
			"#.A.1.#",
			"#....B#",
			"#######",
		],
	],
}

const SOLUTION := ["U", "R", "R", "L", "L", "L", "L", "L", "L", "L", "U", "R", "R"]

var _failures := 0


func _initialize() -> void:
	var code := _run()
	print("[RB-TEST] ===== 多地图自检退出码：", code, " =====")
	quit(code)


func _run() -> int:
	print("[RB-TEST] ===== 多地图 / 传送门 / 颜色 自检开始 =====")
	_part_layout()
	_part_cross_map()
	_part_color()
	_part_end_to_end()
	return 1 if _failures > 0 else 0


func _new_gm() -> Node:
	var gm = load("res://scripts/game_manager.gd").new()
	gm.record_runs = false      # 测试不写真实存档
	gm.start_level(0, TEST_LEVEL)
	return gm


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("[RB-TEST] PASS ", name)
	else:
		_failures += 1
		print("[RB-TEST] FAIL ", name, "  ", detail)


func _dir(ch: String) -> Vector2i:
	match ch:
		"U": return UP
		"D": return DOWN
		"L": return LEFT
		"R": return RIGHT
	return Vector2i.ZERO


func _level(gm) -> Node:
	return gm.get_node("Level")


func _part_layout() -> void:
	var gm = _new_gm()
	var lv = _level(gm)
	_check("R1a 关卡含 2 张地图", lv.room_count() == 2, "实际 %d" % lv.room_count())
	_check("R1b 一共 2 对传送门", lv.portal_pairs.size() == 2,
		"实际 %d" % lv.portal_pairs.size())
	_check("R1c 初始在 0 号地图", lv.current_room() == 0)
	_check("R1d A 门是双向的（0 号图 → 1 号图）",
		lv.portal_at(0, Vector2i(5, 3)) == [1, Vector2i(2, 3)],
		str(lv.portal_at(0, Vector2i(5, 3))))
	_check("R1e 从另一头也能反向查到",
		lv.portal_at(1, Vector2i(2, 3)) == [0, Vector2i(5, 3)],
		str(lv.portal_at(1, Vector2i(2, 3))))


func _part_cross_map() -> void:
	var gm = _new_gm()
	var lv = _level(gm)
	gm.try_move_player(UP)          # (2,4) → (2,3)
	gm.try_move_player(RIGHT)       # → (3,3)
	_check("R2a 推箱前玩家在 0 号图", gm.player_cell() == Vector2i(3, 3))
	gm.try_move_player(RIGHT)       # 把箱子推进 A 门
	var box1 = lv.get_box_at_in(1, Vector2i(2, 3))
	_check("R2b 箱子穿过传送门，出现在 1 号图的 A 门", box1 != null,
		"1 号图 (2,3) 上的箱子 = %s" % str(box1))
	_check("R2c 箱子自己的所属地图也更新了", box1 != null and box1.room == 1)
	_check("R2d 箱子不在 0 号图了", lv.get_box_at_in(0, Vector2i(5, 3)) == null)
	_check("R2e 玩家留在 0 号图（人箱分离）", gm.player_cell() == Vector2i(4, 3))
	_check("R2f 玩家所在地图仍是 0", lv.current_room() == 0)


func _part_color() -> void:
	var gm = _new_gm()
	var lv = _level(gm)
	var goal := Vector2i(4, 3)
	_check("R4a 紫箱(色1) 压在紫地砖(色1) 上 = 到位",
		lv.is_goal_for(1, goal, 1))
	_check("R4b 橙箱(色2) 压在紫地砖上 = 不到位",
		not lv.is_goal_for(1, goal, 2))
	_check("R4c 绿箱(色3) 压在紫地砖上 = 不到位",
		not lv.is_goal_for(1, goal, 3))
	_check("R4d 地砖颜色确实是 1", int(lv.rooms[1]["goal_colors"][goal]) == 1)
	_check("R4e 关卡目标点总数为 1（跨图统计）", lv.total_goal_count() == 1,
		"实际 %d" % lv.total_goal_count())


func _part_end_to_end() -> void:
	var gm = _new_gm()
	var lv = _level(gm)
	for a in SOLUTION:
		if not gm.try_move_player(_dir(a)):
			_check("R5 参考解可完整执行", false, "在 %s 处走不动" % a)
			return
	_check("R5a 参考解走完即通关", gm.is_completed(),
		"玩家 %s / 地图 %d / 到位 %d" % [str(gm.player_cell()),
			lv.current_room(), gm.boxes_on_goal()])
	_check("R5b 通关时箱子在 1 号图的紫地砖上",
		lv.get_box_at_in(1, Vector2i(4, 3)) != null)
	_check("R5c 通关后玩家在 1 号图", lv.current_room() == 1)
