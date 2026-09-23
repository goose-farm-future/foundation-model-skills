#!/usr/bin/env python3
"""Measure what Claude spends on each task in bench/tasks.json, with and without the on-device skills.

Each task is run through headless Claude Code (`claude -p`) in two arms:
  cloud  - no plugins: Claude reads the image/PDF itself (cloud vision)
  local  - this repo's plugins loaded, Bash allowed for the bundled fm
Both arms get the same tools (Read, Bash, Skill), project-only settings and no MCP servers, so
the only difference is the plugins. A warm-up call per arm primes the prompt cache before anything is measured.

    bench/run.py                        # every task, both arms, 3 reps
    bench/run.py --tasks receipt,chart --reps 1
    bench/run.py --model claude-sonnet-5

Appends one JSON line per run to bench/results/runs.jsonl (raw transcripts go to
bench/results/raw/, which is git-ignored). Then run bench/report.py.
"""
import argparse, datetime, json, re, subprocess, sys, time, uuid
from pathlib import Path

BENCH = Path(__file__).resolve().parent
ROOT = BENCH.parent
FIXTURES = BENCH / "fixtures"
RESULTS = BENCH / "results"
PLUGINS = ["ocr", "pdf-to-text", "describe-image", "ask-image"]
MEDIA = re.compile(r"\.(png|jpe?g|heic|heif|gif|webp|tiff?|bmp|pdf)$", re.I)


def arm_args(arm):
    common = ["--output-format", "stream-json", "--verbose", "--no-session-persistence",
              "--setting-sources", "project", "--strict-mcp-config", "--permission-mode", "dontAsk",
              "--tools", "Read,Bash,Skill"]
    if arm == "cloud":
        return common
    allow = []
    for p in PLUGINS:
        fm = ROOT / "plugins" / p / "bin" / "fm"
        allow += [f"Bash({fm}:*)", f'Bash("{fm}":*)']
    args = common + ["--allowedTools", *allow, "Skill"]
    for p in PLUGINS:
        args += ["--plugin-dir", str(ROOT / "plugins" / p)]
    return args


def run_claude(prompt, arm, model):
    # A unique tag keeps repeated runs from hitting each other's prompt cache, so every run pays
    # for its image/PDF like a first read would. The shared system prompt still caches.
    prompt = f"[bench run {uuid.uuid4().hex[:8]}] {prompt}"
    cmd = ["claude", "-p", prompt, "--model", model, *arm_args(arm)]
    t0 = time.time()
    proc = subprocess.run(cmd, cwd=FIXTURES, capture_output=True, text=True, timeout=600)
    events = [json.loads(l) for l in proc.stdout.splitlines() if l.startswith("{")]
    result = next((e for e in reversed(events) if e.get("type") == "result"), None)
    if result is None:
        sys.exit(f"claude produced no result ({arm}):\n{proc.stderr[-2000:]}")
    return events, result, time.time() - t0


def tool_calls(events):
    calls = []
    for e in events:
        if e.get("type") != "assistant":
            continue
        for block in e["message"].get("content", []):
            if block.get("type") == "tool_use":
                calls.append({"name": block["name"], "input": block.get("input", {})})
    return calls


def summarise(task, arm, rep, model, events, result, secs):
    u = result.get("usage", {})
    calls = tool_calls(events)
    answer = result.get("result", "")
    hits = [bool(re.search(p, answer, re.I)) for p in task["expect"]]
    media_reads = [c for c in calls if c["name"] == "Read" and MEDIA.search(c["input"].get("file_path", ""))]
    fm_calls = [c for c in calls if c["name"] == "Bash" and "/bin/fm" in c["input"].get("command", "")]
    return {
        "time": datetime.datetime.now().isoformat(timespec="seconds"),
        "task": task["id"], "skill": task["skill"], "arm": arm, "rep": rep, "model": model,
        "input_tokens": u.get("input_tokens", 0),
        "cache_write_tokens": u.get("cache_creation_input_tokens", 0),
        "cache_read_tokens": u.get("cache_read_input_tokens", 0),
        "output_tokens": u.get("output_tokens", 0),
        "cost_usd": result.get("total_cost_usd", 0),
        "turns": result.get("num_turns", 0),
        "seconds": round(secs, 1),
        "fm_calls": len(fm_calls),
        # A local-arm run that also Read the image/PDF itself fell back to cloud vision.
        "media_reads": len(media_reads),
        "escalated": arm == "local" and len(media_reads) >= 1,
        "facts_found": sum(hits), "facts_total": len(hits), "correct": all(hits),
        "answer": answer,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tasks", help="comma-separated task ids (default: all)")
    ap.add_argument("--arms", default="cloud,local")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--model", default="claude-opus-5-5")
    a = ap.parse_args()

    tasks = json.loads((BENCH / "tasks.json").read_text())
    if a.tasks:
        wanted = a.tasks.split(",")
        tasks = [t for t in tasks if t["id"] in wanted]
    arms = a.arms.split(",")
    (RESULTS / "raw").mkdir(parents=True, exist_ok=True)

    for arm in arms:  # warm the prompt cache so the first measured task isn't charged for it
        run_claude("Reply with OK.", arm, a.model)

    with open(RESULTS / "runs.jsonl", "a") as out:
        for rep in range(1, a.reps + 1):
            for task in tasks:
                for arm in arms:
                    events, result, secs = run_claude(task["prompt"], arm, a.model)
                    row = summarise(task, arm, rep, a.model, events, result, secs)
                    stamp = row["time"].replace(":", "")
                    (RESULTS / "raw" / f"{task['id']}.{arm}.{rep}.{stamp}.jsonl").write_text(
                        "\n".join(json.dumps(e) for e in events))
                    out.write(json.dumps(row) + "\n"); out.flush()
                    fresh = row["input_tokens"] + row["cache_write_tokens"]
                    print(f"{task['id']:16} {arm:5} rep{rep}  fresh-in {fresh:6}  out {row['output_tokens']:5}  "
                          f"${row['cost_usd']:.3f}  {row['facts_found']}/{row['facts_total']}"
                          f"{'  ESCALATED' if row['escalated'] else ''}", flush=True)


if __name__ == "__main__":
    main()
