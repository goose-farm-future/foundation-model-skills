---
name: local-search
description: Search a selected local document collection semantically and return short source passages with file, page and line references.
---

# local-search

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" local-search "<file|folder>" --query "<question>" --limit 5 [--output "<matches.json>"]
```

Builds an in-memory index from the selected files using Apple NaturalLanguage sentence embeddings plus lexical matches. It reads files directly, so no Spotlight registration or persistent index is required. Results contain exact source passages, not generated answers. Use their file/page/line references for follow-up reading.

The default embedding language is `en`; set `--language <code>` for another supported language. If no sentence embedding is installed for that language, the command reports a lexical fallback. `--lexical` explicitly chooses keyword ranking. Scores are ranking signals, not confidence levels. No match does not establish that a fact is absent.

Text, PDF and image files are supported; folders are recursive with hidden files and symlinks skipped. PDF options: `--pages N-M`, `--max-pages N`, `--force-ocr`. All pages are processed by default. Limit is 1–100 passages. Existing output files require `--overwrite`.

Keep queries focused and read only the strongest passages. This skill performs no network requests and has no API charge. Source passages returned to a cloud assistant become part of that assistant's context.
