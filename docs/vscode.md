# VS Code

The shared settings and CSS live in `configs/vscode/.config/vscode/`. `stow vscode` exposes them under `~/.config/vscode`; `./install.sh` installs the declared packages and missing extensions.

The native settings location is `~/Library/Application Support/Code/User/settings.json` on macOS and `~/.config/Code/User/settings.json` on Ubuntu. Setup links it to the shared settings and refuses to replace an unrelated existing file.

Custom workbench CSS is optional. The legacy `~/.config/vscode/install.sh` also patches VS Code's application files; the root installer does not run it. VS Code updates overwrite that patch, and patching can require additional OS permissions. The CSS import uses `file://${userHome}/.config/vscode/custom.css`; the Custom CSS extension expands `${userHome}` on macOS and Linux.
