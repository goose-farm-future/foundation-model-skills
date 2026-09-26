---
name: transcribe-audio
description: Transcribe local audio or video into text, timestamped JSON or WebVTT subtitles using Apple's on-device Speech framework.
---

# transcribe-audio

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" transcribe-audio "<audio|video>" --locale en-US --format json --output "<transcript.json>"
"${CLAUDE_PLUGIN_ROOT}/bin/fm" transcribe-audio "<audio|video>" --locale en-US --format vtt --output "<subtitles.vtt>"
```

Formats: `json` (default, timestamped segments and full text), `txt`, `vtt`. Apple AVFoundation must support the media's audio track. Set the spoken locale explicitly for non-US English. There is no speaker identification; do not attribute speech to named people from these results alone.

Locales listed as installed by `fm doctor` work without a flag. For any other locale, the command says the assets are missing; rerun with `--download-assets` to download the on-device model. This downloads model assets, not a cloud transcription service. Unsupported hardware or languages produce an actionable error. Existing output files require `--overwrite`.

Save the transcript, then search it for relevant passages before reading into context. Transcription can mishear names, numbers and technical terms. Check spoken amounts in particular: in testing, "four hundred and sixteen billion dollars" was written as `$416000000` (416 million), and "Warehouse B" as "warehouse be". Local transcription has no API charge and does not upload the recording.
