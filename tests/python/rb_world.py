# -*- coding: utf-8 -*-
"""Reverse Box 多地图引擎（Python 参考实现）。

严格复刻 scripts/game_manager.gd + scripts/level_manager.gd 的语义，并在此基础上支持：
  - 多张地图（一张关卡 = 若干张同样尺寸的地图）
  - 传送门（A/B/C 成对出现；玩家和箱子都能过门）
  - 颜色匹配（箱子有颜色 a/b/c，地砖有颜色 1/2/3，同色才算到位）

与单图引擎 rb_engine.py 的分工：
  rb_engine.py  只做单图（大关 1 / 大关 2 的纯距离关），已验证，保持不变
  rb_world.py   单图 + 多图 + 传送门 + 颜色（大关 2 的传送门关 / 大关 3 全部）

对外接口（与 rb_engine 同构）：
  parse_world(layouts)            -> World | (None, err)
  replay(world, actions)          -> (win, rewinds_used, err)
  solve_no_rewind(world)          -> actions | None
  search_fast(world, budget, ...) -> actions | None
  search(world, budget, ...)      -> actions | None
  min_rewinds(world, cap)         -> (k, actions)

关键语义（与 GDScript 对齐，改引擎时两边必须一起改）：
  1. 推箱过门：箱子前方是门 → 箱子出现在对面那格；玩家留在原地（人箱分离）。
  2. 玩家过门：玩家走到门上 → 立刻出现在对面那格；对面被箱子占着则整步作废。
  3. **推箱这一下，玩家不触发传送**（脚底下踩到门也不被吸走）。
  4. 颜色：箱子压在同色地砖上才算到位；异色不算。
"""
from collections import deque

MOVES = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}

# 回溯距离上限：0 = 可回到任意过去；>0 = 只能回到不超过这么多步之前
SPAN = 0


def set_span(v):
    global SPAN
    SPAN = int(v or 0)


class Room:
    __slots__ = ("W", "H", "walls", "goal_color", "player", "rows")

    def __init__(self, W, H, walls, goal_color, player, rows):
        self.W, self.H = W, H
        self.walls = walls              # frozenset[(x,y)]
        self.goal_color = goal_color    # {(x,y): 颜色编号}  0 = 无色
        self.player = player            # (x,y) | None
        self.rows = rows


class World:
    __slots__ = ("rooms", "portals", "box_start", "box_colors", "start_player",
                 "layouts", "goal_count")

    def __init__(self, rooms, portals, box_start, box_colors, start_player, layouts):
        self.rooms = rooms
        self.portals = portals          # {(r,x,y): (r,x,y)} 双向
        self.box_start = box_start      # tuple[(r,x,y)] 行优先（= 箱号顺序）
        self.box_colors = box_colors    # tuple[int]       与箱号一一对应
        self.start_player = start_player  # (r,x,y)
        self.layouts = layouts
        self.goal_count = sum(len(rm.goal_color) for rm in rooms)


def parse_world(layouts, strict=True):
    """layouts: [[行...], [行...]] —— 一张或多张地图。"""
    if layouts and isinstance(layouts[0], str):
        layouts = [layouts]
    rooms, portals, letters = [], {}, {}
    box_start, box_colors = [], []
    start_player = None

    for ri, rows in enumerate(layouts):
        lines = [r for r in rows if r.strip()]
        if not lines:
            return None, "空布局"
        W = max(len(r) for r in lines)
        if strict and len({len(r) for r in lines}) != 1:
            return None, f"第 {ri} 张图行宽不一致"
        H = len(lines)
        walls, gc, ps = set(), {}, None
        for y in range(H):
            for x in range(W):
                ch = lines[y][x] if x < len(lines[y]) else "#"
                c = (x, y)
                if ch == "#":
                    walls.add(c)
                elif ch == ".":
                    pass
                elif ch == "*":
                    gc[c] = 0
                elif ch in "123":
                    gc[c] = int(ch)
                elif ch == "$":
                    box_start.append((ri, x, y)); box_colors.append(0)
                elif ch == "&":
                    box_start.append((ri, x, y)); box_colors.append(0); gc[c] = 0
                elif ch in "abc":
                    box_start.append((ri, x, y)); box_colors.append("abc".index(ch) + 1)
                elif ch == "@":
                    ps = c
                elif ch == "+":
                    ps = c; gc[c] = 0
                elif ch in "ABCD":
                    letters.setdefault(ch, []).append((ri, c))
                else:
                    return None, f"非法字符 {ch!r} @图{ri}({x},{y})"
        if strict:
            for x in range(W):
                if (x, 0) not in walls or (x, H - 1) not in walls:
                    return None, f"第 {ri} 张图上下边框不封闭"
            for y in range(H):
                if (0, y) not in walls or (W - 1, y) not in walls:
                    return None, f"第 {ri} 张图左右边框不封闭"
        if ri == 0:
            if ps is None:
                return None, "第 0 张图没有玩家"
            start_player = (0, ps[0], ps[1])
        rooms.append(Room(W, H, frozenset(walls), gc, ps, lines))

    if not rooms:
        return None, "没有任何地图"
    if len({(r.W, r.H) for r in rooms}) != 1:
        return None, "各张地图尺寸必须一致（引擎按同一坐标系摆放对象）"

    for ch in sorted(letters):
        ends = letters[ch]
        if len(ends) != 2:
            return None, f"传送门 {ch} 需要恰好两端，实际 {len(ends)}"
        (r1, c1), (r2, c2) = ends
        portals[(r1, c1[0], c1[1])] = (r2, c2[0], c2[1])
        portals[(r2, c2[0], c2[1])] = (r1, c1[0], c1[1])

    if strict and len(box_start) != sum(len(r.goal_color) for r in rooms):
        return None, f"箱 {len(box_start)} != 目标 {sum(len(r.goal_color) for r in rooms)}"

    return World(rooms, portals, tuple(box_start), tuple(box_colors),
                 start_player, layouts), None


