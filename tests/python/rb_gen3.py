# -*- coding: utf-8 -*-
"""大关 3（多地图 + 传送门 + 颜色）候选生成器 —— 构造式版本。

之前那版是"随机撒箱子"，在这类开放地图上几乎必然无解（试了 170 组，0 命中）。
这一版改成**构造式**：先按力学反推一个一定可解的摆法，再随机加墙/加第二个箱子来制造难度，
最后用参考引擎验收。

构造规则（为什么这样一定能解）：
  · 箱子摆在「某个门」的直线上，距离 k 格，玩家站在箱子后面 —— 照着推就能把箱子推进门。
  · 箱子过门后落在对面那张图的对应门格；目标摆在门口延伸的直线上 —— 继续推就到了。
  · 箱子必须跨图（否则不算"多地图关"）。

筛选：
  ① 地图张数 = 骨架张数（2 / 3 / 4）
  ② 可解（参考解回放通过），动作数 ≤ MAXOPT
  ③ NEED_MIN：若设为 1，则要求"不用时间机制无解"；若设为 2，还要求"1 次回溯不够"
  ④ 至少一个箱子跨图
  ⑤ 入口数 ≤ 3

用法：
  python rb_gen3.py [预算秒] [NEED_MIN]
环境变量：
  GEN_TEMPLATES  t1,t2,t3,t4
  GEN_MAXOPT     解的最长动作数（默认 20）
  GEN_WALLS      额外墙的数量上限（默认 2，用来制造需要回溯的局面）
  GEN_SEED       随机种子
"""
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_world as W   # noqa: E402

W_, H_ = 9, 6                 # 每张地图 9 列 x 6 行（含边框）→ 内圈 x1..7 / y1..4
MAXOPT = int(os.environ.get("GEN_MAXOPT", "20"))
MAXWALLS = int(os.environ.get("GEN_WALLS", "2"))
SPANV = int(os.environ.get("GEN_SPAN", "0"))        # >0 = 回溯距离上限（大关 2）
FORCE_NBOX = int(os.environ.get("GEN_NBOX", "0"))   # >0 = 强制箱子数量
MAXENTRIES = int(os.environ.get("GEN_MAXENTRIES", "3"))   # 入口数上限（多图开放地图可放宽）
NAMES = ["A", "B", "C", "D"]
DIRS = list(W.MOVES.items())

TEMPLATES = {
    # 门：字母 -> [(图号,x,y), (图号,x,y)]
    "t1": {
        "rooms": 2,
        "doors": {"A": [(0, 7, 1), (1, 2, 1)], "B": [(0, 1, 1), (1, 1, 3)]},
    },
    "t2": {
        "rooms": 2,
        "doors": {"A": [(0, 7, 3), (1, 2, 1)], "B": [(0, 1, 4), (1, 7, 4)]},
    },
    "t3": {
        "rooms": 3,
        "doors": {"A": [(0, 7, 1), (1, 2, 1)],
                  "B": [(1, 7, 4), (2, 2, 4)],
                  "C": [(2, 7, 1), (0, 1, 4)]},
    },
    "t4": {
        "rooms": 4,
        "doors": {"A": [(0, 7, 1), (1, 2, 1)],
                  "B": [(1, 7, 1), (2, 2, 1)],
                  "C": [(2, 7, 4), (3, 2, 4)],
                  "D": [(3, 7, 1), (0, 1, 4)]},
    },
}


def blank():
    g = [["#"] * W_ for _ in range(H_)]
    for y in range(1, H_ - 1):
        for x in range(1, W_ - 1):
            g[y][x] = "."
    return g


def inside(c):
    x, y = c
    return 1 <= x <= W_ - 2 and 1 <= y <= H_ - 2


def build_grids(tmpl):
    grids = [blank() for _ in range(tmpl["rooms"])]
    doors = {}
    for ch, ends in tmpl["doors"].items():
        for (r, x, y) in ends:
            grids[r][y][x] = ch
        doors[ch] = ends
    return grids, doors


