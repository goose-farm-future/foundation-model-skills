# foundation-model-skills

A Claude Code plugin marketplace for handing routine work to **local Apple frameworks**. Extract documents, classify batches, search files, transcribe recordings, translate text and cut out images on an Apple silicon Mac.

**Local processing has zero API cost: only your Mac's compute, memory, storage and energy.** No API key, subscription or Private Cloud Compute is used by these commands. The calling cloud assistant still spends tokens selecting a skill and reading its results. Save full artifacts locally and return small manifests or selected excerpts to keep that context small.

## Plugins

Each plugin is independently installable and bundles the same native `fm` executable.

| Plugin | Task | Local engine |
|---|---|---|
| `ocr` | Read text from images and rendered PDF pages | Apple Vision |
| `pdf-to-text` | Read PDF text layers, with OCR for scans | PDFKit + Vision |
| `table-to-csv` | Export recognized tables with row/column structure and source references | Vision document recognition |
| `extract` | Extract requested fields from document batches with exact source quotes | Foundation Models + PDFKit/Vision |
| `condense` | Group log failures, retain exact errors and counts, optionally explain them | Deterministic filtering + optional Foundation Models |
| `classify` | Apply supplied labels or topic tags to local text batches | Foundation Models |
| `local-search` | Return relevant passages from selected local documents | NaturalLanguage sentence embeddings + lexical search |
| `transcribe-audio` | Produce transcripts, timestamped JSON or WebVTT from audio/video | Speech + AVFoundation |
| `translate` | Translate text, Markdown and JSON string catalogs into local artifacts | Translation or Foundation Models |
| `image-cutout` | Isolate a selected subject into a transparent PNG and optional mask | Vision iterative segmentation |

## Requirements

- Apple silicon Mac running **macOS 27 or later**.
- Apple Intelligence enabled for `extract`, `classify`, `condense --explain`, and `translate --engine model`.
- Speech and image segmentation may need Apple's model assets. Use `--download-assets` when a command reports that assets are not ready. Vision can require this preparation flag on subsequent invocations even when assets are cached. These downloads do not upload your input.
- The default Translation engine needs an installed supported language pair. `--engine model` uses the on-device Foundation Model instead. Hardware, locale and model availability are checked at runtime.

Prebuilt arm64 binaries are included; using the plugins does not require Xcode or Python. NaturalLanguage search falls back to lexical ranking if a sentence embedding is unavailable for the requested language.

## Install

```text
/plugin marketplace add goose-farm-future/foundation-model-skills
/plugin install pdf-to-text@foundation-model-skills
/plugin install ocr@foundation-model-skills
/plugin install table-to-csv@foundation-model-skills
/plugin install extract@foundation-model-skills
/plugin install condense@foundation-model-skills
/plugin install classify@foundation-model-skills
/plugin install local-search@foundation-model-skills
/plugin install transcribe-audio@foundation-model-skills
/plugin install translate@foundation-model-skills
/plugin install image-cutout@foundation-model-skills
```

Install the tasks you use. Each skill description adds a small amount to the assistant's context. Run the executable from any installed plugin to inspect capabilities:

```bash
"<plugin-directory>/bin/fm" doctor
"<plugin-directory>/bin/fm" --help
```

## Examples

Here `fm` means the bundled `bin/fm` in an installed plugin, **not** Apple's separate `/usr/bin/fm` command.

```bash
fm table-to-csv statements/ --output tables/
fm extract invoices/ --fields invoice_number,total,due_date --output invoices.json
fm extract contracts/ --schema fields.json --output extracted.json
fm condense build.log --output failures.json --explain
fm classify feedback.txt --lines --labels bug,feature,praise --output labels.json
fm local-search documents/ --query "When does the warehouse lease expire?" --limit 5
fm transcribe-audio meeting.m4a --locale en-AU --format vtt --output meeting.vtt
fm translate strings.json --source en --target es --output translated/
fm translate notes.md --source en --target fr --engine model --output translated-notes/
fm image-cutout product.jpg --point 0.5,0.5 --output product.png --mask mask.png
```

Extraction schemas are JSON objects mapping 1–30 field names to descriptions:

```json
{
  "invoice_number": "Invoice identifier",
  "total": "Total amount due including currency",
  "due_date": "Payment due date"
}
```

Extraction returns copied strings or null, evidence quotes, page/line references and explicit conflicts. It rejects values whose quote is not present in the extracted source text. This is a field-extraction schema, not arbitrary JSON Schema or a promise of semantic accuracy.

Use `--output` for substantial results. JSON commands then print only an artifact path, size and count. Existing output files require `--overwrite`; table and translation output folders must be new and are published after the whole batch succeeds. Inputs cannot be overwritten by their outputs. `extract`, `classify` and `condense` also accept UTF-8 stdin as `-`.

