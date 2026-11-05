# Neovim dependencies

Neovim detects available language runtimes on each launch using `lua/configs/languages.lua`. Go enables Go support; Python enables Python parsers and, with `venv`/`ensurepip`, Black; Python plus Node/npm enables Pyright. Node/npm enables HTML/CSS tools. A C compiler enables C/C++ tools, and Make enables its parser (its language server also needs Python's venv support). Lua support is always enabled for Neovim itself. Missing prerequisites silently skip the corresponding support; installing them makes it eligible on the next launch. Previously installed tools are not deleted.

Lazy installs editor plugins; Mason installs eligible language tools. LSPs and formatters only run once their executable exists. Treesitter installs eligible parsers only when tree-sitter CLI, a C compiler, curl and tar are available; otherwise Neovim retains its built-in syntax highlighting. The outer installer does not install language runtimes, compilers, Make, or the tree-sitter CLI. The custom build runner needs Make; its tmux application runner additionally needs Python.

First installation still needs network access. Download failures can still be reported; missing language runtimes are not errors. `:MasonToolsInstall` retries eligible missing tools, and reopening Neovim retries eligible missing parsers. `--check` checks the core system prerequisites, not optional language tools or internal installation progress.


The config is a Git submodule at `configs/nvim/.config/nvim`. Commit and push its changes there first, then commit its updated pointer in the parent repository.
