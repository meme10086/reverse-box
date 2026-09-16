# -*- coding: utf-8 -*-
"""比较两个 level_manager.gd 的 LEVELS 数组，逐关核对是否改动。

用法：python rb_diff_levels.py <旧文件> [新文件=项目里的]
输出每一段（大关 1 / 11~15 / 16~30）是否逐字一致。
"""
import io
import os
import re
import sys

DEFAULT_NEW = r"D:\Game《Reserve box》\ReverseBox_Godot\scripts\level_manager.gd"


def entries(path):
    s = io.open(path, encoding="utf-8").read()
    body = re.search(r"const LEVELS: Array = \[(.*?)\n\]\n", s, re.S).group(1)
    out, depth, start, in_str, esc = [], 0, None, False, False
    for i, ch in enumerate(body):
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
                out.append(body[start:i + 1].strip())
                start = None
    return out


def main():
    old = sys.argv[1]
    new = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_NEW
    o, n = entries(old), entries(new)
    print("关卡数 旧=%d 新=%d" % (len(o), len(n)))
    if len(o) != len(n):
        return 1
    bad = 0
    for i in range(len(o)):
        if o[i] != n[i]:
            bad += 1
            print("  !! 第 %d 关 有改动" % (i + 1))
    print("逐关一致" if bad == 0 else "有 %d 关改动" % bad)
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
