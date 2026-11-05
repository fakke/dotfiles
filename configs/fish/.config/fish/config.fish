set -gx STARSHIP_CONFIG ~/.config/starship/starship.toml
set -gx CLAUDE_CONFIG_DIR $HOME/.config/claude

if set -q EC2_REGION; and test -n "$EC2_REGION"
    set -gx AWS_REGION "$EC2_REGION"
end

set -U fish_greeting
if status is-interactive
    if type -q starship
        starship init fish | source
    end
    if type -q fzf; and fzf --help | string match -q '*--fish*'
        fzf --fish | source
    end
end
if type -q lsd
    alias ls='lsd'
    alias ll='lsd -la'
    alias tree='lsd --tree'
end
if type -q batcat
    alias cat='batcat'
    alias bat='batcat'
else if type -q bat
    alias cat='bat'
end
alias c='clear'
alias x='exit'
alias nv='nvim'
alias gl='git log --oneline --graph'

# pipx
set PATH $PATH ~/.local/bin

if type -q direnv
    direnv hook fish | source
end
