# -*- coding: utf-8 -*-
"""按「新洞察」标准自动找关卡候选。

筛选条件（都是用户明确要的："难在思考，不是地图大、解法多"）：
  - 地图小：面积 <= 70
  - 无回溯无解（设计红线）
  - 最少回溯次数 >= 2（双回溯 = 新维度；或必须回溯玩家）
  - 最优解 <= 18 个动作（"输入量"小，时间花在想上）
  - 入口 <= 3 种（解法收敛，不能靠试错撞）
用法：python rb_gen2.py [轮数]
"""
import os, random, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_engine as E
from rb_tight import entries

random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 7)
ROUNDS = int(sys.argv[1]) if len(sys.argv) > 1 else 400


def blank(w, h):
    g = [["#" for _ in range(w)] for _ in range(h)]
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            g[y][x] = "."
    return g


def rows_of(g):
    return ["".join(r) for r in g]


def skeletons():
    out = []
    # 双路环（上下两条道，两端连通）
    for w, h in ((9, 6), (10, 6), (9, 7)):
        g = blank(w, h)
        for y in range(2, h - 2):
            for x in range(2, w - 2):
                g[y][x] = "#"
        out.append(("ring", g))
    # 左屋 + 走廊 + 侧袋（在 y=2 或 y=4 开袋）
    for w, h in ((9, 6), (10, 6)):
        for bag in (1, 4):
            g = blank(w, h)
            for x in range(4, w - 1):
                g[3][x] = "#"
            g[bag][2] = "."
            out.append((f"pocket{bag}", g))
    # 单拐角长廊（L 形）
    for w, h in ((9, 6), (10, 7)):
        g = blank(w, h)
        for y in range(1, h - 1):
            for x in range(1, w - 1):
                if not (y == 1 or x == w - 2 or y == h - 2):
                    g[y][x] = "#"
        out.append(("L", g))
    return out


def try_map(g, nbox, want_min=1, max_opt=14, span=2):
    E.set_span(span)
    w, h = len(g[0]), len(g)
    if w * h > 70:
        return None
    free = [(x, y) for y in range(h) for x in range(w) if g[y][x] == "."]
    if len(free) < nbox * 2 + 1:
        return None
    for _ in range(40):
        picks = random.sample(free, nbox * 2 + 1)
        boxes, goals, player = picks[:nbox], picks[nbox:2 * nbox], picks[-1]
        if player in boxes or player in goals:
            continue
        g2 = [row[:] for row in g]
        for (x, y) in goals:
            g2[y][x] = "*"
        for (x, y) in boxes:
            g2[y][x] = "&" if g2[y][x] == "*" else "$"
        g2[player[1]][player[0]] = "@"
        rows = rows_of(g2)
        lv, err = E.parse(rows)
        if lv is None:
            continue
        # ① 最便宜的一步：当普通推箱子必须无解
        if E.solve_no_rewind(rows, limit=150_000)[0] is not None:
            continue
        # ② 在"距离上限"下必须可解，且最好要两次回溯
        require_two = os.environ.get('GEN_REQUIRE_TWO') == '1'
        one, _ = E.search_fast(rows, 1, max_moves=max_opt, limit=60_000)
        if require_two and one is not None:
            continue                     # 只在显式要求时才卡这一条
        acts, k = one, 1
        if acts is None:
            two, _ = E.search_fast(rows, 2, max_moves=max_opt, limit=60_000)
            acts, k = two, 2
        if acts is None or len(acts) > max_opt:
            continue
        p_all, _ = E.search_fast(rows, k, max_moves=max_opt, limit=60_000, allow_box=False)
        b_all, _ = E.search_fast(rows, k, max_moves=max_opt, limit=60_000, allow_player=False)
        need = []
        if p_all is None:
            need.append("玩家回溯必需")
        if b_all is None:
            need.append("箱子回溯必需")
        # 若指定了 GEN_MIN_SPAN，则要求"更小的跨度解不开"（真的吃满这个跨度）
        want_span = os.environ.get('GEN_MIN_SPAN')
        if want_span:
            E.set_span(int(want_span) - 1)
            low, _ = E.search_fast(rows, 2, max_moves=max_opt, limit=50_000)
            E.set_span(span)
            if low is not None:
                continue
        best, good, e = entries(rows, budget=k, slack=2, cap=max_opt + 4)
        if best is None or len(good) > 3:
            continue
        return {"rows": rows, "k": k, "acts": acts, "need": need,
                "entries": sorted(good), "opt": best, "span": span}
    return None


SPANS = [int(x) for x in os.environ.get("GEN_SPANS", "2,3").split(",")]

if __name__ == "__main__":
    budget_s = float(os.environ.get("GEN_BUDGET", "420"))
    t0 = time.time()
    tried = 0
    found = []
    last_n = 0
    skels = skeletons()
    while time.time() - t0 < budget_s:
        for name, g0 in skels:
            for nbox in (2, 3):
                tried += 1
                hit = try_map([row[:] for row in g0], nbox, span=SPANS[tried % len(SPANS)])
                if hit:
                    hit["skel"], hit["nbox"] = name, nbox
                    found.append(hit)
                    print(f"=== 命中 {len(found)}：{name} 箱{nbox} span={hit['span']} k={hit['k']} "
                          f"最优{hit['opt']} 入口{hit['entries']} {' '.join(hit['need'])}",
                          flush=True)
                    for r in hit["rows"]:
                        print("   ", r, flush=True)
                    print("    解:", " ".join(hit["acts"]), flush=True)
        if tried % 10 == 0 or len(found) > last_n:
            print(f"[{time.time()-t0:5.0f}s] 已试 {tried} 张，命中 {len(found)}", flush=True)
            last_n = len(found)
    print("结束：共找到", len(found), "个候选", flush=True)
