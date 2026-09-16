# -*- coding: utf-8 -*-
"""Reverse Box 规则引擎（Python 参考实现）。

严格复刻 scripts/game_manager.gd + scripts/time_trail.gd 的语义：
  - 轨迹：每个对象一条 [起点, 之后每次位置变化]（连续同格不重复记录）
  - 移动：推箱规则，推不动则整次作废
  - 回溯：选一个对象 + 它的某个"严格过去节点"，目标格必须可走且当前无任何对象
          落地后该对象轨迹被截断到该节点，扣 1 次配额
  - 通关：所有目标点被箱子占住

对外接口：
  parse(rows)                  -> Lv | (None, err)
  replay(lv, actions)          -> (win, rewinds_used, err)
  solve_no_rewind(rows)        -> actions | None          （当普通推箱子做 BFS）
  search(rows, budget, ...)    -> actions | None          （含回溯的 BFS）
  min_rewinds(rows, cap)       -> (k, actions) | (None, None)
"""
from collections import deque

MOVES = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}

# 回溯距离上限：0 = 可回到任意过去；>0 = 只能回到不超过这么多步之前（第二大关）
SPAN = 0


def set_span(v):
    """设置当前关卡的回溯距离上限（每个关卡检查前调一次）。"""
    global SPAN
    SPAN = int(v or 0)


class Lv:
    __slots__ = ("W", "H", "walls", "goals", "boxes", "player", "rows")

    def __init__(self, W, H, walls, goals, boxes, player, rows):
        self.W, self.H = W, H
        self.walls = walls          # frozenset[(x,y)]
        self.goals = goals          # frozenset[(x,y)]
        self.boxes = boxes          # tuple[(x,y)] 行优先
        self.player = player
        self.rows = rows


def parse(rows, strict=True):
    lines = [r for r in rows if r.strip()]
    if not lines:
        return None, "空布局"
    W = max(len(r) for r in lines)
    if strict and len({len(r) for r in lines}) != 1:
        return None, "行宽不一致"
    H = len(lines)
    walls, goals, boxes, player = set(), set(), [], None
    for y in range(H):
        for x in range(W):
            ch = lines[y][x] if x < len(lines[y]) else "#"
            c = (x, y)
            if ch == "#":
                walls.add(c)
            elif ch == "*":
                goals.add(c)
            elif ch == ".":
                pass
            elif ch == "$":
                boxes.append(c)
            elif ch == "&":
                boxes.append(c)
                goals.add(c)
            elif ch == "@":
                player = c
            elif ch == "+":
                player = c
                goals.add(c)
            else:
                return None, f"非法字符 {ch!r} @({x},{y})"
    if strict:
        if player is None:
            return None, "没有玩家"
        if len(boxes) != len(goals):
            return None, f"箱 {len(boxes)} != 目标 {len(goals)}"
        for x in range(W):
            if (x, 0) not in walls or (x, H - 1) not in walls:
                return None, "上下边框不封闭"
        for y in range(H):
            if (0, y) not in walls or (W - 1, y) not in walls:
                return None, "左右边框不封闭"
    return Lv(W, H, frozenset(walls), frozenset(goals), tuple(boxes), player, lines), None


def walkable(lv, c):
    return 0 <= c[0] < lv.W and 0 <= c[1] < lv.H and c not in lv.walls


def _init_state(lv):
    """(player, boxes, ptrail, btrails, left)"""
    return (lv.player, lv.boxes, (lv.player,), tuple((b,) for b in lv.boxes), None)


def _box_cells(state):
    return set(state[1])


def valid_nodes(state, obj):
    """obj: 0=玩家, k+1=第 k 个箱子。返回可落地的历史节点下标列表。"""
    player, boxes, ptrail, btrails, _ = state
    trail = ptrail if obj == 0 else btrails[obj - 1]
    if len(trail) < 2:
        return []
    occupied = set(boxes)
    occupied.add(player)
    cur = trail[-1]
    out = []
    for i in range(len(trail) - 1):          # 严格过去
        dest = trail[i]
        if dest == cur:
            continue
        if SPAN > 0 and (len(trail) - 1 - i) > SPAN:   # 距离上限（第二大关）
            continue
        if not walkable_static(dest):
            continue
        if obj == 0:
            if dest in set(boxes):           # 玩家回溯：不能落在箱子上
                continue
        else:
            others = set(boxes) - {cur}
            if dest in others or dest == player:
                continue
        out.append(i)
    return out


