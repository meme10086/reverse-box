# -*- coding: utf-8 -*-
"""把 rb_gen4.py 的 15 关导出成设计文件：
  · 第 16~20 关 → rb_design_ch2b.py（CHAPTER2B）
  · 第 21~30 关 → rb_design_ch3.py （CHAPTER3）
导出前逐关复核（无回溯无解 + 参考解回放），复核不过直接报错退出。

用法：python rb_build_ch4.py
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rb_world as W      # noqa: E402
import rb_gen4 as G4      # noqa: E402

NAMES = [
    "第 16 关 · 借道", "第 17 关 · 更长的走廊", "第 18 关 · 深密室",
    "第 19 关 · 绕行口袋", "第 20 关 · 对岸",
    "第 21 关 · 一河之隔", "第 22 关 · 双箱双色", "第 23 关 · 两扇门",
    "第 24 关 · 长路两箱", "第 25 关 · 越走越远", "第 26 关 · 首尾相接",
    "第 27 关 · 三思", "第 28 关 · 大图·双箱", "第 29 关 · 换行",
    "第 30 关 · 终局·越狱",
]

HINTS = {
    0: "新规则：走廊只有一格宽，你绕不到箱子右边 —— 把它推到尽头之后，试试【回溯箱子】。",
    4: "这一关箱子只能从第 7 行的门进来，目标也在第 7 行。",
    5: "两个箱子、两种颜色：一个从门里来，一个本来就在里面。",
}


def build():
    specs = G4.make_levels()
    assert len(specs) == 15, "应该是 15 关"
    out = []
    for i, spec in enumerate(specs):
        rooms = list(G4.split_rooms(spec))
        rows = G4.mk(spec)
        w, err = W.parse_world(rooms)
        if w is None:
            print("!! 第 %d 关解析失败：%s" % (16 + i, err))
            return 1
        norw = W.solve_no_rewind(w, limit=400_000)[0]
        k, acts = W.min_rewinds(w, cap=3, max_moves=70)
        if norw is not None or acts is None or not W.replay(w, acts)[0]:
            print("!! 第 %d 关复核不过（无回溯=%s，解=%s）" % (
                16 + i, "有解" if norw is not None else "无解", acts))
            return 1
        moves = len([a for a in acts if len(a) == 1])
        out.append({
            "name": NAMES[i], "span": 0, "budget": max(2, k + 1), "par": k,
            "hint": HINTS.get(i, ""),
            "rooms": rooms, "sol": acts, "maps": len(rooms), "moves": moves, "k": k,
        })
        print("OK 第 %d 关 %dx%d 箱%d 步数%d 回溯%d 解长%d" % (
            16 + i, spec["size"][0], spec["size"][1], len(w.box_start),
            moves, k, len(acts)))

    def emit(path, var, items, header):
        with io.open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("# -*- coding: utf-8 -*-\n")
            f.write('"""%s\n\n由 rb_build_ch4.py 从 rb_gen4.py 自动生成（勿手改）。\n' % header)
            f.write("每关都逐条验过：① 解析合法 ② **不用回溯绝对无解** ③ 参考解回放通过。\n")
            f.write('"""\n\n')
            f.write("%s = [\n" % var)
            for lv in items:
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

    emit(os.path.join(HERE, "rb_design_ch2b.py"), "CHAPTER2B", out[:5],
         "大关 2 后 5 关（第 16~20 关）：大图 + 密室传送门 + 强制回溯。")
    emit(os.path.join(HERE, "rb_design_ch3.py"), "CHAPTER3", out[5:],
         "大关 3（第 21~30 关）：大图 + 密室传送门 + 强制回溯（双箱双色进阶）。")
    print("已写出 rb_design_ch2b.py（5 关）与 rb_design_ch3.py（10 关）")
    return 0


if __name__ == "__main__":
    raise SystemExit(build())
