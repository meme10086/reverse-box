# -*- coding: utf-8 -*-
"""把定稿关卡写进 level_manager.gd（只替换 LEVELS 常量）。"""
import io, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_design as D

PROJ = r"D:\Game《Reserve box》\ReverseBox_Godot\scripts\level_manager.gd"

META = [
    ("第 1 关 · 推箱子", 1, 0, "方向键 / WASD 移动。绕到箱子后面，把它推到金色目标点上。你走过的地方会留下淡淡的时间痕迹。"),
    ("第 2 关 · 两次回溯", 3, 2, "这一关要花掉两次回溯，而且不止一种回溯对象。先想清楚：哪一次给箱子，哪一次给你自己。"),
    ("第 3 关 · 环", 2, 2, ""),
    ("第 4 关 · 长廊", 2, 2, ""),
    ("第 5 关 · 侧屋", 2, 2, ""),
    ("第 6 关 · 拐角", 2, 2, ""),
    ("第 7 关 · 上下", 2, 2, ""),
    ("第 8 关 · 双层", 2, 2, ""),
    ("第 9 关 · 绕行", 2, 2, ""),
    ("第 10 关 · 终局", 2, 2, ""),
]

HEADER = """# 10 个关卡，按「一关一个台阶」排布。每关两个回溯参数：
#   rewind_budget —— 可用的回溯次数（玩家回溯 1 次 / 箱子回溯 1 次各消耗 1）。
#   par_rewinds  —— 设计上的最优回溯次数，用于 S/A/B/C 评级。
#
# 难度阶梯（全部经 Python 参考模拟器验证）：
#   第 1 关      纯推箱教学，不需要回溯（唯一允许不用时间机制的关）。
#   第 2 关起    每一关都必须花掉**两次**回溯，其中一部分关卡还要求
#               "玩家回溯"和"箱子回溯"两种都用上 —— 只回溯箱子过不去。
#   地图保持小（9x5 ~ 10x7），难度来自"要想通哪一步用哪种回溯"，
#   而不是地图变大或步数变长。
#
# 所有布局要求：每行等宽、边框全为墙、恰好 1 个玩家、箱子数 == 目标点数。
# 设计红线：除第 1 关外，每一关都**不用时间机制则无解**，且**只给一次回溯也无解**
#          （已用搜索逐关验证：预算 1 找不到解，预算 2 才有解）。
const LEVELS: Array = [
"""


def build():
    out = [HEADER.rstrip("\n")]
    for i, (name, budget, par, hint) in enumerate(META):
        rows = D.LEVELS[i][1]
        out.append("\t{")
        out.append('\t\t"name": "%s",' % name)
        out.append('\t\t"rewind_budget": %d,' % budget)
        out.append('\t\t"par_rewinds": %d,' % par)
        out.append('\t\t"hint": "%s",' % hint)
        out.append('\t\t"layout": [')
        for r in rows:
            out.append('\t\t\t"%s",' % r)
        out.append("\t\t],")
        out.append("\t},")
    out.append("]")
    return "\n".join(out)


def main():
    src = io.open(PROJ, encoding="utf-8").read()
    new = build()
    pat = re.compile(r"# 10 个关卡.*?\nconst LEVELS: Array = \[.*?\n\]\n", re.S)
    if not pat.search(src):
        print("没找到 LEVELS 块")
        return 1
    src2 = pat.sub(new + "\n", src, count=1)
    io.open(PROJ, "w", encoding="utf-8", newline="\n").write(src2)
    print("已写入", len(META), "关；文件长度", len(src), "->", len(src2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
