#!/bin/zsh
# Generate synthetic, local-only fixtures; no user documents or cloud service.
set -eu
root=${0:A:h:h}
if [[ -z ${DEVELOPER_DIR:-} ]]; then
  for d in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    sdks=($d/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX2[7-9]*.sdk(N))
    if (( ${#sdks} )); then export DEVELOPER_DIR=$d/Contents/Developer; break; fi
  done
fi
mkdir -p "$root/.build/fixtures"
xcrun swiftc "$root/tests/make-fixtures.swift" -o "$root/.build/make-fixtures"
xcrun swiftc "$root/tests/inspect-image.swift" -o "$root/.build/inspect-image"
"$root/.build/make-fixtures" "$root/.build/fixtures"
/usr/bin/say -o "$root/.build/fixtures/speech.aiff" 'The invoice number is four four seven one. Payment is due on October fourteen.'
echo "prepared local fixtures in .build/fixtures"