def walkable(w, c):
    r, x, y = c
    if r < 0 or r >= len(w.rooms):
        return False
    rm = w.rooms[r]
    return 0 <= x < rm.W and 0 <= y < rm.H and (x, y) not in rm.walls


def goal_color_at(w, c):
    r, x, y = c
    return w.rooms[r].goal_color.get((x, y), None)


def _init_state(w):
    box0 = w.box_start
    return (w.start_player, box0, (w.start_player,),
            tuple((b,) for b in box0), None)


def won(w, state):
    boxes = state[1]
    for i, b in enumerate(boxes):
        if goal_color_at(w, b) != w.box_colors[i]:
            return False
    return True


def valid_nodes(w, state, obj):
    """obj: 0 = 玩家；k+1 = 第 k 个箱子。返回可落地的历史节点下标。"""
    player, boxes, ptrail, btrails, _ = state
    trail = ptrail if obj == 0 else btrails[obj - 1]
    if len(trail) < 2:
        return []
    cur = trail[-1]
    out = []
    for i in range(len(trail) - 1):
        dest = trail[i]
        if dest == cur:
            continue
        if SPAN > 0 and (len(trail) - 1 - i) > SPAN:
            continue
        if not walkable(w, dest):
            continue
        if obj == 0:
            if dest in boxes:
                continue
        else:
            if any(dest == b for j, b in enumerate(boxes) if j != obj - 1):
                continue
            if dest == player:
                continue
        out.append(i)
    return out


def apply_move(w, state, ch):
    dx, dy = MOVES[ch]
    player, boxes, ptrail, btrails, left = state
    r, px, py = player
    to = (r, px + dx, py + dy)
    if not walkable(w, to):
        return None

    new_boxes, new_btrails = boxes, btrails
    pushed = False
    if to in boxes:
        bi = boxes.index(to)
        beyond = (r, to[1] + dx, to[2] + dy)
        dest = w.portals.get(beyond)
        if dest is None:
            if not walkable(w, beyond) or beyond in boxes:
                return None
            nb = list(boxes)
            nb[bi] = beyond
            new_boxes = tuple(nb)
        else:
            if dest in boxes:                    # 对面门口被占 → 推不动
                return None
            nb = list(boxes)
            nb[bi] = dest
            new_boxes = tuple(nb)
        bt = list(btrails)
        t = list(bt[bi])
        if t[-1] != new_boxes[bi]:
            t.append(new_boxes[bi])
        bt[bi] = tuple(t)
        new_btrails = tuple(bt)
        pushed = True

    new_player = to
    if not pushed:
        dest = w.portals.get(to)
        if dest is not None:
            if dest in boxes:                    # 对面门口被箱子占着 → 进不去
                return None
            new_player = dest

    if ptrail[-1] != new_player:
        ptrail = ptrail + (new_player,)
    return (new_player, new_boxes, ptrail, new_btrails, left)


def apply_rewind(w, state, obj, node):
    player, boxes, ptrail, btrails, left = state
    if left is None or left <= 0:
        return None
    if node not in valid_nodes(w, state, obj):
        return None
    if obj == 0:
        return (ptrail[node], boxes, ptrail[: node + 1], btrails, left - 1)
    k = obj - 1
    t = btrails[k]
    nb = list(boxes)
    nb[k] = t[node]
    bt = list(btrails)
    bt[k] = t[: node + 1]
    return (player, tuple(nb), ptrail, tuple(bt), left - 1)


