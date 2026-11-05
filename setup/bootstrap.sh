#!/usr/bin/env bash

if [[ $manager == apt ]]; then
    command -v apt-get >/dev/null || { echo 'apt-get is missing; this installer requires Ubuntu with APT.' >&2; exit 1; }
fi

if [[ $manager == brew ]] && { [[ ${#linked[@]} -gt 0 ]] || ! command -v stow >/dev/null; }; then
    if ! command -v brew >/dev/null; then
        for executable in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [[ -x $executable ]]; then
                environment=$("$executable" shellenv)
                eval "$environment"
                break
            fi
        done
    fi
    if ! command -v brew >/dev/null; then
        if [[ $mode == check ]]; then
            echo 'Missing Homebrew. Run ./install.sh to install it.' >&2
            exit 1
        fi
        curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$work/homebrew.sh"
        /bin/bash "$work/homebrew.sh"
        for executable in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [[ -x $executable ]]; then
                environment=$("$executable" shellenv)
                eval "$environment"
                break
            fi
        done
        command -v brew >/dev/null || { echo 'Homebrew installation did not provide brew.' >&2; exit 1; }
        echo 'Installed Homebrew.'
    else
        echo 'Homebrew already available.'
    fi
fi

if ! command -v stow >/dev/null; then
    if [[ $mode == check ]]; then
        echo 'Missing Stow. Run ./install.sh to install it.' >&2
        exit 1
    fi
    if [[ $manager == brew ]]; then
        brew install stow
    else
        elevate=()
        [[ $EUID -eq 0 ]] || elevate=(sudo)
        "${elevate[@]}" apt-get update
        "${elevate[@]}" apt-get install -y stow
    fi
    command -v stow >/dev/null || { echo 'Stow installation did not provide stow.' >&2; exit 1; }
    echo 'Installed Stow.'
else
    echo 'Stow already available.'
fi
