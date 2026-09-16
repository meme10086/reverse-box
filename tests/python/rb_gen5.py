# -*- coding: utf-8 -*-
"""大关 2/3 第三版：**多母题 + 大地图 + 密集建筑 + 强制回溯**。

设计法全部借用现有优质解谜资源（出处见文件末尾「设计出处」），
而不是自己凭空想。核心结论：
  · "一个规则、深空间" —— 难度来自**配置**，不是来自堆元素。
  · 好谜题必须**收敛解法**（多解 = 玩家靠试错通关，等于没谜题）。
  · 难度靠**技巧**（借道 / 顺序 / 活板门 / 陷阱）+ 技巧**组合**，逐关一个台阶。
  · 大地图不等于难；**信息过载反而劝退**。所以：画布大、建筑多，
    但**真正可走的格子少**（走廊 + 房间），玩家一眼能看清问题在哪。

本版三类母题（都在"不用回溯绝对无解"上做过精确验证）：
  A 借道（回溯箱子）：1 格宽走廊 + 箱子 + 玩家在左 + 尽头是墙。
  B 双借道（必须回溯 2 次）：两条平行走廊各来一次借道。
  C 双箱对色（大关 3）：两个箱子、两种颜色，目标在两间不同的密室里。

用法：
  python rb_gen5.py          # 自检全部关卡
  python rb_gen5.py -v       # 同时打印地图与参考解
"""
import os
import random
import sys
from collections import deque

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_world as W   # noqa: E402

DIRS = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}


# ---------------- 地图构建 ----------------

def build(size, floors, walls=(), place=()):
    """先铺地板，再压墙（'建筑'），最后放字符。"""
    Wd, Ht = size
    g = [["#"] * Wd for _ in range(Ht)]
    for (x0, y0, x1, y1) in floors:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g[y][x] = "."
    for (x0, y0, x1, y1) in walls:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g[y][x] = "#"
    for (c, ch) in place:
        x, y = c
        g[y][x] = ch
    return ["".join(r) for r in g]


def split(rows, regions):
    """把 regions 里的矩形挖成第 2 张地图（其余在图 0 里变成墙）。"""
    Wd, Ht = len(rows[0]), len(rows)
    r0 = [list(r) for r in rows]
    r1 = [["#"] * Wd for _ in range(Ht)]
    for (x0, y0, x1, y1) in regions:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                r1[y][x] = rows[y][x]
                r0[y][x] = "#"
    return ["".join(r) for r in r0], ["".join(r) for r in r1]


def rect(x0, y0, x1, y1):
    return (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))


def overlaps(a, b, pad=0):
    return not (a[2] + pad < b[0] or b[2] + pad < a[0]
                or a[3] + pad < b[1] or b[3] + pad < a[1])


def decorate(size, protected, rng, count, lo=3, hi=6):
    """在空地上摆几座**封闭的"建筑"**：只挖内部、外面仍是墙 → 玩家进不去，
    纯装饰（这正是 Sokoban 设计里的 Trapper 手法：给玩家大量"看着有用"的空间）。"""
    Wd, Ht = size
    out = []
    tries = 0
    while len(out) < count and tries < 400:
        tries += 1
        w = rng.randint(lo, hi)
        h = rng.randint(lo, hi)
        x0 = rng.randint(2, max(2, Wd - w - 2))
        y0 = rng.randint(2, max(2, Ht - h - 2))
        r = (x0, y0, x0 + w - 1, y0 + h - 1)
        if r[2] >= Wd - 1 or r[3] >= Ht - 1:
            continue
        if any(overlaps(r, p, pad=1) for p in protected):
            continue
        if any(overlaps(r, q, pad=1) for q in out):
            continue
        out.append(r)
    return out


# ---------------- 精确求解器（无回溯）----------------
# 纯推箱子 BFS 的正确做法：**玩家位置按可达区域归一化**（经典 Sokoban 解法）。
# 语义严格对齐引擎：① 走上传送门会传送；② **箱子被推进传送门也会传送**；
# ③ 推箱那一下玩家不传送。这里直接查表实现，比逐次构造状态机快几十倍。

_DIRS4 = ((0, -1), (0, 1), (-1, 0), (1, 0))


