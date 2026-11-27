#!/usr/bin/env bash
# ==============================================================================
# sysupdate — Transparent Arch Linux Update, Cleanup & Health Check
#
# What it DOES:
#   - Checks connectivity, battery (>=20%), sudo access, and stale pacman locks
#   - Updates official + AUR packages via paru or yay (fallback: pacman)
#   - Removes orphaned dependencies (pacman -Qtdq)
#   - Updates Flatpaks & prunes unused runtimes (only if Flatpak has apps)
#   - Updates Snaps, Rustup toolchains, and pipx apps (only if installed & active)
#   - Prunes package/AUR caches and existing developer/browser caches
#   - Vacuums systemd journals, old coredumps (>7d) & refreshes font cache
#   - Audits .pacnew files, failed systemd units, broken symlinks & kernel state
#   - Prints every command before executing it and streams full output live
#
# What it DOES NOT touch:
#   - Personal files (Documents, Pictures, Downloads, Projects, Desktop)
#   - App configs/profiles, browser logins, cookies, bookmarks, or history
#   - Desktop Trash, cloud mounts, GPU shader caches, or UEFI/BIOS firmware
#   - Timeshift snapshots or SSD TRIM (handled separately by `sysedit`)
# ==============================================================================
set -uo pipefail

# --- Terminal Styling ---
if [[ -t 1 ]]; then
    B="\033[1m" DIM="\033[2m"
    C="\033[38;5;117m" G="\033[38;5;114m" Y="\033[38;5;221m"
    R="\033[38;5;203m" M="\033[38;5;183m" GR="\033[38;5;244m" N="\033[0m"
else
    B="" DIM="" C="" G="" Y="" R="" M="" GR="" N=""
fi

QUICK=false
CLEAN_ONLY=false
PACCACHE_ALL=false
AUR_PREF=""

