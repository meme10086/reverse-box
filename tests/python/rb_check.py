# -*- coding: utf-8 -*-
"""关卡批量检查（用快速搜索 + 精确回放验证）。

输出：NoRW（无回溯是否有解，必须「无」）、MIN（最少回溯次数）、
      P!（回溯玩家是否必需）、B!（回溯箱子是否必需）、参考解
用法：python rb_check.py [步数上限]
"""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_engine as E
from rb_design import LEVELS

CAP = int(sys.argv[1]) if len(sys.argv) > 1 else 26


def check(name, rows, budget=None, span=0):
    E.set_span(span)
    lv, err = E.parse(rows)
    if lv is None:
        print(f"[{name}] 解析失败：{err}")
        return
    t0 = time.time()
    nw, _ = E.solve_no_rewind(rows)
    k, acts = E.min_rewinds_fast(rows, cap=4, max_moves=CAP)
    extra = ""
    if k is not None:
        if k > 0:
            p_no, _ = E.search_fast(rows, k, max_moves=CAP, allow_player=False)
            b_no, _ = E.search_fast(rows, k, max_moves=CAP, allow_box=False)
            extra = ("[玩家回溯必需]" if p_no is None else "") + ("[箱子回溯必需]" if b_no is None else "")
        ok, used, rerr = E.replay(rows, acts)
        extra += f" 回放={'通过' if ok else '失败:' + str(rerr)}"
    flag = "OK " if (nw is None or k == 0) and k is not None else "!! "
    print(f"{flag}[{name}] NoRW={'无' if nw is None else '有解'} MIN={k} budget={budget} span={span} {extra}")
    if acts:
        print(f"        解({len([a for a in acts if len(a)==1])}步 + {k}回溯)：{' '.join(acts)}")
    print(f"        {time.time()-t0:.1f}s")


if __name__ == "__main__":
    for item in LEVELS:
        check(item[0], item[1], item[2] if len(item) > 2 else None,
              item[3] if len(item) > 3 else 0)
