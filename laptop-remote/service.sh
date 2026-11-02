#!/bin/bash
# Run the web remote as a macOS login service, so it is always up and you never
# start it from a terminal again.
#
#   ./service.sh install     start it now and at every login
#   ./service.sh uninstall   stop it and remove it
#   ./service.sh status      is it running, and on what address
#   ./service.sh logs        follow its log
#   ./service.sh restart     re-sync and reload after editing tvctl.py or ui.html
#
# Why it does not run straight out of this folder: macOS refuses launchd agents
# access to ~/Documents (TCC), so the agent would die with "Operation not
# permitted". Install copies the three files it needs into ~/Library/Application
# Support/tvremote, which is not protected, and runs them from there. This
# folder stays the source of truth - edit here, then ./service.sh restart.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.tvremote"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
RUN_DIR="$HOME/Library/Application Support/tvremote"
LOG="$HOME/Library/Logs/tvremote.log"
DOMAIN="gui/$(id -u)"
PORT=8787

# launchd starts with a bare PATH, so adb and scrcpy have to be spelled out.
adb_dir="$(dirname "$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")")"
scrcpy_dir="$(dirname "$(command -v scrcpy || echo /opt/homebrew/bin/scrcpy)")"
SVC_PATH="$adb_dir:$scrcpy_dir:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

sync_files() {
  mkdir -p "$RUN_DIR"
  cp "$HERE/tvctl.py" "$HERE/ui.html" "$RUN_DIR/"
  cp "$HERE/tv" "$RUN_DIR/tv"
  chmod +x "$RUN_DIR/tv"
  # seed the known TV address so the service does not have to rescan on first run
  [ -f "$RUN_DIR/.tv-state.json" ] || cp "$HERE/.tv-state.json" "$RUN_DIR/" 2>/dev/null || true
}

write_plist() {
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>              <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$RUN_DIR/tv</string>
        <string>remote</string>
    </array>
    <key>WorkingDirectory</key>   <string>$RUN_DIR</string>
    <key>RunAtLoad</key>          <true/>
    <key>KeepAlive</key>          <true/>
    <key>ThrottleInterval</key>   <integer>10</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>           <string>$SVC_PATH</string>
    </dict>
    <key>StandardOutPath</key>    <string>$LOG</string>
    <key>StandardErrorPath</key>  <string>$LOG</string>
</dict>
</plist>
PLIST_EOF
}

boot_out() { launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true; }
boot_in()  { launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null \
               || launchctl load -w "$PLIST"; }

lan_ip() { ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true; }

addresses() {
  # The .local name is the one to bookmark: it follows this Mac even when DHCP
  # hands it a different IP, so it never goes stale the way an IP does.
  host="$(scutil --get LocalHostName 2>/dev/null | tr 'A-Z' 'a-z')"
  [ -n "$host" ] && echo "    phone / tablet   http://$host.local:$PORT     <- bookmark this one"
  ip="$(lan_ip)"; [ -n "$ip" ] && echo "    same, by IP      http://$ip:$PORT"
  echo "    on this Mac      http://localhost:$PORT"
}

case "${1:-status}" in
  install|restart)
    sync_files
    write_plist
    boot_out
    boot_in
    sleep 3
    if [ "$1" = "install" ]; then
      echo "Installed. The remote starts itself at login and restarts if it crashes."
    else
      echo "Re-synced and restarted."
    fi
    echo
    addresses
    echo
    echo "Log: $LOG"
    ;;
  uninstall)
    boot_out
    rm -f "$PLIST"
    rm -rf "$RUN_DIR"
    echo "Removed. Start it by hand again with: ./tv remote"
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      launchctl print "$DOMAIN/$LABEL" | grep -E "^[[:space:]]+(state|pid|last exit) " || true
    else
      echo "Not installed. Run: ./service.sh install"
    fi
    if curl -fsS -m 30 "http://localhost:$PORT/status" >/dev/null 2>&1; then
      echo "Answering: $(curl -fsS -m 30 "http://localhost:$PORT/status")"
      addresses
    else
      echo "Not answering on port $PORT - check the log: $LOG"
    fi
    ;;
  logs)
    touch "$LOG"; tail -f "$LOG"
    ;;
  *)
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