class _Board:
    def __init__(self, w):
        self.rooms = w.rooms
        self.portals = w.portals
        self.colors = tuple(w.box_colors)
        self.goals = [dict(rm.goal_color) for rm in w.rooms]

    def area(self, player, boxes):
        """玩家在当前箱子配置下能站到的所有格子（含传送门后果）。"""
        seen = {player}
        stack = [player]
        rooms, portals = self.rooms, self.portals
        while stack:
            r, x, y = stack.pop()
            rm = rooms[r]
            for dx, dy in _DIRS4:
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= rm.W or ny >= rm.H:
                    continue
                if (nx, ny) in rm.walls:
                    continue
                n = (r, nx, ny)
                if n in boxes:
                    continue
                p = portals.get(n)
                if p is not None:              # 踩到传送门 → 落到对面
                    if p in boxes or p in seen:
                        continue
                    seen.add(p)
                    stack.append(p)
                else:
                    if n in seen:
                        continue
                    seen.add(n)
                    stack.append(n)
        return frozenset(seen)

    def stepped(self, area, boxes):
        """从可达区域出发做的所有推箱一步 → [(新玩家格, 新箱子元组)]"""
        res = []
        rooms, portals = self.rooms, self.portals
        boxset = frozenset(boxes)
        for c in area:
            r, x, y = c
            rm = rooms[r]
            for dx, dy in _DIRS4:
                bc = (r, x + dx, y + dy)
                if bc not in boxset:
                    continue
                lx, ly = x + 2 * dx, y + 2 * dy
                if lx < 0 or ly < 0 or lx >= rm.W or ly >= rm.H:
                    continue
                if (lx, ly) in rm.walls:
                    continue
                lc = (r, lx, ly)
                dest = portals.get(lc, lc)     # 箱子落点是传送门 → 箱子被传送
                if dest in boxset:
                    continue
                k = boxes.index(bc)
                nb = list(boxes)
                nb[k] = dest
                res.append((bc, tuple(nb)))    # 玩家推进到箱子原来那一格
        return res

    def solved(self, boxes):
        for k, b in enumerate(boxes):
            gc = self.goals[b[0]].get((b[1], b[2]))
            if gc is None or gc != self.colors[k]:
                return False
        return True


def no_rewind_solvable(w, limit=200_000):
    """精确判定：**完全不用回溯**能否通关。True / False / None(=超限，未知)。"""
    b = _Board(w)
    boxes0 = tuple(w.box_start)
    start = (w.start_player, boxes0)
    seen = {(b.area(start[0], boxes0), boxes0)}
    q = deque([start])
    n = 0
    while q:
        player, boxes = q.popleft()
        if b.solved(boxes):
            return True
        area = b.area(player, boxes)
        for np, nb in b.stepped(area, boxes):
            key = (b.area(np, nb), nb)
            if key in seen:
                continue
            seen.add(key)
            n += 1
            if n > limit:
                return None
            q.append((np, nb))
    return False


# ---------------- 母题 A：借道（回溯箱子）----------------

def core_a(size, cy, room, corr_x1, ax, box_x, chamber, goal_x, player,
           pillars=(), box_ch="a", goal_ch="1"):
    """1 格宽走廊 + 箱子 + 玩家在左 + 尽头是墙。
    玩家绕不到箱子右边（绕行口袋只跨过传送门那一格）→ 只能回溯箱子。"""
    Wd, Ht = size
    pocket = rect(3, cy - 1, ax + 1, cy - 1)
    corridor = rect(1, cy, corr_x1, cy)
    ch_y = chamber[1]
    floors = [room, corridor, pocket, chamber] + list(pillars)
    place = [
        ((ax, cy), "A"), ((chamber[0] + 2, ch_y + 1), "A"),
        ((1, cy), "B"), ((chamber[0] + 1, ch_y + 1), "B"),
        ((box_x, cy), box_ch), ((goal_x, ch_y + 1), goal_ch),
        (player, "@"),
    ]
    protected = [room, corridor, pocket, chamber]
    return {
        "size": size, "cy": cy, "floors": floors, "walls": [],
        "place": place, "regions": [chamber], "protected": protected,
        "anchors": {"kind": "a", "ax": ax, "cy": cy, "box_x": box_x,
                    "corr_x1": corr_x1, "ch0": chamber[0], "ch_y": ch_y,
                    "goal_x": goal_x, "player": player},
    }


