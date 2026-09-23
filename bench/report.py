#!/usr/bin/env python3
"""Summarise bench/results/runs.jsonl into a chart and a results table.

    bench/report.py            # writes bench/results/summary.md and bench/results/savings.svg,
                               # and refreshes the table between the BENCH markers in README.md

Figures are medians across reps. Cost is what the Claude Code CLI reports at list price and
weights each token kind correctly (fresh input, cache writes, cache reads, output). The on-device
fm work itself costs nothing, so the skills arm is only Claude's orchestration and reading of fm's text.
"""
import json, re, statistics
from collections import defaultdict
from pathlib import Path

BENCH = Path(__file__).resolve().parent
RESULTS = BENCH / "results"
README = BENCH.parent / "README.md"


def load():
    rows = [json.loads(l) for l in (RESULTS / "runs.jsonl").read_text().splitlines() if l.strip()]
    order = [t["id"] for t in json.loads((BENCH / "tasks.json").read_text())]
    skills = {t["id"]: t["skill"] for t in json.loads((BENCH / "tasks.json").read_text())}
    by = defaultdict(list)
    for r in rows:
        by[(r["task"], r["arm"])].append(r)
    tasks = [t for t in order if (t, "cloud") in by and (t, "local") in by]
    return tasks, skills, by, rows


def agg(runs):
    med = lambda k: statistics.median(r[k] for r in runs)
    return {
        "n": len(runs),
        "cost": med("cost_usd"),
        "fresh": med("input_tokens") + med("cache_write_tokens"),
        "cached": med("cache_read_tokens"),
        "out": med("output_tokens"),
        "turns": med("turns"),
        "secs": med("seconds"),
        "correct": sum(r["correct"] for r in runs),
        "escalated": sum(r.get("escalated", False) for r in runs),
    }


def pct(a, b):
    return (b - a) / a * 100 if a else 0.0


def table(tasks, skills, by):
    head = ("| Task | Skill it covers | Claude cost, cloud vision | Claude cost, with skills | Change "
            "| Fresh input tokens | Correct, cloud / skills | Claude read the file itself (skills installed) |\n|---|---|--:|--:|--:|--:|:-:|:-:|")
    lines, tot_c, tot_l = [head], 0.0, 0.0
    for t in tasks:
        c, l = agg(by[(t, "cloud")]), agg(by[(t, "local")])
        tot_c += c["cost"]; tot_l += l["cost"]
        lines.append(f"| `{t}` | {skills[t]} | ${c['cost']:.3f} | ${l['cost']:.3f} | {pct(c['cost'], l['cost']):+.0f}% "
                     f"| {c['fresh']:,.0f} → {l['fresh']:,.0f} | {c['correct']}/{c['n']} / {l['correct']}/{l['n']} "
                     f"| {l['escalated']}/{l['n']} |")
    lines.append(f"| **All tasks** | | **${tot_c:.3f}** | **${tot_l:.3f}** | **{pct(tot_c, tot_l):+.0f}%** | | | |")
    return "\n".join(lines)


