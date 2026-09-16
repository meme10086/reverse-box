# -*- coding: utf-8 -*-
"""从 scripts/level_manager.gd 里把大关 2（第 11~20 关）的关卡数据原样提取出来。

为什么要这一步：用户明确要求"第一大关一行不改"，大关 2 的前 5 关（11~15）也已经
验证通过 —— 换掉它们没有收益、只有风险。所以改造大关 2 时采取"保留前 5 关、替换后 5 关"，
提取出来的数据会被写进 rb_ch2_levels.py，供装配脚本直接引用。

用法：python rb_extract_ch2.py
输出：rb_ch2_levels.py（LEVELS_11_15 / SOLS_11_15）
"""
import ast
import io
import os
import re
import sys

ROOT = r"D:\Game《Reserve box》\ReverseBox_Godot"
LM = os.path.join(ROOT, "scripts", "level_manager.gd")
ST = os.path.join(ROOT, "tests", "solve_test.gd")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rb_ch2_levels.py")
MARK = "# ---- 大关 2 起点 ----"


def split_entries(text):
    """按顶层花括号切分若干 `{...}` 字典文本。"""
    entries, depth, start = [], 0, None
    in_str = False
    esc = False
    for i, ch in enumerate(text):
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                entries.append(text[start:i + 1])
                start = None
    return entries


def main():
    src = io.open(LM, encoding="utf-8").read()
    if MARK not in src:
        print("找不到大关 2 标记")
        return 1
    body = src.split(MARK, 1)[1]
    end = body.index("\n]\n")
    block = body[:end]
    entries = split_entries(block)
    print("大关 2 共解析出", len(entries), "关")
    levels = []
    for e in entries:
        levels.append(ast.literal_eval(e))
    for i, lv in enumerate(levels):
        print("  第 %d 关：%s  布局 %s" % (
            11 + i, lv.get("name"), "多图" if "rooms" in lv else "%dx%d" % (
                len(lv["layout"]), len(lv["layout"][0]))))

    st = io.open(ST, encoding="utf-8").read()
    m = re.search(r"const SOLUTIONS := \{\n(.*?)\n\}\n", st, re.S)
    sols = {}
    for ln in m.group(1).splitlines():
        mm = re.match(r"\t(\d+):\s*\[(.*)\],?\s*$", ln)
        if mm:
            sols[int(mm.group(1))] = ast.literal_eval("[" + mm.group(2) + "]")
    print("solve_test 里有解的关卡：", sorted(sols))

    keep = list(range(10, 15))          # 11~15 关原样保留
    with io.open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("# -*- coding: utf-8 -*-\n")
        f.write('"""由 rb_extract_ch2.py 自动生成：大关 2 第 11~15 关（原样保留，勿手改）。"""\n\n')
        f.write("LEVELS_11_15 = " + repr([levels[i - 10] for i in keep]) + "\n\n")
        f.write("SOLS_11_15 = " + repr({i: sols[i] for i in keep}) + "\n")
    print("已写出", OUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
