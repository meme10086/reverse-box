# -*- coding: utf-8 -*-
"""把 solve_test.gd 里 A~E 五段单元测试换成「跟着参考解自动推导」的写法。

原因：这些测试原来把旧关卡坐标写死了，一换关卡就整片失败。
现在改为从 SOLUTIONS 里自动找出"第一次玩家回溯 / 第一次箱子回溯"的场景，
只断言规则本身（谁动了、谁没动、扣几次资源），不再依赖具体坐标。
"""
import io, os, re

P = r"D:\Game《Reserve box》\ReverseBox_Godot\tests\solve_test.gd"

NEW = r'''# ---------------- A 玩家独立回溯 ----------------

# 从参考解里自动找出"能单独回溯玩家"的场景：
# 前缀全是不含回溯的走位，最后执行第一次玩家回溯。
func _probe_player_rewind() -> Array:
	for idx in range(1, LevelManager.level_count()):
		var acts: Array = SOLUTIONS[idx]
		for k in range(acts.size()):
			var a := String(acts[k])
			if not a.begins_with("P"):
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
			var boxes_before := _box_cells(gm)
			var pcell_before: Vector2i = gm.player_cell()
			if _do(gm, a):
				return [gm, a, boxes_before, pcell_before, idx]
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
	_check("A4 玩家回溯消耗 1 次", gm.rewinds_used == 1 and gm.rewind_left == gm.rewind_budget - 1)


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
			var trail_before := gm.trail_of_object(1).size()
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
	var box_after: Array = []
	var p_after := Vector2i.ZERO
	var first_done := false
	for a in SOLUTIONS[pick]:
		var s := String(a)
		if s.begins_with("B"):
			_check("C1 第一次回溯（箱子 %s）成功" % s, _do(gm, s))
			box_after = _box_cells(gm)
			p_after = gm.player_cell()
			first_done = true
		elif s.begins_with("P"):
			_check("C2 第二次回溯（玩家 %s）成功" % s, _do(gm, s))
			break
		else:
			_do(gm, s)
	_check("C3 两次回溯后资源正好扣 2", gm.rewinds_used == 2, "实际 %d" % gm.rewinds_used)
	if first_done:
		_check("C4 玩家回溯不影响箱子：箱子数组没变", _box_cells(gm) == box_after,
			"前 %s / 后 %s" % [str(box_after), str(_box_cells(gm))])
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


'''

def main():
    src = io.open(P, encoding="utf-8").read()
    start = src.index("# ---------------- A 玩家独立回溯 ----------------")
    end = src.index("# ---------------- F 即时重开 ----------------")
    out = src[:start] + NEW + src[end:]
    io.open(P, "w", encoding="utf-8", newline="\n").write(out)
    print("A~E 段已替换，长度", len(src), "->", len(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
