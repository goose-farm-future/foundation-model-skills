---
name: ocr
description: Read the text in an image on-device (Apple Vision) instead of sending it to cloud vision. Use instead of Read for screenshots, photos of documents, receipts, error dialogs and scans.
---

# ocr

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" ocr "<image|file.pdf>" [--pages N-M]
```

- Apple Vision's accurate text recogniser, with language detection and correction. EXIF orientation, transparency and small images are handled automatically.
- Output is the text in reading order, one visual line per line, with wide gaps between columns shown as three spaces.
- For PDFs every page is rendered and OCR'd, ignoring any embedded text layer. This catches e-signature fields, stamps, annotations and handwriting that text layers miss. For ordinary PDFs, `pdf-to-text` (if installed) is faster and lossless.
- `[no text detected]` means Vision found no text. Don't infer contents from that.

Vision's characters are reliable (numbers, codes, names), but reading order can break on rotated or multi-column images, so reassemble lines yourself when the layout matters.

## Keep it local

Answer from the OCR text. Reading the image with Read sends it to cloud vision, so don't, unless the text can't answer the question (heavy handwriting, a chart's shape, visual layout) **and** the user agrees. Say what the OCR couldn't give you and ask first.
