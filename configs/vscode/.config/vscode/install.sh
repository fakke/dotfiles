#!/usr/bin/env bash
# Bootstraps VS Code settings/extensions from this repo onto the current machine.
# Safe to re-run: symlinks and installs are idempotent.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) USER_DIR="$HOME/Library/Application Support/Code/User" ;;
    Linux)  USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

mkdir -p "$USER_DIR"

link() {
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then
        # Already a symlink (to us or something else) — just repoint it.
        ln -sf "$src" "$dst"
    elif [ -e "$dst" ]; then
        echo "Backing up existing $dst -> $dst.bak"
        mv "$dst" "$dst.bak"
        ln -s "$src" "$dst"
    else
        ln -s "$src" "$dst"
    fi
    echo "Linked $dst -> $src"
}

link "$REPO_DIR/settings.json" "$USER_DIR/settings.json"

# --- Font ---
if [ "$(uname -s)" = "Darwin" ]; then
    if command -v brew >/dev/null 2>&1; then
        if brew list --cask font-fira-code >/dev/null 2>&1; then
            echo "font-fira-code already installed"
        else
            brew install --cask font-fira-code
        fi
    else
        echo "Homebrew not found — install Fira Code manually: https://github.com/tonsky/FiraCode/releases" >&2
    fi
else
    echo "Non-macOS: install Fira Code manually (e.g. your distro's font package or https://github.com/tonsky/FiraCode/releases), then run 'fc-cache -f'." >&2
fi

# --- Extensions ---
if command -v code >/dev/null 2>&1; then
    while IFS= read -r ext; do
        [ -z "$ext" ] && continue
        echo "Installing extension: $ext"
        code --install-extension "$ext"
    done < "$REPO_DIR/extensions.txt"
else
    echo "'code' CLI not found on PATH — install extensions manually: $(tr '\n' ' ' < "$REPO_DIR/extensions.txt")" >&2
fi

# --- Custom CSS (workbench chrome font) ---
# Patches VS Code's own workbench.html directly (same mechanism as the
# be5invis.vscode-custom-css "Enable Custom CSS and JS" command, reimplemented
# here so it's non-interactive and safe to re-run after every VS Code update,
# which overwrites workbench.html with a clean copy).
find_workbench_html() {
    local base=""
    case "$(uname -s)" in
        Darwin)
            base="/Applications/Visual Studio Code.app/Contents/Resources/app/out/vs/code" ;;
        Linux)
            for c in /usr/share/code/resources/app/out/vs/code /opt/visual-studio-code/resources/app/out/vs/code; do
                [ -d "$c" ] && { base="$c"; break; }
            done
            ;;
    esac
    [ -z "$base" ] && return 1

    local dirs=("electron-browser/workbench" "electron-browser" "electron-sandbox/workbench" "electron-sandbox")
    local files=("workbench-dev.html" "workbench.esm.html" "workbench.html" "workbench-apc-extension.html")
    for d in "${dirs[@]}"; do
        for f in "${files[@]}"; do
            if [ -f "$base/$d/$f" ]; then echo "$base/$d/$f"; return 0; fi
        done
    done
    return 1
}

patch_custom_css() {
    local html_path="$1"
    [ -f "$html_path.orig-backup" ] || cp "$html_path" "$html_path.orig-backup"
    python3 "$REPO_DIR/patch_workbench.py" "$html_path" "$REPO_DIR/custom.css"
}

CSS_PATCHED=false
if HTML_PATH="$(find_workbench_html)"; then
    if patch_custom_css "$HTML_PATH" 2>/dev/null; then
        CSS_PATCHED=true
    fi
else
    echo "Could not locate VS Code's workbench.html — is VS Code installed?" >&2
fi

echo
echo "=== Next steps ==="
if [ "$CSS_PATCHED" = true ]; then
    echo "- Workbench chrome CSS patched. Restart VS Code to see it."
else
    echo "- Workbench chrome CSS NOT patched (permission denied writing into VS Code.app)."
    echo "  Either grant it once: System Settings > Privacy & Security > App Management >"
    echo "  enable for your terminal app, then re-run ./install.sh,"
    echo "  or in VS Code run Command Palette > 'Enable Custom CSS and JS' manually."
fi
