---
name: condense
description: Reduce large local logs, build output and test failures to distinct errors with exact source lines and counts before reading them into context.
---

# condense

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" condense "<log|->" --output "<result.json>" [--max-lines 200] [--explain]
```

The default is deterministic: identify error/warning patterns, group exact duplicate lines, preserve occurrence counts and nearby source lines. `--max-lines` caps distinct events, not input lines; `omitted_events` reports anything excluded. Up to 20 occurrence line numbers per event are included. If no error patterns match, the result contains the first distinct nonempty lines and says so.

`--explain` adds short explanations from the on-device Foundation Model; the exact excerpts remain authoritative. Condensation does not establish a root cause, prove a build passed, or replace an exit code. Read adjacent source lines if the excerpt cuts off a stack trace.

Use a saved log or stdin. When piping a command, preserve its exit status separately; the condenser's success only means the log was processed. Existing output files require `--overwrite`. Local processing has no API charge; read only the relevant events back into the assistant's context.
