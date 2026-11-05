# Local settings and state

Machine-specific settings remain separate; there is no shared `.env` loader.

- Fish: `~/.config/fish/conf.d/local.fish`, described by `configs/fish/.config/fish/conf.d/local.fish.example`.
- tmux helpers: `~/.config/tmux/.env`, described by `configs/tmux/.config/tmux/.env.example`.
- Fish maintains `~/.config/fish/fish_variables` itself.
- tmux resurrect snapshots remain in `~/.config/tmux/resurrect/`; plugins live in `~/.config/tmux/plugins/`.

The installer leaves these files untouched. Back them up separately from the Git repository. Keep `--no-folding` in place until local settings and writable state have been relocated deliberately.

Fish's AWS helpers also need AWS CLI, jq, credentials, and local EC2 settings. GitHub helpers need GitHub CLI and authentication. Databricks helpers need its CLI and a configured virtual environment. Markdown helpers need the separate `~/.local/share/md2{html,pdf}` scripts. These integrations are optional and are not installed by the base package lists.