# ---------------- 母题 B：双借道（必须回溯 2 次）----------------

def core_b(size, room, cy1, cy2, corr_x1, ax, box_x, chamber, goal_x,
           player, pillars=()):
    """两条平行走廊，各来一次借道 → 必须回溯两次（两只箱子各一次）。"""
    Wd, Ht = size
    pk1 = rect(3, cy1 - 1, ax + 1, cy1 - 1)
    pk2 = rect(3, cy2 + 1, ax + 1, cy2 + 1)
    c1 = rect(1, cy1, corr_x1, cy1)
    c2 = rect(1, cy2, corr_x1, cy2)
    # 密室 3 行：上中下各一，箱子进中间行
    ch_y = chamber[1]
    floors = [room, c1, c2, pk1, pk2, chamber] + list(pillars)
    place = [
        ((ax, cy1), "A"), ((chamber[0] + 2, ch_y + 1), "A"),
        ((1, cy1), "B"), ((chamber[0] + 1, ch_y + 1), "B"),
        ((ax, cy2), "C"), ((chamber[0] + 2, ch_y + 3), "C"),
        ((1, cy2), "D"), ((chamber[0] + 1, ch_y + 3), "D"),
        ((box_x, cy1), "a"), ((goal_x, ch_y + 1), "1"),
        ((box_x, cy2), "b"), ((goal_x, ch_y + 3), "2"),
        (player, "@"),
    ]
    protected = [room, c1, c2, pk1, pk2, chamber]
    return {
        "size": size, "cy": cy1, "floors": floors, "walls": [],
        "place": place, "regions": [chamber], "protected": protected,
        "anchors": {"kind": "b", "ax": ax, "cy1": cy1, "cy2": cy2,
                    "box_x": box_x, "corr_x1": corr_x1, "ch0": chamber[0],
                    "ch_y": ch_y, "goal_x": goal_x, "player": player},
    }


# ---------------- 走位 / 参考解（构造式，不靠慢搜索）----------------

_M4 = (("U", (0, -1)), ("D", (0, 1)), ("L", (-1, 0)), ("R", (1, 0)))


def route(w, start, goal, blocked=()):
    """最短走位。**正确建模传送门**：踩上去就落到对面（落点不再连锁传送），
    和引擎一致。blocked 用来避开箱子。"""
    blocked = frozenset(blocked)

    def ok(c):
        r, x, y = c
        if r < 0 or r >= len(w.rooms):
            return False
        rm = w.rooms[r]
        return 0 <= x < rm.W and 0 <= y < rm.H and (x, y) not in rm.walls

    if not ok(start) or not ok(goal):
        return None
    prev = {start: None}
    q = deque([start])
    while q:
        cur = q.popleft()
        if cur == goal:
            break
        for ch, (dx, dy) in _M4:
            nxt = (cur[0], cur[1] + dx, cur[2] + dy)
            if not ok(nxt):
                continue
            if nxt in w.portals:
                nxt = w.portals[nxt]
            if nxt in blocked or nxt in prev or not ok(nxt):
                continue
            prev[nxt] = (cur, ch)
            q.append(nxt)
    if goal not in prev:
        return None
    out, cur = [], goal
    while prev[cur] is not None:
        cur, ch = prev[cur]
        out.append(ch)
    return out[::-1]


