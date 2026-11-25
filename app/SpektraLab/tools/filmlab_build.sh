#!/bin/zsh
# filmlab_build.sh — the Release build, one at a time. Several sessions work in this checkout at once and share
# build/DerivedData; two xcodebuilds there at the same moment fail on the build database. This waits its turn
# (a lock folder, taken by mkdir), builds, and gives the turn back. A lock older than 25 minutes is taken over.
#
#   zsh tools/filmlab_build.sh            # build; the last lines of xcodebuild's output, and its exit status
#
# It does not install: /Applications/FilmLab.app is put there by tools/install_filmlab.sh, which only the
# controlling session runs.
set -uo pipefail
HERE=${0:A:h:h}
cd "$HERE"
LOCK="$HERE/build/.filmlab-build.lock"
mkdir -p "$HERE/build"
waited=0
until mkdir "$LOCK" 2>/dev/null; do
  age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || date +%s) ))
  if (( age > 1500 )); then rm -rf "$LOCK"; continue; fi
  (( waited % 30 == 0 )) && echo "Another build is running ($(cat "$LOCK/who" 2>/dev/null)); waiting…"
  sleep 5; waited=$(( waited + 5 ))
done
echo "pid $$ since $(date +%H:%M:%S)" > "$LOCK/who"
trap 'rm -rf "$LOCK"' EXIT INT TERM
LOG="$HERE/build/filmlab-build-$$.log"
xcodebuild -project SpektraLab.xcodeproj -scheme SpektraLab -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath build/DerivedData build > "$LOG" 2>&1
rc=$?
grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)" "$LOG" | tail -40
echo "Full log: $LOG"
exit $rc