def walkable_static(c):
    """由各入口函数在解析关卡后替换为当前关卡的判定函数。"""
    raise RuntimeError("walkable_static 未初始化")


def _mk_walk(lv):
    walls = lv.walls
    W, H = lv.W, lv.H

    def f(c):
        return 0 <= c[0] < W and 0 <= c[1] < H and c not in walls

    return f


def apply_move(lv, state, ch):
    dx, dy = MOVES[ch]
    player, boxes, ptrail, btrails, left = state
    to = (player[0] + dx, player[1] + dy)
    if not walkable_static(to):
        return None
    boxset = list(boxes)
    if to in boxset:
        beyond = (to[0] + dx, to[1] + dy)
        if not walkable_static(beyond) or beyond in boxset:
            return None
        k = boxset.index(to)
        boxset[k] = beyond
        bt = list(btrails)
        t = list(bt[k])
        if t[-1] != beyond:
            t.append(beyond)
        bt[k] = tuple(t)
        new_ptrail = ptrail + (to,) if ptrail[-1] != to else ptrail
        return (to, tuple(boxset), new_ptrail, tuple(bt), left)
    new_ptrail = ptrail + (to,) if ptrail[-1] != to else ptrail
    return (to, boxes, new_ptrail, btrails, left)


def apply_rewind(lv, state, obj, node):
    player, boxes, ptrail, btrails, left = state
    if left is None or left <= 0:
        return None
    if node not in valid_nodes(state, obj):
        return None
    if obj == 0:
        dest = ptrail[node]
        return (dest, boxes, ptrail[: node + 1], btrails, left - 1)
    k = obj - 1
    t = btrails[k]
    dest = t[node]
    boxes2 = list(boxes)
    boxes2[k] = dest
    bt = list(btrails)
    bt[k] = t[: node + 1]
    return (player, tuple(boxes2), ptrail, tuple(bt), left - 1)


def won(lv, state):
    return all(b in lv.goals for b in state[1])


# ---------------- 纯推箱子 BFS（无回溯） ----------------

def search_fast(rows, budget, max_moves=None, limit=300_000, allow_player=True, allow_box=True):
    """快速搜索：动作生成用完整状态，但「已访问」只看 (玩家, 箱子, 剩余次数)。

    轨迹历史被折叠 —— 不是完备搜索，但速度提高几十倍；找到的解必须再用 replay() 精确验证。
    """
    lv, err = parse(rows)
    if lv is None:
        return None, err
    global walkable_static
    walkable_static = _mk_walk(lv)
    start = (lv.player, lv.boxes, (lv.player,), tuple((b,) for b in lv.boxes), budget)
    seen = {(start[0], start[1], start[4])}
    q = deque([(start, [], 0)])
    while q:
        state, acts, nmoves = q.popleft()
        if won(lv, state):
            ok, used, rerr = replay(rows, acts)
            if ok:
                return acts, None
        succ = []
        for ch in MOVES:
            ns = apply_move(lv, state, ch)
            if ns is not None:
                succ.append((ns, ch))
        if state[4] > 0:
            objs = list(range(1 + len(state[1])))
            if not allow_player:
                objs = [o for o in objs if o != 0]
            if not allow_box:
                objs = [o for o in objs if o == 0]
            for obj in objs:
                for node in valid_nodes(state, obj):
                    ns = apply_rewind(lv, state, obj, node)
                    if ns is not None:
                        tag = f"P{node}" if obj == 0 else f"B{obj - 1}:{node}"
                        succ.append((ns, tag))
        for ns, tag in succ:
            key = (ns[0], ns[1], ns[4])
            if key in seen:
                continue
            if len(tag) == 1 and max_moves is not None and nmoves + 1 > max_moves:
                continue
            seen.add(key)
            if len(seen) > limit:
                return None, "状态爆炸"
            q.append((ns, acts + [tag], nmoves + (1 if len(tag) == 1 else 0)))
    return None, None


def min_rewinds_fast(rows, cap=4, max_moves=None):
    for k in range(0, cap + 1):
        acts, err = search_fast(rows, k, max_moves=max_moves)
        if acts is not None:
            return k, acts
        if err and err != "状态爆炸":
            return None, err
    return None, None


