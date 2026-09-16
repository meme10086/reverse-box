# -*- coding: utf-8 -*-
"""大关 2/3 重做版生成器：**大图 + 密室传送门 + 强制回溯**。

母题（"借道"）—— 为什么不用回溯就绝对过不去：

      ┌── 绕行口袋（只绕开门 A 那一格）──┐
      │                                 │
  ┌───┴─────────────────────────────┐   │
  │ 左屋 @ ── 走廊 ──[A门]── 箱 a ──→→→→ 死路尽头
  └────────┬────────────────────────┘
           │ B门                    ┌── 密室（被墙封死）──┐
           └───────────────────────→│ A门出口 →→→ 颜色地砖 │
                                    └────────────────────┘

  · 箱子在 1 格宽走廊里，玩家在它**左边**；走廊另一头是死路。
  · 玩家永远绕不到箱子右边（只有门 A 那一格开了绕行口袋，别处没开）
    → 只能把箱子往右推到尽头（右侧是墙，谁都推不动）。
  · 唯一出路是**回溯箱子**，把它送回起点；玩家此时正好在它右边，可以往左推。
  · 往左推 → 箱子被推进 A 门 → 出现在**被墙封死的密室**里。
  · 玩家想跟进去必须走 B 门 —— 因为 A 门的出口被箱子占着
    （"单门口运箱必然死局"这条规则在这里正好成了谜题）。

**强制回溯是结构性的**：不用回溯 → 箱子永远停在死路尽头 → 无解。

用法：
  python rb_gen4.py            # 自检全部关卡
  python rb_gen4.py -v         # 同时打印地图与引擎解
环境变量：G4_MINMOVES 过滤（默认 0）
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_world as W   # noqa: E402


def mk(spec):
    W_, H_ = spec["size"]
    g = [["#"] * W_ for _ in range(H_)]
    for (x0, y0, x1, y1) in spec["carve"]:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g[y][x] = "."
    for (cell, ch) in spec["place"]:
        x, y = cell
        g[y][x] = ch
    return ["".join(r) for r in g]


def base(corr_x1, a_out, box, a_in, goal, b_out, b_in, player,
         corr_y=4, room=(1, 5, 3, 7), chamber=(5, 6, 10, 7),
         bypass=(3, 3, 5, 3), size=(15, 9),
         box_color="a", goal_color="1", extra_carve=(), extra_place=()):
    carve = [
        (room[0], room[1], room[2], room[3]),                     # 左屋
        (1, corr_y, corr_x1, corr_y),                             # 走廊（尽头封死）
        (bypass[0], bypass[1], bypass[2], bypass[3]),             # 绕行口袋
        (chamber[0], chamber[1], chamber[2], chamber[3]),         # 密室
    ] + list(extra_carve)
    place = [
        (a_out, "A"), (a_in, "A"),
        (b_out, "B"), (b_in, "B"),
        (box, box_color), (goal, goal_color),
        (player, "@"),
    ] + list(extra_place)
    return {"size": size, "carve": carve, "place": place,
            "chamber_rect": chamber}


def split_rooms(spec):
    """把单图版拆成两张地图：
      图0 = 外面（走廊 / 绕行口袋 / 左屋），**密室那一块填成墙** —— 走不进去；
      图1 = 只有密室（其余全是墙）—— 只能靠传送门进。
    两张图尺寸一致，所以坐标系统一，切换地图不会错位。"""
    rows = mk(spec)
    W_, H_ = spec["size"]
    cx0, cy0, cx1, cy1 = spec["chamber_rect"]
    r0 = [list(r) for r in rows]
    r1 = [["#"] * W_ for _ in range(H_)]
    for y in range(cy0, cy1 + 1):
        for x in range(cx0, cx1 + 1):
            r1[y][x] = rows[y][x]
            r0[y][x] = "#"
    return ["".join(r) for r in r0], ["".join(r) for r in r1]


def make_levels():
    """15 关：第 16~30 关，由易到难（每一关都是"不用回溯绝对过不去"的硬关）。"""
    L = []
    T = tuple  # noqa

    # ---- 16~18：单箱入门。走廊变长 → 密室变深 ----
    L.append(base(10, (4, 4), (6, 4), (7, 6), (10, 6), (1, 4), (6, 6), (3, 6)))
    L.append(base(11, (4, 4), (6, 4), (8, 6), (11, 6), (1, 4), (6, 6), (3, 6),
                  chamber=(5, 6, 11, 7)))
    L.append(base(12, (4, 4), (6, 4), (9, 6), (12, 6), (1, 4), (6, 6), (3, 6),
                  chamber=(5, 6, 12, 7), size=(16, 9)))

    # ---- 19~21：地图更大、走廊更长；其中 20 的目标在第 7 行（箱子必须从第 7 行的门进来）----
    L.append(base(13, (5, 4), (7, 4), (10, 6), (13, 6), (1, 4), (6, 6), (3, 6),
                  chamber=(6, 6, 13, 7), size=(17, 9), bypass=(4, 3, 6, 3)))
    L.append(base(13, (4, 4), (7, 4), (11, 7), (13, 7), (1, 4), (6, 6), (3, 6),
                  chamber=(5, 6, 13, 7), size=(17, 9)))
    L.append(base(14, (4, 4), (7, 4), (11, 6), (14, 6), (1, 4), (7, 6), (3, 6),
                  chamber=(5, 6, 14, 7), size=(18, 9)))

    # ---- 22~24：两个箱子、两种颜色（一个从门来、一个本来就在密室里）----
    L.append(base(12, (4, 4), (6, 4), (7, 6), (11, 6), (1, 4), (5, 6), (3, 6),
                  chamber=(5, 6, 12, 7), size=(16, 9),
                  extra_place=[((6, 7), "b"), ((11, 7), "2")]))
    L.append(base(13, (4, 4), (7, 4), (8, 6), (12, 6), (1, 4), (5, 6), (3, 6),
                  chamber=(5, 6, 13, 7), size=(17, 9),
                  extra_place=[((6, 7), "b"), ((13, 7), "2")]))
    L.append(base(14, (5, 4), (8, 4), (9, 6), (13, 6), (1, 4), (6, 6), (3, 6),
                  chamber=(6, 6, 14, 7), size=(18, 9), bypass=(4, 3, 6, 3),
                  extra_place=[((7, 7), "b"), ((14, 7), "2")]))

    # ---- 25~27：两个箱子 + 走廊更长 ----
    L.append(base(13, (4, 4), (7, 4), (8, 6), (12, 6), (1, 4), (5, 6), (3, 6),
                  chamber=(5, 6, 13, 7), size=(17, 9),
                  extra_place=[((6, 7), "b"), ((12, 7), "2")]))
    L.append(base(14, (5, 4), (8, 4), (9, 6), (13, 6), (1, 4), (6, 6), (3, 6),
                  chamber=(6, 6, 14, 7), size=(18, 9), bypass=(4, 3, 6, 3),
                  extra_place=[((7, 7), "b"), ((13, 7), "2")]))
    L.append(base(15, (5, 4), (8, 4), (9, 6), (14, 6), (1, 4), (6, 6), (3, 6),
                  chamber=(6, 6, 15, 7), size=(19, 9), bypass=(4, 3, 6, 3),
                  extra_place=[((7, 7), "b"), ((14, 7), "2")]))

    # ---- 28~30：终局。地图最大、走廊最长、双箱双色 ----
    L.append(base(16, (5, 4), (9, 4), (10, 6), (15, 6), (1, 4), (7, 6), (3, 6),
                  chamber=(6, 6, 16, 7), size=(20, 9), bypass=(4, 3, 6, 3),
                  extra_place=[((7, 7), "b"), ((15, 7), "2")]))
    L.append(base(16, (5, 4), (9, 4), (10, 7), (15, 7), (1, 4), (7, 6), (3, 6),
                  chamber=(6, 6, 16, 7), size=(20, 9), bypass=(4, 3, 6, 3),
                  extra_place=[((8, 6), "b"), ((15, 6), "2")]))
    L.append(base(17, (6, 4), (10, 4), (11, 6), (16, 6), (1, 4), (7, 6), (3, 6),
                  chamber=(7, 6, 17, 7), size=(21, 9), bypass=(5, 3, 7, 3),
                  extra_place=[((8, 7), "b"), ((16, 7), "2")]))

    return L


def verify(levels, verbose=False):
    ok_all = True
    minmoves = int(os.environ.get("G4_MINMOVES", "0"))
    for i, spec in enumerate(levels):
        idx = 16 + i
        rooms = split_rooms(spec)
        w, err = W.parse_world(list(rooms))
        if w is None:
            print("!! 第 %d 关 解析失败：%s" % (idx, err))
            ok_all = False
            continue
        norw = W.solve_no_rewind(w, limit=400_000)[0]
        k, acts = W.min_rewinds(w, cap=3, max_moves=64)
        moves = len([a for a in acts if len(a) == 1]) if acts else None
        good = W.replay(w, acts)[0] if acts else False
        flag = "OK " if (norw is None and good and k and k >= 1
                         and (moves or 0) >= minmoves) else "!! "
        if flag == "!! ":
            ok_all = False
        print("%s第 %d 关 %dx%d 箱%d 图%d | 无回溯=%s | 最少回溯 %s，步数 %s，回放 %s" % (
            flag, idx, spec["size"][0], spec["size"][1], len(w.box_start), len(w.rooms),
            "无解 ✓" if norw is None else "有解 !!", k if k is not None else -1,
            moves if moves else "-", "通过 ✓" if good else "失败"))
        if verbose:
            for ri, room in enumerate(rooms):
                print("      图%d:" % ri)
                for r in room:
                    print("        " + r)
            if acts:
                print("      解: " + " ".join(acts))
    print("===== 全部通过 =====" if ok_all else "===== 存在不合格关卡 =====")
    return 0 if ok_all else 1


if __name__ == "__main__":
    raise SystemExit(verify(make_levels(), "-v" in sys.argv))