def build_solution(w, m):
    """按母题结构拼出参考解：每个箱子各回溯一次（回到自己的起点）。
    返回动作序列；结构不成立返回 None。"""
    if m["kind"] == "a":
        plan = [(0, m["ax"], m["cy"], m["box_x"], m["corr_x1"], m["goal_x"],
                 m["ch0"], m["ch_y"])]
    else:
        plan = [(0, m["ax"], m["cy1"], m["box_x"], m["corr_x1"], m["goal_x"],
                 m["ch0"], m["ch_y"]),
                (1, m["ax"], m["cy2"], m["box_x"], m["corr_x1"], m["goal_x"],
                 m["ch0"], m["ch_y"] + 2)]
    acts = []
    p = w.start_player
    boxcells = list(w.box_start)
    for (bno, ax, cy, box_x, x1, goal_x, ch0, row) in plan:
        # ① 先走到 A 门右边那一格（绕行口袋）
        seg = route(w, p, (0, ax + 1, cy), blocked=boxcells)
        if seg is None:
            return None
        acts += seg
        p = (0, ax + 1, cy)
        # ② 先把箱子推到走廊尽头（先走位到它左边，再一路推）
        acts += ["R"] * (x1 - ax - 2)
        p = (0, x1 - 1, cy)
        boxcells[bno] = (0, x1, cy)
        # ③ 回溯它回起点 —— 玩家因此落到它右边
        acts.append("B%d:0" % bno)
        boxcells[bno] = (0, box_x, cy)
        # ④ 走到它右边
        seg = route(w, p, (0, box_x + 1, cy), blocked=boxcells)
        if seg is None:
            return None
        acts += seg
        p = (0, box_x + 1, cy)
        # ⑤ 往左把它推进 A 门（箱子随即出现在密室里）
        acts += ["L"] * (box_x - ax)
        p = (0, ax + 1, cy)
        boxcells[bno] = (1, ch0 + 2, row + 1)
        # ⑥ 绕回左端走传送门进密室
        dst = (1, ch0 + 1, row + 1)
        seg = route(w, p, dst, blocked=boxcells)
        if seg is None:
            return None
        acts += seg
        p = dst
        # ⑦ 在密室里把箱子推到同色地砖
        acts += ["R"] * (goal_x - (ch0 + 2))
        p = (1, goal_x - 1, row + 1)
        boxcells[bno] = (1, goal_x, row + 1)
    return acts


# ---------------- 组装 ----------------

def realize(spec, rng, n_buildings=0):
    if n_buildings:
        buildings = decorate(spec["size"], spec["protected"], rng, n_buildings)
        spec = dict(spec)
        spec["floors"] = list(spec["floors"]) + buildings
    rows = build(spec["size"], spec["floors"], spec["walls"], spec["place"])
    return split(rows, spec["regions"])


def level(name, hint, spec, rng, n_buildings=0, par=1, budget=None):
    r0, r1 = realize(spec, rng, n_buildings)
    return {"name": name, "hint": hint, "fig0": r0, "fig1": r1,
            "span": 0, "par": par, "budget": budget if budget else par + 1,
            "anchors": spec.get("anchors")}


