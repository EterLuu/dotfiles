# Shared interactive aliases and functions. Must remain valid in Bash and Zsh.

alias ..='cd ..'
alias ...='cd ../..'
alias ll='ls -alh'
alias la='ls -A'
alias c='clear'

mkcd() {
    [ "$#" -eq 1 ] || {
        printf 'usage: mkcd DIRECTORY\n' >&2
        return 2
    }
    mkdir -p "$1" && cd "$1"
}

croot() {
    if [ -n "${DOTFILES_ROOT:-}" ]; then
        cd "$DOTFILES_ROOT"
    else
        printf 'DOTFILES_ROOT is not set; run dotfiles install\n' >&2
        return 1
    fi
}

if [ -n "${DOTFILES_ROOT:-}" ] && [ -n "${DOTFILES_OS:-}" ]; then
    dotfiles_platform_shell=$DOTFILES_ROOT/profiles/$DOTFILES_OS/shell.sh
    if [ -r "$dotfiles_platform_shell" ]; then
        # shellcheck disable=SC1090
        . "$dotfiles_platform_shell"
    fi
    unset dotfiles_platform_shell
fi

if [ -n "${DOTFILES_ROOT:-}" ] && [ -n "${DOTFILES_HOST:-}" ]; then
    dotfiles_host_shell=$DOTFILES_ROOT/profiles/hosts/$DOTFILES_HOST/shell.sh
    if [ -r "$dotfiles_host_shell" ]; then
        # shellcheck disable=SC1090
        . "$dotfiles_host_shell"
    fi
    unset dotfiles_host_shell
fi

# NVM is installed in different locations by different installers. Keep the
# discovery shared, but call it after local.bash/local.zsh so a device can set
# an explicit NVM_DIR without changing tracked files.
dotfiles_load_nvm() {
    if command -v nvm >/dev/null 2>&1; then
        return 0
    fi

    dotfiles_nvm_dir=""
    if [ -n "${NVM_DIR:-}" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
        dotfiles_nvm_dir=$NVM_DIR
    else
        for dotfiles_nvm_candidate in \
            "${XDG_CONFIG_HOME:-"$HOME/.config"}/nvm" \
            "$HOME/.nvm"; do
            if [ -s "$dotfiles_nvm_candidate/nvm.sh" ]; then
                dotfiles_nvm_dir=$dotfiles_nvm_candidate
                break
            fi
        done
        unset dotfiles_nvm_candidate
    fi

    if [ -n "$dotfiles_nvm_dir" ]; then
        NVM_DIR=$dotfiles_nvm_dir
        export NVM_DIR
        # shellcheck disable=SC1090
        . "$NVM_DIR/nvm.sh"
        if [ -n "${BASH_VERSION:-}" ] && [ -s "$NVM_DIR/bash_completion" ]; then
            # shellcheck disable=SC1090
            . "$NVM_DIR/bash_completion"
        fi
    fi
    unset dotfiles_nvm_dir
}
