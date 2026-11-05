#!/usr/bin/env bash
set -eo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failed=0
while read -r command flag key repository rest; do
    [[ $command == set && $key == @plugin ]] || continue
    repository=${repository//\'/}
    [[ $repository =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]] || exit 1
    name=${repository##*/}
    destination="$HOME/.config/tmux/plugins/$name"
    entry="$destination/${name#tmux-}.tmux"
    [[ $name != tpm ]] || entry="$destination/tpm"
    if [[ ! -e $destination && $1 == install ]]; then
        mkdir -p "$(dirname "$destination")"
        git clone --depth 1 "https://github.com/$repository.git" "$destination"
    fi
    if [[ ! -f $entry ]]; then
        echo "Missing tmux plugin: $repository ($entry)" >&2
        failed=1
    fi
done < "$root/.config/tmux/tmux.conf"
exit "$failed"
