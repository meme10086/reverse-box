# -*- coding: utf-8 -*-
"""把「大关 2 后 5 关（传送门）+ 大关 3（多地图·颜色）」装进项目。

装配策略（关键：已验证的部分绝不重写）：
  · 第 1~10 关：**完全不碰**（用户铁律）。
  · 第 11~15 关：从项目里原样提取（rb_ch2_levels.py），逐字回写，不重新生成。
  · 第 16~20 关：换成 rb_design_ch2b.py（传送门 + 回溯距离上限）。
  · 第 21~30 关：来自 rb_design_ch3.py（多地图 + 颜色）。
  · 备份放在**项目目录之外**（.workbuddy/backups）—— 放进 res:// 会让 Godot 扫到两份
    同名 class_name，运行时用错那一份（这个坑踩过一次）。

用法：python rb_apply_ch23.py
"""
import io
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

ROOT = r"D:\Game《Reserve box》\ReverseBox_Godot"
LM = os.path.join(ROOT, "scripts", "level_manager.gd")
ST = os.path.join(ROOT, "tests", "solve_test.gd")
GODOT = r"D:/Game《Reserve box》/tools/Godot_v4.5-stable_official_win64.exe"
BACKUP_DIR = r"C:\Users\29210\WorkBuddy\Game《Reserve box》\.workbuddy\backups"
MARK2 = "\t# ---- 大关 2 起点 ----"
MARK3 = "\t# ---- 大关 3 起点 ----"


def _esc(s):
    return str(s).replace("\\", "\\\\").replace('"', '\\"')


def emit_level(lv, indent="\t"):
    o = [indent + "{"]
    o.append(indent + '\t"name": "%s",' % _esc(lv.get("name", "")))
    for key in ("rewind_span", "rewind_budget", "par_rewinds"):
        if key in lv and lv[key] is not None:
            o.append(indent + '\t"%s": %d,' % (key, int(lv[key])))
    o.append(indent + '\t"hint": "%s",' % _esc(lv.get("hint", "")))
    if lv.get("guide"):
        o.append(indent + '\t"guide": [')
        for g in lv["guide"]:
            o.append(indent + '\t\t{"tip": "%s", "done": "%s"},' % (
                _esc(g["tip"]), _esc(g["done"])))
        o.append(indent + "\t],")
    if lv.get("rooms"):
        o.append(indent + '\t"rooms": [')
        for room in lv["rooms"]:
            o.append(indent + "\t\t[")
            for row in room:
                o.append(indent + '\t\t\t"%s",' % _esc(row))
            o.append(indent + "\t\t],")
        o.append(indent + "\t],")
    else:
        o.append(indent + '\t"layout": [')
        for row in lv["layout"]:
            o.append(indent + '\t\t"%s",' % _esc(row))
        o.append(indent + "\t],")
    o.append(indent + "},")
    return "\n".join(o)


def split_chapter2(src):
    """返回 (大关 2 段之前的内容, [10 段关卡文本])。"""
    if MARK2 not in src:
        raise SystemExit("找不到大关 2 标记")
    head, rest = src.split(MARK2, 1)
    end = rest.index("\n]\n")
    block = rest[:end]
    # 大关 2 的段落到「大关 3 起点」为止（后面那一段会被整块重写）
    ch2 = block.split(MARK3, 1)[0] if MARK3 in block else block
    entries, depth, start, in_str, esc = [], 0, None, False, False
    for i, ch in enumerate(ch2):
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
                entries.append(ch2[start:i + 1].strip())
                start = None
    if len(entries) != 10:
        raise SystemExit("大关 2 应该恰好 10 关，实际 %d" % len(entries))
    return head, entries, rest[end + 1:]        # rest[end] 是换行，rest[end+1] 才是收尾的 "]"


def build_block(first5_text):
    from rb_design_ch2b import CHAPTER2B
    from rb_design_ch3 import CHAPTER3
    out = [MARK2]
    out.extend("\t" + t + "," for t in first5_text)   # 11~15 原样（补回行首缩进）
    for lv in CHAPTER2B:
        out.append(emit_level({"name": lv["name"], "rewind_span": lv["span"],
                               "rewind_budget": lv["budget"], "par_rewinds": lv["par"],
                               "hint": lv.get("hint", ""), "guide": lv.get("guide"),
                               "rooms": lv["rooms"]}))
    out.append(MARK3)
    for lv in CHAPTER3:
        out.append(emit_level({"name": lv["name"], "rewind_span": lv.get("span", 0),
                               "rewind_budget": lv.get("budget", 2),
                               "par_rewinds": lv.get("par", 1),
                               "hint": lv.get("hint", ""), "guide": lv.get("guide"),
                               "rooms": lv.get("rooms"), "layout": lv.get("layout")}))
    return "\n".join(out) + "\n"


def patch_levels(src, first5_text):
    head, entries, tail = split_chapter2(src)
    return head.rstrip("\n") + "\n" + build_block(first5_text) + tail


def patch_solutions(src, sols):
    pat = re.compile(r"const SOLUTIONS := \{\n(.*?)\n\}\n", re.S)
    m = pat.search(src)
    if not m:
        raise SystemExit("找不到 SOLUTIONS")
    keep = []
    for ln in m.group(1).splitlines():
        mm = re.match(r"\t(\d+):", ln)
        if mm and int(mm.group(1)) < 10:
            keep.append(ln)
    out = ["const SOLUTIONS := {"] + keep
    for idx in sorted(sols):
        out.append("\t%d: [%s]," % (idx, ", ".join('"%s"' % a for a in sols[idx])))
    return src[:m.start()] + "\n".join(out) + "\n}\n" + src[m.end():]


def main():
    lm0 = io.open(LM, encoding="utf-8").read()
    st0 = io.open(ST, encoding="utf-8").read()

    from rb_ch2_levels import LEVELS_11_15, SOLS_11_15
    from rb_design_ch2b import CHAPTER2B
    from rb_design_ch3 import CHAPTER3

    _head, entries, _tail = split_chapter2(lm0)
    first5_text = entries[:5]
    new_lm = patch_levels(lm0, first5_text)

    sols = dict(SOLS_11_15)
    for i, lv in enumerate(CHAPTER2B):
        sols[15 + i] = lv["sol"]
    for i, lv in enumerate(CHAPTER3):
        sols[20 + i] = lv["sol"]
    new_st = patch_solutions(st0, sols)

    os.makedirs(BACKUP_DIR, exist_ok=True)
    bak = os.path.join(BACKUP_DIR, "backup_" + time.strftime("%Y%m%d_%H%M%S"))
    os.makedirs(bak, exist_ok=True)
    shutil.copy2(LM, bak)
    shutil.copy2(ST, bak)
    print("备份在", bak)

    io.open(LM, "w", encoding="utf-8", newline="\n").write(new_lm)
    io.open(ST, "w", encoding="utf-8", newline="\n").write(new_st)
    print("已写入：11~15（原样）+ 16~20（传送门）+ 21~30（多地图·颜色）")

    env = dict(os.environ)
    env.pop("ACC_PRODUCT_CONFIG_V3", None)
    r = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "res://tests/solve_test.gd"],
                       env=env, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=900)
    for l in (r.stdout or "").splitlines():
        if "FAIL" in l:
            print(l)
    print("自检退出码 =", r.returncode)
    if r.returncode != 0:
        io.open(LM, "w", encoding="utf-8", newline="\n").write(lm0)
        io.open(ST, "w", encoding="utf-8", newline="\n").write(st0)
        print("自检未通过 → 已回滚")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
