#!/usr/bin/env python3
"""Fixture-backed local integration tests. No cloud model or paid API calls."""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import traceback
import uuid

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / ".build/fixtures"
RUN = ROOT / ".build/verification" / (time.strftime("%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:6])
RUN.mkdir(parents=True)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--download-assets", action="store_true")
parser.add_argument("--only", help="comma-separated test names")
ARGS = parser.parse_args()
RESULTS = []


class Unavailable(Exception):
    pass


def invoke(skill, *args, stdin=None, expect=0, timeout=180):
    proc = subprocess.run([str(ROOT / "plugins" / skill / "bin/fm"), skill, *map(str, args)],
                          cwd=ROOT, input=stdin, text=True, capture_output=True, timeout=timeout)
    if proc.returncode != expect:
        message = proc.stderr + proc.stdout
        if not ARGS.download_assets and "--download-assets" in message:
            raise Unavailable(message.strip())
        raise AssertionError(f"{skill} exit {proc.returncode}, expected {expect}: {message}")
    return proc.stdout


def result(skill, *args, **kwargs):
    return json.loads(invoke(skill, *args, **kwargs))


def test(name):
    def register(fn):
        if ARGS.only and name not in ARGS.only.split(","):
            return fn
        started = time.monotonic()
        try:
            fn()
            item = {"test": name, "status": "passed"}
        except Unavailable as error:
            item = {"test": name, "status": "skipped", "reason": str(error)}
        except Exception as error:
            item = {"test": name, "status": "failed", "reason": str(error), "traceback": traceback.format_exc()}
        item["seconds"] = round(time.monotonic() - started, 3)
        item["local_api_cost_usd"] = 0
        RESULTS.append(item)
        print(json.dumps(item), flush=True)
        return fn
    return register


@test("packaging")
def packaging():
    market = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())
    assert len(market["plugins"]) == 10
    checksums = set()
    for plugin in market["plugins"]:
        directory = ROOT / plugin["source"]
        manifest = json.loads((directory / ".claude-plugin/plugin.json").read_text())
        assert manifest["name"] == plugin["name"] and manifest["version"] == plugin["version"]
        assert (directory / "skills" / plugin["name"] / "SKILL.md").is_file()
        checksums.add(hashlib.sha256((directory / "bin/fm-darwin-arm64").read_bytes()).hexdigest())
        help_result = subprocess.run([str(directory / "bin/fm"), "--help"], capture_output=True, text=True)
        assert help_result.returncode == 0 and plugin["name"] in help_result.stdout
    assert len(checksums) == 1


@test("table-to-csv")
def tables():
    manifest = result("table-to-csv", FIX / "table.png", "--output", RUN / "tables")
    saved = json.loads(Path(manifest["manifest"]).read_text())
    assert manifest["files"] == 1 and len(saved["files"]) == 1
    rows = list(csv.reader(Path(saved["files"][0]["output"]).open()))
    assert rows[0] == ["Product", "Quantity", "Amount"], rows
    assert rows[1] == ["Apples", "3", "12.50"], rows
    assert rows[2] == ["Tea", "2", "9.00"], rows
    assert saved["files"][0]["columns"] == 3
    assert saved["files"][0]["cells"][0]["row_start"] == 0


@test("extract")
def extraction():
    output = RUN / "extracted.json"
    manifest = result("extract", FIX / "invoice.txt", "--fields", "invoice_number,total,due_date,purchase_order", "--output", output)
    data = json.loads(output.read_text())
    assert manifest["records"] == 1
    fields = data["records"][0]["fields"]
    assert fields["invoice_number"]["value"] == "INV-2048", fields
    assert "1,284.50" in fields["total"]["value"], fields
    assert fields["purchase_order"]["value"] is None, fields
    source = (FIX / "invoice.txt").read_text()
    for field in fields.values():
        for evidence in field["evidence"]:
            assert evidence["quote"] in source and evidence["value"] in evidence["quote"]


@test("extract-schema-batch")
def schema_batch():
    sources = RUN / "invoices"
    sources.mkdir()
    (sources / "first.txt").write_text("Invoice number: FIRST-105\nTotal due: $42.00\n")
    (sources / "second.txt").write_text("Invoice number: SECOND-209\nTotal due: $18.00\n")
    schema = RUN / "fields.json"
    schema.write_text(json.dumps({"id": "Invoice number"}))
    data = result("extract", sources, "--schema", schema)
    assert {r["fields"]["id"]["value"] for r in data["records"]} == {"FIRST-105", "SECOND-209"}


@test("condense")
def condensation():
    lines = [f"INFO completed item {i}" for i in range(1000)]
    lines[40] = lines[600] = "ERROR payment.ts:42 E1007: cannot resolve account"
    lines[80] = "WARNING queue backlog is 15"
    data = result("condense", "-", "--max-lines", "1", stdin="\n".join(lines))
    assert data["total_lines"] == 1000
    assert data["omitted_events"] == 1
    event = data["events"][0]
    assert event["text"] == lines[40] and event["count"] == 2
    assert event["line_numbers"] == [41, 601]
    assert lines[39] in event["context"]


@test("extract-field-coverage")
def extraction_coverage():
    source = RUN / "coverage.txt"
    source.write_text("INVOICE\nSupplier: Cedar Office Supplies\nInvoice number: CED-1042\nIssued: 2026-08-01\nSubtotal: AUD 100.00\nGST: AUD 10.00\nTotal amount due: AUD 110.00\nPayment due date: 2026-08-31\n")
    schema = RUN / "coverage-schema.json"
    schema.write_text(json.dumps({"supplier": "Name of the supplier issuing the invoice", "invoice_number": "Invoice identifier, not the date", "total": "Total amount due including currency", "due_date": "Explicit payment due date, not invoice issue date"}))
    data = result("extract", source, "--schema", schema)
    fields = data["records"][0]["fields"]
    assert fields["invoice_number"]["value"] == "CED-1042", fields
    assert fields["due_date"]["value"] == "2026-08-31", fields
    assert fields["total"]["value"] == "AUD 110.00", fields
    missing = result("extract", "-", "--schema", schema, stdin="INVOICE\nSupplier: Horizon Hosting\nInvoice number: HH-008\nInvoice date: 2026-08-05\nTotal amount due: AUD 55.00\n")
    assert missing["records"][0]["fields"]["due_date"]["status"] == "missing", missing
    conflict = result("extract", "-", "--fields", "total", stdin="Invoice total: AUD 10.00\nRevised invoice total: AUD 12.00\n")
    field = conflict["records"][0]["fields"]["total"]
    assert field["status"] == "conflict" and field["value"] is None and len(field["alternatives"]) == 2, field


@test("condense-explain")
def explanation():
    data = result("condense", "-", "--explain", stdin="ERROR main.swift:17: missing required argument\n")
    assert data["events"][0]["text"] == "ERROR main.swift:17: missing required argument"
    assert data["explanations"] and isinstance(data["explanations"][0], str)


@test("classify")
def classification():
    text = "The checkout crashes when I press pay.\nPlease add a dark theme.\n"
    data = result("classify", "-", "--lines", "--labels", "bug,feature", stdin=text)
    assert [r["labels"] for r in data["records"]] == [["bug"], ["feature"]], data
    assert data["counts"] == {"bug": 1, "feature": 1}


@test("classify-tags")
def tags():
    data = result("classify", "-", stdin="We went hiking in the forest and watched birds.")
    assert data["records"] and 1 <= len(data["records"][0]["labels"]) <= 3


@test("model-chunking")
def chunking():
    source = "The checkout fails with an error when paying.\n" * 500
    data = result("classify", "-", "--labels", "bug,feature", stdin=source)
    assert len(data["records"]) > 1
    assert sum(row["characters"] for row in data["records"]) == len(source)
    assert data["records"][-1]["line_start"] > 1


@test("local-search")
def search():
    data = result("local-search", ROOT / "bench/fixtures/ops-review.pdf", "--query", "Warehouse B lease expiry date", "--limit", "2")
    assert 1 <= len(data["matches"]) <= 2
    assert data["matches"][0]["page"] == 17
    assert "30 June 2028" in data["matches"][0]["text"]
    lexical = result("local-search", FIX / "invoice.txt", "--query", "INV-2048", "--lexical")
    assert lexical["engine"] == "lexical" and lexical["matches"]


@test("transcribe-audio")
def speech():
    extra = ["--download-assets"] if ARGS.download_assets else []
    data = result("transcribe-audio", FIX / "speech.aiff", "--locale", "en-US", *extra)
    assert "invoice" in data["text"].lower() and "october" in data["text"].lower(), data
    assert data["segments"] and all(s["end"] >= s["start"] >= 0 for s in data["segments"])
    output = RUN / "speech.vtt"
    result("transcribe-audio", FIX / "speech.aiff", "--format", "vtt", "--output", output, *extra)
    assert output.read_text().startswith("WEBVTT\n") and " --> " in output.read_text()


@test("translate")
def translation():
    manifest = result("translate", FIX / "translate.txt", "--source", "en", "--target", "es", "--output", RUN / "translated")
    translated = next(Path(manifest["output"]).glob("*.txt")).read_text()
    assert "hola" in translated.lower() and "gracias" in translated.lower(), translated
    assert translated.count("\n") == (FIX / "translate.txt").read_text().count("\n")


@test("translate-model-placeholders")
def translation_model():
    manifest = result("translate", FIX / "strings.json", "--source", "en", "--target", "es", "--engine", "model", "--output", RUN / "translated-model")
    translated = json.loads(next(p for p in Path(manifest["output"]).glob("*.json") if p.name != "manifest.json").read_text())
    assert set(translated) == {"welcome", "count"}
    assert translated["welcome"].count("{name}") == 1
    assert translated["count"].count("%d") == 1
    assert "hola" in translated["welcome"].lower(), translated


@test("image-cutout")
def cutout():
    extra = ["--download-assets"] if ARGS.download_assets else []
    output, mask = RUN / "cutout.png", RUN / "mask.png"
    manifest = result("image-cutout", FIX / "subject.png", "--point", "0.48,0.5", "--output", output, "--mask", mask, *extra)
    inspect = lambda path: json.loads(subprocess.check_output([str(ROOT / ".build/inspect-image"), str(path)], text=True))
    before, after = inspect(FIX / "subject.png"), inspect(output)
    assert (before["width"], before["height"]) == (after["width"], after["height"])
    assert after["has_alpha"] and after["center_alpha"] > 0.9 and after["corner_alpha"] < 0.05, after
    assert inspect(mask)["width"] == manifest["width"]


@test("translate-model-markdown")
def markdown_translation():
    source = RUN / "quick-start.md"
    original = '# Quick start\n\nYou have %d items in your cart.\nRead the [setup guide](https://example.test/setup).\n\n```sh\necho "Hello, {name}"\n```\n'
    source.write_text(original)
    manifest = result("translate", source, "--source", "en", "--target", "fr", "--engine", "model", "--output", RUN / "translated-markdown")
    translated = next(Path(manifest["output"]).glob("*.md")).read_text()
    assert translated.count("\n") == original.count("\n"), translated
    assert translated.startswith("# ") and translated.count("%d") == 1, translated
    assert "(https://example.test/setup)" in translated and "setup))" not in translated, translated
    assert '```sh\necho "Hello, {name}"\n```' in translated, translated


@test("failure-paths")
def errors():
    invoke("classify", "-", "--labels", "bug,bug", stdin="Text", expect=1)
    invoke("extract", FIX / "invoice.txt", "--fields", "id", "--output", FIX / "invoice.txt", "--overwrite", expect=1)
    invoke("local-search", FIX / "invoice.txt", "--query", "total", "--limit", "0", expect=1)
    invoke("extract", ROOT / "tests/fixtures/invoice-text.pdf", "--fields", "id", "--pages", "0", expect=1)
    invoke("image-cutout", FIX / "subject.png", "--point", "2,0", "--output", RUN / "invalid.png", expect=1)
    assert not (RUN / "invalid.png").exists()
    existing = RUN / "existing.json"
    existing.write_text("untouched")
    invoke("condense", "-", "--output", existing, stdin="ERROR failure", expect=1)
    assert existing.read_text() == "untouched"
    original = RUN / "original.txt"
    original.write_text("ERROR source content")
    alias = RUN / "alias.txt"
    os.link(original, alias)
    invoke("condense", original, "--output", alias, "--overwrite", expect=1)
    assert original.read_text() == "ERROR source content"
    (RUN / "bad-strings.json").write_text('{"nested":{"value":"hello"}}')
    invoke("translate", RUN / "bad-strings.json", "--source", "en", "--target", "es", "--engine", "model", "--output", RUN / "bad-translated", expect=1)
    assert not (RUN / "bad-translated").exists()


report = {"artifacts": str(RUN), "results": RESULTS, "local_api_cost_usd": 0}
(RUN / "results.json").write_text(json.dumps(report, indent=2) + "\n")
(RUN.parent / "latest.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"Results: {RUN / 'results.json'}")
sys.exit(1 if any(r["status"] == "failed" for r in RESULTS) else 0)
