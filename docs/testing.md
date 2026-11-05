# Verification

Run `python3 -m unittest discover -s setup/tests -v` to test package selection, deduplication, bootstrap, selection, first-run guidance, and reruns with temporary homes and stub package managers. These tests do not install system packages.

Run `./install.sh --check` to check the actual linked configuration. This can fail legitimately when packages or supported versions are missing.

From `configs/nvim/.config/nvim`, run:

```sh
MASON_TOOL_INSTALLER="$HOME/.local/share/nvim/lazy/mason-tool-installer.nvim" \
nvim --clean --headless -l tests/check_dependencies.lua
```

This exercises runtime detection, missing prerequisites, installation retries, parser setup, and LSP activation using the real Mason installer with a simulated registry. It does not download tools or prove that a real network installation succeeds.
