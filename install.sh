#!/usr/bin/env bash
# install.sh - install the Tandem Dock frontend for the current desktop.
#
# Auto-detects the desktop environment and installs the matching frontend:
# the Cinnamon applet (Cinnamon 6.4+) or the Plasma plasmoid (Plasma 6).
# Also warns when your regular bar sits on the bottom edge (where the
# dock's floating bar belongs) and offers to move it.
#
# Usage:
#   ./install.sh                 auto-detect the desktop environment
#   ./install.sh --with-panel    also add the dock's own bottom auto-hide
#                                panel (both desktops)
#   ./install.sh --cinnamon      force the Cinnamon applet
#   ./install.sh --plasma        force the Plasma plasmoid
#
# Works from a pipe as well, e.g.
#   curl -fsSL https://raw.githubusercontent.com/ciberjohn/tandem-dock/main/install.sh | bash
# In that mode the repo is fetched to a temp dir first; interactive
# prompts (panel move offers) are skipped and printed as instructions.
set -Eeo pipefail

INTERACTIVE=1
[ -t 0 ] || INTERACTIVE=0

FORCE=""
WITH_PANEL=0
for arg in "$@"; do
    case "$arg" in
        --with-panel) WITH_PANEL=1 ;;
        --cinnamon)   FORCE=cinnamon ;;
        --plasma)     FORCE=plasma ;;
        *) echo "unknown option: $arg" >&2; exit 1 ;;
    esac
done

# --- locate the repo: local clone, or download when piped from curl ------

REPO_DIR=""
SRC_self="${BASH_SOURCE[0]}"
if [ -n "$SRC_self" ] && [ -f "$(dirname "$SRC_self")/tandem-dock@ciberjohn/applet.js" ]; then
    REPO_DIR="$(cd "$(dirname "$SRC_self")" && pwd)"
else
    echo "installing from upstream (piped or out-of-repo run): fetching main"
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    curl -fsSL https://github.com/ciberjohn/tandem-dock/archive/refs/heads/main.tar.gz \
        | tar xz -C "$TMP_DIR" --strip-components=1
    REPO_DIR="$TMP_DIR"
fi

# --- desktop detection ----------------------------------------------------

DE="$FORCE"
if [ -z "$DE" ]; then
    case "$(echo "${XDG_CURRENT_DESKTOP:-}" | tr '[:lower:]' '[:upper:]')" in
        *CINNAMON*) DE=cinnamon ;;
        *KDE*)      DE=plasma ;;
    esac
fi
if [ -z "$DE" ]; then
    cat >&2 <<EOF
Could not detect the desktop (XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-empty}").
Tandem Dock supports Cinnamon and KDE Plasma. Force one:
  ./install.sh --cinnamon    Cinnamon applet (Cinnamon 6.4+)
  ./install.sh --plasma      Plasma plasmoid (Plasma 6)
EOF
    exit 1
fi

# ============================================================ Cinnamon ====

cinnamon_install() {
    local UUID="tandem-dock@ciberjohn"
    local APPLETS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cinnamon/applets"
    local SRC="${REPO_DIR}/${UUID}"

    [ -f "${SRC}/applet.js" ] || { echo "Cannot find ${SRC}" >&2; exit 1; }

    mkdir -p "${APPLETS_DIR}"
    rm -rf "${APPLETS_DIR}/${UUID}"
    cp -r "${SRC}" "${APPLETS_DIR}/"
    echo "installed ${UUID} -> ${APPLETS_DIR}/${UUID}"
}

# Bottom panels that are NOT auto-hide are treated as your regular bar:
# the dock's floating bar created by --with-panel sets auto-hide true.
# Prints the ids of such panels, one per line.
cinnamon_regular_bottom_ids() {
    python3 - <<'EOF'
import ast, subprocess
panels = ast.literal_eval(subprocess.check_output(
    ["gsettings", "get", "org.cinnamon", "panels-enabled"]).decode())
autohide = ast.literal_eval(subprocess.check_output(
    ["gsettings", "get", "org.cinnamon", "panels-autohide"]).decode())
hidden = {e.split(":")[0]: e.split(":", 1)[1] for e in autohide}
for entry in panels:
    pid, _height, pos = entry.split(":")
    if pos == "bottom" and hidden.get(pid, "false").lower() != "true":
        print(pid)
EOF
}