# ---------------- 无回溯（当普通推箱子做 BFS） ----------------

def solve_no_rewind(w, limit=2_000_000):
    start = (w.start_player, w.box_start)
    seen = {start}
    q = deque([(start, [])])
    while q:
        (player, boxes), acts = q.popleft()
        st = (player, boxes, (player,), tuple((b,) for b in boxes), 99)
        if won(w, st):
            return acts, None
        for ch in MOVES:
            ns = apply_move(w, st, ch)
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


# ---------------- 含回溯的搜索 ----------------

def search_fast(w, budget, max_moves=None, limit=300_000,
                allow_player=True, allow_box=True):
    """折叠式搜索：动作生成用完整状态，visited 只看 (玩家, 箱子, 剩余次数)。
    找到的解必须再用 replay() 精确验证。"""
    start = (w.start_player, w.box_start, (w.start_player,),
             tuple((b,) for b in w.box_start), budget)
    seen = {(start[0], start[1], start[4])}
    q = deque([(start, [], 0)])
    while q:
        state, acts, nmoves = q.popleft()
        if won(w, state):
            ok, used, _ = replay(w, acts)
            if ok:
                return acts, None
        succ = []
        for ch in MOVES:
            ns = apply_move(w, state, ch)
            if ns is not None:
                succ.append((ns, ch))
        if state[4] > 0:
            objs = list(range(1 + len(state[1])))
            if not allow_player:
                objs = [o for o in objs if o != 0]
            if not allow_box:
                objs = [o for o in objs if o == 0]
            for obj in objs:
                for node in valid_nodes(w, state, obj):
                    ns = apply_rewind(w, state, obj, node)
                    if ns is not None:
                        succ.append((ns, f"P{node}" if obj == 0 else f"B{obj - 1}:{node}"))
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


def search(w, budget, max_moves=None, limit=900_000,
           allow_player=True, allow_box=True):
    """完整搜索：visited 含轨迹，最慢但最严格。"""
    start = (w.start_player, w.box_start, (w.start_player,),
             tuple((b,) for b in w.box_start), budget)
    seen = {start}
    q = deque([(start, [], 0)])
    while q:
        state, acts, nmoves = q.popleft()
        if won(w, state):
            return acts, None
        succ = []
        for ch in MOVES:
            ns = apply_move(w, state, ch)
            if ns is not None:
                succ.append((ns, ch))
        if state[4] > 0:
            objs = list(range(1 + len(state[1])))
            if not allow_player:
                objs = [o for o in objs if o != 0]
            if not allow_box:
                objs = [o for o in objs if o == 0]
            for obj in objs:
                for node in valid_nodes(w, state, obj):
                    ns = apply_rewind(w, state, obj, node)
                    if ns is not None:
                        succ.append((ns, f"P{node}" if obj == 0 else f"B{obj - 1}:{node}"))
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


def min_rewinds(w, cap=4, max_moves=None, fast=True):
    fn = search_fast if fast else search
    for k in range(0, cap + 1):
        acts, err = fn(w, k, max_moves=max_moves)
        if acts is not None:
            return k, acts
        if err and err != "状态爆炸":
            return None, err
    return None, None


# ---------------- 参考解回放 ----------------

def replay(w, actions, verbose=False):
    state = _init_state(w)
    state = (state[0], state[1], state[2], state[3], 99)   # 回放时忽略配额
    used = 0
    for i, a in enumerate(actions):
        if a in MOVES:
            ns = apply_move(w, state, a)
            if ns is None:
                return False, used, f"第 {i+1} 步 {a} 非法（撞墙/推不动/门口被占）"
        elif a.startswith("P") or a.startswith("B"):
            st99 = (state[0], state[1], state[2], state[3], 99)
            if a.startswith("P"):
                obj, node = 0, int(a[1:])
            else:
                k, node = a[1:].split(":")
                obj, node = int(k) + 1, int(node)
            ns = apply_rewind(w, st99, obj, node)
            if ns is None:
                return False, used, f"第 {i+1} 步 {a} 非法（节点不可选）"
            ns = (ns[0], ns[1], ns[2], ns[3], state[4])
            used += 1
        else:
            return False, used, f"未知动作 {a!r}"
        state = ns
        if verbose:
            print(f"  {i+1:>3} {a:<6} 玩家{state[0]} 箱{state[1]}")
    return won(w, state), used, None


def room_of(w, layouts, ri):
    """把第 ri 张图单独拿出来（方便和单图工具对照）。"""
    return layouts[ri]
