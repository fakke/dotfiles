#!/usr/bin/env bash
set -eo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
mode=install
if [[ $# -eq 1 && $1 == --check ]]; then
    mode=check
elif [[ $# -ne 0 ]]; then
    echo 'Usage: ./install.sh [--check]' >&2
    exit 2
fi

command -v git >/dev/null || { echo 'Git is required to inspect the dotfiles checkout.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
case $(uname -s) in
    Darwin) manager=brew ;;
    Linux)
        if [[ ! -r /etc/os-release ]]; then
            echo 'Cannot identify this Linux distribution.' >&2
            exit 1
        fi
        . /etc/os-release
        if [[ $ID != ubuntu ]]; then
            echo 'Supported platforms: macOS and Ubuntu.' >&2
            exit 1
        fi
        manager=apt
        ;;
    *) echo 'Supported platforms: macOS and Ubuntu.' >&2; exit 1 ;;
esac

git -C "$root" ls-files --recurse-submodules -z > "$work/files"
available=()
linked=()
partial=false
for directory in "$root/configs"/*/; do
    [[ -d $directory.config ]] || continue
    package=$(basename "$directory")
    available+=("$package")
    total=0
    matches=0
    while IFS= read -r -d '' file; do
        [[ $file == "configs/$package/.config/"* ]] || continue
        case ${file##*/} in .gitignore|.DS_Store) continue ;; esac
        target="$HOME/${file#"configs/$package/"}"
        total=$((total + 1))
        if [[ -L $target && $target -ef "$root/$file" ]]; then
            matches=$((matches + 1))
        fi
    done < "$work/files"
    if [[ $matches -eq 0 ]]; then
        continue
    elif [[ $matches -ne $total ]]; then
        printf 'Partially linked: %s (%s/%s files). Run stow %s from the repo, then ./install.sh.\n' "$package" "$matches" "$total" "$package" >&2
        partial=true
    else
        linked+=("$package")
    fi
done
[[ $partial == false ]] || exit 1

stow_command=$(command -v stow) || stow_command=
source "$root/setup/bootstrap.sh"
if [[ -n $stow_command ]]; then
    stow_command=stow
else
    stow_command=$(command -v stow)
fi

if [[ ${#linked[@]} -eq 0 ]]; then
    echo 'No linked configs found. No config dependencies installed.'
    if [[ ${#available[@]} -gt 0 ]]; then
        echo 'Choose configs from this example (run from the repo):'
        printf '  cd %q\n' "$root"
        if [[ -f $root/.gitmodules && ! -e $root/configs/nvim/.config/nvim/.git ]]; then
            echo '  git submodule update --init -- configs/nvim/.config/nvim'
        fi
        printf '  %s --simulate %s\n' "$stow_command" "${available[*]}"
        printf '  %s %s && ./install.sh\n' "$stow_command" "${available[*]}"
        echo 'The first Stow command previews; the second links and installs dependencies.'
    fi
    [[ $mode == install ]] && exit 0 || exit 1
fi
printf 'Stowed configs: %s\n' "${linked[*]}"

: > "$work/packages"
for package in "${linked[@]}"; do
    list="$root/configs/$package/setup/packages.$manager"
    if [[ ! -f $list ]]; then
        echo "Missing package list: $list" >&2
        exit 1
    fi
    while IFS= read -r name || [[ -n $name ]]; do
        [[ -n $name && $name != \#* ]] || continue
        if [[ ! $name =~ ^[a-zA-Z0-9][a-zA-Z0-9@+._/-]*$ ]]; then
            echo "Invalid package name in $list: $name" >&2
            exit 1
        fi
        printf '%s\n' "$name" >> "$work/packages"
    done < "$list"
done
LC_ALL=C sort -u "$work/packages" > "$work/unique"

if [[ $manager == brew ]]; then
    brew list --formula -1 > "$work/installed"
    brew list --cask -1 >> "$work/installed"
else
    command -v apt-get >/dev/null || { echo 'apt-get is missing.' >&2; exit 1; }
    dpkg-query -W '-f=${Package}\t${db:Status-Status}\n' > "$work/dpkg"
    awk '$2 == "installed" {print $1}' "$work/dpkg" > "$work/installed"
fi

missing=()
while IFS= read -r name; do
    if ! grep -Fxq "$name" "$work/installed"; then
        if [[ $manager == brew ]]; then
            versions=$(brew list --versions "$name" 2>/dev/null) || versions=
            [[ -z $versions ]] || continue
        fi
        missing+=("$name")
        printf 'Missing package: %s\n' "$name"
    fi
done < "$work/unique"

if [[ $mode == install && ${#missing[@]} -gt 0 ]]; then
    if [[ $manager == brew ]]; then
        HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 brew install "${missing[@]}"
    else
        elevate=()
        [[ $EUID -eq 0 ]] || elevate=(sudo)
        "${elevate[@]}" apt-get update
        unavailable=false
        for name in "${missing[@]}"; do
            policy=$(apt-cache policy "$name")
            if ! awk '/Candidate:/ && $2 != "(none)" {found=1} END {exit !found}' <<< "$policy"; then
                echo "No APT candidate: $name. Enable its official repository or use a supported Ubuntu release." >&2
                [[ $name != code ]] || echo 'VS Code repository: https://code.visualstudio.com/docs/setup/linux' >&2
                unavailable=true
            fi
        done
        [[ $unavailable == false ]] || exit 1
        "${elevate[@]}" apt-get install -y "${missing[@]}"
    fi
fi

if [[ $mode == install ]]; then
    if [[ ${#missing[@]} -gt 0 ]]; then
        printf 'Installed packages: %s\n' "${missing[*]}"
    else
        echo 'All required packages were already installed.'
    fi
fi

failed=0
if [[ $mode == check && ${#missing[@]} -gt 0 ]]; then
    failed=1
fi
bash "$root/setup/check.sh" "${linked[@]}" || failed=1
setup_mode=$mode
[[ $failed -eq 0 ]] || setup_mode=check
for package in "${linked[@]}"; do
    if [[ -f $root/configs/$package/setup/install.sh ]]; then
        bash "$root/configs/$package/setup/install.sh" "$setup_mode" || failed=1
    fi
done
if [[ $failed -eq 0 ]]; then
    if [[ $mode == check ]]; then
        printf 'Checks passed for: %s\n' "${linked[*]}"
    else
        printf 'Dependency setup completed for: %s\n' "${linked[*]}"
        echo 'Config links unchanged.'
    fi
else
    echo 'Some dependencies still need attention; see the messages above.' >&2
fi
exit "$failed"
