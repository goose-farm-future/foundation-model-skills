#!/usr/bin/env python3
"""Score fm's text extraction against the known source text of each fixture, with no Claude involved.

    bench/ocr_accuracy.py

Similarity is difflib's ratio over lower-cased, whitespace-collapsed text (1.0 = identical).
"""
import difflib, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FX = ROOT / "bench" / "fixtures"
RECEIPT = ("CORNER CAFE 12 Harbour St, Mooloolaba Flat white ........ $5.20 Banana bread ...... $6.50 "
           "Orange juice ...... $4.80 TOTAL ............ $16.50 Order #A-7731")
CASES = [  # label, plugin, args, source text
    ("receipt.png · ocr", "ocr", ["receipt.png"], RECEIPT),
    ("receipt-rotated.png · ocr", "ocr", ["receipt-rotated.png"], RECEIPT),
    ("report.pdf · pdf-to-text (text layer)", "pdf-to-text", ["report.pdf"], (FX / "src/report.txt").read_text()),
    ("report.pdf · pdf-to-text --force-ocr", "pdf-to-text", ["report.pdf", "--force-ocr"], (FX / "src/report.txt").read_text()),
]


def norm(s):
    s = re.sub(r"<!--.*?-->|^## Page .*$", "", s, flags=re.M)
    return re.sub(r"\s+", " ", s).strip().lower()


def main():
    print("| Input · command | Similarity to source |\n|---|--:|")
    for label, plugin, args, truth in CASES:
        out = subprocess.run([ROOT / "plugins" / plugin / "bin" / "fm", plugin, *args],
                             cwd=FX, capture_output=True, text=True).stdout
        print(f"| {label} | {difflib.SequenceMatcher(None, norm(out), norm(truth)).ratio():.1%} |")


if __name__ == "__main__":
    main()
