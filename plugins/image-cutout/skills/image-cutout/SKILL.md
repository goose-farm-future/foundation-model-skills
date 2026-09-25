---
name: image-cutout
description: Isolate a subject in a local image using a point or bounding box and save a transparent PNG and optional mask with Apple Vision.
---

# image-cutout

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/fm" image-cutout "<image>" --point 0.5,0.5 --output "<cutout.png>" --mask "<mask.png>"
"${CLAUDE_PLUGIN_ROOT}/bin/fm" image-cutout "<image>" --box 0.2,0.1,0.5,0.7 --output "<cutout.png>"
```

Choose a point inside the intended subject or a tight box around it. Coordinates are normalized to 0–1, with **top-left origin**, after applying the image's EXIF orientation. A box is `x,y,width,height`; provide exactly one selection method. If the target is ambiguous, resolve the selection before running.

Uses macOS 27 Vision's iterative segmentation. Output preserves the oriented image's dimensions and transparency. `--mask` optionally saves the full-size mask. Existing outputs require `--overwrite`; neither output may replace the input or the other output.

If the command reports that segmentation assets are not ready, rerun with `--download-assets` to prepare or download Apple's on-device model. Vision may require this flag again even with cached assets. No source image is uploaded and there is no API charge. Report output paths; inspect the result when the user's task needs edge-quality verification. A valid PNG alone does not establish a good cutout.
