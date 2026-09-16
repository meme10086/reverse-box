# -*- coding: utf-8 -*-
"""解法收敛度分析：一关有"多少种第一步"还能通向解。

原理（解谜设计方法论）：多解的关卡会被玩家靠试错撞通，思考量归零 —— 好谜题要收敛。
所以除了「无回溯无解」，还要看入口数：只有 1~2 种第一步通向解 = 紧。

做法：对每个可能的第一步（4 个方向 + 合法回溯），落子后跑一次有深度上限的
     "还能不能解"判定（已访问只看 玩家/箱子/剩余次数，够快）。

用法：python rb_tight.py [slack] [depth_cap]
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_engine as E


def can_still_win(lv, state, depth, node_cap=120_000):
    """从 state 出发，在 depth 步以内能否通关（折中搜索：轨迹不进 visited）。"""
    seen = {(state[0], state[1], state[4])}
    stack = [(state, 0)]
    n = 0
    while stack:
        st, d = stack.pop()
        if E.won(lv, st):
            return True
        if d >= depth:
            continue
        n += 1
        if n > node_cap:
            return False
        succ = []
        for ch in E.MOVES:
            ns = E.apply_move(lv, st, ch)
            if ns is not None:
                succ.append(ns)
        if st[4] > 0:
            for obj in range(1 + len(st[1])):
                for node in E.valid_nodes(st, obj):
                    ns = E.apply_rewind(lv, st, obj, node)
                    if ns is not None:
                        succ.append(ns)
        for ns in succ:
            key = (ns[0], ns[1], ns[4])
            if key in seen:
                continue
            seen.add(key)
            stack.append((ns, d + 1))
    return False


def entries(rows, budget=None, slack=3, cap=28):
    lv, err = E.parse(rows)
    if lv is None:
        return None, None, (err or "解析失败")
    E.walkable_static = E._mk_walk(lv)
    k, base = E.min_rewinds_fast(rows, cap=budget if budget is not None else 3, max_moves=cap)
    if base is None:
        return None, None, "无解"
    best = len(base)
    depth = best + slack
    start = (lv.player, lv.boxes, (lv.player,), tuple((b,) for b in lv.boxes),
             (budget if budget is not None else k))
    good = []
    for ch in E.MOVES:
        ns = E.apply_move(lv, start, ch)
        if ns is not None and can_still_win(lv, ns, depth):
            good.append(ch)
    if start[4] > 0:
        for obj in range(1 + len(start[1])):
            for node in E.valid_nodes(start, obj):
                ns = E.apply_rewind(lv, start, obj, node)
                if ns is None:
                    continue
                tag = f"P{node}" if obj == 0 else f"B{obj-1}:{node}"
                if can_still_win(lv, ns, depth):
                    good.append(tag)
    return best, good, None


if __name__ == "__main__":
    slack = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    cap = int(sys.argv[2]) if len(sys.argv) > 2 else 28
    from rb_design import LEVELS
    for i, item in enumerate(LEVELS):
        name, rows = item[0], item[1]
        budget = item[2] if len(item) > 2 else None
        n, good, err = entries(rows, budget=budget, slack=slack, cap=cap)
        if n is None:
            print(f"L{i+1:<2} {name:<10} {err}")
            continue
        tag = "紧" if len(good) <= 2 else ("中" if len(good) <= 5 else "松")
        print(f"L{i+1:<2} {name:<10} 最优{n:>3}步  入口{len(good):>2}种 {sorted(good)}  {tag}")
