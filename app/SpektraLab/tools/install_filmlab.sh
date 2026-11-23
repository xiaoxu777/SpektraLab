#!/bin/zsh
# install_filmlab.sh — puts the Release build of FilmLab in /Applications and tells Launch Services about it, so
# Finder, Adobe Bridge and the Dock offer it under Open With. Run after each build you want to use day to day.
set -euo pipefail
HERE=${0:A:h:h}
BUILT="$HERE/build/DerivedData/Build/Products/Release-maccatalyst/FilmLab.app"
DEST="/Applications/FilmLab.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -d "$BUILT" ]] || { echo "No Release build at $BUILT"; exit 1; }
pkill -x FilmLab 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
# Only the installed copy answers Open With. macOS finds any app on disk again by itself, so the build folders'
# copies are not just forgotten but removed (the next build makes its own again; run this after it).
for old in "$HERE"/build/*/Build/Products/*-maccatalyst/FilmLab.app(N); do
  "$LSREG" -u "$old" 2>/dev/null || true
  rm -rf "$old"
done
"$LSREG" -f -R "$DEST"
echo "Installed $DEST"
