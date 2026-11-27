#!/usr/bin/env bash
# ==============================================================================
# sysedit — Dedicated Timeshift Snapshot, SSD TRIM & Script Maintenance Tool
#
# Separated from `sysupdate` so daily updates stay fast and snapshots/TRIM
# only run when you explicitly invoke `sysedit`.
#
# What it DOES (depending on flags):
#   -s, --snapshot  Create a Timeshift snapshot (prompts for optional comment)
#   -t, --trim      Trim mounted SSD filesystems via `sudo fstrim -av`
#   -a, --all       Run both Timeshift snapshot and SSD TRIM
#   -l, --list      List existing Timeshift snapshots
#   -e, --edit      Edit `update.sh` / `sysedit.sh` in $EDITOR
#
# What it DOES NOT touch:
#   - Never upgrades, removes, or modifies packages, caches, or personal files
#   - Never deletes old Timeshift snapshots automatically
# ==============================================================================
set -uo pipefail

if [[ -t 1 ]]; then
    B="\033[1m" DIM="\033[2m"
    C="\033[38;5;117m" G="\033[38;5;114m" Y="\033[38;5;221m"
    R="\033[38;5;203m" GR="\033[38;5;244m" N="\033[0m"
else
    B="" DIM="" C="" G="" Y="" R="" GR="" N=""
fi

DO_SNAPSHOT=false
DO_TRIM=false
DO_LIST=false
DO_EDIT=false
COMMENT="Manual sysedit snapshot"

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

usage() {
    cat <<EOF
sysedit — Dedicated Timeshift Snapshot, SSD TRIM & System Script Utility

Usage: sysedit [OPTIONS]

Options:
  -s, --snapshot [msg]  Create a Timeshift snapshot (optional comment)
  -t, --trim            Trim mounted SSDs (sudo fstrim -av)
  -a, --all             Create a Timeshift snapshot AND trim SSDs
  -l, --list            List existing Timeshift snapshots
  -e, --edit            Open update.sh and sysedit.sh in \$EDITOR
  -h, --help            Show this help and exit

Running \`sysedit\` with no flags opens an interactive menu.

What it NEVER touches:
  - Does not update or remove packages, caches, or personal files
  - Does not delete existing Timeshift snapshots
EOF
    exit 0
}

has() { command -v "$1" &>/dev/null; }

banner() {
    echo ""
    echo -e "${C}${B}╭────────────────────────────────────────────────────────────╮${N}"
    echo -e "${C}${B}│${N}  ${B}sysedit${N}  ${GR}•  Timeshift Snapshots & SSD TRIM${N}               ${C}${B}│${N}"
    echo -e "${C}${B}╰────────────────────────────────────────────────────────────╯${N}"
}

section() {
    local title="$1"
    local line="────────────────────────────────────────────────────────────"
    local pad_len=$(( 52 - ${#title} ))
    (( pad_len < 4 )) && pad_len=4
    echo ""
    echo -e "${C}${B}── ${title} ${GR}${line:0:$pad_len}${N}"
}

ok()   { echo -e "  ${G}✓${N} $1"; }
warn() { echo -e "  ${Y}!${N} $1"; }

run() {
    echo -e "  ${DIM}${C}\$ $*${N}"
    "$@"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--snapshot)
            DO_SNAPSHOT=true
            if [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
                COMMENT="$2"
                shift
            fi
            ;;
        -t|--trim) DO_TRIM=true ;;
        -a|--all)  DO_SNAPSHOT=true; DO_TRIM=true ;;
        -l|--list) DO_LIST=true ;;
        -e|--edit) DO_EDIT=true ;;
        -h|--help) usage ;;
        *) echo -e "${R}Unknown option:${N} $1 (run sysedit --help)"; exit 1 ;;
    esac
    shift
done

# Interactive chooser if invoked with no arguments
if [[ "$DO_SNAPSHOT" == false && "$DO_TRIM" == false && "$DO_LIST" == false && "$DO_EDIT" == false ]]; then
    banner
    echo -e "  ${B}1)${N} Timeshift snapshot   (${C}sysedit -s${N})"
    echo -e "  ${B}2)${N} SSD TRIM (fstrim)    (${C}sysedit -t${N})"
    echo -e "  ${B}3)${N} Snapshot + SSD TRIM  (${C}sysedit -a${N})"
    echo -e "  ${B}4)${N} List snapshots       (${C}sysedit -l${N})"
    echo -e "  ${B}5)${N} Edit system scripts  (${C}sysedit -e${N})"
    echo -e "  ${B}q)${N} Cancel"
    echo ""
    read -r -p "  Select action [1-5/q]: " choice
    case "$choice" in
        1) DO_SNAPSHOT=true ;;
        2) DO_TRIM=true ;;
        3) DO_SNAPSHOT=true; DO_TRIM=true ;;
        4) DO_LIST=true ;;
        5) DO_EDIT=true ;;
        *) exit 0 ;;
    esac
fi

if [[ "$DO_EDIT" == true ]]; then
    editor="${EDITOR:-nvim}"
    run "$editor" "$SCRIPT_DIR/update.sh" "$SCRIPT_DIR/sysedit.sh"
    exit 0
fi

banner

ACTIONS=()
[[ "$DO_LIST" == true ]]     && ACTIONS+=("timeshift --list")
[[ "$DO_SNAPSHOT" == true ]] && ACTIONS+=("timeshift --create")
[[ "$DO_TRIM" == true ]]     && ACTIONS+=("fstrim -av")

echo -e "  ${B}Will run  :${N} ${ACTIONS[*]}"
echo -e "  ${B}Untouched :${N} Packages, caches, personal files, existing snapshots"

if [[ "$DO_LIST" == true || "$DO_SNAPSHOT" == true || "$DO_TRIM" == true ]]; then
    section "Authentication"
    run sudo -v || { echo -e "${R}Sudo authentication failed.${N}"; exit 1; }
fi

if [[ "$DO_LIST" == true ]]; then
    section "Timeshift Snapshots"
    if has timeshift; then
        run sudo timeshift --list
    else
        warn "Timeshift is not installed."
    fi
fi

if [[ "$DO_SNAPSHOT" == true ]]; then
    section "Create Timeshift Snapshot"
    if has timeshift; then
        run sudo timeshift --create --comments "$COMMENT" --tags O || {
            echo -e "  ${R}Timeshift snapshot failed.${N}"
            exit 1
        }
        ok "Snapshot created"
    else
        echo -e "  ${R}Timeshift is not installed.${N}"
        exit 1
    fi
fi

if [[ "$DO_TRIM" == true ]]; then
    section "SSD TRIM (fstrim)"
    if has fstrim; then
        run sudo fstrim -av
        ok "SSD TRIM complete"
    else
        echo -e "  ${R}fstrim not found.${N}"
        exit 1
    fi
fi

echo ""
echo -e "${G}${B}╭────────────────────────────────────────────────────────────╮${N}"
echo -e "${G}${B}│${N}  ${B}sysedit complete${N}                                          ${G}${B}│${N}"
echo -e "${G}${B}╰────────────────────────────────────────────────────────────╯${N}"