def construct(tmpl_name, nbox, nwalls, rng):
    tmpl = TEMPLATES[tmpl_name]
    grids, doors = build_grids(tmpl)
    nrooms = tmpl["rooms"]
    used = set()          # (room, x, y) 已被占用的格
    for ch, ends in doors.items():
        for (r, x, y) in ends:
            used.add((r, x, y))

    def free(room, c):
        x, y = c
        return inside(c) and (room, x, y) not in used and grids[room][y][x] == "."

    letters = random.sample(NAMES, nbox) if nbox <= 4 else NAMES
    cols = random.sample([1, 2, 3], min(nbox, 3))
    while len(cols) < nbox:
        cols.append(random.choice([1, 2, 3]))
    sym_box = {1: "a", 2: "b", 3: "c"}
    sym_goal = {1: "1", 2: "2", 3: "3"}

    placements = []
    for i in range(nbox):
        ok = False
        for _ in range(60):
            ch = random.choice(list(doors))
            ends = doors[ch]
            if rng.random() < 0.5:
                src, dst = ends[0], ends[1]
            else:
                src, dst = ends[1], ends[0]
            sroom, sx, sy = src
            droom, dx, dy = dst
            dname, (ddx, ddy) = random.choice(DIRS)
            k = rng.randint(1, 3)
            boxc = (sx - ddx * k, sy - ddy * k)
            behind = (sx - ddx * (k + 1), sy - ddy * (k + 1))
            path = [(sx - ddx * j, sy - ddy * j) for j in range(1, k + 2)]
            if not all(free(sroom, c) for c in path):
                continue
            # 目标：从对面门口沿某条直线往外推
            gname, (gex, gey) = random.choice(DIRS)
            m = rng.randint(1, 3)
            goalc = (dx + gex * m, dy + gey * m)
            gpath = [(dx + gex * j, dy + gey * j) for j in range(1, m + 1)]
            back = (dx - gex, dy - gey)
            if not all(free(droom, c) for c in gpath):
                continue
            if not (inside(back) and (droom, back[0], back[1]) not in used
                    and grids[droom][back[1]][back[0]] == "."):
                continue
            placements.append((sroom, boxc, behind, droom, goalc, cols[i]))
            for c in path:
                used.add((sroom, c[0], c[1]))
            for c in gpath:
                used.add((droom, c[0], c[1]))
            used.add((droom, back[0], back[1]))
            ok = True
            break
        if not ok:
            return None

    # 玩家起点：优先放在 0 号图的"第一个箱子身后"，否则随便找空格
    pstart = None
    for (sroom, boxc, behind, droom, goalc, col) in placements:
        if sroom == 0 and free(0, behind):
            pstart = behind
            break
    if pstart is None:
        pool = [(x, y) for y in range(1, H_ - 1) for x in range(1, W_ - 1) if free(0, (x, y))]
        if not pool:
            return None
        pstart = rng.choice(pool)

    # 加墙：只在完全没被占用的空格上加，制造需要回溯的局面
    freecells = [(r, x, y) for r in range(nrooms)
                 for y in range(1, H_ - 1) for x in range(1, W_ - 1)
                 if free(r, (x, y)) and not (r == 0 and (x, y) == pstart)]
    rng.shuffle(freecells)
    for i in range(min(nwalls, len(freecells))):
        r, x, y = freecells[i]
        grids[r][y][x] = "#"
        used.add((r, x, y))

    for (sroom, boxc, behind, droom, goalc, col) in placements:
        grids[sroom][boxc[1]][boxc[0]] = sym_box[col]
        grids[droom][goalc[1]][goalc[0]] = sym_goal[col]
    grids[0][pstart[1]][pstart[0]] = "@"
    return [_rows(g) for g in grids]


def _rows(g):
    return ["".join(r) for r in g]


def entries(w, budget, cap):
    good = 0
    base = (w.start_player, w.box_start, (w.start_player,),
            tuple((b,) for b in w.box_start), budget + 2)
    for ch in W.MOVES:
        ns = W.apply_move(w, base, ch)
        if ns is None:
            continue
        nw = _with_state(w, ns)
        acts, err = W.search_fast(nw, budget + 2, max_moves=cap, limit=30_000)
        if acts is not None:
            good += 1
    return good


def _with_state(w, state):
    nw = object.__new__(W.World)
    nw.rooms = w.rooms
    nw.portals = w.portals
    nw.box_start = state[1]
    nw.box_colors = w.box_colors
    nw.start_player = state[0]
    nw.layouts = w.layouts
    nw.goal_count = w.goal_count
    return nw


def evaluate(layouts, need_min, rng):
    W.set_span(SPANV)
    w, err = W.parse_world(layouts)
    if w is None:
        return None, "parse:" + str(err)
    if need_min >= 1 and W.solve_no_rewind(w, limit=120_000)[0] is not None:
        return None, "无回溯就能过"
    cap = max(2, need_min)
    k, acts = W.min_rewinds(w, cap=cap, max_moves=MAXOPT)
    if acts is None:
        return None, "没找到解"
    moves = len([a for a in acts if len(a) == 1])
    if moves > MAXOPT:
        return None, "解太长"
    if k < need_min:
        return None, f"只要 {k} 次回溯"
    if W.replay(w, acts)[0] is not True:
        return None, "回放不过"
    if entries(w, k, MAXOPT + 4) > MAXENTRIES:
        return None, "入口太多"
    return {"rooms": layouts, "sol": acts, "k": k, "moves": moves}, None


def main():
    budget_s = float(sys.argv[1]) if len(sys.argv) > 1 else 300.0
    need_min = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    tmpl_names = [x.strip() for x in
                  os.environ.get("GEN_TEMPLATES", "t1,t2,t3,t4").split(",") if x.strip()]
    rng = random.Random(int(os.environ.get("GEN_SEED", "20260914")))

    t0 = time.time()
    found, tried = [], 0
    while time.time() - t0 < budget_s:
        for name in tmpl_names:
            nrooms = TEMPLATES[name]["rooms"]
            nb = FORCE_NBOX if FORCE_NBOX else rng.choice([1, 2] if nrooms <= 2 else [1, 2, 3])
            nw = rng.randint(0, MAXWALLS)
            layouts = construct(name, nb, nw, rng)
            tried += 1
            if layouts is None:
                continue
            hit, why = evaluate(layouts, need_min, rng)
            if hit is None:
                continue
            hit["tmpl"] = name
            found.append(hit)
            print(f"=== 命中 {len(found)}：{name} 图{nrooms} 箱{nb} 墙{nw} span={SPANV} "
                  f"k={hit['k']} 动作{hit['moves']}")
            for ri, rows in enumerate(hit["rooms"]):
                print(f"  图{ri}: " + " | ".join(rows))
            print("  解: " + " ".join(hit["sol"]), flush=True)
        print(f"[{time.time()-t0:5.0f}s] 已试 {tried} 组，命中 {len(found)}", flush=True)
    print(f"[结束] 共命中 {len(found)}，尝试 {tried} 组，耗时 {time.time()-t0:.0f}s")


if __name__ == "__main__":
    main()
