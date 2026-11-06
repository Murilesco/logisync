#!/usr/bin/env bash
# LogiSync - macOS installer (launchd agent)
#   ./install-macos.sh            install / update
#   ./install-macos.sh uninstall
# macOS asks for "Input Monitoring" permission for the Python binary on first run
# (System Settings > Privacy & Security > Input Monitoring).
set -euo pipefail
DEST="$HOME/Library/Application Support/LogiSync"
PLIST="$HOME/Library/LaunchAgents/io.github.logisync.plist"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
if [[ "${1:-}" == uninstall ]]; then
    rm -rf "$DEST/venv" "$DEST/logisync" "$PLIST"
    echo "LogiSync removed."; exit 0
fi

mkdir -p "$DEST"
python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install --quiet --upgrade hidapi
cp -r "$(dirname "$0")/logisync" "$DEST/"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>io.github.logisync</string>
  <key>ProgramArguments</key><array>
    <string>$DEST/venv/bin/python</string><string>-m</string><string>logisync</string>
  </array>
  <key>WorkingDirectory</key><string>$DEST</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2
(cd "$DEST" && "$DEST/venv/bin/python" -m logisync --status) || true
echo "Installed. Config/log: $DEST"
