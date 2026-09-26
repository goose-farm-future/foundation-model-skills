---
name: table-to-csv
description: Extract tables from PDFs, scans or images into CSV locally using Apple Vision. Use for statements, invoices and batches of tabular documents.
---

# table-to-csv

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" table-to-csv "<image|pdf|folder>" --output "<new-folder>" [--pages N-M] [--max-pages N]
```

The output folder must be new. Each recognized table becomes a separate CSV. `manifest.json` records the source file, page, dimensions, text and cell spans. All pages are processed unless explicitly limited. Folders are recursive; hidden files and symlinks are skipped.

Vision finds each table's rows and columns. On PDF pages with a text layer, each cell's text is then copied exactly from the PDF, not read from pixels. The manifest records each cell's `text_source`: `text layer` (exact), `ocr` (scans and images; can misread `,` as `.` or `$` as `S`), or `empty`. Check `ocr` cells against the source for financial work.

Detection is the limit, not the text. Borderless layouts can be missed entirely; in a 10-K, the income statement, balance sheet and cash-flow statement were not detected. A row label can land on the header row, one row above its numbers. Merged-cell text is placed in the top-left cell; the manifest keeps its full span with zero-based inclusive indices. No detected tables is a valid empty result, not proof that the source has none. For a missed table, use `pdf-to-text` on that page. CSV cells preserve literal text, including spreadsheet formulas; import untrusted CSV as text in a spreadsheet app.

Read only the relevant CSV or manifest entries. Processing runs locally with no API charge; anything printed or read back by the calling assistant enters its context. Do not silently upload the original document if local extraction is insufficient.