def svg(tasks, by, model, reps):
    """Paired horizontal bars: median cost per task, cloud vs local. Static SVG for a README,
    themed for light and dark with a prefers-color-scheme block."""
    data = [(t, agg(by[(t, "cloud")]), agg(by[(t, "local")])) for t in tasks]
    vmax = max(max(c["cost"], l["cost"]) for _, c, l in data)
    step = 0.02 if vmax <= 0.12 else 0.05 if vmax <= 0.3 else 0.1
    top = step * (int(vmax / step) + 1)
    W, label_w, right = 760, 150, 150
    plot_w = W - label_w - right
    bar_h, gap, group_gap, y0 = 12, 2, 18, 92
    H = y0 + len(data) * (2 * bar_h + gap + group_gap) + 40
    x = lambda v: label_w + v / top * plot_w
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
           f'font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif" role="img" '
           f'aria-label="Claude cost per task, cloud vision versus on-device skills">',
           """<style>
  .bg{fill:#fcfcfb} .t1{fill:#0b0b0b} .t2{fill:#52514e} .grid{stroke:#e4e3df} .axis{stroke:#b9b8b2}
  .cloud{fill:#2a78d6} .local{fill:#eb6834} .bad{fill:#c62828}
  @media (prefers-color-scheme: dark){
    .bg{fill:#1a1a19} .t1{fill:#ffffff} .t2{fill:#c3c2b7} .grid{stroke:#2e2e2c} .axis{stroke:#55544f}
    .cloud{fill:#3987e5} .local{fill:#d95926} .bad{fill:#ff6b6b}
  }
</style>""",
           f'<rect class="bg" width="{W}" height="{H}" rx="8"/>',
           f'<text class="t1" x="20" y="30" font-size="16" font-weight="600">What Claude spends per task: reading it itself vs handing it to on-device fm</text>',
           f'<text class="t2" x="20" y="50" font-size="12">Claude\u2019s spend only (the on-device fm work is free). Median of {reps} runs, {model}, USD list price. Lower is better.</text>']
    # legend
    lx = 20
    for cls, name in (("cloud", "Claude reads it (cloud vision)"), ("local", "Claude + on-device fm skills")):
        out.append(f'<rect class="{cls}" x="{lx}" y="62" width="12" height="12" rx="2"/>'
                   f'<text class="t2" x="{lx + 18}" y="72" font-size="12">{name}</text>')
        lx += 230
    out.append(f'<text class="t2" x="{W - 20}" y="72" font-size="12" text-anchor="end">change \u00b7 correct with skills</text>')
    # grid + ticks
    gb = H - 34
    v = 0.0
    while v <= top + 1e-9:
        out.append(f'<line class="grid" x1="{x(v):.1f}" x2="{x(v):.1f}" y1="{y0 - 6}" y2="{gb}"/>'
                   f'<text class="t2" x="{x(v):.1f}" y="{gb + 16}" font-size="11" text-anchor="middle">${v:.2f}</text>')
        v += step
    out.append(f'<line class="axis" x1="{label_w}" x2="{label_w}" y1="{y0 - 6}" y2="{gb}"/>')
    y = y0
    for t, c, l in data:
        out.append(f'<text class="t1" x="{label_w - 10}" y="{y + bar_h + 5}" font-size="12" text-anchor="end">{t}</text>')
        for i, (cls, a) in enumerate((("cloud", c), ("local", l))):
            by_ = y + i * (bar_h + gap)
            w = max(x(a["cost"]) - label_w, 2)
            out.append(f'<rect class="{cls}" x="{label_w}" y="{by_}" width="{w:.1f}" height="{bar_h}" rx="3">'
                       f'<title>{t} · {"cloud" if cls == "cloud" else "local"}: ${a["cost"]:.3f}, '
                       f'{a["fresh"]:,.0f} fresh input tokens, {a["turns"]:.0f} turns</title></rect>')
        ch = pct(c["cost"], l["cost"])
        ok = f'{l["correct"]}/{l["n"]}'
        cls_ok = "t2" if l["correct"] == l["n"] else "bad"
        out.append(f'<text class="t1" x="{W - 60}" y="{y + bar_h + 5}" font-size="12" text-anchor="end" '
                   f'font-weight="600">{ch:+.0f}%</text>'
                   f'<text class="{cls_ok}" x="{W - 20}" y="{y + bar_h + 5}" font-size="12" text-anchor="end">{ok}</text>')
        y += 2 * bar_h + gap + group_gap
    out.append("</svg>")
    return "\n".join(out)


def main():
    tasks, skills, by, rows = load()
    model = rows[-1]["model"]
    reps = max(r["rep"] for r in rows)
    tbl = table(tasks, skills, by)
    (RESULTS / "savings.svg").write_text(svg(tasks, by, model, reps) + "\n")
    (RESULTS / "summary.md").write_text(tbl + "\n")
    text = README.read_text()
    new = re.sub(r"(<!-- BENCH:START -->\n).*?(<!-- BENCH:END -->)", lambda m: m[1] + tbl + "\n" + m[2], text, flags=re.S)
    if new != text:
        README.write_text(new)
    print(tbl)


if __name__ == "__main__":
    main()
