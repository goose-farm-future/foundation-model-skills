---
name: extract
description: Extract requested fields from local documents into structured JSON with source quotes. Use for bulk invoices, reports, forms and text records.
---

# extract

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" extract "<file|folder|->" --fields "invoice_number,total,due_date" --output "<result.json>"
"${CLAUDE_PLUGIN_ROOT}/bin/fm" extract "<file|folder|->" --schema "<fields.json>" --output "<result.json>"
```

A schema is a JSON object of field names and descriptions, not a general JSON Schema:

```json
{"invoice_number":"Invoice identifier","total":"Total amount due, including currency","due_date":"Payment due date"}
```

Request 1–30 fields. Values are copied strings or null, with exact source quotes and page/line references. Missing fields have status `missing`; conflicting values produce null plus `alternatives` and evidence. Ungrounded model outputs are rejected and counted. Quotes prove the text was present, not that the model chose the correct field. Validate important assignments and OCR values from their evidence.

Text, PDF and image inputs are supported. Folders are recursive. `-` reads UTF-8 stdin. All PDF pages are processed by default; `--pages N-M`, `--max-pages N`, and `--force-ocr` are available. Signed or filled PDFs may need `--force-ocr`. Long inputs are token-counted and split into fresh model sessions without dropping text.

Use an output file for bulk work; stdout then contains only its path and record count. Existing files require `--overwrite`. Read only the fields needed downstream. Processing is on-device with no API charge. No cloud fallback is built in.