usage() {
    cat <<EOF
sysupdate — Transparent Arch Linux Update & Maintenance

Usage: sysupdate [OPTIONS]

Options:
  -q, --quick        Skip journals, coredumps & font cache rebuild
  -c, --clean-only   Clean caches and run health checks only (no updates)
  -p, --paccache-all Purge all cached pacman packages (paccache -k 0)
  -a, --aur <tool>   Prefer specific AUR helper (paru or yay)
  -h, --help         Show this help and exit

What it updates (only shown if installed & non-empty):
  - Official repos + AUR (paru / yay / pacman) + orphan removal
  - Flatpak apps & unused runtimes
  - Snap packages, Rustup toolchains, pipx apps

What it NEVER touches:
  - Personal folders, app configs, browser logins/bookmarks/cookies
  - Trash, cloud mounts, GPU shader caches, or BIOS/UEFI firmware
  - Timeshift snapshots or SSD TRIM (use \`sysedit -s\` / \`sysedit -t\`)
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quick)        QUICK=true ;;
        -c|--clean-only)   CLEAN_ONLY=true ;;
        -p|--paccache-all) PACCACHE_ALL=true ;;
        -a|--aur)
            [[ $# -lt 2 ]] && { echo -e "${R}Missing argument for $1${N}"; exit 1; }
            AUR_PREF="$2"; shift ;;
        -h|--help)         usage ;;
        *) echo -e "${R}Unknown option:${N} $1 (run --help)"; exit 1 ;;
    esac
    shift
done

# --- UI & Command Transparency Helpers ---
has()     { command -v "$1" &>/dev/null; }
has_dir_files() { [[ -d "$1" ]] && [[ -n "$(ls -A "$1" 2>/dev/null)" ]]; }

banner() {
    echo ""
    echo -e "${C}${B}╭────────────────────────────────────────────────────────────╮${N}"
    echo -e "${C}${B}│${N}  ${B}sysupdate${N}  ${GR}•  Transparent Arch Linux Maintenance${N}          ${C}${B}│${N}"
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
info() { echo -e "  ${M}•${N} $1"; }

# Print exact command before executing and stream live output (100% transparent)
run() {
    echo -e "  ${DIM}${C}\$ $*${N}"
    "$@"
}

run_or_warn() {
    echo -e "  ${DIM}${C}\$ $*${N}"
    "$@" || warn "Command exited with status $?: $*"
}

# Detect which package managers are actually active on this system
detect_aur_helper() {
    if [[ -n "$AUR_PREF" ]]; then
        if has "$AUR_PREF"; then
            echo "$AUR_PREF"
            return
        fi
        warn "Requested AUR helper '$AUR_PREF' not found; auto-detecting." >&2
    fi
    if has paru; then echo "paru"
    elif has yay; then echo "yay"
    else echo "pacman"
    fi
}

has_flatpaks() {
    has flatpak && [[ -n "$(flatpak list --columns=application 2>/dev/null)" ]]
}

has_snaps() {
    has snap && [[ -n "$(snap list 2>/dev/null | awk 'NR>1')" ]]
}

has_rustup_toolchains() {
    has rustup && [[ -n "$(rustup toolchain list 2>/dev/null | grep -v '^no installed')" ]]
}

has_pipx_packages() {
    has pipx && [[ -n "$(pipx list --short 2>/dev/null)" ]]
}

# --- Start ---
START_TIME=$(date +%s)
START_KB=$(df -Pk / | awk 'NR==2 {print $(NF-2)}')
START_FREE=$(df -Ph / | awk 'NR==2 {print $(NF-2)}')
PKG_TOOL=$(detect_aur_helper)

banner

# Build live transparency scope summary
ACTIVE_TARGETS=()
if [[ "$CLEAN_ONLY" == false ]]; then
    ACTIVE_TARGETS+=("pacman + $PKG_TOOL")
    has_flatpaks          && ACTIVE_TARGETS+=("flatpak")
    has_snaps             && ACTIVE_TARGETS+=("snap")
    has_rustup_toolchains && ACTIVE_TARGETS+=("rustup")
    has_pipx_packages     && ACTIVE_TARGETS+=("pipx")
fi
ACTIVE_TARGETS+=("caches")
[[ "$QUICK" == false ]] && ACTIVE_TARGETS+=("journals")
ACTIVE_TARGETS+=("health-audit")

echo -e "  ${B}Free space :${N} ${G}${START_FREE}${N}"
echo -e "  ${B}Mode       :${N} $([[ "$CLEAN_ONLY" == true ]] && echo "Clean-only" || ([[ "$QUICK" == true ]] && echo "Quick update" || echo "Full update & cleanup"))"
echo -e "  ${B}Will run   :${N} ${ACTIVE_TARGETS[*]}"
echo -e "  ${B}Untouched  :${N} Personal files, configs, browser logins/cookies, Trash, firmware, Timeshift, SSD TRIM"

# --- Pre-flight Checks ---
if [[ "$CLEAN_ONLY" == false ]]; then
    section "Pre-flight Checks"
    if ! run ping -q -c 1 -W 3 1.1.1.1; then
        warn "No internet connectivity to 1.1.1.1."
        read -r -p "  Switch to clean-only mode instead? [Y/n] " ans
        [[ "$ans" =~ ^[nN] ]] && exit 1
        CLEAN_ONLY=true
    else
        ok "Network reachable"
    fi
fi

if [[ -d /sys/class/power_supply/BAT0 ]]; then
    bat_stat=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo Unknown)
    bat_pct=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100)
    if [[ "$bat_stat" == "Discharging" && "$bat_pct" -lt 20 ]]; then
        warn "Battery is discharging at ${bat_pct}%."
        read -r -p "  Continue anyway? [y/N] " ans
        [[ ! "$ans" =~ ^[yY] ]] && exit 1
    fi
fi

section "Authentication"
run sudo -v || { echo -e "${R}Sudo authentication failed.${N}"; exit 1; }
( while true; do sudo -n true 2>/dev/null || exit; sleep 50; done ) &
SUDO_PID=$!
trap 'kill "$SUDO_PID" 2>/dev/null || true' EXIT INT TERM

# --- Package & App Updates ---
if [[ "$CLEAN_ONLY" == false ]]; then
    section "Official & AUR Packages ($PKG_TOOL)"

    if [[ -f /var/lib/pacman/db.lck ]]; then
        if pgrep -x "pacman|paru|yay" &>/dev/null; then
            echo -e "  ${R}Another package manager is already running. Exiting.${N}"
            exit 1
        fi
        run sudo rm -f /var/lib/pacman/db.lck
        ok "Cleared stale pacman lock"
    fi

    MAKEFLAGS="-j$(nproc 2>/dev/null || echo 4)"
    export MAKEFLAGS
    run_or_warn sudo pacman -Sy --needed --noconfirm archlinux-keyring

    case "$PKG_TOOL" in
        paru)   run_or_warn paru -Syu --noconfirm --skipreview ;;
        yay)    run_or_warn yay -Syu --noconfirm --answerdiff None --answerclean None ;;
        pacman) run_or_warn sudo pacman -Syu --noconfirm ;;
    esac

    # Remove orphaned dependencies if present
    while orphans=$(pacman -Qtdq 2>/dev/null) && [[ -n "$orphans" ]]; do
        readarray -t orphan_arr <<< "$orphans"
        run_or_warn sudo pacman -Rns --noconfirm "${orphan_arr[@]}" || break
    done

    # Flatpaks (only if flatpak has installed apps/runtimes)
    if has_flatpaks; then
        section "Flatpak Applications"
        run_or_warn flatpak update -y --noninteractive
        run_or_warn flatpak uninstall --unused -y --noninteractive
        run_or_warn sudo flatpak uninstall --unused -y --noninteractive
    fi

    # Snaps (strictly silent & skipped unless snap exists AND snaps are installed)
    if has_snaps; then
        section "Snap Packages"
        run_or_warn sudo snap refresh
    fi

    # Optional language toolchains (strictly silent unless installed & populated)
    if has_rustup_toolchains; then
        section "Rust Toolchains (rustup)"
        run_or_warn rustup update
    fi

    if has_pipx_packages; then
        section "Python CLI Apps (pipx)"
        run_or_warn pipx upgrade-all
    fi
fi

# --- Package & App Caches ---
section "Package & Build Caches"
keep=$([[ "$PACCACHE_ALL" == true ]] && echo 0 || echo 1)

if has paccache; then
    run_or_warn sudo paccache -r -k "$keep"
    run_or_warn sudo paccache -r -u -k 0
    [[ -d "$HOME/.cache/paru" ]] && run_or_warn paccache -r -k 1 -c "$HOME/.cache/paru"
    [[ -d "$HOME/.cache/yay"  ]] && run_or_warn paccache -r -k 1 -c "$HOME/.cache/yay"
fi

case "$PKG_TOOL" in
    paru)   run_or_warn paru -Sc --noconfirm ;;
    yay)    run_or_warn yay -Sc --noconfirm ;;
    pacman) run_or_warn sudo pacman -Sc --noconfirm ;;
esac

if [[ -d "$HOME/.cache/paru/clone" ]]; then
    run_or_warn find "$HOME/.cache/paru/clone" -type f \( -name "*.pkg.tar.*" -o -name "*.tar.*" -o -name "*.zip" \) -delete
fi
if [[ -d "$HOME/.cache/yay" ]]; then
    run_or_warn find "$HOME/.cache/yay" -type f \( -name "*.pkg.tar.*" -o -name "*.tar.*" -o -name "*.zip" \) -delete
fi
if [[ -d /var/cache/pacman/pkg ]] && find /var/cache/pacman/pkg -maxdepth 1 -name "download-*" -print -quit 2>/dev/null | grep -q .; then
    run_or_warn sudo rm -rf /var/cache/pacman/pkg/download-*
fi

# Developer & Browser Caches (only print & run what actually exists)
section "Developer & Browser Caches"
has uv  && has_dir_files "$HOME/.cache/uv" && run_or_warn uv cache clean
has pip && has_dir_files "$HOME/.cache/pip" && run_or_warn pip cache purge
has go  && has_dir_files "$HOME/.cache/go-build" && run_or_warn go clean -cache
has npm && has_dir_files "$HOME/.npm/_cacache" && run_or_warn npm cache clean --force
has ya  && has_dir_files "$HOME/.cache/yazi" && run_or_warn ya cache clear

CACHE_PATHS=(
    "$HOME/.cache/pip"
    "$HOME/.cache/go-build"
    "$HOME/.cargo/registry/cache"
    "$HOME/.cargo/registry/src"
    "$HOME/.cargo/git/checkouts"
    "$HOME/.arduino15/staging"
    "$HOME/.config/Code/Cache"
    "$HOME/.config/Code/CachedData"
    "$HOME/.config/Code/CachedExtensionVSIXs"
    "$HOME/.config/VSCodium/Cache"
    "$HOME/.config/VSCodium/CachedData"
    "$HOME/.config/VSCodium/CachedExtensionVSIXs"
    "$HOME/.cache/flatpak"
    "$HOME/.cache/io.github.CyberTimon.RapidRAW"
    "$HOME/.var/app/org.telegram.desktop/cache"
    "$HOME/.cache/BraveSoftware/Brave-Browser/Default/Cache/Cache_Data"
    "$HOME/.cache/BraveSoftware/Brave-Browser/Default/Code Cache"
    "$HOME/.cache/vivaldi/Default/Cache/Cache_Data"
    "$HOME/.cache/chromium/Default/Cache/Cache_Data"
    "$HOME/.cache/thumbnails/fail"
)

for dir in "${CACHE_PATHS[@]}"; do
    if has_dir_files "$dir"; then
        run_or_warn find "$dir" -mindepth 1 -delete
    fi
done

for glob_dir in "$HOME"/.var/app/app.zen_browser.zen/cache/zen/*/cache2 "$HOME"/.cache/mozilla/firefox/*/cache2; do
    if has_dir_files "$glob_dir"; then
        run_or_warn find "$glob_dir" -mindepth 1 -delete
    fi
done

if [[ -d "$HOME/.cache/thumbnails" ]]; then
    run_or_warn find "$HOME/.cache/thumbnails" -type f -mtime +14 -delete
fi

# --- System Maintenance ---
if [[ "$QUICK" == false ]]; then
    section "System Maintenance"
    has journalctl && run_or_warn sudo journalctl --vacuum-time=1week --vacuum-size=50M
    has journalctl && run_or_warn journalctl --user --vacuum-time=1week --vacuum-size=20M
    if has_dir_files /var/lib/systemd/coredump; then
        run_or_warn sudo find /var/lib/systemd/coredump -type f -mtime +7 -delete
    fi
    has fc-cache && run_or_warn fc-cache -r
fi

# --- Health Audits ---
section "System Health Audit"
echo -e "  ${DIM}${C}\$ find /etc -name '*.pacnew' -o -name '*.pacsave'${N}"
pacnews=$(find /etc -name "*.pacnew" -o -name "*.pacsave" 2>/dev/null || true)
[[ -n "$pacnews" ]] && warn "Unmerged .pacnew/.pacsave files:\n$pacnews" || ok "No .pacnew/.pacsave files"

echo -e "  ${DIM}${C}\$ systemctl --failed && systemctl --user --failed${N}"
failed_sys=$(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' || true)
failed_usr=$(systemctl --user --failed --no-legend 2>/dev/null | awk '{print $1}' || true)
[[ -n "$failed_sys$failed_usr" ]] && warn "Failed systemd units: $failed_sys $failed_usr" || ok "All systemd services healthy"

echo -e "  ${DIM}${C}\$ find ~/.local/bin ~/.config -xtype l${N}"
broken=$(find "$HOME/.local/bin" "$HOME/.config" -xtype l 2>/dev/null || true)
[[ -n "$broken" ]] && warn "Broken symlinks:\n$broken" || ok "No broken symlinks"

REBOOT_NEEDED=false
RUNNING_KERNEL=$(uname -r)
if [[ ! -d "/usr/lib/modules/$RUNNING_KERNEL" ]]; then
    warn "Kernel updated (running $RUNNING_KERNEL modules replaced) — reboot recommended"
    REBOOT_NEEDED=true
else
    ok "Running kernel $RUNNING_KERNEL matches installed modules"
fi

# --- Final Summary ---
ELAPSED=$(( $(date +%s) - START_TIME ))
END_KB=$(df -Pk / | awk 'NR==2 {print $(NF-2)}')
END_FREE=$(df -Ph / | awk 'NR==2 {print $(NF-2)}')
DIFF_MB=$(( (END_KB - START_KB) / 1024 ))
[[ $DIFF_MB -ge 0 ]] && DELTA="freed ${DIFF_MB} MB" || DELTA="used $(( -DIFF_MB )) MB"

echo ""
echo -e "${G}${B}╭────────────────────────────────────────────────────────────╮${N}"
echo -e "${G}${B}│${N}  ${B}Complete in ${ELAPSED}s${N}  •  Free space: ${B}${END_FREE}${N} (${DELTA})"
echo -e "${G}${B}╰────────────────────────────────────────────────────────────╯${N}"

if has notify-send; then
    urgency=$([[ "$REBOOT_NEEDED" == true ]] && echo critical || echo normal)
    msg="Finished in ${ELAPSED}s | Free: ${END_FREE} (${DELTA})"
    [[ "$REBOOT_NEEDED" == true ]] && msg="Reboot recommended. $msg"
    notify-send -u "$urgency" "sysupdate Complete" "$msg" 2>/dev/null || true
fi
