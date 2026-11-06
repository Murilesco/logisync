#!/usr/bin/env bash
# LogiSync - Linux installer (BlueZ + systemd user service)
#   ./install-linux.sh            install / update
#   ./install-linux.sh uninstall
set -euo pipefail
DEST="$HOME/.local/share/logisync"
UNIT="$HOME/.config/systemd/user/logisync.service"
RULE=/etc/udev/rules.d/70-logisync.rules

if [[ "${1:-}" == uninstall ]]; then
    systemctl --user disable --now logisync.service 2>/dev/null || true
    rm -rf "$DEST" "$UNIT"
    sudo rm -f "$RULE"
    echo "LogiSync removed."; exit 0
fi

python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install --quiet --upgrade hidapi
cp -r "$(dirname "$0")/logisync" "$DEST/"

# Let the logged-in user talk HID++ to Logitech Bluetooth devices (bus 0005, vendor 046D)
echo 'KERNEL=="hidraw*", KERNELS=="0005:046D:*", TAG+="uaccess"' | sudo tee "$RULE" >/dev/null
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=hidraw

mkdir -p "$(dirname "$UNIT")"
cat > "$UNIT" <<EOF
[Unit]
Description=LogiSync - the mouse follows the keyboard Easy-Switch
After=bluetooth.target

[Service]
WorkingDirectory=$DEST
ExecStart=$DEST/venv/bin/python -m logisync
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now logisync.service
sleep 2
(cd "$DEST" && "$DEST/venv/bin/python" -m logisync --status) || true
echo "Installed. Config: ~/.config/logisync/config.json  Log: journalctl --user -u logisync -f"
