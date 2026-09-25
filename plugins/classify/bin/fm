#!/bin/zsh
# Launcher for the on-device fm binary bundled with this plugin.
exe=${0:A:h}/fm-darwin-arm64
if [[ $(uname -sm) != "Darwin arm64" ]]; then
  echo "fm needs an Apple silicon Mac running macOS 27+ with Apple Intelligence enabled." >&2; exit 2
fi
if [[ ! -x $exe ]]; then
  echo "fm: bundled binary missing. Reinstall the plugin, or build from https://github.com/goose-farm-future/foundation-model-skills (scripts/build.sh)." >&2; exit 2
fi
exec $exe "$@"
