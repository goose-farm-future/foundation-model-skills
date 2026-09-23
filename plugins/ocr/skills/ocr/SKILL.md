---
name: ocr
description: On-device OCR (Apple Vision) for images and scanned PDFs. Use for bulk images, scanned multi-page PDFs, or when the user wants a file kept on their Mac. For one ordinary screenshot, just Read it.
---

# ocr

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" ocr "<image|file.pdf>" [--pages N-M]
```

- Apple Vision's accurate text recogniser, with language detection and correction. EXIF orientation, transparency and small images are handled automatically.
- Output is the text in reading order, one visual line per line, with wide gaps between columns shown as three spaces.
- For PDFs every page is rendered and OCR'd, ignoring any embedded text layer. This catches e-signature fields, stamps, annotations and handwriting that text layers miss. For ordinary PDFs, `pdf-to-text` (if installed) is faster and lossless.
- `[no text detected]` means Vision found no text. Don't infer contents from that.

Vision's characters are reliable (numbers, codes, names), but reading order can break on rotated or multi-column images, so reassemble lines yourself when the layout matters. If you also need to know what the image *shows*, use the `describe-image` or `ask-image` skills (if installed). Escalate to Read (cloud vision) only if the OCR is clearly garbled (e.g. heavy handwriting) or the task needs visual judgement, and tell the user you did.
