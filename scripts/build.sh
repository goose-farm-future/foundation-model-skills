#!/bin/zsh
# Build the fm binary from src/ and bundle it (with its launcher) into every plugin that uses it.
# Needs Xcode (or Xcode-beta) with the macOS 27+ SDK, which adds image input to FoundationModels.
set -e
root=${0:A:h:h}
plugins=(ocr pdf-to-text describe-image ask-image)

if [[ -z "$DEVELOPER_DIR" ]]; then
  for d in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    sdks=($d/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX2[7-9]*.sdk(N))
    if (( ${#sdks} )); then
      export DEVELOPER_DIR=$d/Contents/Developer; break
    fi
  done
fi

out=$(mktemp -d)
xcrun swiftc -O -parse-as-library -target arm64-apple-macos27.0 "$root/src/main.swift" -o "$out/fm-darwin-arm64"
for p in $plugins; do
  mkdir -p "$root/plugins/$p/bin"
  cp "$out/fm-darwin-arm64" "$root/plugins/$p/bin/fm-darwin-arm64"
  cp "$root/scripts/fm-wrapper.zsh" "$root/plugins/$p/bin/fm"
  chmod +x "$root/plugins/$p/bin/fm" "$root/plugins/$p/bin/fm-darwin-arm64"
done
rm -rf "$out"
echo "built fm and bundled it into: $plugins" >&2
