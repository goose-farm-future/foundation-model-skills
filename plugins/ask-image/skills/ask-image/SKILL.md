---
name: ask-image
description: Experimental on-device image Q&A (Apple Foundation Model). Use only when the user wants an image kept on their Mac. Unreliable for charts; otherwise Read the image.
---

# ask-image

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" ask-image "<image|file.pdf>" "<question>" [--pages N-M]
```

- The image is OCR'd first and the text is passed to the model as grounding. The model is told to say "not visible" rather than guess.
- Ask one focused question per call. The on-device context window is small, and narrow questions get better answers.

## Checking answers

- If the answer is a number, date, name or code, confirm it against `ocr` / `pdf-to-text` output (if installed) before relying on it.
- If the answer is "not visible" but you expect it to be there, try the `ocr` skill (if installed) and read the text yourself.
- Don't pass on an answer you can't verify. If the question depends on the shape of a chart or anything not printed as text, Read the image instead (unless the user asked to keep it local), and tell the user you did.
