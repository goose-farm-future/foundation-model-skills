#!/usr/bin/env python3
"""Local-only retrieval benchmark on a real SEC 10-K. No cloud model, no API cost.

For each question in bench/sec_questions.json, runs the bundled `fm local-search` over the full
filing and checks whether a returned passage contains the exact answer string. Reports hit@1/3/5
and per-query seconds. This measures the step a cloud assistant depends on when it queries a
large document without uploading it: can local retrieval put the answer in the few excerpts it reads?

    scripts/fetch-sec.sh                 # download + render the filing first
    bench/sec_retrieval.py
    bench/sec_retrieval.py --limit 10 --lexical
"""
import argparse, json, subprocess, time
from pathlib import Path

BENCH = Path(__file__).resolve().parent
FM = BENCH.parent / "plugins/local-search/bin/fm"


def search(doc, query, limit, lexical):
    cmd = [str(FM), "local-search", str(doc), "--query", query, "--limit", str(limit)]
    if lexical:
        cmd.append("--lexical")
    t0 = time.monotonic()
    out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
    return json.loads(out), time.monotonic() - t0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--lexical", action="store_true")
    a = ap.parse_args()

    suite = json.loads((BENCH / "sec_questions.json").read_text())
    doc = BENCH / "fixtures" / suite["document"]
    if not doc.exists():
        raise SystemExit(f"missing {doc}; run scripts/fetch-sec.sh")

    rows = []
    for q in suite["questions"]:
        result, secs = search(doc, q["question"], a.limit, a.lexical)
        ranks = [i + 1 for i, m in enumerate(result["matches"]) if q["answer"] in m["text"]]
        rank = ranks[0] if ranks else None
        pages = [m["page"] for m in result["matches"]]
        rows.append({"id": q["id"], "rank": rank, "seconds": round(secs, 1), "pages": pages, "engine": result["engine"]})
        print(f"{q['id']:14} rank {rank or '-':>2}  {secs:5.1f}s  pages {pages}  (answer on {q['pages']})", flush=True)

    n = len(rows)
    for k in (1, 3, 5):
        if k <= a.limit:
            print(f"hit@{k}: {sum(1 for r in rows if r['rank'] and r['rank'] <= k)}/{n}")
    print(f"median seconds: {sorted(r['seconds'] for r in rows)[n // 2]}  engine: {rows[0]['engine']}")


if __name__ == "__main__":
    main()
