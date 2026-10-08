#!/usr/bin/env bash
#
# Turn the tablet's GNOME session into a demo kiosk: full-screen Firefox on
# the web app, screen blanking / sleep disabled. Run as the TABLET LOGIN USER
# (not sudo) inside the graphical session.
#
#   ./deploy/kiosk-setup.sh
#
set -euo pipefail

KIOSK_URL="${KIOSK_URL:-http://localhost/}"

echo ">> Disabling screen blank, dimming, and auto-suspend..."
gsettings set org.gnome.desktop.session idle-delay 0 || true
gsettings set org.gnome.settings-daemon.plugins.power idle-dim false || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' || true
gsettings set org.gnome.desktop.screensaver lock-enabled false || true

echo ">> Installing an autostart entry for full-screen Firefox..."
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/workload-kiosk.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Workload Selector Kiosk
Exec=firefox --kiosk ${KIOSK_URL}
X-GNOME-Autostart-enabled=true
EOF

echo
echo ">> Done. The kiosk launches on next login."
echo "   Test now without logging out:   firefox --kiosk ${KIOSK_URL}"
echo "   Exit kiosk Firefox any time with Alt+F4."