# $1 = target edge (top|left|right); remaining args = panel ids to move.
cinnamon_move_panels() {
    local target="$1"; shift
    python3 - "$target" "$@" <<'EOF'
import ast, subprocess, sys
target, ids = sys.argv[1], set(sys.argv[2:])
panels = ast.literal_eval(subprocess.check_output(
    ["gsettings", "get", "org.cinnamon", "panels-enabled"]).decode())
moved = []
for i, entry in enumerate(panels):
    pid = entry.split(":")[0]
    if entry.split(":")[-1] == "bottom" and pid in ids:
        moved.append(entry)
        panels[i] = f"{entry.rsplit(':', 1)[0]}:{target}"
if not moved:
    raise SystemExit("no matching bottom panel found")
subprocess.check_call(
    ["gsettings", "set", "org.cinnamon", "panels-enabled", repr(panels)])
print("moved panel(s) " + ", ".join(moved) + f" to the {target} edge")
EOF
}

cinnamon_add_dock_panel() {
    python3 - <<'EOF'
import ast, subprocess

def get(key):
    return ast.literal_eval(subprocess.check_output(
        ["gsettings", "get", "org.cinnamon", key]).decode())

panels = get("panels-enabled")           # e.g. ['1:0:top']
enabled = get("enabled-applets")         # e.g. ['panel1:left:0:uuid:inst']
autohide = get("panels-autohide")        # e.g. ['1:false']
height = get("panels-height")            # e.g. ['1:30']

ids = {int(p.split(":")[0]) for p in panels}
new_id = max(ids, default=0) + 1

panels.append(f"{new_id}:0:bottom")
autohide.append(f"{new_id}:true")
height.append(f"{new_id}:46")

# The trailing number in each enabled-applets entry is a globally unique
# applet instance id (it also names the applet's config file). Reusing an
# existing id breaks applet loading.
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
        ["gsettings", "set", "org.cinnamon", key, repr(val)])
print(f"added bottom panel {new_id} with tandem-dock in its center zone")
EOF
}

# ============================================================== Plasma ====

plasma_install() {
    command -v kpackagetool6 >/dev/null 2>&1 || {
        echo "kpackagetool6 not found - install it first" >&2
        echo "(sudo apt install kpackagetool6)" >&2
        exit 1
    }
    local PKG_DIR="${REPO_DIR}/tandem-dock-plasma"
    [ -f "${PKG_DIR}/metadata.json" ] || { echo "Cannot find ${PKG_DIR}" >&2; exit 1; }
    if kpackagetool6 --type Plasma/Applet --list 2>/dev/null \
            | grep -q "com.ciberjohn.tandemdock"; then
        kpackagetool6 --type Plasma/Applet --upgrade "${PKG_DIR}"
    else
        kpackagetool6 --type Plasma/Applet --install "${PKG_DIR}"
    fi
    echo "installed plasmoid com.ciberjohn.tandemdock"
    echo "add it to a bar: right-click the bar -> Add Widgets... -> Tandem Dock"
}

# Plasma shell scripting via D-Bus (qdbus variant or gdbus).
plasma_eval_script() {
    local script="$1" tool
    for tool in qdbus6 qdbus-qt6 qdbus; do
        if command -v "$tool" >/dev/null 2>&1; then
            "$tool" org.kde.PlasmaShell /Plasma org.kde.PlasmaShell.evaluateScript "$script"
            return $?
        fi
    done
    if command -v gdbus >/dev/null 2>&1; then
        gdbus call --session --dest org.kde.PlasmaShell --object-path /Plasma \
            --method org.kde.PlasmaShell.evaluateScript "$script"
        return $?
    fi
    return 1
}

