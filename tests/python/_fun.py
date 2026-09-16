# -*- coding: utf-8 -*-
import os, sys, random, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rb_world as W
import rb_gen3 as G

random.seed(7)
stat = {"build_fail":0,"parse_fail":0,"norw_solvable":0,"no_solution":0,"toolong":0,"k_low":0,"replay_bad":0,"entries_many":0,"ok":0}
t0=time.time()
for i in range(120):
    built = G.make_candidate("t1", 1)
    if built is None: stat["build_fail"] += 1; continue
    layouts, _ = built
    w, err = W.parse_world(layouts)
    if w is None: stat["parse_fail"] += 1; continue
    if W.solve_no_rewind(w, limit=150_000)[0] is not None: stat["norw_solvable"] += 1; continue
    k, acts = W.min_rewinds(w, cap=2, max_moves=G.MAXOPT)
    if acts is None: stat["no_solution"] += 1; continue
    if k < 1: stat["k_low"] += 1; continue
    stat["ok"] += 1
print("耗时 %.1fs" % (time.time()-t0))
for kk, vv in stat.items(): print(f"  {kk}: {vv}")