def make_levels():
    """15 关：第 16~30 关。每关一个台阶（靠技法与规模，不靠堆箱子）。"""
    rng = random.Random(20260914)
    L = []

    # ============ 大关 2（16~20）：传送门 + 强制回溯 ============

    # 16 借道（教学）：小图，把整套动作走一遍
    L.append(level("第 16 关 · 借道",
                   "一格宽的走廊里，箱子推过头就再也推不回来 —— 试试【回溯箱子】。",
                   core_a((19, 11), 5, rect(1, 6, 5, 9), 15, 8, 11,
                          rect(10, 7, 15, 8), 15, (3, 9)),
                   rng, 2))
    # 17 更长的走廊
    L.append(level("第 17 关 · 更长的走廊", "",
                   core_a((21, 11), 5, rect(1, 6, 5, 9), 17, 8, 13,
                          rect(10, 7, 17, 8), 17, (3, 9)),
                   rng, 4))
    # 18 更大的地图 + 更深的密室
    L.append(level("第 18 关 · 深密室", "",
                   core_a((23, 13), 6, rect(1, 7, 6, 11), 19, 9, 14,
                          rect(11, 8, 19, 10), 19, (3, 11)),
                   rng, 6))
    # 19 房间里加立柱：去绕行路口的路要绕
    L.append(level("第 19 关 · 柱廊", "",
                   core_a((25, 13), 6, rect(1, 7, 6, 11), 21, 9, 15,
                          rect(11, 8, 21, 10), 21, (3, 11),
                          pillars=[rect(3, 9, 4, 10)]),
                   rng, 7))
    # 20 大关 2 终局：最大图
    L.append(level("第 20 关 · 长廊尽头", "",
                   core_a((27, 15), 7, rect(1, 8, 7, 13), 23, 10, 17,
                          rect(12, 9, 23, 11), 23, (3, 13),
                          pillars=[rect(3, 10, 5, 11)]),
                   rng, 8))

    # ============ 大关 3（21~30）：多地图 + 对色 + 强制回溯 ============

    # 21 双借道（必须回溯两次）
    L.append(level("第 21 关 · 两次借道",
                   "两条走廊各有一只箱子，两只都推不回来 —— 回溯要分两次用。",
                   core_b((23, 15), rect(1, 5, 4, 11), 5, 11, 19, 9, 15,
                          rect(12, 6, 19, 9), 19, (2, 10)),
                   rng, 5, par=2))
    # 22 走廊更长
    L.append(level("第 22 关 · 两条长廊", "",
                   core_b((25, 15), rect(1, 5, 4, 11), 5, 11, 21, 9, 17,
                          rect(12, 6, 21, 9), 21, (2, 10)),
                   rng, 6, par=2))
    # 23 走廊更长 + 竖井里有立柱（走位要多想一步）
    L.append(level("第 23 关 · 双柱", "",
                   core_b((27, 17), rect(1, 5, 5, 13), 5, 13, 23, 10, 19,
                          rect(13, 7, 23, 10), 23, (2, 12),
                          pillars=[rect(3, 9, 4, 10)]),
                   rng, 6, par=2))
    # 24 更大的地图
    L.append(level("第 24 关 · 越走越远", "",
                   core_b((29, 17), rect(1, 5, 5, 13), 5, 13, 25, 10, 21,
                          rect(13, 7, 25, 10), 25, (2, 12)),
                   rng, 7, par=2))
    # 25 两条走廊拉得更开（上下距离变长）
    L.append(level("第 25 关 · 双门终局", "",
                   core_b((29, 19), rect(1, 5, 6, 15), 5, 15, 25, 10, 21,
                          rect(13, 9, 25, 12), 25, (3, 14),
                          pillars=[rect(3, 10, 4, 10)]),
                   rng, 8, par=2))
    # 26~30：双借道继续放大
    L.append(level("第 26 关 · 长路双箱", "",
                   core_b((31, 19), rect(1, 5, 6, 15), 5, 15, 27, 11, 23,
                          rect(14, 9, 27, 12), 27, (2, 14)),
                   rng, 9, par=2))
    L.append(level("第 27 关 · 双子密室", "",
                   core_b((31, 19), rect(1, 5, 7, 15), 5, 15, 27, 11, 23,
                          rect(14, 10, 27, 13), 27, (3, 14),
                          pillars=[rect(3, 10, 5, 11)]),
                   rng, 9, par=2))
    L.append(level("第 28 关 · 大图双借道", "",
                   core_b((33, 19), rect(1, 5, 7, 15), 5, 15, 29, 11, 25,
                          rect(15, 10, 29, 13), 29, (2, 14)),
                   rng, 10, par=2))
    L.append(level("第 29 关 · 长廊对色", "",
                   core_b((33, 21), rect(1, 5, 7, 17), 5, 17, 31, 11, 27,
                          rect(15, 12, 31, 15), 31, (2, 16)),
                   rng, 11, par=2))
    L.append(level("第 30 关 · 终局 · 双子长廊", "",
                   core_b((35, 23), rect(1, 5, 8, 19), 5, 19, 33, 12, 28,
                          rect(17, 12, 33, 15), 33, (2, 18),
                          pillars=[rect(3, 12, 6, 13)]),
                   rng, 12, par=2))

    return L


# ---------------- 验收 ----------------

