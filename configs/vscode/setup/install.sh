#!/usr/bin/env bash
set -eo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v code >/dev/null || { echo 'VS Code CLI is required to check extensions.' >&2; exit 1; }
failed=0
case $(uname -s) in
    Darwin) user_dir="$HOME/Library/Application Support/Code/User" ;;
    Linux) user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User" ;;
esac
target="$user_dir/settings.json"
settings="$root/.config/vscode/settings.json"
if [[ ! $target -ef $settings ]]; then
    if [[ -e $target || -L $target ]]; then
        echo "Conflicting VS Code settings: $target. Back it up and remove it before rerunning." >&2
        exit 1
    elif [[ $1 == install ]]; then
        mkdir -p "$user_dir"
        ln -s "$settings" "$target"
    else
        echo "Missing VS Code settings link: $target" >&2
        failed=1
    fi
fi
installed=$(code --list-extensions)
while IFS= read -r extension || [[ -n $extension ]]; do
    [[ -n $extension ]] || continue
    if ! grep -Fxiq "$extension" <<< "$installed"; then
        if [[ $1 == install ]]; then
            code --install-extension "$extension"
        else
            echo "Missing VS Code extension: $extension" >&2
            failed=1
        fi
    fi
done < "$root/.config/vscode/extensions.txt"
exit "$failed"