def solve_no_rewind(rows, limit=2_000_000):
    lv, err = parse(rows)
    if lv is None:
        return None, err
    global walkable_static
    walkable_static = _mk_walk(lv)
    start = (lv.player, lv.boxes)
    seen = {start}
    q = deque([(start, [])])
    while q:
        (player, boxes), acts = q.popleft()
        if all(b in lv.goals for b in boxes):
            return acts, None
        st = (player, boxes, (player,), tuple((b,) for b in boxes), 99)
        for ch in MOVES:
            ns = apply_move(lv, st, ch)
            if ns is None:
                continue
            key = (ns[0], ns[1])
            if key in seen:
                continue
            seen.add(key)
            if len(seen) > limit:
                return None, "状态爆炸"
            q.append((key, acts + [ch]))
    return None, None


# ---------------- 含回溯的 BFS ----------------

def search(rows, budget, max_moves=None, limit=900_000, allow_player=True, allow_box=True):
    lv, err = parse(rows)
    if lv is None:
        return None, err
    global walkable_static
    walkable_static = _mk_walk(lv)
    start = (lv.player, lv.boxes, (lv.player,), tuple((b,) for b in lv.boxes), budget)
    seen = {start}
    q = deque([(start, [], 0)])
    while q:
        state, acts, nmoves = q.popleft()
        if won(lv, state):
            return acts, None
        succ = []
        for ch in MOVES:
            ns = apply_move(lv, state, ch)
            if ns is not None:
                succ.append((ns, ch))
        if state[4] > 0:
            objs = list(range(1 + len(state[1])))
            if not allow_player:
                objs = [o for o in objs if o != 0]
            if not allow_box:
                objs = [o for o in objs if o == 0]
            for obj in objs:
                for node in valid_nodes(state, obj):
                    ns = apply_rewind(lv, state, obj, node)
                    if ns is not None:
                        tag = f"P{node}" if obj == 0 else f"B{obj - 1}:{node}"
                        succ.append((ns, tag))
        for ns, tag in succ:
            key = (ns[0], ns[1], ns[2], ns[3], ns[4])
            if key in seen:
                continue
            seen.add(key)
            if len(seen) > limit:
                return None, "状态爆炸"
            if len(tag) == 1:
                if max_moves is not None and nmoves + 1 > max_moves:
                    continue
                q.append((ns, acts + [tag], nmoves + 1))
            else:
                q.append((ns, acts + [tag], nmoves))
    return None, None


def min_rewinds(rows, cap=4, max_moves=None):
    for k in range(0, cap + 1):
        acts, err = search(rows, k, max_moves=max_moves)
        if acts is not None:
            return k, acts
        if err and err != "状态爆炸":
            return None, err
    return None, None


# ---------------- 参考解回放 ----------------

def replay(rows, actions, verbose=False):
    lv, err = parse(rows)
    if lv is None:
        return False, 0, err
    global walkable_static
    walkable_static = _mk_walk(lv)
    state = (lv.player, lv.boxes, (lv.player,), tuple((b,) for b in lv.boxes), 99)
    used = 0
    for i, a in enumerate(actions):
        if a in MOVES:
            ns = apply_move(lv, state, a)
            if ns is None:
                return False, used, f"第 {i+1} 步 {a} 非法（推不动/撞墙）"
        elif a.startswith("P") or a.startswith("B"):
            ns0 = state
            ns0 = (ns0[0], ns0[1], ns0[2], ns0[3], 99)   # 回放时忽略配额
            if a.startswith("P"):
                obj, node = 0, int(a[1:])
            else:
                k, node = a[1:].split(":")
                obj, node = int(k) + 1, int(node)   # B<箱序号(0基)> → 引擎对象序号 1+箱号
            ns = apply_rewind(lv, ns0, obj, node)
            if ns is None:
                return False, used, f"第 {i+1} 步 {a} 非法（节点不可选/已无配额）"
            used += 1
        else:
            return False, used, f"未知动作 {a!r}"
        state = ns
        if verbose:
            print(f"  {i+1:>3} {a:<6} 玩家{state[0]} 箱{state[1]} 剩{state[4]}")
    return won(lv, state), used, None


def render(rows):
    return "\n".join(rows)