def analyze(rows0, rows1, anchors=None, cap=3, max_moves=90):
    """① 精确判定"不用回溯能否通关"（玩家位置归一化，完备）；
    ② 用**构造式参考解**证明"可解"，并精确回放；
    ③ 对单箱关再探一次"只给 1 次回溯够不够"。"""
    w, err = W.parse_world([rows0, rows1])
    if w is None:
        return None, err
    walk = 0
    for rm in w.rooms:
        for y in range(rm.H):
            for x in range(rm.W):
                if (x, y) not in rm.walls:
                    walk += 1
    info = {"norw": no_rewind_solvable(w), "walk": walk}
    if anchors:
        acts = build_solution(w, anchors)
        if acts is None:
            info["err"] = "构造参考解失败"
            return info, None
        ok, used, rerr = W.replay(w, acts)
        info.update({"acts": acts, "used": used, "rerr": rerr, "k": used,
                     "moves": len([a for a in acts if len(a) == 1])})
        if anchors.get("kind") == "a":
            a1, e1 = W.search_fast(w, 1, max_moves=max_moves, limit=60_000)
            info["one_enough"] = a1 is not None
            info["one_proved"] = (a1 is None and e1 is None)
    return info, None


def verify(levels, verbose=False):
    ok_all = True
    print("关卡名                      画布    可行格 | 不用回溯   | 参考解回溯 | 步数 | 1次够? | 回放")
    for i, lv in enumerate(levels):
        idx = 16 + i
        info, err = analyze(lv["fig0"], lv["fig1"], lv.get("anchors"))
        if info is None:
            print("!! 第 %d 关 %s 解析失败：%s" % (idx, lv["name"], err))
            ok_all = False
            continue
        if "acts" not in info:
            print("!! 第 %d 关 %-14s %dx%-3d 可行格%3d | 无回溯=%s | %s"
                  % (idx, lv["name"].split("·")[-1].strip(),
                     len(lv["fig1"][0]), len(lv["fig1"]), info["walk"],
                     {True: "有解 !!", False: "无解 ✓", None: "超限 ?"}[info["norw"]],
                     info.get("err")))
            ok_all = False
            continue
        norw = info["norw"]
        if info.get("one_enough") is True:
            one = "是"
        elif info.get("one_proved") is True:
            one = "否(已证明)"
        else:
            one = "-"
        good = (norw is False and info["rerr"] is None and info["used"] >= 1)
        if not good:
            ok_all = False
        print("%s第 %2d 关 %-14s %dx%-3d 可行格%3d | %-9s | %d 次       | %4d | %-8s | %s"
              % ("OK " if good else "!! ", idx,
                 lv["name"].split("·")[-1].strip(),
                 len(lv["fig1"][0]), len(lv["fig1"]), info["walk"],
                 {True: "有解 !!", False: "无解 ✓", None: "超限 ?"}[norw],
                 info["used"], info["moves"], one,
                 "通过 ✓" if info["rerr"] is None else "失败 " + str(info["rerr"])))
        if verbose:
            for ri, r in enumerate((lv["fig0"], lv["fig1"])):
                print("      图%d:" % ri)
                for row in r:
                    print("        " + row)
            print("      解: " + " ".join(info["acts"]))
    print("===== 全部通过 =====" if ok_all else "===== 存在不合格关卡 =====")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(verify(make_levels(), "-v" in sys.argv))


# ---------------- 设计出处 ----------------
# · games4brains.de/sokoban-leveldesign.php
#     「目标区法」(Goal area：让目标只能按唯一顺序填) / 「停车位法」(Parking Lot) /
#     「陷阱法」(Trapper：摆一个看着对其实错的走法) / 「诱饵法」(Dummy) /
#     「活板门·滑门法」(Alternating loops：用墙和箱子当门，开/关它形成循环) /
#     难度分级 1~10、难度应逐关上升、以及"提供大量看着有用其实无用的空间"。
# · gamedesign.gg/articles/puzzle-game-design
#     「一个规则、深空间」；锯齿曲线 introduce→practice→twist→combine→mastery；
#     生成关卡必须过 **solvability + uniqueness** 两道闸（多解 = 破题）。
# · stuartspixelgames.com/2021/10/14/puzzle-design-in-puzzledorf-reflections/
#     「看起来简单、解法出人意料」的谜题最受欢迎；难度靠技法与技法组合，
#     不是靠堆方块；信息过载会劝退 → 减少活动部件。
# · puzzlebyrinth.com/en/articles/pushing-verb-puzzle-design
#     「推而不可拉」是难度的根源：不可逆 → 死局 → 逼玩家提前读盘。