For document commands, `--pages N-M` and `--max-pages N` explicitly limit PDF processing. The new batch commands process all pages by default; the original `ocr` and `pdf-to-text` commands retain their 30-page default. Text extraction, classification and search accept `--force-ocr` for signed, filled-in or annotated PDFs whose text layer is incomplete. Folders are scanned recursively, skipping hidden files, packages and symlinks.

`classify --lines` treats each nonempty line as a record. Otherwise classification counts describe document passages; large records may span multiple passages. Custom-label classification uses the general model; topic tagging uses Apple's content-tagging model. Model inputs are counted against the actual context limit and processed in fresh sessions.

Translation supports plain text/Markdown and flat JSON string catalogs. It preserves JSON keys and verifies protected placeholders, code and URLs. Line breaks are retained; unsupported structures and overlong lines fail explicitly. Review translated prose and Markdown formatting before publishing.

Cutout coordinates use a normalized **top-left** origin after EXIF orientation: `--point x,y` or `--box x,y,width,height`. Outputs keep the oriented input's pixel dimensions. Segmentation quality depends on the subject and selection; inspect edge quality when needed.

## Local processing and cloud context

These commands do not upload source files or fall back to a hosted model. Framework model assets may be downloaded during setup. Apple Translation may collect API usage metadata under Apple's platform policies, but it does not send your source or translated content as part of those metrics.

A cloud assistant receives anything it reads from stdout or from a generated file. Keeping a recording or PDF local does **not** make text copied into the assistant's context private from its cloud provider. For bulk work, return paths, counts, selected evidence and exceptions. Images already pasted into a cloud chat have already been sent there; give the skill a local file path instead.

OCR can misread characters or table structure. Model classification and extraction can be wrong even with valid JSON and real quotes. Search returns ranked source passages, not generated answers or proof that a missing result is absent. Speech output does not identify speakers. Condensation retains exact evidence but does not establish a root cause or preserve a shell command's exit status.

## Validation and benchmarks

The new skills are tested locally without paid cloud calls. Local API cost is zero by design; end-to-end cloud-token savings vary with task size and how much output the caller reads.

Earlier PDF/OCR comparisons remain in [bench/results/summary.md](bench/results/summary.md) and [the summary comparison](bench/results/summary-vs-text.md). They describe the tested configurations at the time, not measurements of this expanded catalogue. In those fixtures, long PDFs benefited substantially from extraction; single images could cost more once skill overhead was included. Summarisation also lost facts that exact extraction retained.

The SEC tasks were measured against the current catalogue. On three questions about Apple's 77-page FY2025 10-K, Claude cost fell 56–73%, and all 18 runs in both arms answered correctly. Without the skills, Claude sent 18–23 page images to cloud vision per question. With them, no page image left the Mac; Claude read 1–17 KB of extracted lines or passages. The `plan-*` rows come from earlier runs whose task definitions were not kept.

```bash
scripts/build.sh
scripts/prepare-fixtures.sh
python3 tests/test_tasks.py                  # all new commands, local model inference only
tests/smoke.sh                            # packaging + original OCR/PDF checks
claude plugin validate .
```

Use `python3 tests/test_tasks.py --download-assets` to allow missing Apple speech/segmentation assets to be installed for integration testing. Otherwise asset-dependent checks are reported as skipped if the model is unavailable. Results and artifacts go under `.build/verification/`.

The historical cloud comparison is opt-in and incurs cloud usage:

```bash
bench/run.py --tasks ops-review-20p --reps 1
bench/report.py
```

The SEC filing is not committed. `SEC_CONTACT=you@example.com scripts/fetch-sec.sh` downloads it from EDGAR (which requires a contact email) and renders it to PDF with headless Chrome. `bench/sec_retrieval.py` then scores `local-search` on it with no cloud calls: whether a passage containing the exact answer reaches the top 1, 3 or 5 results.

Its plugin list comes from the current marketplace. Do not compare a new catalogue's overhead against old results without rerunning the comparison. The local test suite is the capability check for the eight new tasks; historical cloud tasks remain media-focused.

## Development

Building requires Xcode with the macOS 27 SDK. `scripts/build.sh` selects Xcode or Xcode-beta and bundles the executable only into plugins registered in `.claude-plugin/marketplace.json`.

```text
src/main.swift           Original image/PDF commands and entry point
src/LocalTasks.swift     CLI parsing, file IO, manifests and token-aware chunking
src/TextTasks.swift      Extraction, classification and log condensation
src/DocumentTasks.swift  Table export and local document search
src/MediaTasks.swift     Speech, translation and image segmentation
plugins/<task>/          Manifest, skill instructions and bundled executable
scripts/                Build, launcher and fixture preparation
tests/                 Local end-to-end verification
bench/                  Historical cloud-token benchmark and evidence
```

To add a task, implement its command, register its plugin, add concise skill instructions, and add a fixture-backed case to the local test suite. Test behavior and failure paths before claiming support. Measure cloud savings separately if making a numerical savings claim.

The experimental `pdf-summary` plugin is outside the release catalogue.

## License

MIT
