# Setup and updates

Run `./install.sh` from a Git checkout. It detects macOS or Ubuntu, installs Homebrew if needed using its [official installer](https://docs.brew.sh/Installation), and installs Stow if needed. It reports which prerequisites were installed or already available.

Only stowed configs determine which application dependencies are installed. With nothing stowed, the script installs no application dependencies and prints a preview command and an example command containing every available config. Edit that example to select what you want. Stow has no post-run hook, so the example chains `stow ... && ./install.sh`. A dry run (`stow --simulate ...`) previews links without installing anything.

The installer never runs Stow or changes your selection. After pulling new files, run Stow for the affected packages, then `./install.sh`. Partial links are reported and left untouched. If Neovim's submodule is missing after a non-recursive clone, the printed instructions include its initialization command before Stow. Initialized submodules are not reset or updated by the installer.

`.stowrc` supplies `--dir=configs`, `--target=~`, and `--verbose`; there is no need to type those flags. Keep running Stow from the repo root. Individual file links remain in use to keep local files outside the checkout.

`./install.sh --check` reports missing packages, links, supported versions, and plugin files without installing or linking anything. A nonzero exit means something needs attention. Existing incompatible versions are reported, not automatically upgraded. Missing APT candidates are reported before the dependency batch is installed; custom repositories and unsupported binary downloads are not added automatically. VS Code on Ubuntu requires [Microsoft's repository](https://code.visualstudio.com/docs/setup/linux).

Each package's `setup/` directory contains `packages.brew`, `packages.apt`, and any app-specific setup script. Shared setup code and its tests live under the root `setup/`. Stow excludes package setup directories. Package lists are deduplicated across the selected configs.

The installer needs network access for downloads and may need an administrator password. It does not change the login shell, restart applications, or patch VS Code. Git and a checkout of this repository are the starting point; private repository authentication stays with Git/SSH. Homebrew's installer handles its own platform and developer-tools requirements.

Fish needs fzf 0.48+; tmux needs 3.2+; the current Neovim config needs Neovim 0.12+. Older Ubuntu repositories may not provide these versions. Installing packages also does not provide a graphical desktop on a headless Pi. Fonts are rendered by the terminal client when connecting over SSH.
