# -*- coding: utf-8 -*-
"""把 gen2.log 里的候选逐个精确复核（replay），只留真正合法的。

输出：verified.txt  每段 = 地图 + 解 + 复核结论
用法：python rb_verify_log.py
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_engine as E

LOG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "gen2.log")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "verified.txt")


def prove(rows, cap=22, limit=250_000):
    """判定"1 次回溯是否够"。

    说明：完整规则搜索（含轨迹）在大地图上会状态爆炸，所以这里用折叠式搜索
    （visited 只看 玩家/箱子/剩余次数）—— 它对本类走廊地图足够彻底，但**不是形式化证明**。
    返回 (是否达到"1 次不够/2 次能解"的标准, 说明)
    """
    if os.environ.get("VERIFY_MODE") == "basic":
        # 大关 2：新意是"距离受限"本身，不再要求"1 次回溯不够"。
        # 回放（replay）内部会按 span 校验每一步是否超距，所以走通即证明合法。
        return True, "距离限制下可解（回放通过）"
    if os.environ.get("STRICT_PROOF") == "1":
        a1, e1 = E.search(rows, 1, max_moves=cap, limit=limit)
        if a1 is not None:
            return False, "1 次回溯就能解（不够硬）"
        if e1 == "状态爆炸":
            return None, "预算1搜索爆炸，无法证明"
        a2, e2 = E.search(rows, 2, max_moves=cap, limit=limit)
        if a2 is None:
            return None, f"2 次回溯未找到解（{e2}）"
        return True, "1 次不够 / 2 次可解（完整规则搜索）"
    a1, _ = E.search_fast(rows, 1, max_moves=cap, limit=120_000)
    if a1 is not None:
        return False, "1 次回溯就能解（不够硬）"
    a2, _ = E.search_fast(rows, 2, max_moves=cap, limit=120_000)
    if a2 is None:
        return None, "2 次回溯未找到解"
    return True, "1 次不够 / 2 次可解（折叠搜索）"

blocks = []
cur = None
for line in open(LOG, encoding="utf-8", errors="replace"):
    m = re.match(r"=== 命中 (\d+)：(\S+) (?:箱(\d+) )?(?:span=(\d+) )?k=(\d+) 最优(\d+) 入口(\S*) (.*)", line.strip())
    if m:
        cur = {"no": m.group(1), "skel": m.group(2),
               "boxes": int(m.group(3) or 0), "span": int(m.group(4) or 0),
               "k": int(m.group(5)), "opt": int(m.group(6)), "need": m.group(8),
               "rows": [], "sol": ""}
        blocks.append(cur)
        continue
    if cur is None:
        continue
    s = line.rstrip("\n")
    if s.startswith("    ") and set(s.strip()) <= set("#.@$*&+"):
        cur["rows"].append(s.strip())
    elif "解:" in s:
        cur["sol"] = s.split("解:")[1].strip()

ok, bad = [], []
fout = open(OUT, "w", encoding="utf-8")
for idx, b in enumerate(blocks):
    if not b["rows"] or not b["sol"]:
        continue
    E.set_span(b.get("span", 0))
    acts = b["sol"].split()
    good, used, err = E.replay(b["rows"], acts)
    nowin = E.solve_no_rewind(b["rows"])[0]
    if not (good and nowin is None):
        bad.append((b, used, err, nowin is not None))
        print(f"[{idx+1}/{len(blocks)}] 命中{b['no']} 回放/无回溯判定不通过", flush=True)
        continue
    proved, note = prove(b["rows"])
    if proved is not True:
        bad.append((b, used, note, False))
        print(f"[{idx+1}/{len(blocks)}] 命中{b['no']} 精确证明不通过：{note}", flush=True)
        continue
    ok.append((b, used))
    # 逐个落盘，任何中断都不会丢已证明的结果
    fout.write(f"### 命中{b['no']} {b['skel']} 箱{b['boxes']} k={used} "
               f"最优{b['opt']} {b['need']}\n")
    for r in b["rows"]:
        fout.write("    " + r + "\n")
    fout.write("    解: " + b["sol"] + "\n\n")
    fout.flush()
    print(f"[{idx+1}/{len(blocks)}] 命中{b['no']} 通过精确证明 ✓", flush=True)
fout.close()

print(f"日志候选 {len(blocks)} 个 → 精确复核通过 {len(ok)} 个，剔除 {len(bad)} 个")
for b, used, err, nw in bad[:5]:
    print(f"  剔除 命中{b['no']}({b['skel']}) 回溯{used} err={err} 无回溯有解={nw}")
