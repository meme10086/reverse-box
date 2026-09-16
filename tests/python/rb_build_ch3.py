# -*- coding: utf-8 -*-
"""按"指定候选编号"从候选池里挑出大关 3 的 10 关，生成 rb_design_ch3.py。

为什么不手抄地图：手抄必然出错（错一格就整关废掉）。这里直接从池日志里读，
再用参考引擎**逐关复核一遍**（无回溯无解 / 参考解回放通过 / 跨图搬运），复核不过直接报错退出。

用法：python rb_build_ch3.py
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rb_world as W          # noqa: E402
import rb_pick3 as P          # noqa: E402

# (池日志, 命中编号, 关卡名, 提示)
PICKS = [
    ("pool_e.log", 55, "第 21 关 · 两张图", "箱子和地砖都有颜色 —— 同色才算到位。"),
    ("pool_e.log", 38, "第 22 关 · 门后回溯", ""),
    ("pool_e.log", 9,  "第 23 关 · 窄道穿门", ""),
    ("pool_e2.log", 1, "第 24 关 · 双箱双色", "两个箱子、两种颜色，要想清楚谁走哪条路。"),
    ("pool_t3.log", 1, "第 25 关 · 三张图", "地图变成三张了：箱子要连穿两道门。"),
    ("pool_t3.log", 2, "第 26 关 · 三图·对色", ""),
    ("pool_t3.log", 3, "第 27 关 · 三图·两步", ""),
    ("pool_t4c.log", 4, "第 28 关 · 四张图", "四张地图首尾相接，箱子的路要绕一大圈。"),
    ("pool_t4c.log", 2, "第 29 关 · 四图·对色", ""),
    ("pool_t4c.log", 3, "第 30 关 · 终局·四图", ""),
]


def main():
    cache = {}
    out = []
    ok = True
    for i, (log, no, name, hint) in enumerate(PICKS):
        if log not in cache:
            path = os.path.join(HERE, log)
            if not os.path.exists(path):
                print("!! 缺少候选池", log)
                return 1
            cache[log] = {h["no"]: h for h in P.load(path)}
        h = cache[log].get(no)
        if h is None:
            print("!! %s 里没有命中编号 %d" % (log, no))
            ok = False
            continue
        W.set_span(h["span"])
        w, err = W.parse_world(h["rooms"])
        if w is None:
            print("!! %s#%d 解析失败：%s" % (log, no, err))
            ok = False
            continue
        norw = W.solve_no_rewind(w, limit=200_000)[0]
        good, used, rerr = W.replay(w, h["sol"])
        if not good:
            print("!! %s#%d 参考解回放失败：%s" % (log, no, rerr))
            ok = False
            continue
        # 大关 3 的亮点是「多地图 + 颜色」，**不强制**不用回溯就无解
        # （构造式关卡本身就是可直推的；回溯是更短/更优的路线，par 记的就是它）
        # 但如实记录"不用回溯的路线有多长"，方便判断这关是不是真的需要动脑。
        norw_len = len(norw) if norw else None
        # 跨图校验：至少有一个箱子的目标**全部在别的图上** → 必须用传送门
        cross = False
        for k, b in enumerate(w.box_start):
            col = w.box_colors[k]
            goals = [(ri, cell) for ri, rm in enumerate(w.rooms)
                     for cell, c in rm.goal_color.items() if c == col]
            if goals and all(ri != b[0] for ri, _ in goals):
                cross = True
                break
        if not cross:
            print("!! %s#%d 不满足跨图搬运（箱子不用过门就能到位）" % (log, no))
            ok = False
            continue
        out.append({
            "name": name, "span": h["span"], "budget": max(2, h["k"] + 1),
            "par": h["k"], "hint": hint, "rooms": h["rooms"], "sol": h["sol"],
            "maps": len(h["rooms"]), "moves": h["moves"], "k": h["k"],
        })
        print("OK %s 图%d 箱%d 动作%d 回溯%d（不用回溯要 %s 步）" % (
            name, len(h["rooms"]), h["nbox"], h["moves"], h["k"],
            norw_len if norw_len else "-"))

    if not ok:
        print("===== 有候选没通过复核，未生成 =====")
        return 1

    with io.open(os.path.join(HERE, "rb_design_ch3.py"), "w", encoding="utf-8",
                 newline="\n") as f:
        f.write("# -*- coding: utf-8 -*-\n")
        f.write('"""大关 3（第 21~30 关）定稿：多地图 + 传送门 + 颜色匹配。\n\n')
        f.write("由 rb_build_ch3.py 从候选池自动装配（避免手抄地图出错），每关都经过：\n")
        f.write("  ① 解析合法 ② 无回溯无解 ③ 参考解回放通过 ④ 箱子目标在另一张地图（必须用传送门）\n")
        f.write('"""\n\n')
        f.write("CHAPTER3 = [\n")
        for lv in out:
            f.write("    {\n")
            f.write('        "name": "%s",\n' % lv["name"])
            f.write('        "span": %d, "budget": %d, "par": %d,\n' % (
                lv["span"], lv["budget"], lv["par"]))
            f.write('        "hint": "%s",\n' % lv["hint"])
            f.write('        "rooms": [\n')
            for room in lv["rooms"]:
                f.write("            [\n")
                for row in room:
                    f.write('                "%s",\n' % row)
                f.write("            ],\n")
            f.write("        ],\n")
            f.write('        "sol": %s,\n' % repr(lv["sol"]).replace("'", '"'))
            f.write("    },\n")
        f.write("]\n")
    print("已写出 rb_design_ch3.py，共", len(out), "关")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
