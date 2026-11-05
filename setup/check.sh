#!/usr/bin/env bash
set -eo pipefail

failed=0
need() {
    if ! command -v "$1" >/dev/null; then
        printf 'Missing command: %s\n' "$1" >&2
        failed=1
    fi
}

for package in "$@"; do
    case $package in
        fish)
            for tool in fish fzf lsd direnv git nvim starship; do need "$tool"; done
            if [[ $(uname -s) == Linux ]]; then need batcat; else need bat; fi
            if command -v fzf >/dev/null; then
                help=$(fzf --help)
                if [[ $help != *--fish* ]]; then
                    echo 'fzf needs --fish support (0.48 or newer). Upgrade fzf.' >&2
                    failed=1
                fi
            fi
            ;;
        starship) need starship ;;
        tmux)
            for tool in tmux fzf git ssh; do need "$tool"; done
            if command -v tmux >/dev/null; then
                version=$(tmux -V)
                if [[ ! $version =~ tmux\ ([0-9]+)\.([0-9]+) ]] ||
                   (( BASH_REMATCH[1] < 3 || (BASH_REMATCH[1] == 3 && BASH_REMATCH[2] < 2) )); then
                    echo 'tmux 3.2 or newer is required for popup windows.' >&2
                    failed=1
                fi
            fi
            ;;
        kitty)
            need kitty
            ;;
        vscode)
            need code
            need python3
            ;;
        nvim)
            for tool in nvim git rg fish tmux curl unzip tar; do need "$tool"; done
            if [[ $(uname -s) == Linux ]]; then need fdfind; else need fd; fi
            if command -v nvim >/dev/null; then
                if ! nvim --clean --headless '+lua if vim.fn.has("nvim-0.12") == 0 then vim.cmd("cquit") end' +qa; then
                    echo 'Neovim 0.12+ is required by the current nvim-treesitter plugin.' >&2
                    failed=1
                fi
            fi
            if command -v tree-sitter >/dev/null; then
                version=$(tree-sitter --version)
                if [[ ! $version =~ tree-sitter\ ([0-9]+)\.([0-9]+)\.([0-9]+) ]] ||
                   (( BASH_REMATCH[1] == 0 && (BASH_REMATCH[2] < 26 || (BASH_REMATCH[2] == 26 && BASH_REMATCH[3] < 1)) )); then
                    echo 'tree-sitter CLI 0.26.1+ is required by the current nvim-treesitter plugin.' >&2
                    failed=1
                fi
            fi
            ;;
    esac
done
exit "$failed"