# Panel containments sit on the BOTTOM edge (location=4) in
# plasma-org.kde.plasma.desktop-appletsrc. Prints their ids, one per line.
# NOTE: the file uses bracketed INI ([Containments][2]) which Python's
# configparser cannot parse - hence the minimal hand parser.
plasma_regular_bottom_ids() {
    python3 - <<'EOF'
import os, re
path = os.path.expanduser(
    "~/.config/plasma-org.kde.plasma.desktop-appletsrc")
if not os.path.exists(path):
    raise SystemExit
sections = {}
section = None
with open(path, encoding="utf-8") as fh:
    for line in fh:
        s = line.strip()
        if not s or s[0] in "#;":
            continue
        if s.startswith("[") and s.endswith("]"):
            section = s[1:-1]
            sections[section] = {}
            continue
        if section is None or "=" not in s:
            continue
        key, val = s.split("=", 1)
        sections[section][key] = val
for name, kv in sections.items():
    m = re.fullmatch(r"Containments\]\[(\d+)", name)
    if not m:
        continue
    if kv.get("plugin", "") == "org.kde.panel" \
            and kv.get("location", "") == "4":
        print(m.group(1))
EOF
}

# $1 = target edge (topEdge|leftEdge|rightEdge); remaining args = panel ids.
# Only the dock's own auto-hide bar can safely live at the bottom edge, so
# only the given regular-bar ids are moved.
plasma_move_panels() {
    local target="$1"; shift
    local ids_js="[$(IFS=,; echo "$*")]"
    plasma_eval_script "for (var i = 0; i < panels().length; i++) {
    var p = panels()[i];
    if (p.location == 'bottomEdge' && ${ids_js}.indexOf(p.id) != -1) {
        p.location = '${target}';
    }
}"
}

plasma_add_dock_panel() {
    plasma_eval_script "var p = new Panel('org.kde.panel');
p.location = 'bottomEdge';
p.height = 46;
p.hiding = 'autohide';
p.addWidget('com.ciberjohn.tandemdock');"
}

# ============================================= bottom-bar warning/move ===

# $1 = desktop key (cinnamon|plasma); $2 = newline-separated regular
# bottom-bar ids, non-empty to trigger.
warn_bottom_bar() {
    local de_key="$1"
    local ids="$2"

    [ -z "$ids" ] && return 0
    if [ -z "$(printf '%s' "$ids" | tr -d '[:space:]')" ]; then
        return 0
    fi

    echo ""
    echo "NOTE: your regular bar is already on the BOTTOM edge."
    echo "The dock's floating bar belongs there (per install), so they would stack."
    if [ "$INTERACTIVE" != "1" ]; then
        echo "Move it first - see 'Moving your regular bar' in the README."
        return 0
    fi

    local reply
    read -r -p "Move it to the [T]op, [L]eft, [R]ight edge, or [K]eep both? (t/l/r/K): " reply
    local target_c target_p
    case "${reply:-k}" in
        t|T) target_c=top;      target_p=topEdge ;;
        l|L) target_c=left;     target_p=leftEdge ;;
        r|R) target_c=right;    target_p=rightEdge ;;
        *)   echo "keeping both bars on the bottom edge"; return 0 ;;
    esac
    # shellcheck disable=SC2086
    case "$de_key" in
        cinnamon) cinnamon_move_panels "$target_c" $ids ;;
        plasma)   plasma_move_panels "$target_p" $ids ;;
    esac
}

# ========================================================== proceed =======

echo "Tandem Dock installer - detected desktop: ${DE}"

if [ "$DE" = "cinnamon" ]; then
    warn_bottom_bar cinnamon "$(cinnamon_regular_bottom_ids)"
    cinnamon_install
    if [ "$WITH_PANEL" = "1" ]; then
        cinnamon_add_dock_panel
        echo "restart Cinnamon (or log out/in) if the panel does not appear"
    else
        echo "to use the dock floating: bottom auto-hide panel, Tandem Dock centered"
    fi
else
    warn_bottom_bar plasma "$(plasma_regular_bottom_ids 2>/dev/null)"
    plasma_install
    if [ "$WITH_PANEL" = "1" ]; then
        if plasma_add_dock_panel; then
            echo "added a bottom auto-hide panel with the dock widget"
        else
            echo "could not script a new panel - add it by hand:"
            echo "  right-click the bar -> Add Panel, then add Tandem Dock"
        fi
    fi
fi
