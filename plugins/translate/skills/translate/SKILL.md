---
name: translate
description: Translate batches of local text, Markdown or JSON string catalogs on-device and save the translated artifacts with a compact manifest.
---

# translate

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" translate "<file|folder>" --source en --target es --output "<new-folder>"
"${CLAUDE_PLUGIN_ROOT}/bin/fm" translate "<file|folder>" --source en --target es --engine model --output "<new-folder>"
```

`system` (default) uses Apple Translation with installed language packs. Its error explains missing packs. `model` uses Apple's on-device Foundation Model for supported languages and does not need separate Translation packs. Both have no API charge and process content locally.

Inputs: UTF-8 `.txt`, `.md`, `.markdown`, and flat JSON objects whose values are strings. JSON keys are preserved. Recognized printf placeholders, `{name}`/`{{name}}` placeholders, code spans/fences and URLs are protected; a changed placeholder fails the operation. Markdown is translated as text: review markup, meaning and tone. Unsupported JSON structures fail explicitly.

The output folder must be new. Each file has a numbered name to avoid collisions; `manifest.json` maps originals to translations. The folder is published only after every file succeeds. Line breaks are preserved. Overlong lines produce a request to split into shorter paragraphs instead of truncating content.

Return artifact paths and a short report. Read sample translations only as needed; rereading the entire translated batch into a cloud model defeats the token-saving purpose.
