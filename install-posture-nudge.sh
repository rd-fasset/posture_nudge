#!/bin/bash
# Posture Nudge — reminds you to switch between sitting and standing
# after every 25 minutes of ACTIVE time at your Mac.
# - Only counts minutes where you've touched the keyboard/mouse recently
# - Walking away for 5+ minutes resets the timer (that counts as a break)
# - Runs quietly in the background and starts automatically at login
#
# Install:   bash install-posture-nudge.sh
# Uninstall: bash install-posture-nudge.sh --uninstall

set -e
LABEL="com.rikesh.posture-nudge"
APP_DIR="$HOME/.posture-nudge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "$1" = "--uninstall" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  rm -rf "$APP_DIR"
  echo "Posture Nudge removed."
  exit 0
fi

mkdir -p "$APP_DIR" "$HOME/Library/LaunchAgents"

# ---------- the background agent ----------
cat > "$APP_DIR/nudge.sh" <<'SCRIPT'
#!/bin/bash
INTERVAL_MIN=25      # active minutes before a nudge
AWAY_RESET_SEC=300   # 5 min idle = you took a break, reset the timer
ACTIVE_SEC=120       # input within last 2 min = this minute counts as active
SNOOZE_MIN=5
STATE="$HOME/.posture-nudge/position"   # "sitting" or "standing"

[ -f "$STATE" ] || echo "sitting" > "$STATE"
active=0

idle_seconds() {
  ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'
}

while true; do
  sleep 60
  idle=$(idle_seconds)
  idle=${idle:-0}

  if [ "$idle" -ge "$AWAY_RESET_SEC" ]; then
    active=0
    continue
  fi
  [ "$idle" -lt "$ACTIVE_SEC" ] && active=$((active + 1))

  if [ "$active" -ge "$INTERVAL_MIN" ]; then
    pos=$(cat "$STATE")
    if [ "$pos" = "sitting" ]; then
      next="standing"; msg="You've been sitting for $INTERVAL_MIN minutes. Time to STAND UP 🧍"
    else
      next="sitting"; msg="You've been standing for $INTERVAL_MIN minutes. Time to SIT DOWN 🪑"
    fi

    afplay /System/Library/Sounds/Glass.aiff &
    result=$(osascript -e "display dialog \"$msg\" with title \"Posture Nudge\" buttons {\"Skip\", \"Snooze $SNOOZE_MIN min\", \"Switched ✓\"} default button \"Switched ✓\" giving up after 300" 2>/dev/null)

    case "$result" in
      *"Switched"*) echo "$next" > "$STATE"; active=0 ;;
      *"Snooze"*)   active=$((INTERVAL_MIN - SNOOZE_MIN)) ;;
      *)            active=0 ;;   # Skip, or dialog timed out
    esac
    echo "$(date '+%F %T') nudge: $pos -> ${result:-no response}" >> "$HOME/.posture-nudge/log.txt"
  fi
done
SCRIPT
chmod +x "$APP_DIR/nudge.sh"

# ---------- launchd: start at login, keep running ----------
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$APP_DIR/nudge.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$APP_DIR/error.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "✅ Posture Nudge is running."
echo "   You'll get a pop-up after every 25 active minutes (starting position: sitting)."
echo "   Edit $APP_DIR/nudge.sh to change timings, then re-run this installer."
echo "   Uninstall: bash $0 --uninstall"
