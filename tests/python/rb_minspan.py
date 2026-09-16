# -*- coding: utf-8 -*-
"""筛"真的吃距离限制"的关卡：算出每关的最小可用跨度 min_span。

判定：把 span 从 1 往上试，找到第一个"能解"的跨度 = min_span。
  - min_span == 1  → 只用回 1 格就够（不吃距离限制，适合当教学关）
  - min_span == 2  → 必须能回 2 格，且回 1 格无解（真正吃 2 格限制）★
  - min_span == 3  → 必须能回 3 格（真正吃 3 格限制）★
用法：python rb_minspan.py gen_span2.log
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_engine as E

CAP = 14


def parse_log(path):
    blocks, cur = [], None
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"=== 命中 (\d+)：(\S+) (?:箱(\d+) )?(?:span=(\d+) )?k=(\d+) 最优(\d+) 入口(\S*) (.*)",
                     line.strip())
        if m:
            cur = {"no": int(m.group(1)), "skel": m.group(2), "boxes": int(m.group(3) or 0),
                   "span": int(m.group(4) or 0), "opt": int(m.group(6)), "rows": [], "sol": ""}
            blocks.append(cur)
            continue
        if cur is None:
            continue
        s = line.rstrip("\n")
        if s.startswith("    ") and set(s.strip()) <= set("#.@$*&+"):
            cur["rows"].append(s.strip())
        elif "解:" in s:
            cur["sol"] = s.split("解:")[1].strip()
    return [b for b in blocks if b["rows"] and b["sol"]]


def min_span(rows):
    """返回 (min_span, 备注)。0 = 不用回溯就能过（不合格）。"""
    E.set_span(0)
    if E.solve_no_rewind(rows, limit=120_000)[0] is not None:
        return None, "无回溯可解（不合格）"
    for s in (1, 2, 3):
        E.set_span(s)
        for budget in (1, 2):
            acts, _ = E.search_fast(rows, budget, max_moves=CAP, limit=50_000)
            if acts is not None and len(acts) <= CAP:
                return s, " ".join(acts)
    return None, "3 格内无解"


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "gen_span2.log"
    for b in parse_log(path):
        ms, note = min_span(b["rows"])
        if ms is None:
            print(f"命中{b['no']:<3}{b['skel']:<9} 箱{b['boxes']} → {note}")
            continue
        tag = {1: "只用1格(教学向)", 2: "★必须2格", 3: "★必须3格"}.get(ms, "?")
        print(f"命中{b['no']:<3}{b['skel']:<9} 箱{b['boxes']} 最优{b['opt']:<3} min_span={ms} {tag}")
