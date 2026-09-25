---
name: pdf-to-text
description: "Extract a PDF's text on-device (PDFKit + Apple Vision OCR) instead of sending its pages to cloud vision. Use instead of Read for any PDF: contracts, reports, statements, scans."
---

# pdf-to-text

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" pdf-to-text "<file.pdf>" [--pages N-M] [--max-pages N] [--force-ocr]
```

- Reads each page's embedded text layer directly (exact and instant) and uses Apple Vision OCR on pages without one (scans, photos of documents).
- Output is plain text with a `## Page N (text layer|OCR)` header per page.
- Processes the first 30 pages by default. Use `--pages 31-60` for more, or `--max-pages`.
- **Long PDFs: search, don't read everything.** To find something, pipe straight into grep in one command, e.g. `"${CLAUDE_PLUGIN_ROOT}/bin/fm" pdf-to-text "<file.pdf>" | grep -n -i -E '^## Page|<term>'`, which gives the matches and the page they fall on. Don't write to temp files, and don't add context lines (-A/-B/-C) to the page-header pattern. Re-run with `--pages N` to read a page in full. Read the whole output only when the task needs the whole document, like a summary.

## Signed, filled-in or annotated PDFs

Text layers often leave out e-signature fields, typed-in form values, stamps, annotations and handwriting. Watch for tell-tale gaps like "extended until 6 2026" (month missing) or empty-looking dates and names.

When you see them, or the PDF has been signed or filled in, re-run the relevant pages with `--force-ocr`. That OCRs the rendered page, so you get what is visible. Compare the two outputs and cite the OCR version for anything missing from the text layer.

## Keep it local

Do the reasoning (summaries, comparisons, extraction) yourself on the text. Reading the PDF with Read sends its pages to cloud vision, so don't, unless the text can't answer the question (a chart or diagram, visual layout) **and** the user agrees. Say what the text couldn't give you and ask first.
