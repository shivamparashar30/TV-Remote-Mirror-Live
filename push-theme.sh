#!/usr/bin/env bash
# Push a theme folder (config.json + optional wallpaper.jpg) to the launcher on the TV.
# Does what cleanyourtv's tools/theme.sh does, but with plain adb instead of its venv.
#   ./push-theme.sh my-theme      apply
#   ./push-theme.sh --reset       back to the built-in look
set -uo pipefail
T="${TV_HOST:-192.168.0.115}:5555"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
PKG=com.gathin.tvhome
DIR=/sdcard/Android/data/$PKG/files
URI=content://$PKG.theme
TMP=/data/local/tmp/cyt-theme
REV=$(python3 -c 'import uuid;print(uuid.uuid4().hex)')

push_one() {           # push_one <local file> <name on tv>
  local src="$1" name="$2"
  "$ADB" -s "$T" push "$src" "$TMP-$name" >/dev/null 2>&1 || { echo "  push failed: $name"; return 1; }
  "$ADB" -s "$T" shell "rm -f $DIR/$name 2>/dev/null; \
    { o=\$(content write --uri $URI/$name < $TMP-$name 2>&1) && case \"\$o\" in *'Unsupported operation'*) false;; esac; } \
    || cp $TMP-$name $DIR/$name 2>/dev/null; rm -f $TMP-$name" >/dev/null 2>&1
  echo "  pushed $name"
}

"$ADB" -s "$T" shell "mkdir -p $DIR" >/dev/null 2>&1

if [ "${1:-}" = "--reset" ]; then
  echo "Removing the theme (back to the built-in look)"
  "$ADB" -s "$T" shell "rm -f $DIR/config.json $DIR/wallpaper.jpg 2>/dev/null; \
     content delete --uri $URI/config.json 2>/dev/null; \
     content delete --uri $URI/wallpaper.jpg 2>/dev/null" >/dev/null 2>&1
else
  THEME="${1:?usage: push-theme.sh <folder> | --reset}"
  [ -f "$THEME/config.json" ] || { echo "no config.json in $THEME"; exit 1; }
  echo "Pushing $THEME"
  push_one "$THEME/config.json" config.json
  [ -f "$THEME/wallpaper.jpg" ] && push_one "$THEME/wallpaper.jpg" wallpaper.jpg
fi

# a changed revision is what makes the launcher re-read the theme
printf '%s' "$REV" > /tmp/cyt-rev && push_one /tmp/cyt-rev theme_revision && rm -f /tmp/cyt-rev

echo "Restarting Home"
"$ADB" -s "$T" shell "am force-stop $PKG" >/dev/null 2>&1
sleep 1
"$ADB" -s "$T" shell "input keyevent 3" >/dev/null 2>&1
sleep 4
echo "On screen: $("$ADB" -s "$T" shell 'dumpsys activity activities | grep -m1 mResumedActivity' 2>/dev/null | tr -d '\r' | grep -oE '[a-z0-9.]+/[A-Za-z0-9._]+')"
