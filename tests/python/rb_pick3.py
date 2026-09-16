# -*- coding: utf-8 -*-
"""从候选池日志里挑关卡，并直接生成可粘贴的 Python 字面量。

日志格式（rb_gen3.py 输出，Windows 下是 CRLF）：
  === 命中 3：t1 图2 箱1 墙2 span=0 k=1 动作17
    图0: ... | ... | ...
    图1: ... | ...
    解: U U R ...

用法：
  python rb_pick3.py pool_e.log            列出候选（按解长排序）
  python rb_pick3.py pool_e.log 1 5 9      只列指定编号，并输出 Python 字面量
"""
import io
import re
import sys

PAT = re.compile(
    r"=== 命中 (\d+)：(\w+) 图(\d+) 箱(\d+) 墙(\d+)(?: span=(\d+))? k=(\d+) 动作(\d+)\r?\n"
    r"(.*?)\r?\n  解: (.*?)\r?\n", re.S)


def load(path):
    txt = io.open(path, encoding="utf-8").read()
    out = []
    for m in PAT.finditer(txt):
        no, tmpl, nrooms, nbox, nw, span, k, moves, body, sol = m.groups()
        span = span or "0"
        rooms = []
        for line in body.strip().splitlines():
            line = line.strip()
            mm = re.match(r"图(\d+):\s*(.*)$", line)
            if mm:
                rooms.append([c.strip() for c in mm.group(2).split("|")])
        out.append({"no": int(no), "tmpl": tmpl, "rooms": rooms,
                    "nbox": int(nbox), "nw": int(nw), "span": int(span),
                    "k": int(k), "moves": int(moves), "sol": sol.split()})
    return out


def show(h):
    print("--- 命中%d %s 图%d 箱%d 墙%d 动作%d k=%d" % (
        h["no"], h["tmpl"], len(h["rooms"]), h["nbox"], h["nw"], h["moves"], h["k"]))
    for i, r in enumerate(h["rooms"]):
        print("    图%d: %s" % (i, " | ".join(r)))
    print("    解:", " ".join(h["sol"]))


def literal(h, name):
    lines = []
    lines.append("    {")
    lines.append('        "name": "%s",' % name)
    lines.append('        "span": %d, "budget": %d, "par": %d,' % (
        h["span"], max(2, h["k"]), h["k"]))
    lines.append('        "hint": "",')
    lines.append('        "rooms": [')
    for r in h["rooms"]:
        lines.append("            [")
        for row in r:
            lines.append('                "%s",' % row)
        lines.append("            ],")
    lines.append("        ],")
    lines.append('        "sol": %s,' % repr(h["sol"]).replace("'", '"'))
    lines.append("    },")
    return "\n".join(lines)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    items = load(sys.argv[1])
    items.sort(key=lambda h: (h["moves"], h["no"]))
    picks = [int(x) for x in sys.argv[2:]] if len(sys.argv) > 2 else []
    if not picks:
        print("共", len(items), "个候选：")
        for h in items:
            show(h)
        return 0
    by_no = {h["no"]: h for h in items}
    for i, no in enumerate(picks):
        h = by_no.get(no)
        if h is None:
            print("!! 没有编号", no)
            continue
        print(literal(h, "第 %d 关 · 待命名" % (21 + i)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
