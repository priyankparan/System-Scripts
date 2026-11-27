# System-Scripts

Transparent, zero-magic Arch Linux maintenance utilities designed to keep system updates fast, safe, and completely visible.

Every command executed is printed to the terminal (`$ <command>`) before running with full live output, and package ecosystems that are absent or unused (such as Snap, Flatpak, `rustup`, or `pipx`) are automatically skipped without clutter.

---

## Repository Structure

```text
System-Scripts/
├── README.md
├── LICENSE
└── Scripts/
    ├── update.sh    # Daily package updates, cache cleanup & health audit (sysupdate)
    └── sysedit.sh   # Dedicated Timeshift snapshots & SSD TRIM utility (sysedit)
```

---

## Installation

1. **Clone the repository and make the scripts executable:**
   ```bash
   git clone https://github.com/priyankparan/System-Scripts.git
   cd System-Scripts
   chmod +x Scripts/update.sh Scripts/sysedit.sh
   ```

2. **Symlink both scripts into `~/.local/bin`:**
   ```bash
   mkdir -p ~/.local/bin
   ln -sfn "$PWD/Scripts/update.sh" ~/.local/bin/sysupdate
   ln -sfn "$PWD/Scripts/sysedit.sh" ~/.local/bin/sysedit
   ```

3. **Ensure `~/.local/bin` is in your `PATH`** (if not already configured in your shell):
   - **Bash / Zsh**: `export PATH="$HOME/.local/bin:$PATH"`
   - **Fish**: `fish_add_path ~/.local/bin`

---

## Scripts

### 1. `sysupdate` (`Scripts/update.sh`)
Handles routine Arch Linux updates, cache pruning, and health diagnostics. Timeshift snapshots and SSD trimming are intentionally excluded so daily updates stay fast.

#### Usage & Options
```text
sysupdate [OPTIONS]
```

| Flag | Description |
| :--- | :--- |
| *(none)* | Full update: official + AUR packages, Flatpak/Snap/etc. (if present), cache cleanup, journal/coredump vacuum & health audit |
| `-q`, `--quick` | Skip systemd journal vacuum, old coredump pruning & font cache refresh |
| `-c`, `--clean-only` | Clean caches and run health checks only (skip all package updates) |
| `-p`, `--paccache-all` | Purge all cached pacman packages (`paccache -k 0`, otherwise keeps 1 version) |
| `-a`, `--aur <tool>` | Force a specific AUR helper (`paru` or `yay`) instead of auto-detecting |
| `-h`, `--help` | Show usage summary and exit |

#### What `sysupdate` Does
- **Pre-flight checks**: Verifies internet connectivity (offers clean-only fallback if offline), warns if laptop battery is discharging below `20%`, refreshes `sudo`, and cleans stale `/var/lib/pacman/db.lck` only if no package manager is running.
- **Official & AUR updates**: Updates `archlinux-keyring` and upgrades official + AUR packages via `paru` or `yay` (falling back to `pacman`), then removes orphaned dependencies (`pacman -Qtdq`).
- **Additional package managers (only if installed & non-empty)**:
  - **Flatpak**: Updates apps and removes unused user/system runtimes.
  - **Snap**: Runs `sudo snap refresh` (strictly omitted if `snap` is not installed or has 0 snaps).
  - **`rustup` / `pipx`**: Updates toolchains / CLI apps only if installed and populated.
- **Cache cleanup**: Prunes pacman & AUR caches (`paccache`, `paru -Sc` / `yay -Sc`), clears existing dev caches (`uv`, `pip`, `go`, `npm`, `cargo`, `arduino15/staging`, `yazi`), disposable editor/browser caches (`Cache_Data` / `cache2`), and thumbnails older than 14 days.
- **System maintenance** *(skipped with `-q`)*: Vacuums systemd/user journals (`50M` / `20M`, `1week`), deletes coredumps older than 7 days, and refreshes `fc-cache`.
- **Health audit**: Checks for unmerged `.pacnew`/`.pacsave` files, failed systemd units, broken symlinks in `~/.local/bin` & `~/.config`, and whether a kernel upgrade requires a reboot, then prints disk space recovered and sends a desktop notification (`notify-send`).

---

### 2. `sysedit` (`Scripts/sysedit.sh`)
Dedicated utility for heavy system maintenance actions separated from `sysupdate`.

#### Usage & Options
```text
sysedit [OPTIONS]
```

| Flag | Description |
| :--- | :--- |
| *(none)* | Opens an interactive action menu |
| `-s`, `--snapshot [msg]` | Create a Timeshift snapshot (with optional comment) |
| `-t`, `--trim` | Trim mounted SSD filesystems (`sudo fstrim -av`) |
| `-a`, `--all` | Create a Timeshift snapshot **and** run SSD TRIM |
| `-l`, `--list` | List existing Timeshift snapshots |
| `-e`, `--edit` | Open `update.sh` and `sysedit.sh` in `$EDITOR` |
| `-h`, `--help` | Show usage summary and exit |

---

## Safety: What Is NEVER Touched

Neither script touches:
- Personal directories (`~/Documents`, `~/Pictures`, `~/Downloads`, `~/Projects`, `~/Desktop`)
- Application configs, editor settings, or dotfiles
- Browser profiles, logins, cookies, bookmarks, or history
- Desktop Trash (`~/.local/share/Trash`) or cloud mounts
- GPU shader caches (e.g., Mesa / RADV shader caches)
- BIOS/UEFI firmware updates
- Existing Timeshift snapshots (never auto-deleted by `sysedit` or `sysupdate`)

---

## Requirements & Notes

- **OS**: Arch Linux (or Arch-based distributions with `pacman`).
- **Core tools**: `bash`, `sudo`, `pacman-contrib` (for `paccache`).
- **Optional tools**: `paru` or `yay`, `flatpak`, `timeshift`, `util-linux` (`fstrim`), `libnotify` (`notify-send`).
- **Non-interactive upgrades**: `sysupdate` passes `--noconfirm --skipreview` to `paru` (`--noconfirm --answerdiff None --answerclean None` for `yay`) so updates run unattended while streaming full output. If you prefer reviewing AUR `PKGBUILD` diffs or taking a snapshot first, run `sysedit -s` and/or `paru -Syu` manually, and use `sysupdate -c` for cleanup only.

---

## License & Disclaimer

Licensed under the [MIT License](LICENSE).

These scripts are provided **"as is"**, without warranty of any kind. The maintainers bear **no responsibility or liability** for any data loss, package breakage, or unintended system changes resulting from running or modifying these scripts — review the code and use at your own risk.
