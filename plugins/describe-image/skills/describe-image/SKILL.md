---
name: describe-image
description: Experimental on-device image description (Apple Foundation Model). Use only when the user wants an image kept on their Mac. Unreliable for charts; otherwise Read the image.
---

# describe-image

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" describe-image "<image|file.pdf>" [--pages N-M]
```

- Runs Apple's on-device model (about 3B parameters) with image input. The image is OCR'd first and that text is handed to the model as the authoritative source for exact characters.
- PDFs are rendered page by page. Use `--pages` to keep it to the pages you need, since each page takes a few seconds.

## Trust levels

- **Layout, objects, colours, chart type, what kind of document or UI:** generally reliable.
- **Exact numbers and names:** take them from `ocr` / `pdf-to-text` output (if installed), not from the description. The small model can misread digits.
- **Fine visual judgement** (design review, subtle UI bugs, dense charts): the small model is weak here. Escalate to Read (cloud vision) and tell the user you did.
