#!/bin/zsh
# filmlab_dmg.sh — packages an installed app; all artwork and Finder changes stay in the image.
# Usage: tools/filmlab_dmg.sh [app-path] [output.dmg]
set -euo pipefail
HERE=${0:A:h:h}
[[ $# -le 2 ]] || { echo "Usage: $0 [app-path] [output.dmg]" >&2; exit 1; }
APP=${1:-/Applications/FilmLab.app}
APP=${APP:A}
[[ -d "$APP" && -f "$APP/Contents/Info.plist" ]] || { echo "No app at $APP" >&2; exit 1; }
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ -n "$VERSION" && "$VERSION" != */* && "$VERSION" != *$'\n'* ]] || { echo "Invalid app version" >&2; exit 1; }
DEST=${2:-$HERE/build/dist/FilmLab-$VERSION.dmg}
DEST=${DEST:A}
[[ "$DEST" != "$APP" && "$DEST" != "$APP"/* ]] || { echo "Output must be outside the installed app" >&2; exit 1; }
mkdir -p "${DEST:h}"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/filmlab-dmg.XXXXXX")
STAGE="$WORK/stage"
MOUNT="$WORK/mount"
MOUNTED=0
cleanup() {
  local result=$?
  trap - EXIT INT TERM
  if (( MOUNTED )); then
    if ! hdiutil detach "$MOUNT" -quiet; then
      echo "Warning: could not detach $MOUNT; temporary files kept at $WORK" >&2
      (( result != 0 )) || result=1
      exit $result
    fi
  fi
  rm -rf "$WORK"
  exit $result
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$STAGE/.background" "$MOUNT" "$WORK/swift-cache"
# Keep Swift's compilation cache temporary too; the installed bundle is only ever read.
swift -module-cache-path "$WORK/swift-cache" "$HERE/tools/filmlab_dmg_background.swift" \
  "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png"
tiffutil -cathidpicheck "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png" \
  -out "$STAGE/.background/background.tiff"
rm "$STAGE/.background/background.png" "$STAGE/.background/background@2x.png"
ditto "$APP" "$STAGE/FilmLab.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -srcfolder "$STAGE" -volname FilmLab -fs HFS+ -format UDRW "$WORK/FilmLab-rw.dmg"
# Finder only keeps icon view options (icon size, background picture) for a volume it shows as a disk, so the image
# is attached the ordinary way under /Volumes and addressed as a disk, not as a folder at a private mount point.
[[ ! -e /Volumes/FilmLab ]] || { echo "/Volumes/FilmLab is already mounted; eject it first" >&2; exit 1; }
MOUNT=/Volumes/FilmLab
# Mark before attaching so cleanup also handles a partially successful attach.
MOUNTED=1
hdiutil attach "$WORK/FilmLab-rw.dmg" -noverify -noautoopen
[[ -d "$MOUNT/FilmLab.app" ]] || { echo "Image did not mount at $MOUNT" >&2; exit 1; }

if ! osascript <<'APPLESCRIPT'
-- Found by trial on macOS 27: Finder keeps the icon view options only from the second time the window is shown
-- (the first showing writes its defaults over them), the picture only when given as an alias of its full path, and
-- everything only when the window is closed after a pause. So the layout is applied twice.
on layout()
  tell application "/System/Library/CoreServices/Finder.app"
    tell disk "FilmLab"
      open
      delay 1
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      -- A hidden-toolbar Finder title bar occupies 28 points above the 660 × 420 content.
      set bounds of container window to {120, 120, 780, 568}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 112
      set text size of viewOptions to 12
      set label position of viewOptions to bottom
      set shows item info of viewOptions to false
      set shows icon preview of viewOptions to false
      set background picture of viewOptions to ((POSIX file "/Volumes/FilmLab/.background/background.tiff") as alias)
      set position of item "FilmLab.app" of container window to {180, 215}
      set position of item "Applications" of container window to {480, 215}
      delay 2
      close
      delay 3
    end tell
  end tell
end layout
layout()
layout()
APPLESCRIPT
then
  echo "Warning: Finder layout could not be saved (check Automation permission); continuing with a plain DMG." >&2
fi
sync

# This Mac's Finder may show its tab bar in every window; the layout then records "ShowTabView" and the image would
# open with a tab bar (covering the foot of the background) for everyone. The value is one byte in the window's
# property list inside .DS_Store: flip it in place, changing nothing else.
python3 - "$MOUNT/.DS_Store" <<'PY' || echo "Warning: could not clear the tab bar setting" >&2
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, 'rb').read())
at = data.find(b'bwspblob')
if at < 0: sys.exit(0)
size = struct.unpack('>I', data[at + 8:at + 12])[0]
start = at + 12
plist = data[start:start + size]
if plist[:8] != b'bplist00': sys.exit(1)
offset_size, ref_size = plist[-26], plist[-25]
count, top, table = struct.unpack('>QQQ', plist[-24:])
def offset(i): return int.from_bytes(plist[table + i * offset_size:table + (i + 1) * offset_size], 'big')
def ref(at): return int.from_bytes(plist[at:at + ref_size], 'big')
root = offset(top)
if plist[root] >> 4 != 0xD or plist[root] & 15 == 15: sys.exit(1)
n = plist[root] & 15
keys = [ref(root + 1 + i * ref_size) for i in range(n)]
values = [ref(root + 1 + (n + i) * ref_size) for i in range(n)]
def text(i):
    o = offset(i); kind, length = plist[o] >> 4, plist[o] & 15
    return bytes(plist[o + 1:o + 1 + length]).decode('ascii') if kind == 5 and length < 15 else None
names = [text(k) for k in keys]
if 'ShowTabView' not in names: sys.exit(0)
value = values[names.index('ShowTabView')]
# The true object may be shared: only flip it when no other key uses it.
if values.count(value) == 1 and plist[offset(value)] == 0x09:
    data[start + offset(value)] = 0x08
    open(path, 'wb').write(data)
PY
sync

# Custom volume icons are optional: SetFile is supplied by Apple's developer tools.
SETFILE=$(command -v SetFile || true)
if [[ -n "$SETFILE" ]]; then
  ICON=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist" 2>/dev/null || true)
  [[ -z "$ICON" || "$ICON" == *.icns ]] || ICON="$ICON.icns"
  if [[ -n "$ICON" && -f "$APP/Contents/Resources/$ICON" ]]; then
    if cp "$APP/Contents/Resources/$ICON" "$MOUNT/.VolumeIcon.icns" 2>/dev/null; then
      "$SETFILE" -a C "$MOUNT" 2>/dev/null || true
    fi
  fi
fi
sync
hdiutil detach "$MOUNT"
MOUNTED=0
hdiutil convert "$WORK/FilmLab-rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$DEST"
echo "Created $DEST ($(du -h "$DEST" | awk '{print $1}'))"
