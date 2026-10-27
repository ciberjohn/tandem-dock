#!/usr/bin/env bash
# install.sh - install the Tandem Dock applet for the current user.
#
# Copies the applet to ~/.local/share/cinnamon/applets/ and, if requested,
# adds a bottom panel with the dock in its center zone (see --with-panel).
#
# Usage:
#   install.sh                 install / update the applet files
#   install.sh --with-panel    also create a bottom panel (auto-hide,
#                              46px) and add the dock to its center zone
set -Eeo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UUID="tandem-dock@ciberjohn"
APPLETS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets"
SRC="${REPO_DIR}/${UUID}"

if [ ! -f "${SRC}/applet.js" ]; then
    echo "Cannot find ${SRC} - run from the repo root." >&2
    exit 1
fi

mkdir -p "${APPLETS_DIR}"
rm -rf "${APPLETS_DIR}/${UUID}"
cp -r "${SRC}" "${APPLETS_DIR}/"
echo "installed ${UUID} -> ${APPLETS_DIR}/${UUID}"

if [ "${1:-}" = "--with-panel" ]; then
    # Pick an unused panel id.
    PANELS=$(gsettings get org.cinnamon panels-enabled)
    echo "current panels: ${PANELS}"
    python3 - <<'EOF'
import json, subprocess, sys

def get(key):
    return json.loads(subprocess.check_output(
        ["gsettings", "get", "org.cinnamon", key]).decode())

panels = get("panels-enabled")           # e.g. ['1:0:top']
enabled = get("enabled-applets")          # e.g. ['panel1:left:0:uuid:inst']
autohide = get("panels-autohide")         # e.g. ['1:false']
height = get("panels-height")             # e.g. ['1:30']

ids = {int(p.split(":")[0]) for p in panels}
new_id = max(ids, default=0) + 1

panels.append(f"{new_id}:0:bottom")
autohide.append(f"{new_id}:true")
height.append(f"{new_id}:46")

# The trailing number in each enabled-applets entry is a globally unique
# applet instance id (it also names the applet's config file). Pick the
# next free one; reusing an existing id breaks applet loading.
inst = 1
used = {int(e.split(":")[-1]) for e in enabled}
while inst in used:
    inst += 1
enabled.append(f"panel{new_id}:center:0:tandem-dock@ciberjohn:{inst}")

for key, val in [
    ("panels-enabled", panels),
    ("panels-autohide", autohide),
    ("panels-height", height),
    ("enabled-applets", enabled),
]:
    subprocess.check_call(
        ["gsettings", "set", "org.cinnamon", key,
         json.dumps(val).replace("'", "'")])
print(f"added bottom panel {new_id} with tandem-dock in its center zone")
EOF
    echo "restart Cinnamon (or log out/in) if the panel does not appear"
fi
