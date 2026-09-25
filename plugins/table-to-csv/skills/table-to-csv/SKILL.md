---
name: table-to-csv
description: Extract tables from PDFs, scans or images into CSV locally using Apple Vision. Use for statements, invoices and batches of tabular documents.
---

# table-to-csv

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" table-to-csv "<image|pdf|folder>" --output "<new-folder>" [--pages N-M] [--max-pages N]
```

The output folder must be new. Each recognized table becomes a separate CSV. `manifest.json` records the source file, page, dimensions, text and cell spans. All pages are processed unless explicitly limited. Folders are recursive; hidden files and symlinks are skipped.

Merged-cell text is placed in the top-left cell; the manifest preserves its full span with zero-based inclusive indices. No detected tables is a valid empty result, not proof that the source contains no tables. OCR can misread characters. Check relevant cells against the source text for exact financial or numerical work. CSV cells preserve literal text, including spreadsheet formulas; import untrusted CSV as text when using a spreadsheet app.

Read only the relevant CSV or manifest entries. Processing runs locally with no API charge; anything printed or read back by the calling assistant enters its context. Do not silently upload the original document if local extraction is insufficient.
