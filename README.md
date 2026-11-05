# Dotfiles

## Setup

From the repo root, run:

```sh
./install.sh
```

It installs Stow (and Homebrew if needed), reports what it did, and prints the next steps. On macOS and Ubuntu, choose the configs you want from this example:

```sh
stow --simulate nvim tmux fish starship kitty vscode
stow nvim tmux fish starship kitty vscode && ./install.sh
```

The first command previews; the second creates links and installs dependencies only for stowed configs. Directory, target, and verbosity are set in `.stowrc`. Rerunning `install.sh` skips installed dependencies; `--check` only checks.

## Local settings

Keep machine-specific values outside the repo:

- Fish: `~/.config/fish/conf.d/local.fish`, using `configs/fish/.config/fish/conf.d/local.fish.example` as a guide.
- tmux: `~/.config/tmux/.env`, using `configs/tmux/.config/tmux/.env.example` as a guide.

There is no shared `.env`. Back up these files and tmux resurrect snapshots separately. Leave `fish_variables` to Fish. See [local settings](docs/local.md).

## Edit and push

Existing linked files can be edited from either location. Create **new shared files inside `configs/`**, then rerun `stow <package>` to expose them. Files created directly in `~/.config` stay local because we use `--no-folding`.

Review `git diff` and `git status`, stage the intended files, commit, and push. For Neovim, work on a branch in `configs/nvim/.config/nvim`; commit and push there first, then commit and push its updated submodule pointer in dotfiles.

## Pull updates

With local work committed or stashed:

```sh
git pull --recurse-submodules
stow -R fish kitty nvim starship tmux vscode
./install.sh
```

Use only **your selected packages** in the Stow command. Restowing refreshes links after additions, removals, or renames; the installer checks and installs dependencies. Submodule updates can leave Neovim detached; switch to your development branch before editing it.

[Setup details](docs/setup.md) · [Neovim](docs/neovim.md) · [VS Code](docs/vscode.md) · [Tests](docs/testing.md)
