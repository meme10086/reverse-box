# -*- coding: utf-8 -*-
"""把第三版（多母题阶梯）的第 16~30 关装进项目。

原则：
  · 第 1~15 关**逐字保留**（1~10 是用户铁律；11~15 已验证）。
  · 第 16~30 关整段换成 rb_gen5.py 的结果（大关 2 的 16~20 + 大关 3 的 21~30）。
  · 备份放**项目目录之外**（放进 res:// 会让 Godot 扫到两份同名 class_name）。
  · 装完自动跑 solve_test.gd；失败自动回滚。

用法：python rb_apply_ch5.py
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

KEEP = 15          # 1~15 关原样保留


def _esc(s):
    return str(s).replace("\\", "\\\\").replace('"', '\\"')


def split_entries(body):
    """把 LEVELS 数组体按顶层花括号切成每一关的文本。"""
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


def emit_level(lv):
    o = ["\t{"]
    o.append('\t\t"name": "%s",' % _esc(lv["name"]))
    o.append('\t\t"rewind_span": %d,' % int(lv.get("span", 0)))
    o.append('\t\t"rewind_budget": %d,' % int(lv["budget"]))
    o.append('\t\t"par_rewinds": %d,' % int(lv["par"]))
    o.append('\t\t"hint": "%s",' % _esc(lv.get("hint", "")))
    if lv.get("guide"):
        o.append('\t\t"guide": [')
        for g in lv["guide"]:
            o.append('\t\t\t{"tip": "%s", "done": "%s"},' % (_esc(g["tip"]), _esc(g["done"])))
        o.append("\t\t],")
    o.append('\t\t"rooms": [')
    for room in lv["rooms"]:
        o.append("\t\t\t[")
        for row in room:
            o.append('\t\t\t\t"%s",' % _esc(row))
        o.append("\t\t\t],")
    o.append("\t\t],")
    o.append("\t},")
    return "\n".join(o)


def patch_levels(src, kept_text, new_levels):
    m = re.search(r"const LEVELS: Array = \[(.*?)\n\]\n", src, re.S)
    if not m:
        raise SystemExit("找不到 LEVELS")
    body = m.group(1)
    entries = split_entries(body)
    if len(entries) != 30:
        raise SystemExit("本来是 30 关，实际解析出 %d" % len(entries))
    lines = ["const LEVELS: Array = ["]
    lines.append("\t# ---- 大关 1 起点（用户铁律：逐字不动） ----")
    for t in kept_text[:10]:
        lines.append("\t" + t + ",")
    lines.append("\t# ---- 大关 2 起点 ----")
    for t in kept_text[10:KEEP]:
        lines.append("\t" + t + ",")
    for lv in new_levels:
        lines.append(emit_level(lv))
    lines.append("]")
    return src[:m.start()] + "\n".join(lines) + "\n" + src[m.end():]


def patch_solutions(src, sols):
    pat = re.compile(r"const SOLUTIONS := \{\n(.*?)\n\}\n", re.S)
    m = pat.search(src)
    if not m:
        raise SystemExit("找不到 SOLUTIONS")
    keep = [ln for ln in m.group(1).splitlines()
            if (mm := re.match(r"\t(\d+):", ln)) and int(mm.group(1)) < KEEP]
    out = ["const SOLUTIONS := {"] + keep
    for idx in sorted(sols):
        out.append("\t%d: [%s]," % (idx, ", ".join('"%s"' % a for a in sols[idx])))
    return src[:m.start()] + "\n".join(out) + "\n}\n" + src[m.end():]


def main():
    import rb_gen5 as G5
    import rb_world as W

    lm0 = io.open(LM, encoding="utf-8").read()
    st0 = io.open(ST, encoding="utf-8").read()
    body = re.search(r"const LEVELS: Array = \[(.*?)\n\]\n", lm0, re.S).group(1)
    kept_text = split_entries(body)

    levels = G5.make_levels()
    out_levels, sols = [], {}
    for i, lv in enumerate(levels):
        idx = KEEP + i
        info, err = G5.analyze(lv["fig0"], lv["fig1"], lv.get("anchors"))
        if info is None or "acts" not in info:
            raise SystemExit("第 %d 关还没通过验收：%s" % (idx + 1, err or info))
        if info["norw"] is not False:
            raise SystemExit("第 %d 关不用回溯也能过（不合格）" % (idx + 1))
        k = info["k"]
        budget = k + 1 if idx < 25 else k          # 最后 5 关不留余量
        out_levels.append({
            "name": lv["name"], "hint": lv["hint"], "span": 0,
            "budget": budget, "par": k, "guide": lv.get("guide"),
            "rooms": [lv["fig0"], lv["fig1"]],
        })
        sols[idx] = info["acts"]
        print("  第 %d 关 最少回溯 %d 预算 %d 步数 %d" % (idx + 1, k, budget, info["moves"]))

    new_lm = patch_levels(lm0, kept_text, out_levels)
    new_st = patch_solutions(st0, sols)

    os.makedirs(BACKUP_DIR, exist_ok=True)
    bak = os.path.join(BACKUP_DIR, "backup_" + time.strftime("%Y%m%d_%H%M%S"))
    os.makedirs(bak, exist_ok=True)
    shutil.copy2(LM, bak)
    shutil.copy2(ST, bak)
    print("备份在", bak)

    io.open(LM, "w", encoding="utf-8", newline="\n").write(new_lm)
    io.open(ST, "w", encoding="utf-8", newline="\n").write(new_st)
    print("已写入：1~15 原样 + 16~30 新关卡")

    env = dict(os.environ)
    env.pop("ACC_PRODUCT_CONFIG_V3", None)
    r = subprocess.run([GODOT, "--headless", "--path", ROOT,
                        "-s", "res://tests/solve_test.gd"],
                       env=env, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=1200)
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
