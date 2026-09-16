# -*- coding: utf-8 -*-
"""把大关 2（第 11~20 关）追加进项目。

设计要点：
- **第一大关 1~10 一行不动**（用户要求）—— 本脚本只在 LEVELS 数组末尾追加，
  用显式标记 `# ---- 大关 2 起点 ----` 保证可重复执行（重复跑会先删掉旧的大关 2 段）。
- solve_test.gd 的 SOLUTIONS 同样只追加 index 10..19。
- 追加完自动跑项目自检；失败则回滚两个文件。

用法：python rb_apply_ch2.py
"""
import io, os, re, shutil, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = r"D:\Game《Reserve box》\ReverseBox_Godot"
LM = os.path.join(ROOT, "scripts", "level_manager.gd")
ST = os.path.join(ROOT, "tests", "solve_test.gd")
GODOT = r"D:/Game《Reserve box》/tools/Godot_v4.5-stable_official_win64.exe"
MARK = "\t# ---- 大关 2 起点 ----\n"

try:
    from rb_design2 import CHAPTER2
except Exception as e:                                     # noqa: BLE001
    print("缺少 rb_design2.py（还没有定稿的大关 2 关卡）：", e)
    raise SystemExit(1)


def levels_block() -> str:
    out = [MARK.rstrip("\n")]
    for lv in CHAPTER2:
        out.append("\t{")
        out.append('\t\t"name": "%s",' % lv["name"])
        out.append('\t\t"rewind_span": %d,' % lv["span"])
        out.append('\t\t"rewind_budget": %d,' % lv["budget"])
        out.append('\t\t"par_rewinds": %d,' % lv["par"])
        out.append('\t\t"hint": "%s",' % lv.get("hint", ""))
        if lv.get("guide"):
            out.append('\t\t"guide": [')
            for g in lv["guide"]:
                out.append('\t\t\t{"tip": "%s", "done": "%s"},' % (g["tip"], g["done"]))
            out.append("\t\t],")
        out.append('\t\t"layout": [')
        for r in lv["rows"]:
            out.append('\t\t\t"%s",' % r)
        out.append("\t\t],")
        out.append("\t},")
    return "\n".join(out) + "\n"


def patch_levels(src: str) -> str:
    # 先删掉上一次写入的大关 2 段（从标记到数组结尾的 ]）
    if MARK in src:
        head, rest = src.split(MARK, 1)
        end = rest.index("\n]\n")
        src = head + rest[end + len("\n]\n"):]
    idx = src.rindex("\n]\n")
    return src[:idx + 1] + levels_block() + src[idx + 1:]


def solutions_block() -> str:
    out = []
    for i, lv in enumerate(CHAPTER2):
        acts = ", ".join('"%s"' % a for a in lv["solution"])
        out.append("\t%d: [%s]," % (10 + i, acts))
    return "\n".join(out) + "\n"


def patch_solutions(src: str) -> str:
    pat = re.compile(r"const SOLUTIONS := \{\n(.*?)\n\}\n", re.S)
    m = pat.search(src)
    if not m:
        raise SystemExit("找不到 SOLUTIONS")
    body = m.group(1)
    # 去掉旧的 10..19 行（如果有）
    keep = [ln for ln in body.splitlines()
            if not re.match(r"\t(1[0-9]):\s*\[", ln)]
    new_body = "\n".join(keep)
    return src[:m.start()] + "const SOLUTIONS := {\n" + new_body + "\n" + solutions_block() + "}\n" + src[m.end():]


def main() -> int:
    bak = os.path.join(ROOT, "tests", "python", "backup_" + time.strftime("%Y%m%d_%H%M%S"))
    os.makedirs(bak, exist_ok=True)
    shutil.copy2(LM, bak)
    shutil.copy2(ST, bak)
    lm0, st0 = io.open(LM, encoding="utf-8").read(), io.open(ST, encoding="utf-8").read()
    try:
        io.open(LM, "w", encoding="utf-8", newline="\n").write(patch_levels(lm0))
        io.open(ST, "w", encoding="utf-8", newline="\n").write(patch_solutions(st0))
        print("已写入大关 2：", len(CHAPTER2), "关；备份在", bak)
    except Exception as e:                                  # noqa: BLE001
        io.open(LM, "w", encoding="utf-8", newline="\n").write(lm0)
        io.open(ST, "w", encoding="utf-8", newline="\n").write(st0)
        print("写入异常，已回滚：", e)
        return 1
    env = dict(os.environ)
    env.pop("ACC_PRODUCT_CONFIG_V3", None)
    r = subprocess.run([GODOT, "--headless", "--path", ROOT, "-s", "res://tests/solve_test.gd"],
                       env=env, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", timeout=600)
    fails = [l for l in (r.stdout or "").splitlines() if "FAIL" in l]
    for l in fails[:10]:
        print(l)
    print("自检退出码 =", r.returncode)
    if r.returncode != 0:
        io.open(LM, "w", encoding="utf-8", newline="\n").write(lm0)
        io.open(ST, "w", encoding="utf-8", newline="\n").write(st0)
        print("自检未通过 → 已回滚两个文件")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
