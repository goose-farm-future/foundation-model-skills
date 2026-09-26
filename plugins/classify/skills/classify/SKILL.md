---
name: classify
description: Classify batches of local text into supplied labels or topic tags using Apple's on-device model. Use for feedback, tickets and document organisation.
---

# classify

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" classify "<file|folder|->" --labels "bug,feature,praise" --lines --output "<result.json>"
"${CLAUDE_PLUGIN_ROOT}/bin/fm" classify "<file|folder|->" --output "<tags.json>"
```

With `--labels`, the general local model chooses exactly one supplied label or `unknown`. Without it, Apple's content-tagging model returns up to three topic tags. Labels are checked against the supplied list. These are model classifications, not calibrated probabilities. They can be wrong on plain cases: in testing, "I was charged twice" came back `unknown` instead of `billing`, and praise that mentioned billing was labelled `billing`. If Apple's model refuses a record, it gets the label `refused` and the run continues; counts include `refused`.

`--lines` makes each nonempty line a record, useful for tickets or feedback. Otherwise records are document passages. Long records are split to the model's measured token budget; counts then describe passages, not necessarily whole documents. Every record has source, page and starting-line references. Input supports UTF-8 text, PDF and images; folders are recursive. PDF options: `--pages N-M`, `--max-pages N`, `--force-ocr`.

Use the saved JSON's counts and selected rows instead of rereading all source text. Existing output files require `--overwrite`. Processing runs locally with no API charge; anything read back by the assistant enters its context.
